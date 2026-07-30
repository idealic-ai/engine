#!/bin/bash
# tests/test-slack-post-sh.sh — Tests for slack-post.sh (engine slack-post)
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-slack-post-sh.sh
#
# Covers: dry-run payload shape, token redaction, env-file key extraction,
# missing-channel error, Slack ok:false handling, happy path. curl is mocked
# via a PATH-prepended stub that records argv+stdin and emits a canned response.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SLACK_POST="$HOME/.claude/engine/scripts/slack-post.sh"

setup() {
  ORIG_PATH="$PATH"
  TMP=$(mktemp -d)
  MOCK_BIN="$TMP/bin"
  mkdir -p "$MOCK_BIN"
  export MOCK_CURL_ARGS="$TMP/curl.args"
  export MOCK_CURL_STDIN="$TMP/curl.stdin"
  export MOCK_CURL_RESPONSE='{"ok":true}'
  cat > "$MOCK_BIN/curl" <<'STUB'
#!/bin/bash
# mock curl: record argv + stdin, emit canned Slack JSON
printf '%s\n' "$*" >> "$MOCK_CURL_ARGS"
cat > "$MOCK_CURL_STDIN" 2>/dev/null || true
printf '%s' "${MOCK_CURL_RESPONSE}"
STUB
  chmod +x "$MOCK_BIN/curl"
  export PATH="$MOCK_BIN:$ORIG_PATH"
  # Isolate token/channel env for each test
  unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN SLACK_INTAKE_CHANNEL
  # Fixture env files
  ENV_WITH_KEY="$TMP/with.env"
  printf 'FOO=bar\nSLACK_INTAKE_TOKEN="xoxb-fromfile"\nBAZ=qux\n' > "$ENV_WITH_KEY"
  ENV_NO_KEY="$TMP/nokey.env"
  printf 'FOO=bar\n' > "$ENV_NO_KEY"
}

teardown() {
  export PATH="$ORIG_PATH"
  rm -rf "$TMP"
  unset MOCK_CURL_ARGS MOCK_CURL_STDIN MOCK_CURL_RESPONSE
}

# Case 1 — dry-run prints a valid JSON body with channel+text, no network call.
test_slack_post_dry_run_payload() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-secret" "$SLACK_POST" --dry-run --channel "C123" --text "hello world" 2>&1)
  local ch txt
  ch=$(printf '%s' "$out" | jq -r '.channel' 2>/dev/null)
  txt=$(printf '%s' "$out" | jq -r '.text' 2>/dev/null)
  assert_eq "C123" "$ch" "dry-run: channel in payload"
  assert_eq "hello world" "$txt" "dry-run: text in payload"
  assert_file_not_exists "$MOCK_CURL_ARGS" "dry-run: no curl call made"
}

# Case 2 — the token must NEVER appear in dry-run output.
test_slack_post_token_redacted() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-supersecret-123" "$SLACK_POST" --dry-run --channel "C1" --text "hi" 2>&1)
  assert_not_contains "xoxb-supersecret-123" "$out" "dry-run: token absent from output"
}

# Case 3 — token extracted from --env-file when no env var is set (grep, not source).
test_slack_post_env_file_extract() {
  MOCK_CURL_RESPONSE='{"ok":true}'
  local rc
  printf '%s' "the body" | "$SLACK_POST" --channel "C1" --env-file "$ENV_WITH_KEY" >/dev/null 2>&1
  rc=$?
  assert_eq "0" "$rc" "env-file: token found → exit 0"
  assert_contains "Bearer xoxb-fromfile" "$(cat "$MOCK_CURL_ARGS" 2>/dev/null)" "env-file: token used in Authorization header"
}

# Case 3b — env-file present but missing the key → clear error, exit 1.
test_slack_post_env_file_missing_key() {
  local rc
  printf '%s' "body" | "$SLACK_POST" --channel "C1" --env-file "$ENV_NO_KEY" >/dev/null 2>&1
  rc=$?
  assert_eq "1" "$rc" "env-file without key → exit 1"
}

# Case 4 — no channel anywhere (not dry-run) → error, exit 1.
test_slack_post_missing_channel() {
  local rc
  printf '%s' "body" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" >/dev/null 2>&1
  rc=$?
  assert_eq "1" "$rc" "missing channel → exit 1"
}

# Case 5 — Slack returns ok:false → print error, exit 1.
test_slack_post_ok_false() {
  export MOCK_CURL_RESPONSE='{"ok":false,"error":"not_in_channel"}'
  local out rc
  out=$(printf '%s' "body" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C1" 2>&1)
  rc=$?
  assert_eq "1" "$rc" "ok:false → exit 1"
  assert_contains "not_in_channel" "$out" "ok:false → surfaces Slack error"
}

# Case 6 — happy path: ok:true → exit 0.
test_slack_post_happy_path() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"123.456"}'
  local rc
  printf '%s' "a message" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C1" >/dev/null 2>&1
  rc=$?
  assert_eq "0" "$rc" "ok:true → exit 0"
}

# Case 7 — --update-ts targets chat.update, puts ts in the body, prints ts on stdout.
test_slack_post_update_endpoint() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"999.111"}'
  local out rc args stdin
  out=$(printf '%s' "edited" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C1" --update-ts "999.111" 2>/dev/null)
  rc=$?
  args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  stdin=$(cat "$MOCK_CURL_STDIN" 2>/dev/null)
  assert_eq "0" "$rc" "update: ok:true → exit 0"
  assert_contains "chat.update" "$args" "update: hits chat.update endpoint"
  assert_eq "999.111" "$(printf '%s' "$stdin" | jq -r '.ts')" "update: ts in request body"
  assert_eq "999.111" "$out" "update: prints message ts on stdout"
}

# Case 7b — without --update-ts, the endpoint stays chat.postMessage.
test_slack_post_default_endpoint() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"1.2"}'
  printf '%s' "new" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C1" >/dev/null 2>&1
  local args; args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_contains "chat.postMessage" "$args" "default: hits chat.postMessage"
  assert_not_contains "chat.update" "$args" "default: not chat.update"
}

# Case 7c — --update-ts dry-run: ts in the body, token still absent, no curl call.
test_slack_post_update_dry_run() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-secret" "$SLACK_POST" --dry-run --channel "C1" --text "hi" --update-ts "42.7" 2>&1)
  assert_eq "42.7" "$(printf '%s' "$out" | jq -r '.ts')" "update dry-run: ts in body"
  assert_not_contains "xoxb-secret" "$out" "update dry-run: token absent"
  assert_file_not_exists "$MOCK_CURL_ARGS" "update dry-run: no curl call"
}

# Case 7d — a normal post prints the returned message ts on stdout (for later editing).
test_slack_post_prints_ts() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"555.222"}'
  local out; out=$(printf '%s' "m" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C1" 2>/dev/null)
  assert_eq "555.222" "$out" "post: prints message ts on stdout"
}

# Case 7e — --update-ts with no value → clear error, exit 1 (no silent postMessage downgrade, no hang).
test_slack_post_update_ts_empty() {
  local rc
  printf '%s' "m" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C1" --update-ts >/dev/null 2>&1
  rc=$?
  assert_eq "1" "$rc" "trailing --update-ts (no value) → exit 1, no hang/downgrade"
}

run_discovered_tests
