#!/bin/bash
# ============================================================================
# test-ticket-watch-backend.sh — `engine ticket watch` when its fswatch backend dies
# ============================================================================
# A fake `fswatch` on PATH plays a scripted sequence of behaviours, one per call:
#   segv            die of a real SIGSEGV at once (timeout re-raises it, so the shell sees 139)
#   segv-on-change  wait until the session's .state.json is replaced, then die of SIGSEGV
#                   (a crash on an incoming event)
#   exit:N          exit with status N at once
#   block           wait until `timeout` ends the call (the watch's re-check tick, 124)
# Calls past the end of the sequence repeat its last line. The real fswatch is never run.
# Every fake call records its number in plan.calls; segv-on-change writes plan.ready once it
# has recorded the file it watches, so a test can notify only after that.
#
# A fake `sleep` beside it logs each argument to plan.sleeps. Given HELD_PAUSE it also holds
# until plan.release exists, so a case can act inside the restart pause without racing it.
# The drain reads a fixture (LINEAR_FIXTURE), so no case reaches Linear.
#
# Cases order events by conditions, never by how long something takes, and assert upper
# bounds on what the watch did rather than on elapsed time. Every wait and every foreground
# watch is limited in real seconds, far above any expected run: a run under heavy load is
# slower rather than red, and a watch that never gives up fails instead of hanging the suite.
#
# The script under test is $ENGINE_SCRIPTS/ticket.sh when ENGINE_SCRIPTS is set, else the
# checkout this file lives in.
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPTS_UNDER_TEST="${ENGINE_SCRIPTS:-$(cd "$(dirname "$0")/.." && pwd)}"
TICKET_SH="$SCRIPTS_UNDER_TEST/ticket.sh"

TEST_DIR=""
WPID=""
WATCH_PID=""
HELD_PAUSE=7.25
LIMIT=60  # real seconds; only a failing case ever reaches it

setup() {
  TEST_DIR=$(mktemp -d)
  WPID="" WATCH_PID=""
  mkdir -p "$TEST_DIR/.claude" "$TEST_DIR/sessions" "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/fswatch" <<'FAKE'
#!/bin/bash
plan="$FAKE_FSWATCH_PLAN" counter="$FAKE_FSWATCH_PLAN.calls"
n=$(( $(cat "$counter" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$counter"
step=$(sed -n "${n}p" "$plan")
[ -n "$step" ] || step=$(tail -1 "$plan")
dir="${!#}"
case "$step" in
  segv) kill -SEGV $$ ;;
  segv-on-change)
    ino=$(stat -f %i "$dir/.state.json" 2>/dev/null)
    : > "$plan.ready"
    while [ "$(stat -f %i "$dir/.state.json" 2>/dev/null)" = "$ino" ]; do /bin/sleep 0.05; done
    kill -SEGV $$ ;;
  exit:*) exit "${step#exit:}" ;;
  block) exec /bin/sleep 600 ;;
esac
exit 99
FAKE
  cat > "$TEST_DIR/bin/sleep" <<FAKE
#!/bin/bash
echo "\$1" >> "\$FAKE_FSWATCH_PLAN.sleeps"
if [ "\$1" = "$HELD_PAUSE" ]; then
  : > "\$FAKE_FSWATCH_PLAN.pausing"
  until [ -f "\$FAKE_FSWATCH_PLAN.release" ]; do /bin/sleep 0.05; done
  exit 0
fi
exec /bin/sleep "\$@"
FAKE
  chmod +x "$TEST_DIR/bin/fswatch" "$TEST_DIR/bin/sleep"
  cat > "$TEST_DIR/fixture.json" <<'JSON'
{"data":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"i1","identifier":"FIN-9","title":"T","url":"u","createdAt":"2020-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","priority":1,"state":{"name":"Todo"},"projectMilestone":null,
   "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"history":{"pageInfo":{"hasNextPage":false},"nodes":[]},"attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
]}}}
JSON
}

teardown() {
  stop_watch
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
  TEST_DIR=""
}

mkstate() {
  mkdir -p "$TEST_DIR/sessions/$1"
  echo "$2" > "$TEST_DIR/sessions/$1/.state.json"
}

