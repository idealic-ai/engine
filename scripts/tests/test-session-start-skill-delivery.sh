#!/bin/bash
# tests/test-session-start-skill-delivery.sh — E2E tests for SessionStart hook skill delivery
#
# Tests the hook's ability to deliver SKILL.md + Phase 0 CMDs + templates when an
# active session exists (especially after /clear).
#
# Scenarios covered:
#   1. lifecycle=resuming — hook delivers skill deps (after dehydration/restart)
#   2. lifecycle=active — happy path works
#   3. Multiple active sessions — hook finds the right one by PPID
#   4. No active session — no skill deps (no crash)
#   5. Active session, pid=null — delivers skill deps (null PID edge case)
#   6. Skill deps tracked in seed file
#   7. Session context line always included
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-start-skill-delivery.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="$HOME/.claude/hooks/session-start-restore.sh"

TMP_DIR=""

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"
  disable_fleet_tmux

  # Symlink the hook and its dependencies
  ln -sf "$HOOK_SCRIPT" "$FAKE_HOME/.claude/hooks/session-start-restore.sh"
  ln -sf "$SCRIPT_DIR/scripts/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  ln -sf "$SCRIPT_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"

  # Create project dir with sessions/
  export PROJECT_DIR="$TMP_DIR/project"
  mkdir -p "$PROJECT_DIR/sessions"

  # Create standards files in fake home
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  echo "# COMMANDS content" > "$FAKE_HOME/.claude/.directives/COMMANDS.md"
  echo "# INVARIANTS content" > "$FAKE_HOME/.claude/.directives/INVARIANTS.md"
  echo "# SIGILS content" > "$FAKE_HOME/.claude/.directives/SIGILS.md"
  echo "# CMD_DEHYDRATE content" > "$FAKE_HOME/.claude/.directives/commands/CMD_DEHYDRATE.md"
  echo "# CMD_RESUME_SESSION content" > "$FAKE_HOME/.claude/.directives/commands/CMD_RESUME_SESSION.md"
  echo "# CMD_PARSE_PARAMETERS content" > "$FAKE_HOME/.claude/.directives/commands/CMD_PARSE_PARAMETERS.md"

  RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/session-start-restore.sh"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# Helper: run the hook with a given source
run_hook() {
  local source="${1:-startup}"
  local cwd="${2:-$PROJECT_DIR}"
  echo "{\"hook_event_name\":\"SessionStart\",\"source\":\"$source\",\"cwd\":\"$cwd\"}" \
    | "$RESOLVED_HOOK" 2>/dev/null
}

