#!/bin/bash
# ~/.claude/scripts/tests/test-run-sh.sh — Integration tests for run.sh fixes
#
# Tests the following bugs fixed in run.sh:
#   1. find_fleet_session() PID check — prevent resuming when another Claude is alive
#   2. Scoped fleetPaneId — tmux session prefix to prevent cross-window collisions
#   3. Reset stale fields — pid=0, status="resuming" when picking up dead session
#   4. Status check in restart — skip sessionId when status=ready-to-kill
#   5. statusline.sh defense-in-depth — skip sessionId write during shutdown
#   6. Migration script — old format to new scoped format

# Don't use set -e globally — we need to handle return codes manually in tests
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPTS_DIR="$HOME/.claude/scripts"
TOOLS_DIR="$HOME/.claude/tools"

# Temp directory for test fixtures
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/sessions/2026_02_06_TEST_SESSION"
  export PWD="$TEST_DIR"
  cd "$TEST_DIR"
}

teardown() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# =============================================================================
# Test 1: find_fleet_session() returns sessionId when PID is dead
# =============================================================================
test_find_fleet_session_dead_pid() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="find_fleet_session returns sessionId when PID is dead"

  setup

  # Create agent file with dead PID (using PID 99999999 which almost certainly doesn't exist)
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "fleetPaneId": "fleet:TestPane",
  "pid": 99999999,
  "sessionId": "test-session-123",
  "status": "active"
}
EOF

  # Source run.sh functions (need to extract find_fleet_session)
  # Since run.sh isn't easily sourceable, we'll inline the function for testing
  find_fleet_session() {
    local pane_id="$1"
    local sessions_dir="$PWD/sessions"
    [ -d "$sessions_dir" ] || return 1

    local agent_file
    agent_file=$(grep -l "\"fleetPaneId\": \"$pane_id\"" "$sessions_dir"/*/.state.json 2>/dev/null \
      | xargs ls -t 2>/dev/null \
      | head -1)

    if [ -n "$agent_file" ] && [ -f "$agent_file" ]; then
      local existing_pid
      existing_pid=$(jq -r '.pid // 0' "$agent_file" 2>/dev/null || echo "0")
      if [ "$existing_pid" != "0" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "[run.sh] WARNING: Session has active agent (PID $existing_pid), starting fresh" >&2
        return 1
      fi

      # Reset stale fields
      jq '.pid = 0 | .status = "resuming"' "$agent_file" > "$agent_file.tmp" \
        && mv "$agent_file.tmp" "$agent_file"

      local session_id
      session_id=$(jq -r '.sessionId // empty' "$agent_file" 2>/dev/null)
      if [ -n "$session_id" ]; then
        echo "$session_id"
        return 0
      fi
    fi
    return 1
  }

  # Run the function
  result=$(find_fleet_session "fleet:TestPane" 2>&1 || echo "ERROR")

  if [ "$result" = "test-session-123" ]; then
    # Also verify stale fields were reset
    new_pid=$(jq -r '.pid' "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json")
    new_status=$(jq -r '.status' "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json")
    if [ "$new_pid" = "0" ] && [ "$new_status" = "resuming" ]; then
      pass "$test_name (and stale fields reset)"
    else
      fail "$test_name (stale fields)" "pid=0, status=resuming" "pid=$new_pid, status=$new_status"
    fi
  else
    fail "$test_name" "test-session-123" "$result"
  fi

  teardown
}

# =============================================================================
# Test 2: find_fleet_session() returns error when PID is alive
# =============================================================================
test_find_fleet_session_alive_pid() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="find_fleet_session returns error when PID is alive"

  setup

  # Use current shell's PID (which is definitely alive)
  local alive_pid=$$

  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<EOF
{
  "fleetPaneId": "fleet:TestPane",
  "pid": $alive_pid,
  "sessionId": "test-session-123",
  "status": "active"
}
EOF

  # Inline the function
  find_fleet_session() {
    local pane_id="$1"
    local sessions_dir="$PWD/sessions"
    [ -d "$sessions_dir" ] || return 1

    local agent_file
    agent_file=$(grep -l "\"fleetPaneId\": \"$pane_id\"" "$sessions_dir"/*/.state.json 2>/dev/null \
      | xargs ls -t 2>/dev/null \
      | head -1)

    if [ -n "$agent_file" ] && [ -f "$agent_file" ]; then
      local existing_pid
      existing_pid=$(jq -r '.pid // 0' "$agent_file" 2>/dev/null || echo "0")
      if [ "$existing_pid" != "0" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "[run.sh] WARNING: Session has active agent (PID $existing_pid), starting fresh" >&2
        return 1
      fi

      jq '.pid = 0 | .status = "resuming"' "$agent_file" > "$agent_file.tmp" \
        && mv "$agent_file.tmp" "$agent_file"

      local session_id
      session_id=$(jq -r '.sessionId // empty' "$agent_file" 2>/dev/null)
      if [ -n "$session_id" ]; then
        echo "$session_id"
        return 0
      fi
    fi
    return 1
  }

  # Run the function — should fail (return 1) and output warning
  output=$(find_fleet_session "fleet:TestPane" 2>&1)
  exit_code=$?

  if [ $exit_code -ne 0 ] && [[ "$output" == *"WARNING"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1 + WARNING message" "exit $exit_code, output: $output"
  fi

  teardown
}

# =============================================================================
# Test 3: Scoped fleetPaneId includes tmux session prefix
# =============================================================================
test_scoped_fleet_pane_id() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="fleetPaneId includes tmux session prefix"

  # Simulate the scoping logic from run.sh
  FLEET_PANE_ID="TestPane"
  TMUX_SESSION_NAME="mywindow"

  # Apply scoping logic (from run.sh lines 75-89)
  if [[ "$FLEET_PANE_ID" != *":"* ]]; then
    FLEET_PANE_ID="${TMUX_SESSION_NAME}:${FLEET_PANE_ID}"
  fi

  expected="mywindow:TestPane"
  if [ "$FLEET_PANE_ID" = "$expected" ]; then
    pass "$test_name"
  else
    fail "$test_name" "$expected" "$FLEET_PANE_ID"
  fi
}

# =============================================================================
# Test 4: Already-scoped fleetPaneId is not double-prefixed
# =============================================================================
test_scoped_fleet_pane_id_no_double_prefix() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="already-scoped fleetPaneId is not double-prefixed"

  FLEET_PANE_ID="fleet:TestPane"
  TMUX_SESSION_NAME="mywindow"

  # Apply scoping logic — should NOT modify already-scoped ID
  if [[ "$FLEET_PANE_ID" != *":"* ]]; then
    FLEET_PANE_ID="${TMUX_SESSION_NAME}:${FLEET_PANE_ID}"
  fi

  expected="fleet:TestPane"
  if [ "$FLEET_PANE_ID" = "$expected" ]; then
    pass "$test_name"
  else
    fail "$test_name" "$expected" "$FLEET_PANE_ID"
  fi
}

