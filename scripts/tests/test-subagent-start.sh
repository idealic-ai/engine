#!/bin/bash
# tests/test-subagent-start.sh — Tests for subagent-start-context.sh hook
#
# Tests SubagentStart hook context injection:
#   1. No active session → empty output
#   2. Active session with logTemplate → injects log template
#   3. Active session with discovered directives → injects directives
#   4. Standards NOT injected (COMMANDS.md, INVARIANTS.md, TAGS.md excluded)
#   5. No logTemplate → no template injection (directives still injected)
#
# Run: bash ~/.claude/engine/scripts/tests/test-subagent-start.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths BEFORE setup_fake_home (avoids circular symlink issues)
REAL_HOOK="$HOME/.claude/hooks/subagent-start-context.sh"
REAL_ENGINE_DIR="$HOME/.claude/engine"
REAL_SCRIPTS_DIR="$HOME/.claude/scripts"

TMP_DIR=""

setup() {
  TMP_DIR=$(mktemp -d)
  export CLAUDE_SUPERVISOR_PID=$$

  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux

  # Symlink core scripts (needed by session.sh find)
  ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  ln -sf "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"

  # Symlink the hook under test
  ln -sf "$REAL_HOOK" "$FAKE_HOME/.claude/hooks/subagent-start-context.sh"

  # Stub fleet and search tools
  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"

  # Work in TMP_DIR so session.sh find scans our test sessions
  cd "$TMP_DIR"

  # Create test session directory
  TEST_SESSION="$TMP_DIR/sessions/test_subagent"
  mkdir -p "$TEST_SESSION"

  RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/subagent-start-context.sh"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# Helper: run the hook with SubagentStart input JSON
run_hook() {
  echo '{"hook_event_name":"SubagentStart","agent_id":"test-agent","agent_type":"task","session_id":"test","transcript_path":"/tmp/test.jsonl","cwd":"'"$TMP_DIR"'"}' \
    | "$RESOLVED_HOOK" 2>/dev/null
}

# ======================================================================
# Test 1: No active session → empty output
# ======================================================================
test_no_session_empty_output() {
  echo "--- 1. No active session → empty output ---"

  # No .state.json exists → session.sh find will fail → hook exits 0 with no output
  local output
  output=$(run_hook) || true

  assert_empty "$output" "no active session → no output"
}

# ======================================================================
# Test 2: Active session with logTemplate → injects log template
# ======================================================================
test_log_template_injection() {
  echo "--- 2. Active session with logTemplate → injects log template ---"

  # Create active session with logTemplate
  cat > "$TEST_SESSION/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "logTemplate": "assets/TEMPLATE_IMPLEMENTATION_LOG.md",
  "preloadedFiles": []
}
JSON

  # Create the template file at the resolved path
  local skill_dir="$FAKE_HOME/.claude/skills/implement/assets"
  mkdir -p "$skill_dir"
  echo "# Implementation Log Template
## Progress Update
*   **Task**: [what]
*   **Status**: [status]" > "$skill_dir/TEMPLATE_IMPLEMENTATION_LOG.md"

  local output
  output=$(run_hook) || true

  assert_not_empty "$output" "active session with logTemplate → produces output"
  assert_contains "hookSpecificOutput" "$output" "output is valid hook response JSON"
  assert_contains "SubagentStart" "$output" "output has correct hookEventName"
  assert_contains "additionalContext" "$output" "output has additionalContext field"
  assert_contains "Implementation Log Template" "$output" "output contains template content"
  assert_contains "Preloaded:" "$output" "output uses [Preloaded:] format"
}

