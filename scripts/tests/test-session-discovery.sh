#!/bin/bash
# ~/.claude/engine/scripts/tests/test-session-discovery.sh
# Tests for session.sh activate/deactivate discovery integration.
#
# Tests: activate seeds touchedDirs/discoveredChecklists from directoriesOfInterest,
# deactivate blocks on unprocessed checklists, deactivate passes when processed,
# no discovery when directoriesOfInterest is empty, re-activation doesn't duplicate.
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-discovery.sh

set -uo pipefail

SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

# Colors
RED='\033[31m'
GREEN='\033[32m'
RESET='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""
ORIGINAL_PATH="$PATH"
ORIGINAL_PWD="$PWD"

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

  # Link real discover-directives.sh
  ln -sf "$ORIGINAL_HOME/.claude/scripts/discover-directives.sh" "$HOME/.claude/scripts/discover-directives.sh"

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

  # Create project structure with instruction files
  PROJECT_DIR="$TEST_DIR/project"
  mkdir -p "$PROJECT_DIR/src/lib"
  mkdir -p "$PROJECT_DIR/src/utils"
  mkdir -p "$PROJECT_DIR/docs"
  echo "# Project README" > "$PROJECT_DIR/README.md"
  echo "# Lib README" > "$PROJECT_DIR/src/lib/README.md"
  echo "# Lib INVARIANTS" > "$PROJECT_DIR/src/lib/INVARIANTS.md"
  echo "# Utils CHECKLIST" > "$PROJECT_DIR/src/utils/CHECKLIST.md"
  echo "# Docs README" > "$PROJECT_DIR/docs/README.md"

  # Create sessions directory
  mkdir -p "$TEST_DIR/sessions"

  # cd into test dir (session.sh uses PWD for project root detection)
  cd "$PROJECT_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  export HOME="$ORIGINAL_HOME"
  export PATH="$ORIGINAL_PATH"
  unset CLAUDE_SUPERVISOR_PID
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

