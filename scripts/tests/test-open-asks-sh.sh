#!/bin/bash
# tests/test-open-asks-sh.sh — Tests for open-asks.sh (lane asks logged with no later answer).
# Run: bash ~/.claude/engine/scripts/tests/test-open-asks-sh.sh
#
# OPEN_ASKS_SH points the suite at a modified copy, which is how each assertion is watched going red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

OPEN_ASKS="${OPEN_ASKS_SH:-$(cd "$(dirname "$0")/.." && pwd)/open-asks.sh}"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

run_check() {
  local out="$1"; shift
  bash "$OPEN_ASKS" "$@" >"$out" 2>"$out.err"
  echo $?
}

write_log() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$@" >"$path"
}

test_an_ask_with_no_answer_is_open_and_exits_3() {
  local s="$TMP_DIR/s1" out="$TMP_DIR/s1.out" rc
  write_log "$s/builds/IDE-171_BUILD_LOG.md" \
    "## [IDE-171] 🚀 Started" "" \
    "## [IDE-171] ❓ Ask base: which base branch?" "*   waiting"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "an unanswered ask exits 3"
  assert_contains "❓ Ask base: which base branch?" "$(cat "$out")" "the ask line is printed"
  assert_contains "IDE-171_BUILD_LOG.md" "$(cat "$out")" "with the log it sits in"
}

test_a_later_answer_closes_the_ask() {
  local s="$TMP_DIR/s2" out="$TMP_DIR/s2.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" \
    "## [A] ❓ Ask base: which base?" \
    "## [A] ✅ Answered base: dev"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "an answered ask exits 0"
  assert_not_contains "❓" "$(cat "$out")" "and is not printed"
}

test_answers_match_by_id_not_by_count() {
  local s="$TMP_DIR/s3" out="$TMP_DIR/s3.out" rc
  write_log "$s/builds/B_BUILD_LOG.md" \
    "## [B] ❓ Ask one: first?" \
    "## [B] ❓ Ask two: second?" \
    "## [B] ✅ Answered one"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "one of two answered still exits 3"
  assert_contains "Ask two" "$(cat "$out")" "the unanswered id is printed"
  assert_not_contains "Ask one" "$(cat "$out")" "the answered id is not"
}

test_an_ask_reopened_after_its_answer_is_open() {
  local s="$TMP_DIR/s4" out="$TMP_DIR/s4.out" rc
  write_log "$s/B_LOG.md" \
    "## [B] ❓ Ask one: first?" \
    "## [B] ✅ Answered one" \
    "## [B] ❓ Ask one: first, again?"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "an ask written after its answer reopens it"
}

test_a_session_path_with_spaces_is_read() {
  local s="$TMP_DIR/Shared drives/s5" out="$TMP_DIR/s5.out" rc
  write_log "$s/builds/C_BUILD_LOG.md" "## [C] ❓ Ask x: y?"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "a path with spaces is scanned"
}

test_no_asks_reports_clean_and_names_how_many_logs_it_read() {
  local s="$TMP_DIR/s6" out="$TMP_DIR/s6.out" rc
  write_log "$s/builds/D_BUILD_LOG.md" "## [D] 🚀 Started"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "no asks exits 0"
  assert_contains "logs read: 1" "$(cat "$out")" "the verdict says how many logs it read"
}

run_discovered_tests
