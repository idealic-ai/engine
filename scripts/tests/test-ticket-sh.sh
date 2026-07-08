#!/bin/bash
# ============================================================================
# test-ticket-sh.sh — Tests for ticket.sh (engine ticket subscribe/notify)
# ============================================================================
# Verifies the dirty-flag + watermark ticket subsystem:
#   subscribe/unsubscribe on a session's .state.json.tickets[]
#   notify fan-out into subscribers' .state.json.updatedTickets[] (excl. notifier)
#   read (drain + advance lastReadAt) and list (non-destructive peek)
# Sessions dir is anchored via a $TEST_DIR/.claude marker (find_project_root),
# so all state lives under a mktemp sandbox.
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TICKET_SH="$HOME/.claude/engine/scripts/ticket.sh"

# ---- Setup / Teardown (run_test invokes these around each test) ----
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.claude" "$TEST_DIR/sessions"
}

teardown() {
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
  TEST_DIR=""
}

# mkstate <session-name> <json> — create sessions/<name>/.state.json with given JSON
mkstate() {
  local name="$1" json="$2"
  mkdir -p "$TEST_DIR/sessions/$name"
  echo "$json" > "$TEST_DIR/sessions/$name/.state.json"
}

# tk <args...> — run ticket.sh from inside the sandbox so resolve_sessions_dir anchors there
tk() {
  ( cd "$TEST_DIR" && "$TICKET_SH" "$@" )
}

# sget <session-name> <jq-filter> — read a value out of a session's state
sget() {
  jq -r "$2" "$TEST_DIR/sessions/$1/.state.json" 2>/dev/null
}

# ---- Tests ----

test_subscribe_adds_object() {
  mkstate S1 '{"skill":"implement"}'
  tk subscribe fin-2712 "$TEST_DIR/sessions/S1" >/dev/null 2>&1
  assert_eq "FIN-2712" "$(sget S1 '.tickets[0].key')" "subscribe normalizes+stores key"
  assert_not_empty "$(sget S1 '.tickets[0].subscribedAt')" "subscribe stamps subscribedAt"
  assert_not_empty "$(sget S1 '.tickets[0].lastReadAt')" "subscribe stamps lastReadAt"
}

test_subscribe_idempotent_case_insensitive() {
  mkstate S1 '{}'
  tk subscribe FIN-2712 "$TEST_DIR/sessions/S1" >/dev/null 2>&1
  tk subscribe fin-2712 "$TEST_DIR/sessions/S1" >/dev/null 2>&1
  assert_eq "1" "$(sget S1 '.tickets | length')" "re-subscribe (any case) does not duplicate"
}

test_unsubscribe_removes() {
  mkstate S1 '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2020-02-02T00:00:00Z","from":"x","note":"n"}]}'
  tk unsubscribe FIN-9 "$TEST_DIR/sessions/S1" >/dev/null 2>&1
  assert_eq "0" "$(sget S1 '.tickets | length')" "unsubscribe empties tickets"
  assert_eq "0" "$(sget S1 '.updatedTickets | length')" "unsubscribe purges its dirty entries"
}

test_notify_delivers_to_subscriber() {
  mkstate A '{}'
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  tk notify FIN-9 "posted rebuttal" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1
  assert_eq "1" "$(sget B '.updatedTickets | length')" "subscriber B gets a dirty entry"
  assert_eq "FIN-9" "$(sget B '.updatedTickets[0].ticket')" "dirty entry has ticket key"
  assert_eq "posted rebuttal" "$(sget B '.updatedTickets[0].note')" "dirty entry carries note"
}

test_notify_excludes_notifier() {
  mkstate A '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  tk notify FIN-9 "hi" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1
  assert_eq "0" "$(sget A '(.updatedTickets // []) | length')" "notifier A does NOT get its own notify"
  assert_eq "1" "$(sget B '.updatedTickets | length')" "other subscriber B is notified"
}

test_notify_no_subscribers_is_noop() {
  mkstate A '{}'
  if tk notify FIN-404 "nobody home" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1; then
    pass "notify with zero subscribers exits 0"
  else
    fail "notify with zero subscribers exits 0" "exit 0" "exit non-zero"
  fi
}

test_read_drains_and_reports_since() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-05-05T00:00:00Z","from":"A","note":"n"}]}'
  local out
  out=$(tk read --json "$TEST_DIR/sessions/B" 2>/dev/null)
  assert_eq "2020-01-01T00:00:00Z" "$(echo "$out" | jq -r '.[0].since')" "read reports since = prior lastReadAt"
  assert_eq "FIN-9" "$(echo "$out" | jq -r '.[0].ticket')" "read reports the ticket"
  assert_eq "0" "$(sget B '.updatedTickets | length')" "read drains the queue"
  assert_neq "2020-01-01T00:00:00Z" "$(sget B '.tickets[0].lastReadAt')" "read advances lastReadAt off the old value"
}

