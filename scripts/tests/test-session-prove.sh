#!/bin/bash
# ~/.claude/engine/scripts/tests/test-session-prove.sh — Hardening tests for session.sh prove
#
# Tests the prove subcommand (proof parsing regex) and the deactivation proof gate.
# Covers: happy path, regex boundary, error paths, whitespace edge cases, integration, regression.
#
# Run: bash ~/.claude/scripts/tests/test-session-prove.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/scripts/session.sh"

# ============================================================
# Helpers
# ============================================================

# Create a minimal .state.json for prove tests
create_state_json() {
  local dir="$1"
  shift
  # Remaining args are provableDebriefItems as JSON array string
  local provable="${1:-null}"
  local skill="${2:-test}"
  local debrief_template="${3:-~/.claude/skills/test/assets/TEMPLATE_TESTING.md}"

  cat > "$dir/.state.json" <<JSONEOF
{
  "skill": "$skill",
  "lifecycle": "active",
  "pid": $$,
  "debriefTemplate": "$debrief_template",
  "provableDebriefItems": $provable,
  "lastHeartbeat": "2026-02-10T00:00:00Z"
}
JSONEOF
}

# ============================================================
# Setup / Teardown
# ============================================================

setup() {
  setup_test_env "test_prove"
}

teardown() {
  cleanup_test_env
}

# ============================================================
# Category: Prove Parsing — Happy Path
# ============================================================

test_prove_single_valid_entry() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: skipped: no files touched
EOF
  )

  assert_contains "Proof recorded for 1 item(s)" "$output" \
    "prove: single valid entry reports 1 item"

  assert_json "$TEST_SESSION/.state.json" '.provenItems["§CMD_MANAGE_DIRECTIVES"]' \
    "skipped: no files touched" \
    "prove: single entry stored in provenItems"
}

test_prove_multiple_valid_entries() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: skipped: no files touched
§CMD_PROCESS_DELEGATIONS: ran: 2 bare tags processed
§CMD_DISPATCH_APPROVAL: skipped: no #needs-X tags
§CMD_CAPTURE_SIDE_DISCOVERIES: skipped: no side discoveries
§CMD_MANAGE_ALERTS: skipped: no alerts
§CMD_REPORT_LEFTOVER_WORK: ran: 1 item reported
EOF
  )

  assert_contains "Proof recorded for 6 item(s)" "$output" \
    "prove: 6 valid entries reports 6 items"

  assert_json "$TEST_SESSION/.state.json" '.provenItems | length' \
    "6" \
    "prove: provenItems has 6 keys"
}

test_prove_reports_correct_count() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: ran: updated README
§CMD_PROCESS_DELEGATIONS: skipped: none
§CMD_DISPATCH_APPROVAL: ran: 3 approved
EOF
  )

  assert_contains "Proof recorded for 3 item(s)" "$output" \
    "prove: correct count in output message"
}

# ============================================================
# Category: Prove Parsing — Regex Boundary (Edge Cases)
# ============================================================

test_prove_rejects_slash_skill_name() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' 2>&1
/delegation-review: ran: checked
EOF
  ) || true

  assert_contains "No valid proof lines" "$output" \
    "prove: /skill-name entries rejected (0 valid lines)"
}

test_prove_rejects_lowercase_cmd() {
  create_state_json "$TEST_SESSION"

  # Mix valid + lowercase — only valid should parse
  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' 2>&1
§CMD_lower_case: ran: test
§CMD_MANAGE_DIRECTIVES: ran: ok
EOF
  )

  assert_contains "Proof recorded for 1 item(s)" "$output" \
    "prove: lowercase entry rejected, valid entry kept"

  local has_lower
  has_lower=$(jq -r '.provenItems | has("§CMD_lower_case")' "$TEST_SESSION/.state.json")
  assert_eq "false" "$has_lower" \
    "prove: lowercase entry not in provenItems"
}

test_prove_rejects_numbers_in_cmd() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' 2>&1
§CMD_STEP_123: ran: test
§CMD_MANAGE_DIRECTIVES: ran: ok
EOF
  )

  assert_contains "Proof recorded for 1 item(s)" "$output" \
    "prove: entry with numbers rejected, valid entry kept"

  local has_numbers
  has_numbers=$(jq -r '.provenItems | has("§CMD_STEP_123")' "$TEST_SESSION/.state.json")
  assert_eq "false" "$has_numbers" \
    "prove: numbered entry not in provenItems"
}

