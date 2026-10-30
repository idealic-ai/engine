#!/bin/bash
# test-run-all.sh — Tests for run_discovered_tests, TEST_FILTER, file pre-filtering, and e2e discovery
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
# RUN_ALL_SH points the verdict tests at another copy of the runner (origin/main's, to watch
# them go red before trusting them).
RUN_ALL="${RUN_ALL_SH:-$TESTS_DIR/run-all.sh}"

# ============================================================
# Test 1: run_discovered_tests discovers and runs all test_* functions
# ============================================================
test_discovered_tests_runs_all() {
  local tmp
  tmp=$(mktemp -d)

  cat > "$tmp/test-sample.sh" <<'SAMPLE'
#!/bin/bash
source "$(dirname "$0")/test-helpers.sh"
test_alpha() { pass "alpha ran"; }
test_beta() { pass "beta ran"; }
run_discovered_tests
SAMPLE

  # Symlink test-helpers.sh so the sample can find it
  mkdir -p "$tmp/nested"
  ln -sf "$TESTS_DIR/test-helpers.sh" "$tmp/test-helpers.sh"

  local output
  output=$(bash "$tmp/test-sample.sh" 2>&1)
  local rc=$?

  assert_eq "0" "$rc" "run_discovered_tests exits 0 when all pass"
  assert_contains "alpha ran" "$output" "test_alpha was discovered and ran"
  assert_contains "beta ran" "$output" "test_beta was discovered and ran"
  assert_contains "2 passed" "$output" "reports 2 passed"

  rm -rf "$tmp"
}

# ============================================================
# Test 2: TEST_FILTER only runs matching functions
# ============================================================
test_filter_matches_function() {
  local tmp
  tmp=$(mktemp -d)

  cat > "$tmp/test-filter.sh" <<'SAMPLE'
#!/bin/bash
source "$(dirname "$0")/test-helpers.sh"
test_session_activate() { pass "session_activate ran"; }
test_session_phase() { pass "session_phase ran"; }
test_tag_add() { pass "tag_add ran"; }
run_discovered_tests
SAMPLE

  ln -sf "$TESTS_DIR/test-helpers.sh" "$tmp/test-helpers.sh"

  local output
  output=$(TEST_FILTER="session" bash "$tmp/test-filter.sh" 2>&1)

  assert_contains "session_activate ran" "$output" "session_activate matched filter"
  assert_contains "session_phase ran" "$output" "session_phase matched filter"
  assert_not_contains "tag_add ran" "$output" "tag_add was filtered out"
  assert_contains "2 passed" "$output" "only 2 tests ran"

  rm -rf "$tmp"
}

# ============================================================
# Test 3: TEST_FILTER=nonexistent runs zero tests, exits 0
# ============================================================
test_filter_no_match_exits_zero() {
  local tmp
  tmp=$(mktemp -d)

  cat > "$tmp/test-empty.sh" <<'SAMPLE'
#!/bin/bash
source "$(dirname "$0")/test-helpers.sh"
test_something() { pass "should not run"; }
run_discovered_tests
SAMPLE

  ln -sf "$TESTS_DIR/test-helpers.sh" "$tmp/test-helpers.sh"

  local output
  output=$(TEST_FILTER="nonexistent" bash "$tmp/test-empty.sh" 2>&1)
  local rc=$?

  assert_eq "0" "$rc" "exits 0 when no tests match"
  assert_contains "0 passed" "$output" "reports 0 passed"
  assert_not_contains "should not run" "$output" "test_something did not run"

  rm -rf "$tmp"
}

# ============================================================
# Test 4: File pre-filter skips files with no matching functions
# ============================================================
test_file_prefilter_skips_nonmatching() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/tests"

  # Create two test files
  cat > "$tmp/tests/test-session.sh" <<'SAMPLE'
#!/bin/bash
source "$(dirname "$0")/test-helpers.sh"
test_session_foo() { pass "session_foo"; }
run_discovered_tests
SAMPLE

  cat > "$tmp/tests/test-tag.sh" <<'SAMPLE'
#!/bin/bash
source "$(dirname "$0")/test-helpers.sh"
test_tag_bar() { pass "tag_bar"; }
run_discovered_tests
SAMPLE

  ln -sf "$TESTS_DIR/test-helpers.sh" "$tmp/tests/test-helpers.sh"
  cp "$TESTS_DIR/run-all.sh" "$tmp/tests/run-all.sh"

  local output
  output=$(TEST_FILTER="session" bash "$tmp/tests/run-all.sh" 2>&1)

  assert_contains "test-session.sh" "$output" "session file was run"
  assert_not_contains "test-tag.sh" "$output" "tag file was skipped by pre-filter"

  rm -rf "$tmp"
}

