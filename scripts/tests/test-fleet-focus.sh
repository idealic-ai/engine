#!/bin/bash
# test-fleet-focus.sh — Tests for @pane_user_focused dimension
#
# Tests the focus state management added to pane-focus-style.sh:
#   - @pane_user_focused set on focus-in (current pane)
#   - @pane_user_focused cleared on focus-out (previous pane)
#   - coordinator-wake signal fired on focus-out
#   - Graceful handling of missing @pane_user_focused (not set = not focused)
#
# Uses an isolated tmux session (does not affect live fleet).
# Requires: tmux

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

# Path to the hook under test
HOOK_SH="$HOME/.claude/hooks/pane-focus-style.sh"

# Check prerequisites and create isolated test tmux session
check_tmux_available() {
    if ! command -v tmux &>/dev/null; then
        echo "SKIP: tmux not available"
        exit 0
    fi

    # Create isolated tmux session (4 panes, WITH hooks for focus testing)
    setup_test_tmux 4 true
    SOCKET="$TEST_TMUX_SOCKET"
    trap cleanup_test_tmux EXIT
}

# Get two panes from the test session
get_two_panes() {
    local window
    window=$(tmux -L "$SOCKET" list-windows -a -F '#{window_id} #{window_panes}' 2>/dev/null \
        | awk '$2 >= 2 { print $1; exit }')
    if [[ -z "$window" ]]; then
        echo "SKIP: Need a window with at least 2 panes for focus tests"
        exit 0
    fi

    TEST_WINDOW="$window"

    local panes
    panes=$(tmux -L "$SOCKET" list-panes -t "$window" -F '#{pane_id}' 2>/dev/null | head -2)
    PANE_A=$(echo "$panes" | head -1)
    PANE_B=$(echo "$panes" | tail -1)
    if [[ -z "$PANE_A" || -z "$PANE_B" || "$PANE_A" == "$PANE_B" ]]; then
        echo "SKIP: Need at least 2 panes in window $window for focus tests"
        exit 0
    fi
}

# Select a pane ensuring the client is on the correct window first
# This is critical: after-select-pane hook uses `display -p` which reads from the
# client's current window, not the target pane's window.
select_pane() {
    local pane_id="$1"
    tmux -L "$SOCKET" select-window -t "$TEST_WINDOW" 2>/dev/null || true
    tmux -L "$SOCKET" select-pane -t "$pane_id" 2>/dev/null
}

# Save focus-related state for a pane
save_focus_state() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_user_focused}' 2>/dev/null || echo ""
}

