#!/bin/bash
# tests/test-threshold.sh — Tests for dehydration threshold (config.sh, overflow hook, statusline)
#
# Tests:
#   1. config.sh exports OVERFLOW_THRESHOLD=0.76
#   2-7. Overflow hook: whitelist, threshold comparison, deny normalization, dehydrate bypass, lifecycle bypass
#   8-11. Statusline: display normalization (raw → threshold-relative percentage)
#
# Run: bash ~/.claude/engine/scripts/tests/test-threshold.sh

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

# Scripts under test
CONFIG_SH="$HOME/.claude/engine/config.sh"
HOOK="$HOME/.claude/engine/hooks/pre-tool-use-overflow.sh"
STATUSLINE="$HOME/.claude/tools/statusline.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"

# Stub Claude: disable fleet (tmux) and debug mode, use PID-based session discovery
unset TMUX 2>/dev/null || true
unset DEBUG 2>/dev/null || true
export CLAUDE_SUPERVISOR_PID=$$

# Test session in project's sessions/ dir (session.sh find scans here)
TEST_SESSION="sessions/test_threshold_$$"

cleanup() { rm -rf "$TEST_SESSION"; }
trap cleanup EXIT

# --- Helpers ---

# Set .state.json fields (jq expression)
set_state() {
  jq "$1" "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

# Run overflow hook with given JSON stdin
run_hook() {
  echo "$1" | "$HOOK" 2>/dev/null
}

# Run statusline with given raw context percentage, extract display percentage
run_statusline() {
  local raw_pct="$1"
  local out
  out=$(echo "{\"context_window\":{\"used_percentage\":$raw_pct},\"session_id\":\"test-sid\",\"cost\":{\"total_cost_usd\":0}}" \
    | "$STATUSLINE" 2>/dev/null)
  echo "$out"
}

# Extract the display percentage from statusline output (last N% in the string)
extract_pct() {
  echo "$1" | grep -oE '[0-9]+%' | tail -1
}

# ============================================
echo "======================================"
echo "Dehydration Threshold Tests"
echo "======================================"
echo ""

# --- 1. config.sh ---
echo "--- 1. config.sh ---"
THRESHOLD=$(bash -c 'source '"$CONFIG_SH"' && echo $OVERFLOW_THRESHOLD')
assert_eq "0.76" "$THRESHOLD" "OVERFLOW_THRESHOLD is 0.76"
echo ""

# --- Setup test session ---
echo "--- Setup: activate test session ---"
"$SESSION_SH" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Verify session.sh find resolves to our test session
FOUND=$("$SESSION_SH" find 2>/dev/null || echo "NOT_FOUND")
if [[ "$FOUND" == *"test_threshold_$$"* ]]; then
  pass "session.sh find resolves to test session"
else
  fail "session.sh find → $FOUND (expected test_threshold_$$)" "test_threshold_$$" "$FOUND"
  echo "  Cannot test hook/statusline without session discovery. Aborting."
  exit_with_results
fi
echo ""

# --- 2. Overflow hook: whitelist (log.sh, session.sh) ---
echo "--- 2. Overflow hook: whitelists ---"

# These checks happen before find_session_dir, so they work regardless
OUT=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"~/.claude/scripts/log.sh foo/LOG.md"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "log.sh whitelisted"

OUT=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"~/.claude/scripts/session.sh phase foo"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "session.sh whitelisted"
echo ""

# --- 3. Overflow hook: allow below threshold ---
echo "--- 3. Overflow hook: allow below threshold ---"

set_state '.contextUsage = 0.50 | .lifecycle = "active" | .overflowed = false | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "50% → allow"

set_state '.contextUsage = 0.75 | .lifecycle = "active" | .overflowed = false | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "75% → allow (just below 76%)"
echo ""

# --- 4. Overflow hook: deny at/above threshold ---
echo "--- 4. Overflow hook: deny at/above threshold ---"

set_state '.contextUsage = 0.76 | .lifecycle = "active" | .overflowed = false | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains '"deny"' "$OUT" "76% → deny (at threshold)"
assert_contains 'Context overflow' "$OUT" "deny message says Context overflow"

set_state '.contextUsage = 0.80 | .lifecycle = "active" | .overflowed = false | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains '"deny"' "$OUT" "80% → deny (above threshold)"
echo ""

# --- 5. Overflow hook: deny message format ---
echo "--- 5. Overflow hook: deny message ---"

# Deny message should contain Context overflow (no percentage — removed for clarity)
set_state '.contextUsage = 0.76 | .lifecycle = "active" | .overflowed = false | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains 'Context overflow' "$OUT" "76% raw → deny with Context overflow message"
echo ""

# --- 6. Overflow hook: dehydrate skill bypass ---
echo "--- 6. Overflow hook: dehydrate bypass ---"

set_state '.contextUsage = 0.80 | .lifecycle = "active" | .overflowed = false | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"dehydrate"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "dehydrate skill allowed during overflow"
echo ""

# --- 7. Overflow hook: lifecycle bypass ---
echo "--- 7. Overflow hook: lifecycle bypass ---"

set_state '.contextUsage = 0.80 | .lifecycle = "dehydrating" | .killRequested = false'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "dehydrating lifecycle → allow all"

set_state '.contextUsage = 0.80 | .lifecycle = "active" | .killRequested = true'
OUT=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"x"}')
assert_contains '"allow"' "$OUT" "killRequested=true → allow all"
echo ""

# --- 8-11. Statusline: display normalization ---
echo "--- 8. Statusline: normalization ---"

# Reset state cleanly for statusline tests
set_state '.contextUsage = 0 | .lifecycle = "active" | .overflowed = false | .killRequested = false'

# 38% raw → 50% display (38/76*100 = 50)
OUT=$(run_statusline 38)
PCT=$(extract_pct "$OUT")
assert_eq "50%" "$PCT" "38% raw → 50% display (half of threshold)"

# Reset overflowed state between statusline runs
set_state '.lifecycle = "active" | .overflowed = false | .killRequested = false'

# 76% raw → 100% display (76/76*100 = 100)
OUT=$(run_statusline 76)
PCT=$(extract_pct "$OUT")
assert_eq "100%" "$PCT" "76% raw → 100% display (at threshold)"

set_state '.lifecycle = "active" | .overflowed = false | .killRequested = false'

# 85% raw → 100% display (capped)
OUT=$(run_statusline 85)
PCT=$(extract_pct "$OUT")
assert_eq "100%" "$PCT" "85% raw → 100% display (capped at 100)"

set_state '.lifecycle = "active" | .overflowed = false | .killRequested = false'

# 0% raw → 0% display
OUT=$(run_statusline 0)
PCT=$(extract_pct "$OUT")
assert_eq "0%" "$PCT" "0% raw → 0% display"
echo ""

exit_with_results