sget() { jq -r "$2" "$TEST_DIR/sessions/$1/.state.json" 2>/dev/null; }

# plan <step>... — write the fake backend's call sequence
plan() { printf '%s\n' "$@" > "$TEST_DIR/plan"; }

calls() { cat "$TEST_DIR/plan.calls" 2>/dev/null || echo 0; }

# pauses_of <secs> — how many times `sleep` was called with exactly this argument
pauses_of() { grep -c -x -- "$1" "$TEST_DIR/plan.sleeps" 2>/dev/null; }

# wait_until <secs> <command...> — true once the command succeeds; false after secs real seconds
wait_until() {
  local limit="$1"; shift
  local end=$(( $(date +%s) + limit ))
  until "$@"; do
    [ "$(date +%s)" -ge "$end" ] && return 1
    sleep 0.1
  done
  return 0
}

# tkf <limit-secs> <args...> — run ticket.sh in the sandbox with the fake fswatch first on
# PATH, ended by `timeout` after limit-secs (a hang then reads as 124)
tkf() {
  local limit="$1"; shift
  ( cd "$TEST_DIR" && PATH="$TEST_DIR/bin:$PATH" FAKE_FSWATCH_PLAN="$TEST_DIR/plan" \
      LINEAR_FIXTURE="$TEST_DIR/fixture.json" WATCH_BACKEND_RETRY_PAUSE="${WATCH_BACKEND_RETRY_PAUSE:-0}" \
      timeout "$limit" "$TICKET_SH" "$@" )
}

notify_b() {
  ( cd "$TEST_DIR" && "$TICKET_SH" notify FIN-9 "reply" --from "$TEST_DIR/sessions/A" ) >/dev/null 2>&1
}

registered() { [ -n "$(sget B '.watchTaskId.pid // empty')" ]; }
calls_at_least() { [ "$(calls)" -ge "$1" ]; }
fake_ready() { [ -f "$TEST_DIR/plan.ready" ]; }
pausing() { [ -f "$TEST_DIR/plan.pausing" ]; }
exited() { [ -s "$TEST_DIR/ec" ]; }
ec() { cat "$TEST_DIR/ec" 2>/dev/null; }

# start_watch <args...> — background watch on session B, limited to 300s; sets WPID (the
# wrapper) and, once the watch has registered, WATCH_PID (its own pid, from watchTaskId)
start_watch() {
  ( tkf 300 watch FIN-9 "$@" "$TEST_DIR/sessions/B" > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $? > "$TEST_DIR/ec" ) &
  WPID=$!
  if wait_until "$LIMIT" registered; then WATCH_PID=$(sget B '.watchTaskId.pid // empty'); fi
}

# stop_watch — stop a watch that has not exited by its own pid, then the wrapper
stop_watch() {
  [ -n "$TEST_DIR" ] && : > "$TEST_DIR/plan.release"
  [ -n "$WATCH_PID" ] && ! exited && kill "$WATCH_PID" 2>/dev/null
  [ -n "$WPID" ] && { kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; }
  WPID="" WATCH_PID=""
}

# wait_exit <secs> — wait up to secs real seconds for the watch to finish, then stop it
wait_exit() {
  wait_until "$1" exited
  stop_watch
}

two_sessions() {
  mkstate A '{}'
  mkstate B '{"ticketCursor":"2020-01-01T00:00:00Z","tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z"}]}'
}

# ---- Tests ----

test_fake_segv_reaches_the_watch_as_139() {
  # Control for the fixture: a real SIGSEGV in the backend reaches the shell as 139 through
  # `timeout`, the status the watch has to handle.
  plan segv
  local rc
  ( PATH="$TEST_DIR/bin:$PATH" FAKE_FSWATCH_PLAN="$TEST_DIR/plan" timeout 5 fswatch -1 "$TEST_DIR" ) 2>/dev/null; rc=$?
  assert_eq "139" "$rc" "a segfaulting backend under timeout reads as 139"
}

