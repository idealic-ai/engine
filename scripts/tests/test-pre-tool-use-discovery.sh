#!/bin/bash
# ~/.claude/engine/scripts/tests/test-pre-tool-use-discovery.sh
# Tests for _run_discovery() in pre-tool-use-overflow-v2.sh (PreToolUse discovery)
#
# Tests: tool filtering, touchedDirs tracking, soft file discovery,
# hard file (CHECKLIST) discovery, directive filtering, COMMANDS.md discovery,
# multi-root engine paths, excluded paths, checklist read tracking.
#
# Run: bash ~/.claude/engine/scripts/tests/test-pre-tool-use-discovery.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths before setup changes HOME
REAL_HOME="$HOME"
HOOK_SH="$REAL_HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
LIB_SH="$REAL_HOME/.claude/scripts/lib.sh"
DISCOVER_SH="$REAL_HOME/.claude/scripts/discover-directives.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""
ORIGINAL_PWD=""
SESSION_DIR=""
PROJECT_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  ORIGINAL_PWD="$PWD"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/hooks"
  mkdir -p "$HOME/.claude/engine"

  # Symlink core scripts into fake home
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  ln -sf "$DISCOVER_SH" "$HOME/.claude/scripts/discover-directives.sh"
  ln -sf "$HOOK_SH" "$HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"

  # Create empty guards.json (no rules — avoids blocking/allow side effects)
  echo '{"rules": []}' > "$HOME/.claude/engine/guards.json"

  # Create empty config.sh (hook sources it; missing file causes exit under set -e)
  touch "$HOME/.claude/engine/config.sh"

  # Create mock fleet.sh (no-op)
  cat > "$HOME/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  # Create test session directory
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"

  # Initial .state.json — active session, discovery-compatible
  cat > "$SESSION_DIR/.state.json" <<JSON
{
  "pid": $$,
  "skill": "test",
  "lifecycle": "active",
  "loading": false,
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0,
  "currentPhase": "4: Test Loop",
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200,
  "directives": ["TESTING.md", "PITFALLS.md", "CHECKLIST.md"]
}
JSON

  # Mock session.sh — returns our test session dir on 'find'
  cat > "$HOME/.claude/scripts/session.sh" <<SCRIPT
#!/bin/bash
if [ "\${1:-}" = "find" ]; then
  echo "$SESSION_DIR"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  # Create project dir with instruction files
  PROJECT_DIR="$TEST_DIR/project"
  mkdir -p "$PROJECT_DIR/src/lib"
  mkdir -p "$PROJECT_DIR/src/utils"
  mkdir -p "$PROJECT_DIR/.directives"
  echo "# Project AGENTS" > "$PROJECT_DIR/.directives/AGENTS.md"
  echo "# Project INVARIANTS" > "$PROJECT_DIR/.directives/INVARIANTS.md"
  echo "# Lib INVARIANTS" > "$PROJECT_DIR/src/lib/INVARIANTS.md"
  echo "# Utils CHECKLIST" > "$PROJECT_DIR/src/utils/CHECKLIST.md"

  # cd into project dir (PWD boundary for discover-directives.sh walk-up)
  cd "$PROJECT_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the PreToolUse hook with given JSON input
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/hooks/pre-tool-use-overflow-v2.sh" 2>/dev/null
}

# Helper: read .state.json
read_state() {
  cat "$SESSION_DIR/.state.json"
}

# =============================================================================
# TOOL FILTERING TESTS
# =============================================================================

test_skips_bash_tool() {
  local test_name="tool filter: skips Bash tool (no discovery)"
  setup

  run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"/tmp/test"}'
  local state
  state=$(read_state)
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")')

  assert_eq "false" "$has_touched" "$test_name"

  teardown
}

test_processes_glob_tool() {
  local test_name="tool filter: processes Glob tool (discovers via path param)"
  setup

  run_hook "{\"tool_name\":\"Glob\",\"tool_input\":{\"pattern\":\"*.ts\",\"path\":\"$PROJECT_DIR/src/lib\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_dir" "$test_name"

  teardown
}

test_processes_grep_tool() {
  local test_name="tool filter: processes Grep tool (discovers via path param)"
  setup

  run_hook "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"TODO\",\"path\":\"$PROJECT_DIR/src/lib\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_dir" "$test_name"

  teardown
}

