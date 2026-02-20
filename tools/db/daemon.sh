#!/usr/bin/env bash
# engine daemon — manage the SQLite engine daemon
# Usage: engine daemon start|stop|status

set -euo pipefail

# Resolve symlinks to find the tool directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
TOOL_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" daemon "$@"
