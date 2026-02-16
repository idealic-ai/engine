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

# Helper: run the hook with stdin JSON, capture stdout
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" 2>/dev/null
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
  echo '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
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
  echo '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
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
  echo '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
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
  echo '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
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
  echo '{"tool_name":"Skill","tool_input":{"skill":"brainstorm"}}' | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name"

  teardown
}

# =============================================================================
# BASH TRIGGER PATH TESTS — engine session activate/continue
# =============================================================================

# Helper: set up .state.json with a skill name for Bash trigger tests
setup_bash_trigger() {
  local skill_name="$1"
  jq -n --arg s "$skill_name" '{pid: 1, skill: $s, loading: false}' > "$SESSION_DIR/.state.json"
}

test_bash_activate_delivers_skill_md_and_templates() {
  local test_name="bash activate: delivers templates (not SKILL.md) via additionalContext"
  setup

  create_skill_with_templates "fake-impl" LOG DEBRIEF
  setup_bash_trigger "fake-impl"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine session activate sessions/test-session fake-impl <<'\''EOF'\''\n{}\nEOF"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  # Bash path: SKILL.md NOT delivered (arrives via command expansion), but templates are
  local has_skill_md has_log has_debrief
  has_skill_md=$(echo "$has_context" | grep -c "SKILL.md" || true)
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_FAKE_IMPL_LOG.md" || true)
  has_debrief=$(echo "$has_context" | grep -c "TEMPLATE_FAKE_IMPL.md" || true)

  if [ "$has_skill_md" -eq 0 ] && [ "$has_log" -ge 1 ] && [ "$has_debrief" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "no SKILL.md + LOG + DEBRIEF" "skill_md=$has_skill_md, log=$has_log, debrief=$has_debrief"
  fi

  teardown
}

test_bash_continue_delivers_skill_md_and_templates() {
  local test_name="bash continue: delivers templates (not SKILL.md) via additionalContext"
  setup

  create_skill_with_templates "fake-impl" LOG DEBRIEF PLAN
  setup_bash_trigger "fake-impl"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine session continue sessions/test-session"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  # Bash path: SKILL.md NOT delivered (arrives via dehydration requiredFiles), but templates are
  local has_skill_md has_log has_plan
  has_skill_md=$(echo "$has_context" | grep -c "SKILL.md" || true)
  has_log=$(echo "$has_context" | grep -c "TEMPLATE_FAKE_IMPL_LOG.md" || true)
  has_plan=$(echo "$has_context" | grep -c "TEMPLATE_FAKE_IMPL_PLAN.md" || true)

  if [ "$has_skill_md" -eq 0 ] && [ "$has_log" -ge 1 ] && [ "$has_plan" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "no SKILL.md + LOG + PLAN" "skill_md=$has_skill_md, log=$has_log, plan=$has_plan"
  fi

  teardown
}

test_bash_ignores_non_matching_commands() {
  local test_name="bash non-matching: ignores engine log, engine tag, etc."
  setup

  create_skill_with_templates "fake-impl" LOG
  setup_bash_trigger "fake-impl"

  local output1 output2 output3
  output1=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine log sessions/test/LOG.md"}}')
  output2=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine tag find #needs-review"}}')
  output3=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')

  if [ -z "$output1" ] && [ -z "$output2" ] && [ -z "$output3" ]; then
    pass "$test_name"
  else
    fail "$test_name" "(empty output for all 3)" "out1='$output1' out2='$output2' out3='$output3'"
  fi

  teardown
}

test_bash_dedup_skips_already_preloaded() {
  local test_name="bash dedup: second run skips already-preloaded files"
  setup

  create_skill_with_templates "fake-impl" LOG

  # First: Skill tool path preloads templates
  run_hook '{"tool_name":"Skill","tool_input":{"skill":"fake-impl"}}' > /dev/null

  # Set up .state.json with skill field (session.sh find returns this dir)
  # Preserve preloadedFiles from first run, add skill field
  local current_state
  current_state=$(cat "$SESSION_DIR/.state.json")
  echo "$current_state" | jq '.skill = "fake-impl"' > "$SESSION_DIR/.state.json"

  # Second: Bash trigger path — SKILL.md is new (not preloaded by Skill path), but templates should dedup
  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine session activate sessions/test fake-impl < /dev/null"}}')

  # Should still have output (SKILL.md is new for Bash path), but templates should be deduped in state
  local preloaded_count
  preloaded_count=$(jq '.preloadedFiles | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")

  # preloadedFiles should not have duplicates
  local unique_count
  unique_count=$(jq '.preloadedFiles | unique | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")

  if [ "$preloaded_count" = "$unique_count" ]; then
    pass "$test_name"
  else
    fail "$test_name" "no duplicates (count=$unique_count)" "total=$preloaded_count unique=$unique_count"
  fi

  teardown
}

test_bash_exits_0_no_skill_in_state() {
  local test_name="bash resilience: exits 0 when .state.json has no skill field"
  setup

  # .state.json without skill field
  echo '{"pid": 1, "loading": false}' > "$SESSION_DIR/.state.json"

  local exit_code
  echo '{"tool_name":"Bash","tool_input":{"command":"engine session activate sessions/x test < /dev/null"}}' \
    | bash "$HOME/.claude/hooks/post-tool-use-templates.sh" > /dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "$test_name"

  teardown
}

test_bash_skill_md_content_appears() {
  local test_name="bash activate: SKILL.md tracked in preloadedFiles but not delivered"
  setup

  create_skill_with_templates "fake-impl" LOG
  setup_bash_trigger "fake-impl"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine session activate sessions/x fake-impl < /dev/null"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  # SKILL.md should NOT be in additionalContext (not delivered on Bash path)
  local has_content
  has_content=$(echo "$has_context" | grep -c "Test skill fake-impl" || true)

  # But SKILL.md SHOULD be tracked in preloadedFiles (marked as loaded)
  local state_file="$SESSION_DIR/.state.json"
  local skill_tracked
  skill_tracked=$(jq '[.preloadedFiles // [] | .[] | select(contains("SKILL.md"))] | length' "$state_file" 2>/dev/null || echo "0")

  if [ "$has_content" -eq 0 ] && [ "$skill_tracked" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "not in context + tracked in state" "in_context=$has_content, tracked=$skill_tracked"
  fi

  teardown
}

# =============================================================================
# BASH PATH: IMMEDIATE DELIVERY OF ALL DEPS (Phase 0 CMDs + prose refs + templates)
# These tests verify that on Bash(engine session activate/continue), all SKILL.md
# dependencies are delivered immediately via additionalContext — NOT queued to
# pendingPreloads for later delivery by overflow-v2.
# =============================================================================

# Helper: create a SKILL.md with Phase 0 CMDs, prose refs, and templates
create_skill_with_deps() {
  local skill_name="$1"
  local skill_dir="$HOME/.claude/skills/$skill_name"
  local assets_dir="$skill_dir/assets"
  local cmd_dir="$HOME/.claude/engine/.directives/commands"
  local fmt_dir="$HOME/.claude/engine/.directives/formats"
  mkdir -p "$assets_dir" "$cmd_dir" "$fmt_dir"

  # Create CMD files that Phase 0 references
  echo "# CMD_REPORT_INTENT definition" > "$cmd_dir/CMD_REPORT_INTENT.md"
  echo "# CMD_SELECT_MODE definition" > "$cmd_dir/CMD_SELECT_MODE.md"
  # Create CMD file referenced in prose (orchestrator)
  echo "# CMD_EXECUTE_SKILL_PHASES definition" > "$cmd_dir/CMD_EXECUTE_SKILL_PHASES.md"
  # Create FMT file referenced in prose
  echo "# FMT_CONTEXT_BLOCK definition" > "$fmt_dir/FMT_CONTEXT_BLOCK.md"

  # Create template
  echo "# Log template for $skill_name" > "$assets_dir/TEMPLATE_DEPTEST_LOG.md"

  # SKILL.md with Phase 0 steps + prose refs to orchestrator CMD and FMT
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
description: "Test skill with deps"
---

# deptest

Invoke §CMD_EXECUTE_SKILL_PHASES to run all phases.

Use §FMT_CONTEXT_BLOCK for context blocks.

```json
{
  "taskType": "DEPTEST",
  "logTemplate": "assets/TEMPLATE_DEPTEST_LOG.md",
  "phases": [
    {
      "major": 0, "minor": 0, "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_SELECT_MODE"]
    },
    {
      "major": 1, "minor": 0, "name": "Work"
    }
  ]
}
```
SKILLEOF
}

test_bash_activate_delivers_all_deps_immediately() {
  local test_name="bash activate: delivers Phase 0 CMDs + prose refs + templates immediately"
  setup

  create_skill_with_deps "deptest"
  setup_bash_trigger "deptest"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine session activate sessions/test-session deptest <<'\''EOF'\''\n{}\nEOF"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  # All deps should be in additionalContext (immediate delivery)
  local has_report_intent has_select_mode has_execute_phases has_fmt_block has_template
  has_report_intent=$(echo "$has_context" | grep -c "CMD_REPORT_INTENT" || true)
  has_select_mode=$(echo "$has_context" | grep -c "CMD_SELECT_MODE" || true)
  has_execute_phases=$(echo "$has_context" | grep -c "CMD_EXECUTE_SKILL_PHASES" || true)
  has_fmt_block=$(echo "$has_context" | grep -c "FMT_CONTEXT_BLOCK" || true)
  has_template=$(echo "$has_context" | grep -c "TEMPLATE_DEPTEST_LOG" || true)

  # SKILL.md itself should NOT be delivered (arrives via skill expansion)
  local has_skill_md
  has_skill_md=$(echo "$has_context" | grep -c "Test skill with deps" || true)

  local all_ok=true
  [ "$has_report_intent" -ge 1 ] || { all_ok=false; }
  [ "$has_select_mode" -ge 1 ] || { all_ok=false; }
  [ "$has_execute_phases" -ge 1 ] || { all_ok=false; }
  [ "$has_fmt_block" -ge 1 ] || { all_ok=false; }
  [ "$has_template" -ge 1 ] || { all_ok=false; }
  [ "$has_skill_md" -eq 0 ] || { all_ok=false; }

  if [ "$all_ok" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "all deps immediate, no SKILL.md" \
      "report_intent=$has_report_intent select_mode=$has_select_mode execute_phases=$has_execute_phases fmt=$has_fmt_block template=$has_template skill_md=$has_skill_md"
  fi

  # Also verify nothing left in pendingPreloads
  local pending_count
  pending_count=$(jq '.pendingPreloads // [] | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")
  assert_eq "0" "$pending_count" "$test_name — pendingPreloads empty"

  teardown
}

test_bash_continue_delivers_all_deps_immediately() {
  local test_name="bash continue: delivers Phase 0 CMDs + prose refs + templates immediately"
  setup

  create_skill_with_deps "deptest"
  setup_bash_trigger "deptest"

  local output
  output=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"engine session continue sessions/test-session"}}')

  local has_context
  has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)

  # Phase 0 CMDs + prose refs + templates all immediate
  local has_report_intent has_execute_phases has_template
  has_report_intent=$(echo "$has_context" | grep -c "CMD_REPORT_INTENT" || true)
  has_execute_phases=$(echo "$has_context" | grep -c "CMD_EXECUTE_SKILL_PHASES" || true)
  has_template=$(echo "$has_context" | grep -c "TEMPLATE_DEPTEST_LOG" || true)

  local all_ok=true
  [ "$has_report_intent" -ge 1 ] || { all_ok=false; }
  [ "$has_execute_phases" -ge 1 ] || { all_ok=false; }
  [ "$has_template" -ge 1 ] || { all_ok=false; }

  if [ "$all_ok" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "all deps immediate" \
      "report_intent=$has_report_intent execute_phases=$has_execute_phases template=$has_template"
  fi

  # pendingPreloads should be empty
  local pending_count
  pending_count=$(jq '.pendingPreloads // [] | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")
  assert_eq "0" "$pending_count" "$test_name — pendingPreloads empty"

  teardown
}


# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-post-tool-use-templates.sh ==="

# Core functionality (Skill tool path)
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

# Bash trigger path (engine session activate/continue)
test_bash_activate_delivers_skill_md_and_templates
test_bash_continue_delivers_skill_md_and_templates
test_bash_ignores_non_matching_commands
test_bash_dedup_skips_already_preloaded
test_bash_exits_0_no_skill_in_state
test_bash_skill_md_content_appears

# Bash path: immediate delivery of all deps
test_bash_activate_delivers_all_deps_immediately
test_bash_continue_delivers_all_deps_immediately

exit_with_results
