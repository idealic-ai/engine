#!/bin/bash
# test-fleet-summary.sh — Tests for fleet.sh summary commands
#
# Integration tests that require a running fleet tmux session.
# Tests the coordinator summaries tab feature:
#   - Discovery of manager groups from @pane_manager options
#   - Summaries window creation with placeholders
#   - Toggle: swap managers into/out of summaries window
#   - Edge cases: no groups, orphaned references, duplicate labels
#
# Requires: tmux with fleet socket running

set -uo pipefail

# Source test helpers
source "$(dirname "$0")/test-helpers.sh"

# Path to fleet.sh (the script under test)
FLEET_SH="$HOME/.claude/scripts/fleet.sh"

# Test socket — use the live fleet socket
SOCKET="fleet"

# Check prerequisites
check_tmux_available() {
    if ! command -v tmux &>/dev/null; then
        echo "SKIP: tmux not available"
        exit 0
    fi

    if ! tmux -L "$SOCKET" has-session 2>/dev/null; then
        echo "SKIP: No fleet tmux session running on socket '$SOCKET'"
        exit 0
    fi
}

# Get two real pane IDs from the fleet for testing
get_test_panes() {
    tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null | head -2
}

# Save @pane_manager and @pane_label for a pane
save_pane_summary_state() {
    local pane_id="$1"
    local label manager
    label=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_label}' 2>/dev/null || echo "")
    manager=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_manager}' 2>/dev/null || echo "")
    echo "${label}|${manager}"
}

# Restore @pane_manager and @pane_label for a pane
restore_pane_summary_state() {
    local pane_id="$1" saved="$2"
    local label manager
    label=$(echo "$saved" | cut -d'|' -f1)
    manager=$(echo "$saved" | cut -d'|' -f2)
    if [[ -n "$label" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_label "$label" 2>/dev/null || true
    fi
    if [[ -n "$manager" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_manager "$manager" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -p -t "$pane_id" -u @pane_manager 2>/dev/null || true
    fi
}

# Save ALL pane summary states
save_all_summary_states() {
    tmux -L "$SOCKET" list-panes -a -F '#{pane_id}|#{@pane_label}|#{@pane_manager}' 2>/dev/null || echo ""
}

# Restore ALL pane summary states
restore_all_summary_states() {
    local saved="$1"
    while IFS='|' read -r pid label manager; do
        [[ -z "$pid" ]] && continue
        if [[ -n "$label" ]]; then
            tmux -L "$SOCKET" set-option -p -t "$pid" @pane_label "$label" 2>/dev/null || true
        fi
        if [[ -n "$manager" ]]; then
            tmux -L "$SOCKET" set-option -p -t "$pid" @pane_manager "$manager" 2>/dev/null || true
        else
            tmux -L "$SOCKET" set-option -p -t "$pid" -u @pane_manager 2>/dev/null || true
        fi
    done <<< "$saved"
}

# Clean up summaries window if created during tests
cleanup_summaries_window() {
    local sw
    sw=$(tmux -L "$SOCKET" list-windows -F '#{window_id} #{window_name}' 2>/dev/null | awk '$2 == "summaries" { print $1; exit }')
    if [[ -n "$sw" ]]; then
        tmux -L "$SOCKET" kill-window -t "$sw" 2>/dev/null || true
    fi
}

# ============================================================
# Category: Discovery
# ============================================================

test_discover_groups_basic() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "discover groups basic" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_summary_state "$pane1")
    saved2=$(save_pane_summary_state "$pane2")

    # Set pane1 as manager (via label), pane2 as worker (declares pane1 as manager)
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "TestManager" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "TestManager" 2>/dev/null

    local result
    result=$("$FLEET_SH" summary list --socket "$SOCKET" 2>/dev/null)

    assert_contains "TestManager" "$result" "Case 1a: summary list shows manager label"
    assert_contains "$pane1" "$result" "Case 1b: summary list shows manager pane ID"

    # Clean up
    restore_pane_summary_state "$pane1" "$saved1"
    restore_pane_summary_state "$pane2" "$saved2"
}

test_discover_no_groups() {
    # Save all states, clear @pane_manager from all panes
    local all_saved
    all_saved=$(save_all_summary_states)

    # Clear all @pane_manager options
    for pid in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$pid" -u @pane_manager 2>/dev/null || true
    done

    local result
    result=$("$FLEET_SH" summary list --socket "$SOCKET" 2>/dev/null)

    assert_contains "No coordinator groups" "$result" "Case 2: summary list reports no groups when none exist"

    restore_all_summary_states "$all_saved"
}

test_discover_orphaned_manager() {
    local pane1
    pane1=$(get_test_panes | head -1)
    [[ -z "$pane1" ]] && { skip "orphaned manager" "no panes available"; return; }

    local saved1
    saved1=$(save_pane_summary_state "$pane1")

    # Set pane1 to declare a manager that doesn't exist
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_manager "NonExistentManager" 2>/dev/null

    local result stderr_output
    stderr_output=$("$FLEET_SH" summary list --socket "$SOCKET" 2>&1 1>/dev/null) || true

    assert_contains "WARNING" "$stderr_output" "Case 3a: orphaned manager reference produces warning"
    assert_contains "NonExistentManager" "$stderr_output" "Case 3b: warning mentions the orphaned name"

    restore_pane_summary_state "$pane1" "$saved1"
}

# ============================================================
# Category: Summary Setup
# ============================================================

test_summary_setup_creates_window() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "summary setup" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_summary_state "$pane1")
    saved2=$(save_pane_summary_state "$pane2")

    # Ensure no summaries window exists
    cleanup_summaries_window

    # Set up a manager group
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "SetupManager" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "SetupManager" 2>/dev/null

    local result
    result=$("$FLEET_SH" summary setup --socket "$SOCKET" 2>/dev/null)

    assert_contains "Created summaries window" "$result" "Case 4a: setup creates summaries window"

    # Verify the window exists
    local sw
    sw=$(tmux -L "$SOCKET" list-windows -F '#{window_name}' 2>/dev/null | grep -c "summaries" || echo "0")
    assert_eq "1" "$sw" "Case 4b: summaries window exists after setup"

    # Verify placeholder has the correct label
    local placeholder_label
    placeholder_label=$(tmux -L "$SOCKET" list-panes -t "summaries" -F '#{@pane_label}' 2>/dev/null | head -1)
    assert_contains "SetupManager" "$placeholder_label" "Case 4c: placeholder pane has manager label"

    # Verify placeholder has @pane_manager_placeholder marker
    local placeholder_marker
    placeholder_marker=$(tmux -L "$SOCKET" list-panes -t "summaries" -F '#{@pane_manager_placeholder}' 2>/dev/null | head -1)
    assert_eq "SetupManager" "$placeholder_marker" "Case 4d: placeholder has @pane_manager_placeholder marker"

    # Clean up
    cleanup_summaries_window
    restore_pane_summary_state "$pane1" "$saved1"
    restore_pane_summary_state "$pane2" "$saved2"
}

