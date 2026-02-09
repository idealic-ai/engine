#!/bin/bash
# ~/.claude/engine/scripts/tests/test-user-info-sh.sh — Deep coverage tests for user-info.sh
#
# Tests: cache mode, symlink detection mode, all field types, fallback behavior
# Covers: .user.json cache, GoogleDrive symlink parsing, json/username/email/domain fields
#
# Run: bash ~/.claude/engine/scripts/tests/test-user-info-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

USER_INFO_SH="$HOME/.claude/engine/scripts/user-info.sh"

TEST_DIR=""
ORIGINAL_HOME="$HOME"

setup() {
  TEST_DIR=$(mktemp -d)
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/engine"
  mkdir -p "$HOME/.claude"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

echo "=== user-info.sh Deep Coverage Tests ==="
echo ""

# ============================================================
# CACHE MODE (.user.json exists)
# ============================================================
echo "--- Cache Mode ---"

test_cache_json_output() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  local output
  output=$(bash "$USER_INFO_SH" json)

  if [[ "$output" == *'"username":"testuser"'* ]] && [[ "$output" == *'"email":"testuser@example.com"'* ]]; then
    pass "CACHE-01: json field returns full cache content"
  else
    fail "CACHE-01: json field returns full cache content" \
      '{"username":"testuser","email":"testuser@example.com",...}' "$output"
  fi
}
run_test test_cache_json_output

test_cache_username() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  local output
  output=$(bash "$USER_INFO_SH" username)

  if [[ "$output" == "testuser" ]]; then
    pass "CACHE-02: username field extracts from cache"
  else
    fail "CACHE-02: username field extracts from cache" \
      "testuser" "$output"
  fi
}
run_test test_cache_username

test_cache_email() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  local output
  output=$(bash "$USER_INFO_SH" email)

  if [[ "$output" == "testuser@example.com" ]]; then
    pass "CACHE-03: email field extracts from cache"
  else
    fail "CACHE-03: email field extracts from cache" \
      "testuser@example.com" "$output"
  fi
}
run_test test_cache_email

test_cache_domain() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  local output
  output=$(bash "$USER_INFO_SH" domain)

  if [[ "$output" == "example.com" ]]; then
    pass "CACHE-04: domain field extracts from cache"
  else
    fail "CACHE-04: domain field extracts from cache" \
      "example.com" "$output"
  fi
}
run_test test_cache_domain

test_cache_default_json() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  # No argument = json
  local output
  output=$(bash "$USER_INFO_SH")

  if [[ "$output" == *'"username":"testuser"'* ]]; then
    pass "CACHE-05: Default (no arg) returns json"
  else
    fail "CACHE-05: Default (no arg) returns json" \
      "json output" "$output"
  fi
}
run_test test_cache_default_json

test_cache_unknown_field_errors() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  local output
  output=$(bash "$USER_INFO_SH" badfield 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Unknown field"* ]]; then
    pass "CACHE-06: Unknown field errors"
  else
    fail "CACHE-06: Unknown field errors" \
      "exit 1 + Unknown field" "rc=$rc, output=$output"
  fi
}
run_test test_cache_unknown_field_errors

# ============================================================
# SYMLINK DETECTION MODE (no cache, symlink exists)
# ============================================================
echo ""
echo "--- Symlink Detection Mode ---"

test_symlink_detection_username() {
  # Create a fake GoogleDrive path and symlink
  local gdrive_path="$TEST_DIR/GoogleDrive-yarik@finchclaims.com/Shared drives/dev/tools"
  mkdir -p "$gdrive_path"
  ln -sf "$gdrive_path" "$HOME/.claude/tools"

  local output
  output=$(bash "$USER_INFO_SH" username)

  if [[ "$output" == "yarik" ]]; then
    pass "SYM-01: Extracts username from GoogleDrive symlink"
  else
    fail "SYM-01: Extracts username from GoogleDrive symlink" \
      "yarik" "$output"
  fi
}
run_test test_symlink_detection_username

test_symlink_detection_email() {
  local gdrive_path="$TEST_DIR/GoogleDrive-yarik@finchclaims.com/Shared drives/dev/tools"
  mkdir -p "$gdrive_path"
  ln -sf "$gdrive_path" "$HOME/.claude/tools"

  local output
  output=$(bash "$USER_INFO_SH" email)

  if [[ "$output" == "yarik@finchclaims.com" ]]; then
    pass "SYM-02: Extracts email from GoogleDrive symlink"
  else
    fail "SYM-02: Extracts email from GoogleDrive symlink" \
      "yarik@finchclaims.com" "$output"
  fi
}
run_test test_symlink_detection_email

test_symlink_detection_domain() {
  local gdrive_path="$TEST_DIR/GoogleDrive-yarik@finchclaims.com/Shared drives/dev/tools"
  mkdir -p "$gdrive_path"
  ln -sf "$gdrive_path" "$HOME/.claude/tools"

  local output
  output=$(bash "$USER_INFO_SH" domain)

  if [[ "$output" == "finchclaims.com" ]]; then
    pass "SYM-03: Extracts domain from GoogleDrive symlink"
  else
    fail "SYM-03: Extracts domain from GoogleDrive symlink" \
      "finchclaims.com" "$output"
  fi
}
run_test test_symlink_detection_domain

