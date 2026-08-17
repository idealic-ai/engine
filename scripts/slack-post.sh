#!/bin/bash
# slack-post.sh — engine slack-post: post a message to Slack via chat.postMessage
#
# A generic, reusable Slack poster. The caller composes the message; this script
# is a dumb pipe that authenticates and sends. Used by /intake to announce a
# completed grooming wave, but intentionally carries no intake-specific wording.
#
# Usage:
#   engine slack-post [--channel <id|#name>] [--title <text>] [--text <str>] \
#                     [--blocks <path|->] [--env-file <path>] [--update-ts <ts>] [--dry-run]
#   engine slack-post --verify [--channel <id>] [--env-file <path>]
#   (message read from STDIN when --text is omitted)
#
# Layout: by default the poster emits a minimal body — one mrkdwn section, plus a
# header when --title is given. --blocks <path|-> instead sends a caller-supplied
# Block Kit array verbatim; only its shape (a JSON array) is checked, never its
# contents. --blocks and --title are mutually exclusive: --title BUILDS a layout,
# --blocks SUPPLIES one. With --blocks, --text becomes the notification fallback
# (defaulted from the first text in the layout when omitted).
#
# --verify: preflight the setup and report what a human must fix. Runs the
# ladder token -> valid -> scopes -> channel -> membership, and SELF-HEALS
# membership via conversations.join when the channels:join scope is granted.
# Needs no message. Exit 0 iff posting AND reading are both possible.
# This is the only check that touches Slack — --dry-run just prints the body
# it WOULD send, so it cannot detect a bad token, a missing scope, or a
# channel the bot was never invited to.
#
# Post vs edit: without --update-ts it sends chat.postMessage (a new message).
# With --update-ts <ts> it sends chat.update to EDIT the message with that ts
# (channel + ts required). On success the message ts is printed to stdout, so a
# caller can capture the ts of a post and later edit that same message in place.
#
# Auth: bot token, resolved in order —
#   1. $SLACK_INTAKE_TOKEN   2. $SLACK_BOT_TOKEN
#   3. SLACK_INTAKE_TOKEN from ./.env.local, then ./.env — the same chain
#      `engine intake doctor` verifies, so a PASS there means a post here works.
#      An explicit --env-file replaces step 3 entirely: only that file is read, and a
#      miss fails loudly rather than falling through to another workspace's token.
# The token is only ever sent in the Authorization header — never printed to
# stdout/stderr, never included in --dry-run output. --env-file is KEY-EXTRACTED
# via grep/sed, never `source`d (a dotfile can hold arbitrary shell).
#
# Channel: --channel  >  $SLACK_INTAKE_CHANNEL  (required unless --dry-run).
#
# Exit: 0 iff Slack responds {"ok":true}; else 1 with Slack's .error on stderr.
#       --dry-run prints the request body (channel+text, token redacted) and exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# extract_env_key / slack_token / resolve_channel / channel_name are shared with
# slack-read.sh. A REQUIRED dependency gets a real guard — `source … || true`
# looks like one and is not (see PITFALLS §PTF_BASH32_COMPATIBILITY).
if [ -f "$SCRIPT_DIR/slack-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/slack-lib.sh"
else
  echo "slack-post: missing required $SCRIPT_DIR/slack-lib.sh" >&2; exit 1
fi

die() { echo "slack-post: $1" >&2; exit 1; }

usage() {
  sed -n '2,/^set /p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
  exit "${1:-0}"
}

channel=""
title=""
text=""
blocks_src=""
env_file="./.env.local"
env_file_arg=""            # set only by an EXPLICIT --env-file — then that file is authoritative
update_ts=""
dry_run=0
verify=0

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)  channel="${2:-}"; shift 2 ;;
    --title)    title="${2:-}"; shift 2 ;;
    --text)     text="${2:-}"; shift 2 ;;
    --blocks)   blocks_src="${2:-}"; [ -n "$blocks_src" ] || die "--blocks requires a path (or - for stdin)"; shift 2 ;;
    --env-file) env_file="${2:-}"; env_file_arg="$env_file"; shift 2 ;;
    --update-ts) update_ts="${2:-}"; [ -n "$update_ts" ] || die "--update-ts requires a message ts value (got empty/none)"; shift 2 ;;
    --dry-run)  dry_run=1; shift ;;
    --verify)   verify=1; shift ;;
    -h|--help)  usage 0 ;;
    *)          die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$blocks_src" ] && [ -n "$title" ] && \
  die "--blocks and --title are mutually exclusive: --title builds a layout, --blocks supplies one"

