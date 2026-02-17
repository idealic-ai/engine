#!/bin/bash
# test-workspace.sh — Workspace scoping integration tests
#
# Tests WORKSPACE env var behavior across:
#   - session.sh activate (stores workspace in .state.json)
#   - session.sh find (SEARCH_PATHS with workspace priority)
#   - find-sessions.sh (resolve_sessions_dir integration)
#   - Edge cases (trailing slash, spaces, nonexistent dir, dot)
#
# Run: bash ~/.claude/engine/scripts/tests/test-workspace.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

# Capture real paths before HOME override
SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
FIND_SESSIONS_SH="$HOME/.claude/engine/scripts/find-sessions.sh"

TMP_DIR=""

# Helper: valid activation JSON with all required fields
valid_activate_json() {
  local overrides="${1:-{\}}"
  jq -n --argjson overrides "$overrides" '{
    "taskType": "TESTING",
    "taskSummary": "test task",
    "scope": "Full",
    "directoriesOfInterest": [],
    "contextPaths": [],
    "requestFiles": [],
    "extraInfo": "",
    "phases": []
  } * $overrides'
}

# Helper: create .state.json in a directory
create_state() {
  local dir="$1"
  local json="$2"
  mkdir -p "$dir"
  echo "$json" > "$dir/.state.json"
}

setup() {
  TMP_DIR=$(mktemp -d)
  export ORIGINAL_HOME="${ORIGINAL_HOME:-$HOME}"

  FAKE_HOME="$TMP_DIR/fake-home"
  mkdir -p "$FAKE_HOME/.claude/scripts"
  mkdir -p "$FAKE_HOME/.claude/hooks"
  mkdir -p "$FAKE_HOME/.claude/tools/session-search"
  mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

  export HOME="$FAKE_HOME"

  # Copy session.sh (NOT symlink — see PITFALLS.md)
  cp "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
  chmod +x "$FAKE_HOME/.claude/scripts/session.sh"
  ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"

  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"
  disable_fleet_tmux

  export CLAUDE_SUPERVISOR_PID=99999999
  unset WORKSPACE 2>/dev/null || true

  cd "$TMP_DIR"
  mkdir -p "$TMP_DIR/sessions"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  unset WORKSPACE 2>/dev/null || true
  unset CLAUDE_SUPERVISOR_PID 2>/dev/null || true
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

# =============================================================================
# CATEGORY A: session.sh activate — WORKSPACE in .state.json
# =============================================================================

test_activate_stores_workspace() {
  local test_name="A1: activate stores WORKSPACE in .state.json"

  export WORKSPACE="apps/viewer/extraction"
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions"

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_WS" implement > /dev/null 2>&1

  assert_json "$TMP_DIR/sessions/TEST_WS/.state.json" '.workspace' \
    "apps/viewer/extraction" "$test_name"
}

test_activate_omits_workspace_when_unset() {
  local test_name="A2: activate omits workspace when WORKSPACE is unset"

  unset WORKSPACE 2>/dev/null || true

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_NOWS" implement > /dev/null 2>&1

  local sf="$TMP_DIR/sessions/TEST_NOWS/.state.json"
  local ws
  ws=$(jq -r '.workspace // "absent"' "$sf" 2>/dev/null)

  # workspace should be absent or null
  if [ "$ws" = "absent" ] || [ "$ws" = "null" ]; then
    pass "$test_name"
  else
    fail "$test_name" "absent or null" "$ws"
  fi
}

test_activate_stores_workspace_on_skill_change() {
  local test_name="A3: activate stores workspace on same-PID skill change"

  # First activation without WORKSPACE
  unset WORKSPACE 2>/dev/null || true
  export CLAUDE_SUPERVISOR_PID=$$

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_REACTIVATE" brainstorm > /dev/null 2>&1

  # Re-activate with WORKSPACE set and different skill
  export WORKSPACE="apps/viewer"
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions"

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_REACTIVATE" implement > /dev/null 2>&1

  assert_json "$TMP_DIR/sessions/TEST_REACTIVATE/.state.json" '.workspace' \
    "apps/viewer" "$test_name"
}

test_activate_stores_workspace_on_idle_reactivation() {
  local test_name="A4: activate stores workspace on idle re-activation"

  create_state "$TMP_DIR/sessions/TEST_IDLE" '{
    "pid": null,
    "skill": "brainstorm",
    "lifecycle": "idle",
    "loading": false,
    "overflowed": false,
    "killRequested": false
  }'

  export WORKSPACE="packages/estimate"
  export CLAUDE_SUPERVISOR_PID=$$
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions"

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_IDLE" implement > /dev/null 2>&1

  assert_json "$TMP_DIR/sessions/TEST_IDLE/.state.json" '.workspace' \
    "packages/estimate" "$test_name"
}

