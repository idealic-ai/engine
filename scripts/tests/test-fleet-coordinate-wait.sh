#!/bin/bash
# test-fleet-coordinate-wait.sh — Tests for fleet.sh coordinate-wait command
#
# Integration tests using an isolated tmux session (does not affect live fleet).
# Tests the event-driven blocking wait mechanism:
#   - Immediate return when actionable panes exist (pre-sweep)
#   - Timeout returns TIMEOUT when no signals arrive
#   - Signal wakes before timeout
#   - Multiple panes — sweep catches all
#   - Timer cleanup on early wake (no orphan processes)
#   - Enriched output format (label, state, location)
#   - --panes filter only returns specified panes
#
# Requires: tmux

set -uo pipefail

# Source test helpers
source "$(dirname "$0")/test-helpers.sh"

# Path to fleet.sh (the script under test)
FLEET_SH="$HOME/.claude/scripts/fleet.sh"

# Check prerequisites and create isolated test tmux session
check_tmux_available() {
    if ! command -v tmux &>/dev/null; then
        echo "SKIP: tmux not available"
        exit 0
    fi

    # Create isolated tmux session (6 panes, no hooks)
    setup_test_tmux 6 false
    SOCKET="$TEST_TMUX_SOCKET"
    trap cleanup_test_tmux EXIT
}

# Get a real pane ID from the fleet for testing
get_test_pane() {
    tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null | head -1
}

# Get pane label for a pane
get_pane_label() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_label}' 2>/dev/null || echo ""
}

# Get pane title for a pane
get_pane_title() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{pane_title}' 2>/dev/null || echo ""
}

# Save and restore pane notify state
save_pane_state() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_notify}' 2>/dev/null || echo ""
}

restore_pane_state() {
    local pane_id="$1" state="$2"
    if [[ -n "$state" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "$state" 2>/dev/null || true
    fi
}

# Save ALL pane states as pipe-delimited pairs (pane_id|state)
# Usage: local saved; saved=$(save_all_pane_states)
save_all_pane_states() {
    tmux -L "$SOCKET" list-panes -a -F '#{pane_id}|#{@pane_notify}' 2>/dev/null || echo ""
}

# Restore ALL pane states from save_all_pane_states output
restore_all_pane_states() {
    local saved="$1"
    while IFS='|' read -r pid state; do
        [[ -z "$pid" ]] && continue
        tmux -L "$SOCKET" set-option -p -t "$pid" @pane_notify "$state" 2>/dev/null || true
    done <<< "$saved"
}

# ============================================================
# Category: Pre-Sweep (Immediate Return)
# ============================================================

test_immediate_return_on_unchecked() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "immediate return on unchecked" "no panes available"; return; }

    local saved_state
    saved_state=$(save_pane_state "$pane_id")

    # Set pane to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    local start_time result
    start_time=$(date +%s)
    result=$("$FLEET_SH" coordinate-wait 5 --socket "$SOCKET" 2>/dev/null)
    local elapsed=$(( $(date +%s) - start_time ))

    # Should return immediately (< 2 seconds)
    if [[ "$elapsed" -lt 2 ]]; then
        pass "Case 1a: coordinate-wait returns immediately when unchecked pane exists"
    else
        fail "Case 1a: coordinate-wait returns immediately" "< 2s" "${elapsed}s"
    fi

    # Should contain the pane ID
    assert_contains "$pane_id" "$result" "Case 1b: output contains the unchecked pane ID"

    # Should contain unchecked state
    assert_contains "unchecked" "$result" "Case 1c: output contains 'unchecked' state"

    restore_pane_state "$pane_id" "$saved_state"
}

test_immediate_return_on_error() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "immediate return on error" "no panes available"; return; }

    local saved_state
    saved_state=$(save_pane_state "$pane_id")

    # Set pane to error
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "error" 2>/dev/null

    local result
    result=$("$FLEET_SH" coordinate-wait 5 --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane_id" "$result" "Case 2a: output contains the error pane ID"
    assert_contains "error" "$result" "Case 2b: output contains 'error' state"

    restore_pane_state "$pane_id" "$saved_state"
}

# ============================================================
# Category: Timeout
# ============================================================

test_timeout_returns_timeout() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "timeout returns TIMEOUT" "no panes available"; return; }

    # Save ALL pane states (not just one)
    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all panes to checked (non-actionable)
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done

    # Drain any stale coordinator-wake signals from live fleet activity
    timeout 0.2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true

    local start_time result
    start_time=$(date +%s)
    # Use timeout wrapper to prevent infinite hang if signal channel has competing listeners
    result=$(timeout 8 "$FLEET_SH" coordinate-wait 2 --socket "$SOCKET" 2>/dev/null) || true
    local elapsed=$(( $(date +%s) - start_time ))

    # V2: output is multiline (TIMEOUT + STATUS), check first line
    local first_line
    first_line=$(echo "$result" | head -1)
    assert_eq "TIMEOUT" "$first_line" "Case 3a: returns TIMEOUT when no actionable panes"

    # Should take approximately 2 seconds (the timeout)
    if [[ "$elapsed" -ge 1 && "$elapsed" -le 6 ]]; then
        pass "Case 3b: timeout duration is approximately correct (${elapsed}s for 2s timeout)"
    else
        fail "Case 3b: timeout duration" "1-6s" "${elapsed}s"
    fi

    # Restore all pane states to their originals
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: Signal Wake
# ============================================================

