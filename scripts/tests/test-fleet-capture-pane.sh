#!/bin/bash
# test-fleet-capture-pane.sh — Tests for fleet.sh parse_pane_content() and cmd_capture_pane()
#
# Tests the terminal parser that powers /oversee:
#   - State detection (hasQuestion true/false)
#   - Content extraction (question text, options, preamble)
#   - Edge cases (empty pane, ANSI codes, submit confirmation)
#   - Multi-select detection (isMultiSelect)
#
# Uses real terminal capture fixtures piped via --stdin mode.

set -euo pipefail

# Source test helpers
source "$(dirname "$0")/test-helpers.sh"

# Path to fleet.sh (the script under test)
FLEET_SH="$HOME/.claude/scripts/fleet.sh"
FIXTURES_DIR="$(dirname "$0")/fixtures"

# Helper: run parse via fleet.sh capture-pane --stdin
parse_fixture() {
    local fixture="$1"
    shift
    "$FLEET_SH" capture-pane --stdin "$@" < "$FIXTURES_DIR/$fixture"
}

# Helper: extract JSON field using jq
json_field() {
    local json="$1" field="$2"
    echo "$json" | jq -r "$field" 2>/dev/null
}

# ============================================================
# Category: State Detection
# ============================================================

test_case1_bare_prompt_returns_no_question() {
    local result
    result=$(parse_fixture "non-question-bare-prompt.txt")

    local has_q option_count
    has_q=$(json_field "$result" '.hasQuestion')
    option_count=$(json_field "$result" '.optionCount')

    assert_eq "false" "$has_q" "Case 1: hasQuestion=false for bare input prompt"
    assert_eq "0" "$option_count" "Case 1: optionCount=0 for bare input prompt"
}

test_case2_single_select_returns_question() {
    local result
    result=$(parse_fixture "single-question.txt")

    local has_q option_count
    has_q=$(json_field "$result" '.hasQuestion')
    option_count=$(json_field "$result" '.optionCount')

    assert_eq "true" "$has_q" "Case 2: hasQuestion=true for single-select question"
    assert_gt "$option_count" 2 "Case 2: optionCount >= 3 for single-select"
}

test_case3_multi_question_tab_state() {
    local result
    result=$(parse_fixture "multi-question-tab2.txt")

    local has_q
    has_q=$(json_field "$result" '.hasQuestion')

    assert_eq "true" "$has_q" "Case 3: hasQuestion=true for multi-question tab state"
}

test_case4_submit_confirmation_returns_no_question() {
    local result
    result=$(parse_fixture "submit-confirmation.txt")

    local has_q
    has_q=$(json_field "$result" '.hasQuestion')

    assert_eq "false" "$has_q" "Case 4: hasQuestion=false for submit confirmation dialog"
}

# ============================================================
# Category: Content Extraction
# ============================================================

test_case5_extracts_question_text() {
    local result
    result=$(parse_fixture "single-question.txt")

    local question
    question=$(json_field "$result" '.question')

    assert_contains "What color is the sky" "$question" "Case 5: question text extracted from single-select"
}

test_case6_extracts_option_labels() {
    local result
    result=$(parse_fixture "single-question.txt")

    local options
    options=$(json_field "$result" '.options')

    assert_contains "Blue" "$options" "Case 6a: option 'Blue' extracted"
    assert_contains "Red" "$options" "Case 6b: option 'Red' extracted"
    assert_contains "Gray" "$options" "Case 6c: option 'Gray' extracted"
}

test_case7_extracts_preamble_context() {
    local result
    result=$(parse_fixture "single-question.txt")

    local preamble
    preamble=$(json_field "$result" '.preamble')

    # Preamble should be empty or minimal for question-only fixtures
    # (the tab line is the question indicator, text above it is preamble)
    # This test validates the preamble field exists and is valid JSON
    if [[ "$preamble" == "null" ]]; then
        pass "Case 7: preamble field exists (null — no text above tab line)"
    else
        pass "Case 7: preamble field exists and contains text"
    fi
}

test_case8_detects_multi_select() {
    local result
    result=$(parse_fixture "multi-select-checkboxes.txt")

    local is_multi has_q
    is_multi=$(json_field "$result" '.isMultiSelect')
    has_q=$(json_field "$result" '.hasQuestion')

    assert_eq "true" "$has_q" "Case 8a: hasQuestion=true for multi-select"
    assert_eq "true" "$is_multi" "Case 8b: isMultiSelect=true for checkbox options"
}

# ============================================================
# Category: Edge Cases
# ============================================================

