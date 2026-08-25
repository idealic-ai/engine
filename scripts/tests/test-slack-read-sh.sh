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
  export TMPDIR="$TMP"   # so the script's mktemp -d download dir is reaped by teardown
  # Per-endpoint canned responses (tests override as needed).
  export MOCK_AUTH_RESPONSE='{"ok":true,"user_id":"UBOT"}'
  export MOCK_LIST_RESPONSE='{"ok":true,"channels":[{"name":"intake","id":"C123"}]}'
  export MOCK_INFO_RESPONSE='{"ok":true,"channel":{"name":"intake"}}'
  export MOCK_USERS_RESPONSE='{"ok":true,"user":{"real_name":"Alice"}}'
  # A 3-message window: own-bot message, a bot_id (webhook) message, one real human.
  export MOCK_HISTORY_RESPONSE='{"ok":true,"has_more":false,"messages":[{"ts":"100.1","user":"UBOT","text":"i am the bot"},{"ts":"100.2","bot_id":"B1","user":"U9","text":"webhook noise"},{"ts":"100.3","user":"UALICE","text":"real human context"}]}'
  export MOCK_REPLIES_RESPONSE='{"ok":true,"messages":[{"ts":"90.0","user":"UOP","text":"the announce parent"},{"ts":"91.1","user":"UALICE","text":"a human reply"}]}'
  # --- File fixtures. Names, sizes and file_access values are copied VERBATIM from a
  # live conversations.history capture (see the session's evidence/live-file-shapes.json):
  # 6 of 22 real names carry spaces, the largest real file is a 317264622-byte .mov, and
  # every real in-message entry carries file_access:"visible". The noise keys (thumb_360,
  # pretty_type, url_private_download) are here so curation is proved to DROP them.
  # One deliberate deviation: `size` on the downloadable fixtures is small enough to serve
  # from an env var. The real one is 2232370; the byte-count check needs body length ==
  # size, and a 2MB env var buys nothing the name shape does not already give us.
  export MOCK_FILE_PNG='{"id":"F0BT7DT5UHE","name":"Screenshot 2026-08-24 at 2.48.13 PM.png","title":"Screenshot 2026-08-24 at 2.48.13 PM.png","mimetype":"image/png","filetype":"png","pretty_type":"PNG","size":4096,"mode":"hosted","file_access":"visible","permalink":"https://finchclaims.slack.com/files/UALICE/F0BT7DT5UHE/screenshot.png","url_private":"https://files.slack.com/files-pri/T1-F0BT7DT5UHE/screenshot.png","url_private_download":"https://files.slack.com/files-pri/T1-F0BT7DT5UHE/download/screenshot.png","thumb_360":"https://files.slack.com/thumb360","user":"UALICE"}'
  export MOCK_FILE_JPEG='{"id":"F0BT7C2BQ72","name":"3BABF0DE-A0A9-44B1-8F4C-B258F8153D7F_1_102_o.jpeg","title":"3BABF0DE-A0A9-44B1-8F4C-B258F8153D7F_1_102_o.jpeg","mimetype":"image/jpeg","filetype":"jpg","size":4096,"mode":"hosted","file_access":"visible","permalink":"https://finchclaims.slack.com/files/UALICE/F0BT7C2BQ72/img.jpeg","url_private":"https://files.slack.com/files-pri/T1-F0BT7C2BQ72/img.jpeg","url_private_download":"https://files.slack.com/files-pri/T1-F0BT7C2BQ72/download/img.jpeg"}'
  export MOCK_FILE_HUGE='{"id":"F0BTHUGEMOV","name":"0824 (2)(1).mov","mimetype":"video/quicktime","filetype":"mov","size":317264622,"mode":"hosted","file_access":"visible","permalink":"https://finchclaims.slack.com/files/UALICE/F0BTHUGEMOV/0824.mov","url_private":"https://files.slack.com/files-pri/T1-F0BTHUGEMOV/0824.mov","url_private_download":"https://files.slack.com/files-pri/T1-F0BTHUGEMOV/download/0824.mov"}'
  export MOCK_FILE_LOCKED='{"id":"F0BTLOCKED1","name":"connect-shared.pdf","mimetype":"application/pdf","filetype":"pdf","size":4096,"mode":"hosted","file_access":"check_file_info","permalink":"https://finchclaims.slack.com/files/UALICE/F0BTLOCKED1/connect.pdf"}'
  # The file-download branch: body served from files.slack.com, with its HTTP code.
  export MOCK_DOWNLOAD_BODY='PNGBYTES'
  export MOCK_DOWNLOAD_CODE='200'
  cat > "$MOCK_BIN/curl" <<'STUB'
