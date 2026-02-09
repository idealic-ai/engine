#!/bin/bash
# ~/.claude/engine/scripts/tests/test-find-sessions-sh.sh — Deep coverage tests for find-sessions.sh
#
# Tests subcommands: today, yesterday, recent, date, range, topic, tag, active, all
# Tests output modes: dirs (default), --files, --debriefs
# Tests: --path override, edge cases
#
# Run: bash ~/.claude/engine/scripts/tests/test-find-sessions-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

FIND_SESSIONS_SH="$HOME/.claude/engine/scripts/find-sessions.sh"

TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/sessions"
}

teardown() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: create a session dir with standard files
create_session() {
  local dir="$1"
  local mtime="${2:-}"  # optional: YYYYMMDDHHM format for touch -t
  mkdir -p "$dir"
  echo "# Implementation" > "$dir/IMPLEMENTATION.md"
  echo "## Log" > "$dir/IMPLEMENTATION_LOG.md"
  echo "## Plan" > "$dir/IMPLEMENTATION_PLAN.md"
  echo "## Details" > "$dir/DETAILS.md"
  if [[ -n "$mtime" ]]; then
    touch -t "$mtime" "$dir/IMPLEMENTATION.md" "$dir/IMPLEMENTATION_LOG.md" "$dir/IMPLEMENTATION_PLAN.md" "$dir/DETAILS.md"
  fi
}

# Helper: create a session with tags
create_tagged_session() {
  local dir="$1"
  local tags="$2"
  mkdir -p "$dir"
  printf '# Test Debrief\n**Tags**: %s\n\nContent.\n' "$tags" > "$dir/BRAINSTORM.md"
}

# Today/yesterday dates for dynamic tests
TODAY=$(date +%Y_%m_%d)
YESTERDAY=$(date -v-1d +%Y_%m_%d)

echo "=== find-sessions.sh Deep Coverage Tests ==="
echo ""

# ============================================================
# DATE-BASED SUBCOMMANDS
# ============================================================
echo "--- Date-based: today, yesterday, recent, date ---"

test_today_finds_todays_sessions() {
  create_session "$TEST_DIR/sessions/${TODAY}_MY_TOPIC"
  create_session "$TEST_DIR/sessions/2025_01_01_OLD_TOPIC"

  local output
  output=$(bash "$FIND_SESSIONS_SH" today --path "$TEST_DIR/sessions")

  if [[ "$output" == *"${TODAY}_MY_TOPIC"* ]] && [[ "$output" != *"OLD_TOPIC"* ]]; then
    pass "DATE-01: today finds only today's sessions"
  else
    fail "DATE-01: today finds only today's sessions" \
      "${TODAY}_MY_TOPIC only" "$output"
  fi
}
run_test test_today_finds_todays_sessions

test_yesterday_finds_yesterdays_sessions() {
  create_session "$TEST_DIR/sessions/${YESTERDAY}_YESTER_WORK"
  create_session "$TEST_DIR/sessions/${TODAY}_TODAY_WORK"

  local output
  output=$(bash "$FIND_SESSIONS_SH" yesterday --path "$TEST_DIR/sessions")

  if [[ "$output" == *"${YESTERDAY}_YESTER_WORK"* ]] && [[ "$output" != *"TODAY_WORK"* ]]; then
    pass "DATE-02: yesterday finds only yesterday's sessions"
  else
    fail "DATE-02: yesterday finds only yesterday's sessions" \
      "${YESTERDAY}_YESTER_WORK only" "$output"
  fi
}
run_test test_yesterday_finds_yesterdays_sessions

test_recent_finds_today_and_yesterday() {
  create_session "$TEST_DIR/sessions/${TODAY}_TODAY_WORK"
  create_session "$TEST_DIR/sessions/${YESTERDAY}_YESTER_WORK"
  create_session "$TEST_DIR/sessions/2025_01_01_OLD_WORK"

  local output
  output=$(bash "$FIND_SESSIONS_SH" recent --path "$TEST_DIR/sessions")

  if [[ "$output" == *"TODAY_WORK"* ]] && [[ "$output" == *"YESTER_WORK"* ]] && [[ "$output" != *"OLD_WORK"* ]]; then
    pass "DATE-03: recent finds today + yesterday, not older"
  else
    fail "DATE-03: recent finds today + yesterday, not older" \
      "TODAY_WORK + YESTER_WORK" "$output"
  fi
}
run_test test_recent_finds_today_and_yesterday

