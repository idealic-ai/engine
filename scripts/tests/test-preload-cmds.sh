#!/bin/bash
# test-preload-cmds.sh — Tests for resolve_phase_cmds() unified CMD resolution
#
# Tests: Phase 0 extraction (matches extract_skill_preloads), Phase N extraction,
# suffix stripping, template inclusion, and edge cases.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

# --- Setup/Teardown ---

setup() {
  setup_test_env "test_cmds_session"

  # Symlink engine scripts
  mkdir -p "$FAKE_HOME/.claude/engine/scripts"
  ln -sf "$REAL_ENGINE_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/engine/scripts/lib.sh"

  # Create minimal directives
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  for f in COMMANDS.md INVARIANTS.md SIGILS.md; do
    echo "# $f" > "$FAKE_HOME/.claude/engine/.directives/$f"
  done

  # Create CMD files that the test skill references
  for cmd in REPORT_INTENT PARSE_PARAMETERS SELECT_MODE INGEST_CONTEXT_BEFORE_WORK \
             INTERROGATE ASK_ROUND LOG_INTERACTION GENERATE_PLAN WALK_THROUGH_RESULTS \
             SELECT_EXECUTION_PATH HANDOFF_TO_AGENT; do
    echo "# CMD_$cmd" > "$FAKE_HOME/.claude/engine/.directives/commands/CMD_${cmd}.md"
  done

  # Symlink
  ln -sf "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"

  # Create a test skill with SKILL.md
  TEST_SKILL_DIR="$FAKE_HOME/.claude/skills/test-skill"
  mkdir -p "$TEST_SKILL_DIR/assets"

  cat > "$TEST_SKILL_DIR/SKILL.md" <<'SKILLEOF'
---
name: test-skill
---

# Test Skill

```json
{
  "taskType": "TEST",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS"],
      "commands": ["§CMD_SELECT_MODE"],
      "proof": []},
    {"label": "1", "name": "Investigation",
      "steps": ["§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depthChosen"]},
    {"label": "2", "name": "Planning",
      "steps": ["§CMD_GENERATE_PLAN", "§CMD_WALK_THROUGH_RESULTS"],
      "commands": [],
      "proof": ["planWritten"]},
    {"label": "3.A", "name": "Build Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_LOG_INTERACTION"],
      "proof": []}
  ],
  "logTemplate": "assets/TEMPLATE_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_DEBRIEF.md",
  "planTemplate": "assets/TEMPLATE_PLAN.md"
}
```
SKILLEOF

  # Create template files
  echo "# Log Template" > "$TEST_SKILL_DIR/assets/TEMPLATE_LOG.md"
  echo "# Debrief Template" > "$TEST_SKILL_DIR/assets/TEMPLATE_DEBRIEF.md"
  echo "# Plan Template" > "$TEST_SKILL_DIR/assets/TEMPLATE_PLAN.md"

  # Re-source lib.sh
  unset _LIB_SH_LOADED
  source "$FAKE_HOME/.claude/scripts/lib.sh"
}

teardown() {
  teardown_fake_home
  rm -rf "${TMP_DIR:-}"
}

trap cleanup_test_env EXIT

# --- Tests ---

test_resolve_phase_0_includes_cmds_and_templates() {
  local output
  output=$(resolve_phase_cmds "test-skill" "0")

  # Should include Phase 0 CMDs
  assert_contains "CMD_REPORT_INTENT" "$output" "Phase 0 includes CMD_REPORT_INTENT"
  assert_contains "CMD_PARSE_PARAMETERS" "$output" "Phase 0 includes CMD_PARSE_PARAMETERS"
  assert_contains "CMD_SELECT_MODE" "$output" "Phase 0 includes CMD_SELECT_MODE from commands[]"

  # Should include templates (Phase 0 only)
  assert_contains "TEMPLATE_LOG" "$output" "Phase 0 includes log template"
  assert_contains "TEMPLATE_DEBRIEF" "$output" "Phase 0 includes debrief template"
  assert_contains "TEMPLATE_PLAN" "$output" "Phase 0 includes plan template"
}

test_resolve_phase_0_matches_extract_skill_preloads() {
  # resolve_phase_cmds(skill, "0") should produce the same files as extract_skill_preloads(skill)
  local new_output old_output
  new_output=$(resolve_phase_cmds "test-skill" "0" | sort)
  old_output=$(extract_skill_preloads "test-skill" | sort)

  assert_eq "$old_output" "$new_output" "resolve_phase_cmds matches extract_skill_preloads"
}

test_resolve_phase_1_no_templates() {
  local output
  output=$(resolve_phase_cmds "test-skill" "1")

  # Should include Phase 1 CMDs
  assert_contains "CMD_INTERROGATE" "$output" "Phase 1 includes CMD_INTERROGATE"
  assert_contains "CMD_ASK_ROUND" "$output" "Phase 1 includes CMD_ASK_ROUND"
  assert_contains "CMD_LOG_INTERACTION" "$output" "Phase 1 includes CMD_LOG_INTERACTION"

  # Should NOT include templates (Phase 0 only)
  assert_not_contains "TEMPLATE_" "$output" "Phase 1 excludes templates"
}

test_resolve_phase_2() {
  local output
  output=$(resolve_phase_cmds "test-skill" "2")

  assert_contains "CMD_GENERATE_PLAN" "$output" "Phase 2 includes CMD_GENERATE_PLAN"
  assert_contains "CMD_WALK_THROUGH_RESULTS" "$output" "Phase 2 includes CMD_WALK_THROUGH_RESULTS"
}

test_resolve_sub_phase() {
  # Sub-phase labels like "3.A" should work
  local output
  output=$(resolve_phase_cmds "test-skill" "3.A")

  assert_contains "CMD_REPORT_INTENT" "$output" "Phase 3.A includes CMD_REPORT_INTENT"
  assert_contains "CMD_LOG_INTERACTION" "$output" "Phase 3.A includes CMD_LOG_INTERACTION"
}

test_resolve_nonexistent_phase() {
  # Non-existent phase returns empty
  local output
  output=$(resolve_phase_cmds "test-skill" "99")
  assert_empty "$output" "non-existent phase returns empty"
}

test_resolve_nonexistent_skill() {
  # Non-existent skill returns empty
  local output
  output=$(resolve_phase_cmds "nonexistent-skill" "0")
  assert_empty "$output" "non-existent skill returns empty"
}

test_resolve_dedup_shared_cmds() {
  # CMD_REPORT_INTENT appears in Phase 0 steps and Phase 3.A steps
  # Each phase resolution should list it once
  local output
  output=$(resolve_phase_cmds "test-skill" "0")
  local count
  count=$(echo "$output" | grep -c "CMD_REPORT_INTENT" || true)
  assert_eq "1" "$count" "CMD_REPORT_INTENT appears once per phase"
}

test_resolve_suffix_stripping() {
  # Proof fields like "depthChosen" should not generate CMD files
  # Only §CMD_ prefixed entries should be resolved
  local output
  output=$(resolve_phase_cmds "test-skill" "1")
  # "depthChosen" is in proof, not prefixed with §CMD_ — should not appear
  assert_not_contains "depthChosen" "$output" "proof data fields not resolved as CMDs"
}

# --- Run ---
run_discovered_tests
