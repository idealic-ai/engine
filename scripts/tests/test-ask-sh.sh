#!/bin/bash
# test-ask-sh.sh — CLI coverage for scripts/ask.sh (`engine ask new|list|answer|serve|path`).
#
# Every test runs against a throwaway ASK_ROOT and an empty ASK_SESSIONS_DIR, so no real seat is
# ever messaged and the fleet's real asks directory is never touched.
set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# The checkout under test is the one this file lives in (ASK_ENGINE_DIR overrides it), never a fixed
# ~/.claude/engine: a worktree's suite must exercise the worktree's ask.sh and ask-app, not the live copy.
ENGINE_DIR="${ASK_ENGINE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
ASK_SH="$ENGINE_DIR/scripts/ask.sh"
ENGINE_SH="$ENGINE_DIR/scripts/engine.sh"

# The served client is built ONCE into a throwaway dir: no test ever builds into (or serves) the
# app's own dist/, which a live server may be reading.
ASK_TEST_DIST_DIR=$(mktemp -d /tmp/askdist-XXXXXX)
trap 'rm -rf "$ASK_TEST_DIST_DIR"' EXIT
(cd "$ENGINE_DIR/tools/ask-app" && npx vite build --logLevel error --outDir "$ASK_TEST_DIST_DIR/dist" --emptyOutDir) >/dev/null 2>&1 \
  || { echo "could not build the test client" >&2; exit 1; }

BODY='## ¶ASK_GO: Choose one: Ship it?
- [ ] [YES] Yes
  Ship tonight.
- [ ] [NO] No'

setup() {
  TMP=$(mktemp -d /tmp/askcli-XXXXXX)
  export ASK_ROOT="$TMP/asks"
  export ASK_SESSIONS_DIR="$TMP/sessions"
  mkdir -p "$ASK_SESSIONS_DIR"
  # The suite never reads live tmux: with no TMUX_PANE the CLI uses FLEET_PANE/FLEET_PARENT.
  unset FLEET_PARENT FLEET_MANAGES LINEAR_API_KEY TMUX_PANE ASK_LIVE_PANES ASK_TMUX_SOCKET
  export FLEET_PANE="idealic:kernel"
  export ASK_APP_DIST="$ASK_TEST_DIST_DIR/dist"
  # No test server reads a real Linear key: the S7 test unsets this to exercise the lookup.
  export ASK_LINEAR_ENV=/dev/null
}

# as_op <args…>: the operator at a bare terminal (no FLEET_PANE), naming itself.
as_op() { env -u FLEET_PANE "$ASK_SH" "$@" --by operator; }
teardown() {
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1 || true
  # NEW-5: a red run must not leak a server. Kill only servers for THIS throwaway root.
  local p
  for p in $(pgrep -f "ask-app/src/server.ts --root $(cd "$ASK_ROOT" 2>/dev/null && pwd -P || echo "$ASK_ROOT") " 2>/dev/null); do kill "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}

test_path_prints_root_seat_dir_and_file() {
  assert_eq "$ASK_ROOT" "$("$ASK_SH" path)" "path with no args prints the asks root"
  assert_eq "$ASK_ROOT/manager:app" "$("$ASK_SH" path manager:app)" "path SEAT prints the seat dir"
  assert_eq "$ASK_ROOT/manager:app/a1.md" "$("$ASK_SH" path manager:app a1)" "path SEAT ID prints the file"
}

test_engine_dispatcher_reaches_ask() {
  assert_eq "$ASK_ROOT" "$("$ENGINE_SH" ask path)" "engine ask path goes through the generic fallback"
}

test_new_writes_file_with_defaults_from_env() {
  local out
  out=$(printf '%s\n' "$BODY" | "$ASK_SH" new --id a1 --why "blocks two lanes" --importance high)
  assert_eq "$ASK_ROOT/idealic:kernel/a1.md" "$out" "new prints the file path under the FLEET_PANE seat"
  assert_file_exists "$out" "the ask file exists"
  assert_contains "to: operator" "$(cat "$out")" "with no FLEET_PARENT the ask goes to the operator"
  assert_contains "status: open" "$(cat "$out")" "a new ask is open"
  assert_contains "why: blocks two lanes" "$(cat "$out")" "header flags land in the header"
}

test_new_to_defaults_to_fleet_parent() {
  local out
  out=$(printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id a2)
  assert_contains "to: manager:idealic" "$(cat "$out")" "FLEET_PARENT is the default recipient"
}

# Fails with a message: assert the exit code AND the specific error, so an unrelated failure cannot pass.
assert_fails_with() {
  local desc="$1" want="$2"; shift 2
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qF -- "$want"; then pass "$desc"
  else fail "$desc" "non-zero exit with '$want'" "rc=$rc out=$out"; fi
}

test_new_refuses_body_without_question() {
  assert_fails_with "new refuses a body with no Choose heading" "body holds no question" \
    bash -c "echo 'just prose' | '$ASK_SH' new --id a3"
}

test_new_refuses_duplicate_id() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id a4 >/dev/null
  assert_fails_with "new refuses an id that already exists" "ask already exists" \
    bash -c "printf '%s\n' '$BODY' | '$ASK_SH' new --id a4"
}

test_list_shows_open_and_filters() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id l1 --importance high >/dev/null
  printf '%s\n' "$BODY" | FLEET_PANE=manager:app "$ASK_SH" new --id l2 --to manager:director >/dev/null
  local out
  out=$("$ASK_SH" list)
  assert_contains "idealic:kernel/l1" "$out" "list shows the first ask"
  assert_contains "manager:app/l2" "$out" "list shows asks across seats"
  assert_contains "Ship it?" "$out" "list shows the first question's title"
  out=$("$ASK_SH" list --to manager:director)
  assert_not_contains "idealic:kernel/l1" "$out" "--to filters by recipient"
  assert_contains "manager:app/l2" "$out" "--to keeps the matching ask"
}

test_answer_writes_json_and_marks_undelivered() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q1 >/dev/null
  local out file
  # The asker (FLEET_PANE in setup) cannot answer its own ask; the operator at a terminal does.
  out=$(as_op answer idealic:kernel/q1 --revision 1 --json '{"GO":["YES"]}' --note "ship it")
  assert_contains "undelivered" "$out" "answer reports undelivered when the asker has no live session"
  file="$ASK_ROOT/idealic:kernel/q1.md"
  assert_contains "status: answered" "$(cat "$file")" "the file is marked answered"
  assert_contains "delivery: undelivered" "$(cat "$file")" "the file records the failed push"
  assert_contains '```json answer' "$(cat "$file")" "the answer is embedded as a json answer block"
  assert_contains '"YES"' "$(cat "$file")" "the selected code is in the answer"
  assert_not_contains "idealic:kernel/q1" "$("$ASK_SH" list)" "an answered ask leaves the default (open) list"
  assert_contains "idealic:kernel/q1" "$("$ASK_SH" list --status answered)" "--status answered shows it"
}

