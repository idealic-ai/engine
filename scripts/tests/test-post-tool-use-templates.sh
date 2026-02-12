#!/bin/bash
# ~/.claude/engine/scripts/tests/test-post-tool-use-templates.sh
# Tests for the PostToolUse templates hook (post-tool-use-templates.sh)
#
# Tests: Skill tool filtering, template path derivation, dedup, skill change,
# no session handling, hyphenated skill names, missing templates.
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

# Helper: run the hook with given JSON input
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" 2>/dev/null
}

# Helper: read .state.json
read_state() {
  cat "$SESSION_DIR/.state.json"
}

# Helper: create template files for a skill
create_skill_templates() {
  local skill_name="$1"
  shift
  local upper_skill
  upper_skill=$(echo "$skill_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
  local skill_dir="$HOME/.claude/skills/$skill_name/assets"
  mkdir -p "$skill_dir"

  for tmpl_type in "$@"; do
    case "$tmpl_type" in
      LOG)
        echo "# Log template for $skill_name" > "$skill_dir/TEMPLATE_${upper_skill}_LOG.md"
        ;;
      DEBRIEF)
        echo "# Debrief template for $skill_name" > "$skill_dir/TEMPLATE_${upper_skill}.md"
        ;;
      PLAN)
        echo "# Plan template for $skill_name" > "$skill_dir/TEMPLATE_${upper_skill}_PLAN.md"
        ;;
    esac
  done
}

# =============================================================================
# TEST: fires on Skill tool
# =============================================================================