test_symlink_detection_json() {
  local gdrive_path="$TEST_DIR/GoogleDrive-yarik@finchclaims.com/Shared drives/dev/tools"
  mkdir -p "$gdrive_path"
  ln -sf "$gdrive_path" "$HOME/.claude/tools"

  local output
  output=$(bash "$USER_INFO_SH" json)

  if [[ "$output" == *'"username":"yarik"'* ]] && [[ "$output" == *'"email":"yarik@finchclaims.com"'* ]] && [[ "$output" == *'"domain":"finchclaims.com"'* ]]; then
    pass "SYM-04: json returns full identity from symlink"
  else
    fail "SYM-04: json returns full identity from symlink" \
      '{"username":"yarik",...}' "$output"
  fi
}
run_test test_symlink_detection_json

test_symlink_different_email() {
  local gdrive_path="$TEST_DIR/GoogleDrive-bob@acme.org/Shared drives/dev/tools"
  mkdir -p "$gdrive_path"
  ln -sf "$gdrive_path" "$HOME/.claude/tools"

  local email domain
  email=$(bash "$USER_INFO_SH" email)
  domain=$(bash "$USER_INFO_SH" domain)

  if [[ "$email" == "bob@acme.org" ]] && [[ "$domain" == "acme.org" ]]; then
    pass "SYM-05: Works with different email/domain combo"
  else
    fail "SYM-05: Works with different email/domain combo" \
      "bob@acme.org / acme.org" "$email / $domain"
  fi
}
run_test test_symlink_different_email

# ============================================================
# FALLBACK MODE (no cache, no valid symlink)
# ============================================================
echo ""
echo "--- Fallback Mode ---"

test_no_symlink_json_returns_nulls() {
  # No cache, no tools symlink
  local output
  output=$(bash "$USER_INFO_SH" json)

  if [[ "$output" == *'"username":null'* ]] && [[ "$output" == *'"email":null'* ]]; then
    pass "FALL-01: No symlink → json returns null fields"
  else
    fail "FALL-01: No symlink → json returns null fields" \
      '{"username":null,"email":null,"domain":null}' "$output"
  fi
}
run_test test_no_symlink_json_returns_nulls

test_no_symlink_field_returns_empty() {
  local output
  output=$(bash "$USER_INFO_SH" username)

  if [[ -z "$output" ]]; then
    pass "FALL-02: No symlink → username returns empty"
  else
    fail "FALL-02: No symlink → username returns empty" \
      "<empty>" "$output"
  fi
}
run_test test_no_symlink_field_returns_empty

test_non_gdrive_symlink_returns_nulls() {
  # Symlink exists but doesn't match GoogleDrive pattern
  mkdir -p "$TEST_DIR/some-other-path/tools"
  ln -sf "$TEST_DIR/some-other-path/tools" "$HOME/.claude/tools"

  local output
  output=$(bash "$USER_INFO_SH" json)

  if [[ "$output" == *'"username":null'* ]]; then
    pass "FALL-03: Non-GoogleDrive symlink → null identity"
  else
    fail "FALL-03: Non-GoogleDrive symlink → null identity" \
      '{"username":null,...}' "$output"
  fi
}
run_test test_non_gdrive_symlink_returns_nulls

test_fallback_unknown_field_errors() {
  local output
  output=$(bash "$USER_INFO_SH" badfield 2>&1)
  local rc=$?

  # No cache, falls through to symlink path, then hits unknown field
  # Behavior depends on path taken — but should either error or return empty
  if [[ $rc -eq 0 ]] && [[ -z "$output" ]]; then
    pass "FALL-04: Unknown field in fallback mode returns empty"
  elif [[ $rc -ne 0 ]]; then
    pass "FALL-04: Unknown field in fallback mode errors"
  else
    fail "FALL-04: Unknown field in fallback mode" \
      "exit 1 or empty" "rc=$rc, output=$output"
  fi
}
run_test test_fallback_unknown_field_errors

# ============================================================
# PRIORITY: Cache takes precedence over symlink
# ============================================================
echo ""
echo "--- Cache Priority ---"

test_cache_overrides_symlink() {
  # Both cache AND symlink exist — cache should win
  echo '{"username":"cached-user","email":"cached@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"

  local gdrive_path="$TEST_DIR/GoogleDrive-symlink-user@other.com/Shared drives/dev/tools"
  mkdir -p "$gdrive_path"
  ln -sf "$gdrive_path" "$HOME/.claude/tools"

  local output
  output=$(bash "$USER_INFO_SH" username)

  if [[ "$output" == "cached-user" ]]; then
    pass "PRIO-01: Cache takes precedence over symlink"
  else
    fail "PRIO-01: Cache takes precedence over symlink" \
      "cached-user" "$output"
  fi
}
run_test test_cache_overrides_symlink

# ============================================================
# RESULTS
# ============================================================

exit_with_results