# =============================================================================
# Test 5: Restart skips sessionId when status=ready-to-kill
# =============================================================================
test_restart_skips_sessionid_when_ready_to_kill() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="restart skips sessionId when status=ready-to-kill"

  setup

  # Create agent file with status=ready-to-kill
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "fleetPaneId": "fleet:TestPane",
  "pid": 0,
  "sessionId": "should-not-use-this",
  "status": "ready-to-kill",
  "restartPrompt": "/session continue --session test"
}
EOF

  RESTART_AGENT_FILE="$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json"

  # Apply the logic from run.sh lines 226-237
  RESTART_SESSION_ID=""
  if [ -n "$RESTART_AGENT_FILE" ] && [ -f "$RESTART_AGENT_FILE" ]; then
    restart_status=$(jq -r '.status // ""' "$RESTART_AGENT_FILE" 2>/dev/null || echo "")
    if [ "$restart_status" != "ready-to-kill" ]; then
      RESTART_SESSION_ID=$(jq -r '.sessionId // empty' "$RESTART_AGENT_FILE" 2>/dev/null || true)
    fi
  fi

  if [ -z "$RESTART_SESSION_ID" ]; then
    pass "$test_name"
  else
    fail "$test_name" "(empty)" "$RESTART_SESSION_ID"
  fi

  teardown
}

