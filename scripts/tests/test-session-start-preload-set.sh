#!/bin/bash
# test-session-start-preload-set.sh — what SessionStart injects, checked against its sources
#
# The standards the hook prints must be exactly get_session_start_seeds (the list PostToolUse
# dedup reads), the pitfalls index must name every ¶PTF_ entry in the files it is built from,
# and a loom resume must carry an excerpt of the loom log rather than the whole log.

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Everything under test comes from this tree: $HOME/.claude is the machine's live engine, which may
# be checked out at another branch, so a hook read from there tests that branch's code.
HOOK_SCRIPT="$SCRIPT_DIR/hooks/session-start-restore.sh"
REAL_PITFALLS="$SCRIPT_DIR/.directives/PITFALLS.md"

TMP_DIR=""

# Here-string matching: the shared helpers pipe echo into grep -q, which under pipefail turns an
# early match on a large haystack into SIGPIPE and reports the match as a miss.
has() { if grep -qF -- "$1" <<< "$2"; then pass "$3"; else fail "$3" "contains '$1'" "$(head -c 400 <<< "$2")"; fi; }
hasnt() { if grep -qF -- "$1" <<< "$2"; then fail "$3" "NOT contains '$1'" "$(grep -F -m1 -- "$1" <<< "$2")"; else pass "$3"; fi; }

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"
  disable_fleet_tmux

  ln -sf "$HOOK_SCRIPT" "$FAKE_HOME/.claude/hooks/session-start-restore.sh"
  ln -sf "$SCRIPT_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  ln -sf "$SCRIPT_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"

  export PROJECT_DIR="$TMP_DIR/project"
  mkdir -p "$PROJECT_DIR/sessions"

  unset _LIB_SH_LOADED
  source "$FAKE_HOME/.claude/scripts/lib.sh"

  # Every listed standard, read from the list, plus the on-demand ones a real tree carries.
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  local rel
  for rel in "${SESSION_START_SEED_FILES[@]}" SIGILS.md commands/CMD_PARSE_PARAMETERS.md; do
    echo "# content of $rel" > "$FAKE_HOME/.claude/.directives/$rel"
  done
  cat > "$FAKE_HOME/.claude/.directives/PITFALLS.md" <<'MD'
# Pitfalls

*   **¶PTF_FAKE_ENGINE_ENTRY**: the planted engine trap
    *   **Mitigation**: body text that must not be preloaded PITFALLS_BODY_MARKER
MD

  RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/session-start-restore.sh"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# Every hook run gets a scrubbed environment. The seat running the tests carries its own
# CLAUDE_SUPERVISOR_PID, TMUX, TMUX_PANE, FLEET_* and session-cache dir, and any one of them lets
# session.sh find resolve the seat's LIVE session, which the hook then reseeds.
hook_env() {
  env -i HOME="$HOME" PATH="$PATH" TMPDIR="$TMP_DIR" \
    CLAUDE_SUPERVISOR_PID="$$" CLAUDE_HOOK_PPID="$$" CLAUDE_SESSION_CACHE_DIR="$TMP_DIR/session-cache" \
    FLEET_SETUP_DONE=1 "$@"
}

run_hook() {
  local source="${1:-startup}"
  local cwd="${2:-$PROJECT_DIR}"
  mkdir -p "$TMP_DIR/session-cache"
  echo "{\"hook_event_name\":\"SessionStart\",\"source\":\"$source\",\"cwd\":\"$cwd\"}" \
    | hook_env bash "$RESOLVED_HOOK" 2>/dev/null
}

# The paths of the [Preloaded: <path>] blocks a hook run printed, sorted, as a JSON array.
printed_standards() {
  grep -E '^\[Preloaded: /' <<< "$1" | sed -E 's/^\[Preloaded: (.*)\]$/\1/' | jq -R . | jq -sc 'sort'
}

test_fake_home_runs_this_trees_code() {
  local tree link target
  tree=$(cd "$SCRIPT_DIR" && pwd -P)
  for link in hooks/session-start-restore.sh scripts/lib.sh scripts/session.sh; do
    target=$(cd "$(dirname "$(readlink "$FAKE_HOME/.claude/$link")")" 2>/dev/null && pwd -P)
    assert_eq "$tree/$(dirname "$link")" "$target" "fake-home $link comes from this tree"
  done
}

test_hook_prints_exactly_the_seed_list() {
  local output expected actual
  output=$(run_hook "startup") || true
  expected=$(get_session_start_seeds | jq -c 'sort')
  actual=$(printed_standards "$output")
  assert_eq "$expected" "$actual" "standards printed == get_session_start_seeds"
  assert_eq "${#SESSION_START_SEED_FILES[@]}" "$(echo "$actual" | jq 'length')" "one block per listed standard"
}

test_seed_file_records_exactly_what_was_printed() {
  local output seed printed recorded
  output=$(run_hook "startup") || true
  seed="$PROJECT_DIR/sessions/.seeds/$$.json"
  assert_file_exists "$seed" "hook wrote a seed for this process"
  printed=$(printed_standards "$output")
  recorded=$(jq -c '.preloadedFiles | sort' "$seed")
  assert_eq "$printed" "$recorded" "seed preloadedFiles == printed standards (no TOC in this project)"
}

test_on_demand_standards_are_not_printed() {
  local output
  output=$(run_hook "startup") || true
  hasnt "content of SIGILS.md" "$output" "SIGILS.md not preloaded"
  hasnt "content of commands/CMD_PARSE_PARAMETERS.md" "$output" "CMD_PARSE_PARAMETERS.md not preloaded"
  hasnt "PITFALLS_BODY_MARKER" "$output" "PITFALLS.md body not preloaded"
}