test_answer_refuses_bad_json() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q2 >/dev/null
  assert_fails_with "answer refuses invalid json" "--json is not valid JSON" \
    "$ASK_SH" answer idealic:kernel/q2 --revision 1 --json '{nope'
}

test_answer_refuses_empty_and_unknown() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q3 >/dev/null
  assert_fails_with "answer refuses {}" "empty answer is not an answer" as_op answer idealic:kernel/q3 --revision 1 --json '{}'
  assert_fails_with "answer refuses an unknown key" "unknown question: NOPE" as_op answer idealic:kernel/q3 --revision 1 --json '{"NOPE":["YES"]}'
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/q3.md")" "a refused answer writes nothing"
}

test_answer_requires_revision_and_refuses_stale() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q4 >/dev/null
  assert_fails_with "answer without --revision is refused" "--revision is required" as_op answer idealic:kernel/q4 --json '{"GO":["YES"]}'
  as_op answer idealic:kernel/q4 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  assert_fails_with "a stale revision is refused" "stale revision" as_op answer idealic:kernel/q4 --revision 1 --json '{"GO":["NO"]}'
  assert_contains '"YES"' "$(cat "$ASK_ROOT/idealic:kernel/q4.md")" "the first answer stands"
}

test_answer_decline_needs_reason() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q5 >/dev/null
  assert_fails_with "decline without a reason is refused" "non-empty reason" as_op answer idealic:kernel/q5 --revision 1 --decline "  "
  as_op answer idealic:kernel/q5 --revision 1 --decline "beyond my grant" >/dev/null
  assert_contains "status: declined" "$(cat "$ASK_ROOT/idealic:kernel/q5.md")" "a decline is recorded as declined"
  assert_contains "beyond my grant" "$(cat "$ASK_ROOT/idealic:kernel/q5.md")" "with its reason"
}

test_stop_never_kills_a_stranger() {
  sleep 300 & local victim=$!
  mkdir -p "$ASK_ROOT"; echo "$victim 4977" > "$ASK_ROOT/.ask-app.pid"
  local out; out=$("$ASK_SH" serve "$ASK_ROOT" --stop 2>&1)
  if kill -0 "$victim" 2>/dev/null; then pass "--stop leaves a recycled pid alone"; else fail "--stop leaves a recycled pid alone" "victim alive" "victim killed"; fi
  assert_contains "stale" "$out" "--stop says the pidfile was stale"
  assert_file_not_exists "$ASK_ROOT/.ask-app.pid" "the stale pidfile is removed"
  kill "$victim" 2>/dev/null || true
}

test_serve_concurrent_starts_leave_one_server() {
  local port=$((20000 + RANDOM % 20000)) i pids
  for i in 1 2 3; do "$ASK_SH" serve "$ASK_ROOT" --port "$port" >"$TMP/race$i.out" 2>&1 & done
  wait
  pids=$(pgrep -f "server.ts --root $(cd "$ASK_ROOT" && pwd -P) " | wc -l | tr -d ' ')
  assert_eq "1" "$pids" "three concurrent serves leave exactly one server for the root"
  local served filed
  served=$(curl -s "http://127.0.0.1:$port/api/health" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pid"])')
  filed=$(awk '{print $1}' "$ASK_ROOT/.ask-app.pid")
  assert_eq "$served" "$filed" "the pidfile names the server that is actually serving"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null
  assert_eq "0" "$(pgrep -f "server.ts --root $(cd "$ASK_ROOT" && pwd -P) " | wc -l | tr -d ' ')" "--stop then leaves none"
}

test_serve_is_idempotent() {
  local port url1 url2 pid1 pid2 health
  port=$((20000 + RANDOM % 20000))
  url1=$("$ASK_SH" serve "$ASK_ROOT" --port "$port" | tail -1)
  assert_eq "http://127.0.0.1:$port/" "$url1" "serve prints the loopback URL"
  health=$(curl -s "http://127.0.0.1:$port/api/health")
  assert_contains '"app":"ask-app"' "$health" "the server answers its health check"
  pid1=$(awk '{print $1}' "$ASK_ROOT/.ask-app.pid")
  url2=$("$ASK_SH" serve "$ASK_ROOT" --port "$port" | tail -1)
  pid2=$(awk '{print $1}' "$ASK_ROOT/.ask-app.pid")
  assert_eq "$url1" "$url2" "a second serve prints the same URL"
  assert_eq "$pid1" "$pid2" "a second serve reuses the running instance"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null
  assert_fail "stop shuts the server down" curl -sf "http://127.0.0.1:$port/api/health"
}

test_unknown_subcommand_fails() {
  assert_fails_with "an unknown subcommand exits non-zero" "unknown subcommand 'frobnicate'" "$ASK_SH" frobnicate
}

# ── v2 ───────────────────────────────────────────────────

test_v2_new_sets_card_fields_and_reserved_for() {
  local out
  out=$(printf '%s\n' "$BODY" | "$ASK_SH" new --id c1 --stake "two lanes stall" --unblocks "E14" --tickets "IDE-253" --reserved-for operator --rank "1 of 3")
  assert_contains "stake: two lanes stall" "$(cat "$out")" "--stake lands in the header"
  assert_contains "reserved-for: operator" "$(cat "$out")" "--reserved-for lands in the header"
  assert_contains "tickets: IDE-253" "$(cat "$out")" "--tickets lands in the header"
}

test_v2_reserved_ask_refuses_a_seat_and_by_operator_from_a_seat() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id r1 --reserved-for operator >/dev/null
  assert_fails_with "a seat cannot answer a reserved-for operator ask" "reserved for operator" \
    env FLEET_PANE=manager:director "$ASK_SH" answer idealic:kernel/r1 --revision 1 --json '{"GO":["YES"]}'
  assert_fails_with "--by operator from a seat with FLEET_PANE is refused" "--by operator from a seat" \
    env FLEET_PANE=manager:director "$ASK_SH" answer idealic:kernel/r1 --revision 1 --json '{"GO":["YES"]}' --by operator
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/r1.md")" "the reserved ask stays open"
  env -u FLEET_PANE "$ASK_SH" answer idealic:kernel/r1 --revision 1 --json '{"GO":["YES"]}' --by operator >/dev/null
  assert_contains "status: answered" "$(cat "$ASK_ROOT/idealic:kernel/r1.md")" "the operator at a terminal with no FLEET_PANE can answer it"
}

