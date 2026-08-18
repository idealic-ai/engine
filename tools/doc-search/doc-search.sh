#!/usr/bin/env bash
# doc-search — semantic search over project documentation
# Wrapper script for easy invocation
set -euo pipefail

# --- GEMINI_API_KEY via the shared engine resolver ---------------------------------
# ONE rule for every consumer: a real env var, then the current session's project root
# (.env.local, then .env). There is deliberately NO $HOME dotfile in the chain — a
# per-project credential comes from the project, never from a global file that would let
# one project's wave authenticate as another's. (Measured before removal: neither
# ~/.env nor ~/.claude/.env exists here, so that branch was dead code.)
if [ -z "${GEMINI_API_KEY:-}" ]; then
  _gem_self="${BASH_SOURCE[0]:-$0}"
  while [ -L "$_gem_self" ]; do
    _gem_d="$(cd -P "$(dirname "$_gem_self")" && pwd)"; _gem_self="$(readlink "$_gem_self")"
    case "$_gem_self" in /*) ;; *) _gem_self="$_gem_d/$_gem_self" ;; esac
  done
  _gem_d="$(cd -P "$(dirname "$_gem_self")" && pwd)"
  for _gem_lib in "${ENGINE_SCRIPTS:-}/env-lib.sh" "$_gem_d/env-lib.sh" \
                  "$_gem_d/../../scripts/env-lib.sh" "$HOME/.claude/engine/scripts/env-lib.sh"; do
    [ -f "$_gem_lib" ] || continue
    # shellcheck source=/dev/null
    . "$_gem_lib"
    GEMINI_API_KEY="$(resolve_env_key GEMINI_API_KEY 2>/dev/null)" || GEMINI_API_KEY=""
    export GEMINI_API_KEY
    break
  done
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