test_grep_directory_path_used_directly() {
  local test_name="tool filter: Grep with directory path uses it directly (not dirname)"
  setup

  # Grep path is typically a directory, not a file — should use it as-is
  run_hook "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"TODO\",\"path\":\"$PROJECT_DIR/src/utils\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  # Should track src/utils directly, not its parent src/
  local has_utils
  has_utils=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/utils" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_utils" "$test_name"

  teardown
}

test_glob_no_path_skips_discovery() {
  local test_name="tool filter: Glob without path param skips discovery"
  setup

  run_hook '{"tool_name":"Glob","tool_input":{"pattern":"*.ts"},"transcript_path":"/tmp/test"}'
  local state
  state=$(read_state)
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")')

  assert_eq "false" "$has_touched" "$test_name"

  teardown
}

test_processes_read_tool() {
  local test_name="tool filter: processes Read tool"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_dir" "$test_name"

  teardown
}

test_processes_edit_tool() {
  local test_name="tool filter: processes Edit tool"
  setup

  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_dir" "$test_name"

  teardown
}

test_processes_write_tool() {
  local test_name="tool filter: processes Write tool"
  setup

  run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_dir" "$test_name"

  teardown
}

# =============================================================================
# TOUCHED DIRS TRACKING TESTS
# =============================================================================

test_tracks_new_dir() {
  local test_name="tracking: adds new directory to touchedDirs"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_dir
  has_dir=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs | has($dir)')

  assert_eq "true" "$has_dir" "$test_name"

  teardown
}

test_idempotent_same_dir() {
  local test_name="tracking: second call to same dir is idempotent (no new discoveries)"
  setup

  # First call — discovers
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state1
  state1=$(read_state)
  local pending1
  pending1=$(echo "$state1" | jq '(.pendingPreloads // []) | length')

  # Second call to same dir — should be idempotent
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/other.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state2
  state2=$(read_state)
  local pending2
  pending2=$(echo "$state2" | jq '(.pendingPreloads // []) | length')

  assert_eq "$pending1" "$pending2" "$test_name"

  teardown
}

test_tracks_multiple_dirs() {
  local test_name="tracking: tracks multiple different directories"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local dir_count
  dir_count=$(echo "$state" | jq '.touchedDirs | length')

  # Should have at least 2 dirs (src/lib and src/utils; walk-up may add more)
  assert_gt "$dir_count" 1 "$test_name"

  teardown
}

# =============================================================================
# SOFT FILE DISCOVERY TESTS
# =============================================================================

test_discovers_invariants_in_pending() {
  local test_name="soft discovery: INVARIANTS.md added to pendingPreloads"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_invariants
  has_invariants=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("INVARIANTS.md"))] | length > 0')

  assert_eq "true" "$has_invariants" "$test_name"

  teardown
}

test_walk_up_discovers_agents() {
  local test_name="soft discovery: walk-up discovers AGENTS.md from project root"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_agents
  has_agents=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("AGENTS.md"))] | length > 0')

  assert_eq "true" "$has_agents" "$test_name"

  teardown
}

test_soft_files_stored_in_touched_dirs() {
  local test_name="soft discovery: discovered file paths stored in touchedDirs values"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local filenames
  filenames=$(echo "$state" | jq --arg dir "$PROJECT_DIR/src/lib" '.touchedDirs[$dir]')
  local has_invariants
  has_invariants=$(echo "$filenames" | jq 'any(endswith("INVARIANTS.md"))')

  assert_eq "true" "$has_invariants" "$test_name"

  teardown
}

# =============================================================================
# COMMANDS.MD DISCOVERY TESTS (Step 1 fix verification)
# =============================================================================

test_discovers_commands_md() {
  local test_name="COMMANDS.md: discovered via walk-up (Step 1 fix)"
  setup

  # Create COMMANDS.md at project root .directives/
  echo "# Project COMMANDS" > "$PROJECT_DIR/.directives/COMMANDS.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_commands
  has_commands=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("COMMANDS.md"))] | length > 0')

  assert_eq "true" "$has_commands" "$test_name"

  teardown
}

# =============================================================================
# DIRECTIVE FILTERING TESTS (core vs skill vs undeclared)
# =============================================================================

