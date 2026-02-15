#!/bin/bash
# Tests for account-switch.sh — Claude Code account rotation
#
# Mocking strategy:
#   - Override CLAUDE_ACCOUNTS_DIR to point into sandbox
#   - Put a mock `security` script early in PATH to simulate Keychain
#   - Mock stores credentials in a flat file instead of real Keychain

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNT_SWITCH="$SCRIPT_DIR/account-switch.sh"

# Mock Keychain credentials (realistic structure)
MOCK_CREDS_1='{"claudeAiOauth":{"accessToken":"tok1","expiresAt":"2026-12-31","rateLimitTier":"tier5","refreshToken":"ref1","scopes":"user","subscriptionType":"pro","email":"user1@gmail.com"},"mcpOAuth":{}}'
MOCK_CREDS_2='{"claudeAiOauth":{"accessToken":"tok2","expiresAt":"2026-12-31","rateLimitTier":"tier5","refreshToken":"ref2","scopes":"user","subscriptionType":"pro","email":"user2@gmail.com"},"mcpOAuth":{}}'
MOCK_CREDS_3='{"claudeAiOauth":{"accessToken":"tok3","expiresAt":"2026-12-31","rateLimitTier":"tier5","refreshToken":"ref3","scopes":"user","subscriptionType":"pro","email":"user3@gmail.com"},"mcpOAuth":{}}'

setup() {
  TMP_DIR=$(mktemp -d)

  # Sandbox accounts directory
  export CLAUDE_ACCOUNTS_DIR="$TMP_DIR/accounts"
  mkdir -p "$CLAUDE_ACCOUNTS_DIR/profiles"

  # Create mock `security` command that uses a flat file as "Keychain"
  MOCK_KEYCHAIN="$TMP_DIR/mock-keychain"
  echo "$MOCK_CREDS_1" > "$MOCK_KEYCHAIN"

  MOCK_BIN="$TMP_DIR/bin"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/security" <<MOCK
#!/bin/bash
KEYCHAIN_FILE="$MOCK_KEYCHAIN"
case "\$1" in
  find-generic-password)
    if [ -f "\$KEYCHAIN_FILE" ]; then
      cat "\$KEYCHAIN_FILE"
    else
      echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
      exit 44
    fi
    ;;
  delete-generic-password)
    rm -f "\$KEYCHAIN_FILE" 2>/dev/null || true
    ;;
  add-generic-password)
    # Extract -w value (last argument)
    local w_val=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        -w) shift; w_val="\$1" ;;
      esac
      shift
    done
    echo "\$w_val" > "\$KEYCHAIN_FILE"
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/security"

  # Prepend mock bin to PATH
  export PATH="$MOCK_BIN:$PATH"

  # Clear env
  unset CLAUDE_ACCOUNT 2>/dev/null || true
}

teardown() {
  rm -rf "$TMP_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# save tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_save_with_email() {
  local output
  output=$("$ACCOUNT_SWITCH" save "user1@gmail.com" 2>&1) || true
  assert_contains "Saved profile: user1@gmail.com" "$output" "save reports success"
  assert_file_exists "$CLAUDE_ACCOUNTS_DIR/profiles/user1@gmail.com.json" "profile file created"
}

test_account_switch_save_extracts_email() {
  local output
  output=$("$ACCOUNT_SWITCH" save 2>&1) || true
  assert_contains "Saved profile: user1@gmail.com" "$output" "email extracted from credentials"
  assert_file_exists "$CLAUDE_ACCOUNTS_DIR/profiles/user1@gmail.com.json" "profile created with extracted email"
}

test_account_switch_save_updates_state() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user1@gmail.com" "state tracks active account"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".accounts | length" "1" "state has 1 account"
}

test_account_switch_save_multiple() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true

  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".accounts | length" "2" "state has 2 accounts"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user2@gmail.com" "latest save becomes active"
}

test_account_switch_save_idempotent() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true

  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".accounts | length" "1" "duplicate save doesn't add twice"
}

# ─────────────────────────────────────────────────────────────────────────────
# switch tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_switch_to_saved() {
  # Save two accounts
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true

  # Switch back to first
  local output
  output=$("$ACCOUNT_SWITCH" switch "user1@gmail.com" 2>&1) || true
  assert_contains "Switched to: user1@gmail.com" "$output" "switch reports success"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user1@gmail.com" "state updated to switched account"

  # Verify Keychain was updated
  local keychain_creds
  keychain_creds=$(cat "$MOCK_KEYCHAIN")
  assert_contains "tok1" "$keychain_creds" "keychain has account 1 token"
}

test_account_switch_switch_missing_profile() {
  local output
  output=$("$ACCOUNT_SWITCH" switch "nonexistent@gmail.com" 2>&1) || true
  assert_contains "ERROR" "$output" "switch rejects missing profile"
}

test_account_switch_switch_no_email() {
  local output
  output=$("$ACCOUNT_SWITCH" switch 2>&1) || true
  assert_contains "ERROR" "$output" "switch requires email argument"
}

# ─────────────────────────────────────────────────────────────────────────────
# rotate tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_rotate_advances() {
  # Save two accounts
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true

  # Switch to user1 first
  "$ACCOUNT_SWITCH" switch "user1@gmail.com" > /dev/null 2>&1 || true

  # Rotate
  local output
  output=$("$ACCOUNT_SWITCH" rotate 2>&1) || true
  assert_contains "Rotated:" "$output" "rotate reports success"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user2@gmail.com" "rotated to next account"
}

