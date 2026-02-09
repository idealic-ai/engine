#!/bin/bash
# ~/.claude/engine/scripts/tests/test-tag-sh.sh — Deep coverage tests for tag.sh
#
# Tests all 4 subcommands: add, remove, swap, find
# Covers: Tags-line operations, inline operations, backtick filtering,
#         idempotency, multi-swap, context mode, edge cases
#
# Run: bash ~/.claude/engine/scripts/tests/test-tag-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TAG_SH="$HOME/.claude/engine/scripts/tag.sh"

# Temp directory for test fixtures
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/sessions"
}

teardown() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: create a markdown file with H1 heading
create_md() {
  local file="$1"
  local content="${2:-# Test Document}"
  echo "$content" > "$file"
}

# Helper: create a markdown file with H1 + existing Tags line
create_md_with_tags() {
  local file="$1"
  local tags="${2:-}"
  printf '# Test Document\n**Tags**: %s\n\nSome body content.\n' "$tags" > "$file"
}

# Helper: create a markdown file with inline tags in body
create_md_with_inline() {
  local file="$1"
  local tag="$2"
  printf '# Test Document\n**Tags**: #other-tag\n\nSome body content.\n### Block — Widget API %s\nMore text here.\n' "$tag" > "$file"
}

echo "=== tag.sh Deep Coverage Tests ==="
echo ""

# ============================================================
# ADD TESTS
# ============================================================
echo "--- Add: Basic Operations ---"

test_add_creates_tags_line() {
  local f="$TEST_DIR/test.md"
  create_md "$f" "# My Document"

  bash "$TAG_SH" add "$f" '#needs-review'

  # Should have **Tags**: line with the tag
  if grep -q '^\*\*Tags\*\*:.*#needs-review' "$f"; then
    pass "ADD-01: Creates **Tags** line and adds tag"
  else
    fail "ADD-01: Creates **Tags** line and adds tag" \
      "**Tags**: #needs-review" "$(cat "$f")"
  fi
}
run_test test_add_creates_tags_line

test_add_tags_line_after_h1() {
  local f="$TEST_DIR/test.md"
  create_md "$f" "# My Document"

  bash "$TAG_SH" add "$f" '#needs-review'

  # Tags line should be line 2 (after H1)
  local line2
  line2=$(sed -n '2p' "$f")
  if [[ "$line2" == *"**Tags**:"*"#needs-review"* ]]; then
    pass "ADD-02: Tags line inserted after H1 (line 2)"
  else
    fail "ADD-02: Tags line inserted after H1 (line 2)" \
      "**Tags**: #needs-review on line 2" "$line2"
  fi
}
run_test test_add_tags_line_after_h1

test_add_to_existing_tags_line() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#existing-tag"

  bash "$TAG_SH" add "$f" '#needs-review'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" == *"#existing-tag"* ]] && [[ "$tags_line" == *"#needs-review"* ]]; then
    pass "ADD-03: Appends to existing Tags line"
  else
    fail "ADD-03: Appends to existing Tags line" \
      "Both #existing-tag and #needs-review" "$tags_line"
  fi
}
run_test test_add_to_existing_tags_line

test_add_idempotent() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-review"

  bash "$TAG_SH" add "$f" '#needs-review'

  # Count occurrences of the tag on the Tags line
  local count
  count=$(grep '^\*\*Tags\*\*:' "$f" | grep -o '#needs-review' | wc -l | tr -d ' ')
  if [[ "$count" == "1" ]]; then
    pass "ADD-04: Idempotent — no duplicate when tag already present"
  else
    fail "ADD-04: Idempotent — no duplicate when tag already present" \
      "1 occurrence" "$count occurrences"
  fi
}
run_test test_add_idempotent

test_add_multiple_tags() {
  local f="$TEST_DIR/test.md"
  create_md "$f" "# My Document"

  bash "$TAG_SH" add "$f" '#needs-review'
  bash "$TAG_SH" add "$f" '#needs-documentation'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" == *"#needs-review"* ]] && [[ "$tags_line" == *"#needs-documentation"* ]]; then
    pass "ADD-05: Multiple sequential adds work"
  else
    fail "ADD-05: Multiple sequential adds work" \
      "Both tags on Tags line" "$tags_line"
  fi
}
run_test test_add_multiple_tags

