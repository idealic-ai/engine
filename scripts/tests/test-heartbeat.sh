#!/bin/bash
# tests/test-heartbeat.sh — Tests for pre-tool-use-heartbeat.sh hook
#
# Tests:
#   1. Loading mode bypass (loading=true → allow, no counting)
#   2. Bash whitelist: log.sh allowed + resets counter
#   3. Bash whitelist: session.sh allowed (no counter reset)
#   4. Read whitelist: ~/.claude/* paths allowed without counting
#   5. Task whitelist: sub-agent launch allowed without counting
#   6. Counter increment on normal tool call
#   7. Warn threshold reached → allow with reminder
#   8. Block threshold reached → deny
#   9. Same-file Edit suppression (consecutive edits to same file don't increment)
#  10. Different-file Edit increments counter normally
#  11. No session → allow (no enforcement)
#
# Uses HOME override for full isolation (same pattern as test-session-sh.sh).
# This ensures session.sh find resolves to our test session, not the real one.
#
# Run: bash ~/.claude/engine/scripts/tests/test-heartbeat.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/hooks/pre-tool-use-heartbeat.sh"
SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

TMP_DIR=$(mktemp -d)

# Use a dead PID for isolation (won't conflict with real sessions)
export CLAUDE_SUPERVISOR_PID=99999999

# Create fake HOME to isolate session.sh find from real sessions
setup_fake_home "$TMP_DIR"
disable_fleet_tmux

# Symlink real scripts into fake home
ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$ORIGINAL_HOME/.claude/hooks/pre-tool-use-heartbeat.sh" "$FAKE_HOME/.claude/hooks/pre-tool-use-heartbeat.sh"

# Stub fleet.sh and search tools
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

# Work in TMP_DIR so session.sh find scans our test sessions
cd "$TMP_DIR"

# Test session — use absolute path so reads/writes go to same file
TEST_SESSION="$TMP_DIR/sessions/test_heartbeat"
mkdir -p "$TEST_SESSION"

# Transcript key simulates per-agent counter isolation
TRANSCRIPT="test-transcript-$$.jsonl"

# Resolved hook path (use original home since symlinked)
RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/pre-tool-use-heartbeat.sh"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run hook with given tool_name and optional tool_input
# tool_input must be valid JSON (use single-quoted strings with real double quotes)
run_hook() {
  local tool_name="$1"
  local tool_input="${2:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s,"session_id":"test","transcript_path":"/tmp/%s"}\n' \
    "$tool_name" "$tool_input" "$TRANSCRIPT" \
    | "$RESOLVED_HOOK" 2>/dev/null
}


# Get counter value for our transcript from the absolute path
get_counter() {
  jq -r --arg key "$TRANSCRIPT" '(.toolCallsByTranscript // {})[$key] // 0' "$TEST_SESSION/.state.json" 2>/dev/null || echo "0"
}