test_list_is_non_destructive() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-05-05T00:00:00Z","from":"A","note":"n"}]}'
  tk list "$TEST_DIR/sessions/B" >/dev/null 2>&1
  assert_eq "1" "$(sget B '.updatedTickets | length')" "list leaves the queue intact"
  assert_eq "2020-01-01T00:00:00Z" "$(sget B '.tickets[0].lastReadAt')" "list leaves lastReadAt intact"
}

test_read_since_filters() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2022-01-01T00:00:00Z","from":"A","note":"old"},{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"new"}]}'
  tk read --since 2023-01-01T00:00:00Z --json "$TEST_DIR/sessions/B" >/dev/null 2>&1
  assert_eq "1" "$(sget B '.updatedTickets | length')" "read --since drains only newer entry"
  assert_eq "old" "$(sget B '.updatedTickets[0].note')" "older entry survives the filtered drain"
}

test_read_empty_is_clean() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  if tk read --json "$TEST_DIR/sessions/B" >/dev/null 2>&1; then
    pass "read with empty queue exits 0"
  else
    fail "read with empty queue exits 0" "exit 0" "exit non-zero"
  fi
  assert_eq "0" "$(tk read --json "$TEST_DIR/sessions/B" 2>/dev/null | jq 'length')" "read --json empty queue → empty array"
}

test_activate_seeds_subscription() {
  local session_sh="$HOME/.claude/engine/scripts/session.sh"
  local sdir="$TEST_DIR/sessions/seed_session"
  mkdir -p "$sdir"
  export CLAUDE_SUPERVISOR_PID=$$
  ( cd "$TEST_DIR" && "$session_sh" activate "$sdir" implement >/dev/null 2>&1 <<'JSON'
{"taskSummary":"seed test","scope":"x","directoriesOfInterest":[],"contextPaths":[],"requestFiles":[],"extraInfo":null,"tickets":["fin-1"]}
JSON
  )
  assert_eq "FIN-1" "$(jq -r '.tickets[0].key // empty' "$sdir/.state.json" 2>/dev/null)" "activate seeds normalized subscription from tickets param"
  assert_eq "object" "$(jq -r '.tickets[0] | type' "$sdir/.state.json" 2>/dev/null)" "seeded ticket is an object, not a bare string"
  assert_not_empty "$(jq -r '.tickets[0].subscribedAt // empty' "$sdir/.state.json" 2>/dev/null)" "seeded ticket has subscribedAt"
}

# ---- watch (fswatch-based blocking watcher; local-signal) ----

test_watch_race_guard_exits_zero() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"q"}]}'
  local out ec
  out=$(tk watch FIN-9 --timeout 5 "$TEST_DIR/sessions/B" 2>/dev/null); ec=$?
  assert_eq "0" "$ec" "watch exits 0 when an update is already pending (race guard)"
  assert_contains "FIN-9" "$out" "watch prints the matched ticket key"
}

test_watch_timeout_exits_124() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  local ec
  tk watch FIN-9 --timeout 1 "$TEST_DIR/sessions/B" >/dev/null 2>&1; ec=$?
  assert_eq "124" "$ec" "watch exits 124 on timeout with no pending update"
}

test_watch_all_subscribed_no_key() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"q"}]}'
  local out ec
  out=$(tk watch --timeout 5 "$TEST_DIR/sessions/B" 2>/dev/null); ec=$?
  assert_eq "0" "$ec" "watch (no key) exits 0 on any subscribed ticket's update"
  assert_contains "FIN-9" "$out" "watch-all prints the matched key"
}

test_watch_key_filters_out_others() {
  mkstate B '{"tickets":[{"key":"FIN-8","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"},{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-8","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"q"}]}'
  local ec
  tk watch FIN-9 --timeout 1 "$TEST_DIR/sessions/B" >/dev/null 2>&1; ec=$?
  assert_eq "124" "$ec" "watch KEY ignores updates for other tickets (times out)"
}

test_watch_no_watchable_exits_1() {
  mkstate B '{}'
  local ec
  tk watch --timeout 1 "$TEST_DIR/sessions/B" >/dev/null 2>&1; ec=$?
  assert_eq "1" "$ec" "watch with no subscriptions and no key exits 1"
}

