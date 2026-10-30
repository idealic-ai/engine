#!/bin/bash
# test-ask-sh.sh — CLI coverage for scripts/ask.sh (`engine ask new|list|answer|serve|path`).
#
# Every test runs against a throwaway ASK_ROOT and an empty ASK_SESSIONS_DIR, so no real seat is
# ever messaged and the fleet's real asks directory is never touched.
set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"
source "$(dirname "$0")/lib-search-first-nudge.sh"

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

# free_port: a TCP port the OS reports unused right now. Never a fixed number: 4977 is the live ask
# server's default port, and other lanes run this suite at the same time.
free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# start_stranger: a process that is not ask-app, listening on its own OS-picked port and answering
# every GET with a non-ask body. Sets STRANGER_PID and STRANGER_PORT. A test whose meaning is "the
# pidfile names someone else's port" uses this, so that port is taken by the test, not by whatever
# else happens to run on the machine.
start_stranger() {
  local f="$TMP/stranger.port" i
  rm -f "$f"
  python3 -c '
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b = b"{\"app\":\"stranger\"}"
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_address[1]))
srv.serve_forever()
' "$f" >/dev/null 2>&1 &
  STRANGER_PID=$!
  for i in $(seq 1 50); do [ -s "$f" ] && break; sleep 0.1; done
  STRANGER_PORT=$(cat "$f")
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

# assert_has_fixed <needle> <file> <desc>: a fixed-string check. assert_contains falls back to a
# basic regex, where a needle like `[declined: x]` is a bracket expression that matches almost anything.
assert_has_fixed() {
  if grep -qF -- "$1" "$2"; then pass "$3"; else fail "$3" "fixed string '$1'" "$(cat "$2")"; fi
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
  mkdir -p "$ASK_ROOT"; echo "$victim $(free_port)" > "$ASK_ROOT/.ask-app.pid"
  local out; out=$("$ASK_SH" serve "$ASK_ROOT" --stop 2>&1)
  if kill -0 "$victim" 2>/dev/null; then pass "--stop leaves a recycled pid alone"; else fail "--stop leaves a recycled pid alone" "victim alive" "victim killed"; fi
  assert_contains "stale" "$out" "--stop says the pidfile was stale"
  assert_file_not_exists "$ASK_ROOT/.ask-app.pid" "the stale pidfile is removed"
  kill "$victim" 2>/dev/null || true
}

test_serve_concurrent_starts_leave_one_server() {
  local port=$(free_port) i pids
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
  port=$(free_port)
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
  local port=$(free_port) root
  "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1
  root=$(cd "$ASK_ROOT" && pwd -P)
  # The pidfile names a stranger that owns the port it names: the test's own listener, never the
  # operator's server on 4977, so a missed discovery fails here the same way on every machine.
  start_stranger; local stranger=$STRANGER_PID
  echo "$stranger $STRANGER_PORT" > "$ASK_ROOT/.ask-app.pid"
  local out; out=$("$ASK_SH" serve "$ASK_ROOT" 2>&1)
  assert_contains "http://127.0.0.1:$port/" "$out" "serve adopts the running server on its own port"
  assert_eq "1" "$(pgrep -f "ask-app/src/server.ts --root $root --port " | wc -l | tr -d ' ')" "and starts no second server"
  echo "$stranger $STRANGER_PORT" > "$ASK_ROOT/.ask-app.pid"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
  assert_eq "0" "$(pgrep -f "ask-app/src/server.ts --root $root --port " | wc -l | tr -d ' ')" "--stop finds it by root even with a wrong pidfile"
  if kill -0 "$stranger" 2>/dev/null; then pass "--stop still never kills the stranger"; else fail "--stop still never kills the stranger" alive killed; fi
  kill "$stranger" 2>/dev/null || true
}