test_hook_injects_pitfalls_index_from_engine_and_project() {
  mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/.directives"
  cat > "$PROJECT_DIR/.directives/PITFALLS.md" <<'MD'
## ¶PTF_FAKE_PROJECT_ENTRY — the planted project trap
Body PROJECT_BODY_MARKER.
MD
  local output
  output=$(run_hook "startup") || true
  has "[Pitfalls index, generated at session start" "$output" "index header present"
  has "- ¶PTF_FAKE_ENGINE_ENTRY — the planted engine trap" "$output" "engine entry indexed"
  has "- ¶PTF_FAKE_PROJECT_ENTRY — the planted project trap" "$output" "project entry indexed"
  hasnt "PROJECT_BODY_MARKER" "$output" "project PITFALLS body not preloaded"
}

test_index_names_every_ptf_in_the_engine_pitfalls() {
  assert_file_exists "$REAL_PITFALLS" "engine PITFALLS.md present"
  local index names missing=0 name
  index=$(generate_pitfalls_index "$REAL_PITFALLS")
  names=$(grep -o '¶PTF_[A-Z0-9_]*' "$REAL_PITFALLS" | sort -u)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [[ "${name#¶}" =~ $PITFALLS_PLACEHOLDER_RE ]] && continue
    if ! grep -qF -- "$name — " <<< "$index"; then
      missing=$((missing + 1))
      echo "    not indexed: $name"
    fi
  done <<< "$names"
  assert_eq "0" "$missing" "every ¶PTF_ name in PITFALLS.md appears in the index"
  assert_eq "$(echo "$names" | grep -c .)" "$(echo "$index" | grep -c '¶PTF_[A-Z0-9_]* — ')" "one index line per distinct name"

  # A definition line must yield its trap, not the prose-only placeholder.
  local defined placeholder=0
  defined=$(grep -oE '^[[:space:]]*[*-][[:space:]]+\*\*[^*]*¶PTF_[A-Z0-9_]+|^#+ .*¶PTF_[A-Z0-9_]+' "$REAL_PITFALLS" \
    | grep -v -i addendum | grep -o '¶PTF_[A-Z0-9_]*' | sort -u)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if grep -F -- "$name — " <<< "$index" | grep -q 'named in prose, no definition line'; then
      placeholder=$((placeholder + 1))
      echo "    defined but no trap text: $name"
    fi
  done <<< "$defined"
  assert_eq "0" "$placeholder" "every defined entry carries its trap text"
}

make_loom_log() {
  local f="$1"
  {
    echo "## [2026-10-01 10:00:00] ▶️ Loom Opened"
    echo "old opening"
    echo ""
    echo "## [2026-10-01 11:00:00] 🧵 LEDGER (11:00): OLD_LEDGER_MARKER"
    echo "- old row"
    echo ""
    local i
    for i in $(seq 1 3000); do echo "## [2026-10-02 00:00:00] 🔧 Progress $i"; echo "FILLER_MARKER line $i"; done
    echo "## [2026-10-03 09:00:00] 🧵 LEDGER (09:00): NEW_LEDGER_MARKER"
    echo "- live row"
    echo ""
    echo "## [2026-10-03 09:05:00] 🤝 Hand-over written (09:05)"
    echo "HANDOVER_MARKER payload"
    echo ""
    echo "## [2026-10-03 09:10:00] 🔧 Progress after"
    echo "AFTER_MARKER"
  } > "$f"
}

test_loom_log_excerpt_keeps_latest_ledger_and_handover() {
  local log="$TMP_DIR/LOOM_LOG.md" out bytes
  make_loom_log "$log"
  bytes=$(wc -c < "$log" | tr -d ' ')
  out=$(loom_log_excerpt "$log")
  has "NEW_LEDGER_MARKER" "$out" "latest ledger present"
  has "live row" "$out" "latest ledger body present"
  has "HANDOVER_MARKER" "$out" "hand-over entry present"
  hasnt "OLD_LEDGER_MARKER" "$out" "older ledger absent"
  hasnt "FILLER_MARKER" "$out" "other entries absent"
  has "AFTER_MARKER" "$out" "entry after the hand-over delivered"
  has "'$log' is $bytes bytes" "$out" "pointer names path and size"
  has "grep -n '^## ' '$log'" "$out" "pointer gives the grep recipe"
}

test_loom_log_excerpt_declines_without_markers() {
  local log="$TMP_DIR/plain.md" rc=0
  printf '## one\nx\n## two\ny\n' > "$log"
  loom_log_excerpt "$log" > /dev/null || rc=$?
  assert_eq "1" "$rc" "no ledger and no hand-over → exit 1 so the caller falls back"
}

test_heading_aligned_tail_caps_and_aligns() {
  local log="$TMP_DIR/big.md" out
  make_loom_log "$log"
  out=$(heading_aligned_tail "$log" 2000)
  has "[... earlier entries omitted; showing the most recent of" "$out" "omission note present"
  has "AFTER_MARKER" "$out" "tail kept"
  hasnt "Loom Opened" "$out" "head dropped"
  local first_body
  first_body=$(sed -n '3p' <<< "$out")
  has "## " "$first_body" "excerpt starts on an entry heading"
  local small="$TMP_DIR/small.md"
  printf '## a\nb\n' > "$small"
  assert_eq "$(cat "$small")" "$(heading_aligned_tail "$small" 2000)" "file under the cap comes back whole"
}

