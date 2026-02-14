#!/bin/bash
# test-cmd-override.sh — Tests for CMD file override detection in _claim_and_preload
#
# Tests that when a local CMD file is claimed and a global CMD with the same basename
# is already in preloadedFiles, the injected content includes an [Override: ...] header.
#
# Run: bash ~/.claude/engine/scripts/tests/test-cmd-override.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths before HOME switch
REAL_HOME="$HOME"
HOOK_SH="$REAL_HOME/.claude/engine/hooks/pre-tool-use-overflow-v2.sh"
LIB_SH="$REAL_HOME/.claude/scripts/lib.sh"
DISCOVER_SH="$REAL_HOME/.claude/scripts/discover-directives.sh"

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

  # Symlink core scripts
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  ln -sf "$DISCOVER_SH" "$HOME/.claude/scripts/discover-directives.sh"
  ln -sf "$HOOK_SH" "$HOME/.claude/hooks/pre-tool-use-overflow-v2.sh"

  # guards.json with preload rule only (raw array — not object-wrapped)
  cat > "$HOME/.claude/engine/guards.json" <<'GUARDS'
[
  {
    "id": "preload",
    "description": "Auto-preload pending files",
    "trigger": {
      "type": "discovery",
      "condition": { "field": "pendingPreloads", "nonEmpty": true }
    },
    "payload": {
      "preload": "$pendingPreloads"
    },
    "mode": "preload",
    "urgency": "allow",
    "priority": 20,
    "inject": "always"
  }
]
GUARDS

  # Empty config.sh
  touch "$HOME/.claude/engine/config.sh"

  # Mock fleet.sh
  cat > "$HOME/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  # Test session directory
  SESSION_DIR="$TEST_DIR/sessions/test-override"
  mkdir -p "$SESSION_DIR"

  # Mock session.sh — returns test session dir
  cat > "$HOME/.claude/scripts/session.sh" <<SCRIPT
#!/bin/bash
if [ "\${1:-}" = "find" ]; then
  echo "$SESSION_DIR"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  # Project dir
  PROJECT_DIR="$TEST_DIR/project"
  mkdir -p "$PROJECT_DIR/src"
  cd "$PROJECT_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the hook with a Read tool call
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/hooks/pre-tool-use-overflow-v2.sh" 2>/dev/null
}

echo "=== test-cmd-override.sh ==="

# =============================================================================
# TEST 1: Override header added when local CMD shadows global
# =============================================================================

test_override_header_when_local_shadows_global() {
  local test_name="override: local CMD gets [Override] header when global is preloaded"
  setup

  # Create global CMD file (already preloaded)
  local global_cmd_dir="$HOME/.claude/engine/.directives/commands"
  mkdir -p "$global_cmd_dir"
  echo "# Global FOO command definition" > "$global_cmd_dir/CMD_FOO.md"
  local global_path="$global_cmd_dir/CMD_FOO.md"

  # Create local CMD file (pending preload)
  local local_cmd="$PROJECT_DIR/.directives/commands/CMD_FOO.md"
  mkdir -p "$(dirname "$local_cmd")"
  echo "# Local FOO override" > "$local_cmd"

  # State: global preloaded, local pending
  cat > "$SESSION_DIR/.state.json" <<STATE
{
  "pid": $$,
  "skill": "test",
  "lifecycle": "active",
  "loading": false,
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0,
  "currentPhase": "3: Build",
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200,
  "preloadedFiles": ["$global_path"],
  "pendingPreloads": ["$local_cmd"]
}
STATE

  # Run hook — the preload rule fires, claims the file, stashes to pendingAllowInjections
  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/index.ts\"},\"transcript_path\":\"/tmp/test\"}"

  # Check pendingAllowInjections in .state.json for override header
  local stashed_content
  stashed_content=$(jq -r '.pendingAllowInjections // [] | .[].content // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")

  if echo "$stashed_content" | grep -q "Override.*shadows.*CMD_FOO.md"; then
    pass "$test_name"
  else
    fail "$test_name" "stashed content contains 'Override: shadows CMD_FOO.md'" "stashed=$(echo "$stashed_content" | head -5)"
  fi

  teardown
}

# =============================================================================
# TEST 2: No override header when CMD has no global counterpart
# =============================================================================

test_no_override_for_novel_cmd() {
  local test_name="override: no [Override] header for CMD without global counterpart"
  setup

  # Create local CMD file with no global equivalent
  local local_cmd="$PROJECT_DIR/.directives/commands/CMD_UNIQUE.md"
  mkdir -p "$(dirname "$local_cmd")"
  echo "# Unique local command" > "$local_cmd"

  cat > "$SESSION_DIR/.state.json" <<STATE
{
  "pid": $$,
  "skill": "test",
  "lifecycle": "active",
  "loading": false,
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0,
  "currentPhase": "3: Build",
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200,
  "preloadedFiles": [],
  "pendingPreloads": ["$local_cmd"]
}
STATE

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/index.ts\"},\"transcript_path\":\"/tmp/test\"}")

  if echo "$output" | grep -q "Override"; then
    fail "$test_name" "no Override header" "output contains Override"
  else
    pass "$test_name"
  fi

  teardown
}

# =============================================================================
# TEST 3: Non-CMD files never get override header
# =============================================================================

test_no_override_for_non_cmd() {
  local test_name="override: non-CMD files never get [Override] header"
  setup

  # Create a non-CMD directive file
  local local_inv="$PROJECT_DIR/.directives/INVARIANTS.md"
  mkdir -p "$(dirname "$local_inv")"
  echo "# Local invariants" > "$local_inv"

  # Global with same basename
  mkdir -p "$HOME/.claude/.directives"
  echo "# Global invariants" > "$HOME/.claude/.directives/INVARIANTS.md"

  cat > "$SESSION_DIR/.state.json" <<STATE
{
  "pid": $$,
  "skill": "test",
  "lifecycle": "active",
  "loading": false,
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0,
  "currentPhase": "3: Build",
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200,
  "preloadedFiles": ["$HOME/.claude/.directives/INVARIANTS.md"],
  "pendingPreloads": ["$local_inv"]
}
STATE

  local output
  output=$(run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/index.ts\"},\"transcript_path\":\"/tmp/test\"}")

  if echo "$output" | grep -q "Override"; then
    fail "$test_name" "no Override header for INVARIANTS.md" "output contains Override"
  else
    pass "$test_name"
  fi

  teardown
}

# Run tests
test_override_header_when_local_shadows_global
test_no_override_for_novel_cmd
test_no_override_for_non_cmd

exit_with_results
