#!/bin/bash
# test-preload-seed.sh — Tests for seed file lifecycle
#
# Tests: seed creation, propagation via hooks, merge into session .state.json,
# stale cleanup, and edge cases.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

# --- Setup/Teardown ---

setup() {
  setup_test_env "test_seed_session"

  # Symlink engine scripts and directives needed by lib.sh functions
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  mkdir -p "$FAKE_HOME/.claude/engine/scripts"
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  ln -sf "$REAL_ENGINE_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/engine/scripts/lib.sh"
  ln -sf "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/engine/scripts/session.sh"
  ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh" 2>/dev/null || true

  # Create minimal directive files (for seeds list)
  for f in COMMANDS.md INVARIANTS.md SIGILS.md; do
    echo "# $f" > "$FAKE_HOME/.claude/engine/.directives/$f"
  done
  for f in CMD_DEHYDRATE.md CMD_RESUME_SESSION.md CMD_PARSE_PARAMETERS.md; do
    echo "# $f" > "$FAKE_HOME/.claude/engine/.directives/commands/$f"
  done

  # Create symlink ~/.claude/.directives → ~/.claude/engine/.directives
  ln -sf "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"

  # Re-source lib.sh with the new HOME
  unset _LIB_SH_LOADED
  source "$FAKE_HOME/.claude/scripts/lib.sh"
}

teardown() {
  # Nothing — cleanup_test_env handles it
  :
}

trap cleanup_test_env EXIT

# --- Tests ---

test_find_preload_state_creates_seed() {
  # When no session and no seed exists, find_preload_state creates a seed
  local result
  result=$(find_preload_state "$$")
  assert_contains ".seeds/" "$result" "returns seed path"
  assert_file_exists "$result" "seed file created"

  local lifecycle
  lifecycle=$(jq -r '.lifecycle' "$result")
  assert_eq "seeding" "$lifecycle" "seed lifecycle is 'seeding'"

  local pid
  pid=$(jq -r '.pid' "$result")
  assert_eq "$$" "$pid" "seed PID matches"

  local preloaded_count
  preloaded_count=$(jq '.preloadedFiles | length' "$result")
  assert_eq "6" "$preloaded_count" "seed has 6 core standards"
}

test_find_preload_state_returns_existing_seed() {
  # Second call returns the same seed, doesn't create a new one
  local result1 result2
  result1=$(find_preload_state "$$")
  result2=$(find_preload_state "$$")
  assert_eq "$result1" "$result2" "same seed returned on second call"
}

test_find_preload_state_returns_session_over_seed() {
  # When an active session exists, returns session .state.json instead of seed
  # session.sh find uses CLAUDE_SUPERVISOR_PID (set to 99999999 in test env)
  local pid="${CLAUDE_SUPERVISOR_PID:-99999999}"
  # Create a seed first
  find_preload_state "$pid" > /dev/null

  # Create an active session with the supervisor PID (so session.sh find matches)
  mkdir -p "$TMP_DIR/sessions/test_active"
  echo "{\"pid\": $pid, \"lifecycle\": \"active\", \"skill\": \"implement\", \"preloadedFiles\": []}" \
    > "$TMP_DIR/sessions/test_active/.state.json"

  local result
  result=$(find_preload_state "$pid")
  assert_contains "test_active/.state.json" "$result" "returns session state, not seed"
}

test_seed_stale_cleanup() {
  # Seeds with dead PIDs are cleaned up by SessionStart
  local seeds_dir="$TMP_DIR/sessions/.seeds"
  mkdir -p "$seeds_dir"

  # Create a seed for a dead PID (99999 should not exist)
  echo '{"pid":99999,"lifecycle":"seeding","preloadedFiles":[]}' > "$seeds_dir/99999.json"
  assert_file_exists "$seeds_dir/99999.json" "stale seed exists before cleanup"

  # Simulate what SessionStart does: check PID liveness
  local seed_pid
  seed_pid=$(jq -r '.pid // 0' "$seeds_dir/99999.json")
  if ! kill -0 "$seed_pid" 2>/dev/null; then
    rm -f "$seeds_dir/99999.json"
  fi

  assert_file_not_exists "$seeds_dir/99999.json" "stale seed cleaned up"
}

