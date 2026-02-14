#!/bin/bash
# tests/test-session-start-restore.sh — Tests for session-start-restore.sh hook
#
# Tests standards preloading on SessionStart (all sources):
#   1. Standards files present → output contains all 3 standards
#   2. One standards file missing → skips it, includes others
#   3. All standards files missing → no standards in output (no crash)
#   4. Non-startup sources → standards preloaded, no dehydration
#   5. Standards output uses [Preloaded: path] format
#   6. Standards come before dehydrated context
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-start-restore.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# session-start-restore.sh is project-local (not in engine/hooks/)
HOOK_SCRIPT="$HOME/.claude/hooks/session-start-restore.sh"

TMP_DIR=""

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"
  disable_fleet_tmux

  # Symlink the hook and its dependencies
  ln -sf "$HOOK_SCRIPT" "$FAKE_HOME/.claude/hooks/session-start-restore.sh"
  ln -sf "$SCRIPT_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  ln -sf "$SCRIPT_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"

  # Create project dir with sessions/
  export PROJECT_DIR="$TMP_DIR/project"
  mkdir -p "$PROJECT_DIR/sessions"

  # Create standards files in fake home
  mkdir -p "$FAKE_HOME/.claude/.directives"
  echo "# COMMANDS content" > "$FAKE_HOME/.claude/.directives/COMMANDS.md"
  echo "# INVARIANTS content" > "$FAKE_HOME/.claude/.directives/INVARIANTS.md"
  echo "# TAGS content" > "$FAKE_HOME/.claude/.directives/TAGS.md"

  RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/session-start-restore.sh"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# Helper: run the hook with a given source
run_hook() {
  local source="${1:-startup}"
  local cwd="${2:-$PROJECT_DIR}"
  echo "{\"hook_event_name\":\"SessionStart\",\"source\":\"$source\",\"cwd\":\"$cwd\"}" \
    | "$RESOLVED_HOOK" 2>/dev/null
}

# --- Test 1: Standards files present ---
test_standards_all_present() {
  local output
  output=$(run_hook "startup") || true

  assert_contains "COMMANDS content" "$output" "output contains COMMANDS.md content"
  assert_contains "INVARIANTS content" "$output" "output contains INVARIANTS.md content"
  assert_contains "TAGS content" "$output" "output contains TAGS.md content"
}

# --- Test 2: One standards file missing ---
test_standards_one_missing() {
  rm -f "$FAKE_HOME/.claude/.directives/TAGS.md"

  local output
  output=$(run_hook "startup") || true

  assert_contains "COMMANDS content" "$output" "output contains COMMANDS.md when TAGS missing"
  assert_contains "INVARIANTS content" "$output" "output contains INVARIANTS.md when TAGS missing"
  assert_not_contains "TAGS content" "$output" "output skips missing TAGS.md"
}

# --- Test 3: All standards files missing ---
test_standards_all_missing() {
  rm -f "$FAKE_HOME/.claude/.directives/COMMANDS.md"
  rm -f "$FAKE_HOME/.claude/.directives/INVARIANTS.md"
  rm -f "$FAKE_HOME/.claude/.directives/TAGS.md"

  local output
  output=$(run_hook "startup") || true

  assert_not_contains "COMMANDS" "$output" "no COMMANDS when file missing"
  assert_not_contains "INVARIANTS" "$output" "no INVARIANTS when file missing"
  assert_not_contains "TAGS" "$output" "no TAGS when file missing"
}

# --- Test 4: Non-startup sources → standards preloaded, no dehydration ---
test_non_startup_preloads_standards() {
  local output

  output=$(run_hook "resume") || true
  assert_contains "COMMANDS content" "$output" "resume source → standards preloaded"
  assert_not_contains "Session Recovery" "$output" "resume source → no dehydrated context"

  output=$(run_hook "compact") || true
  assert_contains "COMMANDS content" "$output" "compact source → standards preloaded"
  assert_not_contains "Session Recovery" "$output" "compact source → no dehydrated context"

  output=$(run_hook "clear") || true
  assert_contains "COMMANDS content" "$output" "clear source → standards preloaded"
  assert_not_contains "Session Recovery" "$output" "clear source → no dehydrated context"
}

