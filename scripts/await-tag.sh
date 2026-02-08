#!/bin/bash
# ~/.claude/scripts/await-tag.sh — Block until a tag appears on a file or in a directory (via fswatch)
#
# Usage:
#   await-tag.sh <file> '<tag>'             # File mode: watch one file for a tag
#   await-tag.sh --dir <path> '<tag>'       # Dir mode: watch all files under path for a tag
#
# Blocks until the target tag is detected, then outputs the match and exits.
# Fires an OS notification (macOS) on detection.
#
# The tag is checked on the **Tags**: line AND inline (backtick-escaped references filtered out),
# matching the two-pass logic of tag.sh find.
#
# Related:
#   Docs: (~/.claude/docs/)
#     DAEMON.md — Async work coordination
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_AWAIT_TAG — Primary usage pattern
#
# Exit codes:
#   0 — Tag detected
#   1 — Error (missing args, file not found)
#   2 — fswatch not installed
#
# Examples:
#   await-tag.sh sessions/.../DELEGATION_REQUEST_AUTH.md '#done-delegation'
#   await-tag.sh --dir sessions/ '#done-research'
#   await-tag.sh --dir sessions/ '#needs-implementation'

set -euo pipefail

# ---- Dependency check ----
if ! command -v fswatch &>/dev/null; then
  echo "ERROR: fswatch is required but not installed." >&2
  echo "Install with: brew install fswatch" >&2
  exit 2
fi

# ---- Parse args ----
DIR_MODE=0
TARGET=""
TAG=""

if [[ "${1:-}" == "--dir" ]]; then
  DIR_MODE=1
  TARGET="${2:?Usage: await-tag.sh --dir <path> '<tag>'}"
  TAG="${3:?Usage: await-tag.sh --dir <path> '<tag>'}"
else
  TARGET="${1:?Usage: await-tag.sh <file> '<tag>'}"
  TAG="${2:?Usage: await-tag.sh <file> '<tag>'}"
fi

# Validate target exists
if [[ $DIR_MODE -eq 1 ]]; then
  if [[ ! -d "$TARGET" ]]; then
    echo "ERROR: Directory not found: $TARGET" >&2
    exit 1
  fi
else
  if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: File not found: $TARGET" >&2
    exit 1
  fi
fi

# ---- Tag detection (two-pass, matches tag.sh find logic) ----
check_file_for_tag() {
  local file="$1"
  local tag="$2"
  # Pass 1: Tags-line
  if grep -q "^\*\*Tags\*\*:.*${tag}" "$file" 2>/dev/null; then
    return 0
  fi
  # Pass 2: Inline (bare tag, not backtick-escaped)
  if grep -v '^\*\*Tags\*\*:' "$file" 2>/dev/null | grep -v "\`${tag}\`" | grep -q "${tag}"; then
    return 0
  fi
  return 1
}

extract_title() {
  head -1 "$1" 2>/dev/null | sed 's/^# //'
}

notify_and_exit() {
  local file="$1"
  local tag="$2"
  local title
  title=$(extract_title "$file")

  # stdout for the agent
  echo "file: $file"
  echo "tag: $tag"
  echo "title: $title"

  # OS notification (macOS)
  if command -v osascript &>/dev/null; then
    osascript -e "display notification \"$title\" with title \"Tag resolved: $tag\" sound name \"Glass\"" 2>/dev/null || true
  fi

  exit 0
}

# ---- Race guard: check if tag already present ----
if [[ $DIR_MODE -eq 0 ]]; then
  # File mode: check the single file
  if check_file_for_tag "$TARGET" "$TAG"; then
    echo "Already resolved (tag present before watch started)."
    notify_and_exit "$TARGET" "$TAG"
  fi
else
  # Dir mode: scan all .md files
  while IFS= read -r -d '' file; do
    if check_file_for_tag "$file" "$TAG"; then
      echo "Already resolved (tag present before watch started)."
      notify_and_exit "$file" "$TAG"
    fi
  done < <(find "$TARGET" -name '*.md' -print0 2>/dev/null)
fi

# ---- Watch loop ----
if [[ $DIR_MODE -eq 0 ]]; then
  # File mode: watch a single file
  fswatch --event Updated "$TARGET" | while read -r _; do
    if check_file_for_tag "$TARGET" "$TAG"; then
      notify_and_exit "$TARGET" "$TAG"
    fi
  done
else
  # Dir mode: watch all files under path
  fswatch --event Updated --recursive "$TARGET" | while read -r changed_file; do
    # Only check .md files
    [[ "$changed_file" == *.md ]] || continue
    if check_file_for_tag "$changed_file" "$TAG"; then
      notify_and_exit "$changed_file" "$TAG"
    fi
  done
fi
