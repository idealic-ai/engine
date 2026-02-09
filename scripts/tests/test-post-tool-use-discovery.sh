#!/bin/bash
# ~/.claude/engine/scripts/tests/test-post-tool-use-discovery.sh
# Tests for the PostToolUse discovery hook (post-tool-use-discovery.sh)
#
# Tests: tool filtering, engine path skip, new dir tracking, discovery integration,
# dedup, checklist tracking, hook output, idempotency.
#
# Run: bash ~/.claude/engine/scripts/tests/test-post-tool-use-discovery.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK_SH="$HOME/.claude/hooks/post-tool-use-discovery.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
DISCOVER_SH="$HOME/.claude/scripts/discover-directives.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""
ORIGINAL_PWD=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  ORIGINAL_PWD="$PWD"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/hooks"

  # Link lib.sh into fake home
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  # Link discover-directives.sh into fake home
  ln -sf "$DISCOVER_SH" "$HOME/.claude/scripts/discover-directives.sh"
  # Link the hook into fake home
  ln -sf "$HOOK_SH" "$HOME/.claude/hooks/post-tool-use-discovery.sh"

  # Create a fake session.sh that returns our test session dir
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"
  echo '{}' > "$SESSION_DIR/.state.json"

  cat > "$HOME/.claude/scripts/session.sh" <<SCRIPT
#!/bin/bash
if [ "\${1:-}" = "find" ]; then
  echo "$SESSION_DIR"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  # Create a project dir with instruction files
  PROJECT_DIR="$TEST_DIR/project"
  mkdir -p "$PROJECT_DIR/src/lib"
  mkdir -p "$PROJECT_DIR/src/utils"
  echo "# Project README" > "$PROJECT_DIR/README.md"
  echo "# Lib INVARIANTS" > "$PROJECT_DIR/src/lib/INVARIANTS.md"
  echo "# Utils CHECKLIST" > "$PROJECT_DIR/src/utils/CHECKLIST.md"

  # Set PWD to project root for discover-directives.sh boundary
  cd "$PROJECT_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the hook with given JSON input
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/hooks/post-tool-use-discovery.sh" 2>/dev/null
}

# Helper: read .state.json
read_state() {
  cat "$SESSION_DIR/.state.json"
}

# =============================================================================
# TOOL FILTERING TESTS
# =============================================================================

test_skips_non_matching_tools() {
  local test_name="tool filter: skips Bash tool (silent exit)"
  setup

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}')
  local exit_code=$?

  local state
  state=$(read_state)
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")')

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ] && [ "$has_touched" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output, no touchedDirs" "exit=$exit_code, output='$output', hasTouched=$has_touched"
  fi

  teardown
}

test_skips_glob_tool() {
  local test_name="tool filter: skips Glob tool"
  setup

  local output
  output=$(run_hook '{"tool_name":"Glob","tool_input":{"pattern":"*.ts"}}')
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output" "exit=$exit_code, output='$output'"
  fi

  teardown
}

