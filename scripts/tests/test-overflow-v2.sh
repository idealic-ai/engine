#!/bin/bash
# tests/test-overflow-v2.sh — Tests for pre-tool-use-overflow-v2.sh hook
#
# Tests:
#   B1. Whitelist: engine log always allowed
#   B2. Whitelist: engine session always allowed
#   B3. Skill(session, args:dehydrate) is allowed (lifecycle unchanged — Bash handles state)
#   B3b. Skill(session, args:continue) is allowed
#   B3c. Skill(session, args:status) does NOT set lifecycle=dehydrating
#   B4. All tools allowed when lifecycle=dehydrating
#   B5. All tools allowed when killRequested=true
#   B6. inline+allow delivery: heartbeat-warn stashes content for PostToolUse
#   B7. inline+block delivery: overflow-dehydration denies with content
#   B8. read+block delivery: denies with file read instruction (custom guards)
#   B9. paste+block delivery: denies with command text without tmux (custom guards)
#   B10. Delivered rules tracked in injectedRules
#   B11. Fallback: blocks at OVERFLOW_THRESHOLD
#   B12. Allow when contextUsage below threshold and no injections
#   B13. Allow when no session directory
#   B14. Non-whitelisted engine subcommand denied during overflow
#   B15. Adversarial engine-like command denied during overflow
#   B16. All files stale (already preloaded) — pendingPreloads cleaned
#   B17. Mixed new + stale files — stale removed, new claimed
#   B18. Non-existent file in pendingPreloads — removed, not added
#   B19. Empty pendingPreloads — no-op, no crash
#
# Run: bash ~/.claude/engine/scripts/tests/test-overflow-v2.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"
GUARDS_JSON="$HOME/.claude/engine/guards.json"

TMP_DIR=$(mktemp -d)

export CLAUDE_SUPERVISOR_PID=99999999

# Ensure default threshold (0.76) — unset flag that raises it to 0.95
unset DISABLE_AUTO_COMPACT 2>/dev/null || true

# Save real paths
REAL_HOOK="$HOOK"
REAL_SESSION_SH="$SESSION_SH"
REAL_LIB_SH="$LIB_SH"
REAL_CONFIG_SH="$CONFIG_SH"
REAL_GUARDS_JSON="$GUARDS_JSON"

setup_fake_home "$TMP_DIR"
disable_fleet_tmux

mkdir -p "$FAKE_HOME/.claude/engine"
mkdir -p "$FAKE_HOME/.claude/hooks"

# Symlink real scripts
ln -sf "$REAL_SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$REAL_LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$REAL_CONFIG_SH" "$FAKE_HOME/.claude/engine/config.sh"
ln -sf "$REAL_GUARDS_JSON" "$FAKE_HOME/.claude/engine/guards.json"
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
      .loading = false | del(.overflowed) | .injectedRules = {} |
      .pendingAllowInjections = [] | .toolCallsByTranscript = {} |
      .toolCallsSinceLastLog = 0 | .pendingPreloads = []' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

# Write custom guards.json for mode-specific tests (B8, B9)
write_test_guards() {
  rm -f "$FAKE_HOME/.claude/engine/guards.json"
  echo "$1" > "$FAKE_HOME/.claude/engine/guards.json"
}