# Another root's server that exits between serve's pgrep and its ps must not end serve. Where other
# lanes run this suite at once, one does; under set -e that ended serve and --stop silently, so a
# running server was neither adopted nor stopped. The pgrep shim lists a pid that has already exited.
test_serve_survives_a_server_that_vanishes_mid_search() {
  local port=$(free_port) bin="$TMP/bin" dead out
  "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1
  sleep 0 & dead=$!; wait "$dead"
  mkdir -p "$bin"
  printf '#!/bin/bash\necho %s\nexec /usr/bin/pgrep "$@"\n' "$dead" > "$bin/pgrep"; chmod +x "$bin/pgrep"
  out=$(PATH="$bin:$PATH" "$ASK_SH" serve "$ASK_ROOT" 2>&1)
  assert_contains "http://127.0.0.1:$port/" "$out" "serve still finds its server when another vanishes mid-search"
  out=$(PATH="$bin:$PATH" "$ASK_SH" serve "$ASK_ROOT" --stop 2>&1)
  assert_contains "stopped ask-app pid" "$out" "and --stop still stops it"
}

# A live server whose health reply is slow once (a loaded machine, a server still starting) is
# still this root's server: --stop must stop it, not call its pidfile stale and kill nothing. The
# curl stand-in makes the first health call time out, as a 1 s limit does on a busy box.
test_serve_stop_survives_one_slow_health_reply() {
  local port=$(free_port) bin="$TMP/slowbin" out
  "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1
  mkdir -p "$bin"
  printf '#!/bin/bash\nif [ ! -e "%s/slow.once" ]; then : > "%s/slow.once"; exit 28; fi\nexec /usr/bin/curl "$@"\n' "$bin" "$bin" > "$bin/curl"
  chmod +x "$bin/curl"
  out=$(PATH="$bin:$PATH" "$ASK_SH" serve "$ASK_ROOT" --stop 2>&1)
  assert_contains "stopped ask-app pid" "$out" "--stop stops a server whose first health reply was slow"
  assert_not_contains "stale pidfile" "$out" "and does not call its pidfile stale"
  assert_fail "nothing serves on the port after --stop" curl -sf -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/api/health"
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
  local proj="$TMP/proj" port=$(free_port) h
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
  local port=$(free_port) pid
  LINEAR_API_KEY=lin_api_EXPORTEDFAKE "$ASK_SH" serve "$ASK_ROOT" --port "$port" >/dev/null 2>&1
  pid=$(cut -d' ' -f1 < "$ASK_ROOT/.ask-app.pid")
  assert_not_contains "EXPORTEDFAKE" "$(ps eww -o command= -p "$pid")" "ps eww shows no exported key"
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1
}

