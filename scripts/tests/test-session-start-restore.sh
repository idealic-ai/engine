#!/bin/bash
# Test: SessionStart hook rehydration system — Hardening
#
# Tests three components:
#   1. Dehydrate command (session.sh dehydrate) — D1-D5
#   2. Hook script (session-start-restore.sh) — H1-H10
#   3. Restart mode detection (session.sh restart) — R1-R3
#
# Per ¶INV_TEST_SANDBOX_ISOLATION: Uses temp sandbox, no real session writes.

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# --- Setup sandbox ---
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Prevent tmux keystroke injection during tests (session.sh dehydrate/restart)
export TEST_MODE=1

# Source lib.sh for shared utilities (safe_json_write, timestamp)
source "$HOME/.claude/scripts/lib.sh"

SESSION_SH="$HOME/.claude/scripts/session.sh"
HOOK_SH="$HOME/.claude/hooks/session-start-restore.sh"

# --- Assert helpers ---
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
  if grep -qF "$needle" <<< "$haystack"; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected to contain: $needle\n    actual: $(head -5 <<< "$haystack")"
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $(head -5 <<< "$haystack")"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if grep -qF "$needle" <<< "$haystack"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    should NOT contain: $needle"
    echo "  FAIL: $label"
    echo "    should NOT contain: $needle"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  fi
}

# --- Helper: create a minimal .state.json ---
create_state() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/.state.json" <<'JSON'
{
  "pid": 99999,
  "skill": "test",
  "lifecycle": "active",
  "loading": false,
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0.5,
  "currentPhase": "3: Testing Loop",
  "startedAt": "2026-02-12T00:00:00Z",
  "lastHeartbeat": "2026-02-12T00:00:00Z"
}
JSON
}

# --- Helper: clear ALL dehydratedContext from sandbox sessions ---
# Prevents cross-test pollution (hook finds first match alphabetically)
clear_all_dehydrated() {
  for f in "$SANDBOX"/sessions/*/.state.json; do
    [ -f "$f" ] || continue
    local has_ctx
    has_ctx=$(jq -r '.dehydratedContext // null | type' "$f" 2>/dev/null || echo "null")
    if [ "$has_ctx" = "object" ]; then
      jq 'del(.dehydratedContext)' "$f" | safe_json_write "$f"
    fi
  done
}

# --- Helper: deactivate ALL sessions in sandbox ---
# Sets lifecycle=completed so they aren't found as "active"
deactivate_all_sessions() {
  for f in "$SANDBOX"/sessions/*/.state.json; do
    [ -f "$f" ] || continue
    jq '.lifecycle = "completed"' "$f" | safe_json_write "$f"
  done
}

# --- Helper: run the hook with simulated stdin ---
run_hook() {
  local source="$1" cwd="$2"
  local input
  input=$(jq -n --arg src "$source" --arg cwd "$cwd" '{hook_event_name:"SessionStart",source:$src,cwd:$cwd}')
  echo "$input" | bash "$HOOK_SH" 2>/dev/null
}

# ============================================================
# TEST GROUP 1: Dehydrate Command (session.sh dehydrate) — D1-D5
# ============================================================
echo ""
echo "=== Test Group 1: Dehydrate Command ==="

# D1: Should merge valid JSON into .state.json under dehydratedContext key
echo ""
echo "D1: Valid JSON merge"
D1_DIR="$SANDBOX/sessions/D1_TEST"
create_state "$D1_DIR"
echo '{"summary":"Test summary","lastAction":"Did something","nextSteps":["step1","step2"],"requiredFiles":["file.md"]}' \
  | bash "$SESSION_SH" dehydrate "$D1_DIR" > /dev/null 2>&1
D1_SUMMARY=$(jq -r '.dehydratedContext.summary' "$D1_DIR/.state.json" 2>/dev/null || echo "missing")
assert_eq "D1: dehydratedContext.summary exists" "Test summary" "$D1_SUMMARY"
D1_STEPS=$(jq -r '.dehydratedContext.nextSteps | length' "$D1_DIR/.state.json" 2>/dev/null || echo "0")
assert_eq "D1: nextSteps has 2 items" "2" "$D1_STEPS"
# Verify original fields preserved
D1_SKILL=$(jq -r '.skill' "$D1_DIR/.state.json" 2>/dev/null || echo "missing")
assert_eq "D1: original .skill preserved" "test" "$D1_SKILL"