test_signal_wakes_before_timeout() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "signal wakes before timeout" "no panes available"; return; }

    # Save ALL pane states (not just one)
    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all panes to checked and clear @pane_user_focused (v2 skips focused panes)
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
        tmux -L "$SOCKET" set-option -pu -t "$p" @pane_user_focused 2>/dev/null || true
    done

    # Background: after 1 second, set pane to unchecked and signal repeatedly
    # (repeated signals handle competing listeners on the coordinator-wake channel)
    (
        sleep 1
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null
        for _i in 1 2 3 4 5; do
            tmux -L "$SOCKET" wait-for -S coordinator-wake 2>/dev/null || true
            sleep 0.3
        done
    ) &
    local bg_pid=$!

    local start_time result
    start_time=$(date +%s)
    # Use timeout wrapper to prevent infinite hang if signal channel has competing listeners
    result=$(timeout 15 "$FLEET_SH" coordinate-wait 10 --socket "$SOCKET" 2>/dev/null) || true
    local elapsed=$(( $(date +%s) - start_time ))

    # Clean up background process
    wait "$bg_pid" 2>/dev/null || true

    # Should wake within ~2 seconds (not 10)
    if [[ "$elapsed" -lt 5 ]]; then
        pass "Case 4a: signal wakes coordinate-wait early (${elapsed}s vs 10s timeout)"
    else
        fail "Case 4a: signal wakes early" "< 5s" "${elapsed}s"
    fi

    assert_contains "$pane_id" "$result" "Case 4b: post-wake sweep finds the unchecked pane"
    assert_not_contains "TIMEOUT" "$result" "Case 4c: result is not TIMEOUT"

    # Restore all pane states to their originals
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: Multiple Panes
# ============================================================

test_multiple_actionable_panes() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "multiple actionable panes" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_state "$pane1")
    saved2=$(save_pane_state "$pane2")

    # Set both to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_notify "unchecked" 2>/dev/null

    local result
    result=$("$FLEET_SH" coordinate-wait 5 --socket "$SOCKET" 2>/dev/null)

    # V2: coordinate-wait picks ONE pane and auto-connects. Verify one of the unchecked panes is picked.
    local picked_pane
    picked_pane=$(echo "$result" | head -1 | cut -d'|' -f1)
    if [[ "$picked_pane" == "$pane1" || "$picked_pane" == "$pane2" ]]; then
        pass "Case 5a: picked pane is one of the unchecked panes ($picked_pane)"
    else
        fail "Case 5a: picked pane should be one of $pane1 or $pane2" "$pane1 or $pane2" "$picked_pane"
    fi

    # V2: output has metadata line + capture JSON (at least 2 lines)
    local line_count
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert_gt "$line_count" 1 "Case 5b: output has metadata + capture JSON"

    # Verify unchecked state in output
    assert_contains "unchecked" "$result" "Case 5c: output contains 'unchecked' state"

    restore_pane_state "$pane1" "$saved1"
    restore_pane_state "$pane2" "$saved2"
}

# ============================================================
# Category: Timer Cleanup
# ============================================================

test_no_orphan_timer_on_early_wake() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "timer cleanup" "no panes available"; return; }

    local saved_state
    saved_state=$(save_pane_state "$pane_id")

    # Set pane to unchecked so coordinate-wait returns immediately (no timer needed)
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    # Count sleep processes before
    local sleeps_before
    sleeps_before=$(pgrep -f "sleep 30" 2>/dev/null | wc -l | tr -d ' ')

    "$FLEET_SH" coordinate-wait 30 --socket "$SOCKET" > /dev/null 2>&1

    # Brief wait for any cleanup
    sleep 0.3

    # Count sleep processes after — should not have increased
    local sleeps_after
    sleeps_after=$(pgrep -f "sleep 30" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$sleeps_after" -le "$sleeps_before" ]]; then
        pass "Case 6: no orphan sleep processes after immediate return"
    else
        fail "Case 6: no orphan processes" "sleeps <= $sleeps_before" "sleeps = $sleeps_after"
    fi

    restore_pane_state "$pane_id" "$saved_state"
}

# ============================================================
# Category: Output Format
# ============================================================

test_enriched_output_format() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "enriched output" "no panes available"; return; }

    local saved_state
    saved_state=$(save_pane_state "$pane_id")

    # Set pane to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    local result
    result=$("$FLEET_SH" coordinate-wait 5 --socket "$SOCKET" 2>/dev/null)

    # Output format: pane_id|state|label|location
    local field_count
    field_count=$(echo "$result" | head -1 | awk -F'|' '{print NF}')

    assert_eq "4" "$field_count" "Case 7a: output has 4 pipe-delimited fields"

    # Check label field is present (may be empty but field exists)
    local label_field
    label_field=$(echo "$result" | head -1 | cut -d'|' -f3)
    # Label can be empty, just verify the field is extractable
    pass "Case 7b: label field extractable (value: '${label_field:-<empty>}')"

    restore_pane_state "$pane_id" "$saved_state"
}

