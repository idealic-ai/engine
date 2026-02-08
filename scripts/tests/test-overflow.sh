#!/bin/bash
# tests/test-overflow.sh — Tests for pre-tool-use-overflow.sh hook
#
# Tests:
#   A1.  Bash whitelist: log.sh allowed even during overflow
#   A2.  Bash whitelist: session.sh allowed even during overflow
#   A3.  Skill(dehydrate) allowed and sets lifecycle=dehydrating
#   A4.  All tools allowed when lifecycle=dehydrating
#   A5.  All tools allowed when killRequested=true
#   A6.  Allow tools when contextUsage below threshold (0.75)
#   A7.  Deny tools when contextUsage above threshold (0.77)
#   A8.  Sets overflowed=true sticky flag on deny
#   A9.  Overflowed flag persists after subsequent below-threshold call
#   A10. Deny non-Bash tools (Read) during overflow
#   A11. Deny non-whitelisted Bash commands during overflow
#   A12. Allow when no session directory found
#   A13. Allow when .state.json is missing
#
# Uses HOME override for full isolation (same pattern as test-heartbeat.sh).
#
# Run: bash ~/.claude/engine/scripts/tests/test-overflow.sh

set -uo pipefail

HOOK="$HOME/.claude/hooks/pre-tool-use-overflow.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"

TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Disable fleet/tmux
unset TMUX 2>/dev/null || true
unset TMUX_PANE 2>/dev/null || true

# Use a dead PID for isolation
export CLAUDE_SUPERVISOR_PID=99999999

# Create fake HOME to isolate session.sh find from real sessions
FAKE_HOME="$TMP_DIR/fake-home"
mkdir -p "$FAKE_HOME/.claude/scripts"
mkdir -p "$FAKE_HOME/.claude/hooks"
mkdir -p "$FAKE_HOME/.claude/engine"
mkdir -p "$FAKE_HOME/.claude/tools/session-search"
mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

# Symlink real scripts into fake home
ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$HOOK" "$FAKE_HOME/.claude/hooks/pre-tool-use-overflow.sh"
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
TEST_SESSION="$TMP_DIR/sessions/test_overflow"
mkdir -p "$TEST_SESSION"

# Resolved hook path
RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/pre-tool-use-overflow.sh"

