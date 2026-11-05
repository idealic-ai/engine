#!/bin/bash
# ============================================================================
# test-ticket-watch-backend.sh — `engine ticket watch` when its fswatch backend dies
# ============================================================================
# A fake `fswatch` on PATH plays a scripted sequence of behaviours, one per call:
#   segv          die of a real SIGSEGV at once (timeout re-raises it, so the shell sees 139)
#   segv-after:N  wait N seconds, then die of SIGSEGV (a crash on an incoming event)
#   exit:N        exit with status N at once
#   block         wait until `timeout` ends the call (the watch's re-check tick, 124)
# Calls past the end of the sequence repeat its last line. The real fswatch is never run.
#
# The script under test is $ENGINE_SCRIPTS/ticket.sh when ENGINE_SCRIPTS is set, else the
# checkout this file lives in.
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPTS_UNDER_TEST="${ENGINE_SCRIPTS:-$(cd "$(dirname "$0")/.." && pwd)}"
TICKET_SH="$SCRIPTS_UNDER_TEST/ticket.sh"

TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.claude" "$TEST_DIR/sessions" "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/fswatch" <<'FAKE'
#!/bin/bash
plan="$FAKE_FSWATCH_PLAN" counter="$FAKE_FSWATCH_PLAN.calls"
n=$(( $(cat "$counter" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$counter"
step=$(sed -n "${n}p" "$plan")
[ -n "$step" ] || step=$(tail -1 "$plan")
case "$step" in
  segv) kill -SEGV $$ ;;
  segv-after:*) sleep "${step#segv-after:}"; kill -SEGV $$ ;;
  exit:*) exit "${step#exit:}" ;;
  block) exec sleep 600 ;;
esac
exit 99
FAKE
  chmod +x "$TEST_DIR/bin/fswatch"
}

