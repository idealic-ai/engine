#!/usr/bin/env bash
# json-schema-validate — validates JSON instance against JSON Schema
# Usage: validate.sh <schema-file> <instance-file>
#        validate.sh --schema-stdin <instance-file>   (schema piped on stdin)
# Exit 0 = valid, Exit 1 = invalid (errors on stderr), Exit 2 = usage error
set -euo pipefail

# Resolve symlinks to get the real tool directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
TOOL_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

# Check node_modules exist
if [ ! -d "$TOOL_DIR/node_modules" ]; then
  echo "ERROR: node_modules not found. Run: npm install --prefix $TOOL_DIR" >&2
  exit 2
fi

exec node "$TOOL_DIR/validate.js" "$@"
