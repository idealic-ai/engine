#!/bin/bash
# test-preload-pipeline.sh — Cross-hook pipeline integration tests
#
# Tests the full preload pipeline: discovery → delivery → dedup across
# multiple directory touches. Reproduces the AGENTS.md re-delivery bug
# where preloadedFiles stays stuck at 6 seeds despite delivery.
#
# Bug: When _run_discovery finds AGENTS.md for dir A, it gets delivered
# via preload_ensure(immediate). When dir B triggers discovery and finds
# the same AGENTS.md, preloadedFiles should prevent re-queuing. If
# preloadedFiles doesn't grow after delivery, AGENTS.md gets re-delivered.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

# --- Setup/Teardown ---

setup() {
  setup_test_env "test_pipeline_session"

  # Symlink engine scripts and directives
  mkdir -p "$FAKE_HOME/.claude/engine/scripts"
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  ln -sf "$REAL_ENGINE_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/engine/scripts/lib.sh"
  ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh" 2>/dev/null || true

  # Create minimal seed directive files (the 6 core seeds)
  for f in COMMANDS.md INVARIANTS.md SIGILS.md; do
    echo "# $f content" > "$FAKE_HOME/.claude/engine/.directives/$f"
  done
  for f in CMD_DEHYDRATE.md CMD_RESUME_SESSION.md CMD_PARSE_PARAMETERS.md; do
    echo "# $f content" > "$FAKE_HOME/.claude/engine/.directives/commands/$f"
  done

  # Symlink ~/.claude/.directives → engine/.directives (mirrors real setup)
  ln -sf "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"

  # Create AGENTS.md at the engine level (the file that gets re-delivered)
  echo "# Workflow Engine AGENTS" > "$FAKE_HOME/.claude/engine/.directives/AGENTS.md"

  # Create directory structure that triggers walk-up discovery
  # Both dir_a and dir_b are under ~/.claude/engine/ and share AGENTS.md ancestor
  mkdir -p "$FAKE_HOME/.claude/engine/hooks"
  mkdir -p "$FAKE_HOME/.claude/engine/scripts/tests"
  echo "# hook file" > "$FAKE_HOME/.claude/engine/hooks/test-hook.sh"
  echo "# test file" > "$FAKE_HOME/.claude/engine/scripts/tests/test-file.sh"

  # Copy discover-directives.sh (needed by _run_discovery)
  cp "$REAL_ENGINE_DIR/scripts/discover-directives.sh" "$FAKE_HOME/.claude/scripts/discover-directives.sh" 2>/dev/null || true
  chmod +x "$FAKE_HOME/.claude/scripts/discover-directives.sh" 2>/dev/null || true

  # Build the 6 seeds array (absolute paths, resolved through symlinks)
  local engine_dir
  engine_dir=$(cd "$FAKE_HOME/.claude/.directives" 2>/dev/null && pwd -P)
  SEEDS=$(jq -n --arg d "$engine_dir" \
    '[$d+"/COMMANDS.md",$d+"/INVARIANTS.md",$d+"/SIGILS.md",$d+"/commands/CMD_DEHYDRATE.md",$d+"/commands/CMD_RESUME_SESSION.md",$d+"/commands/CMD_PARSE_PARAMETERS.md"]')

  # Create session .state.json with 6 seeds
  # PID must match CLAUDE_SUPERVISOR_PID so session.sh find locates this session
  jq -n --argjson pid "${CLAUDE_SUPERVISOR_PID:-$$}" --argjson seeds "$SEEDS" '{
    pid: $pid,
    lifecycle: "active",
    skill: "implement",
    preloadedFiles: $seeds,
    pendingPreloads: [],
    touchedDirs: {},
    pendingAllowInjections: [],
    directives: ["AGENTS.md"]
  }' > "$TEST_SESSION/.state.json"

  STATE_FILE="$TEST_SESSION/.state.json"

  # Re-source lib.sh with new HOME
  unset _LIB_SH_LOADED
  source "$FAKE_HOME/.claude/scripts/lib.sh"

  export HOOK_NAME="pipeline-test"
}

teardown() {
  teardown_fake_home
  rm -rf "${TMP_DIR:-}"
}

trap cleanup_test_env EXIT

# --- Helper: count preloadedFiles ---
count_preloaded() {
  jq '.preloadedFiles | length' "$STATE_FILE"
}

# --- Helper: check if path is in preloadedFiles ---
is_preloaded() {
  local path="$1"
  jq -r --arg p "$path" '.preloadedFiles | any(. == $p)' "$STATE_FILE"
}

