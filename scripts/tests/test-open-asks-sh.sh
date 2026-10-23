#!/bin/bash
# tests/test-open-asks-sh.sh — Tests for open-asks.sh (lane asks logged with no later answer).
# Run: bash ~/.claude/engine/scripts/tests/test-open-asks-sh.sh
#
# OPEN_ASKS_SH points the suite at a modified copy, which is how each assertion is watched going red.
# Fixtures that matter are written through the real log.sh, so headings carry the timestamp bracket
# `engine log` injects before the tag.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
OPEN_ASKS="${OPEN_ASKS_SH:-$SCRIPTS/open-asks.sh}"
LOG_SH="$SCRIPTS/log.sh"

TMP_DIR=$(mktemp -d)
cleanup() { chmod -R u+rwx "$TMP_DIR" 2>/dev/null; rm -rf "$TMP_DIR"; }
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

# Appends one entry exactly as `engine log` does: timestamp injected into the first heading.
elog() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  bash "$LOG_SH" "$path" >/dev/null
}

test_an_ask_with_no_answer_is_open_and_exits_3() {
  local s="$TMP_DIR/s1" out="$TMP_DIR/s1.out" rc
  write_log "$s/builds/IDE-171_BUILD_LOG.md" \
    "## [IDE-171] 🚀 Started" "" \
    "## [IDE-171] ❓ Ask base: which base branch?" "*   waiting"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "an unanswered ask exits 3"
  assert_contains "❓ Ask base: which base branch?" "$(cat "$out")" "the ask line is printed"
  assert_contains "logpath=$s/builds/IDE-171_BUILD_LOG.md" "$(cat "$out")" "with its log, as logpath= at the end"
}

test_a_timestamped_ask_written_by_engine_log_is_found_and_closed() {
  local s="$TMP_DIR/ts" out="$TMP_DIR/ts.out" rc log="$TMP_DIR/ts/builds/A_BUILD_LOG.md"
  elog "$log" <<'EOF'
## [A] ❓ Ask base: which base?
*   waiting
EOF
  assert_contains "] [A] ❓ Ask base" "$(cat "$log")" "fixture carries the injected timestamp bracket"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "a timestamped ask is open"
  elog "$log" <<'EOF'
## [A] ✅ Answered base: dev
EOF
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "a timestamped answer closes it"
}

