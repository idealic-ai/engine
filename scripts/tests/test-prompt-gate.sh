#!/bin/bash
# tests/test-prompt-gate.sh — Tests for user-prompt-submit-session-gate.sh hook
#
# Tests:
#   1. Gate disabled (SESSION_REQUIRED != 1) -> no output
#   2. Active session -> no output (passthrough)
#   3. Dehydrating session -> no output (passthrough)
#   4. Completed session -> injects continuation message
#   5. No session -> injects boot sequence message
#
# Uses HOME override for full isolation (same pattern as test-heartbeat.sh).
#
# Run: bash ~/.claude/engine/scripts/tests/test-prompt-gate.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/hooks/user-prompt-submit-session-gate.sh"
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
ln -sf "$HOOK" "$FAKE_HOME/.claude/hooks/user-prompt-submit-session-gate.sh"

# Stub fleet.sh and search tools
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

# Work in TMP_DIR so session.sh find scans our test sessions
cd "$TMP_DIR"

# Test session -- absolute path
TEST_SESSION="$TMP_DIR/sessions/test_prompt_gate"
mkdir -p "$TEST_SESSION"

# Resolved hook path
RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/user-prompt-submit-session-gate.sh"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run the hook with optional SESSION_REQUIRED override
run_hook() {
  local session_required="${1-1}"
  (
    export SESSION_REQUIRED="$session_required"
    echo '{"session_id":"test","transcript_path":"/tmp/test.jsonl"}' \
      | "$RESOLVED_HOOK" 2>/dev/null
  )
}

echo "======================================"
echo "Prompt Gate Hook Tests"
echo "======================================"
echo ""

# --- 1. Gate disabled ---
echo "--- 1. Gate disabled (SESSION_REQUIRED != 1) ---"

OUT=$(run_hook "")
assert_empty "$OUT" "SESSION_REQUIRED empty -> no output"

OUT=$(run_hook "0")
assert_empty "$OUT" "SESSION_REQUIRED=0 -> no output"

echo ""

# --- 2. Active session -> passthrough ---
echo "--- 2. Active session -> passthrough ---"

export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Clear loading flag
jq 'del(.loading)' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_empty "$OUT" "Active session -> no output (passthrough)"

echo ""

# --- 3. Dehydrating session -> passthrough ---
echo "--- 3. Dehydrating session -> passthrough ---"

jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_empty "$OUT" "Dehydrating session -> no output (passthrough)"

echo ""

# --- 4. Completed session -> injects message ---
echo "--- 4. Completed session -> inject continuation ---"

jq '.lifecycle = "completed" | .skill = "implement"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_not_empty "$OUT" "Completed session -> produces output"
assert_contains '§CMD_REQUIRE_ACTIVE_SESSION' "$OUT" "Message contains CMD_REQUIRE_ACTIVE_SESSION"
assert_contains 'completed' "$OUT" "Message mentions completed"
assert_contains 'implement' "$OUT" "Message mentions the skill"
assert_contains 'hookSpecificOutput' "$OUT" "Output is valid hook response"
assert_contains 'Boot sequence' "$OUT" "Message includes boot sequence"

echo ""

# --- 5. No session -> injects boot message ---
echo "--- 5. No session -> inject boot sequence ---"

rm -f "$TEST_SESSION/.state.json"
export CLAUDE_SUPERVISOR_PID=99999999

OUT=$(run_hook "1")
assert_not_empty "$OUT" "No session -> produces output"
assert_contains '§CMD_REQUIRE_ACTIVE_SESSION' "$OUT" "Message contains CMD_REQUIRE_ACTIVE_SESSION"
assert_contains 'No active session' "$OUT" "Message says no active session"
assert_contains 'Boot sequence' "$OUT" "Message includes boot sequence"
assert_contains 'hookSpecificOutput' "$OUT" "Output is valid hook response"
assert_contains 'AskUserQuestion' "$OUT" "Message instructs to use AskUserQuestion"

exit_with_results
