#!/bin/bash
# tests/test-rule-engine.sh — Tests for the unified rule engine
#
# Tests:
#   Whitelist (W1-W3): hook-level whitelist integration (W4-W7 moved to hooks-validation.test.sh)
#   Per-Transcript (T1-T7): counter increment, isolation, triggers, reset, suppression, Task bypass
#   Session-Gate (G1-G5): lifecycle trigger, whitelist pass-through, dehydrating bypass
#   Heartbeat (H1-H5): warn at eq, block at gte, reset, loading bypass, tmux fallback
#   Rule Evaluation (E1-E7): trigger types, inject:once, priority, OVERFLOW_THRESHOLD
#   Composition (C1-C3): union whitelist, blocking+allow coexist, whitelist persistence
#   Preload Mode (P1-P2): evaluate_rules level (P3-P4 moved to hooks-validation.test.sh)
#   (A1-A5 directive auto-clear moved to hooks-validation.test.sh)
#
# Run: bash ~/.claude/engine/scripts/tests/test-rule-engine.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths before fake home
REAL_SCRIPTS_DIR="$HOME/.claude/scripts"
REAL_ENGINE_DIR="$HOME/.claude/engine"
REAL_HOOKS_DIR="$HOME/.claude/hooks"

TMP_DIR=$(mktemp -d)
export CLAUDE_SUPERVISOR_PID=99999999

setup_fake_home "$TMP_DIR"
disable_fleet_tmux

# Create engine dirs in fake home
mkdir -p "$FAKE_HOME/.claude/engine/hooks"
mkdir -p "$FAKE_HOME/.claude/engine/scripts"

# Symlink core scripts
ln -sf "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh"
ln -sf "$REAL_ENGINE_DIR/hooks/pre-tool-use-overflow-v2.sh" "$FAKE_HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"

# Stub fleet and search tools
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

# Work in TMP_DIR
cd "$TMP_DIR"

# Test session
TEST_SESSION="$TMP_DIR/sessions/test_rule_engine"
mkdir -p "$TEST_SESSION"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Source lib.sh for direct function testing
source "$FAKE_HOME/.claude/scripts/lib.sh"

# Helpers
write_injections() {
  echo "$1" > "$FAKE_HOME/.claude/engine/injections.json"
}

reset_state() {
  cat > "$TEST_SESSION/.state.json" <<STATEEOF
{
  "activePid": $$,
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "4: Build Loop",
  "contextUsage": 0,
  "injectedRules": {},
  "pendingInjections": [],
  "pendingDirectives": [],
  "toolUseWithoutLogs": 0,
  "toolUseWithoutLogsBlockAfter": 10,
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0
}
STATEEOF
}

# Activate session and clear loading flag
# (In production, /session continue calls session.sh continue to clear loading.
#  In tests, we clear it manually after activate.)
activate_session() {
  export CLAUDE_SUPERVISOR_PID=$$
  "$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" implement < /dev/null > /dev/null 2>&1 || true
  jq '.loading = false' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
    && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"
}

# Hook invocation helper — pipes JSON stdin to the hook and captures output
# Returns: hook stdout in $HOOK_OUT, exit code in $HOOK_EXIT
run_hook() {
  local tool_name="${1:-Read}" tool_input="${2:-{\}}" transcript="${3:-test-transcript}"
  local hook="$FAKE_HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
  local input
  input=$(jq -n \
    --arg tn "$tool_name" \
    --argjson ti "$tool_input" \
    --arg tp "/tmp/$transcript" \
    '{tool_name: $tn, tool_input: $ti, transcript_path: $tp}')

  HOOK_EXIT=0
  HOOK_OUT=$(echo "$input" | bash "$hook" 2>/dev/null) || HOOK_EXIT=$?
}

echo "======================================"
echo "Unified Rule Engine Tests"
echo "======================================"
echo ""

# ============================================================
# WHITELIST TESTS (W1-W7)
# ============================================================
echo "--- Whitelist Tests ---"

# W1: Tool matching whitelist allows through blocking injection
reset_state
write_injections '[{
  "id": "test-block",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "blocked" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
  "whitelist": ["AskUserQuestion", "Skill"]
}]'
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# AskUserQuestion is in the whitelist — should pass
run_hook "AskUserQuestion" '{}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "W1: Whitelisted tool passes through blocking injection"

# W2: Tool NOT matching whitelist gets blocked
reset_state
write_injections '[{
  "id": "test-block",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "blocked" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
  "whitelist": ["AskUserQuestion", "Skill"]
}]'
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