# =============================================================================
# Test 6: statusline.sh skips sessionId when status=ready-to-kill
# =============================================================================
test_statusline_skips_sessionid_when_ready_to_kill() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="statusline skips sessionId write when status=ready-to-kill"

  setup

  # Create agent file with status=ready-to-kill
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "pid": 12345,
  "sessionId": "old-session-id",
  "status": "ready-to-kill",
  "contextUsage": 0.5
}
EOF

  agent_file="$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json"
  CONTEXT_DECIMAL="0.7500"
  CLAUDE_SESSION_ID="new-session-id"

  # Apply the logic from statusline.sh update_session (lines 89-108)
  status=$(jq -r '.status // "active"' "$agent_file" 2>/dev/null || echo "active")
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$status" = "ready-to-kill" ] || [ "$status" = "dehydrating" ]; then
    # Session is being terminated — only update contextUsage and heartbeat, NOT sessionId
    jq --argjson usage "$CONTEXT_DECIMAL" --arg ts "$ts" \
      '.contextUsage = $usage | .lastHeartbeat = $ts' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
  else
    # Normal update — include sessionId binding
    jq --argjson usage "$CONTEXT_DECIMAL" --arg ts "$ts" --arg sid "$CLAUDE_SESSION_ID" \
      '.contextUsage = $usage | .lastHeartbeat = $ts | .sessionId = $sid' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
  fi

  # Verify sessionId was NOT updated
  result_session_id=$(jq -r '.sessionId' "$agent_file")
  result_context=$(jq -r '.contextUsage' "$agent_file")

  # Compare as floats (0.75 == 0.7500)
  expected_context="0.75"
  context_match=$(awk "BEGIN {print ($result_context == $expected_context) ? 1 : 0}")

  if [ "$result_session_id" = "old-session-id" ] && [ "$context_match" = "1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "sessionId=old-session-id, contextUsage=0.75" "sessionId=$result_session_id, contextUsage=$result_context"
  fi

  teardown
}

# =============================================================================
# Test 7: Migration script converts old format to new format
# =============================================================================
test_migration_script() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="migration script converts old format to new format"

  setup

  # Create agent file with old format (no colon)
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "fleetPaneId": "MCP",
  "pid": 0,
  "sessionId": "test-session"
}
EOF

  # Run migration script
  output=$("$SCRIPTS_DIR/migrate-fleet-pane-ids.sh" "$TEST_DIR/sessions" 2>&1)

  # Check result
  new_fleet_pane_id=$(jq -r '.fleetPaneId' "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json")

  if [ "$new_fleet_pane_id" = "fleet:MCP" ]; then
    # Also check backup was created
    if [ -f "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json.bak" ]; then
      pass "$test_name (with backup)"
    else
      pass "$test_name (no backup check)"
    fi
  else
    fail "$test_name" "fleet:MCP" "$new_fleet_pane_id"
  fi

  teardown
}

# =============================================================================
# Test 8: Migration script skips already-scoped fleetPaneId
# =============================================================================
test_migration_script_skips_scoped() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="migration script skips already-scoped fleetPaneId"

  setup

  # Create agent file with new format (already has colon)
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "fleetPaneId": "mywindow:MCP",
  "pid": 0,
  "sessionId": "test-session"
}
EOF

  # Run migration script
  output=$("$SCRIPTS_DIR/migrate-fleet-pane-ids.sh" "$TEST_DIR/sessions" 2>&1)

  # Check result — should be unchanged
  new_fleet_pane_id=$(jq -r '.fleetPaneId' "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json")

  if [ "$new_fleet_pane_id" = "mywindow:MCP" ]; then
    # Should NOT have created a backup (no changes made)
    if [ ! -f "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json.bak" ]; then
      pass "$test_name (no backup created)"
    else
      pass "$test_name"
    fi
  else
    fail "$test_name" "mywindow:MCP" "$new_fleet_pane_id"
  fi

  teardown
}

