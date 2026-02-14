#!/bin/bash
# ~/.claude/engine/scripts/tests/test-session-sh.sh — Deep coverage tests for session.sh
#
# Tests all 8 subcommands: init, activate, update, phase, target, deactivate, restart, find
# Uses same custom framework as test-run-sh.sh (setup/teardown/pass/fail/skip)
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-sh.sh

# Don't use set -e globally — we need to handle return codes manually in tests
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_PATH="$PATH"

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/sessions"
  mkdir -p "$TEST_DIR/bin"

  # Create mock fleet.sh (default: no fleet, returns empty)
  cat > "$TEST_DIR/bin/fleet.sh" <<'MOCK'
#!/bin/bash
# Mock fleet.sh — default: return empty pane-id, no-op notify
case "${1:-}" in
  pane-id) echo ""; exit 0 ;;
  notify)  exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/fleet.sh"

  # Create mock session-search.sh and doc-search.sh (no-op)
  for tool in session-search doc-search; do
    mkdir -p "$TEST_DIR/tools/$tool"
    cat > "$TEST_DIR/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
    chmod +x "$TEST_DIR/tools/$tool/$tool.sh"
  done

  # Override HOME so session.sh finds our mocks
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/tools/session-search"
  mkdir -p "$HOME/.claude/tools/doc-search"

  # Copy session.sh (not symlink — see PITFALLS.md: symlink + cat > destroys real file)
  cp "$SESSION_SH" "$HOME/.claude/scripts/session.sh"
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"

  # Link mock fleet.sh into the fake home
  ln -sf "$TEST_DIR/bin/fleet.sh" "$HOME/.claude/scripts/fleet.sh"

  # Link mock search tools
  ln -sf "$TEST_DIR/tools/session-search/session-search.sh" "$HOME/.claude/tools/session-search/session-search.sh"
  ln -sf "$TEST_DIR/tools/doc-search/doc-search.sh" "$HOME/.claude/tools/doc-search/doc-search.sh"

  # Override CLAUDE_SUPERVISOR_PID to a dead PID (default)
  export CLAUDE_SUPERVISOR_PID=99999999

  # cd into test dir so session.sh's $PWD/sessions works for find
  cd "$TEST_DIR"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  export PATH="$ORIGINAL_PATH"
  unset CLAUDE_SUPERVISOR_PID
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: set fleet.sh mock to return a specific pane ID
mock_fleet_pane() {
  local pane_id="$1"
  cat > "$HOME/.claude/scripts/fleet.sh" <<MOCK
#!/bin/bash
case "\${1:-}" in
  pane-id) echo "$pane_id"; exit 0 ;;
  notify)  exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
  chmod +x "$HOME/.claude/scripts/fleet.sh"
}

# Helper: create a .state.json fixture
create_state() {
  local dir="$1"
  local json="$2"
  mkdir -p "$dir"
  echo "$json" > "$dir/.state.json"
}

# Helper: returns a complete valid activation JSON with all required fields.
# Usage: valid_activate_json '{"phases":[...], "taskSummary":"override"}' → merged JSON
# Pass '{}' or omit to get base defaults.
valid_activate_json() {
  local overrides="${1:-{\}}"
  jq -n --argjson overrides "$overrides" '{
    "taskType": "IMPLEMENTATION",
    "taskSummary": "test task",
    "scope": "Full Codebase",
    "directoriesOfInterest": [],
    "preludeFiles": [],
    "contextPaths": [],
    "planTemplate": null,
    "logTemplate": null,
    "debriefTemplate": null,
    "requestTemplate": null,
    "responseTemplate": null,
    "requestFiles": [],
    "nextSkills": [],
    "extraInfo": "",
    "phases": []
  } * $overrides'
}

# =============================================================================
# INIT TESTS
# =============================================================================

