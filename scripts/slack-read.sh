#!/bin/bash
# slack-read.sh — engine slack-read: read Slack messages as JSON, with their
# attachments. Two modes, one transport; the caller interprets them (knows
# nothing about intake).
#
# The read counterpart to `engine slack-post`.
#
#   THREAD  (default) — the human replies on one thread (conversations.replies).
#   HISTORY (--history) — a channel's messages within a time window
#                         (conversations.history, bounded by --lookback/--oldest).
#   A DIFFERENT query shape, not a preference: a thread read is one announce's
#   replies; a history read is channel-wide team discussion over a window.
#
# Usage:
#   engine slack-read --channel <#name> --thread-ts <ts> [--since <ts>]
#                     [--max-file-bytes <n>] [--env-file <path>] [--raw]
#   engine slack-read --history --channel <#name> [--lookback <Nd|Nh>] [--oldest <ts>]
#                     [--max-file-bytes <n>] [--env-file <path>] [--raw]
#     --lookback        window as a duration (Nd/Nh/Nm/Ns); oldest = now - lookback. Default 7d.
#     --oldest          explicit epoch lower bound; overrides --lookback.
#     --max-file-bytes  skip attachments larger than this. Default 26214400 (25MiB);
#                       0 disables downloading entirely (metadata still returned).
#     --raw             no side-trips: no author-name lookup and no downloads. File
#                       METADATA is still returned, so "does this reply have a
#                       screenshot?" is answerable without fetching anything.
#     --history and --thread-ts are mutually exclusive.
#
# Out (stdout, JSON):
#   thread:  {ok, channel, mode:"thread",  thread_ts, download_dir?, count, replies:[<message>]}
#   history: {ok, channel, mode:"history", oldest,    download_dir?, count, messages:[<message>]}
#
#   <message> = {ts, user_id, user_name, text, files?}
#     `files` is OMITTED when the message has no attachments, so a text-only read
#     prints exactly what this command printed before attachments existed. Read it
#     as `(.files // [])`.
#
#   <file> = {id, name, title?, mimetype, filetype, size, permalink, url_private,
#             local_path | download_error}
#     local_path      the bytes, already on THIS machine — hand it straight to
#                     whatever reads files. Present iff the download succeeded.
#     download_error  why it did not. Present iff local_path is absent. The
#                     metadata and the permalink are still there either way, so a
#                     caller can always tell that an attachment EXISTS and open it
#                     in Slack. Exactly one of the two is present outside --raw.
#
#   download_dir  the per-run temp directory the bytes landed in. Present only when
#                 the read actually contained an attachment. It is NEVER cleaned up:
#                 a caller holds local_path and may read it much later, so deleting
#                 on exit would break the one thing local_path is for. The OS reaps
#                 /tmp on reboot. On a long-lived machine running many reads, these
#                 accumulate — that is the accepted cost, not an oversight.
#
# What it drops, and why:
#   * the PARENT message (ts == thread_ts) — it is the announce, not a reply
#   * anything the bot itself authored — own-message exclusion is a real author
#     check here (the bot has its own user id), unlike the Linear side which
#     must match marker prefixes because every skill post lands under the
#     operator's human identity. Do NOT port the marker rule here: it is weaker
#     AND it would drop genuine human replies that happen to start with a marker.
#   * anything carrying a bot_id — which also hides a file shared by an app. That
#     is a known blind spot, not a decision about files.
#
# What it does NOT bound: the NUMBER of attachments in one read. Each file is
# capped by --max-file-bytes; a wide --lookback over a busy channel can still
# fetch many of them. A total-bytes budget would make two runs of the same
# command disagree about what they downloaded, which is worse.
#
# Exit: 0 iff the read SUCCEEDED — including when the thread has no replies, and
#       including when an attachment could not be downloaded. A read that could not
#       happen must never be indistinguishable from a thread with nothing in it;
#       that is the difference between "nobody answered" and "we went deaf". A FILE
#       that could not be fetched is a different thing: the text is the primary
#       payload and always gets through, so the file is marked, not fatal.
#       Non-zero with the reason on stderr when the READ failed.
#
# Scopes: channels:history (public) / groups:history (private) + channels:read
#         for name resolution + users:read for author names. files:read is
#         OPTIONAL: without it attachments still appear with their metadata and
#         permalink, but the bytes cannot be fetched and every file carries a
#         download_error (one stderr warning says so). The bot must be a MEMBER of
#         the channel — reads have no public-channel exemption the way
#         chat:write.public gives posting one. `slack-post --verify` checks all of
#         this, warns on a missing files:read, and self-joins where it can.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/slack-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/slack-lib.sh"
else
  echo "slack-read: missing required $SCRIPT_DIR/slack-lib.sh" >&2; exit 1