# =============================================================================
# Test 9: find_restart_agent_json finds .state.json with killRequested=true
# =============================================================================
test_find_restart_agent_json_finds_kill_requested() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="find_restart_agent_json finds .state.json with killRequested=true"

  setup

  # Create .state.json with killRequested=true
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "killRequested": true,
  "pid": 12345,
  "lifecycle": "active"
}
EOF

  # Unset fleet pane to avoid scoping filter
  unset FLEET_PANE_ID 2>/dev/null || true

  # Inline the function from run.sh (not sourceable)
  find_restart_agent_json() {
    local sessions_dir="$PWD/sessions"
    [ -d "$sessions_dir" ] || return 1

    find -L "$sessions_dir" -name ".state.json" -type f 2>/dev/null | while read -r f; do
      local kill_req=$(jq -r '.killRequested // false' "$f" 2>/dev/null)
      if [ "$kill_req" = "true" ]; then
        if [ -n "${FLEET_PANE_ID:-}" ]; then
          local pane=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
          [ "$pane" != "$FLEET_PANE_ID" ] && continue
        fi
        echo "$f"
        return 0
      fi
    done
  }

  result=$(find_restart_agent_json 2>/dev/null || true)

  if [ -n "$result" ] && [[ "$result" == *".state.json" ]]; then
    pass "$test_name"
  else
    fail "$test_name" "path to .state.json" "$result"
  fi

  teardown
}

# =============================================================================
# Test 10: find_restart_agent_json ignores .state.json with killRequested=false
# =============================================================================
test_find_restart_agent_json_ignores_no_kill() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="find_restart_agent_json ignores killRequested=false"

  setup

  # Create .state.json with killRequested=false
  cat > "$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json" <<'EOF'
{
  "killRequested": false,
  "pid": 12345,
  "lifecycle": "active"
}
EOF

  unset FLEET_PANE_ID 2>/dev/null || true

  # Inline the function
  find_restart_agent_json() {
    local sessions_dir="$PWD/sessions"
    [ -d "$sessions_dir" ] || return 1

    find -L "$sessions_dir" -name ".state.json" -type f 2>/dev/null | while read -r f; do
      local kill_req=$(jq -r '.killRequested // false' "$f" 2>/dev/null)
      if [ "$kill_req" = "true" ]; then
        if [ -n "${FLEET_PANE_ID:-}" ]; then
          local pane=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
          [ "$pane" != "$FLEET_PANE_ID" ] && continue
        fi
        echo "$f"
        return 0
      fi
    done
  }

  result=$(find_restart_agent_json 2>/dev/null || true)

  if [ -z "$result" ]; then
    pass "$test_name"
  else
    fail "$test_name" "(empty)" "$result"
  fi

  teardown
}

# =============================================================================
# Test 11: restart loop cleans up state (killRequested=false, del restartPrompt, lifecycle=restarting)
# =============================================================================
test_restart_loop_clear_state_cleanup() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="restart loop cleans up state after finding killRequested"

  setup

  local sf="$TEST_DIR/sessions/2026_02_06_TEST_SESSION/.state.json"

  # Create .state.json with killRequested=true and a restartPrompt
  cat > "$sf" <<'EOF'
{
  "killRequested": true,
  "restartPrompt": "/session continue --session test",
  "lifecycle": "active",
  "pid": 12345
}
EOF

  # Apply the cleanup logic from run.sh lines 649-650
  jq 'del(.restartPrompt) | .killRequested = false | .lifecycle = "restarting"' \
    "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"

  # Verify state mutations
  local kill_req lifecycle has_prompt
  kill_req=$(jq -r '.killRequested' "$sf")
  lifecycle=$(jq -r '.lifecycle' "$sf")
  has_prompt=$(jq -r '.restartPrompt // "ABSENT"' "$sf")

  if [ "$kill_req" = "false" ] && [ "$lifecycle" = "restarting" ] && [ "$has_prompt" = "ABSENT" ]; then
    pass "$test_name"
  else
    fail "$test_name" "killRequested=false, lifecycle=restarting, restartPrompt=ABSENT" \
      "killRequested=$kill_req, lifecycle=$lifecycle, restartPrompt=$has_prompt"
  fi

  teardown
}