cleanup() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_contains() {
  local expected="$1" actual="$2" msg="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo -e "${GREEN}PASS${NC}: $msg"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $msg"
    echo "  Expected to contain: $expected"
    echo "  Actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $msg"
    echo "  Expected: $expected"
    echo "  Actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Run hook with given tool_name and optional tool_input
run_hook() {
  local tool_name="$1"
  local tool_input="${2:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s,"session_id":"test","transcript_path":"/tmp/test.jsonl"}\n' \
    "$tool_name" "$tool_input" \
    | "$RESOLVED_HOOK" 2>/dev/null
}

# Set contextUsage in .state.json
set_context_usage() {
  local val="$1"
  jq --argjson usage "$val" '.contextUsage = $usage' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

# Reset .state.json to clean active state
reset_state() {
  jq '.lifecycle = "active" | .killRequested = false | del(.overflowed) | .contextUsage = 0' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

echo "======================================"
echo "Overflow Hook Tests"
echo "======================================"
echo ""

# --- Setup: activate test session ---
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Verify session.sh find resolves correctly
FOUND=$("$FAKE_HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "NOT_FOUND")
if [[ "$FOUND" == *"test_overflow"* ]]; then
  echo -e "${GREEN}PASS${NC}: session.sh find resolves to test session"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}: session.sh find → $FOUND (expected test_overflow)"
  FAIL=$((FAIL + 1))
  echo "  Cannot test overflow without session discovery. Aborting."
  exit 1
fi

# Clear loading flag
jq 'del(.loading)' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

echo ""

# =============================================================================
# WHITELIST / BYPASS LOGIC
# =============================================================================

# --- A1. Bash whitelist: log.sh ---
echo "--- A1. Bash whitelist: log.sh ---"
reset_state
set_context_usage 0.80  # above threshold, but log.sh should still be allowed

OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/log.sh sessions/test/LOG.md"}')
assert_contains '"allow"' "$OUT" "log.sh allowed even during overflow"

echo ""

# --- A2. Bash whitelist: session.sh ---
echo "--- A2. Bash whitelist: session.sh ---"
reset_state
set_context_usage 0.80

OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/session.sh dehydrate sessions/test"}')
assert_contains '"allow"' "$OUT" "session.sh allowed even during overflow"

echo ""

# --- A3. Skill(dehydrate) sets lifecycle=dehydrating ---
echo "--- A3. Skill(dehydrate) ---"
reset_state
set_context_usage 0.80

OUT=$(run_hook "Skill" '{"skill":"dehydrate","args":"restart"}')
assert_contains '"allow"' "$OUT" "Skill(dehydrate) allowed"

LIFECYCLE=$(jq -r '.lifecycle' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "dehydrating" "$LIFECYCLE" "lifecycle set to dehydrating"

echo ""

# --- A4. All tools allowed when lifecycle=dehydrating ---
echo "--- A4. lifecycle=dehydrating bypass ---"
reset_state
jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
set_context_usage 0.80

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x","old_string":"a","new_string":"b"}')
assert_contains '"allow"' "$OUT" "Edit allowed during dehydrating"

echo ""

# --- A5. All tools allowed when killRequested=true ---
echo "--- A5. killRequested=true bypass ---"
reset_state
jq '.killRequested = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
set_context_usage 0.80

OUT=$(run_hook "Write" '{"file_path":"/tmp/x","content":"hello"}')
assert_contains '"allow"' "$OUT" "Write allowed when killRequested"

echo ""

# =============================================================================
# THRESHOLD LOGIC
# =============================================================================

# --- A6. Allow when below threshold ---
echo "--- A6. Below threshold (0.75) ---"
reset_state
set_context_usage 0.75

OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "Grep allowed below threshold"

echo ""

# --- A7. Deny when above threshold ---
echo "--- A7. Above threshold (0.77) ---"
reset_state
set_context_usage 0.77

OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"deny"' "$OUT" "Grep denied above threshold"
assert_contains 'CONTEXT OVERFLOW' "$OUT" "Deny message contains CONTEXT OVERFLOW"

echo ""

# --- A8. Sets overflowed=true sticky flag ---
echo "--- A8. Overflowed sticky flag ---"
reset_state
set_context_usage 0.77

run_hook "Grep" '{"pattern":"foo","path":"/tmp"}' > /dev/null
OVERFLOWED=$(jq -r '.overflowed // false' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "true" "$OVERFLOWED" "overflowed=true after deny"

echo ""

# --- A9. Overflowed flag persists after below-threshold call ---
echo "--- A9. Sticky flag persistence ---"
# State from A8: overflowed=true. Now set context below threshold.
set_context_usage 0.10

# overflowed=true + lifecycle=active → the hook still allows (overflowed doesn't block,
# it only blocks via overflow hook's threshold check; stickiness means it's not cleared)
OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "Below threshold → allowed even with overflowed flag"

OVERFLOWED=$(jq -r '.overflowed // false' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_eq "true" "$OVERFLOWED" "overflowed flag persists (sticky)"

echo ""

# =============================================================================
# DENY COVERAGE (NON-WHITELISTED DURING OVERFLOW)
# =============================================================================

# --- A10. Non-Bash tools denied during overflow ---
echo "--- A10. Read denied during overflow ---"
reset_state
set_context_usage 0.77

OUT=$(run_hook "Read" '{"file_path":"/tmp/foo.ts"}')
assert_contains '"deny"' "$OUT" "Read denied during overflow"
assert_contains 'CONTEXT OVERFLOW' "$OUT" "Read deny has CONTEXT OVERFLOW message"

echo ""

# --- A11. Non-whitelisted Bash denied during overflow ---
echo "--- A11. Non-whitelisted Bash denied ---"
reset_state
set_context_usage 0.77

OUT=$(run_hook "Bash" '{"command":"git status"}')
assert_contains '"deny"' "$OUT" "git status denied during overflow"
assert_contains 'CONTEXT OVERFLOW' "$OUT" "Bash deny has CONTEXT OVERFLOW message"

echo ""

# =============================================================================
# NO SESSION / MISSING STATE
# =============================================================================

# --- A12. Allow when no session found ---
echo "--- A12. No session directory ---"
# Use a dead PID that won't match any session
export CLAUDE_SUPERVISOR_PID=99999999

OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "No session → allow"

echo ""

# --- A13. Allow when .state.json is missing ---
echo "--- A13. Missing .state.json ---"
export CLAUDE_SUPERVISOR_PID=$$

# Remove .state.json but keep session dir
rm -f "$TEST_SESSION/.state.json"

OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "Missing .state.json → allow"

echo ""

# --- Summary ---
echo "======================================"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "======================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
