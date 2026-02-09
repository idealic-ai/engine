#!/bin/bash
# ~/.claude/engine/scripts/tests/test-glob-sh.sh — Deep coverage tests for glob.sh
#
# Tests pattern translation, symlink traversal, mtime sorting, path output
# Covers: **, **/*.ext, *.ext, prefix/**/*.ext, dir/*.ext, symlinks, missing paths
#
# Run: bash ~/.claude/engine/scripts/tests/test-glob-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

GLOB_SH="$HOME/.claude/engine/scripts/glob.sh"

TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: create a file tree for testing
create_tree() {
  local root="$1"
  mkdir -p "$root/src/lib" "$root/src/tests" "$root/docs"
  echo "a" > "$root/README.md"
  echo "b" > "$root/docs/guide.md"
  echo "c" > "$root/docs/api.md"
  echo "d" > "$root/src/index.ts"
  echo "e" > "$root/src/lib/utils.ts"
  echo "f" > "$root/src/lib/helper.ts"
  echo "g" > "$root/src/tests/utils.test.ts"
  echo "h" > "$root/src/tests/helper.test.ts"
  # Set different mtimes so sort order is deterministic
  touch -t 202601010000 "$root/README.md"
  touch -t 202601020000 "$root/docs/guide.md"
  touch -t 202601030000 "$root/docs/api.md"
  touch -t 202601040000 "$root/src/index.ts"
  touch -t 202601050000 "$root/src/lib/utils.ts"
  touch -t 202601060000 "$root/src/lib/helper.ts"
  touch -t 202601070000 "$root/src/tests/utils.test.ts"
  touch -t 202601080000 "$root/src/tests/helper.test.ts"
}

echo "=== glob.sh Deep Coverage Tests ==="
echo ""

# ============================================================
# PATTERN: ** (all files recursively)
# ============================================================
echo "--- Pattern: ** (all files) ---"

test_doublestar_all_files() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  if [[ $count -eq 8 ]]; then
    pass "STAR-01: ** finds all 8 files recursively"
  else
    fail "STAR-01: ** finds all 8 files recursively" \
      "8 files" "$count files"
  fi
}
run_test test_doublestar_all_files

test_doublestar_mtime_order() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**' "$TEST_DIR/project")
  local first_file
  first_file=$(echo "$output" | head -1)
  local last_file
  last_file=$(echo "$output" | tail -1)

  # helper.test.ts has newest mtime, README.md has oldest
  if [[ "$first_file" == *"helper.test.ts"* ]] && [[ "$last_file" == *"README.md"* ]]; then
    pass "STAR-02: ** returns newest-first mtime order"
  else
    fail "STAR-02: ** returns newest-first mtime order" \
      "first=helper.test.ts, last=README.md" "first=$first_file, last=$last_file"
  fi
}
run_test test_doublestar_mtime_order

# ============================================================
# PATTERN: **/*.ext (recursive with name glob)
# ============================================================
echo ""
echo "--- Pattern: **/*.ext (recursive name glob) ---"

test_recursive_name_glob_ts() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**/*.ts' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find: index.ts, utils.ts, helper.ts, utils.test.ts, helper.test.ts = 5
  if [[ $count -eq 5 ]]; then
    pass "REC-01: **/*.ts finds all 5 .ts files"
  else
    fail "REC-01: **/*.ts finds all 5 .ts files" \
      "5 files" "$count files: $output"
  fi
}
run_test test_recursive_name_glob_ts

test_recursive_name_glob_md() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**/*.md' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find: README.md, guide.md, api.md = 3
  if [[ $count -eq 3 ]]; then
    pass "REC-02: **/*.md finds all 3 .md files"
  else
    fail "REC-02: **/*.md finds all 3 .md files" \
      "3 files" "$count files: $output"
  fi
}
run_test test_recursive_name_glob_md

test_recursive_name_glob_test_ts() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**/*.test.ts' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find: utils.test.ts, helper.test.ts = 2
  if [[ $count -eq 2 ]]; then
    pass "REC-03: **/*.test.ts finds only 2 test files"
  else
    fail "REC-03: **/*.test.ts finds only 2 test files" \
      "2 files" "$count files: $output"
  fi
}
run_test test_recursive_name_glob_test_ts