# Helper: activate a session with given directoriesOfInterest
activate_with_dirs() {
  local session_dir="$1"
  shift
  local dirs_json="$1"

  "$HOME/.claude/scripts/session.sh" activate "$session_dir" test <<EOF
{
  "taskSummary": "Test session",
  "taskType": "TESTING",
  "directoriesOfInterest": $dirs_json,
  "phases": [{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Test"}]
}
EOF
}

# Helper: read .state.json for a session
read_state() {
  local session_dir="$1"
  cat "$session_dir/.state.json"
}

# =============================================================================
# ACTIVATE DISCOVERY TESTS
# =============================================================================

test_activate_discovers_readme_from_dir() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate discovery: finds README.md from directoriesOfInterest"
  setup

  local session_dir="$TEST_DIR/sessions/test-discovery-1"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/lib\"]" > /dev/null 2>&1

  local state
  state=$(read_state "$session_dir")
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")' 2>/dev/null)

  if [ "$has_touched" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs populated" "state=$state"
  fi

  teardown
}

test_activate_discovers_checklist() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate discovery: adds CHECKLIST.md to discoveredChecklists"
  setup

  local session_dir="$TEST_DIR/sessions/test-discovery-2"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  local state
  state=$(read_state "$session_dir")
  local checklist_count
  checklist_count=$(echo "$state" | jq '(.discoveredChecklists // []) | length' 2>/dev/null)

  if [ "$checklist_count" -gt 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "discoveredChecklists has entries" "checklist_count=$checklist_count, state=$state"
  fi

  teardown
}

test_activate_discovers_from_multiple_dirs() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate discovery: discovers from multiple directoriesOfInterest"
  setup

  local session_dir="$TEST_DIR/sessions/test-discovery-3"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/lib\", \"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  local state
  state=$(read_state "$session_dir")
  local dir_count
  dir_count=$(echo "$state" | jq '(.touchedDirs // {}) | length' 2>/dev/null)

  # Should have entries for lib, utils, and walk-up dirs (src, project root)
  if [ "$dir_count" -gt 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs > 1 entries" "dir_count=$dir_count"
  fi

  teardown
}

test_activate_no_discovery_when_empty_dirs() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate discovery: no discovery when directoriesOfInterest is empty"
  setup

  local session_dir="$TEST_DIR/sessions/test-discovery-4"
  activate_with_dirs "$session_dir" "[]" > /dev/null 2>&1

  local state
  state=$(read_state "$session_dir")
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")' 2>/dev/null)
  local has_checklists
  has_checklists=$(echo "$state" | jq '(.discoveredChecklists // []) | length' 2>/dev/null)

  if [ "$has_touched" != "true" ] || [ "$has_checklists" = "0" ]; then
    pass "$test_name"
  else
    fail "$test_name" "no touchedDirs or checklists" "has_touched=$has_touched, checklists=$has_checklists"
  fi

  teardown
}

test_activate_outputs_discovered_instructions_section() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate discovery: outputs '## Discovered Directives' section"
  setup

  local session_dir="$TEST_DIR/sessions/test-discovery-5"
  local output
  output=$(activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/lib\"]" 2>/dev/null)

  if [[ "$output" == *"Discovered Directives"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "output contains 'Discovered Directives'" "output=$(echo "$output" | head -20)"
  fi

  teardown
}

test_activate_checklist_path_is_absolute() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate discovery: checklist path is absolute"
  setup

  local session_dir="$TEST_DIR/sessions/test-discovery-6"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  local state
  state=$(read_state "$session_dir")
  local first_checklist
  first_checklist=$(echo "$state" | jq -r '(.discoveredChecklists // [])[0] // ""' 2>/dev/null)

  if [[ "$first_checklist" == /* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "absolute path starting with /" "first_checklist=$first_checklist"
  fi

  teardown
}

# =============================================================================
# DEACTIVATE CHECKLIST GATE TESTS
# =============================================================================

test_deactivate_blocks_unprocessed_checklists() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate gate: blocks when unprocessed checklists exist"
  setup

  local session_dir="$TEST_DIR/sessions/test-deactivate-1"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  # Try to deactivate without processing checklists
  local output
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$session_dir" --keywords "test" <<'EOF' 2>&1
Test session complete
EOF
  )
  local exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"unprocessed CHECKLIST"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, error mentions checklists" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_passes_when_checklists_processed() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate gate: passes when all checklists processed"
  setup

  local session_dir="$TEST_DIR/sessions/test-deactivate-2"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  # Read the discovered checklists to know what to mark processed
  local state
  state=$(read_state "$session_dir")
  local checklists
  checklists=$(echo "$state" | jq -c '.discoveredChecklists // []')

  # Mark them as processed via session.sh update
  "$HOME/.claude/scripts/session.sh" update "$session_dir" processedChecklists "$checklists" > /dev/null 2>&1

  # Now deactivate should succeed
  local output
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$session_dir" --keywords "test" <<'EOF' 2>&1
Test session complete
EOF
  )
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 (deactivate succeeds)" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_passes_when_no_checklists() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate gate: passes when no checklists were discovered"
  setup

  local session_dir="$TEST_DIR/sessions/test-deactivate-3"
  # Activate with a dir that has no CHECKLIST.md
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/docs\"]" > /dev/null 2>&1

  local output
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$session_dir" --keywords "test" <<'EOF' 2>&1
Test session complete
EOF
  )
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 (no checklists = no block)" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_error_lists_unprocessed_files() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate gate: error message lists unprocessed file paths"
  setup

  local session_dir="$TEST_DIR/sessions/test-deactivate-4"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  local output
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$session_dir" --keywords "test" <<'EOF' 2>&1
Test session complete
EOF
  )

  if [[ "$output" == *"CHECKLIST.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "error message contains CHECKLIST.md path" "output=$output"
  fi

  teardown
}

test_deactivate_references_invariant_code() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="deactivate gate: error references ¶INV_CHECKLIST_BEFORE_CLOSE"
  setup

  local session_dir="$TEST_DIR/sessions/test-deactivate-5"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  local output
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$session_dir" --keywords "test" <<'EOF' 2>&1
Test session complete
EOF
  )

  if [[ "$output" == *"INV_CHECKLIST_BEFORE_CLOSE"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "error references INV_CHECKLIST_BEFORE_CLOSE" "output=$output"
  fi

  teardown
}

# =============================================================================
# IDEMPOTENCY TESTS
# =============================================================================

test_activate_no_duplicate_checklists_on_reactivate() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="idempotency: re-activation doesn't duplicate checklists"
  setup

  local session_dir="$TEST_DIR/sessions/test-idempotent-1"
  activate_with_dirs "$session_dir" "[\"$PROJECT_DIR/src/utils\"]" > /dev/null 2>&1

  local count_before
  count_before=$(read_state "$session_dir" | jq '(.discoveredChecklists // []) | length')

  # Re-activate same session (skill change triggers re-scan)
  "$HOME/.claude/scripts/session.sh" activate "$session_dir" implement <<EOF 2>/dev/null
{
  "taskSummary": "Re-activate test",
  "taskType": "IMPLEMENTATION",
  "directoriesOfInterest": ["$PROJECT_DIR/src/utils"],
  "phases": [{"major":1,"minor":0,"name":"Setup"}]
}
EOF

  local count_after
  count_after=$(read_state "$session_dir" | jq '(.discoveredChecklists // []) | length')

  if [ "$count_before" = "$count_after" ]; then
    pass "$test_name"
  else
    fail "$test_name" "same checklist count ($count_before)" "before=$count_before, after=$count_after"
  fi

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-session-discovery.sh ==="

# Activate discovery
test_activate_discovers_readme_from_dir
test_activate_discovers_checklist
test_activate_discovers_from_multiple_dirs
test_activate_no_discovery_when_empty_dirs
test_activate_outputs_discovered_instructions_section
test_activate_checklist_path_is_absolute

# Deactivate checklist gate
test_deactivate_blocks_unprocessed_checklists
test_deactivate_passes_when_checklists_processed
test_deactivate_passes_when_no_checklists
test_deactivate_error_lists_unprocessed_files
test_deactivate_references_invariant_code

# Idempotency
test_activate_no_duplicate_checklists_on_reactivate

# Summary
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_RUN total"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
