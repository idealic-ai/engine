#!/bin/bash
# Test: Fleet match priority over PID fallback in SessionStart hook
#
# Bug: Single-pass scan with break 2 on PID fallback causes alphabetically
# earlier sessions with alive PIDs to preempt fleet-matching sessions.
# Also: engine session continue doesn't claim fleet pane (no stale cleanup).
#
# Red-first: these tests FAIL against the current implementation.

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# --- Setup sandbox ---
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export TEST_MODE=1
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
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected to contain: $needle\n    actual: $(head -3 <<< "$haystack")"
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $(head -3 <<< "$haystack")"
  fi
}

# --- Helper: create state with fleet pane ---
create_state_fleet() {
  local dir="$1" skill="$2" fleet_pane="$3" pid="$4"
  mkdir -p "$dir"
  jq -n \
    --argjson pid "$pid" \
    --arg skill "$skill" \
    --arg fleet "$fleet_pane" \
    '{
      pid: $pid,
      skill: $skill,
      lifecycle: "active",
      loading: false,
      overflowed: false,
      killRequested: false,
      contextUsage: 0.5,
      currentPhase: "1: Work",
      fleetPaneId: $fleet,
      startedAt: "2026-02-12T00:00:00Z",
      lastHeartbeat: "2026-02-12T00:00:00Z"
    }' > "$dir/.state.json"
}

# --- Helper: create mock tmux that returns a specific fleet label ---
setup_mock_tmux() {
  local fleet_label="$1"
  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/tmux" <<MOCK
#!/bin/bash
# Mock tmux: return fleet label for display commands
if [[ "\$*" == *"display"* ]]; then
  echo "$fleet_label"
  exit 0
fi
exit 0
MOCK
  chmod +x "$SANDBOX/bin/tmux"
}

# --- Helper: run hook with mock tmux ---
run_hook_fleet() {
  local source="$1" cwd="$2" fleet_label="$3"
  setup_mock_tmux "$fleet_label"
  local input
  input=$(jq -n --arg src "$source" --arg cwd "$cwd" '{hook_event_name:"SessionStart",source:$src,cwd:$cwd}')
  # Set TMUX_PANE to trigger fleet detection path, prepend mock tmux to PATH
  # Note: env vars must be on the right side of pipe to reach the hook process
  echo "$input" | TMUX_PANE="%99" PATH="$SANDBOX/bin:$PATH" \
    bash "$HOOK_SH" 2>/dev/null
}

