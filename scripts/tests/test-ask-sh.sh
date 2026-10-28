#!/bin/bash
# test-ask-sh.sh — CLI coverage for scripts/ask.sh (`engine ask new|list|answer|serve|path`).
#
# Every test runs against a throwaway ASK_ROOT and an empty ASK_SESSIONS_DIR, so no real seat is
# ever messaged and the fleet's real asks directory is never touched.
set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

ASK_SH="$HOME/.claude/engine/scripts/ask.sh"
ENGINE_SH="$HOME/.claude/engine/scripts/engine.sh"

BODY='## ¶ASK_GO: Choose one: Ship it?
- [ ] [YES] Yes
  Ship tonight.
- [ ] [NO] No'

setup() {
  TMP=$(mktemp -d /tmp/askcli-XXXXXX)
  export ASK_ROOT="$TMP/asks"
  export ASK_SESSIONS_DIR="$TMP/sessions"
  mkdir -p "$ASK_SESSIONS_DIR"
  unset FLEET_PARENT
  export FLEET_PANE="idealic:kernel"
}
teardown() {
  "$ASK_SH" serve "$ASK_ROOT" --stop >/dev/null 2>&1 || true
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
  out=$("$ASK_SH" answer idealic:kernel/q1 --revision 1 --json '{"GO":["YES"]}' --by operator --note "ship it")
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
  assert_fails_with "answer refuses {}" "empty answer is not an answer" "$ASK_SH" answer idealic:kernel/q3 --revision 1 --json '{}'
  assert_fails_with "answer refuses an unknown key" "unknown question: NOPE" "$ASK_SH" answer idealic:kernel/q3 --revision 1 --json '{"NOPE":["YES"]}'
  assert_contains "status: open" "$(cat "$ASK_ROOT/idealic:kernel/q3.md")" "a refused answer writes nothing"
}

test_answer_requires_revision_and_refuses_stale() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q4 >/dev/null
  assert_fails_with "answer without --revision is refused" "--revision is required" "$ASK_SH" answer idealic:kernel/q4 --json '{"GO":["YES"]}'
  "$ASK_SH" answer idealic:kernel/q4 --revision 1 --json '{"GO":["YES"]}' >/dev/null
  assert_fails_with "a stale revision is refused" "stale revision" "$ASK_SH" answer idealic:kernel/q4 --revision 1 --json '{"GO":["NO"]}'
  assert_contains '"YES"' "$(cat "$ASK_ROOT/idealic:kernel/q4.md")" "the first answer stands"
}

test_answer_decline_needs_reason() {
  printf '%s\n' "$BODY" | "$ASK_SH" new --id q5 >/dev/null
  assert_fails_with "decline without a reason is refused" "non-empty reason" "$ASK_SH" answer idealic:kernel/q5 --revision 1 --decline "  "
  "$ASK_SH" answer idealic:kernel/q5 --revision 1 --decline "beyond my grant" >/dev/null
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

run_discovered_tests