test_includes_core_directives() {
  local test_name="directive filter: core directives (AGENTS.md, INVARIANTS.md) always included"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)

  local has_agents
  has_agents=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("AGENTS.md"))] | length > 0')
  local has_invariants
  has_invariants=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("INVARIANTS.md"))] | length > 0')

  if [ "$has_agents" = "true" ] && [ "$has_invariants" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "AGENTS.md and INVARIANTS.md in pending" "agents=$has_agents, invariants=$has_invariants"
  fi

  teardown
}

test_includes_declared_skill_directives() {
  local test_name="directive filter: declared skill directives (TESTING.md) included"
  setup

  # Create TESTING.md in src/lib (declared in .state.json directives array)
  echo "# Lib TESTING" > "$PROJECT_DIR/src/lib/TESTING.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_testing
  has_testing=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("TESTING.md"))] | length > 0')

  assert_eq "true" "$has_testing" "$test_name"

  teardown
}

test_excludes_undeclared_skill_directives() {
  local test_name="directive filter: undeclared directives (CONTRIBUTING.md) excluded"
  setup

  # Create CONTRIBUTING.md in src/lib (NOT in core_directives or .state.json directives)
  echo "# Lib CONTRIBUTING" > "$PROJECT_DIR/src/lib/CONTRIBUTING.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local has_contributing
  has_contributing=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(endswith("CONTRIBUTING.md"))] | length > 0')

  assert_eq "false" "$has_contributing" "$test_name"

  teardown
}

# =============================================================================
# ENGINE PATH TRACKING TESTS (multi-root)
# =============================================================================

test_engine_paths_use_root() {
  local test_name="engine root: walk-up from ~/.claude/skills/ capped at ~/.claude/"
  setup

  # Create engine directive structure inside fake HOME
  mkdir -p "$HOME/.claude/.directives"
  echo "# Engine INVARIANTS" > "$HOME/.claude/.directives/INVARIANTS.md"
  mkdir -p "$HOME/.claude/skills/brainstorm"
  echo "# Brainstorm skill" > "$HOME/.claude/skills/brainstorm/SKILL.md"

  # Create a directive ABOVE ~/.claude/ that should NOT be found
  echo "# Home AGENTS" > "$HOME/AGENTS.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/brainstorm/SKILL.md\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)

  # pendingPreloads should contain INVARIANTS.md from ~/.claude/.directives/
  local has_invariants
  has_invariants=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(contains("INVARIANTS.md"))] | length > 0')

  # pendingPreloads should NOT contain AGENTS.md from ~/
  local has_agents
  has_agents=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(contains("AGENTS.md"))] | length > 0')

  if [ "$has_invariants" = "true" ] && [ "$has_agents" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "INVARIANTS.md in pending, AGENTS.md NOT in pending" "$(echo "$state" | jq '.pendingPreloads')"
  fi

  teardown
}

test_engine_directives_added_to_pending() {
  local test_name="engine pending: reading ~/.claude/skills/ adds directives to pendingPreloads"
  setup

  # Create engine directive structure
  mkdir -p "$HOME/.claude/.directives"
  echo "# Engine INVARIANTS" > "$HOME/.claude/.directives/INVARIANTS.md"
  mkdir -p "$HOME/.claude/skills/brainstorm"
  echo "# Brainstorm" > "$HOME/.claude/skills/brainstorm/SKILL.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/brainstorm/SKILL.md\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '(.pendingPreloads // []) | length')

  assert_gt "$pending_count" 0 "$test_name"

  teardown
}

test_project_paths_unchanged() {
  local test_name="project paths: non-engine paths use PWD boundary (no --root)"
  setup

  # Create project directives at root and deep nested
  echo "# Root AGENTS" > "$PROJECT_DIR/.directives/AGENTS.md"
  mkdir -p "$PROJECT_DIR/src/deep/nested"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/deep/nested/file.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)

  # Walk-up from src/deep/nested should find AGENTS.md at project root (PWD boundary)
  local has_agents
  has_agents=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(contains("AGENTS.md"))] | length > 0')

  assert_eq "true" "$has_agents" "$test_name"

  teardown
}

# =============================================================================
# HARD FILE (CHECKLIST) TESTS
# =============================================================================

test_discovers_checklist_adds_to_state() {
  local test_name="hard discovery: adds CHECKLIST.md to discoveredChecklists"
  setup

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local checklist_count
  checklist_count=$(echo "$state" | jq '(.discoveredChecklists // []) | length')

  assert_gt "$checklist_count" 0 "$test_name"

  teardown
}