test_date_finds_specific_date() {
  create_session "$TEST_DIR/sessions/2026_01_15_TARGET"
  create_session "$TEST_DIR/sessions/2026_01_16_OTHER"

  local output
  output=$(bash "$FIND_SESSIONS_SH" date 2026_01_15 --path "$TEST_DIR/sessions")

  if [[ "$output" == *"2026_01_15_TARGET"* ]] && [[ "$output" != *"OTHER"* ]]; then
    pass "DATE-04: date finds sessions for specific date"
  else
    fail "DATE-04: date finds sessions for specific date" \
      "2026_01_15_TARGET only" "$output"
  fi
}
run_test test_date_finds_specific_date

test_date_multiple_sessions_same_day() {
  create_session "$TEST_DIR/sessions/2026_01_15_TOPIC_A"
  create_session "$TEST_DIR/sessions/2026_01_15_TOPIC_B"

  local output
  output=$(bash "$FIND_SESSIONS_SH" date 2026_01_15 --path "$TEST_DIR/sessions")
  local count
  count=$(echo "$output" | grep -c '2026_01_15' || true)

  if [[ $count -eq 2 ]]; then
    pass "DATE-05: date finds multiple sessions on same day"
  else
    fail "DATE-05: date finds multiple sessions on same day" \
      "2 sessions" "$count sessions"
  fi
}
run_test test_date_multiple_sessions_same_day

# ============================================================
# RANGE SUBCOMMAND
# ============================================================
echo ""
echo "--- Range ---"

test_range_inclusive() {
  create_session "$TEST_DIR/sessions/2026_01_10_BEFORE"
  create_session "$TEST_DIR/sessions/2026_01_15_START"
  create_session "$TEST_DIR/sessions/2026_01_18_MIDDLE"
  create_session "$TEST_DIR/sessions/2026_01_20_END"
  create_session "$TEST_DIR/sessions/2026_01_25_AFTER"

  local output
  output=$(bash "$FIND_SESSIONS_SH" range 2026_01_15 2026_01_20 --path "$TEST_DIR/sessions")

  if [[ "$output" == *"START"* ]] && [[ "$output" == *"MIDDLE"* ]] && [[ "$output" == *"END"* ]] \
    && [[ "$output" != *"BEFORE"* ]] && [[ "$output" != *"AFTER"* ]]; then
    pass "RANGE-01: Inclusive range finds START, MIDDLE, END"
  else
    fail "RANGE-01: Inclusive range finds START, MIDDLE, END" \
      "START + MIDDLE + END (not BEFORE/AFTER)" "$output"
  fi
}
run_test test_range_inclusive

test_range_single_day() {
  create_session "$TEST_DIR/sessions/2026_01_15_EXACT"
  create_session "$TEST_DIR/sessions/2026_01_16_NEXT"

  local output
  output=$(bash "$FIND_SESSIONS_SH" range 2026_01_15 2026_01_15 --path "$TEST_DIR/sessions")

  if [[ "$output" == *"EXACT"* ]] && [[ "$output" != *"NEXT"* ]]; then
    pass "RANGE-02: Single-day range works"
  else
    fail "RANGE-02: Single-day range works" \
      "EXACT only" "$output"
  fi
}
run_test test_range_single_day

# ============================================================
# TOPIC SUBCOMMAND
# ============================================================
echo ""
echo "--- Topic ---"

test_topic_case_insensitive() {
  create_session "$TEST_DIR/sessions/2026_01_15_AUTH_REFACTOR"
  create_session "$TEST_DIR/sessions/2026_01_16_LAYOUT_FIX"

  local output
  output=$(bash "$FIND_SESSIONS_SH" topic auth --path "$TEST_DIR/sessions")

  if [[ "$output" == *"AUTH_REFACTOR"* ]] && [[ "$output" != *"LAYOUT"* ]]; then
    pass "TOPIC-01: Case-insensitive topic search"
  else
    fail "TOPIC-01: Case-insensitive topic search" \
      "AUTH_REFACTOR only" "$output"
  fi
}
run_test test_topic_case_insensitive

test_topic_partial_match() {
  create_session "$TEST_DIR/sessions/2026_01_15_ESTIMATE_EXTRACTION"
  create_session "$TEST_DIR/sessions/2026_01_16_ESTIMATE_REVIEW"
  create_session "$TEST_DIR/sessions/2026_01_17_AUTH_SETUP"

  local output
  output=$(bash "$FIND_SESSIONS_SH" topic ESTIMATE --path "$TEST_DIR/sessions")
  local count
  count=$(echo "$output" | grep -c 'ESTIMATE' || true)

  if [[ $count -eq 2 ]]; then
    pass "TOPIC-02: Partial match finds multiple sessions"
  else
    fail "TOPIC-02: Partial match finds multiple sessions" \
      "2 ESTIMATE sessions" "$count"
  fi
}
run_test test_topic_partial_match

# ============================================================
# TAG SUBCOMMAND
# ============================================================
echo ""
echo "--- Tag ---"

