#!/bin/bash
# tests/test-slack-read-sh.sh — Tests for slack-read.sh (engine slack-read)
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-slack-read-sh.sh
#
# Covers BOTH modes: the existing thread read (conversations.replies) and the
# new channel-history read (--history, conversations.history, time-bounded).
# curl is mocked via a PATH-prepended stub that BRANCHES on the endpoint URL
# (slack-read touches auth.test + conversations.list/info + history/replies +
# users.info in one run) and records argv so window params can be asserted.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SLACK_READ="$HOME/.claude/engine/scripts/slack-read.sh"

setup() {
  ORIG_PATH="$PATH"
  TMP=$(mktemp -d)
  MOCK_BIN="$TMP/bin"
  mkdir -p "$MOCK_BIN"
  export MOCK_CURL_ARGS="$TMP/curl.args"
  # Per-endpoint canned responses (tests override as needed).
  export MOCK_AUTH_RESPONSE='{"ok":true,"user_id":"UBOT"}'
  export MOCK_LIST_RESPONSE='{"ok":true,"channels":[{"name":"intake","id":"C123"}]}'
  export MOCK_INFO_RESPONSE='{"ok":true,"channel":{"name":"intake"}}'
  export MOCK_USERS_RESPONSE='{"ok":true,"user":{"real_name":"Alice"}}'
  # A 3-message window: own-bot message, a bot_id (webhook) message, one real human.
  export MOCK_HISTORY_RESPONSE='{"ok":true,"has_more":false,"messages":[{"ts":"100.1","user":"UBOT","text":"i am the bot"},{"ts":"100.2","bot_id":"B1","user":"U9","text":"webhook noise"},{"ts":"100.3","user":"UALICE","text":"real human context"}]}'
  export MOCK_REPLIES_RESPONSE='{"ok":true,"messages":[{"ts":"90.0","user":"UOP","text":"the announce parent"},{"ts":"91.1","user":"UALICE","text":"a human reply"}]}'
  cat > "$MOCK_BIN/curl" <<'STUB'
#!/bin/bash
# mock curl: record argv, branch canned Slack JSON on the endpoint in the URL.
printf '%s\n' "$*" >> "$MOCK_CURL_ARGS"
case "$*" in
  *auth.test*)             printf '%s' "$MOCK_AUTH_RESPONSE" ;;
  *conversations.list*)    printf '%s' "$MOCK_LIST_RESPONSE" ;;
  *conversations.info*)    printf '%s' "$MOCK_INFO_RESPONSE" ;;
  *conversations.history*) printf '%s' "$MOCK_HISTORY_RESPONSE" ;;
  *conversations.replies*) printf '%s' "$MOCK_REPLIES_RESPONSE" ;;
  *users.info*)            printf '%s' "$MOCK_USERS_RESPONSE" ;;
  *)                       printf '%s' '{"ok":false,"error":"unexpected_endpoint"}' ;;
esac
STUB
  chmod +x "$MOCK_BIN/curl"
  export PATH="$MOCK_BIN:$ORIG_PATH"
  unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN SLACK_INTAKE_CHANNEL
}

teardown() {
  export PATH="$ORIG_PATH"
  rm -rf "$TMP"
  unset MOCK_CURL_ARGS MOCK_AUTH_RESPONSE MOCK_LIST_RESPONSE MOCK_INFO_RESPONSE \
        MOCK_USERS_RESPONSE MOCK_HISTORY_RESPONSE MOCK_REPLIES_RESPONSE
}

# The recorded argv line for a given endpoint (last match).
history_argv() { grep 'conversations.history' "$MOCK_CURL_ARGS" 2>/dev/null | tail -1; }

# --- Case 1 — --history requires a channel (no --channel, no env) → fail, no network.
test_history_requires_channel() {
  local out rc
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history 2>&1); rc=$?
  assert_neq "0" "$rc" "--history without a channel → non-zero"
  assert_contains "channel" "$out" "--history without a channel → says channel required"
  assert_file_not_exists "$MOCK_CURL_ARGS" "--history channel-guard fails before any curl"
}

