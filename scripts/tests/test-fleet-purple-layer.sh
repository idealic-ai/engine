#!/bin/bash
# test-fleet-purple-layer.sh — Tests for fleet.sh purple layer system
#
# Integration tests that require a running fleet tmux session.
# Tests the coordinator purple layer feature:
#   - _resolve_pane_color: 4-level priority (coordinator-active > manager > theme > default)
#   - _apply_notify_data: auto-disconnect clears @pane_coordinator_active on non-unchecked
#   - cmd_coordinator_connect: sets @pane_coordinator_active, triggers visual
#   - cmd_coordinator_disconnect: clears @pane_coordinator_active, triggers visual
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

# Get a single test pane
get_test_pane() {
    tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null | head -1
}

# Save purple-layer-relevant state for a pane
save_pane_purple_state() {
    local pane_id="$1"
    local label manager coordinator_active notify pane_bg
    label=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_label}' 2>/dev/null || echo "")
    manager=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_manager}' 2>/dev/null || echo "")
    coordinator_active=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_coordinator_active}' 2>/dev/null || echo "")
    notify=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_notify}' 2>/dev/null || echo "")
    pane_bg=$(tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{pane_bg}' 2>/dev/null || echo "")
    echo "${label}|${manager}|${coordinator_active}|${notify}|${pane_bg}"
}