# D2: Should reject empty stdin
echo ""
echo "D2: Empty stdin rejected"
D2_DIR="$SANDBOX/sessions/D2_TEST"
create_state "$D2_DIR"
cp "$D2_DIR/.state.json" "$D2_DIR/.state.json.before"
D2_EXIT=0
bash "$SESSION_SH" dehydrate "$D2_DIR" < /dev/null > /dev/null 2>&1 || D2_EXIT=$?
assert_eq "D2: exit code 1 on empty stdin" "1" "$D2_EXIT"
D2_DIFF=$(diff "$D2_DIR/.state.json" "$D2_DIR/.state.json.before" 2>&1 || true)
assert_eq "D2: .state.json unchanged" "" "$D2_DIFF"

# D3: Should reject malformed JSON
echo ""
echo "D3: Malformed JSON rejected"
D3_DIR="$SANDBOX/sessions/D3_TEST"
create_state "$D3_DIR"
cp "$D3_DIR/.state.json" "$D3_DIR/.state.json.before"
D3_EXIT=0
echo '{broken json' | bash "$SESSION_SH" dehydrate "$D3_DIR" > /dev/null 2>&1 || D3_EXIT=$?
assert_eq "D3: exit code 1 on malformed JSON" "1" "$D3_EXIT"
D3_DIFF=$(diff "$D3_DIR/.state.json" "$D3_DIR/.state.json.before" 2>&1 || true)
assert_eq "D3: .state.json unchanged" "" "$D3_DIFF"

# D4: Should reject when no .state.json exists
echo ""
echo "D4: No .state.json"
D4_DIR="$SANDBOX/sessions/D4_NOSTATE"
mkdir -p "$D4_DIR"
D4_EXIT=0
echo '{"summary":"test"}' | bash "$SESSION_SH" dehydrate "$D4_DIR" > /dev/null 2>&1 || D4_EXIT=$?
assert_eq "D4: exit code 1 when no .state.json" "1" "$D4_EXIT"

# D5: Should handle large JSON payload (1MB)
echo ""
echo "D5: Large JSON payload (1MB)"
D5_DIR="$SANDBOX/sessions/D5_TEST"
create_state "$D5_DIR"
# Generate ~1MB string
D5_BIG=$(python3 -c "print('x' * 1000000)")
D5_EXIT=0
jq -n --arg s "$D5_BIG" '{"summary":$s,"requiredFiles":[]}' \
  | bash "$SESSION_SH" dehydrate "$D5_DIR" > /dev/null 2>&1 || D5_EXIT=$?
assert_eq "D5: exit code 0 for 1MB payload" "0" "$D5_EXIT"
D5_LEN=$(jq -r '.dehydratedContext.summary | length' "$D5_DIR/.state.json" 2>/dev/null || echo "0")
assert_eq "D5: summary length is 1000000" "1000000" "$D5_LEN"

# ============================================================
# TEST GROUP 2: Hook Script (session-start-restore.sh) — H1-H10
# ============================================================
echo ""
echo "=== Test Group 2: Hook Script ==="

# H1: Should output formatted context when dehydratedContext exists
echo ""
echo "H1: Happy path — formatted output"
clear_all_dehydrated
H1_DIR="$SANDBOX/sessions/H1_TEST"
create_state "$H1_DIR"
jq '.dehydratedContext = {
  "summary": "Two-part session. Built the thing.",
  "lastAction": "Phase 3 entered.",
  "nextSteps": ["Write tests", "Run tests"],
  "handoverInstructions": "Resume at Phase 3.",
  "requiredFiles": [],
  "userHistory": "User is engaged."
}' "$H1_DIR/.state.json" | safe_json_write "$H1_DIR/.state.json"
H1_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "H1: output contains Session Recovery header" "Session Recovery" "$H1_OUTPUT"
assert_contains "H1: output contains summary" "Two-part session" "$H1_OUTPUT"
assert_contains "H1: output contains next steps" "Write tests" "$H1_OUTPUT"
assert_contains "H1: output contains handover" "Resume at Phase 3" "$H1_OUTPUT"
assert_contains "H1: output contains user history" "User is engaged" "$H1_OUTPUT"

