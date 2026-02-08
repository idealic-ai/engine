#!/bin/bash
# tests/test-run-lifecycle.sh — Integration tests for run.sh lifecycle
#
# Tests the full run.sh → Claude binary → session.sh cycle using a stub Claude binary.
# The stub reads a "script" file that tells it what to do (session commands, exit codes, etc.)
#
# Run: bash tmp/test-run-lifecycle.sh

set -uo pipefail

SESSION_SH="$HOME/.claude/scripts/session.sh"
RUN_SH="$HOME/.claude/scripts/run.sh"
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0

# Save original PATH for proper expansion
ORIG_PATH="$PATH"

# Disable fleet/tmux detection for test isolation
unset TMUX 2>/dev/null || true
unset TMUX_PANE 2>/dev/null || true

# Helpers
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_json() {
  local desc="$1" file="$2" field="$3" expected="$4"
  local actual
  actual=$(jq -r "$field" "$file" 2>/dev/null || echo "ERROR")
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_gt() {
  local desc="$1" a="$2" b="$3"
  if [ "$a" -gt "$b" ] 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc ($a is not > $b)"
    FAIL=$((FAIL + 1))
  fi
}

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
      "$HOME/.claude/scripts/session.sh" activate "$DIR" "$SKILL" < /dev/null >/dev/null 2>&1 || true
      ;;
    session:phase)
      DIR=$(echo "$ARGS" | awk '{print $1}')
      PHASE=$(echo "$ARGS" | cut -d' ' -f2-)
      "$HOME/.claude/scripts/session.sh" phase "$DIR" "$PHASE" >/dev/null 2>&1 || true
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
assert_gt "Claude was invoked at least once" "$INVOCATIONS" 0
assert_contains "run.sh printed starting message" "Starting" "$OUTPUT"
assert_contains "run.sh printed goodbye" "Goodbye" "$OUTPUT"

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
  "restartPrompt": "/reanchor --session sessions/restart_test --skill test --phase 3 --continue",
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
assert_gt "Claude invoked at least twice (restart loop)" "$RESTART_INVOCATIONS" 1
assert_contains "run.sh detected restart" "Restart" "$RESTART_OUTPUT"

# Invocations log should contain "reanchor" (the restart prompt passed to second invocation)
RESTART_LOG_CONTENT=$(cat "$RESTART_STUB_DIR/invocations.log")
assert_contains "Restart prompt contains reanchor" "reanchor" "$RESTART_LOG_CONTENT"

# After restart loop, lifecycle should be restarting
assert_json "lifecycle is restarting" \
  "$PROJECT_DIR/sessions/restart_test/.state.json" '.lifecycle' 'restarting'

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

assert_file_exists "state.json created by activate" "$CASE5_SESSION/.state.json"
if [ -f "$CASE5_SESSION/.state.json" ]; then
  assert_json "skill set to implement" "$CASE5_SESSION/.state.json" '.skill' 'implement'
  assert_json "lifecycle is completed" "$CASE5_SESSION/.state.json" '.lifecycle' 'completed'
  assert_json "completedSkills contains implement" "$CASE5_SESSION/.state.json" '.completedSkills[0]' 'implement'

  PHASE_HISTORY_LEN=$(jq '.phaseHistory | length' "$CASE5_SESSION/.state.json" 2>/dev/null || echo "0")
  assert_gt "phaseHistory has entries" "$PHASE_HISTORY_LEN" 0
else
  echo "  SKIP: remaining Case 5 assertions (no state file)"
  FAIL=$((FAIL + 4))
fi

echo ""

# --- Case 6: Full lifecycle with all phases ---
echo "--- Case 6: Full lifecycle activate → all phases → deactivate ---"

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

assert_file_exists "state.json exists" "$CASE6_SESSION/.state.json"
if [ -f "$CASE6_SESSION/.state.json" ]; then
  assert_json "skill is test" "$CASE6_SESSION/.state.json" '.skill' 'test'
  assert_json "lifecycle is completed" "$CASE6_SESSION/.state.json" '.lifecycle' 'completed'
  assert_json "currentPhase is 5: Synthesis" "$CASE6_SESSION/.state.json" '.currentPhase' '5: Synthesis'
  assert_json "completedSkills contains test" "$CASE6_SESSION/.state.json" '.completedSkills[0]' 'test'

  CASE6_PH_LEN=$(jq '.phaseHistory | length' "$CASE6_SESSION/.state.json" 2>/dev/null || echo "0")
  assert_gt "phaseHistory has 5+ entries" "$CASE6_PH_LEN" 4

  CASE6_PID=$(jq -r '.pid' "$CASE6_SESSION/.state.json" 2>/dev/null || echo "0")
  assert_gt "PID is set (not 0)" "$CASE6_PID" 0
else
  echo "  SKIP: remaining Case 6 assertions (no state file)"
  FAIL=$((FAIL + 6))
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

assert_contains "SESSION_REQUIRED=1 exported" "SESSION_REQUIRED=1" "$ENV_OUTPUT"
assert_contains "CLAUDE_SUPERVISOR_PID exported" "CLAUDE_SUPERVISOR_PID=" "$ENV_OUTPUT"
assert_contains "WATCHDOG_PID exported" "WATCHDOG_PID=" "$ENV_OUTPUT"

echo ""

# --- Cleanup ---
rm -rf "$TMP_DIR"

# --- Summary ---
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
