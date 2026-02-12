#!/bin/bash
# tests/test-run-lifecycle.sh — Integration tests for run.sh lifecycle
#
# Tests the full run.sh -> Claude binary -> session.sh cycle using a stub Claude binary.
# The stub reads a "script" file that tells it what to do (session commands, exit codes, etc.)
#
# Run: bash tmp/test-run-lifecycle.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/scripts/session.sh"
RUN_SH="$HOME/.claude/scripts/run.sh"
TMP_DIR=$(mktemp -d)

# Save original PATH for proper expansion
ORIG_PATH="$PATH"

# Disable fleet/tmux detection for test isolation
unset TMUX 2>/dev/null || true
unset TMUX_PANE 2>/dev/null || true

# Create a stub claude binary in a temp dir and return the dir path
# Usage: STUB_BIN_DIR=$(make_stub "script content here")
# The stub writes its args to $STUB_BIN_DIR/invocations.log
make_stub() {
  local script_content="$1"
  local stub_dir="$TMP_DIR/stub_$$_$RANDOM"
  mkdir -p "$stub_dir"

  local script_file="$stub_dir/script.sh"
  echo "$script_content" > "$script_file"

  cat > "$stub_dir/claude" <<'STUBEOF'
#!/bin/bash
# Claude binary stub — reads script from $STUB_SCRIPT_FILE
SCRIPT_FILE="${STUB_SCRIPT_FILE:-}"
LOG_FILE="${STUB_LOG_FILE:-/dev/null}"

echo "INVOKED: args=$*" >> "$LOG_FILE"

[ -z "$SCRIPT_FILE" ] || [ ! -f "$SCRIPT_FILE" ] && exit 0

while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^#.*$ ]] && continue
  [ -z "$line" ] && continue

  CMD=$(echo "$line" | awk '{print $1}')
  ARGS=$(echo "$line" | cut -d' ' -f2-)

  case "$CMD" in
    session:activate)
      DIR=$(echo "$ARGS" | awk '{print $1}')
      SKILL=$(echo "$ARGS" | awk '{print $2}')
      "$HOME/.claude/scripts/session.sh" activate "$DIR" "$SKILL" >/dev/null 2>&1 <<'ACTIVATE_JSON' || true
{"taskType":"TESTING","taskSummary":"stub test","scope":"test","directoriesOfInterest":[],"preludeFiles":[],"contextPaths":[],"planTemplate":null,"logTemplate":null,"debriefTemplate":null,"requestTemplate":null,"responseTemplate":null,"requestFiles":[],"nextSkills":[],"extraInfo":"","phases":[{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Context Ingestion"},{"major":3,"minor":0,"name":"Strategy"},{"major":4,"minor":0,"name":"Testing Loop"},{"major":5,"minor":0,"name":"Synthesis"}]}
ACTIVATE_JSON
      ;;
    session:phase)
      DIR=$(echo "$ARGS" | awk '{print $1}')
      PHASE=$(echo "$ARGS" | cut -d' ' -f2-)
      "$HOME/.claude/scripts/session.sh" phase "$DIR" "$PHASE" < /dev/null >/dev/null 2>&1 || true
      ;;
    session:deactivate)
      DIR=$(echo "$ARGS" | awk '{print $1}')
      "$HOME/.claude/scripts/session.sh" deactivate "$DIR" <<< "Stub deactivation" >/dev/null 2>&1 || true
      ;;
    exit:*)
      CODE=$(echo "$CMD" | cut -d: -f2)
      exit "$CODE"
      ;;
    *)
      ;;
  esac
done < "$SCRIPT_FILE"
exit 0
STUBEOF
  chmod +x "$stub_dir/claude"

  export STUB_SCRIPT_FILE="$script_file"
  export STUB_LOG_FILE="$stub_dir/invocations.log"
  touch "$stub_dir/invocations.log"

  echo "$stub_dir"
}

# Run run.sh with a stub claude
# Usage: OUTPUT=$(run_with_stub "$STUB_BIN_DIR")
run_with_stub() {
  local stub_dir="$1"
  shift
  export FLEET_SETUP_DONE=1
  export STUB_SCRIPT_FILE="$stub_dir/script.sh"
  export STUB_LOG_FILE="$stub_dir/invocations.log"
  timeout 15 env PATH="$stub_dir:$ORIG_PATH" TMUX="" TMUX_PANE="" bash "$RUN_SH" "$@" 2>&1 || true
}

echo "=== run.sh Lifecycle Integration Tests ==="
echo ""

