#!/bin/bash
# test-lib-validate.sh — Tests for validate_* functions in lib.sh
#
# Usage: bash test-lib-validate.sh
#        TEST_FILTER="tag" bash test-lib-validate.sh  # run only tag tests

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"
source "$(dirname "$0")/../lib.sh"

# ============================================================
# validate_tag tests
# ============================================================

test_validate_tag_valid_simple() {
  local result
  result=$(validate_tag "#needs-review")
  assert_eq "needs-review" "$result" "validate_tag: strips # and returns clean tag"
}

test_validate_tag_valid_no_hash() {
  local result
  result=$(validate_tag "needs-review")
  assert_eq "needs-review" "$result" "validate_tag: accepts tag without # prefix"
}

test_validate_tag_valid_single_word() {
  local result
  result=$(validate_tag "#active")
  assert_eq "active" "$result" "validate_tag: single word tag"
}

test_validate_tag_valid_multi_hyphen() {
  local result
  result=$(validate_tag "#needs-some-work")
  assert_eq "needs-some-work" "$result" "validate_tag: multi-hyphen tag"
}

test_validate_tag_valid_with_numbers() {
  local result
  result=$(validate_tag "#p0")
  assert_eq "p0" "$result" "validate_tag: tag with numbers"
}

test_validate_tag_reject_empty() {
  assert_fail "validate_tag: rejects empty string" validate_tag ""
}

test_validate_tag_reject_hash_only() {
  assert_fail "validate_tag: rejects bare #" validate_tag "#"
}

test_validate_tag_reject_uppercase() {
  assert_fail "validate_tag: rejects uppercase" validate_tag "#NEEDS-REVIEW"
}

test_validate_tag_reject_mixed_case() {
  assert_fail "validate_tag: rejects mixed case" validate_tag "#Needs-Review"
}

test_validate_tag_reject_spaces() {
  assert_fail "validate_tag: rejects spaces" validate_tag "#needs review"
}

test_validate_tag_reject_special_chars() {
  assert_fail "validate_tag: rejects special chars" validate_tag '#needs/review'
}

test_validate_tag_reject_sed_injection() {
  assert_fail "validate_tag: rejects sed injection attempt" validate_tag '#needs-review/e'
}

test_validate_tag_reject_starts_with_number() {
  assert_fail "validate_tag: rejects tag starting with number" validate_tag "#0critical"
}

test_validate_tag_reject_starts_with_hyphen() {
  assert_fail "validate_tag: rejects tag starting with hyphen" validate_tag "#-needs-review"
}

# ============================================================
# validate_subcmd tests
# ============================================================

test_validate_subcmd_valid_simple() {
  assert_ok "validate_subcmd: accepts simple subcmd" validate_subcmd "session"
}

test_validate_subcmd_valid_hyphenated() {
  assert_ok "validate_subcmd: accepts hyphenated" validate_subcmd "find-sessions"
}

test_validate_subcmd_valid_with_numbers() {
  assert_ok "validate_subcmd: accepts with numbers" validate_subcmd "session2"
}

test_validate_subcmd_reject_empty() {
  assert_fail "validate_subcmd: rejects empty" validate_subcmd ""
}

test_validate_subcmd_reject_single_char() {
  assert_fail "validate_subcmd: rejects single char" validate_subcmd "a"
}

test_validate_subcmd_reject_slashes() {
  assert_fail "validate_subcmd: rejects slashes" validate_subcmd "../../etc/passwd"
}

test_validate_subcmd_reject_spaces() {
  assert_fail "validate_subcmd: rejects spaces" validate_subcmd "session activate"
}

test_validate_subcmd_reject_uppercase() {
  assert_fail "validate_subcmd: rejects uppercase" validate_subcmd "Session"
}

test_validate_subcmd_reject_semicolons() {
  assert_fail "validate_subcmd: rejects semicolons" validate_subcmd "session;rm"
}

test_validate_subcmd_reject_backticks() {
  assert_fail "validate_subcmd: rejects backticks" validate_subcmd 'session`id`'
}

# ============================================================
# validate_path tests
# ============================================================

test_validate_path_valid_existing_file() {
  local tmp
  tmp=$(mktemp)
  assert_ok "validate_path: accepts existing file" validate_path "$tmp"
  rm -f "$tmp"
}

test_validate_path_valid_existing_dir() {
  local tmp
  tmp=$(mktemp -d)
  assert_ok "validate_path: accepts existing dir" validate_path "$tmp"
  rmdir "$tmp"
}

test_validate_path_reject_empty() {
  assert_fail "validate_path: rejects empty" validate_path ""
}

test_validate_path_reject_traversal() {
  assert_fail "validate_path: rejects .." validate_path "/tmp/../etc/passwd"
}

test_validate_path_reject_traversal_start() {
  assert_fail "validate_path: rejects .. at start" validate_path "../etc/passwd"
}

test_validate_path_reject_traversal_end() {
  assert_fail "validate_path: rejects .. at end" validate_path "/tmp/foo/.."
}

test_validate_path_reject_nonexistent() {
  assert_fail "validate_path: rejects nonexistent" validate_path "/tmp/nonexistent_path_$$_test"
}

test_validate_path_valid_with_spaces() {
  local tmp
  tmp=$(mktemp -d)
  local spaced="$tmp/path with spaces"
  mkdir -p "$spaced"
  assert_ok "validate_path: accepts path with spaces" validate_path "$spaced"
  rm -rf "$tmp"
}

test_validate_path_valid_with_dots_in_name() {
  local tmp
  tmp=$(mktemp -d)
  local dotted="$tmp/.state.json"
  touch "$dotted"
  assert_ok "validate_path: accepts .state.json (single dot)" validate_path "$dotted"
  rm -rf "$tmp"
}

# ============================================================
# validate_phase tests
# ============================================================

test_validate_phase_valid_simple() {
  assert_ok "validate_phase: accepts '3: Execution'" validate_phase "3: Execution"
}

test_validate_phase_valid_subphase() {
  assert_ok "validate_phase: accepts '3.A: Build Loop'" validate_phase "3.A: Build Loop"
}

test_validate_phase_valid_numbered_sub() {
  assert_ok "validate_phase: accepts '4.1: Checklists'" validate_phase "4.1: Checklists"
}

test_validate_phase_reject_empty() {
  assert_fail "validate_phase: rejects empty" validate_phase ""
}

test_validate_phase_reject_forward_slash() {
  assert_fail "validate_phase: rejects /" validate_phase "3: Exec/ution"
}

test_validate_phase_reject_ampersand() {
  assert_fail "validate_phase: rejects &" validate_phase "3: Exec & ution"
}

test_validate_phase_reject_backslash() {
  assert_fail "validate_phase: rejects backslash" validate_phase '3: Exec\ution'
}

test_validate_phase_reject_newline() {
  assert_fail "validate_phase: rejects newline" validate_phase $'3: Exec\nution'
}

# ============================================================
# Run all tests
# ============================================================

run_discovered_tests
