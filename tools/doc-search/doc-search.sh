#!/usr/bin/env bash
# doc-search — semantic search over project documentation
# Wrapper script for easy invocation
set -euo pipefail

# Resolve symlinks to get the real tool directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
TOOL_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

# --- Local embeddings readiness (tools/embed-local) ---------------------------------
# The search CLIs embed through tools/embed-local (Ollama embeddinggemma, 768-d), with
# NO remote fallback, so the gate is "a runner answers and has the model", not a key.
# One gate, shared by all four search wrappers; when it cannot be found the CLI still
# reports the same named failure (RUNNER_ABSENT / MODEL_ABSENT) itself.
for _el_gate in "$TOOL_DIR/../embed-local/embed-local-gate.sh" \
                "$HOME/.claude/engine/tools/embed-local/embed-local-gate.sh"; do
  [ -f "$_el_gate" ] || continue
  # shellcheck source=/dev/null
  . "$_el_gate"
  embed_local_gate || exit 1
  break
done

# Keep the working DB on local disk rather than the Drive-backed sessions/ dir.
# Best-effort by design: a search that falls back to the legacy path is slow, but
# a wrapper that aborts leaves the caller with NO search — and both consumers in
# session.sh discard our stderr, so the failure would be invisible.
for _sdb_lib in "${ENGINE_SCRIPTS:-}/search-db-lib.sh" "${_gem_d:-}/search-db-lib.sh" \
                "$TOOL_DIR/../../scripts/search-db-lib.sh" \
                "$HOME/.claude/engine/scripts/search-db-lib.sh"; do
  [ -f "$_sdb_lib" ] || continue
  # shellcheck source=/dev/null
  . "$_sdb_lib"
  search_db_export_path doc "$@" || true
  break
done

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
