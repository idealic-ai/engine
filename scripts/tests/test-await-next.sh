#!/bin/bash
# test-await-next.sh — the dual-channel blocking primitive at tools/await-next/
#
# Every arm here was proved by planting its negation: see the BUILD report for
# which guard was broken, which arms reddened, and which did not.

source "$(dirname "$0")/test-helpers.sh"

TOOL="$HOME/.claude/engine/tools/await-next/await-next.sh"
DELEGATOR="$HOME/.claude/engine/scripts/await-next.sh"

TMP_DIR=""
cleanup() {
  cleanup_test_tmux
  [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run the tool, capturing stdout+stderr separately and the real exit status.
# Never reads the status through a pipe.
OUT=""
ERR=""
RC=0
run_tool() {
  OUT=$("$TOOL" "$@" 2>"$TMP_DIR/stderr")
  RC=$?
  ERR=$(cat "$TMP_DIR/stderr" 2>/dev/null)
}

setup_tmpdir() {
  TMP_DIR=$(mktemp -d)
}

# ============================================================
# Argument handling and the error exits (no tmux, no sessions)
# ============================================================

test_tool_is_installed_and_executable() {
  assert_file_exists "$TOOL" "the tool exists at tools/await-next/await-next.sh"
  if [ -x "$TOOL" ]; then
    pass "the tool is executable"
  else
    fail "the tool is executable" "executable" "not executable"
  fi
}

test_help_exits_zero_and_names_every_outcome() {
  run_tool --help
  assert_eq "0" "$RC" "--help exits 0"
  assert_contains "CHILD" "$OUT" "--help names the CHILD outcome"
  assert_contains "WORK" "$OUT" "--help names the WORK outcome"
  assert_contains "TIMEOUT" "$OUT" "--help names the TIMEOUT outcome"
  assert_contains "NOCHANNEL" "$OUT" "--help names the NOCHANNEL outcome"
}

test_unknown_argument_is_a_usage_error() {
  run_tool --not-a-flag
  assert_eq "1" "$RC" "an unknown argument exits 1"
  assert_contains "unknown argument" "$ERR" "and says which argument"
}

test_non_numeric_timeout_is_rejected() {
  run_tool --panes worker-0 --socket "no-such-socket-$$" forever
  assert_eq "1" "$RC" "a non-numeric timeout exits 1"
}

test_timeout_above_the_ceiling_is_refused() {
  run_tool 99999
  assert_eq "1" "$RC" "a timeout above the ceiling exits 1"
  assert_contains "ceiling" "$ERR" "and names the ceiling"
}

test_ceiling_boundary_is_inclusive() {
  # 3600 is the ceiling itself: accepted as an argument. It must not then block,
  # so pair it with no channel at all — NOCHANNEL proves the parse passed.
  run_tool 3600
  assert_eq "2" "$RC" "the ceiling value itself parses (falls through to NOCHANNEL, not exit 1)"
}

test_no_channel_at_all_is_nochannel_not_a_block() {
  run_tool 1 --sessions-dir "$TMP_DIR/absent"
  assert_eq "2" "$RC" "NOCHANNEL exits 2"
  assert_contains "NOCHANNEL" "$OUT" "and says NOCHANNEL on line 1"
  assert_contains "REASON" "$OUT" "and gives the reason"
}

test_claims_without_a_sessions_dir_degrades_to_nochannel() {
  run_tool 1 --claims implementation --sessions-dir "$TMP_DIR/does-not-exist"
  assert_eq "2" "$RC" "a claim with no sessions dir leaves no channel"
  assert_contains "no-sessions-dir" "$OUT" "and the reason names the missing dir"
}

test_managed_panes_without_a_tmux_server_degrades_to_nochannel() {
  run_tool 1 --panes worker-0 --socket "fleet-absent-$$" --sessions-dir "$TMP_DIR/absent"
  assert_eq "2" "$RC" "managed panes with no tmux server leave no channel"
  assert_contains "no-tmux-server" "$OUT" "and the reason names the absent server"
}

# ============================================================
# The child channel (tmux panes)
# ============================================================

test_no_actionable_pane_times_out_as_an_outcome() {
  setup_test_tmux 3
  run_tool 1 --panes worker-0,worker-1,worker-2 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_eq "0" "$RC" "TIMEOUT is an outcome, not an error — exit 0"
  assert_contains "TIMEOUT" "$OUT" "and says TIMEOUT"
  assert_contains "STATUS total=3" "$OUT" "and carries a STATUS line counting the managed panes"
  cleanup_test_tmux
}

test_an_unchecked_pane_returns_child() {
  setup_test_tmux 3
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[1]}" @pane_notify unchecked
  run_tool 1 --panes worker-0,worker-1,worker-2 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_eq "0" "$RC" "a CHILD event exits 0"
  assert_contains "CHILD" "$OUT" "and says CHILD"
  assert_contains "${TEST_TMUX_PANES[1]}|unchecked|Worker1" "$OUT" "and names the pane, its state and its label"
  cleanup_test_tmux
}

test_child_carries_a_capture_json_line() {
  setup_test_tmux 2
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify unchecked
  run_tool 1 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  local json
  json=$(printf '%s\n' "$OUT" | sed -n '2p')
  assert_contains '"pane"' "$json" "line 2 of a CHILD result is JSON naming the pane"
  assert_contains '"state"' "$json" "and the state"
  # "lines" exists only on the successful-capture branch. Without this, the arm
  # is satisfied by the {…,"error":"capture failed"} fallback, which is what a
  # detached tmux server produces for an empty pane — so the arm would pass
  # while the capture path was broken.
  assert_contains '"lines"' "$json" "and it is the successful-capture shape, not the capture-failed fallback"
  assert_not_contains 'capture failed' "$json" "a blank pane is a capture of nothing, not a failed capture"
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
      pass "the capture line is parseable JSON"
    else
      fail "the capture line is parseable JSON" "valid JSON" "$json"
    fi
  else
    skip "the capture line is parseable JSON" "jq not installed"
  fi
  cleanup_test_tmux
}

test_error_outranks_done() {
  setup_test_tmux 3
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify done
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[2]}" @pane_notify error
  run_tool 1 --panes worker-0,worker-1,worker-2 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "CHILD ${TEST_TMUX_PANES[2]}|error" "$OUT" "error is picked over done regardless of pane order"
  cleanup_test_tmux
}

