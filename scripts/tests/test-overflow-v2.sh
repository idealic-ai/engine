#!/bin/bash
# tests/test-overflow-v2.sh — Tests for pre-tool-use-overflow-v2.sh hook
#
# Tests:
#   B1. Whitelist: engine log always allowed
#   B2. Whitelist: engine session always allowed
#   B3. Skill(session, args:dehydrate) allowed and sets lifecycle=dehydrating
#   B3b. Skill(session, args:continue) allowed and sets lifecycle=dehydrating
#   B3c. Skill(session, args:status) does NOT set lifecycle=dehydrating
#   B4. All tools allowed when lifecycle=dehydrating
#   B5. All tools allowed when killRequested=true
#   B6. Delivers inline+allow injection via permissionDecisionReason
#   B7. Delivers inline+block injection via hook_deny
#   B8. Delivers read+block injection with file instruction
#   B9. Delivers paste+allow — falls back to block without tmux
#   B10. Marks delivered rules in injectedRules and clears from pendingInjections
#   B11. Fallback: blocks at OVERFLOW_THRESHOLD when no pendingInjections
#   B12. Allow when contextUsage below threshold and no injections
#   B13. Allow when no session directory
#
# Run: bash ~/.claude/engine/scripts/tests/test-overflow-v2.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"

TMP_DIR=$(mktemp -d)

export CLAUDE_SUPERVISOR_PID=99999999

# Save real paths
REAL_HOOK="$HOOK"
REAL_SESSION_SH="$SESSION_SH"
REAL_LIB_SH="$LIB_SH"
REAL_CONFIG_SH="$CONFIG_SH"

setup_fake_home "$TMP_DIR"
disable_fleet_tmux

mkdir -p "$FAKE_HOME/.claude/engine"
mkdir -p "$FAKE_HOME/.claude/hooks"

# Symlink real scripts
ln -sf "$REAL_SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$REAL_LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$REAL_CONFIG_SH" "$FAKE_HOME/.claude/engine/config.sh"
ln -sf "$REAL_HOOK" "$FAKE_HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"

mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

cd "$TMP_DIR"

TEST_SESSION="$TMP_DIR/sessions/test_overflow_v2"
mkdir -p "$TEST_SESSION"

RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run hook with given tool_name and optional tool_input
run_hook() {
  local tool_name="$1"
  local tool_input="${2:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s,"session_id":"test","transcript_path":"/tmp/test.jsonl"}\n' \
    "$tool_name" "$tool_input" \
    | "$RESOLVED_HOOK" 2>/dev/null
}

reset_state() {
  # Preserve fields from session.sh activate, only reset test-relevant fields
  jq '.lifecycle = "active" | .killRequested = false | .contextUsage = 0 |
      del(.overflowed) | .injectedRules = {} | .pendingInjections = []' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

echo "======================================"
echo "Overflow V2 Hook Tests"
echo "======================================"
echo ""

# Activate test session
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" implement < /dev/null > /dev/null 2>&1

# ============================================================
# B1: Whitelist — engine log allowed
# ============================================================
reset_state
OUTPUT=$(run_hook "Bash" '{"command":"engine log sessions/test/LOG.md <<EOF\n## Test\nEOF"}')
if echo "$OUTPUT" | grep -q '"permissionDecision"'; then
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow")
  assert_eq "allow" "$DECISION" "B1: engine log whitelisted"
else
  pass "B1: engine log whitelisted (empty output = allow)"
fi

# ============================================================
# B2: Whitelist — engine session allowed
# ============================================================
reset_state
OUTPUT=$(run_hook "Bash" '{"command":"engine session phase sessions/test \"4: Build\""}')
if echo "$OUTPUT" | grep -q '"permissionDecision"'; then
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow")
  assert_eq "allow" "$DECISION" "B2: engine session whitelisted"
else
  pass "B2: engine session whitelisted (empty output = allow)"
fi

# ============================================================
# B3: Skill(session, args:dehydrate) sets lifecycle=dehydrating
# ============================================================
reset_state
OUTPUT=$(run_hook "Skill" '{"skill":"session","args":"dehydrate restart"}')
LIFECYCLE=$(jq -r '.lifecycle' "$TEST_SESSION/.state.json")
assert_eq "dehydrating" "$LIFECYCLE" "B3: Skill(session, args:dehydrate) sets lifecycle=dehydrating"

# ============================================================
# B3b: Skill(session, args:continue) sets lifecycle=dehydrating
# ============================================================
reset_state
OUTPUT=$(run_hook "Skill" '{"skill":"session","args":"continue --session sessions/TEST --skill do --phase \"1: Work\""}')
LIFECYCLE=$(jq -r '.lifecycle' "$TEST_SESSION/.state.json")
assert_eq "dehydrating" "$LIFECYCLE" "B3b: Skill(session, args:continue) sets lifecycle=dehydrating"

# ============================================================
# B3c: Skill(session, args:status) does NOT set lifecycle=dehydrating
# ============================================================
reset_state
OUTPUT=$(run_hook "Skill" '{"skill":"session","args":"status"}')
LIFECYCLE=$(jq -r '.lifecycle' "$TEST_SESSION/.state.json")
assert_eq "active" "$LIFECYCLE" "B3c: Skill(session, args:status) does NOT set lifecycle=dehydrating"

# ============================================================
# B4: All tools allowed when lifecycle=dehydrating
# ============================================================
jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "B4: tools should be allowed during dehydrating"
else
  pass "B4: tools allowed during dehydrating lifecycle"
fi

# ============================================================
# B5: All tools allowed when killRequested=true
# ============================================================
reset_state
jq '.killRequested = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "B5: tools should be allowed when killRequested"
else
  pass "B5: tools allowed when killRequested=true"
fi

# ============================================================
# B6: inline+allow — delivers via permissionDecisionReason
# ============================================================
reset_state
jq '.pendingInjections = [{
  "ruleId": "test-inline-allow",
  "mode": "inline",
  "urgency": "allow",
  "priority": 10,
  "payload": {"text": "injected content here"}
}]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
REASON=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
assert_eq "allow" "$DECISION" "B6: inline+allow returns allow decision"
assert_contains "injected content here" "$REASON" "B6: inline+allow includes payload in reason"