test_checklist_not_duplicated() {
  local test_name="hard discovery: CHECKLIST.md not duplicated on re-discovery"
  setup

  # Touch utils dir (has CHECKLIST.md)
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/test.ts\"},\"transcript_path\":\"/tmp/test\"}"

  # Manually reset touchedDirs to force re-discovery
  jq '.touchedDirs = {}' "$SESSION_DIR/.state.json" | tee "$SESSION_DIR/.state.json.tmp" > /dev/null && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  # Touch same dir again
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/utils/other.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local count
  count=$(echo "$state" | jq '[.discoveredChecklists[] | select(endswith("CHECKLIST.md"))] | length')

  assert_eq "1" "$count" "$test_name"

  teardown
}

# =============================================================================
# EXCLUDED PATH COMPONENT TESTS (sessions/, tmp/, node_modules/)
# =============================================================================

test_excludes_sessions_subdirectory() {
  local test_name="excluded paths: sessions/ subdirectory does not discover TESTING.md"
  setup

  # Create a sessions/ subdirectory with TESTING.md
  mkdir -p "$PROJECT_DIR/sessions/2026_02_09_SOME_SESSION"
  echo "# Testing Debrief" > "$PROJECT_DIR/sessions/2026_02_09_SOME_SESSION/TESTING.md"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/sessions/2026_02_09_SOME_SESSION/file.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local testing_count
  testing_count=$(echo "$state" | jq '[(.pendingPreloads // [])[] | select(contains("TESTING.md"))] | length')

  assert_eq "0" "$testing_count" "$test_name"

  teardown
}

test_excludes_tmp_subdirectory() {
  local test_name="excluded paths: tmp/ subdirectory does not discover directives"
  setup

  # Create a tmp/ subdirectory with an INVARIANTS.md
  mkdir -p "$PROJECT_DIR/tmp/debug-output"
  echo "# Debug INVARIANTS" > "$PROJECT_DIR/tmp/debug-output/INVARIANTS.md"

  # Remove project-root directives so walk-up finds nothing
  rm -rf "$PROJECT_DIR/.directives"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/tmp/debug-output/file.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '(.pendingPreloads // []) | length')

  assert_eq "0" "$pending_count" "$test_name"

  teardown
}

test_excludes_node_modules_subdirectory() {
  local test_name="excluded paths: node_modules/ subdirectory does not discover directives"
  setup

  # Create a node_modules/ subdirectory with INVARIANTS.md
  mkdir -p "$PROJECT_DIR/node_modules/some-package"
  echo "# Package INVARIANTS" > "$PROJECT_DIR/node_modules/some-package/INVARIANTS.md"

  # Remove project-root directives
  rm -rf "$PROJECT_DIR/.directives"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/node_modules/some-package/index.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '(.pendingPreloads // []) | length')

  assert_eq "0" "$pending_count" "$test_name"

  teardown
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_skips_empty_file_path() {
  local test_name="empty path: skips when file_path is empty"
  setup

  run_hook '{"tool_name":"Read","tool_input":{},"transcript_path":"/tmp/test"}'
  local state
  state=$(read_state)
  local has_touched
  has_touched=$(echo "$state" | jq 'has("touchedDirs")')

  assert_eq "false" "$has_touched" "$test_name"

  teardown
}

test_no_discovery_when_no_instruction_files() {
  local test_name="no files: no pendingPreloads when directory has no instruction files"
  setup

  # Create an empty subdirectory with no instruction files
  mkdir -p "$PROJECT_DIR/empty/deep"

  # Remove project-root directives so walk-up finds nothing
  rm -rf "$PROJECT_DIR/.directives"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/empty/deep/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '(.pendingPreloads // []) | length')

  assert_eq "0" "$pending_count" "$test_name"

  teardown
}

# =============================================================================
# NO SESSION TESTS
# =============================================================================

test_allows_when_no_session() {
  local test_name="no session: allows tool when session.sh find returns empty"
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
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}")
  local exit_code=$?

  # hook_allow outputs JSON with permissionDecision:allow
  local is_allow
  is_allow=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")

  if [ "$exit_code" -eq 0 ] && [ "$is_allow" = "allow" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, permissionDecision=allow" "exit=$exit_code, output='$output'"
  fi

  teardown
}