# Restore purple-layer-relevant state for a pane
restore_pane_purple_state() {
    local pane_id="$1" saved="$2"
    local label manager coordinator_active notify pane_bg
    label=$(echo "$saved" | cut -d'|' -f1)
    manager=$(echo "$saved" | cut -d'|' -f2)
    coordinator_active=$(echo "$saved" | cut -d'|' -f3)
    notify=$(echo "$saved" | cut -d'|' -f4)
    pane_bg=$(echo "$saved" | cut -d'|' -f5)

    # Restore label
    if [[ -n "$label" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_label "$label" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -p -t "$pane_id" -u @pane_label 2>/dev/null || true
    fi

    # Restore manager
    if [[ -n "$manager" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_manager "$manager" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -p -t "$pane_id" -u @pane_manager 2>/dev/null || true
    fi

    # Restore coordinator_active
    if [[ "$coordinator_active" == "true" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_coordinator_active "true" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_coordinator_active 2>/dev/null || true
    fi

    # Restore notify
    if [[ -n "$notify" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "$notify" 2>/dev/null || true
    fi

    # Restore visual bg color
    if [[ -n "$pane_bg" ]]; then
        tmux -L "$SOCKET" select-pane -t "$pane_id" -P "bg=$pane_bg" 2>/dev/null || true
    fi
}

# Save global theme options
save_theme_state() {
    local active manager
    active=$(tmux -L "$SOCKET" show-option -gqv @fleet_theme_active 2>/dev/null || echo "")
    manager=$(tmux -L "$SOCKET" show-option -gqv @fleet_theme_manager 2>/dev/null || echo "")
    echo "${active}|${manager}"
}

# Restore global theme options
restore_theme_state() {
    local saved="$1"
    local active manager
    active=$(echo "$saved" | cut -d'|' -f1)
    manager=$(echo "$saved" | cut -d'|' -f2)

    if [[ -n "$active" ]]; then
        tmux -L "$SOCKET" set-option -g @fleet_theme_active "$active" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -gu @fleet_theme_active 2>/dev/null || true
    fi
    if [[ -n "$manager" ]]; then
        tmux -L "$SOCKET" set-option -g @fleet_theme_manager "$manager" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -gu @fleet_theme_manager 2>/dev/null || true
    fi
}

# Helper: get @pane_coordinator_active value
get_coordinator_active() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_coordinator_active}' 2>/dev/null || echo ""
}

# Helper: get pane bg color
get_pane_bg() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{pane_bg}' 2>/dev/null || echo ""
}

# ============================================================
# Category: cmd_coordinator_connect
# ============================================================

test_connect_sets_coordinator_active() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "connect sets active" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    # Clear any existing coordinator state
    tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_coordinator_active 2>/dev/null || true

    "$FLEET_SH" coordinator-connect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "true" "$result" "Case 12: coordinator-connect sets @pane_coordinator_active=true"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_connect_outputs_confirmation() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "connect confirmation" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    local result
    result=$("$FLEET_SH" coordinator-connect "$pane_id" --socket "$SOCKET" 2>/dev/null)

    assert_contains "Connected" "$result" "Case 13a: coordinator-connect outputs 'Connected'"
    assert_contains "$pane_id" "$result" "Case 13b: coordinator-connect output contains pane_id"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_connect_missing_pane_id() {
    local result exit_code=0
    result=$("$FLEET_SH" coordinator-connect 2>&1) || exit_code=$?

    assert_eq "1" "$exit_code" "Case 14a: coordinator-connect exits 1 with no pane_id"
    assert_contains "Usage" "$result" "Case 14b: coordinator-connect shows Usage with no pane_id"
}

# ============================================================
# Category: cmd_coordinator_disconnect
# ============================================================

test_disconnect_clears_coordinator_active() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "disconnect clears active" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    # Connect first
    "$FLEET_SH" coordinator-connect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    # Then disconnect
    "$FLEET_SH" coordinator-disconnect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "" "$result" "Case 15: coordinator-disconnect clears @pane_coordinator_active"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_disconnect_outputs_confirmation() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "disconnect confirmation" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    # Connect first so there's something to disconnect
    "$FLEET_SH" coordinator-connect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    local result
    result=$("$FLEET_SH" coordinator-disconnect "$pane_id" --socket "$SOCKET" 2>/dev/null)

    assert_contains "Disconnected" "$result" "Case 16a: coordinator-disconnect outputs 'Disconnected'"
    assert_contains "$pane_id" "$result" "Case 16b: coordinator-disconnect output contains pane_id"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_disconnect_missing_pane_id() {
    local result exit_code=0
    result=$("$FLEET_SH" coordinator-disconnect 2>&1) || exit_code=$?

    assert_eq "1" "$exit_code" "Case 17a: coordinator-disconnect exits 1 with no pane_id"
    assert_contains "Usage" "$result" "Case 17b: coordinator-disconnect shows Usage with no pane_id"
}

# ============================================================
# Category: _resolve_pane_color (via coordinator-connect visual)
# ============================================================

test_color_coordinator_active_dark_purple() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "coordinator active color" "no panes available"; return; }

    local saved theme_saved
    saved=$(save_pane_purple_state "$pane_id")
    theme_saved=$(save_theme_state)

    # Clear theme override so hardcoded default applies
    tmux -L "$SOCKET" set-option -gu @fleet_theme_active 2>/dev/null || true

    # Connect — triggers _apply_notify_visual → _resolve_pane_color
    "$FLEET_SH" coordinator-connect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    # Brief wait for visual to apply
    sleep 0.1

    local bg
    bg=$(get_pane_bg "$pane_id")
    assert_eq "#0d0518" "$bg" "Case 1: coordinator-active pane gets dark purple (#0d0518)"

    restore_pane_purple_state "$pane_id" "$saved"
    restore_theme_state "$theme_saved"
}

test_color_theme_override_active() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "theme override active" "no panes available"; return; }

    local saved theme_saved
    saved=$(save_pane_purple_state "$pane_id")
    theme_saved=$(save_theme_state)

    # Set theme override
    tmux -L "$SOCKET" set-option -g @fleet_theme_active "#aabbcc" 2>/dev/null

    # Connect
    "$FLEET_SH" coordinator-connect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    sleep 0.1

    local bg
    bg=$(get_pane_bg "$pane_id")
    assert_eq "#aabbcc" "$bg" "Case 6: @fleet_theme_active overrides hardcoded dark purple"

    restore_pane_purple_state "$pane_id" "$saved"
    restore_theme_state "$theme_saved"
}

test_color_manager_light_purple() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "manager light purple" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2 theme_saved
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_purple_state "$pane1")
    saved2=$(save_pane_purple_state "$pane2")
    theme_saved=$(save_theme_state)

    # Clear theme override
    tmux -L "$SOCKET" set-option -gu @fleet_theme_manager 2>/dev/null || true
    # Clear coordinator-active so manager check is reached
    tmux -L "$SOCKET" set-option -pu -t "$pane1" @pane_coordinator_active 2>/dev/null || true

    # Make pane1 a manager: pane1 has label, pane2 declares that label as manager
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "PurpleTestMgr" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "PurpleTestMgr" 2>/dev/null
    # Set a notify state so _apply_notify_visual is triggered
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_notify "checked" 2>/dev/null

    # Trigger visual refresh on pane1 via notify (uses TMUX_PANE to target)
    # Use coordinator-disconnect as a no-op visual refresh trigger
    "$FLEET_SH" coordinator-disconnect "$pane1" --socket "$SOCKET" > /dev/null 2>&1

    sleep 0.1

    local bg
    bg=$(get_pane_bg "$pane1")
    assert_eq "#1a0a2e" "$bg" "Case 2: manager pane gets light purple (#1a0a2e)"

    restore_pane_purple_state "$pane1" "$saved1"
    restore_pane_purple_state "$pane2" "$saved2"
    restore_theme_state "$theme_saved"
}

