#!/bin/bash
# Test: SessionStart hook delegates session resolution to `session.sh find`
#
# The hook no longer scans/selects sessions itself. It calls the canonical
# resolver (fleet-exact match, then strict PID == this process, with a
# PID-guard). Regression guarded here: a stale, alphabetically-first session
# owned by a DIFFERENT live PID must NOT be attached to this pane — the old
# loose "any alive PID" fallback picked exactly that. Fleet-vs-PID priority
# proper is covered in test-session-sh.sh (find_by_pid / find_no_match /
# find_rejects_alive_different_pid).
#
# Non-fleet (PID) path keeps these hermetic (¶INV_TMUX_AND_FLEET_OPTIONAL).

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

# --- Helper: run hook resolving as a specific process (non-fleet/PID path) ---
# Unsets TMUX/TMUX_PANE so `session.sh find` skips fleet and matches by
# CLAUDE_SUPERVISOR_PID only. Cleans the per-PID find cache after each run.
run_hook_pid() {
  local source="$1" cwd="$2" pid="$3"
  local input
  input=$(jq -n --arg src "$source" --arg cwd "$cwd" '{hook_event_name:"SessionStart",source:$src,cwd:$cwd}')
  echo "$input" | env -u TMUX -u TMUX_PANE CLAUDE_SUPERVISOR_PID="$pid" \
    bash "$HOOK_SH" 2>/dev/null
  rm -f "/tmp/claude-session-cache-$pid" 2>/dev/null || true
}

# --- Helper: reset the sandbox to a clean slate between tests ---
# Full wipe (not just lifecycle=completed): `session.sh find` matches by PID
# regardless of lifecycle, so a leftover dir sharing a test PID would collide.
deactivate_all() {
  rm -rf "$SANDBOX"/sessions
  mkdir -p "$SANDBOX"/sessions
}

# A real, alive PID distinct from $$ — the "owning" process for these tests.
sleep 300 &
OWNER_PID=$!
trap 'kill "$OWNER_PID" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

# ============================================================
# TEST GROUP: Delegation to session.sh find (F1-F3)
# ============================================================
echo ""
echo "=== SessionStart Hook: delegates to session.sh find ==="

# F1: hook attaches the session owned by THIS process (exact PID match)
echo ""
echo "F1: attaches the session owned by this process"
deactivate_all

F1_OWNED="$SANDBOX/sessions/ZZZ_OWNED_LOOP"
create_state_fleet "$F1_OWNED" "loop" "" "$OWNER_PID"

F1_OUTPUT=$(run_hook_pid "resume" "$SANDBOX" "$OWNER_PID")
assert_contains "F1: attaches owned session (loop skill)" "Skill: loop" "$F1_OUTPUT"
assert_contains "F1: attaches owned session name" "ZZZ_OWNED_LOOP" "$F1_OUTPUT"

# F2: REGRESSION — a stale, alphabetically-first session owned by a DIFFERENT
# alive PID must NOT be attached. The old loose fallback picked AAA; the fixed
# hook resolves by exact PID and picks ZZZ.
echo ""
echo "F2: stale alive-PID session does not preempt the owned session"
deactivate_all

F2_STALE="$SANDBOX/sessions/AAA_STALE_ALIVE"
create_state_fleet "$F2_STALE" "test" "" "$$"     # $$ alive, but not our process
F2_OWNED="$SANDBOX/sessions/ZZZ_OWNED"
create_state_fleet "$F2_OWNED" "analyze" "" "$OWNER_PID"

F2_OUTPUT=$(run_hook_pid "resume" "$SANDBOX" "$OWNER_PID")
assert_contains "F2: attaches owned session, not stale AAA" "ZZZ_OWNED" "$F2_OUTPUT"
assert_contains "F2: correct skill (analyze)" "Skill: analyze" "$F2_OUTPUT"

# F3: when this process owns no session, the context line is (none) even though
# other sessions have alive PIDs — never attach an unrelated session.
echo ""
echo "F3: owns nothing -> Session: (none) despite alive-PID sessions"
deactivate_all

F3_OTHER="$SANDBOX/sessions/AAA_OTHER_ALIVE"
create_state_fleet "$F3_OTHER" "implement" "" "$$"   # alive, belongs to a different process

F3_OUTPUT=$(run_hook_pid "resume" "$SANDBOX" "424242")  # a PID no session owns
assert_contains "F3: reports no active session" "Session: (none)" "$F3_OUTPUT"

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