test_watch_ignores_already_read_entry() {
  # An updatedTickets entry OLDER than the ticket's lastReadAt watermark (already seen,
  # left un-drained by a keyed/--since read or a re-arm-without-drain) must NOT re-wake.
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2024-06-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"stale"}]}'
  local ec
  tk watch FIN-9 --timeout 1 "$TEST_DIR/sessions/B" >/dev/null 2>&1; ec=$?
  assert_eq "124" "$ec" "watch ignores an already-read (notifiedAt <= lastReadAt) entry — no stale re-wake"
}

test_watch_fires_on_fresh_entry_past_watermark() {
  # A fresh notify (notifiedAt > lastReadAt) fires even when an older already-read entry
  # for the same ticket still lingers in the queue.
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2024-06-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"stale"},{"ticket":"FIN-9","notifiedAt":"2024-12-01T00:00:00Z","from":"B","note":"fresh"}]}'
  local out ec
  out=$(tk watch FIN-9 --timeout 5 "$TEST_DIR/sessions/B" 2>/dev/null); ec=$?
  assert_eq "0" "$ec" "watch fires on a fresh entry past the watermark despite an older lingering one"
  assert_contains "FIN-9" "$out" "watch prints the freshly-updated key"
}

test_watch_wakes_on_background_notify() {
  mkstate A '{}'
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  local ecfile="$TEST_DIR/watch.ec"
  ( tk watch FIN-9 --timeout 15 "$TEST_DIR/sessions/B" >/dev/null 2>&1; echo $? > "$ecfile" ) &
  local wpid=$!
  sleep 2
  tk notify FIN-9 "reply" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1
  wait "$wpid"
  assert_eq "0" "$(cat "$ecfile" 2>/dev/null)" "watch wakes and exits 0 when a notify lands mid-watch"
}

# ---- unbounded default (no --timeout → block until a real update; no fake-wake) ----

test_watch_unbounded_default_race_guard_exits_zero() {
  # With NO --timeout, an already-pending update must still short-circuit to exit 0
  # (never block). Proves the unbounded default doesn't hang when a match exists.
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"q"}]}'
  local out ec
  out=$(tk watch FIN-9 "$TEST_DIR/sessions/B" 2>/dev/null); ec=$?
  assert_eq "0" "$ec" "unbounded watch (no --timeout) exits 0 when an update is already pending"
  assert_contains "FIN-9" "$out" "unbounded watch prints the matched key"
}

test_watch_unbounded_default_wakes_on_notify() {
  # With NO --timeout, an unbounded watch blocks until a real notify, then exits 0 —
  # it never self-terminates on a deadline (no 124 fake-wake).
  mkstate A '{}'
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  local ecfile="$TEST_DIR/watch-unbounded.ec"
  ( tk watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>&1; echo $? > "$ecfile" ) &
  local wpid=$!
  sleep 2
  assert_not_empty "$(sget B '.watchTaskId.pid // empty')" "unbounded watch registers a live watchTaskId while blocking"
  tk notify FIN-9 "reply" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1
  # Safety net: an unbounded watch has no self-timeout, so if the notify ever races
  # past it this test must NOT hang the suite — bounded-poll for exit, then hard-kill.
  local i
  for i in 1 2 3 4 5 6 7 8; do kill -0 "$wpid" 2>/dev/null || break; sleep 1; done
  kill "$wpid" 2>/dev/null
  wait "$wpid" 2>/dev/null
  assert_eq "0" "$(cat "$ecfile" 2>/dev/null)" "unbounded watch wakes and exits 0 on a real notify (no deadline)"
}

test_watch_unbounded_poll_tick_does_not_wake() {
  # The internal re-check tick (WATCH_RECHECK_SECS) must NOT exit the process — only a
  # real match does. With a 1s tick and no pending update, the watch survives many
  # ticks (stays live), then exits 0 only when a genuine notify lands.
  mkstate A '{}'
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  local ecfile="$TEST_DIR/watch-poll.ec"
  ( WATCH_RECHECK_SECS=1 tk watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>&1; echo $? > "$ecfile" ) &
  local wpid=$!
  sleep 4  # ~4 re-check ticks with no match
  if kill -0 "$wpid" 2>/dev/null; then
    pass "unbounded watch survives internal re-check ticks without exiting (no fake-wake)"
  else
    fail "unbounded watch survives internal re-check ticks without exiting (no fake-wake)" "still blocking" "exited (code $(cat "$ecfile" 2>/dev/null))"
  fi
  tk notify FIN-9 "reply" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1
  local i
  for i in 1 2 3 4 5 6 7 8; do kill -0 "$wpid" 2>/dev/null || break; sleep 1; done
  kill "$wpid" 2>/dev/null
  wait "$wpid" 2>/dev/null
  assert_eq "0" "$(cat "$ecfile" 2>/dev/null)" "unbounded watch still exits 0 on a real notify after surviving ticks"
}