# --- verify: preflight the setup, self-heal what can be self-healed ---
# Ordered so each step's failure explains the next one's absence. Runs before
# the message read, because a preflight must not require something to say.
has_scope() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }

run_verify() {
  local tok tok_src="" scopes resp hdr ok err bot team ch ch_src ch_id ch_disp rc=0 joinable=1

  # 1. token — report the SOURCE, never the value
  tok="${SLACK_INTAKE_TOKEN:-}"; [ -n "$tok" ] && tok_src="\$SLACK_INTAKE_TOKEN"
  if [ -z "$tok" ]; then tok="${SLACK_BOT_TOKEN:-}"; [ -n "$tok" ] && tok_src="\$SLACK_BOT_TOKEN"; fi
  if [ -z "$tok" ]; then
    # Same resolver the post path uses, so --verify cannot certify a token the post
    # cannot see. The SOURCE is reported (never the value), so an explicit --env-file
    # and the two project dotfiles stay distinguishable.
    if tok="$(slack_token "$env_file_arg")"; then
      if [ -n "$env_file_arg" ]; then tok_src="$env_file_arg"
      elif [ -n "$(extract_env_key ./.env.local SLACK_INTAKE_TOKEN)" ]; then tok_src="./.env.local"
      else tok_src="./.env"; fi
    fi
  fi
  if [ -z "$tok" ]; then
    echo "✗ token       missing"
    echo "  → add SLACK_INTAKE_TOKEN=xoxb-… to $env_file (gitignored), or export it"
    return 1
  fi
  echo "✓ token       found via $tok_src"

  # 2. validity + granted scopes (auth.test needs no scope; scopes ride the header)
  hdr=$(mktemp) || return 1
  resp=$(curl -sS -D "$hdr" -H "Authorization: Bearer $tok" "https://slack.com/api/auth.test" 2>/dev/null)
  ok=$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)
  if [ "$ok" != "true" ]; then
    err=$(printf '%s' "$resp" | jq -r '.error // "unreachable"' 2>/dev/null || echo unreachable)
    echo "✗ token       rejected by Slack: $err"
    echo "  → re-issue the bot token and update $env_file"
    rm -f "$hdr"; return 1
  fi
  bot=$(printf '%s' "$resp" | jq -r '.user // "?"'); team=$(printf '%s' "$resp" | jq -r '.team // "?"')
  scopes=$(grep -i '^x-oauth-scopes:' "$hdr" | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  rm -f "$hdr"
  echo "✓ auth        bot=$bot team=$team"

  # 3. scopes — post needs chat:write; read needs channels:history (public) or groups:history (private)
  if has_scope "$scopes" "chat:write"; then echo "✓ chat:write  granted (posting possible)"
  else echo "✗ chat:write  MISSING — the announce cannot post"; rc=1; fi
  if has_scope "$scopes" "channels:history" || has_scope "$scopes" "groups:history"; then
    echo "✓ history     granted (reading thread replies possible)"
  else
    echo "✗ history     MISSING channels:history — thread replies cannot be read"
    echo "  → add the scope at api.slack.com/apps, then REINSTALL (scopes need a reinstall)"; rc=1
  fi
  has_scope "$scopes" "channels:join" || joinable=0

  # 4. channel — the env file carries the TOKEN only, so a channel left there reads as empty
  ch="${channel:-${SLACK_INTAKE_CHANNEL:-}}"
  if [ -n "$channel" ]; then ch_src="--channel"; else ch_src="\$SLACK_INTAKE_CHANNEL"; fi
  if [ -z "$ch" ]; then
    echo "✗ channel     unset"
    echo "  → pass --channel '#name', or EXPORT \$SLACK_INTAKE_CHANNEL (--env-file extracts the token only)"
    return 1
  fi
  ch_id=$(resolve_channel "$tok" "$ch") || {
    echo "✗ channel     '$ch' not found in this workspace"
    echo "  → check the spelling; a renamed or archived channel will not resolve, which is deliberate —"
    echo "    silently posting to the wrong place is worse than failing here"
    return 1
  }
  ch_disp=$(channel_name "$tok" "$ch_id")
  echo "✓ channel     $ch_disp (via $ch_src)"

  # 5. membership — reads require it; posting to a public channel does too without chat:write.public
  resp=$(curl -sS -H "Authorization: Bearer $tok" \
    "https://slack.com/api/conversations.history?channel=$ch_id&limit=1" 2>/dev/null)
  ok=$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)
  err=$(printf '%s' "$resp" | jq -r '.error // ""' 2>/dev/null || echo "")

  if [ "$ok" = "true" ]; then
    echo "✓ membership  bot is in the channel — reads work"
    [ "$rc" -eq 0 ] && echo "" && echo "READY — posting and reading both verified."
    return "$rc"
  fi

  if [ "$err" = "not_in_channel" ] && [ "$joinable" -eq 1 ]; then
    # 6. self-heal (public channels only; channels:join is what makes this possible)
    resp=$(curl -sS -X POST -H "Authorization: Bearer $tok" \
      -H "Content-type: application/x-www-form-urlencoded" \
      --data-urlencode "channel=$ch_id" "https://slack.com/api/conversations.join" 2>/dev/null)
    if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)" = "true" ]; then
      echo "✓ membership  bot was not in the channel — SELF-JOINED via conversations.join"
      [ "$rc" -eq 0 ] && echo "" && echo "READY — posting and reading both verified (after self-join)."
      return "$rc"
    fi
    err=$(printf '%s' "$resp" | jq -r '.error // "join_failed"' 2>/dev/null || echo join_failed)
    echo "✗ membership  not in channel, and self-join failed: $err"
  elif [ "$err" = "not_in_channel" ]; then
    echo "✗ membership  bot is NOT in the channel (no channels:join scope to self-heal)"
  else
    echo "✗ membership  read check failed: ${err:-unknown_error}"
  fi
  echo "  → run '/invite @$bot' in $ch_disp. Reads always require membership;"
  echo "    posting does too unless the token carries chat:write.public."
  return 1
}

