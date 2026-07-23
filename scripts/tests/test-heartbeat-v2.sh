#!/bin/bash
# tests/test-heartbeat-v2.sh — Tests for heartbeat logic in pre-tool-use-overflow-v2.sh
#
# The heartbeat (per-transcript counter, warn/block thresholds, same-file edit
# suppression) is embedded in the unified overflow-v2 hook.
#
# Tests:
#   C1. Loading bypass — all tools allowed when loading=true
#   C2. Dehydrating bypass — all tools allowed when lifecycle=dehydrating
#   C3. Whitelist — engine log resets counter
#   C4. Whitelist — engine session allowed
#   C5. Whitelist — Read of ~/.claude/ files allowed
#   C6. Whitelist — Task tool allowed
#   C7. Warn at warn threshold (heartbeat-warn rule, eq:3 in guards.json)
#   C8. Block at block threshold (heartbeat-block rule, gte:10 in guards.json)
#   C9. Counter increments on non-whitelisted tool calls
#   C10. Same-file edit suppression
#
# Run: bash ~/.claude/engine/scripts/tests/test-heartbeat-v2.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"
GUARDS_JSON="$HOME/.claude/engine/guards.json"

TMP_DIR=$(mktemp -d)
export CLAUDE_SUPERVISOR_PID=99999999

REAL_HOOK="$HOOK"
REAL_SESSION_SH="$SESSION_SH"
REAL_LIB_SH="$LIB_SH"
REAL_CONFIG_SH="$CONFIG_SH"
REAL_GUARDS_JSON="$GUARDS_JSON"

setup_fake_home "$TMP_DIR"
disable_fleet_tmux

mkdir -p "$FAKE_HOME/.claude/engine"
mkdir -p "$FAKE_HOME/.claude/hooks"

ln -sf "$REAL_SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$REAL_LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$REAL_CONFIG_SH" "$FAKE_HOME/.claude/engine/config.sh"
ln -sf "$REAL_GUARDS_JSON" "$FAKE_HOME/.claude/engine/guards.json"
ln -sf "$REAL_HOOK" "$FAKE_HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"

mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

cd "$TMP_DIR"

TEST_SESSION="$TMP_DIR/sessions/test_heartbeat_v2"
mkdir -p "$TEST_SESSION"

RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"
TRANSCRIPT_PATH="/tmp/test_heartbeat_transcript.jsonl"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_hook() {
  local tool_name="$1"
  local tool_input="${2:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s,"session_id":"test","transcript_path":"%s"}\n' \
    "$tool_name" "$tool_input" "$TRANSCRIPT_PATH" \
    | "$RESOLVED_HOOK" 2>/dev/null
}

