#!/bin/bash
# test-run-restart-rename.sh — run.sh's restart lookup survives a seat rename
#
# run.sh computes FLEET_PANE_ID once at start-up. When a seat is renamed while run.sh lives
# (migrate-fleet-pane-ids.sh --rename … --live), the bound session's fleetPaneId moves to
# the new label. find_restart_agent_json must re-read the live pane id, or the restart of a
# renamed seat is never matched and run.sh exits instead of restarting.
#
# Tests the REAL function, extracted from run.sh, with a stubbed fleet.sh.

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

RUN_SH="${RUN_SH_UNDER_TEST:-$(cd "$(dirname "$0")/.." && pwd)/run.sh}"

TMP=""
setup() {
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-run-restart-rename.XXXXXX")
  mkdir -p "$TMP/sessions" "$TMP/bin"
  # fleet.sh stub: `pane-id` prints $STUB_PANE_ID, or fails when it is empty
  cat > "$TMP/bin/fleet.sh" <<'EOF'
#!/bin/bash
[ "$1" = "pane-id" ] || exit 1
[ -n "${STUB_PANE_ID:-}" ] || exit 1
echo "$STUB_PANE_ID"
EOF
  chmod +x "$TMP/bin/fleet.sh"
  SCRIPTS_DIR="$TMP/bin"
  resolve_sessions_dir() { echo "$TMP/sessions"; }
  eval "$(sed -n '/^find_restart_agent_json() {/,/^}/p' "$RUN_SH")"
}
teardown() { [ -n "$TMP" ] && rm -r "$TMP"; TMP=""; unset STUB_PANE_ID FLEET_PANE_ID; }

kill_req() {  # <name> <fleetPaneId>
  mkdir -p "$TMP/sessions/$1"
  jq -n --arg id "$2" '{fleetPaneId: $id, killRequested: true}' > "$TMP/sessions/$1/.state.json"
}

test_function_extracted() {
  assert_eq "function" "$(type -t find_restart_agent_json)" "find_restart_agent_json extracted from run.sh"
}

test_renamed_seat_still_restarts() {
  kill_req S "yarik-fleet:domain:handbook"
  FLEET_PANE_ID="yarik-fleet:domain:Handbook"       # cached at start-up, before the rename
  STUB_PANE_ID="yarik-fleet:domain:handbook"; export STUB_PANE_ID
  local got; got=$(find_restart_agent_json || true)
  assert_eq "$TMP/sessions/S/.state.json" "$got" "a session rebound to the renamed label is found"
}

test_other_pane_not_stolen() {
  kill_req OTHER "yarik-fleet:domain:studio"
  FLEET_PANE_ID="yarik-fleet:domain:Handbook"
  STUB_PANE_ID="yarik-fleet:domain:handbook"; export STUB_PANE_ID
  local got; got=$(find_restart_agent_json || true)
  assert_eq "" "$got" "another pane's restart is still not taken"
}

test_old_id_no_longer_matches_after_rename() {
  kill_req OLD "yarik-fleet:domain:Handbook"
  FLEET_PANE_ID="yarik-fleet:domain:Handbook"
  STUB_PANE_ID="yarik-fleet:domain:handbook"; export STUB_PANE_ID
  local got; got=$(find_restart_agent_json || true)
  assert_eq "" "$got" "the live id wins over the cached one"
}

test_fleet_sh_failure_falls_back_to_cached() {
  kill_req S "yarik-fleet:domain:Handbook"
  FLEET_PANE_ID="yarik-fleet:domain:Handbook"
  STUB_PANE_ID=""; export STUB_PANE_ID
  local got; got=$(find_restart_agent_json || true)
  assert_eq "$TMP/sessions/S/.state.json" "$got" "when fleet.sh gives nothing, the start-up id is used"
}

test_fleet_sh_failure_keeps_pane_scoping() {
  # Without the fallback FLEET_PANE_ID would go empty, scoping would switch off, and this
  # pane would take another pane's restart.
  kill_req OTHER "yarik-fleet:domain:studio"
  FLEET_PANE_ID="yarik-fleet:domain:Handbook"
  STUB_PANE_ID=""; export STUB_PANE_ID
  local got; got=$(find_restart_agent_json || true)
  assert_eq "" "$got" "when fleet.sh gives nothing, another pane's restart is still not taken"
}

test_non_fleet_mode_unchanged() {
  kill_req ANY "whatever:x:y"
  FLEET_PANE_ID=""
  STUB_PANE_ID="yarik-fleet:domain:handbook"; export STUB_PANE_ID
  local got; got=$(find_restart_agent_json || true)
  assert_eq "$TMP/sessions/ANY/.state.json" "$got" "outside fleet mode any killRequested session is taken, as before"
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$t"
done
exit_with_results
