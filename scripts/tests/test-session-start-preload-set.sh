#!/bin/bash
# test-session-start-preload-set.sh — what SessionStart injects, checked against its sources
#
# The standards the hook prints must be exactly get_session_start_seeds (the list PostToolUse
# dedup reads), the pitfalls index must name every ¶PTF_ entry in the files it is built from,
# and a loom resume must carry an excerpt of the loom log rather than the whole log.

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$HOME/.claude/hooks/session-start-restore.sh"
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

run_hook() {
  local source="${1:-startup}"
  local cwd="${2:-$PROJECT_DIR}"
  local owner=$$
  echo "{\"hook_event_name\":\"SessionStart\",\"source\":\"$source\",\"cwd\":\"$cwd\"}" \
    | CLAUDE_SUPERVISOR_PID="$owner" CLAUDE_HOOK_PPID="$owner" "$RESOLVED_HOOK" 2>/dev/null
  rm -f "/tmp/claude-session-cache-$owner" 2>/dev/null || true
}

# The paths of the [Preloaded: <path>] blocks a hook run printed, sorted, as a JSON array.
printed_standards() {
  grep -E '^\[Preloaded: /' <<< "$1" | sed -E 's/^\[Preloaded: (.*)\]$/\1/' | jq -R . | jq -sc 'sort'
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
    if ! grep -qF -- "- $name — " <<< "$index"; then
      missing=$((missing + 1))
      echo "    not indexed: $name"
    fi
  done <<< "$names"
  assert_eq "0" "$missing" "every ¶PTF_ name in PITFALLS.md appears in the index"
  assert_eq "$(echo "$names" | grep -c .)" "$(echo "$index" | grep -c '^- ¶PTF_')" "one index line per distinct name"

  # A definition line must yield its trap, not the prose-only placeholder.
  local defined placeholder=0
  defined=$(grep -oE '^[[:space:]]*[*-][[:space:]]+\*\*¶PTF_[A-Z0-9_]+|^#+ .*¶PTF_[A-Z0-9_]+' "$REAL_PITFALLS" \
    | grep -v -i addendum | grep -o '¶PTF_[A-Z0-9_]*' | sort -u)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if grep -F -- "- $name — " <<< "$index" | grep -q 'named in prose, no definition line'; then
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
  hasnt "AFTER_MARKER" "$out" "entry after the hand-over absent"
  has "$log is $bytes bytes" "$out" "pointer names path and size"
  has "grep -n '^## ' $log" "$out" "pointer gives the grep recipe"
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
  has "[Loom log excerpt: $LOOM_SESSION/LOOM_LOG.md is" "$output" "excerpt pointer present"
  has "HANDOVER_MARKER" "$output" "hand-over delivered"
  hasnt "FILLER_MARKER" "$output" "rest of the log not delivered"
}

test_non_loom_log_gets_heading_aligned_tail() {
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
    printf '## [2026-10-23 19:16:00] 🤝 Hand-over written (19:18)\nFIT_HANDOVER_MARKER\n'
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

run_discovered_tests
