#!/bin/bash
# tests/test-phase-enforcement.sh — Tests for session.sh phase enforcement
# Run: bash ~/.claude/engine/scripts/tests/test-phase-enforcement.sh

set -uo pipefail

SESSION_SH="$HOME/.claude/scripts/session.sh"
TMP_DIR=$(mktemp -d)
TEST_DIR="$TMP_DIR/sessions/test_session"
STATE_FILE="$TEST_DIR/.state.json"
PASS=0
FAIL=0

# Helper: create a fresh state file with phases
reset_state() {
  local current_phase="${1:-1: Setup}"
  mkdir -p "$TEST_DIR"
  cat > "$STATE_FILE" <<AGENTEOF
{
  "pid": 99999,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "$current_phase",
  "phases": [
    {"major": 1, "minor": 0, "name": "Setup"},
    {"major": 2, "minor": 0, "name": "Context Ingestion"},
    {"major": 3, "minor": 0, "name": "Interrogation"},
    {"major": 4, "minor": 0, "name": "Planning"},
    {"major": 5, "minor": 0, "name": "Build Loop"},
    {"major": 6, "minor": 0, "name": "Synthesis"}
  ],
  "phaseHistory": ["$current_phase"]
}
AGENTEOF
}

# Helper: create state file with sub-phases declared
reset_state_with_subphases() {
  local current_phase="${1:-1: Setup}"
  mkdir -p "$TEST_DIR"
  cat > "$STATE_FILE" <<AGENTEOF
{
  "pid": 99999,
  "skill": "test",
  "lifecycle": "active",
  "currentPhase": "$current_phase",
  "phases": [
    {"major": 1, "minor": 0, "name": "Setup"},
    {"major": 2, "minor": 0, "name": "Context Ingestion"},
    {"major": 3, "minor": 0, "name": "Strategy"},
    {"major": 3, "minor": 1, "name": "Agent Handoff"},
    {"major": 4, "minor": 0, "name": "Testing Loop"},
    {"major": 5, "minor": 0, "name": "Synthesis"}
  ],
  "phaseHistory": ["$current_phase"]
}
AGENTEOF
}

# Helper: create state file WITHOUT phases (backward compat)
reset_state_no_phases() {
  local current_phase="${1:-Phase 3: Execution}"
  mkdir -p "$TEST_DIR"
  cat > "$STATE_FILE" <<AGENTEOF
{
  "pid": 99999,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "$current_phase"
}
AGENTEOF
}

# Helper: assert command succeeds
assert_ok() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected success, got failure)"
    ((FAIL++))
  fi
}

# Helper: assert command fails
assert_fail() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  FAIL: $desc (expected failure, got success)"
    ((FAIL++))
  else
    echo "  PASS: $desc"
    ((PASS++))
  fi
}

# Helper: assert JSON field equals value
assert_json() {
  local desc="$1" field="$2" expected="$3"
  local actual
  actual=$(jq -r "$field" "$STATE_FILE" 2>/dev/null || echo "ERROR")
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++))
  fi
}

echo "=== Phase Enforcement Tests ==="
echo ""

# --- Sequential Forward ---
echo "--- Sequential Forward ---"
reset_state "1: Setup"
assert_ok "1→2 sequential forward" \
  "$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion"
assert_json "currentPhase updated to 2" '.currentPhase' '2: Context Ingestion'

assert_ok "2→3 sequential forward" \
  "$SESSION_SH" phase "$TEST_DIR" "3: Interrogation"

assert_ok "3→4 sequential forward" \
  "$SESSION_SH" phase "$TEST_DIR" "4: Planning"

assert_ok "4→5 sequential forward" \
  "$SESSION_SH" phase "$TEST_DIR" "5: Build Loop"

assert_ok "5→6 sequential forward" \
  "$SESSION_SH" phase "$TEST_DIR" "6: Synthesis"

echo ""

# --- Skip Forward ---
echo "--- Skip Forward ---"
reset_state "1: Setup"
assert_fail "1→3 skip without approval" \
  "$SESSION_SH" phase "$TEST_DIR" "3: Interrogation"

assert_ok "1→3 skip with approval" \
  "$SESSION_SH" phase "$TEST_DIR" "3: Interrogation" --user-approved "User said: 'Skip to Phase 3' in response to 'How to proceed?'"
assert_json "currentPhase updated to 3" '.currentPhase' '3: Interrogation'

reset_state "1: Setup"
assert_fail "1→6 big skip without approval" \
  "$SESSION_SH" phase "$TEST_DIR" "6: Synthesis"

assert_ok "1→6 big skip with approval" \
  "$SESSION_SH" phase "$TEST_DIR" "6: Synthesis" --user-approved "User said: 'Jump to synthesis' in response to 'Ready?'"

echo ""

# --- Backward ---
echo "--- Backward ---"
reset_state "4: Planning"
assert_fail "4→2 backward without approval" \
  "$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion"

assert_ok "4→2 backward with approval" \
  "$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion" --user-approved "User said: 'Go back to context' in response to 'Plan ready?'"
assert_json "currentPhase updated to 2" '.currentPhase' '2: Context Ingestion'