# --- Helper: deactivate all sessions ---
deactivate_all() {
  for f in "$SANDBOX"/sessions/*/.state.json; do
    [ -f "$f" ] || continue
    jq '.lifecycle = "completed"' "$f" | safe_json_write "$f"
  done
}

# ============================================================
# TEST GROUP: Fleet Priority (F1-F3)
# ============================================================
echo ""
echo "=== Fleet Priority: SessionStart Hook ==="

# F1: Fleet match should win over PID fallback when PID session sorts first
echo ""
echo "F1: Fleet match wins over earlier-sorting PID match"
deactivate_all

# Session AAA sorts first alphabetically, has alive PID, WRONG fleet pane
F1_AAA="$SANDBOX/sessions/AAA_OLD_TEST"
create_state_fleet "$F1_AAA" "test" "fleet:other:Pane" "$$"
# $$ = current shell PID — guaranteed alive

# Session ZZZ sorts last, has dead PID (99999), CORRECT fleet pane
F1_ZZZ="$SANDBOX/sessions/ZZZ_NEW_LOOP"
create_state_fleet "$F1_ZZZ" "loop" "fleet:target:Worker" "99999"
# PID 99999 very likely dead

F1_OUTPUT=$(run_hook_fleet "startup" "$SANDBOX" "target:Worker")
# The hook should pick ZZZ (fleet match), not AAA (PID match)
assert_contains "F1: picks fleet-matching session (loop skill)" "Skill: loop" "$F1_OUTPUT"
assert_contains "F1: picks ZZZ session name" "ZZZ_NEW_LOOP" "$F1_OUTPUT"

# F2: Fleet match should win even when PID-matching session has dehydratedContext
echo ""
echo "F2: Fleet match wins over PID match with dehydratedContext"
deactivate_all

F2_AAA="$SANDBOX/sessions/AAA_DEHYDRATED"
create_state_fleet "$F2_AAA" "test" "fleet:other:Pane" "$$"
jq '.dehydratedContext = {"summary":"wrong session","requiredFiles":[]}' \
  "$F2_AAA/.state.json" | safe_json_write "$F2_AAA/.state.json"

F2_ZZZ="$SANDBOX/sessions/ZZZ_FLEET_MATCH"
create_state_fleet "$F2_ZZZ" "loop" "fleet:target:Worker" "99999"

F2_OUTPUT=$(run_hook_fleet "startup" "$SANDBOX" "target:Worker")
# Fleet match (ZZZ) should still win — dehydrated context on AAA is irrelevant
assert_contains "F2: picks fleet-matching session" "ZZZ_FLEET_MATCH" "$F2_OUTPUT"
assert_contains "F2: correct skill (loop)" "Skill: loop" "$F2_OUTPUT"

# F3: When fleet matches, context line shows correct session even if PID session sorts first
echo ""
echo "F3: Context line shows fleet-matched session, not PID-matched"
deactivate_all

F3_EARLY="$SANDBOX/sessions/AAA_PID_ALIVE"
create_state_fleet "$F3_EARLY" "implement" "fleet:build:Builder" "$$"

F3_CORRECT="$SANDBOX/sessions/ZZZ_CORRECT"
create_state_fleet "$F3_CORRECT" "analyze" "fleet:data:Analyst" "99999"

F3_OUTPUT=$(run_hook_fleet "resume" "$SANDBOX" "data:Analyst")
assert_contains "F3: context line shows correct session" "ZZZ_CORRECT" "$F3_OUTPUT"
assert_contains "F3: context line shows correct skill" "Skill: analyze" "$F3_OUTPUT"

# ============================================================
# TEST GROUP: Continue Fleet Claim (CF1-CF2)
# ============================================================
echo ""
echo "=== Continue Fleet Claim: session.sh continue ==="

# CF1: continue should clear stale fleetPaneId from other sessions
echo ""
echo "CF1: continue clears stale fleetPaneId from other sessions"
deactivate_all

CF1_STALE="$SANDBOX/sessions/CF1_STALE"
create_state_fleet "$CF1_STALE" "test" "fleet:target:Worker" "99998"
# Stale session has the fleet pane ID we're about to claim

CF1_ACTIVE="$SANDBOX/sessions/CF1_ACTIVE"
create_state_fleet "$CF1_ACTIVE" "loop" "fleet:target:Worker" "99999"
# Active session also has the same fleet pane ID

# Run continue on CF1_ACTIVE (simulates resume after dehydration)
# Need to set CLAUDE_SUPERVISOR_PID so continue registers our PID
CLAUDE_SUPERVISOR_PID=$$ bash "$SESSION_SH" continue "$CF1_ACTIVE" > /dev/null 2>&1 || true

# After continue, the STALE session should have its fleetPaneId cleared
CF1_STALE_FLEET=$(jq -r '.fleetPaneId // "cleared"' "$CF1_STALE/.state.json" 2>/dev/null)
assert_eq "CF1: stale session fleetPaneId cleared" "cleared" "$CF1_STALE_FLEET"

# And the active session should retain its fleetPaneId
CF1_ACTIVE_FLEET=$(jq -r '.fleetPaneId // "cleared"' "$CF1_ACTIVE/.state.json" 2>/dev/null)
assert_eq "CF1: active session retains fleetPaneId" "fleet:target:Worker" "$CF1_ACTIVE_FLEET"

# CF2: continue should clear stale PID from other sessions
echo ""
echo "CF2: continue clears stale PID from other sessions"
deactivate_all

CF2_STALE="$SANDBOX/sessions/CF2_STALE"
create_state_fleet "$CF2_STALE" "test" "fleet:other:Pane" "$$"
# Stale session has OUR PID (from a previous activation in a different pane)

CF2_ACTIVE="$SANDBOX/sessions/CF2_ACTIVE"
create_state_fleet "$CF2_ACTIVE" "loop" "fleet:target:Worker" "99999"

CLAUDE_SUPERVISOR_PID=$$ bash "$SESSION_SH" continue "$CF2_ACTIVE" > /dev/null 2>&1 || true

# After continue, stale session should have its PID cleared
CF2_STALE_PID=$(jq -r '.pid // "cleared"' "$CF2_STALE/.state.json" 2>/dev/null)
assert_eq "CF2: stale session PID cleared" "cleared" "$CF2_STALE_PID"

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