create_loom_session() {
  local skill_dir="$FAKE_HOME/.claude/skills/loom"
  mkdir -p "$skill_dir/assets"
  echo "# loom log template" > "$skill_dir/assets/TEMPLATE_LOOM_LOG.md"
  echo "# loom debrief template" > "$skill_dir/assets/TEMPLATE_LOOM.md"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
description: "Test loom skill"
---

```json
{
  "taskType": "LOOM",
  "logTemplate": "assets/TEMPLATE_LOOM_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_LOOM.md",
  "phases": [{"major": 0, "minor": 0, "name": "Setup", "steps": []}]
}
```
SKILLEOF
  LOOM_SESSION="$PROJECT_DIR/sessions/test_loom"
  mkdir -p "$LOOM_SESSION"
  cat > "$LOOM_SESSION/.state.json" <<JSON
{"pid": $$, "skill": "loom", "lifecycle": "active", "currentPhase": "0: Setup", "preloadedFiles": []}
JSON
}

test_loom_resume_delivers_excerpt_not_whole_log() {
  create_loom_session
  make_loom_log "$LOOM_SESSION/LOOM_LOG.md"
  local output
  output=$(run_hook "clear") || true
  has "[Preloaded: $LOOM_SESSION/LOOM_LOG.md]" "$output" "loom log block present"
  has "[Loom log excerpt: '$LOOM_SESSION/LOOM_LOG.md' is" "$output" "excerpt pointer present"
  has "HANDOVER_MARKER" "$output" "hand-over delivered"
  hasnt "FILLER_MARKER" "$output" "rest of the log not delivered"
}

test_loom_log_without_markers_gets_heading_aligned_tail() {
  create_loom_session
  # Same session shape, a log with no loom markers: falls back to the 50 KB tail.
  local i
  for i in $(seq 1 4000); do echo "## [2026-10-02 00:00:00] Progress $i"; echo "PLAIN_FILLER line $i."; done > "$LOOM_SESSION/LOOM_LOG.md"
  echo "## last entry" >> "$LOOM_SESSION/LOOM_LOG.md"; echo "PLAIN_LAST" >> "$LOOM_SESSION/LOOM_LOG.md"
  local output
  output=$(run_hook "clear") || true
  has "[... earlier entries omitted; showing the most recent of" "$output" "tail note present"
  has "PLAIN_LAST" "$output" "tail delivered"
  hasnt "PLAIN_FILLER line 1." "$output" "head not delivered"
}

test_debrief_is_delivered_whole() {
  create_loom_session
  local i
  { for i in $(seq 1 4000); do echo "debrief line $i DEBRIEF_LINE"; done; echo "DEBRIEF_END"; } > "$LOOM_SESSION/LOOM.md"
  local output
  output=$(run_hook "clear") || true
  has "debrief line 1 DEBRIEF_LINE" "$output" "debrief head delivered"
  has "DEBRIEF_END" "$output" "debrief end delivered"
  hasnt "[... earlier entries omitted" "$output" "debrief not truncated"
}

# --- Fit on a loom resume at today's sizes: real standards, real loom skill, logs at measured sizes ---

# Real engine directives and skills behind the fake HOME, so sizes are the live ones.
use_real_engine() {
  local skills_dir="${1:-$SCRIPT_DIR/skills}"
  rm -rf "$FAKE_HOME/.claude/.directives" "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.claude/engine"
  ln -s "$SCRIPT_DIR/.directives" "$FAKE_HOME/.claude/.directives"
  ln -s "$skills_dir" "$FAKE_HOME/.claude/skills"
  ln -s "$SCRIPT_DIR" "$FAKE_HOME/.claude/engine"
}

# A loom session whose log and dialogue match the sizes measured on 2026-10-23 (1.7 MB, 1.06 MB).
make_measured_loom_session() {
  LOOM_SESSION="$PROJECT_DIR/sessions/fit_loom"
  mkdir -p "$LOOM_SESSION" "$PROJECT_DIR/docs"
  head -c 11400 /dev/zero | tr '\0' 'x' | fold -w 100 > "$PROJECT_DIR/docs/TOC.md"
  cat > "$LOOM_SESSION/.state.json" <<JSON
{"pid": $$, "skill": "loom", "lifecycle": "active", "currentPhase": "3: Weave", "preloadedFiles": []}
JSON
  {
    awk 'BEGIN { f = "log filler log filler log filler log filler log filler log filler log filler"; for (i = 1; i <= 9000; i++) printf "## [2026-10-22 10:00:00] 🔧 Progress %d\n%s %s\n\n", i, f, f }'
    printf '## [2026-10-23 19:15:00] 🧵 LEDGER (19:15): FIT_LEDGER_MARKER\n- row\n\n'
    printf '## [2026-10-23 19:16:00] 🤝 Hand-over written (19:18)\nFIT_HANDOVER_MARKER\n\n'
    # 57 entries (~39 KB) after the hand-over, as measured on the conductor's log.
    awk 'BEGIN { f = sprintf("%660s", ""); gsub(/ /, "a", f); for (i = 1; i <= 56; i++) printf "## [2026-10-23 20:%02d:00] 🧵 [LANE] step %d\n%s\n\n", i % 60, i, f }'
    printf '## [2026-10-23 21:20:00] 🧵 [SLOTCLAIM] round 2 done\nFIT_NEWEST_LOG_MARKER\n'
  } > "$LOOM_SESSION/LOOM_LOG.md"
  {
    awk 'BEGIN { f = "dialogue filler dialogue filler dialogue filler dialogue filler dialogue filler dialogue filler dialogue filler"; for (i = 1; i <= 7700; i++) printf "## [2026-10-22 10:00:00] entry %d\n%s\n", i, f }'
    printf '## [2026-10-23 20:00:00] newest entry\nFIT_NEWEST_DIALOGUE_MARKER\n'
  } > "$LOOM_SESSION/DIALOGUE.md"
}

