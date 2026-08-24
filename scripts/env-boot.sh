# env-boot.sh — THE ONE way a script reaches the engine's credential resolver.
#
# Sourcing this leaves `env-lib.sh` loaded, so `resolve_env_key` and `env_load_domain`
# are callable. It exists because finding the library was being reinvented: six
# byte-identical symlink chain-walks lived in gemini.sh, research.sh, doc-search.sh,
# session-search.sh and both tools/ wrappers, plus variants elsewhere. One resolver
# reached fifteen different ways is the same defect as several resolvers — it just
# fails later, and it is why `engine doctor` gates this (EB-01).
#
# Callers source it in three lines rather than twelve:
#
#   for _b in "${ENGINE_SCRIPTS:-}/env-boot.sh" "$HOME/.claude/engine/scripts/env-boot.sh"; do
#     [ -f "$_b" ] && { . "$_b"; break; }
#   done
#
# ⚠️ THE CHAIN-WALK BELOW IS THE POINT OF THIS FILE, and must stay here rather than being
# simplified away: a script may be a symlink (the test suites symlink these into a fake
# HOME, and /usr/local/bin/engine is one), so the sibling library is found relative to
# the RESOLVED path, never to the link. ENGINE_SCRIPTS is preferred when the dispatcher
# exported it; the walk is the fallback for a direct source and for a stale export.
_eb_lib=""
if [ -n "${ENGINE_SCRIPTS:-}" ] && [ -f "${ENGINE_SCRIPTS}/env-lib.sh" ]; then
  _eb_lib="${ENGINE_SCRIPTS}/env-lib.sh"
else
  _eb_self="${BASH_SOURCE[0]:-$0}"
  while [ -L "$_eb_self" ]; do
    _eb_d="$(cd -P "$(dirname "$_eb_self")" && pwd)"; _eb_self="$(readlink "$_eb_self")"
    case "$_eb_self" in /*) ;; *) _eb_self="$_eb_d/$_eb_self" ;; esac
  done
  _eb_d="$(cd -P "$(dirname "$_eb_self")" && pwd)"
  for _eb_c in "$_eb_d/env-lib.sh" "$_eb_d/../../scripts/env-lib.sh" \
               "$_eb_d/../../../scripts/env-lib.sh" "$HOME/.claude/engine/scripts/env-lib.sh"; do
    [ -f "$_eb_c" ] && { _eb_lib="$_eb_c"; break; }
  done
fi
if [ -n "$_eb_lib" ]; then
  # shellcheck source=/dev/null
  . "$_eb_lib"
else
  echo "env-boot: cannot find env-lib.sh (tried \$ENGINE_SCRIPTS and a sibling walk)" >&2
fi
unset _eb_self _eb_d _eb_c