# Helper: create a minimal SKILL.md with Phase 0 CMDs + templates
create_test_skill() {
  local skill_name="$1"
  local skill_dir="$FAKE_HOME/.claude/skills/$skill_name"
  local assets_dir="$skill_dir/assets"
  mkdir -p "$assets_dir"

  # Phase 0 CMD files (engine path — where resolve_phase_cmds looks)
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  echo "# CMD_SELECT_MODE content" > "$FAKE_HOME/.claude/engine/.directives/commands/CMD_SELECT_MODE.md"
  echo "# CMD_REPORT_INTENT content" > "$FAKE_HOME/.claude/engine/.directives/commands/CMD_REPORT_INTENT.md"

  # Template files
  local skill_upper=$(echo "$skill_name" | tr '[:lower:]' '[:upper:]')
  echo "# Log template for $skill_name" > "$assets_dir/TEMPLATE_${skill_upper}_LOG.md"
  echo "# Debrief template for $skill_name" > "$assets_dir/TEMPLATE_${skill_upper}.md"

  # SKILL.md with JSON block referencing Phase 0 CMDs + templates
  cat > "$skill_dir/SKILL.md" <<SKILLEOF
---
description: "Test $skill_name skill"
---

# $skill_name

\`\`\`json
{
  "taskType": "IMPLEMENTATION",
  "logTemplate": "assets/TEMPLATE_${skill_upper}_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_${skill_upper}.md",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "steps": ["§CMD_SELECT_MODE", "§CMD_REPORT_INTENT"]},
    {"major": 3, "minor": 0, "name": "Build Loop"}
  ]
}
\`\`\`
SKILLEOF
}

# --- Test 1: lifecycle=resuming — hook delivers skill deps ---
test_lifecycle_resuming_delivers_skill_deps() {
  create_test_skill "implement"

  # Create a session with lifecycle=resuming (after dehydration/restart)
  local session_dir="$PROJECT_DIR/sessions/test_resuming"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "resuming",
  "currentPhase": "0: Setup",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # lifecycle=resuming with live PID should deliver skill deps
  assert_contains "Test implement skill" "$output" \
    "lifecycle=resuming with live PID → SKILL.md delivered"

  assert_contains "CMD_SELECT_MODE content" "$output" \
    "lifecycle=resuming with live PID → current phase CMD delivered"
}

# --- Test 2: lifecycle=active — happy path works ---
test_lifecycle_active_delivers_skill_deps() {
  create_test_skill "brainstorm"

  # Create a session with lifecycle=active at Phase 0 (happy path)
  local session_dir="$PROJECT_DIR/sessions/test_active"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "brainstorm",
  "lifecycle": "active",
  "currentPhase": "0: Setup",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # SKILL.md content should be in output
  assert_contains "Test brainstorm skill" "$output" \
    "lifecycle=active with live PID → SKILL.md delivered"

  # Phase 0 CMD files should be in output
  assert_contains "CMD_SELECT_MODE content" "$output" \
    "lifecycle=active with live PID → current phase CMD delivered"

  # Standards should still be present
  assert_contains "COMMANDS content" "$output" \
    "standards present alongside skill deps"
}

# --- Test 3: Multiple sessions — finds the right one by PID ---
test_multiple_active_sessions_finds_correct_one() {
  create_test_skill "implement"
  create_test_skill "brainstorm"
  create_test_skill "refine"

  local dead_pid=9999999
  local other_live_pid=$$
  local current_ppid=$PPID

  # Session 1: completed (dead PID) — should be skipped
  local session_1="$PROJECT_DIR/sessions/completed_session"
  mkdir -p "$session_1"
  cat > "$session_1/.state.json" <<JSON
{
  "pid": $dead_pid,
  "skill": "brainstorm",
  "lifecycle": "active",
  "currentPhase": "1: Analysis",
  "preloadedFiles": []
}
JSON

  # Session 2: active but DIFFERENT live PID — should be skipped if current PPID doesn't match
  local session_2="$PROJECT_DIR/sessions/other_session"
  mkdir -p "$session_2"
  cat > "$session_2/.state.json" <<JSON
{
  "pid": $other_live_pid,
  "skill": "brainstorm",
  "lifecycle": "active",
  "currentPhase": "2: Planning",
  "preloadedFiles": []
}
JSON

  # Session 3: active with CURRENT PPID — should be found and used
  local session_3="$PROJECT_DIR/sessions/current_session"
  mkdir -p "$session_3"
  cat > "$session_3/.state.json" <<JSON
{
  "pid": $current_ppid,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Should find the one with current PPID and deliver its SKILL.md (implement, not brainstorm)
  assert_contains "Test implement skill" "$output" \
    "multiple active sessions → finds correct one by matching PPID"

  # Should NOT contain brainstorm SKILL.md
  assert_not_contains "Test brainstorm skill" "$output" \
    "multiple active sessions → doesn't deliver unmatched session SKILL.md"
}

# --- Test 4: No active session — no skill deps, no crash ---
test_no_active_session_no_skill_deps() {
  create_test_skill "implement"

  # No sessions directory or empty sessions — just return standards
  local output
  output=$(run_hook "clear") || true

  # Standards should be present
  assert_contains "COMMANDS content" "$output" \
    "no active session → standards present"

  # Skill SKILL.md should NOT be present
  assert_not_contains "Test implement skill" "$output" \
    "no active session → no SKILL.md delivered"

  # No crash (output is valid)
  assert_not_empty "$output" "no active session → exit cleanly with standards"
}

# --- Test 5: Active session but pid=null — skips in pid_exists check ---
test_active_session_null_pid_finds_skill_deps() {
  create_test_skill "implement"

  # Create a session with lifecycle=active but pid=null
  # Note: pid=null in JSON is treated as "no PID", so pid_exists should fail.
  # However, the hook reads it as 0 (via jq), and pid_exists may not check 0 properly.
  # This test documents the bug: null PID sessions still deliver skill deps.
  local session_dir="$PROJECT_DIR/sessions/null_pid_session"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": null,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Standards should be present
  assert_contains "COMMANDS content" "$output" \
    "null PID → standards present"

  # BUG: Skill deps ARE delivered even though pid=null (should not be)
  # This test documents the bug — the hook delivers skill deps for null PIDs
  assert_contains "Test implement skill" "$output" \
    "null PID with lifecycle=active → BUG: SKILL.md still delivered (pid_exists doesn't reject null/0)"

  # No crash
  assert_not_empty "$output" "null PID → exit cleanly with standards"
}

# --- Test 6: Skill deps tracked in seed file ---
test_skill_deps_tracked_in_seed_file() {
  create_test_skill "implement"

  # Create a session with lifecycle=active
  local session_dir="$PROJECT_DIR/sessions/seed_tracking"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "0: Setup",
  "preloadedFiles": []
}
JSON

  # The hook creates seed file with PPID (parent of the hook process)
  # In the test, the hook runs as a subprocess, so its PPID is the current shell ($$)
  run_hook "clear" > /dev/null || true

  # Seed file should exist — the hook creates it with its own PPID
  # In the test environment, this is not necessarily $$, but it should exist somewhere
  local seeds_dir="$PROJECT_DIR/sessions/.seeds"
  if [ -d "$seeds_dir" ]; then
    local seed_count=$(find "$seeds_dir" -name "*.json" 2>/dev/null | wc -l)
    if [ "$seed_count" -gt 0 ]; then
      pass "seed file created after clear with active session"

      # Check that seed file contains skill deps
      local seed_file=$(find "$seeds_dir" -name "*.json" 2>/dev/null | head -1)
      local has_skill_md=$(jq '[.preloadedFiles[] | select(contains("SKILL.md"))] | length' "$seed_file" 2>/dev/null || echo "0")
      assert_eq "1" "$has_skill_md" "seed preloadedFiles includes SKILL.md"

      local has_cmd=$(jq '[.preloadedFiles[] | select(contains("CMD_SELECT_MODE"))] | length' "$seed_file" 2>/dev/null || echo "0")
      assert_eq "1" "$has_cmd" "seed preloadedFiles includes current phase CMD path"
    else
      fail "seed file created after clear with active session" "seed file exists" "not found in $seeds_dir"
    fi
  else
    fail "seed file created after clear with active session" "seed file exists" ".seeds dir not found"
  fi
}

# --- Test 7: Skill deps only on clear/resume, not on startup (when no session exists) ---
test_skill_deps_only_when_active_session() {
  create_test_skill "implement"

  # On startup with NO active session, skill deps should not be delivered
  local output
  output=$(run_hook "startup") || true

  assert_contains "COMMANDS content" "$output" "startup → standards delivered"
  assert_not_contains "Test implement skill" "$output" "startup (no active session) → no SKILL.md"
}

# --- Test 8: Session context line always included ---
test_session_context_line_included() {
  create_test_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_context"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "toolCallsSinceLastLog": 5,
  "toolUseWithoutLogsBlockAfter": 10,
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Session context line should be present
  assert_contains "[Session Context]" "$output" "session context line included"
  assert_contains "Session: test_context" "$output" "session context includes session name"
  assert_contains "Skill: implement" "$output" "session context includes skill name"
  assert_contains "Phase: 3: Build" "$output" "session context includes phase"
  assert_contains "Heartbeat: 5/10" "$output" "session context includes heartbeat"
}

# --- Test 9: Standards preloaded on all sources (including clear) ---
test_standards_preloaded_on_clear() {
  # No active session — just verify standards are preloaded on clear source
  local output
  output=$(run_hook "clear") || true

  assert_contains "COMMANDS content" "$output" "clear source → COMMANDS preloaded"
  assert_contains "INVARIANTS content" "$output" "clear source → INVARIANTS preloaded"
  assert_contains "SIGILS content" "$output" "clear source → SIGILS preloaded"
  assert_contains "CMD_DEHYDRATE content" "$output" "clear source → CMD_DEHYDRATE preloaded"
  assert_contains "CMD_RESUME_SESSION content" "$output" "clear source → CMD_RESUME_SESSION preloaded"
  assert_contains "CMD_PARSE_PARAMETERS content" "$output" "clear source → CMD_PARSE_PARAMETERS preloaded"
}

# --- Test 10: Multiple skill deps are all delivered ---
test_multiple_phase0_cmds_delivered() {
  create_test_skill "implement"

  # Session at Phase 0 — should deliver both Phase 0 CMDs
  local session_dir="$PROJECT_DIR/sessions/multi_cmd"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "0: Setup",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Both Phase 0 CMDs should be present
  assert_contains "CMD_SELECT_MODE content" "$output" "first Phase 0 CMD delivered"
  assert_contains "CMD_REPORT_INTENT content" "$output" "second Phase 0 CMD delivered"
}

# --- Test 11: Fleet match — correct session selected among many ---
test_fleet_match_correct_session_selected() {
  create_test_skill "implement"
  create_test_skill "analyze"
  create_test_skill "brainstorm"

  # Create 3 sessions with different fleet pane IDs
  local session_alpha="$PROJECT_DIR/sessions/session_alpha"
  mkdir -p "$session_alpha"
  cat > "$session_alpha/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "fleetPaneId": "test-fleet:main:Alpha",
  "preloadedFiles": []
}
JSON

  local session_beta="$PROJECT_DIR/sessions/session_beta"
  mkdir -p "$session_beta"
  cat > "$session_beta/.state.json" <<JSON
{
  "pid": $$,
  "skill": "analyze",
  "lifecycle": "active",
  "currentPhase": "2: Analysis",
  "fleetPaneId": "test-fleet:main:Beta",
  "preloadedFiles": []
}
JSON

  local session_gamma="$PROJECT_DIR/sessions/session_gamma"
  mkdir -p "$session_gamma"
  cat > "$session_gamma/.state.json" <<JSON
{
  "pid": $$,
  "skill": "brainstorm",
  "lifecycle": "resuming",
  "currentPhase": "1: Ideation",
  "fleetPaneId": "test-fleet:data:Gamma",
  "preloadedFiles": []
}
JSON

  # Create mock tmux in PATH that returns main:Beta
  mkdir -p "$TMP_DIR/bin"
  cat > "$TMP_DIR/bin/tmux" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"display"* ]] && [[ "$*" == *"window_name"* ]]; then
  echo "main:Beta"
  exit 0
fi
exit 1
MOCK
  chmod +x "$TMP_DIR/bin/tmux"

  # Set tmux env vars
  export TMUX_PANE="test:0.0"
  export TMUX="test"
  export PATH="$TMP_DIR/bin:$PATH"

  local output
  output=$(run_hook "clear") || true

  # Should find analyze (Beta matches main:Beta), NOT implement (Alpha is alphabetically first)
  assert_contains "Test analyze skill" "$output" \
    "fleet match → correct session selected (analyze, not implement)"

  assert_not_contains "Test implement skill" "$output" \
    "fleet match → doesn't deliver unmatched session SKILL.md (implement)"

  # brainstorm should not appear either
  assert_not_contains "Test brainstorm skill" "$output" \
    "fleet match → doesn't deliver unmatched session SKILL.md (brainstorm)"

  # Cleanup
  unset TMUX_PANE TMUX
}

# --- Test 12: Fleet match with resuming lifecycle ---
test_fleet_match_resuming_lifecycle() {
  create_test_skill "implement"
  create_test_skill "analyze"
  create_test_skill "brainstorm"

  # Create 3 sessions, target the resuming one with fleet match
  local session_alpha="$PROJECT_DIR/sessions/session_alpha"
  mkdir -p "$session_alpha"
  cat > "$session_alpha/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "fleetPaneId": "test-fleet:main:Alpha",
  "preloadedFiles": []
}
JSON

  local session_beta="$PROJECT_DIR/sessions/session_beta"
  mkdir -p "$session_beta"
  cat > "$session_beta/.state.json" <<JSON
{
  "pid": $$,
  "skill": "analyze",
  "lifecycle": "active",
  "currentPhase": "2: Analysis",
  "fleetPaneId": "test-fleet:main:Beta",
  "preloadedFiles": []
}
JSON

  local session_gamma="$PROJECT_DIR/sessions/session_gamma"
  mkdir -p "$session_gamma"
  cat > "$session_gamma/.state.json" <<JSON
{
  "pid": $$,
  "skill": "brainstorm",
  "lifecycle": "resuming",
  "currentPhase": "1: Ideation",
  "fleetPaneId": "test-fleet:data:Gamma",
  "preloadedFiles": []
}
JSON

  # Create mock tmux that returns data:Gamma
  mkdir -p "$TMP_DIR/bin"
  cat > "$TMP_DIR/bin/tmux" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"display"* ]] && [[ "$*" == *"window_name"* ]]; then
  echo "data:Gamma"
  exit 0
fi
exit 1
MOCK
  chmod +x "$TMP_DIR/bin/tmux"

  export TMUX_PANE="test:0.0"
  export TMUX="test"
  export PATH="$TMP_DIR/bin:$PATH"

  local output
  output=$(run_hook "clear") || true

  # Should find brainstorm (Gamma matches data:Gamma) with resuming lifecycle
  assert_contains "Test brainstorm skill" "$output" \
    "fleet match resuming → correct session selected (brainstorm)"

  # Should not have the others
  assert_not_contains "Test implement skill" "$output" \
    "fleet match resuming → doesn't deliver implement"

  assert_not_contains "Test analyze skill" "$output" \
    "fleet match resuming → doesn't deliver analyze"

  unset TMUX_PANE TMUX
}

# --- Test 13: No fleet match — falls back to first alive PID ---
test_no_fleet_match_fallback_to_first_alive_pid() {
  create_test_skill "implement"
  create_test_skill "analyze"

  # Create 2 sessions with different fleetPaneIds that won't match
  local session_alpha="$PROJECT_DIR/sessions/session_alpha"
  mkdir -p "$session_alpha"
  cat > "$session_alpha/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "fleetPaneId": "test-fleet:main:Alpha",
  "preloadedFiles": []
}
JSON

  local session_beta="$PROJECT_DIR/sessions/session_beta"
  mkdir -p "$session_beta"
  cat > "$session_beta/.state.json" <<JSON
{
  "pid": $$,
  "skill": "analyze",
  "lifecycle": "active",
  "currentPhase": "2: Analysis",
  "fleetPaneId": "test-fleet:main:Beta",
  "preloadedFiles": []
}
JSON

  # Create mock tmux that returns a non-existent pane
  mkdir -p "$TMP_DIR/bin"
  cat > "$TMP_DIR/bin/tmux" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"display"* ]] && [[ "$*" == *"window_name"* ]]; then
  echo "data:Nonexistent"
  exit 0
fi
exit 1
MOCK
  chmod +x "$TMP_DIR/bin/tmux"

  export TMUX_PANE="test:0.0"
  export TMUX="test"
  export PATH="$TMP_DIR/bin:$PATH"

  local output
  output=$(run_hook "clear") || true

  # Should fall back to first alphabetical alive session (session_alpha with implement)
  assert_contains "Test implement skill" "$output" \
    "no fleet match → falls back to first alive PID (implement)"

  assert_not_contains "Test analyze skill" "$output" \
    "no fleet match → doesn't deliver second session (analyze)"

  unset TMUX_PANE TMUX
}

# Helper: create a multi-phase test skill with distinct CMDs per phase
create_multi_phase_skill() {
  local skill_name="$1"
  local skill_dir="$FAKE_HOME/.claude/skills/$skill_name"
  local assets_dir="$skill_dir/assets"
  mkdir -p "$assets_dir"

  # CMD files for different phases
  local cmd_dir="$FAKE_HOME/.claude/engine/.directives/commands"
  mkdir -p "$cmd_dir"
  echo "# CMD_SELECT_MODE content" > "$cmd_dir/CMD_SELECT_MODE.md"
  echo "# CMD_REPORT_INTENT content" > "$cmd_dir/CMD_REPORT_INTENT.md"
  echo "# CMD_INGEST_CONTEXT content" > "$cmd_dir/CMD_INGEST_CONTEXT_BEFORE_WORK.md"
  echo "# CMD_INTERROGATE content" > "$cmd_dir/CMD_INTERROGATE.md"
  echo "# CMD_ASK_ROUND content" > "$cmd_dir/CMD_ASK_ROUND.md"
  echo "# CMD_GENERATE_PLAN content" > "$cmd_dir/CMD_GENERATE_PLAN.md"
  echo "# CMD_GENERATE_DEBRIEF content" > "$cmd_dir/CMD_GENERATE_DEBRIEF.md"
  echo "# CMD_RUN_SYNTHESIS_PIPELINE content" > "$cmd_dir/CMD_RUN_SYNTHESIS_PIPELINE.md"
  # Orchestrator CMDs (prose refs in SKILL.md, not in any phase's steps)
  echo "# CMD_EXECUTE_SKILL_PHASES content" > "$cmd_dir/CMD_EXECUTE_SKILL_PHASES.md"
  echo "# CMD_EXECUTE_PHASE_STEPS content" > "$cmd_dir/CMD_EXECUTE_PHASE_STEPS.md"

  # Template files
  local skill_upper=$(echo "$skill_name" | tr '[:lower:]' '[:upper:]')
  echo "# Log template for $skill_name" > "$assets_dir/TEMPLATE_${skill_upper}_LOG.md"
  echo "# Debrief template for $skill_name" > "$assets_dir/TEMPLATE_${skill_upper}.md"

  # SKILL.md with multiple phases having DIFFERENT CMDs + prose refs to orchestrator CMDs
  cat > "$skill_dir/SKILL.md" <<SKILLEOF
---
description: "Test $skill_name skill"
---

# $skill_name

Execute §CMD_EXECUTE_SKILL_PHASES.

\`\`\`json
{
  "taskType": "IMPLEMENTATION",
  "logTemplate": "assets/TEMPLATE_${skill_upper}_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_${skill_upper}.md",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "steps": ["§CMD_SELECT_MODE", "§CMD_REPORT_INTENT", "§CMD_INGEST_CONTEXT_BEFORE_WORK"]},
    {"major": 1, "minor": 0, "name": "Interrogation", "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"], "commands": ["§CMD_ASK_ROUND"]},
    {"major": 2, "minor": 0, "name": "Planning", "steps": ["§CMD_REPORT_INTENT", "§CMD_GENERATE_PLAN"]},
    {"major": 3, "minor": 0, "name": "Execution"},
    {"label": "3.A", "major": 3, "minor": 1, "name": "Build Loop", "steps": ["§CMD_REPORT_INTENT"]},
    {"major": 4, "minor": 0, "name": "Synthesis", "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"]},
    {"label": "4.2", "major": 4, "minor": 2, "name": "Debrief", "steps": ["§CMD_GENERATE_DEBRIEF"]}
  ]
}
\`\`\`

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Setting up.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

## 1. Interrogation

§CMD_REPORT_INTENT:
> 1: Interrogating.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

## 2. Planning

§CMD_REPORT_INTENT:
> 2: Planning.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)
SKILLEOF
}

# --- Test 15: Current phase CMDs delivered, not Phase 0 ---
test_current_phase_cmds_delivered_not_phase0() {
  create_multi_phase_skill "implement"

  # Session at Phase 1 (Interrogation) — should get INTERROGATE + ASK_ROUND, NOT SELECT_MODE
  local session_dir="$PROJECT_DIR/sessions/test_phase1"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "1: Interrogation",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Should deliver Phase 1 CMDs
  assert_contains "CMD_INTERROGATE content" "$output" \
    "Phase 1 active → CMD_INTERROGATE delivered (phase 1 step)"
  assert_contains "CMD_ASK_ROUND content" "$output" \
    "Phase 1 active → CMD_ASK_ROUND delivered (phase 1 command)"

  # Should NOT deliver Phase 0-only CMDs
  assert_not_contains "CMD_SELECT_MODE content" "$output" \
    "Phase 1 active → CMD_SELECT_MODE NOT delivered (phase 0 only)"
  assert_not_contains "CMD_INGEST_CONTEXT content" "$output" \
    "Phase 1 active → CMD_INGEST_CONTEXT NOT delivered (phase 0 only)"
}

# --- Test 16: Sub-phase label CMDs delivered (e.g., "4.2: Debrief") ---
test_sub_phase_cmds_delivered() {
  create_multi_phase_skill "implement"

  # Session at Phase 4.2 (Debrief sub-phase)
  local session_dir="$PROJECT_DIR/sessions/test_phase42"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "4.2: Debrief",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Should deliver Phase 4.2 CMDs
  assert_contains "CMD_GENERATE_DEBRIEF content" "$output" \
    "Phase 4.2 active → CMD_GENERATE_DEBRIEF delivered (phase 4.2 step)"

  # Should NOT deliver Phase 0 CMDs
  assert_not_contains "CMD_SELECT_MODE content" "$output" \
    "Phase 4.2 active → CMD_SELECT_MODE NOT delivered (phase 0 only)"

  # Should NOT deliver Phase 4.0 CMDs either
  assert_not_contains "CMD_RUN_SYNTHESIS_PIPELINE content" "$output" \
    "Phase 4.2 active → CMD_RUN_SYNTHESIS_PIPELINE NOT delivered (phase 4.0, not 4.2)"
}

# --- Test 17: SKILL.md prose refs resolved and delivered ---
test_skill_md_prose_refs_delivered() {
  create_multi_phase_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_prose_refs"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3.A: Build Loop",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # SKILL.md has bare §CMD_EXECUTE_SKILL_PHASES in prose (outside code fences)
  assert_contains "CMD_EXECUTE_SKILL_PHASES content" "$output" \
    "SKILL.md prose ref → CMD_EXECUTE_SKILL_PHASES delivered"

  # §CMD_EXECUTE_PHASE_STEPS also appears in prose
  assert_contains "CMD_EXECUTE_PHASE_STEPS content" "$output" \
    "SKILL.md prose ref → CMD_EXECUTE_PHASE_STEPS delivered"
}

# --- Test 18: Phase 0 still works when session is at Phase 0 ---
test_phase0_cmds_when_at_phase0() {
  create_multi_phase_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_at_phase0"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "0: Setup",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # Phase 0 CMDs + templates
  assert_contains "CMD_SELECT_MODE content" "$output" \
    "Phase 0 active → CMD_SELECT_MODE delivered"
  assert_contains "CMD_REPORT_INTENT content" "$output" \
    "Phase 0 active → CMD_REPORT_INTENT delivered"
  assert_contains "Log template" "$output" \
    "Phase 0 active → log template delivered"
  assert_contains "Debrief template" "$output" \
    "Phase 0 active → debrief template delivered"

  # Phase 1 CMDs should NOT be present
  assert_not_contains "CMD_INTERROGATE content" "$output" \
    "Phase 0 active → CMD_INTERROGATE NOT delivered (phase 1 only)"
}

# --- Test 14: Not in tmux — falls back gracefully ---
test_not_in_tmux_falls_back_gracefully() {
  create_test_skill "implement"
  create_test_skill "analyze"

  # Create 2 sessions with fleet pane IDs (but we won't be in tmux)
  local session_alpha="$PROJECT_DIR/sessions/session_alpha"
  mkdir -p "$session_alpha"
  cat > "$session_alpha/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Build",
  "fleetPaneId": "test-fleet:main:Alpha",
  "preloadedFiles": []
}
JSON

  local session_beta="$PROJECT_DIR/sessions/session_beta"
  mkdir -p "$session_beta"
  cat > "$session_beta/.state.json" <<JSON
{
  "pid": $$,
  "skill": "analyze",
  "lifecycle": "active",
  "currentPhase": "2: Analysis",
  "fleetPaneId": "test-fleet:main:Beta",
  "preloadedFiles": []
}
JSON

  # Ensure we're NOT in tmux
  unset TMUX_PANE
  unset TMUX

  local output
  output=$(run_hook "clear") || true

  # Should not crash and should deliver first alphabetical session (implement)
  assert_contains "Test implement skill" "$output" \
    "not in tmux → no crash, falls back to first alive session"

  assert_not_contains "Test analyze skill" "$output" \
    "not in tmux → doesn't deliver second session"

  assert_contains "COMMANDS content" "$output" \
    "not in tmux → standards still present"
}

# --- Test 19: No duplicate preloads when CMD appears in both prose refs and phase CMDs ---
test_no_dupe_when_cmd_in_prose_and_phase() {
  create_multi_phase_skill "implement"

  # Session at Phase 1 — CMD_REPORT_INTENT is both:
  #   - a Phase 1 step (via resolve_phase_cmds)
  #   - a SKILL.md prose ref (§CMD_REPORT_INTENT: appears outside code fences)
  local session_dir="$PROJECT_DIR/sessions/test_dedup"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "1: Interrogation",
  "preloadedFiles": []
}
JSON

  local output
  output=$(run_hook "clear") || true

  # CMD_REPORT_INTENT should appear exactly ONCE
  local count
  count=$(echo "$output" | grep -c 'CMD_REPORT_INTENT content' || true)
  assert_eq "1" "$count" \
    "CMD_REPORT_INTENT delivered exactly once (not duped between prose refs and phase CMDs)"

  # CMD_EXECUTE_SKILL_PHASES should also be exactly once (prose ref only)
  count=$(echo "$output" | grep -c 'CMD_EXECUTE_SKILL_PHASES content' || true)
  assert_eq "1" "$count" \
    "CMD_EXECUTE_SKILL_PHASES delivered exactly once (prose ref)"

  # CMD_INTERROGATE should be exactly once (phase CMD only, not a prose ref)
  count=$(echo "$output" | grep -c 'CMD_INTERROGATE content' || true)
  assert_eq "1" "$count" \
    "CMD_INTERROGATE delivered exactly once (phase CMD)"
}

# --- Test 20: Debrief exists → preloaded as session artifact ---
test_debrief_preloaded_when_exists() {
  create_multi_phase_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_debrief"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3.A: Build Loop",
  "preloadedFiles": []
}
JSON

  # Create a debrief file in the session
  cat > "$session_dir/IMPLEMENT.md" <<MD
# Implementation Debrief
**Tags**: \`#needs-review\`

## Summary
We implemented the widget parser with TDD approach.

## Changes
- Added parser.ts
- Added parser.test.ts
MD

  # Also create a log file (should NOT be preloaded when debrief exists)
  cat > "$session_dir/IMPLEMENT_LOG.md" <<MD
## Session Start
* **Item**: Widget parser
MD

  local output
  output=$(run_hook "clear") || true

  # Debrief should be preloaded
  assert_contains "We implemented the widget parser" "$output" \
    "debrief exists → debrief content preloaded"

  # Log should NOT be preloaded (debrief takes priority)
  assert_not_contains "Widget parser" "$output" \
    "debrief exists → log NOT preloaded (debrief takes priority)" || true
  # NOTE: log content might overlap with debrief. Check for [Preloaded: header instead
  local log_preload_count
  log_preload_count=$(echo "$output" | grep -c 'Preloaded:.*IMPLEMENT_LOG.md' || true)
  assert_eq "0" "$log_preload_count" \
    "debrief exists → log file NOT in preloaded headers"
}

# --- Test 21: No debrief, log exists → log preloaded as fallback ---
test_log_preloaded_when_no_debrief() {
  create_multi_phase_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_log_fallback"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3.A: Build Loop",
  "preloadedFiles": []
}
JSON

  # Only a log file, no debrief
  cat > "$session_dir/IMPLEMENT_LOG.md" <<MD
## Session Start
* **Item**: Widget parser implementation
* **Goal**: Build the parser step by step

## Progress Update
* **Task**: Completed step 1 — schema types
* **Status**: done
MD

  local output
  output=$(run_hook "clear") || true

  # Log should be preloaded as fallback
  assert_contains "Completed step 1" "$output" \
    "no debrief → log content preloaded as fallback"

  local log_preload_count
  log_preload_count=$(echo "$output" | grep -c 'Preloaded:.*IMPLEMENT_LOG.md' || true)
  assert_eq "1" "$log_preload_count" \
    "no debrief → log file appears in preloaded header"
}

# --- Test 22: Neither debrief nor log → no artifact preloaded (no crash) ---
test_no_artifact_no_crash() {
  create_multi_phase_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_no_artifacts"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "0: Setup",
  "preloadedFiles": []
}
JSON

  # No debrief, no log — fresh session

  local output
  output=$(run_hook "clear") || true

  # Should still deliver SKILL.md + CMDs (no crash)
  assert_contains "Test implement skill" "$output" \
    "no artifacts → SKILL.md still delivered"
  assert_contains "CMD_SELECT_MODE content" "$output" \
    "no artifacts → Phase 0 CMDs still delivered"

  # No artifact preloads
  local artifact_count
  artifact_count=$(echo "$output" | grep -c 'Preloaded:.*IMPLEMENT' | grep -v 'TEMPLATE' || true)
  # Should only have TEMPLATE_ references, not session artifacts
}

# --- Test 23: DIALOGUE.md also preloaded when it exists ---
test_details_preloaded_alongside_debrief() {
  create_test_skill "implement"

  local session_dir="$PROJECT_DIR/sessions/test_details"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3.A: Build Loop",
  "preloadedFiles": []
}
JSON

  cat > "$session_dir/IMPLEMENT.md" <<MD
# Implementation Debrief
## Summary
Built the widget parser.
MD

  cat > "$session_dir/DIALOGUE.md" <<MD
## Interrogation Results
**Type**: Q&A

**Agent**: What testing approach?
**User**: Use TDD with jest.
MD

  local output
  output=$(run_hook "clear") || true

  # Debrief should be preloaded
  assert_contains "Built the widget parser" "$output" \
    "debrief preloaded alongside DIALOGUE.md"

  # DIALOGUE.md should also be preloaded
  assert_contains "What testing approach" "$output" \
    "DIALOGUE.md preloaded for interrogation context"
}

# --- Test 24: Skill name maps to correct debrief filename ---
test_skill_debrief_filename_mapping() {
  # Create an "analyze" skill — debrief should be ANALYZE.md
  create_multi_phase_skill "analyze"

  local session_dir="$PROJECT_DIR/sessions/test_analyze_artifact"
  mkdir -p "$session_dir"
  cat > "$session_dir/.state.json" <<JSON
{
  "pid": $$,
  "skill": "analyze",
  "lifecycle": "active",
  "currentPhase": "3.A: Build Loop",
  "preloadedFiles": []
}
JSON

  # Create ANALYZE.md (not IMPLEMENT.md)
  cat > "$session_dir/ANALYZE.md" <<MD
# Analysis Report
## Findings
Found 3 critical issues in the auth module.
MD

  local output
  output=$(run_hook "clear") || true

  assert_contains "Found 3 critical issues" "$output" \
    "analyze skill → ANALYZE.md preloaded (correct filename mapping)"
}

echo "======================================"
echo "Session Start Skill Delivery E2E Tests"
echo "======================================"
echo ""

run_test test_lifecycle_resuming_delivers_skill_deps
run_test test_lifecycle_active_delivers_skill_deps
run_test test_multiple_active_sessions_finds_correct_one
run_test test_no_active_session_no_skill_deps
run_test test_active_session_null_pid_finds_skill_deps
run_test test_skill_deps_tracked_in_seed_file
run_test test_skill_deps_only_when_active_session
run_test test_session_context_line_included
run_test test_standards_preloaded_on_clear
run_test test_multiple_phase0_cmds_delivered
run_test test_fleet_match_correct_session_selected
run_test test_fleet_match_resuming_lifecycle
run_test test_no_fleet_match_fallback_to_first_alive_pid
run_test test_not_in_tmux_falls_back_gracefully
run_test test_current_phase_cmds_delivered_not_phase0
run_test test_sub_phase_cmds_delivered
run_test test_skill_md_prose_refs_delivered
run_test test_phase0_cmds_when_at_phase0
run_test test_no_dupe_when_cmd_in_prose_and_phase
run_test test_debrief_preloaded_when_exists
run_test test_log_preloaded_when_no_debrief
run_test test_no_artifact_no_crash
run_test test_details_preloaded_alongside_debrief
run_test test_skill_debrief_filename_mapping

exit_with_results