test_color_coordinator_beats_manager() {
    local panes
    panes=$(get_test_panes)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "coordinator beats manager" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2 theme_saved
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_purple_state "$pane1")
    saved2=$(save_pane_purple_state "$pane2")
    theme_saved=$(save_theme_state)

    # Clear theme overrides
    tmux -L "$SOCKET" set-option -gu @fleet_theme_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -gu @fleet_theme_manager 2>/dev/null || true

    # Make pane1 BOTH a manager AND coordinator-active
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_label "DualTestMgr" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_manager "DualTestMgr" 2>/dev/null

    # Connect as coordinator (sets active + visual)
    "$FLEET_SH" coordinator-connect "$pane1" --socket "$SOCKET" > /dev/null 2>&1

    sleep 0.1

    local bg
    bg=$(get_pane_bg "$pane1")
    assert_eq "#0d0518" "$bg" "Case 5: coordinator-active (#0d0518) beats manager (#1a0a2e)"

    restore_pane_purple_state "$pane1" "$saved1"
    restore_pane_purple_state "$pane2" "$saved2"
    restore_theme_state "$theme_saved"
}

test_color_hardcoded_defaults() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "hardcoded defaults" "no panes available"; return; }

    local saved theme_saved
    saved=$(save_pane_purple_state "$pane_id")
    theme_saved=$(save_theme_state)

    # Clear all purple layer state
    tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_manager 2>/dev/null || true
    # Clear any theme overrides for checked state
    tmux -L "$SOCKET" set-option -gu @fleet_theme_checked 2>/dev/null || true
    # Temporarily clear label so pane isn't detected as manager
    tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_label 2>/dev/null || true

    # Set notify state and trigger visual via disconnect (no-op clear + visual refresh)
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "checked" 2>/dev/null
    "$FLEET_SH" coordinator-disconnect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    sleep 0.1

    local bg
    bg=$(get_pane_bg "$pane_id")
    assert_eq "#0a1005" "$bg" "Case 4: hardcoded default for 'checked' state is #0a1005"

    restore_pane_purple_state "$pane_id" "$saved"
    restore_theme_state "$theme_saved"
}