test_unchecked_outranks_done() {
  setup_test_tmux 3
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify done
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[2]}" @pane_notify unchecked
  run_tool 1 --panes worker-0,worker-1,worker-2 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "CHILD ${TEST_TMUX_PANES[2]}|unchecked" "$OUT" "unchecked is picked over done regardless of pane order"
  cleanup_test_tmux
}

test_error_outranks_unchecked() {
  setup_test_tmux 3
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify unchecked
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[2]}" @pane_notify error
  run_tool 1 --panes worker-0,worker-1,worker-2 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "CHILD ${TEST_TMUX_PANES[2]}|error" "$OUT" "error is picked over unchecked regardless of pane order"
  cleanup_test_tmux
}

test_a_user_focused_pane_yields_focused_not_child() {
  setup_test_tmux 2
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify unchecked
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_user_focused 1
  run_tool 1 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_eq "0" "$RC" "FOCUSED exits 0"
  assert_contains "FOCUSED" "$OUT" "the only actionable pane being user-focused yields FOCUSED"
  assert_not_contains "CHILD" "$OUT" "and never hands the user's pane to the coordinator"
  cleanup_test_tmux
}

test_the_pane_filter_excludes_an_unmanaged_pane() {
  setup_test_tmux 3
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[2]}" @pane_notify error
  run_tool 1 --panes worker-0 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "TIMEOUT" "$OUT" "an actionable pane outside --panes is not picked up"
  assert_contains "STATUS total=1" "$OUT" "and STATUS counts only the managed pane"
  cleanup_test_tmux
}

test_sweep_first_returns_without_waiting_out_the_timeout() {
  setup_test_tmux 2
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify error
  local t0 t1
  t0=$(date +%s)
  run_tool 30 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  t1=$(date +%s)
  assert_contains "CHILD" "$OUT" "an already-actionable pane is swept before any blocking"
  if [ $((t1 - t0)) -lt 5 ]; then
    pass "sweep-first returns in under 5s against a 30s timeout (took $((t1 - t0))s)"
  else
    fail "sweep-first returns in under 5s against a 30s timeout" "<5s" "$((t1 - t0))s"
  fi
  cleanup_test_tmux
}

test_the_timeout_ceiling_actually_bounds_the_wait() {
  setup_test_tmux 2
  local t0 t1 elapsed
  t0=$(date +%s)
  run_tool 2 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  assert_contains "TIMEOUT" "$OUT" "a 2s wait with nothing to find ends in TIMEOUT"
  if [ "$elapsed" -ge 1 ] && [ "$elapsed" -le 8 ]; then
    pass "the wait is bounded: it blocked for ${elapsed}s, between the 2s ask and a generous ceiling"
  else
    fail "the wait is bounded near the requested 2s" "1..8s" "${elapsed}s"
  fi
  cleanup_test_tmux
}