# H2: Should clear dehydratedContext after consumption
echo ""
echo "H2: dehydratedContext cleared after consumption"
# H1 already consumed it — check
H2_CTX=$(jq -r '.dehydratedContext // "null"' "$H1_DIR/.state.json" 2>/dev/null)
assert_eq "H2: dehydratedContext is null after hook" "null" "$H2_CTX"

# H3: Non-startup sources → standards preloaded, dehydration skipped
echo ""
echo "H3: source=resume preloads standards, skips dehydration"
clear_all_dehydrated
H3_DIR="$SANDBOX/sessions/H3_TEST"
create_state "$H3_DIR"
jq '.dehydratedContext = {"summary":"should not appear in resume","requiredFiles":[]}' \
  "$H3_DIR/.state.json" | safe_json_write "$H3_DIR/.state.json"
H3_OUTPUT=$(run_hook "resume" "$SANDBOX")
assert_not_contains "H3: no dehydrated context on resume" "should not appear in resume" "$H3_OUTPUT"
# Verify dehydratedContext NOT cleared (dehydration didn't run)
H3_CTX=$(jq -r '.dehydratedContext.summary // "missing"' "$H3_DIR/.state.json" 2>/dev/null)
assert_eq "H3: dehydratedContext preserved on resume" "should not appear in resume" "$H3_CTX"

# H4: source=compact preloads standards, skips dehydration
echo ""
echo "H4: source=compact preloads standards, skips dehydration"
H4_OUTPUT=$(run_hook "compact" "$SANDBOX")
assert_not_contains "H4: no dehydrated context on compact" "### Summary" "$H4_OUTPUT"

# H5: Should handle missing requiredFiles gracefully
echo ""
echo "H5: Missing files get [MISSING] marker"
clear_all_dehydrated
H5_DIR="$SANDBOX/sessions/H5_TEST"
create_state "$H5_DIR"
jq '.dehydratedContext = {
  "summary": "Test missing files",
  "requiredFiles": ["/nonexistent/path/that/does/not/exist.md"]
}' "$H5_DIR/.state.json" | safe_json_write "$H5_DIR/.state.json"
H5_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "H5: output contains MISSING marker" "MISSING" "$H5_OUTPUT"
assert_contains "H5: output shows the file path" "/nonexistent/path" "$H5_OUTPUT"

# H6: Should resolve ~ prefix paths correctly
echo ""
echo "H6: ~ prefix path resolution"
clear_all_dehydrated
H6_DIR="$SANDBOX/sessions/H6_TEST"
create_state "$H6_DIR"
# Use a file we know exists in ~/.claude/
jq '.dehydratedContext = {
  "summary": "Test tilde resolution",
  "requiredFiles": ["~/.claude/scripts/lib.sh"]
}' "$H6_DIR/.state.json" | safe_json_write "$H6_DIR/.state.json"
H6_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "H6: output contains lib.sh content" "safe_json_write" "$H6_OUTPUT"

# H7: Should resolve sessions/ prefix paths correctly
echo ""
echo "H7: sessions/ prefix path resolution"
clear_all_dehydrated
H7_DIR="$SANDBOX/sessions/H7_TEST"
create_state "$H7_DIR"
# Create a test file in the sandbox sessions dir
echo "H7 test content marker" > "$SANDBOX/sessions/H7_TEST/testfile.md"
jq '.dehydratedContext = {
  "summary": "Test sessions prefix",
  "requiredFiles": ["sessions/H7_TEST/testfile.md"]
}' "$H7_DIR/.state.json" | safe_json_write "$H7_DIR/.state.json"
H7_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "H7: output contains sessions/ file content" "H7 test content marker" "$H7_OUTPUT"

