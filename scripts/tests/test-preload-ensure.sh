#!/bin/bash
# test-preload-ensure.sh — Tests for preload_ensure() single entry point
#
# Tests: dedup (path + inode), immediate vs next urgency, atomic state tracking,
# auto-expand refs, SKILL.md CMD exclusion.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

# --- Setup/Teardown ---

setup() {
  setup_test_env "test_ensure_session"

  # Symlink engine scripts and directives
  mkdir -p "$FAKE_HOME/.claude/engine/scripts"
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  ln -sf "$REAL_ENGINE_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/engine/scripts/lib.sh"
  ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh" 2>/dev/null || true

  # Create minimal directive files
  for f in COMMANDS.md INVARIANTS.md SIGILS.md; do
    echo "# $f" > "$FAKE_HOME/.claude/engine/.directives/$f"
  done
  for f in CMD_DEHYDRATE.md CMD_RESUME_SESSION.md CMD_PARSE_PARAMETERS.md; do
    echo "# $f" > "$FAKE_HOME/.claude/engine/.directives/commands/$f"
  done

  # Symlink ~/.claude/.directives → engine
  ln -sf "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"

  # Create test content files
  TEST_CONTENT_DIR="$TMP_DIR/content"
  mkdir -p "$TEST_CONTENT_DIR"
  echo "# Test File A" > "$TEST_CONTENT_DIR/file_a.md"
  echo "# Test File B" > "$TEST_CONTENT_DIR/file_b.md"
  echo "# Test File C with §CMD_DEHYDRATE ref" > "$TEST_CONTENT_DIR/file_with_ref.md"

  # Create a session with a state file for testing
  jq -n --argjson pid "$$" '{
    pid: $pid,
    lifecycle: "active",
    skill: "implement",
    preloadedFiles: [],
    pendingPreloads: [],
    touchedDirs: {}
  }' > "$TEST_SESSION/.state.json"

  # Re-source lib.sh
  unset _LIB_SH_LOADED
  source "$FAKE_HOME/.claude/scripts/lib.sh"

  # Set HOOK_NAME for log_delivery calls
  export HOOK_NAME="test"
}

teardown() {
  teardown_fake_home
  rm -rf "${TMP_DIR:-}"
}

trap cleanup_test_env EXIT

# --- Tests ---

test_preload_ensure_immediate_delivers() {
  # immediate urgency: delivers content and tracks in preloadedFiles
  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "result is 'delivered'"
  assert_not_empty "$_PRELOAD_CONTENT" "content is set"
  assert_contains "Test File A" "$_PRELOAD_CONTENT" "content contains file text"

  # Check state tracking
  local state_file
  state_file=$(find_preload_state)
  local norm_path
  norm_path=$(normalize_preload_path "$TEST_CONTENT_DIR/file_a.md")
  local tracked
  tracked=$(jq -r --arg p "$norm_path" '.preloadedFiles | any(. == $p)' "$state_file")
  assert_eq "true" "$tracked" "file tracked in preloadedFiles"
}

test_preload_ensure_next_queues() {
  # next urgency: queues to pendingPreloads, doesn't deliver content
  preload_ensure "$TEST_CONTENT_DIR/file_b.md" "test" "next"
  assert_eq "queued" "$_PRELOAD_RESULT" "result is 'queued'"
  assert_empty "$_PRELOAD_CONTENT" "no content for queued delivery"

  # Check state tracking
  local state_file
  state_file=$(find_preload_state)
  local norm_path
  norm_path=$(normalize_preload_path "$TEST_CONTENT_DIR/file_b.md")
  local queued
  queued=$(jq -r --arg p "$norm_path" '.pendingPreloads | any(. == $p)' "$state_file")
  assert_eq "true" "$queued" "file queued in pendingPreloads"
}

test_preload_ensure_dedup_skips() {
  # Second call for same file skips
  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "first call delivers"

  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"
  assert_eq "skipped" "$_PRELOAD_RESULT" "second call skips (dedup)"
}

test_preload_ensure_inode_dedup() {
  # Hardlink to same file is deduped via inode
  local link_path="$TEST_CONTENT_DIR/file_a_link.md"
  ln "$TEST_CONTENT_DIR/file_a.md" "$link_path"

  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "original delivered"

  preload_ensure "$link_path" "test" "immediate"
  assert_eq "skipped" "$_PRELOAD_RESULT" "hardlink skipped (inode dedup)"
}

test_preload_ensure_nonexistent_skips() {
  # Non-existent file: immediate returns skipped (no crash)
  preload_ensure "/nonexistent/file.md" "test" "immediate"
  assert_eq "skipped" "$_PRELOAD_RESULT" "nonexistent file skipped"
}

test_preload_ensure_delivery_log() {
  # With PRELOAD_TEST_LOG set, events are logged
  local log_file="$TMP_DIR/delivery.log"
  export PRELOAD_TEST_LOG="$log_file"

  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"

  assert_file_exists "$log_file" "delivery log created"
  local event
  event=$(head -1 "$log_file" | jq -r '.event')
  assert_eq "direct-deliver" "$event" "delivery event logged"

  # Second call should log skip
  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"
  local skip_event
  skip_event=$(tail -1 "$log_file" | jq -r '.event')
  assert_eq "skip-dedup" "$skip_event" "skip event logged"

  unset PRELOAD_TEST_LOG
}

test_preload_ensure_uses_seed_when_no_session() {
  # When no active session, preload_ensure uses/creates a seed
  # Remove the test session state
  rm -f "$TEST_SESSION/.state.json"

  preload_ensure "$TEST_CONTENT_DIR/file_a.md" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "delivered via seed state"

  # Check that a seed file was used
  local state_file
  state_file=$(find_preload_state)
  assert_contains ".seeds/" "$state_file" "state is a seed file"
}

# --- Run ---
run_discovered_tests
