#!/bin/bash
# ~/.claude/engine/scripts/tests/test-post-tool-use-templates.sh
# Tests for the PostToolUse templates hook (post-tool-use-templates.sh)
#
# Tests: Skill tool filtering, direct additionalContext delivery via SKILL.md
# JSON fields, session tracking (preloadedFiles), dedup, no-session delivery.
#
# Run: bash ~/.claude/engine/scripts/tests/test-post-tool-use-templates.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK_SH="$HOME/.claude/hooks/post-tool-use-templates.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

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
  # Link the hook into fake home
  ln -sf "$HOOK_SH" "$HOME/.claude/hooks/post-tool-use-templates.sh"

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

  cd "$TEST_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the hook with env vars, capture stdout
run_hook() {
  local input="$1"
  local tool_name tool_input
  tool_name=$(echo "$input" | jq -r '.tool_name // ""')
  tool_input=$(echo "$input" | jq -c '.tool_input // {}')
  TOOL_NAME="$tool_name" TOOL_INPUT="$tool_input" bash "$HOME/.claude/hooks/post-tool-use-templates.sh" 2>/dev/null
}

# Helper: read .state.json
read_state() {
  cat "$SESSION_DIR/.state.json"
}

# Helper: create SKILL.md with JSON block + template files for a skill
create_skill_with_templates() {
  local skill_name="$1"
  shift
  local skill_dir="$HOME/.claude/skills/$skill_name"
  local assets_dir="$skill_dir/assets"
  mkdir -p "$assets_dir"

  # Build JSON fields and create template files
  local json_fields=""
  for tmpl_type in "$@"; do
    local filename
    local upper_skill
    upper_skill=$(echo "$skill_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    case "$tmpl_type" in
      LOG)
        filename="TEMPLATE_${upper_skill}_LOG.md"
        echo "# Log template for $skill_name" > "$assets_dir/$filename"
        json_fields="${json_fields}  \"logTemplate\": \"assets/$filename\",
"
        ;;
      DEBRIEF)
        filename="TEMPLATE_${upper_skill}.md"
        echo "# Debrief template for $skill_name" > "$assets_dir/$filename"
        json_fields="${json_fields}  \"debriefTemplate\": \"assets/$filename\",
"
        ;;
      PLAN)
        filename="TEMPLATE_${upper_skill}_PLAN.md"
        echo "# Plan template for $skill_name" > "$assets_dir/$filename"
        json_fields="${json_fields}  \"planTemplate\": \"assets/$filename\",
"
        ;;
    esac
  done

  # Create SKILL.md with JSON block
  cat > "$skill_dir/SKILL.md" <<SKILLEOF
---
description: "Test skill $skill_name"
---

# $skill_name