test_unbounded_watch_survives_a_segfault_and_wakes_on_notify() {
  two_sessions
  plan segv block
  WATCH_RECHECK_SECS=1 start_watch
  wait_until "$LIMIT" calls_at_least 2
  if ! exited && [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
    pass "unbounded watch is still live after its backend segfaulted and restarted"
  else
    fail "unbounded watch is still live after its backend segfaulted and restarted" "live" "exited $(ec): $(cat "$TEST_DIR/err")"
  fi
  assert_eq "$WATCH_PID" "$(sget B '.watchTaskId.pid // empty')" "watchTaskId still names the same watch after the restart, so the gate still sees it"
  notify_b
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "the restarted watch exits 0 on the next real update"
  assert_contains "FIN-9" "$(cat "$TEST_DIR/out")" "and reports the ticket"
}

test_a_crash_on_an_event_is_treated_as_a_wake() {
  # The backend dies on the notify's write; the re-check tick is 60s away and later calls
  # block, so only re-checking on the crash itself finds the update before the wait ends.
  two_sessions
  plan segv-on-change block
  WATCH_RECHECK_SECS=60 start_watch
  wait_until "$LIMIT" fake_ready
  notify_b
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "an update that crashed the backend is drained on the crash, not on the next tick"
  assert_contains "FIN-9" "$(cat "$TEST_DIR/out")" "the crash-wake reports the ticket"
}

test_an_update_during_the_restart_pause_is_drained_after_it() {
  # The update lands while the pause is held, so no fswatch runs and nothing reports the
  # write; only a check after the pause finds it. A bounded watch has no re-check tick.
  two_sessions
  plan segv block
  WATCH_BACKEND_RETRY_PAUSE=$HELD_PAUSE start_watch --timeout 280
  wait_until "$LIMIT" pausing
  notify_b
  : > "$TEST_DIR/plan.release"
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "a bounded watch drains an update that landed while it paused before restarting"
  assert_contains "FIN-9" "$(cat "$TEST_DIR/out")" "and reports the ticket"
}

test_an_update_during_the_pause_is_drained_by_an_unbounded_watch() {
  two_sessions
  plan segv block
  WATCH_BACKEND_RETRY_PAUSE=$HELD_PAUSE WATCH_RECHECK_SECS=280 start_watch
  wait_until "$LIMIT" pausing
  notify_b
  : > "$TEST_DIR/plan.release"
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "an unbounded watch drains an update from the pause without waiting for its tick"
}

test_exit_2_backend_is_retried_too() {
  two_sessions
  plan exit:2 exit:2 block
  WATCH_RECHECK_SECS=1 start_watch
  wait_until "$LIMIT" calls_at_least 3
  if ! exited; then pass "watch survives two backend exits of 2"; else fail "watch survives two backend exits of 2" "live" "exited $(ec)"; fi
  notify_b
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "and still exits 0 on a real update"
}

test_persistent_failure_gives_up_with_2_after_the_retry_budget() {
  two_sessions
  plan exit:2
  local rc
  WATCH_BACKEND_RETRIES=3 tkf "$LIMIT" watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>"$TEST_DIR/err"; rc=$?
  assert_eq "2" "$rc" "a backend that never runs cleanly ends the watch with 2 (124 would mean it never gave up)"
  assert_eq "4" "$(calls)" "the backend was started once plus three retries, then the watch gave up"
  assert_contains "in a row" "$(cat "$TEST_DIR/err")" "the give-up message says the failures were consecutive"
  assert_empty "$(sget B '.watchTaskId.pid // empty')" "watchTaskId is cleared, so the gate sees the session unarmed"
}

test_the_restart_pause_is_taken() {
  # Budget 2: two pauses before giving up. Counted from the arguments `sleep` received,
  # because elapsed time under load passes with no pause at all.
  two_sessions
  plan exit:2
  local rc
  WATCH_BACKEND_RETRIES=2 WATCH_BACKEND_RETRY_PAUSE=3 tkf "$LIMIT" watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "the watch gives up with 2"
  assert_eq "2" "$(pauses_of 3)" "it paused before each restart"
}

test_a_bounded_watch_that_spends_its_budget_exits_2_before_its_deadline() {
  two_sessions
  plan exit:2
  local rc
  WATCH_BACKEND_RETRIES=2 tkf "$LIMIT" watch FIN-9 --timeout 30 "$TEST_DIR/sessions/B" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "a bounded watch whose backend keeps failing exits 2, not 124"
  assert_eq "3" "$(calls)" "after one start plus two retries"
}

test_non_numeric_settings_fall_back_to_their_defaults() {
  two_sessions
  plan exit:2
  local rc
  WATCH_BACKEND_RETRIES=five tkf "$LIMIT" watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "a non-numeric retry budget still gives up (124 would mean it never did)"
  assert_eq "6" "$(calls)" "with the default budget of 5"
  rm -f "$TEST_DIR/plan.calls" "$TEST_DIR/plan.sleeps"
  WATCH_BACKEND_RETRIES=1 WATCH_BACKEND_RETRY_PAUSE=soon tkf "$LIMIT" watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>"$TEST_DIR/err"; rc=$?
  assert_eq "2" "$rc" "a non-numeric pause does not break the watch"
  assert_eq "1" "$(pauses_of 1)" "and falls back to the default 1s pause"
  assert_not_contains "invalid" "$(cat "$TEST_DIR/err")" "sleep is never handed the bad value"
}

test_the_pause_does_not_run_past_a_bounded_deadline() {
  # Asserted on the argument `sleep` received: elapsed time says nothing under load.
  two_sessions
  plan exit:2 block
  local rc longest
  WATCH_BACKEND_RETRY_PAUSE=50 tkf "$LIMIT" watch FIN-9 --timeout 5 "$TEST_DIR/sessions/B" >/dev/null 2>"$TEST_DIR/err"; rc=$?
  longest=$(sort -n "$TEST_DIR/plan.sleeps" 2>/dev/null | tail -1)
  assert_eq "124" "$rc" "the watch ends at its deadline"
  assert_contains "timed out after 5s" "$(cat "$TEST_DIR/err")" "the 124 is its own deadline, not the test's limit"
  assert_not_empty "$longest" "a pause was taken"
  assert_gt "6" "${longest%.*}" "the 50s pause was cut to the time remaining (slept ${longest:-nothing})"
}

test_a_healthy_run_resets_the_retry_budget() {
  # Crash, tick, crash, tick...: four crashes against a budget of two, never two in a row.
  two_sessions
  plan exit:139 block exit:139 block exit:139 block exit:139 block
  WATCH_BACKEND_RETRIES=2 WATCH_RECHECK_SECS=1 start_watch
  wait_until "$LIMIT" calls_at_least 8
  if ! exited && [ "$(calls)" -ge 8 ]; then
    pass "four crashes separated by healthy runs do not exhaust a budget of two (calls: $(calls))"
  else
    fail "four crashes separated by healthy runs do not exhaust a budget of two" "live after 8 calls" "exited $(ec) after $(calls) calls"
  fi
  notify_b
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "and the watch still exits 0 on a real update"
}

test_bounded_watch_treats_a_crash_as_a_wake() {
  two_sessions
  plan segv-on-change block
  start_watch --timeout 60
  wait_until "$LIMIT" fake_ready
  notify_b
  wait_exit "$LIMIT"
  assert_eq "0" "$(ec)" "a bounded watch drains an update whose write crashed its backend"
  assert_not_contains "timed out" "$(cat "$TEST_DIR/err")" "and does not report the crash as a timeout"
}

test_bounded_watch_keeps_its_deadline_after_a_crash() {
  two_sessions
  plan segv block
  local rc t0 t1
  t0=$(date +%s)
  tkf "$LIMIT" watch FIN-9 --timeout 4 "$TEST_DIR/sessions/B" >/dev/null 2>"$TEST_DIR/err"; rc=$?
  t1=$(date +%s)
  assert_eq "124" "$rc" "with no update, a bounded watch whose backend crashed still ends at its deadline with 124"
  assert_gt "$((t1 - t0))" "2" "it waited for the deadline instead of quitting at the crash (elapsed $((t1 - t0))s)"
  assert_contains "timed out after 4s" "$(cat "$TEST_DIR/err")" "and the 124 is its own deadline, not the test's limit"
}

run_discovered_tests