test_prove_accepts_underscores() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: ran: updated README
EOF
  )

  assert_contains "Proof recorded for 1 item(s)" "$output" \
    "prove: §CMD with underscores accepted"
}

test_prove_skips_blank_lines() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: ran: first

§CMD_PROCESS_DELEGATIONS: ran: second
EOF
  )

  assert_contains "Proof recorded for 2 item(s)" "$output" \
    "prove: blank lines between entries skipped"
}

# ============================================================
# Category: Prove Parsing — Error Paths
# ============================================================

test_prove_fails_empty_stdin() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' 2>&1
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "1" "$rc" \
    "prove: empty stdin exits with code 1"
  assert_contains "No proof provided" "$output" \
    "prove: empty stdin error message"
}

test_prove_fails_all_invalid_lines() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' 2>&1
/delegation-review: ran: test
/some-other-skill: ran: test
random garbage line
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "1" "$rc" \
    "prove: all-invalid-lines exits with code 1"
  assert_contains "No valid proof lines" "$output" \
    "prove: all-invalid error message"
}

test_prove_fails_no_state_json() {
  # Use a dir without .state.json
  local empty_dir="$TMP_DIR/sessions/no_state"
  mkdir -p "$empty_dir"

  local output
  output=$(bash "$SESSION_SH" prove "$empty_dir" <<'EOF' 2>&1
§CMD_MANAGE_DIRECTIVES: ran: test
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "1" "$rc" \
    "prove: no .state.json exits with code 1"
  assert_contains "No .state.json" "$output" \
    "prove: no .state.json error message"
}

# ============================================================
# Category: Prove Parsing — Whitespace Edge Cases
# ============================================================

test_prove_colons_in_proof_value() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: ran: 2 items: done: all good
EOF
  )

  assert_contains "Proof recorded for 1 item(s)" "$output" \
    "prove: colons in proof value accepted"

  local value
  value=$(jq -r '.provenItems["§CMD_MANAGE_DIRECTIVES"]' "$TEST_SESSION/.state.json")
  assert_eq "ran: 2 items: done: all good" "$value" \
    "prove: colons in proof value preserved correctly"
}

test_prove_mixed_valid_and_invalid() {
  create_state_json "$TEST_SESSION"

  local output
  output=$(bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF'
§CMD_MANAGE_DIRECTIVES: ran: first
/delegation-review: ran: should be dropped
§CMD_PROCESS_DELEGATIONS: ran: second
EOF
  )

  assert_contains "Proof recorded for 2 item(s)" "$output" \
    "prove: mixed valid/invalid — correct count"

  local has_slash
  has_slash=$(jq -r '.provenItems | has("/delegation-review")' "$TEST_SESSION/.state.json")
  assert_eq "false" "$has_slash" \
    "prove: slash entry not in provenItems"
}

# ============================================================
# Category: Deactivation Gate — Integration
# ============================================================