test_a_later_answer_closes_the_ask() {
  local s="$TMP_DIR/s2" out="$TMP_DIR/s2.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" \
    "## [A] ❓ Ask base: which base?" \
    "## [A] ✅ Answered base: dev"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "an answered ask exits 0"
  assert_not_contains "OPEN" "$(cat "$out")" "and is not printed"
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

test_an_answer_under_another_lanes_tag_does_not_close() {
  local s="$TMP_DIR/xt" out="$TMP_DIR/xt.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" \
    "## [A] ❓ Ask base: which base?" \
    "## [B] ✅ Answered base: dev"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "[B]'s answer leaves [A]'s ask open"
}

test_a_quoted_ask_in_a_bullet_is_not_an_ask() {
  local s="$TMP_DIR/q" out="$TMP_DIR/q.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" \
    "## [A] 🚀 Started" \
    '*   format is `## [A] ❓ Ask base: which?`' \
    "*   [A] ❓ Ask base: quoted"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "only a heading is an ask"
}

test_a_fenced_example_is_not_an_ask() {
  local s="$TMP_DIR/f" out="$TMP_DIR/f.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" \
    "## [A] 🚀 Started" '```' "## [A] ❓ Ask base: example?" '```' "## [A] done"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "a heading inside a code fence is not an ask"
}

test_sub_lane_tags_are_read() {
  local s="$TMP_DIR/sub" out="$TMP_DIR/sub.out" rc
  elog "$s/builds/S6_BUILD_LOG.md" <<'EOF'
## [S6:build] ❓ Ask base: which?
EOF
  write_log "$s/builds/IDE-106_LOG.md" \
    "## [IDE-106 prove r3] ❓ Ask perm: may I?" \
    "## [PIPELAND2/prove] ❓ Ask x: y?"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "sub-lane asks are open"
  assert_contains "[S6:build]" "$(cat "$out")" "a colon tag is read"
  assert_contains "[IDE-106 prove r3]" "$(cat "$out")" "a tag with spaces is read"
  assert_contains "[PIPELAND2/prove]" "$(cat "$out")" "a slash tag is read"
  assert_contains "open asks: 3" "$(cat "$out")" "all three counted"
}

test_the_conductor_closes_an_ask_in_the_lane_log_or_in_LOOM_LOG() {
  local s="$TMP_DIR/cond" out="$TMP_DIR/cond.out" rc
  elog "$s/builds/A_BUILD_LOG.md" <<'EOF'
## [A] ❓ Ask base: which?
EOF
  elog "$s/builds/B_BUILD_LOG.md" <<'EOF'
## [B] ❓ Ask perm: may I?
EOF
  elog "$s/builds/A_BUILD_LOG.md" <<'EOF'
## [A] ✅ Answered base: dev (conductor)
EOF
  elog "$s/LOOM_LOG.md" <<'EOF'
## [B] ✅ Answered perm: yes
EOF
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "an answer in the lane log or in LOOM_LOG.md closes"
}

test_an_answer_in_some_other_lanes_log_does_not_close() {
  local s="$TMP_DIR/oth" out="$TMP_DIR/oth.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" "## [A] ❓ Ask base: which?"
  write_log "$s/builds/C_BUILD_LOG.md" "## [A] ✅ Answered base: dev"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "only the lane's own log and LOOM_LOG.md close an ask"
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

test_variation_selectors_punctuation_and_case_do_not_break_matching() {
  local s="$TMP_DIR/vs" out="$TMP_DIR/vs.out" rc
  write_log "$s/A_LOG.md" \
    $'## [A] \xe2\x9d\x93\xef\xb8\x8f Ask sel: selector on the ask?' \
    "## [A] ❓ Ask base: which?" \
    $'## [A] \xe2\x9c\x85\xef\xb8\x8f Answered sel: yes' \
    "## [A] ✅ Answered Base. dev"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "selector, trailing punctuation and case all close"
  write_log "$s/B_LOG.md" $'## [B] \xe2\x9d\x93\xef\xb8\x8f Ask only: open?'
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "an ask with a variation selector is found"
}

test_an_ask_like_heading_that_cannot_be_parsed_is_reported() {
  local s="$TMP_DIR/un" out="$TMP_DIR/un.out" rc
  write_log "$s/A_LOG.md" "## [A] ❓ Ask: no id here?" "## ❓ Ask base: no tag?"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "an unparseable ask is a finding, not a clean"
  assert_contains "unparsed: 2" "$(cat "$out")" "both are counted as unparsed"
  assert_contains "UNPARSED" "$(cat "$out")" "and printed"
}

test_a_session_path_with_spaces_is_read() {
  local s="$TMP_DIR/Shared drives/s5" out="$TMP_DIR/s5.out" rc
  write_log "$s/builds/C_BUILD_LOG.md" "## [C] ❓ Ask x: y?"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "a path with spaces is scanned"
}

test_a_symlinked_session_dir_is_followed() {
  local real="$TMP_DIR/realsess" link="$TMP_DIR/linksess" out="$TMP_DIR/ln.out" rc
  write_log "$real/builds/C_BUILD_LOG.md" "## [C] ❓ Ask x: y?"
  ln -s "$real" "$link"
  rc=$(run_check "$out" "$link")
  assert_eq "3" "$rc" "a session dir that is a symlink is read"
}

test_extra_roots_are_read_and_a_file_reached_twice_counts_once() {
  local s="$TMP_DIR/r1" extra="$TMP_DIR/backup" out="$TMP_DIR/r.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" "## [A] 🚀 Started"
  write_log "$extra/D_BUILD_LOG.md" "## [D] ❓ Ask x: y?"
  ln -s "$extra/D_BUILD_LOG.md" "$s/builds/D_BUILD_LOG.md"
  rc=$(run_check "$out" "$s")
  assert_eq "3" "$rc" "a symlinked log inside the session is read"
  rc=$(run_check "$out" "$s" --also "$extra")
  assert_eq "3" "$rc" "an extra root is read"
  assert_contains "open asks: 1" "$(cat "$out")" "a file reached by two paths counts once"
  assert_contains "logs read: 2" "$(cat "$out")" "and is read once"
}

test_an_unreadable_directory_is_a_fault_not_a_clean() {
  local s="$TMP_DIR/ur" out="$TMP_DIR/ur.out" rc
  write_log "$s/builds/A_BUILD_LOG.md" "## [A] ❓ Ask x: y?"
  chmod 000 "$s/builds"
  rc=$(run_check "$out" "$s")
  chmod 755 "$s/builds"
  assert_eq "2" "$rc" "an unreadable subdirectory exits 2"
  assert_contains "builds" "$(cat "$out.err")" "and names the path"
}

test_faults_exit_2() {
  local out="$TMP_DIR/fx.out" rc
  rc=$(run_check "$out")
  assert_eq "2" "$rc" "no argument exits 2"
  rc=$(run_check "$out" "$TMP_DIR/nope")
  assert_eq "2" "$rc" "a missing dir exits 2"
  rc=$(run_check "$out" "$TMP_DIR" --also)
  assert_eq "2" "$rc" "--also with no dir exits 2"
}

test_no_asks_reports_clean_and_names_how_many_logs_it_read() {
  local s="$TMP_DIR/s6" out="$TMP_DIR/s6.out" rc
  write_log "$s/builds/D_BUILD_LOG.md" "## [D] 🚀 Started"
  rc=$(run_check "$out" "$s")
  assert_eq "0" "$rc" "no asks exits 0"
  assert_contains "logs read: 1" "$(cat "$out")" "the verdict says how many logs it read"
}

test_no_logs_at_all_warns() {
  local s="$TMP_DIR/empty" out="$TMP_DIR/em.out" rc
  mkdir -p "$s"
  rc=$(run_check "$out" "$s")
  assert_contains "no *_LOG.md" "$(cat "$out.err")" "a reading of zero logs warns"
}

run_discovered_tests
