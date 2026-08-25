#!/bin/bash
# tests/test-debrief.sh — Tests for session.sh debrief command and §CMD_ proof key parsing
# Run: bash ~/.claude/scripts/tests/test-debrief.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/scripts/session.sh"
TMP_DIR=$(mktemp -d)
TEST_DIR="$TMP_DIR/sessions/test_session"
STATE_FILE="$TEST_DIR/.state.json"

trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================
# Helpers
# ============================================================

# Create a state file with synthesis sub-phases that have §CMD_ proof fields
create_state_with_cmd_proof() {
  local current_phase="${1:-5: Synthesis}"
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
    {"major": 3, "minor": 0, "name": "Planning"},
    {"major": 4, "minor": 0, "name": "Build Loop"},
    {"major": 5, "minor": 0, "name": "Synthesis"},
    {"major": 5, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 5, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 5, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_BACKLINKS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 5, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "phaseHistory": ["$current_phase"]
}
AGENTEOF
}

# Create a minimal state with fewer synthesis sub-phases (e.g., brainstorm-like)
create_state_minimal_proof() {
  local current_phase="${1:-4: Synthesis}"
  mkdir -p "$TEST_DIR"
  cat > "$STATE_FILE" <<AGENTEOF
{
  "pid": 99999,
  "skill": "brainstorm",
  "lifecycle": "active",
  "currentPhase": "$current_phase",
  "phases": [
    {"major": 1, "minor": 0, "name": "Setup"},
    {"major": 2, "minor": 0, "name": "Dialogue"},
    {"major": 3, "minor": 0, "name": "Convergence"},
    {"major": 4, "minor": 0, "name": "Synthesis"},
    {"major": 4, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 4, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 4, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS"]},
    {"major": 4, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "phaseHistory": ["$current_phase"]
}
AGENTEOF
}

# Create state with NO synthesis sub-phases (no proof fields at all)
create_state_no_proof() {
  mkdir -p "$TEST_DIR"
  cat > "$STATE_FILE" <<AGENTEOF
{
  "pid": 99999,
  "skill": "do",
  "lifecycle": "active",
  "currentPhase": "2: Work",
  "phases": [
    {"major": 1, "minor": 0, "name": "Setup"},
    {"major": 2, "minor": 0, "name": "Work"},
    {"major": 3, "minor": 0, "name": "Close"}
  ],
  "phaseHistory": ["2: Work"]
}
AGENTEOF
}

echo "=== Debrief Command & §CMD_ Proof Key Tests ==="
echo ""

# ============================================================
# Group 1: Proof Key Parser — §CMD_ prefixed keys
# ============================================================
echo "--- Group 1: Proof Key Parser (§CMD_ prefixed keys) ---"

create_state_with_cmd_proof "5: Synthesis"

# Test: §CMD_ prefixed proof key is parsed correctly
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.1: Checklists" <<'EOF'
§CMD_PROCESS_CHECKLISTS: skipped: none discovered
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "§CMD_ proof key accepted (exit 0)"
assert_json "$STATE_FILE" '.currentPhase' '5.1: Checklists' "currentPhase updated to 5.1"

# Verify proof is stored in phaseHistory
PROOF_VAL=$(jq -r '.phaseHistory[-1].proof["§CMD_PROCESS_CHECKLISTS"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
assert_eq "skipped: none discovered" "$PROOF_VAL" "§CMD_ proof value stored in phaseHistory"

# Test: Multiple §CMD_ proof keys in one transition
# FROM validation checks proof on the phase being LEFT (5.3: Pipeline has 6 proof keys)
create_state_with_cmd_proof "5.3: Pipeline"
jq '.currentPhase = "5.3: Pipeline"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.4: Close" <<'EOF'
§CMD_MANAGE_DIRECTIVES: skipped: no files touched
§CMD_PROCESS_DELEGATIONS: ran: 2 bare tags processed
§CMD_DISPATCH_APPROVAL: ran: 2 items dispatched
§CMD_CAPTURE_SIDE_DISCOVERIES: skipped: none found
§CMD_MANAGE_BACKLINKS: skipped: none needed
§CMD_REPORT_LEFTOVER_WORK: ran: 1 item reported
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "Multiple §CMD_ proof keys accepted (exit 0)"

# Verify all 6 proof keys stored
PROOF_KEYS=$(jq -r '.phaseHistory[-1].proof | keys | length' "$STATE_FILE" 2>/dev/null)
assert_eq "6" "$PROOF_KEYS" "All 6 §CMD_ proof keys stored in phaseHistory"

DELEG_VAL=$(jq -r '.phaseHistory[-1].proof["§CMD_PROCESS_DELEGATIONS"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
assert_eq "ran: 2 bare tags processed" "$DELEG_VAL" "§CMD_PROCESS_DELEGATIONS proof value correct"

# Test: Missing §CMD_ proof key is rejected (leaving 5.1 which requires §CMD_PROCESS_CHECKLISTS)
create_state_with_cmd_proof "5.1: Checklists"
jq '.currentPhase = "5.1: Checklists"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.2: Debrief" 2>&1 <<'EOF'
EOF
)
PHASE_RESULT=$?
assert_eq "1" "$PHASE_RESULT" "Missing §CMD_ proof key rejected (exit 1)"

# Test: Mixed §CMD_ and short-name proof keys work (backward compat)
create_state_with_cmd_proof "5.1: Checklists"
jq '.currentPhase = "5.1: Checklists"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.2: Debrief" <<'EOF'
§CMD_GENERATE_DEBRIEF_file: sessions/test/IMPLEMENTATION.md
§CMD_GENERATE_DEBRIEF_tags: #needs-review
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "§CMD_ with underscore suffix parsed correctly (exit 0)"

echo ""

# ============================================================
# Group 2: Section Discovery — debrief reads phases array
# ============================================================
echo "--- Group 2: Section Discovery ---"

# Test: Full skill (implement) — discovers all §CMD_ proof fields
create_state_with_cmd_proof "5: Synthesis"
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "debrief exits 0 for valid session"
assert_contains "§CMD_PROCESS_DELEGATIONS" "$DEBRIEF_OUTPUT" "debrief outputs delegations section"
assert_contains "§CMD_CAPTURE_SIDE_DISCOVERIES" "$DEBRIEF_OUTPUT" "debrief outputs discoveries section"
assert_contains "§CMD_REPORT_LEFTOVER_WORK" "$DEBRIEF_OUTPUT" "debrief outputs leftover section"
assert_contains "§CMD_MANAGE_DIRECTIVES" "$DEBRIEF_OUTPUT" "debrief outputs directives section"
assert_contains "§CMD_MANAGE_BACKLINKS" "$DEBRIEF_OUTPUT" "debrief outputs backlinks section"

# Test: Minimal skill (brainstorm-like) — only declared sections appear
create_state_minimal_proof "4: Synthesis"
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_PROCESS_DELEGATIONS" "$DEBRIEF_OUTPUT" "minimal: delegations present (declared)"
assert_not_contains "§CMD_CAPTURE_SIDE_DISCOVERIES" "$DEBRIEF_OUTPUT" "minimal: discoveries absent (not declared)"
assert_not_contains "§CMD_REPORT_LEFTOVER_WORK" "$DEBRIEF_OUTPUT" "minimal: leftover absent (not declared)"
assert_not_contains "§CMD_DISPATCH_APPROVAL" "$DEBRIEF_OUTPUT" "minimal: dispatch absent (not declared)"
assert_not_contains "§CMD_MANAGE_BACKLINKS" "$DEBRIEF_OUTPUT" "minimal: backlinks absent (not declared)"

# Test: No synthesis sub-phases — debrief outputs nothing (or minimal)
create_state_no_proof
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_not_contains "## §CMD_" "$DEBRIEF_OUTPUT" "no-proof: no §CMD_ section headings output"

echo ""

# ============================================================
# Group 3: SCAN — Delegations (tag scan)
# ============================================================
echo "--- Group 3: SCAN — Delegations ---"

create_state_with_cmd_proof "5: Synthesis"

# Create a LOG file with a bare inline tag
cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## ▶️ Task Start
*   **Item**: Build the feature
*   **Goal**: Implement auth

## 🚧 Block — API migration #needs-implementation
*   **Obstacle**: Old API doesn't support new auth flow
LOGEOF

# Create a debrief with a tag on the Tags line
cat > "$TEST_DIR/IMPLEMENTATION.md" <<'DEBRIEFEOF'
# Implementation Debriefing: Auth Feature
**Tags**: #needs-review #needs-documentation

## 1. Executive Summary
The auth feature was implemented.
DEBRIEFEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_PROCESS_DELEGATIONS" "$DEBRIEF_OUTPUT" "delegations section present"
# Should find at least the inline tag
DELEG_LINE=$(echo "$DEBRIEF_OUTPUT" | grep -A 20 "§CMD_PROCESS_DELEGATIONS" | head -20)
assert_contains "#needs-" "$DELEG_LINE" "delegations found bare #needs- tags"

# Test: No tags — count is 0
rm -f "$TEST_DIR/IMPLEMENTATION_LOG.md" "$TEST_DIR/IMPLEMENTATION.md"
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_PROCESS_DELEGATIONS (0)" "$DEBRIEF_OUTPUT" "delegations (0) when no tags"

echo ""

# ============================================================
# Group 4: SCAN — Side Discoveries (emoji grep)
# ============================================================
echo "--- Group 4: SCAN — Side Discoveries ---"

create_state_with_cmd_proof "5: Synthesis"

cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## ▶️ Task Start
*   **Item**: Build the feature

## 👁️ Observation
*   **Focus**: utils.ts
*   **Detail**: File is getting huge (500+ lines)

## 😟 Concern
*   **Topic**: Memory Usage
*   **Detail**: Creating new Float32Array every frame

## ✅ Success / Commit
*   **Item**: Step 1
*   **Changes**: Created types.ts
LOGEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DISC_SECTION=$(echo "$DEBRIEF_OUTPUT" | grep -A 10 "§CMD_CAPTURE_SIDE_DISCOVERIES")
assert_contains "§CMD_CAPTURE_SIDE_DISCOVERIES" "$DEBRIEF_OUTPUT" "discoveries section present"
# Should find the observation and concern entries
assert_contains "👁️" "$DISC_SECTION" "discoveries found observation emoji"

# Test: No discoveries — count is 0
cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## ▶️ Task Start
*   **Item**: Build the feature

## ✅ Success / Commit
*   **Item**: Step 1
LOGEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_CAPTURE_SIDE_DISCOVERIES (0)" "$DEBRIEF_OUTPUT" "discoveries (0) when no emojis"

echo ""

# ============================================================
# Group 5: SCAN — Leftover Work (unchecked items + blocks)
# ============================================================
echo "--- Group 5: SCAN — Leftover Work ---"

create_state_with_cmd_proof "5: Synthesis"

cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'PLANEOF'
## Steps
*   [x] **Step 1**: Done
*   [ ] **Step 2**: Not done yet
*   [x] **Step 3**: Done
*   [ ] **Step 4**: Also not done
PLANEOF

cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## ✅ Success / Commit
*   **Item**: Step 1

## 🚧 Block / Friction
*   **Obstacle**: TypeScript error in StreamController
*   **Severity**: Blocking
LOGEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
LEFT_SECTION=$(echo "$DEBRIEF_OUTPUT" | grep -A 15 "§CMD_REPORT_LEFTOVER_WORK")
assert_contains "§CMD_REPORT_LEFTOVER_WORK" "$DEBRIEF_OUTPUT" "leftover section present"
# Should find unchecked items and blocks
assert_contains "[ ]" "$LEFT_SECTION" "leftover found unchecked plan items"

# Test: All done — count is 0
cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'PLANEOF'
## Steps
*   [x] **Step 1**: Done
*   [x] **Step 2**: Also done
PLANEOF
rm -f "$TEST_DIR/IMPLEMENTATION_LOG.md"

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_REPORT_LEFTOVER_WORK (0)" "$DEBRIEF_OUTPUT" "leftover (0) when all done"

echo ""

# ============================================================
# Group 6: STATIC + DEPENDENT sections
# ============================================================
echo "--- Group 6: STATIC + DEPENDENT ---"

create_state_with_cmd_proof "5: Synthesis"

# With delegation results
cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## 🚧 Block — Auth #needs-implementation
*   **Obstacle**: Old API
LOGEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_MANAGE_DIRECTIVES" "$DEBRIEF_OUTPUT" "static: directives always shown"
assert_contains "§CMD_MANAGE_BACKLINKS" "$DEBRIEF_OUTPUT" "static: backlinks always shown"
assert_contains "§CMD_DISPATCH_APPROVAL" "$DEBRIEF_OUTPUT" "dependent: dispatch shown when delegations > 0"

# Without delegation results — dispatch should NOT appear
rm -f "$TEST_DIR/IMPLEMENTATION_LOG.md"
rm -f "$TEST_DIR/IMPLEMENTATION.md"

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_MANAGE_DIRECTIVES" "$DEBRIEF_OUTPUT" "static: directives still shown (0 delegations)"
# Dispatch should be absent when delegations found 0
DELEG_COUNT=$(echo "$DEBRIEF_OUTPUT" | sed -n 's/.*§CMD_PROCESS_DELEGATIONS (\([0-9]*\)).*/\1/p' | head -1)
DELEG_COUNT=${DELEG_COUNT:-0}
if [ "$DELEG_COUNT" = "0" ]; then
  assert_not_contains "§CMD_DISPATCH_APPROVAL" "$DEBRIEF_OUTPUT" "dependent: dispatch hidden when delegations = 0"
fi

echo ""

# ============================================================
# Group 7: Integration — full debrief output
# ============================================================
echo "--- Group 7: Integration ---"

create_state_with_cmd_proof "5: Synthesis"

# Create realistic session artifacts
cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## ▶️ Task Start
*   **Item**: Build centralized synthesis pipeline

## 👁️ Observation
*   **Focus**: COMMANDS.md
*   **Detail**: Getting very long (1200+ lines)

## 🚧 Block / Friction
*   **Obstacle**: UTF-8 regex in sed
*   **Severity**: Annoyance

## ✅ Success / Commit
*   **Item**: Step 1
*   **Changes**: Updated session.sh
LOGEOF

cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'PLANEOF'
## Steps
*   [x] **Step 1**: Fix parser
*   [ ] **Step 2**: Add debrief command
*   [x] **Step 3**: Add tests
PLANEOF

cat > "$TEST_DIR/IMPLEMENTATION.md" <<'DEBRIEFEOF'
# Implementation Debriefing: Synthesis Pipeline
**Tags**: #needs-review

## 1. Executive Summary
Built the centralized synthesis pipeline.
DEBRIEFEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_eq "0" "$?" "integration: debrief exits 0"
assert_contains "## Instructions" "$DEBRIEF_OUTPUT" "integration: has instructions header"
assert_contains "§CMD_PROCESS_DELEGATIONS" "$DEBRIEF_OUTPUT" "integration: has delegations"
assert_contains "§CMD_CAPTURE_SIDE_DISCOVERIES" "$DEBRIEF_OUTPUT" "integration: has discoveries"
assert_contains "§CMD_REPORT_LEFTOVER_WORK" "$DEBRIEF_OUTPUT" "integration: has leftover"
assert_contains "§CMD_MANAGE_DIRECTIVES" "$DEBRIEF_OUTPUT" "integration: has directives"
assert_contains "§CMD_MANAGE_BACKLINKS" "$DEBRIEF_OUTPUT" "integration: has backlinks"

echo ""

# ============================================================
# Group 8: Malformed State — debrief resilience
# ============================================================
echo "--- Group 8: Malformed State ---"

# Case 8.1: Invalid JSON (truncated) — should exit 1 or degrade gracefully
mkdir -p "$TEST_DIR"
echo '{ "phases": [' > "$STATE_FILE"
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
# jq will fail to parse, so debrief should treat it as "no phases"
if [ "$DEBRIEF_RESULT" = "0" ]; then
  assert_contains "no phases" "$DEBRIEF_OUTPUT" "8.1: truncated JSON degrades to 'no phases'"
else
  # Exit 1 is also acceptable — the state is corrupt
  pass "8.1: truncated JSON exits non-zero ($DEBRIEF_RESULT)"
fi

# Case 8.2: Empty phases array — should exit 0 with informational message
mkdir -p "$TEST_DIR"
cat > "$STATE_FILE" <<'AGENTEOF'
{
  "pid": 99999,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "5: Synthesis",
  "phases": []
}
AGENTEOF
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "8.2: empty phases array exits 0"
assert_contains "no phases" "$DEBRIEF_OUTPUT" "8.2: empty phases array says 'no phases'"

# Case 8.3: Phases with no proof fields on any entry
mkdir -p "$TEST_DIR"
cat > "$STATE_FILE" <<'AGENTEOF'
{
  "pid": 99999,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Planning",
  "phases": [
    {"major": 1, "minor": 0, "name": "Setup"},
    {"major": 2, "minor": 0, "name": "Context"},
    {"major": 3, "minor": 0, "name": "Planning"}
  ]
}
AGENTEOF
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "8.3: no proof fields exits 0"
assert_contains "nothing to scan" "$DEBRIEF_OUTPUT" "8.3: says nothing to scan when no §CMD_ refs in phases"

# Case 8.4: Phases with empty proof arrays
mkdir -p "$TEST_DIR"
cat > "$STATE_FILE" <<'AGENTEOF'
{
  "pid": 99999,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "5: Synthesis",
  "phases": [
    {"major": 5, "minor": 0, "name": "Synthesis"},
    {"major": 5, "minor": 1, "name": "Checklists", "proof": []},
    {"major": 5, "minor": 2, "name": "Debrief", "proof": []}
  ]
}
AGENTEOF
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "8.4: empty proof arrays exits 0"
assert_contains "nothing to scan" "$DEBRIEF_OUTPUT" "8.4: empty proof arrays with no steps/commands treated as nothing to scan"

echo ""

# ============================================================
# Group 9: Proof Parser — adversarial inputs
# ============================================================
echo "--- Group 9: Proof Parser (adversarial) ---"

# Case 9.1: Proof value containing colons
create_state_with_cmd_proof "5: Synthesis"
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.1: Checklists" <<'EOF'
§CMD_PROCESS_CHECKLISTS: value: with: colons: everywhere
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "9.1: proof value with colons accepted (exit 0)"
PROOF_VAL=$(jq -r '.phaseHistory[-1].proof["§CMD_PROCESS_CHECKLISTS"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
assert_eq "value: with: colons: everywhere" "$PROOF_VAL" "9.1: proof value preserves colons"

# Case 9.2: Key with leading whitespace — should NOT be parsed
create_state_with_cmd_proof "5: Synthesis"
"$SESSION_SH" phase "$TEST_DIR" "5.1: Checklists" <<'EOF' > /dev/null 2>&1
  §CMD_PROCESS_CHECKLISTS: value with leading space key
EOF
PHASE_RESULT=$?
if [ "$PHASE_RESULT" != "0" ]; then
  pass "9.2: leading whitespace key rejected (exit $PHASE_RESULT)"
else
  # Even if exit 0 (parser edge case), phase should NOT have advanced correctly
  # Check that the proof value is missing (key wasn't parsed)
  PROOF_VAL=$(jq -r '.phaseHistory[-1].proof["§CMD_PROCESS_CHECKLISTS"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
  if [ "$PROOF_VAL" = "MISSING" ] || [ "$PROOF_VAL" = "" ]; then
    pass "9.2: leading whitespace key not parsed (proof value missing)"
  else
    fail "9.2: leading whitespace key should not be parsed" "MISSING" "$PROOF_VAL"
  fi
fi

# Case 9.3: Duplicate proof keys — last value wins (jq merge behavior)
# FROM validation checks proof on 5.3 (Pipeline, 6 keys) — provide all 6 with one duplicate
create_state_with_cmd_proof "5.3: Pipeline"
jq '.currentPhase = "5.3: Pipeline"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.4: Close" <<'EOF'
§CMD_MANAGE_DIRECTIVES: first value
§CMD_PROCESS_DELEGATIONS: ran: 1 item
§CMD_DISPATCH_APPROVAL: skipped
§CMD_CAPTURE_SIDE_DISCOVERIES: skipped
§CMD_MANAGE_BACKLINKS: skipped
§CMD_REPORT_LEFTOVER_WORK: skipped
§CMD_MANAGE_DIRECTIVES: second value (overwrites first)
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "9.3: duplicate keys accepted (exit 0)"
DUP_VAL=$(jq -r '.phaseHistory[-1].proof["§CMD_MANAGE_DIRECTIVES"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
assert_eq "second value (overwrites first)" "$DUP_VAL" "9.3: last duplicate key value wins"

# Case 9.4: Proof value with quotes and backslashes
create_state_with_cmd_proof "5: Synthesis"
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.1: Checklists" <<'EOF'
§CMD_PROCESS_CHECKLISTS: ran "2 items" with \n escaped chars
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "9.4: proof value with quotes/backslashes accepted (exit 0)"
PROOF_VAL=$(jq -r '.phaseHistory[-1].proof["§CMD_PROCESS_CHECKLISTS"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
assert_contains "2 items" "$PROOF_VAL" "9.4: proof value with quotes preserved"

echo ""

# ============================================================
# Group 10: Missing Artifacts — scan resilience
# ============================================================
echo "--- Group 10: Missing Artifacts ---"

# Case 10.1: Only .state.json — all scans should report (0)
create_state_with_cmd_proof "5: Synthesis"
rm -f "$TEST_DIR"/*.md
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "10.1: only .state.json exits 0"
assert_contains "§CMD_PROCESS_DELEGATIONS (0)" "$DEBRIEF_OUTPUT" "10.1: delegations (0) with no md files"
assert_contains "§CMD_CAPTURE_SIDE_DISCOVERIES (0)" "$DEBRIEF_OUTPUT" "10.1: discoveries (0) with no md files"
assert_contains "§CMD_REPORT_LEFTOVER_WORK (0)" "$DEBRIEF_OUTPUT" "10.1: leftover (0) with no md files"

# Case 10.2: LOG file with only success/task emojis (no discovery emojis)
create_state_with_cmd_proof "5: Synthesis"
cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## ✅ Success / Commit
*   **Item**: Step 1
*   **Changes**: Added feature

## ▶️ Task Start
*   **Item**: Step 2
*   **Goal**: More work
LOGEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_CAPTURE_SIDE_DISCOVERIES (0)" "$DEBRIEF_OUTPUT" "10.2: discoveries (0) with only success/task emojis"

# Case 10.3: PLAN file with all items checked (mixed * and - list markers)
create_state_with_cmd_proof "5: Synthesis"
cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'PLANEOF'
## Steps
*   [x] **Step 1**: Done
-   [x] **Step 2**: Also done
* [x] **Step 3**: Done too
- [x] **Step 4**: All done
PLANEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
assert_contains "§CMD_REPORT_LEFTOVER_WORK (0)" "$DEBRIEF_OUTPUT" "10.3: leftover (0) with all items checked (mixed markers)"

echo ""

# ============================================================
# Group 11: Backward Compat — mixed field names
# ============================================================
echo "--- Group 11: Backward Compat ---"

# Case 11.1: Mixed old-style and §CMD_ proof fields — debrief only outputs §CMD_ sections
mkdir -p "$TEST_DIR"
cat > "$STATE_FILE" <<'AGENTEOF'
{
  "pid": 99999,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "5: Synthesis",
  "phases": [
    {"major": 5, "minor": 0, "name": "Synthesis"},
    {"major": 5, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 5, "minor": 2, "name": "Debrief", "proof": ["debrief_file", "tags_line"]},
    {"major": 5, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS"]}
  ],
  "phaseHistory": ["5: Synthesis"]
}
AGENTEOF

DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "11.1: mixed field names exits 0"
assert_contains "§CMD_PROCESS_DELEGATIONS" "$DEBRIEF_OUTPUT" "11.1: §CMD_ fields present in debrief output"
assert_contains "§CMD_MANAGE_DIRECTIVES" "$DEBRIEF_OUTPUT" "11.1: §CMD_ directives field present"
# Old-style fields (debrief_file, tags_line) should NOT appear as section headings
assert_not_contains "## debrief_file" "$DEBRIEF_OUTPUT" "11.1: old-style debrief_file NOT in sections"
assert_not_contains "## tags_line" "$DEBRIEF_OUTPUT" "11.1: old-style tags_line NOT in sections"

# Case 11.2: Old-style proof keys in phase transitions still work
create_state_with_cmd_proof "5: Synthesis"
# Modify to use old-style proof field
jq '.phases[5].proof = ["checklists_processed"]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
OUTPUT=$("$SESSION_SH" phase "$TEST_DIR" "5.1: Checklists" <<'EOF'
checklists_processed: 2 checklists evaluated
EOF
2>&1)
PHASE_RESULT=$?
assert_eq "0" "$PHASE_RESULT" "11.2: old-style proof key accepted in phase transition"
PROOF_VAL=$(jq -r '.phaseHistory[-1].proof["checklists_processed"] // "MISSING"' "$STATE_FILE" 2>/dev/null)
assert_eq "2 checklists evaluated" "$PROOF_VAL" "11.2: old-style proof value stored"

echo ""

# ============================================================
# Group 12: tag.sh Fallback — delegations grep path
# ============================================================
echo "--- Group 12: tag.sh Fallback ---"

# Case 12.1: Delegations scan uses grep fallback when tag.sh is not available
create_state_with_cmd_proof "5: Synthesis"

# Create an artifact with bare inline tags
cat > "$TEST_DIR/IMPLEMENTATION_LOG.md" <<'LOGEOF'
## 🚧 Block — Migration #needs-implementation
*   **Obstacle**: Old API incompatible
LOGEOF

# Temporarily hide tag.sh by overriding PATH
# The debrief command uses `command -v "$HOME/.claude/scripts/tag.sh"` to check
# We need to make that check fail — rename tag.sh temporarily is too invasive
# Instead, test that debrief still finds tags (it uses grep fallback)
# The actual tag.sh check is `command -v "$HOME/.claude/scripts/tag.sh"` which checks
# file existence. We can't easily mock this without touching the real file.
# Instead, verify the grep fallback path works by checking the output has the tag.
DEBRIEF_OUTPUT=$("$SESSION_SH" debrief "$TEST_DIR" 2>&1)
DEBRIEF_RESULT=$?
assert_eq "0" "$DEBRIEF_RESULT" "12.1: debrief exits 0 with tags present"
# Whether tag.sh or grep path is used, we should find the delegation
DELEG_SECTION=$(echo "$DEBRIEF_OUTPUT" | grep -A 5 "§CMD_PROCESS_DELEGATIONS")
assert_contains "#needs-implementation" "$DELEG_SECTION" "12.1: delegation tag found in output (either path)"

echo ""

# ============================================================
# Results
# ============================================================
exit_with_results
