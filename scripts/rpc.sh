#!/bin/bash
set -euo pipefail

# ~/.claude/scripts/rpc.sh — Unified RPC CLI for all daemon namespaces (db.*, fs.*, agent.*)
#
# Usage: engine rpc <cmd> [json-args]
#
# Examples:
#   engine rpc agent.skills.list '{}'
#   engine rpc fs.paths.resolve '{"paths": ["~/Projects"]}'
#   engine rpc fs.files.read '{"path": "/tmp/test.txt"}'

TOOL_DIR="$(cd "$HOME/.claude/engine/tools/shared" && pwd)"

exec npx --prefix "$HOME/.claude/engine/tools" tsx "$TOOL_DIR/src/rpc-cli.ts" "$@"
