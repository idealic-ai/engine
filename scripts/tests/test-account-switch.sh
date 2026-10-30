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

  # Mock `security`: an account-keyed "Keychain" — one file per account under
  # $KC_DIR, named by the -a value — plus a call log. It never touches the real
  # keychain. Like the real binary: find/delete without -a hit the first item,
  # add without -U refuses an existing item (exit 45). Touch $KC_FAIL_FIND to
  # make every find fail.
  export USER="${USER:-tester}"
  KC_DIR="$TMP_DIR/kc"
  KC_LOG="$TMP_DIR/security-calls.log"
  KC_FAIL_FIND="$TMP_DIR/fail-find"
  mkdir -p "$KC_DIR"
  : > "$KC_LOG"
  MOCK_KEYCHAIN="$KC_DIR/$USER"
  echo "$MOCK_CREDS_1" > "$MOCK_KEYCHAIN"

  MOCK_BIN="$TMP_DIR/bin"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/security" <<MOCK
#!/bin/bash
KC_DIR="$KC_DIR"
verb="\$1"; shift
acct=""; svc=""; w_val=""; upd=0; has_w=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    -a) shift; acct="\$1" ;;
    -s) shift; svc="\$1" ;;
    -U) upd=1 ;;
    -w) has_w=1; if [ "\$verb" = add-generic-password ]; then shift; w_val="\$1"; fi ;;
  esac
  shift
done
echo "\$verb|a=\$acct|s=\$svc|U=\$upd" >> "$KC_LOG"
first_item() { ls "\$KC_DIR" | head -n1; }
case "\$verb" in
  find-generic-password)
    [ -e "$KC_FAIL_FIND" ] && { echo "security: forced failure" >&2; exit 51; }
    item="\${acct:-\$(first_item)}"
    if [ -n "\$item" ] && [ -f "\$KC_DIR/\$item" ]; then
      cat "\$KC_DIR/\$item"
    else
      echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
      exit 44
    fi
    ;;
  delete-generic-password)
    item="\${acct:-\$(first_item)}"
    [ -n "\$item" ] && [ -f "\$KC_DIR/\$item" ] || exit 44
    rm -f "\$KC_DIR/\$item"
    ;;
  add-generic-password)
    if [ -f "\$KC_DIR/\$acct" ] && [ "\$upd" = 0 ]; then
      echo "security: SecKeychainItemCreateFromContent: The specified item already exists in the keychain." >&2
      exit 45
    fi
    printf '%s\\n' "\$w_val" > "\$KC_DIR/\$acct"
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
# keychain write tests (ROTATEKEEP) — what a switch leaves in the Keychain item
# Claude Code reads (service "Claude Code-credentials", account $USER)
# ─────────────────────────────────────────────────────────────────────────────

ORPHAN_ACCOUNT="Claude Code-credentials"
LIVE_MCP='{"plugin:linear:linear|abc123":{"serverName":"linear","accessToken":"mcp-live","expiresAt":1793000000000,"scope":"read write"},"sentry|9f":{"serverName":"sentry","accessToken":"mcp-sentry","expiresAt":1500000000000.5}}'
LIVE_ITEM='{"claudeAiOauth":{"accessToken":"tok1","refreshToken":"ref1","email":"user1@gmail.com"},"mcpOAuth":'"$LIVE_MCP"',"organizationUuid":"org-live"}'

# The item is compact JSON as Claude Code writes it (JSON.stringify). The merge
# goes through jq, which keeps key order and number literals of that form but
# would print an exponent literal such as 1.5e12 as 1.5E+12 (same value);
# JSON.stringify never writes one below 1e21.

# Two profiles as they exist on disk: credentials hold only claudeAiOauth
# (user2's also carries a foreign mcpOAuth, which must not reach the item).
seed_profiles() {
  jq -n '{email:"user1@gmail.com",credentials:{claudeAiOauth:{accessToken:"tok1",refreshToken:"ref1",email:"user1@gmail.com"}},savedAt:"x"}' \
    > "$CLAUDE_ACCOUNTS_DIR/profiles/user1@gmail.com.json"
  jq -n '{email:"user2@gmail.com",credentials:{claudeAiOauth:{accessToken:"tok2",refreshToken:"ref2",email:"user2@gmail.com"},mcpOAuth:{"foreign|1":{accessToken:"mcp-foreign"}}},savedAt:"x"}' \
    > "$CLAUDE_ACCOUNTS_DIR/profiles/user2@gmail.com.json"
  echo '{"activeAccount":"user1@gmail.com","accounts":["user1@gmail.com","user2@gmail.com"],"lastRotation":"","rotationCount":0}' \
    > "$CLAUDE_ACCOUNTS_DIR/state.json"
  printf '%s\n' "$LIVE_ITEM" > "$MOCK_KEYCHAIN"
  : > "$KC_LOG"
}

