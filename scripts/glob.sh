#!/bin/bash
# ~/.claude/scripts/glob.sh — Symlink-aware file globbing
#
# Drop-in Bash alternative when the Glob tool fails on symlinked paths.
#
# Usage:
#   glob.sh <pattern> [path]
#
# Arguments:
#   pattern — glob pattern (e.g., **/*.ts, *.md, src/**/*.test.ts)
#   path    — optional root directory (defaults to .)
#
# Related:
#   Invariants: (~/.claude/standards/INVARIANTS.md)
#     ¶INV_GLOB_THROUGH_SYMLINKS — Primary use case (Glob tool fallback)
#
# Output: Newline-delimited file paths, relative to path, sorted by
# modification time (newest first) — matching Glob tool behavior.
#
# Pattern translation:
#   **/*.ts          → find -L . -name '*.ts'
#   *.md             → find -L . -maxdepth 1 -name '*.md'
#   src/**/*.test.ts → find -L src/ -name '*.test.ts'
#   **               → find -L . -type f
#
# Examples:
#   glob.sh '**' sessions/2026_02_04_FOO
#   glob.sh '**/*.ts' packages/estimate/src
#   glob.sh '*.md' sessions/2026_02_04_FOO

set -euo pipefail

[[ $# -eq 0 ]] && { echo "Usage: glob.sh <pattern> [path]" >&2; exit 1; }

PATTERN="$1"
ROOT="${2:-.}"
# Keep the original root for output paths (preserves symlink names)
ORIGINAL_ROOT="$ROOT"

# Resolve the root, following symlinks (for find -L to work)
RESOLVED_ROOT="$(cd -P "$ROOT" 2>/dev/null && pwd)" || {
  # Path doesn't exist or isn't accessible — exit cleanly
  exit 0
}

# --- Pattern translation ---
# Split pattern into prefix dir + filename glob
# e.g. "src/**/*.test.ts" → prefix="src", nameglob="*.test.ts"
# e.g. "**/*.ts"          → prefix="",    nameglob="*.ts"
# e.g. "*.md"             → prefix="",    nameglob="*.md",  shallow=true
# e.g. "**"               → prefix="",    nameglob="",      allfiles=true

FIND_ARGS=()
FIND_PATH="$RESOLVED_ROOT"
SHALLOW=false

if [[ "$PATTERN" == "**" ]]; then
  # All files recursively
  FIND_ARGS=(-type f)
elif [[ "$PATTERN" == *"**/"* ]]; then
  # Has ** recursive component — extract prefix and name glob
  prefix="${PATTERN%%\*\*/*}"
  nameglob="${PATTERN##*\*\*/}"

  if [[ -n "$prefix" ]]; then
    # Strip trailing slash from prefix
    prefix="${prefix%/}"
    FIND_PATH="$RESOLVED_ROOT/$prefix"
  fi

  if [[ -n "$nameglob" ]]; then
    FIND_ARGS=(-name "$nameglob")
  else
    FIND_ARGS=(-type f)
  fi
elif [[ "$PATTERN" == *"/"* ]]; then
  # Has a directory component but no ** — treat as literal path + shallow glob
  dir="${PATTERN%/*}"
  nameglob="${PATTERN##*/}"
  FIND_PATH="$RESOLVED_ROOT/$dir"
  FIND_ARGS=(-maxdepth 1 -name "$nameglob")
  SHALLOW=true
else
  # Simple pattern like "*.md" — shallow search in root only
  FIND_ARGS=(-maxdepth 1 -name "$PATTERN")
  SHALLOW=true
fi

# Bail if the search path doesn't exist
[[ -d "$FIND_PATH" ]] || exit 0

# --- Execute find, sort by mtime descending ---
# Use -L to follow symlinks, skip broken ones via -type f
find -L "$FIND_PATH" "${FIND_ARGS[@]}" -type f 2>/dev/null \
  | while IFS= read -r f; do
      # Get mtime epoch + path
      mtime=$(stat -f "%m" "$f" 2>/dev/null) || continue
      echo "$mtime $f"
    done \
  | sort -rn \
  | while IFS=' ' read -r _ filepath; do
      # Strip resolved root, prepend original root (preserves symlink path)
      relpath="${filepath#$RESOLVED_ROOT/}"
      if [[ "$ORIGINAL_ROOT" == "." ]]; then
        echo "$relpath"
      else
        echo "$ORIGINAL_ROOT/$relpath"
      fi
    done
