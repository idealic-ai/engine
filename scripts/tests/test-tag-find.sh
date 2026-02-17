#!/bin/bash
# ============================================================================
# test-tag-find.sh — Tests for tag.sh find discovery rules
# ============================================================================
# Verifies that tag.sh find correctly discovers inline tags across all .md
# file types (escape-by-default — ¶INV_ESCAPE_BY_DEFAULT ensures bare tags
# are intentional). Only binary DBs (*.db) are excluded from Pass 2.
# Tags-line Pass 1 is always unfiltered.
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TAG_SH="$HOME/.claude/scripts/tag.sh"

assert_found() {
  local desc="$1" file="$2" results="$3"
  if echo "$results" | grep -q "$file"; then
    pass "$desc"
  else
    fail "$desc" "found $file" "not found"
  fi
}

assert_not_found() {
  local desc="$1" file="$2" results="$3"
  if echo "$results" | grep -q "$file"; then
    fail "$desc" "not found $file" "found"
  else
    pass "$desc"
  fi
}

# ---- Setup / Teardown ----
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/sessions/2026_TEST_SESSION"
  local S="$TEST_DIR/sessions/2026_TEST_SESSION"

  # File with Tags-line tag (Pass 1 — should ALWAYS be found)
  cat > "$S/IMPLEMENTATION.md" << 'EOF'
# Implementation Debriefing
**Tags**: #needs-implementation
## 1. Executive Summary
Some content here.
EOF

  # File with inline tag in debrief (Pass 2 — should be found, debriefs not excluded)
  cat > "$S/ANALYSIS.md" << 'EOF'
# Analysis Report
**Tags**: #needs-review
## Side Discoveries
This needs work: #needs-implementation
EOF

  # DEHYDRATED_CONTEXT.md with inline tag (now FOUND — no blacklist, escape-by-default)
  cat > "$S/DEHYDRATED_CONTEXT.md" << 'EOF'
# Dehydrated Context
## Required Files
The previous session had #needs-implementation items pending.
EOF

  # _LOG.md with inline tag (now FOUND — no blacklist, escape-by-default)
  cat > "$S/IMPLEMENTATION_LOG.md" << 'EOF'
# Implementation Log
## Task Start
Working on #needs-implementation item from plan.
EOF

  # DIALOGUE.md with inline tag (now FOUND — no blacklist, escape-by-default)
  cat > "$S/DIALOGUE.md" << 'EOF'
# Q&A Record
## Round 1
User mentioned #needs-implementation for the auth module.
EOF

  # .state.json with tag string (should be EXCLUDED — not .md, grep skips non-text)
  cat > "$S/.state.json" << 'EOF'
{"skill":"implement","extraInfo":"has #needs-implementation tag"}
EOF

  # _PLAN.md with inline tag (now FOUND — no blacklist, escape-by-default)
  cat > "$S/IMPLEMENTATION_PLAN.md" << 'EOF'
# Implementation Plan
## Steps
* [ ] Step 1: Fix #needs-implementation items
EOF

  # BRAINSTORM.md with inline tag (should be found — brainstorms not excluded)
  cat > "$S/BRAINSTORM.md" << 'EOF'
# Brainstorm
**Tags**: #needs-review
## Ideas
This is a real work item: #needs-implementation
EOF

  # File with backtick-escaped tag (should be EXCLUDED — existing behavior)
  cat > "$S/DOCS.md" << 'EOF'
# Documentation
Reference to `#needs-implementation` should not match.
EOF

  # File with Tags-line on DIALOGUE.md (Tags-line should be found via Pass 1)
  cat > "$TEST_DIR/sessions/2026_TEST_SESSION_2/placeholder" << 'EOF'
placeholder
EOF
  mkdir -p "$TEST_DIR/sessions/2026_TEST_TAGS_LINE_DETAILS"
  cat > "$TEST_DIR/sessions/2026_TEST_TAGS_LINE_DETAILS/DIALOGUE.md" << 'EOF'
# Q&A Record
**Tags**: #needs-implementation
## Round 1
Some Q&A content.
EOF
}

