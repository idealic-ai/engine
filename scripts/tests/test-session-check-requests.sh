#!/bin/bash
# ============================================================================
# test-session-check-requests.sh — Tests for session.sh check Validation 3
# ============================================================================
# Verifies that session.sh check correctly validates requestFiles before
# deactivation (INV_REQUEST_BEFORE_CLOSE). Covers:
#   - Type A: Formal REQUEST files (filename contains "REQUEST")
#   - Type B: Inline-tag source files (any other file)
#   - Skip paths (empty requestFiles, requestCheckPassed=true)
#   - Edge cases (mixed types, mixed escaping, multiple files)
#
# Promoted from tmp/test-inline-tag-validation.sh + new edge cases.
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

# Helper: create a session dir with .state.json configured for V3 testing.
# V1 tag scan is pre-passed (tagCheckPassed=true) so we isolate V3.
# Args: $1=name, $2=JSON array of request file paths
make_session() {
  local name="$1"
  local request_files_json="$2"
  local dir="$TEST_DIR/sessions/$name"
  mkdir -p "$dir"
  cat > "$dir/.state.json" <<SJSON
{
  "lifecycle": "active",
  "skill": "implement",
  "pid": 1234,
  "tagCheckPassed": true,
  "requestCheckPassed": false,
  "checkPassed": false,
  "discoveredChecklists": [],
  "requestFiles": $request_files_json
}
SJSON
  echo "$dir"
}

# ============================================================================
# PROMOTED TESTS (P-01 through P-11) — from tmp/test-inline-tag-validation.sh
# ============================================================================

