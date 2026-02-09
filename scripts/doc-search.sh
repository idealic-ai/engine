#!/usr/bin/env bash
# doc-search — wrapper script for doc-search CLI
# Resolves tool directory via symlinks (works in both local and remote mode)
set -euo pipefail

# Load GEMINI_API_KEY from project .env if not already set
if [ -z "${GEMINI_API_KEY:-}" ] && [ -f ".env" ]; then
  GEMINI_API_KEY=$(grep -E '^GEMINI_API_KEY=' .env | cut -d'=' -f2- | tr -d '"' || true)
  export GEMINI_API_KEY
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "ERROR: GEMINI_API_KEY not set. Add it to .env or export it." >&2
  exit 1
fi

# Resolve the real tool directory (follows ~/.claude/tools -> engine/tools symlink)
TOOL_DIR="$(cd "$HOME/.claude/tools/doc-search" && pwd)"

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
