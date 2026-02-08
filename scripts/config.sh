#!/bin/bash
# ~/.claude/scripts/config.sh — User-level config manager
#
# Related:
#   (no direct doc/invariant/command references — utility layer)
#   Consumers: run.sh (terminalLinkProtocol), statusline.sh, setup.sh
#
# Usage:
#   config.sh get <key>           # Get value (returns default if unset)
#   config.sh set <key> <value>   # Set value
#   config.sh list                # List all config
#
# Config file: ~/.claude/config.json

set -eo pipefail

CONFIG_FILE="$HOME/.claude/config.json"

# Defaults (simple key=value, no associative array for portability)
get_default() {
  case "$1" in
    terminalLinkProtocol) echo "cursor://file" ;;
    *) echo "" ;;
  esac
}

list_default_keys() {
  echo "terminalLinkProtocol"
}

# Ensure config file exists
ensure_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo '{}' > "$CONFIG_FILE"
  fi
}

cmd_get() {
  local key="$1"
  ensure_config
  local value=$(jq -r --arg k "$key" '.[$k] // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$value" ]; then
    get_default "$key"
  else
    echo "$value"
  fi
}

cmd_set() {
  local key="$1"
  local value="$2"
  ensure_config
  local tmp=$(mktemp)
  jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  echo "Set $key = $value"
}

cmd_list() {
  ensure_config
  echo "# Config: $CONFIG_FILE"
  echo "# (defaults shown if unset)"
  echo ""

  # Show all keys (from file + defaults)
  {
    jq -r 'keys[]' "$CONFIG_FILE" 2>/dev/null || true
    list_default_keys
  } | sort -u | while read -r key; do
    local value=$(cmd_get "$key")
    local source="config"
    if ! jq -e --arg k "$key" '.[$k]' "$CONFIG_FILE" &>/dev/null; then
      source="default"
    fi
    printf "%-25s = %s (%s)\n" "$key" "$value" "$source"
  done
}

case "${1:-}" in
  get)
    [ -z "${2:-}" ] && { echo "Usage: config.sh get <key>" >&2; exit 1; }
    cmd_get "$2"
    ;;
  set)
    [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "Usage: config.sh set <key> <value>" >&2; exit 1; }
    cmd_set "$2" "$3"
    ;;
  list)
    cmd_list
    ;;
  *)
    echo "Usage: config.sh <get|set|list> [args...]" >&2
    exit 1
    ;;
esac
