#!/bin/bash
# ============================================================================
# test-session-check-tags.sh — Tests for session.sh check tag scanning
# ============================================================================
# Verifies that session.sh check correctly scans session .md artifacts for
# bare unescaped inline #needs-*/#active-*/#done-* lifecycle tags (the
# INV_ESCAPE_BY_DEFAULT enforcement gate).
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/scripts/session.sh"

# ---- Setup / Teardown ----
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

make_session() {
  local name="$1"
  local dir="$TEST_DIR/sessions/$name"
  mkdir -p "$dir"
  cat > "$dir/.state.json" << 'SJSON'
{"lifecycle":"active","skill":"implement","pid":1234}
SJSON
  echo "$dir"
}

# ---- Tests ----

test_passes_no_bare_tags() {
  local S
  S=$(make_session "clean_session")

  # Tags only on Tags-line and backtick-escaped in body
  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review

## Summary
The `#needs-brainstorm` tag was resolved.
All `#needs-implementation` items done.
MD

  local output exit_code
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1) || true
  exit_code=$?
  # Re-run to capture exit code properly
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "check passes when no bare inline tags"
  else
    fail "check passes when no bare inline tags" "exit 0" "exit $exit_code"
  fi
}

test_fails_bare_needs_tag() {
  local S
  S=$(make_session "bare_needs")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Task Start
Found an issue that #needs-brainstorm before we proceed.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "check fails when bare #needs-* tag found"
  else
    fail "check fails when bare #needs-* tag found" "exit 1" "exit $exit_code"
  fi
}

test_fails_bare_active_tag() {
  local S
  S=$(make_session "bare_active")

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review

## Status
Currently #active-implementation in progress.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "check fails when bare #active-* tag found"
  else
    fail "check fails when bare #active-* tag found" "exit 1" "exit $exit_code"
  fi
}

test_fails_bare_done_tag() {
  local S
  S=$(make_session "bare_done")

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review

## Summary
The previous #done-brainstorm session informed this.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "check fails when bare #done-* tag found"
  else
    fail "check fails when bare #done-* tag found" "exit 1" "exit $exit_code"
  fi
}

test_ignores_tags_line() {
  local S
  S=$(make_session "tags_line")

  # Only tags on the Tags line — should pass
  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review #needs-documentation

## Summary
All work completed.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "check ignores tags on **Tags**: line"
  else
    fail "check ignores tags on **Tags**: line" "exit 0" "exit $exit_code"
  fi
}

test_ignores_backtick_escaped() {
  local S
  S=$(make_session "escaped")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Decision
We resolved the `#needs-brainstorm` tag from the previous session.
The `#needs-implementation` items were all addressed.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "check ignores backtick-escaped tags"
  else
    fail "check ignores backtick-escaped tags" "exit 0" "exit $exit_code"
  fi
}

test_works_with_checklists() {
  local S
  S=$(make_session "with_checklists")

  # Session with discovered checklists AND no bare tags
  jq '.discoveredChecklists = ["/tmp/CHECKLIST.md"]' "$S/.state.json" > "$S/.tmp.json" && mv "$S/.tmp.json" "$S/.state.json"

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review

## Summary
Clean implementation, no inline tags.
MD

  # Provide checklist results on stdin
  local exit_code
  "$SESSION_SH" check "$S" << 'STDIN' > /dev/null 2>&1
## CHECKLIST: /tmp/CHECKLIST.md
- [x] All items verified
STDIN
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "check works with tag scan + checklist validation together"
  else
    fail "check works with tag scan + checklist validation together" "exit 0" "exit $exit_code"
  fi
}

test_both_tag_and_checklist_fail() {
  local S
  S=$(make_session "both_fail")

  # Session with discovered checklists AND bare tags — tag scan should fail first
  jq '.discoveredChecklists = ["/tmp/CHECKLIST.md"]' "$S/.state.json" > "$S/.tmp.json" && mv "$S/.tmp.json" "$S/.state.json"

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review

## Summary
This #needs-brainstorm should block.
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    # Verify it's the TAG scan that failed, not the checklist
    if echo "$output" | grep -q "ESCAPE_BY_DEFAULT"; then
      pass "tag scan fails first when both tags and checklists present"
    else
      fail "tag scan fails first when both tags and checklists present" "tag error" "other error"
    fi
  else
    fail "tag scan fails first when both tags and checklists present" "exit 1" "exit $exit_code"
  fi
}