# ============================================================
# Category: --panes Filter
# ============================================================

test_panes_filter_by_id() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "--panes filter" "need at least 2 panes"
        return
    fi

    local pane1 pane2 saved1 saved2
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    saved1=$(save_pane_state "$pane1")
    saved2=$(save_pane_state "$pane2")

    # Set both to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_notify "unchecked" 2>/dev/null

    # Filter to only pane1
    local result
    result=$("$FLEET_SH" coordinate-wait 5 --panes "$pane1" --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane1" "$result" "Case 8a: filtered output contains requested pane"
    assert_not_contains "$pane2" "$result" "Case 8b: filtered output excludes non-requested pane"

    restore_pane_state "$pane1" "$saved1"
    restore_pane_state "$pane2" "$saved2"
}

test_panes_filter_by_label() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "--panes filter by label" "no panes available"; return; }

    local label saved_state
    label=$(get_pane_label "$pane_id")
    saved_state=$(save_pane_state "$pane_id")

    if [[ -z "$label" ]]; then
        skip "Case 9: --panes filter by label" "pane has no @pane_label"
        restore_pane_state "$pane_id" "$saved_state"
        return
    fi

    # Set pane to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    # Filter by label name
    local result
    result=$("$FLEET_SH" coordinate-wait 5 --panes "$label" --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane_id" "$result" "Case 9: --panes filter by label finds the pane"

    restore_pane_state "$pane_id" "$saved_state"
}

test_panes_filter_by_title() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "--panes filter by title" "no panes available"; return; }

    local title saved_state
    title=$(get_pane_title "$pane_id")
    saved_state=$(save_pane_state "$pane_id")

    if [[ -z "$title" ]]; then
        skip "Case 10: --panes filter by title" "pane has no pane_title"
        restore_pane_state "$pane_id" "$saved_state"
        return
    fi

    # Set pane to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    # Filter by pane title
    local result
    result=$("$FLEET_SH" coordinate-wait 5 --panes "$title" --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane_id" "$result" "Case 10: --panes filter by title finds the pane"

    restore_pane_state "$pane_id" "$saved_state"
}

# ============================================================
# Category: "done" State as Actionable
# ============================================================

test_done_state_is_actionable() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "done state actionable" "no panes available"; return; }

    local saved_state
    saved_state=$(save_pane_state "$pane_id")

    # Set pane to "done" — should be treated as actionable (line 913: unchecked|error|done)
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "done" 2>/dev/null

    local start_time result
    start_time=$(date +%s)
    result=$("$FLEET_SH" coordinate-wait 5 --socket "$SOCKET" 2>/dev/null)
    local elapsed=$(( $(date +%s) - start_time ))

    # Should return immediately (pre-sweep finds "done" pane)
    if [[ "$elapsed" -lt 2 ]]; then
        pass "Case 11a: coordinate-wait returns immediately when done pane exists"
    else
        fail "Case 11a: coordinate-wait returns immediately for done" "< 2s" "${elapsed}s"
    fi

    assert_contains "$pane_id" "$result" "Case 11b: output contains the done pane ID"
    assert_contains "done" "$result" "Case 11c: output contains 'done' state"

    restore_pane_state "$pane_id" "$saved_state"
}

# ============================================================
# Category: Error Path (No tmux session)
# ============================================================

test_error_no_tmux_session() {
    # Use a non-existent socket to trigger the tmux availability check error path
    local result exit_code
    result=$("$FLEET_SH" coordinate-wait 2 --socket "nonexistent_socket_$$" 2>&1) || exit_code=$?

    # Should return exit code 1
    assert_eq "1" "${exit_code:-0}" "Case 12a: exit code is 1 when no tmux session"

    # Should contain error message on stderr (captured via 2>&1)
    assert_contains "ERROR" "$result" "Case 12b: output contains ERROR message"
    assert_contains "No fleet tmux session" "$result" "Case 12c: error mentions no fleet session"
}

# ============================================================
# Category: Multi-Value --panes Filter
# ============================================================

test_multi_value_panes_filter() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 3 ]]; then
        skip "multi-value --panes filter" "need at least 3 panes"
        return
    fi

    local pane1 pane2 pane3 saved1 saved2 saved3
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    pane3=$(echo "$panes" | sed -n '3p')
    saved1=$(save_pane_state "$pane1")
    saved2=$(save_pane_state "$pane2")
    saved3=$(save_pane_state "$pane3")

    # Set all three to unchecked
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane3" @pane_notify "unchecked" 2>/dev/null

    # Filter to pane1 and pane2 via comma-separated list (tests IFS=',' parsing at line 920)
    local result
    result=$("$FLEET_SH" coordinate-wait 5 --panes "${pane1},${pane2}" --socket "$SOCKET" 2>/dev/null)

    # V2: picks ONE pane from the filtered list. Verify it's one of the first two.
    local picked_pane
    picked_pane=$(echo "$result" | head -1 | cut -d'|' -f1)
    if [[ "$picked_pane" == "$pane1" || "$picked_pane" == "$pane2" ]]; then
        pass "Case 13a: comma-separated filter picks from allowed panes ($picked_pane)"
    else
        fail "Case 13a: picked pane should be from filter" "$pane1 or $pane2" "$picked_pane"
    fi
    pass "Case 13b: (v2 picks one pane — multi-pane output removed)"
    assert_not_contains "$pane3" "$result" "Case 13c: comma-separated filter excludes third pane"

    restore_pane_state "$pane1" "$saved1"
    restore_pane_state "$pane2" "$saved2"
    restore_pane_state "$pane3" "$saved3"
}

