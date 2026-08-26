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
# mock curl: record argv + stdin, emit canned Slack JSON. Honours -D <file> by
# writing $MOCK_SCOPES as the x-oauth-scopes header — that header is where
# --verify reads the app's granted scopes from.
#
# stdin is read ONLY for `--data @-`. The suite's own loop is driven from a
# process substitution, so its stdin IS the remaining list of test names: an
# unconditional `cat` swallows that list and every later test vanishes without a
# failure. Every call that has no request body (users.list, conversations.open,
# --verify) hits that path.
#
# The response is routed by ENDPOINT, because one resolution now spans several:
# a directory read, a DM open, and the post. $MOCK_CURL_RESPONSE stays the
# fallback, so every pre-existing case behaves exactly as before.
printf '%s\n' "$*" >> "$MOCK_CURL_ARGS"
case " $* " in *" --data @- "*) cat > "$MOCK_CURL_STDIN" 2>/dev/null || true ;; esac
_prev=""; _url=""
for _a in "$@"; do
  case "$_prev" in -D|--dump-header) printf 'HTTP/1.1 200 OK\r\nx-oauth-scopes: %s\r\n' "${MOCK_SCOPES-}" > "$_a" ;; esac
  case "$_a" in https://slack.com/api/*) _url="$_a" ;; esac
  _prev="$_a"
done
_resp=""
case "$_url" in
  *users.lookupByEmail*) _resp="${MOCK_LOOKUP_EMAIL-}" ;;
  *conversations.open*)  _resp="${MOCK_CONV_OPEN-}" ;;
  *users.list*)
    case " $* " in
      *cursor=*) _resp="${MOCK_USERS_LIST_PAGE2-}" ;;
      *)         _resp="${MOCK_USERS_LIST-}" ;;
    esac ;;
esac
[ -n "$_resp" ] || _resp="${MOCK_CURL_RESPONSE}"
printf '%s' "$_resp"
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
  unset MOCK_CURL_ARGS MOCK_CURL_STDIN MOCK_CURL_RESPONSE MOCK_SCOPES
  unset MOCK_USERS_LIST MOCK_USERS_LIST_PAGE2 MOCK_LOOKUP_EMAIL MOCK_CONV_OPEN
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

# --- --verify reports files:read, and reports it as a WARNING.
# A verifier that failed on a missing files:read would fail every workspace that reads
# Slack and does not care about attachments; one that stayed silent would certify a
# setup whose every attachment comes back undownloadable. Both are the failure mode in
# scripts/.directives/PITFALLS.md — a checker disagreeing with its consumer.
# `< /dev/null` is load-bearing, not tidiness. run_discovered_tests drives its loop
# from a process substitution, so the loop's stdin IS the remaining list of test names.
# --verify reads nothing from stdin, so the mock curl's `cat` would inherit that list,
# swallow it, and silently end the run — every test after this one would vanish without
# a failure. Suites that pipe a message into slack-post never notice.
verify_out() { # $1 = granted scope list
  MOCK_SCOPES="$1" MOCK_CURL_RESPONSE='{"ok":true,"user":"bot","team":"T"}' \
    SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --verify < /dev/null 2>&1
}

test_verify_reports_files_read_granted() {
  local out
  out=$(verify_out "chat:write,channels:history,channels:read,users:read,files:read")
  assert_contains "files:read  granted" "$out" "--verify names files:read when granted"
}

test_verify_warns_on_missing_files_read() {
  local out
  out=$(verify_out "chat:write,channels:history,channels:read,users:read")
  assert_contains "files:read  MISSING" "$out" "--verify names files:read when absent"
  assert_contains "listed but not downloaded" "$out" "and says what is actually lost"
  assert_not_contains "✗ files:read" "$out" "as a warning, not a failure marker"
}

test_verify_files_read_does_not_change_exit_code() {
  local rc_with rc_without
  verify_out "chat:write,channels:history,channels:read,users:read,files:read" >/dev/null 2>&1; rc_with=$?
  verify_out "chat:write,channels:history,channels:read,users:read"            >/dev/null 2>&1; rc_without=$?
  assert_eq "$rc_with" "$rc_without" "a missing files:read leaves the verdict unchanged"
}