test_v2_draft_then_send_one_message_per_seat() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id b1 >/dev/null
  printf '%s\n' "$BODY" | "$ASK_SH" new --id b2 >/dev/null
  as_op draft idealic:kernel/b1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  as_op draft idealic:kernel/b2 --revision 1 --decline "not mine" >/dev/null
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/b1.md")" "a draft leaves the ask open"
  assert_contains '```json draft' "$(cat "$ASK_ROOT/idealic:kernel/b1.md")" "the draft is in the file"
  assert_contains "draft" "$("$ASK_SH" list)" "list shows that an ask holds a draft"
  assert_contains "no drafts of yours to send" "$("$ASK_SH" send)" "S1: a seat's bare send never flushes the operator's drafts"
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/b1.md")" "so b1 is still open"
  local out; out=$(as_op send)
  assert_contains "settled idealic:kernel/b1" "$out" "send settles the first draft"
  assert_contains "settled idealic:kernel/b2" "$out" "send settles the second draft"
  assert_contains "push idealic:kernel undelivered (2 asks)" "$out" "ONE push for the seat, covering both asks"
  assert_contains "status: answered" "$(cat "$ASK_ROOT/idealic:kernel/b1.md")" "b1 is answered"
  assert_contains "status: declined" "$(cat "$ASK_ROOT/idealic:kernel/b2.md")" "b2 is declined"
}

test_v2_send_without_a_draft_sends_nothing() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id b3 >/dev/null
  local out; out=$(as_op send idealic:kernel/b3 2>&1)
  assert_contains "refused idealic:kernel/b3" "$out" "a ref with no draft is refused"
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/b3.md")" "and nothing is written"
}

test_v2_read_stamps_readAt_and_acted_stamps_acted() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id rd1 >/dev/null
  as_op answer idealic:kernel/rd1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  local out; out=$(FLEET_PANE=idealic:kernel "$ASK_SH" read idealic:kernel/rd1)
  assert_contains "Ship it? → Yes · idealic:kernel/rd1#GO" "$out" "read prints title → answer · id"
  assert_contains "readAt: " "$(cat "$ASK_ROOT/idealic:kernel/rd1.md")" "read stamps readAt"
  assert_contains "readBy: idealic:kernel" "$(cat "$ASK_ROOT/idealic:kernel/rd1.md")" "and who read it"
  FLEET_PANE=idealic:kernel "$ASK_SH" acted idealic:kernel/rd1 "shipped it" >/dev/null
  assert_contains "acted: shipped it" "$(cat "$ASK_ROOT/idealic:kernel/rd1.md")" "acted stamps its summary"
  assert_contains "acted" "$("$ASK_SH" list --status answered)" "list shows the acted state"
}

test_v2_read_by_a_non_recipient_is_not_a_read() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id rd2 >/dev/null
  as_op answer idealic:kernel/rd2 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  local out; out=$(FLEET_PANE=manager:idealic "$ASK_SH" read idealic:kernel/rd2 2>&1)
  assert_contains "not stamped" "$out" "a non-recipient's read says it was not stamped"
  assert_not_contains "readAt: " "$(cat "$ASK_ROOT/idealic:kernel/rd2.md")" "and no readAt is written"
}

test_v2_pickup_reads_settled_unread_including_declines() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id p1 >/dev/null
  printf '%s\n' "$BODY" | "$ASK_SH" new --id p2 >/dev/null
  as_op answer idealic:kernel/p1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  as_op answer idealic:kernel/p2 --revision 1 --decline "no" >/dev/null
  local out; out=$(FLEET_PANE=idealic:kernel "$ASK_SH" read --unread)
  assert_contains "idealic:kernel/p1" "$out" "the pickup reads the answered ask"
  assert_contains "idealic:kernel/p2" "$out" "the pickup reads the declined ask (NEW-4)"
  assert_eq "" "$(FLEET_PANE=idealic:kernel "$ASK_SH" read --unread)" "a second pickup finds nothing unread"
}

test_v2_list_status_settled_includes_declines() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id s1 >/dev/null
  as_op answer idealic:kernel/s1 --revision 1 --decline "no" >/dev/null
  assert_contains "idealic:kernel/s1" "$("$ASK_SH" list --status settled)" "--status settled includes a decline (NEW-4)"
  assert_contains "idealic:kernel/s1" "$("$ASK_SH" list --status answered,declined)" "a comma list of statuses works"
}

test_v2_forward_only_by_holder_and_recorded() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id f1 >/dev/null
  assert_fails_with "the asker cannot move to:" "only the holder" \
    env FLEET_PANE=idealic:kernel "$ASK_SH" forward idealic:kernel/f1 --to operator
  FLEET_PANE=manager:idealic "$ASK_SH" forward idealic:kernel/f1 --to manager:director >/dev/null
  assert_contains "to: manager:director" "$(cat "$ASK_ROOT/idealic:kernel/f1.md")" "the holder moved it"
  assert_contains "forwards: manager:idealic→manager:director@" "$(cat "$ASK_ROOT/idealic:kernel/f1.md")" "and the move is recorded"
  assert_contains "idealic:kernel/f1" "$("$ASK_SH" list --status open --to manager:director)" "hop.sh's inbox query still finds it"
}

# NEW-2: a lock left by a SIGKILLed serve is recovered (BSD find rejected -mmin +0.5, so it never was).
test_v2_stale_serve_lock_is_recovered() {
  mkdir -p "$ASK_ROOT/.ask-app.lock"
  touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$ASK_ROOT/.ask-app.lock"
  local out rc
  out=$("$ASK_SH" serve "$ASK_ROOT" --stop 2>&1); rc=$?
  assert_eq "0" "$rc" "--stop succeeds past a 2-minute-old lock"
  assert_contains "not running" "$out" "and reports the true state"
}

# NEW-1: a server whose pidfile was lost is found by its root, so a second serve adopts it.
test_v2_lost_pidfile_server_is_adopted_not_doubled() {
  local port=$((20000 + RANDOM % 20000)) root
  "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1
  root=$(cd "$ASK_ROOT" && pwd -P)
  sleep 300 & local stranger=$!
  echo "$stranger 4977" > "$ASK_ROOT/.ask-app.pid"
  local out; out=$("$ASK_SH" serve "$ASK_ROOT" 2>&1)
  assert_contains "http://127.0.0.1:$port/" "$out" "serve adopts the running server on its own port"
  assert_eq "1" "$(pgrep -f "ask-app/src/server.ts --root $root --port " | wc -l | tr -d ' ')" "and starts no second server"
  echo "$stranger 4977" > "$ASK_ROOT/.ask-app.pid"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
  assert_eq "0" "$(pgrep -f "ask-app/src/server.ts --root $root --port " | wc -l | tr -d ' ')" "--stop finds it by root even with a wrong pidfile"
  if kill -0 "$stranger" 2>/dev/null; then pass "--stop still never kills the stranger"; else fail "--stop still never kills the stranger" alive killed; fi
  kill "$stranger" 2>/dev/null || true
}

# ── v2 fix round 1 ──────────────────────────────────────────────────────────────

