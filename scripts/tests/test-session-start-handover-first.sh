#!/bin/bash
# tests/test-session-start-handover-first.sh — after /dehydrate, the restored session sees its
# hand-over before the standards, inside the inline slots.
#
# Runs THIS tree's session-start-restore.sh through THIS tree's session-start-chunk.sh (48 slots
# of 8500 bytes, as scripts/setup-lib.sh registers them) on a synthetic dehydrated .state.json
# (fixtures/dehydrated-restore/state.json: each text field opens with a HOFIRST_MARK_* marker),
# with this tree's real standards and skills linked into a fake HOME. Required files and the loom
# log are synthetic and sized like real ones (each required file is tailed to 50 KB), so the
# preload overflows the slots the way a real restore does.
#
# Run A requires four session files and a loom skill dep (TEMPLATE_LOOM.md), which the skill
# files would otherwise deliver only after the 217 KB loom SKILL.md, past the slots. Run B
# requires the loom SKILL.md alone, which is carried whole inside the required block.
#
# HANDOVER_FIRST_LIVE=1 measures a live session instead: it reads
# $HANDOVER_FIRST_LIVE_SESSION/.state.json (and that session's LOOM_LOG.md and DIALOGUE.md, if
# present) without writing to them, and copies them into the sandbox. With no session given, or
# one whose state holds no dehydratedContext, the suite skips.
#
# Run: bash scripts/tests/run-all.sh test-session-start-handover-first.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

TREE="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$TREE/hooks/session-start-restore.sh"
CHUNKER="$TREE/hooks/session-start-chunk.sh"
FIXTURE="$TREE/scripts/tests/fixtures/dehydrated-restore/state.json"
SLOTS=48
CHUNK=8500

LIVE=0
if [ "${HANDOVER_FIRST_LIVE:-0}" = 1 ]; then
  LIVE_SESSION="${HANDOVER_FIRST_LIVE_SESSION:-}"
  if [ -z "$LIVE_SESSION" ] || [ ! -f "$LIVE_SESSION/.state.json" ]; then
    echo "SKIP: HANDOVER_FIRST_LIVE=1 needs HANDOVER_FIRST_LIVE_SESSION=<session dir holding .state.json>"
    exit 0
  fi
  if ! jq -e '.dehydratedContext' "$LIVE_SESSION/.state.json" >/dev/null 2>&1; then
    echo "SKIP: $LIVE_SESSION/.state.json holds no dehydratedContext"
    exit 0
  fi
  LIVE=1
fi

TMP_DIR=$(mktemp -d)
trap 'teardown_fake_home; rm -rf "$TMP_DIR"' EXIT
setup_fake_home "$TMP_DIR"
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"
disable_fleet_tmux
ln -sf "$TREE/scripts/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$TREE/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$HOOK" "$FAKE_HOME/.claude/hooks/session-start-restore.sh"
ln -sf "$TREE/.directives" "$FAKE_HOME/.claude/.directives"
ln -sf "$TREE/skills" "$FAKE_HOME/.claude/skills"
ln -sf "$TREE" "$FAKE_HOME/.claude/engine"
export CLAUDE_SESSION_CACHE_DIR="$TMP_DIR"

PROJECT="$TMP_DIR/project"
SESSION="$PROJECT/sessions/2026_01_01_HANDOVER_FIRST"
mkdir -p "$SESSION/builds" "$PROJECT/.claude"
SKILL_MD="$HOME/.claude/skills/loom/SKILL.md"
SKILL_DEP="$HOME/.claude/skills/loom/assets/TEMPLATE_LOOM.md"

# Synthetic file of about $2 bytes with markdown headings, so heading_aligned_tail has seams.
filler() {
  local path="$1" bytes="$2" n=0
  mkdir -p "$(dirname "$path")"
  : > "$path"
  while [ "$(wc -c < "$path")" -lt "$bytes" ]; do
    {
      printf '## Entry %04d\n' "$n"
      for _ in 1 2 3 4 5 6 7 8; do
        printf -- '- line of filler text for %s, entry %04d, so the file has real weight\n' "$(basename "$path")" "$n"
      done
      printf '\n'
    } >> "$path"
    n=$((n + 1))
  done
}