#!/bin/bash
# mock curl: record argv, branch canned Slack JSON on the endpoint in the URL.
# Honours -o <path> and -w <format> so the file-download path is testable; the
# API branches keep writing to stdout, which is how slack-read reads them.
# It does NOT model -L: a redirect is a real-curl behaviour the live smoke covers.
printf '%s\n' "$*" >> "$MOCK_CURL_ARGS"
_out=""; _wfmt=""; _prev=""
for _a in "$@"; do
  case "$_prev" in
    -o|--output)    _out="$_a" ;;
    -w|--write-out) _wfmt="$_a" ;;
  esac
  _prev="$_a"
done
_emit() { # $1 body, $2 http code
  if [ -n "$_out" ]; then printf '%s' "$1" > "$_out"; else printf '%s' "$1"; fi
  [ -n "$_wfmt" ] && printf '%s' "$_wfmt" | sed "s/%{http_code}/$2/g"
  return 0
}
case "$*" in
  *files.slack.com*)       _emit "${MOCK_DOWNLOAD_BODY-}" "${MOCK_DOWNLOAD_CODE:-200}" ;;
  *auth.test*)             _emit "$MOCK_AUTH_RESPONSE" 200 ;;
  *conversations.list*)    _emit "$MOCK_LIST_RESPONSE" 200 ;;
  *conversations.info*)    _emit "$MOCK_INFO_RESPONSE" 200 ;;
  *conversations.history*) _emit "$MOCK_HISTORY_RESPONSE" 200 ;;
  *conversations.replies*) _emit "$MOCK_REPLIES_RESPONSE" 200 ;;
  *users.info*)            _emit "$MOCK_USERS_RESPONSE" 200 ;;
  *)                       _emit '{"ok":false,"error":"unexpected_endpoint"}' 404 ;;
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
        MOCK_USERS_RESPONSE MOCK_HISTORY_RESPONSE MOCK_REPLIES_RESPONSE \
        MOCK_DOWNLOAD_BODY MOCK_DOWNLOAD_CODE
}

# --- File-fixture helpers -----------------------------------------------------
# A thread whose single human reply carries the given file objects.
replies_with_files() {
  local files="$1" text="${2-a human reply}"
  printf '{"ok":true,"messages":[{"ts":"90.0","user":"UOP","text":"the announce parent"},{"ts":"91.1","user":"UALICE","text":%s,"files":[%s]}]}' \
    "$(printf '%s' "$text" | jq -Rs .)" "$files"
}
# A channel window whose single human message carries the given file objects.
history_with_files() {
  local files="$1" text="${2-real human context}"
  printf '{"ok":true,"has_more":false,"messages":[{"ts":"100.3","user":"UALICE","text":%s,"files":[%s]}]}' \
    "$(printf '%s' "$text" | jq -Rs .)" "$files"
}
# N bytes of predictable filler, for a body whose length must equal a declared size.
mock_bytes() { head -c "$1" /dev/zero | tr '\0' 'x'; }
# Every recorded curl argv line, as one blob.
all_argv() { cat "$MOCK_CURL_ARGS" 2>/dev/null; }

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

# --- Case 8 — --raw short-circuits to a filtered array and takes NO side-trips.
# Widened from "no users.info" once --raw also gained a download to skip: the flag's
# meaning is "no extra network round-trips", and the assertion should say that.
test_history_raw() {
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --lookback 7d --raw 2>/dev/null)
  assert_eq "array" "$(printf '%s' "$out" | jq -r 'type')" "--raw → a bare array"
  assert_eq "1" "$(printf '%s' "$out" | jq -r 'length')" "--raw → filtered (own+bot dropped)"
  assert_not_contains "users.info" "$(cat "$MOCK_CURL_ARGS")" "--raw → no name-resolution call"
  assert_not_contains "files.slack.com" "$(cat "$MOCK_CURL_ARGS")" "--raw → no file download either"
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

