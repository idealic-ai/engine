#!/bin/bash
# tests/test-guard-framework.sh — Tests for evaluate-guards subcommand
#
# Tests:
#   A1. evaluate-guards writes pendingGuards when contextUsage >= threshold
#   A2. evaluate-guards respects inject:once — doesn't re-add if already in injectedRules
#   A3. evaluate-guards matches lifecycle trigger (noActiveSession)
#   A4. evaluate-guards matches phase trigger (Synthesis)
#   A5. evaluate-guards matches discovery trigger (pendingPreloads non-empty)
#   A6. evaluate-guards matches toolCount trigger
#   A7. Priority ordering — lower number first in pendingGuards
#   A8. evaluate-guards skips rules when no match
#   A9. evaluate-guards exits cleanly when no .state.json
#   A10. evaluate-guards resolves OVERFLOW_THRESHOLD reference
#
# Run: bash ~/.claude/engine/scripts/tests/test-guard-framework.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
CONFIG_SH="$HOME/.claude/engine/config.sh"

TMP_DIR=$(mktemp -d)

# Use a dead PID for isolation
export CLAUDE_SUPERVISOR_PID=99999999

# Create fake HOME to isolate
REAL_SESSION_SH="$SESSION_SH"
REAL_LIB_SH="$LIB_SH"
REAL_CONFIG_SH="$CONFIG_SH"

setup_fake_home "$TMP_DIR"
disable_fleet_tmux
unset DISABLE_AUTO_COMPACT 2>/dev/null || true

# Create engine dir in fake home
mkdir -p "$FAKE_HOME/.claude/engine"

# Symlink real scripts into fake home
ln -sf "$REAL_SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$REAL_LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$REAL_CONFIG_SH" "$FAKE_HOME/.claude/engine/config.sh"

# Stub fleet and search tools
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

# Work in TMP_DIR so session.sh find scans our test sessions
cd "$TMP_DIR"

# Test session
TEST_SESSION="$TMP_DIR/sessions/test_guard"
mkdir -p "$TEST_SESSION"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Helper: create a minimal guards.json with specific rules
write_guards() {
  local content="$1"
  echo "$content" > "$FAKE_HOME/.claude/engine/guards.json"
}

# Helper: reset .state.json to a known state
reset_state() {
  cat > "$TEST_SESSION/.state.json" <<STATEEOF
{
  "activePid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "4: Build Loop",
  "contextUsage": 0,
  "injectedRules": {},
  "pendingGuards": [],
  "pendingPreloads": [],
  "toolUseWithoutLogs": 0,
  "toolUseWithoutLogsBlockAfter": 10
}
STATEEOF
}

echo "======================================"
echo "Guard Framework Tests (evaluate-guards)"
echo "======================================"
echo ""

# --- Setup: activate test session ---
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" implement < /dev/null > /dev/null 2>&1

# ============================================================
# A1: contextThreshold trigger matches when contextUsage >= threshold
# ============================================================
reset_state
jq '.contextUsage = 0.55' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-threshold",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
  "payload": { "text": "test content" },
  "mode": "inline",
  "urgency": "allow",
  "priority": 10,
  "inject": "once"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "1" "$PENDING" "A1: contextThreshold trigger populates pendingGuards"

RULE_ID=$(jq -r '.pendingGuards[0].ruleId' "$TEST_SESSION/.state.json")
assert_eq "test-threshold" "$RULE_ID" "A1: correct ruleId in pendingGuards"

# ============================================================
# A2: inject:once skips already-injected rules
# ============================================================
reset_state
jq '.contextUsage = 0.55 | .injectedRules = {"test-threshold": true}' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-threshold",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
  "payload": { "text": "test content" },
  "mode": "inline",
  "urgency": "allow",
  "priority": 10,
  "inject": "once"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "0" "$PENDING" "A2: inject:once skips already-injected rule"

# ============================================================
# A3: lifecycle trigger (noActiveSession)
# ============================================================
reset_state
jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-lifecycle",
  "trigger": { "type": "lifecycle", "condition": { "noActiveSession": true } },
  "payload": { "text": "no session active" },
  "mode": "inline",
  "urgency": "block",
  "priority": 0,
  "inject": "always"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "1" "$PENDING" "A3: lifecycle trigger matches when lifecycle != active"

