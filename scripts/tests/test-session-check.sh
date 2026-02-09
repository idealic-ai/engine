#!/bin/bash
# ~/.claude/engine/scripts/tests/test-session-check.sh
# Tests for session.sh check subcommand and deactivate checklist gate (checkPassed flow)
#
# Tests: session.sh check validation (empty stdin, missing blocks, empty blocks, happy path,
# no checklists, paths with spaces) and deactivate checklist gate (blocking, allowing).
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-check.sh

# Don't use set -e globally — we need to handle return codes manually in tests
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""
ORIGINAL_PATH="$PATH"

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/tools/session-search"
  mkdir -p "$HOME/.claude/tools/doc-search"

  # Symlink the real session.sh and lib.sh
  ln -sf "$SESSION_SH" "$HOME/.claude/scripts/session.sh"
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"

  # Create mock fleet.sh (no-op)
  cat > "$HOME/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  pane-id) echo ""; exit 0 ;;
  notify)  exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  # Create mock search tools (no-op)
  for tool in session-search doc-search; do
    cat > "$HOME/.claude/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
    chmod +x "$HOME/.claude/tools/$tool/$tool.sh"
  done

  # Override CLAUDE_SUPERVISOR_PID to current PID (alive)
  export CLAUDE_SUPERVISOR_PID=$$

  # Create session directory
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  export PATH="$ORIGINAL_PATH"
  unset CLAUDE_SUPERVISOR_PID
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: write a .state.json fixture
write_state() {
  echo "$1" > "$SESSION_DIR/.state.json"
}

# =============================================================================
# session.sh check — VALIDATION TESTS
# =============================================================================

test_check_fails_no_stdin() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="check: fails when no stdin is provided"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md"]
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"§CMD_PROCESS_CHECKLISTS"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, output contains §CMD_PROCESS_CHECKLISTS" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_check_fails_missing_block() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="check: fails when a discovered checklist has no matching block"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md", "/path/to/OTHER_CHECKLIST.md"]
  }'

  # Only provide one of the two discovered checklists
  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" <<'EOF' 2>&1
## CHECKLIST: /path/to/CHECKLIST.md
- [x] Verified item
EOF
  ) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"/path/to/OTHER_CHECKLIST.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, output mentions missing path" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_check_fails_empty_block() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="check: fails when a checklist block has no items"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md"]
  }'

  # Provide header but no items
  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" <<'EOF' 2>&1
## CHECKLIST: /path/to/CHECKLIST.md
This block has no checklist items at all.
EOF
  ) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"empty"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, output mentions empty" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_check_passes_happy_path() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="check: passes and sets checkPassed=true when all blocks are valid"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md", "/path/to/OTHER.md"]
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" <<'EOF' 2>&1
## CHECKLIST: /path/to/CHECKLIST.md
- [x] Verified item one
- [x] Verified item two

## CHECKLIST: /path/to/OTHER.md
- [x] All good here
- [ ] Not applicable (reason explained)
EOF
  ) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed"
  fi

  teardown
}

test_check_passes_no_checklists() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="check: passes trivially when no checklists are discovered"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active"
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" <<'EOF' 2>&1
## CHECKLIST: /irrelevant/path
- [x] Does not matter
EOF
  ) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ] && [[ "$output" == *"trivially"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true, output contains trivially" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi

  teardown
}

# =============================================================================
# session.sh deactivate — CHECKLIST GATE TESTS
# =============================================================================

test_deactivate_blocks_no_checkpassed() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate: blocks when checkPassed is not set but checklists discovered"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md"]
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$SESSION_DIR" <<'EOF' 2>&1
Test session deactivation attempt
EOF
  ) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"INV_CHECKLIST_BEFORE_CLOSE"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, output references INV_CHECKLIST_BEFORE_CLOSE" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_allows_with_checkpassed() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate: allows when checkPassed is true"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md"],
    "checkPassed": true
  }'

  # No debriefTemplate in state -> debrief gate is skipped
  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$SESSION_DIR" <<'EOF' 2>&1
Test session deactivation with checkPassed
EOF
  ) || exit_code=$?

  local lifecycle
  lifecycle=$(jq -r '.lifecycle' "$SESSION_DIR/.state.json" 2>/dev/null || echo "unknown")

  if [ "$exit_code" -eq 0 ] && [ "$lifecycle" = "completed" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, lifecycle=completed" "exit=$exit_code, lifecycle=$lifecycle, output=$output"
  fi

  teardown
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_check_handles_paths_with_spaces() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="check: handles paths with spaces in checklist paths"
  setup

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/with spaces/to/CHECKLIST.md"]
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" <<'EOF' 2>&1
## CHECKLIST: /path/with spaces/to/CHECKLIST.md
- [x] Item verified despite spaces in path
EOF
  ) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-session-check.sh ==="

# session.sh check — Validation
test_check_fails_no_stdin
test_check_fails_missing_block
test_check_fails_empty_block
test_check_passes_happy_path
test_check_passes_no_checklists

# session.sh deactivate — Checklist gate
test_deactivate_blocks_no_checkpassed
test_deactivate_allows_with_checkpassed

# Edge cases
test_check_handles_paths_with_spaces

# Summary
exit_with_results