test_tag_finds_tagged_sessions() {
  create_tagged_session "$TEST_DIR/sessions/2026_01_15_REVIEWED" "#needs-review"
  create_tagged_session "$TEST_DIR/sessions/2026_01_16_DONE" "#done-review"

  local output
  output=$(bash "$FIND_SESSIONS_SH" tag '#needs-review' --path "$TEST_DIR/sessions")

  if [[ "$output" == *"REVIEWED"* ]] && [[ "$output" != *"DONE"* ]]; then
    pass "TAG-01: Finds sessions containing tag"
  else
    fail "TAG-01: Finds sessions containing tag" \
      "REVIEWED only" "$output"
  fi
}
run_test test_tag_finds_tagged_sessions

test_tag_no_match_exits_clean() {
  create_tagged_session "$TEST_DIR/sessions/2026_01_15_WORK" "#other-tag"

  local output
  output=$(bash "$FIND_SESSIONS_SH" tag '#nonexistent' --path "$TEST_DIR/sessions" 2>&1)
  local rc=$?

  if [[ $rc -eq 0 ]] && [[ -z "$output" ]]; then
    pass "TAG-02: No tag matches exits 0 with empty output"
  else
    fail "TAG-02: No tag matches exits 0 with empty output" \
      "exit 0, empty" "rc=$rc, output=$output"
  fi
}
run_test test_tag_no_match_exits_clean

# ============================================================
# ALL SUBCOMMAND
# ============================================================
echo ""
echo "--- All ---"

test_all_lists_all_sessions() {
  create_session "$TEST_DIR/sessions/2026_01_15_A"
  create_session "$TEST_DIR/sessions/2026_01_16_B"
  create_session "$TEST_DIR/sessions/2025_06_01_C"

  local output
  output=$(bash "$FIND_SESSIONS_SH" all --path "$TEST_DIR/sessions")
  local count
  count=$(echo "$output" | grep -c '' || true)

  if [[ $count -eq 3 ]]; then
    pass "ALL-01: Lists all 3 sessions"
  else
    fail "ALL-01: Lists all 3 sessions" \
      "3 sessions" "$count"
  fi
}
run_test test_all_lists_all_sessions

# ============================================================
# OUTPUT MODES
# ============================================================
echo ""
echo "--- Output Modes ---"

test_files_mode_shows_timestamps() {
  create_session "$TEST_DIR/sessions/2026_01_15_WORK" "202601150900"

  local output
  output=$(bash "$FIND_SESSIONS_SH" date 2026_01_15 --files --path "$TEST_DIR/sessions")

  # --files output should have timestamps and file paths
  if [[ "$output" == *"2026-01-15"* ]] && [[ "$output" == *"IMPLEMENTATION.md"* ]]; then
    pass "MODE-01: --files shows timestamps and file paths"
  else
    fail "MODE-01: --files shows timestamps and file paths" \
      "timestamps + file paths" "$output"
  fi
}
run_test test_files_mode_shows_timestamps

test_debriefs_mode_filters_correctly() {
  create_session "$TEST_DIR/sessions/2026_01_15_WORK"

  local output
  output=$(bash "$FIND_SESSIONS_SH" date 2026_01_15 --debriefs --path "$TEST_DIR/sessions")

  # Should include IMPLEMENTATION.md (debrief) but NOT _LOG, _PLAN, DETAILS
  if [[ "$output" == *"IMPLEMENTATION.md"* ]] \
    && [[ "$output" != *"_LOG.md"* ]] \
    && [[ "$output" != *"_PLAN.md"* ]] \
    && [[ "$output" != *"DETAILS.md"* ]]; then
    pass "MODE-02: --debriefs includes debrief, excludes LOG/PLAN/DETAILS"
  else
    fail "MODE-02: --debriefs includes debrief, excludes LOG/PLAN/DETAILS" \
      "Only IMPLEMENTATION.md" "$output"
  fi
}
run_test test_debriefs_mode_filters_correctly

test_debriefs_excludes_research_files() {
  local dir="$TEST_DIR/sessions/2026_01_15_WORK"
  create_session "$dir"
  echo "request" > "$dir/RESEARCH_REQUEST_FOO.md"
  echo "response" > "$dir/RESEARCH_RESPONSE_FOO.md"
  echo "delegation req" > "$dir/DELEGATION_REQUEST_BAR.md"
  echo "delegation resp" > "$dir/DELEGATION_RESPONSE_BAR.md"

  local output
  output=$(bash "$FIND_SESSIONS_SH" date 2026_01_15 --debriefs --path "$TEST_DIR/sessions")

  if [[ "$output" != *"RESEARCH_REQUEST"* ]] && [[ "$output" != *"DELEGATION_REQUEST"* ]] \
    && [[ "$output" != *"RESEARCH_RESPONSE"* ]] && [[ "$output" != *"DELEGATION_RESPONSE"* ]]; then
    pass "MODE-03: --debriefs excludes REQUEST_/RESPONSE_/DELEGATION_ files"
  else
    fail "MODE-03: --debriefs excludes REQUEST_/RESPONSE_/DELEGATION_ files" \
      "No research/delegation files" "$output"
  fi
}
run_test test_debriefs_excludes_research_files