test_account_switch_rotate_wraps_around() {
  # Save two accounts, active is user2
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true

  # Rotate: user2 → user1 (wrap)
  local output
  output=$("$ACCOUNT_SWITCH" rotate 2>&1) || true
  assert_contains "Rotated:" "$output" "wrap-around rotate reports success"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user1@gmail.com" "wrapped to first account"
}

test_account_switch_rotate_needs_two_accounts() {
  # Only one account saved
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true

  local output
  output=$("$ACCOUNT_SWITCH" rotate 2>&1) || true
  assert_contains "ERROR" "$output" "rotate rejects single account"
}

test_account_switch_rotate_idempotent_via_env() {
  # Save two accounts
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true
  "$ACCOUNT_SWITCH" switch "user1@gmail.com" > /dev/null 2>&1 || true

  # First rotate succeeds
  "$ACCOUNT_SWITCH" rotate > /dev/null 2>&1 || true
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user2@gmail.com" "first rotate succeeded"

  # Second rotate with stale CLAUDE_ACCOUNT should skip
  export CLAUDE_ACCOUNT="user1@gmail.com"
  local output
  output=$("$ACCOUNT_SWITCH" rotate 2>&1) || true
  assert_contains "SKIP" "$output" "second rotate skips (already rotated)"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user2@gmail.com" "active unchanged after skip"
  unset CLAUDE_ACCOUNT
}

test_account_switch_rotate_increments_count() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true
  "$ACCOUNT_SWITCH" switch "user1@gmail.com" > /dev/null 2>&1 || true

  "$ACCOUNT_SWITCH" rotate > /dev/null 2>&1 || true
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".rotationCount" "1" "rotation count incremented"
}

# ─────────────────────────────────────────────────────────────────────────────
# list tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_list_empty() {
  local output
  output=$("$ACCOUNT_SWITCH" list 2>&1) || true
  assert_contains "no saved accounts" "$output" "list shows empty state"
}

test_account_switch_list_shows_active() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  echo "$MOCK_CREDS_2" > "$MOCK_KEYCHAIN"
  "$ACCOUNT_SWITCH" save "user2@gmail.com" > /dev/null 2>&1 || true

  local output
  output=$("$ACCOUNT_SWITCH" list 2>&1) || true
  assert_contains "(active)" "$output" "list marks active account"
  assert_contains "user1@gmail.com" "$output" "list shows account 1"
  assert_contains "user2@gmail.com" "$output" "list shows account 2"
}

# ─────────────────────────────────────────────────────────────────────────────
# status tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_status_empty() {
  local output
  output=$("$ACCOUNT_SWITCH" status 2>&1) || true
  assert_contains "Accounts: 0" "$output" "status shows 0 accounts"
}

test_account_switch_status_with_accounts() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true

  local output
  output=$("$ACCOUNT_SWITCH" status 2>&1) || true
  assert_contains "Active: user1@gmail.com" "$output" "status shows active"
  assert_contains "Accounts: 1" "$output" "status shows count"
}

test_account_switch_status_shows_env() {
  export CLAUDE_ACCOUNT="test@gmail.com"
  local output
  output=$("$ACCOUNT_SWITCH" status 2>&1) || true
  assert_contains "CLAUDE_ACCOUNT (env): test@gmail.com" "$output" "status shows env var"
  unset CLAUDE_ACCOUNT
}

# ─────────────────────────────────────────────────────────────────────────────
# remove tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_remove_deletes_profile() {
  "$ACCOUNT_SWITCH" save "user1@gmail.com" > /dev/null 2>&1 || true
  "$ACCOUNT_SWITCH" remove "user1@gmail.com" > /dev/null 2>&1 || true

  assert_file_not_exists "$CLAUDE_ACCOUNTS_DIR/profiles/user1@gmail.com.json" "profile file deleted"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".accounts | length" "0" "account removed from state"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "" "active account cleared"
}

test_account_switch_remove_missing() {
  local output
  output=$("$ACCOUNT_SWITCH" remove "nonexistent@gmail.com" 2>&1) || true
  assert_contains "ERROR" "$output" "remove rejects missing profile"
}

# ─────────────────────────────────────────────────────────────────────────────
# help tests
# ─────────────────────────────────────────────────────────────────────────────

test_account_switch_help() {
  local output
  output=$("$ACCOUNT_SWITCH" help 2>&1) || true
  assert_contains "Usage:" "$output" "help shows usage"
  assert_contains "save" "$output" "help lists save command"
  assert_contains "rotate" "$output" "help lists rotate command"
}

test_account_switch_unknown_command() {
  local output
  output=$("$ACCOUNT_SWITCH" bogus 2>&1) || true
  assert_contains "ERROR" "$output" "unknown command shows error"
}

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

run_test test_account_switch_save_with_email
run_test test_account_switch_save_extracts_email
run_test test_account_switch_save_updates_state
run_test test_account_switch_save_multiple
run_test test_account_switch_save_idempotent
run_test test_account_switch_switch_to_saved
run_test test_account_switch_switch_missing_profile
run_test test_account_switch_switch_no_email
run_test test_account_switch_rotate_advances
run_test test_account_switch_rotate_wraps_around
run_test test_account_switch_rotate_needs_two_accounts
run_test test_account_switch_rotate_idempotent_via_env
run_test test_account_switch_rotate_increments_count
run_test test_account_switch_list_empty
run_test test_account_switch_list_shows_active
run_test test_account_switch_status_empty
run_test test_account_switch_status_with_accounts
run_test test_account_switch_status_shows_env
run_test test_account_switch_remove_deletes_profile
run_test test_account_switch_remove_missing
run_test test_account_switch_help
run_test test_account_switch_unknown_command
exit_with_results