# Prints the inline part (slots 0..47) and the spilled remainder of a preload, as the chunker emits them.
split_inline() {
  local preload="$1" inline_out="$2" spill_out="$3" gen="$TMP_DIR/gen.sh" i
  printf '#!/bin/bash\ncat %q\n' "$preload" > "$gen"; chmod +x "$gen"
  rm -rf "$TMP_DIR/chunkcache"; mkdir -p "$TMP_DIR/chunkcache"
  : > "$inline_out"
  for i in $(seq 0 47); do
    echo '{"session_id":"fit","source":"clear"}' | PRELOAD_GENERATOR="$gen" PRELOAD_CACHE_DIR="$TMP_DIR/chunkcache" \
      bash "$SCRIPT_DIR/hooks/session-start-chunk.sh" "$i" 48 >> "$inline_out"
  done
  local inline_bytes
  inline_bytes=$(grep -v '^\[preload overflow:' "$inline_out" | wc -c | tr -d ' ')
  tail -c +"$((inline_bytes + 1))" "$preload" > "$spill_out"
}

assert_session_state_inline() {
  local inline="$1" label="$2"
  has "FIT_NEWEST_DIALOGUE_MARKER" "$(cat "$inline")" "$label: newest DIALOGUE entry is inline"
  has "FIT_LEDGER_MARKER" "$(cat "$inline")" "$label: ledger extract is inline"
  has "FIT_HANDOVER_MARKER" "$(cat "$inline")" "$label: hand-over is inline"
  has "FIT_NEWEST_LOG_MARKER" "$(cat "$inline")" "$label: newest loom-log entry is inline"
}

test_loom_resume_keeps_session_state_inline_at_todays_sizes() {
  use_real_engine
  make_measured_loom_session
  run_hook "clear" > "$TMP_DIR/preload.txt" || true
  split_inline "$TMP_DIR/preload.txt" "$TMP_DIR/inline.txt" "$TMP_DIR/spill.txt"
  assert_session_state_inline "$TMP_DIR/inline.txt" "today's sizes"
  hasnt "TEMPLATE_LOOM_LOG.md]" "$(cat "$TMP_DIR/preload.txt")" "log template not delivered once the session log exists"
}

test_planted_large_skill_file_spills_only_skill_files() {
  local skills="$TMP_DIR/skills-planted"
  mkdir -p "$skills"
  cp -R "$SCRIPT_DIR/skills/loom" "$skills/loom"
  { echo ""; echo "## Planted filler"; head -c 102400 /dev/zero | tr '\0' 'p' | fold -w 100; } >> "$skills/loom/SKILL.md"
  use_real_engine "$skills"
  make_measured_loom_session
  run_hook "clear" > "$TMP_DIR/preload.txt" || true
  split_inline "$TMP_DIR/preload.txt" "$TMP_DIR/inline.txt" "$TMP_DIR/spill.txt"
  has "[preload overflow:" "$(cat "$TMP_DIR/inline.txt")" "the planted file does overflow the slots"
  assert_session_state_inline "$TMP_DIR/inline.txt" "planted 100 KB skill file"
  local spill
  spill=$(cat "$TMP_DIR/spill.txt")
  hasnt "FIT_NEWEST_DIALOGUE_MARKER" "$spill" "spill holds no DIALOGUE"
  hasnt "Loom log excerpt" "$spill" "spill holds no log excerpt"
  hasnt "[Preloaded: $LOOM_SESSION" "$spill" "spill holds no session artifact"
}

test_dialogue_tail_keeps_newest_and_points_at_the_rest() {
  local d="$TMP_DIR/DIALOGUE.md" out i
  awk 'BEGIN { x = sprintf("%200s", ""); gsub(/ /, "x", x); for (i = 1; i <= 400; i++) printf "## entry %d\n%s\n", i, x }' > "$d"
  printf '## newest\nNEWEST_LINE\n' >> "$d"
  out=$(dialogue_tail "$d" 100 4000)
  has "NEWEST_LINE" "$out" "newest line present"
  has "[DIALOGUE excerpt: $d is" "$out" "pointer names the path and size"
  has "tail -n" "$out" "pointer gives tail -n"
  assert_gt "4500" "$(printf '%s' "$out" | wc -c | tr -d ' ')" "excerpt within the byte cap plus pointer"
  has "## " "$(sed -n '3p' <<< "$out")" "excerpt starts on an entry heading"
  local big="$TMP_DIR/big-entry.md"
  { echo "## only"; head -c 20000 /dev/zero | tr '\0' 'y' | fold -w 100; echo "LAST_OF_HUGE"; } > "$big"
  out=$(dialogue_tail "$big" 100 4000)
  has "LAST_OF_HUGE" "$out" "an oversized newest entry still shows its newest lines"
  local small="$TMP_DIR/small-dlg.md"
  printf '## a\nb\n' > "$small"
  assert_eq "$(cat "$small")" "$(dialogue_tail "$small" 100 4000)" "a short dialogue comes back whole, no pointer"
}

# --- Ruled core set, pinned literally (everything else here derives from the list) ---

test_core_set_is_the_ruled_five() {
  assert_eq "COMMANDS.md INVARIANTS.md VOICE.md commands/CMD_DEHYDRATE.md commands/CMD_RESUME_SESSION.md" \
    "${SESSION_START_SEED_FILES[*]}" "core set is exactly the operator's 2026-10-23 ruling"
}

# --- Isolation: a hook run under this harness must never reach a live session ---

