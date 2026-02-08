#!/bin/bash
# ~/.claude/engine/scripts/tests/test-session-sh.sh — Deep coverage tests for session.sh
#
# Tests all 8 subcommands: init, activate, update, phase, target, deactivate, restart, find
# Uses same custom framework as test-run-sh.sh (setup/teardown/pass/fail/skip)
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-sh.sh

# Don't use set -e globally — we need to handle return codes manually in tests
set -uo pipefail

SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

  # Symlink the real session.sh and lib.sh
  ln -sf "$SESSION_SH" "$HOME/.claude/scripts/session.sh"
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

pass() {
  echo -e "${GREEN}PASS${RESET}: $1"
  ((TESTS_PASSED++))
}

fail() {
  echo -e "${RED}FAIL${RESET}: $1"
  echo "  Expected: $2"
  echo "  Got: $3"
  ((TESTS_FAILED++))
}

skip() {
  echo -e "${YELLOW}SKIP${RESET}: $1 — $2"
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

# =============================================================================
# INIT TESTS
# =============================================================================

test_init_creates_directory() {
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate: merges JSON from stdin into .state.json"
  setup

  echo '{"taskSummary":"test task","extraInfo":"some extra"}' | \
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
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate: derives currentPhase from phases array"
  setup

  echo '{"phases":[{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Build"}]}' | \
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate: updates skill and wipes phases for same PID + different skill"
  setup

  export CLAUDE_SUPERVISOR_PID=$$
  create_state "$TEST_DIR/sessions/NEWSKILL" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active", loading: false,
    phases: [{"major":1,"minor":0,"name":"Setup"}],
    currentPhase: "1: Setup"
  }')"

  echo '{"phases":[{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Build"}]}' | \
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
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="activate: clears killRequested and overflowed on re-activation"
  setup

  export CLAUDE_SUPERVISOR_PID=$$
  create_state "$TEST_DIR/sessions/OVERFLOW" "$(jq -n --argjson pid $$ '{
    pid: $pid, skill: "brainstorm", lifecycle: "active", loading: false,
    killRequested: true, overflowed: true, currentPhase: "1: Setup"
  }')"

  # Activate with a different skill to trigger the re-activation path (not early-exit)
  echo '{"phases":[{"major":1,"minor":0,"name":"Setup"}]}' | \
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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

  # SESSION_A should have pid=0 now
  local old_pid
  old_pid=$(jq -r '.pid' "$TEST_DIR/sessions/SESSION_A/.state.json" 2>/dev/null)

  if [ "$old_pid" = "0" ]; then
    pass "$test_name"
  else
    fail "$test_name" "SESSION_A pid=0" "SESSION_A pid=$old_pid"
  fi

  teardown
}

# =============================================================================
# ACTIVATE — completedSkills Gate
# =============================================================================

test_activate_rejects_completed_skill() {
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
# UPDATE TESTS
# =============================================================================

test_update_numeric_value() {
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  sub_exists=$(jq '[.phases[] | select(.major == 4 and .minor == 1)] | length' "$sf")

  if [ $exit_code -eq 0 ] && [ "$phase" = "4.1: Agent Handoff" ] && [ "$sub_exists" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, phase='4.1: Agent Handoff', sub-phase in array" \
      "exit $exit_code, phase=$phase, sub_exists=$sub_exists"
  fi

  teardown
}

test_phase_clears_loading_flag() {
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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

# =============================================================================
# TARGET TEST
# =============================================================================

test_target_updates_target_file() {
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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

# =============================================================================
# RESTART TESTS
# =============================================================================

test_restart_sets_kill_requested() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="restart: sets killRequested=true and writes restartPrompt"
  setup

  create_state "$TEST_DIR/sessions/RESTART" '{
    "pid": 99999999, "skill": "implement", "lifecycle": "active",
    "currentPhase": "4: Build", "sessionId": "sess-123", "contextUsage": 0.75
  }'

  # No WATCHDOG_PID so it won't try to signal
  unset WATCHDOG_PID 2>/dev/null || true
  "$SESSION_SH" restart "$TEST_DIR/sessions/RESTART" > /dev/null 2>&1 || true  # restart calls exit 0

  local sf="$TEST_DIR/sessions/RESTART/.state.json"
  local kill_req prompt ctx sid
  kill_req=$(jq -r '.killRequested' "$sf")
  prompt=$(jq -r '.restartPrompt' "$sf")
  ctx=$(jq -r '.contextUsage' "$sf")
  sid=$(jq -r '.sessionId // "deleted"' "$sf")

  if [ "$kill_req" = "true" ] && [[ "$prompt" == *"/reanchor"* ]] && [ "$ctx" = "0" ] && [ "$sid" = "deleted" ]; then
    pass "$test_name"
  else
    fail "$test_name" "killRequested=true, prompt contains /reanchor, ctx=0, sessionId deleted" \
      "kill=$kill_req, prompt=$prompt, ctx=$ctx, sid=$sid"
  fi

  teardown
}

test_restart_missing_state_file() {
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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
  TESTS_RUN=$((TESTS_RUN + 1))
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

  echo ""
  echo "--- Target ---"
  test_target_updates_target_file

  echo ""
  echo "--- Deactivate ---"
  test_deactivate_sets_completed
  test_deactivate_requires_description
  test_deactivate_appends_completed_skills
  test_deactivate_stores_keywords

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
  echo "============================================="
  echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
  echo "============================================="

  if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
  fi
}

main "$@"
