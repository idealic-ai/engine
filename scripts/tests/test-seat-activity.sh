#!/bin/bash
# test-seat-activity.sh — the per-seat activity record the hooks write (lib.sh seat_activity_record)
# and that `engine broadcast` reads for a seat's idle time.
#
#   lib      — the record's shape and path, keyed by FLEET_PANE; nothing written without a seat or a
#              session id; a seat name that is not one token writes nothing; the write is a rename.
#   subagent — a tool call carrying agent_id counts for the seat, marked as a lane's.
#   hooks    — UserPromptSubmit (user-prompt-working.sh), PreToolUse (pre-tool-use-one-strike.sh)
#              and Stop (stop-notify.sh) each write it, and each still does its own job.
#   cost     — the added write, timed in a loop.
#
# Runs against the tree holding this file (a fake HOME links its lib.sh), never ~/.claude.

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

ACT=""
setup() {
  setup_test_env seatact
  ACT="$TMP_DIR/activity"
  export SEAT_ACTIVITY_DIR="$ACT"
  export FLEET_PANE="app:ask"
}
teardown() { unset SEAT_ACTIVITY_DIR FLEET_PANE; cleanup_test_env; }

lib() { bash -c 'source "$HOME/.claude/scripts/lib.sh"; seat_activity_record "$@"' _ "$@"; }
SID='"session_id":"0c1d2e3f-aaaa-bbbb-cccc-0123456789ab"'

test_record_written_with_its_fields() {
  local before; before=$(date +%s)
  lib prompt "{$SID,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}"
  assert_file_exists "$ACT/app:ask.json" "lib: the record is <dir>/<seat>.json"
  local f="$ACT/app:ask.json"
  assert_eq "app:ask" "$(jq -r .seat "$f")" "lib: it names the seat"
  assert_eq "0c1d2e3f-aaaa-bbbb-cccc-0123456789ab" "$(jq -r .sessionId "$f")" "lib: it holds the session id from the hook input"
  assert_eq "prompt" "$(jq -r .event "$f")" "lib: it holds the event kind"
  local t; t=$(jq -r .lastActivityAt "$f")
  if [ "$t" -ge "$before" ] && [ "$t" -le "$(( $(date +%s) + 1 ))" ]; then pass "lib: lastActivityAt is now, in epoch seconds"
  else fail "lib: lastActivityAt is now, in epoch seconds" "~$before" "$t"; fi
  [[ "$(jq -r .pid "$f")" =~ ^[0-9]+$ ]] && pass "lib: it holds a pid" || fail "lib: it holds a pid" "a number" "$(jq -r .pid "$f")"
  assert_eq "" "$(ls -A "$ACT" | grep -v '^app:ask.json$' || true)" "lib: no temp file is left beside it"
}

test_rewrite_replaces_the_record() {
  lib prompt "{$SID}"
  lib tool "{$SID,\"tool_name\":\"Bash\"}"
  assert_eq "tool" "$(jq -r .event "$ACT/app:ask.json")" "lib: the newest event replaces the record"
  assert_eq 1 "$(jq -s length "$ACT/app:ask.json")" "lib: one JSON document, not appended"
}

test_no_seat_writes_nothing() {
  FLEET_PANE="" lib prompt "{$SID}"
  assert_eq "" "$(ls -A "$ACT" 2>/dev/null || true)" "lib: without FLEET_PANE nothing is written"
  local bad
  for bad in "a/b" ".hidden" "-x" "two words"; do
    FLEET_PANE="$bad" lib prompt "{$SID}"
  done
  assert_eq "" "$(ls -A "$ACT" 2>/dev/null || true)" "lib: a seat name with a slash, a leading dot or dash, or a space writes nothing"
}

test_no_session_id_writes_nothing() {
  lib prompt '{"prompt":"x"}'
  assert_file_not_exists "$ACT/app:ask.json" "lib: without a session id nothing is written"
  lib prompt '{"tool_input":{"command":"echo \"session_id\":\"forged\""}}'
  assert_file_not_exists "$ACT/app:ask.json" "lib: a session_id inside an escaped string is not read as the field"
}

test_subagent_tool_call_counts_for_the_seat() {
  lib tool "{$SID,\"agent_id\":\"a1b2\",\"agent_type\":\"builder\",\"tool_name\":\"Read\"}"
  assert_eq "tool:subagent" "$(jq -r .event "$ACT/app:ask.json")" "subagent: a lane's tool call writes the seat's record, marked as a lane's"
  assert_eq "0c1d2e3f-aaaa-bbbb-cccc-0123456789ab" "$(jq -r .sessionId "$ACT/app:ask.json")" "subagent: under the parent session's id"
}