teardown() {
  [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# ---- Tests ----

test_excludes_binary_db() {
  local S="$TEST_DIR/sessions/2026_TEST_SESSION"
  # Create a fake .db file with the tag string
  echo "#needs-implementation" > "$TEST_DIR/sessions/.session-search.db"
  echo "#needs-implementation" > "$TEST_DIR/sessions/.session-search.db.bak"

  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_not_found "find excludes .session-search.db" ".session-search.db" "$results"
  assert_not_found "find excludes .session-search.db.bak" ".session-search.db.bak" "$results"
}

test_finds_dehydrated_context() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "find discovers DEHYDRATED_CONTEXT.md inline tags" "DEHYDRATED_CONTEXT.md" "$results"
}

test_finds_log_files() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "find discovers IMPLEMENTATION_LOG.md inline tags" "IMPLEMENTATION_LOG.md" "$results"
}

test_finds_details_inline() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "find discovers DIALOGUE.md inline tags" "2026_TEST_SESSION/DIALOGUE.md" "$results"
}

test_excludes_state_json() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_not_found "find excludes .state.json" ".state.json" "$results"
}

test_finds_plan_files() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "find discovers IMPLEMENTATION_PLAN.md inline tags" "IMPLEMENTATION_PLAN.md" "$results"
}

test_keeps_debrief_files() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "find keeps IMPLEMENTATION.md (Tags line)" "IMPLEMENTATION.md" "$results"
  assert_found "find keeps ANALYSIS.md (inline in debrief)" "ANALYSIS.md" "$results"
  assert_found "find keeps BRAINSTORM.md (inline in brainstorm)" "BRAINSTORM.md" "$results"
}

test_tags_line_never_filtered() {
  # DIALOGUE.md is excluded from inline Pass 2, but if it has a Tags-line with the tag,
  # it should still be found via Pass 1
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "find keeps DIALOGUE.md when tag is on Tags line" "2026_TEST_TAGS_LINE_DETAILS/DIALOGUE.md" "$results"
}

test_backtick_escaped_excluded() {
  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_not_found "find excludes backtick-escaped references" "DOCS.md" "$results"
}

# ---- Hardening Tests (HF-01 through HF-05) ----

test_hf01_finds_tag_in_plan_step() {
  local S="$TEST_DIR/sessions/2026_HF_SESSION"
  mkdir -p "$S"

  cat > "$S/TESTING_PLAN.md" << 'EOF'
# Testing Plan

## Steps
*   [ ] **Step 1**: Setup environment
*   [ ] **Step 2**: Fix #needs-implementation items from review
*   [ ] **Step 3**: Run tests
EOF

  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "HF-01: finds tag in plan step with mixed content" "TESTING_PLAN.md" "$results"
}