# write_state SRC DEST [REQUIRED...]: the dehydrated state for a run owned by this shell.
write_state() {
  local src="$1" dest="$2"
  shift 2
  if [ "$LIVE" = 1 ]; then
    jq --arg pid "$$" '.pid = ($pid | tonumber) | del(.fleetPaneId) | .lifecycle = "active"' \
      "$src" > "$dest"
  else
    jq --arg pid "$$" --args '.pid = ($pid | tonumber) | del(.fleetPaneId) | .lifecycle = "active"
        | .dehydratedContext.requiredFiles = $ARGS.positional' "$@" < "$src" > "$dest"
  fi
}

# run_slots ID SESSION_DIR: the 48 slots exactly as Claude Code registers them, for the dehydrated
# state in SESSION_DIR. Slice i goes to $OUT/<i>; sets OUT, CACHE_FILE, INLINE, OVERFLOW.
run_slots() {
  local id="$1" input i
  OUT="$TMP_DIR/slices-$id"
  mkdir -p "$OUT"
  input=$(jq -n --arg cwd "$PROJECT" --arg id "$id" '{hook_event_name:"SessionStart",source:"startup",session_id:$id,cwd:$cwd}')
  for ((i = 0; i < SLOTS; i++)); do
    printf '%s' "$input" | env -u TMUX -u TMUX_PANE CLAUDE_SUPERVISOR_PID="$$" \
      PRELOAD_GENERATOR="$HOOK" PRELOAD_CACHE_DIR="$TMP_DIR/cache-$id" PRELOAD_CHUNK_BYTES="$CHUNK" \
      bash "$CHUNKER" "$i" "$SLOTS" > "$OUT/$i" 2>/dev/null
  done
  CACHE_FILE=$(ls "$TMP_DIR/cache-$id"/*.txt 2>/dev/null | head -1)
  if [ ! -s "${CACHE_FILE:-}" ]; then
    fail "run $id: the generator wrote a preload cache" "a non-empty cache-$id/*.txt" "${CACHE_FILE:-none}"
    exit_with_results
  fi
  INLINE="$TMP_DIR/inline-$id.txt"
  for ((i = 0; i < SLOTS; i++)); do cat "$OUT/$i"; done > "$INLINE"
  OVERFLOW=$(grep -h '^\[preload overflow' "$OUT/$((SLOTS - 1))" || true)
}

REQ=()
if [ "$LIVE" = 1 ]; then
  for f in LOOM_LOG.md DIALOGUE.md; do
    [ -f "$LIVE_SESSION/$f" ] && cp "$LIVE_SESSION/$f" "$SESSION/$f"
  done
  STATE_SRC="$LIVE_SESSION/.state.json"
  while IFS= read -r p; do [ -n "$p" ] && REQ+=("$p"); done \
    < <(jq -r '.dehydratedContext.requiredFiles // [] | .[]' "$STATE_SRC")
else
  filler "$SESSION/LOOM_LOG.md" 120000
  filler "$SESSION/DIALOGUE.md" 30000
  for name in LOOM_INHERITANCE.md LOOM_LOG_COPY.md DIALOGUE_COPY.md builds/SNAPSHOT_REPORT.md; do
    filler "$PROJECT/sessions/$name" 60000
    REQ+=("$PROJECT/sessions/$name")
  done
  REQ+=("$SKILL_DEP")
  STATE_SRC="$FIXTURE"
fi
write_state "$STATE_SRC" "$SESSION/.state.json" ${REQ[@]+"${REQ[@]}"}
run_slots handoverfirst "$SESSION"

# The slot (0-based) whose slice first holds the fixed string $1, or "none".
slot_of() {
  local i
  for ((i = 0; i < SLOTS; i++)); do
    grep -qF -- "$1" "$OUT/$i" && { echo "$i"; return; }
  done
  echo none
}
# Byte offset of the first line holding $1 in the full preload, or -1.
offset_of() {
  LC_ALL=C awk -v s="$1" 'index($0, s) { print off; found = 1; exit } { off += length($0) + 1 } END { if (!found) print -1 }' "$CACHE_FILE"
}
# pass when $1 (a fixed string) is in the full preload before the standards and inside the slots.
assert_inline_before_standards() {
  local needle="$1" label="$2" off slot
  off=$(offset_of "$needle")
  slot=$(slot_of "$needle")
  if [ "$off" -ge 0 ] && [ "$STD_OFF" -ge 0 ] && [ "$off" -lt "$STD_OFF" ] && [ "$slot" != none ]; then
    pass "$label"
  else
    fail "$label" "offset < $STD_OFF and in a slot" "offset $off, slot $slot"
  fi
}

# Measured on run A.
BYTES=$(wc -c < "$CACHE_FILE" | tr -d ' ')
CHUNKS=$(( (BYTES + CHUNK - 1) / CHUNK ))
STD_OFF=$(offset_of "/.directives/COMMANDS.md]")
H_SLOT=$(slot_of "## Session Recovery (Dehydrated Context)")
R_SLOT=$(slot_of "## Session Recovery: Required Files")
echo "  measure: preload ${BYTES} bytes, about ${CHUNKS} chunks of ${CHUNK} for ${SLOTS} slots"
echo "  measure: hand-over in slot ${H_SLOT}, required files from slot ${R_SLOT}, COMMANDS.md at byte ${STD_OFF}"
echo "  measure: ${OVERFLOW:-no overflow}"

# ============================================================
test_handover_in_first_slot() {
  assert_eq "0" "$H_SLOT" "the dehydrated hand-over opens in slot 0"
}

test_handover_sections_precede_standards() {
  local label
  for label in "### Summary" "### Last Action" "### Next Steps" "### Handover Instructions" \
    "### User Interaction History"; do
    assert_inline_before_standards "$label" "$label is inline, before the standards"
  done
  [ ${#REQ[@]} -eq 0 ] || assert_inline_before_standards "## Session Recovery: Required Files" \
    "the required files start inline, before the standards"
}

test_handover_text_is_inline() {
  [ "$LIVE" = 0 ] || { pass "live run: the markers belong to the synthetic fixture"; return; }
  local m
  for m in SUMMARY LAST_ACTION NEXT_STEP_A NEXT_STEP_C HANDOVER USER_HISTORY; do
    assert_inline_before_standards "HOFIRST_MARK_$m" "the $m text itself is inline, before the standards"
  done
}

test_no_required_file_in_overflow() {
  local p real
  if [ -z "$OVERFLOW" ]; then
    pass "no overflow, so no required file was cut"
    return
  fi
  assert_not_contains "dehydrated summary" "$OVERFLOW" "the overflow did not cut the dehydrated summary"
  assert_not_contains "required file " "$OVERFLOW" "the overflow did not cut a required file's block"
  for p in ${REQ[@]+"${REQ[@]}"}; do
    assert_not_contains "${p/#$HOME/~}" "$OVERFLOW" "the overflow line does not name required $(basename "$p") by ~ path"
    assert_not_contains "$p" "$OVERFLOW" "the overflow line does not name required $(basename "$p")"
    real="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")"
    assert_not_contains "$real" "$OVERFLOW" "the overflow line does not name required $(basename "$p") by its real path"
  done
  assert_contains ".directives/" "$OVERFLOW" "the overflow cut standards"
}

# The fixed string $1 is in file $2. assert_contains would retry a miss as a regex, and a
# "[Preloaded: …]" needle read as a regex is a bracket expression that matches almost anything.
assert_file_has() {
  if grep -qF -- "$1" "$2"; then pass "$3"; else fail "$3" "contains '$1'" "absent from $(basename "$2")"; fi
}

# The last non-blank line of file $1 is in the 48 slots.
assert_tail_inline() {
  local last
  last=$(grep -v '^[[:space:]]*$' "$1" | tail -1)
  if grep -qF -- "$last" "$INLINE"; then
    pass "$2"
  else
    fail "$2" "$last" "absent from the 48 slots"
  fi
}

test_required_skill_dep_carried() {
  [ "$LIVE" = 0 ] || { pass "live run: the skill-dep case belongs to the synthetic run"; return; }
  assert_file_has "[The skill file, whole; carried here" "$INLINE" \
    "the required skill dep is carried inside the required block"
  assert_tail_inline "$SKILL_DEP" "the required skill dep is inline to its last line"
  assert_eq "0" "$(grep -c "^\[Preloaded: .*/skills/loom/assets/TEMPLATE_LOOM.md\]" "$CACHE_FILE")" \
    "the carried skill dep is not repeated among the skill files"
}