fi

die() { echo "slack-read: $1" >&2; exit 1; }

usage() {
  sed -n '2,/^set /p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
  exit "${1:-0}"
}

channel=""; thread_ts=""; since=""; env_file="./.env.local"; raw=0
env_file_arg=""            # set only by an EXPLICIT --env-file — then that file is authoritative
history=0; lookback=""; oldest=""
max_file_bytes=26214400    # 25MiB. Big enough for any screenshot or PDF, small enough
                           # that one screen recording cannot stall a wave. 0 disables.

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)   channel="${2:-}"; shift 2 ;;
    --thread-ts) thread_ts="${2:-}"; shift 2 ;;
    --since)     since="${2:-}"; shift 2 ;;
    --history)   history=1; shift ;;
    --lookback)  lookback="${2:-}"; shift 2 ;;
    --oldest)    oldest="${2:-}"; shift 2 ;;
    --env-file)  env_file="${2:-}"; env_file_arg="$env_file"; shift 2 ;;
    --raw)       raw=1; shift ;;
    --max-file-bytes) max_file_bytes="${2:-}"; shift 2 ;;
    -h|--help)   usage 0 ;;
    *)           die "unknown argument: $1 (see --help)" ;;
  esac
done

# Parse a duration (Nd / Nh / Nm / Ns, or bare seconds) to seconds. Portable:
# we do epoch arithmetic against `date +%s` (universal), NEVER a relative-date
# string (`date -v` BSD vs `date -d` GNU) — so there is no date-flavor to detect.
duration_seconds() {
  local d="$1" n unit
  case "$d" in
    *[!0-9dhms]* ) return 1 ;;
    *d) n="${d%d}"; unit=86400 ;;
    *h) n="${d%h}"; unit=3600 ;;
    *m) n="${d%m}"; unit=60 ;;
    *s) n="${d%s}"; unit=1 ;;
    *)  n="$d";     unit=1 ;;
  esac
  [ -n "$n" ] || return 1
  printf '%s' "$(( n * unit ))"
}

case "$max_file_bytes" in *[!0-9]* | "") die "bad --max-file-bytes '$max_file_bytes' (whole bytes, or 0 to disable downloading)" ;; esac

# A Slack filename reaches a shell: 6 of 22 real names in one channel carried spaces,
# and the largest carried parentheses too. Everything outside [A-Za-z0-9._-] becomes a
# dash; runs collapse; leading/trailing dashes go. The extension is kept so a reader
# (and anything detecting type by suffix) still sees a .png as a .png.
sanitize_name() {
  local n="$1" base ext
  case "$n" in
    *.*) ext=".${n##*.}"; base="${n%.*}" ;;
    *)   ext="";          base="$n"      ;;
  esac
  base=$(printf '%s' "$base" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-' | sed -E 's/-+/-/g; s/^-+//; s/-+$//' | cut -c1-120)
  ext=$(printf '%s' "$ext" | LC_ALL=C tr -cd 'A-Za-z0-9.')
  [ -n "$base" ] || base="file"
  printf '%s%s' "$base" "$ext"
}

channel="${channel:-${SLACK_INTAKE_CHANNEL:-}}"
[ -n "$channel" ] || die "channel required (--channel '#name' or an exported \$SLACK_INTAKE_CHANNEL)"

if [ "$history" -eq 1 ]; then
  # Channel-wide, window-bounded read — a DIFFERENT query shape than the thread
  # read, sharing only the transport. See skills/intake/INTAKE_SYSTEM.md.
  [ -z "$thread_ts" ] || die "--history and --thread-ts are mutually exclusive (channel-history vs a single thread)"
  if [ -z "$oldest" ]; then
    [ -n "$lookback" ] || lookback="7d"   # matches SLACK_INTAKE_CONTEXT_LOOKBACK_DAYS default
    secs="$(duration_seconds "$lookback")" || die "bad --lookback '$lookback' (use Nd / Nh / Nm / Ns, e.g. 7d)"
    oldest=$(( $(date +%s) - secs ))
  fi
  case "$oldest" in *[!0-9]* | "") die "bad --oldest '$oldest' (epoch seconds)" ;; esac
else
  [ -n "$thread_ts" ] || die "--thread-ts required (the parent message ts — a thread's thread_ts IS its parent's ts). For a channel-wide window use --history."
fi

token="$(slack_token "$env_file_arg")" \
  || die "no Slack token (set \$SLACK_INTAKE_TOKEN or add it to $env_file)"

ch_id="$(resolve_channel "$token" "$channel")" \
  || die "channel '$channel' not found — a renamed or archived channel will not resolve, which is deliberate"
