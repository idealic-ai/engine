#!/usr/bin/env bash
# session-search — semantic search over session history
# Usage: session-search.sh index [path]
#        session-search.sh query "text" [--tags X] [--after YYYY-MM-DD] [--before YYYY-MM-DD] [--file GLOB]
set -euo pipefail

# Load GEMINI_API_KEY from project .env if not already set
if [ -z "${GEMINI_API_KEY:-}" ] && [ -f ".env" ]; then
  GEMINI_API_KEY=$(grep -E '^GEMINI_API_KEY=' .env | cut -d'=' -f2- | tr -d '"' || true)
fi
export GEMINI_API_KEY="${GEMINI_API_KEY:-AIzaSyDjT2ZF-1hkkv5W0ALQNaVTVmKYSrDPod0}"

# Resolve symlinks to get the real tool directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
TOOL_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
