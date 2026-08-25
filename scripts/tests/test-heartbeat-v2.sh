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

# C17 removed: it asserted that a sub-agent is NOT heartbeat-blocked, a requirement
# the design reversed — sub-agents get their own budget and ARE blocked against it,
# which is what makes them log. The canonical assertion now lives in
# test-overflow-v2-subagent.sh S3/S3b. C18 below stays as the parent-side control.

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
# C19: Subagent counter does NOT overwrite global toolCallsSinceLastLog
# ============================================================
# A sub-agent fires this hook under the PARENT's transcript_path, so a different
# transcript path does NOT identify one — `agent_id` is the discriminator, and
# sub-agent state is namespaced `sub:<agent_id>`.
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
SUBAGENT_ID="agentC19"
SUBAGENT_KEY="sub:$SUBAGENT_ID"
# Establish parent's primary key + set counter
run_hook "Grep" '{"pattern":"test"}' > /dev/null
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 2 | .toolCallsSinceLastLog = 2' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# Subagent makes a call — should NOT overwrite toolCallsSinceLastLog
printf '{"tool_name":"Grep","tool_input":{"pattern":"test"},"session_id":"test","transcript_path":"%s","agent_id":"%s"}\n' \
  "$TRANSCRIPT_PATH" "$SUBAGENT_ID" | "$RESOLVED_HOOK" 2>/dev/null > /dev/null

GLOBAL_COUNTER=$(jq -r '.toolCallsSinceLastLog // 0' "$TEST_SESSION/.state.json")
SUBAGENT_COUNTER=$(jq -r --arg key "$SUBAGENT_KEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
assert_eq "2" "$GLOBAL_COUNTER" "C19: global counter preserved (subagent did not overwrite)"
assert_eq "1" "$SUBAGENT_COUNTER" "C19: subagent per-transcript counter incremented"

# ============================================================
# C19b: A SECOND PARENT transcript does not clobber the global either
# ============================================================
# Distinct from C19: no agent_id, so this is a parent — a restart or a second
# instance against the same session dir. 68/598 real sessions carry two-plus
# parent keys, so this is common, not exotic. Writing the global from a
# non-primary transcript REWINDS the primary's displayed count.
# Enforcement reads toolCallsByTranscript, so this is display-correctness only.
reset_state
TKEY=$(basename "$TRANSCRIPT_PATH")
SECOND_TKEY="second_parent_transcript.jsonl"
run_hook "Grep" '{"pattern":"test"}' > /dev/null   # stamps primaryTranscriptKey
jq --arg key "$TKEY" '.toolCallsByTranscript[$key] = 9 | .toolCallsSinceLastLog = 9' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

printf '{"tool_name":"Grep","tool_input":{"pattern":"test"},"session_id":"test","transcript_path":"%s"}\n' \
  "/tmp/$SECOND_TKEY" | "$RESOLVED_HOOK" 2>/dev/null > /dev/null

GLOBAL_AFTER=$(jq -r '.toolCallsSinceLastLog // 0' "$TEST_SESSION/.state.json")
SECOND_COUNTER=$(jq -r --arg key "$SECOND_TKEY" '.toolCallsByTranscript[$key] // 0' "$TEST_SESSION/.state.json")
PRIMARY_STILL=$(jq -r '.primaryTranscriptKey // ""' "$TEST_SESSION/.state.json")
assert_eq "9" "$GLOBAL_AFTER" "C19b: secondary parent transcript does not rewind the global"
assert_eq "1" "$SECOND_COUNTER" "C19b: secondary parent still advances its own counter"
assert_eq "$TKEY" "$PRIMARY_STILL" "C19b: primaryTranscriptKey unchanged by the secondary"

# ============================================================
# C20: heartbeat block-scope — the block fires ONLY on read tools (Read/Grep/Glob).
# Writes, Bash, and every MCP tool are NEVER blocked, even far past the threshold.
# (appliesTo:["Read","Grep","Glob"] on heartbeat-block — robust where a bypass whitelist
# can't be: the matcher can't glob tool names, so mcp__* is uncoverable by whitelist.)
# ============================================================
_dec() { echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow"; }
C20_TKEY=$(basename "$TRANSCRIPT_PATH")
set_count_high() {
  reset_state
  jq --arg k "$C20_TKEY" '.toolCallsByTranscript[$k] = 15' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

set_count_high; assert_eq "deny"  "$(_dec "$(run_hook "Read"  '{"file_path":"/x/f.ts"}')")"                       "C20a: Read IS blocked past threshold"
set_count_high; assert_eq "deny"  "$(_dec "$(run_hook "Grep"  '{"pattern":"x"}')")"                               "C20b: Grep IS blocked past threshold"
set_count_high; assert_eq "deny"  "$(_dec "$(run_hook "Glob"  '{"pattern":"*.ts"}')")"                            "C20c: Glob IS blocked past threshold"
set_count_high; assert_eq "allow" "$(_dec "$(run_hook "Bash"  '{"command":"echo hi"}')")"                         "C20d: Bash is NEVER blocked (exempt — can be a write)"
set_count_high; assert_eq "allow" "$(_dec "$(run_hook "Write" '{"file_path":"/x/f.ts","content":"c"}')")"         "C20e: Write is NEVER blocked"
set_count_high; assert_eq "allow" "$(_dec "$(run_hook "Edit"  '{"file_path":"/x/f.ts","old_string":"a","new_string":"b"}')")" "C20f: Edit is NEVER blocked"
set_count_high; assert_eq "allow" "$(_dec "$(run_hook "mcp__github__get_me" '{}')")"                              "C20g: MCP tool is NEVER blocked (whitelist can't glob mcp__*; block-scope handles it)"

# ============================================================
# C21: the warn nudge (count 3) is scoped to reads too — no nudge on a write, nudge on a read.
# ============================================================
reset_state
jq --arg k "$C20_TKEY" '.toolCallsByTranscript[$k] = 2 | .pendingAllowInjections = []' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
run_hook "Write" '{"file_path":"/x/f.ts","content":"c"}' > /dev/null
assert_eq "" "$(jq -r '[.pendingAllowInjections[]? | select(.ruleId=="heartbeat-warn")] | (.[0].ruleId // "")' "$TEST_SESSION/.state.json" 2>/dev/null || echo "")" "C21a: no heartbeat-warn nudge on a Write (warn scoped to reads)"

reset_state
jq --arg k "$C20_TKEY" '.toolCallsByTranscript[$k] = 2 | .pendingAllowInjections = []' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
run_hook "Grep" '{"pattern":"x"}' > /dev/null
assert_eq "heartbeat-warn" "$(jq -r '[.pendingAllowInjections[]? | select(.ruleId=="heartbeat-warn")] | (.[0].ruleId // "")' "$TEST_SESSION/.state.json" 2>/dev/null || echo "")" "C21b: warn DOES nudge on a Grep read (control)"

# ============================================================
# Results
# ============================================================
exit_with_results