test_color_theme_override_state() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "theme override state" "no panes available"; return; }

    local saved theme_saved
    saved=$(save_pane_purple_state "$pane_id")
    theme_saved=$(save_theme_state)

    # Save and clear the checked theme override specifically
    local orig_checked_theme
    orig_checked_theme=$(tmux -L "$SOCKET" show-option -gqv @fleet_theme_checked 2>/dev/null || echo "")

    # Clear purple layer state
    tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$pane_id" @pane_label 2>/dev/null || true

    # Set a theme override for "checked" state
    tmux -L "$SOCKET" set-option -g @fleet_theme_checked "#112233" 2>/dev/null

    # Trigger visual with checked state
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "checked" 2>/dev/null
    "$FLEET_SH" coordinator-disconnect "$pane_id" --socket "$SOCKET" > /dev/null 2>&1

    sleep 0.1

    local bg
    bg=$(get_pane_bg "$pane_id")
    assert_eq "#112233" "$bg" "Case 3: @fleet_theme_checked overrides hardcoded default"

    # Restore checked theme
    if [[ -n "$orig_checked_theme" ]]; then
        tmux -L "$SOCKET" set-option -g @fleet_theme_checked "$orig_checked_theme" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -gu @fleet_theme_checked 2>/dev/null || true
    fi

    restore_pane_purple_state "$pane_id" "$saved"
    restore_theme_state "$theme_saved"
}

# ============================================================
# Category: _apply_notify_data (Auto-Disconnect)
# ============================================================

test_auto_disconnect_on_checked() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "auto-disconnect checked" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    # Set coordinator active and ensure initial state differs from "checked" to avoid debounce
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    # Trigger notify with "checked" — should auto-disconnect
    TMUX_PANE="$pane_id" "$FLEET_SH" notify checked 2>/dev/null || true

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "" "$result" "Case 7: auto-disconnect clears @pane_coordinator_active on 'checked'"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_auto_disconnect_on_working() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "auto-disconnect working" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    TMUX_PANE="$pane_id" "$FLEET_SH" notify working 2>/dev/null || true

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "" "$result" "Case 8: auto-disconnect clears @pane_coordinator_active on 'working'"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_auto_disconnect_on_done() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "auto-disconnect done" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    TMUX_PANE="$pane_id" "$FLEET_SH" notify done 2>/dev/null || true

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "" "$result" "Case 9: auto-disconnect clears @pane_coordinator_active on 'done'"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_auto_disconnect_on_error() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "auto-disconnect error" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "checked" 2>/dev/null

    TMUX_PANE="$pane_id" "$FLEET_SH" notify error 2>/dev/null || true

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "" "$result" "Case 10: auto-disconnect clears @pane_coordinator_active on 'error'"

    restore_pane_purple_state "$pane_id" "$saved"
}

test_no_disconnect_on_unchecked() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "no disconnect unchecked" "no panes available"; return; }

    local saved
    saved=$(save_pane_purple_state "$pane_id")

    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "checked" 2>/dev/null

    TMUX_PANE="$pane_id" "$FLEET_SH" notify unchecked 2>/dev/null || true

    local result
    result=$(get_coordinator_active "$pane_id")
    assert_eq "true" "$result" "Case 11: @pane_coordinator_active preserved on 'unchecked'"

    restore_pane_purple_state "$pane_id" "$saved"
}

# ============================================================
# Run all tests
# ============================================================

echo "=== fleet.sh purple layer tests ==="
echo ""

# Check prerequisites first
check_tmux_available

# cmd_coordinator_connect
test_connect_sets_coordinator_active
test_connect_outputs_confirmation
test_connect_missing_pane_id

# cmd_coordinator_disconnect
test_disconnect_clears_coordinator_active
test_disconnect_outputs_confirmation
test_disconnect_missing_pane_id

# _resolve_pane_color (via visual)
test_color_coordinator_active_dark_purple
test_color_theme_override_active
test_color_manager_light_purple
test_color_coordinator_beats_manager
test_color_hardcoded_defaults
test_color_theme_override_state

# _apply_notify_data (auto-disconnect)
test_auto_disconnect_on_checked
test_auto_disconnect_on_working
test_auto_disconnect_on_done
test_auto_disconnect_on_error
test_no_disconnect_on_unchecked

exit_with_results
