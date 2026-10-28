# Sourced by the /prove S3 helpers. Loads the `prove` credential domain
# (skills/prove/assets/credentials.json) through the engine's ONE resolver, then builds
# PROFILE_ARG, ENDPOINT_ARG and PROVE_S3_LOCAL. No output on success.
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
#
# WHICH FILE DECLARES THE ENDPOINT IS RESOLVED *BEFORE* THE LOAD, not after. env_key_source
# answers the literal string `environment` for any key that is already set, and the load below sets
# it — so a question asked afterwards can only ever answer `environment`, which prove_declared_
# endpoint reads as "no file declared one" and the destination gate then compares nothing. That
# made the gate silently vacuous on exactly the path an operator runs: a file naming one store, an
# ambient variable naming another, and a publish that stated a port without ever checking it.
PROVE_S3_DECLARED_SRC=""
if [ -n "${PROVE_S3_ENV:-}" ]; then
  PROVE_S3_DECLARED_SRC="$PROVE_S3_ENV"
elif type env_key_source >/dev/null 2>&1; then
  PROVE_S3_DECLARED_SRC="$(env_key_source PROVE_S3_ENDPOINT 2>/dev/null)" || PROVE_S3_DECLARED_SRC=""
  if [ "$PROVE_S3_DECLARED_SRC" = environment ]; then PROVE_S3_DECLARED_SRC=""; fi
fi
if [ -n "${PROVE_S3_ENV:-}" ]; then
  env_load_domain prove --env-file "$PROVE_S3_ENV" || return 1
else
  env_load_domain prove || return 1
fi
# Derived publish context, shared by every /prove S3 helper:
#   PROVE_S3_ENDPOINT_URL / PROVE_S3_PUBLIC_URL  the endpoint and URL base, empty for AWS S3
#   PROVE_S3_LOCAL  1 when the endpoint is a loopback URL (the local MinIO started with the kit)
#   ENDPOINT_ARG    (--endpoint-url <endpoint>) when an endpoint is set, else empty
#   PROFILE_ARG     (--profile <PROVE_S3_PROFILE>) when a profile is named, else empty
# A loopback endpoint has no AWS identity behind it: credentials come from
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, falling back to the kit's KIT_PROOFS_MINIO_USER /
# KIT_PROOFS_MINIO_PASSWORD when neither is set (nothing is invented), and the per-user
# key segment defaults to the login name because there is no STS caller to ask.
# Every branch below is an `if` and the file ends on one: sourcing scripts run `set -e`, and a
# false `&&` as the last command would kill the caller at its source line.
# An empty dotfile value does not shadow a manifest default, so AWS S3 is chosen by naming it:
# PROVE_S3_ENDPOINT=aws (or none). The raw keys keep that sentinel so a child script resolves the
# same answer; consumers read the derived PROVE_S3_ENDPOINT_URL / PROVE_S3_PUBLIC_URL instead.
PROVE_S3_ENDPOINT_URL="${PROVE_S3_ENDPOINT:-}"
PROVE_S3_PUBLIC_URL="${PROVE_S3_PUBLIC_BASE:-$PROVE_S3_ENDPOINT_URL}"
case "$PROVE_S3_ENDPOINT_URL" in
  aws|AWS|none|NONE) PROVE_S3_ENDPOINT_URL=""; PROVE_S3_PUBLIC_URL="" ;;
esac
PROVE_S3_LOCAL=0
case "$PROVE_S3_ENDPOINT_URL" in
  http://127.0.0.1|http://127.0.0.1:*|http://127.0.0.1/*|http://localhost|http://localhost:*|http://localhost/*|\
  https://127.0.0.1|https://127.0.0.1:*|https://127.0.0.1/*|https://localhost|https://localhost:*|https://localhost/*)
    PROVE_S3_LOCAL=1 ;;
esac
ENDPOINT_ARG=()
if [ -n "$PROVE_S3_ENDPOINT_URL" ]; then
  ENDPOINT_ARG=(--endpoint-url "$PROVE_S3_ENDPOINT_URL")
fi
if [ "$PROVE_S3_LOCAL" = 1 ]; then
  # The local MinIO's login is whatever the kit started it with: app/proofs/compose.yml reads
  # KIT_PROOFS_MINIO_USER / KIT_PROOFS_MINIO_PASSWORD (overridden in the kit's app/.env). Use that
  # pair only when BOTH are set and no AWS key pair is. NO pair is ever assumed here: with nothing
  # set and no profile, the keys stay unset and the upload fails, after the line below names the fix.
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_SECRET_ACCESS_KEY:-}" ] \
     && [ -n "${KIT_PROOFS_MINIO_USER:-}" ] && [ -n "${KIT_PROOFS_MINIO_PASSWORD:-}" ]; then
    export AWS_ACCESS_KEY_ID="$KIT_PROOFS_MINIO_USER"
    export AWS_SECRET_ACCESS_KEY="$KIT_PROOFS_MINIO_PASSWORD"
  fi
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${PROVE_S3_PROFILE:-}" ] && [ -z "${AWS_PROFILE:-}" ]; then
    echo "_prove-s3-env: no credentials for the local store at $PROVE_S3_ENDPOINT_URL — set KIT_PROOFS_MINIO_USER and KIT_PROOFS_MINIO_PASSWORD to the login the kit's app/proofs/compose.yml started MinIO with (see ~/Projects/kit/app/proofs/README.md § Credentials), or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY, or PROVE_S3_PROFILE=<a profile holding that login>. No login is assumed." >&2
  fi
  export AWS_REGION="${AWS_REGION:-${PROVE_S3_REGION:-us-east-1}}"
  if [ -z "${PROVE_S3_USER:-}" ]; then
    PROVE_S3_USER="$(id -un 2>/dev/null || printf local)"
  fi