# S9 (round 2): the client is rebuilt when its BUILD ID differs from the sources' — not by mtime —
# into a temp dir moved into place under a lock; and the server refuses a client of another build.
test_r2_serve_rebuilds_by_build_id_and_the_server_refuses_a_mismatch() {
  local port=$(free_port) d="$TMP/dist" want out
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
  local port=$(free_port) r="$TMP/a+b(c)" out
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

# IDE-333 acceptance 3: before writing an ask, search sessions and docs, and cite the result as Evidence:.
test_r1_author_guide_says_search_before_you_ask() {
  local guide="$ENGINE_DIR/skills/ask/assets/ASK_AUTHOR_GUIDE.md" v body
  v=$(search_nudge_violations "$guide" 'Is this an ask at all?' "$ENGINE_DIR")
  assert_eq "" "$v" "the guide's 'Is this an ask at all?' names session-search and doc-search with working commands"
  body=$(awk 'index($0,"## Is this an ask at all?")==1 {f=1; next} f && /^## / {exit} f' "$guide")
  assert_contains '`Evidence:`' "$body" "and says to cite what the search found as an Evidence: line"
  # Plant: drop the doc-search command; the check must go red.
  cp "$guide" "$TMP/guide.md"
  FIND='engine doc-search query "' REPL='engine doc-search find "' perl -0pi -e 's/\Q$ENV{FIND}\E/$ENV{REPL}/' "$TMP/guide.md"
  v=$(search_nudge_violations "$TMP/guide.md" 'Is this an ask at all?' "$ENGINE_DIR")
  assert_contains "doc-search: no 'engine doc-search query" "$v" "plant: without the doc-search command the check is red"
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
  local port=$(free_port) d="$TMP/dist" fake="$TMP/fake-vite" out before
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

# ── withdraw (ASKWITHDRAW) ───────────────────────────────

test_askwithdraw_the_asker_withdraws_and_the_holder_is_told_no_action() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wd1 >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/wd1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  local out; out=$("$ASK_SH" withdraw idealic:kernel/wd1 --reason "the ticket closed")
  assert_contains "withdrawn	idealic:kernel/wd1	revision 2	the ticket closed" "$out" "withdraw reports the ask, its revision and the reason"
  assert_contains "draft discarded	saved by manager:idealic" "$out" "and the draft it discarded"
  assert_contains "notice manager:idealic" "$out" "and notices the holder"
  local f; f=$(cat "$ASK_ROOT/idealic:kernel/wd1.md")
  assert_contains "status: withdrawn" "$f" "the ask is withdrawn"
  assert_contains "withdrawn-actor: idealic:kernel" "$f" "with who"
  assert_contains "withdrawn-at: " "$f" "when"
  assert_contains "withdrawn-reason: the ticket closed" "$f" "and why"
  assert_contains "withdrawn-draft-of: manager:idealic" "$f" "the discarded draft is recorded"
  assert_not_contains '```json draft' "$f" "and the draft is gone"
  assert_not_contains "superseded" "$f" "it is not a supersede"
}

test_askwithdraw_who_may_withdraw() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wo1 --reserved-for operator >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wo2 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wo3 >/dev/null
  as_op withdraw idealic:kernel/wo1 --reason moot >/dev/null
  assert_contains "withdrawn-actor: operator" "$(cat "$ASK_ROOT/idealic:kernel/wo1.md")" "the operator (--by operator) withdraws a reserved ask"
  FLEET_PANE=manager:idealic FLEET_MANAGES=kernel "$ASK_SH" withdraw idealic:kernel/wo2 --reason moot >/dev/null
  assert_contains "withdrawn-actor: manager:idealic" "$(cat "$ASK_ROOT/idealic:kernel/wo2.md")" "the asker's manager (FLEET_MANAGES) withdraws"
  assert_fails_with "a peer is refused" "only the asker (idealic:kernel), its manager or the operator withdraws" \
    env FLEET_PANE=idealic:runner "$ASK_SH" withdraw idealic:kernel/wo3 --reason moot
  assert_fails_with "the holder that does not manage the asker is refused" "only the asker" \
    env -u FLEET_MANAGES FLEET_PANE=manager:idealic "$ASK_SH" withdraw idealic:kernel/wo3 --reason moot
  assert_fails_with "a seat may not claim operator" "--by operator from a seat" \
    env FLEET_PANE=app:writer "$ASK_SH" withdraw idealic:kernel/wo3 --reason moot --by operator
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/wo3.md")" "after the refusals wo3 is still open"
}

