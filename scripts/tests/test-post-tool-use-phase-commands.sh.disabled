#!/bin/bash
# ~/.claude/engine/scripts/tests/test-post-tool-use-phase-commands.sh
# Tests for the PostToolUse phase-commands hook (post-tool-use-phase-commands.sh)
#
# Tests: tool filtering, Phase: detection, §CMD_ proof resolution, suffix stripping,
# dedup, missing files, preloadedFiles dedup, no proof fields.
#
# Run: bash ~/.claude/engine/scripts/tests/test-post-tool-use-phase-commands.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK_SH="$HOME/.claude/hooks/post-tool-use-phase-commands.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/hooks"

  # Link lib.sh into fake home
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  # Link the hook into fake home
  ln -sf "$HOOK_SH" "$HOME/.claude/hooks/post-tool-use-phase-commands.sh"

  # Create a fake session.sh that returns our test session dir
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"

  cat > "$HOME/.claude/scripts/session.sh" <<SCRIPT
#!/bin/bash
if [ "\${1:-}" = "find" ]; then
  echo "$SESSION_DIR"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  # Create CMD files directory with test CMD files
  CMD_DIR="$HOME/.claude/engine/.directives/commands"
  mkdir -p "$CMD_DIR"
  echo "# CMD_GENERATE_DEBRIEF" > "$CMD_DIR/CMD_GENERATE_DEBRIEF.md"
  echo "# CMD_WALK_THROUGH_RESULTS" > "$CMD_DIR/CMD_WALK_THROUGH_RESULTS.md"
  echo "# CMD_PROCESS_CHECKLISTS" > "$CMD_DIR/CMD_PROCESS_CHECKLISTS.md"
  echo "# CMD_FOO_BAR" > "$CMD_DIR/CMD_FOO_BAR.md"

  # Default .state.json with phases array
  cat > "$SESSION_DIR/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "loading": false,
  "currentPhase": "5: Synthesis",
  "phases": [
    {"major": 4, "minor": 0, "name": "Build Loop", "proof": ["plan_steps_completed", "tests_pass"]},
    {"major": 5, "minor": 0, "name": "Synthesis", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags", "§CMD_PROCESS_CHECKLISTS_done"]}
  ],
  "preloadedFiles": []
}
JSON
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the hook with given JSON input
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/hooks/post-tool-use-phase-commands.sh" 2>/dev/null
}

# Helper: read .state.json
read_state() {
  cat "$SESSION_DIR/.state.json"
}

# =============================================================================
# TEST 1: §CMD_ proof fields → writes correct pendingCommands paths
# =============================================================================

