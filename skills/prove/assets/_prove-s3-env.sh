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
# ONE shared bootstrap (scripts/env-boot.sh) rather than a private chain-walk — the walk
# itself now lives there, so a symlinked source still finds the library. `engine doctor`
# gates this as EB-01.
for _prove_boot in "${ENGINE_SCRIPTS:-}/env-boot.sh" "$HOME/.claude/engine/scripts/env-boot.sh" \
                   "$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/../../../scripts/env-boot.sh"; do
  [ -f "$_prove_boot" ] || continue
  # shellcheck source=/dev/null
  . "$_prove_boot"
  break
done
if ! type env_load_domain >/dev/null 2>&1; then
  echo "_prove-s3-env: cannot find the engine resolver via env-boot.sh" >&2
  return 1
fi
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
# ONE source of AWS identity. PROVE_S3_PROFILE is an explicit override; with it unset the
# profile is the one the doctor provisioned (FINCH_AGENT_AWS_PROFILE) — the same per-person
# agent credential everything else uses, attributable and revocable per person and carrying
# no login_session to expire. Two ways to name an identity was the duplication, and the
# hand-set one had been seeded to an SSO profile that lapsed daily, so publishing broke
# every morning while a perfectly good credential sat unused.
#
# Both branches are `if`s and this stays the LAST statement in the file: every sourcing
# script runs `set -e`, and `.` returns the status of its last command, so a false `&&`
# here would kill the caller at its source line having printed nothing. Naming no profile
# is a supported config (instance credentials), not an edge case.
_prove_profile="${PROVE_S3_PROFILE:-}"
if [ -z "$_prove_profile" ]; then
  _prove_profile="$(resolve_env_key FINCH_AGENT_AWS_PROFILE 2>/dev/null || true)"
fi
if [ -n "$_prove_profile" ]; then
  PROFILE_ARG=(--profile "$_prove_profile")
fi