test_seed_merge_into_session() {
  # Seed's preloadedFiles are merged into session .state.json
  local seeds_dir="$TMP_DIR/sessions/.seeds"
  mkdir -p "$seeds_dir"

  # Create a seed with extra tracked files
  jq -n '{
    pid: 12345,
    lifecycle: "seeding",
    preloadedFiles: ["/path/a.md", "/path/b.md"],
    pendingPreloads: ["/path/c.md"],
    touchedDirs: {"/some/dir": []}
  }' > "$seeds_dir/12345.json"

  # Create a session .state.json with its own preloaded files
  mkdir -p "$TMP_DIR/sessions/merge_test"
  jq -n '{
    pid: 12345,
    lifecycle: "active",
    skill: "implement",
    preloadedFiles: ["/path/b.md", "/path/d.md"],
    pendingPreloads: [],
    touchedDirs: {}
  }' > "$TMP_DIR/sessions/merge_test/.state.json"

  local state_file="$TMP_DIR/sessions/merge_test/.state.json"
  local seed_file="$seeds_dir/12345.json"

  # Simulate merge (same logic as session.sh activate)
  jq -s '
    (.[0].preloadedFiles // []) as $sp |
    (.[1].preloadedFiles // []) as $seedp |
    (.[0].pendingPreloads // []) as $pp |
    (.[1].pendingPreloads // []) as $seedpp |
    (.[0].touchedDirs // {}) as $td |
    (.[1].touchedDirs // {}) as $seedtd |
    .[0] |
    .preloadedFiles = ($sp + $seedp | unique) |
    .pendingPreloads = ($pp + $seedpp | unique) |
    .touchedDirs = ($td * $seedtd)
  ' "$state_file" "$seed_file" | safe_json_write "$state_file"
  rm -f "$seed_file"

  # Verify merge
  local preloaded_count
  preloaded_count=$(jq '.preloadedFiles | length' "$state_file")
  assert_eq "3" "$preloaded_count" "merged preloadedFiles has 3 unique entries (a, b, d)"

  local has_a has_c
  has_a=$(jq 'any(.preloadedFiles[]; . == "/path/a.md")' "$state_file")
  has_c=$(jq 'any(.pendingPreloads[]; . == "/path/c.md")' "$state_file")
  assert_eq "true" "$has_a" "seed's /path/a.md merged"
  assert_eq "true" "$has_c" "seed's pendingPreloads /path/c.md merged"

  assert_file_not_exists "$seed_file" "seed deleted after merge"
}

test_seed_without_activation() {
  # Seed persists if no activation happens — no crash, no orphan
  local result
  result=$(find_preload_state "$$")
  assert_file_exists "$result" "seed persists without activation"

  # Write something to the seed
  jq '.preloadedFiles += ["/extra/file.md"]' "$result" | safe_json_write "$result"
  local count
  count=$(jq '.preloadedFiles | length' "$result")
  assert_eq "7" "$count" "seed updated with extra file"
}

test_multiple_seeds_per_pid() {
  # Different PIDs get different seed files
  local seed1 seed2
  seed1=$(find_preload_state "10001")
  seed2=$(find_preload_state "10002")
  assert_neq "$seed1" "$seed2" "different PIDs get different seeds"
  assert_file_exists "$seed1" "seed 1 exists"
  assert_file_exists "$seed2" "seed 2 exists"
}

test_log_delivery_noop_when_unset() {
  # _log_delivery is a no-op when PRELOAD_TEST_LOG is not set
  unset PRELOAD_TEST_LOG 2>/dev/null || true
  _log_delivery "test" "event" "file" "source"
  # No crash = pass
  pass "_log_delivery no-op when PRELOAD_TEST_LOG unset"
}

test_log_delivery_writes_when_set() {
  local log_file="$TMP_DIR/delivery.log"
  PRELOAD_TEST_LOG="$log_file" _log_delivery "test-hook" "direct-deliver" "/path/file.md" "test-source"

  assert_file_exists "$log_file" "delivery log created"
  local hook
  hook=$(jq -r '.hook' "$log_file")
  assert_eq "test-hook" "$hook" "hook field correct"
  local event
  event=$(jq -r '.event' "$log_file")
  assert_eq "direct-deliver" "$event" "event field correct"
}

# --- Run ---
run_discovered_tests