# ============================================================
# PATH OVERRIDE
# ============================================================
echo ""
echo "--- Path Override ---"

test_custom_path() {
  local custom="$TEST_DIR/custom-sessions"
  mkdir -p "$custom"
  create_session "$custom/2026_01_15_CUSTOM"

  local output
  output=$(bash "$FIND_SESSIONS_SH" all --path "$custom")

  if [[ "$output" == *"CUSTOM"* ]]; then
    pass "PATH-01: --path overrides default sessions/ search"
  else
    fail "PATH-01: --path overrides default sessions/ search" \
      "CUSTOM found" "$output"
  fi
}
run_test test_custom_path

# ============================================================
# TIME-BASED SUBCOMMANDS (active, since)
# ============================================================
echo ""
echo "--- Time-based: active ---"

test_active_finds_recently_modified() {
  # Create a session with files touched right now (within last 24h)
  create_session "$TEST_DIR/sessions/2026_01_01_RECENT_ACTIVITY"
  touch "$TEST_DIR/sessions/2026_01_01_RECENT_ACTIVITY/IMPLEMENTATION.md"

  # Create a session with old files
  create_session "$TEST_DIR/sessions/2025_01_01_OLD" "202501010000"

  local output
  output=$(bash "$FIND_SESSIONS_SH" active --path "$TEST_DIR/sessions")

  if [[ "$output" == *"RECENT_ACTIVITY"* ]] && [[ "$output" != *"_OLD"* ]]; then
    pass "TIME-01: active finds sessions with recent file modifications"
  else
    fail "TIME-01: active finds sessions with recent file modifications" \
      "RECENT_ACTIVITY only" "$output"
  fi
}
run_test test_active_finds_recently_modified

# ============================================================
# EDGE CASES
# ============================================================
echo ""
echo "--- Edge Cases ---"

test_no_args_shows_usage() {
  local output
  output=$(bash "$FIND_SESSIONS_SH" 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Usage"* ]]; then
    pass "EDGE-01: No arguments shows usage"
  else
    fail "EDGE-01: No arguments shows usage" \
      "exit 1 + Usage" "rc=$rc, output=$output"
  fi
}
run_test test_no_args_shows_usage

test_unknown_subcommand_errors() {
  local output
  output=$(bash "$FIND_SESSIONS_SH" badcommand --path "$TEST_DIR/sessions" 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Unknown subcommand"* ]]; then
    pass "EDGE-02: Unknown subcommand shows error"
  else
    fail "EDGE-02: Unknown subcommand shows error" \
      "exit 1 + Unknown subcommand" "rc=$rc, output=$output"
  fi
}
run_test test_unknown_subcommand_errors

test_empty_sessions_dir() {
  local output
  output=$(bash "$FIND_SESSIONS_SH" all --path "$TEST_DIR/sessions")

  if [[ -z "$output" ]]; then
    pass "EDGE-03: Empty sessions dir returns empty output"
  else
    fail "EDGE-03: Empty sessions dir returns empty output" \
      "<empty>" "$output"
  fi
}
run_test test_empty_sessions_dir

test_date_no_match() {
  create_session "$TEST_DIR/sessions/2026_01_15_WORK"

  local output
  output=$(bash "$FIND_SESSIONS_SH" date 2099_12_31 --path "$TEST_DIR/sessions")

  if [[ -z "$output" ]]; then
    pass "EDGE-04: No matching date returns empty"
  else
    fail "EDGE-04: No matching date returns empty" \
      "<empty>" "$output"
  fi
}
run_test test_date_no_match

test_all_sorted() {
  create_session "$TEST_DIR/sessions/2026_01_20_C"
  create_session "$TEST_DIR/sessions/2026_01_10_A"
  create_session "$TEST_DIR/sessions/2026_01_15_B"

  local output
  output=$(bash "$FIND_SESSIONS_SH" all --path "$TEST_DIR/sessions")
  local first
  first=$(echo "$output" | head -1)
  local last
  last=$(echo "$output" | tail -1)

  if [[ "$first" == *"_10_A"* ]] && [[ "$last" == *"_20_C"* ]]; then
    pass "EDGE-05: all output is sorted alphabetically"
  else
    fail "EDGE-05: all output is sorted alphabetically" \
      "first=_10_A, last=_20_C" "first=$first, last=$last"
  fi
}
run_test test_all_sorted

# ============================================================
# RESULTS
# ============================================================
exit_with_results