test_outputs_actionable_info() {
  local S
  S=$(make_session "actionable")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Block
There is a #needs-brainstorm item here on line 4.
MD

  local output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)

  # Check output includes file path
  local has_file has_line has_tag
  has_file=0; has_line=0; has_tag=0

  echo "$output" | grep -q "IMPLEMENTATION_LOG.md" && has_file=1
  echo "$output" | grep -q ":4:" && has_line=1
  echo "$output" | grep -q "#needs-brainstorm" && has_tag=1

  if [ "$has_file" -eq 1 ] && [ "$has_line" -eq 1 ] && [ "$has_tag" -eq 1 ]; then
    pass "check outputs file, line number, and tag name"
  else
    fail "check outputs file, line number, and tag name" "file+line+tag" "file=$has_file line=$has_line tag=$has_tag"
  fi
}

test_tagCheckPassed_skips_scan() {
  local S
  S=$(make_session "skip_scan")

  # Set tagCheckPassed=true — scan should be skipped even with bare tags
  jq '.tagCheckPassed = true' "$S/.state.json" > "$S/.tmp.json" && mv "$S/.tmp.json" "$S/.state.json"

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Task
Still has bare #needs-brainstorm tag but was already addressed.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "check skips tag scan when tagCheckPassed=true"
  else
    fail "check skips tag scan when tagCheckPassed=true" "exit 0" "exit $exit_code"
  fi
}

test_multiple_tags_same_file() {
  local S
  S=$(make_session "multi_tags")

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation
**Tags**: #needs-review

## Findings
This #needs-brainstorm and also #needs-implementation are both open.
Another line with #active-research in progress.
MD

  local output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  local exit_code=$?

  # Should fail and report all three tags
  local count
  count=$(echo "$output" | grep -c '#needs-\|#active-\|#done-' 2>/dev/null || echo 0)

  if [ "$exit_code" -eq 1 ] && [ "$count" -ge 3 ]; then
    pass "check reports multiple bare tags in same file"
  else
    fail "check reports multiple bare tags in same file" "exit 1 + 3+ tags" "exit=$exit_code count=$count"
  fi
}

test_empty_session_passes() {
  local S
  S=$(make_session "empty_session")

  # No .md files at all
  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "check passes on empty session (no .md files)"
  else
    fail "check passes on empty session (no .md files)" "exit 0" "exit $exit_code"
  fi
}

# ---- Hardening Tests (HC-01 through HC-08) ----

test_hc01_bare_tag_in_plan_step() {
  local S
  S=$(make_session "hc01_plan_step")

  cat > "$S/IMPLEMENTATION_PLAN.md" << 'MD'
# Implementation Plan

## Steps
*   [ ] **Step 1**: Setup the environment
*   [ ] **Step 2**: Build the core module
*   [ ] **Step 3**: Fix #needs-implementation items from previous session
*   [ ] **Step 4**: Run tests
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "#needs-implementation"; then
    pass "HC-01: detects bare tag in plan step description"
  else
    fail "HC-01: detects bare tag in plan step description" "exit 1 + tag found" "exit=$exit_code"
  fi
}

test_hc02_bare_tag_in_heading() {
  local S
  S=$(make_session "hc02_heading")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Task Start
Started work on the widget.

### Block — Widget API #needs-brainstorm
The API design needs discussion before we can proceed.
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "#needs-brainstorm"; then
    pass "HC-02: detects bare tag in markdown heading"
  else
    fail "HC-02: detects bare tag in markdown heading" "exit 1 + tag found" "exit=$exit_code"
  fi
}