# The leak path that reseeded a live conductor: the real fleet.sh turns an inherited TMUX/TMUX_PANE
# into a pane id, and that id matches fleetPaneId on a live session in the project's own sessions/.
# A stub tmux answers fleet.sh's queries; the decoy's pid is dead, so only the pane can reach it.
setup_fleet_decoy() {
  mkdir -p "$TMP_DIR/bin"
  cat > "$TMP_DIR/bin/tmux" <<'SH'
#!/bin/bash
case "$*" in
  *session_name*) echo decoysess ;;
  *window_name*) echo decoywin ;;
  *pane_label*) echo decoylabel ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$TMP_DIR/bin/tmux"
  rm -f "$FAKE_HOME/.claude/scripts/fleet.sh"
  ln -s "$SCRIPT_DIR/scripts/fleet.sh" "$FAKE_HOME/.claude/scripts/fleet.sh"
  DECOY="$PROJECT_DIR/sessions/LIVE_DECOY"
  mkdir -p "$DECOY"
  local dead; dead=$(bash -c 'echo $$'); 
  printf '{"pid": %s, "skill": "loom", "lifecycle": "active", "fleetPaneId": "decoysess:decoywin:decoylabel", "preloadedFiles": ["/live/untouched.md"]}\n' "$dead" > "$DECOY/.state.json"
  SEAT_ENV=(TMUX="$TMP_DIR/sock/fleet,4242,0" TMUX_PANE="%7" PATH="$TMP_DIR/bin:$PATH")
}

test_hook_run_cannot_resolve_a_live_session() {
  setup_fleet_decoy
  local before after output
  before=$(shasum "$DECOY/.state.json")
  output=$(env "${SEAT_ENV[@]}" bash -c "$(declare -f hook_env run_hook); TMP_DIR='$TMP_DIR' PROJECT_DIR='$PROJECT_DIR' RESOLVED_HOOK='$RESOLVED_HOOK' run_hook clear") || true
  after=$(shasum "$DECOY/.state.json")
  assert_eq "$before" "$after" "under hook_env, the decoy live session is untouched"
  has "Session: (none)" "$output" "under hook_env, no session resolved"
}

test_the_leak_path_is_real_without_env_i() {
  # The guard above only means something if the same seat variables DO reach the decoy when the
  # environment is inherited, so prove it.
  setup_fleet_decoy
  local before after output
  before=$(shasum "$DECOY/.state.json")
  mkdir -p "$TMP_DIR/session-cache"
  output=$(echo "{\"hook_event_name\":\"SessionStart\",\"source\":\"clear\",\"cwd\":\"$PROJECT_DIR\"}" \
    | env "${SEAT_ENV[@]}" CLAUDE_SESSION_CACHE_DIR="$TMP_DIR/session-cache" bash "$RESOLVED_HOOK" 2>/dev/null) || true
  after=$(shasum "$DECOY/.state.json")
  assert_neq "$before" "$after" "with the seat's variables inherited, the decoy IS reseeded"
  has "Session: LIVE_DECOY" "$output" "with the seat's variables inherited, the decoy IS resolved"
}

# --- Loom-log excerpt edge cases (from the review's scratch cases A–J) ---

# Writes stdin to a loom log under a path with spaces; callable at the end of a pipe.
rc_log() { mkdir -p "$TMP_DIR/shared drive/sess ion"; cat > "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md"; }

test_excerpt_delivers_entries_after_the_markers() {
  rc_log <<'MD'
# Loom log
## [2026-10-01 10:00:00] 🧵 LEDGER (10:00) OLD_LEDGER_MARK
* old
## [2026-10-01 10:05:00] 🤝 Hand-over written (10:05) HANDOVER_MARK
* hand
## [2026-10-01 11:00:00] 🧵 [THREADX] done NEWEST_ENTRY_MARK
* the newest state
MD
  local out
  out=$(loom_log_excerpt "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md")
  has "OLD_LEDGER_MARK" "$out" "A: ledger delivered"
  has "HANDOVER_MARK" "$out" "A: hand-over delivered"
  has "NEWEST_ENTRY_MARK" "$out" "A: entry newer than both markers delivered"
  has "Entries written after the latest marker: 1" "$out" "A: the tail is labelled with its count"
}

test_excerpt_tail_is_capped_and_keeps_the_newest() {
  { printf '## 🧵 Ledger (live — rewrite in place as threads advance)\n* t\n'
    awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "## [2026-10-01 10:00:00] 🔧 entry %d\nbody body body body body body body body\n", i }'; } | rc_log
  local out
  out=$(loom_log_excerpt "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md" 4000)
  has "entry 3000" "$out" "H: top-of-file ledger + 3000 newer entries → newest entry delivered"
  assert_eq "0" "$(grep -cxF '## [2026-10-01 10:00:00] 🔧 entry 10' <<< "$out")" "H: old entries are not"
  assert_gt "8000" "$(printf '%s' "$out" | wc -c | tr -d ' ')" "H: excerpt stays near its cap"
}

test_excerpt_ignores_erratum_and_ledger_named_threads() {
  printf '## [t] 🧵 LEDGER (10:00) REAL_LEDGER_BODY\n* ALPHA_ROW\n## [t] 🧵 LEDGER erratum (10:01): ERRATUM_MARK\n## [t] 🧵 LEDGERNAME landed\n* n\n' | rc_log
  local out
  out=$(loom_log_excerpt "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md")
  has "ALPHA_ROW" "$out" "B/G: erratum and LEDGERNAME headings do not displace the real ledger"
}

test_excerpt_marks_a_stale_handover_and_prints_once() {
  printf '## [2026-09-01] 🤝 Hand-over written STALE_HANDOVER\n* ancient\n## [2026-10-01] 🧵 LEDGER (Oct 1) FRESH_LEDGER\n' | rc_log
  local out first
  out=$(loom_log_excerpt "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md")
  first=$(grep -m1 'STALE_HANDOVER\|FRESH_LEDGER' <<< "$out")
  has "FRESH_LEDGER" "$first" "C: the newer marker comes first"
  has "OLDER than the Ledger" "$out" "C: the stale hand-over is labelled"
  printf '## [t] 🧵 LEDGER + 🤝 Hand-over written BOTH_MARK\n* body\n' | rc_log
  out=$(loom_log_excerpt "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md")
  assert_eq "1" "$(grep -c BOTH_MARK <<< "$out")" "F: a heading carrying both markers is printed once"
}