# H8: No dehydratedContext — should still output session context + standards
echo ""
echo "H8: No dehydratedContext — context line + standards only"
clear_all_dehydrated
H8_DIR="$SANDBOX/sessions/H8_TEST"
create_state "$H8_DIR"
# No dehydratedContext in state — hook should output context line + standards, no recovery block
H8_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "H8: has Session Context line" "[Session Context]" "$H8_OUTPUT"
assert_not_contains "H8: no dehydrated summary block" "### Summary" "$H8_OUTPUT"

# H9: Should handle empty requiredFiles array
echo ""
echo "H9: Empty requiredFiles — no file blocks"
clear_all_dehydrated
H9_DIR="$SANDBOX/sessions/H9_TEST"
create_state "$H9_DIR"
jq '.dehydratedContext = {
  "summary": "Empty files test",
  "requiredFiles": []
}' "$H9_DIR/.state.json" | safe_json_write "$H9_DIR/.state.json"
H9_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "H9: output contains summary" "Empty files test" "$H9_OUTPUT"
assert_not_contains "H9: output has no Required Files section" "### Required Files (Auto-Loaded)" "$H9_OUTPUT"

# H10: Should be idempotent — re-run after restore re-outputs and clears
echo ""
echo "H10: Idempotency — re-run after restoring dehydratedContext"
clear_all_dehydrated
H10_DIR="$SANDBOX/sessions/H10_TEST"
create_state "$H10_DIR"
jq '.dehydratedContext = {
  "summary": "Idempotency test",
  "requiredFiles": []
}' "$H10_DIR/.state.json" | safe_json_write "$H10_DIR/.state.json"
# First run
H10_OUT1=$(run_hook "startup" "$SANDBOX")
assert_contains "H10: first run has summary" "Idempotency test" "$H10_OUT1"
# Verify cleared
H10_CTX1=$(jq -r '.dehydratedContext // "null"' "$H10_DIR/.state.json" 2>/dev/null)
assert_eq "H10: cleared after first run" "null" "$H10_CTX1"
# Restore dehydratedContext (simulating crash recovery)
clear_all_dehydrated
jq '.dehydratedContext = {
  "summary": "Idempotency test",
  "requiredFiles": []
}' "$H10_DIR/.state.json" | safe_json_write "$H10_DIR/.state.json"
# Second run
H10_OUT2=$(run_hook "startup" "$SANDBOX")
assert_contains "H10: second run produces same output" "Idempotency test" "$H10_OUT2"
H10_CTX2=$(jq -r '.dehydratedContext // "null"' "$H10_DIR/.state.json" 2>/dev/null)
assert_eq "H10: cleared after second run" "null" "$H10_CTX2"

# ============================================================
# TEST GROUP 2B: Session Context Block — C1-C3
# ============================================================
echo ""
echo "=== Test Group 2B: Session Context Block ==="

# C1: Should include Session Context line with active session details
echo ""
echo "C1: Active session shows details in context line"
clear_all_dehydrated
C1_DIR="$SANDBOX/sessions/C1_TEST"
create_state "$C1_DIR"
# Make it look active with PID matching current process
jq --arg pid "$$" '.pid = ($pid | tonumber) | .lifecycle = "active" | .skill = "test" | .currentPhase = "2: Testing Loop" | .toolCallsSinceLastLog = 3 | .toolUseWithoutLogsBlockAfter = 10' \
  "$C1_DIR/.state.json" | safe_json_write "$C1_DIR/.state.json"
C1_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "C1: has Session Context header" "[Session Context]" "$C1_OUTPUT"
assert_contains "C1: shows session name" "C1_TEST" "$C1_OUTPUT"
assert_contains "C1: shows skill" "Skill: test" "$C1_OUTPUT"
assert_contains "C1: shows phase" "Phase: 2: Testing Loop" "$C1_OUTPUT"
assert_contains "C1: shows heartbeat" "Heartbeat: 3/10" "$C1_OUTPUT"