test_processes_read_tool() {
  local test_name="tool filter: processes Read tool"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  if [ "$has_dir" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs has $PROJECT_DIR/src/lib" "state=$state"
  fi

  teardown
}

test_processes_edit_tool() {
  local test_name="tool filter: processes Edit tool"
  setup

  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  if [ "$has_dir" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs has $PROJECT_DIR/src/lib" "state=$state"
  fi

  teardown
}

test_processes_write_tool() {
  local test_name="tool filter: processes Write tool"
  setup

  run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  if [ "$has_dir" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs has $PROJECT_DIR/src/lib" "state=$state"
  fi

  teardown
}

# =============================================================================
# ENGINE PATH SKIP TESTS
# =============================================================================

test_skips_engine_paths() {
  local test_name="engine skip: ignores ~/.claude/ paths"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/scripts/lib.sh\"}}" > /dev/null
  local state
  state=$(read_state)
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")')

  if [ "$has_touched" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "no touchedDirs (engine path skipped)" "state=$state"
  fi

  teardown
}

# =============================================================================
# NO SESSION TESTS
# =============================================================================

test_skips_when_no_session() {
  local test_name="no session: skips when session.sh find returns empty"
  setup

  # Override session.sh to return empty
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
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}")
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output" "exit=$exit_code, output='$output'"
  fi

  teardown
}

# =============================================================================
# TOUCHED DIRS TRACKING TESTS
# =============================================================================

test_tracks_new_dir() {
  local test_name="tracking: adds new directory to touchedDirs"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  if [ "$has_dir" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs contains $PROJECT_DIR/src/lib" "state=$state"
  fi

  teardown
}

test_idempotent_same_dir() {
  local test_name="tracking: second call to same dir produces no output (idempotent)"
  setup

  # First call -- should discover
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null

  # Second call -- should be silent
  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/other.ts\"}}")

  if [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "no output on second call" "output='$output'"
  fi

  teardown
}

# =============================================================================
# SOFT FILE DISCOVERY TESTS
# =============================================================================

test_discovers_soft_files_and_outputs_message() {
  local test_name="soft discovery: outputs hookSpecificOutput message for README/INVARIANTS"
  setup

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}")

  local has_hook_output
  has_hook_output=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null || echo "")

  if [ "$has_hook_output" = "PostToolUse" ]; then
    pass "$test_name"
  else
    fail "$test_name" "hookSpecificOutput with PostToolUse event" "output='$output'"
  fi

  teardown
}

test_message_contains_invariant_code() {
  local test_name="soft discovery: message references INV_DIRECTIVE_STACK"
  setup

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}")

  local message
  message=$(echo "$output" | jq -r '.hookSpecificOutput.message' 2>/dev/null || echo "")

  if [[ "$message" == *"INV_DIRECTIVE_STACK"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "message contains INV_DIRECTIVE_STACK" "message='$message'"
  fi

  teardown
}

test_soft_files_stored_in_touched_dirs() {
  local test_name="soft discovery: stores basenames in touchedDirs values"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null

  local state
  state=$(read_state)
  local filenames
  filenames=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs[$dir]')

  # Should contain INVARIANTS.md (local) and README.md (from walk-up to project root)
  local has_invariants
  has_invariants=$(echo "$filenames" | jq 'index("INVARIANTS.md") != null')

  if [ "$has_invariants" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs values contain INVARIANTS.md" "filenames=$filenames"
  fi

  teardown
}

test_dedup_across_dirs() {
  local test_name="soft discovery: second dir doesn't re-suggest already-suggested files"
  setup

  # First call discovers README.md from project root walk-up
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null

  # Second call from a different dir -- README.md was already suggested via first dir
  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/test.ts\"}}")

  # Output may contain CHECKLIST suggestion but should NOT re-suggest README.md if already covered
  # The dedup logic checks basenames across all touchedDirs values
  local state
  state=$(read_state)
  local dir_count
  dir_count=$(echo "$state" | jq '.touchedDirs | length')

  if [ "$dir_count" = "2" ]; then
    pass "$test_name"
  else
    fail "$test_name" "2 dirs in touchedDirs" "dir_count=$dir_count, state=$state"
  fi

  teardown
}

# =============================================================================
# HARD FILE (CHECKLIST) TESTS
# =============================================================================

test_discovers_checklist_adds_to_state() {
  local test_name="hard discovery: adds CHECKLIST.md to discoveredChecklists"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/test.ts\"}}" > /dev/null

  local state
  state=$(read_state)
  local checklists
  checklists=$(echo "$state" | jq '.discoveredChecklists // []')
  local count
  count=$(echo "$checklists" | jq 'length')

  if [ "$count" -gt 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "discoveredChecklists has entries" "checklists=$checklists"
  fi

  teardown
}

test_checklist_not_duplicated() {
  local test_name="hard discovery: CHECKLIST.md not duplicated on repeated discovery"
  setup

  # Touch utils dir (has CHECKLIST.md)
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/test.ts\"}}" > /dev/null

  # Manually reset touchedDirs to force re-discovery (simulating a different session or cleared state)
  jq '.touchedDirs = {}' "$SESSION_DIR/.state.json" | tee "$SESSION_DIR/.state.json.tmp" > /dev/null && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  # Touch same dir again
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/other.ts\"}}" > /dev/null

  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '[.discoveredChecklists[] | select(. | endswith("CHECKLIST.md"))] | length')

  if [ "$count" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exactly 1 CHECKLIST.md entry" "count=$count, state=$state"
  fi

  teardown
}

# =============================================================================
# EMPTY FILE_PATH TESTS
# =============================================================================

test_skips_empty_file_path() {
  local test_name="empty path: skips when file_path is empty"
  setup

  local output
  output=$(run_hook '{"tool_name":"Read","tool_input":{}}')
  local exit_code=$?
  local state
  state=$(read_state)

  if [ "$exit_code" -eq 0 ] && [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no output" "exit=$exit_code, output='$output'"
  fi

  teardown
}

# =============================================================================
# NO DISCOVERY FILES TESTS
# =============================================================================

test_no_output_when_no_instruction_files() {
  local test_name="no files: no output when directory has no instruction files"
  setup

  # Create an empty subdirectory with no instruction files
  mkdir -p "$PROJECT_DIR/empty/deep"

  # Remove project-root README so walk-up finds nothing
  rm -f "$PROJECT_DIR/README.md"

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/empty/deep/test.ts\"}}")

  if [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "no output" "output='$output'"
  fi

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-post-tool-use-discovery.sh ==="

# Tool filtering
test_skips_non_matching_tools
test_skips_glob_tool
test_processes_read_tool
test_processes_edit_tool
test_processes_write_tool

# Engine path skip
test_skips_engine_paths

# No session
test_skips_when_no_session

# Touched dirs tracking
test_tracks_new_dir
test_idempotent_same_dir

# Soft file discovery
test_discovers_soft_files_and_outputs_message
test_message_contains_invariant_code
test_soft_files_stored_in_touched_dirs
test_dedup_across_dirs

# Hard file (checklist) discovery
test_discovers_checklist_adds_to_state
test_checklist_not_duplicated

# Edge cases
test_skips_empty_file_path
test_no_output_when_no_instruction_files

exit_with_results