# ============================================================
# PATTERN: prefix/**/*.ext (prefix + recursive)
# ============================================================
echo ""
echo "--- Pattern: prefix/**/*.ext ---"

test_prefix_recursive() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" 'src/**/*.ts' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find: src/index.ts, src/lib/utils.ts, src/lib/helper.ts,
  # src/tests/utils.test.ts, src/tests/helper.test.ts = 5
  if [[ $count -eq 5 ]]; then
    pass "PRE-01: src/**/*.ts finds all 5 .ts files under src/"
  else
    fail "PRE-01: src/**/*.ts finds all 5 .ts files under src/" \
      "5 files" "$count files: $output"
  fi
}
run_test test_prefix_recursive

test_prefix_recursive_subdir() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" 'src/lib/**/*.ts' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find: src/lib/utils.ts, src/lib/helper.ts = 2
  if [[ $count -eq 2 ]]; then
    pass "PRE-02: src/lib/**/*.ts finds only 2 lib files"
  else
    fail "PRE-02: src/lib/**/*.ts finds only 2 lib files" \
      "2 files" "$count files: $output"
  fi
}
run_test test_prefix_recursive_subdir

# ============================================================
# PATTERN: *.ext (shallow, root only)
# ============================================================
echo ""
echo "--- Pattern: *.ext (shallow) ---"

test_shallow_glob() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '*.md' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find only README.md (root level), NOT docs/*.md
  if [[ $count -eq 1 ]] && [[ "$output" == *"README.md"* ]]; then
    pass "SHAL-01: *.md finds only root-level README.md"
  else
    fail "SHAL-01: *.md finds only root-level README.md" \
      "1 file (README.md)" "$count files: $output"
  fi
}
run_test test_shallow_glob

test_shallow_no_match() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '*.py' "$TEST_DIR/project")

  if [[ -z "$output" ]]; then
    pass "SHAL-02: *.py returns empty (no Python files)"
  else
    fail "SHAL-02: *.py returns empty (no Python files)" \
      "<empty>" "$output"
  fi
}
run_test test_shallow_no_match

# ============================================================
# PATTERN: dir/*.ext (directory + shallow)
# ============================================================
echo ""
echo "--- Pattern: dir/*.ext ---"

test_dir_shallow_glob() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" 'docs/*.md' "$TEST_DIR/project")
  local count
  count=$(echo "$output" | grep -c '' || true)

  # Should find: docs/guide.md, docs/api.md = 2
  if [[ $count -eq 2 ]]; then
    pass "DIR-01: docs/*.md finds 2 doc files"
  else
    fail "DIR-01: docs/*.md finds 2 doc files" \
      "2 files" "$count files: $output"
  fi
}
run_test test_dir_shallow_glob

# ============================================================
# SYMLINK TRAVERSAL
# ============================================================
echo ""
echo "--- Symlink Traversal ---"

test_follows_symlinks() {
  # Create a real dir and a symlink to it
  mkdir -p "$TEST_DIR/real-dir"
  echo "x" > "$TEST_DIR/real-dir/data.md"
  touch -t 202601010000 "$TEST_DIR/real-dir/data.md"

  mkdir -p "$TEST_DIR/project"
  ln -sf "$TEST_DIR/real-dir" "$TEST_DIR/project/linked"

  local output
  output=$(bash "$GLOB_SH" '**/*.md' "$TEST_DIR/project")

  if [[ "$output" == *"data.md"* ]]; then
    pass "SYM-01: Follows symlinked directories (-L)"
  else
    fail "SYM-01: Follows symlinked directories (-L)" \
      "data.md found through symlink" "$output"
  fi
}
run_test test_follows_symlinks