run_hook "Grep" '{"pattern": "foo"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "W2: Non-whitelisted tool gets blocked"

# W3: Union semantics — tool matching ANY rule's whitelist passes ALL rules
reset_state
write_injections '[
  {
    "id": "rule-a", "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
    "payload": { "text": "A" }, "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
    "whitelist": ["AskUserQuestion"]
  },
  {
    "id": "rule-b", "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
    "payload": { "text": "B" }, "mode": "inline", "urgency": "block", "priority": 3, "inject": "always",
    "whitelist": ["Skill"]
  }
]'
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# Skill only in rule-b's whitelist, but union merges both → Skill passes ALL rules
run_hook "Skill" '{"skill": "do"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "W3: Union whitelist — tool in any rule's whitelist passes all"

# W4-W7: Direct match_whitelist_entry function tests moved to hooks-validation.test.sh Group 6

echo ""

# ============================================================
# PER-TRANSCRIPT TESTS (T1-T7)
# ============================================================
echo "--- Per-Transcript Tests ---"

# T1: Counter increments per-transcript key
reset_state
activate_session

write_injections '[]'

run_hook "Read" '{"file_path": "/tmp/a.txt"}' "transcript-A"
COUNTER_A=$(jq -r '.toolCallsByTranscript["transcript-A"] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$COUNTER_A" "T1: Counter increments for transcript-A"

# T2: Different transcript keys have independent counters
run_hook "Read" '{"file_path": "/tmp/b.txt"}' "transcript-B"
COUNTER_B=$(jq -r '.toolCallsByTranscript["transcript-B"] // 0' "$TEST_SESSION/.state.json")
COUNTER_A2=$(jq -r '.toolCallsByTranscript["transcript-A"] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$COUNTER_B" "T2a: transcript-B gets its own counter"
assert_eq "1" "$COUNTER_A2" "T2b: transcript-A counter unchanged"

# T3: perTranscriptToolCount gte trigger matches at threshold
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 9}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# Evaluate rules with counter at 9, gte=10 → Read increments to 10 → gte matches
write_injections '[{
  "id": "gte-test",
  "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
  "payload": { "text": "blocked at gte 10" },
  "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
  "whitelist": ["Bash(engine log *)"]
}]'

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "T3: perTranscriptToolCount gte trigger blocks at threshold"

# T4: perTranscriptToolCount eq trigger fires exactly at target
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 2}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "eq-test",
  "trigger": { "type": "perTranscriptToolCount", "condition": { "eq": 3 } },
  "payload": { "text": "warn at eq 3" },
  "mode": "inline", "urgency": "allow", "priority": 50, "inject": "always"
}]'

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
HAS_REASON=$(jq -r '.pendingAllowInjections // [] | .[].content // ""' "$TEST_SESSION/.state.json" 2>/dev/null || echo "")
assert_eq "allow" "$DECISION" "T4a: eq trigger fires as allow at exactly eq=3"
assert_not_empty "$HAS_REASON" "T4b: eq trigger stashes content for PostToolUse delivery"

# Check it doesn't fire at 4 (not eq 3)
run_hook "Read" '{"file_path": "/tmp/bar.txt"}' "test-t"
DECISION2=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
HAS_REASON2=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
assert_eq "allow" "$DECISION2" "T4c: eq trigger does NOT fire at counter=4"
assert_empty "$HAS_REASON2" "T4d: no reason at counter=4 (eq didn't match)"

# T5: Counter resets on engine log command
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 8}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[]'

