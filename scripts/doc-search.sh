#!/usr/bin/env bash
# doc-search — wrapper script for doc-search CLI
# Resolves tool directory via symlinks (works in both local and remote mode)
set -euo pipefail

export GEMINI_API_KEY="${GEMINI_API_KEY:-AIzaSyDjT2ZF-1hkkv5W0ALQNaVTVmKYSrDPod0}"

# Resolve the real tool directory (follows ~/.claude/tools -> engine/tools symlink)
TOOL_DIR="$(cd "$HOME/.claude/tools/doc-search" && pwd)"

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
