#!/bin/bash
# tests/test-state-injector.sh — Tests for user-prompt-state-injector.sh hook
#
# Tests:
#   1. No injection when SESSION_REQUIRED != 1
#   2. No injection when no active session
#   3. No injection when session is completed
#   4. Injects state when session is active (all fields present)
#   5. Handles missing .state.json fields gracefully (defaults)
#   6. Output is valid JSON
#   7. Contains time field (current date YYYY-MM-DD)
#
# Uses HOME override for full isolation (same pattern as test-prompt-gate.sh).
#
# Run: bash ~/.claude/engine/scripts/tests/test-state-injector.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/hooks/user-prompt-state-injector.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

TMP_DIR=$(mktemp -d)

# Use a dead PID for isolation
export CLAUDE_SUPERVISOR_PID=99999999
unset SESSION_REQUIRED 2>/dev/null || true

# Create fake HOME to isolate session.sh find from real sessions
setup_fake_home "$TMP_DIR"
disable_fleet_tmux

# Symlink real scripts into fake home
ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$HOOK" "$FAKE_HOME/.claude/hooks/user-prompt-state-injector.sh"

# Stub fleet.sh and search tools
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

# Work in TMP_DIR so session.sh find scans our test sessions
cd "$TMP_DIR"

# Test session — absolute path
TEST_SESSION="$TMP_DIR/sessions/test_state_injector"
mkdir -p "$TEST_SESSION"

# Resolved hook path
RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/user-prompt-state-injector.sh"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run the hook with optional SESSION_REQUIRED override
run_hook() {
  local session_required="${1:-1}"
  (
    export SESSION_REQUIRED="$session_required"
    echo '{"session_id":"test","transcript_path":"/tmp/test.jsonl"}' \
      | "$RESOLVED_HOOK" 2>/dev/null
  )
}

echo "======================================"
echo "State Injector Hook Tests"
echo "======================================"
echo ""

# --- 1. No injection when SESSION_REQUIRED != 1 ---
echo "--- 1. Gate disabled (SESSION_REQUIRED != 1) ---"

OUT=$(run_hook "")
assert_empty "$OUT" "SESSION_REQUIRED empty -> no output"

OUT=$(run_hook "0")
assert_empty "$OUT" "SESSION_REQUIRED=0 -> no output"

echo ""

# --- 2. No injection when no active session ---
echo "--- 2. No active session -> no output ---"

# No .state.json exists yet, CLAUDE_SUPERVISOR_PID is a dead PID
OUT=$(run_hook "1")
assert_empty "$OUT" "No active session -> no output"

echo ""

# --- 3. No injection when session is completed ---
echo "--- 3. Completed session -> no output ---"

# Create and activate a session, then set it to completed
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Set lifecycle to completed
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_empty "$OUT" "Completed session -> no output"

echo ""

# --- 4. Injects state when session is active ---
echo "--- 4. Active session with all fields -> injects state ---"

# Set up a fully populated .state.json
jq '.lifecycle = "active" | .skill = "implement" | .currentPhase = "4: Build Loop" | .toolCallsSinceLastLog = 3 | .toolUseWithoutLogsBlockAfter = 10 | del(.loading)' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_not_empty "$OUT" "Active session -> produces output"
assert_contains "hookSpecificOutput" "$OUT" "Output contains hookSpecificOutput"
assert_contains "Session Context" "$OUT" "Output contains Session Context header"
assert_contains "implement" "$OUT" "Output contains skill name"
assert_contains "4: Build Loop" "$OUT" "Output contains phase"
assert_contains "3/10" "$OUT" "Output contains heartbeat counter 3/10"
assert_contains "test_state_injector" "$OUT" "Output contains session basename"

echo ""

# --- 5. Handles missing fields gracefully ---
echo "--- 5. Missing fields -> defaults ---"

# Create minimal .state.json with only lifecycle=active and pid
jq -n --argjson pid $$ '{"pid": $pid, "lifecycle": "active"}' \
  > "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_not_empty "$OUT" "Minimal .state.json -> still produces output"
assert_contains "Session Context" "$OUT" "Output still has Session Context header"
assert_contains "0/10" "$OUT" "Heartbeat defaults to 0/10"
assert_not_contains "Skill:" "$OUT" "No Skill field when skill is empty"

echo ""

# --- 6. Output is valid JSON ---
echo "--- 6. Output is valid JSON ---"

# Restore full state for JSON validation
jq -n --argjson pid $$ '{"pid": $pid, "lifecycle": "active", "skill": "test", "currentPhase": "1: Setup", "toolCallsSinceLastLog": 0, "toolUseWithoutLogsBlockAfter": 10}' \
  > "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
if echo "$OUT" | jq empty 2>/dev/null; then
  pass "Output is valid JSON"
else
  fail "Output is valid JSON" "valid JSON" "$OUT"
fi

# Verify JSON structure has the expected key path
MSG=$(echo "$OUT" | jq -r '.hookSpecificOutput.message' 2>/dev/null || echo "ERROR")
if [ "$MSG" != "ERROR" ] && [ "$MSG" != "null" ]; then
  pass "JSON has hookSpecificOutput.message field"
else
  fail "JSON has hookSpecificOutput.message field" "non-null message" "$MSG"
fi

echo ""

# --- 7. Contains time field ---
echo "--- 7. Contains current date ---"

TODAY=$(date '+%Y-%m-%d')
OUT=$(run_hook "1")
assert_contains "$TODAY" "$OUT" "Output contains today's date ($TODAY)"

echo ""

exit_with_results