# --- Case 19 — a text-only read is byte-identical to the pre-change output.
# The expected JSON below was captured from the UNMODIFIED script before the file
# mapper existed. It is the backward-compatibility pin: a message with no
# attachments must gain no keys, and the envelope must gain no download_dir.
test_textonly_output_unchanged() {
  local out expected
  expected='{"channel":"#intake","count":1,"messages":[{"text":"real human context","ts":"100.3","user_id":"UALICE","user_name":"Alice"}],"mode":"history","ok":true,"oldest":1}'
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --oldest 1 2>/dev/null | jq -S -c .)
  assert_eq "$expected" "$out" "text-only history output is byte-identical to pre-change"

  expected='{"channel":"#intake","count":1,"mode":"thread","ok":true,"replies":[{"text":"a human reply","ts":"91.1","user_id":"UALICE","user_name":"Alice"}],"thread_ts":"90.0"}'
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null | jq -S -c .)
  assert_eq "$expected" "$out" "text-only thread output is byte-identical to pre-change"
}

# --- Case 10 — a reply carrying a file surfaces it, curated to the ten keys.
test_thread_file_metadata_surfaced() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.replies[0].files | length')" "the reply carries one file"
  assert_eq "F0BT7DT5UHE" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].id')" "file id surfaced"
  assert_eq "Screenshot 2026-08-24 at 2.48.13 PM.png" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].name')" "real name preserved verbatim"
  assert_eq "image/png" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].mimetype')" "mimetype surfaced"
  assert_eq "4096" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].size')" "size surfaced"
  assert_eq "https://finchclaims.slack.com/files/UALICE/F0BT7DT5UHE/screenshot.png" \
    "$(printf '%s' "$out" | jq -r '.replies[0].files[0].permalink')" "permalink surfaced"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].thumb_360')" "noise key thumb_360 dropped"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].pretty_type')" "noise key pretty_type dropped"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].file_access')" "internal key file_access dropped"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].url_private_download')" "internal key url_private_download dropped"
}

# --- Case 11 — the empty-looking message. A file-only reply (text "") must survive
# the filter AND carry its file. This is the reported defect: today it returns as
# {ts, user_id, user_name, text:""} — a reply that looks like nothing was said.
test_file_only_message_is_not_empty() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_JPEG" "")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.count')" "the file-only reply survives the filter"
  assert_eq "" "$(printf '%s' "$out" | jq -r '.replies[0].text')" "its text really is empty"
  assert_eq "3BABF0DE-A0A9-44B1-8F4C-B258F8153D7F_1_102_o.jpeg" \
    "$(printf '%s' "$out" | jq -r '.replies[0].files[0].name')" "and it carries the file that IS the message"
}

# --- Case 18 — --raw shows file metadata and takes no side-trips at all.
test_raw_shows_metadata_downloads_nothing() {
  export MOCK_HISTORY_RESPONSE="$(history_with_files "$MOCK_FILE_PNG")"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --oldest 1 --raw 2>/dev/null)
  assert_eq "array" "$(printf '%s' "$out" | jq -r 'type')" "--raw → a bare array"
  assert_eq "Screenshot 2026-08-24 at 2.48.13 PM.png" "$(printf '%s' "$out" | jq -r '.[0].files[0].name')" "--raw still shows file metadata"
  assert_eq "https://finchclaims.slack.com/files/UALICE/F0BT7DT5UHE/screenshot.png" \
    "$(printf '%s' "$out" | jq -r '.[0].files[0].permalink')" "--raw still shows the permalink"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.[0].files[0].local_path')" "--raw → no local_path"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.[0].files[0].download_error')" "--raw → no download_error either"
  assert_not_contains "files.slack.com" "$(all_argv)" "--raw → no file fetched"
}