# Simulate engine log command (Bash tool with engine log)
# Note: The hook bypasses early for engine log — resets counter and allows
run_hook "Bash" '{"command": "engine log sessions/test/LOG.md <<EOF\ntest\nEOF"}' "test-t"
COUNTER_AFTER=$(jq -r '.toolCallsByTranscript["test-t"] // -1' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER_AFTER" "T5: Counter resets on engine log command"

# T6: Same-file edit suppression
reset_state
activate_session

write_injections '[]'

# First edit to file-x → counter=1
run_hook "Edit" '{"file_path": "/tmp/file-x.ts", "old_string": "a", "new_string": "b"}' "test-t"
C1=$(jq -r '.toolCallsByTranscript["test-t"] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$C1" "T6a: First edit to file increments counter"

# Second edit to SAME file → counter stays 1
run_hook "Edit" '{"file_path": "/tmp/file-x.ts", "old_string": "b", "new_string": "c"}' "test-t"
C2=$(jq -r '.toolCallsByTranscript["test-t"] // 0' "$TEST_SESSION/.state.json")
assert_eq "1" "$C2" "T6b: Same-file edit does NOT increment counter"

# Edit to DIFFERENT file → counter=2
run_hook "Edit" '{"file_path": "/tmp/file-y.ts", "old_string": "a", "new_string": "b"}' "test-t"
C3=$(jq -r '.toolCallsByTranscript["test-t"] // 0' "$TEST_SESSION/.state.json")
assert_eq "2" "$C3" "T6c: Different-file edit increments counter"

# T7: Task tool bypasses counter
reset_state
activate_session

write_injections '[]'

run_hook "Task" '{"prompt": "do stuff", "subagent_type": "general-purpose"}' "test-t"
COUNTER_TASK=$(jq -r '.toolCallsByTranscript["test-t"] // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER_TASK" "T7: Task tool does NOT increment counter"

echo ""

# ============================================================
# SESSION-GATE TESTS (G1-G5)
# ============================================================
echo "--- Session-Gate Tests ---"

# G1: No active session → blocks non-whitelisted tools
reset_state
activate_session
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "session-gate",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no active session" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
  "whitelist": ["AskUserQuestion", "Skill", "Bash(engine session *)"]
}]'

run_hook "Grep" '{"pattern": "foo"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "G1: No active session blocks non-whitelisted Grep"

# G2: Active session → session-gate doesn't fire
reset_state
activate_session

write_injections '[{
  "id": "session-gate",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no active session" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
  "whitelist": ["AskUserQuestion"]
}]'

run_hook "Grep" '{"pattern": "foo"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "G2: Active session allows all tools (session-gate doesn't fire)"

# G3: Completed session → gate re-engages
reset_state
activate_session
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "session-gate",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no active session" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
  "whitelist": ["AskUserQuestion"]
}]'

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "G3: Completed session re-engages gate (blocks Read)"

# G4: Whitelisted tools pass during gate
reset_state
activate_session
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "session-gate",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no active session" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
  "whitelist": ["AskUserQuestion", "Skill", "Bash(engine session *)"]
}]'

run_hook "AskUserQuestion" '{}' "test-t"
D1=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$D1" "G4a: AskUserQuestion passes during gate"

run_hook "Skill" '{"skill": "do"}' "test-t"
D2=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$D2" "G4b: Skill passes during gate"

# G5: Dehydrating lifecycle → allows all
reset_state
activate_session
jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "session-gate",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no active session" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always"
}]'

run_hook "Grep" '{"pattern": "anything"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "G5: Dehydrating lifecycle bypasses all rules"

echo ""

# ============================================================
# HEARTBEAT TESTS (H1-H5)
# ============================================================
echo "--- Heartbeat Tests ---"

# H1: Warn fires exactly at warn_after (eq trigger)
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 2}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "heartbeat-warn",
  "trigger": { "type": "perTranscriptToolCount", "condition": { "eq": 3 } },
  "payload": { "text": "Log soon" },
  "mode": "inline", "urgency": "allow", "priority": 50, "inject": "always",
  "whitelist": ["Bash(engine log *)"]
}]'

run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
REASON=$(jq -r '.pendingAllowInjections // [] | .[].content // ""' "$TEST_SESSION/.state.json" 2>/dev/null || echo "")
assert_eq "allow" "$DECISION" "H1a: Warn is allow (doesn't block)"
assert_contains "Log soon" "$REASON" "H1b: Warn message stashed for PostToolUse delivery"

# H2: Block fires at block_after (gte trigger)
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 9}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "heartbeat-block",
  "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
  "payload": { "text": "Must log now" },
  "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
  "whitelist": ["Bash(engine log *)"]
}]'

run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "H2: Block fires at gte threshold"

# H3: Counter reset clears both warn and block
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 15}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "heartbeat-block",
  "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
  "payload": { "text": "Must log" },
  "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
  "whitelist": ["Bash(engine log *)"]
}]'

# engine log resets counter
run_hook "Bash" '{"command": "engine log sessions/test/LOG.md <<EOF\ntest\nEOF"}' "test-t"

# After reset, Read should pass (counter back to 0)
run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "H3: After counter reset, tools pass again"

# H4: Loading lifecycle bypasses heartbeat counter
reset_state
activate_session
jq '.loading = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[]'

