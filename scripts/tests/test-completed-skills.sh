#!/bin/bash
# tests/test-completed-skills.sh — Tests for completedSkills gating + .state.json rename
#
# Tests:
#   1. Activate → deactivate → completedSkills contains the skill
#   2. Re-activate same skill → rejected (exit 1)
#   3. Re-activate same skill with --user-approved → succeeds
#   4. Activate different skill after deactivation → succeeds
#   5. Deactivate twice → completedSkills not duplicated (idempotent)
#   6. .state.json filename used (not .agent.json)
#   7. Migration: old .agent.json auto-renamed to .state.json on activate

set -euo pipefail
source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/scripts/session.sh"
TEST_DIR="/tmp/test-completed-skills-$$"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Setup: create test session directory
mkdir -p "$TEST_DIR/sessions/test_session"

# Override CLAUDE_SUPERVISOR_PID for deterministic testing
export CLAUDE_SUPERVISOR_PID=$$

echo "=== Test 1: Activate → deactivate → completedSkills contains skill ==="
"$SESSION_SH" activate "$TEST_DIR/sessions/test_session" implement < /dev/null >/dev/null 2>&1
"$SESSION_SH" deactivate "$TEST_DIR/sessions/test_session" <<'EOF'
Test deactivation for completedSkills
EOF
COMPLETED=$(jq -r '.completedSkills | join(",")' "$TEST_DIR/sessions/test_session/.state.json" 2>/dev/null)
assert_eq "implement" "$COMPLETED" "completedSkills contains implement"

echo ""
echo "=== Test 2: Re-activate same skill → rejected ==="
OUTPUT=$("$SESSION_SH" activate "$TEST_DIR/sessions/test_session" implement < /dev/null 2>&1 || true)
EXIT_CODE=$?
# The activate should fail — check error message
assert_contains "already completed" "$OUTPUT" "Rejected with error message"

echo ""
echo "=== Test 3: Re-activate same skill with --user-approved → succeeds ==="
OUTPUT=$("$SESSION_SH" activate "$TEST_DIR/sessions/test_session" implement --user-approved "User said: 'yes, continue implement'" < /dev/null 2>&1)
assert_contains "re-activation approved" "$OUTPUT" "Approved re-activation"

echo ""
echo "=== Test 4: Activate different skill → succeeds (multi-modal) ==="
# First deactivate current
"$SESSION_SH" deactivate "$TEST_DIR/sessions/test_session" <<'EOF'
Test second deactivation
EOF
# Now activate a DIFFERENT skill — should succeed without --user-approved
OUTPUT=$("$SESSION_SH" activate "$TEST_DIR/sessions/test_session" analyze < /dev/null 2>&1)
assert_contains "Session" "$OUTPUT" "Different skill accepted"
# Should NOT contain "already completed" error
if echo "$OUTPUT" | grep -q "already completed"; then
  fail "Different skill should not be rejected"
else
  pass "Different skill not rejected"
fi

echo ""
echo "=== Test 5: Deactivate twice → completedSkills not duplicated ==="
"$SESSION_SH" deactivate "$TEST_DIR/sessions/test_session" <<'EOF'
Test analyze deactivation
EOF
COMPLETED=$(jq -r '.completedSkills | join(",")' "$TEST_DIR/sessions/test_session/.state.json" 2>/dev/null)
# Should have implement,analyze (no duplicates)
IMPL_COUNT=$(jq '[.completedSkills[] | select(. == "implement")] | length' "$TEST_DIR/sessions/test_session/.state.json")
assert_eq "1" "$IMPL_COUNT" "implement appears once"
assert_contains "analyze" "$COMPLETED" "completedSkills has both skills"

echo ""
echo "=== Test 6: .state.json filename used ==="
assert_eq "true" "$([ -f "$TEST_DIR/sessions/test_session/.state.json" ] && echo true || echo false)" "state.json exists"
assert_eq "false" "$([ -f "$TEST_DIR/sessions/test_session/.agent.json" ] && echo true || echo false)" "agent.json does NOT exist"

echo ""
echo "=== Test 7: Migration — old .agent.json auto-renamed ==="
# Create a fresh session with an old .agent.json file
mkdir -p "$TEST_DIR/sessions/migrate_test"
echo '{"pid": 99999, "skill": "test", "lifecycle": "completed"}' > "$TEST_DIR/sessions/migrate_test/.agent.json"
assert_eq "true" "$([ -f "$TEST_DIR/sessions/migrate_test/.agent.json" ] && echo true || echo false)" "Old .agent.json exists before migrate"
OUTPUT=$("$SESSION_SH" activate "$TEST_DIR/sessions/migrate_test" debug < /dev/null 2>&1)
assert_contains "Migrated" "$OUTPUT" "Migration message"
assert_eq "true" "$([ -f "$TEST_DIR/sessions/migrate_test/.state.json" ] && echo true || echo false)" "After migration: .state.json exists"
assert_eq "false" "$([ -f "$TEST_DIR/sessions/migrate_test/.agent.json" ] && echo true || echo false)" "After migration: .agent.json gone"

echo ""
echo "=== Test 8: Existing phase enforcement still works ==="
# Use a fresh session for clean phase enforcement test
mkdir -p "$TEST_DIR/sessions/phase_test"
"$SESSION_SH" activate "$TEST_DIR/sessions/phase_test" implement < /dev/null >/dev/null 2>&1
# Set up phases array
jq '.phases = [{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Build"}]' \
  "$TEST_DIR/sessions/phase_test/.state.json" > "$TEST_DIR/sessions/phase_test/.state.json.tmp" \
  && mv "$TEST_DIR/sessions/phase_test/.state.json.tmp" "$TEST_DIR/sessions/phase_test/.state.json"
# Must start at phase 1 first, then transition to 2
"$SESSION_SH" phase "$TEST_DIR/sessions/phase_test" "1: Setup" >/dev/null 2>&1
# Sequential transition should work
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR/sessions/phase_test" "2: Build" 2>&1)
assert_contains "Phase:" "$OUTPUT" "Phase transition works"

exit_with_results
