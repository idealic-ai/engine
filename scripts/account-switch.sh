#!/bin/bash
# ~/.claude/tools/account-switch/account-switch.sh — Claude Code account rotation
#
# Usage:
#   engine account-switch save [email]       # Save current Keychain credentials as a profile
#   engine account-switch switch <email>     # Switch to a saved profile
#   engine account-switch rotate             # Rotate to next account (round-robin)
#   engine account-switch list               # List saved profiles
#   engine account-switch status             # Show current state
#   engine account-switch remove <email>     # Remove a saved profile
#
# Credential storage:
#   Profiles: ~/.claude/accounts/profiles/<email>.json
#   State:    ~/.claude/accounts/state.json
#   Keychain: "Claude Code-credentials" (macOS Keychain)
#
# Race condition prevention:
#   run.sh exports CLAUDE_ACCOUNT=<email> at launch.
#   rotate checks: if current active != CLAUDE_ACCOUNT, someone already rotated → skip.
#
# Related:
#   Docs: (~/.claude/docs/)
#     sessions/2026_02_15_CLAUDE_ACCOUNT_ROTATION/BRAINSTORM.md — Design
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Works without fleet

set -euo pipefail

ACCOUNTS_DIR="${CLAUDE_ACCOUNTS_DIR:-$HOME/.claude/accounts}"
PROFILES_DIR="$ACCOUNTS_DIR/profiles"
STATE_FILE="$ACCOUNTS_DIR/state.json"
KEYCHAIN_SERVICE="Claude Code-credentials"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

ensure_dirs() {
  mkdir -p "$PROFILES_DIR"
}

# Read current credentials from macOS Keychain
read_keychain() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null
}

# Write credentials to macOS Keychain (delete + add to avoid duplicates)
write_keychain() {
  local json="$1"
  # Delete existing entry (ignore error if not found)
  security delete-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null || true
  # Add new entry
  security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_SERVICE" -w "$json"
}

# Extract email from credential JSON
extract_email() {
  local json="$1"
  # Try to extract from claudeAiOauth — email might be in various places
  # Fall back to asking the user
  echo "$json" | jq -r '
    .claudeAiOauth.email //
    .claudeAiOauth.accountEmail //
    empty
  ' 2>/dev/null || true
}

# Read state file (create if missing)
read_state() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo '{"activeAccount":"","accounts":[],"lastRotation":"","rotationCount":0}'
  fi
}

