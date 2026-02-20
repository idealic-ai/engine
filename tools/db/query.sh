#!/usr/bin/env bash
# engine query — send SQL to the engine daemon
# Usage: engine query 'SQL' [params...] [--single] [--format=json|tsv|scalar]
# Usage: engine query [params...] [--single] [--format=...] <<'SQL'
#   SELECT * FROM sessions WHERE id = ?
# SQL

set -euo pipefail

# Resolve symlinks to find the tool directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
TOOL_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" query "$@"