# --- --to: posting to a PERSON ------------------------------------------------
# --channel is a place, --to is a person. Everything below is about the second:
# the three resolution tiers, and the fact that an ambiguous query must PRINT
# and STOP rather than pick someone. There is no TTY to ask on.

# A workspace directory covering every case the resolver has to separate:
#   Leo Moura   — unique on 'leo' once the deleted Leo is dropped
#   Rob Coyle   — ambiguous with Robin Vale on 'rob'
#   Robin Vale  — no email, so the candidate row must say so rather than blank
#   Leo Ghost   — DELETED; cannot receive a DM, so it must not create ambiguity
#   buildbot    — no display name, no email
DIRECTORY_JSON='{"ok":true,"members":[
  {"id":"U0AAAAAAAA1","deleted":false,"real_name":"Leonardo Moura","profile":{"display_name":"Leo Moura","real_name":"Leonardo Moura","email":"leonardo@example.com"}},
  {"id":"U0BBBBBBBB2","deleted":false,"real_name":"Rob Coyle","profile":{"display_name":"Rob Coyle","real_name":"Rob Coyle","email":"robcoyle@example.com"}},
  {"id":"U0CCCCCCCC3","deleted":false,"real_name":"Robin Vale","profile":{"display_name":"Robin Vale","real_name":"Robin Vale"}},
  {"id":"U0DDDDDDDD4","deleted":true,"real_name":"Leo Ghost","profile":{"display_name":"Leo Ghost","real_name":"Leo Ghost","email":"ghost@example.com"}},
  {"id":"U0EEEEEEEE5","deleted":false,"is_bot":true,"real_name":"buildbot","profile":{"display_name":"","real_name":"buildbot"}}
]}'

DM_OPEN_JSON='{"ok":true,"channel":{"id":"D0RESOLVED1"}}'

# Resolve + post for real: directory read, DM open, then the message.
# Each mocked endpoint DEFAULTS here and is overridable by the caller — a case
# that wants a failing conversations.open sets MOCK_CONV_OPEN and everything
# else stays on the happy path. Hardcoding them would silently shadow the
# override and leave the case asserting the happy path under a failure name.
to_post() { # $@ = extra slack-post args
  MOCK_USERS_LIST="${MOCK_USERS_LIST:-$DIRECTORY_JSON}" \
  MOCK_LOOKUP_EMAIL="${MOCK_LOOKUP_EMAIL:-}" \
  MOCK_CONV_OPEN="${MOCK_CONV_OPEN:-$DM_OPEN_JSON}" \
  MOCK_CURL_RESPONSE='{"ok":true,"ts":"100.1"}' \
  SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --text "hi" "$@" < /dev/null 2>&1
}

# Case T1 — a U… id is already the answer: no directory search, straight to the DM.
test_to_user_id_skips_the_search() {
  local out rc args
  out=$(to_post --to "U0AAAAAAAA1"); rc=$?
  args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_eq "0" "$rc" "--to <U… id>: exit 0"
  assert_not_contains "users.list" "$args" "--to <U… id>: never searches the directory"
  assert_contains "conversations.open" "$args" "--to <U… id>: opens the DM"
  assert_contains "chat.postMessage" "$args" "--to <U… id>: posts"
}

# Case T1b — the DM channel, not the user id, is what reaches chat.postMessage.
# A user id is not a channel; conversations.open is the step that makes one.
test_to_posts_to_the_opened_dm_channel() {
  to_post --to "U0AAAAAAAA1" >/dev/null 2>&1
  assert_eq "D0RESOLVED1" "$(jq -r '.channel' < "$MOCK_CURL_STDIN" 2>/dev/null)" \
    "--to: the D… channel from conversations.open is what gets posted to"
}

# Case T2 — an email goes to users.lookupByEmail: one hit or none, never ambiguous.
test_to_email_uses_lookup_by_email() {
  local out rc args
  out=$(MOCK_LOOKUP_EMAIL='{"ok":true,"user":{"id":"U0AAAAAAAA1"}}' to_post --to "leonardo@example.com"); rc=$?
  args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_eq "0" "$rc" "--to <email>: exit 0"
  assert_contains "users.lookupByEmail" "$args" "--to <email>: uses users.lookupByEmail"
  assert_not_contains "users.list" "$args" "--to <email>: never falls through to the directory search"
}