# Restore focus-related state
restore_focus_state() {
    local pane_id="$1" state="$2"
    if [[ -n "$state" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_user_focused "$state" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_user_focused 2>/dev/null || true
    fi
}

# ============================================================
# Setup / Teardown
# ============================================================

TEST_WINDOW=""
PANE_A=""
PANE_B=""

# One-time init (called before first test, not per-test)
init_test_session() {
    check_tmux_available
    get_two_panes
}

setup() {
    # Reset focus state for clean test (we own this session)
    tmux -L "$SOCKET" set-option -pu -t "$PANE_A" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$PANE_B" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set -g @last_focused_pane "" 2>/dev/null || true
    tmux -L "$SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null || true
    tmux -L "$SOCKET" set -g @focus_hook_running "0" 2>/dev/null || true
    # Drain any stale coordinator-wake signals from previous tests
    for _ in 1 2 3; do timeout 0.1 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true; done
}

teardown() {
    :
}

# ============================================================
# Tests
# ============================================================

test_focus_in_sets_pane_user_focused() {
    # When a pane receives focus, @pane_user_focused should be set to 1

    # Clear any existing focus state and ensure we start on a different pane
    tmux -L "$SOCKET" set-option -pu -t "$PANE_A" @pane_user_focused 2>/dev/null || true
    select_pane "$PANE_B"
    sleep 0.2

    # Now select PANE_A (triggers after-select-pane hook → pane-focus-style.sh)
    select_pane "$PANE_A"
    sleep 0.3

    local focused
    focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_A" '#{@pane_user_focused}' 2>/dev/null || echo "")

    assert_eq "1" "$focused" "@pane_user_focused should be 1 on focused pane"
}

test_focus_out_clears_pane_user_focused() {
    # When user switches away from a pane, @pane_user_focused should be cleared

    # Set PANE_A as focused
    tmux -L "$SOCKET" set-option -p -t "$PANE_A" @pane_user_focused "1" 2>/dev/null
    tmux -L "$SOCKET" set -g @last_focused_pane "$PANE_A" 2>/dev/null

    # Switch to PANE_B (PANE_A loses focus)
    select_pane "$PANE_B"
    sleep 0.3

    local a_focused
    a_focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_A" '#{@pane_user_focused}' 2>/dev/null || echo "")

    # @pane_user_focused should be cleared (empty or 0) on the pane that lost focus
    if [[ "$a_focused" == "1" ]]; then
        fail "@pane_user_focused should be cleared on unfocused pane" "empty or 0" "$a_focused"
    else
        pass "@pane_user_focused cleared on unfocused pane"
    fi
}

test_focus_switch_sets_new_clears_old() {
    # Full focus switch: A focused → switch to B → A cleared, B set

    # Start with A focused
    select_pane "$PANE_A"
    sleep 0.3

    # Now switch to B
    select_pane "$PANE_B"
    sleep 0.3

    local a_focused b_focused
    a_focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_A" '#{@pane_user_focused}' 2>/dev/null || echo "")
    b_focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_B" '#{@pane_user_focused}' 2>/dev/null || echo "")

    if [[ "$a_focused" == "1" ]]; then
        fail "PANE_A should not be focused after switching to PANE_B" "empty or 0" "$a_focused"
    else
        pass "PANE_A @pane_user_focused cleared after switch"
    fi

    assert_eq "1" "$b_focused" "PANE_B @pane_user_focused should be 1 after focus"
}

test_missing_pane_user_focused_treated_as_not_focused() {
    # When @pane_user_focused is not set at all, it should read as empty (not focused)
    # This tests the graceful skip behavior for coordinate-wait

    # Clear the variable entirely
    tmux -L "$SOCKET" set-option -pu -t "$PANE_A" @pane_user_focused 2>/dev/null || true

    local focused
    focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_A" '#{@pane_user_focused}' 2>/dev/null || echo "")

    if [[ "$focused" == "1" ]]; then
        fail "Unset @pane_user_focused should not read as focused" "empty" "$focused"
    else
        pass "Unset @pane_user_focused reads as not focused (graceful skip)"
    fi
}

test_coordinator_wake_fired_on_focus_out() {
    # When a pane loses focus, coordinator-wake signal should be fired
    # This wakes coordinate-wait to re-sweep (newly eligible pane)

    # Start a background wait-for with short timeout
    local wake_file="/tmp/test-wake-$$"
    (timeout 3 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null && echo "WOKE" > "$wake_file") &
    local wait_pid=$!

    sleep 0.3  # Let wait-for register

    # Set PANE_A as focused, then switch to trigger focus-out wake
    tmux -L "$SOCKET" set-option -p -t "$PANE_A" @pane_user_focused "1" 2>/dev/null
    tmux -L "$SOCKET" set -g @last_focused_pane "$PANE_A" 2>/dev/null
    select_pane "$PANE_B"

    # Wait for the background process (should complete quickly if woken)
    sleep 0.5

    if [[ -f "$wake_file" ]]; then
        pass "coordinator-wake fired on focus-out"
    else
        # Check if process is still running (not yet woken)
        if kill -0 "$wait_pid" 2>/dev/null; then
            kill "$wait_pid" 2>/dev/null || true
            wait "$wait_pid" 2>/dev/null || true
            fail "coordinator-wake should be fired on focus-out" "signal sent" "no signal detected"
        else
            # Process exited but no wake_file — might have been timeout
            fail "coordinator-wake should be fired on focus-out" "signal sent" "process exited without wake"
        fi
    fi

    # Cleanup
    wait "$wait_pid" 2>/dev/null || true
    : > "$wake_file" 2>/dev/null || true
}

# ============================================================
# Category: Focus Hook Guards
# ============================================================

test_suppress_hook_blocks_focus_tracking() {
    # F1: When @suppress_focus_hook=1, selecting a pane should NOT set @pane_user_focused
    # Tests line 31-33 suppress guard in pane-focus-style.sh

    # Clear focus state and set suppress flag
    tmux -L "$SOCKET" set-option -pu -t "$PANE_A" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set -g @suppress_focus_hook "1" 2>/dev/null

    # Select PANE_A (triggers after-select-pane hook)
    select_pane "$PANE_A"
    sleep 0.3

    local focused
    focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_A" '#{@pane_user_focused}' 2>/dev/null || echo "")

    # Should NOT be set because suppress is active
    if [[ "$focused" == "1" ]]; then
        fail "F1: @pane_user_focused should NOT be set when suppress hook is active" "empty" "$focused"
    else
        pass "F1: suppress hook prevents @pane_user_focused from being set"
    fi

    # Cleanup: clear suppress flag
    tmux -L "$SOCKET" set -g @suppress_focus_hook "0" 2>/dev/null
}

test_no_wake_on_first_focus() {
    # F2: When @last_focused_pane is empty (first focus), coordinator-wake should NOT fire
    # Tests line 51 condition — when LAST is empty, focus-out block is skipped

    # Clear last focused pane (simulate first-ever focus)
    tmux -L "$SOCKET" set -g @last_focused_pane "" 2>/dev/null

    # Drain any stale coordinator-wake signals
    timeout 0.2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true

    # Start a background wait-for to detect if wake fires
    local wake_file="/tmp/test-wake-first-$$"
    rm -f "$wake_file"
    (timeout 2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null && echo "WOKE" > "$wake_file") &
    local wait_pid=$!

    sleep 0.3  # Let wait-for register

    # Select a pane (first focus — no previous pane)
    select_pane "$PANE_A"
    sleep 0.5

    # Check if wake was fired (it should NOT be)
    if [[ -f "$wake_file" && "$(cat "$wake_file" 2>/dev/null)" == "WOKE" ]]; then
        fail "F2: coordinator-wake should NOT fire on first focus (no previous pane)" "no signal" "signal detected"
    else
        pass "F2: no coordinator-wake on first focus (no previous pane)"
    fi

    # Cleanup
    kill "$wait_pid" 2>/dev/null || true
    wait "$wait_pid" 2>/dev/null || true
    rm -f "$wake_file"
}

test_same_pane_focus_noop() {
    # F3: When CURR==LAST (re-focusing same pane), should be a no-op
    # Tests line 51 condition `LAST != CURR` — same-pane focus skips unfocus block

    # Set PANE_A as the last focused and currently focused
    tmux -L "$SOCKET" set -g @last_focused_pane "$PANE_A" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$PANE_A" @pane_user_focused "1" 2>/dev/null

    # Drain stale signals aggressively (live fleet may have queued multiple)
    for _ in 1 2 3 4 5; do timeout 0.1 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true; done

    # Start a background wait-for to detect if wake fires
    local wake_file="/tmp/test-wake-same-$$"
    rm -f "$wake_file"
    (timeout 1.5 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null && echo "WOKE" > "$wake_file") &
    local wait_pid=$!
    sleep 0.2

    # Re-select the same pane
    select_pane "$PANE_A"
    sleep 0.3

    # @pane_user_focused should still be set
    local focused
    focused=$(tmux -L "$SOCKET" display-message -p -t "$PANE_A" '#{@pane_user_focused}' 2>/dev/null || echo "")
    assert_eq "1" "$focused" "F3a: @pane_user_focused stays set on same-pane focus"

    # coordinator-wake should NOT fire (no pane lost focus)
    if [[ -f "$wake_file" && "$(cat "$wake_file" 2>/dev/null)" == "WOKE" ]]; then
        fail "F3b: coordinator-wake should NOT fire on same-pane focus" "no signal" "signal detected"
    else
        pass "F3b: no coordinator-wake on same-pane focus"
    fi

    # Cleanup
    kill "$wait_pid" 2>/dev/null || true
    wait "$wait_pid" 2>/dev/null || true
    rm -f "$wake_file"
}

# ============================================================
# Run
# ============================================================

init_test_session

run_test test_focus_in_sets_pane_user_focused
run_test test_focus_out_clears_pane_user_focused
run_test test_focus_switch_sets_new_clears_old
run_test test_missing_pane_user_focused_treated_as_not_focused
run_test test_coordinator_wake_fired_on_focus_out
run_test test_suppress_hook_blocks_focus_tracking
run_test test_no_wake_on_first_focus
run_test test_same_pane_focus_noop
exit_with_results
