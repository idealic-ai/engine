#!/bin/bash
# Test: PostToolUse injection delivery hook
# Covers: post-tool-use-injections.sh (stash delivery via additionalContext)
#
# Verifies the stash-and-deliver mechanism:
#   PreToolUse stashes allow-urgency injections to .state.json:pendingAllowInjections
#   PostToolUse reads them, delivers via additionalContext, clears the stash
#
# Per ¶INV_TEST_SANDBOX_ISOLATION: Uses temp sandbox, overrides HOME.

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# --- Setup sandbox ---
SANDBOX=$(mktemp -d)
REAL_HOME="$HOME"
trap 'rm -rf "$SANDBOX"' EXIT

# Hook under test
HOOK="$REAL_HOME/.claude/engine/hooks/post-tool-use-injections.sh"

# Create minimal mock HOME structure
mkdir -p "$SANDBOX/.claude/scripts"

# Symlink real lib.sh (provides safe_json_write)
ln -s "$REAL_HOME/.claude/scripts/lib.sh" "$SANDBOX/.claude/scripts/lib.sh"

# Create mock session dir
SESSION_DIR="$SANDBOX/sessions/2026_01_01_TEST"
mkdir -p "$SESSION_DIR"

# Create mock session.sh that returns our test session dir
cat > "$SANDBOX/.claude/scripts/session.sh" <<'MOCK'
#!/bin/bash
if [ "${1:-}" = "find" ]; then
  echo "$TEST_SESSION_DIR"
  exit 0
fi
exit 1
MOCK
chmod +x "$SANDBOX/.claude/scripts/session.sh"

# --- Assertion helpers ---
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected: $expected\n    actual:   $actual"
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected to contain: $needle\n    actual: $haystack"
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    should NOT contain: $needle\n    actual: $haystack"
    echo "  FAIL: $label"
    echo "    should NOT contain: $needle"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  fi
}

# --- Helper: write .state.json ---
write_state() {
  local pending_json="${1:-[]}"
  cat > "$SESSION_DIR/.state.json" <<JSON
{
  "lifecycle": "active",
  "skill": "implement",
  "pid": $$,
  "pendingAllowInjections": $pending_json
}
JSON
}

# --- Helper: run the hook ---
run_hook() {
  HOME="$SANDBOX" TEST_SESSION_DIR="$SESSION_DIR" bash "$HOOK" 2>/dev/null || true
}

# ============================================================
# TEST 1: Delivers stashed inline injection via additionalContext
# ============================================================
echo ""
echo "=== Test 1: Delivers stashed inline injection ==="
write_state '[{"ruleId": "heartbeat-warn", "content": "[Injection: heartbeat-warn] Log your progress soon."}]'

OUTPUT=$(run_hook)

echo ""
echo "Case 1a: Output contains additionalContext"
assert_contains "output has additionalContext" "additionalContext" "$OUTPUT"

echo ""
echo "Case 1b: Output contains injection content"
assert_contains "output has heartbeat-warn content" "Log your progress soon" "$OUTPUT"

echo ""
echo "Case 1c: Output contains hookEventName PostToolUse"
assert_contains "output has PostToolUse event" "PostToolUse" "$OUTPUT"

# ============================================================
# TEST 2: Clears pendingAllowInjections after delivery
# ============================================================
echo ""
echo "=== Test 2: Clears stash after delivery ==="
write_state '[{"ruleId": "test-rule", "content": "test content"}]'
run_hook > /dev/null

REMAINING=$(jq '.pendingAllowInjections | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "error")
echo ""
echo "Case 2a: pendingAllowInjections is empty after delivery"
assert_eq "stash cleared" "0" "$REMAINING"

# ============================================================
# TEST 3: Silent exit when no pending injections
# ============================================================
echo ""
echo "=== Test 3: Silent exit when empty ==="
write_state '[]'

OUTPUT=$(run_hook)
echo ""
echo "Case 3a: No output when stash is empty"
assert_eq "no output" "" "$OUTPUT"

# ============================================================
# TEST 4: Silent exit when pendingAllowInjections is missing
# ============================================================
echo ""
echo "=== Test 4: Silent exit when field missing ==="
cat > "$SESSION_DIR/.state.json" <<JSON
{
  "lifecycle": "active",
  "skill": "implement",
  "pid": $$
}
JSON

OUTPUT=$(run_hook)
echo ""
echo "Case 4a: No output when field is absent"
assert_eq "no output for missing field" "" "$OUTPUT"

# ============================================================
# TEST 5: Multiple stashed injections
# ============================================================
echo ""
echo "=== Test 5: Multiple stashed injections ==="
write_state '[
  {"ruleId": "heartbeat-warn", "content": "[Injection: heartbeat-warn] Log soon."},
  {"ruleId": "synthesis-commands", "content": "[Injection: synthesis-commands] Execute pipeline."},
  {"ruleId": "standards-preload", "content": "[Preloaded: /path/to/file] file content here"}
]'

OUTPUT=$(run_hook)
echo ""
echo "Case 5a: Output contains first injection"
assert_contains "has heartbeat-warn" "Log soon" "$OUTPUT"

echo ""
echo "Case 5b: Output contains second injection"
assert_contains "has synthesis-commands" "Execute pipeline" "$OUTPUT"

echo ""
echo "Case 5c: Output contains third injection"
assert_contains "has standards-preload" "file content here" "$OUTPUT"

echo ""
echo "Case 5d: All cleared after delivery"
REMAINING=$(jq '.pendingAllowInjections | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "error")
assert_eq "all cleared" "0" "$REMAINING"

# ============================================================
# TEST 6: Output is valid JSON
# ============================================================
echo ""
echo "=== Test 6: Output is valid JSON ==="
write_state '[{"ruleId": "test", "content": "test content with \"quotes\" and newlines"}]'

OUTPUT=$(run_hook)
JSON_VALID=$(echo "$OUTPUT" | jq '.' > /dev/null 2>&1 && echo "valid" || echo "invalid")
echo ""
echo "Case 6a: Hook output is valid JSON"
assert_eq "valid JSON" "valid" "$JSON_VALID"

# ============================================================
# TEST 7: No session dir — silent exit
# ============================================================
echo ""
echo "=== Test 7: No session dir — silent exit ==="

OUTPUT=$(HOME="$SANDBOX" TEST_SESSION_DIR="" bash "$HOOK" 2>/dev/null || true)
echo ""
echo "Case 7a: No output when no session"
assert_eq "no output without session" "" "$OUTPUT"

# ============================================================
# RESULTS
# ============================================================
echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
fi

exit 0