# --- Case 3: Normal exit ---
echo "--- Case 3: Normal exit (Claude exits 0) ---"
STUB_DIR=$(make_stub "exit:0")
OUTPUT=$(run_with_stub "$STUB_DIR")

INVOCATIONS=$(wc -l < "$STUB_DIR/invocations.log" | tr -d ' ')
assert_gt "$INVOCATIONS" 0 "Claude was invoked at least once"
assert_contains "Starting" "$OUTPUT" "run.sh printed starting message"
assert_contains "Goodbye" "$OUTPUT" "run.sh printed goodbye"

echo ""

# --- Case 4: Restart loop ---
echo "--- Case 4: Restart loop (Claude exits, restart detected) ---"

# We need a project-like dir with sessions/ subdirectory for find_restart_agent_json
PROJECT_DIR="$TMP_DIR/project4"
mkdir -p "$PROJECT_DIR/sessions/restart_test"

# Pre-set restart state in .state.json
cat > "$PROJECT_DIR/sessions/restart_test/.state.json" <<RESTARTEOF
{
  "pid": 0,
  "skill": "test",
  "lifecycle": "active",
  "currentPhase": "3: Testing",
  "killRequested": true,
  "restartPrompt": "/session continue --session sessions/restart_test --skill test --phase \"3: Testing\"",
  "overflowed": false
}
RESTARTEOF

# Create a stub that counts invocations via a file
COUNTER_FILE="$TMP_DIR/restart_counter"
echo "0" > "$COUNTER_FILE"

RESTART_STUB_DIR="$TMP_DIR/restart_bin"
mkdir -p "$RESTART_STUB_DIR"
cat > "$RESTART_STUB_DIR/claude" <<RSTUBEOF
#!/bin/bash
COUNT=\$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "$COUNTER_FILE"
echo "INVOKED #\$COUNT: args=\$*" >> "$RESTART_STUB_DIR/invocations.log"

# Second+ invocation: clear restart state so run.sh stops looping
if [ "\$COUNT" -ge 2 ]; then
  STATE_FILE="$PROJECT_DIR/sessions/restart_test/.state.json"
  if [ -f "\$STATE_FILE" ]; then
    jq '.killRequested = false | del(.restartPrompt)' "\$STATE_FILE" > "\$STATE_FILE.tmp" \\
      && mv "\$STATE_FILE.tmp" "\$STATE_FILE"
  fi
fi
exit 0
RSTUBEOF
chmod +x "$RESTART_STUB_DIR/claude"
touch "$RESTART_STUB_DIR/invocations.log"

export FLEET_SETUP_DONE=1
RESTART_OUTPUT=$(timeout 15 env PATH="$RESTART_STUB_DIR:$ORIG_PATH" TMUX="" TMUX_PANE="" bash -c "cd '$PROJECT_DIR' && bash '$RUN_SH'" 2>&1 || true)

RESTART_INVOCATIONS=$(grep -c "INVOKED" "$RESTART_STUB_DIR/invocations.log" || echo "0")
assert_gt "$RESTART_INVOCATIONS" 1 "Claude invoked at least twice (restart loop)"
assert_contains "Restart" "$RESTART_OUTPUT" "run.sh detected restart"

# Invocations log should contain "/session continue" (the restart prompt passed to second invocation)
RESTART_LOG_CONTENT=$(cat "$RESTART_STUB_DIR/invocations.log")
assert_contains "session continue" "$RESTART_LOG_CONTENT" "Restart prompt contains /session continue"

# After restart loop, lifecycle should be restarting
assert_json "$PROJECT_DIR/sessions/restart_test/.state.json" '.lifecycle' 'restarting' "lifecycle is restarting"

echo ""

# --- Case 5: Claude stub invokes session.sh commands ---
echo "--- Case 5: Claude stub runs session.sh activate/phase/deactivate ---"

CASE5_SESSION="$TMP_DIR/sessions/case5_test"
mkdir -p "$CASE5_SESSION"

STUB_DIR=$(make_stub "$(cat <<CASE5EOF
session:activate $CASE5_SESSION implement
session:phase $CASE5_SESSION 1: Setup
session:phase $CASE5_SESSION 2: Context Ingestion
session:deactivate $CASE5_SESSION
exit:0
CASE5EOF
)")
OUTPUT=$(run_with_stub "$STUB_DIR")

