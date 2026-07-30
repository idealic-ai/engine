# Sourced by the /prove S3 helpers. Resolves PROVE_S3_* config: a real env var wins,
# else the nearest project .env (walk up from $PWD; PROVE_S3_ENV overrides the path).
# Exports the vars (with defaults) and builds PROFILE_ARG. No output on success.
_prove_find_env() {
  if [ -n "${PROVE_S3_ENV:-}" ]; then
    [ -f "$PROVE_S3_ENV" ] && printf '%s' "$PROVE_S3_ENV"
    return
  fi
  local d="$PWD"
  while :; do
    [ -f "$d/.env" ] && { printf '%s' "$d/.env"; return; }
    [ "$d" = "/" ] && return
    d="$(dirname "$d")"
  done
}
_prove_envfile="$(_prove_find_env || true)"
if [ -n "${_prove_envfile:-}" ]; then
  _prove_envget() { grep -E "^${1}=" "$_prove_envfile" 2>/dev/null | tail -1 | cut -d= -f2- \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//'; }
  : "${PROVE_S3_BUCKET:=$(_prove_envget PROVE_S3_BUCKET)}"
  : "${PROVE_S3_REGION:=$(_prove_envget PROVE_S3_REGION)}"
  : "${PROVE_S3_PREFIX:=$(_prove_envget PROVE_S3_PREFIX)}"
  : "${PROVE_S3_STATE_PREFIX:=$(_prove_envget PROVE_S3_STATE_PREFIX)}"
  : "${PROVE_S3_EVENTS_PREFIX:=$(_prove_envget PROVE_S3_EVENTS_PREFIX)}"
  : "${PROVE_S3_PROFILE:=$(_prove_envget PROVE_S3_PROFILE)}"
  : "${PROVE_S3_USER:=$(_prove_envget PROVE_S3_USER)}"
fi
PROVE_S3_REGION="${PROVE_S3_REGION:-us-east-2}"
PROVE_S3_PREFIX="${PROVE_S3_PREFIX:-proofs}"
PROVE_S3_STATE_PREFIX="${PROVE_S3_STATE_PREFIX:-state}"
PROVE_S3_EVENTS_PREFIX="${PROVE_S3_EVENTS_PREFIX:-events}"
PROFILE_ARG=()
[ -n "${PROVE_S3_PROFILE:-}" ] && PROFILE_ARG=(--profile "$PROVE_S3_PROFILE")