test_hf02_finds_tag_in_log_heading() {
  local S="$TEST_DIR/sessions/2026_HF_SESSION"
  # Session already exists from HF-01

  cat > "$S/IMPLEMENTATION_LOG_HF.md" << 'EOF'
# Implementation Log

## Task Start
Working on the feature.

### Block — Auth Flow #needs-brainstorm
The auth design needs discussion.
EOF

  local results
  results=$("$TAG_SH" find '#needs-brainstorm' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "HF-02: finds tag in log heading (inline tag placement)" "IMPLEMENTATION_LOG_HF.md" "$results"
}

test_hf03_excludes_only_backtick_escaped() {
  local S="$TEST_DIR/sessions/2026_HF_ESCAPED_ONLY"
  mkdir -p "$S"

  cat > "$S/NOTES.md" << 'EOF'
# Session Notes

## Summary
The `#needs-brainstorm` tag was resolved in the previous session.
We also handled `#needs-implementation` items from the plan.
No bare tags here — everything is properly escaped.
EOF

  local results
  results=$("$TAG_SH" find '#needs-brainstorm' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_not_found "HF-03: excludes file with ONLY backtick-escaped occurrences" "NOTES.md" "$results"
}

test_hf04_finds_tag_in_testing_debrief() {
  local S="$TEST_DIR/sessions/2026_HF_TESTING"
  mkdir -p "$S"

  cat > "$S/TESTING.md" << 'EOF'
# Testing Debriefing
**Tags**: #needs-review

## Findings
During testing we discovered a #needs-implementation gap in the auth module.
EOF

  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "HF-04: finds tag in TESTING.md debrief inline body" "2026_HF_TESTING/TESTING.md" "$results"
}

test_hf05_context_flag_output() {
  local S="$TEST_DIR/sessions/2026_HF_CONTEXT"
  mkdir -p "$S"

  cat > "$S/ANALYSIS.md" << 'EOF'
# Analysis Report
**Tags**: #needs-review

## Findings
The widget module has #needs-implementation work pending.
EOF

  local results
  results=$("$TAG_SH" find '#needs-implementation' "$TEST_DIR/sessions/" --context 2>/dev/null)

  # Context mode should include line numbers and surrounding text
  local has_line_num has_context
  has_line_num=0; has_context=0

  echo "$results" | grep -q ":[0-9]" && has_line_num=1
  echo "$results" | grep -q "widget" && has_context=1

  if [ "$has_line_num" -eq 1 ] && [ "$has_context" -eq 1 ]; then
    pass "HF-05: --context flag returns line numbers and surrounding text"
  else
    fail "HF-05: --context flag returns line numbers and surrounding text" "line_num+context" "line_num=$has_line_num context=$has_context"
  fi
}

# ---- Code Span Filtering Tests (CS-01 through CS-04) ----

test_cs01_excludes_tag_in_code_span() {
  local S="$TEST_DIR/sessions/2026_CS_CODE_SPAN"
  mkdir -p "$S"

  cat > "$S/COMMANDS_REF.md" << 'EOF'
# Command Reference

## Tag Operations
Use `engine tag swap "$FILE" '#needs-review' '#done-review'` to resolve tags.
Use `engine tag find '#needs-implementation' sessions/` to discover work items.
EOF

  local results
  results=$("$TAG_SH" find '#needs-review' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_not_found "CS-01: excludes tag inside larger backtick code span" "COMMANDS_REF.md" "$results"
}

test_cs02_excludes_tag_in_code_span_with_quotes() {
  local S="$TEST_DIR/sessions/2026_CS_QUOTES"
  mkdir -p "$S"

  cat > "$S/ANALYSIS.md" << 'EOF'
# Analysis
**Tags**: #needs-review

## Findings
The scanner filters `grep -v "\`${ESCAPED_TAG}\`"` which misses '#needs-review' inside spans.
EOF

  local results
  results=$("$TAG_SH" find '#needs-review' "$TEST_DIR/sessions/" 2>/dev/null)
  # Should be found via Tags-line (Pass 1), but NOT via inline (the body reference is in a code span)
  assert_found "CS-02: still found via Tags line even when body has code-span reference" "ANALYSIS.md" "$results"
}

test_cs03_bare_tag_still_found_alongside_code_span() {
  local S="$TEST_DIR/sessions/2026_CS_MIXED"
  mkdir -p "$S"

  cat > "$S/LOG.md" << 'EOF'
# Log

## Notes
Use `engine tag find '#needs-brainstorm'` to search. Also #needs-brainstorm here bare.
EOF

  local results
  results=$("$TAG_SH" find '#needs-brainstorm' "$TEST_DIR/sessions/" 2>/dev/null)
  assert_found "CS-03: bare tag still found when also present in code span on same line" "LOG.md" "$results"
}

test_cs04_context_mode_excludes_code_span() {
  local S="$TEST_DIR/sessions/2026_CS_CONTEXT"
  mkdir -p "$S"

  cat > "$S/DOCS.md" << 'EOF'
# Documentation

## Commands
Run `engine tag swap "$FILE" '#needs-review' '#done-review'` to resolve.
EOF

  local results
  results=$("$TAG_SH" find '#needs-review' "$TEST_DIR/sessions/" --context 2>/dev/null)
  assert_not_found "CS-04: context mode excludes tag inside code span" "DOCS.md" "$results"
}

# ---- Run ----
setup

echo "=== tag.sh find exclusion tests ==="
echo ""

test_excludes_binary_db
test_finds_dehydrated_context
test_finds_log_files
test_finds_details_inline
test_excludes_state_json
test_finds_plan_files
test_keeps_debrief_files
test_tags_line_never_filtered
test_backtick_escaped_excluded

echo ""
echo "=== Hardening tests ==="
echo ""

test_hf01_finds_tag_in_plan_step
test_hf02_finds_tag_in_log_heading
test_hf03_excludes_only_backtick_escaped
test_hf04_finds_tag_in_testing_debrief
test_hf05_context_flag_output

echo ""
echo "=== Code span filtering tests ==="
echo ""

test_cs01_excludes_tag_in_code_span
test_cs02_excludes_tag_in_code_span_with_quotes
test_cs03_bare_tag_still_found_alongside_code_span
test_cs04_context_mode_excludes_code_span

teardown

exit_with_results
