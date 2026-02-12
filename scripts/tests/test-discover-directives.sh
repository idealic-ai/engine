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
# TEST 14: --root caps walk-up boundary
# =============================================================================

test_root_caps_walkup() {
  local test_name="root flag: --root caps walk-up boundary"
  setup

  # AGENTS.md at TEST_DIR root (should NOT be found — outside --root boundary)
  echo "# Root Agents" > "$TEST_DIR/AGENTS.md"
  # INVARIANTS.md inside the --root boundary
  mkdir -p "$TEST_DIR/sub/deep"
  echo "# Deep INVARIANTS" > "$TEST_DIR/sub/deep/INVARIANTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/sub/deep" --walk-up --root "$TEST_DIR/sub" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" != *"AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "INVARIANTS.md found, AGENTS.md NOT found" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 15: --root tighter than PWD wins
# =============================================================================

test_root_tighter_than_pwd() {
  local test_name="root flag: --root tighter than PWD wins"
  setup

  # PWD is TEST_DIR (set by setup's cd)
  mkdir -p "$TEST_DIR/a/b/c"
  echo "# C Agents" > "$TEST_DIR/a/b/c/AGENTS.md"
  echo "# A INVARIANTS" > "$TEST_DIR/a/INVARIANTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/a/b/c" --walk-up --root "$TEST_DIR/a/b" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"AGENTS.md"* ]] && \
     [[ "$result" != *"INVARIANTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "AGENTS.md found at c, INVARIANTS.md NOT found at a" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 16: --root same as target — no walk-up
# =============================================================================

test_root_same_as_target() {
  local test_name="root flag: --root same as target dir — no walk-up"
  setup

  mkdir -p "$TEST_DIR/mydir"
  echo "# Root Agents" > "$TEST_DIR/AGENTS.md"
  echo "# Mydir INVARIANTS" > "$TEST_DIR/mydir/INVARIANTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/mydir" --walk-up --root "$TEST_DIR/mydir" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" != *"AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "only INVARIANTS.md (no walk-up past root)" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 17: --root without --walk-up has no effect
# =============================================================================

test_root_without_walkup() {
  local test_name="root flag: --root without --walk-up has no effect"
  setup

  mkdir -p "$TEST_DIR/sub/deep"
  echo "# Deep INVARIANTS" > "$TEST_DIR/sub/deep/INVARIANTS.md"
  echo "# Root Agents" > "$TEST_DIR/AGENTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/sub/deep" --root "$TEST_DIR/sub" 2>/dev/null)
  local exit_code=$?

  # Without --walk-up, only target dir is scanned — same as no --root
  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" != *"AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "only target dir scanned (INVARIANTS.md)" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 18: --root with --type soft filters correctly
# =============================================================================

test_root_with_type_soft() {
  local test_name="root flag: --root with --type soft filters correctly"
  setup

  mkdir -p "$TEST_DIR/sub/deep"
  echo "# Deep AGENTS" > "$TEST_DIR/sub/deep/AGENTS.md"
  echo "# Sub CHECKLIST" > "$TEST_DIR/sub/CHECKLIST.md"
  echo "# Root INVARIANTS" > "$TEST_DIR/INVARIANTS.md"

  local result
  result=$(bash "$SCRIPT" "$TEST_DIR/sub/deep" --walk-up --type soft --root "$TEST_DIR/sub" 2>/dev/null)
  local exit_code=$?

  # Should find AGENTS.md (soft, at target), NOT CHECKLIST.md (hard, filtered by --type soft)
  # Should NOT find INVARIANTS.md at TEST_DIR (outside --root boundary)
  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"AGENTS.md"* ]] && \
     [[ "$result" != *"CHECKLIST.md"* ]] && \
     [[ "$result" != *"INVARIANTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "AGENTS.md only (soft + root-capped)" "exit=$exit_code, output=$result"
  fi

  teardown
}

# =============================================================================
# TEST 19: --root walk-up works when target is NOT under PWD (cross-tree)
# =============================================================================

test_root_cross_tree_walkup() {
  local test_name="root flag: walk-up works when target is NOT under PWD (cross-tree)"
  setup

  # Simulate real-world: PWD=/Users/x/Projects/finch (LONGER path), target=~/.claude/deep (SHORTER --root)
  # The bug: string-length comparison picks PWD as boundary when PWD is longer, even though
  # PWD is in a completely different tree from the target. Walk-up breaks immediately.
  # Key: project_dir must be LONGER than other_tree to trigger the bug.
  local project_dir="$TEST_DIR/users/someone/Projects/myproject"
  local other_tree="$TEST_DIR/dotclaude"

  mkdir -p "$project_dir"
  mkdir -p "$other_tree/deep/nested"
  mkdir -p "$other_tree/.directives"
  echo "# Tree INVARIANTS" > "$other_tree/.directives/INVARIANTS.md"

  # Set PWD to project dir (different tree, LONGER path)
  cd "$project_dir"

  local result
  result=$(bash "$SCRIPT" "$other_tree/deep/nested" --walk-up --root "$other_tree" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"INVARIANTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, INVARIANTS.md found via walk-up" "exit=$exit_code, output=$result"
  fi

  cd "$ORIGINAL_PWD"
  teardown
}

# =============================================================================
# TEST 20: --root walk-up finds intermediate .directives/ in cross-tree
# =============================================================================

test_root_cross_tree_intermediate_directives() {
  local test_name="root flag: walk-up finds .directives/ at intermediate level (cross-tree)"
  setup

  # Simulate: PWD = /Users/x/Projects/finch (LONGER), target = ~/.claude/skills/analyze/modes/
  # .directives/INVARIANTS.md is at ~/.claude/skills/ (intermediate ancestor)
  # Key: project_dir LONGER than claude_dir to trigger the bug
  local project_dir="$TEST_DIR/users/someone/Projects/myproject"
  local claude_dir="$TEST_DIR/dc"

  mkdir -p "$project_dir"
  mkdir -p "$claude_dir/skills/analyze/modes"
  mkdir -p "$claude_dir/skills/.directives"
  echo "# Skills INVARIANTS" > "$claude_dir/skills/.directives/INVARIANTS.md"

  # PWD is in a completely different tree (and LONGER)
  cd "$project_dir"

  local result
  result=$(bash "$SCRIPT" "$claude_dir/skills/analyze/modes" --walk-up --root "$claude_dir" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$result" == *"INVARIANTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, skills/.directives/INVARIANTS.md found" "exit=$exit_code, output=$result"
  fi

  cd "$ORIGINAL_PWD"
  teardown
}

# =============================================================================
# TEST 21: --root walk-up finds files at multiple levels in cross-tree
# =============================================================================

test_root_cross_tree_multiple_levels() {
  local test_name="root flag: walk-up finds files at multiple ancestor levels (cross-tree)"
  setup

  # Key: project_dir LONGER than claude_dir to trigger the bug
  local project_dir="$TEST_DIR/users/someone/Projects/myproject"
  local claude_dir="$TEST_DIR/dc"

  mkdir -p "$project_dir"
  mkdir -p "$claude_dir/skills/analyze/modes"
  mkdir -p "$claude_dir/skills/analyze/.directives"
  mkdir -p "$claude_dir/skills/.directives"
  mkdir -p "$claude_dir/.directives"

  echo "# Analyze TESTING" > "$claude_dir/skills/analyze/.directives/TESTING.md"
  echo "# Skills INVARIANTS" > "$claude_dir/skills/.directives/INVARIANTS.md"
  echo "# Root AGENTS" > "$claude_dir/.directives/AGENTS.md"

  cd "$project_dir"

  local result
  result=$(bash "$SCRIPT" "$claude_dir/skills/analyze/modes" --walk-up --root "$claude_dir" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"TESTING.md"* ]] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" == *"AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "all 3 files from different ancestor levels" "exit=$exit_code, output=$result"
  fi

  cd "$ORIGINAL_PWD"
  teardown
}

# =============================================================================
# TEST 22: --root cross-tree still caps at root boundary
# =============================================================================

test_root_cross_tree_caps_at_root() {
  local test_name="root flag: cross-tree walk-up stops at --root boundary"
  setup

  # Key: project_dir LONGER than claude_dir to trigger the bug
  local project_dir="$TEST_DIR/users/someone/Projects/myproject"
  local claude_dir="$TEST_DIR/dc"

  mkdir -p "$project_dir"
  mkdir -p "$claude_dir/skills/analyze"
  # File ABOVE the --root (should NOT be found)
  echo "# Above Root" > "$TEST_DIR/AGENTS.md"
  # File AT the --root (should be found)
  echo "# Root INVARIANTS" > "$claude_dir/INVARIANTS.md"

  cd "$project_dir"

  local result
  result=$(bash "$SCRIPT" "$claude_dir/skills/analyze" --walk-up --root "$claude_dir" 2>/dev/null)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ] && \
     [[ "$result" == *"INVARIANTS.md"* ]] && \
     [[ "$result" != *"Above Root"* ]] && \
     [[ "$result" != *"$TEST_DIR/AGENTS.md"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "INVARIANTS.md at root, NOT AGENTS.md above root" "exit=$exit_code, output=$result"
  fi

  cd "$ORIGINAL_PWD"
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

# --root flag tests
test_root_caps_walkup
test_root_tighter_than_pwd
test_root_same_as_target
test_root_without_walkup
test_root_with_type_soft

# --root cross-tree tests (PWD not ancestor of target)
test_root_cross_tree_walkup
test_root_cross_tree_intermediate_directives
test_root_cross_tree_multiple_levels
test_root_cross_tree_caps_at_root

# Summary
exit_with_results