# ============================================================
# REMOVE TESTS
# ============================================================
echo ""
echo "--- Remove: Tags-line Operations ---"

test_remove_from_tags_line() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-review #needs-documentation"

  bash "$TAG_SH" remove "$f" '#needs-review'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" != *"#needs-review"* ]] && [[ "$tags_line" == *"#needs-documentation"* ]]; then
    pass "REM-01: Removes tag from Tags line, preserves others"
  else
    fail "REM-01: Removes tag from Tags line, preserves others" \
      "Only #needs-documentation remains" "$tags_line"
  fi
}
run_test test_remove_from_tags_line

test_remove_last_tag() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-review"

  bash "$TAG_SH" remove "$f" '#needs-review'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" == "**Tags**:" ]] || [[ "$tags_line" == "**Tags**: " ]]; then
    pass "REM-02: Removes last tag, Tags line remains (empty)"
  else
    fail "REM-02: Removes last tag, Tags line remains (empty)" \
      "**Tags**: (empty)" "$tags_line"
  fi
}
run_test test_remove_last_tag

test_remove_nonexistent_tag() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-review"
  local before
  before=$(cat "$f")

  bash "$TAG_SH" remove "$f" '#nonexistent-tag'
  local rc=$?

  local after
  after=$(cat "$f")
  # Should not error, file should be unchanged (except possibly whitespace)
  if [[ $rc -eq 0 ]] && grep -q '#needs-review' "$f"; then
    pass "REM-03: Removing nonexistent tag is no-op (no error)"
  else
    fail "REM-03: Removing nonexistent tag is no-op (no error)" \
      "exit 0, file unchanged" "rc=$rc"
  fi
}
run_test test_remove_nonexistent_tag

echo ""
echo "--- Remove: Inline Operations ---"

test_remove_inline_at_line() {
  local f="$TEST_DIR/test.md"
  create_md_with_inline "$f" '#needs-decision'

  # Find the line number with the inline tag
  local line_num
  line_num=$(grep -n '#needs-decision' "$f" | grep -v '^\*\*Tags\*\*:' | head -1 | cut -d: -f1)

  bash "$TAG_SH" remove "$f" '#needs-decision' --inline "$line_num"

  # Tag should be gone from that line
  local line_content
  line_content=$(sed -n "${line_num}p" "$f")
  if [[ "$line_content" != *"#needs-decision"* ]]; then
    pass "REM-04: Removes inline tag at specific line"
  else
    fail "REM-04: Removes inline tag at specific line" \
      "Tag removed from line $line_num" "$line_content"
  fi
}
run_test test_remove_inline_at_line

test_remove_inline_wrong_line_errors() {
  local f="$TEST_DIR/test.md"
  create_md_with_inline "$f" '#needs-decision'

  # Try to remove from line 1 (H1 heading, no tag there)
  local output
  output=$(bash "$TAG_SH" remove "$f" '#needs-decision' --inline 1 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"ERROR"* ]]; then
    pass "REM-05: Errors when tag not found at specified inline line"
  else
    fail "REM-05: Errors when tag not found at specified inline line" \
      "exit 1 + ERROR message" "rc=$rc, output=$output"
  fi
}
run_test test_remove_inline_wrong_line_errors

# ============================================================
# SWAP TESTS
# ============================================================
echo ""
echo "--- Swap: Tags-line Operations ---"

test_swap_on_tags_line() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-review"

  bash "$TAG_SH" swap "$f" '#needs-review' '#done-review'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" == *"#done-review"* ]] && [[ "$tags_line" != *"#needs-review"* ]]; then
    pass "SWAP-01: Swaps tag on Tags line"
  else
    fail "SWAP-01: Swaps tag on Tags line" \
      "#done-review (not #needs-review)" "$tags_line"
  fi
}
run_test test_swap_on_tags_line

test_swap_comma_separated() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-rework"

  # Swap either #needs-review or #needs-rework with #done-review
  bash "$TAG_SH" swap "$f" '#needs-review,#needs-rework' '#done-review'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" == *"#done-review"* ]] && [[ "$tags_line" != *"#needs-rework"* ]]; then
    pass "SWAP-02: Comma-separated multi-swap finds matching tag"
  else
    fail "SWAP-02: Comma-separated multi-swap finds matching tag" \
      "#done-review (not #needs-rework)" "$tags_line"
  fi
}
run_test test_swap_comma_separated