teardown() {
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

# tkf <args...> — run ticket.sh in the sandbox with the fake fswatch first on PATH
tkf() {
  ( cd "$TEST_DIR" && PATH="$TEST_DIR/bin:$PATH" FAKE_FSWATCH_PLAN="$TEST_DIR/plan" \
      WATCH_BACKEND_RETRY_PAUSE="${WATCH_BACKEND_RETRY_PAUSE:-0}" "$TICKET_SH" "$@" )
}

notify_b() {
  ( cd "$TEST_DIR" && "$TICKET_SH" notify FIN-9 "reply" --from "$TEST_DIR/sessions/A" ) >/dev/null 2>&1
}

# start_watch <ecfile> <args...> — background watch; sets WPID
start_watch() {
  local ecfile="$1"; shift
  ( tkf watch FIN-9 "$@" "$TEST_DIR/sessions/B" > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $? > "$ecfile" ) &
  WPID=$!
}

# wait_exit <pid> <secs> — wait up to secs for pid to exit; then stop it
wait_exit() {
  local i=0
  while [ "$i" -lt "$2" ] && kill -0 "$1" 2>/dev/null; do sleep 0.25; i=$((i + 1)); done
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null
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
  local ec="$TEST_DIR/ec"
  WATCH_RECHECK_SECS=1 start_watch "$ec"
  sleep 2
  if kill -0 "$WPID" 2>/dev/null; then
    pass "unbounded watch is still live after its backend segfaulted"
  else
    fail "unbounded watch is still live after its backend segfaulted" "live" "exited $(cat "$ec" 2>/dev/null): $(cat "$TEST_DIR/err")"
  fi
  assert_not_empty "$(sget B '.watchTaskId.pid // empty')" "watchTaskId stays registered across the restart, so the gate still sees a watcher"
  notify_b
  wait_exit "$WPID" 24
  assert_eq "0" "$(cat "$ec" 2>/dev/null)" "the restarted watch exits 0 on the next real update"
  assert_contains "FIN-9" "$(cat "$TEST_DIR/out")" "and reports the ticket"
}

test_a_crash_on_an_event_is_treated_as_a_wake() {
  # The backend dies one second in, after the update has landed; the re-check tick is far away
  # (60s) and later calls block, so only re-checking on the crash itself finds the update quickly.
  two_sessions
  plan segv-after:1 block
  local ec="$TEST_DIR/ec"
  WATCH_RECHECK_SECS=60 start_watch "$ec"
  sleep 0.4
  notify_b
  wait_exit "$WPID" 20
  assert_eq "0" "$(cat "$ec" 2>/dev/null)" "an update that landed before the crash is drained on the crash, not on the next tick"
  assert_contains "FIN-9" "$(cat "$TEST_DIR/out")" "the crash-wake reports the ticket"
}

test_exit_2_backend_is_retried_too() {
  two_sessions
  plan exit:2 exit:2 block
  local ec="$TEST_DIR/ec"
  WATCH_RECHECK_SECS=1 start_watch "$ec"
  sleep 2
  if kill -0 "$WPID" 2>/dev/null; then pass "watch survives two backend exits of 2"; else fail "watch survives two backend exits of 2" "live" "exited $(cat "$ec" 2>/dev/null)"; fi
  notify_b
  wait_exit "$WPID" 24
  assert_eq "0" "$(cat "$ec" 2>/dev/null)" "and still exits 0 on a real update"
}

test_persistent_failure_gives_up_with_2_after_the_retry_budget() {
  two_sessions
  plan exit:2
  local rc
  WATCH_BACKEND_RETRIES=3 tkf watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>"$TEST_DIR/err"; rc=$?
  assert_eq "2" "$rc" "a backend that never runs cleanly ends the watch with 2"
  assert_eq "4" "$(calls)" "the backend was started once plus three retries, then the watch gave up"
  assert_contains "in a row" "$(cat "$TEST_DIR/err")" "the give-up message says the failures were consecutive"
  assert_empty "$(sget B '.watchTaskId.pid // empty')" "watchTaskId is cleared, so the gate sees the session unarmed"
}

test_a_healthy_run_resets_the_retry_budget() {
  # Crash, tick, crash, tick...: four crashes against a budget of two, never two in a row.
  two_sessions
  plan exit:139 block exit:139 block exit:139 block exit:139 block
  local ec="$TEST_DIR/ec"
  WATCH_BACKEND_RETRIES=2 WATCH_RECHECK_SECS=1 start_watch "$ec"
  local i=0
  while [ "$i" -lt 40 ] && [ "$(calls)" -lt 8 ] && kill -0 "$WPID" 2>/dev/null; do sleep 0.25; i=$((i + 1)); done
  if kill -0 "$WPID" 2>/dev/null; then
    pass "four crashes separated by healthy runs do not exhaust a budget of two (calls: $(calls))"
  else
    fail "four crashes separated by healthy runs do not exhaust a budget of two" "live" "exited $(cat "$ec" 2>/dev/null) after $(calls) calls"
  fi
  notify_b
  wait_exit "$WPID" 24
  assert_eq "0" "$(cat "$ec" 2>/dev/null)" "and the watch still exits 0 on a real update"
}

test_bounded_watch_treats_a_crash_as_a_wake() {
  two_sessions
  plan segv-after:1 block
  local ec="$TEST_DIR/ec"
  start_watch "$ec" --timeout 30
  sleep 0.4
  notify_b
  wait_exit "$WPID" 20
  assert_eq "0" "$(cat "$ec" 2>/dev/null)" "a bounded watch drains an update that landed before its backend crashed"
  assert_not_contains "timed out" "$(cat "$TEST_DIR/err")" "and does not report the crash as a timeout"
}

test_bounded_watch_keeps_its_deadline_after_a_crash() {
  two_sessions
  plan segv block
  local rc t0 t1
  t0=$(date +%s)
  tkf watch FIN-9 --timeout 4 "$TEST_DIR/sessions/B" >/dev/null 2>"$TEST_DIR/err"; rc=$?
  t1=$(date +%s)
  assert_eq "124" "$rc" "with no update, a bounded watch whose backend crashed still ends at its deadline with 124"
  assert_gt "$((t1 - t0))" "2" "it waited for the deadline instead of quitting at the crash (elapsed $((t1 - t0))s)"
}

run_discovered_tests