# --- Helper: count pendingPreloads ---
count_pending() {
  jq '.pendingPreloads | length' "$STATE_FILE"
}

# --- Tests ---

test_P1_preloaded_files_grows_after_immediate_delivery() {
  # BASELINE: preloadedFiles starts with exactly 6 seeds
  local before
  before=$(count_preloaded)
  assert_eq "6" "$before" "P1: starts with 6 seeds"

  # Create a file to deliver
  local test_file="$TMP_DIR/content/agents.md"
  mkdir -p "$TMP_DIR/content"
  echo "# AGENTS content" > "$test_file"

  # Deliver via preload_ensure(immediate)
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P1: file delivered"

  # CRITICAL ASSERTION: preloadedFiles should now have 7 entries
  local after
  after=$(count_preloaded)
  assert_eq "7" "$after" "P1: preloadedFiles grew from 6 to 7 after delivery"
}

test_P2_dedup_prevents_redelivery_after_tracking() {
  # Deliver a file
  local test_file="$TMP_DIR/content/test.md"
  mkdir -p "$TMP_DIR/content"
  echo "# test content" > "$test_file"

  preload_ensure "$test_file" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P2: first delivery succeeds"

  # Second delivery should be skipped
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "skipped" "$_PRELOAD_RESULT" "P2: second delivery skipped (dedup)"
}

