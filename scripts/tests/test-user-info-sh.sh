#!/bin/bash
# ~/.claude/engine/scripts/tests/test-user-info-sh.sh — Deep coverage tests for user-info.sh
#
# Tests: cache mode, git-config mode, no-identity error, data-root, cache priority
# Covers: .user.json cache, git user.email fallback, json/username/email/domain/data-root fields
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
  unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
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
# GIT CONFIG MODE (no cache, git user.email set)
# ============================================================
echo ""
echo "--- Git Config Mode ---"

set_git_email() {
  git config --global user.email "$1"
}

test_git_username() {
  set_git_email "you@example.com"
  local output
  output=$(bash "$USER_INFO_SH" username)
  if [[ "$output" == "you" ]]; then
    pass "GIT-01: username derived from git user.email"
  else
    fail "GIT-01: username derived from git user.email" "you" "$output"
  fi
}
run_test test_git_username

test_git_email() {
  set_git_email "you@example.com"
  local output
  output=$(bash "$USER_INFO_SH" email)
  if [[ "$output" == "you@example.com" ]]; then
    pass "GIT-02: email read from git user.email"
  else
    fail "GIT-02: email read from git user.email" "you@example.com" "$output"
  fi
}
run_test test_git_email

test_git_domain() {
  set_git_email "bob@acme.org"
  local output
  output=$(bash "$USER_INFO_SH" domain)
  if [[ "$output" == "acme.org" ]]; then
    pass "GIT-03: domain derived from git user.email"
  else
    fail "GIT-03: domain derived from git user.email" "acme.org" "$output"
  fi
}
run_test test_git_domain

test_git_json() {
  set_git_email "you@example.com"
  local output
  output=$(bash "$USER_INFO_SH" json)
  if [[ "$output" == *'"username":"you"'* ]] && [[ "$output" == *'"email":"you@example.com"'* ]] && [[ "$output" == *'"domain":"example.com"'* ]]; then
    pass "GIT-04: json returns full identity from git config"
  else
    fail "GIT-04: json returns full identity from git config" '{"username":"you",...}' "$output"
  fi
}
run_test test_git_json

test_drive_symlink_ignored() {
  # A cloud-mount-shaped tools symlink is no longer an identity source
  local drive_path="$TEST_DIR/CloudSync-drive-user@other.com/shared/dev/tools"
  mkdir -p "$drive_path"
  ln -sf "$drive_path" "$HOME/.claude/tools"
  set_git_email "you@example.com"
  local output
  output=$(bash "$USER_INFO_SH" email)
  if [[ "$output" == "you@example.com" ]]; then
    pass "GIT-05: cloud-mount symlink is not an identity source"
  else
    fail "GIT-05: cloud-mount symlink is not an identity source" "you@example.com" "$output"
  fi
}
run_test test_drive_symlink_ignored

# ============================================================
# NO IDENTITY (no cache, no git user.email)
# ============================================================
echo ""
echo "--- No Identity ---"

test_no_identity_errors() {
  local output rc=0
  output=$(bash "$USER_INFO_SH" json 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" == *"git config --global user.email"* ]]; then
    pass "NOID-01: No identity -> exit 1 with git user.email hint"
  else
    fail "NOID-01: No identity -> exit 1 with git user.email hint" "rc!=0 + hint" "rc=$rc, output=$output"
  fi
}
run_test test_no_identity_errors

test_no_identity_field_stdout_empty() {
  local output rc=0
  output=$(bash "$USER_INFO_SH" username 2>/dev/null) || rc=$?
  if [[ $rc -ne 0 ]] && [[ -z "$output" ]]; then
    pass "NOID-02: No identity -> username prints nothing on stdout"
  else
    fail "NOID-02: No identity -> username prints nothing on stdout" "rc!=0, <empty>" "rc=$rc, output=$output"
  fi
}
run_test test_no_identity_field_stdout_empty

test_unknown_field_errors_without_identity() {
  local output rc=0
  output=$(bash "$USER_INFO_SH" badfield 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" == *"Unknown field"* ]]; then
    pass "NOID-03: Unknown field errors even without identity"
  else
    fail "NOID-03: Unknown field errors even without identity" "exit 1 + Unknown field" "rc=$rc, output=$output"
  fi
}
run_test test_unknown_field_errors_without_identity

# ============================================================
# DATA ROOT (local disk, identity-independent)
# ============================================================
echo ""
echo "--- Data Root ---"

test_data_root_is_local() {
  local output
  output=$(bash "$USER_INFO_SH" data-root)
  if [[ "$output" == "$HOME/.claude/data" ]]; then
    pass "ROOT-01: data-root is \$HOME/.claude/data without any identity"
  else
    fail "ROOT-01: data-root is \$HOME/.claude/data without any identity" "$HOME/.claude/data" "$output"
  fi
}
run_test test_data_root_is_local

test_data_root_with_cache() {
  echo '{"username":"testuser","email":"testuser@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"
  local output
  output=$(bash "$USER_INFO_SH" data-root)
  if [[ "$output" == "$HOME/.claude/data" ]] && [[ "$output" != *CloudSync* ]]; then
    pass "ROOT-02: data-root stays local when a cache exists"
  else
    fail "ROOT-02: data-root stays local when a cache exists" "$HOME/.claude/data" "$output"
  fi
}
run_test test_data_root_with_cache

# ============================================================
# PRIORITY: Cache takes precedence over git config
# ============================================================
echo ""
echo "--- Cache Priority ---"

test_cache_overrides_git() {
  echo '{"username":"cached-user","email":"cached@example.com","domain":"example.com"}' > "$HOME/.claude/engine/.user.json"
  set_git_email "git-user@other.com"
  local output
  output=$(bash "$USER_INFO_SH" username)
  if [[ "$output" == "cached-user" ]]; then
    pass "PRIO-01: Cache takes precedence over git config"
  else
    fail "PRIO-01: Cache takes precedence over git config" "cached-user" "$output"
  fi
}
run_test test_cache_overrides_git

# ============================================================
# RESULTS
# ============================================================

exit_with_results