echo ""

# --- Sub-phase Auto-Append ---
echo "--- Sub-phase Auto-Append ---"
reset_state "4: Planning"
assert_ok "4→4.1 sub-phase auto-append" \
  "$SESSION_SH" phase "$TEST_DIR" "4.1: Agent Handoff"
assert_json "currentPhase updated to 4.1" '.currentPhase' '4.1: Agent Handoff'

# Verify 4.1 was inserted into phases array
assert_json "4.1 in phases array" \
  '[.phases[] | select(.major == 4 and .minor == 1)] | length' '1'

assert_ok "4.1→4.2 sub-phase chain" \
  "$SESSION_SH" phase "$TEST_DIR" "4.2: Review"
assert_json "currentPhase updated to 4.2" '.currentPhase' '4.2: Review'

# After sub-phases, should be able to go to next major phase (5)
assert_ok "4.2→5 forward to next major" \
  "$SESSION_SH" phase "$TEST_DIR" "5: Build Loop"

echo ""

# --- Sub-phase Skippability ---
# Sub-phases are optional alternative paths. Major phases are sequential.
# Rule: Skip sub-phases to next major = OK. Skip a major = requires --user-approved.
echo "--- Sub-phase Skippability ---"

# Skip declared sub-phase 3.1 to go to next major 4 (should be allowed)
reset_state_with_subphases "3: Strategy"
assert_ok "3→4 skip declared sub-phase 3.1 to next major" \
  "$SESSION_SH" phase "$TEST_DIR" "4: Testing Loop"
assert_json "currentPhase updated to 4" '.currentPhase' '4: Testing Loop'

# Enter sub-phase then skip to next major (should be allowed)
reset_state_with_subphases "3: Strategy"
"$SESSION_SH" phase "$TEST_DIR" "3.1: Agent Handoff" > /dev/null 2>&1
assert_ok "3.1→4 from sub-phase to next major" \
  "$SESSION_SH" phase "$TEST_DIR" "4: Testing Loop"

# Skip major 4 entirely from 3 (should FAIL — major skip)
reset_state_with_subphases "3: Strategy"
assert_fail "3→5 skip entire major 4 without approval" \
  "$SESSION_SH" phase "$TEST_DIR" "5: Synthesis"

# Sub-phases within same major: free movement (any order)
reset_state_with_subphases "3: Strategy"
assert_ok "3.0→3.1 forward sub-phase" \
  "$SESSION_SH" phase "$TEST_DIR" "3.1: Agent Handoff"

# From a sub-phase, should reach the next major without needing approval
reset_state_with_subphases "1: Setup"
"$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion" > /dev/null 2>&1
"$SESSION_SH" phase "$TEST_DIR" "3: Strategy" > /dev/null 2>&1
"$SESSION_SH" phase "$TEST_DIR" "3.1: Agent Handoff" > /dev/null 2>&1
assert_ok "3.1→4 sequential after entering sub-phase" \
  "$SESSION_SH" phase "$TEST_DIR" "4: Testing Loop"
assert_ok "4→5 continues normally" \
  "$SESSION_SH" phase "$TEST_DIR" "5: Synthesis"

echo ""

# --- Phase History ---
echo "--- Phase History ---"
reset_state "1: Setup"
"$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion" > /dev/null 2>&1
"$SESSION_SH" phase "$TEST_DIR" "3: Interrogation" > /dev/null 2>&1
assert_json "phaseHistory has 3 entries" '.phaseHistory | length' '3'
assert_json "phaseHistory last is 3: Interrogation" '.phaseHistory[-1]' '3: Interrogation'

echo ""

# --- Backward Compatibility (no phases array) ---
echo "--- Backward Compatibility ---"
reset_state_no_phases "Phase 3: Execution"
assert_ok "any transition allowed without phases array" \
  "$SESSION_SH" phase "$TEST_DIR" "Phase 1: Setup"

assert_ok "backward transition allowed without phases array" \
  "$SESSION_SH" phase "$TEST_DIR" "Phase 5: Synthesis"

echo ""

# --- Format Validation ---
echo "--- Format Validation ---"
reset_state "1: Setup"
assert_fail "no number prefix rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "Setup"

assert_fail "text-only prefix rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "Phase 1: Setup"

echo ""

# --- Whitelist Format Validation ---
# Only "N: Name" or "N.M: Name" formats are valid. Everything else rejected.
echo "--- Whitelist Format Validation ---"

# Valid formats (should pass)
reset_state "1: Setup"
assert_ok "valid N: format (5: Build Loop)" \
  "$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion"
reset_state "1: Setup"
assert_ok "valid N.M: format (1.1: Sub)" \
  "$SESSION_SH" phase "$TEST_DIR" "1.1: Sub"