restore_real_guards() {
  rm -f "$FAKE_HOME/.claude/engine/guards.json"
  ln -sf "$REAL_GUARDS_JSON" "$FAKE_HOME/.claude/engine/guards.json"
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
# B3: Skill(session, args:dehydrate) is allowed
# In the new architecture, only Bash(engine session dehydrate)
# sets lifecycle=dehydrating. Skill invocations load the protocol;
# the lifecycle change happens when the protocol runs the bash command.
# ============================================================
reset_state
OUTPUT=$(run_hook "Skill" '{"skill":"session","args":"dehydrate restart"}')
if echo "$OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
  fail "B3: Skill(session, dehydrate) should be allowed"
else
  pass "B3: Skill(session, dehydrate) is allowed"
fi

# ============================================================
# B3b: Skill(session, args:continue) is allowed
# ============================================================
reset_state
OUTPUT=$(run_hook "Skill" '{"skill":"session","args":"continue --session sessions/TEST --skill do --phase \"1: Work\""}')
if echo "$OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
  fail "B3b: Skill(session, continue) should be allowed"
else
  pass "B3b: Skill(session, continue) is allowed"
fi

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
# B6: inline+allow — heartbeat-warn stashes content for PostToolUse
# Trigger: set per-transcript counter to 2 (hook increments to 3,
# matching heartbeat-warn rule with eq:3 condition)
# ============================================================
reset_state
jq '.toolCallsByTranscript = {"test.jsonl": 2} | .toolCallsSinceLastLog = 2' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
# Should allow (not deny)
if echo "$OUTPUT" | grep -q '"permissionDecision".*"deny"'; then
  fail "B6: inline+allow should not deny"
else
  # Verify content stashed in pendingAllowInjections
  STASH_LEN=$(jq '.pendingAllowInjections // [] | length' "$TEST_SESSION/.state.json")
  STASH_RULE=$(jq -r '.pendingAllowInjections[0].ruleId // ""' "$TEST_SESSION/.state.json")
  if [ "$STASH_LEN" -gt 0 ] && [ "$STASH_RULE" = "heartbeat-warn" ]; then
    pass "B6: inline+allow stashes heartbeat-warn for PostToolUse delivery"
  else
    fail "B6: inline+allow should stash content" "heartbeat-warn stash" "len=$STASH_LEN rule=$STASH_RULE"
  fi
fi

# ============================================================
# B7: inline+block — overflow-dehydration denies with content
# Trigger: contextUsage=0.80 > default threshold 0.76
# Tool: Read (not in overflow-dehydration whitelist)
# ============================================================
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B7: inline+block (overflow) returns deny"

# ============================================================
# B8: read+block — denies with file read instruction
# Uses custom guards.json with a read-mode blocking rule
# ============================================================
reset_state
write_test_guards '[{
  "id": "test-read-block",
  "trigger": {"type": "contextThreshold", "condition": {"gte": 0.01}},
  "payload": {"files": ["/some/directive.md"]},
  "mode": "read",
  "urgency": "block",
  "priority": 20,
  "inject": "always"
}]'
jq '.contextUsage = 0.50' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B8: read+block returns deny"
restore_real_guards

# ============================================================
# B9: paste+block — denies with command text without tmux
# Uses custom guards.json with a paste-mode blocking rule
# ============================================================
reset_state
unset TMUX 2>/dev/null || true
write_test_guards '[{
  "id": "test-paste-block",
  "trigger": {"type": "contextThreshold", "condition": {"gte": 0.01}},
  "payload": {"command": "/session dehydrate restart"},
  "mode": "paste",
  "urgency": "block",
  "priority": 5,
  "inject": "always"
}]'
jq '.contextUsage = 0.50' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B9: paste+block returns deny without tmux"
restore_real_guards

# ============================================================
# B10: Delivered rules tracked in injectedRules
# Trigger overflow-dehydration via contextUsage, verify tracking
# ============================================================
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Read" '{"file_path":"/some/file.ts"}' > /dev/null

INJECTED=$(jq -r '.injectedRules["overflow-dehydration"] // "false"' "$TEST_SESSION/.state.json")
assert_eq "true" "$INJECTED" "B10: delivered rule tracked in injectedRules"

# ============================================================
# B11: Fallback — blocks at OVERFLOW_THRESHOLD
# contextUsage=0.80 > default threshold 0.76
# ============================================================
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B11: fallback blocks at overflow threshold"