test_a_spurious_wake_does_not_end_the_wait_early() {
  # A wake says "something changed", never "something is actionable"
  # (§INV_WAKE_ON_ACTIONABLE_STATES: the sweep is truth). Fire the signal with
  # nothing actionable behind it: the call must still run out its own ceiling.
  setup_test_tmux 2
  ( sleep 1; tmux -L "$TEST_TMUX_SOCKET" wait-for -S coordinator-wake 2>/dev/null ) &
  local waker=$!
  local t0 t1 elapsed
  t0=$(date +%s)
  run_tool 6 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  kill "$waker" 2>/dev/null || true
  assert_contains "TIMEOUT" "$OUT" "a wake with nothing behind it still ends in TIMEOUT"
  if [ "$elapsed" -ge 4 ]; then
    pass "and it ran out its 6s ceiling rather than returning on the wake (${elapsed}s)"
  else
    fail "a spurious wake must not short-circuit the wait" ">=4s of a 6s ceiling" "${elapsed}s"
  fi
  cleanup_test_tmux
}

test_zero_timeout_is_sweep_only() {
  setup_test_tmux 2
  local t0 t1
  t0=$(date +%s)
  run_tool 0 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  t1=$(date +%s)
  assert_contains "TIMEOUT" "$OUT" "a zero timeout with nothing to find returns a named outcome"
  if [ $((t1 - t0)) -le 3 ]; then
    pass "a zero timeout does not block (took $((t1 - t0))s)"
  else
    fail "a zero timeout does not block" "<=3s" "$((t1 - t0))s"
  fi
  # Asserting only the speed above would survive the removal of the sweep itself,
  # so require that a zero timeout still SWEEPS.
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[1]}" @pane_notify error
  run_tool 0 --panes worker-0,worker-1 --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "CHILD ${TEST_TMUX_PANES[1]}|error" "$OUT" "a zero timeout still sweeps, so an actionable pane comes back with no wait"
  cleanup_test_tmux
}

# ============================================================
# The work channel (delegation tags under sessions/)
# ============================================================

plant_tag() {
  local file="$1" tag="$2"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# A delegation request

**Tags**: $tag

Body text.
EOF
}

test_an_untargeted_tag_is_found_and_claimed() {
  local sdir="$TMP_DIR/w1/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation"
  run_tool 1 --claims implementation --sessions-dir "$sdir"
  assert_eq "0" "$RC" "a WORK event exits 0"
  assert_contains "WORK " "$OUT" "and says WORK"
  assert_contains "#delegated-implementation" "$OUT" "naming the tag it found"
  assert_contains "CLAIMED" "$OUT" "and reports the claim"
  assert_contains "#claimed-implementation" "$(cat "$sdir/s1/REQUEST.md")" "the file now carries #claimed-"
  assert_not_contains "#delegated-implementation" "$(cat "$sdir/s1/REQUEST.md")" "and no longer carries #delegated-"
}

test_an_already_claimed_tag_is_not_re_served() {
  local sdir="$TMP_DIR/w2/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#claimed-implementation"
  run_tool 1 --claims implementation --sessions-dir "$sdir"
  assert_contains "TIMEOUT" "$OUT" "work already claimed is not handed out again"
  assert_not_contains "WORK " "$OUT" "and no WORK line is emitted"
}

test_a_tag_for_another_noun_is_ignored() {
  local sdir="$TMP_DIR/w3/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-research"
  run_tool 1 --claims implementation --sessions-dir "$sdir"
  assert_contains "TIMEOUT" "$OUT" "a noun this worker does not claim is left alone"
  assert_contains "#delegated-research" "$(cat "$sdir/s1/REQUEST.md")" "and the tag is untouched"
}

test_a_targeted_tag_for_somebody_else_is_left_alone() {
  local sdir="$TMP_DIR/w4/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation %auth:Worker-9"
  run_tool 1 --claims implementation --targeted-claims implementation \
            --pane "auth:Worker-1" --sessions-dir "$sdir"
  assert_contains "TIMEOUT" "$OUT" "a tag targeted at another pane is not claimed"
  assert_contains "#delegated-implementation" "$(cat "$sdir/s1/REQUEST.md")" "and the tag is untouched"
}