test_askwithdraw_refusals() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wr1 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wr2 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wr3 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wr4 >/dev/null
  assert_fails_with "a reason is required" "--reason is required" "$ASK_SH" withdraw idealic:kernel/wr1
  assert_fails_with "a blank reason is refused" "--reason is required" "$ASK_SH" withdraw idealic:kernel/wr1 --reason "  "
  assert_fails_with "a missing ask is refused" "no ask idealic:kernel/nope" "$ASK_SH" withdraw idealic:kernel/nope --reason moot
  as_op answer idealic:kernel/wr1 --revision 1 --json '{"GO":["NO"]}' >/dev/null
  assert_fails_with "an answered ask is history" "is answered: that one is history" "$ASK_SH" withdraw idealic:kernel/wr1 --reason moot
  as_op answer idealic:kernel/wr2 --revision 1 --decline "not mine" >/dev/null
  assert_fails_with "a declined ask is history" "is declined: that one is history" "$ASK_SH" withdraw idealic:kernel/wr2 --reason moot
  "$ASK_SH" supersede idealic:kernel/wr3 --by idealic:kernel/wr4 >/dev/null
  assert_fails_with "a superseded ask is refused, naming its replacement" "already superseded by idealic:kernel/wr4" "$ASK_SH" withdraw idealic:kernel/wr3 --reason moot
  "$ASK_SH" withdraw idealic:kernel/wr4 --reason first >/dev/null
  assert_fails_with "an already withdrawn ask is refused" "already withdrawn by idealic:kernel (first)" "$ASK_SH" withdraw idealic:kernel/wr4 --reason again
}

test_askwithdraw_withdrawn_ask_takes_no_answer_draft_or_send_and_leaves_the_open_list() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wa1 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wa2 >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/wa1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  "$ASK_SH" withdraw idealic:kernel/wa1 --reason "no longer needed" >/dev/null
  assert_fails_with "answer after withdraw is refused" "ask wa1 is withdrawn by idealic:kernel (no longer needed): there is nothing to answer" \
    as_op answer idealic:kernel/wa1 --revision 2 --json '{"GO":["YES"]}'
  assert_fails_with "even at the revision read before the withdrawal" "is withdrawn" \
    as_op answer idealic:kernel/wa1 --revision 1 --json '{"GO":["YES"]}'
  assert_fails_with "draft is refused" "is withdrawn" \
    env FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/wa1 --revision 2 --json '{"GO":["YES"]}'
  local out; out=$(FLEET_PANE=manager:idealic "$ASK_SH" send idealic:kernel/wa1 2>&1); local rc=$?
  assert_eq "1" "$rc" "send of the withdrawn ask exits 1"
  assert_contains "refused idealic:kernel/wa1	ask wa1 is withdrawn" "$out" "send refuses it"
  assert_contains "status: withdrawn" "$(cat "$ASK_ROOT/idealic:kernel/wa1.md")" "nothing settled it: the status survives a re-read"
  local list; list=$("$ASK_SH" list)
  assert_not_contains "idealic:kernel/wa1" "$list" "the default (open) list hides the withdrawn ask"
  assert_contains "idealic:kernel/wa2" "$list" "and still shows the open one"
  assert_not_contains "idealic:kernel/wa1" "$("$ASK_SH" list --status settled)" "settled does not hold it"
  assert_contains "withdrawn	idealic:kernel/wa1" "$("$ASK_SH" list --status withdrawn)" "--status withdrawn reaches it"
  assert_contains "withdrawn by idealic:kernel: no longer needed" "$("$ASK_SH" list --status all)" "list shows who and why"
  assert_contains "withdrawn by idealic:kernel at " "$("$ASK_SH" read idealic:kernel/wa1 2>/dev/null)" "read shows who and when"
  assert_contains ": no longer needed" "$("$ASK_SH" read idealic:kernel/wa1 2>/dev/null)" "and why"
}

test_askwithdraw_rename_seat_rewrites_its_seat_fields() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id wn1 >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/wn1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  "$ASK_SH" withdraw idealic:kernel/wn1 --reason moot >/dev/null
  as_op rename-seat manager:idealic manager:kit >/dev/null
  assert_contains "withdrawn-draft-of: manager:kit" "$(cat "$ASK_ROOT/idealic:kernel/wn1.md")" "rename-seat rewrites withdrawn-draft-of"
  as_op rename-seat idealic:kernel idealic:core >/dev/null
  assert_contains "withdrawn-actor: idealic:core" "$(cat "$ASK_ROOT/idealic:core/wn1.md")" "and withdrawn-actor"
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
  assert_has_fixed "[declined: needs the budget owner]" "$f" "with the reason"
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