test_deactivate_passes_with_full_proof() {
  local items='["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS"]'
  create_state_json "$TEST_SESSION" "$items" "test" "~/.claude/skills/test/assets/TEMPLATE_TESTING.md"

  # Create debrief file (required by §CMD_DEBRIEF_BEFORE_CLOSE)
  echo "# Testing Debrief" > "$TEST_SESSION/TESTING.md"

  # Submit proof for all items
  bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' > /dev/null
§CMD_MANAGE_DIRECTIVES: ran: updated
§CMD_PROCESS_DELEGATIONS: skipped: none
EOF

  # Attempt deactivation with description
  local output
  output=$(bash "$SESSION_SH" deactivate "$TEST_SESSION" <<'EOF' 2>&1
Test session completed.
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "0" "$rc" \
    "deactivate: passes with full proof"
  assert_contains "Session deactivated" "$output" \
    "deactivate: success message present"
}

test_deactivate_fails_missing_proof() {
  local items='["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL"]'
  create_state_json "$TEST_SESSION" "$items" "test" "~/.claude/skills/test/assets/TEMPLATE_TESTING.md"

  # Create debrief file
  echo "# Testing Debrief" > "$TEST_SESSION/TESTING.md"

  # Submit proof for only 2 of 3 items
  bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' > /dev/null
§CMD_MANAGE_DIRECTIVES: ran: updated
§CMD_PROCESS_DELEGATIONS: skipped: none
EOF

  # Attempt deactivation
  local output
  output=$(bash "$SESSION_SH" deactivate "$TEST_SESSION" <<'EOF' 2>&1
Test session completed.
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "1" "$rc" \
    "deactivate: fails with missing proof"
  assert_contains "1 debrief pipeline item(s) lack proof" "$output" \
    "deactivate: reports missing count"
  assert_contains "§CMD_DISPATCH_APPROVAL" "$output" \
    "deactivate: lists the missing item"
}

test_deactivate_fails_no_prove_called() {
  local items='["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS"]'
  create_state_json "$TEST_SESSION" "$items" "test" "~/.claude/skills/test/assets/TEMPLATE_TESTING.md"

  # Create debrief file
  echo "# Testing Debrief" > "$TEST_SESSION/TESTING.md"

  # Never call prove — deactivation should fail
  local output
  output=$(bash "$SESSION_SH" deactivate "$TEST_SESSION" <<'EOF' 2>&1
Test session completed.
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "1" "$rc" \
    "deactivate: fails when prove never called"
  assert_contains "2 debrief pipeline item(s) lack proof" "$output" \
    "deactivate: reports all items as missing"
}

# ============================================================
# Category: Regression — Original Bug
# ============================================================

test_regression_slash_skill_silently_dropped() {
  # The original bug: /delegation-review was in provableDebriefItems.
  # session.sh prove silently dropped it, so proof could never be recorded.
  # Deactivation then failed with "1 item lacks proof".
  local items='["/delegation-review", "§CMD_MANAGE_DIRECTIVES"]'
  create_state_json "$TEST_SESSION" "$items" "test" "~/.claude/skills/test/assets/TEMPLATE_TESTING.md"

  # Create debrief file
  echo "# Testing Debrief" > "$TEST_SESSION/TESTING.md"

  # Try to prove BOTH entries (agent submits both)
  bash "$SESSION_SH" prove "$TEST_SESSION" <<'EOF' > /dev/null
/delegation-review: ran: checked all tags
§CMD_MANAGE_DIRECTIVES: ran: updated
EOF

  # Only §CMD entry should be in provenItems
  local has_slash
  has_slash=$(jq -r '.provenItems | has("/delegation-review")' "$TEST_SESSION/.state.json")
  assert_eq "false" "$has_slash" \
    "REGRESSION: /delegation-review silently dropped by prove"

  local has_cmd
  has_cmd=$(jq -r '.provenItems | has("§CMD_MANAGE_DIRECTIVES")' "$TEST_SESSION/.state.json")
  assert_eq "true" "$has_cmd" \
    "REGRESSION: §CMD entry correctly preserved"

  # Deactivation should fail because /delegation-review has no proof
  local output
  output=$(bash "$SESSION_SH" deactivate "$TEST_SESSION" <<'EOF' 2>&1
Test session completed.
EOF
  ) && local rc=0 || local rc=$?

  assert_eq "1" "$rc" \
    "REGRESSION: deactivation fails for /delegation-review"
  assert_contains "/delegation-review" "$output" \
    "REGRESSION: error message names the unprovable item"
}

# ============================================================
# Run All Tests
# ============================================================

echo "=== session.sh prove — Hardening Tests ==="
echo ""

# Happy Path
run_test test_prove_single_valid_entry
run_test test_prove_multiple_valid_entries
run_test test_prove_reports_correct_count

# Regex Boundary
run_test test_prove_rejects_slash_skill_name
run_test test_prove_rejects_lowercase_cmd
run_test test_prove_rejects_numbers_in_cmd
run_test test_prove_accepts_underscores
run_test test_prove_skips_blank_lines

# Error Paths
run_test test_prove_fails_empty_stdin
run_test test_prove_fails_all_invalid_lines
run_test test_prove_fails_no_state_json

# Whitespace Edge Cases
run_test test_prove_colons_in_proof_value
run_test test_prove_mixed_valid_and_invalid

# Deactivation Gate Integration
run_test test_deactivate_passes_with_full_proof
run_test test_deactivate_fails_missing_proof
run_test test_deactivate_fails_no_prove_called

# Regression
run_test test_regression_slash_skill_silently_dropped

exit_with_results