test_unwritable_dir_never_fails() {
  : > "$TMP_DIR/afile"
  SEAT_ACTIVITY_DIR="$TMP_DIR/afile/sub" lib prompt "{$SID}"
  assert_eq 0 "$?" "lib: an unwritable dir returns 0 (a hook must not fail on it)"
}

# ---- the hooks
hook() { # hook <file> <json> → OUT, RC
  OUT=$(printf '%s' "$2" | bash "$REAL_HOOKS_DIR/$1" 2>&1); RC=$?
}

test_hook_user_prompt_writes() {
  hook user-prompt-working.sh "{$SID,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"go\"}"
  assert_eq 0 "$RC" "hook: user-prompt-working exits 0"
  assert_eq "prompt" "$(jq -r .event "$ACT/app:ask.json" 2>/dev/null)" "hook: UserPromptSubmit writes the record"
}

# Every wake arrives as a user turn, and each kind is a prompt to the hook: a typed prompt, a
# cross-session SendMessage, a broadcast push (deliver.ts sends a user message), a task
# notification (a lane's hand-back). Each must stamp the record. Whether Claude Code fires
# UserPromptSubmit for the last three is not observable in a transcript here (none records a
# UserPromptSubmit attachment, not even for typed prompts), so the record does not depend on it:
# the turn such a wake starts ends in Stop, and any tool call in it runs PreToolUse.
test_hook_every_wake_kind_stamps() {
  local p kind
  for kind in typed cross-session broadcast task-notification; do
    case "$kind" in
      typed) p="please look at the queue" ;;
      cross-session) p='<cross-session-message from=\"meta:fleet\">done</cross-session-message>' ;;
      broadcast) p='Use /ask.\nack (from manager:app): engine broadcast ack q1' ;;
      task-notification) p='<task-notification><task-id>a1</task-id><status>completed</status></task-notification>' ;;
    esac
    rm -f "$ACT/app:ask.json"
    hook user-prompt-working.sh "{$SID,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$p\"}"
    assert_eq "prompt" "$(jq -r .event "$ACT/app:ask.json" 2>/dev/null)" "wake: a $kind prompt stamps the record"
    rm -f "$ACT/app:ask.json"
    hook stop-notify.sh "{$SID,\"hook_event_name\":\"Stop\"}"
    assert_eq "stop" "$(jq -r .event "$ACT/app:ask.json" 2>/dev/null)" "wake: and the turn a $kind wake starts stamps it at Stop"
  done
}

test_hook_pre_tool_use_writes_and_still_guards() {
  hook pre-tool-use-one-strike.sh "{$SID,\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/x\"}}"
  assert_contains '"permissionDecision":"allow"' "$OUT" "hook: one-strike still allows a non-Bash tool"
  assert_eq "tool" "$(jq -r .event "$ACT/app:ask.json" 2>/dev/null)" "hook: PreToolUse writes the record"
  rm -f "$ACT/app:ask.json"
  CLAUDE_HOOK_WARNED_DIR="$TMP_DIR/w" hook pre-tool-use-one-strike.sh "{$SID,\"agent_id\":\"x9\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git reset --hard\"}}"
  assert_contains '"deny"' "$OUT" "hook: one-strike still denies a destructive command"
  assert_eq "tool:subagent" "$(jq -r .event "$ACT/app:ask.json" 2>/dev/null)" "hook: a subagent's denied call still marks the seat active"
}

test_hook_stop_writes() {
  hook stop-notify.sh "{$SID,\"hook_event_name\":\"Stop\"}"
  assert_eq 0 "$RC" "hook: stop-notify exits 0"
  assert_eq "stop" "$(jq -r .event "$ACT/app:ask.json" 2>/dev/null)" "hook: Stop writes the record"
}

# The added cost, per call: the function alone, sourced once, 50 calls.
test_cost_is_a_few_ms() {
  local ms
  ms=$(bash -c 'source "$HOME/.claude/scripts/lib.sh"
    s=$(perl -MTime::HiRes=time -e "printf q(%d), time*1000")
    for i in $(seq 50); do seat_activity_record tool "$1"; done
    e=$(perl -MTime::HiRes=time -e "printf q(%d), time*1000")
    echo $(( (e - s) / 50 ))' _ "{$SID,\"tool_name\":\"Read\"}")
  echo "    (seat_activity_record: ${ms} ms per call, load $(uptime | sed 's/.*averages*: //'))"
  # Two forks (date, mv): ~12 ms at load ~90 on this box. The bound only catches a jq, a tmux call
  # or a lib.sh source creeping in; the measured figure is printed above.
  if [ "$ms" -le 100 ]; then pass "cost: ${ms} ms per call (bound 100 ms)"; else fail "cost: under 100 ms per call" "<=100" "$ms"; fi
}

run_discovered_tests
