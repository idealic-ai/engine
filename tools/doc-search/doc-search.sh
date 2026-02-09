#!/usr/bin/env bash
# doc-search — semantic search over project documentation
# Wrapper script for easy invocation
set -euo pipefail

# Load GEMINI_API_KEY from project .env if not already set
if [ -z "${GEMINI_API_KEY:-}" ] && [ -f ".env" ]; then
  GEMINI_API_KEY=$(grep -E '^GEMINI_API_KEY=' .env | cut -d'=' -f2- | tr -d '"' || true)
fi
if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "ERROR: GEMINI_API_KEY not set. Add it to .env or export it." >&2
  exit 1
fi

# Resolve symlinks to get the real tool directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
TOOL_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