# --- Case 2 — --history and --thread-ts are mutually exclusive.
test_history_thread_mutually_exclusive() {
  local out rc
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "C123" --thread-ts "90.0" 2>&1); rc=$?
  assert_neq "0" "$rc" "--history + --thread-ts → non-zero"
  assert_contains "thread-ts" "$out" "--history + --thread-ts → names the conflict"
}

# --- Case 3 — --lookback 7d computes oldest ≈ now-7d and sends it to history.
test_history_lookback_computes_oldest() {
  local now expected actual diff
  now=$(date +%s); expected=$((now - 604800))
  SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d >/dev/null 2>&1
  local argv; argv=$(history_argv)
  assert_contains "oldest=" "$argv" "history call carries an oldest param"
  actual=$(printf '%s' "$argv" | sed -n 's/.*oldest=\([0-9]*\).*/\1/p')
  assert_not_empty "$actual" "oldest is a numeric epoch"
  diff=$(( actual > expected ? actual - expected : expected - actual ))
  [ "$diff" -le 120 ] && pass "lookback-oldest" "oldest within 120s of now-7d (Δ=${diff}s)" \
    || fail "lookback-oldest" "oldest off by ${diff}s (actual=$actual expected≈$expected)"
}

# --- Case 4 — explicit --oldest overrides --lookback.
test_history_oldest_overrides_lookback() {
  SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d --oldest 1000 >/dev/null 2>&1
  local argv; argv=$(history_argv)
  local actual; actual=$(printf '%s' "$argv" | sed -n 's/.*oldest=\([0-9]*\).*/\1/p')
  assert_eq "1000" "$actual" "--oldest wins over --lookback"
}

# --- Case 5 — happy path: history shape, own+bot excluded, name resolved.
test_history_happy_path() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d 2>/dev/null)
  assert_eq "true" "$(printf '%s' "$out" | jq -r '.ok')" "ok:true"
  assert_eq "history" "$(printf '%s' "$out" | jq -r '.mode')" "mode:history"
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.count')" "own + bot_id excluded → 1 message"
  assert_eq "real human context" "$(printf '%s' "$out" | jq -r '.messages[0].text')" "the human message survives"
  assert_eq "Alice" "$(printf '%s' "$out" | jq -r '.messages[0].user_name')" "author id resolved to name"
}

# --- Case 6 — an empty window is a success with count 0, not an error.
test_history_empty_window() {
  export MOCK_HISTORY_RESPONSE='{"ok":true,"has_more":false,"messages":[]}'
  local out rc
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "empty window → exit 0"
  assert_eq "0" "$(printf '%s' "$out" | jq -r '.count')" "empty window → count 0"
}

# --- Case 7 — a read that could not happen is a hard failure, not an empty read.
test_history_not_in_channel() {
  export MOCK_HISTORY_RESPONSE='{"ok":false,"error":"not_in_channel"}'
  local out rc
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d 2>&1); rc=$?
  assert_neq "0" "$rc" "not_in_channel → non-zero (deaf ≠ empty)"
  assert_contains "member" "$out" "not_in_channel → explains the bot must be a member"
}

# --- Case 8 — --raw short-circuits name resolution to a filtered array.
test_history_raw() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d --raw 2>/dev/null)
  assert_eq "array" "$(printf '%s' "$out" | jq -r 'type')" "--raw → a bare array"
  assert_eq "1" "$(printf '%s' "$out" | jq -r 'length')" "--raw → filtered (own+bot dropped)"
  assert_not_contains "users.info" "$(cat "$MOCK_CURL_ARGS")" "--raw → no name-resolution call"
}

# --- Case 9 — thread mode (no --history) is unchanged: replies shape, parent dropped.
test_thread_mode_unchanged() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  assert_eq "true" "$(printf '%s' "$out" | jq -r '.ok')" "thread ok:true"
  assert_eq "90.0" "$(printf '%s' "$out" | jq -r '.thread_ts')" "thread_ts echoed"
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.count')" "parent dropped → 1 reply"
  assert_eq "a human reply" "$(printf '%s' "$out" | jq -r '.replies[0].text')" "the reply survives"
}

run_discovered_tests