# =============================================================================
# PRELOADED FILES DEDUP TEST
# =============================================================================

test_skips_already_preloaded_files() {
  local test_name="preloaded dedup: files in preloadedFiles are not re-added to pendingPreloads"
  setup

  # Pre-populate preloadedFiles with a path that would otherwise be discovered
  local invariants_path="$PROJECT_DIR/.directives/INVARIANTS.md"
  jq --arg file "$invariants_path" '.preloadedFiles = [$file]' \
    "$SESSION_DIR/.state.json" | tee "$SESSION_DIR/.state.json.tmp" > /dev/null \
    && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/lib/test.ts\"},\"transcript_path\":\"/tmp/test\"}"
  local state
  state=$(read_state)

  # The project-root INVARIANTS.md should NOT be in pendingPreloads (already preloaded)
  local root_invariants_in_pending
  root_invariants_in_pending=$(echo "$state" | jq --arg file "$invariants_path" \
    '[(.pendingPreloads // [])[] | select(. == $file)] | length')

  assert_eq "0" "$root_invariants_in_pending" "$test_name"

  teardown
}

# =============================================================================
# SIBLING DIRECTORY DEDUP TESTS (double preload bug)
# =============================================================================

test_sibling_dirs_no_duplicate_pendingPreloads() {
  local test_name="sibling dedup: two sibling leaf dirs don't duplicate ancestor directives in pendingPreloads"
  setup

  mkdir -p "$PROJECT_DIR/pkg/.directives"
  mkdir -p "$PROJECT_DIR/pkg/src/workflows/process-estimate"
  mkdir -p "$PROJECT_DIR/pkg/src/workflows/annotate-estimate"
  echo "# Pkg AGENTS" > "$PROJECT_DIR/pkg/.directives/AGENTS.md"
  echo "# Pkg INVARIANTS" > "$PROJECT_DIR/pkg/.directives/INVARIANTS.md"

  rm -rf "$PROJECT_DIR/.directives"

  # Touch leaf A
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/workflows/process-estimate/foo.ts\"},\"transcript_path\":\"/tmp/test\"}"
  # Touch leaf B (sibling)
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/workflows/annotate-estimate/bar.ts\"},\"transcript_path\":\"/tmp/test\"}"

  local state
  state=$(read_state)

  local agents_count
  agents_count=$(echo "$state" | jq \
    '[(.pendingPreloads // [])[] | select(endswith("pkg/.directives/AGENTS.md"))] | length')

  assert_eq "1" "$agents_count" "$test_name"

  teardown
}

test_activation_seeded_dirs_prevent_runtime_requeue() {
  # THE ACTUAL BUG: session activation seeds touchedDirs with basenames ("AGENTS.md"),
  # but _run_discovery stores full normalized paths ("/abs/path/.directives/AGENTS.md").
  # The already_suggested check compares full paths against basenames → no match → re-queued.
  local test_name="activation dedup: activation-seeded touchedDirs prevents runtime re-discovery"
  setup

  mkdir -p "$PROJECT_DIR/pkg/.directives"
  mkdir -p "$PROJECT_DIR/pkg/src/a"
  echo "# Pkg AGENTS" > "$PROJECT_DIR/pkg/.directives/AGENTS.md"

  rm -rf "$PROJECT_DIR/.directives"

  # Simulate what session.sh activate does: seed touchedDirs with BASENAMES
  # (session.sh line 854: .touchedDirs[$dir] = ["AGENTS.md"] — basenames, not full paths)
  local directives_dir="$PROJECT_DIR/pkg/.directives"
  jq --arg dir "$directives_dir" \
    '(.touchedDirs //= {}) | .touchedDirs[$dir] = ["AGENTS.md"]' \
    "$SESSION_DIR/.state.json" | tee "$SESSION_DIR/.state.json.tmp" > /dev/null \
    && mv "$SESSION_DIR/.state.json.tmp" "$SESSION_DIR/.state.json"

  # Now touch a file under pkg/ — _run_discovery walks up, finds same AGENTS.md
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/a/foo.ts\"},\"transcript_path\":\"/tmp/test\"}"

  local state
  state=$(read_state)

  # AGENTS.md should NOT be in pendingPreloads — it was already seeded by activation
  local agents_count
  agents_count=$(echo "$state" | jq \
    '[(.pendingPreloads // [])[] | select(endswith("pkg/.directives/AGENTS.md"))] | length')

  assert_eq "0" "$agents_count" "$test_name"

  teardown
}

