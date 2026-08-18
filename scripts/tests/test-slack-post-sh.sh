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

# mksession DIR — make DIR a project with an ACTIVE session.
# The DEFAULTED token chain is anchored to the current session's project root, so a
# case that exercises it must have one; without it the resolver refuses to look at all
# and the assertion below would pass or fail for the wrong reason.
export CLAUDE_SUPERVISOR_PID="$$"
mksession() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/sessions/t" "$d/.session-cache"
  printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$d/sessions/t/.state.json"
  export CLAUDE_SESSION_CACHE_DIR="$d/.session-cache"
  rm -f "$d/.session-cache"/* 2>/dev/null || true
}

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
  out=$(SLACK_INTAKE_TOKEN="xoxb-secret" "$SLACK_POST" --dry-run --channel "C0123ABCD" --text "hello world" 2>&1)
  local ch txt
  ch=$(printf '%s' "$out" | jq -r '.channel' 2>/dev/null)
  txt=$(printf '%s' "$out" | jq -r '.text' 2>/dev/null)
  assert_eq "C0123ABCD" "$ch" "dry-run: channel in payload"
  assert_eq "hello world" "$txt" "dry-run: text in payload"
  assert_file_not_exists "$MOCK_CURL_ARGS" "dry-run: no curl call made"
}

# Case 2 — the token must NEVER appear in dry-run output.
test_slack_post_token_redacted() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-supersecret-123" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "hi" 2>&1)
  assert_not_contains "xoxb-supersecret-123" "$out" "dry-run: token absent from output"
}

# Case 3 — token extracted from --env-file when no env var is set (grep, not source).
test_slack_post_env_file_extract() {
  MOCK_CURL_RESPONSE='{"ok":true}'
  local rc
  printf '%s' "the body" | "$SLACK_POST" --channel "C01ABCDEF" --env-file "$ENV_WITH_KEY" >/dev/null 2>&1
  rc=$?
  assert_eq "0" "$rc" "env-file: token found → exit 0"
  assert_contains "Bearer xoxb-fromfile" "$(cat "$MOCK_CURL_ARGS" 2>/dev/null)" "env-file: token used in Authorization header"
}

# Case 3b — env-file present but missing the key → clear error, exit 1.
test_slack_post_env_file_missing_key() {
  local rc
  printf '%s' "body" | "$SLACK_POST" --channel "C01ABCDEF" --env-file "$ENV_NO_KEY" >/dev/null 2>&1
  rc=$?
  assert_eq "1" "$rc" "env-file without key → exit 1"
}

# Case 3c — with NO --env-file the post walks the same chain `engine env doctor`
# verifies (./.env.local then ./.env), so a doctor PASS means the announce works.
test_slack_post_default_chain_reads_dotenv() {
  MOCK_CURL_RESPONSE='{"ok":true}'
  local rc
  mksession "$TMP/proj"
  printf 'SLACK_INTAKE_TOKEN=xoxb-fromdotenv\n' > "$TMP/proj/.env"
  ( cd "$TMP/proj" && printf '%s' "body" | "$SLACK_POST" --channel "C01ABCDEF" >/dev/null 2>&1 )
  rc=$?
  assert_eq "0" "$rc" "no --env-file: a token in ./.env resolves → exit 0"
  assert_contains "Bearer xoxb-fromdotenv" "$(cat "$MOCK_CURL_ARGS" 2>/dev/null)" "no --env-file: ./.env token reaches the Authorization header"
}

# Case 3d — an explicit --env-file is authoritative: a miss fails loudly rather than
# falling through to the cwd's dotfile (which may belong to a different workspace).
test_slack_post_env_file_no_fallthrough() {
  local rc
  # A session here too: otherwise this asserts "no anchor", not "no fallthrough",
  # and would stay green even if the fallthrough rule were broken.
  mksession "$TMP/proj2"
  printf 'SLACK_INTAKE_TOKEN=xoxb-other-workspace\n' > "$TMP/proj2/.env.local"
  ( cd "$TMP/proj2" && printf '%s' "body" | "$SLACK_POST" --channel "C01ABCDEF" --env-file "$ENV_NO_KEY" >/dev/null 2>&1 )
  rc=$?
  assert_eq "1" "$rc" "explicit --env-file without the key does NOT fall through to ./.env.local"
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
  out=$(printf '%s' "body" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" 2>&1)
  rc=$?
  assert_eq "1" "$rc" "ok:false → exit 1"
  assert_contains "not_in_channel" "$out" "ok:false → surfaces Slack error"
}

# Case 6 — happy path: ok:true → exit 0.
test_slack_post_happy_path() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"123.456"}'
  local rc
  printf '%s' "a message" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" >/dev/null 2>&1
  rc=$?
  assert_eq "0" "$rc" "ok:true → exit 0"
}

# Case 7 — --update-ts targets chat.update, puts ts in the body, prints ts on stdout.
test_slack_post_update_endpoint() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"999.111"}'
  local out rc args stdin
  out=$(printf '%s' "edited" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --update-ts "999.111" 2>/dev/null)
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
  printf '%s' "new" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" >/dev/null 2>&1
  local args; args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_contains "chat.postMessage" "$args" "default: hits chat.postMessage"
  assert_not_contains "chat.update" "$args" "default: not chat.update"
}

# Case 7c — --update-ts dry-run: ts in the body, token still absent, no curl call.
test_slack_post_update_dry_run() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-secret" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "hi" --update-ts "42.7" 2>&1)
  assert_eq "42.7" "$(printf '%s' "$out" | jq -r '.ts')" "update dry-run: ts in body"
  assert_not_contains "xoxb-secret" "$out" "update dry-run: token absent"
  assert_file_not_exists "$MOCK_CURL_ARGS" "update dry-run: no curl call"
}

# Case 7d — a normal post prints the returned message ts on stdout (for later editing).
test_slack_post_prints_ts() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"555.222"}'
  local out; out=$(printf '%s' "m" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" 2>/dev/null)
  assert_eq "555.222" "$out" "post: prints message ts on stdout"
}

# Case 7e — --update-ts with no value → clear error, exit 1 (no silent postMessage downgrade, no hang).
test_slack_post_update_ts_empty() {
  local rc
  printf '%s' "m" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --update-ts >/dev/null 2>&1
  rc=$?
  assert_eq "1" "$rc" "trailing --update-ts (no value) → exit 1, no hang/downgrade"
}

# --- thread replies (--thread-ts) -----------------------------------------
# --thread-ts routes a NEW message into an existing thread. It is the sibling of
# --update-ts (an optional ts that modifies the body) but NOT of its endpoint
# switch: a reply is still chat.postMessage.

# Case 9 — --thread-ts puts thread_ts in the body and STAYS on chat.postMessage.
test_slack_post_thread_ts_stays_on_post_message() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"888.222"}'
  local out rc args stdin
  out=$(printf '%s' "reply" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --thread-ts "777.111" 2>/dev/null)
  rc=$?
  args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  stdin=$(cat "$MOCK_CURL_STDIN" 2>/dev/null)
  assert_eq "0" "$rc" "thread: ok:true → exit 0"
  assert_contains "chat.postMessage" "$args" "thread: a reply is still chat.postMessage"
  assert_not_contains "chat.update" "$args" "thread: never switches to chat.update"
  assert_eq "777.111" "$(printf '%s' "$stdin" | jq -r '.thread_ts')" "thread: thread_ts reaches the wire"
  assert_eq "888.222" "$out" "thread: prints the REPLY's own ts on stdout"
}

# Case 9b — --thread-ts dry-run: thread_ts in the body, token absent, no curl call.
test_slack_post_thread_ts_dry_run() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-secret" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "hi" --thread-ts "42.7" 2>&1)
  assert_eq "42.7" "$(printf '%s' "$out" | jq -r '.thread_ts')" "thread dry-run: thread_ts in body"
  assert_not_contains "xoxb-secret" "$out" "thread dry-run: token absent"
  assert_file_not_exists "$MOCK_CURL_ARGS" "thread dry-run: no curl call"
}

# Case 9c — the injection sits AFTER the body-build branches, so every layout
# threads: --blocks keeps its 4 blocks verbatim AND gains thread_ts. This is the
# case a per-branch injection would silently lose.
test_slack_post_thread_ts_with_blocks() {
  local out
  out=$(printf '%s' "$BLOCKS_FIXTURE_JSON" \
    | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - --thread-ts "1.5" 2>&1)
  assert_eq "1.5" "$(printf '%s' "$out" | jq -r '.thread_ts')" "thread + blocks: thread_ts survives the blocks path"
  assert_eq "header,context,divider,section" \
    "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "thread + blocks: layout untouched"
}

# Case 9d — ditto for the --title layout (the third body-build branch).
test_slack_post_thread_ts_with_title() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --title "T" --text "body" --thread-ts "2.5" 2>&1)
  assert_eq "2.5" "$(printf '%s' "$out" | jq -r '.thread_ts')" "thread + title: thread_ts survives the title path"
  assert_eq "header,section" "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "thread + title: layout untouched"
}

# Case 9e — --thread-ts and --update-ts are mutually exclusive (chat.update has
# no thread_ts; passing both is an incoherent request, not a merge).
test_slack_post_thread_ts_update_ts_conflict() {
  local rc out
  out=$(printf '%s' "m" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --thread-ts "1.1" --update-ts "2.2" 2>&1)
  rc=$?
  assert_eq "1" "$rc" "--thread-ts + --update-ts → exit 1"
  assert_contains "mutually exclusive" "$out" "--thread-ts + --update-ts → explains why"
}

# Case 9f — trailing --thread-ts with no value → clear error, exit 1 (no silent
# top-level downgrade, which is exactly the failure this flag exists to prevent).
test_slack_post_thread_ts_empty() {
  local rc out
  out=$(printf '%s' "m" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --thread-ts 2>&1)
  rc=$?
  assert_eq "1" "$rc" "trailing --thread-ts (no value) → exit 1, no hang/downgrade"
  assert_contains "thread-ts requires" "$out" "empty --thread-ts → names the flag"
}

# Case 9g — PARITY: without --thread-ts the key is absent entirely, on every
# layout. An always-present null/empty thread_ts would change what Slack sees.
test_slack_post_no_thread_ts_key_when_absent() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "body" 2>&1)
  assert_eq "false" "$(printf '%s' "$out" | jq -r 'has("thread_ts")')" "no --thread-ts: key absent on the default path"
  out=$(printf '%s' "$BLOCKS_FIXTURE_JSON" \
    | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - 2>&1)
  assert_eq "false" "$(printf '%s' "$out" | jq -r 'has("thread_ts")')" "no --thread-ts: key absent on the blocks path"
}

# Case 9h — --help documents the flag (this header is the script's only docs).
test_slack_post_thread_ts_documented() {
  local out; out=$("$SLACK_POST" --help 2>&1)
  assert_contains "thread-ts <ts>" "$out" "help: --thread-ts is documented in the usage header"
}

# --- block structure ------------------------------------------------------
# The suite above asserts channel, text, endpoint and exit codes — never the
# LAYOUT. A caller that supplies blocks needs the poster to pass them through
# untouched, and nothing below the wire tells it whether that happened. These
# are the structural assertions: block COUNT and TYPE ORDER, on both paths.

# Fixture: a caller-supplied layout using the non-classic block types the intake
# announce depends on, so a regression that flattens or reorders them is caught.
BLOCKS_FIXTURE_JSON='[
  {"type":"header","text":{"type":"plain_text","text":"Wave 1","emoji":true}},
  {"type":"context","elements":[{"type":"mrkdwn","text":"ctx"}]},
  {"type":"divider"},
  {"type":"section","text":{"type":"mrkdwn","text":"tail"}}
]'

# Case 8 — default layout: --text alone is exactly one section.
test_slack_post_default_block_structure() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "body" 2>&1)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.blocks | length')" "default: exactly 1 block"
  assert_eq "section" "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "default: block types"
}

# Case 8b — --title layout: header then section, in that order.
test_slack_post_title_block_structure() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --title "T" --text "body" 2>&1)
  assert_eq "2" "$(printf '%s' "$out" | jq -r '.blocks | length')" "title: exactly 2 blocks"
  assert_eq "header,section" "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "title: header then section"
}

# Case 8c — --blocks <path>: the array reaches the body VERBATIM (count + order).
test_slack_post_blocks_from_file() {
  local f="$TMP/blocks.json" out
  printf '%s' "$BLOCKS_FIXTURE_JSON" > "$f"
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks "$f" 2>&1)
  assert_eq "4" "$(printf '%s' "$out" | jq -r '.blocks | length')" "blocks file: all 4 blocks survive"
  assert_eq "header,context,divider,section" \
    "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "blocks file: type order preserved"
  assert_eq "$(printf '%s' "$BLOCKS_FIXTURE_JSON" | jq -Sc .)" \
    "$(printf '%s' "$out" | jq -Sc '.blocks')" "blocks file: byte-identical pass-through"
}

# Case 8d — --blocks - reads the array from stdin.
test_slack_post_blocks_from_stdin() {
  local out
  out=$(printf '%s' "$BLOCKS_FIXTURE_JSON" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - 2>&1)
  assert_eq "header,context,divider,section" \
    "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "blocks stdin: type order preserved"
}

# Case 8e — the {"blocks":[…]} envelope (what Block Kit Builder exports) is accepted.
test_slack_post_blocks_envelope() {
  local out
  out=$(printf '{"blocks":%s}' "$BLOCKS_FIXTURE_JSON" \
    | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - 2>&1)
  assert_eq "4" "$(printf '%s' "$out" | jq -r '.blocks | length')" "blocks envelope: unwrapped to 4 blocks"
}

# Case 8f — with --blocks and no --text, `text` falls back to the layout's first
# string, so the Slack notification is never empty.
test_slack_post_blocks_text_fallback() {
  local out
  out=$(printf '%s' "$BLOCKS_FIXTURE_JSON" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - 2>&1)
  assert_eq "Wave 1" "$(printf '%s' "$out" | jq -r '.text')" "blocks: notification text from first layout string"
}

# Case 8g — --text with --blocks overrides the derived fallback, layout untouched.
test_slack_post_blocks_explicit_text() {
  local out
  out=$(printf '%s' "$BLOCKS_FIXTURE_JSON" \
    | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - --text "mine" 2>&1)
  assert_eq "mine" "$(printf '%s' "$out" | jq -r '.text')" "blocks + --text: explicit text wins"
  assert_eq "4" "$(printf '%s' "$out" | jq -r '.blocks | length')" "blocks + --text: layout unchanged"
}

# Case 8h — --blocks and --title are mutually exclusive (one builds, one supplies).
test_slack_post_blocks_title_conflict() {
  local rc out
  out=$(printf '%s' "$BLOCKS_FIXTURE_JSON" \
    | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - --title "T" 2>&1)
  rc=$?
  assert_eq "1" "$rc" "--blocks + --title → exit 1"
  assert_contains "mutually exclusive" "$out" "--blocks + --title → explains why"
}

# Case 8i — a non-layout payload is refused rather than posted for Slack to reject.
test_slack_post_blocks_bad_shape() {
  local rc
  printf '%s' '{"not":"blocks"}' | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - >/dev/null 2>&1
  rc=$?
  assert_eq "1" "$rc" "--blocks with a non-array/non-envelope → exit 1"
}

# Case 8j — a missing --blocks file is named, not silently ignored.
test_slack_post_blocks_missing_file() {
  local rc out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks "$TMP/nope.json" 2>&1)
  rc=$?
  assert_eq "1" "$rc" "--blocks with a missing file → exit 1"
  assert_contains "not found" "$out" "--blocks missing file → names the path"
}

# Case 8k — the layout survives to the WIRE, not just to --dry-run.
test_slack_post_blocks_reach_the_wire() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"7.7"}'
  printf '%s' "$BLOCKS_FIXTURE_JSON" | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --blocks - >/dev/null 2>&1
  local sent; sent=$(cat "$MOCK_CURL_STDIN" 2>/dev/null)
  assert_eq "header,context,divider,section" \
    "$(printf '%s' "$sent" | jq -r '[.blocks[].type] | join(",")')" "wire: block types as sent to Slack"
}

run_discovered_tests