# --- Case 20 — history mode surfaces files too; this is not a thread-only feature.
test_history_file_metadata_surfaced() {
  export MOCK_HISTORY_RESPONSE="$(history_with_files "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --oldest 1 2>/dev/null)
  assert_eq "1" "$(printf '%s' "$out" | jq -r '.messages[0].files | length')" "history message carries the file"
  assert_eq "F0BT7DT5UHE" "$(printf '%s' "$out" | jq -r '.messages[0].files[0].id')" "file id surfaced in history mode"
}

# --- Case 21 — download_dir is in the envelope and really exists.
test_download_dir_present() {
  export MOCK_HISTORY_RESPONSE="$(history_with_files "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out dir
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --oldest 1 2>/dev/null)
  dir=$(printf '%s' "$out" | jq -r '.download_dir // ""')
  assert_not_empty "$dir" "envelope carries download_dir"
  assert_dir_exists "$dir" "download_dir exists on disk"
}

# --- Case 12 — the on-disk name is <file-id>-<sanitised-name>, and the file is there.
test_download_sanitised_name() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out path
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  path=$(printf '%s' "$out" | jq -r '.replies[0].files[0].local_path // ""')
  assert_not_empty "$path" "a downloaded file carries local_path"
  assert_eq "F0BT7DT5UHE-Screenshot-2026-08-24-at-2.48.13-PM.png" "$(basename "$path")" \
    "id-prefixed, spaces sanitised, extension preserved"
  assert_file_exists "$path" "the bytes are on disk"
  assert_eq "4096" "$(wc -c < "$path" | tr -d ' ')" "and there are as many of them as Slack declared"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].download_error')" "a downloaded file carries no download_error"
}

# --- Case 13 — a file above the ceiling is skipped WITHOUT being fetched.
test_download_size_cap_skips_before_fetching() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_HUGE")"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  assert_contains "exceeds size limit" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].download_error')" \
    "the 302MB .mov is marked as over the limit"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].local_path')" "no local_path for a skipped file"
  assert_eq "https://finchclaims.slack.com/files/UALICE/F0BTHUGEMOV/0824.mov" \
    "$(printf '%s' "$out" | jq -r '.replies[0].files[0].permalink')" "the permalink survives so a human can still open it"
  assert_not_contains "files.slack.com" "$(all_argv)" "the cap is checked BEFORE the fetch, not after"
}

# --- Case 14 — --max-file-bytes raises the ceiling and the same file downloads.
test_download_max_file_bytes_raises_cap() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "${MOCK_FILE_HUGE//317264622/4096}")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" --max-file-bytes 400000000 2>/dev/null)
  assert_not_empty "$(printf '%s' "$out" | jq -r '.replies[0].files[0].local_path // ""')" "--max-file-bytes lets it through"
  assert_eq "F0BTHUGEMOV-0824-2-1.mov" "$(basename "$(printf '%s' "$out" | jq -r '.replies[0].files[0].local_path')")" \
    "parentheses and spaces both sanitised"
}

# --- Case 15 — --max-file-bytes 0 disables downloading without giving up metadata.
test_download_disabled_by_zero_cap() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_PNG")"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" --max-file-bytes 0 2>/dev/null)
  assert_contains "disabled" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].download_error')" "0 → downloading disabled"
  assert_eq "Screenshot 2026-08-24 at 2.48.13 PM.png" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].name')" "metadata still present"
  assert_eq "Alice" "$(printf '%s' "$out" | jq -r '.replies[0].user_name')" "name resolution still runs"
  assert_not_contains "files.slack.com" "$(all_argv)" "nothing fetched"
}

# --- Case 16 — a 403 marks the file and does NOT fail the read. The text is the
# primary payload: a fetch that could not happen must never cost the message.
test_download_403_marks_but_read_succeeds() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_CODE="403"
  export MOCK_DOWNLOAD_BODY="denied"
  local out rc
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "a failed download does not fail the read"
  assert_eq "a human reply" "$(printf '%s' "$out" | jq -r '.replies[0].text')" "the message text survives"
  assert_contains "403" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].download_error')" "the file is marked with the HTTP code"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].local_path')" "no local_path on a failed fetch"
}

# --- Case 17 — file_access other than "visible" is marked, never fetched.
test_download_file_access_not_visible() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_LOCKED")"
  local out
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  assert_contains "file_access" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].download_error')" \
    "a non-visible file names file_access as the reason"
  assert_not_contains "files.slack.com" "$(all_argv)" "and is never fetched"
}