reset_state "1: Setup"
# Multi-digit major
"$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion" > /dev/null 2>&1  # get to 2 first
"$SESSION_SH" phase "$TEST_DIR" "3: Interrogation" > /dev/null 2>&1
"$SESSION_SH" phase "$TEST_DIR" "4: Planning" > /dev/null 2>&1
"$SESSION_SH" phase "$TEST_DIR" "5: Build Loop" > /dev/null 2>&1
"$SESSION_SH" phase "$TEST_DIR" "6: Synthesis" > /dev/null 2>&1
# Now test going back with approval (tests format, not sequence)
assert_ok "valid multi-digit format (12: Name) with approval" \
  "$SESSION_SH" phase "$TEST_DIR" "12: Something" --user-approved "Reason: testing format"

# Invalid formats — alpha-style (the migration target)
reset_state "1: Setup"
assert_fail "alpha-style 5b rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5b: Triage"

reset_state "1: Setup"
assert_fail "alpha-style 3b rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "3b: Handoff"

reset_state "1: Setup"
assert_fail "alpha-style 1a rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "1a: Setup"

reset_state "1: Setup"
assert_fail "alpha-style uppercase 5B rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5B: Upper"

# Invalid formats — other non-whitelisted patterns
reset_state "1: Setup"
assert_fail "underscore 5_1 rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5_1: Test"

reset_state "1: Setup"
assert_fail "space between digits 5 1 rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5 1: Test"

reset_state "1: Setup"
assert_fail "mixed 5.1b rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5.1b: Mixed"

reset_state "1: Setup"
assert_fail "no major .1 rejected" \
  "$SESSION_SH" phase "$TEST_DIR" ".1: No Major"

reset_state "1: Setup"
assert_fail "trailing dot 5. rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5.: No Minor"

reset_state "1: Setup"
assert_fail "space before colon 5 : rejected" \
  "$SESSION_SH" phase "$TEST_DIR" "5 : Space"

echo ""

# --- Same Phase (re-entry) ---
echo "--- Same Phase Re-entry ---"
reset_state "3: Interrogation"
assert_ok "re-entering same phase (no-op, always allowed)" \
  "$SESSION_SH" phase "$TEST_DIR" "3: Interrogation"
assert_json "phase unchanged after re-entry" '.currentPhase' '3: Interrogation'

# Skill-switch scenario: activate with different skill → agent re-enters phase 1
reset_state "1: Setup"
# Simulate: activate sets currentPhase to "1: Setup" after skill change
# Agent then calls session.sh phase "1: Setup" to formally enter it
assert_ok "skill-switch re-entry at 1: Setup (common scenario)" \
  "$SESSION_SH" phase "$TEST_DIR" "1: Setup"

echo ""

# --- Loading flag cleared ---
echo "--- Loading Flag ---"
reset_state "1: Setup"
jq '.loading = true' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
"$SESSION_SH" phase "$TEST_DIR" "2: Context Ingestion" > /dev/null 2>&1
assert_json "loading flag cleared after phase transition" '.loading // "cleared"' 'cleared'

echo ""

# --- Skill-Change Phase Reset ---
echo "--- Skill-Change Phase Reset ---"

# Test 30: Activate with different skill resets phaseHistory and currentPhase
reset_state "6: Synthesis"
# Simulate existing state: phaseHistory has entries from previous skill
jq '.phaseHistory = ["1: Setup", "2: Context Ingestion", "3: Interrogation", "4: Planning", "5: Build Loop", "6: Synthesis"]' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
# Activate with a DIFFERENT skill and new phases array
export CLAUDE_SUPERVISOR_PID=99999
"$SESSION_SH" activate "$TEST_DIR" "debug" <<'ACTIVATEEOF' > /dev/null 2>&1
{
  "taskSummary": "test skill change",
  "phases": [
    {"major": 1, "minor": 0, "name": "Setup"},
    {"major": 2, "minor": 0, "name": "Hypothesis"},
    {"major": 3, "minor": 0, "name": "Investigation"}
  ]
}
ACTIVATEEOF
assert_json "skill change resets phaseHistory to empty" '.phaseHistory | length' '0'
assert_json "skill change derives currentPhase from new phases" '.currentPhase' '1: Setup'
assert_json "skill change updates skill name" '.skill' 'debug'

# Test 31: Activate with same skill (same PID) does NOT reset phaseHistory
reset_state "3: Interrogation"
jq '.phaseHistory = ["1: Setup", "2: Context Ingestion", "3: Interrogation"]' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
"$SESSION_SH" activate "$TEST_DIR" "implement" < /dev/null > /dev/null 2>&1
assert_json "same-skill re-activation preserves phaseHistory" '.phaseHistory | length' '3'

# Test 32: Activate with different skill but NO phases array falls back to default
reset_state "5: Build Loop"
jq '.phaseHistory = ["1: Setup", "2: Context Ingestion", "3: Interrogation", "4: Planning", "5: Build Loop"]' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
"$SESSION_SH" activate "$TEST_DIR" "analyze" <<'ACTIVATEEOF' > /dev/null 2>&1
{
  "taskSummary": "test skill change no phases"
}
ACTIVATEEOF
assert_json "skill change without phases resets phaseHistory" '.phaseHistory | length' '0'
assert_json "skill change without phases uses default currentPhase" '.currentPhase' 'Phase 1: Setup'

echo ""

# --- Cleanup ---
rm -rf "$TMP_DIR"

# --- Summary ---
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
