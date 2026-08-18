# Sourced by the /prove S3 helpers. Loads the `prove` credential domain
# (skills/prove/assets/credentials.json) through the engine's ONE resolver, then builds
# PROFILE_ARG. No output on success.
#
# There is deliberately NO `KEY=` parser here any more. The seven PROVE_S3_* rows and
# their four defaults are declared in the manifest; env_load_domain resolves them the
# same way every other engine credential resolves — real env var, then the current
# session's anchored .env.local, then its .env.
# ONE-LINE IMPORT when the engine dispatcher ran (it exports ENGINE_SCRIPTS). The
# chain-walk below is the FALLBACK for a direct source — which is how the test suites
# reach this file — and for a bogus ENGINE_SCRIPTS, so a stale export degrades rather
# than breaking resolution outright.
_prove_env_lib=""
[ -n "${ENGINE_SCRIPTS:-}" ] && [ -f "$ENGINE_SCRIPTS/env-lib.sh" ] && _prove_env_lib="$ENGINE_SCRIPTS/env-lib.sh"
if [ -z "$_prove_env_lib" ]; then
  _prove_env_src="${BASH_SOURCE[0]:-$0}"
  while [ -L "$_prove_env_src" ]; do
    _prove_env_dir="$(cd -P "$(dirname "$_prove_env_src")" && pwd)"
    _prove_env_src="$(readlink "$_prove_env_src")"
    case "$_prove_env_src" in /*) ;; *) _prove_env_src="$_prove_env_dir/$_prove_env_src" ;; esac
  done
  _prove_env_dir="$(cd -P "$(dirname "$_prove_env_src")" && pwd)"
  [ -f "$_prove_env_dir/../../../scripts/env-lib.sh" ] && _prove_env_lib="$_prove_env_dir/../../../scripts/env-lib.sh"
fi
if [ -z "$_prove_env_lib" ]; then
  echo "_prove-s3-env: cannot find the engine resolver (env-lib.sh) via \$ENGINE_SCRIPTS or a sibling walk" >&2
  return 1
fi
# shellcheck source=/dev/null
. "$_prove_env_lib"
# PROVE_S3_ENV pins ONE authoritative env file (the /prove tests use it to guarantee the
# operator's real bucket and profile cannot leak into a publish under test). Same rule as
# slack-post's --env-file: explicit means only-that-file, never a fallthrough.
if [ -n "${PROVE_S3_ENV:-}" ]; then
  env_load_domain prove --env-file "$PROVE_S3_ENV" || return 1
else
  env_load_domain prove || return 1
fi
PROFILE_ARG=()
# An `if`, not `[ … ] && …`, and specifically because this is the LAST line of the file. Every
# sourcing script runs `set -e`, and `.` returns the status of the last command it ran — so the
# false branch of an && list here makes the SOURCE fail, and the sourcing script dies at its
# `. _prove-s3-env.sh` line having printed nothing at all. PROVE_S3_PROFILE is optional (a config
# on instance credentials sets none), so that false branch is a supported config, not an edge case.
if [ -n "${PROVE_S3_PROFILE:-}" ]; then
  PROFILE_ARG=(--profile "$PROVE_S3_PROFILE")
fi