# =============================================================================
# CATEGORY B: session.sh find — SEARCH_PATHS with WORKSPACE
# =============================================================================

test_find_discovers_workspace_session() {
  local test_name="B1: find discovers session in workspace/sessions/"

  export WORKSPACE="apps/viewer"
  export CLAUDE_SUPERVISOR_PID=$$
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions/WS_SESSION"

  create_state "$TMP_DIR/$WORKSPACE/sessions/WS_SESSION" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"WS_SESSION"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + path contains WS_SESSION" "exit=$exit_code, output=$output"
  fi
}

test_find_prefers_workspace_over_global() {
  local test_name="B2: find prefers workspace session over global"

  export WORKSPACE="apps/viewer"
  export CLAUDE_SUPERVISOR_PID=$$

  # Active session in workspace
  create_state "$TMP_DIR/$WORKSPACE/sessions/WS_PREF" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  # Active session in global (same PID)
  create_state "$TMP_DIR/sessions/GLOBAL_PREF" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1)

  # Should find workspace session (searched first)
  assert_contains "$WORKSPACE/sessions/WS_PREF" "$output" "$test_name"
}

test_find_falls_back_to_global() {
  local test_name="B3: find falls back to global when workspace has no match"

  export WORKSPACE="apps/viewer"
  export CLAUDE_SUPERVISOR_PID=$$
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions"  # empty

  create_state "$TMP_DIR/sessions/GLOBAL_FALLBACK" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"GLOBAL_FALLBACK"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + GLOBAL_FALLBACK" "exit=$exit_code, output=$output"
  fi
}