test_init_creates_directory() {
  local test_name="init: creates directory when it doesn't exist"
  setup

  local output
  output=$("$SESSION_SH" init "$TEST_DIR/sessions/NEW_SESSION" 2>&1)

  if [ -d "$TEST_DIR/sessions/NEW_SESSION" ] && [[ "$output" == *"New session created"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "directory created + 'New session created'" "dir_exists=$([ -d "$TEST_DIR/sessions/NEW_SESSION" ] && echo yes || echo no), output=$output"
  fi

  teardown
}

test_init_existing_directory() {
  local test_name="init: reports 'already exists' for existing directory"
  setup

  mkdir -p "$TEST_DIR/sessions/EXISTING"
  local output
  output=$("$SESSION_SH" init "$TEST_DIR/sessions/EXISTING" 2>&1)

  if [[ "$output" == *"already exists"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "'already exists' in output" "$output"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — FRESH TESTS
# =============================================================================

test_activate_creates_state_json() {
  local test_name="activate: creates .state.json with correct fields"
  setup

  "$SESSION_SH" activate "$TEST_DIR/sessions/FRESH" brainstorm < /dev/null > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/FRESH/.state.json"
  if [ ! -f "$sf" ]; then
    fail "$test_name" ".state.json exists" "file missing"
    teardown; return
  fi

  local pid skill lifecycle loading ctx phase
  pid=$(jq -r '.pid' "$sf")
  skill=$(jq -r '.skill' "$sf")
  lifecycle=$(jq -r '.lifecycle' "$sf")
  loading=$(jq -r '.loading' "$sf")
  ctx=$(jq -r '.contextUsage' "$sf")
  phase=$(jq -r '.currentPhase' "$sf")

  if [ "$pid" = "99999999" ] && [ "$skill" = "brainstorm" ] && [ "$lifecycle" = "active" ] && \
     [ "$loading" = "true" ] && [ "$ctx" = "0" ] && [ "$phase" = "Phase 1: Setup" ]; then
    pass "$test_name"
  else
    fail "$test_name" "pid=99999999, skill=brainstorm, lifecycle=active, loading=true, ctx=0, phase='Phase 1: Setup'" \
      "pid=$pid, skill=$skill, lifecycle=$lifecycle, loading=$loading, ctx=$ctx, phase=$phase"
  fi

  teardown
}

test_activate_with_fleet_pane() {
  local test_name="activate: sets fleetPaneId when fleet.sh returns pane ID"
  setup
  mock_fleet_pane "test:pane:1"

  "$SESSION_SH" activate "$TEST_DIR/sessions/FLEET" brainstorm < /dev/null > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/FLEET/.state.json"
  local fleet_pane
  fleet_pane=$(jq -r '.fleetPaneId' "$sf" 2>/dev/null)

  if [ "$fleet_pane" = "test:pane:1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "fleetPaneId=test:pane:1" "fleetPaneId=$fleet_pane"
  fi

  teardown
}

test_activate_merges_stdin_json() {
  local test_name="activate: merges JSON from stdin into .state.json"
  setup

  valid_activate_json '{"taskSummary":"test task","extraInfo":"some extra"}' | \
    "$SESSION_SH" activate "$TEST_DIR/sessions/MERGE" brainstorm > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/MERGE/.state.json"
  local summary extra
  summary=$(jq -r '.taskSummary' "$sf" 2>/dev/null)
  extra=$(jq -r '.extraInfo' "$sf" 2>/dev/null)

  if [ "$summary" = "test task" ] && [ "$extra" = "some extra" ]; then
    pass "$test_name"
  else
    fail "$test_name" "taskSummary='test task', extraInfo='some extra'" "taskSummary=$summary, extraInfo=$extra"
  fi

  teardown
}

test_activate_sets_phase_from_phases_array() {
  local test_name="activate: derives currentPhase from phases array"
  setup

  valid_activate_json '{"phases":[{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Build"}]}' | \
    "$SESSION_SH" activate "$TEST_DIR/sessions/PHASES" brainstorm > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/PHASES/.state.json"
  local phase
  phase=$(jq -r '.currentPhase' "$sf" 2>/dev/null)

  if [ "$phase" = "1: Setup" ]; then
    pass "$test_name"
  else
    fail "$test_name" "currentPhase='1: Setup'" "currentPhase=$phase"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — SAME PID RE-ACTIVATION
# =============================================================================

test_activate_same_pid_same_skill() {
  local test_name="activate: re-activates silently for same PID + same skill"
  setup

  # Use current shell PID
  export CLAUDE_SUPERVISOR_PID=$$
  create_state "$TEST_DIR/sessions/REACTIVATE" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active", loading: false,
    contextUsage: 0.5, currentPhase: "3: Execution"
  }')"

  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/REACTIVATE" brainstorm < /dev/null 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"re-activated"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + 're-activated'" "exit $exit_code, output=$output"
  fi

  teardown
}

test_activate_same_pid_new_skill() {
  local test_name="activate: updates skill and wipes phases for same PID + different skill"
  setup

  export CLAUDE_SUPERVISOR_PID=$$
  create_state "$TEST_DIR/sessions/NEWSKILL" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active", loading: false,
    phases: [{"major":1,"minor":0,"name":"Setup"}],
    currentPhase: "1: Setup"
  }')"

  valid_activate_json '{"phases":[{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Build"}]}' | \
    "$SESSION_SH" activate "$TEST_DIR/sessions/NEWSKILL" implement > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/NEWSKILL/.state.json"
  local skill phase_history
  skill=$(jq -r '.skill' "$sf")
  phase_history=$(jq -r '.phaseHistory | length' "$sf" 2>/dev/null || echo "null")

  if [ "$skill" = "implement" ] && [ "$phase_history" = "0" ]; then
    pass "$test_name"
  else
    fail "$test_name" "skill=implement, phaseHistory=[] (length 0)" "skill=$skill, phaseHistory length=$phase_history"
  fi

  teardown
}

test_activate_resets_overflow_flags() {
  local test_name="activate: clears killRequested and overflowed on re-activation"
  setup

  export CLAUDE_SUPERVISOR_PID=$$
  create_state "$TEST_DIR/sessions/OVERFLOW" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active", loading: false,
    killRequested: true, overflowed: true, currentPhase: "1: Setup"
  }')"

  # Activate with a different skill to trigger the re-activation path (not early-exit)
  valid_activate_json '{"phases":[{"major":1,"minor":0,"name":"Setup"}]}' | \
    "$SESSION_SH" activate "$TEST_DIR/sessions/OVERFLOW" implement > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/OVERFLOW/.state.json"
  local kill_req overflowed
  kill_req=$(jq -r '.killRequested' "$sf")
  overflowed=$(jq -r '.overflowed' "$sf")

  if [ "$kill_req" = "false" ] && [ "$overflowed" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "killRequested=false, overflowed=false" "killRequested=$kill_req, overflowed=$overflowed"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — PID CONFLICTS
# =============================================================================

test_activate_rejects_alive_pid() {
  local test_name="activate: rejects activation when different alive PID holds session"
  setup

  # Create state with current shell PID (definitely alive)
  create_state "$TEST_DIR/sessions/TAKEN" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active"
  }')"

  # Try to activate with a different PID
  export CLAUDE_SUPERVISOR_PID=99999999
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/TAKEN" implement < /dev/null 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"active agent"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'active agent'" "exit $exit_code, output=$output"
  fi

  teardown
}

test_activate_cleans_dead_pid() {
  local test_name="activate: cleans up stale .state.json when PID is dead"
  setup

  # Create state with dead PID
  create_state "$TEST_DIR/sessions/STALE" '{
    "pid": 99999998,
    "skill": "brainstorm",
    "lifecycle": "active"
  }'

  export CLAUDE_SUPERVISOR_PID=99999999
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/STALE" implement < /dev/null 2>&1)
  local exit_code=$?

  local sf="$TEST_DIR/sessions/STALE/.state.json"
  local new_pid
  new_pid=$(jq -r '.pid' "$sf" 2>/dev/null)

  if [ $exit_code -eq 0 ] && [ "$new_pid" = "99999999" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, new pid=99999999" "exit $exit_code, pid=$new_pid"
  fi

  teardown
}

test_activate_claims_pid_from_other_sessions() {
  local test_name="activate: clears PID from other sessions"
  setup

  export CLAUDE_SUPERVISOR_PID=99999999

  # Create SESSION_A with our PID
  create_state "$TEST_DIR/sessions/SESSION_A" '{
    "pid": 99999999,
    "skill": "brainstorm",
    "lifecycle": "active"
  }'

  # Activate SESSION_B with same PID
  "$SESSION_SH" activate "$TEST_DIR/sessions/SESSION_B" implement < /dev/null > /dev/null 2>&1

  # SESSION_A should have pid deleted (del(.pid) removes the key)
  local old_pid
  old_pid=$(jq -r '.pid // "deleted"' "$TEST_DIR/sessions/SESSION_A/.state.json" 2>/dev/null)

  if [ "$old_pid" = "null" ] || [ "$old_pid" = "deleted" ]; then
    pass "$test_name"
  else
    fail "$test_name" "SESSION_A pid=null/deleted" "SESSION_A pid=$old_pid"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — completedSkills Gate
# =============================================================================

test_activate_rejects_completed_skill() {
  local test_name="activate: rejects activation when skill is in completedSkills"
  setup

  create_state "$TEST_DIR/sessions/COMPLETED" '{
    "pid": 99999998,
    "skill": "brainstorm",
    "lifecycle": "completed",
    "completedSkills": ["brainstorm"]
  }'

  export CLAUDE_SUPERVISOR_PID=99999999
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/COMPLETED" brainstorm < /dev/null 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"already completed"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'already completed'" "exit $exit_code, output=$output"
  fi

  teardown
}

test_activate_allows_completed_with_approval() {
  local test_name="activate: allows re-activation with --user-approved"
  setup

  create_state "$TEST_DIR/sessions/REAPPROVE" '{
    "pid": 99999998,
    "skill": "brainstorm",
    "lifecycle": "completed",
    "completedSkills": ["brainstorm"]
  }'

  export CLAUDE_SUPERVISOR_PID=99999999
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/REAPPROVE" brainstorm --user-approved "User said redo it" < /dev/null 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"re-activation approved"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + 're-activation approved'" "exit $exit_code, output=$output"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — MIGRATION
# =============================================================================

test_activate_migrates_agent_json() {
  local test_name="activate: migrates .agent.json to .state.json"
  setup

  mkdir -p "$TEST_DIR/sessions/MIGRATE"
  echo '{"pid": 99999998, "skill": "brainstorm", "lifecycle": "active"}' > "$TEST_DIR/sessions/MIGRATE/.agent.json"

  export CLAUDE_SUPERVISOR_PID=99999999
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/MIGRATE" brainstorm < /dev/null 2>&1)

  if [ -f "$TEST_DIR/sessions/MIGRATE/.state.json" ] && \
     [ ! -f "$TEST_DIR/sessions/MIGRATE/.agent.json" ] && \
     [[ "$output" == *"Migrated"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" ".state.json exists, .agent.json gone, 'Migrated' in output" \
      "state=$([ -f "$TEST_DIR/sessions/MIGRATE/.state.json" ] && echo yes || echo no), agent=$([ -f "$TEST_DIR/sessions/MIGRATE/.agent.json" ] && echo yes || echo no)"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — REQUIRED FIELDS VALIDATION
# =============================================================================

test_activate_rejects_missing_required_fields() {
  local test_name="activate: errors when required JSON fields are missing"
  setup

  # Provide JSON with only taskSummary — should list missing dynamic fields
  # Static fields (taskType, phases, debriefTemplate, etc.) come from SKILL.md, not agent
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/VALIDATE" implement <<'PARAMS' 2>&1
{"taskSummary": "Test task"}
PARAMS
  )
  local exit_code=$?

  # Should fail and mention missing dynamic fields (scope, contextPaths, etc.)
  local has_error has_scope has_context
  has_error=0; has_scope=0; has_context=0
  [[ "$output" == *"Missing required"* ]] && has_error=1
  [[ "$output" == *"scope"* ]] && has_scope=1
  [[ "$output" == *"contextPaths"* ]] && has_context=1

  if [ $exit_code -ne 0 ] && [ $has_error -eq 1 ] && [ $has_scope -eq 1 ] && [ $has_context -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + lists missing dynamic fields (scope, contextPaths, etc.)" \
      "exit=$exit_code, has_error=$has_error, has_scope=$has_scope, has_context=$has_context"
  fi

  teardown
}

test_activate_accepts_complete_json() {
  local test_name="activate: accepts JSON with all required fields"
  setup

  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/VALID" implement <<'PARAMS' 2>&1
{
  "taskType": "IMPLEMENTATION",
  "taskSummary": "Build the feature",
  "scope": "Full Codebase",
  "directoriesOfInterest": [],
  "preludeFiles": [],
  "contextPaths": [],
  "planTemplate": null,
  "logTemplate": "skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md",
  "debriefTemplate": "skills/implement/assets/TEMPLATE_IMPLEMENTATION.md",
  "requestTemplate": null,
  "responseTemplate": null,
  "requestFiles": [],
  "nextSkills": [],
  "extraInfo": "",
  "phases": [{"major": 1, "minor": 0, "name": "Setup"}]
}
PARAMS
  )
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"Session activated"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + 'Session activated'" "exit=$exit_code, output=$output"
  fi

  teardown
}

# =============================================================================
# SKILL.MD EXTRACTION TESTS
# =============================================================================

# Helper: create a mock SKILL.md with a JSON block in the fake home
create_mock_skill() {
  local skill="$1"
  local json_block="$2"
  local skill_dir="$HOME/.claude/skills/$skill"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<SKILLEOF
---
description: "Test skill"
---
# Test Skill

\`\`\`json
$json_block
\`\`\`

## Phase 1: Setup
...
SKILLEOF
}

test_activate_extracts_skill_json() {
  local test_name="activate: extracts static fields from SKILL.md JSON block"
  setup

  create_mock_skill "test-skill" '{
    "taskType": "ANALYSIS",
    "phases": [{"major": 1, "minor": 0, "name": "Setup"}],
    "nextSkills": ["implement", "fix"]
  }'

  "$SESSION_SH" activate "$TEST_DIR/sessions/SKILL_EXTRACT" test-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Test extraction",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$TEST_DIR/sessions/SKILL_EXTRACT/.state.json"
  local task_type phases_len next_skills
  task_type=$(jq -r '.taskType' "$sf")
  phases_len=$(jq '.phases | length' "$sf")
  next_skills=$(jq -r '.nextSkills[0]' "$sf")

  if [ "$task_type" = "ANALYSIS" ] && [ "$phases_len" = "1" ] && [ "$next_skills" = "implement" ]; then
    pass "$test_name"
  else
    fail "$test_name" "taskType=ANALYSIS, phases_len=1, nextSkills[0]=implement" \
      "taskType=$task_type, phases_len=$phases_len, nextSkills[0]=$next_skills"
  fi

  teardown
}

test_activate_resolves_skill_paths() {
  local test_name="activate: resolves relative template paths from SKILL.md to absolute"
  setup

  create_mock_skill "test-skill" '{
    "taskType": "TEST",
    "logTemplate": "assets/TEMPLATE_TEST_LOG.md",
    "debriefTemplate": "assets/TEMPLATE_TEST.md",
    "planTemplate": "assets/TEMPLATE_TEST_PLAN.md"
  }'

  "$SESSION_SH" activate "$TEST_DIR/sessions/SKILL_PATHS" test-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Test paths",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$TEST_DIR/sessions/SKILL_PATHS/.state.json"
  local log_tmpl debrief_tmpl
  log_tmpl=$(jq -r '.logTemplate' "$sf")
  debrief_tmpl=$(jq -r '.debriefTemplate' "$sf")

  local expected_prefix="$HOME/.claude/skills/test-skill"
  if [[ "$log_tmpl" == "$expected_prefix/assets/TEMPLATE_TEST_LOG.md" ]] && \
     [[ "$debrief_tmpl" == "$expected_prefix/assets/TEMPLATE_TEST.md" ]]; then
    pass "$test_name"
  else
    fail "$test_name" "paths resolved to $expected_prefix/..." \
      "logTemplate=$log_tmpl, debriefTemplate=$debrief_tmpl"
  fi

  teardown
}

test_activate_skill_overwrites_agent_static() {
  local test_name="activate: SKILL.md static fields overwrite agent-provided values"
  setup

  create_mock_skill "test-skill" '{
    "taskType": "CORRECT_TYPE",
    "phases": [{"major": 1, "minor": 0, "name": "Correct Phase"}]
  }'

  # Agent provides WRONG static fields — SKILL.md should win
  "$SESSION_SH" activate "$TEST_DIR/sessions/SKILL_OVERWRITE" test-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Test overwrite",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": "",
  "taskType": "WRONG_TYPE",
  "phases": [{"major": 99, "minor": 0, "name": "Wrong Phase"}]
}
PARAMS

  local sf="$TEST_DIR/sessions/SKILL_OVERWRITE/.state.json"
  local task_type phase_name
  task_type=$(jq -r '.taskType' "$sf")
  phase_name=$(jq -r '.phases[0].name' "$sf")

  if [ "$task_type" = "CORRECT_TYPE" ] && [ "$phase_name" = "Correct Phase" ]; then
    pass "$test_name"
  else
    fail "$test_name" "SKILL.md values win (CORRECT_TYPE, Correct Phase)" \
      "taskType=$task_type, phase_name=$phase_name"
  fi

  teardown
}

test_activate_skips_missing_skill() {
  local test_name="activate: skips extraction when SKILL.md doesn't exist"
  setup

  # No mock skill created — agent provides everything manually
  "$SESSION_SH" activate "$TEST_DIR/sessions/SKILL_MISSING" no-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Test missing skill",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": "",
  "taskType": "MANUAL_TYPE"
}
PARAMS
  local exit_code=$?

  local sf="$TEST_DIR/sessions/SKILL_MISSING/.state.json"
  local task_type
  task_type=$(jq -r '.taskType' "$sf")

  if [ $exit_code -eq 0 ] && [ "$task_type" = "MANUAL_TYPE" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + agent taskType preserved" \
      "exit=$exit_code, taskType=$task_type"
  fi

  teardown
}

test_activate_dynamic_only_with_skill() {
  local test_name="activate: succeeds with dynamic-only JSON when SKILL.md provides static"
  setup

  create_mock_skill "test-skill" '{
    "taskType": "TEST",
    "phases": [{"major": 1, "minor": 0, "name": "Setup"}],
    "nextSkills": [],
    "logTemplate": "assets/LOG.md",
    "debriefTemplate": "assets/DEBRIEF.md"
  }'

  # Agent provides ONLY dynamic fields — static come from SKILL.md
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/SKILL_DYNAMIC" test-skill <<'PARAMS' 2>&1
{
  "taskSummary": "Test dynamic only",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS
  )
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"Session activated"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + 'Session activated'" \
      "exit=$exit_code, output=$(echo "$output" | head -1)"
  fi

  teardown
}

# =============================================================================
# SKILL.MD EXTRACTION: EXPANDED COVERAGE (Cases 1-10)
# =============================================================================

test_activate_same_pid_skill_change_extracts() {
  local test_name="activate: applies SKILL.md static fields on same-PID skill change"
  setup

  create_mock_skill "skill-a" '{
    "taskType": "TYPE_A",
    "phases": [{"label": "0", "name": "Setup A"}]
  }'
  create_mock_skill "skill-b" '{
    "taskType": "TYPE_B",
    "phases": [{"label": "0", "name": "Setup B"}]
  }'

  # First activation with skill-a
  export CLAUDE_SUPERVISOR_PID=$$
  "$SESSION_SH" activate "$TEST_DIR/sessions/SAME_PID" skill-a <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "First activation",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  # Re-activate same session with skill-b (same PID)
  "$SESSION_SH" activate "$TEST_DIR/sessions/SAME_PID" skill-b <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Second activation",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$TEST_DIR/sessions/SAME_PID/.state.json"
  local task_type skill phase_name
  task_type=$(jq -r '.taskType' "$sf")
  skill=$(jq -r '.skill' "$sf")
  phase_name=$(jq -r '.phases[0].name' "$sf")

  if [ "$task_type" = "TYPE_B" ] && [ "$skill" = "skill-b" ] && [ "$phase_name" = "Setup B" ]; then
    pass "$test_name"
  else
    fail "$test_name" "taskType=TYPE_B, skill=skill-b, phase=Setup B" \
      "taskType=$task_type, skill=$skill, phase=$phase_name"
  fi

  teardown
}

test_activate_idle_reactivation_extracts() {
  local test_name="activate: applies SKILL.md static fields on idle reactivation"
  setup

  create_mock_skill "idle-skill" '{
    "taskType": "IDLE_TYPE",
    "phases": [{"label": "0", "name": "Idle Setup"}],
    "nextSkills": ["/fix"]
  }'

  # Create an idle .state.json with null PID
  local dir="$TEST_DIR/sessions/IDLE_REACTIVATE"
  mkdir -p "$dir"
  cat > "$dir/.state.json" <<'STATE'
{
  "pid": null,
  "skill": "old-skill",
  "lifecycle": "idle",
  "loading": false,
  "overflowed": false,
  "killRequested": false,
  "taskType": "OLD_TYPE"
}
STATE

  export CLAUDE_SUPERVISOR_PID=$$
  "$SESSION_SH" activate "$dir" idle-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Idle reactivation test",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$dir/.state.json"
  local task_type lifecycle pid next_skill
  task_type=$(jq -r '.taskType' "$sf")
  lifecycle=$(jq -r '.lifecycle' "$sf")
  pid=$(jq -r '.pid' "$sf")
  next_skill=$(jq -r '.nextSkills[0]' "$sf")

  if [ "$task_type" = "IDLE_TYPE" ] && [ "$lifecycle" = "active" ] && \
     [ "$pid" = "$$" ] && [ "$next_skill" = "/fix" ]; then
    pass "$test_name"
  else
    fail "$test_name" "taskType=IDLE_TYPE, lifecycle=active, pid=$$, nextSkills[0]=/fix" \
      "taskType=$task_type, lifecycle=$lifecycle, pid=$pid, nextSkills[0]=$next_skill"
  fi

  teardown
}

test_activate_resolves_modes_paths() {
  local test_name="activate: resolves modes nested file paths to absolute"
  setup

  create_mock_skill "modes-skill" '{
    "taskType": "MODES_TEST",
    "modes": {
      "coverage": {"label": "Coverage", "description": "Gap filling", "file": "modes/coverage.md"},
      "hardening": {"label": "Hardening", "description": "Edge cases", "file": "modes/hardening.md"}
    }
  }'

  "$SESSION_SH" activate "$TEST_DIR/sessions/MODES_PATHS" modes-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Test modes paths",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$TEST_DIR/sessions/MODES_PATHS/.state.json"
  local coverage_file hardening_file
  coverage_file=$(jq -r '.modes.coverage.file' "$sf")
  hardening_file=$(jq -r '.modes.hardening.file' "$sf")

  local expected_prefix="$HOME/.claude/skills/modes-skill"
  if [[ "$coverage_file" == "$expected_prefix/modes/coverage.md" ]] && \
     [[ "$hardening_file" == "$expected_prefix/modes/hardening.md" ]]; then
    pass "$test_name"
  else
    fail "$test_name" "modes paths resolved to $expected_prefix/modes/..." \
      "coverage=$coverage_file, hardening=$hardening_file"
  fi

  teardown
}

test_activate_same_pid_same_skill_no_remerge() {
  local test_name="activate: same-PID same-skill exits early without re-merging state"
  setup

  create_mock_skill "test-skill" '{
    "taskType": "ORIGINAL",
    "phases": [{"label": "0", "name": "Setup"}]
  }'

  export CLAUDE_SUPERVISOR_PID=$$
  "$SESSION_SH" activate "$TEST_DIR/sessions/NO_REMERGE" test-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "First activation",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  # Add a custom field to .state.json
  local sf="$TEST_DIR/sessions/NO_REMERGE/.state.json"
  jq '.customField = "survive"' "$sf" | tee "$sf.tmp" > /dev/null && mv "$sf.tmp" "$sf"

  # Re-activate same skill, same PID
  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/NO_REMERGE" test-skill < /dev/null 2>&1) || true

  local custom_field
  custom_field=$(jq -r '.customField // "missing"' "$sf")

  if [[ "$output" == *"Session re-activated"* ]] && [ "$custom_field" = "survive" ]; then
    pass "$test_name"
  else
    fail "$test_name" "early exit with 'Session re-activated' + customField survives" \
      "output=$(echo "$output" | head -1), customField=$custom_field"
  fi

  teardown
}

test_activate_setup_copies_session_sh() {
  local test_name="activate: setup() copies session.sh instead of symlinking"
  setup

  local session_sh_path="$HOME/.claude/scripts/session.sh"
  if [ -L "$session_sh_path" ]; then
    fail "$test_name" "regular file (not symlink)" "is a symlink"
  elif [ -f "$session_sh_path" ]; then
    pass "$test_name"
  else
    fail "$test_name" "regular file exists" "file does not exist"
  fi

  teardown
}

test_activate_invalid_json_graceful() {
  local test_name="activate: gracefully handles invalid JSON in SKILL.md"
  setup

  # Create SKILL.md with malformed JSON
  local skill_dir="$HOME/.claude/skills/bad-json"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
description: "Bad JSON skill"
---
# Bad JSON Skill

```json
{ "taskType": "BROKEN", "phases": INVALID_NOT_JSON }
```
SKILLEOF

  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/BAD_JSON" bad-json <<'PARAMS' 2>&1
{
  "taskSummary": "Test bad json",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": "",
  "taskType": "AGENT_FALLBACK"
}
PARAMS
  ) || true
  local exit_code=$?

  local sf="$TEST_DIR/sessions/BAD_JSON/.state.json"
  local task_type
  task_type=$(jq -r '.taskType' "$sf" 2>/dev/null || echo "missing")

  if [ $exit_code -eq 0 ] && [ "$task_type" = "AGENT_FALLBACK" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + agent taskType=AGENT_FALLBACK preserved" \
      "exit=$exit_code, taskType=$task_type"
  fi

  teardown
}

test_activate_no_json_block_graceful() {
  local test_name="activate: handles SKILL.md with no JSON block"
  setup

  # Create SKILL.md with no ```json fence
  local skill_dir="$HOME/.claude/skills/no-json"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
description: "No JSON skill"
---
# No JSON Skill

This skill has prose but no JSON block.

## Phase 1: Setup
Just do things.
SKILLEOF

  local output
  output=$("$SESSION_SH" activate "$TEST_DIR/sessions/NO_JSON" no-json <<'PARAMS' 2>&1
{
  "taskSummary": "Test no json block",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": "",
  "taskType": "AGENT_PROVIDED"
}
PARAMS
  ) || true
  local exit_code=$?

  local sf="$TEST_DIR/sessions/NO_JSON/.state.json"
  local task_type
  task_type=$(jq -r '.taskType' "$sf" 2>/dev/null || echo "missing")

  if [ $exit_code -eq 0 ] && [ "$task_type" = "AGENT_PROVIDED" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 + agent taskType=AGENT_PROVIDED preserved" \
      "exit=$exit_code, taskType=$task_type"
  fi

  teardown
}

test_activate_absolute_paths_unchanged() {
  local test_name="activate: absolute paths in SKILL.md are not double-resolved"
  setup

  create_mock_skill "abs-path-skill" '{
    "taskType": "ABS_TEST",
    "logTemplate": "/absolute/path/LOG.md",
    "debriefTemplate": "assets/TEMPLATE_REL.md"
  }'

  "$SESSION_SH" activate "$TEST_DIR/sessions/ABS_PATHS" abs-path-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "Test absolute paths",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$TEST_DIR/sessions/ABS_PATHS/.state.json"
  local log_tmpl debrief_tmpl
  log_tmpl=$(jq -r '.logTemplate' "$sf")
  debrief_tmpl=$(jq -r '.debriefTemplate' "$sf")

  local expected_prefix="$HOME/.claude/skills/abs-path-skill"
  if [ "$log_tmpl" = "/absolute/path/LOG.md" ] && \
     [[ "$debrief_tmpl" == "$expected_prefix/assets/TEMPLATE_REL.md" ]]; then
    pass "$test_name"
  else
    fail "$test_name" "logTemplate=/absolute/path/LOG.md (unchanged), debriefTemplate resolved" \
      "logTemplate=$log_tmpl, debriefTemplate=$debrief_tmpl"
  fi

  teardown
}

test_activate_static_filter_preserves_dynamic() {
  local test_name="activate: static filter overwrites only static fields, preserves dynamic"
  setup

  create_mock_skill "filter-skill" '{
    "taskType": "SKILL_TYPE",
    "phases": [{"label": "0", "name": "Skill Phase"}],
    "nextSkills": ["/review"]
  }'

  "$SESSION_SH" activate "$TEST_DIR/sessions/STATIC_FILTER" filter-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "My specific task",
  "scope": "Narrow scope",
  "directoriesOfInterest": ["src/"],
  "contextPaths": ["docs/README.md"],
  "requestFiles": [],
  "extraInfo": "Agent-only info",
  "taskType": "WRONG_AGENT_TYPE"
}
PARAMS

  local sf="$TEST_DIR/sessions/STATIC_FILTER/.state.json"
  local task_type task_summary scope extra_info
  task_type=$(jq -r '.taskType' "$sf")
  task_summary=$(jq -r '.taskSummary' "$sf")
  scope=$(jq -r '.scope' "$sf")
  extra_info=$(jq -r '.extraInfo' "$sf")

  if [ "$task_type" = "SKILL_TYPE" ] && \
     [ "$task_summary" = "My specific task" ] && \
     [ "$scope" = "Narrow scope" ] && \
     [ "$extra_info" = "Agent-only info" ]; then
    pass "$test_name"
  else
    fail "$test_name" "static overwritten (SKILL_TYPE), dynamic preserved (My specific task, Narrow scope, Agent-only info)" \
      "taskType=$task_type, taskSummary=$task_summary, scope=$scope, extraInfo=$extra_info"
  fi

  teardown
}

test_activate_stale_pid_then_extracts() {
  local test_name="activate: cleans stale PID then applies SKILL.md extraction on fresh activation"
  setup

  create_mock_skill "stale-skill" '{
    "taskType": "STALE_FRESH",
    "phases": [{"label": "0", "name": "Fresh Start"}]
  }'

  # Create .state.json with a dead PID
  local dir="$TEST_DIR/sessions/STALE_PID"
  mkdir -p "$dir"
  cat > "$dir/.state.json" <<'STATE'
{
  "pid": 99999998,
  "skill": "old-skill",
  "lifecycle": "active",
  "taskType": "OLD_STALE"
}
STATE

  export CLAUDE_SUPERVISOR_PID=$$
  "$SESSION_SH" activate "$dir" stale-skill <<'PARAMS' > /dev/null 2>&1
{
  "taskSummary": "After stale cleanup",
  "scope": "Full",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": ""
}
PARAMS

  local sf="$dir/.state.json"
  local task_type pid phase_name
  task_type=$(jq -r '.taskType' "$sf")
  pid=$(jq -r '.pid' "$sf")
  phase_name=$(jq -r '.phases[0].name' "$sf")

  if [ "$task_type" = "STALE_FRESH" ] && [ "$pid" = "$$" ] && [ "$phase_name" = "Fresh Start" ]; then
    pass "$test_name"
  else
    fail "$test_name" "taskType=STALE_FRESH, pid=$$, phase=Fresh Start" \
      "taskType=$task_type, pid=$pid, phase=$phase_name"
  fi

  teardown
}

# =============================================================================
# UPDATE TESTS
# =============================================================================

test_update_numeric_value() {
  local test_name="update: stores numeric value as number"
  setup

  create_state "$TEST_DIR/sessions/UPD_NUM" '{
    "pid": 99999999, "skill": "brainstorm", "contextUsage": 0
  }'

  "$SESSION_SH" update "$TEST_DIR/sessions/UPD_NUM" contextUsage 0.85 > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/UPD_NUM/.state.json"
  local val type_check
  val=$(jq -r '.contextUsage' "$sf")
  # Check it's a number (jq type)
  type_check=$(jq -r '.contextUsage | type' "$sf")

  if [ "$val" = "0.85" ] && [ "$type_check" = "number" ]; then
    pass "$test_name"
  else
    fail "$test_name" "contextUsage=0.85 (number)" "val=$val, type=$type_check"
  fi

  teardown
}

test_update_string_value() {
  local test_name="update: stores string value as string"
  setup

  create_state "$TEST_DIR/sessions/UPD_STR" '{
    "pid": 99999999, "skill": "brainstorm"
  }'

  "$SESSION_SH" update "$TEST_DIR/sessions/UPD_STR" skill implement > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/UPD_STR/.state.json"
  local val type_check
  val=$(jq -r '.skill' "$sf")
  type_check=$(jq -r '.skill | type' "$sf")

  if [ "$val" = "implement" ] && [ "$type_check" = "string" ]; then
    pass "$test_name"
  else
    fail "$test_name" "skill=implement (string)" "val=$val, type=$type_check"
  fi

  teardown
}

test_update_missing_state_file() {
  local test_name="update: errors when .state.json doesn't exist"
  setup

  mkdir -p "$TEST_DIR/sessions/NO_STATE"
  local output
  output=$("$SESSION_SH" update "$TEST_DIR/sessions/NO_STATE" field value 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"No .state.json"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'No .state.json'" "exit $exit_code, output=$output"
  fi

  teardown
}

# =============================================================================
# PHASE — SEQUENTIAL ENFORCEMENT
# =============================================================================

test_phase_allows_sequential() {
  local test_name="phase: allows next-in-sequence phase transition"
  setup

  create_state "$TEST_DIR/sessions/PHASE_SEQ" "$(jq -n '{
    pid: 99999999, skill: "implement", lifecycle: "active", loading: true,
    currentPhase: "1: Setup",
    phases: [
      {major: 1, minor: 0, name: "Setup"},
      {major: 2, minor: 0, name: "Build"},
      {major: 3, minor: 0, name: "Synth"}
    ]
  }')"

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_SEQ" "2: Build" > /dev/null 2>&1
  local exit_code=$?

  local sf="$TEST_DIR/sessions/PHASE_SEQ/.state.json"
  local phase
  phase=$(jq -r '.currentPhase' "$sf")

  if [ $exit_code -eq 0 ] && [ "$phase" = "2: Build" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, currentPhase='2: Build'" "exit $exit_code, phase=$phase"
  fi

  teardown
}

test_phase_rejects_skip() {
  local test_name="phase: rejects skipping a phase without --user-approved"
  setup

  create_state "$TEST_DIR/sessions/PHASE_SKIP" "$(jq -n '{
    pid: 99999999, skill: "implement", lifecycle: "active",
    currentPhase: "1: Setup",
    phases: [
      {major: 1, minor: 0, name: "Setup"},
      {major: 2, minor: 0, name: "Build"},
      {major: 3, minor: 0, name: "Synth"}
    ]
  }')"

  local output
  output=$("$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_SKIP" "3: Synth" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"Non-sequential"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'Non-sequential'" "exit $exit_code, output=$output"
  fi

  teardown
}

test_phase_allows_skip_with_approval() {
  local test_name="phase: allows skip with --user-approved"
  setup

  create_state "$TEST_DIR/sessions/PHASE_APPROVE" "$(jq -n '{
    pid: 99999999, skill: "implement", lifecycle: "active",
    currentPhase: "1: Setup",
    phases: [
      {major: 1, minor: 0, name: "Setup"},
      {major: 2, minor: 0, name: "Build"},
      {major: 3, minor: 0, name: "Synth"}
    ]
  }')"

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_APPROVE" "3: Synth" --user-approved "User said skip" > /dev/null 2>&1
  local exit_code=$?

  local sf="$TEST_DIR/sessions/PHASE_APPROVE/.state.json"
  local phase
  phase=$(jq -r '.currentPhase' "$sf")

  if [ $exit_code -eq 0 ] && [ "$phase" = "3: Synth" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, currentPhase='3: Synth'" "exit $exit_code, phase=$phase"
  fi

  teardown
}

test_phase_auto_appends_subphase() {
  local test_name="phase: auto-appends sub-phase with same major"
  setup

  create_state "$TEST_DIR/sessions/PHASE_SUB" "$(jq -n '{
    pid: 99999999, skill: "implement", lifecycle: "active",
    currentPhase: "4: Planning",
    phases: [
      {major: 1, minor: 0, name: "Setup"},
      {major: 4, minor: 0, name: "Planning"},
      {major: 5, minor: 0, name: "Build"}
    ]
  }')"

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_SUB" "4.1: Agent Handoff" > /dev/null 2>&1
  local exit_code=$?

  local sf="$TEST_DIR/sessions/PHASE_SUB/.state.json"
  local phase sub_exists
  phase=$(jq -r '.currentPhase' "$sf")
  # Auto-appended sub-phases use label-only format (no major/minor fields)
  sub_exists=$(jq '[.phases[] | select(.label == "4.1")] | length' "$sf")

  if [ $exit_code -eq 0 ] && [ "$phase" = "4.1: Agent Handoff" ] && [ "$sub_exists" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, phase='4.1: Agent Handoff', sub-phase in array" \
      "exit $exit_code, phase=$phase, sub_exists=$sub_exists"
  fi

  teardown
}

test_phase_clears_loading_flag() {
  local test_name="phase: clears loading flag and resets counters"
  setup

  create_state "$TEST_DIR/sessions/PHASE_LOAD" "$(jq -n '{
    pid: 99999999, skill: "implement", lifecycle: "active", loading: true,
    currentPhase: "1: Setup",
    toolCallsByTranscript: {"tx1": 5, "tx2": 3},
    phases: [
      {major: 1, minor: 0, name: "Setup"},
      {major: 2, minor: 0, name: "Build"}
    ]
  }')"

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_LOAD" "2: Build" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/PHASE_LOAD/.state.json"
  local loading_exists counters phase_history_len
  loading_exists=$(jq 'has("loading")' "$sf")
  counters=$(jq '.toolCallsByTranscript | length' "$sf")
  phase_history_len=$(jq '.phaseHistory | length' "$sf")

  if [ "$loading_exists" = "false" ] && [ "$counters" = "0" ] && [ "$phase_history_len" -ge 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "loading deleted, counters={}, phaseHistory>=1" \
      "loading_exists=$loading_exists, counters=$counters, history_len=$phase_history_len"
  fi

  teardown
}

test_phase_no_enforcement_without_phases_array() {
  local test_name="phase: allows any transition when no phases array"
  setup

  create_state "$TEST_DIR/sessions/PHASE_FREE" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "1: Setup"
  }'

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_FREE" "5: Random Phase" > /dev/null 2>&1
  local exit_code=$?

  local sf="$TEST_DIR/sessions/PHASE_FREE/.state.json"
  local phase
  phase=$(jq -r '.currentPhase' "$sf")

  if [ $exit_code -eq 0 ] && [ "$phase" = "5: Random Phase" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, currentPhase='5: Random Phase'" "exit $exit_code, phase=$phase"
  fi

  teardown
}

test_phase_populates_pending_commands() {
  local test_name="phase: populates pendingPreloads from steps and commands arrays"
  setup

  # Create CMD files in the fake HOME so session.sh can resolve them
  local cmd_dir="$HOME/.claude/.directives/commands"
  mkdir -p "$cmd_dir"
  echo "# APPEND_LOG" > "$cmd_dir/CMD_APPEND_LOG.md"
  echo "# TRACK_PROGRESS" > "$cmd_dir/CMD_TRACK_PROGRESS.md"
  # CMD_NONEXISTENT.md intentionally NOT created — should be filtered out

  create_state "$TEST_DIR/sessions/PHASE_CMD" "$(jq -n '{
    pid: 99999999, skill: "fix", lifecycle: "active", loading: true,
    currentPhase: "2: Triage Walk-Through",
    phases: [
      {major: 2, minor: 0, name: "Triage Walk-Through"},
      {major: 3, minor: 0, name: "Fix Loop",
       steps: ["§CMD_NONEXISTENT"],
       commands: ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS"]}
    ]
  }')"

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_CMD" "3: Fix Loop" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/PHASE_CMD/.state.json"
  local pending_count pending_has_append pending_has_track pending_has_nonexistent
  pending_count=$(jq '.pendingPreloads | length' "$sf" 2>/dev/null || echo "0")
  pending_has_append=$(jq '[.pendingPreloads[] | test("CMD_APPEND_LOG")] | any' "$sf" 2>/dev/null || echo "false")
  pending_has_track=$(jq '[.pendingPreloads[] | test("CMD_TRACK_PROGRESS")] | any' "$sf" 2>/dev/null || echo "false")
  pending_has_nonexistent=$(jq '[.pendingPreloads[] | test("CMD_NONEXISTENT")] | any' "$sf" 2>/dev/null || echo "false")

  if [ "$pending_count" = "2" ] && [ "$pending_has_append" = "true" ] && [ "$pending_has_track" = "true" ] && [ "$pending_has_nonexistent" = "false" ]; then
    pass "$test_name"
  else
    fail "$test_name" "2 pending (APPEND_LOG + TRACK_PROGRESS, no NONEXISTENT)" \
      "count=$pending_count, append=$pending_has_append, track=$pending_has_track, nonexistent=$pending_has_nonexistent"
  fi

  teardown
}

test_phase_skips_already_preloaded_commands() {
  local test_name="phase: filters already-preloaded files from pendingPreloads"
  setup

  local cmd_dir="$HOME/.claude/.directives/commands"
  mkdir -p "$cmd_dir"
  echo "# APPEND_LOG" > "$cmd_dir/CMD_APPEND_LOG.md"
  echo "# TRACK_PROGRESS" > "$cmd_dir/CMD_TRACK_PROGRESS.md"

  create_state "$TEST_DIR/sessions/PHASE_PRELOADED" "$(jq -n '{
    pid: 99999999, skill: "fix", lifecycle: "active", loading: true,
    currentPhase: "2: Triage Walk-Through",
    preloadedFiles: ["~/.claude/.directives/commands/CMD_APPEND_LOG.md"],
    phases: [
      {major: 2, minor: 0, name: "Triage Walk-Through"},
      {major: 3, minor: 0, name: "Fix Loop",
       commands: ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS"]}
    ]
  }')"

  "$SESSION_SH" phase "$TEST_DIR/sessions/PHASE_PRELOADED" "3: Fix Loop" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/PHASE_PRELOADED/.state.json"
  local pending_count pending_has_track
  pending_count=$(jq '.pendingPreloads | length' "$sf" 2>/dev/null || echo "0")
  pending_has_track=$(jq '[.pendingPreloads[] | test("CMD_TRACK_PROGRESS")] | any' "$sf" 2>/dev/null || echo "false")

  if [ "$pending_count" = "1" ] && [ "$pending_has_track" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "1 pending (TRACK_PROGRESS only, APPEND_LOG filtered)" \
      "count=$pending_count, track=$pending_has_track"
  fi

  teardown
}

# =============================================================================
# TARGET TEST
# =============================================================================

test_target_updates_target_file() {
  local test_name="target: sets targetFile in .state.json"
  setup

  create_state "$TEST_DIR/sessions/TARGET" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active"
  }'

  "$SESSION_SH" target "$TEST_DIR/sessions/TARGET" "IMPLEMENTATION.md" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/TARGET/.state.json"
  local target
  target=$(jq -r '.targetFile' "$sf")

  if [ "$target" = "IMPLEMENTATION.md" ]; then
    pass "$test_name"
  else
    fail "$test_name" "targetFile=IMPLEMENTATION.md" "targetFile=$target"
  fi

  teardown
}

# =============================================================================
# DEACTIVATE TESTS
# =============================================================================

test_deactivate_sets_completed() {
  local test_name="deactivate: sets lifecycle=completed and stores description"
  setup

  create_state "$TEST_DIR/sessions/DEACT" '{
    "pid": 99999999, "skill": "brainstorm", "lifecycle": "active"
  }'

  echo "Did some work on brainstorming" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/DEACT/.state.json"
  local lifecycle desc
  lifecycle=$(jq -r '.lifecycle' "$sf")
  desc=$(jq -r '.sessionDescription' "$sf")

  if [ "$lifecycle" = "completed" ] && [ "$desc" = "Did some work on brainstorming" ]; then
    pass "$test_name"
  else
    fail "$test_name" "lifecycle=completed, desc='Did some work on brainstorming'" \
      "lifecycle=$lifecycle, desc=$desc"
  fi

  teardown
}

test_deactivate_requires_description() {
  local test_name="deactivate: errors when no description piped"
  setup

  create_state "$TEST_DIR/sessions/DEACT_NODESC" '{
    "pid": 99999999, "skill": "brainstorm", "lifecycle": "active"
  }'

  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_NODESC" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"Description is required"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'Description is required'" "exit $exit_code, output=$output"
  fi

  teardown
}

