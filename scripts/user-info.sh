#!/bin/bash
# user-info.sh — Resolve user identity from the .user.json cache or git config
#
# Related:
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_INFER_USER_FROM_GIT — Identity comes from the cache, else git user.email
#
# Usage: user-info.sh [field]
#   field: username | email | domain | data-root | json (default: json)
#
# Detection order:
#   1. ~/.claude/engine/.user.json cache
#   2. git config --global user.email
#   3. Error: asks the user to set git user.email
#
# Fields:
#   username   — local part of the email, e.g. "you"
#   email      — e.g. "you@example.com"
#   domain     — e.g. "example.com"
#   data-root  — local root for per-project user data (sessions, reports, assets):
#                always "$HOME/.claude/data". Needs no identity.
#
# Example:
#   user-info.sh              # {"username":"you","email":"you@example.com","domain":"example.com"}
#   user-info.sh username     # you
#   user-info.sh email        # you@example.com
#   user-info.sh data-root    # /Users/you/.claude/data

set -euo pipefail

FIELD="${1:-json}"
CACHE_FILE="$HOME/.claude/engine/.user.json"

case "$FIELD" in
  json|username|email|domain) ;;
  data-root) echo "$HOME/.claude/data"; exit 0 ;;
  *) echo "Unknown field: $FIELD" >&2; exit 1 ;;
esac

if [ -f "$CACHE_FILE" ]; then
  case "$FIELD" in
    json)     cat "$CACHE_FILE" ;;
    username) jq -r '.username' "$CACHE_FILE" ;;
    email)    jq -r '.email' "$CACHE_FILE" ;;
    domain)   jq -r '.domain' "$CACHE_FILE" ;;
  esac
  exit 0
fi

EMAIL=$(git config --global user.email 2>/dev/null || true)
if [ -z "$EMAIL" ] || [[ "$EMAIL" != *@* ]]; then
  echo "ERROR: Could not determine your identity." >&2
  echo "  Set it with: git config --global user.email you@example.com" >&2
  exit 1
fi

USERNAME="${EMAIL%@*}"
DOMAIN="${EMAIL#*@}"

case "$FIELD" in
  username) echo "$USERNAME" ;;
  email)    echo "$EMAIL" ;;
  domain)   echo "$DOMAIN" ;;
  json)     echo "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"domain\":\"$DOMAIN\"}" ;;
esac
