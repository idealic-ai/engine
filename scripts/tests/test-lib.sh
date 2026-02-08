#!/bin/bash
# ~/.claude/engine/scripts/tests/test-lib.sh — Unit tests for lib.sh shared utilities
#
# Tests all 5 functions: timestamp, pid_exists, hook_allow, hook_deny, safe_json_write
#
# Run: bash ~/.claude/engine/scripts/tests/test-lib.sh

set -uo pipefail

LIB_SH="$HOME/.claude/scripts/lib.sh"

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  # Link lib.sh into the fake home
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  # Unset guard to allow re-sourcing
  unset _LIB_SH_LOADED
  # Source lib.sh
  source "$HOME/.claude/scripts/lib.sh"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  unset _LIB_SH_LOADED
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

pass() {
  echo -e "${GREEN}PASS${RESET}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}FAIL${RESET}: $1"
  echo "  Expected: $2"
  echo "  Got: $3"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# =============================================================================
# TIMESTAMP TESTS
# =============================================================================

test_timestamp_iso_format() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="timestamp: outputs ISO format"
  setup

  local result
  result=$(timestamp)

  # Match pattern: YYYY-MM-DDTHH:MM:SSZ
  if [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    pass "$test_name"
  else
    fail "$test_name" "YYYY-MM-DDTHH:MM:SSZ pattern" "$result"
  fi

  teardown
}

# =============================================================================
# PID_EXISTS TESTS
# =============================================================================

test_pid_exists_running() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="pid_exists: returns 0 for running PID"
  setup

  if pid_exists $$; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 for PID $$" "non-zero exit"
  fi

  teardown
}

test_pid_exists_dead() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="pid_exists: returns 1 for dead PID"
  setup

  if pid_exists 99999999; then
    fail "$test_name" "exit 1 for PID 99999999" "exit 0"
  else
    pass "$test_name"
  fi

  teardown
}

# =============================================================================
# HOOK_ALLOW TESTS
# =============================================================================

test_hook_allow_json() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="hook_allow: outputs correct JSON"
  setup

  # hook_allow calls exit 0, so run in subshell
  local result
  result=$(hook_allow)
  local expected='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

  if [ "$result" = "$expected" ]; then
    pass "$test_name"
  else
    fail "$test_name" "$expected" "$result"
  fi

  teardown
}

# =============================================================================
# HOOK_DENY TESTS
# =============================================================================

test_hook_deny_json() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="hook_deny: outputs correct JSON with all 3 args"
  setup

  # hook_deny calls exit 0, so run in subshell
  local result
  result=$(hook_deny "Access denied" "Please activate a session first" "session_dir=/tmp/test")

  # Parse with jq to verify structure
  local decision reason
  decision=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecision')
  reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason')

  if [ "$decision" = "deny" ] && [[ "$reason" == *"Access denied"* ]] && [[ "$reason" == *"Please activate a session first"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "deny decision with reason containing both messages" "decision=$decision, reason=$reason"
  fi

  teardown
}

test_hook_deny_debug_included() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="hook_deny: DEBUG=1 includes debug info"
  setup

  local result
  DEBUG=1 result=$(hook_deny "Error" "Fix it" "debug_data=123")

  local reason
  reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason')

  if [[ "$reason" == *"debug_data=123"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "reason containing debug_data=123" "$reason"
  fi

  teardown
}

test_hook_deny_debug_excluded() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="hook_deny: DEBUG unset excludes debug info"
  setup

  local result
  unset DEBUG
  result=$(hook_deny "Error" "Fix it" "debug_data=123")

  local reason
  reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason')

  if [[ "$reason" != *"debug_data=123"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "reason NOT containing debug_data=123" "$reason"
  fi

  teardown
}

# =============================================================================
# SAFE_JSON_WRITE TESTS
# =============================================================================

test_safe_json_write_valid() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="safe_json_write: valid JSON writes atomically"
  setup

  local target="$TEST_DIR/test.json"
  echo '{"hello":"world"}' | safe_json_write "$target"
  local exit_code=$?

  local content
  content=$(cat "$target")

  if [ "$exit_code" -eq 0 ] && [ "$content" = '{"hello":"world"}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and content={\"hello\":\"world\"}" "exit=$exit_code, content=$content"
  fi

  teardown
}

test_safe_json_write_invalid() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="safe_json_write: invalid JSON is rejected"
  setup

  local target="$TEST_DIR/test.json"
  echo '{"hello":"world"}' > "$target"

  local exit_code=0
  echo 'not json at all' | safe_json_write "$target" 2>/dev/null || exit_code=$?

  local content
  content=$(cat "$target")

  if [ "$exit_code" -ne 0 ] && [ "$content" = '{"hello":"world"}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero and file unchanged" "exit=$exit_code, content=$content"
  fi

  teardown
}

test_safe_json_write_concurrent() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="safe_json_write: concurrent writes don't corrupt"
  setup

  local target="$TEST_DIR/concurrent.json"
  echo '{"init":true}' > "$target"

  # Launch two concurrent writes
  (echo '{"writer":"A"}' | safe_json_write "$target") &
  local pid_a=$!
  (echo '{"writer":"B"}' | safe_json_write "$target") &
  local pid_b=$!

  wait "$pid_a" "$pid_b"

  # Result should be valid JSON (either A or B wins, but no corruption)
  local content
  content=$(cat "$target")
  if echo "$content" | jq empty 2>/dev/null; then
    local writer
    writer=$(echo "$content" | jq -r '.writer')
    if [ "$writer" = "A" ] || [ "$writer" = "B" ]; then
      pass "$test_name"
    else
      fail "$test_name" "writer=A or writer=B" "writer=$writer"
    fi
  else
    fail "$test_name" "valid JSON after concurrent writes" "corrupted: $content"
  fi

  teardown
}

test_safe_json_write_stale_lock() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="safe_json_write: stale lock is cleaned up"
  setup

  local target="$TEST_DIR/locked.json"
  local lock_dir="${target}.lock"

  # Create a stale lock (make it look old)
  mkdir "$lock_dir"
  # Touch with old timestamp (>10s ago)
  touch -t 202601010000 "$lock_dir"

  local exit_code=0
  echo '{"recovered":true}' | safe_json_write "$target" || exit_code=$?

  local content
  content=$(cat "$target" 2>/dev/null || echo "")

  if [ "$exit_code" -eq 0 ] && [ "$content" = '{"recovered":true}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and recovered content" "exit=$exit_code, content=$content"
  fi

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-lib.sh ==="

# timestamp
test_timestamp_iso_format

# pid_exists
test_pid_exists_running
test_pid_exists_dead

# hook_allow
test_hook_allow_json

# hook_deny
test_hook_deny_json
test_hook_deny_debug_included
test_hook_deny_debug_excluded

# safe_json_write
test_safe_json_write_valid
test_safe_json_write_invalid
test_safe_json_write_concurrent
test_safe_json_write_stale_lock

# Summary
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_RUN total"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