# ============================================================
# A4: phase trigger matches when currentPhase contains pattern
# ============================================================
reset_state
jq '.currentPhase = "5: Synthesis"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-phase",
  "trigger": { "type": "phase", "condition": { "matches": "Synthesis" } },
  "payload": { "text": "synthesis commands" },
  "mode": "inline",
  "urgency": "allow",
  "priority": 30,
  "inject": "once"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "1" "$PENDING" "A4: phase trigger matches Synthesis"

RULE_ID=$(jq -r '.pendingGuards[0].ruleId' "$TEST_SESSION/.state.json")
assert_eq "test-phase" "$RULE_ID" "A4: correct phase rule matched"

# ============================================================
# A5: discovery trigger (pendingPreloads non-empty)
# ============================================================
reset_state
jq '.pendingPreloads = ["/some/file.md"]' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-discovery",
  "trigger": { "type": "discovery", "condition": { "field": "pendingPreloads", "nonEmpty": true } },
  "payload": { "files": ["$pendingPreloads"] },
  "mode": "read",
  "urgency": "block",
  "priority": 20,
  "inject": "always"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "1" "$PENDING" "A5: discovery trigger matches non-empty pendingPreloads"

# ============================================================
# A6: toolCount trigger
# ============================================================
reset_state
jq '.toolUseWithoutLogs = 15 | .toolUseWithoutLogsBlockAfter = 10' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-toolcount",
  "trigger": { "type": "toolCount", "condition": { "field": "toolUseWithoutLogs", "gte": "toolUseWithoutLogsBlockAfter" } },
  "payload": { "command": "log now" },
  "mode": "paste",
  "urgency": "interrupt",
  "priority": 5,
  "inject": "always"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "1" "$PENDING" "A6: toolCount trigger matches when counter >= threshold"

# ============================================================
# A7: Priority ordering — lower number first
# ============================================================
reset_state
jq '.contextUsage = 0.55 | .currentPhase = "5: Synthesis"' \
  "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[
  {
    "id": "high-priority",
    "trigger": { "type": "contextThreshold", "condition": { "gte": 0.50 } },
    "payload": { "text": "high" },
    "mode": "inline", "urgency": "allow", "priority": 5, "inject": "once"
  },
  {
    "id": "low-priority",
    "trigger": { "type": "phase", "condition": { "matches": "Synthesis" } },
    "payload": { "text": "low" },
    "mode": "inline", "urgency": "allow", "priority": 30, "inject": "once"
  }
]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

FIRST=$(jq -r '.pendingGuards[0].ruleId' "$TEST_SESSION/.state.json")
SECOND=$(jq -r '.pendingGuards[1].ruleId' "$TEST_SESSION/.state.json")
assert_eq "high-priority" "$FIRST" "A7: lower priority number comes first"
assert_eq "low-priority" "$SECOND" "A7: higher priority number comes second"

# ============================================================
# A8: No match — pendingGuards stays empty
# ============================================================
reset_state

write_guards '[{
  "id": "test-no-match",
  "trigger": { "type": "contextThreshold", "condition": { "gte": 0.90 } },
  "payload": { "text": "wont match" },
  "mode": "inline",
  "urgency": "allow",
  "priority": 10,
  "inject": "once"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "0" "$PENDING" "A8: no match leaves pendingGuards empty"

# ============================================================
# A9: exits cleanly when no .state.json
# ============================================================
EMPTY_SESSION="$TMP_DIR/sessions/empty_session"
mkdir -p "$EMPTY_SESSION"

OUTPUT=$("$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$EMPTY_SESSION" 2>&1 || true)
pass "A9: exits cleanly when no .state.json (no crash)"

# ============================================================
# A10: OVERFLOW_THRESHOLD reference resolved
# ============================================================
reset_state
jq '.contextUsage = 0.80' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

write_guards '[{
  "id": "test-overflow-ref",
  "trigger": { "type": "contextThreshold", "condition": { "gte": "OVERFLOW_THRESHOLD" } },
  "payload": { "command": "/session dehydrate restart" },
  "mode": "paste",
  "urgency": "block",
  "priority": 1,
  "inject": "always"
}]'

"$FAKE_HOME/.claude/scripts/session.sh" evaluate-guards "$TEST_SESSION" > /dev/null 2>&1

PENDING=$(jq '.pendingGuards | length' "$TEST_SESSION/.state.json")
assert_eq "1" "$PENDING" "A10: OVERFLOW_THRESHOLD reference resolved (0.80 >= 0.76)"

# ============================================================
# Results
# ============================================================
exit_with_results