# Write state file atomically
write_state() {
  local json="$1"
  local tmp="$STATE_FILE.tmp"
  echo "$json" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# Get ordered account list from state
get_accounts() {
  read_state | jq -r '.accounts[]' 2>/dev/null
}

# Get active account email
get_active() {
  read_state | jq -r '.activeAccount // ""' 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────

cmd_save() {
  local email="${1:-}"
  ensure_dirs

  # Read current Keychain credentials
  local creds
  creds=$(read_keychain) || {
    echo "ERROR: No credentials found in Keychain. Log in first with 'claude login'." >&2
    exit 1
  }

  # Try to extract email if not provided
  if [ -z "$email" ]; then
    email=$(extract_email "$creds")
    if [ -z "$email" ]; then
      echo "ERROR: Could not extract email from credentials. Provide it explicitly:" >&2
      echo "  engine account-switch save user@gmail.com" >&2
      exit 1
    fi
  fi

  # Save profile
  local profile_file="$PROFILES_DIR/$email.json"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n \
    --arg email "$email" \
    --arg now "$now" \
    --argjson creds "$creds" \
    '{email: $email, credentials: $creds, savedAt: $now}' \
    > "$profile_file"

  # Update state: add to accounts list if not present, set as active
  local state
  state=$(read_state)
  state=$(echo "$state" | jq \
    --arg email "$email" \
    '.activeAccount = $email |
     if (.accounts | index($email)) then . else .accounts += [$email] end')
  write_state "$state"

  echo "Saved profile: $email"
  echo "Profiles: $(echo "$state" | jq -r '.accounts | length') total"
}

cmd_switch() {
  local email="${1:-}"
  if [ -z "$email" ]; then
    echo "ERROR: Email required. Usage: engine account-switch switch user@gmail.com" >&2
    exit 1
  fi

  local profile_file="$PROFILES_DIR/$email.json"
  if [ ! -f "$profile_file" ]; then
    echo "ERROR: No profile found for $email" >&2
    echo "Available profiles:" >&2
    cmd_list >&2
    exit 1
  fi

  # Read credentials from profile
  local creds
  creds=$(jq -r '.credentials' "$profile_file")

  # Write to Keychain
  write_keychain "$creds"

  # Update state
  local state
  state=$(read_state)
  state=$(echo "$state" | jq --arg email "$email" '.activeAccount = $email')
  write_state "$state"

  echo "Switched to: $email"
}

cmd_rotate() {
  ensure_dirs

  local state
  state=$(read_state)

  local active
  active=$(echo "$state" | jq -r '.activeAccount // ""')

  local account_count
  account_count=$(echo "$state" | jq -r '.accounts | length')

  if [ "$account_count" -lt 2 ]; then
    echo "ERROR: Need at least 2 saved accounts to rotate. Currently: $account_count" >&2
    echo "Save more accounts with: engine account-switch save <email>" >&2
    exit 1
  fi

  # Race condition check: if CLAUDE_ACCOUNT is set and differs from active,
  # someone already rotated → skip
  if [ -n "${CLAUDE_ACCOUNT:-}" ] && [ "$active" != "$CLAUDE_ACCOUNT" ]; then
    echo "SKIP: Already rotated (was $CLAUDE_ACCOUNT, now $active)"
    exit 0
  fi

  # Find next account (round-robin)
  local next
  next=$(echo "$state" | jq -r \
    --arg active "$active" \
    '.accounts as $accts |
     ($accts | index($active) // -1) as $idx |
     $accts[(($idx + 1) % ($accts | length))]')

  if [ "$next" = "$active" ]; then
    echo "ERROR: Rotation resolved to same account ($active). Check state." >&2
    exit 1
  fi

  # Switch to next account
  cmd_switch "$next"

  # Update rotation metadata
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  state=$(read_state)
  state=$(echo "$state" | jq \
    --arg now "$now" \
    '.lastRotation = $now | .rotationCount = (.rotationCount + 1)')
  write_state "$state"

  echo "Rotated: $active → $next (rotation #$(echo "$state" | jq -r '.rotationCount'))"
}

cmd_list() {
  ensure_dirs

  local active
  active=$(get_active)

  local count=0
  for profile in "$PROFILES_DIR"/*.json; do
    [ -f "$profile" ] || continue
    local email
    email=$(jq -r '.email' "$profile")
    local saved_at
    saved_at=$(jq -r '.savedAt // "unknown"' "$profile")

    if [ "$email" = "$active" ]; then
      echo "* $email (active) — saved $saved_at"
    else
      echo "  $email — saved $saved_at"
    fi
    count=$((count + 1))
  done

  if [ "$count" -eq 0 ]; then
    echo "(no saved accounts)"
    echo "Save current account: engine account-switch save <email>"
  fi
}

cmd_status() {
  local state
  state=$(read_state)

  echo "Active: $(echo "$state" | jq -r '.activeAccount // "(none)"')"
  echo "Accounts: $(echo "$state" | jq -r '.accounts | length')"
  echo "Rotations: $(echo "$state" | jq -r '.rotationCount')"
  echo "Last rotation: $(echo "$state" | jq -r '.lastRotation // "(never)"')"

  if [ -n "${CLAUDE_ACCOUNT:-}" ]; then
    echo "CLAUDE_ACCOUNT (env): $CLAUDE_ACCOUNT"
  fi
}

cmd_remove() {
  local email="${1:-}"
  if [ -z "$email" ]; then
    echo "ERROR: Email required. Usage: engine account-switch remove user@gmail.com" >&2
    exit 1
  fi

  local profile_file="$PROFILES_DIR/$email.json"
  if [ ! -f "$profile_file" ]; then
    echo "ERROR: No profile found for $email" >&2
    exit 1
  fi

  rm "$profile_file"

  # Remove from state
  local state
  state=$(read_state)
  state=$(echo "$state" | jq --arg email "$email" \
    '.accounts = [.accounts[] | select(. != $email)] |
     if .activeAccount == $email then .activeAccount = "" else . end')
  write_state "$state"

  echo "Removed: $email"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

SUBCMD="${1:-help}"
shift || true

case "$SUBCMD" in
  save)    cmd_save "$@" ;;
  switch)  cmd_switch "$@" ;;
  rotate)  cmd_rotate "$@" ;;
  list)    cmd_list "$@" ;;
  status)  cmd_status "$@" ;;
  remove)  cmd_remove "$@" ;;
  help|--help|-h)
    echo "Usage: engine account-switch <command> [args]"
    echo ""
    echo "Commands:"
    echo "  save [email]     Save current Keychain credentials as a profile"
    echo "  switch <email>   Switch to a saved profile"
    echo "  rotate           Rotate to next account (round-robin)"
    echo "  list             List saved profiles"
    echo "  status           Show current state"
    echo "  remove <email>   Remove a saved profile"
    ;;
  *)
    echo "ERROR: Unknown command '$SUBCMD'. Run 'engine account-switch help' for usage." >&2
    exit 1
    ;;
esac