test_deactivate_appends_completed_skills() {
  local test_name="deactivate: adds current skill to completedSkills"
  setup

  create_state "$TEST_DIR/sessions/DEACT_SKILLS" '{
    "pid": 99999999, "skill": "brainstorm", "lifecycle": "active"
  }'

  echo "Finished brainstorming" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_SKILLS" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/DEACT_SKILLS/.state.json"
  local skills
  skills=$(jq -r '.completedSkills | join(",")' "$sf" 2>/dev/null)

  if [ "$skills" = "brainstorm" ]; then
    pass "$test_name"
  else
    fail "$test_name" "completedSkills=[brainstorm]" "completedSkills=$skills"
  fi

  teardown
}

test_deactivate_stores_keywords() {
  local test_name="deactivate: stores keywords as array"
  setup

  create_state "$TEST_DIR/sessions/DEACT_KW" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active"
  }'

  echo "Implemented auth" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_KW" --keywords "auth,middleware,NestJS" > /dev/null 2>&1

  local sf="$TEST_DIR/sessions/DEACT_KW/.state.json"
  local kw_count kw_first kw_last
  kw_count=$(jq '.searchKeywords | length' "$sf")
  kw_first=$(jq -r '.searchKeywords[0]' "$sf")
  kw_last=$(jq -r '.searchKeywords[2]' "$sf")

  if [ "$kw_count" = "3" ] && [ "$kw_first" = "auth" ] && [ "$kw_last" = "NestJS" ]; then
    pass "$test_name"
  else
    fail "$test_name" "3 keywords: [auth, ..., NestJS]" "count=$kw_count, first=$kw_first, last=$kw_last"
  fi

  teardown
}

