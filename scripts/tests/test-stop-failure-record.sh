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
#   PARSE-01      input that does not parse as a StopFailure event -> nothing written
#   CHILD-01      a session_id that is not the session's own (a child `claude -p` that inherited
#                 the supervisor pid) -> nothing written, conductor or lane
#   SKILL-01      the session is not a loom -> no conductor heading
#   CLASS-01/02   a transient error says resume by SendMessage; a recurring one says re-dispatch
#   LIVE-01       the input exactly as measured live on 2026-10-30 (claude 2.1.314, a subagent
#                 with a bad model id): agent_id + agent_type, the PARENT's session_id and
#                 transcript_path, the brief as a plain string

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

REAL_HOOK="${STOP_FAILURE_HOOK_UNDER_TEST:-$(cd "$(dirname "$0")/../.." && pwd)/hooks/stop-failure-record.sh}"

setup() {
  setup_test_env "2026_10_30_FAILTEST"
  HOOK="$REAL_HOOK"
  PROJ_DIR="$FAKE_HOME/.claude/projects/-fake"
  CONVO="$PROJ_DIR/convo-1"
  mkdir -p "$CONVO/subagents" "$TEST_SESSION/builds"
  jq -n '{pid: 99999999, lifecycle: "active", skill: "loom", currentPhase: "1: Loom",
          sessionId: "convo-1"}' > "$TEST_SESSION/.state.json"
  printf '# loom log\n' > "$TEST_SESSION/LOOM_LOG.md"
  echo '{"type":"user"}' > "$CONVO.jsonl"
}

teardown() { cleanup_test_env; }

# $1 tag, $2 brief text (the lane transcript's first record)
plant_lane() {
  jq -cn --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]}}' \
    > "$CONVO/subagents/agent-a$1.jsonl"
}

# $1 error, $2 agent_id (empty = the conductor's own turn), $3 session_id (default convo-1)
run_hook() {
  jq -cn --arg e "$1" --arg a "$2" --arg tp "$CONVO.jsonl" --arg sid "${3:-convo-1}" '{
      session_id: $sid, transcript_path: $tp, cwd: "/tmp", hook_event_name: "StopFailure",
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

test_unparseable_input_writes_nothing() {
  printf '{"error":"authentication_failed", truncated' | bash "$HOOK" >/dev/null 2>&1
  printf '{"hook_event_name":"Stop","error":"authentication_failed","session_id":"convo-1"}' \
    | bash "$HOOK" >/dev/null 2>&1
  assert_eq "# loom log" "$(cat "$TEST_SESSION/LOOM_LOG.md")" \
    "PARSE-01: a truncated input, or one that is not a StopFailure event, writes nothing"
}
run_test test_unparseable_input_writes_nothing

test_a_child_claude_with_another_session_writes_nothing() {
  printf '## [GOREQ] critique start\n' > "$TEST_SESSION/builds/GOREQ_LOG.md"
  plant_lane GOREQ "[GOREQ] Log: $TEST_SESSION/builds/GOREQ_LOG.md"
  run_hook authentication_failed "" child-9 >/dev/null
  run_hook authentication_failed aGOREQ child-9 >/dev/null
  assert_eq "# loom log" "$(cat "$TEST_SESSION/LOOM_LOG.md")" \
    "CHILD-01: a conductor turn from another conversation is not this conductor's"
  assert_eq "## [GOREQ] critique start" "$(cat "$TEST_SESSION/builds/GOREQ_LOG.md")" \
    "CHILD-02: nor is a lane dispatched from another conversation"
  run_hook authentication_failed "" >/dev/null
  assert_contains "conductor turn failed" "$(cat "$TEST_SESSION/LOOM_LOG.md")" \
    "CHILD-03: control: the session's own conversation is recorded"
}
run_test test_a_child_claude_with_another_session_writes_nothing

test_a_non_loom_session_gets_no_conductor_heading() {
  jq '.skill = "implement"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/s.tmp" \
    && mv "$TEST_SESSION/s.tmp" "$TEST_SESSION/.state.json"
  printf '# implement log\n' > "$TEST_SESSION/IMPLEMENT_LOG.md"
  run_hook authentication_failed "" >/dev/null
  assert_eq "# implement log" "$(cat "$TEST_SESSION/IMPLEMENT_LOG.md")" \
    "SKILL-01: a session that is not a loom gets no conductor heading"
  assert_eq "# loom log" "$(cat "$TEST_SESSION/LOOM_LOG.md")" "SKILL-02: nor does any other log"
}
run_test test_a_non_loom_session_gets_no_conductor_heading

test_the_heading_says_resume_or_redispatch_by_error_class() {
  printf '## [TRANS] start\n' > "$TEST_SESSION/builds/TRANS_LOG.md"
  plant_lane TRANS "[TRANS] Log: $TEST_SESSION/builds/TRANS_LOG.md"
  printf '## [RECUR] start\n' > "$TEST_SESSION/builds/RECUR_LOG.md"
  plant_lane RECUR "[RECUR] Log: $TEST_SESSION/builds/RECUR_LOG.md"
  run_hook overloaded aTRANS >/dev/null
  run_hook invalid_request aRECUR >/dev/null
  local t r
  t=$(cat "$TEST_SESSION/builds/TRANS_LOG.md"); r=$(cat "$TEST_SESSION/builds/RECUR_LOG.md")
  assert_contains "resume by SendMessage" "$t" "CLASS-01: a transient error says resume by SendMessage"
  assert_contains "re-dispatch" "$r" "CLASS-02: a recurring error says re-dispatch from the log"
  assert_not_contains "resume by SendMessage" "$r" "CLASS-03: and does not say resume"
}
run_test test_the_heading_says_resume_or_redispatch_by_error_class

test_the_input_as_measured_live() {
  printf '## [BADLANE] start\n' > "$TEST_SESSION/builds/BADLANE_LOG.md"
  jq -cn --arg t "[BADLANE] say hello, log $TEST_SESSION/builds/BADLANE_LOG.md" \
    '{type:"user",sessionId:"convo-1",message:{role:"user",content:$t}}' \
    > "$CONVO/subagents/agent-a66d995aa0b628de8.jsonl"
  jq -cn --arg tp "$CONVO.jsonl" '{agent_id:"a66d995aa0b628de8", agent_type:"badagent",
      cwd:"/tmp", effort:"medium", error:"model_not_found", hook_event_name:"StopFailure",
      last_assistant_message:"There is an issue with the selected model", prompt_id:"p1",
      session_id:"convo-1", transcript_path:$tp}' | bash "$HOOK" >/dev/null 2>&1
  assert_contains "## [BADLANE] lane failed: model_not_found" \
    "$(cat "$TEST_SESSION/builds/BADLANE_LOG.md")" \
    "LIVE-01: the measured subagent input resolves the lane from the parent's transcript_path"
}
run_test test_the_input_as_measured_live

exit_with_results