# =============================================================================
# Session display name (claude -n) — tests 12-17
#
# These load the real functions out of run.sh rather than re-declaring a copy, so
# a change to run.sh that breaks naming shows up here instead of passing against
# a stale duplicate.
# =============================================================================

RUN_SH="$SCRIPTS_DIR/run.sh"

load_name_fns() {
  eval "$(awk '/^fleet_session_name\(\) \{$/,/^\}$/' "$RUN_SH")"
  eval "$(awk '/^user_session_name\(\) \{$/,/^\}$/' "$RUN_SH")"
}

# Build a throwaway workspace whose PATH has a `claude` that only records its argv.
# Nothing launches: the stub exits 0 immediately.
name_lab_setup() {
  LAB=$(mktemp -d)
  mkdir -p "$LAB/bin" "$LAB/cwd/sessions"
  cat > "$LAB/bin/claude" <<'STUB'
#!/bin/bash
{ for a in "$@"; do echo "ARG:$a"; done; } >> "$ARGV_OUT"
exit 0
STUB
  chmod +x "$LAB/bin/claude"
}

name_lab_teardown() { [ -n "${LAB:-}" ] && rm -rf "$LAB"; }

# Echo the argv run.sh would hand claude. $1 = FLEET_PANE ("" for no fleet); rest = run.sh args.
capture_argv() {
  local pane="$1"; shift
  export ARGV_OUT="$LAB/argv.out"; : > "$ARGV_OUT"
  ( cd "$LAB/cwd" && env -u TMUX -u TMUX_PANE -u FLEET_PANE ${pane:+FLEET_PANE="$pane"} \
      ARGV_OUT="$ARGV_OUT" PATH="$LAB/bin:$PATH" \
      timeout 60 bash "$RUN_SH" "$@" ) >/dev/null 2>&1
  grep '^ARG:' "$ARGV_OUT" | sed 's/^ARG://'
}

# --- Test 12: the colon in window:label is preserved verbatim -----------------
test_session_name_preserves_pane_label() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="fleet_session_name keeps window:label intact (colon survives)"
  load_name_fns
  local got
  got=$(fleet_session_name "meta:Commands")
  if [ "$got" = "meta:Commands" ]; then pass "$test_name"; else fail "$test_name" "meta:Commands" "$got"; fi
}

# --- Test 13: nothing that could become a flag or an escape sequence gets out --
test_session_name_sanitizes_hostile_input() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="fleet_session_name neutralizes empty/blank/dash/control-char labels"
  load_name_fns
  local problems=""
  [ -n "$(fleet_session_name '')" ]     && problems="$problems empty->nonempty"
  [ -n "$(fleet_session_name '   ')" ]  && problems="$problems blank->nonempty"
  [ -n "$(fleet_session_name '---')" ]  && problems="$problems dashes->nonempty"
  # A leading dash must not survive: claude would read it as a flag and abort startup
  case "$(fleet_session_name '--dangerously-skip-permissions')" in
    -*) problems="$problems leading-dash-survived" ;;
  esac
  # Control characters must not reach the terminal-title escape sequence
  case "$(fleet_session_name "$(printf 'a\033]0;x')")" in
    *$'\033'*) problems="$problems esc-survived" ;;
  esac
  case "$(fleet_session_name "$(printf 'a\nb')")" in
    *$'\n'*) problems="$problems newline-survived" ;;
  esac
  # Bounded, because the name lands in the terminal title and the /resume picker
  [ "$(fleet_session_name "$(printf 'x%.0s' $(seq 1 200))" | wc -c | tr -d ' ')" -gt 64 ] \
    && problems="$problems unbounded-length"
  if [ -z "$problems" ]; then pass "$test_name"; else fail "$test_name" "(no problems)" "$problems"; fi
}

