#!/bin/bash
# ~/.claude/engine/scripts/await-next.sh — Dual-channel fleet blocking primitive (delegator)
#
# Delegates to project-local tools/await-next/ TS tool.
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
if [[ -n "$PROJECT_ROOT" ]] && [[ -x "$PROJECT_ROOT/tools/await-next/await-next.sh" ]]; then
  exec "$PROJECT_ROOT/tools/await-next/await-next.sh" "$@"
fi

# Engine fallback, mirroring tag.sh. The root walk above terminates at $HOME for
# any cwd outside a project that carries its own .claude/, because $HOME/.claude
# always exists — so a project-local install is not reliably reachable and the
# engine copy is the one that always is.
ENGINE_TOOL="$(cd "$SCRIPT_DIR/.." && pwd)/tools/await-next/await-next.sh"
if [[ -x "$ENGINE_TOOL" ]]; then
  exec "$ENGINE_TOOL" "$@"
fi

echo "ERROR: await-next tool not found. Install tools/await-next/ in your project." >&2
exit 1