if [ "$verify" -eq 1 ]; then
  run_verify
  exit $?
fi

# --- blocks (--blocks <path|->): a caller-supplied Block Kit array ---
# The poster validates the SHAPE only (a JSON array) and never inspects or
# authors the layout — composing blocks belongs to the caller, not here.
blocks_json=""
if [ -n "$blocks_src" ]; then
  if [ "$blocks_src" = "-" ]; then
    blocks_json="$(cat)"
  else
    [ -f "$blocks_src" ] || die "--blocks file not found: $blocks_src"
    blocks_json="$(cat "$blocks_src")"
  fi
  # Accept both shapes a caller plausibly has on disk: a bare array, or the
  # {"blocks":[…]} envelope Block Kit Builder exports. Anything else is a typo,
  # not a layout — fail rather than post something Slack will reject opaquely.
  blocks_json="$(printf '%s' "$blocks_json" | jq -c '
    if type == "array" then .
    elif type == "object" and (.blocks | type) == "array" then .blocks
    else error("shape") end' 2>/dev/null)" \
    || die "--blocks must be a JSON array of Block Kit blocks, or an object with a \"blocks\" array"
fi

# --- message: the message body without --blocks, the notification fallback with it ---
if [ -n "$text" ]; then
  message="$text"
elif [ -n "$blocks_json" ]; then
  # Slack renders `text` in notifications and previews, so a caller that supplied
  # only blocks still gets a useful one: the first text string in the layout.
  message="$(printf '%s' "$blocks_json" \
    | jq -r 'first(.. | objects | select(.type? == "plain_text" or .type? == "mrkdwn") | .text? // empty) // ""')"
  [ -n "$message" ] || message="(see message)"