test_P3_discovery_jq_dedup_filters_preloaded_files() {
  # Simulate _run_discovery's jq dedup check in isolation
  # Add a file to preloadedFiles first
  local agents_path
  agents_path=$(normalize_preload_path "$FAKE_HOME/.claude/engine/.directives/AGENTS.md")

  jq --arg p "$agents_path" '
    .preloadedFiles += [$p] | .preloadedFiles |= unique
  ' "$STATE_FILE" | safe_json_write "$STATE_FILE"

  # Now run the same jq that _run_discovery uses (lines 245-261 of overflow-v2)
  local files_json
  files_json=$(jq -n --arg f "$agents_path" '[$f]')

  local result_pending
  result_pending=$(jq --argjson files "$files_json" '
    (.preloadedFiles // []) as $pf |
    (.pendingPreloads //= []) |
    reduce ($files[]) as $f (.;
      if ($pf | any(. == $f)) then .
      elif (.pendingPreloads | index($f)) then .
      else .pendingPreloads += [$f]
      end
    ) | .pendingPreloads | length
  ' "$STATE_FILE")

  assert_eq "0" "$result_pending" "P3: file already in preloadedFiles → NOT added to pendingPreloads"
}

test_P4_discovery_then_delivery_then_rediscovery_no_duplicate() {
  # THE BUG REPRODUCTION TEST
  # Simulates: dir A discovered → AGENTS.md queued → delivered → dir B discovered → should NOT re-queue

  local agents_path
  agents_path=$(normalize_preload_path "$FAKE_HOME/.claude/engine/.directives/AGENTS.md")

  # Step 1: Simulate _run_discovery adding AGENTS.md to pendingPreloads
  # (as if discover-directives.sh walked up from dir A and found it)
  jq --arg f "$agents_path" '
    .pendingPreloads += [$f] | .pendingPreloads |= unique
  ' "$STATE_FILE" | safe_json_write "$STATE_FILE"

  local pending_after_discovery
  pending_after_discovery=$(count_pending)
  assert_eq "1" "$pending_after_discovery" "P4: AGENTS.md queued after dir A discovery"

  # Step 2: Simulate preload rule delivery (what _deliver_allow_rules does)
  preload_ensure "$agents_path" "overflow(preload)" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P4: AGENTS.md delivered"

  # Step 2b: Simulate cleanup (remove from pendingPreloads)
  local norm_path
  norm_path=$(normalize_preload_path "$agents_path")
  local processed_json
  processed_json=$(jq -n --arg p "$agents_path" --arg n "$norm_path" '[$p, $n] | unique')
  jq --argjson proc "$processed_json" '
    (.pendingPreloads //= []) | .pendingPreloads -= $proc
  ' "$STATE_FILE" | safe_json_write "$STATE_FILE"

  # Verify: preloadedFiles should have AGENTS.md
  local is_tracked
  is_tracked=$(is_preloaded "$agents_path")
  assert_eq "true" "$is_tracked" "P4: AGENTS.md in preloadedFiles after delivery"

  local preloaded_count
  preloaded_count=$(count_preloaded)
  assert_eq "7" "$preloaded_count" "P4: preloadedFiles count is 7 (6 seeds + AGENTS.md)"

  # Step 3: Simulate _run_discovery for dir B finding same AGENTS.md
  # This is the _run_discovery jq from lines 245-261 of overflow-v2
  local files_json
  files_json=$(jq -n --arg f "$agents_path" '[$f]')
  jq --argjson files "$files_json" '
    (.preloadedFiles // []) as $pf |
    (.pendingPreloads //= []) |
    reduce ($files[]) as $f (.;
      if ($pf | any(. == $f)) then .
      elif (.pendingPreloads | index($f)) then .
      else .pendingPreloads += [$f]
      end
    )
  ' "$STATE_FILE" | safe_json_write "$STATE_FILE"

  # CRITICAL: pendingPreloads should be empty (AGENTS.md already in preloadedFiles)
  local pending_after_rediscovery
  pending_after_rediscovery=$(count_pending)
  assert_eq "0" "$pending_after_rediscovery" "P4: AGENTS.md NOT re-queued (dedup via preloadedFiles)"
}

test_P5_injections_hook_cleanup_preserves_preloaded() {
  # Simulate: preloadedFiles has 7 entries + pendingAllowInjections has content
  # After injections hook clears stash, preloadedFiles should still have 7

  local test_file="$TMP_DIR/content/test_p5.md"
  mkdir -p "$TMP_DIR/content"
  echo "# P5 test" > "$test_file"

  # Deliver a file to get preloadedFiles to 7
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P5: file delivered"

  local before
  before=$(count_preloaded)
  assert_eq "7" "$before" "P5: preloadedFiles has 7 before injections cleanup"

  # Add some pendingAllowInjections (simulating what overflow-v2 stashes)
  jq '.pendingAllowInjections = [{"ruleId": "preload", "content": "test content"}]' \
    "$STATE_FILE" | safe_json_write "$STATE_FILE"

  # Simulate what post-tool-use-injections.sh does at line 86:
  # jq '.pendingAllowInjections = []' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  local tmp_file="${STATE_FILE}.tmp.$$"
  jq '.pendingAllowInjections = []' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

  # preloadedFiles should be preserved
  local after
  after=$(count_preloaded)
  assert_eq "7" "$after" "P5: preloadedFiles still 7 after injections cleanup"
}

test_P6_multiple_state_writes_preserve_preloaded() {
  # Simulate the sequence of writes that happen during a single tool call:
  # 1. Counter increment (overflow-v2 step 5)
  # 2. preload_ensure delivery (overflow-v2 preload rule)
  # 3. pendingPreloads cleanup
  # 4. _track_delivered (injectedRules write)
  # 5. pendingAllowInjections stash
  # 6. injections hook clear

  local test_file="$TMP_DIR/content/test_p6.md"
  mkdir -p "$TMP_DIR/content"
  echo "# P6 test" > "$test_file"

  # Step 1: Counter increment
  jq '.toolCallsSinceLastLog = 5 | .toolCallsByTranscript.test = 5' \
    "$STATE_FILE" | safe_json_write "$STATE_FILE"

  local after_counter
  after_counter=$(count_preloaded)
  assert_eq "6" "$after_counter" "P6: preloaded still 6 after counter write"

  # Step 2: preload_ensure delivery
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P6: file delivered"

  local after_delivery
  after_delivery=$(count_preloaded)
  assert_eq "7" "$after_delivery" "P6: preloaded 7 after delivery"

  # Step 3: pendingPreloads cleanup
  jq '.pendingPreloads = []' "$STATE_FILE" | safe_json_write "$STATE_FILE"

  local after_cleanup
  after_cleanup=$(count_preloaded)
  assert_eq "7" "$after_cleanup" "P6: preloaded still 7 after pending cleanup"

  # Step 4: _track_delivered
  jq '.injectedRules.preload = true | .lastHeartbeat = "now"' \
    "$STATE_FILE" | safe_json_write "$STATE_FILE"

  local after_track
  after_track=$(count_preloaded)
  assert_eq "7" "$after_track" "P6: preloaded still 7 after track_delivered"

  # Step 5: pendingAllowInjections stash
  jq '.pendingAllowInjections = [{"ruleId": "preload", "content": "x"}]' \
    "$STATE_FILE" | safe_json_write "$STATE_FILE"

  local after_stash
  after_stash=$(count_preloaded)
  assert_eq "7" "$after_stash" "P6: preloaded still 7 after stash"

  # Step 6: injections hook clear (manual temp+mv, not safe_json_write)
  local tmp="${STATE_FILE}.tmp.$$"
  jq '.pendingAllowInjections = []' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  local after_injections
  after_injections=$(count_preloaded)
  assert_eq "7" "$after_injections" "P6: preloaded still 7 after injections clear"
}

test_P7_delivery_event_log_tracks_pipeline() {
  # With PRELOAD_TEST_LOG set, verify the full delivery chain is logged
  local log_file="$TMP_DIR/delivery.log"
  export PRELOAD_TEST_LOG="$log_file"

  local test_file="$TMP_DIR/content/test_p7.md"
  mkdir -p "$TMP_DIR/content"
  echo "# P7 test" > "$test_file"

  # Deliver
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P7: delivered"

  # Try to deliver again
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "skipped" "$_PRELOAD_RESULT" "P7: skipped on redelivery"

  # Check delivery log has both events
  local deliver_count skip_count
  deliver_count=$(grep -c '"direct-deliver"' "$log_file" || echo "0")
  skip_count=$(grep -c '"skip-dedup"' "$log_file" || echo "0")
  assert_eq "1" "$deliver_count" "P7: exactly 1 delivery logged"
  assert_eq "1" "$skip_count" "P7: exactly 1 skip logged"

  unset PRELOAD_TEST_LOG
}

test_P8_full_run_discovery_integration() {
  # Integration test using the actual _run_discovery function
  # Requires discover-directives.sh to be available

  if [ ! -x "$FAKE_HOME/.claude/scripts/discover-directives.sh" ]; then
    skip "P8: discover-directives.sh not available"
    return 0
  fi

  # Set up the globals that _run_discovery expects
  local TOOL_NAME="Read"
  local TOOL_INPUT
  TOOL_INPUT=$(jq -n --arg p "$FAKE_HOME/.claude/engine/hooks/test-hook.sh" '{"file_path": $p}')

  # Source the overflow-v2 hook's _run_discovery function
  # We need to define it locally since it's not exported from the hook
  _run_discovery_local() {
    local state_file="$1"
    local file_path
    file_path=$(echo "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null || echo "")
    [ -n "$file_path" ] || return 0

    local dir_path
    if [ -d "$file_path" ]; then
      dir_path="$file_path"
    else
      dir_path=$(dirname "$file_path")
    fi
    [ -n "$dir_path" ] || return 0

    local already_tracked
    already_tracked=$(jq -r --arg dir "$dir_path" \
      '(.touchedDirs // {}) | has($dir)' "$state_file" 2>/dev/null || echo "false")
    if [ "$already_tracked" = "true" ]; then
      return 0
    fi

    jq --arg dir "$dir_path" \
      '(.touchedDirs //= {}) | .touchedDirs[$dir] = []' \
      "$state_file" | safe_json_write "$state_file"

    local root_arg=""
    if [[ "$dir_path" == "$HOME/.claude/"* ]]; then
      root_arg="--root $HOME/.claude"
    fi

    local soft_files
    soft_files=$("$HOME/.claude/scripts/discover-directives.sh" "$dir_path" --walk-up --type soft $root_arg 2>/dev/null || echo "")

    local core_directives=("AGENTS.md" "INVARIANTS.md" "COMMANDS.md")
    local skill_directives
    skill_directives=$(jq -r '(.directives // []) | .[]' "$state_file" 2>/dev/null || echo "")

    local new_soft_files=()
    if [ -n "$soft_files" ]; then
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        file=$(normalize_preload_path "$file")
        local local_basename
        local_basename=$(basename "$file")

        local is_core=false
        local core
        for core in "${core_directives[@]}"; do
          if [ "$local_basename" = "$core" ]; then
            is_core=true
            break
          fi
        done

        if [ "$is_core" = "false" ]; then
          local is_declared=false
          if [ -n "$skill_directives" ]; then
            local declared
            while IFS= read -r declared; do
              if [ "$local_basename" = "$declared" ]; then
                is_declared=true
                break
              fi
            done <<< "$skill_directives"
          fi
          if [ "$is_declared" = "false" ]; then
            continue
          fi
        fi

        local already_suggested
        already_suggested=$(jq -r --arg file "$file" \
          '[(.touchedDirs // {}) | to_entries[] | .value[] | select(. == $file)] | length > 0' \
          "$state_file" 2>/dev/null || echo "false")
        if [ "$already_suggested" != "true" ]; then
          new_soft_files+=("$file")
        fi
      done <<< "$soft_files"
    fi

    if [ ${#new_soft_files[@]} -gt 0 ]; then
      local filenames_json="[]"
      local f
      for f in "${new_soft_files[@]}"; do
        filenames_json=$(echo "$filenames_json" | jq --arg name "$f" '. + [$name] | unique')
      done
      jq --arg dir "$dir_path" --argjson names "$filenames_json" \
        '(.touchedDirs //= {}) | .touchedDirs[$dir] = $names' \
        "$state_file" | safe_json_write "$state_file"
    fi

    if [ ${#new_soft_files[@]} -gt 0 ]; then
      local files_json="[]"
      local f
      for f in "${new_soft_files[@]}"; do
        files_json=$(echo "$files_json" | jq --arg f "$f" '. + [$f]')
      done
      jq --argjson files "$files_json" '
        (.preloadedFiles // []) as $pf |
        (.pendingPreloads //= []) |
        reduce ($files[]) as $f (.;
          if ($pf | any(. == $f)) then .
          elif (.pendingPreloads | index($f)) then .
          else .pendingPreloads += [$f]
          end
        )
      ' "$state_file" | safe_json_write "$state_file"
    fi
  }

  # Run discovery for dir A (hooks/)
  _run_discovery_local "$STATE_FILE"

  local pending_a
  pending_a=$(count_pending)
  # Should have found AGENTS.md (at engine/.directives/ level)
  assert_gt "$pending_a" "0" "P8: discovery found files for dir A"

  # Deliver all pending files (simulate preload rule)
  local pending_paths
  pending_paths=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null || echo "")
  while IFS= read -r ppath; do
    [ -n "$ppath" ] || continue
    preload_ensure "$ppath" "overflow(preload)" "immediate"
  done <<< "$pending_paths"

  # Cleanup pendingPreloads
  jq '.pendingPreloads = []' "$STATE_FILE" | safe_json_write "$STATE_FILE"

  local preloaded_after_delivery
  preloaded_after_delivery=$(count_preloaded)
  assert_gt "$preloaded_after_delivery" "6" "P8: preloadedFiles grew after delivery"

  # Now touch dir B (scripts/tests/)
  TOOL_INPUT=$(jq -n --arg p "$FAKE_HOME/.claude/engine/scripts/tests/test-file.sh" '{"file_path": $p}')
  _run_discovery_local "$STATE_FILE"

  local pending_b
  pending_b=$(count_pending)
  # AGENTS.md should NOT be re-queued because it's in preloadedFiles
  assert_eq "0" "$pending_b" "P8: no re-queuing after dir B discovery (AGENTS.md already preloaded)"
}

test_P9_pid_mismatch_causes_tracking_loss() {
  # REGRESSION TEST: Documents the PID mismatch failure mode.
  # When CLAUDE_SUPERVISOR_PID doesn't match the PID in .state.json,
  # find_preload_state() can't find the session and falls back to a seed file.
  # Writes to preloadedFiles go to the seed instead of the session .state.json,
  # causing the "stuck at 6 seeds" bug observed in the audit.

  # Override CLAUDE_SUPERVISOR_PID to a non-matching value
  local orig_pid="$CLAUDE_SUPERVISOR_PID"
  export CLAUDE_SUPERVISOR_PID=88888888

  local test_file="$TMP_DIR/content/test_p9.md"
  mkdir -p "$TMP_DIR/content"
  echo "# P9 test" > "$test_file"

  # Deliver — this will write to a SEED file (not the session .state.json)
  # because session.sh find can't match PID 88888888
  preload_ensure "$test_file" "test" "immediate"
  assert_eq "delivered" "$_PRELOAD_RESULT" "P9: file still delivers (to wrong state)"

  # Session .state.json should NOT have grown (writes went to seed)
  local session_count
  session_count=$(count_preloaded)
  assert_eq "6" "$session_count" "P9: session preloadedFiles stuck at 6 (PID mismatch → writes to seed)"

  # The state_file that preload_ensure used is a seed, not the session
  local actual_state
  actual_state=$(find_preload_state)
  assert_contains ".seeds/" "$actual_state" "P9: find_preload_state returned seed (not session)"

  # Restore
  export CLAUDE_SUPERVISOR_PID="$orig_pid"
}

# NOTE: P10 parallel delivery test deferred — requires _atomic_claim_preload
# integration in preload_ensure(), which has test env issues with find_preload_state()
# returning a different state file than $STATE_FILE in the test harness.
# The _atomic_claim_preload function itself works (proved in isolation).
# See session 2026_02_17_DOUBLE_PRELOAD_FIX for details.

# --- Run ---
run_discovered_tests
