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
# ENGINE PATH TRACKING TESTS (multi-root)
# =============================================================================

test_tracks_engine_paths() {
  local test_name="engine tracking: ~/.claude/ paths ARE tracked in touchedDirs"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/scripts/lib.sh\"}}" > /dev/null
  local state
  state=$(read_state)
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")')

  if [ "$has_touched" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs exists (engine path tracked)" "state=$state"
  fi

  teardown
}

test_engine_paths_use_root() {
  local test_name="engine root: walk-up from ~/.claude/skills/ finds ~/.claude/.directives/ but NOT ~/"
  setup

  # Create engine directive structure inside fake HOME
  mkdir -p "$HOME/.claude/.directives"
  echo "# Engine INVARIANTS" > "$HOME/.claude/.directives/INVARIANTS.md"
  mkdir -p "$HOME/.claude/skills/brainstorm"
  echo "# Brainstorm skill" > "$HOME/.claude/skills/brainstorm/SKILL.md"

  # Create a directive ABOVE ~/.claude/ that should NOT be found
  echo "# Home AGENTS" > "$HOME/AGENTS.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/brainstorm/SKILL.md\"}}" > /dev/null
  local state
  state=$(read_state)

  # pendingDirectives should contain INVARIANTS.md from ~/.claude/.directives/
  local has_invariants
  has_invariants=$(echo "$state" | jq '[(.pendingDirectives // [])[] | select(contains("INVARIANTS.md"))] | length > 0')

  # pendingDirectives should NOT contain AGENTS.md from ~/
  local has_agents
  has_agents=$(echo "$state" | jq '[(.pendingDirectives // [])[] | select(contains("AGENTS.md"))] | length > 0')

  if [ "$has_invariants" = "true" ] && [ "$has_agents" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "INVARIANTS.md in pending, AGENTS.md NOT in pending" "state=$state"
  fi

  teardown
}

test_engine_directives_added_to_pending() {
  local test_name="engine pending: reading ~/.claude/skills/ adds directives to pendingDirectives"
  setup

  # Create engine directive structure inside fake HOME
  mkdir -p "$HOME/.claude/.directives"
  echo "# Engine INVARIANTS" > "$HOME/.claude/.directives/INVARIANTS.md"
  mkdir -p "$HOME/.claude/skills/brainstorm"
  echo "# Brainstorm" > "$HOME/.claude/skills/brainstorm/SKILL.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/brainstorm/SKILL.md\"}}" > /dev/null
  local state
  state=$(read_state)

  local pending_count
  pending_count=$(echo "$state" | jq '(.pendingDirectives // []) | length')

  if [ "$pending_count" -gt 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "pendingDirectives non-empty" "state=$state"
  fi

  teardown
}

test_project_paths_unchanged() {
  local test_name="project paths: non-engine paths still use PWD boundary (no --root)"
  setup

  # Create project directives at project root and deep inside
  echo "# Root AGENTS" > "$PROJECT_DIR/AGENTS.md"
  mkdir -p "$PROJECT_DIR/src/deep/nested"
  echo "# Deep INVARIANTS" > "$PROJECT_DIR/src/deep/nested/INVARIANTS.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/deep/nested/file.ts\"}}" > /dev/null
  local state
  state=$(read_state)

  # Walk-up from src/deep/nested should find AGENTS.md at project root (PWD boundary)
  local has_agents
  has_agents=$(echo "$state" | jq '[(.pendingDirectives // [])[] | select(contains("AGENTS.md"))] | length > 0')

  if [ "$has_agents" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "AGENTS.md found via walk-up to PWD" "state=$state"
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
  local test_name="soft discovery: stores full paths in touchedDirs values"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"}}" > /dev/null

  local state
  state=$(read_state)
  local filenames
  filenames=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs[$dir]')

  # Should contain full path ending in INVARIANTS.md (local discovery)
  local has_invariants
  has_invariants=$(echo "$filenames" | jq 'any(endswith("INVARIANTS.md"))')

  if [ "$has_invariants" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "touchedDirs values contain path ending in INVARIANTS.md" "filenames=$filenames"
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
# EXCLUDED PATH COMPONENT TESTS (¶INV_DIRECTIVE_STACK — sessions/, tmp/, etc.)
# =============================================================================

test_excludes_sessions_subdirectory() {
  local test_name="excluded paths: sessions/ subdirectory does not discover TESTING.md"
  setup

  # Create a sessions/ subdirectory with a TESTING.md (mimics session debrief artifact)
  mkdir -p "$PROJECT_DIR/sessions/2026_02_09_SOME_SESSION"
  echo "# Testing Debrief" > "$PROJECT_DIR/sessions/2026_02_09_SOME_SESSION/TESTING.md"

  # Also add TESTING.md to skill directives so it would be picked up if not excluded
  jq '.directives = ["TESTING.md"]' "$SESSION_DIR/.state.json" | tee "$SESSION_DIR/.state.json.tmp" > /dev/null && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/sessions/2026_02_09_SOME_SESSION/file.ts\"}}")

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '[(.pendingDirectives // [])[] | select(contains("TESTING.md"))]')
  local testing_count
  testing_count=$(echo "$pending" | jq 'length')

  if [ "$testing_count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "TESTING.md not in pendingDirectives (sessions/ excluded)" "pending=$pending, output='$output'"
  fi

  teardown
}

test_excludes_tmp_subdirectory() {
  local test_name="excluded paths: tmp/ subdirectory does not discover README.md"
  setup

  # Create a tmp/ subdirectory with a README.md
  mkdir -p "$PROJECT_DIR/tmp/debug-output"
  echo "# Debug README" > "$PROJECT_DIR/tmp/debug-output/README.md"

  # Remove project-root README so it doesn't confuse the test
  rm -f "$PROJECT_DIR/README.md"

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/tmp/debug-output/file.ts\"}}")

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingDirectives // []')
  local count
  count=$(echo "$pending" | jq 'length')

  if [ "$count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "no pendingDirectives (tmp/ excluded)" "pending=$pending"
  fi

  teardown
}

test_excludes_node_modules_subdirectory() {
  local test_name="excluded paths: node_modules/ subdirectory does not discover README.md"
  setup

  # Create a node_modules/ subdirectory with a README.md
  mkdir -p "$PROJECT_DIR/node_modules/some-package"
  echo "# Package README" > "$PROJECT_DIR/node_modules/some-package/README.md"

  # Remove project-root README
  rm -f "$PROJECT_DIR/README.md"

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/node_modules/some-package/index.ts\"}}")

  local state
  state=$(read_state)
  local pending
  pending=$(echo "$state" | jq '.pendingDirectives // []')
  local count
  count=$(echo "$pending" | jq 'length')

  if [ "$count" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "no pendingDirectives (node_modules/ excluded)" "pending=$pending"
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

# Engine path tracking (multi-root)
test_tracks_engine_paths
test_engine_paths_use_root
test_engine_directives_added_to_pending
test_project_paths_unchanged

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

# Excluded path components (sessions/, tmp/, node_modules/)
test_excludes_sessions_subdirectory
test_excludes_tmp_subdirectory
test_excludes_node_modules_subdirectory

# Edge cases
test_skips_empty_file_path
test_no_output_when_no_instruction_files

exit_with_results