run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
COUNTER_LOADING=$(jq -r '.toolCallsByTranscript["test-t"] // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER_LOADING" "H4: Loading state skips counter increment"

# H5: Heartbeat block with engine log whitelisted — engine log passes
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 11}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "heartbeat-block",
  "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
  "payload": { "text": "Must log" },
  "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
  "whitelist": ["Bash(engine log *)"]
}]'

# engine log gets hardcoded bypass (before rules)
run_hook "Bash" '{"command": "engine log sessions/test/LOG.md <<EOF\ntest\nEOF"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "H5: engine log always passes (hardcoded bypass)"

echo ""

# ============================================================
# RULE EVALUATION TESTS (E1-E7)
# ============================================================
echo "--- Rule Evaluation Tests ---"

# E1: contextThreshold trigger
reset_state
jq '.contextUsage = 0.55' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "ctx-test",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
  "payload": { "text": "context threshold" },
  "mode": "inline", "urgency": "allow", "priority": 10, "inject": "once"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "1" "$COUNT" "E1: contextThreshold trigger matches"

# E2: lifecycle trigger
reset_state
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "lc-test",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no session" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "1" "$COUNT" "E2: lifecycle trigger matches when not active"

# E3: phase trigger
reset_state
jq '.currentPhase = "5: Synthesis"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "phase-test",
  "trigger": { "type": "phase", "condition": { "matches": "Synthesis" } },
  "payload": { "text": "synth" },
  "mode": "inline", "urgency": "allow", "priority": 30, "inject": "once"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "1" "$COUNT" "E3: phase trigger matches Synthesis"

# E4: discovery trigger
reset_state
jq '.pendingDirectives = ["/some/file.md"]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "disc-test",
  "trigger": { "type": "discovery", "condition": { "field": "pendingDirectives", "nonEmpty": true } },
  "payload": { "files": "$pendingDirectives" },
  "mode": "read", "urgency": "block", "priority": 20, "inject": "always"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "1" "$COUNT" "E4: discovery trigger matches non-empty pendingDirectives"

# E5: inject:once skips already-injected
reset_state
jq '.contextUsage = 0.55 | .injectedRules = {"ctx-test": true}' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "ctx-test",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
  "payload": { "text": "test" },
  "mode": "inline", "urgency": "allow", "priority": 10, "inject": "once"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "0" "$COUNT" "E5: inject:once skips already-injected rule"

# E6: Priority ordering
reset_state
jq '.contextUsage = 0.55 | .currentPhase = "5: Synthesis"' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {"id": "low-pri", "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
   "payload": { "text": "low" }, "mode": "inline", "urgency": "allow", "priority": 30, "inject": "once"},
  {"id": "high-pri", "trigger": { "type": "phase", "condition": { "matches": "Synthesis" } },
   "payload": { "text": "high" }, "mode": "inline", "urgency": "allow", "priority": 5, "inject": "once"}
]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
FIRST=$(echo "$RESULT" | jq -r '.[0].ruleId')
SECOND=$(echo "$RESULT" | jq -r '.[1].ruleId')
assert_eq "high-pri" "$FIRST" "E6a: Lower priority number first"
assert_eq "low-pri" "$SECOND" "E6b: Higher priority number second"

# E7: OVERFLOW_THRESHOLD reference resolved
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "overflow-ref",
  "trigger": { "type": "contextThreshold", "condition": { "gte": "OVERFLOW_THRESHOLD" } },
  "payload": { "command": "/session dehydrate restart" },
  "mode": "paste", "urgency": "block", "priority": 1, "inject": "always"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "1" "$COUNT" "E7: OVERFLOW_THRESHOLD reference resolved (0.80 >= 0.76)"

echo ""

# ============================================================
# COMPOSITION TESTS (C1-C3)
# ============================================================
echo "--- Composition Tests ---"

# C1: Multiple blocking rules — union whitelist prevents deadlock
reset_state
activate_session
jq '.lifecycle = "completed" | .toolCallsByTranscript = {"test-t": 15}' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {
    "id": "gate", "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
    "payload": { "text": "no session" },
    "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
    "whitelist": ["AskUserQuestion", "Bash(engine session *)"]
  },
  {
    "id": "heartbeat", "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
    "payload": { "text": "log now" },
    "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
    "whitelist": ["Bash(engine log *)"]
  }
]'