assert_file_exists "$CASE5_SESSION/.state.json" "state.json created by activate"
if [ -f "$CASE5_SESSION/.state.json" ]; then
  assert_json "$CASE5_SESSION/.state.json" '.skill' 'implement' "skill set to implement"
  assert_json "$CASE5_SESSION/.state.json" '.lifecycle' 'completed' "lifecycle is completed"
  assert_json "$CASE5_SESSION/.state.json" '.completedSkills[0]' 'implement' "completedSkills contains implement"

  PHASE_HISTORY_LEN=$(jq '.phaseHistory | length' "$CASE5_SESSION/.state.json" 2>/dev/null || echo "0")
  assert_gt "$PHASE_HISTORY_LEN" 0 "phaseHistory has entries"
else
  echo "  SKIP: remaining Case 5 assertions (no state file)"
  TESTS_FAILED=$((TESTS_FAILED + 4))
fi

echo ""

# --- Case 6: Full lifecycle with all phases ---
echo "--- Case 6: Full lifecycle activate -> all phases -> deactivate ---"

CASE6_SESSION="$TMP_DIR/sessions/case6_test"
mkdir -p "$CASE6_SESSION"

STUB_DIR=$(make_stub "$(cat <<CASE6EOF
session:activate $CASE6_SESSION test
session:phase $CASE6_SESSION 1: Setup
session:phase $CASE6_SESSION 2: Context Ingestion
session:phase $CASE6_SESSION 3: Strategy
session:phase $CASE6_SESSION 4: Testing Loop
session:phase $CASE6_SESSION 5: Synthesis
session:deactivate $CASE6_SESSION
exit:0
CASE6EOF
)")
OUTPUT=$(run_with_stub "$STUB_DIR")

assert_file_exists "$CASE6_SESSION/.state.json" "state.json exists"
if [ -f "$CASE6_SESSION/.state.json" ]; then
  assert_json "$CASE6_SESSION/.state.json" '.skill' 'test' "skill is test"
  assert_json "$CASE6_SESSION/.state.json" '.lifecycle' 'completed' "lifecycle is completed"
  assert_json "$CASE6_SESSION/.state.json" '.currentPhase' '5: Synthesis' "currentPhase is 5: Synthesis"
  assert_json "$CASE6_SESSION/.state.json" '.completedSkills[0]' 'test' "completedSkills contains test"

  CASE6_PH_LEN=$(jq '.phaseHistory | length' "$CASE6_SESSION/.state.json" 2>/dev/null || echo "0")
  assert_gt "$CASE6_PH_LEN" 4 "phaseHistory has 5+ entries"

  CASE6_PID=$(jq -r '.pid' "$CASE6_SESSION/.state.json" 2>/dev/null || echo "0")
  assert_gt "$CASE6_PID" 0 "PID is set (not 0)"
else
  echo "  SKIP: remaining Case 6 assertions (no state file)"
  TESTS_FAILED=$((TESTS_FAILED + 6))
fi

echo ""

# --- Case 7: SESSION_REQUIRED and CLAUDE_SUPERVISOR_PID exported ---
echo "--- Case 7: Environment variables exported to Claude ---"

ENV_STUB_DIR="$TMP_DIR/env_bin"
mkdir -p "$ENV_STUB_DIR"
cat > "$ENV_STUB_DIR/claude" <<'ENVSTUBEOF'
#!/bin/bash
[ "${SESSION_REQUIRED:-}" = "1" ] && echo "SESSION_REQUIRED=1" || echo "SESSION_REQUIRED_MISSING"
[ -n "${CLAUDE_SUPERVISOR_PID:-}" ] && echo "CLAUDE_SUPERVISOR_PID=$CLAUDE_SUPERVISOR_PID" || echo "CLAUDE_SUPERVISOR_PID_MISSING"
[ -n "${WATCHDOG_PID:-}" ] && echo "WATCHDOG_PID=$WATCHDOG_PID" || echo "WATCHDOG_PID_MISSING"
exit 0
ENVSTUBEOF
chmod +x "$ENV_STUB_DIR/claude"

export FLEET_SETUP_DONE=1
ENV_OUTPUT=$(timeout 15 env PATH="$ENV_STUB_DIR:$ORIG_PATH" TMUX="" TMUX_PANE="" bash "$RUN_SH" 2>&1 || true)

assert_contains "SESSION_REQUIRED=1" "$ENV_OUTPUT" "SESSION_REQUIRED=1 exported"
assert_contains "CLAUDE_SUPERVISOR_PID=" "$ENV_OUTPUT" "CLAUDE_SUPERVISOR_PID exported"
assert_contains "WATCHDOG_PID=" "$ENV_OUTPUT" "WATCHDOG_PID exported"

echo ""

# --- Cleanup ---
rm -rf "$TMP_DIR"

exit_with_results