test_summary_setup_idempotent() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "summary setup idempotent" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_summary_state "$pane1")
    saved2=$(save_pane_summary_state "$pane2")

    cleanup_summaries_window

    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "IdempotentMgr" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "IdempotentMgr" 2>/dev/null

    # Run setup twice
    "$FLEET_SH" summary setup --socket "$SOCKET" > /dev/null 2>&1
    local result
    result=$("$FLEET_SH" summary setup --socket "$SOCKET" 2>/dev/null)

    assert_contains "already exists" "$result" "Case 5: second setup is idempotent"

    cleanup_summaries_window
    restore_pane_summary_state "$pane1" "$saved1"
    restore_pane_summary_state "$pane2" "$saved2"
}

# ============================================================
# Category: Toggle
# ============================================================

test_summary_toggle_swap_in() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "toggle swap in" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_summary_state "$pane1")
    saved2=$(save_pane_summary_state "$pane2")

    cleanup_summaries_window

    # Set up manager group
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "ToggleMgr" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "ToggleMgr" 2>/dev/null

    # Record manager's original window
    local orig_window
    orig_window=$(tmux -L "$SOCKET" display-message -p -t "$pane1" '#{window_id}' 2>/dev/null)

    # Setup summaries window
    "$FLEET_SH" summary setup --socket "$SOCKET" > /dev/null 2>&1

    # Get summaries window ID
    local sw
    sw=$(tmux -L "$SOCKET" list-windows -F '#{window_id} #{window_name}' 2>/dev/null | awk '$2 == "summaries" { print $1; exit }')

    # Toggle IN
    local result
    result=$("$FLEET_SH" summary toggle --socket "$SOCKET" 2>/dev/null)

    assert_contains "Swapped" "$result" "Case 6a: toggle reports swap"
    assert_contains "into summaries" "$result" "Case 6b: toggle reports direction (into)"

    # Verify manager is now in the summaries window
    local mgr_current_window
    mgr_current_window=$(tmux -L "$SOCKET" display-message -p -t "$pane1" '#{window_id}' 2>/dev/null)
    assert_eq "$sw" "$mgr_current_window" "Case 6c: manager pane is now in summaries window"

    # Toggle BACK
    result=$("$FLEET_SH" summary toggle --socket "$SOCKET" 2>/dev/null)

    assert_contains "back to source" "$result" "Case 6d: toggle reports direction (back)"

    # Verify manager is back in original window
    mgr_current_window=$(tmux -L "$SOCKET" display-message -p -t "$pane1" '#{window_id}' 2>/dev/null)
    assert_eq "$orig_window" "$mgr_current_window" "Case 6e: manager pane returned to original window"

    cleanup_summaries_window
    restore_pane_summary_state "$pane1" "$saved1"
    restore_pane_summary_state "$pane2" "$saved2"
}

test_summary_toggle_no_groups() {
    # Save all states, clear @pane_manager from all panes
    local all_saved
    all_saved=$(save_all_summary_states)

    for pid in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$pid" -u @pane_manager 2>/dev/null || true
    done

    local result
    result=$("$FLEET_SH" summary toggle --socket "$SOCKET" 2>/dev/null)

    assert_contains "No coordinator groups" "$result" "Case 7: toggle with no groups is a no-op"

    restore_all_summary_states "$all_saved"
}

test_summary_toggle_no_summaries_window() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "toggle no summaries window" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_summary_state "$pane1")
    saved2=$(save_pane_summary_state "$pane2")

    cleanup_summaries_window

    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "NoWinMgr" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "NoWinMgr" 2>/dev/null

    local result exit_code
    result=$("$FLEET_SH" summary toggle --socket "$SOCKET" 2>/dev/null) || exit_code=$?

    assert_contains "No summaries window" "$result" "Case 8: toggle without summaries window gives helpful error"

    restore_pane_summary_state "$pane1" "$saved1"
    restore_pane_summary_state "$pane2" "$saved2"
}

# ============================================================
# Run all tests
# ============================================================

echo "=== fleet.sh summary tests ==="
echo ""

# Check prerequisites first
check_tmux_available

# Discovery
test_discover_groups_basic
test_discover_no_groups
test_discover_orphaned_manager

# Setup
test_summary_setup_creates_window
test_summary_setup_idempotent

# Toggle
test_summary_toggle_swap_in
test_summary_toggle_no_groups
test_summary_toggle_no_summaries_window

exit_with_results