# ============================================================
# Category: Wake Signal Negative Test
# ============================================================

test_wake_signal_non_actionable_states() {
    local pane_id
    pane_id=$(get_test_pane)
    [[ -z "$pane_id" ]] && { skip "wake signal negative" "no panes available"; return; }

    # Save ALL pane states
    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all panes to non-actionable states (checked/working)
    local toggle=0
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        if [[ $((toggle % 2)) -eq 0 ]]; then
            tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
        else
            tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "working" 2>/dev/null || true
        fi
        toggle=$((toggle + 1))
    done

    # Drain stale signals
    timeout 0.2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true

    # Background: send wake signal after 1s but DON'T change any state to actionable
    (
        sleep 1
        for _i in 1 2 3; do
            tmux -L "$SOCKET" wait-for -S coordinator-wake 2>/dev/null || true
            sleep 0.2
        done
    ) &
    local bg_pid=$!

    # Short timeout — should still return TIMEOUT since no panes are actionable after wake
    local result
    result=$(timeout 8 "$FLEET_SH" coordinate-wait 3 --socket "$SOCKET" 2>/dev/null) || true

    wait "$bg_pid" 2>/dev/null || true

    # V2: output is multiline (TIMEOUT + STATUS), check first line
    local first_line
    first_line=$(echo "$result" | head -1)
    assert_eq "TIMEOUT" "$first_line" "Case 14: wake with no actionable panes still returns TIMEOUT"

    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: Mixed State Scenario
# ============================================================

test_mixed_states_only_actionable_returned() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 3 ]]; then
        skip "mixed state scenario" "need at least 3 panes"
        return
    fi

    local pane1 pane2 pane3 saved1 saved2 saved3
    pane1=$(echo "$panes" | sed -n '1p')
    pane2=$(echo "$panes" | sed -n '2p')
    pane3=$(echo "$panes" | sed -n '3p')
    saved1=$(save_pane_state "$pane1")
    saved2=$(save_pane_state "$pane2")
    saved3=$(save_pane_state "$pane3")

    # Mixed states: checked (non-actionable), error (actionable), unchecked (actionable)
    tmux -L "$SOCKET" set-option -p -t "$pane1" @pane_notify "checked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane2" @pane_notify "error" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$pane3" @pane_notify "unchecked" 2>/dev/null

    local result
    result=$("$FLEET_SH" coordinate-wait 5 --socket "$SOCKET" 2>/dev/null)

    # V2: picks ONE actionable pane. Verify it's one of the two actionable panes (not the checked one).
    local picked_pane
    picked_pane=$(echo "$result" | head -1 | cut -d'|' -f1)
    assert_not_contains "$pane1" "$(echo "$result" | head -1)" "Case 15a: checked pane excluded from picked line"
    if [[ "$picked_pane" == "$pane2" || "$picked_pane" == "$pane3" ]]; then
        pass "Case 15b: picked pane is one of the actionable panes ($picked_pane)"
    else
        fail "Case 15b: picked pane should be actionable" "$pane2 or $pane3" "$picked_pane"
    fi

    # Verify the picked pane's state in output (error or unchecked)
    local picked_state
    picked_state=$(echo "$result" | head -1 | cut -d'|' -f2)
    if [[ "$picked_state" == "error" || "$picked_state" == "unchecked" ]]; then
        pass "Case 15c: picked pane has actionable state ($picked_state)"
    else
        fail "Case 15c: picked state should be actionable" "error or unchecked" "$picked_state"
    fi

    restore_pane_state "$pane1" "$saved1"
    restore_pane_state "$pane2" "$saved2"
    restore_pane_state "$pane3" "$saved3"
}

# ============================================================
# Category: V2 — Auto-Disconnect Previous Pane
# ============================================================