# M3: --by is checked against FLEET_PANE on answer, draft, forward, send and discard.
test_r1_identity_is_checked_against_fleet_pane() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id m1 >/dev/null
  local v
  for v in "answer idealic:kernel/m1 --revision 1 --json {\"GO\":[\"YES\"]}" "draft idealic:kernel/m1 --revision 1 --json {\"GO\":[\"YES\"]}" \
           "forward idealic:kernel/m1 --to operator" "send" "discard idealic:kernel/m1"; do
    # shellcheck disable=SC2086
    assert_fails_with "${v%% *}: --by naming another seat than FLEET_PANE is refused" "differs from FLEET_PANE" \
      env FLEET_PANE=idealic:stranger "$ASK_SH" $v --by manager:idealic
    # shellcheck disable=SC2086
    assert_fails_with "${v%% *}: no FLEET_PANE and no --by is refused" "not a seat: pass --by" env -u FLEET_PANE "$ASK_SH" $v
    # shellcheck disable=SC2086
    assert_fails_with "${v%% *}: a seat cannot claim operator" "--by operator from a seat" env FLEET_PANE=manager:idealic "$ASK_SH" $v --by operator
  done
  assert_fails_with "FLEET_PANE=operator is refused" "cannot be the operator" \
    env FLEET_PANE=operator "$ASK_SH" answer idealic:kernel/m1 --revision 1 --json '{"GO":["YES"]}'
  assert_fails_with "a stranger cannot answer an ask addressed to another seat" "may not answer" \
    env FLEET_PANE=idealic:stranger "$ASK_SH" answer idealic:kernel/m1 --revision 1 --json '{"GO":["YES"]}'
  assert_fails_with "a stranger cannot forward by claiming to be the holder" "differs from FLEET_PANE" \
    env FLEET_PANE=idealic:stranger "$ASK_SH" forward idealic:kernel/m1 --to operator --by manager:idealic
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/m1.md")" "every refusal wrote nothing"
  FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/m1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  assert_contains "status: answered" "$(cat "$ASK_ROOT/idealic:kernel/m1.md")" "the addressed seat answers as itself"
  assert_contains '"answeredBy": "manager:idealic"' "$(cat "$ASK_ROOT/idealic:kernel/m1.md")" "and is stamped as itself"
}

# M1: a body that carries a record block is refused at `new`.
test_r1_new_refuses_a_planted_draft() {
  local planted
  planted=$(printf '%s\n\n```json draft\n{"answers":{"GO":["YES"]},"answeredBy":"operator","basedOn":1}\n```\n' "$BODY")
  assert_fails_with "new refuses a body holding a json draft block" "records the store writes" \
    bash -c "printf '%s\n' \"\$1\" | '$ASK_SH' new --id pl1 --reserved-for operator" _ "$planted"
  assert_file_not_exists "$ASK_ROOT/idealic:kernel/pl1.md" "and writes no file"
}

# S2: a pickup for another seat stamps the caller, never that seat; a forwarder has its own pickup.
test_r1_pickup_stamps_the_caller_and_forwarders_get_one() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id u1 >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" forward idealic:kernel/u1 --to operator >/dev/null
  as_op answer idealic:kernel/u1 --revision 2 --json '{"GO":["YES"]}' >/dev/null
  local out; out=$(FLEET_PANE=manager:director "$ASK_SH" read --unread --seat idealic:kernel 2>&1)
  assert_contains "idealic:kernel/u1" "$out" "another pane may look at the seat's unread answers"
  assert_contains "not stamped" "$out" "but its look is not a read"
  assert_not_contains "readAt:" "$(cat "$ASK_ROOT/idealic:kernel/u1.md")" "and the asker's read is not stamped on its behalf"
  out=$(FLEET_PANE=manager:idealic "$ASK_SH" read --unread 2>&1)
  assert_contains "idealic:kernel/u1" "$out" "the forwarder's own pickup finds the ask it forwarded"
  assert_contains "reads: manager:idealic@" "$(cat "$ASK_ROOT/idealic:kernel/u1.md")" "and stamps the forwarder's own read"
  assert_contains "idealic:kernel/u1" "$(FLEET_PANE=idealic:kernel "$ASK_SH" read --unread)" "M2: the forwarder's read does not hide it from the asker"
  assert_contains "readBy: idealic:kernel" "$(cat "$ASK_ROOT/idealic:kernel/u1.md")" "whose own read is now stamped"
  assert_fails_with "M2: acted by a non-recipient is refused" "not a recipient" \
    env FLEET_PANE=idealic:stranger "$ASK_SH" acted idealic:kernel/u1 "used it"
}

# Silent holder: the holder's parent (FLEET_MANAGES lists the holder) may forward; the asker may not.
test_r1_parent_of_a_silent_holder_may_forward() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id h1 >/dev/null
  assert_fails_with "a seat that does not manage the holder is refused" "neither" \
    env FLEET_PANE=manager:director FLEET_MANAGES="manager:other" "$ASK_SH" forward idealic:kernel/h1 --to operator
  assert_fails_with "the asker may re-ping but not forward" "re-pings the holder" \
    env FLEET_PANE=idealic:kernel FLEET_MANAGES="manager:idealic" "$ASK_SH" forward idealic:kernel/h1 --to operator
  FLEET_PANE=manager:director FLEET_MANAGES="manager:x,manager:idealic" "$ASK_SH" forward idealic:kernel/h1 --to operator >/dev/null
  assert_contains "to: operator" "$(cat "$ASK_ROOT/idealic:kernel/h1.md")" "the holder's parent moved it"
  assert_contains "forwards: manager:idealic→manager:director@" "$(cat "$ASK_ROOT/idealic:kernel/h1.md")" "through itself, so it hears the answer"
}

# S3: an answer left `pending` by a writer that died is pushed again on the next read.
test_r1_read_repushes_a_pending_left_by_a_dead_writer() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id c1 >/dev/null
  as_op answer idealic:kernel/c1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  local f="$ASK_ROOT/idealic:kernel/c1.md"
  python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = re.sub(r"^delivery: .*$", "delivery: pending", t, flags=re.M)
t = re.sub(r"^status: answered$", "status: answered\ndeliveryWriter: 999999@2026-10-29T00:00:00Z", t, flags=re.M)
open(p, "w").write(t)
PY
  assert_contains "delivery: pending" "$(cat "$f")" "the crash left the answer pending"
  local out; out=$(FLEET_PANE=idealic:kernel "$ASK_SH" read idealic:kernel/c1 2>&1)
  assert_contains "repushed idealic:kernel/c1" "$out" "the next read pushes it again"
  assert_contains "delivery: undelivered" "$(cat "$f")" "and stamps the push's real outcome (no live seat here)"
  assert_not_contains "deliveryWriter:" "$(cat "$f")" "the writer stamp is cleared"
}

