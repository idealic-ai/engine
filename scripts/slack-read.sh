#!/bin/bash
# slack-read.sh — engine slack-read: read Slack messages as JSON. Two modes,
# one transport; the caller interprets them (knows nothing about intake).
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
#                     [--env-file <path>] [--raw]
#   engine slack-read --history --channel <#name> [--lookback <Nd|Nh>] [--oldest <ts>]
#                     [--env-file <path>] [--raw]
#     --lookback  window as a duration (Nd/Nh/Nm/Ns); oldest = now - lookback. Default 7d.
#     --oldest    explicit epoch lower bound; overrides --lookback.
#     --history and --thread-ts are mutually exclusive.
#
# Out (stdout, JSON):
#   thread:  {ok, channel, mode:"thread",  thread_ts, count, replies:[{ts,user_id,user_name,text}]}
#   history: {ok, channel, mode:"history", oldest,    count, messages:[{ts,user_id,user_name,text}]}
#
# What it drops, and why:
#   * the PARENT message (ts == thread_ts) — it is the announce, not a reply
#   * anything the bot itself authored — own-message exclusion is a real author
#     check here (the bot has its own user id), unlike the Linear side which
#     must match marker prefixes because every skill post lands under the
#     operator's human identity. Do NOT port the marker rule here: it is weaker
#     AND it would drop genuine human replies that happen to start with a marker.
#
# Exit: 0 iff the read SUCCEEDED — including when the thread has no replies.
#       Non-zero with the reason on stderr otherwise. A read that could not
#       happen must never be indistinguishable from a thread with nothing in it;
#       that is the difference between "nobody answered" and "we went deaf".
#
# Scopes: channels:history (public) / groups:history (private) + channels:read
#         for name resolution + users:read for author names. The bot must be a
#         MEMBER of the channel — reads have no public-channel exemption the way
#         chat:write.public gives posting one. `slack-post --verify` checks all
#         of this and self-joins where it can.
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
filtered=$(jq --arg parent "$thread_ts" --arg me "$me" --arg since "$since" '
  map(select(.ts != $parent))
  | map(select((.user // "") != $me))
  | map(select(has("bot_id") | not))
  | (if $since == "" then . else map(select((.ts|tonumber) > ($since|tonumber))) end)
  | map({ts, user_id: (.user // ""), text: (.text // "")})
' "$acc")
rm -f "$acc"

if [ "$raw" -eq 1 ]; then printf '%s\n' "$filtered"; exit 0; fi

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
        --arg ch "$ch_name" --argjson oldest "$oldest" '
    {ok: true, channel: $ch, mode: "history", oldest: $oldest,
     count: ($msgs | length),
     messages: ($msgs | map(. + {user_name: ($names[.user_id] // .user_id)}))}
  '
else
  jq -n --argjson replies "$filtered" --argjson names "$names" \
        --arg ch "$ch_name" --arg ts "$thread_ts" '
    {ok: true, channel: $ch, mode: "thread", thread_ts: $ts,
     count: ($replies | length),
     replies: ($replies | map(. + {user_name: ($names[.user_id] // .user_id)}))}
  '
fi