# --- Test 5: Standards output uses [Preloaded: path] format ---
test_standards_preloaded_format() {
  local output
  output=$(run_hook "startup") || true

  assert_contains "[Preloaded:" "$output" "output uses [Preloaded:] format marker"
  assert_contains "COMMANDS.md]" "$output" "preloaded marker includes COMMANDS.md filename"
  assert_contains "INVARIANTS.md]" "$output" "preloaded marker includes INVARIANTS.md filename"
  assert_contains "TAGS.md]" "$output" "preloaded marker includes TAGS.md filename"
}

# --- Test 6: Standards come before dehydrated context ---
test_standards_before_dehydrated() {
  # Create a session with dehydrated context
  local session_dir="$PROJECT_DIR/sessions/test_session"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "test",
  "lifecycle": "active",
  "dehydratedContext": {
    "summary": "Test dehydrated context",
    "lastAction": "testing",
    "nextSteps": ["verify"],
    "handoverInstructions": "none"
  }
}
JSON

  local output
  output=$(run_hook "startup") || true

  # Both standards and dehydrated context should be present
  assert_contains "COMMANDS content" "$output" "standards present alongside dehydrated context"
  assert_contains "Test dehydrated context" "$output" "dehydrated context still present"

  # Standards should appear before dehydrated context
  local standards_pos dehydrated_pos
  standards_pos=$(echo "$output" | grep -n "Preloaded:" | head -1 | cut -d: -f1)
  dehydrated_pos=$(echo "$output" | grep -n "Session Recovery" | head -1 | cut -d: -f1)

  if [ -n "$standards_pos" ] && [ -n "$dehydrated_pos" ] && [ "$standards_pos" -lt "$dehydrated_pos" ]; then
    pass "standards appear before dehydrated context"
  else
    fail "standards appear before dehydrated context" "standards_line < dehydrated_line" "standards=$standards_pos, dehydrated=$dehydrated_pos"
  fi
}

# --- Test 7: Preloaded files recorded in .state.json ---
test_preloaded_files_recorded() {
  # Create an active session with a .state.json that has preloadedFiles
  local session_dir="$PROJECT_DIR/sessions/test_preloaded"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "test",
  "lifecycle": "active",
  "preloadedFiles": ["old_file.md"]
}
JSON

  # Create CMD_DEHYDRATE.md, CMD_RESUME_SESSION.md, and CMD_PARSE_PARAMETERS.md so all 6 paths exist
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  echo "# CMD_DEHYDRATE" > "$FAKE_HOME/.claude/.directives/commands/CMD_DEHYDRATE.md"
  echo "# CMD_RESUME_SESSION" > "$FAKE_HOME/.claude/.directives/commands/CMD_RESUME_SESSION.md"
  echo "# CMD_PARSE_PARAMETERS" > "$FAKE_HOME/.claude/.directives/commands/CMD_PARSE_PARAMETERS.md"

  run_hook "startup" > /dev/null || true

  # After hook, .state.json should have preloadedFiles with the 6 standard+command paths
  local count
  count=$(jq '.preloadedFiles | length' "$session_dir/.state.json" 2>/dev/null || echo "0")
  assert_eq "6" "$count" "preloadedFiles has 6 entries after startup"

  # Check specific paths are present
  local has_commands has_invariants has_tags has_dehydrate has_rehydrate has_parse_params
  has_commands=$(jq '[.preloadedFiles[] | select(contains("COMMANDS.md"))] | length' "$session_dir/.state.json" 2>/dev/null || echo "0")
  has_invariants=$(jq '[.preloadedFiles[] | select(contains("INVARIANTS.md"))] | length' "$session_dir/.state.json" 2>/dev/null || echo "0")
  has_tags=$(jq '[.preloadedFiles[] | select(contains("TAGS.md"))] | length' "$session_dir/.state.json" 2>/dev/null || echo "0")
  has_dehydrate=$(jq '[.preloadedFiles[] | select(contains("CMD_DEHYDRATE.md"))] | length' "$session_dir/.state.json" 2>/dev/null || echo "0")
  has_rehydrate=$(jq '[.preloadedFiles[] | select(contains("CMD_RESUME_SESSION.md"))] | length' "$session_dir/.state.json" 2>/dev/null || echo "0")
  has_parse_params=$(jq '[.preloadedFiles[] | select(contains("CMD_PARSE_PARAMETERS.md"))] | length' "$session_dir/.state.json" 2>/dev/null || echo "0")

  assert_eq "1" "$has_commands" "preloadedFiles includes COMMANDS.md"
  assert_eq "1" "$has_invariants" "preloadedFiles includes INVARIANTS.md"
  assert_eq "1" "$has_tags" "preloadedFiles includes TAGS.md"
  assert_eq "1" "$has_dehydrate" "preloadedFiles includes CMD_DEHYDRATE.md"
  assert_eq "1" "$has_rehydrate" "preloadedFiles includes CMD_RESUME_SESSION.md"
  assert_eq "1" "$has_parse_params" "preloadedFiles includes CMD_PARSE_PARAMETERS.md"
}