# ============================================================
# Test 5: --grep flag is parsed and sets TEST_FILTER
# ============================================================
test_grep_flag_parsed() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/tests"

  cat > "$tmp/tests/test-helpers.sh" <<'STUB'
#!/bin/bash
[ -n "${_TEST_HELPERS_LOADED:-}" ] && return 0
_TEST_HELPERS_LOADED=1
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
pass() { echo "PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }
fail() { echo "FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }
run_test() {
  local name="$1"
  if [ -n "${TEST_FILTER:-}" ]; then
    case "$name" in *"$TEST_FILTER"*) ;; *) return 0 ;; esac
  fi
  eval "$name"
}
run_discovered_tests() {
  local fn
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    run_test "$fn"
  done < <(declare -F | awk '{print $3}' | grep '^test_' || true)
  echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed (${TESTS_RUN} total)"
  [ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
}
print_results() { echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed (${TESTS_RUN} total)"; }
exit_with_results() { print_results; [ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1; }
STUB

  cat > "$tmp/tests/test-one.sh" <<'SAMPLE'
#!/bin/bash
source "$(dirname "$0")/test-helpers.sh"
test_alpha() { pass "alpha"; }
test_beta() { pass "beta"; }
run_discovered_tests
SAMPLE

  cp "$TESTS_DIR/run-all.sh" "$tmp/tests/run-all.sh"

  local output
  output=$(bash "$tmp/tests/run-all.sh" --grep alpha 2>&1)

  assert_contains "alpha" "$output" "alpha test ran with --grep"
  assert_not_contains "beta" "$output" "beta was filtered out by --grep"

  rm -rf "$tmp"
}

# ============================================================
# Test 6: E2e recursive discovery finds tests in subdirectories
# ============================================================
test_e2e_recursive_discovery() {
  local e2e_dir="$TESTS_DIR/e2e"

  if [ ! -d "$e2e_dir" ]; then
    skip "e2e directory not found" "run from engine tests dir"
    return
  fi

  local count
  count=$(find "$e2e_dir" -name 'test-*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')

  assert_gt "$count" "1" "e2e recursive discovery finds >1 test files (found $count)"

  # Verify protocol subdirectory is included
  local protocol_count
  protocol_count=$(find "$e2e_dir/protocol" -name 'test-*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')

  assert_gt "$protocol_count" "0" "protocol/ tests are discoverable under e2e/ (found $protocol_count)"
}

# ============================================================
# Verdict tests (LOOMINSTR Fix 1). A suite's exit status alone is not its verdict.
# plant_suite <dir> <name> <body> writes a suite that prints <body> and exits per the body.
# ============================================================
plant_runner() {
  local dir="$1"
  mkdir -p "$dir/tests"
  ln -sf "$TESTS_DIR/test-helpers.sh" "$dir/tests/test-helpers.sh"
  cp "$RUN_ALL" "$dir/tests/run-all.sh"
}
plant_suite() {
  printf '#!/bin/bash\n%s\n' "$3" > "$1/tests/$2"
}

# Control: an honest green suite is still a pass, and a passing line that merely NAMES failure
# ("PASS: bad JSON produces FAIL") does not condemn it.
test_verdict_control_green_suite_passes() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-good.sh 'echo "PASS: bad JSON produces FAIL"; echo "Results: 2 passed, 0 failed (2 total)"; exit 0'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "0" "$rc" "an honest green suite leaves run-all at exit 0"
  assert_contains "ALL 1 SUITES PASSED" "$output" "the honest suite is counted a pass"
  rm -rf "$tmp"
}

# A bare "N passed, M failed" tally is a results line too; without it three honest suites in this
# tree read as having no tally. RED: drop the bare shape from RESULTS_LINE_RE.
test_verdict_bare_tally_shape_passes() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-bare.sh 'echo "  ok   a case"; echo; echo "21 passed, 0 failed"; exit 0'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "0" "$rc" "a bare tally suite leaves run-all at exit 0"
  assert_contains "(21 passed)" "$output" "the bare tally's count is read"
  rm -rf "$tmp"
}