# S7: the Linear key file is the working project's .env.local, found as env-lib.sh finds it.
test_r1_linear_key_comes_from_the_working_project() {
  local proj="$TMP/proj" port=$((20000 + RANDOM % 20000)) h
  mkdir -p "$proj/.git" "$proj/sessions/s1"
  printf 'LINEAR_API_KEY=lin_api_PROJECTKEY\n' > "$proj/.env.local"
  ( cd "$proj/sessions/s1" && unset ASK_LINEAR_ENV && _ENV_ANCHOR_RESOLVING=1 "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1 )
  h=$(curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health")
  assert_contains '"tickets":true' "$h" "the project's .env.local key turns tooltips on"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
  # A later start from outside any project reuses the file the last start remembered (<root>/.ask-app.env),
  # so a restart from another directory keeps its tooltips.
  assert_contains "ASK_LINEAR_ENV=$proj/.env.local" "$(cat "$ASK_ROOT/.ask-app.env")" "serve remembers the key file it used"
  ( cd "$TMP" && unset ASK_LINEAR_ENV && _ENV_ANCHOR_RESOLVING=1 "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1 )
  h=$(curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health")
  assert_contains '"tickets":true' "$h" "a restart outside any project reuses the remembered key file"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
  # With nothing remembered, outside any project there is no key, and no fixed fallback path.
  rm -f "$ASK_ROOT/.ask-app.env"
  ( cd "$TMP" && unset ASK_LINEAR_ENV && _ENV_ANCHOR_RESOLVING=1 "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1 )
  h=$(curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health")
  assert_contains '"tickets":false' "$h" "with nothing remembered, outside any project there is no key"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
  # A remembered path that no longer exists is not reused.
  printf 'ASK_LINEAR_ENV=%s\n' "$TMP/gone/.env.local" > "$ASK_ROOT/.ask-app.env"
  ( cd "$TMP" && unset ASK_LINEAR_ENV && _ENV_ANCHOR_RESOLVING=1 "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1 )
  h=$(curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health")
  assert_contains '"tickets":false' "$h" "a remembered key file that is gone is not used"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
}

# N1: an exported LINEAR_API_KEY never reaches the server's environment block.
test_r1_exported_linear_key_is_not_in_the_server_env() {
  local port=$((20000 + RANDOM % 20000)) pid
  LINEAR_API_KEY=lin_api_EXPORTEDFAKE "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1
  pid=$(cut -d' ' -f1 < "$ASK_ROOT/.ask-app.pid")
  assert_not_contains "EXPORTEDFAKE" "$(ps eww -o command= -p "$pid")" "ps eww shows no exported key"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
}

# S9 (round 2): the client is rebuilt when its BUILD ID differs from the sources' — not by mtime —
# into a temp dir moved into place under a lock; and the server refuses a client of another build.
test_r2_serve_rebuilds_by_build_id_and_the_server_refuses_a_mismatch() {
  local port=$((20000 + RANDOM % 20000)) d="$TMP/dist" want out
  want=$(node --no-warnings "$ENGINE_DIR/tools/ask-app/src/build-id.ts")
  cp -R "$ASK_TEST_DIST_DIR/dist" "$d"
  assert_eq "$want" "$(cat "$d/.build-id")" "the throwaway build is stamped with the sources' build id"
  touch -t 200001010000 "$d/index.html"
  out=$(ASK_APP_DIST="$d" "$ASK_SH" serve "$ASK_ROOT" --port "$port" 2>&1)
  assert_not_contains "building" "$out" "an OLD mtime with the right build id is not rebuilt (mtime is not the signal)"
  assert_contains '<div id="root">' "$(curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/")" "and it is served"
  # A build of another id under a live server (a v1 dist restored, or a stale copy): refused, loudly.
  echo "0000000000000000" > "$d/.build-id"
  out=$(curl -s -w ' %{http_code}' -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/")
  assert_contains "build mismatch" "$out" "the server refuses a client of another build"
  assert_contains " 503" "$out" "with a 503"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
  rm "$d/.build-id"
  out=$(ASK_APP_DIST="$d" "$ASK_SH" serve "$ASK_ROOT" --port "$port" 2>&1)
  assert_contains "building ask-app client $want" "$out" "an unstamped (v1) client is rebuilt on the next fresh serve"
  assert_eq "$want" "$(cat "$d/.build-id")" "the rebuilt client carries the sources' id"
  assert_eq "" "$(ls -d "$d".tmp-* "$d".old-* "$d".lock 2>/dev/null)" "no temp dir, old dir or lock is left behind"
  assert_eq "1" "$(ls -d "$d".v1-backup-* 2>/dev/null | wc -l | tr -d ' ')" "SHOULD-5: the unstamped client is kept aside as dist.v1-backup-<ts>, the rollback"
  assert_file_exists "$(ls -d "$d".v1-backup-* | head -1)/index.html" "and the backup holds the old client"
  assert_contains '<div id="root">' "$(curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/")" "and the new client is served"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
}

# N4: a root whose path holds regex characters still finds its own server.
test_r1_root_with_regex_characters_is_found() {
  local port=$((20000 + RANDOM % 20000)) r="$TMP/a+b(c)" out
  "$ASK_SH" serve "$r" --port "$port" >/dev/null 2>&1
  rm -f "$r/.ask-app.pid"
  out=$("$ASK_SH" serve "$r" 2>&1)
  assert_contains "adopted running ask-app" "$out" "a lost pidfile is adopted by root, + and ( notwithstanding"
  out=$("$ASK_SH" serve "$r" --stop 2>&1)
  assert_contains "stopped ask-app pid" "$out" "and --stop finds it"
  assert_fail "nothing serves on the port after --stop" curl -sf -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health"
}

# Relay: the operator answered in a seat's terminal; the seat records it, visibly, as a relay.
test_r1_relay_records_the_operator_answer_on_a_reserved_ask() {
  # Round 2: the relayer is a seat in the ask's chain (here the addressee), never the asker.
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:docs "$ASK_SH" new --id docchan --reserved-for operator >/dev/null
  local f="$ASK_ROOT/idealic:kernel/docchan.md" out
  assert_fails_with "--by operator without the relay flag is still refused" "--by operator from a seat" \
    env FLEET_PANE=manager:docs "$ASK_SH" answer idealic:kernel/docchan --revision 1 --json '{"GO":["YES"]}' --by operator
  assert_fails_with "a relay needs a note saying when and where" "--relayed-from needs --note" \
    env FLEET_PANE=manager:docs "$ASK_SH" answer idealic:kernel/docchan --revision 1 --json '{"GO":["YES"]}' --relayed-from operator
  assert_fails_with "a bare terminal does not relay" "is recorded by a seat" \
    env -u FLEET_PANE "$ASK_SH" answer idealic:kernel/docchan --revision 1 --json '{"GO":["YES"]}' --relayed-from operator --note x --by operator
  assert_fails_with "the asker never relays to its own ask" "never relays" \
    env FLEET_PANE=idealic:kernel "$ASK_SH" answer idealic:kernel/docchan --revision 1 --json '{"GO":["YES"]}' --relayed-from operator --note x
  assert_fails_with "a bystander cannot relay" "may not relay" \
    env FLEET_PANE=idealic:stranger "$ASK_SH" answer idealic:kernel/docchan --revision 1 --json '{"GO":["YES"]}' --relayed-from operator --note x
  assert_contains "status: open" "$(cat "$f")" "the refused relays wrote nothing"
  out=$(FLEET_PANE=manager:docs "$ASK_SH" answer idealic:kernel/docchan --revision 1 --json '{"GO":["YES"]}' --relayed-from operator --note "operator in my chat, 02:20")
  assert_contains "undelivered" "$out" "the push goes to the asker (no live seat in the test), not back to the relayer"
  assert_contains "status: answered" "$(cat "$f")" "the addressee's relay on a reserved ask passes"
  assert_contains '"answeredBy": "operator"' "$(cat "$f")" "stamped as the operator's answer"
  assert_contains '"answeredVia": "relay:manager:docs"' "$(cat "$f")" "with the relaying seat named"
  assert_contains "by operator, relayed by manager:docs" "$(FLEET_PANE=idealic:kernel "$ASK_SH" read idealic:kernel/docchan)" "read shows the relayer"
  FLEET_PANE=idealic:kernel "$ASK_SH" acted idealic:kernel/docchan "applied" >/dev/null
  assert_contains "acted: applied" "$(cat "$f")" "once relayed, acted works"
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id mgr >/dev/null
  assert_fails_with "a seat that is neither in the chain nor the asker's manager cannot relay" "may not relay" \
    env FLEET_PANE=manager:director "$ASK_SH" answer idealic:kernel/mgr --revision 1 --json '{"GO":["YES"]}' --relayed-from operator --note x
  FLEET_PANE=manager:director FLEET_MANAGES="manager:x,idealic:kernel" "$ASK_SH" answer idealic:kernel/mgr --revision 1 --json '{"GO":["YES"]}' --relayed-from operator --note "chat" >/dev/null 2>&1
  assert_contains '"answeredVia": "relay:manager:director"' "$(cat "$ASK_ROOT/idealic:kernel/mgr.md")" "a manager of the asker (FLEET_MANAGES) may relay"
}

# Round 2: an ask is filed by the live seat, to somebody else.
test_r2_new_is_filed_by_the_live_seat_to_somebody_else() {
  assert_fails_with "--from another seat is refused from a pane" "differs from this seat" \
    bash -c "printf '%s\n' \"\$1\" | '$ASK_SH' new --id f1 --from manager:app" _ "$BODY"
  assert_fails_with "--from operator is refused from a pane" "differs from this seat" \
    bash -c "printf '%s\n' \"\$1\" | '$ASK_SH' new --id f2 --from operator" _ "$BODY"
  assert_fails_with "--from operator is refused at a bare terminal too" "the operator is not one" \
    bash -c "printf '%s\n' \"\$1\" | env -u FLEET_PANE '$ASK_SH' new --id f3 --from operator" _ "$BODY"
  assert_fails_with "an asker cannot address an ask to itself" "cannot address an ask to itself" \
    bash -c "printf '%s\n' \"\$1\" | '$ASK_SH' new --id f4 --to idealic:kernel" _ "$BODY"
  printf '%s\n' "$BODY" | "$ASK_SH" new --id f5 --from idealic:kernel >/dev/null
  assert_file_exists "$ASK_ROOT/idealic:kernel/f5.md" "--from that repeats the live seat is fine"
}

# Round 2: a reserved ask ruled in chat is closed only as a relay of the operator, with a note.
test_r2_ruled_in_chat_on_a_reserved_ask_needs_a_relay() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:domain "$ASK_SH" new --id rr1 --reserved-for operator >/dev/null
  local f="$ASK_ROOT/idealic:kernel/rr1.md"
  assert_fails_with "the asker alone cannot close a reserved ask as ruled" "--relayed-from operator" \
    "$ASK_SH" acted idealic:kernel/rr1 "did it" --ruled-in-chat "operator, 03:00"
  assert_fails_with "nor by relaying it itself" "never relays" \
    "$ASK_SH" acted idealic:kernel/rr1 "did it" --ruled-in-chat "operator, 03:00" --relayed-from operator --note "chat"
  assert_fails_with "the holder's relay needs a note" "--note" \
    env FLEET_PANE=manager:domain "$ASK_SH" acted idealic:kernel/rr1 "did it" --ruled-in-chat "operator, 03:00" --relayed-from operator
  assert_contains "status: open" "$(cat "$f")" "still open"
  FLEET_PANE=manager:domain "$ASK_SH" acted idealic:kernel/rr1 "did it" --ruled-in-chat "operator, 03:00" --relayed-from operator --note "in my chat" >/dev/null
  assert_contains "status: ruled" "$(cat "$f")" "the holder relaying the operator's ruling closes it"
  assert_contains "relayed by manager:domain: in my chat" "$(cat "$f")" "and the record says who relayed it and where"
}

test_r1_revise_by_the_asker_only() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id rv1 >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/rv1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  assert_fails_with "a forwarder or holder cannot revise" "only the asker" \
    env FLEET_PANE=manager:idealic "$ASK_SH" revise idealic:kernel/rv1 --stake "x" --keep-body
  assert_fails_with "the operator cannot revise" "only the asker" \
    env -u FLEET_PANE "$ASK_SH" revise idealic:kernel/rv1 --stake "x" --keep-body --by operator
  local out; out=$(printf '%s\n' "${BODY/Ship it?/Ship it tonight?}" | "$ASK_SH" revise idealic:kernel/rv1 --stake "two lanes stall")
  assert_contains "revision 2" "$out" "a revise bumps the revision"
  assert_contains "notice manager:idealic" "$out" "and notices the holder, not the asker"
  assert_contains "revisions: 2@" "$(cat "$ASK_ROOT/idealic:kernel/rv1.md")" "and records what changed"
  assert_contains "Ship it tonight?" "$(cat "$ASK_ROOT/idealic:kernel/rv1.md")" "with the new body"
  out=$(FLEET_PANE=manager:idealic "$ASK_SH" send idealic:kernel/rv1 2>&1)
  assert_contains "stale" "$out" "a draft from before the revise is refused as stale"
}

test_r1_new_refuses_long_option_codes() {
  assert_fails_with "new names a code longer than the grammar reads (12 at most)" "[OVERLONGCODE1]" \
    bash -c "printf '## ¶ASK_W: Choose one: Where?\n- [ ] [OVERLONGCODE1] In a worktree\n- [ ] [NO] No\n' | '$ASK_SH' new --id wt1"
  assert_file_not_exists "$ASK_ROOT/idealic:kernel/wt1.md" "and files nothing"
}

test_r1_acted_on_an_ask_ruled_in_chat() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:domain "$ASK_SH" new --id op1 >/dev/null
  assert_fails_with "acted on an unanswered ask is refused, pointing at the honest ways" "--ruled-in-chat" \
    "$ASK_SH" acted idealic:kernel/op1 "did it"
  "$ASK_SH" acted idealic:kernel/op1 "did it" --ruled-in-chat "operator in manager:domain chat, 02:30" >/dev/null
  assert_contains "status: ruled" "$(cat "$ASK_ROOT/idealic:kernel/op1.md")" "--ruled-in-chat closes it as ruled"
  assert_contains "ruledInChat: operator in manager:domain chat, 02:30" "$(cat "$ASK_ROOT/idealic:kernel/op1.md")" "saying who and when"
  assert_not_contains '```json answer' "$(cat "$ASK_ROOT/idealic:kernel/op1.md")" "and invents no answer"
}

test_r1_new_points_to_the_author_guide_when_it_warns() {
  local out
  out=$(printf '## Choose one: Ship?\n- [ ] [YES] Yes\n- [ ] No idea\n' | "$ASK_SH" new --id g1 2>&1 >/dev/null)
  assert_contains "warning: \"Ship?\": 1 option(s) have no [CODE]" "$out" "new warns about a codeless option"
  assert_contains "skills/ask/assets/ASK_AUTHOR_GUIDE.md" "$out" "and points to the author guide"
  assert_file_exists "$ENGINE_DIR/skills/ask/assets/ASK_AUTHOR_GUIDE.md" "the guide it points to exists"
  out=$(printf '%s\n' "$BODY" | "$ASK_SH" new --id g2 2>&1 >/dev/null)
  assert_eq "" "$out" "a well-formed ask prints no warning and no pointer"
  out=$(printf '## Choose one: X?\n- [ ] [OVERLONGCODE1] x\n' | "$ASK_SH" new --id g3 2>&1)
  assert_contains "ASK_AUTHOR_GUIDE.md" "$out" "a refusal points to the guide too"
}

# Stale identity: run.sh caches FLEET_PANE/FLEET_PARENT at launch; the live pane label and parent win.
test_r1_live_pane_label_beats_a_stale_fleet_pane() {
  local live="$TMP/live-panes" out
  printf 'domain:stats %%7 manager:domain\nmanager:domain %%3 -\n' > "$live"
  out=$(printf '%s\n' "$BODY" | TMUX_PANE=%7 ASK_LIVE_PANES="$live" FLEET_PANE=domain:domain FLEET_PARENT=manager:director "$ASK_SH" new --id lv1 2>"$TMP/lv.err")
  assert_eq "$ASK_ROOT/domain:stats/lv1.md" "$out" "the live label is the asker, not the stale FLEET_PANE"
  assert_contains "to: manager:domain" "$(cat "$out")" "the live @pane_parent is the default recipient"
  assert_contains "FLEET_PANE 'domain:domain' is stale; using the live pane label 'domain:stats'" "$(cat "$TMP/lv.err")" "the stale cache is warned about"
  assert_contains "FLEET_PARENT 'manager:director' is stale" "$(cat "$TMP/lv.err")" "and the stale parent too"
  TMUX_PANE=%3 ASK_LIVE_PANES="$live" FLEET_PANE=manager:director "$ASK_SH" answer domain:stats/lv1 --revision 1 --json '{"GO":["YES"]}' >/dev/null 2>&1
  assert_contains '"answeredBy": "manager:domain"' "$(cat "$out")" "the live label acts (answers) even under a stale FLEET_PANE"
  TMUX_PANE=%7 ASK_LIVE_PANES="$live" FLEET_PANE=domain:domain "$ASK_SH" acted domain:stats/lv1 "used it" >/dev/null 2>&1
  assert_contains "actedBy: domain:stats" "$(cat "$out")" "acted works as the live seat (no 'domain:domain is not a recipient')"
  printf '%s\n' "$BODY" | TMUX_PANE=%9 ASK_LIVE_PANES="$live" FLEET_PANE=idealic:kernel "$ASK_SH" new --id lv2 >/dev/null 2>&1
  assert_file_exists "$ASK_ROOT/idealic:kernel/lv2.md" "an unreadable live pane falls back to the cache"
}

# K3 (round 3): the temp build's id is checked BEFORE it is moved in — a build that comes out as
# another id (here a stand-in vite) never replaces the client, and nothing is left behind.
test_r3_a_build_of_the_wrong_id_is_never_moved_in() {
  local port=$((20000 + RANDOM % 20000)) d="$TMP/dist" fake="$TMP/fake-vite" out before
  cp -R "$ASK_TEST_DIST_DIR/dist" "$d"
  echo "0000000000000000" > "$d/.build-id"
  before=$(cat "$d/index.html")
  cat > "$fake" <<'SH'
#!/bin/bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "--outDir" ] && out="$2"; shift; done
mkdir -p "$out"; echo "<html>wrong build</html>" > "$out/index.html"; echo "ffffffffffffffff" > "$out/.build-id"
SH
  chmod +x "$fake"
  out=$(ASK_VITE_BUILD="$fake" ASK_APP_DIST="$d" "$ASK_SH" serve "$ASK_ROOT" --port "$port" 2>&1); local rc=$?
  assert_eq "1" "$rc" "serve fails when the build is not the sources' build"
  assert_contains "is not build" "$out" "and says so"
  assert_eq "$before" "$(cat "$d/index.html")" "the client in place is unchanged"
  assert_eq "0000000000000000" "$(cat "$d/.build-id")" "and keeps its id"
  assert_eq "" "$(ls -d "$d".tmp-* "$d".lock "$d".v1-backup-* 2>/dev/null)" "no temp dir, lock or backup is left"
  assert_fail "no server was started" curl -sf -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health"
}

# ── supersede ────────────────────────────────────────────

test_r4_supersede_by_the_asker_links_both_asks() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sp1 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sp2 >/dev/null
  local out; out=$("$ASK_SH" supersede idealic:kernel/sp1 --by idealic:kernel/sp2)
  assert_contains "superseded	idealic:kernel/sp1 → idealic:kernel/sp2" "$out" "supersede reports the link"
  assert_contains "notice manager:idealic" "$out" "and notices the old ask's holder"
  local old; old=$(cat "$ASK_ROOT/idealic:kernel/sp1.md")
  assert_contains "status: superseded" "$old" "the old ask is superseded"
  assert_contains "superseded-by: idealic:kernel/sp2" "$old" "and points at its replacement"
  assert_contains "superseded-at: " "$old" "with a time"
  assert_contains "superseded-actor: idealic:kernel" "$old" "and who did it"
  assert_contains "revision: 2" "$old" "its revision moves"
  assert_contains "supersedes: idealic:kernel/sp1" "$(cat "$ASK_ROOT/idealic:kernel/sp2.md")" "the new ask points back"
  assert_contains "revision: 1" "$(cat "$ASK_ROOT/idealic:kernel/sp2.md")" "and its revision does not move"
}

test_r4_supersede_refusals() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sr1 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sr2 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sr3 >/dev/null
  assert_fails_with "a missing old ask is refused" "no ask idealic:kernel/nope" "$ASK_SH" supersede idealic:kernel/nope --by idealic:kernel/sr2
  assert_fails_with "a missing new ask is refused" "no ask idealic:kernel/nope" "$ASK_SH" supersede idealic:kernel/sr1 --by idealic:kernel/nope
  assert_fails_with "an ask cannot supersede itself" "cannot supersede itself" "$ASK_SH" supersede idealic:kernel/sr1 --by idealic:kernel/sr1
  assert_fails_with "the holder, not being the asker or its manager, is refused" "only the asker" \
    env FLEET_PANE=manager:idealic "$ASK_SH" supersede idealic:kernel/sr1 --by idealic:kernel/sr2
  assert_fails_with "a replacement is required" "exactly one replacement" "$ASK_SH" supersede idealic:kernel/sr1
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/sr1.md")" "after the refusals sr1 is still open"
  "$ASK_SH" supersede idealic:kernel/sr2 --by idealic:kernel/sr3 >/dev/null
  assert_fails_with "an already-superseded old ask is refused, naming its replacement" "already superseded by idealic:kernel/sr3" \
    "$ASK_SH" supersede idealic:kernel/sr2 --by idealic:kernel/sr1
  assert_fails_with "a superseded replacement is refused" "idealic:kernel/sr2 is itself superseded" \
    "$ASK_SH" supersede idealic:kernel/sr1 --by idealic:kernel/sr2
  as_op answer idealic:kernel/sr1 --revision 1 --json '{"GO":["NO"]}' >/dev/null
  assert_fails_with "an answered old ask is history" "answered asks are history" \
    "$ASK_SH" supersede idealic:kernel/sr1 --by idealic:kernel/sr3
}

test_r4_supersede_by_operator_and_manager() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id so1 --reserved-for operator >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id so2 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id so3 >/dev/null
  as_op supersede idealic:kernel/so1 --by idealic:kernel/so2 >/dev/null
  assert_contains "superseded-actor: operator" "$(cat "$ASK_ROOT/idealic:kernel/so1.md")" "the operator (--by operator) supersedes a reserved ask"
  FLEET_PANE=manager:idealic FLEET_MANAGES=kernel "$ASK_SH" supersede idealic:kernel/so3 --by idealic:kernel/so2 >/dev/null
  assert_contains "superseded-actor: manager:idealic" "$(cat "$ASK_ROOT/idealic:kernel/so3.md")" "the asker's manager (FLEET_MANAGES) supersedes"
  assert_fails_with "a seat may not claim operator" "--by operator from a seat" \
    env FLEET_PANE=app:writer "$ASK_SH" supersede idealic:kernel/so2 --by idealic:kernel/so3 --by operator
}

test_r4_superseded_ask_takes_no_answer_draft_or_send_and_leaves_the_open_list() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sa1 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id sa2 >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/sa1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  "$ASK_SH" supersede idealic:kernel/sa1 --by idealic:kernel/sa2 >/dev/null
  assert_fails_with "answer on a superseded ask is refused, naming the new ask" "superseded by idealic:kernel/sa2; answer that one instead" \
    as_op answer idealic:kernel/sa1 --revision 2 --json '{"GO":["YES"]}'
  assert_fails_with "even at the revision read before the supersede" "superseded by idealic:kernel/sa2" \
    as_op answer idealic:kernel/sa1 --revision 1 --json '{"GO":["YES"]}'
  assert_fails_with "draft is refused" "superseded by idealic:kernel/sa2" \
    env FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/sa1 --revision 2 --json '{"GO":["YES"]}'
  local out; out=$(FLEET_PANE=manager:idealic "$ASK_SH" send idealic:kernel/sa1 2>&1); local rc=$?
  assert_eq "1" "$rc" "send of the superseded ask exits 1"
  assert_contains "refused idealic:kernel/sa1	ask sa1 is superseded by idealic:kernel/sa2" "$out" "send refuses it, naming the new ask"
  assert_contains "status: superseded" "$(cat "$ASK_ROOT/idealic:kernel/sa1.md")" "nothing settled it"
  local list; list=$("$ASK_SH" list)
  assert_not_contains "idealic:kernel/sa1" "$list" "the default (open) list hides the superseded ask"
  assert_contains "idealic:kernel/sa2" "$list" "and shows its replacement"
  assert_contains "superseded	idealic:kernel/sa1" "$("$ASK_SH" list --status superseded)" "--status superseded still reaches it"
}