test_deactivate_outputs_all_errors() {
  local test_name="deactivate: outputs all errors when multiple gates fail"
  setup

  # State with discoveredChecklists but no checkPassed, and a debriefTemplate
  # currentPhase must be > 1 so EARLY_PHASE=false and gates actually fire
  create_state "$TEST_DIR/sessions/DEACT_MULTI" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "3: Synthesis",
    "debriefTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md",
    "discoveredChecklists": ["packages/foo/CHECKLIST.md"]
  }'
  # No debrief file exists, no description piped, checklist not passed → all 3 gates fail

  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_MULTI" 2>&1)
  local exit_code=$?

  local has_desc_err has_debrief_err has_checklist_err
  has_desc_err=0
  has_debrief_err=0
  has_checklist_err=0
  [[ "$output" == *"Description is required"* ]] && has_desc_err=1
  [[ "$output" == *"Cannot deactivate — no debrief file found"* ]] && has_debrief_err=1
  [[ "$output" == *"Cannot deactivate"*"checkPassed"* ]] && has_checklist_err=1

  if [ $exit_code -ne 0 ] && [ $has_desc_err -eq 1 ] && [ $has_debrief_err -eq 1 ] && [ $has_checklist_err -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + all 3 gate errors present" \
      "exit=$exit_code, desc_err=$has_desc_err, debrief_err=$has_debrief_err, checklist_err=$has_checklist_err"
  fi

  teardown
}