test_cmd_proof_fields_write_pending_commands() {
  local test_name="1: §CMD_ proof fields write correct pendingCommands paths"
  setup

  # Simulate a phase transition Bash output
  run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq -r '.pendingCommands // []')
  local count
  count=$(echo "$pending" | jq 'length')

  # Should have CMD_GENERATE_DEBRIEF.md and CMD_PROCESS_CHECKLISTS.md
  local has_debrief
  has_debrief=$(echo "$pending" | jq 'any(endswith("CMD_GENERATE_DEBRIEF.md"))')
  local has_checklists
  has_checklists=$(echo "$pending" | jq 'any(endswith("CMD_PROCESS_CHECKLISTS.md"))')

  if [ "$count" -eq 2 ] && [ "$has_debrief" = "true" ] && [ "$has_checklists" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "2 pendingCommands (DEBRIEF + CHECKLISTS)" "count=$count, pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 2: No proof fields on phase → pendingCommands empty/unchanged
# =============================================================================

test_no_proof_fields_leaves_pending_empty() {
  local test_name="2: no proof fields leaves pendingCommands unchanged"
  setup

  # Set state to a phase with no §CMD_ proofs
  jq '.currentPhase = "4: Build Loop"' "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 4: Build Loop\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '(.pendingCommands // []) | length')

  if [ "$count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "0 pendingCommands (no §CMD_ proofs)" "count=$count, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST 3: Suffix stripping: §CMD_FOO_BAR_baz → CMD_FOO_BAR.md
# =============================================================================

test_suffix_stripping() {
  local test_name="3: suffix stripping: §CMD_FOO_BAR_baz → CMD_FOO_BAR.md"
  setup

  # Create a phase with a suffix-bearing proof field
  jq '.currentPhase = "6: Custom" | .phases += [{"major": 6, "minor": 0, "name": "Custom", "proof": ["§CMD_FOO_BAR_baz"]}]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 6: Custom\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq -r '.pendingCommands // []')
  local has_foo_bar
  has_foo_bar=$(echo "$pending" | jq 'any(endswith("CMD_FOO_BAR.md"))')

  if [ "$has_foo_bar" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "pendingCommands contains CMD_FOO_BAR.md" "pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 4: Dedup: multiple proofs resolving to same CMD file → single entry
# =============================================================================

test_dedup_same_cmd() {
  local test_name="4: dedup: multiple proofs → same CMD → single entry"
  setup

  # Phase 5 has §CMD_GENERATE_DEBRIEF_file and §CMD_GENERATE_DEBRIEF_tags → both resolve to CMD_GENERATE_DEBRIEF.md
  run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local debrief_count
  debrief_count=$(echo "$state" | jq '[(.pendingCommands // [])[] | select(endswith("CMD_GENERATE_DEBRIEF.md"))] | length')

  if [ "$debrief_count" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exactly 1 CMD_GENERATE_DEBRIEF.md entry" "count=$debrief_count, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST 5: Plain strings (no §CMD_ prefix) → ignored
# =============================================================================

test_plain_strings_ignored() {
  local test_name="5: plain strings (no §CMD_ prefix) ignored"
  setup

  # Phase with only plain proof fields
  jq '.currentPhase = "4: Build Loop"' "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 4: Build Loop\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '(.pendingCommands // []) | length')

  # "plan_steps_completed" and "tests_pass" have no §CMD_ prefix → 0 pendingCommands
  if [ "$count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "0 pendingCommands (plain proof strings)" "count=$count"
  fi

  teardown
}

# =============================================================================
# TEST 6: Missing CMD file on disk → skipped silently
# =============================================================================

test_missing_cmd_file_skipped() {
  local test_name="6: missing CMD file on disk skipped silently"
  setup

  # Add a proof field whose CMD file doesn't exist
  jq '.currentPhase = "6: Custom" | .phases += [{"major": 6, "minor": 0, "name": "Custom", "proof": ["§CMD_NONEXISTENT_THING_done"]}]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_response":"Phase: 6: Custom\nProof required..."}')
  local exit_code=$?

  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '(.pendingCommands // []) | length')

  if [ "$exit_code" -eq 0 ] && [ "$count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, 0 pendingCommands" "exit=$exit_code, count=$count"
  fi

  teardown
}

# =============================================================================
# TEST 7: Non-Bash tool → hook exits immediately
# =============================================================================

test_non_bash_tool_exits() {
  local test_name="7: non-Bash tool exits immediately"
  setup

  local output
  output=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/some/file"}}')
  local exit_code=$?

  local state
  state=$(read_state)
  local has_pending
  has_pending=$(echo "$state" | jq 'has("pendingCommands")')

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ] && [ "$has_pending" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output, no pendingCommands" "exit=$exit_code, output='$output', hasPending=$has_pending"
  fi

  teardown
}

# =============================================================================
# TEST 8: No "Phase:" in stdout → hook exits immediately
# =============================================================================

test_no_phase_in_stdout_exits() {
  local test_name="8: no Phase: in stdout exits immediately"
  setup

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_response":"some normal bash output\nno phase here"}')
  local exit_code=$?

  local state
  state=$(read_state)
  local has_pending
  has_pending=$(echo "$state" | jq 'has("pendingCommands")')

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ] && [ "$has_pending" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output, no pendingCommands" "exit=$exit_code, output='$output', hasPending=$has_pending"
  fi

  teardown
}

# =============================================================================
# TEST 9: Already in preloadedFiles → not added to pendingCommands
# =============================================================================

test_preloaded_files_dedup() {
  local test_name="9: already in preloadedFiles not added to pendingCommands"
  setup

  # Pre-populate preloadedFiles with CMD_GENERATE_DEBRIEF.md
  local cmd_path="$HOME/.claude/engine/.directives/commands/CMD_GENERATE_DEBRIEF.md"
  jq --arg file "$cmd_path" '.preloadedFiles = [$file]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingCommands // []')

  # CMD_GENERATE_DEBRIEF.md should NOT be in pendingCommands (already preloaded)
  # CMD_PROCESS_CHECKLISTS.md should still be there
  local has_debrief
  has_debrief=$(echo "$pending" | jq 'any(endswith("CMD_GENERATE_DEBRIEF.md"))')
  local has_checklists
  has_checklists=$(echo "$pending" | jq 'any(endswith("CMD_PROCESS_CHECKLISTS.md"))')

  if [ "$has_debrief" = "false" ] && [ "$has_checklists" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "DEBRIEF not in pending, CHECKLISTS in pending" "pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 10: Idempotency — running hook twice with same phase produces same result
# =============================================================================

test_idempotency_no_duplicate_pending() {
  local test_name="10: idempotency: running hook twice produces no duplicate pendingCommands"
  setup

  # Run hook twice with the same phase transition
  run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}' > /dev/null
  run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local debrief_count
  debrief_count=$(echo "$state" | jq '[(.pendingCommands // [])[] | select(endswith("CMD_GENERATE_DEBRIEF.md"))] | length')
  local checklists_count
  checklists_count=$(echo "$state" | jq '[(.pendingCommands // [])[] | select(endswith("CMD_PROCESS_CHECKLISTS.md"))] | length')

  if [ "$debrief_count" -eq 1 ] && [ "$checklists_count" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exactly 1 of each CMD after 2 runs" "debrief=$debrief_count, checklists=$checklists_count"
  fi

  teardown
}

# =============================================================================
# TEST 11: Empty phases array → hook exits gracefully
# =============================================================================

test_empty_phases_array() {
  local test_name="11: empty phases array exits gracefully"
  setup

  # Remove phases array entirely
  jq 'del(.phases)' "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}')
  local exit_code=$?

  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '(.pendingCommands // []) | length')

  if [ "$exit_code" -eq 0 ] && [ "$count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, 0 pendingCommands" "exit=$exit_code, count=$count"
  fi

  teardown
}

# =============================================================================
# TEST 12: No session found → silent exit
# =============================================================================

test_no_session_silent_exit() {
  local test_name="12: no session found exits silently"
  setup

  # Override session.sh to return empty (no session)
  cat > "$HOME/.claude/scripts/session.sh" <<'SCRIPT'
#!/bin/bash
if [ "${1:-}" = "find" ]; then
  echo ""
  exit 1
fi
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}')
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output" "exit=$exit_code, output='$output'"
  fi

  teardown
}

# =============================================================================
# TEST 13: TOOL_OUTPUT env var fallback when tool_response is empty
# =============================================================================

test_tool_output_env_var_fallback() {
  local test_name="13: TOOL_OUTPUT env var fallback"
  setup

  # Send JSON with empty tool_response, set TOOL_OUTPUT env var
  TOOL_OUTPUT="Phase: 5: Synthesis\nProof required..." \
    run_hook '{"tool_name":"Bash","tool_response":""}' > /dev/null

  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '(.pendingCommands // []) | length')

  # Should have picked up the phase from TOOL_OUTPUT and found CMDs
  if [ "$count" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "pendingCommands non-empty (TOOL_OUTPUT fallback worked)" "count=$count"
  fi

  teardown
}

# =============================================================================
# TEST 14: Phase with mixed proofs — only §CMD_ ones processed
# =============================================================================

test_mixed_proofs_only_cmd_processed() {
  local test_name="14: mixed proofs: only §CMD_ prefixed ones processed"
  setup

  # Create a phase with a mix of plain and §CMD_ proof fields
  jq '.currentPhase = "7: Mixed" | .phases += [{"major": 7, "minor": 0, "name": "Mixed", "proof": ["plain_field", "§CMD_FOO_BAR_baz", "another_plain", "§CMD_WALK_THROUGH_RESULTS_done"]}]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 7: Mixed\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingCommands // []')

  # Should have CMD_FOO_BAR.md (exists) and CMD_WALK_THROUGH_RESULTS.md (exists)
  # Should NOT have plain_field or another_plain
  local has_foo_bar
  has_foo_bar=$(echo "$pending" | jq 'any(endswith("CMD_FOO_BAR.md"))')
  local has_walk
  has_walk=$(echo "$pending" | jq 'any(endswith("CMD_WALK_THROUGH_RESULTS.md"))')
  local count
  count=$(echo "$pending" | jq 'length')

  if [ "$has_foo_bar" = "true" ] && [ "$has_walk" = "true" ] && [ "$count" -eq 2 ]; then
    pass "$test_name"
  else
    fail "$test_name" "2 pendingCommands (FOO_BAR + WALK_THROUGH_RESULTS)" "count=$count, pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 15: CMD name without lowercase suffix — §CMD_CHECK → CMD_CHECK.md
# =============================================================================

test_cmd_name_no_lowercase_suffix() {
  local test_name="15: CMD name without lowercase suffix preserved"
  setup

  # Create CMD_CHECK.md
  echo "# CMD_CHECK" > "$CMD_DIR/CMD_CHECK.md"

  # Create a phase with a proof field that has no lowercase suffix
  jq '.currentPhase = "8: Verify" | .phases += [{"major": 8, "minor": 0, "name": "Verify", "proof": ["§CMD_CHECK"]}]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 8: Verify\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingCommands // []')
  local has_check
  has_check=$(echo "$pending" | jq 'any(endswith("CMD_CHECK.md"))')

  if [ "$has_check" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "pendingCommands contains CMD_CHECK.md" "pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 16: pendingCommands already has entries — new commands append
# =============================================================================

test_pending_commands_append_not_overwrite() {
  local test_name="16: new commands append to existing pendingCommands"
  setup

  # Pre-populate pendingCommands with an existing entry
  jq '.pendingCommands = ["/some/existing/CMD_OLD.md"]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":"Phase: 5: Synthesis\nProof required..."}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingCommands // []')
  local has_old
  has_old=$(echo "$pending" | jq 'any(. == "/some/existing/CMD_OLD.md")')
  local has_debrief
  has_debrief=$(echo "$pending" | jq 'any(endswith("CMD_GENERATE_DEBRIEF.md"))')
  local count
  count=$(echo "$pending" | jq 'length')

  # Should have old entry + new entries (GENERATE_DEBRIEF + PROCESS_CHECKLISTS = 3 total)
  if [ "$has_old" = "true" ] && [ "$has_debrief" = "true" ] && [ "$count" -eq 3 ]; then
    pass "$test_name"
  else
    fail "$test_name" "3 pendingCommands (old + DEBRIEF + CHECKLISTS)" "count=$count, pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 17: Malformed tool_response (missing field) → graceful handling
# =============================================================================

test_malformed_tool_response_graceful() {
  local test_name="17: malformed JSON (no tool_response field) handled gracefully"
  setup

  local output
  output=$(run_hook '{"tool_name":"Bash"}')
  local exit_code=$?

  # Should exit cleanly (no Phase: in stdout fallback)
  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 (graceful)" "exit=$exit_code, output='$output'"
  fi

  teardown
}

# =============================================================================
# TEST 18: tool_response as object (real Claude Code format) → extracts .stdout
# =============================================================================

test_tool_response_object_extracts_stdout() {
  local test_name="18: tool_response as object extracts .stdout field"
  setup

  # Claude Code sends Bash tool_response as an object: {stdout, stderr, interrupted, ...}
  run_hook '{"tool_name":"Bash","tool_response":{"stdout":"Phase: 5: Synthesis\nProof required...","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false}}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingCommands // []')
  local count
  count=$(echo "$pending" | jq 'length')

  local has_debrief
  has_debrief=$(echo "$pending" | jq 'any(endswith("CMD_GENERATE_DEBRIEF.md"))')
  local has_checklists
  has_checklists=$(echo "$pending" | jq 'any(endswith("CMD_PROCESS_CHECKLISTS.md"))')

  if [ "$count" -eq 2 ] && [ "$has_debrief" = "true" ] && [ "$has_checklists" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "2 pendingCommands from object tool_response" "count=$count, pending=$pending"
  fi

  teardown
}

# =============================================================================
# TEST 19: tool_response object with non-Phase stdout → exits cleanly
# =============================================================================

test_tool_response_object_no_phase() {
  local test_name="19: tool_response object without Phase: in stdout exits cleanly"
  setup

  run_hook '{"tool_name":"Bash","tool_response":{"stdout":"some normal output","stderr":"","interrupted":false}}' > /dev/null
  local exit_code=$?

  local state
  state=$(read_state)
  local has_pending
  has_pending=$(echo "$state" | jq 'has("pendingCommands")')

  if [ "$exit_code" -eq 0 ] && [ "$has_pending" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no pendingCommands" "exit=$exit_code, hasPending=$has_pending"
  fi

  teardown
}

# =============================================================================
# TEST 20: steps array populates pendingCommands
# =============================================================================

test_steps_array_populates_pending() {
  local test_name="20: steps array populates pendingCommands"
  setup

  # Create a phase with steps (not just proof fields)
  jq '.currentPhase = "6: Custom" | .phases += [{"major": 6, "minor": 0, "name": "Custom", "steps": ["§CMD_WALK_THROUGH_RESULTS"], "commands": [], "proof": []}]' \
    "$SESSION_DIR/.state.json" > "$SESSION_DIR/.state.json.tmp" && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook '{"tool_name":"Bash","tool_response":{"stdout":"Phase: 6: Custom","stderr":"","interrupted":false}}' > /dev/null

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingCommands // []')
  local has_walk
  has_walk=$(echo "$pending" | jq 'any(endswith("CMD_WALK_THROUGH_RESULTS.md"))')

  if [ "$has_walk" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "pendingCommands contains CMD_WALK_THROUGH_RESULTS.md" "pending=$pending"
  fi

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-post-tool-use-phase-commands.sh ==="

# Original tests (1-9)
test_cmd_proof_fields_write_pending_commands
test_no_proof_fields_leaves_pending_empty
test_suffix_stripping
test_dedup_same_cmd
test_plain_strings_ignored
test_missing_cmd_file_skipped
test_non_bash_tool_exits
test_no_phase_in_stdout_exits
test_preloaded_files_dedup

# New coverage tests (10-17)
test_idempotency_no_duplicate_pending
test_empty_phases_array
test_no_session_silent_exit
test_tool_output_env_var_fallback
test_mixed_proofs_only_cmd_processed
test_cmd_name_no_lowercase_suffix
test_pending_commands_append_not_overwrite
test_malformed_tool_response_graceful

# Bug fix tests (18-20): tool_response as object
test_tool_response_object_extracts_stdout
test_tool_response_object_no_phase
test_steps_array_populates_pending

exit_with_results