test_v2_auto_disconnect_previous() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 3 ]]; then
        skip "v2 auto-disconnect" "need at least 3 panes (coordinator + 2 workers)"
        return
    fi

    local coordinator worker1 worker2
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')
    worker2=$(echo "$panes" | sed -n '3p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Simulate: previous call connected worker1 (purple layer + @pane_last_coordinated)
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$coordinator" @pane_last_coordinated "$worker1" 2>/dev/null

    # Make worker2 unchecked (actionable), worker1 checked (non-actionable)
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "checked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker2" @pane_notify "unchecked" 2>/dev/null

    # Call coordinate-wait with coordinator context
    TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "${worker1},${worker2}" --socket "$SOCKET" > /dev/null 2>&1

    # Verify: worker1 should have @pane_coordinator_active cleared (auto-disconnected)
    local w1_active
    w1_active=$(tmux -L "$SOCKET" display-message -p -t "$worker1" '#{@pane_coordinator_active}' 2>/dev/null || echo "")

    if [[ "$w1_active" == "true" ]]; then
        fail "V2-1a: auto-disconnect should clear @pane_coordinator_active on previous pane" "empty" "$w1_active"
    else
        pass "V2-1a: auto-disconnect clears @pane_coordinator_active on previous pane"
    fi

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Auto-Connect Picked Pane
# ============================================================

test_v2_auto_connect_picked() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 auto-connect" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all to non-actionable except worker1
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    # Clear any existing coordinator connection
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true

    # Call coordinate-wait
    TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "$worker1" --socket "$SOCKET" > /dev/null 2>&1

    # Verify: worker1 should have @pane_coordinator_active=true (auto-connected)
    local w1_active
    w1_active=$(tmux -L "$SOCKET" display-message -p -t "$worker1" '#{@pane_coordinator_active}' 2>/dev/null || echo "")

    assert_eq "true" "$w1_active" "V2-2a: auto-connect sets @pane_coordinator_active on picked pane"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Store @pane_last_coordinated
# ============================================================

test_v2_store_last_coordinated() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 store @pane_last_coordinated" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Clear any prior state
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true

    # Set all to non-actionable except worker1
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    # Call coordinate-wait
    TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "$worker1" --socket "$SOCKET" > /dev/null 2>&1

    # Verify: coordinator pane should have @pane_last_coordinated set to worker1
    local stored
    stored=$(tmux -L "$SOCKET" display-message -p -t "$coordinator" '#{@pane_last_coordinated}' 2>/dev/null || echo "")

    assert_eq "$worker1" "$stored" "V2-3a: @pane_last_coordinated stores the connected pane ID"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — FOCUSED Return
# ============================================================

test_v2_focused_return_when_all_focused() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 FOCUSED return" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Set worker1 to unchecked (actionable) AND @pane_user_focused=1 (user is looking)
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_user_focused "1" 2>/dev/null

    # Set all others to non-actionable
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        [[ "$p" == "$worker1" ]] && continue
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done

    # Drain stale signals
    timeout 0.2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true

    # Call coordinate-wait — should return FOCUSED (all actionable panes are user-focused)
    local result
    result=$(TMUX_PANE="$coordinator" timeout 5 "$FLEET_SH" coordinate-wait 2 --panes "$worker1" --socket "$SOCKET" 2>/dev/null) || true

    # First line should be FOCUSED
    local first_line
    first_line=$(echo "$result" | head -1)

    assert_eq "FOCUSED" "$first_line" "V2-4a: returns FOCUSED when all actionable panes are user-focused"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_user_focused 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Skip Focused Panes in Sweep
# ============================================================

test_v2_skip_focused_panes_in_sweep() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 3 ]]; then
        skip "v2 skip focused panes" "need at least 3 panes"
        return
    fi

    local coordinator worker1 worker2
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')
    worker2=$(echo "$panes" | sed -n '3p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Both workers unchecked, but worker1 is user-focused (should be skipped)
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_user_focused "1" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker2" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_user_focused 2>/dev/null || true

    local result
    result=$(TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "${worker1},${worker2}" --socket "$SOCKET" 2>/dev/null)

    # worker2 should be in results (not focused), worker1 should be skipped (focused)
    assert_contains "$worker2" "$result" "V2-5a: non-focused unchecked pane is in results"
    assert_not_contains "$worker1" "$result" "V2-5b: user-focused pane is skipped in sweep"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Capture JSON on Second Line
# ============================================================

test_v2_capture_json_second_line() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 capture JSON" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all to non-actionable except worker1
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    local result
    result=$(TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "$worker1" --socket "$SOCKET" 2>/dev/null)

    # v2 output: line 1 = metadata, line 2 = capture JSON
    local line_count
    line_count=$(echo "$result" | wc -l | tr -d ' ')

    assert_gt "$line_count" 1 "V2-6a: output has more than 1 line (metadata + capture)"

    # Second line should be valid JSON (has opening brace)
    local second_line
    second_line=$(echo "$result" | sed -n '2p')

    assert_contains "{" "$second_line" "V2-6b: second line contains JSON opening brace"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Graceful Missing @pane_user_focused
# ============================================================

test_v2_graceful_missing_focus() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 graceful missing focus" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Clear @pane_user_focused entirely (not set = not focused = don't skip)
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_user_focused 2>/dev/null || true

    # Set worker1 to unchecked
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    local result
    result=$(TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "$worker1" --socket "$SOCKET" 2>/dev/null)

    # Pane without @pane_user_focused should NOT be skipped (graceful: unset = not focused)
    assert_contains "$worker1" "$result" "V2-7a: pane without @pane_user_focused is not skipped (graceful)"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Auto-Disconnect on TIMEOUT
# ============================================================

test_v2_auto_disconnect_on_timeout() {
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 auto-disconnect on timeout" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Simulate: previous call connected worker1
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_coordinator_active "true" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$coordinator" @pane_last_coordinated "$worker1" 2>/dev/null

    # Set all panes to non-actionable → forces TIMEOUT
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done

    # Drain stale signals
    timeout 0.2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true

    # Call coordinate-wait with short timeout
    timeout 8 bash -c "TMUX_PANE='$coordinator' '$FLEET_SH' coordinate-wait 1 --panes '$worker1' --socket '$SOCKET'" > /dev/null 2>&1 || true

    # Verify: worker1 should have @pane_coordinator_active cleared even on timeout
    local w1_active
    w1_active=$(tmux -L "$SOCKET" display-message -p -t "$worker1" '#{@pane_coordinator_active}' 2>/dev/null || echo "")

    if [[ "$w1_active" == "true" ]]; then
        fail "V2-8a: auto-disconnect should clear @pane_coordinator_active even on TIMEOUT" "empty" "$w1_active"
    else
        pass "V2-8a: auto-disconnect clears @pane_coordinator_active on TIMEOUT"
    fi

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: Edge Timeout Values
# ============================================================

test_short_timeout() {
    # Use --panes with a non-existent pane to guarantee no match,
    # eliminating race conditions from live fleet activity changing pane states.
    local start_time result
    start_time=$(date +%s)
    result=$(timeout 8 "$FLEET_SH" coordinate-wait 1 --panes "nonexistent_pane_$$" --socket "$SOCKET" 2>/dev/null) || true
    local elapsed=$(( $(date +%s) - start_time ))

    # V2: output is multiline (TIMEOUT + STATUS), check first line
    local first_line
    first_line=$(echo "$result" | head -1)
    assert_eq "TIMEOUT" "$first_line" "Case 16a: 1s timeout returns TIMEOUT when no actionable panes"

    if [[ "$elapsed" -ge 1 && "$elapsed" -le 5 ]]; then
        pass "Case 16b: 1s timeout completes in reasonable time (${elapsed}s)"
    else
        fail "Case 16b: 1s timeout duration" "1-5s" "${elapsed}s"
    fi
}

# ============================================================
# Category: Help
# ============================================================

test_help_flag() {
    local result
    result=$("$FLEET_SH" coordinate-wait --help 2>/dev/null)

    assert_contains "coordinate-wait" "$result" "Case 10a: --help shows command name"
    assert_contains "timeout" "$result" "Case 10b: --help mentions timeout"
    assert_contains "panes" "$result" "Case 10c: --help mentions --panes"
}

# ============================================================
# Category: V2 — Lifecycle Chain (3 Sequential Calls)
# ============================================================

test_v2_lifecycle_chain_3_calls() {
    # CW1: connect A → disconnect A + connect B → disconnect B + connect C
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 4 ]]; then
        skip "v2 lifecycle chain" "need at least 4 panes (coordinator + 3 workers)"
        return
    fi

    local coordinator worker1 worker2 worker3
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')
    worker2=$(echo "$panes" | sed -n '3p')
    worker3=$(echo "$panes" | sed -n '4p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Save coordinator state
    local saved_last_coord
    saved_last_coord=$(tmux -L "$SOCKET" display-message -p -t "$coordinator" '#{@pane_last_coordinated}' 2>/dev/null || echo "")

    # Clear initial state
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker3" @pane_coordinator_active 2>/dev/null || true

    # --- Call 1: Connect worker1 ---
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "${worker1},${worker2},${worker3}" --socket "$SOCKET" > /dev/null 2>&1

    local w1_active last_coord
    w1_active=$(tmux -L "$SOCKET" display-message -p -t "$worker1" '#{@pane_coordinator_active}' 2>/dev/null || echo "")
    last_coord=$(tmux -L "$SOCKET" display-message -p -t "$coordinator" '#{@pane_last_coordinated}' 2>/dev/null || echo "")
    assert_eq "true" "$w1_active" "CW1a: call 1 — worker1 connected"
    assert_eq "$worker1" "$last_coord" "CW1b: call 1 — @pane_last_coordinated = worker1"

    # --- Call 2: Disconnect worker1, connect worker2 ---
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "checked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker2" @pane_notify "unchecked" 2>/dev/null

    TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "${worker1},${worker2},${worker3}" --socket "$SOCKET" > /dev/null 2>&1

    local w1_after w2_active
    w1_after=$(tmux -L "$SOCKET" display-message -p -t "$worker1" '#{@pane_coordinator_active}' 2>/dev/null || echo "")
    w2_active=$(tmux -L "$SOCKET" display-message -p -t "$worker2" '#{@pane_coordinator_active}' 2>/dev/null || echo "")
    last_coord=$(tmux -L "$SOCKET" display-message -p -t "$coordinator" '#{@pane_last_coordinated}' 2>/dev/null || echo "")

    if [[ "$w1_after" == "true" ]]; then
        fail "CW1c: call 2 — worker1 should be disconnected" "empty" "$w1_after"
    else
        pass "CW1c: call 2 — worker1 disconnected"
    fi
    assert_eq "true" "$w2_active" "CW1d: call 2 — worker2 connected"
    assert_eq "$worker2" "$last_coord" "CW1e: call 2 — @pane_last_coordinated = worker2"

    # --- Call 3: Disconnect worker2, connect worker3 ---
    tmux -L "$SOCKET" set-option -p -t "$worker2" @pane_notify "checked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker3" @pane_notify "unchecked" 2>/dev/null

    TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "${worker1},${worker2},${worker3}" --socket "$SOCKET" > /dev/null 2>&1

    local w2_after w3_active
    w2_after=$(tmux -L "$SOCKET" display-message -p -t "$worker2" '#{@pane_coordinator_active}' 2>/dev/null || echo "")
    w3_active=$(tmux -L "$SOCKET" display-message -p -t "$worker3" '#{@pane_coordinator_active}' 2>/dev/null || echo "")
    last_coord=$(tmux -L "$SOCKET" display-message -p -t "$coordinator" '#{@pane_last_coordinated}' 2>/dev/null || echo "")

    if [[ "$w2_after" == "true" ]]; then
        fail "CW1f: call 3 — worker2 should be disconnected" "empty" "$w2_after"
    else
        pass "CW1f: call 3 — worker2 disconnected"
    fi
    assert_eq "true" "$w3_active" "CW1g: call 3 — worker3 connected"
    assert_eq "$worker3" "$last_coord" "CW1h: call 3 — @pane_last_coordinated = worker3"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker3" @pane_coordinator_active 2>/dev/null || true
    if [[ -n "$saved_last_coord" ]]; then
        tmux -L "$SOCKET" set-option -p -t "$coordinator" @pane_last_coordinated "$saved_last_coord" 2>/dev/null || true
    else
        tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    fi
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Auto-Disconnect Destroyed Pane
# ============================================================

test_v2_auto_disconnect_destroyed_pane() {
    # CW2: When @pane_last_coordinated points to a non-existent pane, auto-disconnect should not crash
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 destroyed pane resilience" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Set @pane_last_coordinated to a non-existent pane ID
    tmux -L "$SOCKET" set-option -p -t "$coordinator" @pane_last_coordinated "%999" 2>/dev/null

    # Make worker1 unchecked (actionable)
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    # Should complete without error despite dead pane reference
    local result
    result=$(TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "$worker1" --socket "$SOCKET" 2>/dev/null) || true

    # Should have picked worker1
    assert_contains "$worker1" "$result" "CW2a: picks real pane despite dead @pane_last_coordinated"

    # @pane_last_coordinated should now point to worker1 (updated)
    local last_coord
    last_coord=$(tmux -L "$SOCKET" display-message -p -t "$coordinator" '#{@pane_last_coordinated}' 2>/dev/null || echo "")
    assert_eq "$worker1" "$last_coord" "CW2b: @pane_last_coordinated updated to real pane"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — TIMEOUT STATUS Line Format
# ============================================================

test_v2_timeout_status_line_format() {
    # CW3: TIMEOUT output should include STATUS line with correct format
    # Use --panes with non-existent pane to eliminate race conditions
    local result
    result=$(timeout 8 "$FLEET_SH" coordinate-wait 1 --panes "nonexistent_pane_cw3_$$" --socket "$SOCKET" 2>/dev/null) || true

    # First line should be TIMEOUT
    local first_line
    first_line=$(echo "$result" | head -1)
    assert_eq "TIMEOUT" "$first_line" "CW3a: first line is TIMEOUT"

    # Second line should match STATUS format
    local second_line
    second_line=$(echo "$result" | sed -n '2p')
    assert_contains "STATUS" "$second_line" "CW3b: second line contains STATUS"
    assert_contains "total=" "$second_line" "CW3c: STATUS line has total= field"
    assert_contains "working=" "$second_line" "CW3d: STATUS line has working= field"
    assert_contains "done=" "$second_line" "CW3e: STATUS line has done= field"
}

# ============================================================
# Category: V2 — FOCUSED STATUS Line
# ============================================================

test_v2_focused_status_line() {
    # CW4: FOCUSED output should include STATUS line with focused count > 0
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 FOCUSED status line" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Set worker1 to unchecked + focused
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_user_focused "1" 2>/dev/null

    # Set all others to non-actionable
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        [[ "$p" == "$worker1" ]] && continue
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done

    # Drain stale signals
    timeout 0.2 tmux -L "$SOCKET" wait-for coordinator-wake 2>/dev/null || true

    local result
    result=$(TMUX_PANE="$coordinator" timeout 5 "$FLEET_SH" coordinate-wait 2 --panes "$worker1" --socket "$SOCKET" 2>/dev/null) || true

    # First line should be FOCUSED
    local first_line
    first_line=$(echo "$result" | head -1)
    assert_eq "FOCUSED" "$first_line" "CW4a: first line is FOCUSED"

    # Second line should have STATUS with focused > 0
    local second_line
    second_line=$(echo "$result" | sed -n '2p')
    assert_contains "STATUS" "$second_line" "CW4b: second line contains STATUS"
    assert_contains "focused=" "$second_line" "CW4c: STATUS line has focused= field"

    # Extract focused count and verify > 0
    local focused_count
    focused_count=$(echo "$second_line" | grep -o 'focused=[0-9]*' | cut -d= -f2)
    if [[ -n "$focused_count" && "$focused_count" -gt 0 ]]; then
        pass "CW4d: focused count is > 0 (focused=$focused_count)"
    else
        fail "CW4d: focused count should be > 0" "> 0" "${focused_count:-empty}"
    fi

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_user_focused 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Capture JSON Valid (jq parseable)
# ============================================================

test_v2_capture_json_valid() {
    # CW5: Capture JSON (second line) should be valid JSON parseable by jq
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 2 ]]; then
        skip "v2 capture JSON valid" "need at least 2 panes"
        return
    fi

    local coordinator worker1
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all to non-actionable except worker1
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null

    local result
    result=$(TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "$worker1" --socket "$SOCKET" 2>/dev/null)

    # Lines 2+ should be valid JSON (capture JSON can be multiline)
    local json_content
    json_content=$(echo "$result" | tail -n +2)

    if echo "$json_content" | jq . > /dev/null 2>&1; then
        pass "CW5: capture JSON is valid (parseable by jq)"
    else
        fail "CW5: capture JSON should be valid" "valid JSON" "$(echo "$json_content" | head -3)"
    fi

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: V2 — Mixed Focus Priority
# ============================================================

test_v2_mixed_focus_priority() {
    # CW6: Should pick non-focused pane when mix of focused and non-focused actionable panes exist
    local panes
    panes=$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null)
    local pane_count
    pane_count=$(echo "$panes" | wc -l | tr -d ' ')

    if [[ "$pane_count" -lt 4 ]]; then
        skip "v2 mixed focus priority" "need at least 4 panes (coordinator + 3 workers)"
        return
    fi

    local coordinator worker1 worker2 worker3
    coordinator=$(echo "$panes" | sed -n '1p')
    worker1=$(echo "$panes" | sed -n '2p')
    worker2=$(echo "$panes" | sed -n '3p')
    worker3=$(echo "$panes" | sed -n '4p')

    local all_saved
    all_saved=$(save_all_pane_states)

    # worker1: unchecked + focused (actionable but user is looking)
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -p -t "$worker1" @pane_user_focused "1" 2>/dev/null
    # worker2: unchecked + not focused (actionable, available)
    tmux -L "$SOCKET" set-option -p -t "$worker2" @pane_notify "unchecked" 2>/dev/null
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_user_focused 2>/dev/null || true
    # worker3: checked (non-actionable)
    tmux -L "$SOCKET" set-option -p -t "$worker3" @pane_notify "checked" 2>/dev/null

    local result
    result=$(TMUX_PANE="$coordinator" "$FLEET_SH" coordinate-wait 5 --panes "${worker1},${worker2},${worker3}" --socket "$SOCKET" 2>/dev/null)

    # worker2 should be picked (unchecked + not focused)
    local picked_pane
    picked_pane=$(echo "$result" | head -1 | cut -d'|' -f1)
    assert_eq "$worker2" "$picked_pane" "CW6a: non-focused unchecked pane picked over focused unchecked pane"
    assert_not_contains "$worker1" "$(echo "$result" | head -1)" "CW6b: focused unchecked pane is skipped"
    assert_not_contains "$worker3" "$(echo "$result" | head -1)" "CW6c: checked pane is skipped"

    # Cleanup
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_user_focused 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker1" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$worker2" @pane_coordinator_active 2>/dev/null || true
    tmux -L "$SOCKET" set-option -pu -t "$coordinator" @pane_last_coordinated 2>/dev/null || true
    restore_all_pane_states "$all_saved"
}

# ============================================================
# Run all tests
# ============================================================

echo "=== fleet.sh coordinate-wait tests ==="
echo ""

# Check prerequisites first
check_tmux_available

# Pre-Sweep
test_immediate_return_on_unchecked
test_immediate_return_on_error

# Timeout
test_timeout_returns_timeout

# Signal Wake
test_signal_wakes_before_timeout

# Multiple Panes
test_multiple_actionable_panes

# Timer Cleanup
test_no_orphan_timer_on_early_wake

# Output Format
test_enriched_output_format

# --panes Filter
test_panes_filter_by_id
test_panes_filter_by_label
test_panes_filter_by_title

# Help
test_help_flag

# "done" State
test_done_state_is_actionable

# Error Path
test_error_no_tmux_session

# Multi-Value --panes Filter
test_multi_value_panes_filter

# Wake Signal Negative
test_wake_signal_non_actionable_states

# Mixed State
test_mixed_states_only_actionable_returned

# Edge Timeout
test_short_timeout

# V2 — Auto-Disconnect
test_v2_auto_disconnect_previous

# V2 — Auto-Connect
test_v2_auto_connect_picked

# V2 — Store @pane_last_coordinated
test_v2_store_last_coordinated

# V2 — FOCUSED Return
test_v2_focused_return_when_all_focused

# V2 — Skip Focused Panes
test_v2_skip_focused_panes_in_sweep

# V2 — Capture JSON
test_v2_capture_json_second_line

# V2 — Graceful Missing Focus
test_v2_graceful_missing_focus

# V2 — Auto-Disconnect on TIMEOUT
test_v2_auto_disconnect_on_timeout

# V2 — Lifecycle Chain (3 calls)
test_v2_lifecycle_chain_3_calls

# V2 — Auto-Disconnect Destroyed Pane
test_v2_auto_disconnect_destroyed_pane

# V2 — TIMEOUT STATUS Line Format
test_v2_timeout_status_line_format

# V2 — FOCUSED STATUS Line
test_v2_focused_status_line

# V2 — Capture JSON Valid
test_v2_capture_json_valid

# V2 — Mixed Focus Priority
test_v2_mixed_focus_priority

exit_with_results