test_deactivate_single_error_only() {
  local test_name="deactivate: outputs only relevant error when one gate fails"
  setup

  # State with debriefTemplate but no debrief file. No checklists. Description IS provided.
  # currentPhase must be > 1 so EARLY_PHASE=false and debrief gate fires
  create_state "$TEST_DIR/sessions/DEACT_SINGLE" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "3: Synthesis",
    "debriefTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md"
  }'
  # No debrief file → only gate 2 should fire

  local output
  output=$(echo "Some description" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_SINGLE" 2>&1)
  local exit_code=$?

  local has_desc_err has_debrief_err has_checklist_err
  has_desc_err=0
  has_debrief_err=0
  has_checklist_err=0
  [[ "$output" == *"Description is required"* ]] && has_desc_err=1
  [[ "$output" == *"Cannot deactivate — no debrief file found"* ]] && has_debrief_err=1
  [[ "$output" == *"checkPassed"* ]] && has_checklist_err=1

  if [ $exit_code -ne 0 ] && [ $has_desc_err -eq 0 ] && [ $has_debrief_err -eq 1 ] && [ $has_checklist_err -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + ONLY debrief error" \
      "exit=$exit_code, desc_err=$has_desc_err, debrief_err=$has_debrief_err, checklist_err=$has_checklist_err"
  fi

  teardown
}

# =============================================================================
# TERMINAL PROOF TESTS (deactivate from idle with phase proof)
# =============================================================================

test_deactivate_terminal_proof_succeeds_no_proof_fields() {
  local test_name="deactivate terminal proof: succeeds when current phase has no proof fields"
  setup

  # Idle session with phases array, but terminal phase has no proof fields
  create_state "$TEST_DIR/sessions/DEACT_TP1" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Did some work",
    "phases": [
      {"label": "4.4", "name": "Close"}
    ]
  }'

  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_TP1" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_terminal_proof_blocks_no_stdin() {
  local test_name="deactivate terminal proof: blocks when phase has proof fields but no stdin"
  setup

  # Idle session with phases array, terminal phase HAS proof fields
  create_state "$TEST_DIR/sessions/DEACT_TP2" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Did some work",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": ["session_idled", "description_written"]}
    ]
  }'

  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_TP2" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"Terminal proof required"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'Terminal proof required'" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_terminal_proof_succeeds_with_proof() {
  local test_name="deactivate terminal proof: succeeds when proof is piped via stdin"
  setup

  # Idle session with proof fields on terminal phase
  create_state "$TEST_DIR/sessions/DEACT_TP3" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Did some work",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": ["session_idled", "description_written"]}
    ]
  }'

  local output
  output=$(printf 'session_idled: true\ndescription_written: true' | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_TP3" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_terminal_proof_skips_no_phases() {
  local test_name="deactivate terminal proof: skips validation when no phases array"
  setup

  # Idle session WITHOUT phases array (backward compat)
  create_state "$TEST_DIR/sessions/DEACT_TP4" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Did some work"
  }'

  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/DEACT_TP4" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 (no phases = no enforcement)" "exit=$exit_code, output=$output"
  fi

  teardown
}

