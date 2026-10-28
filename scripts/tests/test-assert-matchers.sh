#!/bin/bash
# test-assert-matchers.sh — assert_contains / assert_not_contains on haystacks larger than a pipe buffer
set -euo pipefail
source "$(dirname "$0")/test-helpers.sh"

# 200 KB with the needle on the first line: a matcher that pipes echo into grep -q stops reading
# after line one, the writer takes SIGPIPE, and pipefail reports the match as a miss.
big_haystack() {
  printf 'NEEDLE_AT_TOP\n'
  local i
  for i in $(seq 1 4000); do printf 'filler line %05d padded to about fifty bytes.....\n' "$i"; done
  printf 'NEEDLE_AT_END\n'
}

test_contains_matches_early_needle_in_large_output() {
  local hay
  hay=$(big_haystack)
  assert_gt "${#hay}" "65536" "haystack is larger than a pipe buffer"
  assert_contains "NEEDLE_AT_TOP" "$hay" "early match in large output is reported as a match"
  assert_contains "NEEDLE_AT_END" "$hay" "late match in large output is reported as a match"
}

test_not_contains_reports_early_needle_in_large_output() {
  local hay result
  hay=$(big_haystack)
  # Run the negative assertion in a subshell with fresh counters; it must FAIL there.
  result=$( (TESTS_PASSED=0; TESTS_FAILED=0; assert_not_contains "NEEDLE_AT_TOP" "$hay" "inner" >/dev/null; echo "$TESTS_FAILED") )
  assert_eq "1" "$result" "assert_not_contains fails on a needle present early in large output"
}

test_needle_starting_with_dash_is_a_pattern_not_an_option() {
  assert_contains "- item" "$(printf 'a\n- item\n')" "leading-dash needle matches"
  assert_not_contains "- absent" "$(printf 'a\n- item\n')" "leading-dash needle absent"
}

run_discovered_tests