test_fires_on_skill_tool() {
  local test_name="fires on Skill tool: adds templates to pendingTemplates"
  setup

  create_skill_templates "brainstorm" LOG DEBRIEF

  run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' > /dev/null

  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '.pendingTemplates | length')
  local has_log
  has_log=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_BRAINSTORM_LOG.md"))] | length')
  local has_debrief
  has_debrief=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_BRAINSTORM.md"))] | length')

  if [ "$pending_count" = "2" ] && [ "$has_log" = "1" ] && [ "$has_debrief" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "2 pendingTemplates (LOG + DEBRIEF)" "pending_count=$pending_count, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST: ignores non-Skill tools
# =============================================================================

test_ignores_non_skill_tools() {
  local test_name="ignores non-Skill tools: no state changes"
  setup

  run_hook '{"tool_name":"Read","tool_input":{"file_path":"/some/file"}}' > /dev/null

  local state
  state=$(read_state)
  local has_pending
  has_pending=$(echo "$state" | jq 'has("pendingTemplates")')
  local has_last_skill
  has_last_skill=$(echo "$state" | jq 'has("lastPreloadedSkill")')

  if [ "$has_pending" = "false" ] && [ "$has_last_skill" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "no pendingTemplates, no lastPreloadedSkill" "state=$state"
  fi

  teardown
}

# =============================================================================
# TEST: derives correct template paths (all 3 types)
# =============================================================================

test_derives_correct_template_paths() {
  local test_name="derives correct paths: all 3 template types for skill 'implement'"
  setup

  create_skill_templates "implement" LOG DEBRIEF PLAN

  run_hook '{"tool_name":"Skill","tool_input":{"skill":"implement"}}' > /dev/null

  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '.pendingTemplates | length')
  local has_log
  has_log=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_IMPLEMENT_LOG.md"))] | length')
  local has_debrief
  has_debrief=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_IMPLEMENT.md"))] | length')
  local has_plan
  has_plan=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_IMPLEMENT_PLAN.md"))] | length')

  if [ "$pending_count" = "3" ] && [ "$has_log" = "1" ] && [ "$has_debrief" = "1" ] && [ "$has_plan" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "3 pendingTemplates (LOG + DEBRIEF + PLAN)" "pending_count=$pending_count, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST: skips missing templates
# =============================================================================

test_skips_missing_templates() {
  local test_name="skips missing: only LOG exists for skill 'test'"
  setup

  # Only create LOG template (no DEBRIEF, no PLAN)
  create_skill_templates "test" LOG

  run_hook '{"tool_name":"Skill","tool_input":{"skill":"test"}}' > /dev/null

  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '.pendingTemplates | length')
  local has_log
  has_log=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_TEST_LOG.md"))] | length')

  if [ "$pending_count" = "1" ] && [ "$has_log" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "1 pendingTemplates (LOG only)" "pending_count=$pending_count, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST: dedup on reinvocation
# =============================================================================

test_dedup_on_reinvocation() {
  local test_name="dedup: second invocation of same skill is no-op"
  setup

  create_skill_templates "brainstorm" LOG DEBRIEF

  # First invocation
  run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' > /dev/null
  local state_after_first
  state_after_first=$(read_state)
  local count_first
  count_first=$(echo "$state_after_first" | jq '.pendingTemplates | length')

  # Second invocation — should be deduped via lastPreloadedSkill
  run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' > /dev/null
  local state_after_second
  state_after_second=$(read_state)
  local count_second
  count_second=$(echo "$state_after_second" | jq '.pendingTemplates | length')

  if [ "$count_first" = "2" ] && [ "$count_second" = "2" ]; then
    pass "$test_name"
  else
    fail "$test_name" "count stays at 2 after second call" "count_first=$count_first, count_second=$count_second"
  fi

  teardown
}

# =============================================================================
# TEST: skill change repreloads
# =============================================================================

test_skill_change_repreloads() {
  local test_name="skill change: switching skills adds new templates"
  setup

  create_skill_templates "brainstorm" LOG
  create_skill_templates "implement" LOG DEBRIEF

  # First: brainstorm
  run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' > /dev/null

  # Second: implement — should add implement templates
  run_hook '{"tool_name":"Skill","tool_input":{"skill":"implement"}}' > /dev/null

  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '.pendingTemplates | length')
  local last_skill
  last_skill=$(echo "$state" | jq -r '.lastPreloadedSkill')

  # Should have 3 total: 1 brainstorm + 2 implement
  if [ "$pending_count" = "3" ] && [ "$last_skill" = "implement" ]; then
    pass "$test_name"
  else
    fail "$test_name" "3 pendingTemplates, lastPreloadedSkill=implement" "pending_count=$pending_count, last_skill=$last_skill, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST: skips when no session
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

  create_skill_templates "brainstorm" LOG

  local output
  output=$(run_hook '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}')
  local exit_code=$?

  # State should be unchanged (still {})
  local state
  state=$(read_state)
  local has_pending
  has_pending=$(echo "$state" | jq 'has("pendingTemplates")')

  if [ "$exit_code" -eq 0 ] && [ "$has_pending" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, no pendingTemplates" "exit=$exit_code, state=$state"
  fi

  teardown
}

# =============================================================================
# TEST: handles hyphenated skill name
# =============================================================================

test_handles_hyphenated_skill_name() {
  local test_name="hyphenated: edit-skill derives TEMPLATE_EDIT_SKILL_LOG.md"
  setup

  create_skill_templates "edit-skill" LOG

  run_hook '{"tool_name":"Skill","tool_input":{"skill":"edit-skill"}}' > /dev/null

  local state
  state=$(read_state)
  local pending_count
  pending_count=$(echo "$state" | jq '.pendingTemplates | length')
  local has_log
  has_log=$(echo "$state" | jq '[.pendingTemplates[] | select(endswith("TEMPLATE_EDIT_SKILL_LOG.md"))] | length')

  if [ "$pending_count" = "1" ] && [ "$has_log" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "1 pendingTemplates with TEMPLATE_EDIT_SKILL_LOG.md" "pending_count=$pending_count, state=$state"
  fi

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
test_dedup_on_reinvocation
test_skill_change_repreloads
test_skips_when_no_session
test_handles_hyphenated_skill_name

exit_with_results