# ── round 2 ──────────────────────────────────────────────

test_r5_pass_up_skips_the_asker_up_its_chain() {
  # The critique's failing input: manager:app asks app:writer; app:writer's parent is the asker.
  local live="$TMP/live-panes" f="$ASK_ROOT/manager:app/pa1.md" out
  printf 'app:writer %%7 manager:app\nmanager:app %%3 manager:director\nmanager:director %%1 -\n' > "$live"
  printf '%s\n' "$BODY" | FLEET_PANE=manager:app "$ASK_SH" new --id pa1 --to app:writer --reserved-for operator >/dev/null
  out=$(TMUX_PANE=%7 ASK_LIVE_PANES="$live" FLEET_PANE=app:writer "$ASK_SH" answer manager:app/pa1 --revision 1 --decline "not mine" 2>&1)
  assert_contains "passed up, not declined	manager:app/pa1 → manager:director" "$out" "the pass-up skips the asker to the asker's parent"
  assert_contains "status: open" "$(cat "$f")" "the ask stays open"
  assert_contains "to: manager:director" "$(cat "$f")" "held by the next rung"
  assert_contains "app:writer→manager:director@" "$(cat "$f")" "the hop names the move"
  assert_has_fixed "[declined: not mine]" "$f" "with the reason"
  printf '%s\n' "$BODY" | FLEET_PANE=manager:app "$ASK_SH" new --id pa2 --to app:writer --reserved-for operator >/dev/null
  out=$(FLEET_PANE=app:writer FLEET_PARENT=manager:app "$ASK_SH" answer manager:app/pa2 --revision 1 --decline "not mine" 2>&1)
  assert_contains "passed up, not declined	manager:app/pa2 → operator" "$out" "outside tmux the asker's parent is unreadable, so it ends at the operator"
}

test_r5_draft_decline_of_a_reserved_ask_points_at_answer() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id pd1 --reserved-for operator >/dev/null
  assert_fails_with "a seat's draft decline is refused, saying how to pass it up" "use \`engine ask answer --decline\` to pass it up" \
    env FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/pd1 --revision 1 --decline "no"
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/pd1.md")" "and the ask is untouched"
}

test_r5_supersede_refuses_ambiguous_positionals() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id px1 >/dev/null
  printf '%s\n' "$BODY" | "$ASK_SH" new --id px2 >/dev/null
  printf '%s\n' "$BODY" | "$ASK_SH" new --id px3 >/dev/null
  assert_fails_with "two positional refs are refused" "one old ask only" \
    "$ASK_SH" supersede idealic:kernel/px1 idealic:kernel/px3 --by idealic:kernel/px2
  assert_fails_with "--by before the old ask is refused, showing both readings" "engine ask supersede idealic:kernel/px2 --by idealic:kernel/px1" \
    "$ASK_SH" supersede --by idealic:kernel/px1 idealic:kernel/px2
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/px1.md")" "px1 is untouched"
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/px2.md")" "px2 is untouched"
}

test_r5_supersede_tells_the_asker_when_someone_else_does_it() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id pn1 >/dev/null
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id pn2 >/dev/null
  local out; out=$(as_op supersede idealic:kernel/pn1 --by idealic:kernel/pn2)
  assert_contains "notice idealic:kernel" "$out" "the operator's supersede notices the asker"
  assert_contains "notice manager:idealic" "$out" "and the holder"
}

