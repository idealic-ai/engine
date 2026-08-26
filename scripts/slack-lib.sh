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
# ONE shared bootstrap (scripts/env-boot.sh) rather than a private chain-walk. `engine
# doctor` gates this as EB-01 — one resolver reached many ways fails like many resolvers.
for _slack_lib_boot in "${ENGINE_SCRIPTS:-}/env-boot.sh" "$HOME/.claude/engine/scripts/env-boot.sh"; do
  [ -f "$_slack_lib_boot" ] || continue
  # shellcheck source=/dev/null
  . "$_slack_lib_boot"
  break
done
if ! type resolve_env_key >/dev/null 2>&1; then
  echo "slack-lib: could not load the engine resolver via env-boot.sh" >&2
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
# `U` is in the recognized-id class so a USER id is passed back as the id it is.
# It is not a channel and callers must route it through resolve_user/open_dm —
# but reporting it as a channel that does not exist reads as a Slack restriction
# and is not one, which is the failure this class exists to prevent.
resolve_channel() {
  local tok="$1" want="$2" types="public_channel,private_channel" cursor="" resp id err
  printf '%s' "$want" | grep -qE '^[CDGU][A-Z0-9]{7,}$' && { printf '%s' "$want"; return 0; }
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

# Resolve a PERSON to a Slack user id. Three tiers, strictest first, so an
# unambiguous selector short-circuits before the search that can be ambiguous:
#   1. a U… id            — already the answer
#   2. anything with @     — users.lookupByEmail; one hit or none, never ambiguous
#   3. a bare name         — case-insensitive SUBSTRING over display name, real
#                            name and the email local-part across users.list
# Deleted accounts are dropped: they cannot receive a DM, so keeping them only
# manufactures ambiguity.
#
# Exit codes carry the OUTCOME, because "not found" and "could not look" are
# different failures and a caller must be able to say which one happened:
#   0  stdout is one U… id
#   2  AMBIGUOUS — stdout is one candidate row per line, already column-padded
#      (id, display name, real name, email); the caller prints them and posts nothing
#   3  no match
#   4  cannot look — stdout is the missing scope name
#   1  other failure — stdout is Slack's .error
resolve_user() {
  local tok="$1" want="$2" resp err cursor="" acc="[]" n
  printf '%s' "$want" | grep -qE '^U[A-Z0-9]{7,}$' && { printf '%s' "$want"; return 0; }
  case "$want" in
    *@*)
      resp=$(curl -sS -G -H "Authorization: Bearer $tok" \
        --data-urlencode "email=$want" "https://slack.com/api/users.lookupByEmail" 2>/dev/null)
      if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)" = "true" ]; then
        printf '%s' "$resp" | jq -r '.user.id // empty' 2>/dev/null
        return 0
      fi
      err=$(printf '%s' "$resp" | jq -r '.error // "unreachable"' 2>/dev/null || echo unreachable)
      case "$err" in
        users_not_found) return 3 ;;
        missing_scope)   printf 'users:read.email'; return 4 ;;
        *)               printf '%s' "$err"; return 1 ;;
      esac
      ;;
  esac
  while :; do
    resp=$(curl -sS -H "Authorization: Bearer $tok" \
      "https://slack.com/api/users.list?limit=200${cursor:+&cursor=$cursor}" 2>/dev/null)
    if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)" != "true" ]; then
      err=$(printf '%s' "$resp" | jq -r '.error // "unreachable"' 2>/dev/null || echo unreachable)
      [ "$err" = "missing_scope" ] && { printf 'users:read'; return 4; }
      printf '%s' "$err"; return 1
    fi
    acc=$(printf '%s' "$resp" | jq -c --argjson acc "$acc" --arg q "$want" '
      ($q | ascii_downcase) as $needle
      | $acc + [ .members[]
          | select(.deleted != true)
          | { id: .id,
              display: (.profile.display_name // ""),
              real:    (.profile.real_name // .real_name // ""),
              email:   (.profile.email // "") }
          | select( ((.display | ascii_downcase) | contains($needle))
                 or ((.real    | ascii_downcase) | contains($needle))
                 or (((.email | split("@") | .[0] // "") | ascii_downcase) | contains($needle)) ) ]
      ' 2>/dev/null) || { printf 'directory_parse_failed'; return 1; }
    cursor=$(printf '%s' "$resp" | jq -r '.response_metadata.next_cursor // empty' 2>/dev/null)
    [ -n "$cursor" ] || break
  done
  n=$(printf '%s' "$acc" | jq -r 'length' 2>/dev/null || echo 0)
  [ "$n" -eq 0 ] && return 3
  [ "$n" -eq 1 ] && { printf '%s' "$acc" | jq -r '.[0].id'; return 0; }
  # Column widths are paired with the header slack-post prints above these rows.
  # The id leads because it is what the caller re-invokes with, and tier 1
  # guarantees it resolves to exactly this person.
  printf '%s' "$acc" | jq -r '
    def pad($n): if length < $n then . + (" " * ($n - length)) else . + " " end;
    .[] | (.id | pad(13)) + ((if .display == "" then "-" else .display end) | pad(22))
        + ((if .real == "" then "-" else .real end) | pad(24))
        + (if .email == "" then "(no email visible)" else .email end)'
  return 2
}

# Open the IM channel with a user id and print its D… id. A user id is not a
# channel; this is the step that turns one into somewhere chat.postMessage can
# send. Needs im:write.
#   0  stdout is the D… id
#   4  cannot open — stdout is the missing scope name
#   1  other failure — stdout is Slack's .error
open_dm() {
  local tok="$1" uid="$2" resp err id
  resp=$(curl -sS -X POST -H "Authorization: Bearer $tok" \
    -H "Content-type: application/x-www-form-urlencoded" \
    --data-urlencode "users=$uid" "https://slack.com/api/conversations.open" 2>/dev/null)
  if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)" = "true" ]; then
    id=$(printf '%s' "$resp" | jq -r '.channel.id // empty' 2>/dev/null)
    [ -n "$id" ] || { printf 'no_channel_in_response'; return 1; }
    printf '%s' "$id"; return 0
  fi
  err=$(printf '%s' "$resp" | jq -r '.error // "unreachable"' 2>/dev/null || echo unreachable)
  [ "$err" = "missing_scope" ] && { printf 'im:write'; return 4; }
  printf '%s' "$err"; return 1
}

# id -> #name, for display only. Never let an id reach user-facing output.
channel_name() {
  local n
  n=$(curl -sS -H "Authorization: Bearer $1" "https://slack.com/api/conversations.info?channel=$2" 2>/dev/null \
      | jq -r '.channel.name // empty' 2>/dev/null)
  [ -n "$n" ] && printf '#%s' "$n" || printf '%s' "the configured channel"
}