# --- Case 22 — THE TRAP. An unauthorised url_private answers 302 → a small HTML page,
# so with -L the fetch is a *successful* 200 carrying an error page. Measured against
# live Slack: 142 bytes of text/html. Only the byte count against Slack's declared
# size distinguishes it from the real file. Both checks, or this ships silently.
test_download_wrong_length_is_a_failure() {
  export MOCK_REPLIES_RESPONSE="$(replies_with_files "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_CODE="200"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 142)"
  local out dir
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --channel "#intake" --thread-ts "90.0" 2>/dev/null)
  assert_contains "truncated" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].download_error')" \
    "200 with the wrong byte count is a FAILED download, not a success"
  assert_eq "null" "$(printf '%s' "$out" | jq -r '.replies[0].files[0].local_path')" "no local_path for a wrong-length body"
  dir=$(printf '%s' "$out" | jq -r '.download_dir')
  assert_empty "$(ls -A "$dir" 2>/dev/null)" "and no plausible-looking stray file is left behind"
}

# --- Case 23 — one file shared into two messages downloads once.
test_download_shared_file_fetched_once() {
  export MOCK_HISTORY_RESPONSE="$(printf '{"ok":true,"has_more":false,"messages":[{"ts":"100.3","user":"UALICE","text":"first","files":[%s]},{"ts":"100.4","user":"UALICE","text":"again","files":[%s]}]}' "$MOCK_FILE_PNG" "$MOCK_FILE_PNG")"
  export MOCK_DOWNLOAD_BODY="$(mock_bytes 4096)"
  local out a b n
  out=$(SLACK_INTAKE_TOKEN="xoxb-x" "$SLACK_READ" --history --channel "#intake" --oldest 1 2>/dev/null)
  a=$(printf '%s' "$out" | jq -r '.messages[0].files[0].local_path')
  b=$(printf '%s' "$out" | jq -r '.messages[1].files[0].local_path')
  assert_eq "$a" "$b" "both messages point at the same bytes"
  n=$(grep -c 'files.slack.com' "$MOCK_CURL_ARGS" 2>/dev/null || echo 0)
  assert_eq "1" "$n" "and the file was fetched exactly once"
}

# --- Case 24 (LIVE, env-gated) — the fixtures still match reality.
# Runs only when SLACK_READ_LIVE_CHANNEL is exported and a real token resolves;
# otherwise it prints why it skipped, so a silent absence is never mistaken for
# coverage. Asserts SHAPE, never content — the corpus of a real channel changes
# daily, and a test that asserted what is IN it would be broken by ordinary use.
# This is the only check that can catch Slack changing its payload out from under
# fixtures I copied from it once: an offline suite cannot fail on a key it has
# never seen. See scripts/.directives/PITFALLS.md.
test_zz_live_shape_smoke() {
  export PATH="$ORIG_PATH"          # real curl, real network
  local ch out n
  ch="${SLACK_READ_LIVE_CHANNEL:-}"
  if [ -z "$ch" ]; then
    echo "  SKIP live smoke: export SLACK_READ_LIVE_CHANNEL='#name' (and a resolvable Slack token) to run it"
    return 0
  fi
  out=$("$SLACK_READ" --history --channel "$ch" --lookback 30d 2>/dev/null)
  assert_eq "true" "$(printf '%s' "$out" | jq -r '.ok // false')" "live: the read succeeded"
  n=$(printf '%s' "$out" | jq '[ .messages[]? | select(has("files")) ] | length')
  if [ "${n:-0}" -eq 0 ]; then
    echo "  NOTE live smoke: no attachment in the last 30d of $ch — shape of files[] not exercised"
    return 0
  fi
  assert_not_empty "$(printf '%s' "$out" | jq -r '.download_dir // ""')" "live: download_dir present when files exist"
  assert_eq "true" "$(printf '%s' "$out" | jq '[ .messages[]? | (.files // [])[] |
      (has("id") and has("name") and has("size") and has("permalink")
       and (has("local_path") or has("download_error"))) ] | all')" \
    "live: every file carries the curated keys and exactly one of local_path / download_error"
}

run_discovered_tests