# RED on main: the suite prints FAIL and exits 0; main ticks it and exits 0.
test_verdict_fail_line_at_exit_zero_is_red() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-liar.sh 'echo "FAIL: the thing is BROKEN"; echo "Results: 1 passed, 1 failed (2 total)"; exit 0'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "1" "$rc" "a suite that prints FAIL and exits 0 makes run-all exit 1"
  assert_contains "1/1 SUITES FAILED" "$output" "the lying suite is counted a failure"
  assert_contains "failure line" "$output" "the row names the reason"
  rm -rf "$tmp"
}

# RED on main: a suite that ran zero cases is displayed "(0 passed)" and ticked.
test_verdict_zero_cases_is_red() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-empty.sh 'echo "Results: 0 passed, 0 failed (0 total)"; exit 0'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "1" "$rc" "a suite that ran zero cases makes run-all exit 1"
  assert_contains "ran 0 cases" "$output" "the row says nothing was checked"
  rm -rf "$tmp"
}

# RED on main: a suite with no results line at all is ticked on its exit status.
test_verdict_missing_results_line_is_red() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-silent.sh 'exit 0'
  local rc
  bash "$tmp/tests/run-all.sh" >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "a suite with no results line makes run-all exit 1"
  rm -rf "$tmp"
}

# A hung suite under an opted-in budget is killed, named as a timeout, and the suite after it
# still runs and is counted. The planted sleep writes its pid, and the test checks it is GONE.
# RED: drop the timeout, or let the kill miss the suite's process group.
test_verdict_hung_suite_times_out_and_later_suites_run() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-a-hang.sh "sleep 30 & echo \$! > '$tmp/hang.pid'; wait; echo 'Results: 1 passed, 0 failed (1 total)'"
  plant_suite "$tmp" test-b-after.sh 'echo "Results: 1 passed, 0 failed (1 total)"; exit 0'
  local output rc
  # The outer bound only stops a runner with no timeout from holding this suite for 30s.
  output=$(ENGINE_TEST_TIMEOUT=2 perl -e 'alarm 15; exec @ARGV' bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "1" "$rc" "a hung suite makes run-all exit 1, not hang"
  assert_contains "TIMEOUT after" "$output" "the hung suite's row names the timeout"
  assert_contains "load" "$output" "the timeout row carries the load"
  assert_contains "test-b-after.sh" "$output" "the suite after the hang still ran"
  assert_contains "1/2 SUITES FAILED" "$output" "both suites are counted"
  local hp; hp=$(cat "$tmp/hang.pid" 2>/dev/null)
  if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then pass "the hung suite's sleep was killed"
  else fail "the hung suite's sleep was killed" "pid $hp gone" "still alive"; kill "$hp" 2>/dev/null; fi
  rm -rf "$tmp"
}

# The timeout is opt-in: with ENGINE_TEST_TIMEOUT unset a slow honest suite is green, and the
# header says no budget applies. RED: restore a default budget shorter than the suite.
test_verdict_timeout_is_opt_in() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-slow.sh 'sleep 3; echo "Results: 1 passed, 0 failed (1 total)"; exit 0'
  local output rc
  output=$(env -u ENGINE_TEST_TIMEOUT bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "0" "$rc" "a slow honest suite is green with no budget set"
  assert_contains "per-suite timeout off" "$output" "the header says the run is unbounded"
  rm -rf "$tmp"
}

# A suite's OWN exit 124 is an ordinary red exit, not a timeout. RED: map 124 to TIMEOUT unconditionally.
test_verdict_own_124_is_not_a_timeout() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-own124.sh 'echo "Results: 1 passed, 0 failed (1 total)"; exit 124'
  local output
  output=$(ENGINE_TEST_TIMEOUT=60 bash "$tmp/tests/run-all.sh" 2>&1)
  assert_contains "exit 124" "$output" "the row reads the suite's own exit 124"
  assert_not_contains "TIMEOUT after" "$output" "and does not call it a timeout"
  rm -rf "$tmp"
}

# A suite whose every case SKIPped ran nothing on this machine: green, with a note saying so, and
# the summary counts it. Driven through the real test-helpers.sh, so the helper's results line
# and the runner's reading of it are tested together. RED: treat 0 passed as red even when every
# case skipped, or leave the summary silent about it.
test_verdict_all_skipped_is_green_with_a_note() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-skips.sh 'source "$(dirname "$0")/test-helpers.sh"
test_a() { skip "needs a tool" "not installed"; }
test_b() { skip "another"; }
run_discovered_tests'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "0" "$rc" "an all-skipped suite leaves run-all at exit 0"
  assert_contains "2 skipped" "$output" "the row counts the skips"
  assert_contains "nothing ran on this machine" "$output" "the row says nothing ran"
  assert_contains "1 suite(s) ran nothing" "$output" "the summary banner says how many suites ran nothing"
  rm -rf "$tmp"
}