# ======================================================================
# Test 3: Active session with discovered directives → injects directives
# ======================================================================
test_directive_injection() {
  echo "--- 3. Active session with discovered directives → injects directives ---"

  # Create directive files
  local directive_dir="$FAKE_HOME/.claude/skills/.directives"
  mkdir -p "$directive_dir"
  echo "# Skill-level pitfalls
- Watch out for X" > "$directive_dir/PITFALLS.md"

  local project_directive_dir="$TMP_DIR/.directives"
  mkdir -p "$project_directive_dir"
  echo "# Project agents config
- Agent A does Y" > "$project_directive_dir/AGENTS.md"

  # Create active session with preloadedFiles (directives already discovered)
  cat > "$TEST_SESSION/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "logTemplate": "",
  "preloadedFiles": [
    "$FAKE_HOME/.claude/skills/.directives/PITFALLS.md",
    "$project_directive_dir/AGENTS.md"
  ]
}
JSON

  local output
  output=$(run_hook) || true

  assert_not_empty "$output" "active session with directives → produces output"
  assert_contains "Skill-level pitfalls" "$output" "output contains PITFALLS.md content"
  assert_contains "Project agents config" "$output" "output contains AGENTS.md content"
}

# ======================================================================
# Test 4: Standards NOT injected
# ======================================================================
test_standards_excluded() {
  echo "--- 4. Standards NOT injected in sub-agent context ---"

  # Create standards files (these exist in the main agent but should NOT be injected)
  mkdir -p "$FAKE_HOME/.claude/.directives"
  echo "# COMMANDS content" > "$FAKE_HOME/.claude/.directives/COMMANDS.md"
  echo "# INVARIANTS content" > "$FAKE_HOME/.claude/.directives/INVARIANTS.md"
  echo "# TAGS content" > "$FAKE_HOME/.claude/.directives/TAGS.md"

  # Create a non-standards directive
  local directive_dir="$FAKE_HOME/.claude/skills/.directives"
  mkdir -p "$directive_dir"
  echo "# Skill pitfalls" > "$directive_dir/PITFALLS.md"

  # Session has both standards and non-standards in preloadedFiles
  cat > "$TEST_SESSION/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "logTemplate": "",
  "preloadedFiles": [
    "$FAKE_HOME/.claude/.directives/COMMANDS.md",
    "$FAKE_HOME/.claude/.directives/INVARIANTS.md",
    "$FAKE_HOME/.claude/.directives/TAGS.md",
    "$FAKE_HOME/.claude/skills/.directives/PITFALLS.md"
  ]
}
JSON

  local output
  output=$(run_hook) || true

  assert_not_contains "COMMANDS content" "$output" "COMMANDS.md NOT in sub-agent context"
  assert_not_contains "INVARIANTS content" "$output" "INVARIANTS.md NOT in sub-agent context"
  assert_not_contains "TAGS content" "$output" "TAGS.md NOT in sub-agent context"
  assert_contains "Skill pitfalls" "$output" "non-standards directives ARE injected"
}

# ======================================================================
# Test 5: No logTemplate → no template injection (directives still work)
# ======================================================================
test_no_log_template() {
  echo "--- 5. No logTemplate → no template injection ---"

  # Create a directive
  local directive_dir="$FAKE_HOME/.claude/skills/.directives"
  mkdir -p "$directive_dir"
  echo "# Skill pitfalls for test 5" > "$directive_dir/PITFALLS.md"

  # Session with no logTemplate but with directives
  cat > "$TEST_SESSION/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "logTemplate": "",
  "preloadedFiles": [
    "$FAKE_HOME/.claude/skills/.directives/PITFALLS.md"
  ]
}
JSON

  local output
  output=$(run_hook) || true

  assert_not_empty "$output" "session without logTemplate but with directives → produces output"
  assert_contains "Skill pitfalls for test 5" "$output" "directives still injected without logTemplate"
  assert_not_contains "TEMPLATE" "$output" "no template content when logTemplate is empty"
}

# ======================================================================
# Run all tests
# ======================================================================

echo "======================================"
echo "SubagentStart Hook Tests"
echo "======================================"
echo ""

run_test test_no_session_empty_output
echo ""
run_test test_log_template_injection
echo ""
run_test test_directive_injection
echo ""
run_test test_standards_excluded
echo ""
run_test test_no_log_template

echo ""
exit_with_results