# Case T3 — a bare name is a case-insensitive SUBSTRING match, so 'leo' finds Leo Moura.
test_to_bare_name_substring_match() {
  local out rc
  out=$(to_post --to "LEO"); rc=$?
  assert_eq "0" "$rc" "--to leo: exit 0"
  assert_eq "D0RESOLVED1" "$(jq -r '.channel' < "$MOCK_CURL_STDIN" 2>/dev/null)" "--to leo: resolves to a DM"
  assert_contains "users.list" "$(cat "$MOCK_CURL_ARGS" 2>/dev/null)" "--to leo: searched the directory"
}

# Case T3b — a deleted account cannot receive a DM, so it is not a candidate.
# Without this, the deleted Leo would make every 'leo' ambiguous.
test_to_skips_deleted_accounts() {
  local out rc
  out=$(to_post --to "ghost"); rc=$?
  assert_eq "1" "$rc" "--to ghost: a deleted-only match is no match"
  assert_contains "no Slack user matches" "$out" "--to ghost: reported as absent, not ambiguous"
}

# Case T3c — the directory is paged; a person on page 2 is still found.
test_to_pages_the_directory() {
  local out rc
  out=$(MOCK_USERS_LIST='{"ok":true,"members":[],"response_metadata":{"next_cursor":"c2"}}' \
        MOCK_USERS_LIST_PAGE2="$DIRECTORY_JSON" \
        MOCK_CONV_OPEN='{"ok":true,"channel":{"id":"D0RESOLVED1"}}' \
        MOCK_CURL_RESPONSE='{"ok":true,"ts":"1.1"}' \
        SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --text hi --to "leo" < /dev/null 2>&1); rc=$?
  assert_eq "0" "$rc" "--to: follows next_cursor to page 2"
}

# Case T3d — a typed @name is a person, not an email. Without the strip it routes
# to users.lookupByEmail and can never match.
test_to_strips_leading_at() {
  to_post --to "@leo" >/dev/null 2>&1
  local args; args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_contains "users.list" "$args" "--to @leo: searched the directory"
  assert_not_contains "users.lookupByEmail" "$args" "--to @leo: NOT treated as an email"
}

# --- ambiguity is a protocol, not a prompt --------------------------------
# Case T4 — more than one match: print the candidates, post NOTHING, exit non-zero.
test_to_ambiguous_posts_nothing() {
  local out rc args
  out=$(to_post --to "rob"); rc=$?
  args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_eq "1" "$rc" "--to rob: ambiguous → exit 1"
  assert_not_contains "chat.postMessage" "$args" "--to rob: nothing was posted"
  assert_not_contains "conversations.open" "$args" "--to rob: no DM was even opened"
}

# Case T4b — the candidate rows carry what a caller needs to choose, id FIRST:
# the id is what the re-invocation uses, and tier 1 guarantees it resolves.
test_to_ambiguous_candidate_rows() {
  local out
  out=$(to_post --to "rob")
  assert_contains "matches more than one person" "$out" "ambiguous: says why nothing happened"
  assert_contains "USER ID" "$out" "ambiguous: column header names the id"
  assert_contains "U0BBBBBBBB2" "$out" "ambiguous: first candidate id"
  assert_contains "U0CCCCCCCC3" "$out" "ambiguous: second candidate id"
  assert_contains "Rob Coyle" "$out" "ambiguous: display name"
  assert_contains "Robin Vale" "$out" "ambiguous: the other display name"
  assert_contains "robcoyle@example.com" "$out" "ambiguous: email where the token can see it"
  assert_contains "no email visible" "$out" "ambiguous: and marks the column when it cannot"
  assert_contains "lacks users:read.email" "$out" "ambiguous: says the blank may be a scope, not an absent address"
  assert_contains "\-\-to <USER ID>" "$out" "ambiguous: names the re-invocation"
}

# Case T4c — the printed id resolves to exactly one person, so the loop terminates.
test_to_ambiguous_id_resolves_on_reinvoke() {
  local rc
  to_post --to "U0BBBBBBBB2" >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "the id printed by an ambiguous match posts cleanly on re-invoke"
}