test_excerpt_pointer_quotes_the_path_and_notes_a_cut() {
  { printf '## [t] 🧵 LEDGER (x)\n'; awk 'BEGIN { for (i = 1; i <= 2000; i++) print "row row row row row row row row row row row row row row row row row row row row " i }'; } | rc_log
  local out
  out=$(loom_log_excerpt "$TMP_DIR/shared drive/sess ion/LOOM_LOG.md")
  has "'$TMP_DIR/shared drive/sess ion/LOOM_LOG.md'" "$(head -1 <<< "$out")" "E: pointer quotes a path containing spaces"
  has "[... block cut at 50000 bytes" "$out" "a cut ledger block says so"
}

# --- Pitfalls index: kit's severity form and placeholders ---

test_index_reads_severity_marked_bullets() {
  local f="$TMP_DIR/glyph-PITFALLS.md" idx
  printf -- '- **⛔⛔ ¶PTF_GLYPHED_ENTRY**: the glyphed trap text\n  continues here.\n\n*   **¶PTF_REAL**: real\n\nName entries like `¶PTF_UPPER_SNAKE_CASE`.\n' > "$f"
  idx=$(generate_pitfalls_index "$f")
  has "- ⛔⛔ ¶PTF_GLYPHED_ENTRY — the glyphed trap text continues here." "$idx" "I: severity marks kept and wrapped trap joined"
  hasnt "named in prose" "$idx" "I: severity-marked entry is not prose-only"
  hasnt "PTF_UPPER_SNAKE_CASE" "$idx" "J: placeholder name dropped"
}

test_index_on_a_copy_of_kit_pitfalls() {
  local kit="$SCRIPT_DIR/scripts/tests/fixtures/kit-pitfalls/PITFALLS.md" copy="$TMP_DIR/kit-PITFALLS.md" idx
  assert_file_exists "$kit" "kit PITFALLS.md snapshot present in the fixtures"
  cp "$kit" "$copy"
  idx=$(generate_pitfalls_index "$copy")
  local defined
  defined=$(grep -cE '^[[:space:]]*[*-][[:space:]]+\*\*[^*]*¶PTF_' "$copy")
  assert_gt "$defined" "0" "kit copy has bullet definitions"
  assert_eq "0" "$(grep -c 'named in prose' <<< "$idx")" "every kit entry carries its trap text"
  has "⛔" "$idx" "severity marks survive"
}

# --- Session artifacts are recorded as excerpts, and lanes are not handed them whole ---

test_excerpted_artifacts_recorded_as_excerpts() {
  create_loom_session
  make_loom_log "$LOOM_SESSION/LOOM_LOG.md"
  printf '## d\nx\n' > "$LOOM_SESSION/DIALOGUE.md"
  run_hook "clear" > /dev/null || true
  local seed="$PROJECT_DIR/sessions/.seeds/$$.json"
  assert_eq "false" "$(jq '(.preloadedFiles // []) | any(endswith("/LOOM_LOG.md") or endswith("/DIALOGUE.md"))' "$seed")" "log and DIALOGUE not in preloadedFiles"
  assert_eq "2" "$(jq '(.preloadedExcerpts // []) | length' "$seed")" "both recorded in preloadedExcerpts"
}

test_non_loom_skill_log_gets_the_tail() {
  local skill_dir="$FAKE_HOME/.claude/skills/implement"
  mkdir -p "$skill_dir/assets"
  echo "# t" > "$skill_dir/assets/TEMPLATE_IMPLEMENTATION_LOG.md"
  printf -- '---\ndescription: x\n---\n\n```json\n{"logTemplate": "assets/TEMPLATE_IMPLEMENTATION_LOG.md", "debriefTemplate": "assets/TEMPLATE_IMPLEMENTATION.md", "phases": [{"major": 0, "minor": 0, "name": "Setup", "steps": []}]}\n```\n' > "$skill_dir/SKILL.md"
  local sess="$PROJECT_DIR/sessions/impl"
  mkdir -p "$sess"
  printf '{"pid": %s, "skill": "implement", "lifecycle": "active", "currentPhase": "0: Setup", "preloadedFiles": []}\n' "$$" > "$sess/.state.json"
  awk 'BEGIN { for (i = 1; i <= 4000; i++) printf "## step %d\nIMPL_FILLER %d.\n", i, i; print "## last"; print "IMPL_LAST" }' > "$sess/IMPLEMENTATION_LOG.md"
  local output
  output=$(run_hook "clear") || true
  has "IMPL_LAST" "$output" "non-loom log: newest entry delivered"
  has "[... earlier entries omitted" "$output" "non-loom log: tail note"
  hasnt "IMPL_FILLER 1." "$output" "non-loom log: head not delivered"
}