# C2: Should show Session: (none) when no active session
echo ""
echo "C2: No active session shows (none)"
clear_all_dehydrated
deactivate_all_sessions
C2_DIR="$SANDBOX/sessions/C2_TEST"
create_state "$C2_DIR"
# PID 99999 from create_state is unlikely to be alive; all others deactivated
C2_OUTPUT=$(run_hook "startup" "$SANDBOX")
assert_contains "C2: has Session Context header" "[Session Context]" "$C2_OUTPUT"
assert_contains "C2: shows (none)" "Session: (none)" "$C2_OUTPUT"

# C3: Context line appears on non-startup sources too (resume, compact)
echo ""
echo "C3: Context line on resume source"
clear_all_dehydrated
deactivate_all_sessions
C3_DIR="$SANDBOX/sessions/C3_TEST"
create_state "$C3_DIR"
jq --arg pid "$$" '.pid = ($pid | tonumber) | .lifecycle = "active"' \
  "$C3_DIR/.state.json" | safe_json_write "$C3_DIR/.state.json"
C3_OUTPUT=$(run_hook "resume" "$SANDBOX")
assert_contains "C3: resume source has Session Context" "[Session Context]" "$C3_OUTPUT"
assert_contains "C3: resume source shows session" "C3_TEST" "$C3_OUTPUT"

# ============================================================
# TEST GROUP 3: Restart Mode Detection (session.sh restart) — R1-R3
# ============================================================
echo ""
echo "=== Test Group 3: Restart Mode Detection ==="

# CRITICAL: Unset WATCHDOG_PID so restart tests don't signal the real watchdog
# (which would kill the actual Claude process running these tests)
unset WATCHDOG_PID 2>/dev/null || true

# R1: Should set restartMode=hook when dehydratedContext exists
echo ""
echo "R1: restartMode=hook with dehydratedContext"
R1_DIR="$SANDBOX/sessions/R1_TEST"
create_state "$R1_DIR"
# First dehydrate, then restart
echo '{"summary":"test","requiredFiles":[]}' \
  | bash "$SESSION_SH" dehydrate "$R1_DIR" > /dev/null 2>&1
# Run restart (sandbox-safe — WATCHDOG_PID unset above)
bash "$SESSION_SH" restart "$R1_DIR" > /dev/null 2>&1 || true
R1_MODE=$(jq -r '.restartMode' "$R1_DIR/.state.json" 2>/dev/null || echo "missing")
assert_eq "R1: restartMode is hook" "hook" "$R1_MODE"

# R2: Should set restartMode=prompt when no dehydratedContext
echo ""
echo "R2: restartMode=prompt without dehydratedContext"
R2_DIR="$SANDBOX/sessions/R2_TEST"
create_state "$R2_DIR"
# No dehydrate — just restart
bash "$SESSION_SH" restart "$R2_DIR" > /dev/null 2>&1 || true
R2_MODE=$(jq -r '.restartMode' "$R2_DIR/.state.json" 2>/dev/null || echo "missing")
assert_eq "R2: restartMode is prompt" "prompt" "$R2_MODE"

# R3: Should still write restartPrompt regardless of mode
echo ""
echo "R3: restartPrompt written in both modes"
R3_PROMPT_HOOK=$(jq -r '.restartPrompt' "$R1_DIR/.state.json" 2>/dev/null || echo "")
R3_PROMPT_NOHOOK=$(jq -r '.restartPrompt' "$R2_DIR/.state.json" 2>/dev/null || echo "")
R3_HAS_HOOK=$( [ -n "$R3_PROMPT_HOOK" ] && echo "yes" || echo "no" )
R3_HAS_NOHOOK=$( [ -n "$R3_PROMPT_NOHOOK" ] && echo "yes" || echo "no" )
assert_eq "R3: restartPrompt exists with hook mode" "yes" "$R3_HAS_HOOK"
assert_eq "R3: restartPrompt exists with prompt mode" "yes" "$R3_HAS_NOHOOK"
# Both should contain /session continue
assert_contains "R3: hook mode prompt has /session continue" "/session continue" "$R3_PROMPT_HOOK"
assert_contains "R3: prompt mode prompt has /session continue" "/session continue" "$R3_PROMPT_NOHOOK"

# --- Summary ---
echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
if [ "$FAIL" -gt 0 ]; then
  printf "$ERRORS\n"
  exit 1
fi
exit 0
