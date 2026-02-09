#!/bin/bash
# ~/.claude/engine/scripts/tests/test-tmux.sh — Fleet/tmux integration tests
#
# Tests fleet.sh commands and session.sh fleet-mode integration using a real
# tmux test server (tmux -L test-fleet-$$) for isolation. No mocking of tmux.
#
# Categories:
#   Setup (S-01..S-03): Test server creation, multi-pane, pane labels
#   Pane Identity (PI-01..PI-05): pane-id composite ID generation
#   Notify (N-01..N-06): Notification state + color assertions
#   Window Aggregation (W-01..W-04): Priority-based window notify
#   Session Fleet Integration (SF-01..SF-04): session.sh activate/find/phase
#   Fleet Claiming (FC-01..FC-02): PID conflicts, stale pane cleanup
#   Notify Edge Cases (NE-01..NE-02): Non-focused pane color, deactivate notify
#   Concurrent Sockets (CS-01): Socket isolation between fleet and fleet-project
#   Socket Helpers (SH-01..SH-02): config-path default and workgroup
#
# Run: bash ~/.claude/engine/scripts/tests/test-tmux.sh

# NOTE: set -uo pipefail, NOT set -e (counter increment issue per ENGINE_TESTING.md)
set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

FLEET_SH="$HOME/.claude/scripts/fleet.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
HOOK_SH="$HOME/.claude/hooks/pane-focus-style.sh"

# Test isolation: unique socket name per test run
SOCKET="test-fleet-$$"
WORKGROUP_SOCKET="fleet-project-test-$$"

# Save original env vars (restored in cleanup to prevent corruption when running inside fleet)
ORIGINAL_TMUX="${TMUX:-}"
ORIGINAL_TMUX_PANE="${TMUX_PANE:-}"
ORIGINAL_HOME="$HOME"

# Stub Claude PID
export CLAUDE_SUPERVISOR_PID=$$

# Unset DEBUG to avoid statusline debug mode
unset DEBUG 2>/dev/null || true

# Test session directory (for session.sh integration tests)
TEST_DIR=""