test_swap_preserves_other_tags() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#needs-review #needs-documentation"

  bash "$TAG_SH" swap "$f" '#needs-review' '#done-review'

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ "$tags_line" == *"#done-review"* ]] && [[ "$tags_line" == *"#needs-documentation"* ]]; then
    pass "SWAP-03: Swap preserves other tags"
  else
    fail "SWAP-03: Swap preserves other tags" \
      "#done-review AND #needs-documentation" "$tags_line"
  fi
}
run_test test_swap_preserves_other_tags

echo ""
echo "--- Swap: Inline Operations ---"

test_swap_inline_at_line() {
  local f="$TEST_DIR/test.md"
  create_md_with_inline "$f" '#needs-decision'

  local line_num
  line_num=$(grep -n '#needs-decision' "$f" | grep -v '^\*\*Tags\*\*:' | head -1 | cut -d: -f1)

  bash "$TAG_SH" swap "$f" '#needs-decision' '#done-decision' --inline "$line_num"

  local line_content
  line_content=$(sed -n "${line_num}p" "$f")
  if [[ "$line_content" == *"#done-decision"* ]] && [[ "$line_content" != *"#needs-decision"* ]]; then
    pass "SWAP-04: Swaps inline tag at specific line"
  else
    fail "SWAP-04: Swaps inline tag at specific line" \
      "#done-decision on line $line_num" "$line_content"
  fi
}
run_test test_swap_inline_at_line

test_swap_inline_comma_separated() {
  local f="$TEST_DIR/test.md"
  create_md_with_inline "$f" '#needs-rework'

  local line_num
  line_num=$(grep -n '#needs-rework' "$f" | grep -v '^\*\*Tags\*\*:' | head -1 | cut -d: -f1)

  bash "$TAG_SH" swap "$f" '#needs-review,#needs-rework' '#done-review' --inline "$line_num"

  local line_content
  line_content=$(sed -n "${line_num}p" "$f")
  if [[ "$line_content" == *"#done-review"* ]] && [[ "$line_content" != *"#needs-rework"* ]]; then
    pass "SWAP-05: Inline comma-separated multi-swap"
  else
    fail "SWAP-05: Inline comma-separated multi-swap" \
      "#done-review on line $line_num" "$line_content"
  fi
}
run_test test_swap_inline_comma_separated

test_swap_inline_no_match_errors() {
  local f="$TEST_DIR/test.md"
  create_md_with_inline "$f" '#needs-decision'

  # Try to swap a tag that doesn't exist at the specified line
  local output
  output=$(bash "$TAG_SH" swap "$f" '#nonexistent' '#done-something' --inline 1 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"ERROR"* ]]; then
    pass "SWAP-06: Errors when no matching tag at inline line"
  else
    fail "SWAP-06: Errors when no matching tag at inline line" \
      "exit 1 + ERROR message" "rc=$rc, output=$output"
  fi
}
run_test test_swap_inline_no_match_errors

# ============================================================
# FIND TESTS
# ============================================================
echo ""
echo "--- Find: Tags-line Discovery ---"

test_find_tags_line_match() {
  local dir="$TEST_DIR/sessions"
  create_md_with_tags "$dir/DOC_A.md" "#needs-review"
  create_md_with_tags "$dir/DOC_B.md" "#other-tag"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir")

  if [[ "$output" == *"DOC_A.md"* ]] && [[ "$output" != *"DOC_B.md"* ]]; then
    pass "FIND-01: Finds file by Tags-line match"
  else
    fail "FIND-01: Finds file by Tags-line match" \
      "Only DOC_A.md" "$output"
  fi
}
run_test test_find_tags_line_match

test_find_multiple_matches() {
  local dir="$TEST_DIR/sessions"
  create_md_with_tags "$dir/DOC_A.md" "#needs-review"
  create_md_with_tags "$dir/DOC_B.md" "#needs-review #other"
  create_md_with_tags "$dir/DOC_C.md" "#other-tag"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir")

  local count
  count=$(echo "$output" | grep -c 'DOC_' || true)
  if [[ $count -eq 2 ]] && [[ "$output" != *"DOC_C.md"* ]]; then
    pass "FIND-02: Finds multiple Tags-line matches"
  else
    fail "FIND-02: Finds multiple Tags-line matches" \
      "2 matches (A and B)" "$output"
  fi
}
run_test test_find_multiple_matches

