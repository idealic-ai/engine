#!/bin/bash
# slack-post.sh — engine slack-post: post a message to Slack via chat.postMessage
#
# A generic, reusable Slack poster. The caller composes the message; this script
# is a dumb pipe that authenticates and sends. Used by /intake to announce a
# completed grooming wave, but intentionally carries no intake-specific wording.
#
# Usage:
#   engine slack-post [--channel <id|#name>] [--title <text>] [--text <str>] \
#                     [--env-file <path>] [--dry-run]
#   (message read from STDIN when --text is omitted)
#
# Auth: bot token, resolved in order —
#   1. $SLACK_INTAKE_TOKEN   2. $SLACK_BOT_TOKEN
#   3. the SLACK_INTAKE_TOKEN key extracted from --env-file (default ./.env.local)
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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh" 2>/dev/null || true

die() { echo "slack-post: $1" >&2; exit 1; }

usage() {
  sed -n '2,/^set /p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
  exit "${1:-0}"
}

# Extract a KEY=value from an env file WITHOUT sourcing it (dotfiles are untrusted).
extract_env_key() {
  local file="$1" key="$2" line
  [ -f "$file" ] || return 1
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | head -1) || return 1
  [ -n "$line" ] || return 1
  # strip up to first '=', then surrounding quotes/whitespace
  line="${line#*=}"
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')"
  [ -n "$line" ] || return 1
  printf '%s' "$line"
}

channel=""
title=""
text=""
env_file="./.env.local"
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)  channel="${2:-}"; shift 2 ;;
    --title)    title="${2:-}"; shift 2 ;;
    --text)     text="${2:-}"; shift 2 ;;
    --env-file) env_file="${2:-}"; shift 2 ;;
    --dry-run)  dry_run=1; shift ;;
    -h|--help)  usage 0 ;;
    *)          die "unknown argument: $1 (see --help)" ;;
  esac
done

# --- message (--text or stdin) ---
if [ -n "$text" ]; then
  message="$text"
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
if [ -n "$title" ]; then
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

# --- dry run: print body (token never lives here) and stop ---
if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$body"
  exit 0
fi

# --- token (env, then env-file extraction) ---
token="${SLACK_INTAKE_TOKEN:-${SLACK_BOT_TOKEN:-}}"
if [ -z "$token" ]; then
  token="$(extract_env_key "$env_file" SLACK_INTAKE_TOKEN)" \
    || die "no Slack token (set \$SLACK_INTAKE_TOKEN or add it to $env_file)"
fi
[ -n "$token" ] || die "no Slack token (set \$SLACK_INTAKE_TOKEN or add it to $env_file)"

# --- send (body via stdin so the token stays out of argv) ---
response=$(printf '%s' "$body" | curl -sS -X POST \
  -H "Authorization: Bearer $token" \
  -H "Content-type: application/json; charset=utf-8" \
  --data @- \
  "https://slack.com/api/chat.postMessage") || die "network error calling Slack"

ok=$(printf '%s' "$response" | jq -r '.ok // false' 2>/dev/null || echo "false")
if [ "$ok" = "true" ]; then
  exit 0
fi
err=$(printf '%s' "$response" | jq -r '.error // "unknown_error"' 2>/dev/null || echo "unknown_error")
die "chat.postMessage failed: $err"