# Set counter to specific value
set_counter() {
  local val="$1"
  jq --arg key "$TRANSCRIPT" --argjson tc "$val" \
    '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = $tc' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

echo "======================================"
echo "Heartbeat Hook Tests"
echo "======================================"
echo ""

# --- Setup: activate test session ---
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Verify session.sh find resolves correctly
FOUND=$("$FAKE_HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "NOT_FOUND")
if [[ "$FOUND" == *"test_heartbeat"* ]]; then
  pass "session.sh find resolves to test session"
else
  fail "session.sh find → $FOUND (expected test_heartbeat)"
  echo "  Cannot test heartbeat without session discovery. Aborting."
  exit 1
fi

# Clear loading flag and set logTemplate so heartbeat enforcement runs
# (without logTemplate, hook exits early at line 130 with allow — no counting)
jq 'del(.loading) | .logTemplate = "TESTING_LOG.md"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

echo ""

# --- 1. Loading mode bypass ---
echo "--- 1. Loading mode bypass ---"

jq '.loading = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x"}')
assert_contains '"allow"' "$OUT" "loading=true → allow (bypass)"

COUNTER=$(get_counter)
assert_eq "0" "$COUNTER" "loading mode doesn't increment counter"

# Clear loading flag
jq 'del(.loading)' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

echo ""

# --- 2. Bash: direct log.sh path NOT whitelisted (only engine CLI is) ---
echo "--- 2. Bash: direct log.sh ---"

set_counter 5
OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/log.sh '"$TEST_SESSION"'/TESTING_LOG.md"}')
# Direct script path goes through main logic — counter increments, not resets
COUNTER=$(get_counter)
assert_eq "6" "$COUNTER" "direct log.sh increments counter (not whitelisted)"

echo ""

# --- 2b. Bash whitelist: engine log resets counter ---
echo "--- 2b. Bash whitelist: engine log ---"

set_counter 5
OUT=$(run_hook "Bash" '{"command":"engine log sessions/test/TESTING_LOG.md"}')
assert_contains '"allow"' "$OUT" "engine log allowed"

COUNTER=$(get_counter)
assert_eq "0" "$COUNTER" "engine log resets counter to 0"

# Edge case: engine log with heredoc content
set_counter 7
OUT=$(run_hook "Bash" '{"command":"engine log sessions/foo/LOG.md <<EOF\n## Entry\nEOF"}')
assert_contains '"allow"' "$OUT" "engine log with heredoc allowed"
COUNTER=$(get_counter)
assert_eq "0" "$COUNTER" "engine log with heredoc resets counter"

echo ""

# --- 3. Bash: direct session.sh path NOT whitelisted (only engine CLI is) ---
echo "--- 3. Bash: direct session.sh ---"

set_counter 5
OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/session.sh phase foo"}')
# Direct script path goes through main logic — counter increments
COUNTER=$(get_counter)
assert_eq "6" "$COUNTER" "direct session.sh increments counter (not whitelisted)"

# --- 3b. Bash whitelist: engine session (no reset) ---
echo "--- 3b. Bash whitelist: engine session ---"

set_counter 5
OUT=$(run_hook "Bash" '{"command":"engine session phase sessions/foo \"4: Fix Loop\""}')
assert_contains '"allow"' "$OUT" "engine session allowed"

COUNTER=$(get_counter)
assert_eq "5" "$COUNTER" "engine session doesn't reset counter"

# Adversarial: engine without whitelisted subcommand
set_counter 3
OUT=$(run_hook "Bash" '{"command":"engine setup"}')
# Non-whitelisted engine commands should increment counter like any other Bash call
COUNTER=$(get_counter)
assert_eq "4" "$COUNTER" "engine setup increments counter (not whitelisted)"

echo ""

# --- 4. Read whitelist: ~/.claude/* ---
echo "--- 4. Read whitelist ---"

set_counter 3
OUT=$(run_hook "Read" '{"file_path":"'"$FAKE_HOME"'/.claude/.directives/COMMANDS.md"}')
assert_contains '"allow"' "$OUT" "Read ~/.claude/* allowed"

COUNTER=$(get_counter)
assert_eq "3" "$COUNTER" "Read ~/.claude/* doesn't increment"

echo ""

# --- 5. Task whitelist ---
echo "--- 5. Task whitelist ---"

set_counter 3
OUT=$(run_hook "Task" '{"prompt":"do something"}')
assert_contains '"allow"' "$OUT" "Task allowed without counting"

COUNTER=$(get_counter)
assert_eq "3" "$COUNTER" "Task doesn't increment"

echo ""

# --- 6. Counter increment on normal tool ---
echo "--- 6. Counter increment ---"

set_counter 0
OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "Normal tool allowed (under threshold)"

COUNTER=$(get_counter)
assert_eq "1" "$COUNTER" "Counter incremented to 1"

# Second call
OUT=$(run_hook "Glob" '{"pattern":"*.md"}')
COUNTER=$(get_counter)
assert_eq "2" "$COUNTER" "Counter incremented to 2"

echo ""

# --- 7. Warn threshold ---
echo "--- 7. Warn threshold ---"

# Default warn threshold is 3
set_counter 2
OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "At warn threshold → still allowed"
assert_contains '§CMD_LOG_BETWEEN_TOOL_USES' "$OUT" "Warn message present"

echo ""

# --- 8. Block threshold ---
echo "--- 8. Block threshold ---"

# Default block threshold is 10
set_counter 9
OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"deny"' "$OUT" "At block threshold → denied"
assert_contains '§CMD_LOG_BETWEEN_TOOL_USES' "$OUT" "Block message present"

echo ""

# --- 9. Same-file Edit suppression ---
echo "--- 9. Same-file Edit suppression ---"

set_counter 0
# First edit to file A
OUT=$(run_hook "Edit" '{"file_path":"/tmp/fileA.ts"}')
COUNTER=$(get_counter)
assert_eq "1" "$COUNTER" "First edit increments counter"

# Second edit to same file A — should NOT increment
OUT=$(run_hook "Edit" '{"file_path":"/tmp/fileA.ts"}')
assert_contains '"allow"' "$OUT" "Same-file edit allowed"
COUNTER=$(get_counter)
assert_eq "1" "$COUNTER" "Same-file edit doesn't increment"

echo ""

# --- 10. Different-file Edit increments ---
echo "--- 10. Different-file Edit ---"

# Edit to file B (different from A) — should increment
OUT=$(run_hook "Edit" '{"file_path":"/tmp/fileB.ts"}')
COUNTER=$(get_counter)
assert_eq "2" "$COUNTER" "Different-file edit increments counter"

echo ""

# --- 11. No session → allow ---
echo "--- 11. No session ---"

# Remove test session state file
rm -f "$TEST_SESSION/.state.json"

OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "No session → allow (no enforcement)"

exit_with_results