test_rename_seat_route_moves_asks_and_refuses_a_bystander() {
  printf '%s\n' "$BODY" | FLEET_PARENT=manager:idealic "$ASK_SH" new --id rs1 >/dev/null
  assert_fails_with "a seat that does not manage idealic:kernel cannot rename it" "only the operator or idealic:kernel's manager" \
    env FLEET_PANE=idealic:ui "$ASK_SH" rename-seat idealic:kernel core:kernel
  local dry; dry=$("$ASK_SH" rename-seat idealic:kernel core:kernel --dry-run)
  assert_contains "would move 1 ask" "$dry" "a dry run says what it would move"
  [ -f "$ASK_ROOT/idealic:kernel/rs1.md" ] && pass "and moves nothing" || fail "the dry run moved rs1"
  local out; out=$(as_op rename-seat idealic:kernel core:kernel)
  assert_contains "moved 1 ask; changed 1 field in 1 file" "$out" "the operator's run moves the ask and rewrites its from:"
  assert_contains "from: core:kernel" "$(cat "$ASK_ROOT/core:kernel/rs1.md")" "the moved ask names its new seat"
  [ ! -e "$ASK_ROOT/idealic:kernel" ] && pass "the old folder is gone" || fail "idealic:kernel/ still exists"
  out=$(as_op rename-seat idealic:kernel core:kernel)
  assert_contains "moved 0 asks; changed 0 fields in 0 files" "$out" "a second pass changes nothing"
}

test_ide339_answer_grant_records_class_and_refusals() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id gr1 --to manager:idealic >/dev/null
  printf '%s\n' "$BODY" | "$ASK_SH" new --id gr2 --to manager:idealic >/dev/null
  printf '%s\n' "$BODY" | "$ASK_SH" new --id gr3 --to manager:idealic --reserved-for manager:idealic >/dev/null
  assert_fails_with "--grant takes only A-D" "--grant takes A, B, C or D" \
    env FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/gr1 --revision 1 --json '{"GO":["YES"]}' --grant E
  assert_fails_with "--grant is refused for the operator" "grant class" as_op answer idealic:kernel/gr2 --revision 1 --json '{"GO":["YES"]}' --grant A
  assert_fails_with "--grant is refused on a reserved-for ask" "reserved" \
    env FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/gr3 --revision 1 --json '{"GO":["YES"]}' --grant C
  assert_fails_with "--grant is refused on a draft" "--grant" \
    env FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/gr2 --revision 1 --json '{"GO":["YES"]}' --grant B
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/gr2.md")" "a refused grant writes nothing"
  # IDE-339 round 2 (MUST-1): only the asker's manager writes a grant class: its FLEET_MANAGES must list the asker.
  assert_fails_with "--grant is refused from an addressee that does not manage the asker" "is not a manager of idealic:kernel" \
    env -u FLEET_MANAGES FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/gr1 --revision 1 --json '{"GO":["YES"]}' --grant B
  assert_fails_with "--grant is refused when FLEET_MANAGES lists other seats" "is not a manager of idealic:kernel" \
    env FLEET_MANAGES=runner,ui FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/gr1 --revision 1 --json '{"GO":["YES"]}' --grant B
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/gr1.md")" "a non-manager's refused grant writes nothing"
  FLEET_MANAGES=kernel,runner FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/gr1 --revision 1 --json '{"GO":["YES"]}' --grant B >/dev/null
  assert_contains '"grantClass": "B"' "$(cat "$ASK_ROOT/idealic:kernel/gr1.md")" "a manager's --grant B is recorded in the answer"
  assert_contains "· grant B" "$(env -u FLEET_PANE "$ASK_SH" read idealic:kernel/gr1 2>/dev/null)" "read prints the grant class beside who answered"
}

test_ide339_operator_over_a_seat_answer_is_overruled_and_kept_in_history() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id ov1 --to manager:idealic >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/ov1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  as_op answer idealic:kernel/ov1 --revision 2 --json '{"GO":["NO"]}' >/dev/null
  local f="$ASK_ROOT/idealic:kernel/ov1.md"
  assert_contains "overruled: manager:idealic" "$(cat "$f")" "the operator's answer over a seat's stamps overruled:"
  assert_contains '```json history' "$(cat "$f")" "the seat's answer is kept in the history fence"
  assert_contains '"answeredBy": "manager:idealic"' "$(cat "$f")" "with its answerer"
}

