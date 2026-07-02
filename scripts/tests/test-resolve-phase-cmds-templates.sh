#!/bin/bash
# test-resolve-phase-cmds-templates.sh — Tests that resolve_phase_cmds outputs templates at ALL phases
#
# Tests:
#   3.1/1: Phase 0 includes templates (regression guard)
#   3.1/2: Phase 1 includes templates (currently FAILS — core bug)
#   3.1/3: Sub-phase 3.A includes templates
#   3.1/4: Templates deduplicated with CMD paths

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# --- Test helpers ---

setup() {
  TEST_TMPDIR=$(mktemp -d)
  setup_fake_home "$TEST_TMPDIR"

  # Copy lib.sh so resolve_phase_cmds is available
  cp "$SCRIPT_DIR/../lib.sh" "$HOME/.claude/scripts/lib.sh"
  source "$HOME/.claude/scripts/lib.sh"

  # Create minimal skill with templates
  local skill_dir="$HOME/.claude/skills/tpltest"
  local assets_dir="$skill_dir/assets"
  local cmd_dir="$HOME/.claude/engine/.directives/commands"
  mkdir -p "$assets_dir" "$cmd_dir"

  # CMD files for phases
  echo "# CMD_REPORT_INTENT" > "$cmd_dir/CMD_REPORT_INTENT.md"
  echo "# CMD_SELECT_MODE" > "$cmd_dir/CMD_SELECT_MODE.md"
  echo "# CMD_INTERROGATE" > "$cmd_dir/CMD_INTERROGATE.md"
  echo "# CMD_GENERATE_PLAN" > "$cmd_dir/CMD_GENERATE_PLAN.md"

  # Template files
  echo "# Log template" > "$assets_dir/TEMPLATE_TPLTEST_LOG.md"
  echo "# Debrief template" > "$assets_dir/TEMPLATE_TPLTEST.md"
  echo "# Plan template" > "$assets_dir/TEMPLATE_TPLTEST_PLAN.md"

  # SKILL.md with phases and templates
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
description: "Template test skill"
---

# tpltest

```json
{
  "taskType": "TPLTEST",
  "logTemplate": "assets/TEMPLATE_TPLTEST_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_TPLTEST.md",
  "planTemplate": "assets/TEMPLATE_TPLTEST_PLAN.md",
  "phases": [
    {
      "major": 0, "minor": 0, "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_SELECT_MODE"]
    },
    {
      "major": 1, "minor": 0, "name": "Strategy",
      "steps": ["§CMD_INTERROGATE", "§CMD_GENERATE_PLAN"]
    },
    {
      "major": 2, "minor": 0, "name": "Execution"
    },
    {
      "major": 2, "minor": 1, "name": "Testing Loop",
      "steps": ["§CMD_REPORT_INTENT"]
    }
  ]
}
```
SKILLEOF
}

teardown() {
  teardown_fake_home
  [ -n "${TEST_TMPDIR:-}" ] && rm -rf "$TEST_TMPDIR"
}

# --- Tests ---

test_phase0_includes_templates() {
  local test_name="3.1/1: Phase 0 includes templates (regression guard)"
  setup

  local output
  output=$(resolve_phase_cmds "tpltest" "0" 2>/dev/null || true)

  local has_log has_debrief has_plan
  has_log=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_LOG" || true)
  has_debrief=$(echo "$output" | grep -c "TEMPLATE_TPLTEST\.md" || true)
  has_plan=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_PLAN" || true)

  if [ "$has_log" -ge 1 ] && [ "$has_debrief" -ge 1 ] && [ "$has_plan" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "all 3 templates present" "log=$has_log debrief=$has_debrief plan=$has_plan"
  fi

  teardown
}

test_phase1_includes_templates() {
  local test_name="3.1/2: Phase 1 includes templates (RED — core bug)"
  setup

  local output
  output=$(resolve_phase_cmds "tpltest" "1" 2>/dev/null || true)

  local has_log has_debrief has_plan
  has_log=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_LOG" || true)
  has_debrief=$(echo "$output" | grep -c "TEMPLATE_TPLTEST\.md" || true)
  has_plan=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_PLAN" || true)

  # Also verify Phase 1 CMDs are present
  local has_interrogate has_gen_plan
  has_interrogate=$(echo "$output" | grep -c "CMD_INTERROGATE" || true)
  has_gen_plan=$(echo "$output" | grep -c "CMD_GENERATE_PLAN" || true)

  local all_ok=true
  [ "$has_log" -ge 1 ] || all_ok=false
  [ "$has_debrief" -ge 1 ] || all_ok=false
  [ "$has_plan" -ge 1 ] || all_ok=false
  [ "$has_interrogate" -ge 1 ] || all_ok=false
  [ "$has_gen_plan" -ge 1 ] || all_ok=false

  if [ "$all_ok" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "templates + Phase 1 CMDs" \
      "log=$has_log debrief=$has_debrief plan=$has_plan interrogate=$has_interrogate gen_plan=$has_gen_plan"
  fi

  teardown
}

test_subphase_includes_templates() {
  local test_name="3.1/3: Sub-phase 2.1 includes templates"
  setup

  local output
  output=$(resolve_phase_cmds "tpltest" "2.1" 2>/dev/null || true)

  local has_log has_debrief has_plan
  has_log=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_LOG" || true)
  has_debrief=$(echo "$output" | grep -c "TEMPLATE_TPLTEST\.md" || true)
  has_plan=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_PLAN" || true)

  # Also verify sub-phase CMD is present
  local has_report_intent
  has_report_intent=$(echo "$output" | grep -c "CMD_REPORT_INTENT" || true)

  local all_ok=true
  [ "$has_log" -ge 1 ] || all_ok=false
  [ "$has_debrief" -ge 1 ] || all_ok=false
  [ "$has_plan" -ge 1 ] || all_ok=false
  [ "$has_report_intent" -ge 1 ] || all_ok=false

  if [ "$all_ok" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "templates + sub-phase CMD" \
      "log=$has_log debrief=$has_debrief plan=$has_plan report_intent=$has_report_intent"
  fi

  teardown
}

test_templates_no_duplicates() {
  local test_name="3.1/4: Templates not duplicated in output"
  setup

  local output
  output=$(resolve_phase_cmds "tpltest" "0" 2>/dev/null || true)

  # Count occurrences of each template
  local log_count debrief_count plan_count
  log_count=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_LOG" || true)
  debrief_count=$(echo "$output" | grep -c "TEMPLATE_TPLTEST\.md" || true)
  plan_count=$(echo "$output" | grep -c "TEMPLATE_TPLTEST_PLAN" || true)

  if [ "$log_count" -eq 1 ] && [ "$debrief_count" -eq 1 ] && [ "$plan_count" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exactly 1 of each" "log=$log_count debrief=$debrief_count plan=$plan_count"
  fi

  teardown
}

# --- Run ---
echo "=== test-resolve-phase-cmds-templates.sh ==="
test_phase0_includes_templates
test_phase1_includes_templates
test_subphase_includes_templates
test_templates_no_duplicates
exit_with_results