test_subagent_gets_index_skips_excerpts_and_survives_large_context() {
  ln -sf "$SCRIPT_DIR/hooks/subagent-start-context.sh" "$FAKE_HOME/.claude/hooks/subagent-start-context.sh"
  local sess="$PROJECT_DIR/sessions/sub"
  mkdir -p "$sess"
  head -c 3000000 /dev/zero | tr '\0' 'L' | fold -w 100 > "$sess/LOOM_LOG.md"
  head -c 1500000 /dev/zero | tr '\0' 'D' | fold -w 100 > "$TMP_DIR/big-directive.md"
  jq -n --argjson pid "$$" --arg log "$sess/LOOM_LOG.md" --arg big "$TMP_DIR/big-directive.md" \
    '{pid: $pid, skill: "loom", lifecycle: "active", preloadedFiles: [$log, $big]}' > "$sess/.state.json"
  local out rc=0
  out=$(echo "{\"cwd\":\"$PROJECT_DIR\"}" | (cd "$PROJECT_DIR" && hook_env bash "$FAKE_HOME/.claude/hooks/subagent-start-context.sh")) || rc=$?
  assert_eq "0" "$rc" "subagent hook exits 0 with a 1.5 MB context"
  local ctx
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<< "$out" 2>/dev/null || true)
  has "[Pitfalls index, generated from:" "$ctx" "subagent receives the pitfalls index"
  has "¶PTF_FAKE_ENGINE_ENTRY" "$ctx" "index carries the engine entry"
  hasnt "LLLLLLLLLL" "$ctx" "the session log is not cat'ed whole"
  has "DDDDDDDDDD" "$ctx" "a large ordinary directive still arrives"
}

test_large_pitfalls_loaded_later_arrives_as_its_index() {
  local f="$TMP_DIR/area/.directives/PITFALLS.md"
  mkdir -p "$(dirname "$f")"
  { printf -- '*   **¶PTF_LATER_ENTRY**: the later trap\n\n'; head -c 20000 /dev/zero | tr '\0' 'b' | fold -w 100; } > "$f"
  mkdir -p "$PROJECT_DIR/sessions/.seeds"
  (cd "$PROJECT_DIR" && CLAUDE_SUPERVISOR_PID=$$ CLAUDE_SESSION_CACHE_DIR="$TMP_DIR/session-cache" preload_ensure "$f" "test" "immediate")
  local content
  content=$(cd "$PROJECT_DIR" && CLAUDE_SUPERVISOR_PID=77777 CLAUDE_SESSION_CACHE_DIR="$TMP_DIR/session-cache" bash -c 'source "$HOME/.claude/scripts/lib.sh"; preload_ensure "$1" test immediate; printf "%b" "$_PRELOAD_CONTENT"' _ "$f")
  has "¶PTF_LATER_ENTRY — the later trap" "$content" "large PITFALLS delivered as its index"
  has "grep -n -A12" "$content" "with a pointer to read an entry"
  hasnt "bbbbbbbbbb" "$content" "not the body"
  local small="$TMP_DIR/area2/.directives/PITFALLS.md"
  mkdir -p "$(dirname "$small")"; printf -- '*   **¶PTF_SMALL**: small body SMALL_BODY\n' > "$small"
  content=$(cd "$PROJECT_DIR" && CLAUDE_SUPERVISOR_PID=77778 CLAUDE_SESSION_CACHE_DIR="$TMP_DIR/session-cache" bash -c 'source "$HOME/.claude/scripts/lib.sh"; preload_ensure "$1" test immediate; printf "%b" "$_PRELOAD_CONTENT"' _ "$small")
  has "SMALL_BODY" "$content" "a small PITFALLS is still delivered whole"
}

# --- A dehydrated restart (startup) at the reviewer's measured shape: seven required files, ~223 KB,
# one of them the loom log itself and one the active skill's SKILL.md ---

# The line that follows the first line equal to $1 in file $2.
line_after() { awk -v want="$1" 'found { print; exit } $0 == want { found = 1 }' "$2"; }

make_dehydrated_context() {
  local d="$TMP_DIR/required" i
  mkdir -p "$d"
  for i in 1 2 3 4; do
    awk -v n="$i" 'BEGIN { for (j = 1; j <= 700; j++) printf "## [t] required %d entry %d\nrequired body text for padding the file out\n", n, j }' > "$d/REQ_$i.md"
  done
  jq -n --arg log "$LOOM_SESSION/LOOM_LOG.md" --arg skill "$HOME/.claude/skills/loom/SKILL.md" \
    --arg r1 "$d/REQ_1.md" --arg r2 "$d/REQ_2.md" --arg r3 "$d/REQ_3.md" --arg r4 "$d/REQ_4.md" \
    '{summary: "DEHYDRATED_SUMMARY_MARKER", lastAction: "x", nextSteps: ["y"], handoverInstructions: "z",
      requiredFiles: [$log, $r1, $r2, $r3, $r4, $skill]}' > "$TMP_DIR/dehyd.json"
  jq --slurpfile d "$TMP_DIR/dehyd.json" '.dehydratedContext = $d[0]' "$LOOM_SESSION/.state.json" > "$TMP_DIR/st" \
    && mv "$TMP_DIR/st" "$LOOM_SESSION/.state.json"
}

test_startup_with_dehydrated_context_keeps_session_state_inline() {
  use_real_engine
  make_measured_loom_session
  make_dehydrated_context
  run_hook "startup" > "$TMP_DIR/preload.txt" || true
  split_inline "$TMP_DIR/preload.txt" "$TMP_DIR/inline.txt" "$TMP_DIR/spill.txt"
  local all; all=$(cat "$TMP_DIR/preload.txt")
  has "DEHYDRATED_SUMMARY_MARKER" "$(cat "$TMP_DIR/inline.txt")" "startup: dehydrated summary is inline"
  assert_session_state_inline "$TMP_DIR/inline.txt" "startup with dehydrated context"
  has "[Already in this preload" "$(line_after "#### File: $LOOM_SESSION/LOOM_LOG.md" "$TMP_DIR/preload.txt")" "the loom log as a required file is not delivered again"
  has "[Already in this preload" "$(line_after "#### File: $HOME/.claude/skills/loom/SKILL.md" "$TMP_DIR/preload.txt")" "the active SKILL.md as a required file is not delivered again"
  has "required 1 entry 700" "$all" "an ordinary required file is still delivered"
  local notice; notice=$(grep -F '[preload overflow:' "$TMP_DIR/inline.txt" || true)
  if [ -n "$notice" ]; then
    hasnt "DIALOGUE" "$notice" "the overflow notice does not list the DIALOGUE tail"
    hasnt "loom-log" "$notice" "the overflow notice does not list the log excerpt"
  else
    pass "nothing spilled"
  fi
}