# =============================================================================
# RESTART TESTS
# =============================================================================

test_restart_sets_kill_requested() {
  local test_name="restart: sets killRequested=true and writes restartPrompt"
  setup

  create_state "$TEST_DIR/sessions/RESTART" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "4: Build", "sessionId": "sess-123", "contextUsage": 0.75
  }'

  # No WATCHDOG_PID so it won't try to signal; TEST_MODE prevents tmux keystroke injection
  unset WATCHDOG_PID 2>/dev/null || true
  TEST_MODE=1 "$SESSION_SH" restart "$TEST_DIR/sessions/RESTART" > /dev/null 2>&1 || true  # restart calls exit 0

  local sf="$TEST_DIR/sessions/RESTART/.state.json"
  local kill_req prompt ctx sid
  kill_req=$(jq -r '.killRequested' "$sf")
  prompt=$(jq -r '.restartPrompt' "$sf")
  ctx=$(jq -r '.contextUsage' "$sf")
  sid=$(jq -r '.sessionId // "deleted"' "$sf")

  if [ "$kill_req" = "true" ] && [[ "$prompt" == *"/session continue"* ]] && [ "$ctx" = "0" ] && [ "$sid" = "deleted" ]; then
    pass "$test_name"
  else
    fail "$test_name" "killRequested=true, prompt contains /session continue, ctx=0, sessionId deleted" \
      "kill=$kill_req, prompt=$prompt, ctx=$ctx, sid=$sid"
  fi

  teardown
}

