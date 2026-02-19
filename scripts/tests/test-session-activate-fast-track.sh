#!/bin/bash
# Test: --fast-track flag on session.sh activate
# Covers: flag parsing, SHOULD_SCAN override, completedSkills bypass, idle path unification
#
# Per ¶INV_TEST_SANDBOX_ISOLATION: Uses temp sandbox, no real project/GDrive writes.

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# --- Setup sandbox ---
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SESSION_DIR="$SANDBOX/sessions/2026_01_01_TEST"
mkdir -p "$SESSION_DIR"

# Override SESSIONS_DIR so session.sh doesn't touch real sessions
export PROJECT_ROOT="$SANDBOX"

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected: $expected\n    actual:   $actual"
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected to contain: $needle\n    actual: $haystack"
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    should NOT contain: $needle\n    actual: $haystack"
    echo "  FAIL: $label"
    echo "    should NOT contain: $needle"
    echo "    actual: $haystack"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  fi
}

SESSION_SH="$HOME/.claude/scripts/session.sh"

# ============================================================
# TEST GROUP 1: --fast-track flag parsing
# ============================================================
echo ""
echo "=== Flag Parsing ==="

# Verify session.sh source contains --fast-track case
FAST_TRACK_CASE=$(grep -c '\-\-fast-track)' "$SESSION_SH" || echo "0")
echo ""
echo "Case 1: session.sh has --fast-track flag handler"
assert_eq "session.sh has --fast-track case" "1" "$FAST_TRACK_CASE"

# Verify FAST_TRACK variable is initialized
FAST_TRACK_INIT=$(grep -c 'FAST_TRACK=""' "$SESSION_SH" || echo "0")
echo ""
echo "Case 2: FAST_TRACK variable initialized"
assert_eq "FAST_TRACK initialized" "1" "$FAST_TRACK_INIT"

# ============================================================
# TEST GROUP 2: SHOULD_SCAN override
# ============================================================
echo ""
echo "=== SHOULD_SCAN Override ==="

# Verify the fast-track override exists after all path logic
OVERRIDE_LINE=$(grep -n 'FAST_TRACK.*true.*SHOULD_SCAN=false\|SHOULD_SCAN=false.*FAST_TRACK' "$SESSION_SH" || echo "")
OVERRIDE_EXISTS=$(grep -c '"\$FAST_TRACK" = true.*SHOULD_SCAN=false\|FAST_TRACK.*=.*true.*then' "$SESSION_SH" || echo "0")
echo ""
echo "Case 3: SHOULD_SCAN override block exists"
# Check for the if block pattern
OVERRIDE_BLOCK=$(grep -A1 'FAST_TRACK.*=.*true' "$SESSION_SH" | grep -c 'SHOULD_SCAN=false' || echo "0")
assert_eq "fast-track override sets SHOULD_SCAN=false" "1" "$OVERRIDE_BLOCK"

# ============================================================
# TEST GROUP 3: completedSkills bypass
# ============================================================
echo ""
echo "=== completedSkills Gate Bypass ==="

# Verify the gate condition includes FAST_TRACK check
GATE_LINE=$(grep 'completedSkills Gate' -A5 "$SESSION_SH" | grep 'FAST_TRACK' || echo "")
echo ""
echo "Case 4: completedSkills gate checks FAST_TRACK"
assert_contains "gate has FAST_TRACK check" "FAST_TRACK" "$GATE_LINE"

# ============================================================
# TEST GROUP 4: Idle path unification
# ============================================================
echo ""
echo "=== Idle Path Unification ==="

# Verify idle path no longer hardcodes SHOULD_SCAN=false
# The old line was: SHOULD_SCAN=false  # Fast-track: skip RAG scans
# The new line should be: SHOULD_SCAN=true  # Unified: --fast-track override applied later if set
IDLE_SCAN_LINE=$(grep -A50 'EXISTING_LIFECYCLE.*=.*idle' "$SESSION_SH" | grep 'SHOULD_SCAN=' | head -1 || echo "")
echo ""
echo "Case 5: Idle path sets SHOULD_SCAN=true (unified)"
assert_contains "idle path SHOULD_SCAN=true" "SHOULD_SCAN=true" "$IDLE_SCAN_LINE"

# Verify old hardcoded false is gone
IDLE_HARDCODED_FALSE=$(grep -A50 'EXISTING_LIFECYCLE.*=.*idle' "$SESSION_SH" | grep -c 'SHOULD_SCAN=false' 2>/dev/null; true)
echo ""
echo "Case 6: Idle path has no hardcoded SHOULD_SCAN=false"
assert_eq "no hardcoded SHOULD_SCAN=false in idle path" "0" "$IDLE_HARDCODED_FALSE"

