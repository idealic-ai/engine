#!/bin/bash
# discover-directives.sh — Discover directive markdown files in a directory (and ancestors)
#
# Usage: discover-directives.sh <target-dir> [--walk-up] [--type soft|hard|all] [--include-shared]
#
# Directive types:
#   soft: README.md, INVARIANTS.md, TESTING.md, PITFALLS.md
#   hard: CHECKLIST.md
#   all:  both soft and hard (default)
#
# Options:
#   --walk-up          Traverse ancestor directories up to PWD boundary
#   --type <type>      Filter by directive type (soft|hard|all, default: all)
#   --include-shared   Accepted flag (reserved for session.sh, currently no-op)
#
# Output: Absolute paths, one per line, deduplicated (sort -u)
# Exit:   0 if files found, 1 if nothing found

set -uo pipefail

# --- Parse arguments ---
TARGET_DIR=""
WALK_UP=false
TYPE="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --walk-up)
      WALK_UP=true
      shift
      ;;
    --type)
      TYPE="${2:-all}"
      shift 2
      ;;
    --include-shared)
      shift
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  echo "Usage: discover-directives.sh <target-dir> [--walk-up] [--type soft|hard|all]" >&2
  exit 1
fi

# Resolve to absolute path
if [[ "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="$PWD/$TARGET_DIR"
fi

# Normalize (remove trailing slash)
TARGET_DIR="${TARGET_DIR%/}"

# --- Excluded directory names ---
EXCLUDED_DIRS="node_modules .git sessions tmp dist build"

# --- Directive file lists ---
SOFT_FILES="README.md INVARIANTS.md TESTING.md PITFALLS.md"
HARD_FILES="CHECKLIST.md"

# Determine which files to look for based on --type
case "$TYPE" in
  soft)
    DIRECTIVE_FILES="$SOFT_FILES"
    ;;
  hard)
    DIRECTIVE_FILES="$HARD_FILES"
    ;;
  all|*)
    DIRECTIVE_FILES="$SOFT_FILES $HARD_FILES"
    ;;
esac

# --- Check if a directory is excluded ---
is_excluded() {
  local dir_path="$1"
  local dir_name
  dir_name=$(basename "$dir_path")
  for excl in $EXCLUDED_DIRS; do
    if [ "$dir_name" = "$excl" ]; then
      return 0
    fi
  done
  return 1
}

# --- Check if a path component contains an excluded dir ---
path_contains_excluded() {
  local dir_path="$1"
  local IFS='/'
  for component in $dir_path; do
    [ -z "$component" ] && continue
    for excl in $EXCLUDED_DIRS; do
      if [ "$component" = "$excl" ]; then
        return 0
      fi
    done
  done
  return 1
}

# --- Collect results ---
RESULTS=""

scan_dir() {
  local dir="$1"

  # Skip excluded directories
  if is_excluded "$dir"; then
    return
  fi

  # Also check if any path component is excluded
  if path_contains_excluded "$dir"; then
    return
  fi

  [ -d "$dir" ] || return

  for fname in $DIRECTIVE_FILES; do
    if [ -f "$dir/$fname" ]; then
      local abs_path
      # Get real absolute path
      abs_path=$(cd "$dir" 2>/dev/null && pwd)/"$fname"
      RESULTS="${RESULTS}${RESULTS:+$'\n'}${abs_path}"
    fi
  done
}

# Scan the target directory
scan_dir "$TARGET_DIR"

# Walk up to ancestors if requested
if [ "$WALK_UP" = true ]; then
  BOUNDARY="$PWD"
  CURRENT="$TARGET_DIR"

  while true; do
    # Move to parent
    PARENT=$(dirname "$CURRENT")

    # Stop if we've reached the boundary or can't go higher
    if [ "$PARENT" = "$CURRENT" ]; then
      break
    fi

    # Check if parent is still within (or equal to) the boundary
    # The parent must start with the boundary path (or equal it)
    case "$PARENT" in
      "$BOUNDARY"|"$BOUNDARY"/*)
        scan_dir "$PARENT"
        CURRENT="$PARENT"
        ;;
      *)
        break
        ;;
    esac
  done
fi

# --- Output deduplicated results ---
if [ -z "$RESULTS" ]; then
  exit 1
fi

echo "$RESULTS" | sort -u
exit 0
