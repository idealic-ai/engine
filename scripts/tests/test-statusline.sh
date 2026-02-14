#!/bin/bash
# tests/test-statusline.sh — Tests for statusline.sh
#
# Tests:
#   B1.  Updates contextUsage in .state.json
#   B2.  Updates lastHeartbeat timestamp
#   B3.  Binds sessionId in normal state
#   B4.  Does NOT bind sessionId when killRequested=true
#   B5.  Does NOT bind sessionId when overflowed=true
#   B6.  Does NOT bind sessionId when lifecycle=dehydrating
#   B7.  Still updates contextUsage when killRequested
#   B8.  Claims PID when .state.json PID doesn't match
#   B9.  Shows 'No session' when no session found
#   B10. Shows session name with skill/phase
#   B11. Normalizes percentage (threshold=100% display)
#   B12. Shows cost in output
#   B13. Shows agent name when present
#
# Uses HOME override for full isolation (same pattern as test-heartbeat.sh).
#
# Run: bash ~/.claude/engine/scripts/tests/test-statusline.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

unset DISABLE_AUTO_COMPACT 2>/dev/null || true

STATUSLINE="$HOME/.claude/engine/tools/statusline.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"

TMP_DIR=$(mktemp -d)

# Disable fleet/tmux
unset TMUX 2>/dev/null || true
unset TMUX_PANE 2>/dev/null || true

# Create fake HOME to isolate session.sh find from real sessions
FAKE_HOME="$TMP_DIR/fake-home"
mkdir -p "$FAKE_HOME/.claude/scripts"
mkdir -p "$FAKE_HOME/.claude/engine/tools"
mkdir -p "$FAKE_HOME/.claude/engine"
mkdir -p "$FAKE_HOME/.claude/tools/session-search"
mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

# Symlink real scripts into fake home
ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$STATUSLINE" "$FAKE_HOME/.claude/engine/tools/statusline.sh"
ln -sf "$CONFIG_SH" "$FAKE_HOME/.claude/engine/config.sh"

# Stub fleet.sh (no fleet)
cat > "$FAKE_HOME/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  pane-id) echo ""; exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
chmod +x "$FAKE_HOME/.claude/scripts/fleet.sh"

# Stub search tools
for tool in session-search doc-search; do
  cat > "$FAKE_HOME/.claude/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
  chmod +x "$FAKE_HOME/.claude/tools/$tool/$tool.sh"
done

# Save original HOME and switch
ORIGINAL_HOME="$HOME"
export HOME="$FAKE_HOME"

# Work in TMP_DIR so session.sh find scans our test sessions
cd "$TMP_DIR"

# Test session — absolute path
TEST_SESSION="$TMP_DIR/sessions/2026_02_08_TEST_STATUS"
mkdir -p "$TEST_SESSION"

# Resolved statusline path
RESOLVED_STATUSLINE="$FAKE_HOME/.claude/engine/tools/statusline.sh"

cleanup() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run statusline with given stdin JSON
run_statusline() {
  local input="$1"
  echo "$input" | "$RESOLVED_STATUSLINE" 2>/dev/null
}

# Build realistic stdin JSON
# Usage: make_input [used_percentage] [session_id] [agent_name] [total_cost]
make_input() {
  local pct="${1:-0}"
  local sid="${2:-test-session-id}"
  local agent="${3:-}"
  local cost="${4:-0}"
  local agent_json="null"
  if [ -n "$agent" ]; then
    agent_json="{\"name\":\"$agent\"}"
  fi
  printf '{"context_window":{"used_percentage":%s},"session_id":"%s","agent":%s,"cost":{"total_cost_usd":%s}}' \
    "$pct" "$sid" "$agent_json" "$cost"
}