# ============================================================
# TEST GROUP 5: .state.json storage
# ============================================================
echo ""
echo "=== fastTrack storage in .state.json ==="

# Verify session.sh stores fastTrack in .state.json when flag is set
STORE_FASTTRACK=$(grep -c 'fastTrack.*true\|\.fastTrack' "$SESSION_SH" || echo "0")
echo ""
echo "Case 7: session.sh stores fastTrack in .state.json"
# Should have at least 1 occurrence (the jq '.fastTrack = true' line)
if [ "$STORE_FASTTRACK" -ge 1 ]; then
  PASS=$((PASS + 1))
  echo "  PASS: fastTrack stored in .state.json ($STORE_FASTTRACK occurrences)"
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: fastTrack not stored in .state.json"
  echo "  FAIL: fastTrack not stored in .state.json"
fi

# ============================================================
# TEST GROUP 6: Integration — activate with --fast-track
# ============================================================
echo ""
echo "=== Integration: activate with --fast-track ==="

# Create a fresh session and activate with --fast-track
rm -f "$SESSION_DIR/.state.json"
ACTIVATE_OUTPUT=$(CLAUDE_SUPERVISOR_PID=$$ engine session activate "$SESSION_DIR" implement --fast-track <<'EOF'
{
  "taskType": "IMPLEMENTATION",
  "taskSummary": "Test fast-track",
  "scope": "test",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "planTemplate": "",
  "logTemplate": "",
  "debriefTemplate": "",
  "requestTemplate": "",
  "responseTemplate": "",
  "requestFiles": [],
  "nextSkills": [],
  "extraInfo": "",
  "directives": [],
  "phases": [{"major": 0, "minor": 0, "name": "Setup"}]
}
EOF
)

echo ""
echo "Case 8: Activate with --fast-track succeeds"
assert_contains "activation succeeds" "Session activated" "$ACTIVATE_OUTPUT"

echo ""
echo "Case 9: Activate with --fast-track skips scans (no SRC_ACTIVE_ALERTS)"
assert_not_contains "no alert scan" "SRC_ACTIVE_ALERTS" "$ACTIVATE_OUTPUT"

echo ""
echo "Case 10: .state.json has fastTrack: true"
STORED_FT=$(jq -r '.fastTrack // "null"' "$SESSION_DIR/.state.json" 2>/dev/null || echo "error")
assert_eq "fastTrack stored" "true" "$STORED_FT"

# ============================================================
# TEST GROUP 7: Integration — activate without --fast-track (control)
# ============================================================
echo ""
echo "=== Integration: activate without --fast-track (control) ==="

# Reset session
rm -f "$SESSION_DIR/.state.json"
ACTIVATE_CONTROL=$(CLAUDE_SUPERVISOR_PID=$$ engine session activate "$SESSION_DIR" implement <<'EOF'
{
  "taskType": "IMPLEMENTATION",
  "taskSummary": "Test full ceremony",
  "scope": "test",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "planTemplate": "",
  "logTemplate": "",
  "debriefTemplate": "",
  "requestTemplate": "",
  "responseTemplate": "",
  "requestFiles": [],
  "nextSkills": [],
  "extraInfo": "",
  "directives": [],
  "phases": [{"major": 0, "minor": 0, "name": "Setup"}]
}
EOF
)

echo ""
echo "Case 11: Activate without --fast-track runs scans"
assert_contains "scans run" "SRC_ACTIVE_ALERTS" "$ACTIVATE_CONTROL"

# ============================================================
# TEST GROUP 8: completedSkills + --fast-track bypasses gate
# ============================================================
echo ""
echo "=== completedSkills + --fast-track ==="

# Add completedSkills to state
jq '.completedSkills = ["implement"]' "$SESSION_DIR/.state.json" | \
  cat > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

echo ""
echo "Case 12: Activate with --fast-track bypasses completedSkills gate"
ACTIVATE_BYPASS=$(CLAUDE_SUPERVISOR_PID=$$ engine session activate "$SESSION_DIR" implement --fast-track < /dev/null 2>&1) || true
# Should NOT contain the rejection message
assert_not_contains "no rejection" "was already completed" "$ACTIVATE_BYPASS"

echo ""
echo "Case 13: Activate without --fast-track hits completedSkills gate"
ACTIVATE_REJECT=$(CLAUDE_SUPERVISOR_PID=$$ engine session activate "$SESSION_DIR" implement < /dev/null 2>&1) || true
assert_contains "gate rejects" "was already completed" "$ACTIVATE_REJECT"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  printf "$ERRORS\n"
  exit 1
fi
exit 0