else
  message="$(cat)"
fi
[ -n "$message" ] || die "empty message (pass --text or pipe via stdin)"

# --- channel ---
channel="${channel:-${SLACK_INTAKE_CHANNEL:-}}"
if [ "$dry_run" -eq 0 ] && [ -z "$channel" ]; then
  die "channel required (--channel or \$SLACK_INTAKE_CHANNEL)"
fi

# --- request body (jq-built; --arg is injection-safe) ---
if [ -n "$blocks_json" ]; then
  body=$(jq -n --arg ch "$channel" --arg txt "$message" --argjson bl "$blocks_json" \
    '{channel:$ch, text:$txt, blocks:$bl}') || die "failed to build request body"
elif [ -n "$title" ]; then
  body=$(jq -n --arg ch "$channel" --arg txt "$message" --arg t "$title" \
    '{channel:$ch, text:$txt, blocks:[
       {type:"header",  text:{type:"plain_text", text:$t, emoji:true}},
       {type:"section", text:{type:"mrkdwn", text:$txt}}
     ]}') || die "failed to build request body"
else
  body=$(jq -n --arg ch "$channel" --arg txt "$message" \
    '{channel:$ch, text:$txt, blocks:[
       {type:"section", text:{type:"mrkdwn", text:$txt}}
     ]}') || die "failed to build request body"
fi

# --- update mode: add the target message ts (chat.update edits it in place) ---
if [ -n "$update_ts" ]; then
  body=$(printf '%s' "$body" | jq --arg ts "$update_ts" '. + {ts:$ts}') || die "failed to add ts to request body"
fi

# --- dry run: print body (token never lives here) and stop ---
if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$body"
  exit 0
fi

# --- token (the shared resolver: env, then ./.env.local, then ./.env — or ONLY an
#     explicit --env-file, so the doctor's PASS and this post agree on one search set) ---
token="${SLACK_INTAKE_TOKEN:-${SLACK_BOT_TOKEN:-}}"
if [ -z "$token" ]; then
  token="$(slack_token "$env_file_arg")" \
    || die "no Slack token (set \$SLACK_INTAKE_TOKEN or add it to $env_file)"
fi
[ -n "$token" ] || die "no Slack token (set \$SLACK_INTAKE_TOKEN or add it to $env_file)"

# --- resolve the channel name to the id the API needs (internal only) ---
# Done after the token because resolution is an API call, and after the body
# build so --dry-run keeps working with no token and no network.
resolved=$(resolve_channel "$token" "$channel") \
  || die "channel '$channel' not found — check the name, or that the workspace still has it (a renamed channel will not resolve)"
body=$(printf '%s' "$body" | jq --arg ch "$resolved" '.channel = $ch') \
  || die "failed to set resolved channel on request body"

# --- endpoint: chat.update when editing an existing message, else chat.postMessage ---
endpoint="chat.postMessage"
[ -n "$update_ts" ] && endpoint="chat.update"

# --- send (body via stdin so the token stays out of argv) ---
response=$(printf '%s' "$body" | curl -sS -X POST \
  -H "Authorization: Bearer $token" \
  -H "Content-type: application/json; charset=utf-8" \
  --data @- \
  "https://slack.com/api/$endpoint") || die "network error calling Slack"

ok=$(printf '%s' "$response" | jq -r '.ok // false' 2>/dev/null || echo "false")
if [ "$ok" = "true" ]; then
  # Print the message ts so a caller can capture it (to edit this message later).
  printf '%s\n' "$(printf '%s' "$response" | jq -r '.ts // empty' 2>/dev/null || true)"
  exit 0
fi
err=$(printf '%s' "$response" | jq -r '.error // "unknown_error"' 2>/dev/null || echo "unknown_error")
die "$endpoint failed: $err"