test_symlinked_root() {
  # Root path itself is a symlink
  mkdir -p "$TEST_DIR/real-sessions/2026_01_01_FOO"
  echo "x" > "$TEST_DIR/real-sessions/2026_01_01_FOO/LOG.md"
  touch -t 202601010000 "$TEST_DIR/real-sessions/2026_01_01_FOO/LOG.md"

  ln -sf "$TEST_DIR/real-sessions" "$TEST_DIR/sessions"

  local output
  output=$(bash "$GLOB_SH" '**/*.md' "$TEST_DIR/sessions")

  if [[ "$output" == *"sessions/"* ]] && [[ "$output" == *"LOG.md"* ]]; then
    pass "SYM-02: Works when root path is a symlink (preserves original path)"
  else
    fail "SYM-02: Works when root path is a symlink (preserves original path)" \
      "sessions/.../LOG.md" "$output"
  fi
}
run_test test_symlinked_root

# ============================================================
# PATH OUTPUT FORMAT
# ============================================================
echo ""
echo "--- Path Output ---"

test_output_preserves_original_root() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**/*.md' "$TEST_DIR/project")

  # All paths should start with the original root
  local bad_paths
  bad_paths=$(echo "$output" | grep -v "^$TEST_DIR/project/" || true)
  if [[ -z "$bad_paths" ]]; then
    pass "PATH-01: All paths prefixed with original root"
  else
    fail "PATH-01: All paths prefixed with original root" \
      "All start with $TEST_DIR/project/" "Bad: $bad_paths"
  fi
}
run_test test_output_preserves_original_root

test_default_root_is_dot() {
  create_tree "$TEST_DIR/project"

  # Run from inside the project dir with no path arg
  local output
  output=$(cd "$TEST_DIR/project" && bash "$GLOB_SH" '*.md')

  # Should output relative path without "./" prefix
  if [[ "$output" == "README.md" ]]; then
    pass "PATH-02: Default root (.) outputs relative paths"
  else
    fail "PATH-02: Default root (.) outputs relative paths" \
      "README.md" "$output"
  fi
}
run_test test_default_root_is_dot

# ============================================================
# EDGE CASES
# ============================================================
echo ""
echo "--- Edge Cases ---"

test_missing_path_exits_clean() {
  local output
  output=$(bash "$GLOB_SH" '**/*.md' "$TEST_DIR/nonexistent" 2>&1)
  local rc=$?

  if [[ $rc -eq 0 ]] && [[ -z "$output" ]]; then
    pass "EDGE-01: Missing path exits 0 with no output"
  else
    fail "EDGE-01: Missing path exits 0 with no output" \
      "exit 0, empty" "rc=$rc, output=$output"
  fi
}
run_test test_missing_path_exits_clean

test_empty_directory() {
  mkdir -p "$TEST_DIR/empty"

  local output
  output=$(bash "$GLOB_SH" '**' "$TEST_DIR/empty")

  if [[ -z "$output" ]]; then
    pass "EDGE-02: Empty directory returns no output"
  else
    fail "EDGE-02: Empty directory returns no output" \
      "<empty>" "$output"
  fi
}
run_test test_empty_directory

test_no_args_errors() {
  local output
  output=$(bash "$GLOB_SH" 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Usage"* ]]; then
    pass "EDGE-03: No arguments shows usage and exits 1"
  else
    fail "EDGE-03: No arguments shows usage and exits 1" \
      "exit 1 + Usage" "rc=$rc, output=$output"
  fi
}
run_test test_no_args_errors

test_nonexistent_prefix_pattern() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" 'nonexistent/**/*.ts' "$TEST_DIR/project")

  if [[ -z "$output" ]]; then
    pass "EDGE-04: Nonexistent prefix in pattern returns empty"
  else
    fail "EDGE-04: Nonexistent prefix in pattern returns empty" \
      "<empty>" "$output"
  fi
}
run_test test_nonexistent_prefix_pattern

test_no_matching_extension() {
  create_tree "$TEST_DIR/project"

  local output
  output=$(bash "$GLOB_SH" '**/*.xyz' "$TEST_DIR/project")

  if [[ -z "$output" ]]; then
    pass "EDGE-05: No matching extension returns empty"
  else
    fail "EDGE-05: No matching extension returns empty" \
      "<empty>" "$output"
  fi
}
run_test test_no_matching_extension

# ============================================================
# RESULTS
# ============================================================
exit_with_results