fi
PROFILE_ARG=()
if [ -n "${PROVE_S3_PROFILE:-}" ]; then
  PROFILE_ARG=(--profile "$PROVE_S3_PROFILE")
fi

# --- Where the shared-state objects live: ONE answer, for all three scripts ---------------------
# The state doc is NESTED UNDER THE PUBLISH PREFIX (proofs/state/<doc>.json), so the object is
# covered by the same anonymous-read grant that already serves the page. A board that can be read
# can read its own state, with no second policy statement to keep in step — and the stores diverge
# on exactly that statement: the kit's MinIO grants GetObject on `<bucket>/proofs*` only, so a
# sibling top-level `state/<doc>.json` is a 403 to every reader while `proofs/state/<doc>.json` is
# served. A key already inside the prefix is left alone, so an operator who sets
# PROVE_S3_STATE_PREFIX=proofs/state gets the same answer rather than proofs/proofs/state.
#
# The EVENTS prefix stays OUTSIDE the public prefix on purpose: an event carries the voter's name
# and is owner-read-only by design. Nest it and every reader could enumerate who answered what.
prove_state_key() {
  local sp="${PROVE_S3_STATE_PREFIX:-state}" pp="${PROVE_S3_PREFIX:-proofs}"
  case "$sp" in
    "$pp"|"$pp"/*) printf '%s/%s.json' "${sp%/}" "$1" ;;
    *)             printf '%s/%s/%s.json' "${pp%/}" "${sp%/}" "$1" ;;
  esac
}
prove_events_key_prefix() {
  printf '%s/%s/' "${PROVE_S3_EVENTS_PREFIX:-events}" "$1"
}

# --- WHICH STORE: the port, never the bucket ----------------------------------------------------
#
# More than one local store answers the SAME bucket name at the SAME prefix, so a publish aimed at
# the wrong one succeeds, exits 0 and returns a URL that serves somebody else's store. Everything
# the publisher used to print or assert as an identity was bucket+prefix, which is identical on
# both. The endpoint's PORT is the only thing that differs, so the port is the identity.

# prove_endpoint_id [ENDPOINT] -> a comparable destination identity on stdout.
# `aws-s3` for the AWS sentinels and for no endpoint at all; otherwise scheme://host:port with the
# scheme's default port made explicit, so `http://h` and `http://h:80` do not read as two stores.
prove_endpoint_id() {
  local u="${1:-}" scheme rest host port
  case "$u" in ''|aws|AWS|none|NONE) printf 'aws-s3'; return 0 ;; esac
  u="${u%/}"
  case "$u" in
    http://*)  scheme=http;  rest="${u#http://}" ;;
    https://*) scheme=https; rest="${u#https://}" ;;
    *)         printf '%s' "$u"; return 0 ;;   # not a URL we can normalise; compare verbatim
  esac
  rest="${rest%%/*}"
  case "$rest" in
    *:*) host="${rest%:*}"; port="${rest##*:}" ;;
    *)   host="$rest";      port="" ;;
  esac
  if [ -z "$port" ]; then
    [ "$scheme" = https ] && port=443 || port=80
  fi
  printf '%s://%s:%s' "$scheme" "$host" "$port"
}

# prove_declared_endpoint -> the endpoint the env FILE declares, plus the file, as "FILE<TAB>VALUE".
# Read from the FILE rather than the environment because an ambient override shadowing the file IS
# the failure: the file named one store and something else won, with nothing saying which got the
# bytes. Empty output means no file declared one, and the gate then checks nothing — it verifies a
# declaration, it never invents one.
prove_declared_endpoint() {
  local src="${PROVE_S3_DECLARED_SRC:-}" val=""
  [ -n "$src" ] && [ -f "$src" ] || return 0
  val="$(extract_env_key "$src" PROVE_S3_ENDPOINT 2>/dev/null)" || val=""
  [ -n "$val" ] || return 0
  printf '%s\t%s' "$src" "$val"
}

# prove_destination_gate -> states the destination, refuses a mismatch. Call it BEFORE any byte
# moves. Returns 3 on refusal; the caller exits.
prove_destination_gate() {
  local who="${1:-publish}" resolved declared_pair declared_src declared want got
  resolved="${PROVE_S3_ENDPOINT_URL:-}"
  got="$(prove_endpoint_id "$resolved")"

  declared_pair="$(prove_declared_endpoint)"
  if [ -n "$declared_pair" ]; then
    declared_src="${declared_pair%%	*}"
    declared="${declared_pair#*	}"
    want="$(prove_endpoint_id "$declared")"
    if [ "$want" != "$got" ]; then
      echo "$who: REFUSED — this is not the store $declared_src declares." >&2
      echo "  declared:  $declared  ($want)" >&2
      echo "  resolved:  ${resolved:-AWS S3 (no endpoint)}  ($got)" >&2
      echo "  The bucket matches either way — every local store here answers '${PROVE_S3_BUCKET:-?}'," >&2
      echo "  so the PORT is what says which one. Something in the environment overrode the file." >&2
      echo "  Publish to the declared store, or change the declaration deliberately." >&2
      return 3
    fi
  fi

  printf '%s: destination  endpoint=%s  bucket=%s  prefix=%s\n' \
    "$who" "${resolved:-AWS-S3}" "${PROVE_S3_BUCKET:-?}" "${PROVE_S3_PREFIX:-proofs}" >&2
  if [ "${PROVE_S3_LOCAL:-0}" = 1 ]; then
    printf '%s:   read the PORT (%s) — more than one local store answers bucket %s at this prefix, so a bucket match is not a destination match.\n' \
      "$who" "${got##*:}" "${PROVE_S3_BUCKET:-?}" >&2
  fi
  return 0
}
