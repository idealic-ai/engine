#!/bin/bash
# tests/test-overflow-v2-subagent.sh — Sub-agent isolation for pre-tool-use-overflow-v2.sh
#
# Regression guard for session-scoped hook state bleeding into ephemeral sub-agents.
# Sub-agent tool calls fire PreToolUse under the PARENT's transcript_path but carry a
# populated `agent_id`; the parent's own calls have no `agent_id`. The hook must key
# off `agent_id`, not the transcript, so that:
#   - sub-agent calls never touch the parent's heartbeat budget (Problem 1)
#   - sub-agent calls never inherit the parent's contextUsage / overflow (Problem 2)
#   - the PARENT path is unchanged (heartbeat + overflow still enforced)
#
# Cases:
#   S1  sub-agent Bash call does NOT increment the parent's global toolCallsSinceLastLog
#   S2  sub-agent counter lands under toolCallsByTranscript["sub:<id>"], not the parent key
#   S3  sub-agent call at its own count 10+ is ALLOWED (heartbeat-block downgraded)
#   S4  sub-agent Read at contextUsage 0.94 is ALLOWED (read-throttle dropped)
#   S5  sub-agent Bash at contextUsage 0.80 is ALLOWED (overflow-dehydration dropped)
#   S6  PARENT call at per-transcript count 10+ is STILL blocked (regression)
#   S7  PARENT Read at contextUsage 0.94 is STILL blocked (regression)
#   S8  fan-out: 3 distinct agent_ids each track independently; parent global untouched
#
# Run: bash ~/.claude/engine/scripts/tests/test-overflow-v2-subagent.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
POST_HOOK="$HOME/.claude/engine/hooks/post-tool-use-injections.sh"
SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"
GUARDS_JSON="$HOME/.claude/engine/guards.json"

TMP_DIR=$(mktemp -d)
export CLAUDE_SUPERVISOR_PID=99999999
unset DISABLE_AUTO_COMPACT 2>/dev/null || true

REAL_HOOK="$HOOK"
REAL_POST_HOOK="$POST_HOOK"
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
ln -sf "$REAL_POST_HOOK" "$FAKE_HOME/.claude/hooks/post-tool-use-injections.sh"

mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

cd "$TMP_DIR"

TEST_SESSION="$TMP_DIR/sessions/test_overflow_v2_subagent"
mkdir -p "$TEST_SESSION"

RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Parent tool call: no agent_id (matches Claude Code's parent-call input shape).
run_hook() {
  local tool_name="$1" tool_input="${2:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s,"session_id":"test","transcript_path":"/tmp/test.jsonl"}\n' \
    "$tool_name" "$tool_input" | "$RESOLVED_HOOK" 2>/dev/null
}

# Sub-agent tool call: populated agent_id + agent_type, under the PARENT's transcript_path
# (this is exactly what Claude Code sends for a sub-agent's tool call).
run_hook_sub() {
  local agent_id="$1" tool_name="$2" tool_input="${3:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s,"session_id":"test","transcript_path":"/tmp/test.jsonl","agent_id":"%s","agent_type":"general-purpose"}\n' \
    "$tool_name" "$tool_input" "$agent_id" | "$RESOLVED_HOOK" 2>/dev/null
}

# Reset to a running parent session that has already established its transcript.
reset_state() {
  jq '.lifecycle = "active" | .killRequested = false | .contextUsage = 0 |
      .loading = false | del(.overflowed) | .injectedRules = {} |
      .pendingAllowInjections = [] | .toolCallsByTranscript = {} |
      .toolCallsSinceLastLog = 0 | .pendingPreloads = [] |
      .touchedDirs = {} | .primaryTranscriptKey = "test.jsonl"' \
    "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

set_state() {
  jq "$1" "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

decision_of() {
  echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow"
}

# PostToolUse injection-delivery hook, called as parent ("") or a sub-agent (agent_id).
run_post_hook() {
  local agent_id="$1"
  if [ -n "$agent_id" ]; then
    printf '{"tool_name":"Bash","tool_input":{},"transcript_path":"/tmp/test.jsonl","agent_id":"%s"}\n' "$agent_id" \
      | "$FAKE_HOME/.claude/hooks/post-tool-use-injections.sh" 2>/dev/null
  else
    printf '{"tool_name":"Bash","tool_input":{},"transcript_path":"/tmp/test.jsonl"}\n' \
      | "$FAKE_HOME/.claude/hooks/post-tool-use-injections.sh" 2>/dev/null
  fi
}

json_get() { jq -r "$1" "$TEST_SESSION/.state.json" 2>/dev/null || echo ""; }

echo "======================================"
echo "Overflow V2 — Sub-agent Isolation Tests"
echo "======================================"
echo ""

export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" implement < /dev/null > /dev/null 2>&1

# ============================================================
# S1: sub-agent call does not touch the parent's global counter
# ============================================================
reset_state
run_hook_sub "agentA" "Bash" '{"command":"echo hi"}' > /dev/null
GLOBAL=$(jq -r '.toolCallsSinceLastLog // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$GLOBAL" "S1: sub-agent call leaves parent toolCallsSinceLastLog at 0"

# ============================================================
# S2: sub-agent counter is namespaced by agent_id, parent key untouched
# ============================================================
reset_state
run_hook_sub "agentA" "Bash" '{"command":"echo hi"}' > /dev/null
SUB=$(jq -r '.toolCallsByTranscript["sub:agentA"] // 0' "$TEST_SESSION/.state.json")
PARENTKEY=$(jq -r '.toolCallsByTranscript["test.jsonl"] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$SUB" "S2a: sub-agent counter under sub:agentA"
assert_eq "0" "$PARENTKEY" "S2b: parent transcript counter untouched by sub-agent"

# ============================================================
# S3: sub-agent IS heartbeat-blocked at its OWN count 10+ (own-counter heartbeat — forces it to log)
# ============================================================
reset_state
set_state '.toolCallsByTranscript["sub:agentA"] = 10'
OUT=$(run_hook_sub "agentA" "Bash" '{"command":"echo hi"}')
assert_eq "deny" "$(decision_of "$OUT")" "S3: sub-agent IS heartbeat-blocked at its own count 10+"

# S3b: a DIFFERENT sub-agent is not blocked by agentA's count (independent counters)
reset_state
set_state '.toolCallsByTranscript["sub:agentA"] = 10'
OUT=$(run_hook_sub "agentB" "Bash" '{"command":"echo hi"}')
assert_eq "allow" "$(decision_of "$OUT")" "S3b: a different sub-agent (agentB) not blocked by agentA's count"

# S3c: the PARENT is not blocked by a sub-agent's count
reset_state
set_state '.toolCallsByTranscript["sub:agentA"] = 10'
OUT=$(run_hook "Bash" '{"command":"echo hi"}')
assert_eq "allow" "$(decision_of "$OUT")" "S3c: parent not blocked by a sub-agent's count"

# ============================================================
# S4: sub-agent Read at high context is allowed (read-throttle dropped)
# ============================================================
reset_state
set_state '.contextUsage = 0.94'
OUT=$(run_hook_sub "agentA" "Read" '{"file_path":"/some/file.ts"}')
assert_eq "allow" "$(decision_of "$OUT")" "S4: sub-agent Read not read-throttled at 0.94"

# ============================================================
# S5: sub-agent at overflow threshold is allowed (overflow-dehydration dropped)
# ============================================================
reset_state
set_state '.contextUsage = 0.80'
OUT=$(run_hook_sub "agentA" "Bash" '{"command":"echo hi"}')
assert_eq "allow" "$(decision_of "$OUT")" "S5: sub-agent not overflow-blocked at 0.80"

# ============================================================
# S6 (regression): PARENT still heartbeat-blocked at count 10+
# ============================================================
reset_state
set_state '.toolCallsByTranscript["test.jsonl"] = 10'
OUT=$(run_hook "Bash" '{"command":"echo hi"}')
assert_eq "deny" "$(decision_of "$OUT")" "S6: parent STILL heartbeat-blocked at count 10+"

# ============================================================
# S7 (regression): PARENT still read-throttled/overflow at high context
# ============================================================
reset_state
set_state '.contextUsage = 0.94'
OUT=$(run_hook "Read" '{"file_path":"/some/file.ts"}')
assert_eq "deny" "$(decision_of "$OUT")" "S7: parent STILL blocked (overflow/read-throttle) at 0.94"

# ============================================================
# S8 (fan-out): 3 agents track independently, parent global untouched
# ============================================================
reset_state
run_hook_sub "agA" "Bash" '{"command":"echo 1"}' > /dev/null
run_hook_sub "agB" "Bash" '{"command":"echo 2"}' > /dev/null
run_hook_sub "agC" "Bash" '{"command":"echo 3"}' > /dev/null
A=$(jq -r '.toolCallsByTranscript["sub:agA"] // 0' "$TEST_SESSION/.state.json")
B=$(jq -r '.toolCallsByTranscript["sub:agB"] // 0' "$TEST_SESSION/.state.json")
C=$(jq -r '.toolCallsByTranscript["sub:agC"] // 0' "$TEST_SESSION/.state.json")
GLOBAL=$(jq -r '.toolCallsSinceLastLog // 0' "$TEST_SESSION/.state.json")
PKEY=$(jq -r '.toolCallsByTranscript["test.jsonl"] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$A" "S8a: agA tracked independently"
assert_eq "1" "$B" "S8b: agB tracked independently"
assert_eq "1" "$C" "S8c: agC tracked independently"
assert_eq "0" "$GLOBAL" "S8d: parent global untouched across fan-out"
assert_eq "0" "$PKEY" "S8e: parent transcript counter untouched across fan-out"

# ============================================================
# S9: a sub-agent's `engine log` resets ONLY its own sub:<id> counter
#     (so a blocked sub-agent can escape by logging; parent's counters untouched)
# ============================================================
reset_state
set_state '.toolCallsByTranscript["sub:agentA"] = 10 | .toolCallsSinceLastLog = 5 | .toolCallsByTranscript["test.jsonl"] = 5'
OUT=$(run_hook_sub "agentA" "Bash" '{"command":"engine log sessions/x/LOG.md <<EOF\n## t\nEOF"}')
assert_eq "allow" "$(decision_of "$OUT")" "S9: sub-agent engine log is allowed (bypass)"
assert_eq "0" "$(json_get '.toolCallsByTranscript["sub:agentA"] // 0')" "S9a: sub-agent log reset its OWN counter to 0"
assert_eq "5" "$(json_get '.toolCallsSinceLastLog // 0')" "S9b: sub-agent log did NOT reset the parent global"
assert_eq "5" "$(json_get '.toolCallsByTranscript["test.jsonl"] // 0')" "S9c: sub-agent log did NOT reset the parent transcript counter"

# ============================================================
# S10: a sub-agent's heartbeat-warn nudge (fires at count==3) is stashed tagged with its agent_id
# ============================================================
reset_state
set_state '.toolCallsByTranscript["sub:agentA"] = 2'
OUT=$(run_hook_sub "agentA" "Bash" '{"command":"echo hi"}')
assert_eq "allow" "$(decision_of "$OUT")" "S10: sub-agent warn is allow (not blocked)"
assert_eq "agentA" "$(json_get '.pendingAllowInjections[0].agentId // ""')" "S10a: sub-agent nudge tagged with its own agentId"

# ============================================================
# S11: PostToolUse drain is agent-scoped — a sub-agent's nudge is not swept into the parent
# ============================================================
reset_state
set_state '.pendingAllowInjections = [{"ruleId":"heartbeat-warn","content":"nudge-for-A","agentId":"agentA"}]'
PARENT_OUT=$(run_post_hook "")
assert_eq "1" "$(json_get '.pendingAllowInjections | length')" "S11a: parent drain leaves the sub-agent's nudge queued"
assert_not_contains "nudge-for-A" "$PARENT_OUT" "S11b: parent did NOT receive the sub-agent's nudge"
SUB_OUT=$(run_post_hook "agentA")
assert_eq "0" "$(json_get '.pendingAllowInjections | length')" "S11c: the owning sub-agent drains its own nudge"
assert_contains "nudge-for-A" "$SUB_OUT" "S11d: sub-agent received its own nudge"

# ============================================================
# S12: a sub-agent's Read does NOT claim a directory (parent keeps its directive autoload)
# ============================================================
reset_state
run_hook_sub "agentA" "Read" '{"file_path":"/some/dir/file.ts"}' > /dev/null
assert_eq "false" "$(json_get '(.touchedDirs // {}) | has("/some/dir")')" "S12: sub-agent Read did NOT claim /some/dir"
reset_state
run_hook "Read" '{"file_path":"/some/dir/file.ts"}' > /dev/null
assert_eq "true" "$(json_get '(.touchedDirs // {}) | has("/some/dir")')" "S12b: parent Read DOES claim /some/dir (control)"

# ============================================================
# S13: a sub-agent's Edit uses its own namespaced lastEditFile key (can't stall the parent)
# ============================================================
reset_state
run_hook_sub "agentA" "Edit" '{"file_path":"/x/f.ts"}' > /dev/null
assert_eq "/x/f.ts" "$(json_get '.["lastEditFile_sub:agentA"] // ""')" "S13a: sub-agent Edit recorded under lastEditFile_sub:agentA"
assert_eq "" "$(json_get '.["lastEditFile_test.jsonl"] // ""')" "S13b: sub-agent Edit did NOT write the parent's lastEditFile key"

# ============================================================
# S14: contract canary — the hook must still read the discriminator field named `agent_id`.
# A silent upstream rename reverts isolation to full bleed with every fabricated-input test green.
# ============================================================
if grep -qE '\.agent_id' "$REAL_HOOK"; then
  pass "S14: hook still reads the .agent_id discriminator (contract pinned)"
else
  fail "S14: hook no longer references .agent_id — isolation reverts to full bleed (see PTF_SESSION_HOOK_STATE_BLEEDS_TO_SUBAGENTS)"
fi

exit_with_results