# --- "not found" and "could not look" are different failures ---------------
# Case T5 — zero matches: say what was searched and where.
test_to_zero_matches_names_the_search() {
  local out rc
  out=$(to_post --to "zzzznobody"); rc=$?
  assert_eq "1" "$rc" "--to zzzznobody: exit 1"
  assert_contains "no Slack user matches" "$out" "zero match: says nobody matched"
  assert_contains "display name, real name and email local-part" "$out" "zero match: says what was searched"
  assert_contains "users.list" "$out" "zero match: says where it looked"
  assert_contains "The lookup worked" "$out" "zero match: distinguishes itself from a failed lookup"
}

# Case T5b — an email that nobody has reads differently from a name that nobody has.
test_to_zero_matches_email_wording() {
  local out
  out=$(MOCK_LOOKUP_EMAIL='{"ok":false,"error":"users_not_found"}' to_post --to "nobody@example.com")
  assert_contains "no Slack user has the email" "$out" "email zero match: its own wording"
  assert_not_contains "no Slack user matches" "$out" "email zero match: not the directory-search wording"
}

# Case T6 — a MISSING SCOPE is a missing wrapper, not a missing person. Reporting
# the two the same way is how a capability we have becomes one we believe we lack.
test_to_missing_users_read_scope() {
  local out rc
  out=$(MOCK_USERS_LIST='{"ok":false,"error":"missing_scope"}' to_post --to "leo"); rc=$?
  assert_eq "1" "$rc" "missing users:read → exit 1"
  assert_contains "users:read" "$out" "missing scope: names the scope"
  assert_contains "missing scope, not a missing person" "$out" "missing scope: says which failure this is"
  assert_contains "REINSTALL" "$out" "missing scope: says how to fix it"
  assert_not_contains "no Slack user matches" "$out" "missing scope: never renders as absence"
}

# Case T6b — the email tier names ITS scope, which is a different one.
test_to_missing_users_read_email_scope() {
  local out
  out=$(MOCK_LOOKUP_EMAIL='{"ok":false,"error":"missing_scope"}' to_post --to "leonardo@example.com")
  assert_contains "users:read.email" "$out" "missing scope: the email tier names users:read.email"
  assert_not_contains "no Slack user has the email" "$out" "missing scope: never renders as absence"
}

# Case T6c — and so does the DM open, which needs im:write.
test_to_missing_im_write_scope() {
  local out
  out=$(MOCK_CONV_OPEN='{"ok":false,"error":"missing_scope"}' to_post --to "leo")
  assert_contains "im:write" "$out" "conversations.open: names im:write when it is missing"
  assert_contains "cannot open a DM" "$out" "conversations.open: says what failed"
}

# Case T6d — any other conversations.open error surfaces Slack's own word for it.
test_to_open_dm_error_surfaces() {
  local out rc
  out=$(MOCK_CONV_OPEN='{"ok":false,"error":"user_not_found"}' to_post --to "leo"); rc=$?
  assert_eq "1" "$rc" "conversations.open failure → exit 1"
  assert_contains "user_not_found" "$out" "conversations.open failure: surfaces Slack's error"
}

# --- flag hygiene ---------------------------------------------------------
# Case T7 — a place and a person are different questions; asking both is incoherent.
test_to_and_channel_conflict() {
  local out rc
  out=$(printf '%s' m | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --to "leo" 2>&1); rc=$?
  assert_eq "1" "$rc" "--channel + --to → exit 1"
  assert_contains "mutually exclusive" "$out" "--channel + --to → explains why"
}

# Case T7b — a user id handed to --channel used to come back as "channel not
# found", which reads as a Slack restriction and is not one. Redirect instead.
test_channel_with_user_id_redirects() {
  local out rc
  out=$(printf '%s' m | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "U0AAAAAAAA1" 2>&1); rc=$?
  assert_eq "1" "$rc" "--channel <U… id> → exit 1"
  assert_contains "that is a person, not a place" "$out" "--channel <U… id>: names the confusion"
  assert_contains "Use: \-\-to U0AAAAAAAA1" "$out" "--channel <U… id>: names the flag that works"
  assert_not_contains "not found" "$out" "--channel <U… id>: never reported as a missing channel"
}