reset_state() {
  jq '.lifecycle = "active" | .loading = false | .contextUsage = 0 |
      .toolCallsByTranscript = {} | .injectedRules = {} |
      .logTemplate = "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md"' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

echo "======================================"
echo "Heartbeat V2 Hook Tests"
echo "======================================"
echo ""

export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" implement < /dev/null > /dev/null 2>&1

# ============================================================
# C1: Loading bypass
# ============================================================
reset_state
jq '.loading = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/code.ts"}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "C1: should allow during loading"
else
  pass "C1: tools allowed during loading=true"
fi

# ============================================================
# C2: Dehydrating bypass
# ============================================================
reset_state
jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Read" '{"file_path":"/some/code.ts"}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "C2: should allow during dehydrating"
else
  pass "C2: tools allowed during dehydrating lifecycle"
fi

# ============================================================
# C3: engine log resets counter
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 5' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Bash" '{"command":"engine log sessions/test/LOG.md <<EOF\n## Test\nEOF"}' > /dev/null

COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER" "C3: engine log resets counter to 0"

# ============================================================
# C4: engine session allowed
# ============================================================
reset_state
OUTPUT=$(run_hook "Bash" '{"command":"engine session phase sessions/test \"4: Build\""}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "C4: engine session should be whitelisted"
else
  pass "C4: engine session whitelisted"
fi

# ============================================================
# C5: Read of ~/.claude/ files allowed
# ============================================================
reset_state
OUTPUT=$(run_hook "Read" "{\"file_path\":\"$FAKE_HOME/.claude/skills/implement/SKILL.md\"}")
if echo "$OUTPUT" | grep -q "deny"; then
  fail "C5: Read of ~/.claude/ should be whitelisted"
else
  pass "C5: Read of ~/.claude/ files whitelisted"
fi

# ============================================================
# C6: Task tool allowed
# ============================================================
reset_state
OUTPUT=$(run_hook "Task" '{"prompt":"do something"}')
if echo "$OUTPUT" | grep -q "deny"; then
  fail "C6: Task tool should be whitelisted"
else
  pass "C6: Task tool whitelisted"
fi

# ============================================================
# C7: Warn at warn threshold
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
# Set counter to warn_after - 1 so next call hits warn
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 2' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
# In unified overflow-v2, allow-urgency warnings are stashed to pendingAllowInjections
# for PostToolUse delivery (not in PreToolUse permissionDecisionReason)
STASHED=$(jq -r '.pendingAllowInjections // [] | .[0].content // ""' "$TEST_SESSION/.state.json")
assert_eq "allow" "$DECISION" "C7: warns but allows at warn threshold"
assert_contains "CMD_APPEND_LOG" "$STASHED" "C7: warn stashed for PostToolUse delivery"

# ============================================================
# C8: Block at block threshold (heartbeat-block: gte:10 in guards.json)
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
# Set counter to 9 so next call increments to 10, triggering heartbeat-block (gte:10)
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 9' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "C8: blocks at block threshold"

# ============================================================
# C9: Counter increments on non-whitelisted calls
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")

run_hook "Grep" '{"pattern":"test"}' > /dev/null
COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$COUNTER" "C9: counter increments after non-whitelisted call"

run_hook "Glob" '{"pattern":"*.ts"}' > /dev/null
COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "2" "$COUNTER" "C9: counter increments again"

# ============================================================
# C10: Same-file edit suppression
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")

# First edit of a file — counter increments
run_hook "Edit" '{"file_path":"/some/file.ts","old_string":"a","new_string":"b"}' > /dev/null
COUNTER1=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")

# Second edit of SAME file — should be suppressed (counter doesn't increment)
run_hook "Edit" '{"file_path":"/some/file.ts","old_string":"b","new_string":"c"}' > /dev/null
COUNTER2=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")

assert_eq "$COUNTER1" "$COUNTER2" "C10: same-file edit suppression (counter unchanged)"

# ============================================================
# C11: Different-file edit increments counter
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")

# First edit of file A
run_hook "Edit" '{"file_path":"/some/file-a.ts","old_string":"a","new_string":"b"}' > /dev/null
COUNTER1=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")

# Second edit of file B (different file) — should increment
run_hook "Edit" '{"file_path":"/some/file-b.ts","old_string":"x","new_string":"y"}' > /dev/null
COUNTER2=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")

assert_eq "$((COUNTER1 + 1))" "$COUNTER2" "C11: different-file edit increments counter"

# ============================================================
# C12: Completed lifecycle → skip heartbeat (no counter increment)
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Grep" '{"pattern":"test"}' > /dev/null
COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER" "C12: completed lifecycle skips heartbeat counter"

# Restore active lifecycle for remaining tests
reset_state

# ============================================================
# C13: Bash with direct script path NOT whitelisted
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")

# engine log IS whitelisted, but a direct path to the script should NOT be
run_hook "Bash" '{"command":"/Users/x/.claude/scripts/log.sh sessions/test/LOG.md"}' > /dev/null
COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$COUNTER" "C13: direct script path increments counter (not whitelisted)"

# ============================================================
# C14: Non-whitelisted engine subcommand increments counter
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")

# engine tag is NOT in the heartbeat hardcoded whitelist
run_hook "Bash" '{"command":"engine tag find #needs-review"}' > /dev/null
COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$COUNTER" "C14: non-whitelisted engine subcommand increments counter"

# ============================================================
# C15: TaskOutput whitelisted (not blocked by heartbeat)
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 15' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "TaskOutput" '{"task_id":"abc123","block":true}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
if [ "$DECISION" = "deny" ]; then
  fail "C15: TaskOutput should be whitelisted by heartbeat-block"
else
  pass "C15: TaskOutput whitelisted by heartbeat-block"
fi

# ============================================================
# C16: TaskOutput does NOT increment counter
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")

run_hook "TaskOutput" '{"task_id":"abc123","block":true}' > /dev/null
COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER" "C16: TaskOutput does not increment counter"

# ============================================================
# C17: Subagent IS blocked at heartbeat threshold — on its OWN sub:<agent_id> counter.
# A sub-agent keeps its own heartbeat discipline (§PTF_SESSION_HOOK_STATE_BLEEDS_TO_SUBAGENTS);
# detection is by the `agent_id` field, NOT the transcript_path (which is the parent's).
# ============================================================
reset_state
SUBAGENT_ID="agent-c17"
SUBAGENT_CKEY="sub:$SUBAGENT_ID"
# Establish parent's primary transcript key by making a parent call first
run_hook "Grep" '{"pattern":"test"}' > /dev/null
# Set the subagent's OWN namespaced counter to 9 so its next call triggers heartbeat-block (gte:10)
jq --arg key "$SUBAGENT_CKEY" '.toolCallsByTranscript[$key] = 9' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# Subagent identified by agent_id (fires under the PARENT's transcript_path) → namespaced sub:<agent_id>
OUTPUT=$(printf '{"tool_name":"Grep","tool_input":{"pattern":"test"},"session_id":"test","transcript_path":"%s","agent_id":"%s"}\n' \
  "$TRANSCRIPT_PATH" "$SUBAGENT_ID" | "$RESOLVED_HOOK" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "C17: subagent IS blocked at heartbeat threshold on its own sub:<agent_id> counter"

# ============================================================
# C18: Parent IS blocked at same threshold (control test)
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
# Make a parent call to establish primaryTranscriptKey
run_hook "Grep" '{"pattern":"test"}' > /dev/null
# Set parent counter to 9 so next call triggers heartbeat-block (gte:10)
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 9' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "C18: parent IS blocked at heartbeat threshold (control)"

# ============================================================
# C19: Subagent (agent_id) counter does NOT overwrite global toolCallsSinceLastLog.
# A sub-agent increments ONLY its own sub:<agent_id> counter — never the parent's global.
# ============================================================
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
SUBAGENT_ID="agent-c19"
SUBAGENT_CKEY="sub:$SUBAGENT_ID"
# Establish parent's primary key + set counter
run_hook "Grep" '{"pattern":"test"}' > /dev/null
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 2 | .toolCallsSinceLastLog = 2' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# Subagent (agent_id) makes a call — increments only sub:<id>, must NOT touch toolCallsSinceLastLog
printf '{"tool_name":"Grep","tool_input":{"pattern":"test"},"session_id":"test","transcript_path":"%s","agent_id":"%s"}\n' \
  "$TRANSCRIPT_PATH" "$SUBAGENT_ID" | "$RESOLVED_HOOK" 2>/dev/null > /dev/null

GLOBAL_COUNTER=$(jq -r '.toolCallsSinceLastLog // 0' "$TEST_SESSION/.state.json")
SUBAGENT_COUNTER=$(jq -r --arg key "$SUBAGENT_CKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "2" "$GLOBAL_COUNTER" "C19: global counter preserved (subagent did not overwrite)"
assert_eq "1" "$SUBAGENT_COUNTER" "C19: subagent per-agent_id counter incremented"

# ============================================================
# Contract-aware heartbeat (piece 2)
# ============================================================
# Helper: strip the checkpoint fields this feature owns so cases don't leak.
# Also drains pendingAllowInjections (append-only across tool calls) so a warn
# assertion reads THIS case's fresh entry at [0], not a stale one from an earlier case.
clear_checkpoint_state() {
  jq 'del(.checkpointCounters) | del(.lastCheckpoint) | del(.checkpointStrategy) |
      .pendingAllowInjections = []' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

# ============================================================
# C20: engine log --reason step bumps checkpointCounters.step + lastCheckpoint
# ============================================================
reset_state
clear_checkpoint_state

run_hook "Bash" '{"command":"engine log sessions/test/LOG.md --reason step <<EOF\n## Step\nEOF"}' > /dev/null

STEP=$(jq -r '.checkpointCounters.step // 0' "$TEST_SESSION/.state.json")
LR=$(jq -r '.lastCheckpoint.reason // ""' "$TEST_SESSION/.state.json")
LAT=$(jq -r '.lastCheckpoint.at // ""' "$TEST_SESSION/.state.json")
assert_eq "1" "$STEP" "C20: --reason step bumps checkpointCounters.step to 1"
assert_eq "step" "$LR" "C20: lastCheckpoint.reason = step"
assert_neq "" "$LAT" "C20: lastCheckpoint.at is stamped"

# ============================================================
# C21: bare engine log resets counter but does NOT touch checkpointCounters
# ============================================================
reset_state
clear_checkpoint_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 5' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Bash" '{"command":"engine log sessions/test/LOG.md <<EOF\n## Plain\nEOF"}' > /dev/null

COUNTER=$(jq -r --arg key "$TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
HAS_CC=$(jq -r 'has("checkpointCounters")' "$TEST_SESSION/.state.json")
HAS_LC=$(jq -r 'has("lastCheckpoint")' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER" "C21: bare engine log resets no-log counter (existing behavior)"
assert_eq "false" "$HAS_CC" "C21: bare engine log leaves checkpointCounters untouched"
assert_eq "false" "$HAS_LC" "C21: bare engine log leaves lastCheckpoint untouched"

# ============================================================
# C22: non-log tool call does not touch checkpointCounters
# ============================================================
reset_state
clear_checkpoint_state

run_hook "Grep" '{"pattern":"test"}' > /dev/null

HAS_CC=$(jq -r 'has("checkpointCounters")' "$TEST_SESSION/.state.json")
HAS_LC=$(jq -r 'has("lastCheckpoint")' "$TEST_SESSION/.state.json")
assert_eq "false" "$HAS_CC" "C22: non-log tool leaves checkpointCounters untouched"
assert_eq "false" "$HAS_LC" "C22: non-log tool leaves lastCheckpoint untouched"

# ============================================================
# C23: two --reason logs accumulate counters correctly
# ============================================================
reset_state
clear_checkpoint_state

run_hook "Bash" '{"command":"engine log sessions/test/LOG.md --reason step <<EOF\n## S1\nEOF"}' > /dev/null
run_hook "Bash" '{"command":"engine log sessions/test/LOG.md --reason step <<EOF\n## S2\nEOF"}' > /dev/null
run_hook "Bash" '{"command":"engine log sessions/test/LOG.md --reason section <<EOF\n## Sec\nEOF"}' > /dev/null

STEP=$(jq -r '.checkpointCounters.step // 0' "$TEST_SESSION/.state.json")
SECTION=$(jq -r '.checkpointCounters.section // 0' "$TEST_SESSION/.state.json")
LR=$(jq -r '.lastCheckpoint.reason // ""' "$TEST_SESSION/.state.json")
assert_eq "2" "$STEP" "C23: two --reason step logs accumulate to 2"
assert_eq "1" "$SECTION" "C23: one --reason section log counts as 1"
assert_eq "section" "$LR" "C23: lastCheckpoint tracks the most recent reason"

# ============================================================
# C24: warn WITH checkpointStrategy restates the contract + names the gap
# ============================================================
reset_state
clear_checkpoint_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '
  .toolCallsByTranscript[$key] = 2 |
  .checkpointStrategy = {
    "progressLadder": {
      "step": ["log","plan-tick"],
      "section": ["log","plan-tick","run-tests"],
      "planComplete": ["scrutinize","snapshot"]
    }
  } |
  .checkpointCounters = {"step": 4, "section": 0}
' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
STASHED=$(jq -r '.pendingAllowInjections // [] | .[0].content // ""' "$TEST_SESSION/.state.json")
assert_eq "allow" "$DECISION" "C24: warns but allows at warn threshold with strategy"
assert_contains "contract:" "$STASHED" "C24: warn restates the committed contract"
assert_contains "steps 4" "$STASHED" "C24: warn names the step count from counters"
assert_contains "overdue" "$STASHED" "C24: warn names the gap (section overdue)"

# ============================================================
# C25: warn WITHOUT checkpointStrategy is generic (byte-compat back-guard)
# ============================================================
reset_state
clear_checkpoint_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 2' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
STASHED=$(jq -r '.pendingAllowInjections // [] | .[0].content // ""' "$TEST_SESSION/.state.json")
assert_eq "allow" "$DECISION" "C25: warns but allows at warn threshold (no strategy)"
assert_contains "CMD_APPEND_LOG" "$STASHED" "C25: generic warn still delivered"
assert_not_contains "contract:" "$STASHED" "C25: no contract line without a strategy"
assert_not_contains "overdue" "$STASHED" "C25: no gap line without a strategy"

# ============================================================
# C26: malformed checkpointStrategy degrades to generic (no crash)
# ============================================================
reset_state
clear_checkpoint_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 2 | .checkpointStrategy = "garbage-not-an-object"' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
STASHED=$(jq -r '.pendingAllowInjections // [] | .[0].content // ""' "$TEST_SESSION/.state.json")
assert_eq "allow" "$DECISION" "C26: malformed strategy does not crash the hook"
assert_contains "CMD_APPEND_LOG" "$STASHED" "C26: malformed strategy degrades to generic warn"
assert_not_contains "contract:" "$STASHED" "C26: malformed strategy emits no contract line"

# ============================================================
# C27: block-tier floor still fires unchanged (no strategy)
# ============================================================
reset_state
clear_checkpoint_state
TKEY=$(basename "$TRANSCRIPT_PATH")
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 9' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUTPUT=$(run_hook "Grep" '{"pattern":"test"}')
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
assert_eq "deny" "$DECISION" "C27: block-tier floor still fires unchanged"

# ============================================================
# Results
# ============================================================
exit_with_results