test_skill_files_and_session_excerpts_present() {
  assert_file_has "[Preloaded: $SKILL_MD]" "$CACHE_FILE" "the loom SKILL.md is still among the skill files"
  local n
  # CMD_DEHYDRATE and CMD_RESUME_SESSION are boot standards, not skill files.
  n=$(grep "^\[Preloaded: .*/\.directives/commands/CMD_" "$CACHE_FILE" \
    | grep -cv "/CMD_DEHYDRATE.md\]\|/CMD_RESUME_SESSION.md\]" || true)
  if [ "${n:-0}" -gt 0 ]; then
    pass "the skill's command files are still in the preload ($n blocks)"
  else
    fail "the skill's command files are still in the preload" "at least one [Preloaded: …/CMD_*] block" "0"
  fi
  assert_inline_before_standards "[Session Files: " "the session file listing is inline, before the standards"
}

test_standards_index_inline() {
  assert_inline_before_standards "[Standards index, generated at session start" \
    "the standards index is inline, before the standards"
  assert_inline_before_standards "- ¶INV_PROTOCOL_IS_TASK — " "the index names an ¶INV_ rule"
  assert_inline_before_standards "- ¶CMD_APPEND_LOG — " "the index names a ¶CMD_ command"
}

test_standards_still_in_full_preload() {
  if grep -qF "/.directives/INVARIANTS.md]" "$CACHE_FILE"; then
    pass "the standards are still in the full preload"
  else
    fail "the standards are still in the full preload" "[Preloaded: …/INVARIANTS.md]" "absent"
  fi
}