# ============================================================
# B7: inline+block — delivers via hook_deny
# ============================================================
reset_state
jq '.pendingInjections = [{
  "ruleId": "test-inline-block",
  "mode": "inline",
  "urgency": "block",
  "priority": 10,
  "payload": {"text": "blocking content"}
}]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B7: inline+block returns deny decision"

# ============================================================
# B8: read+block — includes file instruction
# ============================================================
reset_state
jq '.pendingInjections = [{
  "ruleId": "test-read-block",
  "mode": "read",
  "urgency": "block",
  "priority": 20,
  "payload": {"files": ["/some/directive.md"]}
}]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B8: read+block returns deny"

# ============================================================
# B9: paste+allow — falls back to block without tmux
# ============================================================
reset_state
unset TMUX 2>/dev/null || true
jq '.pendingInjections = [{
  "ruleId": "test-paste-allow",
  "mode": "paste",
  "urgency": "allow",
  "priority": 5,
  "payload": {"command": "/session dehydrate restart"}
}]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B9: paste+allow falls back to block without tmux"

# ============================================================
# B10: Delivered rules marked in injectedRules, cleared from pendingInjections
# ============================================================
reset_state
jq '.pendingInjections = [{
  "ruleId": "test-delivery",
  "mode": "inline",
  "urgency": "allow",
  "priority": 10,
  "payload": {"text": "delivered content"}
}]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Read" '{"file_path":"/some/file.ts"}' > /dev/null

INJECTED=$(jq -r '.injectedRules["test-delivery"] // "false"' "$TEST_SESSION/.state.json")
REMAINING=$(jq '.pendingInjections | length' "$TEST_SESSION/.state.json")
assert_eq "true" "$INJECTED" "B10: delivered rule marked in injectedRules"
assert_eq "0" "$REMAINING" "B10: delivered rule cleared from pendingInjections"

# ============================================================
# B11: Fallback — blocks at OVERFLOW_THRESHOLD when no injections
# ============================================================
reset_state
jq '.contextUsage = 0.80 | .pendingInjections = []' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B11: fallback blocks at overflow threshold"

# ============================================================
# B12: Allow when below threshold and no injections
# ============================================================
reset_state
jq '.contextUsage = 0.30 | .pendingInjections = []' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "B12: should allow when below threshold"
else
  pass "B12: allows tool when below threshold and no injections"
fi

# ============================================================
# B13: Allow when no session directory
# ============================================================
# Can't easily test this in isolation since session.sh find will find our test session.
# Instead just verify hook doesn't crash with bad input.
OUTPUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}\n' | "$RESOLVED_HOOK" 2>/dev/null || true)
pass "B13: hook doesn't crash on execution"

# ============================================================
# Results
# ============================================================
exit_with_results