\`\`\`json
{
  "taskType": "$(echo "$skill_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')",
${json_fields}  "phases": []
}
\`\`\`
SKILLEOF
}

# =============================================================================
# TEST: fires on Skill tool — delivers templates via additionalContext
# =============================================================================

test_fires_on_skill_tool() {
  local test_name="fires on Skill tool: delivers templates via additionalContext"
  setup

  create_skill_with_templates "brainstorm" LOG DEBRIEF

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}')

  # Check stdout has additionalContext with template content
  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  local has_log has_debrief
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_BRAINSTORM_LOG.md" || true)
  has_debrief=$(echo "$has_context" | grep -c "TEMPLATE_BRAINSTORM.md" || true)

  if [ "$has_log" -ge 1 ] && [ "$has_debrief" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "additionalContext with LOG + DEBRIEF templates" "has_log=$has_log, has_debrief=$has_debrief"
  fi

  teardown
}

# =============================================================================
# TEST: ignores non-Skill tools
# =============================================================================

test_ignores_non_skill_tools() {
  local test_name="ignores non-Skill tools: no output"
  setup

  local output
  output=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/some/file"}}')

  if [ -z "$output" ]; then
    pass "$test_name"
  else
    fail "$test_name" "(empty output)" "$output"
  fi

  teardown
}

# =============================================================================
# TEST: derives correct template paths (all 3 types from SKILL.md JSON)
# =============================================================================

test_derives_correct_template_paths() {
  local test_name="derives correct paths: all 3 template types from SKILL.md JSON"
  setup

  create_skill_with_templates "implement" LOG DEBRIEF PLAN

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"implement"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  local has_log has_debrief has_plan
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_IMPLEMENT_LOG.md" || true)
  has_debrief=$(echo "$has_context" | grep -c "TEMPLATE_IMPLEMENT.md" || true)
  has_plan=$(echo "$has_context" | grep -c "TEMPLATE_IMPLEMENT_PLAN.md" || true)

  if [ "$has_log" -ge 1 ] && [ "$has_debrief" -ge 1 ] && [ "$has_plan" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "additionalContext with LOG + DEBRIEF + PLAN" "has_log=$has_log, has_debrief=$has_debrief, has_plan=$has_plan"
  fi

  teardown
}

# =============================================================================
# TEST: skips missing templates gracefully
# =============================================================================

test_skips_missing_templates() {
  local test_name="skips missing: only LOG exists, DEBRIEF/PLAN absent"
  setup

  create_skill_with_templates "test" LOG

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"test"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  local has_log has_debrief
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_TEST_LOG.md" || true)
  has_debrief=$(echo "$has_context" | grep -c "TEMPLATE_TEST.md" || true)

  if [ "$has_log" -ge 1 ] && [ "$has_debrief" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "LOG present, DEBRIEF absent" "has_log=$has_log, has_debrief=$has_debrief"
  fi

  teardown
}

# =============================================================================
# TEST: template content is included in additionalContext
# =============================================================================

test_template_content_included() {
  local test_name="content: template file content appears in additionalContext"
  setup

  create_skill_with_templates "brainstorm" LOG

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  # The template file contains "# Log template for brainstorm"
  local has_content
  has_content=$(echo "$has_context" | grep -c "Log template for brainstorm" || true)

  if [ "$has_content" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "contains template file content" "content not found in additionalContext"
  fi

  teardown
}

# =============================================================================
# TEST: session tracking — preloadedFiles
# =============================================================================

test_session_tracking() {
  local test_name="session tracking: updates preloadedFiles"
  setup

  create_skill_with_templates "brainstorm" LOG DEBRIEF

  run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' > /dev/null

  local state
  state=$(read_state)
  local preloaded_count
  preloaded_count=$(echo "$state" | jq '.preloadedFiles | length' 2>/dev/null || echo "0")

  if [ "$preloaded_count" -gt 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "preloadedFiles non-empty" "preloaded_count=$preloaded_count"
  fi

  teardown
}

# =============================================================================
# TEST: no session — still delivers templates via additionalContext
# =============================================================================

test_delivers_without_session() {
  local test_name="no session: still delivers templates via direct additionalContext"
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

  create_skill_with_templates "brainstorm" LOG DEBRIEF

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  local has_log
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_BRAINSTORM_LOG.md" || true)

  if [ "$has_log" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "additionalContext with templates even without session" "has_log=$has_log"
  fi

  teardown
}

# =============================================================================
# TEST: handles hyphenated skill name
# =============================================================================

test_handles_hyphenated_skill_name() {
  local test_name="hyphenated: edit-skill reads from SKILL.md JSON correctly"
  setup

  create_skill_with_templates "edit-skill" LOG

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"edit-skill"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  local has_log
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_EDIT_SKILL_LOG.md" || true)

  if [ "$has_log" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "additionalContext with TEMPLATE_EDIT_SKILL_LOG.md" "has_log=$has_log"
  fi

  teardown
}

# =============================================================================
# FAILURE SCENARIO TESTS — .state.json corruption / race conditions
# These reproduce the "PostToolUse:Skill hook error" bug where unprotected
# jq calls crash the hook under set -euo pipefail.
# =============================================================================

test_exits_0_with_corrupted_state_json() {
  local test_name="resilience: exits 0 with corrupted .state.json"
  setup

  create_skill_with_templates "brainstorm" LOG DEBRIEF

  # Corrupt .state.json with invalid JSON
  echo "NOT VALID JSON {{{" > "$SESSION_DIR/.state.json"

  local output exit_code
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}') || true
  # Re-run to capture exit code cleanly
  TOOL_NAME=Skill TOOL_INPUT='{"skill":"brainstorm"}' bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name — exit code"
  # Direct delivery should still work even if .state.json update fails
  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_log
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_BRAINSTORM_LOG.md" || true)
  if [ "$has_log" -ge 1 ]; then
    pass "$test_name — direct delivery still works"
  else
    fail "$test_name — direct delivery still works" "additionalContext present" "missing"
  fi

  teardown
}

test_exits_0_with_empty_state_json() {
  local test_name="resilience: exits 0 with empty .state.json"
  setup

  create_skill_with_templates "brainstorm" LOG

  # Empty file — jq empty will fail on this
  > "$SESSION_DIR/.state.json"

  local exit_code
  TOOL_NAME=Skill TOOL_INPUT='{"skill":"brainstorm"}' bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name"

  teardown
}

test_exits_0_with_missing_preloaded_fields() {
  local test_name="resilience: exits 0 when .state.json lacks preloadedFiles"
  setup

  create_skill_with_templates "brainstorm" LOG

  # Minimal JSON without preloadedFiles or pendingPreloads
  echo '{"pid": 1, "skill": "test"}' > "$SESSION_DIR/.state.json"

  local output exit_code
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}') || true
  TOOL_NAME=Skill TOOL_INPUT='{"skill":"brainstorm"}' bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name — exit code"
  # Direct delivery should still work
  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  assert_not_empty "$has_context" "$test_name — direct delivery still works"

  teardown
}

test_exits_0_with_state_json_deleted_mid_run() {
  local test_name="resilience: exits 0 when .state.json disappears mid-execution"
  setup

  create_skill_with_templates "brainstorm" LOG

  # session.sh find returns a dir, but .state.json doesn't exist
  rm -f "$SESSION_DIR/.state.json"

  local exit_code
  TOOL_NAME=Skill TOOL_INPUT='{"skill":"brainstorm"}' bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name"

  teardown
}

test_exits_0_with_state_json_array_instead_of_object() {
  local test_name="resilience: exits 0 when .state.json is a JSON array"
  setup

  create_skill_with_templates "brainstorm" LOG

  # Valid JSON but wrong shape — jq operations expecting object will fail
  echo '["not", "an", "object"]' > "$SESSION_DIR/.state.json"

  local exit_code
  TOOL_NAME=Skill TOOL_INPUT='{"skill":"brainstorm"}' bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name"

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-post-tool-use-templates.sh ==="

# Core functionality
test_fires_on_skill_tool
test_ignores_non_skill_tools
test_derives_correct_template_paths
test_skips_missing_templates
test_template_content_included
test_session_tracking
test_delivers_without_session
test_handles_hyphenated_skill_name

# Failure scenarios (reproduce "hook error" bug)
test_exits_0_with_corrupted_state_json
test_exits_0_with_empty_state_json
test_exits_0_with_missing_preloaded_fields
test_exits_0_with_state_json_deleted_mid_run
test_exits_0_with_state_json_array_instead_of_object

exit_with_results
