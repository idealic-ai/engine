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

run_discovered_tests