# ── a reserved ask declined by a seat is passed up (the operator's ruling, 2026-10-30) ──

test_r4_reserved_decline_by_a_seat_passes_up_and_stays_open() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id pu1 --reserved-for operator >/dev/null
  local f="$ASK_ROOT/idealic:kernel/pu1.md" out
  out=$(FLEET_PANE=manager:idealic FLEET_PARENT=manager:director "$ASK_SH" answer idealic:kernel/pu1 --revision 1 --decline "needs the budget owner")
  assert_contains "passed up, not declined	idealic:kernel/pu1 → manager:director" "$out" "the CLI says it was passed up, and to whom"
  assert_contains "notice manager:director" "$out" "and that the next holder was told"
  assert_contains "status: open" "$(cat "$f")" "the reserved ask stays open"
  assert_contains "to: manager:director" "$(cat "$f")" "it moved to the decliner's parent"
  assert_contains "manager:idealic→manager:director@" "$(cat "$f")" "the hop is in forwards:"
  assert_contains "[declined: needs the budget owner]" "$(cat "$f")" "with the reason"
  assert_not_contains '```json answer' "$(cat "$f")" "and no decline was recorded as an answer"
  out=$(FLEET_PANE=manager:director "$ASK_SH" answer idealic:kernel/pu1 --revision 2 --decline "the operator's call")
  assert_contains "passed up, not declined	idealic:kernel/pu1 → operator" "$out" "a decliner with no parent passes it to the operator"
  assert_contains "to: operator" "$(cat "$f")" "so it now sits with the operator"
  as_op answer idealic:kernel/pu1 --revision 3 --decline "not doing this" >/dev/null
  assert_contains "status: declined" "$(cat "$f")" "the operator's own decline closes it"
}

test_r4_unreserved_decline_by_a_seat_is_unchanged() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id pu2 >/dev/null
  local out; out=$(FLEET_PANE=manager:idealic FLEET_PARENT=manager:director "$ASK_SH" answer idealic:kernel/pu2 --revision 1 --decline "no")
  assert_not_contains "passed up" "$out" "an unreserved decline is not passed up"
  assert_contains "status: declined" "$(cat "$ASK_ROOT/idealic:kernel/pu2.md")" "it closes as declined"
  assert_contains "to: manager:idealic" "$(cat "$ASK_ROOT/idealic:kernel/pu2.md")" "and does not move"
}

run_discovered_tests