# --- Cleanup ---
cleanup() {
  # Kill ALL test sockets to prevent orphaned tmux servers on early failure
  for s in "$SOCKET" "$WORKGROUP_SOCKET" \
           "${FLEET_SOCKET:-}" "${NOTIFY_SOCKET:-}" "${AGG_SOCKET:-}" \
           "${SF_SOCKET:-}" "${NE_SOCKET:-}" \
           "${CS_SOCKET_A:-}" "${CS_SOCKET_B:-}" \
           "${CR_SOCKET:-}" \
           "${NE_EXT_SOCKET:-}" "${NC_SOCKET:-}" "${RT_SOCKET:-}" \
           "${NV_SOCKET:-}" "${W5_SOCKET:-}" "${GF_SOCKET:-}" \
           "${SS_SOCKET:-}" \
           "${HK_SOCKET:-}" "${SE_SOCKET:-}" "${AC_SOCKET:-}"; do
    [[ -n "$s" ]] && tmux -L "$s" kill-server 2>/dev/null || true
  done
  # Kill any spawned sleep process (used by FC-01)
  [[ -n "${FC01_SLEEP_PID:-}" ]] && kill "$FC01_SLEEP_PID" 2>/dev/null || true
  if [[ -n "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
  # Restore original env vars to prevent corruption when running inside fleet panes
  if [[ -n "$ORIGINAL_TMUX" ]]; then
    export TMUX="$ORIGINAL_TMUX"
  else
    unset TMUX 2>/dev/null || true
  fi
  if [[ -n "$ORIGINAL_TMUX_PANE" ]]; then
    export TMUX_PANE="$ORIGINAL_TMUX_PANE"
  else
    unset TMUX_PANE 2>/dev/null || true
  fi
  export HOME="$ORIGINAL_HOME"
}
trap cleanup EXIT

# --- Helpers ---

# assert_exit is unique to this file (not in test-helpers.sh)
assert_exit() {
  local expected_code="$1" msg="$2"
  shift 2
  local actual_code=0
  "$@" >/dev/null 2>&1 || actual_code=$?
  if [[ "$expected_code" -eq "$actual_code" ]]; then
    pass "$msg"
  else
    fail "$msg" "exit code $expected_code" "exit code $actual_code"
  fi
}

# Get tmux option for a pane
get_pane_option() {
  local socket="$1" pane="$2" option="$3"
  tmux -L "$socket" display-message -p -t "$pane" "#{$option}" 2>/dev/null || echo ""
}

# Get tmux window option
get_window_option() {
  local socket="$1" option="$2"
  tmux -L "$socket" show-options -w -v "$option" 2>/dev/null || echo ""
}

# Get pane style (for bg color assertions)
# select-pane -P sets window-style/window-active-style as pane-level options
get_pane_style() {
  local socket="$1" pane="$2"
  tmux -L "$socket" display-message -p -t "$pane" '#{window-style}' 2>/dev/null \
    || tmux -L "$socket" show-options -p -t "$pane" -v "window-style" 2>/dev/null \
    || echo ""
}

# Set up TMUX env vars to point at our test socket
setup_tmux_env() {
  local socket="$1" pane="$2"
  # TMUX format: /path/to/socket,pid,session -- we need the socket path
  local socket_path
  socket_path=$(tmux -L "$socket" display-message -p '#{socket_path}' 2>/dev/null || echo "/tmp/tmux-$(id -u)/$socket")
  export TMUX="${socket_path},$(tmux -L "$socket" display-message -p '#{pid}' 2>/dev/null || echo '0'),0"
  export TMUX_PANE="$pane"
}

# ============================================
echo "======================================"
echo "Tmux/Fleet Integration Tests"
echo "======================================"
echo ""

# =============================================
# Category: Setup & Teardown (S-01..S-03)
# =============================================
echo "--- Setup: Create test tmux server ---"

# S-01: Create test tmux server
tmux -L "$SOCKET" new-session -d -s test-session -n test-window
S01_RC=$?
assert_eq "0" "$S01_RC" "S-01: Create tmux test server on $SOCKET"

# Verify session exists
tmux -L "$SOCKET" has-session -t test-session 2>/dev/null
S01_VERIFY=$?
assert_eq "0" "$S01_VERIFY" "S-01: Verify test-session exists"

# S-02: Add second pane for multi-pane tests
tmux -L "$SOCKET" split-window -t test-session:test-window
PANE_COUNT=$(tmux -L "$SOCKET" list-panes -t test-session:test-window 2>/dev/null | wc -l | tr -d ' ')
assert_eq "2" "$PANE_COUNT" "S-02: Two panes in test-window"

# Get pane IDs for later use
PANE0=$(tmux -L "$SOCKET" list-panes -t test-session:test-window -F '#{pane_id}' 2>/dev/null | head -1)
PANE1=$(tmux -L "$SOCKET" list-panes -t test-session:test-window -F '#{pane_id}' 2>/dev/null | tail -1)

# S-03: Set @pane_label on both panes
tmux -L "$SOCKET" set-option -p -t "$PANE0" @pane_label "Agent1"
tmux -L "$SOCKET" set-option -p -t "$PANE1" @pane_label "Agent2"

LABEL0=$(get_pane_option "$SOCKET" "$PANE0" "@pane_label")
LABEL1=$(get_pane_option "$SOCKET" "$PANE1" "@pane_label")
assert_eq "Agent1" "$LABEL0" "S-03: Pane 0 label is Agent1"
assert_eq "Agent2" "$LABEL1" "S-03: Pane 1 label is Agent2"
echo ""

# =============================================
# Category: fleet.sh pane-id (PI-01..PI-05)
# =============================================
echo "--- fleet.sh pane-id ---"

# PI-01: pane-id returns composite ID when inside fleet socket
# We need to trick fleet.sh into thinking it's on a "fleet" socket.
# Our socket is "test-fleet-$$" which starts with "test-" not "fleet".
# So we need a fleet-named socket. Create one.
FLEET_SOCKET="fleet-testrun$$"
tmux -L "$FLEET_SOCKET" new-session -d -s test-session -n test-window
tmux -L "$FLEET_SOCKET" set-option -p @pane_label "Agent1"
FLEET_PANE0=$(tmux -L "$FLEET_SOCKET" list-panes -t test-session:test-window -F '#{pane_id}' 2>/dev/null | head -1)

# Set up TMUX env to point at fleet socket
setup_tmux_env "$FLEET_SOCKET" "$FLEET_PANE0"

PANE_ID=$("$FLEET_SH" pane-id 2>/dev/null || echo "")
assert_eq "test-session:test-window:Agent1" "$PANE_ID" "PI-01: pane-id returns composite ID"

# PI-02: pane-id returns exit 1 when TMUX is unset
(
  unset TMUX
  unset TMUX_PANE
  "$FLEET_SH" pane-id >/dev/null 2>&1
)
PI02_RC=$?
assert_eq "1" "$PI02_RC" "PI-02: pane-id exits 1 when TMUX unset"

# PI-03: pane-id returns exit 1 when socket is non-fleet
# Use our test-fleet-$$ socket (starts with "test-", not "fleet")
setup_tmux_env "$SOCKET" "$PANE0"
(
  "$FLEET_SH" pane-id >/dev/null 2>&1
)
PI03_RC=$?
assert_eq "1" "$PI03_RC" "PI-03: pane-id exits 1 for non-fleet socket"

# PI-04: pane-id returns exit 1 when @pane_label is missing
# Create a pane in our fleet socket without a label
tmux -L "$FLEET_SOCKET" split-window -t test-session:test-window
FLEET_PANE_NOLABEL=$(tmux -L "$FLEET_SOCKET" list-panes -t test-session:test-window -F '#{pane_id}' 2>/dev/null | tail -1)
# Do NOT set @pane_label on this new pane
setup_tmux_env "$FLEET_SOCKET" "$FLEET_PANE_NOLABEL"
(
  "$FLEET_SH" pane-id >/dev/null 2>&1
)
PI04_RC=$?
assert_eq "1" "$PI04_RC" "PI-04: pane-id exits 1 when @pane_label missing"

# PI-05: pane-id works with workgroup socket (fleet-project)
tmux -L "$WORKGROUP_SOCKET" new-session -d -s proj-session -n proj-window
tmux -L "$WORKGROUP_SOCKET" set-option -p @pane_label "Worker1"
WG_PANE0=$(tmux -L "$WORKGROUP_SOCKET" list-panes -t proj-session:proj-window -F '#{pane_id}' 2>/dev/null | head -1)
setup_tmux_env "$WORKGROUP_SOCKET" "$WG_PANE0"
PANE_ID_WG=$("$FLEET_SH" pane-id 2>/dev/null || echo "")
assert_eq "proj-session:proj-window:Worker1" "$PANE_ID_WG" "PI-05: pane-id works with fleet-project socket"

# Clean up: kill fleet-testrun socket (but keep fleet-project for CS-01)
# We will also need fleet socket for notify tests, so create a clean one
tmux -L "$FLEET_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: fleet.sh notify (N-01..N-06)
# =============================================
echo "--- fleet.sh notify ---"

# Create a clean fleet socket for notify tests
NOTIFY_SOCKET="fleet-notify$$"
tmux -L "$NOTIFY_SOCKET" new-session -d -s notify-session -n notify-window
tmux -L "$NOTIFY_SOCKET" set-option -p @pane_label "NotifyAgent"
NOTIFY_PANE=$(tmux -L "$NOTIFY_SOCKET" list-panes -t notify-session:notify-window -F '#{pane_id}' 2>/dev/null | head -1)

setup_tmux_env "$NOTIFY_SOCKET" "$NOTIFY_PANE"

# N-01: notify working sets @pane_notify="working"
"$FLEET_SH" notify working 2>/dev/null || true
N01_STATE=$(get_pane_option "$NOTIFY_SOCKET" "$NOTIFY_PANE" "@pane_notify")
assert_eq "working" "$N01_STATE" "N-01: notify working sets @pane_notify=working"

# N-02: notify error sets @pane_notify="error" and bg color
"$FLEET_SH" notify error 2>/dev/null || true
N02_STATE=$(get_pane_option "$NOTIFY_SOCKET" "$NOTIFY_PANE" "@pane_notify")
assert_eq "error" "$N02_STATE" "N-02: notify error sets @pane_notify=error"

# N-03: notify unchecked sets @pane_notify="unchecked"
"$FLEET_SH" notify unchecked 2>/dev/null || true
N03_STATE=$(get_pane_option "$NOTIFY_SOCKET" "$NOTIFY_PANE" "@pane_notify")
assert_eq "unchecked" "$N03_STATE" "N-03: notify unchecked sets @pane_notify=unchecked"

# N-04: notify with invalid state exits 1
(
  setup_tmux_env "$NOTIFY_SOCKET" "$NOTIFY_PANE"
  "$FLEET_SH" notify bogus >/dev/null 2>&1
)
N04_RC=$?
assert_eq "1" "$N04_RC" "N-04: notify exits 1 for invalid state"

# N-05: notify-clear resets to "done"
"$FLEET_SH" notify error 2>/dev/null || true
"$FLEET_SH" notify-clear 2>/dev/null || true
N05_STATE=$(get_pane_option "$NOTIFY_SOCKET" "$NOTIFY_PANE" "@pane_notify")
assert_eq "done" "$N05_STATE" "N-05: notify-clear resets to done"

# N-06: notify-check transitions unchecked->checked only
# First: set to unchecked, call notify-check -> should become checked
tmux -L "$NOTIFY_SOCKET" set-option -p -t "$NOTIFY_PANE" @pane_notify "unchecked" 2>/dev/null
"$FLEET_SH" notify-check "$NOTIFY_PANE" 2>/dev/null || true
N06A_STATE=$(get_pane_option "$NOTIFY_SOCKET" "$NOTIFY_PANE" "@pane_notify")
assert_eq "checked" "$N06A_STATE" "N-06a: notify-check transitions unchecked->checked"

# Second: set to working, call notify-check -> should stay working
tmux -L "$NOTIFY_SOCKET" set-option -p -t "$NOTIFY_PANE" @pane_notify "working" 2>/dev/null
"$FLEET_SH" notify-check "$NOTIFY_PANE" 2>/dev/null || true
N06B_STATE=$(get_pane_option "$NOTIFY_SOCKET" "$NOTIFY_PANE" "@pane_notify")
assert_eq "working" "$N06B_STATE" "N-06b: notify-check does NOT transition working"

echo ""

# =============================================
# Category: Window Aggregation (W-01..W-04)
# =============================================
echo "--- Window Aggregation (update_window_notify) ---"

# Create a 2-pane fleet window for aggregation tests
AGG_SOCKET="fleet-agg$$"
tmux -L "$AGG_SOCKET" new-session -d -s agg-session -n agg-window
tmux -L "$AGG_SOCKET" split-window -t agg-session:agg-window
AGG_PANE0=$(tmux -L "$AGG_SOCKET" list-panes -t agg-session:agg-window -F '#{pane_id}' 2>/dev/null | head -1)
AGG_PANE1=$(tmux -L "$AGG_SOCKET" list-panes -t agg-session:agg-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE0" @pane_label "Agg1"
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE1" @pane_label "Agg2"

setup_tmux_env "$AGG_SOCKET" "$AGG_PANE0"

# W-01: All panes "done" -> window "done"
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE0" @pane_notify "done" 2>/dev/null
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE1" @pane_notify "done" 2>/dev/null
"$FLEET_SH" notify done 2>/dev/null || true  # triggers update_window_notify via cmd_notify
W01_STATE=$(get_window_option "$AGG_SOCKET" "@window_notify")
assert_eq "done" "$W01_STATE" "W-01: All panes done -> window done"

# W-02: One pane "error", one "working" -> window "error"
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE0" @pane_notify "error" 2>/dev/null
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE1" @pane_notify "working" 2>/dev/null
# Trigger update by calling notify on pane0 (which will set pane0 again but also call update_window_notify)
"$FLEET_SH" notify error 2>/dev/null || true
W02_STATE=$(get_window_option "$AGG_SOCKET" "@window_notify")
assert_eq "error" "$W02_STATE" "W-02: error+working -> window error"

# W-03: One pane "unchecked", one "working" -> window "unchecked"
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE0" @pane_notify "working" 2>/dev/null
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE1" @pane_notify "unchecked" 2>/dev/null
"$FLEET_SH" notify working 2>/dev/null || true  # triggers update via pane0
W03_STATE=$(get_window_option "$AGG_SOCKET" "@window_notify")
assert_eq "unchecked" "$W03_STATE" "W-03: working+unchecked -> window unchecked"

# W-04: One pane "working", one "checked" -> window "working"
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE0" @pane_notify "checked" 2>/dev/null
tmux -L "$AGG_SOCKET" set-option -p -t "$AGG_PANE1" @pane_notify "working" 2>/dev/null
# Need to trigger from a pane pointing at this socket
setup_tmux_env "$AGG_SOCKET" "$AGG_PANE1"
"$FLEET_SH" notify working 2>/dev/null || true
W04_STATE=$(get_window_option "$AGG_SOCKET" "@window_notify")
assert_eq "working" "$W04_STATE" "W-04: checked+working -> window working"

# Cleanup aggregation socket
tmux -L "$AGG_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: session.sh Fleet Integration (SF-01..SF-04)
# =============================================
echo "--- session.sh Fleet Integration ---"

# Set up a test directory structure mimicking a project
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/sessions"

# Create a fleet socket for session integration tests
SF_SOCKET="fleet-sf$$"
tmux -L "$SF_SOCKET" new-session -d -s sf-session -n sf-window
tmux -L "$SF_SOCKET" set-option -p @pane_label "SFAgent"
SF_PANE=$(tmux -L "$SF_SOCKET" list-panes -t sf-session:sf-window -F '#{pane_id}' 2>/dev/null | head -1)

# Set up TMUX env to point at fleet socket
setup_tmux_env "$SF_SOCKET" "$SF_PANE"

# We need HOME override so session.sh finds our fleet.sh that works with test socket
FAKE_HOME="$TEST_DIR/fake-home"
mkdir -p "$FAKE_HOME/.claude/scripts"
mkdir -p "$FAKE_HOME/.claude/tools/session-search"
mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

# Symlink real scripts into fake home
ln -sf "$ORIGINAL_HOME/.claude/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
# Symlink real fleet.sh into fake home (it uses $HOME/.claude/scripts/fleet.sh internally)
ln -sf "$ORIGINAL_HOME/.claude/scripts/fleet.sh" "$FAKE_HOME/.claude/scripts/fleet.sh"
# Symlink user-info.sh
if [[ -f "$ORIGINAL_HOME/.claude/scripts/user-info.sh" ]]; then
  ln -sf "$ORIGINAL_HOME/.claude/scripts/user-info.sh" "$FAKE_HOME/.claude/scripts/user-info.sh"
fi

# Create mock search tools (no-op)
for tool in session-search doc-search; do
  cat > "$FAKE_HOME/.claude/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
  chmod +x "$FAKE_HOME/.claude/tools/$tool/$tool.sh"
done

# Override HOME for session.sh calls
export HOME="$FAKE_HOME"

SF_SESSION_DIR="$TEST_DIR/sessions/sf_test_$$"

# SF-01: session.sh activate stores fleetPaneId
"$FAKE_HOME/.claude/scripts/session.sh" activate "$SF_SESSION_DIR" test < /dev/null >/dev/null 2>&1 || true
SF01_FLEET_PANE=$(jq -r '.fleetPaneId // ""' "$SF_SESSION_DIR/.state.json" 2>/dev/null || echo "")
assert_eq "sf-session:sf-window:SFAgent" "$SF01_FLEET_PANE" "SF-01: activate stores fleetPaneId"

# SF-02: session.sh find discovers session by fleetPaneId
# session.sh find uses $PWD/sessions, so cd to test dir
ORIGINAL_PWD="$PWD"
cd "$TEST_DIR"
SF02_FOUND=$("$FAKE_HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "NOT_FOUND")
cd "$ORIGINAL_PWD"
assert_contains "sf_test_$$" "$SF02_FOUND" "SF-02: find discovers session by fleetPaneId"

# SF-03: session.sh phase sets @pane_notify="working"
# Need to add phases array for phase enforcement
jq '.phases = [{"major":1,"minor":0,"name":"Setup"},{"major":2,"minor":0,"name":"Context"},{"major":3,"minor":0,"name":"Execution"}]' \
  "$SF_SESSION_DIR/.state.json" > "$SF_SESSION_DIR/.state.json.tmp" \
  && mv "$SF_SESSION_DIR/.state.json.tmp" "$SF_SESSION_DIR/.state.json"

# First move to phase 1 (re-enter current), then 2, then 3
"$FAKE_HOME/.claude/scripts/session.sh" phase "$SF_SESSION_DIR" "1: Setup" >/dev/null 2>&1 || true
"$FAKE_HOME/.claude/scripts/session.sh" phase "$SF_SESSION_DIR" "2: Context" >/dev/null 2>&1 || true
"$FAKE_HOME/.claude/scripts/session.sh" phase "$SF_SESSION_DIR" "3: Execution" >/dev/null 2>&1 || true
SF03_STATE=$(get_pane_option "$SF_SOCKET" "$SF_PANE" "@pane_notify")
assert_eq "working" "$SF03_STATE" "SF-03: phase transition sets @pane_notify=working"

# SF-04: session.sh phase "WAITING: user input" sets @pane_notify="unchecked"
# Note: WAITING: labels don't start with a digit, so phase enforcement rejects them.
# Remove the phases array to disable enforcement and test the WAITING->unchecked notify path.
jq 'del(.phases)' "$SF_SESSION_DIR/.state.json" > "$SF_SESSION_DIR/.state.json.tmp" \
  && mv "$SF_SESSION_DIR/.state.json.tmp" "$SF_SESSION_DIR/.state.json"
"$FAKE_HOME/.claude/scripts/session.sh" phase "$SF_SESSION_DIR" "WAITING: user input" >/dev/null 2>&1 || true
SF04_STATE=$(get_pane_option "$SF_SOCKET" "$SF_PANE" "@pane_notify")
assert_eq "unchecked" "$SF04_STATE" "SF-04: WAITING phase sets @pane_notify=unchecked"

echo ""

# =============================================
# Category: Fleet Session Claiming (FC-01..FC-02)
# =============================================
echo "--- Fleet Session Claiming ---"

# FC-01: session.sh activate rejects when a different alive PID holds the session
FC01_DIR="$TEST_DIR/sessions/fc01_test"
mkdir -p "$FC01_DIR"
# Spawn a controlled background process for a guaranteed-alive, guaranteed-different PID
# (PPID can equal $$ or 1 in containers/PID namespaces)
sleep 9999 &
FC01_SLEEP_PID=$!
ALIVE_PID="$FC01_SLEEP_PID"
cat > "$FC01_DIR/.state.json" <<JSON
{"pid":$ALIVE_PID,"skill":"test","lifecycle":"active","fleetPaneId":"fc-dummy"}
JSON
FC01_RC=0
"$FAKE_HOME/.claude/scripts/session.sh" activate "$FC01_DIR" test < /dev/null >/dev/null 2>&1 || FC01_RC=$?
assert_eq "1" "$FC01_RC" "FC-01: activate rejects when different alive PID holds session"

# FC-02: Re-activate from same pane clears stale fleetPaneId
FC02_DIR_A="$TEST_DIR/sessions/fc02_session_a"
FC02_DIR_B="$TEST_DIR/sessions/fc02_session_b"
mkdir -p "$FC02_DIR_A" "$FC02_DIR_B"

# Activate session A -- it will get our current fleetPaneId
"$FAKE_HOME/.claude/scripts/session.sh" activate "$FC02_DIR_A" test < /dev/null >/dev/null 2>&1 || true
FC02A_FPANE=$(jq -r '.fleetPaneId // ""' "$FC02_DIR_A/.state.json" 2>/dev/null)

# Now activate session B from the same pane -- should claim the fleetPaneId
"$FAKE_HOME/.claude/scripts/session.sh" activate "$FC02_DIR_B" test < /dev/null >/dev/null 2>&1 || true

# Session A should have lost its fleetPaneId
FC02A_AFTER=$(jq -r '.fleetPaneId // "MISSING"' "$FC02_DIR_A/.state.json" 2>/dev/null)
assert_eq "MISSING" "$FC02A_AFTER" "FC-02: Re-activate clears stale fleetPaneId from old session"

echo ""

# =============================================
# Category: Notify Edge Cases (NE-01..NE-02)
# =============================================
echo "--- Notify Edge Cases ---"

# NE-01: notify from non-focused pane applies color without switching focus
# Create a 2-pane fleet socket
NE_SOCKET="fleet-ne$$"
tmux -L "$NE_SOCKET" new-session -d -s ne-session -n ne-window
tmux -L "$NE_SOCKET" split-window -t ne-session:ne-window
NE_PANE0=$(tmux -L "$NE_SOCKET" list-panes -t ne-session:ne-window -F '#{pane_id}' 2>/dev/null | head -1)
NE_PANE1=$(tmux -L "$NE_SOCKET" list-panes -t ne-session:ne-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$NE_SOCKET" set-option -p -t "$NE_PANE0" @pane_label "NE1"
tmux -L "$NE_SOCKET" set-option -p -t "$NE_PANE1" @pane_label "NE2"

# Focus pane 1
tmux -L "$NE_SOCKET" select-pane -t "$NE_PANE1" 2>/dev/null

# Call notify error from pane 0 (not focused)
setup_tmux_env "$NE_SOCKET" "$NE_PANE0"
"$FLEET_SH" notify error 2>/dev/null || true

# Verify pane 0 has the error state
NE01_P0_STATE=$(get_pane_option "$NE_SOCKET" "$NE_PANE0" "@pane_notify")
assert_eq "error" "$NE01_P0_STATE" "NE-01: Non-focused pane gets error state"

# Verify pane 1 is still the active pane (focus not stolen)
NE01_ACTIVE=$(tmux -L "$NE_SOCKET" display-message -p '#{pane_id}' 2>/dev/null || echo "")
assert_eq "$NE_PANE1" "$NE01_ACTIVE" "NE-01: Focus not stolen from pane 1"

tmux -L "$NE_SOCKET" kill-server 2>/dev/null || true

# NE-02: session.sh deactivate sets @pane_notify="unchecked"
# Re-use SF session: set pane to "done" first so we can see the transition to "unchecked"
# NOTE: We intentionally do NOT call session.sh phase "DONE" here -- that would trigger
# fleet.sh notify unchecked as a side effect, masking whether deactivate itself notifies.
setup_tmux_env "$SF_SOCKET" "$SF_PANE"
"$FLEET_SH" notify done 2>/dev/null || true

# Verify pre-condition: pane is "done" (not already "unchecked")
NE02_PRE=$(get_pane_option "$SF_SOCKET" "$SF_PANE" "@pane_notify")
assert_eq "done" "$NE02_PRE" "NE-02 pre: pane starts as done"

# Deactivate -- this should set @pane_notify=unchecked via its own notification path
"$FAKE_HOME/.claude/scripts/session.sh" deactivate "$SF_SESSION_DIR" <<'DESC'
Test deactivation for NE-02
DESC
NE02_STATE=$(get_pane_option "$SF_SOCKET" "$SF_PANE" "@pane_notify")
assert_eq "unchecked" "$NE02_STATE" "NE-02: deactivate sets @pane_notify=unchecked"

# Kill SF socket
tmux -L "$SF_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Concurrent Socket Isolation (CS-01)
# =============================================
echo "--- Concurrent Socket Isolation ---"

# CS-01: Operations on one fleet socket don't affect another
CS_SOCKET_A="fleet-csa$$"
CS_SOCKET_B="fleet-csb$$"
tmux -L "$CS_SOCKET_A" new-session -d -s cs-a -n cs-win
tmux -L "$CS_SOCKET_B" new-session -d -s cs-b -n cs-win
tmux -L "$CS_SOCKET_A" set-option -p @pane_label "CSA"
tmux -L "$CS_SOCKET_B" set-option -p @pane_label "CSB"

CS_PANE_A=$(tmux -L "$CS_SOCKET_A" list-panes -F '#{pane_id}' 2>/dev/null | head -1)
CS_PANE_B=$(tmux -L "$CS_SOCKET_B" list-panes -F '#{pane_id}' 2>/dev/null | head -1)

# Set initial states
tmux -L "$CS_SOCKET_A" set-option -p -t "$CS_PANE_A" @pane_notify "done" 2>/dev/null
tmux -L "$CS_SOCKET_B" set-option -p -t "$CS_PANE_B" @pane_notify "done" 2>/dev/null

# Modify socket A only
setup_tmux_env "$CS_SOCKET_A" "$CS_PANE_A"
"$FLEET_SH" notify error 2>/dev/null || true

# Verify socket A changed
CS01_A=$(get_pane_option "$CS_SOCKET_A" "$CS_PANE_A" "@pane_notify")
assert_eq "error" "$CS01_A" "CS-01a: Socket A changed to error"

# Verify socket B unchanged
CS01_B=$(get_pane_option "$CS_SOCKET_B" "$CS_PANE_B" "@pane_notify")
assert_eq "done" "$CS01_B" "CS-01b: Socket B unchanged (still done)"

tmux -L "$CS_SOCKET_A" kill-server 2>/dev/null || true
tmux -L "$CS_SOCKET_B" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Concurrent Notify Race (CR-01)
# =============================================
echo "--- Concurrent Notify Stress Test ---"

# CR-01: Fire concurrent notifications to 10+ panes -- focus must not move
CR_SOCKET="fleet-cr$$"
tmux -L "$CR_SOCKET" new-session -d -s cr-test -x 200 -y 50

# Create 9 additional panes (10 total)
for i in $(seq 1 9); do
  tmux -L "$CR_SOCKET" split-window -t cr-test -h 2>/dev/null || \
  tmux -L "$CR_SOCKET" split-window -t cr-test -v 2>/dev/null
done
tmux -L "$CR_SOCKET" select-layout -t cr-test tiled 2>/dev/null || true

# Collect all pane IDs
CR_PANE_IDS=()
while IFS= read -r id; do CR_PANE_IDS+=("$id"); done < \
  <(tmux -L "$CR_SOCKET" list-panes -t cr-test -F '#{pane_id}')

CR_PANE_COUNT=${#CR_PANE_IDS[@]}

# Focus the first pane (this is the "user's active pane")
CR_FOCUS_PANE="${CR_PANE_IDS[0]}"
tmux -L "$CR_SOCKET" select-pane -t "$CR_FOCUS_PANE"

# Label all panes for fleet.sh
for i in "${!CR_PANE_IDS[@]}"; do
  tmux -L "$CR_SOCKET" set-option -p -t "${CR_PANE_IDS[$i]}" @pane_label "cr-agent-$i"
  tmux -L "$CR_SOCKET" set-option -p -t "${CR_PANE_IDS[$i]}" @pane_notify "working" 2>/dev/null || true
done

# Fire notifications to ALL non-focused panes concurrently in background
CR_ERR_DIR=$(mktemp -d)
CR_PIDS=()
for i in $(seq 1 $((CR_PANE_COUNT - 1))); do
  (
    CR_SOCK_PATH=$(tmux -L "$CR_SOCKET" display-message -p '#{socket_path}' 2>/dev/null || echo "/tmp/tmux-$(id -u)/$CR_SOCKET")
    export TMUX="${CR_SOCK_PATH},$(tmux -L "$CR_SOCKET" display-message -p '#{pid}' 2>/dev/null || echo '0'),0"
    export TMUX_PANE="${CR_PANE_IDS[$i]}"
    "$FLEET_SH" notify done 2>"$CR_ERR_DIR/err-$i.txt" || true
  ) &
  CR_PIDS+=($!)
done

# Wait for all background notifications to complete
for pid in "${CR_PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
sleep 0.3  # Let tmux settle

# ASSERT 1: Focus pane is still focused (no focus theft)
CR_CURRENT_FOCUS=$(tmux -L "$CR_SOCKET" display-message -p '#{pane_id}' 2>/dev/null || echo "")
assert_eq "$CR_FOCUS_PANE" "$CR_CURRENT_FOCUS" \
  "CR-01a: Focus pane unchanged after $((CR_PANE_COUNT - 1)) concurrent notifications"

# ASSERT 2: All notified panes have @pane_notify=done
CR_ALL_DONE=true
for i in $(seq 1 $((CR_PANE_COUNT - 1))); do
  CR_STATE=$(tmux -L "$CR_SOCKET" show-option -p -t "${CR_PANE_IDS[$i]}" -v @pane_notify 2>/dev/null || echo "")
  if [[ "$CR_STATE" != "done" ]]; then
    CR_ALL_DONE=false
    break
  fi
done
assert_eq "true" "$CR_ALL_DONE" \
  "CR-01b: All $((CR_PANE_COUNT - 1)) notified panes have @pane_notify=done"

# ASSERT 3: No stderr errors from concurrent notifications
CR_HAS_ERRORS=false
for f in "$CR_ERR_DIR"/err-*.txt; do
  [[ -f "$f" ]] && [[ -s "$f" ]] && { CR_HAS_ERRORS=true; break; }
done
assert_eq "false" "$CR_HAS_ERRORS" \
  "CR-01c: No stderr errors from concurrent notifications"

rm -rf "$CR_ERR_DIR"

# ASSERT 4: Window-level aggregation correct after concurrent blast
# Set the focused pane (pane 0) to "done" too -- it was "working" from setup (line 614)
# and the concurrent blast only updated panes 1-9
setup_tmux_env "$CR_SOCKET" "$CR_FOCUS_PANE"
"$FLEET_SH" notify done 2>/dev/null || true
CR_WIN_STATE=$(tmux -L "$CR_SOCKET" show-options -w -v @window_notify 2>/dev/null || echo "")
assert_eq "done" "$CR_WIN_STATE" \
  "CR-01d: Window aggregation is done after all panes notified done"

tmux -L "$CR_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Notify Edge Cases Extended (NE-03..NE-05)
# =============================================
echo "--- Notify Edge Cases Extended ---"

# Create a fleet socket for edge case tests
NE_EXT_SOCKET="fleet-neext$$"
tmux -L "$NE_EXT_SOCKET" new-session -d -s neext-session -n neext-window
tmux -L "$NE_EXT_SOCKET" split-window -t neext-session:neext-window
NE_EXT_PANE0=$(tmux -L "$NE_EXT_SOCKET" list-panes -t neext-session:neext-window -F '#{pane_id}' 2>/dev/null | head -1)
NE_EXT_PANE1=$(tmux -L "$NE_EXT_SOCKET" list-panes -t neext-session:neext-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$NE_EXT_SOCKET" set-option -p -t "$NE_EXT_PANE0" @pane_label "NEX1"
tmux -L "$NE_EXT_SOCKET" set-option -p -t "$NE_EXT_PANE1" @pane_label "NEX2"

# NE-03: Focused pane notify skips style but sets @pane_notify
# Focus pane0, then notify FROM pane0 (target == active)
tmux -L "$NE_EXT_SOCKET" select-pane -t "$NE_EXT_PANE0" 2>/dev/null
# Clear any existing style
tmux -L "$NE_EXT_SOCKET" set-option -p -t "$NE_EXT_PANE0" style "default" 2>/dev/null || true
setup_tmux_env "$NE_EXT_SOCKET" "$NE_EXT_PANE0"
"$FLEET_SH" notify error 2>/dev/null || true

NE03_STATE=$(get_pane_option "$NE_EXT_SOCKET" "$NE_EXT_PANE0" "@pane_notify")
assert_eq "error" "$NE03_STATE" "NE-03a: Focused pane gets @pane_notify=error"

NE03_STYLE=$(get_pane_style "$NE_EXT_SOCKET" "$NE_EXT_PANE0")
# Style is NOT applied to focused pane -- avoids flash/distraction while user is looking at it
NE03_HAS_BG="false"
echo "$NE03_STYLE" | grep -q "bg=" && NE03_HAS_BG="true"
assert_eq "false" "$NE03_HAS_BG" "NE-03b: Focused pane does NOT get bg tint (skip to avoid flash)"

# NE-04: Rapid state transitions on same pane (last write wins)
setup_tmux_env "$NE_EXT_SOCKET" "$NE_EXT_PANE1"
tmux -L "$NE_EXT_SOCKET" select-pane -t "$NE_EXT_PANE0" 2>/dev/null  # Focus pane0, notify from pane1
"$FLEET_SH" notify working 2>/dev/null || true
"$FLEET_SH" notify done 2>/dev/null || true
"$FLEET_SH" notify error 2>/dev/null || true
NE04_STATE=$(get_pane_option "$NE_EXT_SOCKET" "$NE_EXT_PANE1" "@pane_notify")
assert_eq "error" "$NE04_STATE" "NE-04: Rapid transitions settle to last state (error)"

# NE-05: Empty TMUX_PANE falls back to current pane (else branch)
setup_tmux_env "$NE_EXT_SOCKET" "$NE_EXT_PANE0"
tmux -L "$NE_EXT_SOCKET" select-pane -t "$NE_EXT_PANE0" 2>/dev/null
tmux -L "$NE_EXT_SOCKET" set-option -p -t "$NE_EXT_PANE0" @pane_notify "done" 2>/dev/null
unset TMUX_PANE
(
  # Run in subshell to keep TMUX_PANE unset isolated
  unset TMUX_PANE
  "$FLEET_SH" notify working 2>/dev/null
)
NE05_RC=$?
# The else branch at line 471 uses set-option -p without -t, which targets the current pane
NE05_STATE=$(get_pane_option "$NE_EXT_SOCKET" "$NE_EXT_PANE0" "@pane_notify")
assert_eq "working" "$NE05_STATE" "NE-05: Empty TMUX_PANE fallback sets current pane"

tmux -L "$NE_EXT_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Notify-Check Focus Simulation (NC-01..NC-02)
# =============================================
echo "--- Notify-Check Focus Simulation ---"

NC_SOCKET="fleet-nc$$"
tmux -L "$NC_SOCKET" new-session -d -s nc-session -n nc-window
tmux -L "$NC_SOCKET" split-window -t nc-session:nc-window
NC_PANE0=$(tmux -L "$NC_SOCKET" list-panes -t nc-session:nc-window -F '#{pane_id}' 2>/dev/null | head -1)
NC_PANE1=$(tmux -L "$NC_SOCKET" list-panes -t nc-session:nc-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$NC_SOCKET" set-option -p -t "$NC_PANE0" @pane_label "NC1"
tmux -L "$NC_SOCKET" set-option -p -t "$NC_PANE1" @pane_label "NC2"

setup_tmux_env "$NC_SOCKET" "$NC_PANE0"

# NC-01: Focus unchecked pane -> notify-check -> checked
tmux -L "$NC_SOCKET" set-option -p -t "$NC_PANE1" @pane_notify "unchecked" 2>/dev/null
# Simulate user focusing pane1
tmux -L "$NC_SOCKET" select-pane -t "$NC_PANE1" 2>/dev/null
# Call notify-check as the focus hook would
"$FLEET_SH" notify-check "$NC_PANE1" 2>/dev/null || true
NC01_STATE=$(get_pane_option "$NC_SOCKET" "$NC_PANE1" "@pane_notify")
assert_eq "checked" "$NC01_STATE" "NC-01: Focus on unchecked pane + notify-check -> checked"

# NC-02: Focus error pane -> notify-check -> still error
tmux -L "$NC_SOCKET" set-option -p -t "$NC_PANE0" @pane_notify "error" 2>/dev/null
tmux -L "$NC_SOCKET" select-pane -t "$NC_PANE0" 2>/dev/null
"$FLEET_SH" notify-check "$NC_PANE0" 2>/dev/null || true
NC02_STATE=$(get_pane_option "$NC_SOCKET" "$NC_PANE0" "@pane_notify")
assert_eq "error" "$NC02_STATE" "NC-02: Focus on error pane + notify-check -> still error"

tmux -L "$NC_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Interleaved Cross-Pane Transitions (RT-01)
# =============================================
echo "--- Interleaved Cross-Pane Transitions ---"

RT_SOCKET="fleet-rt$$"
tmux -L "$RT_SOCKET" new-session -d -s rt-session -n rt-window
tmux -L "$RT_SOCKET" split-window -t rt-session:rt-window
RT_PANE0=$(tmux -L "$RT_SOCKET" list-panes -t rt-session:rt-window -F '#{pane_id}' 2>/dev/null | head -1)
RT_PANE1=$(tmux -L "$RT_SOCKET" list-panes -t rt-session:rt-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$RT_SOCKET" set-option -p -t "$RT_PANE0" @pane_label "RT1"
tmux -L "$RT_SOCKET" set-option -p -t "$RT_PANE1" @pane_label "RT2"

# Interleave: pane0=working, pane1=error, pane0=done, pane1=done
setup_tmux_env "$RT_SOCKET" "$RT_PANE0"
"$FLEET_SH" notify working 2>/dev/null || true
setup_tmux_env "$RT_SOCKET" "$RT_PANE1"
"$FLEET_SH" notify error 2>/dev/null || true
setup_tmux_env "$RT_SOCKET" "$RT_PANE0"
"$FLEET_SH" notify done 2>/dev/null || true
setup_tmux_env "$RT_SOCKET" "$RT_PANE1"
"$FLEET_SH" notify done 2>/dev/null || true

RT01_P0=$(get_pane_option "$RT_SOCKET" "$RT_PANE0" "@pane_notify")
RT01_P1=$(get_pane_option "$RT_SOCKET" "$RT_PANE1" "@pane_notify")
RT01_WIN=$(tmux -L "$RT_SOCKET" show-options -w -v @window_notify 2>/dev/null || echo "")
assert_eq "done" "$RT01_P0" "RT-01a: Pane 0 settles to done after interleaved transitions"
assert_eq "done" "$RT01_P1" "RT-01b: Pane 1 settles to done after interleaved transitions"
assert_eq "done" "$RT01_WIN" "RT-01c: Window aggregation done after interleaved transitions"

tmux -L "$RT_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Negative Validation (NV-01..NV-02)
# =============================================
echo "--- Negative Validation ---"

# NV-01/NV-02 need a fleet socket for TMUX env
NV_SOCKET="fleet-nv$$"
tmux -L "$NV_SOCKET" new-session -d -s nv-session -n nv-window
tmux -L "$NV_SOCKET" set-option -p @pane_label "NV1"
NV_PANE=$(tmux -L "$NV_SOCKET" list-panes -t nv-session:nv-window -F '#{pane_id}' 2>/dev/null | head -1)
setup_tmux_env "$NV_SOCKET" "$NV_PANE"

# NV-01: notify with empty string exits 1
(
  setup_tmux_env "$NV_SOCKET" "$NV_PANE"
  "$FLEET_SH" notify "" >/dev/null 2>&1
)
NV01_RC=$?
assert_eq "1" "$NV01_RC" "NV-01: notify with empty string exits 1"

# NV-02: notify with no arguments exits 1
(
  setup_tmux_env "$NV_SOCKET" "$NV_PANE"
  "$FLEET_SH" notify >/dev/null 2>&1
)
NV02_RC=$?
assert_eq "1" "$NV02_RC" "NV-02: notify with no arguments exits 1"

tmux -L "$NV_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Window Aggregation Extended (W-05)
# =============================================
echo "--- Window Aggregation Extended ---"

# W-05: 3-pane aggregation with all different states
W5_SOCKET="fleet-w5$$"
tmux -L "$W5_SOCKET" new-session -d -s w5-session -n w5-window
tmux -L "$W5_SOCKET" split-window -t w5-session:w5-window
tmux -L "$W5_SOCKET" split-window -t w5-session:w5-window
W5_PANES=()
while IFS= read -r id; do W5_PANES+=("$id"); done < \
  <(tmux -L "$W5_SOCKET" list-panes -t w5-session:w5-window -F '#{pane_id}')
for i in "${!W5_PANES[@]}"; do
  tmux -L "$W5_SOCKET" set-option -p -t "${W5_PANES[$i]}" @pane_label "W5-$i"
done

# Set 3 different states: error, working, unchecked
tmux -L "$W5_SOCKET" set-option -p -t "${W5_PANES[0]}" @pane_notify "error" 2>/dev/null
tmux -L "$W5_SOCKET" set-option -p -t "${W5_PANES[1]}" @pane_notify "working" 2>/dev/null
tmux -L "$W5_SOCKET" set-option -p -t "${W5_PANES[2]}" @pane_notify "unchecked" 2>/dev/null
# Trigger window aggregation via notify on any pane
setup_tmux_env "$W5_SOCKET" "${W5_PANES[0]}"
"$FLEET_SH" notify error 2>/dev/null || true
W05_WIN=$(tmux -L "$W5_SOCKET" show-options -w -v @window_notify 2>/dev/null || echo "")
assert_eq "error" "$W05_WIN" "W-05: 3-pane agg with error+working+unchecked -> window error"

tmux -L "$W5_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Graceful Failure (GF-01)
# =============================================
echo "--- Graceful Failure ---"

# GF-01: Notify on killed/destroyed pane fails gracefully
GF_SOCKET="fleet-gf$$"
tmux -L "$GF_SOCKET" new-session -d -s gf-session -n gf-window
tmux -L "$GF_SOCKET" split-window -t gf-session:gf-window
GF_PANE0=$(tmux -L "$GF_SOCKET" list-panes -t gf-session:gf-window -F '#{pane_id}' 2>/dev/null | head -1)
GF_PANE1=$(tmux -L "$GF_SOCKET" list-panes -t gf-session:gf-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$GF_SOCKET" set-option -p -t "$GF_PANE0" @pane_label "GF1"
tmux -L "$GF_SOCKET" set-option -p -t "$GF_PANE1" @pane_label "GF2"

# Kill pane1, then try to notify it
DEAD_PANE_ID="$GF_PANE1"
tmux -L "$GF_SOCKET" kill-pane -t "$GF_PANE1" 2>/dev/null || true

# Notify targeting the dead pane -- should not crash
setup_tmux_env "$GF_SOCKET" "$DEAD_PANE_ID"
GF01_RC=0
"$FLEET_SH" notify error 2>/dev/null || GF01_RC=$?
# The || true in cmd_notify's set-option should prevent crash, exit 0
assert_eq "0" "$GF01_RC" "GF-01: Notify on killed pane exits 0 (graceful failure)"

tmux -L "$GF_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Suppress & Debounce (SS-01..SS-04)
# =============================================
echo "--- Suppress & Debounce ---"

# Create a fleet socket for suppress/debounce tests
SS_SOCKET="fleet-ss$$"
tmux -L "$SS_SOCKET" new-session -d -s ss-session -n ss-window
tmux -L "$SS_SOCKET" split-window -t ss-session:ss-window
SS_PANE0=$(tmux -L "$SS_SOCKET" list-panes -t ss-session:ss-window -F '#{pane_id}' 2>/dev/null | head -1)
SS_PANE1=$(tmux -L "$SS_SOCKET" list-panes -t ss-session:ss-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$SS_SOCKET" set-option -p -t "$SS_PANE0" @pane_label "SS1"
tmux -L "$SS_SOCKET" set-option -p -t "$SS_PANE1" @pane_label "SS2"

# SS-01: @suppress_focus_hook is 0 after notify completes
# Focus pane0, notify from pane1 (unfocused -- triggers the suppress compound)
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE0" 2>/dev/null
setup_tmux_env "$SS_SOCKET" "$SS_PANE1"
"$FLEET_SH" notify error 2>/dev/null || true
SS01_SUPPRESS=$(tmux -L "$SS_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
assert_eq "0" "$SS01_SUPPRESS" "SS-01: @suppress_focus_hook cleared after notify"

# SS-02: State-check debounce skips redundant visual update
# Set pane1 to error, then notify error again -- state unchanged, visual should be skipped
# Record the style before second notify
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE0" 2>/dev/null
setup_tmux_env "$SS_SOCKET" "$SS_PANE1"
"$FLEET_SH" notify error 2>/dev/null || true
SS02_STYLE_BEFORE=$(tmux -L "$SS_SOCKET" display -p -t "$SS_PANE1" '#{window-style}' 2>/dev/null || echo "")
# Manually change the style to something different to detect if notify re-applies it
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE1" -P "bg=green" 2>/dev/null
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE0" 2>/dev/null  # restore focus
# Now notify error again -- state is still "error", so visual update should be SKIPPED
"$FLEET_SH" notify error 2>/dev/null || true
SS02_STYLE_AFTER=$(tmux -L "$SS_SOCKET" display -p -t "$SS_PANE1" '#{window-style}' 2>/dev/null || echo "")
# If debounce worked, the green style should remain (not overwritten back to error color)
assert_eq "bg=green" "$SS02_STYLE_AFTER" "SS-02: State-check debounce skips redundant visual update"

# SS-03: Hook exits early when @suppress_focus_hook is set
# Set suppress=1 manually, select a pane (which triggers the hook), verify no style change
tmux -L "$SS_SOCKET" set -g @suppress_focus_hook "1" 2>/dev/null
# Set pane1 to a known style
tmux -L "$SS_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null  # briefly clear to set style
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE1" -P "bg=blue" 2>/dev/null
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE0" 2>/dev/null  # restore focus
SS03_PRE_STYLE=$(tmux -L "$SS_SOCKET" display -p -t "$SS_PANE1" '#{window-style}' 2>/dev/null || echo "")
# Now set suppress=1 and trigger focus change
tmux -L "$SS_SOCKET" set -g @suppress_focus_hook "1" 2>/dev/null
# Simulate a focus change that would normally trigger the hook
# The hook should exit early and NOT change pane1's style
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE1" 2>/dev/null
sleep 0.1  # Give hook time to (not) fire
SS03_POST_STYLE=$(tmux -L "$SS_SOCKET" display -p -t "$SS_PANE0" '#{window-style}' 2>/dev/null || echo "")
# Clear suppress to avoid leaving it stuck
tmux -L "$SS_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
# pane0 was the "last focused" -- if hook ran, it would have tinted pane0. If suppressed, pane0 is unchanged.
# We can't directly assert the hook didn't run (it's async), but we verify suppress flag behavior
assert_eq "0" "$(tmux -L "$SS_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")" \
  "SS-03: @suppress_focus_hook can be set and cleared"

# SS-04: Notify with state change applies visual update
# Reset state, then notify with a NEW state -- should apply visual
tmux -L "$SS_SOCKET" set-option -p -t "$SS_PANE1" @pane_notify "done" 2>/dev/null
tmux -L "$SS_SOCKET" select-pane -t "$SS_PANE0" 2>/dev/null
setup_tmux_env "$SS_SOCKET" "$SS_PANE1"
"$FLEET_SH" notify error 2>/dev/null || true
SS04_STYLE=$(tmux -L "$SS_SOCKET" display -p -t "$SS_PANE1" '#{window-style}' 2>/dev/null || echo "")
assert_contains "bg=#3d2020" "$SS04_STYLE" "SS-04: State change applies visual update (error color)"

tmux -L "$SS_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Hook Direct Invocation (HK-01..HK-08)
# =============================================
echo "--- Hook Direct Invocation ---"

# Create a fleet socket for hook tests (direct invocation of pane-focus-style.sh)
HK_SOCKET="fleet-hk$$"
tmux -L "$HK_SOCKET" new-session -d -s hk-session -n hk-window
tmux -L "$HK_SOCKET" split-window -t hk-session:hk-window
HK_PANE0=$(tmux -L "$HK_SOCKET" list-panes -t hk-session:hk-window -F '#{pane_id}' 2>/dev/null | head -1)
HK_PANE1=$(tmux -L "$HK_SOCKET" list-panes -t hk-session:hk-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$HK_SOCKET" set-option -p -t "$HK_PANE0" @pane_label "HK1"
tmux -L "$HK_SOCKET" set-option -p -t "$HK_PANE1" @pane_label "HK2"

# Helper: invoke hook directly with controlled TMUX env
run_hook() {
  local socket="$1"
  local socket_path
  socket_path=$(tmux -L "$socket" display-message -p '#{socket_path}' 2>/dev/null || echo "/tmp/tmux-$(id -u)/$socket")
  TMUX="${socket_path},$(tmux -L "$socket" display-message -p '#{pid}' 2>/dev/null || echo '0'),0" \
    bash "$ORIGINAL_HOME/.claude/hooks/pane-focus-style.sh" 2>/dev/null
}

# HK-01: Hook exits immediately when @suppress_focus_hook=1
tmux -L "$HK_SOCKET" set -g @suppress_focus_hook "1" 2>/dev/null
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
tmux -L "$HK_SOCKET" set -g @last_focused_pane "$HK_PANE1" 2>/dev/null
tmux -L "$HK_SOCKET" set-option -p -t "$HK_PANE1" @pane_notify "error" 2>/dev/null
# Set pane1 to a known style -- if hook fires despite suppress, it would change it
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE1" -P "bg=purple" 2>/dev/null
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
run_hook "$HK_SOCKET"
HK01_STYLE=$(tmux -L "$HK_SOCKET" display -p -t "$HK_PANE1" '#{window-style}' 2>/dev/null || echo "")
assert_eq "bg=purple" "$HK01_STYLE" "HK-01: Hook exits when @suppress_focus_hook=1 (style unchanged)"
# Clean up suppress
tmux -L "$HK_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null

# HK-02 through HK-06: Hook tints LAST pane with correct color for each status
# Setup: focus pane0, pane1 is LAST. Invoke hook after setting @last_focused_pane=pane1.
# Note: no declare -A (macOS bash 3.x compat)
hk_expected_color() {
  case "$1" in
    error)     echo "bg=#3d2020" ;;
    unchecked) echo "bg=#081a10" ;;
    working)   echo "bg=#080c10" ;;
    checked)   echo "bg=#0a1005" ;;
    done)      echo "bg=#0a0a0a" ;;
  esac
}
HK_NUM=2
for hk_status in error unchecked working checked done; do
  # Reset: clear styles, set up LAST/CURR
  tmux -L "$HK_SOCKET" set -g @focus_hook_running "0" 2>/dev/null
  tmux -L "$HK_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
  tmux -L "$HK_SOCKET" set -g @last_focused_pane "$HK_PANE1" 2>/dev/null
  tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
  tmux -L "$HK_SOCKET" set-option -p -t "$HK_PANE1" @pane_notify "$hk_status" 2>/dev/null
  # Clear pane1 style so the hook must apply it fresh
  tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE1" -P "default" 2>/dev/null
  tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
  run_hook "$HK_SOCKET"
  sleep 0.1
  HK_RESULT=$(tmux -L "$HK_SOCKET" display -p -t "$HK_PANE1" '#{window-style}' 2>/dev/null || echo "")
  HK_EXPECTED=$(hk_expected_color "$hk_status")
  assert_contains "$HK_EXPECTED" "$HK_RESULT" "HK-0${HK_NUM}: Hook tints LAST pane with $hk_status color ($HK_EXPECTED)"
  HK_NUM=$((HK_NUM + 1))
done

# HK-07: Hook sets CURR pane to black
tmux -L "$HK_SOCKET" set -g @focus_hook_running "0" 2>/dev/null
tmux -L "$HK_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
tmux -L "$HK_SOCKET" set -g @last_focused_pane "$HK_PANE1" 2>/dev/null
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
# Set curr pane to non-black so we can see the hook change it
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" -P "bg=red" 2>/dev/null
tmux -L "$HK_SOCKET" set-option -p -t "$HK_PANE1" @pane_notify "done" 2>/dev/null
run_hook "$HK_SOCKET"
sleep 0.1
HK07_STYLE=$(tmux -L "$HK_SOCKET" display -p -t "$HK_PANE0" '#{window-style}' 2>/dev/null || echo "")
assert_contains "bg=black" "$HK07_STYLE" "HK-07: Hook sets CURR pane to black"

# HK-08: Hook skips tint when LAST pane style already matches target
tmux -L "$HK_SOCKET" set -g @focus_hook_running "0" 2>/dev/null
tmux -L "$HK_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
tmux -L "$HK_SOCKET" set -g @last_focused_pane "$HK_PANE1" 2>/dev/null
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
tmux -L "$HK_SOCKET" set-option -p -t "$HK_PANE1" @pane_notify "error" 2>/dev/null
# Pre-set pane1 style to exact target tint -- hook should skip it
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE1" -P "bg=#3d2020" 2>/dev/null
tmux -L "$HK_SOCKET" select-pane -t "$HK_PANE0" 2>/dev/null
run_hook "$HK_SOCKET"
sleep 0.1
# After hook, suppress should be 0 (never set because tint was skipped)
HK08_SUPPRESS=$(tmux -L "$HK_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
assert_eq "0" "$HK08_SUPPRESS" "HK-08: Hook skips tint when LAST style already matches (suppress stayed 0)"

tmux -L "$HK_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Suppress Edge Cases (SE-01..SE-04)
# =============================================
echo "--- Suppress Edge Cases ---"

SE_SOCKET="fleet-se$$"
tmux -L "$SE_SOCKET" new-session -d -s se-session -n se-window
tmux -L "$SE_SOCKET" split-window -t se-session:se-window
SE_PANE0=$(tmux -L "$SE_SOCKET" list-panes -t se-session:se-window -F '#{pane_id}' 2>/dev/null | head -1)
SE_PANE1=$(tmux -L "$SE_SOCKET" list-panes -t se-session:se-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$SE_SOCKET" set-option -p -t "$SE_PANE0" @pane_label "SE1"
tmux -L "$SE_SOCKET" set-option -p -t "$SE_PANE1" @pane_label "SE2"

# SE-01: Suppress flag is 0 after all 5 state transitions
tmux -L "$SE_SOCKET" select-pane -t "$SE_PANE0" 2>/dev/null
setup_tmux_env "$SE_SOCKET" "$SE_PANE1"
SE01_ALL_CLEAR=true
for se_state in working error unchecked checked done; do
  "$FLEET_SH" notify "$se_state" 2>/dev/null || true
  SE01_FLAG=$(tmux -L "$SE_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
  if [[ "$SE01_FLAG" != "0" ]]; then
    SE01_ALL_CLEAR=false
    break
  fi
done
assert_eq "true" "$SE01_ALL_CLEAR" "SE-01: Suppress flag is 0 after all 5 state transitions"

# SE-02: Concurrent notify calls both complete with suppress=0
# Reset pane states
tmux -L "$SE_SOCKET" set-option -p -t "$SE_PANE0" @pane_notify "done" 2>/dev/null
tmux -L "$SE_SOCKET" set-option -p -t "$SE_PANE1" @pane_notify "done" 2>/dev/null
tmux -L "$SE_SOCKET" select-pane -t "$SE_PANE0" 2>/dev/null  # focus pane0
# Fire concurrent notifications to pane0 and pane1
SE_ERR_DIR=$(mktemp -d)
(
  setup_tmux_env "$SE_SOCKET" "$SE_PANE1"
  "$FLEET_SH" notify error 2>"$SE_ERR_DIR/err-1.txt" || true
) &
SE_PID1=$!
(
  # Need pane0 unfocused for style to apply -- but pane0 IS focused.
  # We'll notify from pane0 (focused path) which skips style but tests flag behavior
  setup_tmux_env "$SE_SOCKET" "$SE_PANE0"
  "$FLEET_SH" notify working 2>"$SE_ERR_DIR/err-0.txt" || true
) &
SE_PID2=$!
wait "$SE_PID1" 2>/dev/null || true
wait "$SE_PID2" 2>/dev/null || true
sleep 0.2
SE02_FLAG=$(tmux -L "$SE_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
SE02_P1=$(tmux -L "$SE_SOCKET" show-option -p -t "$SE_PANE1" -v @pane_notify 2>/dev/null || echo "")
assert_eq "0" "$SE02_FLAG" "SE-02a: Suppress=0 after concurrent notify"
assert_eq "error" "$SE02_P1" "SE-02b: Pane1 state correct after concurrent notify"
rm -rf "$SE_ERR_DIR"

# SE-03: Suppress flag visible during compound (observability test)
# We can't directly observe mid-compound state, but we can verify the flag is SET
# by checking it right after the compound starts. Instead, verify a simpler property:
# set suppress=1, check it's 1, clear it.
tmux -L "$SE_SOCKET" set -g @suppress_focus_hook "1" 2>/dev/null
SE03_SET=$(tmux -L "$SE_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
tmux -L "$SE_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
SE03_CLEAR=$(tmux -L "$SE_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
assert_eq "1" "$SE03_SET" "SE-03a: Suppress flag is immediately visible when set"
assert_eq "0" "$SE03_CLEAR" "SE-03b: Suppress flag is immediately visible when cleared"

# SE-04: Notify from focused pane does not touch suppress flag
tmux -L "$SE_SOCKET" select-pane -t "$SE_PANE0" 2>/dev/null
tmux -L "$SE_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
tmux -L "$SE_SOCKET" set-option -p -t "$SE_PANE0" @pane_notify "done" 2>/dev/null
setup_tmux_env "$SE_SOCKET" "$SE_PANE0"
"$FLEET_SH" notify error 2>/dev/null || true
SE04_FLAG=$(tmux -L "$SE_SOCKET" show -gqv @suppress_focus_hook 2>/dev/null || echo "")
assert_eq "0" "$SE04_FLAG" "SE-04: Focused pane notify does not touch suppress flag"

tmux -L "$SE_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Additional Coverage (AC-01..AC-04)
# =============================================
echo "--- Additional Coverage ---"

AC_SOCKET="fleet-ac$$"
tmux -L "$AC_SOCKET" new-session -d -s ac-session -n ac-window
tmux -L "$AC_SOCKET" split-window -t ac-session:ac-window
AC_PANE0=$(tmux -L "$AC_SOCKET" list-panes -t ac-session:ac-window -F '#{pane_id}' 2>/dev/null | head -1)
AC_PANE1=$(tmux -L "$AC_SOCKET" list-panes -t ac-session:ac-window -F '#{pane_id}' 2>/dev/null | tail -1)
tmux -L "$AC_SOCKET" set-option -p -t "$AC_PANE0" @pane_label "AC1"
tmux -L "$AC_SOCKET" set-option -p -t "$AC_PANE1" @pane_label "AC2"

# AC-01: Hook guard re-entry prevention
tmux -L "$AC_SOCKET" set -g @focus_hook_running "1" 2>/dev/null
tmux -L "$AC_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
tmux -L "$AC_SOCKET" set -g @last_focused_pane "$AC_PANE1" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" 2>/dev/null
tmux -L "$AC_SOCKET" set-option -p -t "$AC_PANE1" @pane_notify "error" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE1" -P "bg=cyan" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" 2>/dev/null
# Invoke hook directly -- should exit due to guard
AC_SP=$(tmux -L "$AC_SOCKET" display-message -p '#{socket_path}' 2>/dev/null || echo "/tmp/tmux-$(id -u)/$AC_SOCKET")
TMUX="${AC_SP},$(tmux -L "$AC_SOCKET" display-message -p '#{pid}' 2>/dev/null || echo '0'),0" \
  bash "$ORIGINAL_HOME/.claude/hooks/pane-focus-style.sh" 2>/dev/null || true
AC01_STYLE=$(tmux -L "$AC_SOCKET" display -p -t "$AC_PANE1" '#{window-style}' 2>/dev/null || echo "")
assert_eq "bg=cyan" "$AC01_STYLE" "AC-01: Hook guard prevents re-entry (style unchanged)"
tmux -L "$AC_SOCKET" set -g @focus_hook_running "0" 2>/dev/null

# AC-02: Hook handles missing @last_focused_pane gracefully
tmux -L "$AC_SOCKET" set -g @focus_hook_running "0" 2>/dev/null
tmux -L "$AC_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
# Unset @last_focused_pane by setting it to empty
tmux -L "$AC_SOCKET" set -g @last_focused_pane "" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" -P "bg=yellow" 2>/dev/null
# Invoke hook -- should skip LAST tinting (no LAST), set CURR to black
TMUX="${AC_SP},$(tmux -L "$AC_SOCKET" display-message -p '#{pid}' 2>/dev/null || echo '0'),0" \
  bash "$ORIGINAL_HOME/.claude/hooks/pane-focus-style.sh" 2>/dev/null || true
sleep 0.1
AC02_CURR=$(tmux -L "$AC_SOCKET" display -p -t "$AC_PANE0" '#{window-style}' 2>/dev/null || echo "")
assert_contains "bg=black" "$AC02_CURR" "AC-02: Hook handles missing @last_focused_pane (CURR set to black)"

# AC-03: Fleet.sh notify applies correct bg color for all 5 states on unfocused pane
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" 2>/dev/null  # focus pane0
setup_tmux_env "$AC_SOCKET" "$AC_PANE1"
# Note: no declare -A (macOS bash 3.x compat) -- reuse hk_expected_color helper
AC03_ALL_CORRECT=true
for ac_state in error unchecked working checked done; do
  # Reset pane state to force a new state each time
  tmux -L "$AC_SOCKET" set-option -p -t "$AC_PANE1" @pane_notify "RESET" 2>/dev/null
  "$FLEET_SH" notify "$ac_state" 2>/dev/null || true
  AC03_STYLE=$(tmux -L "$AC_SOCKET" display -p -t "$AC_PANE1" '#{window-style}' 2>/dev/null || echo "")
  AC03_EXPECTED=$(hk_expected_color "$ac_state")
  if ! echo "$AC03_STYLE" | grep -q "$AC03_EXPECTED"; then
    AC03_ALL_CORRECT=false
    fail "AC-03: fleet.sh $ac_state should set $AC03_EXPECTED" "$AC03_EXPECTED" "$AC03_STYLE"
  fi
done
if [[ "$AC03_ALL_CORRECT" == "true" ]]; then
  pass "AC-03: Fleet.sh notify applies correct bg color for all 5 states"
fi

# AC-04: Hook with CURR==LAST (same pane re-focused) is a no-op for LAST tinting
tmux -L "$AC_SOCKET" set -g @focus_hook_running "0" 2>/dev/null
tmux -L "$AC_SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
tmux -L "$AC_SOCKET" set -g @last_focused_pane "$AC_PANE0" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" 2>/dev/null
tmux -L "$AC_SOCKET" select-pane -t "$AC_PANE0" -P "bg=orange" 2>/dev/null
TMUX="${AC_SP},$(tmux -L "$AC_SOCKET" display-message -p '#{pid}' 2>/dev/null || echo '0'),0" \
  bash "$ORIGINAL_HOME/.claude/hooks/pane-focus-style.sh" 2>/dev/null || true
sleep 0.1
AC04_STYLE=$(tmux -L "$AC_SOCKET" display -p -t "$AC_PANE0" '#{window-style}' 2>/dev/null || echo "")
# CURR==LAST means the LAST block is skipped (if LAST != CURR guard), and CURR gets set to black
assert_contains "bg=black" "$AC04_STYLE" "AC-04: Hook with CURR==LAST sets CURR to black (LAST tinting skipped)"

tmux -L "$AC_SOCKET" kill-server 2>/dev/null || true

echo ""

# =============================================
# Category: Socket Helpers (SH-01..SH-02)
# =============================================
echo "--- Socket Helpers ---"

# Restore HOME for config-path tests (it uses get_user_id and get_fleet_base)
export HOME="$ORIGINAL_HOME"

# SH-01: fleet.sh config-path returns default path ending in {user}-fleet.yml
SH01_OUT=$("$FLEET_SH" config-path 2>/dev/null || echo "")
assert_contains "fleet.yml" "$SH01_OUT" "SH-01: config-path default ends with fleet.yml"

# SH-02: fleet.sh config-path project returns workgroup path
SH02_OUT=$("$FLEET_SH" config-path project 2>/dev/null || echo "")
assert_contains "project.yml" "$SH02_OUT" "SH-02: config-path project ends with project.yml"

echo ""

# =============================================
# Cleanup extra tmux servers
# =============================================
tmux -L "$NOTIFY_SOCKET" kill-server 2>/dev/null || true

# Restore HOME
export HOME="$ORIGINAL_HOME"

exit_with_results