ch_name="$(channel_name "$token" "$ch_id")"

# Who are we? Needed to exclude our own messages by author.
me=$(curl -sS -H "Authorization: Bearer $token" "https://slack.com/api/auth.test" 2>/dev/null \
     | jq -r '.user_id // empty' 2>/dev/null)
[ -n "$me" ] || die "auth.test failed — token invalid or Slack unreachable"

# --- fetch, following cursors (both a long thread and a wide window paginate) ---
if [ "$history" -eq 1 ]; then
  endpoint="conversations.history"
  base_url="https://slack.com/api/conversations.history?channel=$ch_id&oldest=$oldest&limit=200"
else
  endpoint="conversations.replies"
  base_url="https://slack.com/api/conversations.replies?channel=$ch_id&ts=$thread_ts&limit=200"
fi
acc=$(mktemp) || die "mktemp failed"
echo '[]' > "$acc"
cursor=""
while :; do
  resp=$(curl -sS -H "Authorization: Bearer $token" \
    "${base_url}${cursor:+&cursor=$cursor}" 2>/dev/null)
  if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)" != "true" ]; then
    err=$(printf '%s' "$resp" | jq -r '.error // "unreachable"' 2>/dev/null)
    rm -f "$acc"
    case "$err" in
      not_in_channel) die "cannot read $ch_name — the bot is not a member. Run: engine slack-post --verify --channel '$channel'" ;;
      missing_scope)  die "cannot read $ch_name — missing scope (needs channels:history / groups:history)" ;;
      thread_not_found) die "no thread at ts $thread_ts in $ch_name — check the announce ts" ;;
      *) die "$endpoint failed: $err" ;;
    esac
  fi
  printf '%s' "$resp" | jq --slurpfile a "$acc" '$a[0] + (.messages // [])' > "$acc.tmp" && mv "$acc.tmp" "$acc"
  cursor=$(printf '%s' "$resp" | jq -r '.response_metadata.next_cursor // empty' 2>/dev/null)
  [ -n "$cursor" ] || break
done