# Case T7c — resolve_channel itself now RECOGNIZES a U… id rather than hunting for
# a channel by that name. slack-read and --verify share this resolver.
test_resolve_channel_passes_user_ids_through() {
  local out rc
  out=$(bash -c '. "$HOME/.claude/engine/scripts/slack-lib.sh"; resolve_channel tok U0AAAAAAAA1'); rc=$?
  assert_eq "0" "$rc" "resolve_channel: a U… id resolves rather than failing"
  assert_eq "U0AAAAAAAA1" "$out" "resolve_channel: passed through as the id it is"
  assert_file_not_exists "$MOCK_CURL_ARGS" "resolve_channel: no directory call to recognize an id"
}

# Case T7d — trailing --to with no value → named error, no hang.
test_to_empty() {
  local out rc
  out=$(printf '%s' m | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --to 2>&1); rc=$?
  assert_eq "1" "$rc" "trailing --to (no value) → exit 1"
  assert_contains "\-\-to requires a person" "$out" "empty --to → names the flag"
}

# Case T7e — --verify checks a channel's setup; a person has nothing to verify.
test_to_with_verify_conflict() {
  local out rc
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --verify --to "leo" < /dev/null 2>&1); rc=$?
  assert_eq "1" "$rc" "--verify + --to → exit 1"
  assert_contains "nothing to verify about a person" "$out" "--verify + --to → explains why"
}

# Case T7f — --help documents the flag (this header is the script's only docs).
test_to_documented() {
  local out; out=$("$SLACK_POST" --help 2>&1)
  assert_contains "\-\-to <name|email|U…>" "$out" "help: --to is documented in the usage header"
  assert_contains "conversations.open" "$out" "help: says how a person becomes a channel"
}

# Case T8 — --dry-run --to resolves the PERSON but opens no conversation. A dry
# run that created a DM would not be dry.
test_to_dry_run_resolves_without_opening() {
  local out args
  out=$(MOCK_USERS_LIST="$DIRECTORY_JSON" SLACK_INTAKE_TOKEN="xoxb-x" \
        "$SLACK_POST" --dry-run --to "leo" --text "hi" < /dev/null 2>/dev/null)
  args=$(cat "$MOCK_CURL_ARGS" 2>/dev/null)
  assert_eq "U0AAAAAAAA1" "$(printf '%s' "$out" | jq -r '.channel')" "dry-run --to: body carries the resolved user id"
  assert_not_contains "conversations.open" "$args" "dry-run --to: no conversation opened"
  assert_not_contains "chat.postMessage" "$args" "dry-run --to: nothing posted"
}

# Case T8b — and it says on stderr exactly how the real post would differ, so the
# printed body is never mistaken for the one that goes on the wire.
test_to_dry_run_states_the_difference() {
  local err
  err=$(MOCK_USERS_LIST="$DIRECTORY_JSON" SLACK_INTAKE_TOKEN="xoxb-x" \
        "$SLACK_POST" --dry-run --to "leo" --text "hi" < /dev/null 2>&1 >/dev/null)
  assert_contains "U0AAAAAAAA1" "$err" "dry-run --to: names who it resolved to"
  assert_contains "conversations.open" "$err" "dry-run --to: names the step it skipped"
}

# --- the 3000-character section cap ---------------------------------------
# Slack rejects a section over 3000 characters as `invalid_blocks` — an error
# that names the block and never the length, so the cause is not discoverable
# from the failure. Split instead.

rep() { printf "%${2}s" '' | tr ' ' "$1"; }   # rep <char> <count>

# Case C1 — text with NO newlines at all still splits, and no block exceeds the cap.
test_chunker_splits_text_with_no_newlines() {
  local out longtext
  longtext=$(rep x 7000)
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "$longtext" 2>&1)
  assert_eq "3" "$(printf '%s' "$out" | jq -r '.blocks | length')" "7000 chars with no break → 3 sections"
  assert_eq "3000" "$(printf '%s' "$out" | jq -r '[.blocks[].text.text | length] | max')" "no section exceeds 3000"
  assert_eq "section" "$(printf '%s' "$out" | jq -r '[.blocks[].type] | unique | join(",")')" "every block is a section"
}