test_find_no_match_exits_zero() {
  local dir="$TEST_DIR/sessions"
  create_md_with_tags "$dir/DOC_A.md" "#other-tag"

  local output
  output=$(bash "$TAG_SH" find '#nonexistent' "$dir" 2>&1)
  local rc=$?

  if [[ $rc -eq 0 ]] && [[ -z "$output" ]]; then
    pass "FIND-03: No matches returns exit 0 with empty output"
  else
    fail "FIND-03: No matches returns exit 0 with empty output" \
      "exit 0, empty output" "rc=$rc, output=$output"
  fi
}
run_test test_find_no_match_exits_zero

echo ""
echo "--- Find: Inline Discovery ---"

test_find_inline_tag() {
  local dir="$TEST_DIR/sessions"
  create_md_with_inline "$dir/DOC_A.md" '#needs-decision'

  local output
  output=$(bash "$TAG_SH" find '#needs-decision' "$dir")

  if [[ "$output" == *"DOC_A.md"* ]]; then
    pass "FIND-04: Finds inline (non-Tags-line) tag"
  else
    fail "FIND-04: Finds inline (non-Tags-line) tag" \
      "DOC_A.md in output" "$output"
  fi
}
run_test test_find_inline_tag

test_find_excludes_backtick_escaped() {
  local dir="$TEST_DIR/sessions"
  local f="$dir/DOC_A.md"
  # File with only backtick-escaped reference — should NOT be found
  printf '# Test Document\n**Tags**:\n\nThe `#needs-review` tag is auto-applied.\n' > "$f"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir" 2>&1)

  if [[ -z "$output" ]]; then
    pass "FIND-05: Backtick-escaped reference is filtered out"
  else
    fail "FIND-05: Backtick-escaped reference is filtered out" \
      "empty output (no match)" "$output"
  fi
}
run_test test_find_excludes_backtick_escaped

test_find_union_dedup() {
  local dir="$TEST_DIR/sessions"
  # File has tag on BOTH Tags line AND inline — should appear only once
  local f="$dir/DOC_A.md"
  printf '# Test Document\n**Tags**: #needs-review\n\nSome text with #needs-review inline.\n' > "$f"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir")

  local count
  count=$(echo "$output" | grep -c 'DOC_A.md' || true)
  if [[ $count -eq 1 ]]; then
    pass "FIND-06: Union deduplicates files found in both passes"
  else
    fail "FIND-06: Union deduplicates files found in both passes" \
      "1 occurrence of DOC_A.md" "$count occurrences"
  fi
}
run_test test_find_union_dedup

test_find_custom_path() {
  local dir="$TEST_DIR/custom-dir"
  mkdir -p "$dir"
  create_md_with_tags "$dir/DOC_A.md" "#needs-review"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir")

  if [[ "$output" == *"DOC_A.md"* ]]; then
    pass "FIND-07: Custom search path works"
  else
    fail "FIND-07: Custom search path works" \
      "DOC_A.md in output" "$output"
  fi
}
run_test test_find_custom_path

echo ""
echo "--- Find: Context Mode ---"

test_find_context_mode() {
  local dir="$TEST_DIR/sessions"
  create_md_with_tags "$dir/DOC_A.md" "#needs-review"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir" --context)

  # Context mode should include file:line format and surrounding text
  if [[ "$output" == *"DOC_A.md:"* ]] && [[ "$output" == *"Tags"* ]]; then
    pass "FIND-08: Context mode shows file:line and surrounding text"
  else
    fail "FIND-08: Context mode shows file:line and surrounding text" \
      "file:line + context" "$output"
  fi
}
run_test test_find_context_mode

test_find_context_inline() {
  local dir="$TEST_DIR/sessions"
  create_md_with_inline "$dir/DOC_A.md" '#needs-decision'

  local output
  output=$(bash "$TAG_SH" find '#needs-decision' "$dir" --context)

  # Should show the inline location with context
  if [[ "$output" == *"DOC_A.md:"* ]] && [[ "$output" == *"Widget API"* ]]; then
    pass "FIND-09: Context mode shows inline tag with lookaround"
  else
    fail "FIND-09: Context mode shows inline tag with lookaround" \
      "file:line + Widget API context" "$output"
  fi
}
run_test test_find_context_inline