# --- filter: drop the parent and anything we authored; apply --since ---
# `kept` holds the surviving messages UNCURATED — the download step needs keys
# (file_access, url_private_download) that never reach the output.
kept=$(jq --arg parent "$thread_ts" --arg me "$me" --arg since "$since" '
  map(select(.ts != $parent))
  | map(select((.user // "") != $me))
  | map(select(has("bot_id") | not))
  | (if $since == "" then . else map(select((.ts|tonumber) > ($since|tonumber))) end)
' "$acc")
rm -f "$acc"

# --- curate: the public message shape, plus files when the message has any ---
# `files` is OMITTED when a message has none, so a text-only read is byte-identical
# to what this command printed before attachments existed. Callers use (.files // []).
filtered=$(printf '%s' "$kept" | jq '
  map(
    {ts, user_id: (.user // ""), text: (.text // "")}
    + (if ((.files // []) | length) > 0 then
         {files: [ (.files // [])[] |
           {id, name, mimetype, filetype, size, permalink, url_private}
           + (if (.title // "") == "" or .title == .name then {} else {title} end) ]}
       else {} end)
  )
')

# --raw means "no side-trips": no downloads and no name resolution. Metadata still
# shows, so a caller who only needs to know an attachment exists pays for nothing.
if [ "$raw" -eq 1 ]; then printf '%s\n' "$filtered"; exit 0; fi

# --- download the attachments (once per DISTINCT file id) ------------------
# A read that could not happen is fatal (see Exit, above); a FILE that could not be
# fetched is not. The message text is the primary payload and always gets through —
# an unfetchable file keeps its metadata and permalink and gains a download_error.
download_dir=""
if [ "$(printf '%s' "$kept" | jq '[ .[] | (.files // [])[] ] | length')" -gt 0 ]; then
  _tmproot="${TMPDIR:-/tmp}"; _tmproot="${_tmproot%/}"   # macOS exports TMPDIR with a trailing slash
  download_dir=$(mktemp -d "$_tmproot/slack-read.XXXXXX") || die "mktemp -d failed"
  dl_results=$(mktemp) || die "mktemp failed"
  # Results go to a FILE: the loop below runs in a pipeline subshell, so a shell
  # variable set here would be discarded. See scripts/.directives/PITFALLS.md.
  printf '%s' "$kept" | jq -r '
    [ .[] | (.files // [])[] ]
    | unique_by(.id)
    | .[]
    | [ (.id // ""), ((.size // -1) | tostring), (.file_access // "visible"),
        (.url_private_download // .url_private // ""), (.name // .id // "file") ]
    | @tsv
  ' | while IFS=$(printf '\t') read -r fid fsize faccess furl fname; do
    [ -n "$fid" ] || continue
    err=""
    if [ "$max_file_bytes" -eq 0 ]; then
      err="downloading disabled (--max-file-bytes 0)"
    elif [ "$faccess" != "visible" ]; then
      err="not accessible (file_access=$faccess)"
    elif [ "$fsize" = "-1" ]; then
      err="no size declared"
    elif [ "$fsize" -gt "$max_file_bytes" ]; then
      err="exceeds size limit ($(( fsize / 1048576 ))MB > $(( max_file_bytes / 1048576 ))MB)"
    elif [ -z "$furl" ]; then
      err="no download url"
    else
      dest="$download_dir/${fid}-$(sanitize_name "$fname")"
      code=$(curl -sS -L -o "$dest" -w '%{http_code}' \
             -H "Authorization: Bearer $token" "$furl" 2>/dev/null)
      if [ "$code" != "200" ]; then
        rm -f "$dest"; err="download failed (http ${code:-none})"
      else
        got=$(wc -c < "$dest" | tr -d ' ')
        # BOTH checks, and neither is redundant. An unauthorised url_private answers
        # 302 to a small HTML page, so with -L the fetch is a *successful* 200 whose
        # body is an error page. Only the byte count against Slack's declared size
        # tells the two apart. Drop either check and that page ships as a .png.
        if [ "$got" != "$fsize" ]; then
          rm -f "$dest"; err="download truncated ($got of $fsize bytes)"
        fi
      fi
    fi
    if [ -n "$err" ]; then
      jq -n --arg id "$fid" --arg e "$err" '{id: $id, download_error: $e}' >> "$dl_results"
    else
      jq -n --arg id "$fid" --arg p "$dest" '{id: $id, local_path: $p}' >> "$dl_results"
    fi
  done

  dl_map=$(jq -s 'INDEX(.id)' "$dl_results" 2>/dev/null) || dl_map='{}'
  [ -n "$dl_map" ] || dl_map='{}'
  filtered=$(printf '%s' "$filtered" | jq --argjson m "$dl_map" '
    map(if has("files") then .files |= map(. + (($m[.id] // {}) | del(.id))) else . end)
  ')

  # One line, once, when EVERY attachment failed for an access-shaped reason — the
  # signature of a missing files:read scope. Loud enough to find, never fatal.
  dl_total=$(jq -s 'length' "$dl_results" 2>/dev/null || echo 0)
  dl_denied=$(jq -s '[ .[] | select((.download_error // "") | test("file_access|http 40[13]")) ] | length' \
              "$dl_results" 2>/dev/null || echo 0)
  if [ "${dl_total:-0}" -gt 0 ] && [ "${dl_denied:-0}" -eq "${dl_total:-0}" ]; then
    echo "slack-read: none of the $dl_total attachment(s) could be downloaded — the app may be missing the files:read scope. Metadata and permalinks are still present." >&2
  fi
  rm -f "$dl_results"
fi

# --- resolve author ids to real names (one call per DISTINCT author) ---
names='{}'
for uid in $(printf '%s' "$filtered" | jq -r '[.[].user_id] | unique | .[]' 2>/dev/null); do
  [ -n "$uid" ] || continue
  nm=$(curl -sS -H "Authorization: Bearer $token" "https://slack.com/api/users.info?user=$uid" 2>/dev/null \
       | jq -r '.user.real_name // .user.profile.display_name // empty' 2>/dev/null)
  [ -n "$nm" ] || nm="$uid"
  names=$(printf '%s' "$names" | jq --arg u "$uid" --arg n "$nm" '. + {($u): $n}')
done

if [ "$history" -eq 1 ]; then
  jq -n --argjson msgs "$filtered" --argjson names "$names" \
        --arg ch "$ch_name" --argjson oldest "$oldest" --arg dir "$download_dir" '
    {ok: true, channel: $ch, mode: "history", oldest: $oldest}
    + (if $dir == "" then {} else {download_dir: $dir} end)
    + {count: ($msgs | length),
       messages: ($msgs | map(. + {user_name: ($names[.user_id] // .user_id)}))}
  '
else
  jq -n --argjson replies "$filtered" --argjson names "$names" \
        --arg ch "$ch_name" --arg ts "$thread_ts" --arg dir "$download_dir" '
    {ok: true, channel: $ch, mode: "thread", thread_ts: $ts}
    + (if $dir == "" then {} else {download_dir: $dir} end)
    + {count: ($replies | length),
       replies: ($replies | map(. + {user_name: ($names[.user_id] // .user_id)}))}
  '
fi