test_p01_inline_source_bare_needs_blocks() {
  local S req_file
  req_file="$TEST_DIR/p01_source.md"
  cat > "$req_file" <<'MD'
# Some Debrief
**Tags**: #done-brainstorm

## Section
This has a bare #needs-implementation tag inline.
MD
  S=$(make_session "p01" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "P-01: inline source file with bare #needs-* blocks"
  else
    fail "P-01: inline source file with bare #needs-* blocks" "exit 1" "exit $exit_code"
  fi
}

test_p02_inline_source_done_only_passes() {
  local S req_file
  req_file="$TEST_DIR/p02_source.md"
  cat > "$req_file" <<'MD'
# Some Debrief
**Tags**: #done-implementation

## Section
All tags resolved. This used to have #done-implementation inline too.
MD
  S=$(make_session "p02" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "P-02: inline source file with #done-* only passes"
  else
    fail "P-02: inline source file with #done-* only passes" "exit 0" "exit $exit_code"
  fi
}

test_p03_inline_source_escaped_passes() {
  local S req_file
  req_file="$TEST_DIR/p03_source.md"
  cat > "$req_file" <<'MD'
# Analysis Report
**Tags**: #done-review

## Notes
The `#needs-implementation` tag was discussed but is just a reference.
We also mentioned `#needs-brainstorm` in passing.
MD
  S=$(make_session "p03" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "P-03: backtick-escaped #needs-* in source file passes"
  else
    fail "P-03: backtick-escaped #needs-* in source file passes" "exit 0" "exit $exit_code"
  fi
}

test_p04_inline_source_missing_blocks() {
  local S
  S=$(make_session "p04" "[\"$TEST_DIR/nonexistent_file.md\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "P-04: missing request file blocks"
  else
    fail "P-04: missing request file blocks" "exit 1" "exit $exit_code"
  fi
}

test_p05_request_no_response_blocks() {
  local S req_file
  req_file="$TEST_DIR/IMPLEMENTATION_REQUEST_FEATURE.md"
  cat > "$req_file" <<'MD'
# Implementation Request: Feature
**Tags**: #needs-implementation

## Context
Some context here.

## Expectations
Build the thing.
MD
  S=$(make_session "p05" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "P-05: formal REQUEST without ## Response blocks"
  else
    fail "P-05: formal REQUEST without ## Response blocks" "exit 1" "exit $exit_code"
  fi
}

test_p06_request_fulfilled_passes() {
  local S req_file
  req_file="$TEST_DIR/BRAINSTORM_REQUEST_DESIGN.md"
  cat > "$req_file" <<'MD'
# Brainstorm Request: Design
**Tags**: #done-brainstorm

## Context
Discuss design options.

## Response
Fulfilled by: sessions/2026_02_09_TOPIC/
Summary: Design options explored, decision made.
MD
  S=$(make_session "p06" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "P-06: fulfilled formal REQUEST passes"
  else
    fail "P-06: fulfilled formal REQUEST passes" "exit 0" "exit $exit_code"
  fi
}

test_p07_mixed_types_one_failing_blocks() {
  local S source_file req_file
  source_file="$TEST_DIR/p07_debrief.md"
  cat > "$source_file" <<'MD'
# Brainstorm
**Tags**: #done-brainstorm

## Ideas
This still has #needs-implementation inline.
MD
  req_file="$TEST_DIR/IMPLEMENTATION_REQUEST_THING.md"
  cat > "$req_file" <<'MD'
# Implementation Request: Thing
**Tags**: #done-implementation

## Response
Done.
MD
  S=$(make_session "p07" "[\"$source_file\", \"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "P-07: mixed types with one failing Type B blocks"
  else
    fail "P-07: mixed types with one failing Type B blocks" "exit 1" "exit $exit_code"
  fi
}

test_p08_inline_source_needs_on_tags_line_blocks() {
  local S req_file
  req_file="$TEST_DIR/p08_source.md"
  cat > "$req_file" <<'MD'
# Debrief
**Tags**: #needs-review

## Section
Clean body text, no inline tags.
MD
  S=$(make_session "p08" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "P-08: bare #needs-* on Tags line of source file blocks"
  else
    fail "P-08: bare #needs-* on Tags line of source file blocks" "exit 0" "exit $exit_code"
  fi
}

test_p09_empty_request_files_passes() {
  local S
  S=$(make_session "p09" "[]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "P-09: empty requestFiles array passes (skips V3)"
  else
    fail "P-09: empty requestFiles array passes (skips V3)" "exit 0" "exit $exit_code"
  fi
}

test_p10_request_bare_needs_in_body_blocks() {
  local S req_file
  req_file="$TEST_DIR/BRAINSTORM_REQUEST_DESIGN2.md"
  cat > "$req_file" <<'MD'
# Brainstorm Request: Design
**Tags**: #done-brainstorm

## Context
This mentions #needs-implementation inline in the body.

## Response
Fulfilled by: sessions/2026_02_09_TOPIC/
Summary: Design explored.
MD
  S=$(make_session "p10" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "P-10: REQUEST file with bare #needs-* in body blocks"
  else
    fail "P-10: REQUEST file with bare #needs-* in body blocks" "exit 1" "exit $exit_code"
  fi
}

test_p11_request_fully_clean_passes() {
  local S req_file
  req_file="$TEST_DIR/IMPLEMENTATION_REQUEST_CLEAN.md"
  cat > "$req_file" <<'MD'
# Implementation Request: Clean
**Tags**: #done-implementation

## Context
This references `#needs-brainstorm` only as escaped text.

## Response
Fulfilled by: sessions/2026_02_09_TOPIC/
Summary: Implemented cleanly.
MD
  S=$(make_session "p11" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "P-11: fully clean REQUEST file passes"
  else
    fail "P-11: fully clean REQUEST file passes" "exit 0" "exit $exit_code"
  fi
}

# ============================================================================
# NEW EDGE CASES (E-01 through E-05)
# ============================================================================

test_e01_request_check_passed_skips() {
  local S req_file
  req_file="$TEST_DIR/e01_unfulfilled.md"
  cat > "$req_file" <<'MD'
# Some File
**Tags**: #needs-implementation

## Still has bare tags — would fail if scanned
MD
  local dir="$TEST_DIR/sessions/e01"
  mkdir -p "$dir"
  # requestCheckPassed=true — should skip V3 entirely
  cat > "$dir/.state.json" <<SJSON
{
  "lifecycle": "active",
  "skill": "implement",
  "pid": 1234,
  "tagCheckPassed": true,
  "requestCheckPassed": true,
  "checkPassed": false,
  "discoveredChecklists": [],
  "requestFiles": ["$req_file"]
}
SJSON

  local exit_code output
  output=$("$SESSION_SH" check "$dir" < /dev/null 2>&1)
  exit_code=$?

  if [ "$exit_code" -eq 0 ] && echo "$output" | grep -q "already passed"; then
    pass "E-01: requestCheckPassed=true skips V3"
  else
    fail "E-01: requestCheckPassed=true skips V3" "exit 0 + 'already passed'" "exit=$exit_code"
  fi
}

test_e02_request_needs_on_tags_line_blocks() {
  local S req_file
  req_file="$TEST_DIR/IMPLEMENTATION_REQUEST_TAGSLINE.md"
  cat > "$req_file" <<'MD'
# Implementation Request: Tags Line Test
**Tags**: #needs-implementation

## Context
The tags line still has bare #needs-implementation.

## Response
Fulfilled by: sessions/2026_02_09_TOPIC/
Summary: Done but forgot to swap tag.
MD
  S=$(make_session "e02" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "E-02: REQUEST with #needs-* on Tags line blocks"
  else
    fail "E-02: REQUEST with #needs-* on Tags line blocks" "exit 1" "exit $exit_code"
  fi
}

test_e03_mixed_escaped_bare_same_line_blocks() {
  local S req_file
  req_file="$TEST_DIR/IMPLEMENTATION_REQUEST_MIXED.md"
  cat > "$req_file" <<'MD'
# Implementation Request: Mixed Escaping
**Tags**: #done-implementation

## Context
Resolved `#needs-brainstorm` but found #needs-implementation here.

## Response
Fulfilled by: sessions/2026_02_09_TOPIC/
Summary: Partially resolved.
MD
  S=$(make_session "e03" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "E-03: mixed escaped+bare #needs-* on same line blocks"
  else
    fail "E-03: mixed escaped+bare #needs-* on same line blocks" "exit 1" "exit $exit_code"
  fi
}

test_e04_multiple_request_files_all_pass() {
  local S req_a req_b req_c
  req_a="$TEST_DIR/IMPLEMENTATION_REQUEST_A.md"
  cat > "$req_a" <<'MD'
# Implementation Request: A
**Tags**: #done-implementation

## Response
Done.
MD
  req_b="$TEST_DIR/e04_source_b.md"
  cat > "$req_b" <<'MD'
# Debrief B
**Tags**: #done-review

## Summary
All clean, no bare tags.
MD
  req_c="$TEST_DIR/BRAINSTORM_REQUEST_C.md"
  cat > "$req_c" <<'MD'
# Brainstorm Request: C
**Tags**: #done-brainstorm

## Response
Explored and decided.
MD
  S=$(make_session "e04" "[\"$req_a\", \"$req_b\", \"$req_c\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "E-04: multiple request files all passing"
  else
    fail "E-04: multiple request files all passing" "exit 0" "exit $exit_code"
  fi
}

test_e05_request_file_with_active_tag_passes() {
  local S req_file
  req_file="$TEST_DIR/e05_source.md"
  cat > "$req_file" <<'MD'
# Debrief
**Tags**: #done-implementation

## Notes
The #active-implementation tag was left here but V3 only checks #needs-*.
MD
  S=$(make_session "e05" "[\"$req_file\"]")

  local exit_code
  "$SESSION_SH" check "$S" < /dev/null > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "E-05: request file with bare #active-* passes (V3 only checks #needs-*)"
  else
    fail "E-05: request file with bare #active-* passes (V3 only checks #needs-*)" "exit 0" "exit $exit_code"
  fi
}

# ============================================================================
# RUN ALL TESTS
# ============================================================================
setup

echo "=== session.sh check Validation 3: Request Files ==="
echo ""
echo "--- Promoted tests (P-01 through P-11) ---"

test_p01_inline_source_bare_needs_blocks
test_p02_inline_source_done_only_passes
test_p03_inline_source_escaped_passes
test_p04_inline_source_missing_blocks
test_p05_request_no_response_blocks
test_p06_request_fulfilled_passes
test_p07_mixed_types_one_failing_blocks
test_p08_inline_source_needs_on_tags_line_blocks
test_p09_empty_request_files_passes
test_p10_request_bare_needs_in_body_blocks
test_p11_request_fully_clean_passes

echo ""
echo "--- New edge cases (E-01 through E-05) ---"

test_e01_request_check_passed_skips
test_e02_request_needs_on_tags_line_blocks
test_e03_mixed_escaped_bare_same_line_blocks
test_e04_multiple_request_files_all_pass
test_e05_request_file_with_active_tag_passes

teardown

exit_with_results
