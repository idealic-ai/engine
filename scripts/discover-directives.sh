#!/bin/bash
# discover-directives.sh — Discover directive markdown files in a directory (and ancestors)
#
# Usage: discover-directives.sh <target-dir> [--walk-up] [--type soft|hard|all] [--root <path>] [--include-shared]
#
# Directive types:
#   soft: AGENTS.md, INVARIANTS.md, TESTING.md, PITFALLS.md, TEMPLATE.md, CHECKLIST.md
#   hard: (none)
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

# Source shared utilities (provides STANDARD_EXCLUDED_DIRS, is_excluded_dir, is_path_excluded)
source "$HOME/.claude/scripts/lib.sh"

# --- Parse arguments ---
TARGET_DIR=""
WALK_UP=false
TYPE="all"
ROOT_DIR=""

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
    --root)
      ROOT_DIR="${2:-}"
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

# --- Directive file lists ---
SOFT_FILES="AGENTS.md INVARIANTS.md ARCHITECTURE.md COMMANDS.md TESTING.md PITFALLS.md CONTRIBUTING.md TEMPLATE.md CHECKLIST.md"
HARD_FILES=""

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

# --- Collect results ---
RESULTS=""

scan_dir() {
  local dir="$1"

  # Skip excluded directories (uses shared functions from lib.sh)
  if is_excluded_dir "$dir"; then
    return
  fi

  # Also check if any path component is excluded
  if is_path_excluded "$dir"; then
    return
  fi

  [ -d "$dir" ] || return

  local abs_dir
  abs_dir=$(cd "$dir" 2>/dev/null && pwd) || return

  for fname in $DIRECTIVE_FILES; do
    # Check .directives/ subfolder first (preferred location)
    if [ -f "$dir/.directives/$fname" ]; then
      RESULTS="${RESULTS}${RESULTS:+$'\n'}${abs_dir}/.directives/${fname}"
    # Fall back to flat directory root (legacy compat)
    elif [ -f "$dir/$fname" ]; then
      RESULTS="${RESULTS}${RESULTS:+$'\n'}${abs_dir}/${fname}"
    fi
  done
}

# Scan the target directory
scan_dir "$TARGET_DIR"

# Walk up to ancestors if requested
if [ "$WALK_UP" = true ]; then
  BOUNDARY="$PWD"
  if [ -n "${ROOT_DIR:-}" ]; then
    # Use --root as boundary when target is under --root (cross-tree case).
    # PWD is only relevant when the target is under PWD.
    case "$TARGET_DIR" in
      "$ROOT_DIR"|"$ROOT_DIR"/*)
        BOUNDARY="$ROOT_DIR"
        ;;
    esac
  fi
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