test_restart_missing_state_file() {
  local test_name="restart: errors when .state.json doesn't exist"
  setup

  mkdir -p "$TEST_DIR/sessions/NO_RESTART"
  local output
  output=$("$SESSION_SH" restart "$TEST_DIR/sessions/NO_RESTART" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"No .state.json"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'No .state.json'" "exit $exit_code, output=$output"
  fi

  teardown
}

# =============================================================================
# FIND TESTS
# =============================================================================

test_find_by_pid() {
  local test_name="find: finds session by matching PID (non-fleet mode)"
  setup

  export CLAUDE_SUPERVISOR_PID=99999999
  create_state "$TEST_DIR/sessions/FINDME" '{
    "pid": 99999999, "skill": "brainstorm", "lifecycle": "active"
  }'

  local output
  output=$("$SESSION_SH" find 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [[ "$output" == *"sessions/FINDME"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output contains sessions/FINDME" "exit $exit_code, output=$output"
  fi

  teardown
}

test_find_no_match() {
  local test_name="find: exits 1 when no session matches"
  setup

  export CLAUDE_SUPERVISOR_PID=99999999
  # Create a session with a DIFFERENT PID
  create_state "$TEST_DIR/sessions/OTHER" '{
    "pid": 88888888, "skill": "brainstorm", "lifecycle": "active"
  }'

  "$SESSION_SH" find > /dev/null 2>&1
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1" "exit $exit_code"
  fi

  teardown
}

test_find_rejects_alive_different_pid() {
  local test_name="find: exits 1 when fleet match has alive different PID"
  setup

  mock_fleet_pane "test:pane:1"
  export CLAUDE_SUPERVISOR_PID=99999999

  # Create state with fleet pane match but different ALIVE PID ($$)
  create_state "$TEST_DIR/sessions/FLEET_TAKEN" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active",
    fleetPaneId: "test:pane:1"
  }')"

  "$SESSION_SH" find > /dev/null 2>&1
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 (alive different PID)" "exit $exit_code"
  fi

  teardown
}

# =============================================================================
# TERMINAL PROOF INTEGRATION TESTS
# =============================================================================

test_full_lifecycle_idle_then_deactivate_with_proof() {
  local test_name="lifecycle: activate → phase → idle → deactivate with proof"
  setup

  local DIR="$TEST_DIR/sessions/LIFECYCLE1"

  # Step 1: Activate with phases array where terminal phase has proof fields
  local output
  output=$(valid_activate_json '{"phases":[{"label":"0","name":"Setup","proof":[]},{"label":"1","name":"Work","proof":[]},{"label":"2","name":"Synthesis","proof":["session_idled","description_written"]}]}' | "$SESSION_SH" activate "$DIR" implement 2>&1)

  # Step 2: Transition through phases to terminal phase
  echo "" | "$SESSION_SH" phase "$DIR" "0: Setup" 2>&1 > /dev/null
  echo "" | "$SESSION_SH" phase "$DIR" "1: Work" 2>&1 > /dev/null
  echo "" | "$SESSION_SH" phase "$DIR" "2: Synthesis" 2>&1 > /dev/null

  # Step 3: Call idle (stores description + keywords)
  echo "Completed lifecycle test work" | "$SESSION_SH" idle "$DIR" --keywords "test,lifecycle" 2>&1 > /dev/null

  # Step 4: Deactivate with proof via stdin
  output=$(printf 'session_idled: true\ndescription_written: true' | "$SESSION_SH" deactivate "$DIR" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    local lifecycle
    lifecycle=$(jq -r '.lifecycle' "$DIR/.state.json")
    assert_eq "completed" "$lifecycle" "$test_name — lifecycle is completed"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_full_lifecycle_idle_then_deactivate_no_proof_needed() {
  local test_name="lifecycle: activate → idle → deactivate succeeds when terminal phase has no proof fields"
  setup

  local DIR="$TEST_DIR/sessions/LIFECYCLE2"

  # Activate with phases array where terminal phase has empty proof
  valid_activate_json '{"phases":[{"label":"0","name":"Setup","proof":[]},{"label":"1","name":"Work","proof":[]},{"label":"2","name":"Synthesis","proof":[]}]}' | "$SESSION_SH" activate "$DIR" implement 2>&1 > /dev/null

  # Transition through phases
  echo "" | "$SESSION_SH" phase "$DIR" "0: Setup" 2>&1 > /dev/null
  echo "" | "$SESSION_SH" phase "$DIR" "1: Work" 2>&1 > /dev/null
  echo "" | "$SESSION_SH" phase "$DIR" "2: Synthesis" 2>&1 > /dev/null

  # Idle with description
  echo "No proof needed work" | "$SESSION_SH" idle "$DIR" 2>&1 > /dev/null

  # Deactivate — no proof needed (empty proof array on terminal phase)
  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$DIR" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    local lifecycle
    lifecycle=$(jq -r '.lifecycle' "$DIR/.state.json")
    assert_eq "completed" "$lifecycle" "$test_name — lifecycle is completed"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_direct_deactivate_active_session_skips_proof() {
  local test_name="lifecycle: direct deactivate (active, no idle) skips proof gate"
  setup

  local DIR="$TEST_DIR/sessions/LIFECYCLE3"

  # Activate with proof fields on terminal phase
  valid_activate_json '{"phases":[{"label":"0","name":"Setup","proof":[]},{"label":"2","name":"Synthesis","proof":["session_idled","description_written"]}]}' | "$SESSION_SH" activate "$DIR" implement 2>&1 > /dev/null

  # Transition to terminal phase
  echo "" | "$SESSION_SH" phase "$DIR" "0: Setup" 2>&1 > /dev/null
  echo "" | "$SESSION_SH" phase "$DIR" "2: Synthesis" 2>&1 > /dev/null

  # Deactivate directly (lifecycle=active, not idle) — stdin is description, NOT proof
  local output
  output=$(echo "Direct deactivation description" | "$SESSION_SH" deactivate "$DIR" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    local desc
    desc=$(jq -r '.sessionDescription' "$DIR/.state.json")
    assert_contains "Direct deactivation" "$desc" "$test_name — description stored"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_idle_stdin_is_proof_not_description() {
  local test_name="deactivate stdin routing: idle session uses stdin as proof, description from state"
  setup

  # Create idle session with description already stored
  create_state "$TEST_DIR/sessions/STDIN_PROOF" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Work done in idle",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": ["session_idled"]}
    ]
  }'

  # Deactivate with proof via stdin
  local output
  output=$(printf 'session_idled: true' | "$SESSION_SH" deactivate "$TEST_DIR/sessions/STDIN_PROOF" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    # Description should come from stored state, not from stdin
    local desc
    desc=$(jq -r '.sessionDescription' "$TEST_DIR/sessions/STDIN_PROOF/.state.json")
    assert_eq "Work done in idle" "$desc" "$test_name — description from state"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_active_stdin_is_description_not_proof() {
  local test_name="deactivate stdin routing: active session uses stdin as description, skips proof"
  setup

  # Create active session with proof-gated terminal phase
  create_state "$TEST_DIR/sessions/STDIN_DESC" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "4.4: Close",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": ["session_idled", "description_written"]}
    ]
  }'

  # Deactivate with description via stdin (lifecycle=active → proof gate skipped)
  local output
  output=$(echo "This is a description not proof" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/STDIN_DESC" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    local desc
    desc=$(jq -r '.sessionDescription' "$TEST_DIR/sessions/STDIN_DESC/.state.json")
    assert_contains "This is a description" "$desc" "$test_name — description stored"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_terminal_proof_partial_fields() {
  local test_name="deactivate terminal proof: blocks on partial proof (missing field)"
  setup

  # Idle session, terminal phase needs two proof fields
  create_state "$TEST_DIR/sessions/PARTIAL_PROOF" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Partial proof work",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": ["session_idled", "description_written"]}
    ]
  }'

  # Only provide one of two required proof fields
  local output
  output=$(printf 'session_idled: true' | "$SESSION_SH" deactivate "$TEST_DIR/sessions/PARTIAL_PROOF" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    assert_contains "Terminal proof incomplete" "$output" "$test_name — error mentions incomplete"
    assert_contains "description_written" "$output" "$test_name — error mentions missing field"
  else
    fail "$test_name" "exit 1 (partial proof)" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_terminal_proof_unfilled_blanks() {
  local test_name="deactivate terminal proof: blocks on unfilled blank (________)"
  setup

  # Idle session with proof fields
  create_state "$TEST_DIR/sessions/UNFILLED_BLANK" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "Unfilled blank work",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": ["session_idled", "description_written"]}
    ]
  }'

  # Provide proof with unfilled placeholder
  local output
  output=$(printf 'session_idled: ________\ndescription_written: true' | "$SESSION_SH" deactivate "$TEST_DIR/sessions/UNFILLED_BLANK" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    assert_contains "unfilled blank" "$output" "$test_name — error mentions unfilled blank"
  else
    fail "$test_name" "exit 1 (unfilled blank)" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_deactivate_idle_no_description_stored() {
  local test_name="deactivate: blocks when idle session has no stored description"
  setup

  # Idle session with empty sessionDescription
  create_state "$TEST_DIR/sessions/NO_DESC_IDLE" '{
    "pid": null, "skill": "implement", "lifecycle": "idle",
    "currentPhase": "4.4: Close",
    "sessionDescription": "",
    "phases": [
      {"label": "4.4", "name": "Close", "proof": []}
    ]
  }'

  # Deactivate — stdin is proof (lifecycle=idle), description comes from state (empty)
  local output
  output=$(echo "" | "$SESSION_SH" deactivate "$TEST_DIR/sessions/NO_DESC_IDLE" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"Description is required"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + 'Description is required'" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_continue_clears_loading_flag() {
  local test_name="continue: clears loading flag and resets toolCallsByTranscript"
  setup

  local DIR="$TEST_DIR/sessions/CONTINUE1"
  create_state "$DIR" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "3: Build", "loading": true,
    "toolCallsByTranscript": {"Bash": 5, "Read": 3}
  }'

  local output
  output=$(echo "" | "$SESSION_SH" continue "$DIR" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    local sf="$DIR/.state.json"
    local loading tc_count phase
    loading=$(jq -r '.loading // "deleted"' "$sf")
    tc_count=$(jq '.toolCallsByTranscript | length' "$sf")
    phase=$(jq -r '.currentPhase' "$sf")

    assert_eq "deleted" "$loading" "$test_name — loading flag deleted"
    assert_eq "0" "$tc_count" "$test_name — toolCallsByTranscript reset to empty"
    assert_eq "3: Build" "$phase" "$test_name — currentPhase unchanged"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

test_continue_preserves_phase_state() {
  local test_name="continue: preserves currentPhase and phaseHistory"
  setup

  local DIR="$TEST_DIR/sessions/CONTINUE2"
  create_state "$DIR" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "3.A: Build Loop",
    "phaseHistory": ["0: Setup", "1: Context", "2: Plan", "3.A: Build Loop"],
    "loading": true,
    "toolCallsByTranscript": {"Bash": 10}
  }'

  local output
  output=$(echo "" | "$SESSION_SH" continue "$DIR" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    local sf="$DIR/.state.json"
    local phase history_len
    phase=$(jq -r '.currentPhase' "$sf")
    history_len=$(jq '.phaseHistory | length' "$sf")

    assert_eq "3.A: Build Loop" "$phase" "$test_name — currentPhase preserved"
    assert_eq "4" "$history_len" "$test_name — phaseHistory unchanged (4 entries)"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi

  teardown
}

# =============================================================================
# Run all tests
# =============================================================================
main() {
  echo "============================================="
  echo "session.sh Deep Coverage Tests"
  echo "============================================="
  echo ""

  echo "--- Init ---"
  test_init_creates_directory
  test_init_existing_directory

  echo ""
  echo "--- Activate: Fresh ---"
  test_activate_creates_state_json
  test_activate_with_fleet_pane
  test_activate_merges_stdin_json
  test_activate_sets_phase_from_phases_array

  echo ""
  echo "--- Activate: Same PID Re-activation ---"
  test_activate_same_pid_same_skill
  test_activate_same_pid_new_skill
  test_activate_resets_overflow_flags

  echo ""
  echo "--- Activate: PID Conflicts ---"
  test_activate_rejects_alive_pid
  test_activate_cleans_dead_pid
  test_activate_claims_pid_from_other_sessions

  echo ""
  echo "--- Activate: completedSkills Gate ---"
  test_activate_rejects_completed_skill
  test_activate_allows_completed_with_approval

  echo ""
  echo "--- Activate: Migration ---"
  test_activate_migrates_agent_json

  echo ""
  echo "--- Activate: Required Fields ---"
  test_activate_rejects_missing_required_fields
  test_activate_accepts_complete_json

  echo ""
  echo "--- Activate: SKILL.md Extraction ---"
  test_activate_extracts_skill_json
  test_activate_resolves_skill_paths
  test_activate_skill_overwrites_agent_static
  test_activate_skips_missing_skill
  test_activate_dynamic_only_with_skill

  echo ""
  echo "--- Activate: Extraction Expanded Coverage ---"
  test_activate_same_pid_skill_change_extracts
  test_activate_idle_reactivation_extracts
  test_activate_resolves_modes_paths
  test_activate_same_pid_same_skill_no_remerge
  test_activate_setup_copies_session_sh
  test_activate_invalid_json_graceful
  test_activate_no_json_block_graceful
  test_activate_absolute_paths_unchanged
  test_activate_static_filter_preserves_dynamic
  test_activate_stale_pid_then_extracts

  echo ""
  echo "--- Update ---"
  test_update_numeric_value
  test_update_string_value
  test_update_missing_state_file

  echo ""
  echo "--- Phase: Sequential Enforcement ---"
  test_phase_allows_sequential
  test_phase_rejects_skip
  test_phase_allows_skip_with_approval
  test_phase_auto_appends_subphase
  test_phase_clears_loading_flag
  test_phase_no_enforcement_without_phases_array
  test_phase_populates_pending_commands
  test_phase_skips_already_preloaded_commands

  echo ""
  echo "--- Target ---"
  test_target_updates_target_file

  echo ""
  echo "--- Deactivate ---"
  test_deactivate_sets_completed
  test_deactivate_requires_description
  test_deactivate_appends_completed_skills
  test_deactivate_stores_keywords
  test_deactivate_outputs_all_errors
  test_deactivate_single_error_only

  echo ""
  echo "--- Terminal Proof ---"
  test_deactivate_terminal_proof_succeeds_no_proof_fields
  test_deactivate_terminal_proof_blocks_no_stdin
  test_deactivate_terminal_proof_succeeds_with_proof
  test_deactivate_terminal_proof_skips_no_phases

  echo ""
  echo "--- Restart ---"
  test_restart_sets_kill_requested
  test_restart_missing_state_file

  echo ""
  echo "--- Find ---"
  test_find_by_pid
  test_find_no_match
  test_find_rejects_alive_different_pid

  echo ""
  echo "--- Terminal Proof Integration ---"
  test_full_lifecycle_idle_then_deactivate_with_proof
  test_full_lifecycle_idle_then_deactivate_no_proof_needed
  test_direct_deactivate_active_session_skips_proof
  test_deactivate_idle_stdin_is_proof_not_description
  test_deactivate_active_stdin_is_description_not_proof
  test_deactivate_terminal_proof_partial_fields
  test_deactivate_terminal_proof_unfilled_blanks
  test_deactivate_idle_no_description_stored
  test_continue_clears_loading_flag
  test_continue_preserves_phase_state

  exit_with_results
}

main "$@"
