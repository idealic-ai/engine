#!/bin/bash
# tests/test-prompt-gate.sh — Tests for user-prompt-submit-session-gate.sh hook
#
# Tests:
#   1. Gate disabled (SESSION_REQUIRED != 1) → no output
#   2. Active session → no output (passthrough)
#   3. Dehydrating session → no output (passthrough)
#   4. Completed session → injects continuation message
#   5. No session → injects boot sequence message
#
# Uses HOME override for full isolation (same pattern as test-heartbeat.sh).
#
# Run: bash ~/.claude/engine/scripts/tests/test-prompt-gate.sh

set -uo pipefail

HOOK="$HOME/.claude/hooks/user-prompt-submit-session-gate.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Disable fleet/tmux
unset TMUX 2>/dev/null || true
unset TMUX_PANE 2>/dev/null || true
unset SESSION_REQUIRED 2>/dev/null || true

# Use a dead PID for isolation
export CLAUDE_SUPERVISOR_PID=99999999

# Create fake HOME to isolate session.sh find from real sessions
FAKE_HOME="$TMP_DIR/fake-home"
mkdir -p "$FAKE_HOME/.claude/scripts"
mkdir -p "$FAKE_HOME/.claude/hooks"
mkdir -p "$FAKE_HOME/.claude/tools/session-search"
mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

# Symlink real scripts into fake home
ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$HOOK" "$FAKE_HOME/.claude/hooks/user-prompt-submit-session-gate.sh"

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
TEST_SESSION="$TMP_DIR/sessions/test_prompt_gate"
mkdir -p "$TEST_SESSION"

# Resolved hook path
RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/user-prompt-submit-session-gate.sh"

cleanup() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_empty() {
  local actual="$1" msg="$2"
  if [ -z "$actual" ]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $msg"
    echo "  Expected empty output"
    echo "  Actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

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

assert_not_empty() {
  local actual="$1" msg="$2"
  if [ -n "$actual" ]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC}: $msg"
    echo "  Expected non-empty output, got nothing"
    FAIL=$((FAIL + 1))
  fi
}

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
assert_empty "$OUT" "SESSION_REQUIRED empty → no output"

OUT=$(run_hook "0")
assert_empty "$OUT" "SESSION_REQUIRED=0 → no output"

echo ""

# --- 2. Active session → passthrough ---
echo "--- 2. Active session → passthrough ---"

export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

# Clear loading flag
jq 'del(.loading)' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_empty "$OUT" "Active session → no output (passthrough)"

echo ""

# --- 3. Dehydrating session → passthrough ---
echo "--- 3. Dehydrating session → passthrough ---"

jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_empty "$OUT" "Dehydrating session → no output (passthrough)"

echo ""

# --- 4. Completed session → injects message ---
echo "--- 4. Completed session → inject continuation ---"

jq '.lifecycle = "completed" | .skill = "implement"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "1")
assert_not_empty "$OUT" "Completed session → produces output"
assert_contains '§CMD_REQUIRE_ACTIVE_SESSION' "$OUT" "Message contains §CMD_REQUIRE_ACTIVE_SESSION"
assert_contains 'completed' "$OUT" "Message mentions completed"
assert_contains 'implement' "$OUT" "Message mentions the skill"
assert_contains 'hookSpecificOutput' "$OUT" "Output is valid hook response"
assert_contains 'Boot sequence' "$OUT" "Message includes boot sequence"

echo ""

# --- 5. No session → injects boot message ---
echo "--- 5. No session → inject boot sequence ---"

rm -f "$TEST_SESSION/.state.json"
export CLAUDE_SUPERVISOR_PID=99999999

OUT=$(run_hook "1")
assert_not_empty "$OUT" "No session → produces output"
assert_contains '§CMD_REQUIRE_ACTIVE_SESSION' "$OUT" "Message contains §CMD_REQUIRE_ACTIVE_SESSION"
assert_contains 'No active session' "$OUT" "Message says no active session"
assert_contains 'Boot sequence' "$OUT" "Message includes boot sequence"
assert_contains 'hookSpecificOutput' "$OUT" "Output is valid hook response"
assert_contains 'AskUserQuestion' "$OUT" "Message instructs to use AskUserQuestion"

echo ""

echo "======================================"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "======================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