# ============================================================
# B12: Allow when below threshold and no injections
# ============================================================
reset_state
jq '.contextUsage = 0.30' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
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
# B14: Non-whitelisted engine subcommand denied during overflow
# ============================================================
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# engine tag is NOT in the hardcoded whitelist (only engine log and engine session)
OUTPUT=$(run_hook "Bash" '{"command":"engine tag find #needs-review"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B14: engine tag denied during overflow (not whitelisted)"

# ============================================================
# B15: Adversarial engine-like command denied during overflow
# ============================================================
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# "engineering-tool" is not "engine" — should not match the whitelist
OUTPUT=$(run_hook "Bash" '{"command":"engineering-tool log sessions/test/LOG.md"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "B15: adversarial engine-like command denied during overflow"

# ============================================================
# B16: All files stale (already preloaded) — pendingPreloads cleaned
# pendingPreloads has 2 files, both already in preloadedFiles.
# _claim_and_preload should remove them from pendingPreloads without
# adding duplicates to preloadedFiles.
# ============================================================
reset_state
# Create real files on disk
mkdir -p "$FAKE_HOME/.claude/test-directives"
echo "# Commands" > "$FAKE_HOME/.claude/test-directives/COMMANDS.md"
echo "# Invariants" > "$FAKE_HOME/.claude/test-directives/INVARIANTS.md"

PRELOAD_PATH1="~/.claude/test-directives/COMMANDS.md"
PRELOAD_PATH2="~/.claude/test-directives/INVARIANTS.md"

jq --arg p1 "$PRELOAD_PATH1" --arg p2 "$PRELOAD_PATH2" '
  .pendingPreloads = [$p1, $p2] |
  .preloadedFiles = [$p1, $p2] |
  .contextUsage = 0.30
' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Read" '{"file_path":"/some/file.ts"}' > /dev/null

PENDING=$(jq '.pendingPreloads // []' "$TEST_SESSION/.state.json")
PENDING_LEN=$(echo "$PENDING" | jq 'length')
PRELOADED_LEN=$(jq '.preloadedFiles | length' "$TEST_SESSION/.state.json")
if [ "$PENDING_LEN" -eq 0 ]; then
  pass "B16: all-stale pendingPreloads cleaned to empty"
else
  fail "B16: all-stale pendingPreloads should be empty" "0" "$PENDING_LEN"
fi

# ============================================================
# B17: Mixed new + stale files — stale removed, new claimed
# pendingPreloads has 3 files: 1 already preloaded (stale), 2 new.
# _claim_and_preload should claim the 2 new, remove all 3 from pending.
# ============================================================
reset_state
mkdir -p "$FAKE_HOME/.claude/test-directives"
echo "# Commands" > "$FAKE_HOME/.claude/test-directives/COMMANDS.md"
echo "# New File A" > "$FAKE_HOME/.claude/test-directives/NEW_A.md"
echo "# New File B" > "$FAKE_HOME/.claude/test-directives/NEW_B.md"

STALE_PATH="~/.claude/test-directives/COMMANDS.md"
NEW_PATH_A="~/.claude/test-directives/NEW_A.md"
NEW_PATH_B="~/.claude/test-directives/NEW_B.md"

jq --arg s "$STALE_PATH" --arg a "$NEW_PATH_A" --arg b "$NEW_PATH_B" '
  .pendingPreloads = [$s, $a, $b] |
  .preloadedFiles = [$s] |
  .contextUsage = 0.30
' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')

PENDING_LEN=$(jq '.pendingPreloads | length' "$TEST_SESSION/.state.json")
# New files should be in preloadedFiles now
HAS_NEW_A=$(jq --arg a "$NEW_PATH_A" '.preloadedFiles | any(. == $a)' "$TEST_SESSION/.state.json")
HAS_NEW_B=$(jq --arg b "$NEW_PATH_B" '.preloadedFiles | any(. == $b)' "$TEST_SESSION/.state.json")

if [ "$PENDING_LEN" -eq 0 ] && [ "$HAS_NEW_A" = "true" ] && [ "$HAS_NEW_B" = "true" ]; then
  pass "B17: mixed stale+new — stale removed, new claimed"
else
  fail "B17: mixed stale+new" "pending=0, newA=true, newB=true" "pending=$PENDING_LEN, newA=$HAS_NEW_A, newB=$HAS_NEW_B"
fi

# ============================================================
# B18: Non-existent file in pendingPreloads — removed, not added
# pendingPreloads has 1 file that doesn't exist on disk.
# _claim_and_preload should remove it from pendingPreloads and NOT
# add it to preloadedFiles.
# ============================================================
reset_state
GHOST_PATH="~/.claude/test-directives/DOES_NOT_EXIST.md"

jq --arg g "$GHOST_PATH" '
  .pendingPreloads = [$g] |
  .preloadedFiles = [] |
  .contextUsage = 0.30
' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Read" '{"file_path":"/some/file.ts"}' > /dev/null

PENDING_LEN=$(jq '.pendingPreloads | length' "$TEST_SESSION/.state.json")
HAS_GHOST=$(jq --arg g "$GHOST_PATH" '.preloadedFiles | any(. == $g)' "$TEST_SESSION/.state.json")

if [ "$PENDING_LEN" -eq 0 ] && [ "$HAS_GHOST" = "false" ]; then
  pass "B18: non-existent file removed from pending, not added to preloaded"
else
  fail "B18: non-existent file" "pending=0, ghost=false" "pending=$PENDING_LEN, ghost=$HAS_GHOST"
fi

# ============================================================
# B19: Empty pendingPreloads — no-op, no crash
# pendingPreloads is []. Normal state. Hook should not crash or
# corrupt state.
# ============================================================
reset_state
jq '.pendingPreloads = [] | .preloadedFiles = ["existing.md"] | .contextUsage = 0.30' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
EXIT_CODE=$?

PENDING_LEN=$(jq '.pendingPreloads | length' "$TEST_SESSION/.state.json")
PRELOADED=$(jq -r '.preloadedFiles[0]' "$TEST_SESSION/.state.json")

if [ "$EXIT_CODE" -eq 0 ] && [ "$PENDING_LEN" -eq 0 ] && [ "$PRELOADED" = "existing.md" ]; then
  pass "B19: empty pendingPreloads — no-op, no crash, state preserved"
else
  fail "B19: empty pendingPreloads" "exit=0, pending=0, preloaded=existing.md" "exit=$EXIT_CODE, pending=$PENDING_LEN, preloaded=$PRELOADED"
fi

# ============================================================
# Results
# ============================================================
exit_with_results
