#!/bin/bash
# test-run-all.sh — Tests for run_discovered_tests, TEST_FILTER, file pre-filtering, and e2e discovery
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

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

# Run
run_test test_discovered_tests_runs_all
run_test test_filter_matches_function
run_test test_filter_no_match_exits_zero
run_test test_file_prefilter_skips_nonmatching
run_test test_grep_flag_parsed
run_test test_e2e_recursive_discovery
exit_with_results