# Case C1b — splitting must not LOSE text: the pieces rejoin to the original.
test_chunker_is_lossless_on_a_hard_cut() {
  local out longtext
  longtext=$(rep x 7000)
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "$longtext" 2>&1)
  assert_eq "$longtext" "$(printf '%s' "$out" | jq -r '[.blocks[].text.text] | join("")')" \
    "a hard cut rejoins to the original text"
}

# Case C2 — a paragraph boundary is preferred over a mid-word cut, so the split
# lands somewhere a reader can follow.
test_chunker_breaks_on_paragraph_boundaries() {
  local out a b
  a=$(rep a 2500); b=$(rep b 2500)
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" \
        --text "$(printf '%s\n\n%s' "$a" "$b")" 2>&1)
  assert_eq "2" "$(printf '%s' "$out" | jq -r '.blocks | length')" "two paragraphs over the cap → 2 sections"
  assert_eq "$a" "$(printf '%s' "$out" | jq -r '.blocks[0].text.text')" "first section is exactly the first paragraph"
  assert_eq "$b" "$(printf '%s' "$out" | jq -r '.blocks[1].text.text')" "second section is exactly the second paragraph"
}

# Case C2b — a line boundary is the fallback when a single paragraph is too long.
test_chunker_falls_back_to_line_boundaries() {
  local out a b
  a=$(rep a 2500); b=$(rep b 2500)
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" \
        --text "$(printf '%s\n%s' "$a" "$b")" 2>&1)
  assert_eq "2" "$(printf '%s' "$out" | jq -r '.blocks | length')" "one over-cap paragraph → split on its line break"
  assert_eq "$a" "$(printf '%s' "$out" | jq -r '.blocks[0].text.text')" "line split: first section is the first line"
}

# Case C3 — text under the cap is untouched: still exactly one section.
test_chunker_leaves_short_text_alone() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "$(rep y 2999)" 2>&1)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.blocks | length')" "2999 chars → still 1 section"
}

# Case C3b — exactly at the cap is still one section (the boundary is inclusive).
test_chunker_boundary_is_inclusive() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "$(rep y 3000)" 2>&1)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.blocks | length')" "exactly 3000 chars → 1 section"
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --text "$(rep y 3001)" 2>&1)
  assert_eq "2" "$(printf '%s' "$out" | jq -r '.blocks | length')" "3001 chars → 2 sections"
}

# Case C4 — --title keeps ONE header and gains the extra sections after it.
test_chunker_under_title_layout() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --title "T" --text "$(rep x 7000)" 2>&1)
  assert_eq "header,section,section,section" \
    "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "title + long text: one header, three sections"
  assert_eq "3000" "$(printf '%s' "$out" | jq -r '[.blocks[] | select(.type=="section") | .text.text | length] | max')" \
    "title layout: no section exceeds 3000"
}

# Case C5 — --blocks is a caller-supplied layout and is never re-chunked.
# Composing blocks belongs to the caller; re-cutting one would be authoring it.
test_chunker_leaves_caller_blocks_alone() {
  local out
  out=$(jq -n --arg t "$(rep z 5000)" '[{type:"section",text:{type:"mrkdwn",text:$t}}]' \
    | SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --dry-run --channel "C01ABCDEF" --blocks - --text "fallback" 2>&1)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.blocks | length')" "--blocks: an over-cap caller section is passed through untouched"
  assert_eq "5000" "$(printf '%s' "$out" | jq -r '.blocks[0].text.text | length')" "--blocks: length untouched"
}

# Case C6 — the split survives to the WIRE, not just to --dry-run.
test_chunker_reaches_the_wire() {
  export MOCK_CURL_RESPONSE='{"ok":true,"ts":"9.9"}'
  SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_POST" --channel "C01ABCDEF" --text "$(rep x 7000)" >/dev/null 2>&1
  local sent; sent=$(cat "$MOCK_CURL_STDIN" 2>/dev/null)
  assert_eq "3" "$(printf '%s' "$sent" | jq -r '.blocks | length')" "wire: 3 sections as sent to Slack"
  assert_eq "3000" "$(printf '%s' "$sent" | jq -r '[.blocks[].text.text | length] | max')" "wire: no section over the cap"
}

run_discovered_tests