test_a_targeted_tag_for_us_is_claimed() {
  local sdir="$TMP_DIR/w5/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation %auth:Worker-1"
  run_tool 1 --claims implementation --targeted-claims implementation \
            --pane "auth:Worker-1" --sessions-dir "$sdir"
  assert_contains "WORK " "$OUT" "a tag targeted at this pane is claimed"
  assert_contains "#claimed-implementation" "$(cat "$sdir/s1/REQUEST.md")" "and the file records the claim"
}

test_a_targeted_only_worker_leaves_untargeted_work_alone() {
  local sdir="$TMP_DIR/w6/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation"
  run_tool 1 --targeted-claims implementation --pane "auth:Worker-1" --sessions-dir "$sdir"
  assert_contains "TIMEOUT" "$OUT" "untargeted work needs an ordinary claim, not a targeted one"
  assert_contains "#delegated-implementation" "$(cat "$sdir/s1/REQUEST.md")" "and the tag is untouched"
}

test_the_claim_leaves_no_lock_behind() {
  local sdir="$TMP_DIR/w7/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation"
  run_tool 1 --claims implementation --sessions-dir "$sdir"
  assert_contains "CLAIMED" "$OUT" "the claim succeeded"
  assert_dir_exists "$sdir/s1" "the session dir survives"
  if [ -d "$sdir/s1/REQUEST.md.await-next.lock" ]; then
    fail "the claim lock is released" "no lock dir" "lock dir still present"
  else
    pass "the claim lock is released"
  fi
}

test_a_held_lock_blocks_the_claim_rather_than_corrupting_the_file() {
  local sdir="$TMP_DIR/w8/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation"
  mkdir -p "$sdir/s1/REQUEST.md.await-next.lock"
  run_tool 0 --claims implementation --sessions-dir "$sdir"
  assert_contains "#delegated-implementation" "$(cat "$sdir/s1/REQUEST.md")" "a file whose lock is held is not rewritten"
  assert_not_contains "WORK " "$OUT" "and no WORK is handed back for work we could not claim"
  rmdir "$sdir/s1/REQUEST.md.await-next.lock"
}

# ============================================================
# Both channels at once
# ============================================================

test_children_come_before_work() {
  setup_test_tmux 2
  local sdir="$TMP_DIR/both/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation"
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify unchecked
  run_tool 1 --panes worker-0,worker-1 --claims implementation \
            --sessions-dir "$sdir" --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "CHILD" "$OUT" "with both channels hot, the child wins"
  assert_not_contains "WORK " "$OUT" "and the tag is not claimed in the same call"
  assert_contains "#delegated-implementation" "$(cat "$sdir/s1/REQUEST.md")" "so the tag is still available next call"
  cleanup_test_tmux
}

test_work_outranks_a_focused_pane() {
  setup_test_tmux 2
  local sdir="$TMP_DIR/focwork/sessions"
  plant_tag "$sdir/s1/REQUEST.md" "#delegated-implementation"
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_notify unchecked
  tmux -L "$TEST_TMUX_SOCKET" set-option -p -t "${TEST_TMUX_PANES[0]}" @pane_user_focused 1
  run_tool 1 --panes worker-0,worker-1 --claims implementation \
            --sessions-dir "$sdir" --socket "$TEST_TMUX_SOCKET" --no-connect
  assert_contains "WORK " "$OUT" "a user-focused pane does not starve claimable work"
  cleanup_test_tmux
}

# ============================================================
# Reachability through the engine CLI
# ============================================================

test_the_delegator_reaches_the_engine_tool() {
  local out rc
  out=$(cd "$TMP_DIR" && "$DELEGATOR" --help 2>&1)
  rc=$?
  assert_eq "0" "$rc" "the delegator resolves to a real tool and exits 0 on --help"
  assert_contains "await-next.sh" "$out" "and the help text comes from the tool, not the not-found error"
  assert_not_contains "await-next tool not found" "$out" "the not-found branch is no longer reached"
}

test_the_delegator_still_prefers_a_project_local_tool() {
  local proj="$TMP_DIR/proj"
  mkdir -p "$proj/.claude" "$proj/tools/await-next"
  cat > "$proj/tools/await-next/await-next.sh" <<'STUB'
#!/bin/bash
echo "PROJECT_LOCAL_STUB"
exit 0
STUB
  chmod +x "$proj/tools/await-next/await-next.sh"
  local out
  out=$(cd "$proj" && "$DELEGATOR" --help 2>&1)
  assert_contains "PROJECT_LOCAL_STUB" "$out" "a project-local tool still overrides the engine copy"
}

setup_tmpdir
run_discovered_tests