# ---- watchTaskId self-registration (auto-watch hard-gate liveness source) ----

test_watch_self_registers_live_pid() {
  mkstate A '{}'
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  ( tk watch FIN-9 --timeout 15 "$TEST_DIR/sessions/B" >/dev/null 2>&1 ) &
  local wpid=$!
  sleep 2
  local pid
  pid=$(sget B '.watchTaskId.pid // empty')
  assert_not_empty "$pid" "watch registers watchTaskId.pid while blocking"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    pass "registered watchTaskId.pid is a live process (kill -0)"
  else
    fail "registered watchTaskId.pid is a live process (kill -0)" "alive pid" "$pid"
  fi
  assert_not_empty "$(sget B '.watchTaskId.startedAt // empty')" "watchTaskId carries startedAt"
  assert_contains "FIN-9" "$(sget B '.watchTaskId.keys // empty')" "watchTaskId.keys records the watched set"
  tk notify FIN-9 "reply" --from "$TEST_DIR/sessions/A" >/dev/null 2>&1
  wait "$wpid" 2>/dev/null
  assert_empty "$(sget B '.watchTaskId.pid // empty')" "watchTaskId cleared on graceful wake exit"
}

test_watch_clears_watchtaskid_on_timeout() {
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  local ec
  tk watch FIN-9 --timeout 1 "$TEST_DIR/sessions/B" >/dev/null 2>&1; ec=$?
  assert_eq "124" "$ec" "watch still exits 124 on timeout (self-reg preserves exit code)"
  assert_empty "$(sget B '.watchTaskId.pid // empty')" "watchTaskId cleared after timeout via trap"
}

test_watch_trap_pid_guard_preserves_newer() {
  # A stale watchTaskId from a DIFFERENT (dead) pid must not be clobbered-cleared by
  # a race-guard early-return path (which never registers or traps).
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}],"updatedTickets":[{"ticket":"FIN-9","notifiedAt":"2024-01-01T00:00:00Z","from":"A","note":"q"}],"watchTaskId":{"pid":999999,"startedAt":"2020-01-01T00:00:00Z","keys":"FIN-9"}}'
  # Race guard returns 0 immediately (pending update) — must not touch a foreign watchTaskId.
  tk watch FIN-9 --timeout 5 "$TEST_DIR/sessions/B" >/dev/null 2>&1
  assert_eq "999999" "$(sget B '.watchTaskId.pid // empty')" "race-guard exit leaves a foreign watchTaskId untouched (pid-guarded trap)"
}

test_watch_supersedes_previous_watcher() {
  # Arming a new watcher kills the previous live one — only ONE watcher per session,
  # so re-arming can't stack multiple blocked fswatch shells.
  mkstate B '{"tickets":[{"key":"FIN-9","subscribedAt":"2020-01-01T00:00:00Z","lastReadAt":"2020-01-01T00:00:00Z"}]}'
  ( tk watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>&1 ) &
  local w1=$!
  sleep 2
  local pid1; pid1=$(sget B '.watchTaskId.pid // empty')
  ( tk watch FIN-9 "$TEST_DIR/sessions/B" >/dev/null 2>&1 ) &
  local w2=$!
  sleep 2
  local pid2; pid2=$(sget B '.watchTaskId.pid // empty')

  if [ -n "$pid1" ] && [ -n "$pid2" ] && [ "$pid1" != "$pid2" ]; then
    pass "re-arm registers a new watcher pid (supersede)"
  else
    fail "re-arm registers a new watcher pid (supersede)" "pid1 != pid2 (both set)" "pid1=$pid1 pid2=$pid2"
  fi
  # The superseded watcher's process is dead; the new one is still live and registered.
  if kill -0 "$pid1" 2>/dev/null; then
    fail "previous watcher killed when a new one arms" "pid1 dead" "pid1 alive"
  else
    pass "previous watcher killed when a new one arms"
  fi
  assert_eq "$pid2" "$(sget B '.watchTaskId.pid // empty')" "watchTaskId points at the surviving (newest) watcher"

  kill "$pid1" "$pid2" "$w1" "$w2" 2>/dev/null
  wait "$w1" "$w2" 2>/dev/null
}

run_discovered_tests