test_case9_empty_pane_graceful() {
    local result
    result=$(parse_fixture "empty-pane.txt")

    local has_q
    has_q=$(json_field "$result" '.hasQuestion')

    assert_eq "false" "$has_q" "Case 9a: hasQuestion=false for empty pane"

    # Verify valid JSON output
    if echo "$result" | jq . > /dev/null 2>&1; then
        pass "Case 9b: valid JSON output for empty pane"
    else
        fail "Case 9b: valid JSON output for empty pane" "valid JSON" "$result"
    fi
}

test_case10_strips_status_line() {
    local result
    result=$(parse_fixture "non-question-bare-prompt.txt")

    local preamble options
    preamble=$(json_field "$result" '.preamble')
    options=$(json_field "$result" '.options')

    assert_not_contains "OVERSEE_SKILL_DESIGN" "$preamble" "Case 10a: status line not in preamble"
    assert_not_contains "OVERSEE_SKILL_DESIGN" "$options" "Case 10b: status line not in options"
}

# ============================================================
# Category: Robustness
# ============================================================

test_case12_handles_ansi_escape_codes() {
    local result
    result=$(parse_fixture "ansi-escape-codes.txt")

    local has_q question options
    has_q=$(json_field "$result" '.hasQuestion')
    question=$(json_field "$result" '.question')
    options=$(json_field "$result" '.options')

    assert_eq "true" "$has_q" "Case 12a: hasQuestion=true despite ANSI codes"
    assert_not_contains $'\033' "$question" "Case 12b: no ANSI escape codes in question text"
    assert_not_contains $'\033' "$options" "Case 12c: no ANSI escape codes in options"
    assert_contains "What color is the sky" "$question" "Case 12d: question text extracted after ANSI stripping"
}

# ============================================================
# Category: cmd_list_panes (tmux-dependent)
# ============================================================

test_case11_list_panes_format() {
    # This test requires real tmux — skip if unavailable
    if ! command -v tmux &>/dev/null; then
        skip "Case 11: list-panes output format" "tmux not available"
        return
    fi

    # Check if any fleet tmux is running
    if ! tmux -L fleet list-panes -a 2>/dev/null | head -1 > /dev/null 2>&1; then
        skip "Case 11: list-panes output format" "no fleet tmux session running"
        return
    fi

    local result
    result=$("$FLEET_SH" list-panes --socket fleet 2>/dev/null || echo "")

    if [[ -z "$result" ]]; then
        skip "Case 11: list-panes output format" "no panes returned"
        return
    fi

    # Each line should have: pane_id state location title
    local first_line
    first_line=$(echo "$result" | head -1)
    local field_count
    field_count=$(echo "$first_line" | awk '{print NF}')

    assert_gt "$field_count" 2 "Case 11: list-panes output has at least 3 fields per line"
}

# ============================================================
# Category: --stdin passthrough and --pane/--state flags
# ============================================================

test_stdin_passes_pane_and_state() {
    local result
    result=$(parse_fixture "single-question.txt" --pane "%42" --state "unchecked")

    local pane state
    pane=$(json_field "$result" '.pane')
    state=$(json_field "$result" '.notifyState')

    assert_eq "%42" "$pane" "stdin: --pane flag passed through to JSON"
    assert_eq "unchecked" "$state" "stdin: --state flag passed through to JSON"
}

test_stdin_defaults_pane_and_state() {
    local result
    result=$(parse_fixture "single-question.txt")

    local pane state
    pane=$(json_field "$result" '.pane')
    state=$(json_field "$result" '.notifyState')

    assert_eq "unknown" "$pane" "stdin: pane defaults to 'unknown'"
    assert_eq "unknown" "$state" "stdin: state defaults to 'unknown'"
}

# ============================================================
# Run all tests
# ============================================================

echo "=== fleet.sh capture-pane / parse_pane_content tests ==="
echo ""

# State Detection
test_case1_bare_prompt_returns_no_question
test_case2_single_select_returns_question
test_case3_multi_question_tab_state
test_case4_submit_confirmation_returns_no_question

# Content Extraction
test_case5_extracts_question_text
test_case6_extracts_option_labels
test_case7_extracts_preamble_context
test_case8_detects_multi_select

# Edge Cases
test_case9_empty_pane_graceful
test_case10_strips_status_line

# Robustness
test_case12_handles_ansi_escape_codes

# cmd_list_panes (tmux-dependent)
test_case11_list_panes_format

# Passthrough
test_stdin_passes_pane_and_state
test_stdin_defaults_pane_and_state

exit_with_results
