#!/bin/bash
# test-stop-failure-record.sh — Tests for the StopFailure hook that records an API-error death.
#
# StopFailure fires INSTEAD of Stop when an API error (authentication_failed, rate_limit,
# overloaded, …) ends a turn; its output and exit code are ignored, so the only thing it can do
# is write a record. LANEAUTH (2026-10-30): nothing recorded tonight's three auth-failed turns,
# two of them lanes, and the conductor re-dispatched a lane 9 minutes into its work.
#
# The arms are pairs that differ in one input, so none passes vacuously:
#   LANE-01/02    a lane whose brief names its own log -> the heading lands THERE, not in the
#                 session log
#   NOLOG-01      a lane with no log yet (died at step 0) -> the session log, naming the tag
#   COND-01       no agent_id: the conductor's own turn -> the session log, conductor heading
#   NOSESS-01     no session resolves -> nothing written, exit 0
#   SANITIZE-01   an error value carrying a newline and a fake heading -> written as "unknown"

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

REAL_HOOK="${STOP_FAILURE_HOOK_UNDER_TEST:-$(cd "$(dirname "$0")/../.." && pwd)/hooks/stop-failure-record.sh}"

setup() {
  setup_test_env "2026_10_30_FAILTEST"
  HOOK="$REAL_HOOK"
  PROJ_DIR="$FAKE_HOME/.claude/projects/-fake"
  CONVO="$PROJ_DIR/convo-1"
  mkdir -p "$CONVO/subagents" "$TEST_SESSION/builds"
  jq -n '{pid: 99999999, lifecycle: "active", skill: "loom", currentPhase: "1: Loom"}' \
    > "$TEST_SESSION/.state.json"
  printf '# loom log\n' > "$TEST_SESSION/LOOM_LOG.md"
  echo '{"type":"user"}' > "$CONVO.jsonl"
}

teardown() { cleanup_test_env; }

# $1 tag, $2 brief text (the lane transcript's first record)
plant_lane() {
  jq -cn --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]}}' \
    > "$CONVO/subagents/agent-a$1.jsonl"
}

# $1 error, $2 agent_id (empty = the conductor's own turn)
run_hook() {
  jq -cn --arg e "$1" --arg a "$2" --arg tp "$CONVO.jsonl" '{
      session_id: "convo-1", transcript_path: $tp, cwd: "/tmp", hook_event_name: "StopFailure",
      error: $e, last_assistant_message: "Not logged in · Please run /login"}
    + (if $a == "" then {} else {agent_id: $a} end)' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

test_lane_heading_lands_in_the_lanes_own_log() {
  printf '## [GOREQ] critique start\n' > "$TEST_SESSION/builds/GOREQ_LOG.md"
  plant_lane GOREQ "[GOREQ] You are thread GOREQ. Log: $TEST_SESSION/builds/GOREQ_LOG.md via engine log."
  assert_eq "0" "$(run_hook authentication_failed aGOREQ)" "LANE-00: the hook exits 0"
  local lane; lane=$(cat "$TEST_SESSION/builds/GOREQ_LOG.md")
  assert_contains "## [GOREQ] lane failed: authentication_failed" "$lane" \
    "LANE-01: the lane's own log gets the failed heading"
  assert_contains "agent aGOREQ" "$lane" "LANE-01b: the heading names the agent to SendMessage"
  assert_contains "session convo-1" "$lane" "LANE-01c: and the conversation it lives in"
  if printf '%s' "$lane" | grep -qE '^## \[GOREQ\] .*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]'; then
    pass "LANE-01d: the heading carries a timestamp lane-stall can date"
  else
    fail "LANE-01d: the heading carries a timestamp lane-stall can date" "[YYYY-MM-DD HH:MM:SS]" "$lane"
  fi
  assert_not_contains "lane failed" "$(cat "$TEST_SESSION/LOOM_LOG.md")" \
    "LANE-02: the session log is untouched when the lane's log resolves"
}
run_test test_lane_heading_lands_in_the_lanes_own_log

test_lane_resolved_by_thread_announcement() {
  printf '## [FENCELANG] start\n' > "$TEST_SESSION/builds/FENCELANG_LOG.md"
  plant_lane FENCELANG "Critique round 2. You are thread FENCELANG; log at $TEST_SESSION/builds/FENCELANG_LOG.md"
  run_hook rate_limit aFENCELANG >/dev/null
  assert_contains "## [FENCELANG] lane failed: rate_limit" "$(cat "$TEST_SESSION/builds/FENCELANG_LOG.md")" \
    "LANE-03: a tag from a 'thread TAG' announcement resolves, and the error value is the input's"
}
run_test test_lane_resolved_by_thread_announcement

test_lane_without_a_log_goes_to_the_session_log() {
  plant_lane KILLGUARD "[KILLGUARD] You are thread KILLGUARD. Log: $TEST_SESSION/builds/KILLGUARD_LOG.md"
  run_hook authentication_failed aKILLGUARD >/dev/null
  assert_file_not_exists "$TEST_SESSION/builds/KILLGUARD_LOG.md" \
    "NOLOG-00: the hook never creates a lane's log"
  local s; s=$(cat "$TEST_SESSION/LOOM_LOG.md")
  assert_contains "[KILLGUARD] lane failed: authentication_failed" "$s" \
    "NOLOG-01: a lane with no log yet is recorded in the session log, by tag"
  assert_contains "no lane log" "$s" "NOLOG-02: and the heading says why it is here"
}
run_test test_lane_without_a_log_goes_to_the_session_log

test_conductor_turn_goes_to_the_session_log() {
  assert_eq "0" "$(run_hook authentication_failed "")" "COND-00: the hook exits 0"
  local s; s=$(cat "$TEST_SESSION/LOOM_LOG.md")
  assert_contains "conductor turn failed: authentication_failed" "$s" \
    "COND-01: the conductor's own failed turn is recorded in the session log"
  assert_contains "next call that succeeds" "$s" \
    "COND-02: the heading says what proves the API is back"
}
run_test test_conductor_turn_goes_to_the_session_log

test_no_session_writes_nothing() {
  rm -f "$TEST_SESSION/.state.json"
  printf '## [GOREQ] critique start\n' > "$TEST_SESSION/builds/GOREQ_LOG.md"
  plant_lane GOREQ "[GOREQ] Log: $TEST_SESSION/builds/GOREQ_LOG.md"
  assert_eq "0" "$(run_hook authentication_failed "")" "NOSESS-00: exit 0 with no session"
  assert_eq "# loom log" "$(cat "$TEST_SESSION/LOOM_LOG.md")" "NOSESS-01: no session, nothing written"
}
run_test test_no_session_writes_nothing

test_error_value_is_sanitized() {
  run_hook "$(printf 'x\n## [FAKE] retired=landed')" "" >/dev/null
  local s; s=$(cat "$TEST_SESSION/LOOM_LOG.md")
  assert_not_contains "[FAKE]" "$s" "SANITIZE-01: a crafted error value cannot plant a heading"
  assert_contains "conductor turn failed: unknown" "$s" "SANITIZE-02: it is written as unknown"
}
run_test test_error_value_is_sanitized

exit_with_results