# engine log is in heartbeat whitelist; union includes it
# BUT engine log has hardcoded bypass so it passes before rules
# Test Bash(engine session *) — in gate whitelist, union includes it
run_hook "Bash" '{"command": "engine session activate sessions/test implement"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "C1: Union whitelist — engine session passes both gate+heartbeat"

# C2: Blocking + allow rules coexist — blocking takes priority
reset_state
activate_session
jq '.contextUsage = 0.55' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

# One blocking rule (no whitelist) + one allow rule both trigger
write_injections '[
  {
    "id": "blocker", "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
    "payload": { "text": "too much context" },
    "mode": "inline", "urgency": "block", "priority": 1, "inject": "always"
  },
  {
    "id": "guide", "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
    "payload": { "text": "guidance" },
    "mode": "inline", "urgency": "allow", "priority": 10, "inject": "always"
  }
]'

run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "C2: Blocking rule takes priority over allow rule"

# C3: Whitelisted tool passes blocking but still gets allow injection guidance
reset_state
activate_session
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {
    "id": "gate", "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
    "payload": { "text": "no session" },
    "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
    "whitelist": ["AskUserQuestion"]
  },
  {
    "id": "ctx-guide", "trigger": { "type": "contextThreshold", "condition": { "gte": 0.00 } },
    "payload": { "text": "context guidance" },
    "mode": "inline", "urgency": "allow", "priority": 50, "inject": "always"
  }
]'

run_hook "AskUserQuestion" '{}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
REASON=$(jq -r '.pendingAllowInjections // [] | .[].content // ""' "$TEST_SESSION/.state.json" 2>/dev/null || echo "")
assert_eq "allow" "$DECISION" "C3a: Whitelisted tool passes blocking"
assert_contains "context guidance" "$REASON" "C3b: Allow injection stashed for PostToolUse delivery"

echo ""

# ============================================================
# COMPOSITION EXTENSION TESTS (C4-C7)
# ============================================================
echo "--- Composition Extension Tests ---"

# C4: Union whitelist with non-bypass tool (AskUserQuestion) passes when gate+heartbeat both block
reset_state
activate_session
jq '.lifecycle = "completed" | .toolCallsByTranscript = {"test-t": 15}' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {
    "id": "gate", "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
    "payload": { "text": "no session" },
    "mode": "inline", "urgency": "block", "priority": 2, "inject": "always",
    "whitelist": ["AskUserQuestion", "Skill"]
  },
  {
    "id": "heartbeat", "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
    "payload": { "text": "log now" },
    "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
    "whitelist": ["Bash(engine log *)"]
  }
]'

# AskUserQuestion is in gate whitelist but NOT heartbeat whitelist
# Union merges both → AskUserQuestion passes ALL blocking rules
# Unlike C1 which tests engine session (hardcoded bypass), this tests true union path
run_hook "AskUserQuestion" '{}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "C4: Non-bypass tool (AskUserQuestion) passes via union whitelist"

# C5: Non-union tool blocked when gate+heartbeat both block
# Same setup as C4 — Grep is in neither whitelist
run_hook "Grep" '{"pattern": "foo"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "C5: Non-union tool (Grep) blocked when both rules fire"

# C6: Warn + block interaction — both rules present, block fires at gte=10
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 9}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {
    "id": "heartbeat-warn", "trigger": { "type": "perTranscriptToolCount", "condition": { "eq": 3 } },
    "payload": { "text": "Log soon" },
    "mode": "inline", "urgency": "allow", "priority": 50, "inject": "always",
    "whitelist": ["Bash(engine log *)"]
  },
  {
    "id": "heartbeat-block", "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
    "payload": { "text": "Must log" },
    "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
    "whitelist": ["Bash(engine log *)"]
  }
]'

# Counter=9 → Read increments to 10 → block fires (gte=10), warn doesn't match (eq=3 ≠ 10)
run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$DECISION" "C6: Block fires at gte=10 even when warn rule also present"

# C7: Warn fires at eq=3, then block fires at gte=10 — sequential escalation
reset_state
activate_session
jq '.toolCallsByTranscript = {"test-t": 2}' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {
    "id": "heartbeat-warn", "trigger": { "type": "perTranscriptToolCount", "condition": { "eq": 3 } },
    "payload": { "text": "Log soon" },
    "mode": "inline", "urgency": "allow", "priority": 50, "inject": "always",
    "whitelist": ["Bash(engine log *)"]
  },
  {
    "id": "heartbeat-block", "trigger": { "type": "perTranscriptToolCount", "condition": { "gte": 10 } },
    "payload": { "text": "Must log" },
    "mode": "inline", "urgency": "block", "priority": 5, "inject": "always",
    "whitelist": ["Bash(engine log *)"]
  }
]'