# One case skipped and the others asserted nothing: that is not "every case skipped". RED: pass
# any 0-passed suite that printed a SKIP line.
test_verdict_some_skipped_rest_empty_is_red() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-partskip.sh 'echo "SKIP: case one needs X"; echo "Results: 0 passed, 0 failed (3 total)"; exit 0'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "1" "$rc" "a suite where 1 of 3 cases skipped and none passed is red"
  assert_contains "1 of 3" "$output" "the row says how many of the total skipped"
  rm -rf "$tmp"
}

# The skip count is read with grep -c, never grep -q in a pipe: under pipefail a large output
# makes grep -q's early exit SIGPIPE the producer and the test read false (N1). RED: probe with
# printf | grep -q.
test_verdict_all_skipped_reads_the_same_with_large_output() {
  local tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-bigskip.sh 'echo "SKIP: only case"; for i in $(seq 1 20000); do echo "noise line $i"; done; echo "Results: 0 passed, 0 failed, 1 skipped (1 total)"; exit 0'
  local output rc
  output=$(bash "$tmp/tests/run-all.sh" 2>&1); rc=$?
  assert_eq "0" "$rc" "an all-skipped suite with 20000 lines of output is still green"
  rm -rf "$tmp"
}

# INT or TERM to the runner stops the running suite and its children. RED: run the suite in a
# process group the runner does not kill (main's runner under a timeout, or no trap).
interrupt_arm() {
  local sig="$1" tmp; tmp=$(mktemp -d); plant_runner "$tmp"
  plant_suite "$tmp" test-long.sh "echo \$\$ > '$tmp/suite.pid'; sleep 30 & echo \$! > '$tmp/child.pid'; wait"
  # INT restored to default: an async command in a script starts with INT ignored, and bash
  # cannot trap a signal ignored on entry.
  ENGINE_TEST_TIMEOUT="${2:-0}" perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' bash "$tmp/tests/run-all.sh" >"$tmp/out" 2>&1 &
  local rpid=$! i
  for i in $(seq 1 50); do [ -s "$tmp/child.pid" ] && break; sleep 0.1; done
  kill "-$sig" "$rpid"
  wait "$rpid"; local rc=$?
  sleep 0.5
  local sp cp; sp=$(cat "$tmp/suite.pid" 2>/dev/null); cp=$(cat "$tmp/child.pid" 2>/dev/null)
  assert_eq "130" "$rc" "$sig (budget ${2:-0}): the runner exits 130"
  if [ -n "$sp" ] && ! kill -0 "$sp" 2>/dev/null; then pass "$sig (budget ${2:-0}): the running suite is gone"
  else fail "$sig (budget ${2:-0}): the running suite is gone" "pid $sp gone" "alive"; kill "$sp" 2>/dev/null; fi
  if [ -n "$cp" ] && ! kill -0 "$cp" 2>/dev/null; then pass "$sig (budget ${2:-0}): the suite's child is gone"
  else fail "$sig (budget ${2:-0}): the suite's child is gone" "pid $cp gone" "alive"; kill "$cp" 2>/dev/null; fi
  rm -rf "$tmp"
}
test_interrupt_stops_the_running_suite() {
  interrupt_arm INT 0
  interrupt_arm INT 60
  interrupt_arm TERM 60
}

# Run
run_test test_discovered_tests_runs_all
run_test test_filter_matches_function
run_test test_filter_no_match_exits_zero
run_test test_file_prefilter_skips_nonmatching
run_test test_grep_flag_parsed
run_test test_e2e_recursive_discovery
run_test test_verdict_control_green_suite_passes
run_test test_verdict_bare_tally_shape_passes
run_test test_verdict_fail_line_at_exit_zero_is_red
run_test test_verdict_zero_cases_is_red
run_test test_verdict_missing_results_line_is_red
run_test test_verdict_hung_suite_times_out_and_later_suites_run
run_test test_verdict_timeout_is_opt_in
run_test test_verdict_own_124_is_not_a_timeout
run_test test_verdict_all_skipped_is_green_with_a_note
run_test test_verdict_some_skipped_rest_empty_is_red
run_test test_verdict_all_skipped_reads_the_same_with_large_output
run_test test_interrupt_stops_the_running_suite
exit_with_results