test_overflow_notice_names_the_sections_that_spilled() {
  local f="$TMP_DIR/sections.txt" gen="$TMP_DIR/gen2.sh" out
  {
    echo "[Preloaded: /fit/INLINE_FIRST.md]"; head -c 30000 /dev/zero | tr '\0' 'a' | fold -w 100; echo
    echo "[DIALOGUE excerpt: x]"; echo "newest"
    echo "[Preloaded: /fit/SPILL_PARTIAL.md]"; head -c 30000 /dev/zero | tr '\0' 'b' | fold -w 100; echo
    echo "#### File: /fit/SPILL_WHOLE.md"; head -c 20000 /dev/zero | tr '\0' 'c' | fold -w 100; echo
  } > "$f"
  printf '#!/bin/bash\ncat %q\n' "$f" > "$gen"; chmod +x "$gen"
  rm -rf "$TMP_DIR/cc"; mkdir -p "$TMP_DIR/cc"
  out=$(echo '{"session_id":"n","source":"clear"}' | PRELOAD_GENERATOR="$gen" PRELOAD_CACHE_DIR="$TMP_DIR/cc" PRELOAD_CHUNK_BYTES=8500 \
    bash "$SCRIPT_DIR/hooks/session-start-chunk.sh" 5 6)
  local notice; notice=$(grep -F '[preload overflow:' <<< "$out")
  has "/fit/SPILL_PARTIAL.md (from part-way through)" "$notice" "a section cut by the boundary is named as partial"
  has "required file /fit/SPILL_WHOLE.md" "$notice" "a wholly spilled section is named"
  hasnt "INLINE_FIRST" "$notice" "an inline section is not named"
  hasnt "DIALOGUE" "$notice" "an inline DIALOGUE tail is not named"
}

# --- Definitions that left SIGILS.md are delivered by the citations that use them ---

test_moved_definitions_live_once_in_their_own_files() {
  local n f
  for n in CMD_FIND_TAGGED_FILES CMD_TAG_FILE CMD_UNTAG_FILE CMD_SWAP_TAG_IN_FILE CMD_HANDLE_INLINE_TAG; do
    f="$SCRIPT_DIR/.directives/commands/$n.md"
    has "¶$n" "$(cat "$f" 2>/dev/null)" "$n defined in commands/$n.md"
    hasnt "¶$n" "$(cat "$SCRIPT_DIR/.directives/SIGILS.md")" "$n no longer defined in SIGILS.md"
  done
  for n in FMT_DECISION_CARD FMT_ANSWER_GRADATION FMT_CONTEXT_BLOCK FMT_TICKET_LINK FMT_TICKET_COMMENT_LINK FMT_FILE_LINK; do
    has "¶$n" "$(cat "$SCRIPT_DIR/.directives/formats/$n.md" 2>/dev/null)" "$n defined in formats/$n.md"
    hasnt "¶$n" "$(cat "$SCRIPT_DIR/.directives/SIGILS.md")" "$n no longer defined in SIGILS.md"
  done
  has "¶TAG_DISPATCH" "$(cat "$SCRIPT_DIR/.directives/tags/TAG_DISPATCH.md" 2>/dev/null)" "TAG_DISPATCH defined in tags/TAG_DISPATCH.md"
  hasnt "¶TAG_DISPATCH" "$(cat "$SCRIPT_DIR/.directives/SIGILS.md")" "TAG_DISPATCH no longer defined in SIGILS.md"
}

test_citing_files_deliver_the_tag_commands() {
  local d="$SCRIPT_DIR/.directives/commands" pair src want got
  for pair in CMD_HANDLE_INLINE_TAG:CMD_TAG_FILE CMD_RESOLVE_BARE_TAGS:CMD_TAG_FILE CMD_PROCESS_CHECKLISTS:CMD_TAG_FILE \
              CMD_CAPTURE_SIDE_DISCOVERIES:CMD_TAG_FILE CMD_TAG_TRIAGE:CMD_HANDLE_INLINE_TAG CMD_TAG_TRIAGE:CMD_TAG_FILE \
              CMD_WALK_THROUGH_RESULTS:CMD_HANDLE_INLINE_TAG CMD_WALK_THROUGH_RESULTS:CMD_TAG_FILE CMD_DECISION_TREE:CMD_HANDLE_INLINE_TAG; do
    src="${pair%%:*}"; want="${pair#*:}"
    got=$(resolve_refs "$d/$src.md" 1 '[]' 2>/dev/null || true)
    has "/commands/$want.md" "$got" "$src delivers $want"
  done
  got=$(resolve_refs "$SCRIPT_DIR/skills/review/SKILL.md" 1 '[]' 2>/dev/null || true)
  has "/commands/CMD_SWAP_TAG_IN_FILE.md" "$got" "/review delivers CMD_SWAP_TAG_IN_FILE"
  use_real_engine
  printf 'Route with §TAG_DISPATCH; render with §FMT_DECISION_CARD.\n' > "$TMP_DIR/cites.md"
  got=$(resolve_refs "$TMP_DIR/cites.md" 1 '[]' 2>/dev/null || true)
  has "/tags/TAG_DISPATCH.md" "$got" "a bare §TAG_ citation resolves to tags/"
  has "/formats/FMT_DECISION_CARD.md" "$got" "a bare §FMT_ citation resolves to formats/"
}

run_discovered_tests