# Counter=2 → Read increments to 3 → warn fires (eq=3), allow
run_hook "Read" '{"file_path": "/tmp/a.txt"}' "test-t"
D1=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
R1=$(jq -r '.pendingAllowInjections // [] | .[].content // ""' "$TEST_SESSION/.state.json" 2>/dev/null || echo "")
assert_eq "allow" "$D1" "C7a: Warn fires at counter=3 (allow)"
assert_contains "Log soon" "$R1" "C7b: Warn message stashed for PostToolUse delivery"

# Now increment from 3 to 10 (7 more calls)
for i in $(seq 4 9); do
  run_hook "Read" '{"file_path": "/tmp/pad.txt"}' "test-t"
done

# Counter should be 9 now. One more → 10 → block
run_hook "Read" '{"file_path": "/tmp/final.txt"}' "test-t"
D2=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "deny" "$D2" "C7c: Block fires at counter=10 after escalation"

echo ""

# ============================================================
# DIRECT FUNCTION TESTS (F1-F4)
# ============================================================
echo "--- Direct Function Tests ---"

# F1: _primary_input_field() returns correct field for each tool
assert_eq "command" "$(_primary_input_field "Bash")" "F1a: Bash → command"
assert_eq "file_path" "$(_primary_input_field "Read")" "F1b: Read → file_path"
assert_eq "file_path" "$(_primary_input_field "Edit")" "F1c: Edit → file_path"
assert_eq "file_path" "$(_primary_input_field "Write")" "F1d: Write → file_path"
assert_eq "skill" "$(_primary_input_field "Skill")" "F1e: Skill → skill"
assert_eq "pattern" "$(_primary_input_field "Glob")" "F1f: Glob → pattern"
assert_eq "pattern" "$(_primary_input_field "Grep")" "F1g: Grep → pattern"
assert_eq "" "$(_primary_input_field "AskUserQuestion")" "F1h: Unknown tool → empty"
assert_eq "" "$(_primary_input_field "Task")" "F1i: Task → empty"

# F2: _track_delivered() marks blocking rules in injectedRules (integration via hook)
reset_state
activate_session
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "tracked-block",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "blocked" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always"
}]'

# Run hook — it will block and track the rule
run_hook "Grep" '{"pattern": "foo"}' "test-t"
TRACKED=$(jq -r '.injectedRules["tracked-block"] // "missing"' "$TEST_SESSION/.state.json")
assert_eq "true" "$TRACKED" "F2: Blocking rule tracked in injectedRules"

# F3: _track_delivered() marks allow rules too (integration via hook)
reset_state
activate_session
jq '.contextUsage = 0.55' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "tracked-allow",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
  "payload": { "text": "guidance" },
  "mode": "inline", "urgency": "allow", "priority": 10, "inject": "once"
}]'

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
TRACKED=$(jq -r '.injectedRules["tracked-allow"] // "missing"' "$TEST_SESSION/.state.json")
assert_eq "true" "$TRACKED" "F3: Allow rule tracked in injectedRules"

# F4: match_whitelist() with empty JSON array returns 1 (no match)
if match_whitelist '[]' "Read" '{"file_path": "/tmp/foo"}'; then
  fail "F4: Empty whitelist array should return 1 (no match)"
else
  pass "F4: Empty whitelist array returns 1 (no match)"
fi

echo ""

# ============================================================
# ERROR PATH TESTS (X1-X5)
# ============================================================
echo "--- Error Path Tests ---"

# X1: Missing injections.json — hook allows all
reset_state
activate_session
rm -f "$FAKE_HOME/.claude/engine/injections.json"

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "X1: Missing injections.json — hook allows all"

# X2: Empty injections.json array — hook allows all
reset_state
activate_session
write_injections '[]'

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "X2: Empty injections.json — hook allows all"

# X3: Malformed injections.json — hook allows all (graceful degradation)
reset_state
activate_session
echo "this is not json at all {{{" > "$FAKE_HOME/.claude/engine/injections.json"

run_hook "Read" '{"file_path": "/tmp/foo.txt"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "X3: Malformed injections.json — hook allows all (graceful degradation)"

