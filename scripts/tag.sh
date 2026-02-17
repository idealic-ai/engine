#!/bin/bash
# ~/.claude/engine/scripts/tag.sh — Semantic tag management (delegator)
#
# Delegates to project-local tools/tags/ TS tool if available,
# otherwise falls back to the original bash implementation (tag.sh.bak).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find project root (walk up looking for .claude/ marker)
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.claude" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT=$(find_project_root 2>/dev/null || echo "")

# Check for project-local TS tool
if [[ -n "$PROJECT_ROOT" ]] && [[ -x "$PROJECT_ROOT/tools/tags/tags.sh" ]]; then
  exec "$PROJECT_ROOT/tools/tags/tags.sh" "$@"
fi

# Fallback to original bash implementation
if [[ -x "$SCRIPT_DIR/tag.sh.bak" ]]; then
  exec "$SCRIPT_DIR/tag.sh.bak" "$@"
fi

echo "ERROR: No tag implementation found" >&2
exit 1