# CF3: a session not touched within ENGINE_CLAIM_SCAN_DAYS is never read
echo ""
echo "CF3: claim scan skips state files older than the scan window"
deactivate_all

CF3_OLD="$SANDBOX/sessions/CF3_OLD"
create_state_fleet "$CF3_OLD" "test" "fleet:target:Worker" "99997"
touch -t 202501010000 "$CF3_OLD/.state.json"

CF3_ACTIVE="$SANDBOX/sessions/CF3_ACTIVE"
create_state_fleet "$CF3_ACTIVE" "loop" "fleet:target:Worker" "99999"

ENGINE_CLAIM_SCAN_DAYS=14 CLAUDE_SUPERVISOR_PID=$$ bash "$SESSION_SH" continue "$CF3_ACTIVE" > /dev/null 2>&1 || true

CF3_OLD_FLEET=$(jq -r '.fleetPaneId // "cleared"' "$CF3_OLD/.state.json" 2>/dev/null)
assert_eq "CF3: old session left untouched" "fleet:target:Worker" "$CF3_OLD_FLEET"

# CF4: a state file that stalls on read (a FIFO stands in for an evicted synced file)
# costs at most the per-file timeout, and the other stale claims are still cleared
echo ""
echo "CF4: a stalled state file is skipped after the per-file timeout"
deactivate_all
rm -rf "$SANDBOX/sessions/CF3_OLD"

CF4_STALL="$SANDBOX/sessions/CF4_STALL"
mkdir -p "$CF4_STALL"
mkfifo "$CF4_STALL/.state.json"

CF4_STALE="$SANDBOX/sessions/CF4_STALE"
create_state_fleet "$CF4_STALE" "test" "fleet:target:Worker" "99996"

CF4_ACTIVE="$SANDBOX/sessions/CF4_ACTIVE"
create_state_fleet "$CF4_ACTIVE" "loop" "fleet:target:Worker" "99999"

CF4_START=$(date +%s)
ENGINE_CLAIM_SCAN_TIMEOUT=1 CLAUDE_SUPERVISOR_PID=$$ bash "$SESSION_SH" continue "$CF4_ACTIVE" > /dev/null 2>&1 || true
CF4_ELAPSED=$(( $(date +%s) - CF4_START ))

assert_eq "CF4: continue finishes within 10s despite the stalled file" "yes" "$([ "$CF4_ELAPSED" -lt 10 ] && echo yes || echo "no (${CF4_ELAPSED}s)")"
CF4_STALE_FLEET=$(jq -r '.fleetPaneId // "cleared"' "$CF4_STALE/.state.json" 2>/dev/null)
assert_eq "CF4: other stale session still cleared" "cleared" "$CF4_STALE_FLEET"

# CF5: outside TEST_MODE the scan runs in the background, so continue returns before it finishes
echo ""
echo "CF5: claim scan is detached from continue by default"
deactivate_all

CF5_START=$(date +%s)
env -u TEST_MODE ENGINE_CLAIM_SCAN_TIMEOUT=20 CLAUDE_SUPERVISOR_PID=$$ bash "$SESSION_SH" continue "$CF4_ACTIVE" > /dev/null 2>&1 || true
CF5_ELAPSED=$(( $(date +%s) - CF5_START ))
assert_eq "CF5: continue returns without waiting on the 20s stall" "yes" "$([ "$CF5_ELAPSED" -lt 15 ] && echo yes || echo "no (${CF5_ELAPSED}s)")"
rm -rf "$CF4_STALL"

# CF6: a PID claim matches the whole number only
echo ""
echo "CF6: PID claim does not clear a longer PID that shares the prefix"
deactivate_all

CF6_LONGER="$SANDBOX/sessions/CF6_LONGER"
create_state_fleet "$CF6_LONGER" "test" "fleet:other:Pane" "${$}7"

CF6_ACTIVE="$SANDBOX/sessions/CF6_ACTIVE"
create_state_fleet "$CF6_ACTIVE" "loop" "fleet:target:Worker" "99999"

CLAUDE_SUPERVISOR_PID=$$ bash "$SESSION_SH" continue "$CF6_ACTIVE" > /dev/null 2>&1 || true
CF6_PID=$(jq -r '.pid // "cleared"' "$CF6_LONGER/.state.json" 2>/dev/null)
assert_eq "CF6: longer PID kept" "${$}7" "$CF6_PID"

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