test_account_switch_rotate_keeps_mcp_oauth() {
  seed_profiles
  local rc=0
  "$ACCOUNT_SWITCH" rotate > /dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "rotate exits 0"
  assert_eq "tok2" "$(jq -r '.claudeAiOauth.accessToken' "$MOCK_KEYCHAIN")" "item now holds the next account's claudeAiOauth"
  assert_eq '{"claudeAiOauth":{"accessToken":"tok2","refreshToken":"ref2","email":"user2@gmail.com"},"mcpOAuth":'"$LIVE_MCP"',"organizationUuid":"org-live"}' \
    "$(cat "$MOCK_KEYCHAIN")" "item bytes: only claudeAiOauth changed, mcpOAuth and the rest byte-for-byte"
  assert_eq "org-live" "$(jq -r '.organizationUuid' "$MOCK_KEYCHAIN")" "other top-level keys survive"
  assert_eq '["claudeAiOauth","mcpOAuth","organizationUuid"]' "$(jq -c 'keys_unsorted' "$MOCK_KEYCHAIN")" "key order kept"
  assert_not_contains "mcp-foreign" "$(cat "$MOCK_KEYCHAIN")" "a profile's mcpOAuth is never copied into the item"
}

test_account_switch_writes_user_account_in_place() {
  seed_profiles
  "$ACCOUNT_SWITCH" switch "user2@gmail.com" > /dev/null 2>&1 || true
  local log; log=$(cat "$KC_LOG")
  assert_contains "find-generic-password|a=$USER|s=Claude Code-credentials" "$log" "reads the \$USER item"
  assert_contains "add-generic-password|a=$USER|s=Claude Code-credentials|U=1" "$log" "updates the \$USER item in place (-U)"
  assert_not_contains "delete-generic-password" "$log" "never deletes the item"
}

test_account_switch_never_writes_orphan_account() {
  seed_profiles
  printf '%s\n' '{"claudeAiOauth":{"accessToken":"orphan"}}' > "$KC_DIR/$ORPHAN_ACCOUNT"
  local before; before=$(cat "$KC_DIR/$ORPHAN_ACCOUNT")
  "$ACCOUNT_SWITCH" rotate > /dev/null 2>&1 || true
  assert_not_contains "a=$ORPHAN_ACCOUNT" "$(cat "$KC_LOG")" "no call names the orphan account"
  assert_eq "$before" "$(cat "$KC_DIR/$ORPHAN_ACCOUNT")" "orphan item untouched"
  assert_eq "$LIVE_MCP" "$(jq -c '.mcpOAuth' "$MOCK_KEYCHAIN")" "merge read the \$USER item, not the first item"
}

test_account_switch_read_failure_refuses() {
  seed_profiles
  touch "$KC_FAIL_FIND"
  local before; before=$(cat "$MOCK_KEYCHAIN")
  local output rc=0
  output=$("$ACCOUNT_SWITCH" switch "user2@gmail.com" 2>&1) || rc=$?
  assert_not_empty "$([ "$rc" != 0 ] && echo nonzero)" "switch exits nonzero when the item cannot be read"
  assert_contains "ERROR" "$output" "refusal is reported"
  assert_not_contains "add-generic-password" "$(cat "$KC_LOG")" "nothing is written"
  assert_eq "$before" "$(cat "$MOCK_KEYCHAIN")" "item unchanged"
  assert_json "$CLAUDE_ACCOUNTS_DIR/state.json" ".activeAccount" "user1@gmail.com" "state not advanced"
}

test_account_switch_missing_item_refuses() {
  seed_profiles
  rm -f "$MOCK_KEYCHAIN"
  local rc=0
  "$ACCOUNT_SWITCH" switch "user2@gmail.com" > /dev/null 2>&1 || rc=$?
  assert_not_empty "$([ "$rc" != 0 ] && echo nonzero)" "switch refuses when no \$USER item exists"
  assert_not_contains "add-generic-password" "$(cat "$KC_LOG")" "no fresh blob written"
}

test_account_switch_profile_without_oauth_refuses() {
  seed_profiles
  jq -n '{email:"user2@gmail.com",credentials:{mcpOAuth:{}},savedAt:"x"}' > "$CLAUDE_ACCOUNTS_DIR/profiles/user2@gmail.com.json"
  local before; before=$(cat "$MOCK_KEYCHAIN")
  local rc=0
  "$ACCOUNT_SWITCH" switch "user2@gmail.com" > /dev/null 2>&1 || rc=$?
  assert_not_empty "$([ "$rc" != 0 ] && echo nonzero)" "switch refuses a profile with no claudeAiOauth"
  assert_eq "$before" "$(cat "$MOCK_KEYCHAIN")" "item unchanged"
}

test_account_switch_write_idempotent() {
  seed_profiles
  "$ACCOUNT_SWITCH" switch "user2@gmail.com" > /dev/null 2>&1 || true
  local first; first=$(cat "$MOCK_KEYCHAIN")
  "$ACCOUNT_SWITCH" switch "user2@gmail.com" > /dev/null 2>&1 || true
  assert_eq "$first" "$(cat "$MOCK_KEYCHAIN")" "second identical switch leaves identical bytes"
  assert_eq "1" "$(ls "$KC_DIR" | wc -l | tr -d ' ')" "still exactly one item"
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
run_test test_account_switch_rotate_keeps_mcp_oauth
run_test test_account_switch_writes_user_account_in_place
run_test test_account_switch_never_writes_orphan_account
run_test test_account_switch_read_failure_refuses
run_test test_account_switch_missing_item_refuses
run_test test_account_switch_profile_without_oauth_refuses
run_test test_account_switch_write_idempotent
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
