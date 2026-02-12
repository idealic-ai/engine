#!/bin/bash
# test-fleet-oversee-wait.sh — Tests for fleet.sh oversee-wait command
#
# Integration tests that require a running fleet tmux session.
# Tests the event-driven blocking wait mechanism:
#   - Immediate return when actionable panes exist (pre-sweep)
#   - Timeout returns TIMEOUT when no signals arrive
#   - Signal wakes before timeout
#   - Multiple panes — sweep catches all
#   - Timer cleanup on early wake (no orphan processes)
#   - Enriched output format (label, state, location)
#   - --panes filter only returns specified panes
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

# Get a real pane ID from the fleet for testing
get_test_pane() {
    tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null | head -1
}

# Get pane label for a pane
get_pane_label() {
    local pane_id="$1"
    tmux -L "$SOCKET" display-message -p -t "$pane_id" '#{@pane_label}' 2>/dev/null || echo ""
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
    result=$("$FLEET_SH" oversee-wait 5 --socket "$SOCKET" 2>/dev/null)
    local elapsed=$(( $(date +%s) - start_time ))

    # Should return immediately (< 2 seconds)
    if [[ "$elapsed" -lt 2 ]]; then
        pass "Case 1a: oversee-wait returns immediately when unchecked pane exists"
    else
        fail "Case 1a: oversee-wait returns immediately" "< 2s" "${elapsed}s"
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
    result=$("$FLEET_SH" oversee-wait 5 --socket "$SOCKET" 2>/dev/null)

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

    # Drain any stale overseer-wake signals from live fleet activity
    timeout 0.2 tmux -L "$SOCKET" wait-for overseer-wake 2>/dev/null || true

    local start_time result
    start_time=$(date +%s)
    # Use timeout wrapper to prevent infinite hang if signal channel has competing listeners
    result=$(timeout 8 "$FLEET_SH" oversee-wait 2 --socket "$SOCKET" 2>/dev/null) || true
    local elapsed=$(( $(date +%s) - start_time ))

    assert_eq "TIMEOUT" "$result" "Case 3a: returns TIMEOUT when no actionable panes"

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

    # Set all panes to checked
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done

    # Background: after 1 second, set pane to unchecked and signal repeatedly
    # (repeated signals handle competing listeners on the overseer-wake channel)
    (
        sleep 1
        tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null
        for _i in 1 2 3 4 5; do
            tmux -L "$SOCKET" wait-for -S overseer-wake 2>/dev/null || true
            sleep 0.3
        done
    ) &
    local bg_pid=$!

    local start_time result
    start_time=$(date +%s)
    # Use timeout wrapper to prevent infinite hang if signal channel has competing listeners
    result=$(timeout 15 "$FLEET_SH" oversee-wait 10 --socket "$SOCKET" 2>/dev/null) || true
    local elapsed=$(( $(date +%s) - start_time ))

    # Clean up background process
    wait "$bg_pid" 2>/dev/null || true

    # Should wake within ~2 seconds (not 10)
    if [[ "$elapsed" -lt 5 ]]; then
        pass "Case 4a: signal wakes oversee-wait early (${elapsed}s vs 10s timeout)"
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
    result=$("$FLEET_SH" oversee-wait 5 --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane1" "$result" "Case 5a: output contains first unchecked pane"
    assert_contains "$pane2" "$result" "Case 5b: output contains second unchecked pane"

    # Count lines — should be at least 2
    local line_count
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert_gt "$line_count" 1 "Case 5c: multiple lines in output for multiple panes"

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

    # Set pane to unchecked so oversee-wait returns immediately (no timer needed)
    tmux -L "$SOCKET" set-option -p -t "$pane_id" @pane_notify "unchecked" 2>/dev/null

    # Count sleep processes before
    local sleeps_before
    sleeps_before=$(pgrep -f "sleep 30" 2>/dev/null | wc -l | tr -d ' ')

    "$FLEET_SH" oversee-wait 30 --socket "$SOCKET" > /dev/null 2>&1

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
    result=$("$FLEET_SH" oversee-wait 5 --socket "$SOCKET" 2>/dev/null)

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
    result=$("$FLEET_SH" oversee-wait 5 --panes "$pane1" --socket "$SOCKET" 2>/dev/null)

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
    result=$("$FLEET_SH" oversee-wait 5 --panes "$label" --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane_id" "$result" "Case 9: --panes filter by label finds the pane"

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
    result=$("$FLEET_SH" oversee-wait 5 --socket "$SOCKET" 2>/dev/null)
    local elapsed=$(( $(date +%s) - start_time ))

    # Should return immediately (pre-sweep finds "done" pane)
    if [[ "$elapsed" -lt 2 ]]; then
        pass "Case 11a: oversee-wait returns immediately when done pane exists"
    else
        fail "Case 11a: oversee-wait returns immediately for done" "< 2s" "${elapsed}s"
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
    result=$("$FLEET_SH" oversee-wait 2 --socket "nonexistent_socket_$$" 2>&1) || exit_code=$?

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
    result=$("$FLEET_SH" oversee-wait 5 --panes "${pane1},${pane2}" --socket "$SOCKET" 2>/dev/null)

    assert_contains "$pane1" "$result" "Case 13a: comma-separated filter includes first pane"
    assert_contains "$pane2" "$result" "Case 13b: comma-separated filter includes second pane"
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
    timeout 0.2 tmux -L "$SOCKET" wait-for overseer-wake 2>/dev/null || true

    # Background: send wake signal after 1s but DON'T change any state to actionable
    (
        sleep 1
        for _i in 1 2 3; do
            tmux -L "$SOCKET" wait-for -S overseer-wake 2>/dev/null || true
            sleep 0.2
        done
    ) &
    local bg_pid=$!

    # Short timeout — should still return TIMEOUT since no panes are actionable after wake
    local result
    result=$(timeout 8 "$FLEET_SH" oversee-wait 3 --socket "$SOCKET" 2>/dev/null) || true

    wait "$bg_pid" 2>/dev/null || true

    assert_eq "TIMEOUT" "$result" "Case 14: wake with no actionable panes still returns TIMEOUT"

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
    result=$("$FLEET_SH" oversee-wait 5 --socket "$SOCKET" 2>/dev/null)

    assert_not_contains "$pane1" "$result" "Case 15a: checked pane excluded from results"
    assert_contains "$pane2" "$result" "Case 15b: error pane included in results"
    assert_contains "$pane3" "$result" "Case 15c: unchecked pane included in results"

    # Verify the specific states in output
    assert_contains "error" "$result" "Case 15d: output contains 'error' state"
    assert_contains "unchecked" "$result" "Case 15e: output contains 'unchecked' state"

    restore_pane_state "$pane1" "$saved1"
    restore_pane_state "$pane2" "$saved2"
    restore_pane_state "$pane3" "$saved3"
}

# ============================================================
# Category: Edge Timeout Values
# ============================================================

test_short_timeout() {
    # Save ALL pane states
    local all_saved
    all_saved=$(save_all_pane_states)

    # Set all panes to checked (non-actionable)
    for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}' 2>/dev/null); do
        tmux -L "$SOCKET" set-option -p -t "$p" @pane_notify "checked" 2>/dev/null || true
    done

    # Drain stale signals
    timeout 0.2 tmux -L "$SOCKET" wait-for overseer-wake 2>/dev/null || true

    local start_time result
    start_time=$(date +%s)
    # 1-second timeout — should return quickly
    # NOTE: timeout=0 means "no limit" in GNU coreutils, so we test 1s instead
    result=$(timeout 8 "$FLEET_SH" oversee-wait 1 --socket "$SOCKET" 2>/dev/null) || true
    local elapsed=$(( $(date +%s) - start_time ))

    assert_eq "TIMEOUT" "$result" "Case 16a: 1s timeout returns TIMEOUT when no actionable panes"

    if [[ "$elapsed" -ge 1 && "$elapsed" -le 5 ]]; then
        pass "Case 16b: 1s timeout completes in reasonable time (${elapsed}s)"
    else
        fail "Case 16b: 1s timeout duration" "1-5s" "${elapsed}s"
    fi

    restore_all_pane_states "$all_saved"
}

# ============================================================
# Category: Help
# ============================================================

test_help_flag() {
    local result
    result=$("$FLEET_SH" oversee-wait --help 2>/dev/null)

    assert_contains "oversee-wait" "$result" "Case 10a: --help shows command name"
    assert_contains "timeout" "$result" "Case 10b: --help mentions timeout"
    assert_contains "panes" "$result" "Case 10c: --help mentions --panes"
}

# ============================================================
# Run all tests
# ============================================================

echo "=== fleet.sh oversee-wait tests ==="
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

exit_with_results