# Reset .state.json to clean active state
reset_state() {
  jq '.lifecycle = "active" | .killRequested = false | del(.overflowed) | .contextUsage = 0 | del(.sessionId)' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

echo "======================================"
echo "Statusline Tests"
echo "======================================"
echo ""

# --- Setup: activate test session ---
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Verify session.sh find resolves correctly
FOUND=$("$FAKE_HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "NOT_FOUND")
if [[ "$FOUND" == *"TEST_STATUS"* ]]; then
  pass "session.sh find resolves to test session"
else
  fail "session.sh find → $FOUND (expected TEST_STATUS)" "TEST_STATUS" "$FOUND"
  echo "  Cannot test statusline without session discovery. Aborting."
  exit 1
fi

# Clear loading flag
jq 'del(.loading)' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

echo ""

# =============================================================================
# STATE UPDATES (.state.json mutations)
# =============================================================================

# --- B1. Updates contextUsage ---
echo "--- B1. contextUsage update ---"
reset_state

run_statusline "$(make_input 42)" > /dev/null
USAGE=$(jq -r '.contextUsage' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "0.4200" "$USAGE" "contextUsage updated to 0.4200 (4 decimal places)"

echo ""

# --- B2. Updates lastHeartbeat ---
echo "--- B2. lastHeartbeat update ---"
reset_state

run_statusline "$(make_input 10)" > /dev/null
HEARTBEAT=$(jq -r '.lastHeartbeat // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
# Verify ISO format: YYYY-MM-DDTHH:MM:SSZ
if [[ "$HEARTBEAT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  pass "lastHeartbeat in ISO format ($HEARTBEAT)"
else
  fail "lastHeartbeat should be ISO format" "ISO format" "$HEARTBEAT"
fi

echo ""

# --- B3. Binds sessionId in normal state ---
echo "--- B3. sessionId binding (normal) ---"
reset_state

run_statusline "$(make_input 10 'test-sid-123')" > /dev/null
SID=$(jq -r '.sessionId // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "test-sid-123" "$SID" "sessionId bound to test-sid-123"

echo ""

# --- B4. Does NOT bind sessionId when killRequested ---
echo "--- B4. sessionId skipped (killRequested) ---"
reset_state
# Set a known sessionId, then trigger killRequested
jq '.sessionId = "old-sid" | .killRequested = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_statusline "$(make_input 10 'new-sid-456')" > /dev/null
SID=$(jq -r '.sessionId // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "old-sid" "$SID" "sessionId NOT updated when killRequested (still old-sid)"

echo ""

# --- B5. Does NOT bind sessionId when overflowed ---
echo "--- B5. sessionId skipped (overflowed) ---"
reset_state
jq '.sessionId = "old-sid" | .overflowed = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_statusline "$(make_input 10 'new-sid-789')" > /dev/null
SID=$(jq -r '.sessionId // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "old-sid" "$SID" "sessionId NOT updated when overflowed (still old-sid)"

echo ""

# --- B6. Does NOT bind sessionId when lifecycle=dehydrating ---
echo "--- B6. sessionId skipped (dehydrating) ---"
reset_state
jq '.sessionId = "old-sid" | .lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_statusline "$(make_input 10 'new-sid-abc')" > /dev/null
SID=$(jq -r '.sessionId // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "old-sid" "$SID" "sessionId NOT updated when dehydrating (still old-sid)"

echo ""

# --- B7. contextUsage still updated when killRequested ---
echo "--- B7. contextUsage updated during kill ---"
reset_state
jq '.killRequested = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_statusline "$(make_input 85)" > /dev/null
USAGE=$(jq -r '.contextUsage' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "0.8500" "$USAGE" "contextUsage updated despite killRequested"

echo ""

# --- B8. PID preserved when matching ---
echo "--- B8. PID preserved ---"
reset_state
# Verify current PID matches (session was activated with $$)
# PID claiming (changing PID) requires fleet pane — can't test without tmux
# Instead verify PID stays correct after statusline run

FILE_PID_BEFORE=$(jq -r '.pid' "$TEST_SESSION/.state.json" 2>/dev/null)
run_statusline "$(make_input 10)" > /dev/null
FILE_PID_AFTER=$(jq -r '.pid' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "$FILE_PID_BEFORE" "$FILE_PID_AFTER" "PID preserved when matching ($$)"

echo ""

# =============================================================================
# DISPLAY OUTPUT
# =============================================================================

# --- B9. No session → "No session" in red ---
echo "--- B9. No session display ---"
# Use a dead PID so session.sh find fails
export CLAUDE_SUPERVISOR_PID=99999999

OUT=$(run_statusline "$(make_input 10)")
assert_contains "No session" "$OUT" "Shows 'No session' when no session found"

# Restore PID and re-activate session for remaining tests
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1
jq 'del(.loading)' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

echo ""

# --- B10. Session name with skill/phase ---
echo "--- B10. Session name + skill/phase ---"
reset_state
# Set a phase in .state.json
jq '.currentPhase = "3: Strategy"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_statusline "$(make_input 10)")
assert_contains "3. Strategy" "$OUT" "Shows phase in N. Name format (no phases array)"
# Session name should have date stripped: 2026_02_08_TEST_STATUS → TEST_STATUS
assert_contains "TEST_STATUS" "$OUT" "Session name has date prefix stripped"

echo ""

# --- B11. Normalized percentage ---
echo "--- B11. Normalized percentage ---"
reset_state

# 38% raw, threshold=0.76 → 38/(76)*100 = 50%
OUT=$(run_statusline "$(make_input 38)")
assert_contains "50%" "$OUT" "38% raw → 50% normalized (threshold=76%)"

echo ""

# --- B12. Cost in output ---
echo "--- B12. Cost display ---"
reset_state

OUT=$(run_statusline "$(make_input 10 'sid' '' 1.5)")
assert_contains '$1.50' "$OUT" "Cost shows as \$1.50"

echo ""

# --- B13. Agent name in output ---
echo "--- B13. Agent name ---"
reset_state

OUT=$(run_statusline "$(make_input 10 'sid' 'builder' 0)")
assert_contains "builder" "$OUT" "Agent name 'builder' shown in output"

echo ""

exit_with_results