test_three_sibling_dirs_single_preload() {
  local test_name="sibling dedup: three sibling leaf dirs — ancestor directive queued exactly once"
  setup

  mkdir -p "$PROJECT_DIR/pkg/.directives"
  mkdir -p "$PROJECT_DIR/pkg/src/x"
  mkdir -p "$PROJECT_DIR/pkg/src/y"
  mkdir -p "$PROJECT_DIR/pkg/src/z"
  echo "# Pkg AGENTS" > "$PROJECT_DIR/pkg/.directives/AGENTS.md"

  rm -rf "$PROJECT_DIR/.directives"

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/x/foo.ts\"},\"transcript_path\":\"/tmp/test\"}"
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/y/bar.ts\"},\"transcript_path\":\"/tmp/test\"}"
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/z/baz.ts\"},\"transcript_path\":\"/tmp/test\"}"

  local state
  state=$(read_state)

  local agents_count
  agents_count=$(echo "$state" | jq \
    '[(.pendingPreloads // [])[] | select(endswith("pkg/.directives/AGENTS.md"))] | length')

  assert_eq "1" "$agents_count" "$test_name"

  teardown
}

# =============================================================================
# PARALLEL RACE CONDITION TESTS (atomic claim)
# =============================================================================

test_parallel_hooks_single_discovery() {
  local test_name="parallel race: concurrent hooks on same dir — only one discovers"
  setup

  mkdir -p "$PROJECT_DIR/pkg/.directives"
  mkdir -p "$PROJECT_DIR/pkg/src/a"
  echo "# Pkg AGENTS" > "$PROJECT_DIR/pkg/.directives/AGENTS.md"

  rm -rf "$PROJECT_DIR/.directives"

  # Simulate parallel hooks: launch two hook invocations for the SAME directory concurrently.
  # Both touch pkg/src/a/ — only one should claim the directory and discover AGENTS.md.
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/a/foo.ts\"},\"transcript_path\":\"/tmp/test\"}" &
  local pid1=$!
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/pkg/src/a/bar.ts\"},\"transcript_path\":\"/tmp/test\"}" &
  local pid2=$!

  wait "$pid1" 2>/dev/null || true
  wait "$pid2" 2>/dev/null || true

  local state
  state=$(read_state)

  # AGENTS.md should appear exactly once in pendingPreloads (not twice)
  local agents_count
  agents_count=$(echo "$state" | jq \
    '[(.pendingPreloads // [])[] | select(endswith("pkg/.directives/AGENTS.md"))] | length')

  assert_eq "1" "$agents_count" "$test_name"

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-pre-tool-use-discovery.sh ==="

# Tool filtering
test_skips_bash_tool
test_processes_glob_tool
test_processes_grep_tool
test_grep_directory_path_used_directly
test_glob_no_path_skips_discovery
test_processes_read_tool
test_processes_edit_tool
test_processes_write_tool

# Touched dirs tracking
test_tracks_new_dir
test_idempotent_same_dir
test_tracks_multiple_dirs

# Soft file discovery
test_discovers_invariants_in_pending
test_walk_up_discovers_agents
test_soft_files_stored_in_touched_dirs

# COMMANDS.md discovery (Step 1 fix)
test_discovers_commands_md

# Directive filtering
test_includes_core_directives
test_includes_declared_skill_directives
test_excludes_undeclared_skill_directives

# Engine path tracking (multi-root)
test_engine_paths_use_root
test_engine_directives_added_to_pending
test_project_paths_unchanged

# Hard file (checklist) discovery
test_discovers_checklist_adds_to_state
test_checklist_not_duplicated

# Excluded path components
test_excludes_sessions_subdirectory
test_excludes_tmp_subdirectory
test_excludes_node_modules_subdirectory

# Edge cases
test_skips_empty_file_path
test_no_discovery_when_no_instruction_files

# No session
test_allows_when_no_session

# Preloaded files dedup
test_skips_already_preloaded_files

# Sibling directory dedup (double preload bug)
test_sibling_dirs_no_duplicate_pendingPreloads
test_activation_seeded_dirs_prevent_runtime_requeue
test_three_sibling_dirs_single_preload

# Parallel race condition (atomic claim)
test_parallel_hooks_single_discovery

exit_with_results
