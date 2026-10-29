#!/bin/bash
# test-test-helpers.sh — assert_contains / assert_not_contains go red when they should.
#
# Every case runs the helper in a subshell on a fresh copy of the helpers and reads the
# pass/fail counters it left behind, so a helper that passes without checking is caught
# here rather than trusted. Large-text (SIGPIPE) cases and the dash-led cases that pass
# live in test-assert-matchers.sh and are not repeated here.
#
# TEST_HELPERS_UNDER_TEST points the cases at another copy of the helpers (to plant an old
# defect and watch this suite go red). The runner's own counters always come from the real
# file next to this one.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/test-helpers.sh"

UNDER_TEST="${TEST_HELPERS_UNDER_TEST:-$HERE/test-helpers.sh}"

# _verdict HELPER ARGS... -> prints "PASSED FAILED" from a fresh copy of the helpers.
_verdict() {
  (
    unset _TEST_HELPERS_LOADED
    # shellcheck disable=SC1090
    source "$UNDER_TEST"
    set -o pipefail
    "$@" > /dev/null 2>&1
    echo "$TESTS_PASSED $TESTS_FAILED"
  )
}

_expect() {
  local want="$1" label="$2"; shift 2
  local got; got=$(_verdict "$@")
  case "$want" in
    pass) assert_eq "1 0" "$got" "$label" ;;
    fail) assert_eq "0 1" "$got" "$label" ;;
  esac
}

# ---- dash-led patterns -------------------------------------------------------

test_dash_pattern_present() {
  _expect fail "assert_not_contains FAILS on a present dash-led pattern" \
    assert_not_contains "--to" "claude --to worker-3 --resume" "m"
  _expect fail "assert_not_contains FAILS on a present single-dash pattern" \
    assert_not_contains "-e" "grep -e x" "m"
}

test_dash_pattern_absent() {
  _expect fail "assert_contains FAILS on an absent dash-led pattern" \
    assert_contains "--to" "claude --resume only" "m"
}

# echo eats a lone -n / -e as its own option; the text must reach grep as written.
test_dash_led_text_reaches_grep() {
  _expect pass "assert_contains sees a text that is just '-n'" \
    assert_contains "-n" "-n" "m"
  _expect fail "assert_not_contains sees a text that is just '-e'" \
    assert_not_contains "-e" "-e" "m"
}

# ---- a grep that cannot run --------------------------------------------------

# A grep exiting 2 checked nothing, so "absent" must not be read from it.
_with_broken_grep() {
  grep() { return 2; }
  "$@"
}

test_grep_error_is_a_failure_not_a_pass() {
  _expect fail "assert_not_contains FAILS when grep exits 2" \
    _with_broken_grep assert_not_contains "anything" "some text" "m"
  _expect fail "assert_contains FAILS when grep exits 2" \
    _with_broken_grep assert_contains "some" "some text" "m"
}

# ---- regex behaviour ---------------------------------------------------------
# assert_contains is the one helper that takes a regex: a fixed-string match first,
# then a basic (BRE) regex. assert_not_contains is fixed-string only.

test_assert_contains_regex_fallback() {
  _expect pass "assert_contains matches a BRE regex" \
    assert_contains "fo*bar" "foooobar" "m"
  _expect pass "assert_contains matches an anchored BRE regex" \
    assert_contains "^line two$" $'line one\nline two' "m"
  _expect fail "assert_contains fails when neither literal nor regex matches" \
    assert_contains "fo*bar" "fxbar" "m"
  _expect pass "assert_contains still matches regex metacharacters literally" \
    assert_contains "a[1" "x a[1 y" "m"
  _expect fail "assert_contains is BRE, not ERE: 'a+' does not match 'aa'" \
    assert_contains "a+" "aa" "m"
}

test_assert_not_contains_is_literal() {
  _expect pass "assert_not_contains treats '.' literally (a.c is absent from abc)" \
    assert_not_contains "a.c" "abc" "m"
  _expect fail "assert_not_contains finds a literal regex-looking string" \
    assert_not_contains "a.c" "x a.c y" "m"
}

run_discovered_tests