# X4: Rule with unknown trigger type — skipped gracefully, other rules still evaluate
reset_state
activate_session
jq '.contextUsage = 0.55' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[
  {
    "id": "unknown-trigger",
    "trigger": { "type": "foobar", "condition": { "whatever": true } },
    "payload": { "text": "mystery" },
    "mode": "inline", "urgency": "block", "priority": 1, "inject": "always"
  },
  {
    "id": "valid-rule",
    "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
    "payload": { "text": "valid" },
    "mode": "inline", "urgency": "allow", "priority": 10, "inject": "once"
  }
]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
RULE_ID=$(echo "$RESULT" | jq -r '.[0].ruleId')
assert_eq "1" "$COUNT" "X4a: Unknown trigger type skipped, valid rule still evaluates"
assert_eq "valid-rule" "$RULE_ID" "X4b: Only valid rule in results"

# X5: Missing .state.json fields — defaults used
reset_state
# Write minimal state — only activePid and lifecycle
cat > "$TEST_SESSION/.state.json" <<STATEEOF
{
  "activePid": $$,
  "pid": $$,
  "lifecycle": "active"
}
STATEEOF

write_injections '[{
  "id": "ctx-default",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
  "payload": { "text": "test" },
  "mode": "inline", "urgency": "allow", "priority": 10, "inject": "once"
}]'

# contextUsage defaults to 0, so 0 >= 0.50 should NOT match
RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "0" "$COUNT" "X5: Missing contextUsage defaults to 0 (rule doesn't match)"

echo ""

# ============================================================
# LIFECYCLE BYPASS TESTS (L1-L2)
# ============================================================
echo "--- Lifecycle Bypass Tests ---"

# L1: Overflowed state skips heartbeat counter
reset_state
activate_session
jq '.overflowed = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[]'

run_hook "Read" '{"file_path": "/tmp/test.txt"}' "test-t"
COUNTER_OVF=$(jq -r '.toolCallsByTranscript["test-t"] // 0' "$TEST_SESSION/.state.json")
assert_eq "0" "$COUNTER_OVF" "L1: Overflowed state skips counter increment"

# L2: killRequested allows all tools (even with blocking rules)
reset_state
activate_session
jq '.killRequested = true' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "should-be-bypassed",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "blocked" },
  "mode": "inline", "urgency": "block", "priority": 2, "inject": "always"
}]'

run_hook "Grep" '{"pattern": "anything"}' "test-t"
DECISION=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
assert_eq "allow" "$DECISION" "L2: killRequested bypasses all rules"

echo ""

# ============================================================
# PRELOAD MODE TESTS (P1-P4)
# ============================================================
echo "--- Preload Mode Tests ---"

# Create a test standards file in fake home for preload tests
mkdir -p "$FAKE_HOME/.claude/.directives"
echo "# Test Standards Content" > "$FAKE_HOME/.claude/.directives/TEST_STANDARDS.md"
echo "This is test standards content for preload mode." >> "$FAKE_HOME/.claude/.directives/TEST_STANDARDS.md"

# P1: standards-preload rule matches when lifecycle=none (evaluate_rules level)
reset_state
jq '.lifecycle = "none" | .contextUsage = 0' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "standards-preload",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": {
    "preload": ["~/.claude/.directives/TEST_STANDARDS.md"]
  },
  "mode": "preload", "urgency": "allow", "priority": 3, "inject": "once"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
MODE=$(echo "$RESULT" | jq -r '.[0].mode // "none"')
assert_eq "1" "$COUNT" "P1a: standards-preload rule matches when lifecycle=none"
assert_eq "preload" "$MODE" "P1b: matched rule has mode=preload"

# P2: inject:once prevents re-injection after delivery
reset_state
jq '.lifecycle = "none" | .injectedRules = {"standards-preload": true}' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_injections '[{
  "id": "standards-preload",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": {
    "preload": ["~/.claude/.directives/TEST_STANDARDS.md"]
  },
  "mode": "preload", "urgency": "allow", "priority": 3, "inject": "once"
}]'

RESULT=$(evaluate_rules "$TEST_SESSION/.state.json" "$FAKE_HOME/.claude/engine/injections.json" "test-t")
COUNT=$(echo "$RESULT" | jq 'length')
assert_eq "0" "$COUNT" "P2: inject:once prevents re-injection after delivery"

# P3-P4: Preload content delivery tests moved to hooks-validation.test.sh Groups 4-5
# (Old tests used urgency:block delivery format which changed — now uses allow+PostToolUse stash)

echo ""

