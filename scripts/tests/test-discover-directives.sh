#!/bin/bash
# ~/.claude/engine/scripts/tests/test-discover-directives.sh — Unit tests for discover-directives.sh
#
# Tests walk-up logic, boundary detection, type filtering, exclusion rules,
# and discovery of all directive types (AGENTS.md, INVARIANTS.md, TESTING.md, PITFALLS.md, CHECKLIST.md, etc.).
#
# Run: bash ~/.claude/engine/scripts/tests/test-discover-directives.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT="$HOME/.claude/scripts/discover-directives.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_PWD=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_PWD="$PWD"
  # Set PWD to sandbox root (project root boundary for walk-up)
  cd "$TEST_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# =============================================================================
# TEST 1: Single directory — finds files in current dir (no walk-up)
# =============================================================================

test_single_dir_finds_agents() {
  local test_name="single dir: finds AGENTS.md in target directory"
  setup

  mkdir -p "$TEST_DIR/src/components"
  echo "# Component Agents" > "$TEST_DIR/src/components/AGENTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/src/components" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"src/components/AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output contains AGENTS.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 2: Walk-up finds files at multiple levels
# =============================================================================

test_walkup_finds_multiple_levels() {
  local test_name="walk-up: finds files at multiple ancestor levels"
  setup

  # Create files at different levels
  echo "# Root Agents" > "$TEST_DIR/AGENTS.md"
  mkdir -p "$TEST_DIR/src/lib"
  echo "# Src INVARIANTS" > "$TEST_DIR/src/INVARIANTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/src/lib" --walk-up 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"INVARIANTS.md"* ]] && [[ "$result" == *"AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, contains INVARIANTS.md and AGENTS.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 3: Walk-up stops at project root boundary (PWD)
# =============================================================================

test_walkup_stops_at_project_root() {
  local test_name="walk-up: stops at project root (PWD) boundary"
  setup

  mkdir -p "$TEST_DIR/deep/nested/dir"
  echo "# Deep Agents" > "$TEST_DIR/deep/nested/dir/AGENTS.md"

  cd "$TEST_DIR/deep"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/deep/nested/dir" --walk-up 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"dir/AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, contains dir/AGENTS.md" "exit=$exit_code, output=$result"
  fi

  cd "$ORIGINAL_PWD"
  teardown
}

# =============================================================================
# TEST 4: No discovery files found — exit 1
# =============================================================================

test_no_files_exits_1() {
  local test_name="no files: exits 1 when no directive files found"
  setup

  mkdir -p "$TEST_DIR/empty/dir"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/empty/dir" --walk-up 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 1" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 5: --type soft returns all soft directive files
# =============================================================================

test_type_soft_filters() {
  local test_name="type soft: returns AGENTS.md, INVARIANTS.md, TESTING.md, PITFALLS.md"
  setup

  mkdir -p "$TEST_DIR/mydir"
  echo "# AGENTS" > "$TEST_DIR/mydir/AGENTS.md"
  echo "# INVARIANTS" > "$TEST_DIR/mydir/INVARIANTS.md"
  echo "# TESTING" > "$TEST_DIR/mydir/TESTING.md"
  echo "# PITFALLS" > "$TEST_DIR/mydir/PITFALLS.md"
  echo "# CHECKLIST" > "$TEST_DIR/mydir/CHECKLIST.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/mydir" --type soft 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"AGENTS.md"* ]] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" == *"TESTING.md"* ]] && \
     [[ "$result" == *"PITFALLS.md"* ]] && \
     [[ "$result" != *"CHECKLIST.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "AGENTS.md + INVARIANTS.md + TESTING.md + PITFALLS.md, no CHECKLIST.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 6: --type hard returns only CHECKLIST.md
# =============================================================================

test_type_hard_filters() {
  local test_name="type hard: returns only CHECKLIST.md"
  setup

  mkdir -p "$TEST_DIR/mydir"
  echo "# README" > "$TEST_DIR/mydir/README.md"
  echo "# PITFALLS" > "$TEST_DIR/mydir/PITFALLS.md"
  echo "# CHECKLIST" > "$TEST_DIR/mydir/CHECKLIST.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/mydir" --type hard 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"CHECKLIST.md"* ]] && \
     [[ "$result" != *"README.md"* ]] && \
     [[ "$result" != *"PITFALLS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "CHECKLIST.md only, no README.md or PITFALLS.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 7: Excluded directories are skipped
# =============================================================================

test_excluded_dirs_skipped() {
  local test_name="exclusions: skips node_modules, .git, sessions, tmp, dist, build"
  setup

  for excl in node_modules .git sessions tmp dist build; do
    mkdir -p "$TEST_DIR/$excl"
    echo "# Should be skipped" > "$TEST_DIR/$excl/AGENTS.md"
  done

  local any_found=false
  for excl in node_modules .git sessions tmp dist build; do
    local result
    result=$(bash "$SCRIPT" "$TEST_DIR/$excl" 2>/dev/null)
    local exit_code=$?
    if [ "$exit_code" -eq 0 ] && [ -n "$result" ]; then
      any_found=true
      break
    fi
  done

  if [ "$any_found" = false ]; then
    pass "$test_name"
  else
    fail "$test_name" "all excluded dirs return exit 1" "at least one returned files"
  fi

  teardown
}

# =============================================================================
# TEST 8: Walk-up deduplicates results
# =============================================================================

test_walkup_deduplicates() {
  local test_name="walk-up: deduplicates results (sort -u)"
  setup

  mkdir -p "$TEST_DIR/src"
  echo "# Root Agents" > "$TEST_DIR/AGENTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/src" --walk-up 2>/dev/null)
  local exit_code=$?

  local count
  count=$(echo "$result" | grep -c "AGENTS.md" || true)

  if [ "$exit_code" -eq 0 ] && [ "$count" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exactly 1 AGENTS.md line" "exit=$exit_code, count=$count"
  fi

  teardown
}

# =============================================================================
# TEST 9: --type all returns both soft and hard files
# =============================================================================

test_type_all_returns_everything() {
  local test_name="type all: returns all directive types"
  setup

  mkdir -p "$TEST_DIR/mydir"
  echo "# AGENTS" > "$TEST_DIR/mydir/AGENTS.md"
  echo "# INVARIANTS" > "$TEST_DIR/mydir/INVARIANTS.md"
  echo "# TESTING" > "$TEST_DIR/mydir/TESTING.md"
  echo "# PITFALLS" > "$TEST_DIR/mydir/PITFALLS.md"
  echo "# CHECKLIST" > "$TEST_DIR/mydir/CHECKLIST.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/mydir" --type all 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"AGENTS.md"* ]] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" == *"TESTING.md"* ]] && \
     [[ "$result" == *"PITFALLS.md"* ]] && \
     [[ "$result" == *"CHECKLIST.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "all 5 directive files" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 10: Default type is 'all'
# =============================================================================

test_default_type_is_all() {
  local test_name="default: no --type flag behaves like --type all"
  setup

  mkdir -p "$TEST_DIR/mydir"
  echo "# AGENTS" > "$TEST_DIR/mydir/AGENTS.md"
  echo "# CHECKLIST" > "$TEST_DIR/mydir/CHECKLIST.md"
  echo "# PITFALLS" > "$TEST_DIR/mydir/PITFALLS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/mydir" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"AGENTS.md"* ]] && \
     [[ "$result" == *"CHECKLIST.md"* ]] && \
     [[ "$result" == *"PITFALLS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "AGENTS.md, CHECKLIST.md, and PITFALLS.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 11: Discovers PITFALLS.md specifically
# =============================================================================

test_discovers_pitfalls() {
  local test_name="pitfalls: discovers PITFALLS.md in target directory"
  setup

  mkdir -p "$TEST_DIR/src/lib"
  echo "# Pitfalls for this module" > "$TEST_DIR/src/lib/PITFALLS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/src/lib" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"PITFALLS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output contains PITFALLS.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 12: Discovers TESTING.md specifically
# =============================================================================

test_discovers_testing() {
  local test_name="testing: discovers TESTING.md in target directory"
  setup

  mkdir -p "$TEST_DIR/packages/shared"
  echo "# Testing standards" > "$TEST_DIR/packages/shared/TESTING.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/packages/shared" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"TESTING.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output contains TESTING.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 13: Walk-up finds PITFALLS.md at ancestor level
# =============================================================================

test_walkup_finds_pitfalls_ancestor() {
  local test_name="walk-up: finds PITFALLS.md at ancestor level"
  setup

  echo "# Root Pitfalls" > "$TEST_DIR/PITFALLS.md"
  mkdir -p "$TEST_DIR/src/deep/nested"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/src/deep/nested" --walk-up 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"PITFALLS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output contains PITFALLS.md" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-discover-directives.sh ==="

test_single_dir_finds_agents
test_walkup_finds_multiple_levels
test_walkup_stops_at_project_root
test_no_files_exits_1
test_type_soft_filters
test_type_hard_filters
test_excluded_dirs_skipped
test_walkup_deduplicates
test_type_all_returns_everything
test_default_type_is_all
test_discovers_pitfalls
test_discovers_testing
test_walkup_finds_pitfalls_ancestor

# Summary
exit_with_results