# --- Test 8: Dehydrate command files preloaded in output ---
test_dehydrate_command_files_preloaded() {
  # Create command files (new location after refactor)
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  echo "# CMD_DEHYDRATE content" > "$FAKE_HOME/.claude/.directives/commands/CMD_DEHYDRATE.md"
  echo "# CMD_RESUME_SESSION content" > "$FAKE_HOME/.claude/.directives/commands/CMD_RESUME_SESSION.md"
  echo "# CMD_PARSE_PARAMETERS content" > "$FAKE_HOME/.claude/.directives/commands/CMD_PARSE_PARAMETERS.md"

  local output
  output=$(run_hook "startup") || true

  assert_contains "CMD_DEHYDRATE content" "$output" "output contains CMD_DEHYDRATE.md content"
  assert_contains "CMD_RESUME_SESSION content" "$output" "output contains CMD_RESUME_SESSION.md content"
  assert_contains "CMD_PARSE_PARAMETERS content" "$output" "output contains CMD_PARSE_PARAMETERS.md content"
  assert_contains "[Preloaded:" "$output" "command files use [Preloaded:] format"
  assert_contains "CMD_DEHYDRATE.md]" "$output" "preloaded marker includes CMD_DEHYDRATE.md"
  assert_contains "CMD_RESUME_SESSION.md]" "$output" "preloaded marker includes CMD_RESUME_SESSION.md"
  assert_contains "CMD_PARSE_PARAMETERS.md]" "$output" "preloaded marker includes CMD_PARSE_PARAMETERS.md"
}

# --- Test 9: One dehydrate command file missing, other still preloaded ---
test_dehydrate_command_one_missing() {
  # Only create one of the two command files
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  echo "# CMD_DEHYDRATE only" > "$FAKE_HOME/.claude/.directives/commands/CMD_DEHYDRATE.md"
  # Do NOT create CMD_RESUME_SESSION.md

  local output
  output=$(run_hook "startup") || true

  assert_contains "CMD_DEHYDRATE only" "$output" "output contains CMD_DEHYDRATE.md when CMD_RESUME_SESSION missing"
  assert_not_contains "CMD_RESUME_SESSION" "$output" "output skips missing CMD_RESUME_SESSION.md file"

  # Standards should still be present
  assert_contains "COMMANDS content" "$output" "standards still present when command file missing"
}

echo "======================================"
echo "Session Start Restore Hook Tests"
echo "======================================"
echo ""

run_test test_standards_all_present
run_test test_standards_one_missing
run_test test_standards_all_missing
run_test test_non_startup_preloads_standards
run_test test_standards_preloaded_format
run_test test_standards_before_dehydrated
run_test test_preloaded_files_recorded
run_test test_dehydrate_command_files_preloaded
run_test test_dehydrate_command_one_missing

exit_with_results