# ASKFOLLOWUP: fu <ref-seat> <id> <rev> <kind> <fork|-> <text>: the operator's follow-up, written through
# the store as the server writes it (stamped operator/browser). No live session: the push is undelivered.
fu() {
  local fork="$5"; [ "$fork" = "-" ] && fork=""
  node --no-warnings --input-type=module -e '
    const [root, seat, id, rev, kind, fork, text] = process.argv.slice(1);
    const { followupAsk } = await import(process.env.ASK_STORE);
    await followupAsk(root, seat, id, { by: "operator", via: "browser", kind, ...(fork ? { fork } : {}), text, picks: fork ? { [fork]: ["YES"] } : undefined }, { expectedRevision: Number(rev) });
  ' "$ASK_ROOT" "$1" "$2" "$3" "$4" "$fork" "$6"
}
export ASK_STORE="$ENGINE_DIR/tools/ask-app/src/lib/store.ts"

test_askfollowup_read_prints_followups_and_revise_answers_them() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id fu1 --to manager:idealic >/dev/null
  fu idealic:kernel fu1 1 first GO "run the smoke test first"
  fu idealic:kernel fu1 2 question - "is this blocking two lanes?"
  local f="$ASK_ROOT/idealic:kernel/fu1.md" out
  assert_has_fixed "## Follow-up 1" "$f" "the follow-up is a ## Follow-up entry in the file"
  assert_contains "status: open" "$(cat "$f")" "the ask stays open"
  out=$(env -u FLEET_PANE "$ASK_SH" read idealic:kernel/fu1 2>/dev/null)
  assert_contains "follow-up 1 · first · fork GO · from operator" "$out" "read prints the first follow-up with its kind and fork"
  assert_contains "run the smoke test first" "$out" "with its text"
  assert_contains "unsent picks: GO YES" "$out" "and the unsent picks"
  assert_contains "follow-up 2 · question · from operator" "$out" "and the second, a question with no fork"
  assert_contains "undelivered" "$out" "a failed push is shown as undelivered"
  assert_contains "awaiting a revise" "$out" "an unanswered follow-up says it waits on a revise"
  out=$("$ASK_SH" revise idealic:kernel/fu1 --keep-body --answers-followup 1,2)
  assert_contains "changed: followup 1,2" "$out" "revise --answers-followup alone is a revision"
  out=$(env -u FLEET_PANE "$ASK_SH" read idealic:kernel/fu1 2>/dev/null)
  assert_contains "addressed in revision 4 by idealic:kernel" "$out" "read shows the follow-ups as addressed"
  assert_fails_with "an unknown follow-up is refused" "holds no follow-up 7" "$ASK_SH" revise idealic:kernel/fu1 --keep-body --answers-followup 7
  assert_fails_with "a non-number is refused" "--answers-followup takes" "$ASK_SH" revise idealic:kernel/fu1 --keep-body --answers-followup x
  assert_fails_with "only the asker revises, follow-up or not" "only the asker" env FLEET_PANE=manager:idealic "$ASK_SH" revise idealic:kernel/fu1 --keep-body --answers-followup 1
}

test_askfollowup_operator_drafts_over_a_seat_answer_and_sends_an_overrule() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id fd1 --to manager:idealic >/dev/null
  FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/fd1 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  local f="$ASK_ROOT/idealic:kernel/fd1.md"
  assert_fails_with "a seat never drafts over a settled answer" "only an open ask, or the operator over a settled answer, takes a draft" \
    env FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/fd1 --revision 2 --json '{"GO":["NO"]}'
  assert_contains "draft saved" "$(as_op draft idealic:kernel/fd1 --revision 2 --json '{"GO":["NO"]}')" "the operator drafts over the seat's answer"
  assert_contains "status: answered" "$(cat "$f")" "the seat's answer stands until the draft is sent"
  assert_contains "settled idealic:kernel/fd1" "$(as_op send idealic:kernel/fd1)" "the operator's draft sends"
  assert_contains "overruled: manager:idealic" "$(cat "$f")" "and overrules the seat"
}