# ============================================================
# EDGE CASES
# ============================================================
echo ""
echo "--- Edge Cases ---"

test_unknown_action_errors() {
  local output
  output=$(bash "$TAG_SH" badcommand 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Unknown action"* ]]; then
    pass "EDGE-01: Unknown action returns error"
  else
    fail "EDGE-01: Unknown action returns error" \
      "exit 1 + Unknown action" "rc=$rc, output=$output"
  fi
}
run_test test_unknown_action_errors

test_add_preserves_body_content() {
  local f="$TEST_DIR/test.md"
  printf '# My Document\n\nParagraph one.\n\nParagraph two.\n' > "$f"

  bash "$TAG_SH" add "$f" '#needs-review'

  # Body paragraphs should still be present
  if grep -q 'Paragraph one' "$f" && grep -q 'Paragraph two' "$f"; then
    pass "EDGE-02: Add preserves existing body content"
  else
    fail "EDGE-02: Add preserves existing body content" \
      "Both paragraphs preserved" "$(cat "$f")"
  fi
}
run_test test_add_preserves_body_content

test_swap_no_match_on_tags_line() {
  local f="$TEST_DIR/test.md"
  create_md_with_tags "$f" "#other-tag"

  # Swap a tag that's not on the Tags line — should be silent no-op (Tags-line mode)
  bash "$TAG_SH" swap "$f" '#nonexistent' '#done-something'
  local rc=$?

  local tags_line
  tags_line=$(grep '^\*\*Tags\*\*:' "$f")
  if [[ $rc -eq 0 ]] && [[ "$tags_line" == *"#other-tag"* ]]; then
    pass "EDGE-03: Tags-line swap with no match is no-op"
  else
    fail "EDGE-03: Tags-line swap with no match is no-op" \
      "exit 0, #other-tag preserved" "rc=$rc, tags=$tags_line"
  fi
}
run_test test_swap_no_match_on_tags_line

test_find_in_subdirectories() {
  local dir="$TEST_DIR/sessions"
  mkdir -p "$dir/subdir"
  create_md_with_tags "$dir/subdir/DOC_A.md" "#needs-review"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir")

  if [[ "$output" == *"DOC_A.md"* ]]; then
    pass "EDGE-04: Find searches subdirectories recursively"
  else
    fail "EDGE-04: Find searches subdirectories recursively" \
      "DOC_A.md found in subdir" "$output"
  fi
}
run_test test_find_in_subdirectories

test_find_mixed_bare_and_escaped() {
  local dir="$TEST_DIR/sessions"
  local f="$dir/DOC_A.md"
  # File with BOTH bare inline tag AND backtick-escaped reference
  printf '# Test Document\n**Tags**:\n\nThe `#needs-review` tag is common.\n### Block #needs-review\n' > "$f"

  local output
  output=$(bash "$TAG_SH" find '#needs-review' "$dir")

  # Should find the file (bare inline on line 5)
  if [[ "$output" == *"DOC_A.md"* ]]; then
    pass "EDGE-05: Finds bare inline even when backtick-escaped also present"
  else
    fail "EDGE-05: Finds bare inline even when backtick-escaped also present" \
      "DOC_A.md found" "$output"
  fi
}
run_test test_find_mixed_bare_and_escaped

test_remove_inline_preserves_surrounding() {
  local f="$TEST_DIR/test.md"
  printf '# Test Document\n**Tags**:\n\n### Block — Widget API #needs-decision\nMore text.\n' > "$f"

  bash "$TAG_SH" remove "$f" '#needs-decision' --inline 4

  local line4
  line4=$(sed -n '4p' "$f")
  # Line should still have the heading text, just without the tag
  if [[ "$line4" == *"Widget API"* ]] && [[ "$line4" != *"#needs-decision"* ]]; then
    pass "EDGE-06: Inline remove preserves surrounding text"
  else
    fail "EDGE-06: Inline remove preserves surrounding text" \
      "Widget API without tag" "$line4"
  fi
}
run_test test_remove_inline_preserves_surrounding

# ============================================================
# RESULTS
# ============================================================

exit_with_results
