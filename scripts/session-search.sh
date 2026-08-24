#!/usr/bin/env bash
# session-search — wrapper script for session-search CLI
# Resolves tool directory via symlinks (works in both local and remote mode)
set -euo pipefail

# --- GEMINI_API_KEY via the shared engine resolver ---------------------------------
# ONE rule for every consumer: a real env var, then the current session's project root
# (.env.local, then .env). There is deliberately NO $HOME dotfile in the chain — a
# per-project credential comes from the project, never from a global file that would let
# one project's wave authenticate as another's. (Measured before removal: neither
# ~/.env nor ~/.claude/.env exists here, so that branch was dead code.)
if [ -z "${GEMINI_API_KEY:-}" ]; then
  # ONE bootstrap, shared. This used to be a byte-identical twelve-line symlink chain-walk
  # repeated in six files; it lives in env-boot.sh now and `engine doctor` gates (EB-01)
  # against a seventh appearing.
  for _gem_boot in "${ENGINE_SCRIPTS:-}/env-boot.sh" "$HOME/.claude/engine/scripts/env-boot.sh"; do
    [ -f "$_gem_boot" ] || continue
    # shellcheck source=/dev/null
    . "$_gem_boot"
    GEMINI_API_KEY="$(resolve_env_key GEMINI_API_KEY 2>/dev/null)" || GEMINI_API_KEY=""
    export GEMINI_API_KEY
    break
  done
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "ERROR: GEMINI_API_KEY not set. Add it to .env or export it." >&2
  exit 1
fi

# Resolve the real tool directory (follows ~/.claude/tools -> engine/tools symlink)
TOOL_DIR="$(cd "$HOME/.claude/tools/session-search" && pwd)"

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
  search_db_export_path session "$@" || true
  break
done

exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