# ============================================================
# DYNAMIC PAYLOAD RESOLUTION TESTS (D1-D7)
# ============================================================
echo "--- Dynamic Payload Resolution Tests ---"

# D1: _resolve_payload_refs resolves $pendingDirectives from state
reset_state
activate_session
jq '.pendingDirectives = ["/tmp/dir1.md", "/tmp/dir2.md"]' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

PAYLOAD='{"preload": "$pendingDirectives"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
RESOLVED_TYPE=$(echo "$RESOLVED" | jq -r '.preload | type')
RESOLVED_LEN=$(echo "$RESOLVED" | jq '.preload | length')
RESOLVED_FIRST=$(echo "$RESOLVED" | jq -r '.preload[0]')
assert_eq "array" "$RESOLVED_TYPE" "D1a: \$pendingDirectives resolved to array"
assert_eq "2" "$RESOLVED_LEN" "D1b: Resolved array has 2 entries"
assert_eq "/tmp/dir1.md" "$RESOLVED_FIRST" "D1c: First entry matches state"

# D2: Non-$ values pass through unchanged
PAYLOAD='{"preload": ["static.md"], "text": "hello"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
STATIC_VAL=$(echo "$RESOLVED" | jq -r '.preload[0]')
TEXT_VAL=$(echo "$RESOLVED" | jq -r '.text')
assert_eq "static.md" "$STATIC_VAL" "D2a: Static array passes through"
assert_eq "hello" "$TEXT_VAL" "D2b: Non-$ string passes through"

# D3: $fieldName that doesn't exist in state resolves to original (null check)
PAYLOAD='{"preload": "$nonExistentField"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
RESOLVED_VAL=$(echo "$RESOLVED" | jq -r '.preload')
assert_eq '$nonExistentField' "$RESOLVED_VAL" "D3: Missing state field leaves $-ref unchanged"

# D4: Empty pendingDirectives resolves to empty array
jq '.pendingDirectives = []' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

PAYLOAD='{"preload": "$pendingDirectives"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
RESOLVED_LEN=$(echo "$RESOLVED" | jq '.preload | length')
assert_eq "0" "$RESOLVED_LEN" "D4: Empty pendingDirectives resolves to empty array"

# D5: Inline $var interpolation within string values
reset_state
activate_session
jq '.lifecycle = "completed" | .sessionDir = "sessions/FOO"' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

PAYLOAD='{"text": "status: $lifecycle, dir: $sessionDir"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
RESOLVED_TEXT=$(echo "$RESOLVED" | jq -r '.text')
assert_eq "status: completed, dir: sessions/FOO" "$RESOLVED_TEXT" "D5: Inline \$var interpolation resolves multiple vars in string"

# D6: Inline $var alongside whole-value $ref in same payload
reset_state
activate_session
jq '.pendingDirectives = ["/a.md"] | .lifecycle = "active"' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

PAYLOAD='{"preload": "$pendingDirectives", "text": "life: $lifecycle"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
RESOLVED_TYPE=$(echo "$RESOLVED" | jq -r '.preload | type')
RESOLVED_FIRST=$(echo "$RESOLVED" | jq -r '.preload[0]')
RESOLVED_TEXT=$(echo "$RESOLVED" | jq -r '.text')
assert_eq "array" "$RESOLVED_TYPE" "D6a: Whole-value \$ref resolved to array"
assert_eq "/a.md" "$RESOLVED_FIRST" "D6b: Whole-value array content correct"
assert_eq "life: active" "$RESOLVED_TEXT" "D6c: Inline \$var resolved in same payload"

# D7: Unknown inline $var left unchanged
reset_state
activate_session
PAYLOAD='{"text": "val: $unknownInlineField"}'
RESOLVED=$(_resolve_payload_refs "$PAYLOAD" "$TEST_SESSION/.state.json")
RESOLVED_TEXT=$(echo "$RESOLVED" | jq -r '.text')
assert_eq 'val: $unknownInlineField' "$RESOLVED_TEXT" "D7: Unknown inline \$var left unchanged"

echo ""

# ============================================================
# DIRECTIVE PRELOAD + AUTO-CLEAR TESTS (A1-A5)
# ============================================================
# A1-A5: Directive preload auto-clear tests moved to hooks-validation.test.sh Groups 4-5
# (Old tests used urgency:block — changed to urgency:allow in Fix 3b. V2 tests new behavior.)

echo ""

# ============================================================
# Results
# ============================================================
exit_with_results