test_fencelang_new_and_revise_refuse_an_untagged_fence_with_exit_2() {
  local bf="$TMP/untagged.md" rc out
  printf 'Context.\n\n```\nnpm test\n```\n\n%s\n' "$BODY" > "$bf"
  out=$("$ASK_SH" new --id fl1 --body-file "$bf" 2>&1); rc=$?
  assert_eq "2" "$rc" "new exits 2 on a fence with no language"
  assert_contains 'line 3: fenced block has no language; write ```text if nothing fits' "$out" "new names the line and the text hint"
  [ -e "$ASK_ROOT/idealic:kernel/fl1.md" ] && fail "new writes nothing when refused" "no file" "file exists" || pass "new writes nothing when refused"
  printf '```text\nnpm test\n```\n\n%s\n' "$BODY" > "$bf"
  "$ASK_SH" new --id fl2 --body-file "$bf" >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "new accepts a fence tagged text"
  printf '%s\n\n```\nx\n```\n' "$BODY" > "$bf"
  out=$("$ASK_SH" revise idealic:kernel/fl2 --body-file "$bf" 2>&1); rc=$?
  assert_eq "2" "$rc" "revise exits 2 on a fence with no language"
  assert_contains "fenced block has no language" "$out" "revise names it"
}

test_fencelang_every_line_of_a_multi_line_refusal_starts_with_ask_prefix() {
  local bf="$TMP/untagged2.md" rc out n bad
  printf '%s\n\n```\na\n```\n\n```\nb\n```\n' "$BODY" > "$bf"
  out=$("$ASK_SH" new --id fl3 --body-file "$bf" 2>&1 >/dev/null); rc=$?
  assert_eq "2" "$rc" "new exits 2 on two untagged fences"
  n=$(printf '%s\n' "$out" | grep -c 'fenced block has no language')
  assert_eq "2" "$n" "both untagged fences are named, one line each"
  bad=$(printf '%s\n' "$out" | grep -vc '^ask: ' || true)
  assert_eq "0" "$bad" "every stderr line of the refusal starts with ask: "
}

# IDE-339 OVEROP: a seat never replaces the operator's answer; the operator changes its own.
test_overop_a_seat_cannot_replace_the_operators_answer() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id op1 --to manager:idealic >/dev/null
  as_op answer idealic:kernel/op1 --revision 1 --json '{"GO":["NO"]}' >/dev/null
  local f="$ASK_ROOT/idealic:kernel/op1.md" before
  before=$(cat "$f")
  assert_fails_with "a manager's re-answer over the operator is refused" "operator already answered this at" \
    env FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/op1 --revision 2 --json '{"GO":["YES"]}'
  assert_fails_with "the refusal names the operator's choice and says what to do" "(GO NO); a seat cannot replace it — send a follow-up instead" \
    env FLEET_PANE=manager:idealic "$ASK_SH" answer idealic:kernel/op1 --revision 2 --json '{"GO":["YES"]}'
  assert_fails_with "a seat's draft over the operator is refused" "operator already answered this at" \
    env FLEET_PANE=manager:idealic "$ASK_SH" draft idealic:kernel/op1 --revision 2 --json '{"GO":["YES"]}'
  assert_eq "$before" "$(cat "$f")" "the refused answer and draft write nothing"
  as_op answer idealic:kernel/op1 --revision 2 --json '{"GO":["YES"]}' >/dev/null
  assert_contains '"YES"' "$(sed -n '/```json answer/,/```$/p' "$f")" "the operator changes its own answer"
}

run_discovered_tests