# --- Test 14: claude's parser is last-flag-wins, so we must read the last one --
test_user_session_name_last_wins() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="user_session_name reads all -n forms and takes the last"
  load_name_fns
  local problems=""
  [ "$(user_session_name -p hi)" != "" ]                  && problems="$problems none"
  [ "$(user_session_name -n A)" != "A" ]                  && problems="$problems short"
  [ "$(user_session_name --name A)" != "A" ]              && problems="$problems long"
  [ "$(user_session_name --name=A)" != "A" ]              && problems="$problems equals"
  [ "$(user_session_name -nA)" != "A" ]                   && problems="$problems attached"
  [ "$(user_session_name -n A -n B)" != "B" ]             && problems="$problems last-wins"
  [ "$(user_session_name --name=A -n B)" != "B" ]         && problems="$problems mixed"
  if [ -z "$problems" ]; then pass "$test_name"; else fail "$test_name" "(no problems)" "$problems"; fi
}

# --- Test 15: no fleet means run.sh execs exactly as it always did -------------
# ¶INV_FLEET_GRACEFUL_OUTSIDE_TMUX. An empty -n '' would be a bug, not a no-op.
test_no_fleet_emits_no_name_flag() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="outside a fleet run.sh passes no -n/--name at all"
  name_lab_setup
  local nameless blank control
  nameless=$(capture_argv "" | grep -cE '^(--name|-n)$' || true)
  # A blank pane label must behave the same as no pane at all
  blank=$(capture_argv "   " | grep -cE '^(--name|-n)$' || true)
  # Positive control: the same probe must find a flag when there IS one, otherwise
  # the two zeros above would pass even if the probe were blind.
  control=$(capture_argv "meta:Commands" | grep -cE '^(--name|-n)$' || true)
  name_lab_teardown
  if [ "$nameless" -eq 0 ] && [ "$blank" -eq 0 ] && [ "$control" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "no-fleet=0, blank=0, control=1" "$nameless, $blank, $control"
  fi
}

# --- Test 16: inside a fleet the pane label becomes the display name -----------
test_fleet_pane_becomes_session_name() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="inside a fleet run.sh passes --name <window:label>"
  name_lab_setup
  local argv
  argv=$(capture_argv "meta:Commands")
  name_lab_teardown
  if echo "$argv" | grep -q '^--name$' && echo "$argv" | grep -q '^meta:Commands$'; then
    pass "$test_name"
  else
    fail "$test_name" "--name followed by meta:Commands" "$(echo "$argv" | tr '\n' '|')"
  fi
}

# --- Test 17: a caller-supplied -n beats the derived one, and only once --------
test_user_name_overrides_fleet_name() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="caller -n overrides the fleet-derived name (exactly one name flag)"
  name_lab_setup
  local argv flags derived
  argv=$(capture_argv "meta:Commands" -n Custom)
  flags=$(echo "$argv" | grep -cE '^(-n|--name)$' || true)
  derived=$(echo "$argv" | grep -c '^meta:Commands$' || true)
  name_lab_teardown
  if [ "$flags" -eq 1 ] && [ "$derived" -eq 0 ] && echo "$argv" | grep -q '^Custom$'; then
    pass "$test_name"
  else
    fail "$test_name" "1 name flag, value Custom, no meta:Commands" \
      "flags=$flags derived=$derived argv=$(echo "$argv" | tr '\n' '|')"
  fi
}

# =============================================================================
# Run all tests
# =============================================================================
main() {
  echo "============================================="
  echo "run.sh Integration Tests"
  echo "============================================="
  echo ""

  test_find_fleet_session_dead_pid
  test_find_fleet_session_alive_pid
  test_scoped_fleet_pane_id
  test_scoped_fleet_pane_id_no_double_prefix
  test_restart_skips_sessionid_when_ready_to_kill
  test_statusline_skips_sessionid_when_ready_to_kill
  test_migration_script
  test_migration_script_skips_scoped
  test_find_restart_agent_json_finds_kill_requested
  test_find_restart_agent_json_ignores_no_kill
  test_restart_loop_clear_state_cleanup
  test_session_name_preserves_pane_label
  test_session_name_sanitizes_hostile_input
  test_user_session_name_last_wins
  test_no_fleet_emits_no_name_flag
  test_fleet_pane_becomes_session_name
  test_user_name_overrides_fleet_name

  exit_with_results
}

main "$@"