test_hc03_bare_tag_in_debrief_narrative() {
  local S
  S=$(make_session "hc03_narrative")

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation Debriefing
**Tags**: #needs-review

## 2. The Story
The previous #needs-brainstorm session informed this work. We built on the design
decisions made during the brainstorm and translated them into code.
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "#needs-brainstorm"; then
    pass "HC-03: detects bare tag in debrief narrative text"
  else
    fail "HC-03: detects bare tag in debrief narrative text" "exit 1 + tag found" "exit=$exit_code"
  fi
}

test_hc04_multiple_lifecycle_families_same_line() {
  local S
  S=$(make_session "hc04_multi_family")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Tag Management
Swapped #needs-review to #done-review on 42 files.
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  # Should detect BOTH tags
  local count
  count=$(echo "$output" | grep -c '#needs-review\|#done-review' 2>/dev/null || echo 0)

  if [ "$exit_code" -eq 1 ] && [ "$count" -ge 2 ]; then
    pass "HC-04: detects multiple different lifecycle families on same line"
  else
    fail "HC-04: detects multiple different lifecycle families on same line" "exit 1 + 2 tags" "exit=$exit_code count=$count"
  fi
}

test_hc05_tag_at_start_of_line() {
  local S
  S=$(make_session "hc05_line_start")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Notes
#needs-implementation — the auth module needs work
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "#needs-implementation"; then
    pass "HC-05: detects tag at start of line"
  else
    fail "HC-05: detects tag at start of line" "exit 1 + tag found" "exit=$exit_code"
  fi
}

test_hc06_tag_at_end_of_line() {
  local S
  S=$(make_session "hc06_line_end")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Notes
The auth module still needs work #needs-implementation
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "#needs-implementation"; then
    pass "HC-06: detects tag at end of line"
  else
    fail "HC-06: detects tag at end of line" "exit 1 + tag found" "exit=$exit_code"
  fi
}

test_hc07_tags_line_extra_whitespace() {
  local S
  S=$(make_session "hc07_whitespace")

  cat > "$S/IMPLEMENTATION.md" << 'MD'
# Implementation Debriefing
**Tags**:   #needs-review  #needs-documentation

## Summary
Clean implementation.
MD

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "HC-07: Tags-line with extra whitespace passes"
  else
    fail "HC-07: Tags-line with extra whitespace passes" "exit 0" "exit $exit_code"
  fi
}

test_hc08_mixed_escaped_and_bare_same_line() {
  local S
  S=$(make_session "hc08_mixed")

  cat > "$S/IMPLEMENTATION_LOG.md" << 'MD'
# Implementation Log

## Status
Resolved `#needs-brainstorm` but found #needs-implementation here.
MD

  local exit_code output
  output=$("$SESSION_SH" check "$S" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "#needs-implementation"; then
    pass "HC-08: detects bare tag when mixed with backtick-escaped on same line"
  else
    fail "HC-08: detects bare tag when mixed with backtick-escaped on same line" "exit 1 + bare tag found" "exit=$exit_code output=$(echo "$output" | head -5)"
  fi
}

# ---- Run ----
setup

echo "=== session.sh check tag scanning tests ==="
echo ""

test_passes_no_bare_tags
test_fails_bare_needs_tag
test_fails_bare_active_tag
test_fails_bare_done_tag
test_ignores_tags_line
test_ignores_backtick_escaped
test_works_with_checklists
test_both_tag_and_checklist_fail
test_outputs_actionable_info
test_tagCheckPassed_skips_scan
test_multiple_tags_same_file
test_empty_session_passes

echo ""
echo "=== Hardening tests ==="
echo ""

test_hc01_bare_tag_in_plan_step
test_hc02_bare_tag_in_heading
test_hc03_bare_tag_in_debrief_narrative
test_hc04_multiple_lifecycle_families_same_line
test_hc05_tag_at_start_of_line
test_hc06_tag_at_end_of_line
test_hc07_tags_line_extra_whitespace
test_hc08_mixed_escaped_and_bare_same_line

teardown

exit_with_results