test_find_only_global_when_no_workspace() {
  local test_name="B4: find uses only global sessions/ when WORKSPACE unset"

  unset WORKSPACE 2>/dev/null || true
  export CLAUDE_SUPERVISOR_PID=$$

  create_state "$TMP_DIR/sessions/GLOBAL_ONLY" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"GLOBAL_ONLY"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + GLOBAL_ONLY" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# CATEGORY C: find-sessions.sh — resolve_sessions_dir integration
# =============================================================================

test_find_sessions_lists_workspace_sessions() {
  local test_name="C1: find-sessions lists workspace sessions when WORKSPACE set"

  export WORKSPACE="apps/viewer"
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions/2026_02_14_WS_TEST"
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions/2026_02_13_WS_OTHER"

  local output
  output=$("$FIND_SESSIONS_SH" all 2>&1) || true

  if [[ "$output" == *"2026_02_14_WS_TEST"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "output contains 2026_02_14_WS_TEST" "output=$output"
  fi
}

test_find_sessions_uses_global_without_workspace() {
  local test_name="C2: find-sessions uses global sessions/ when WORKSPACE unset"

  unset WORKSPACE 2>/dev/null || true
  mkdir -p "$TMP_DIR/sessions/2026_02_14_GLOBAL_TEST"

  local output
  output=$("$FIND_SESSIONS_SH" all 2>&1) || true

  if [[ "$output" == *"2026_02_14_GLOBAL_TEST"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "output contains 2026_02_14_GLOBAL_TEST" "output=$output"
  fi
}

# =============================================================================
# CATEGORY D: session-start-restore.sh — WORKSPACE scanning
# (Deferred — hook has complex dependencies and output format)
# =============================================================================

# =============================================================================
# CATEGORY E: statusline.sh — workspace display
# (Deferred — requires Claude API context mocking)
# =============================================================================

# =============================================================================
# CATEGORY F: Edge Cases
# =============================================================================

test_trailing_slash_workspace() {
  local test_name="F1: trailing slash in WORKSPACE handled correctly"

  export WORKSPACE="apps/viewer/"
  mkdir -p "$TMP_DIR/apps/viewer/sessions"

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_TRAILING" implement > /dev/null 2>&1

  local sf="$TMP_DIR/sessions/TEST_TRAILING/.state.json"
  local ws
  ws=$(jq -r '.workspace' "$sf" 2>/dev/null)

  # Workspace should be stored (exit code may be non-zero for dead PID)
  if [ -n "$ws" ] && [ "$ws" != "null" ]; then
    pass "$test_name"
  else
    fail "$test_name" "workspace stored (non-empty)" "ws=$ws"
  fi
}

test_trailing_slash_find() {
  local test_name="F1b: find works with trailing slash WORKSPACE"

  export WORKSPACE="apps/viewer/"
  export CLAUDE_SUPERVISOR_PID=$$
  mkdir -p "$TMP_DIR/apps/viewer/sessions/TRAIL_FIND"

  create_state "$TMP_DIR/apps/viewer/sessions/TRAIL_FIND" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1) || true

  # find uses $PWD/${WORKSPACE}/sessions — trailing slash creates apps/viewer//sessions
  # which bash resolves to apps/viewer/sessions. Should still work.
  if [[ "$output" == *"TRAIL_FIND"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "found TRAIL_FIND" "output=$output"
  fi
}

test_workspace_with_spaces() {
  local test_name="F2: WORKSPACE with spaces in path"

  export WORKSPACE="apps/my viewer"
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions"

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_SPACES" implement > /dev/null 2>&1

  assert_json "$TMP_DIR/sessions/TEST_SPACES/.state.json" '.workspace' \
    "apps/my viewer" "$test_name"
}

test_workspace_spaces_find() {
  local test_name="F2b: find works with spaces in WORKSPACE path"

  export WORKSPACE="apps/my viewer"
  export CLAUDE_SUPERVISOR_PID=$$
  mkdir -p "$TMP_DIR/$WORKSPACE/sessions/SPACE_FIND"

  create_state "$TMP_DIR/$WORKSPACE/sessions/SPACE_FIND" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1) || true

  if [[ "$output" == *"SPACE_FIND"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "found SPACE_FIND" "output=$output"
  fi
}

test_nonexistent_workspace_activate() {
  local test_name="F3: activate works when WORKSPACE dir doesn't exist"

  export WORKSPACE="nonexistent/path"
  # Do NOT create the workspace dir

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_NOEXIST" implement > /dev/null 2>&1

  assert_json "$TMP_DIR/sessions/TEST_NOEXIST/.state.json" '.workspace' \
    "nonexistent/path" "$test_name"
}

test_nonexistent_workspace_find_fallback() {
  local test_name="F3b: find falls back to global when WORKSPACE dir doesn't exist"

  export WORKSPACE="nonexistent/path"
  export CLAUDE_SUPERVISOR_PID=$$
  # No workspace dir — find should fall back to global

  create_state "$TMP_DIR/sessions/GLOBAL_NOEXIST" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"GLOBAL_NOEXIST"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + GLOBAL_NOEXIST" "exit=$exit_code, output=$output"
  fi
}

test_dot_workspace() {
  local test_name="F4: dot WORKSPACE doesn't crash"

  export WORKSPACE="."

  valid_activate_json | \
    "$SESSION_SH" activate "$TMP_DIR/sessions/TEST_DOT" implement > /dev/null 2>&1

  assert_json "$TMP_DIR/sessions/TEST_DOT/.state.json" '.workspace' \
    "." "$test_name"
}

test_dot_workspace_find() {
  local test_name="F4b: find with dot WORKSPACE resolves to ./sessions/"

  export WORKSPACE="."
  export CLAUDE_SUPERVISOR_PID=$$
  # ./sessions/ in TMP_DIR is the same as sessions/ — already created in setup

  create_state "$TMP_DIR/sessions/DOT_FIND" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "implement", lifecycle: "active"
  }')"

  local output
  output=$("$SESSION_SH" find 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"DOT_FIND"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + DOT_FIND" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== Category A: session.sh activate — WORKSPACE in .state.json ==="
run_test test_activate_stores_workspace
run_test test_activate_omits_workspace_when_unset
run_test test_activate_stores_workspace_on_skill_change
run_test test_activate_stores_workspace_on_idle_reactivation

echo ""
echo "=== Category B: session.sh find — SEARCH_PATHS with WORKSPACE ==="
run_test test_find_discovers_workspace_session
run_test test_find_prefers_workspace_over_global
run_test test_find_falls_back_to_global
run_test test_find_only_global_when_no_workspace

echo ""
echo "=== Category C: find-sessions.sh — resolve_sessions_dir ==="
run_test test_find_sessions_lists_workspace_sessions
run_test test_find_sessions_uses_global_without_workspace

echo ""
echo "=== Category F: Edge Cases ==="
run_test test_trailing_slash_workspace
run_test test_trailing_slash_find
run_test test_workspace_with_spaces
run_test test_workspace_spaces_find
run_test test_nonexistent_workspace_activate
run_test test_nonexistent_workspace_find_fallback
run_test test_dot_workspace
run_test test_dot_workspace_find

exit_with_results
