#!/bin/bash
# slack-lib.sh — shared Slack helpers for engine slack-* commands.
#
# Sourced by slack-post.sh and slack-read.sh. Holds only mechanics both need:
# token extraction, channel name→id resolution, and id→name for display.
# Deliberately NOT in lib.sh: that is sourced best-effort by many scripts, and
# these are REQUIRED — a caller must fail loudly if they are missing, which is
# the opposite of lib.sh's optional contract.
#
# Channel NAMES are the human-facing identifier everywhere; ids are internal
# and never printed. See INTAKE_SYSTEM.md §PASS_HEARTBEAT.

# extract_env_key / env_key_files / resolve_env_key live in env-lib.sh — the single
# dotfile-precedence rule. Re-exported by sourcing here: intake.sh and the test suite
# obtain extract_env_key by sourcing THIS file, and must keep doing so.
# The link chain is walked first: a test suite may symlink this lib into a fake HOME,
# where the sibling env-lib.sh does not exist.
_SLACK_LIB_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_SLACK_LIB_SRC" ]; do
  _SLACK_LIB_DIR="$(cd -P "$(dirname "$_SLACK_LIB_SRC")" && pwd)"
  _SLACK_LIB_SRC="$(readlink "$_SLACK_LIB_SRC")"
  case "$_SLACK_LIB_SRC" in /*) ;; *) _SLACK_LIB_SRC="$_SLACK_LIB_DIR/$_SLACK_LIB_SRC" ;; esac
done
_SLACK_LIB_DIR="$(cd -P "$(dirname "$_SLACK_LIB_SRC")" && pwd)"
if [ -f "$_SLACK_LIB_DIR/env-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$_SLACK_LIB_DIR/env-lib.sh"
else
  echo "slack-lib: missing required $_SLACK_LIB_DIR/env-lib.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# Resolve the bot token. Called with NO argument (or an empty one) the shared chain
# applies: $SLACK_INTAKE_TOKEN / $SLACK_BOT_TOKEN → ./.env.local → ./.env.
# An EXPLICITLY-supplied env-file is AUTHORITATIVE — only that file is searched, so
# `--env-file wsB.env` can never fall through to another workspace's token.
# Never printed by callers.
slack_token() {
  local explicit="${1:-}" tok
  tok="${SLACK_INTAKE_TOKEN:-${SLACK_BOT_TOKEN:-}}"
  if [ -z "$tok" ]; then
    if [ -n "$explicit" ]; then
      tok="$(extract_env_key "$explicit" SLACK_INTAKE_TOKEN)" || return 1
    else
      tok="$(resolve_env_key SLACK_INTAKE_TOKEN)" || return 1
    fi
  fi
  [ -n "$tok" ] || return 1
  printf '%s' "$tok"
}

# Resolve a channel NAME (#name or name) to the id the Slack API requires.
# An id passed in still works: ids are uppercase, Slack channel names are
# lowercase, so the shapes cannot collide. Needs channels:read.
# Fails rather than guessing — a renamed channel must not resolve silently.
resolve_channel() {
  local tok="$1" want="$2" types="public_channel,private_channel" cursor="" resp id err
  printf '%s' "$want" | grep -qE '^[CGD][A-Z0-9]{7,}$' && { printf '%s' "$want"; return 0; }
  want="${want#\#}"
  while :; do
    resp=$(curl -sS -H "Authorization: Bearer $tok" \
      "https://slack.com/api/conversations.list?exclude_archived=true&types=$types&limit=1000${cursor:+&cursor=$cursor}" 2>/dev/null)
    if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)" != "true" ]; then
      err=$(printf '%s' "$resp" | jq -r '.error // ""' 2>/dev/null)
      # Slack fails the WHOLE call when any requested type lacks its scope —
      # asking for private_channel without groups:read kills the public listing
      # too. Degrade rather than demand a scope a public channel never needed.
      if [ "$err" = "missing_scope" ] && [ "$types" != "public_channel" ]; then
        types="public_channel"; cursor=""; continue
      fi
      return 1
    fi
    id=$(printf '%s' "$resp" | jq -r --arg n "$want" '.channels[] | select(.name==$n) | .id' 2>/dev/null | head -1)
    [ -n "$id" ] && { printf '%s' "$id"; return 0; }
    cursor=$(printf '%s' "$resp" | jq -r '.response_metadata.next_cursor // empty' 2>/dev/null)
    [ -n "$cursor" ] || return 1
  done
}

# id -> #name, for display only. Never let an id reach user-facing output.
channel_name() {
  local n
  n=$(curl -sS -H "Authorization: Bearer $1" "https://slack.com/api/conversations.info?channel=$2" 2>/dev/null \
      | jq -r '.channel.name // empty' 2>/dev/null)
  [ -n "$n" ] && printf '#%s' "$n" || printf '%s' "the configured channel"
}