# Run B: the loom SKILL.md is the one required file. It is carried whole and inline, not repeated.
test_required_skill_md_carried_whole() {
  [ "$LIVE" = 0 ] || { pass "live run: the SKILL.md case belongs to the synthetic run"; return; }
  local s2="$PROJECT/sessions/2026_01_02_HANDOVER_SKILL"
  mkdir -p "$s2"
  rm -f "$SESSION/.state.json"
  write_state "$FIXTURE" "$s2/.state.json" "$SKILL_MD"
  run_slots handoverskill "$s2"
  STD_OFF=$(offset_of "/.directives/COMMANDS.md]")
  echo "  measure (run B): $(wc -c < "$CACHE_FILE" | tr -d ' ') bytes; ${OVERFLOW:-no overflow}" | cut -c1-200
  assert_inline_before_standards "HOFIRST_MARK_SUMMARY" "run B restores the hand-over inline"
  assert_file_has "[The skill file, whole; carried here" "$INLINE" \
    "the required SKILL.md is carried inside the required block"
  assert_tail_inline "$SKILL_MD" "the required SKILL.md is inline to its last line"
  assert_eq "0" "$(grep -cF "[Preloaded: $SKILL_MD]" "$CACHE_FILE")" \
    "the carried SKILL.md is not repeated among the skill files"
  assert_not_contains "$SKILL_MD" "$OVERFLOW" "the overflow line does not name the required SKILL.md"
  assert_not_contains "required file " "$OVERFLOW" "run B's overflow cut no required file"
}

run_test test_handover_in_first_slot
run_test test_handover_sections_precede_standards
run_test test_handover_text_is_inline
run_test test_no_required_file_in_overflow
run_test test_required_skill_dep_carried
run_test test_skill_files_and_session_excerpts_present
run_test test_standards_index_inline
run_test test_standards_still_in_full_preload
run_test test_required_skill_md_carried_whole
exit_with_results
