#!/usr/bin/env bash
# Publish a self-contained /prove HTML to S3 and print its public URL (stdout ONLY).
#
# Usage:  publish-s3.sh <proofPath> [<slug>]
#
# Config resolution (first wins):
#   1. real environment variables (PROVE_S3_*)
#   2. the nearest project .env (walk up from $PWD; override the path with PROVE_S3_ENV)
#   3. otherwise: poke the user (never guesses a bucket)
#
# Keys:
#   PROVE_S3_BUCKET   (required) target bucket, e.g. staging-finch-proofs
#   PROVE_S3_REGION   (default us-east-2) region for the virtual-hosted URL
#   PROVE_S3_PREFIX   (default proofs)    key prefix; MUST match the bucket's public-read policy prefix
#   PROVE_S3_PROFILE  (optional) AWS CLI profile, e.g. finch-staging
#   PROVE_S3_USER     (optional) per-user key segment; else derived from the AWS caller identity
#
# Contract: the composed proof lands at
#   s3://$PROVE_S3_BUCKET/$PROVE_S3_PREFIX/<user>/<slug>-<rand8>.html
# and is served at
#   https://$PROVE_S3_BUCKET.s3.$PROVE_S3_REGION.amazonaws.com/<same key>
# The random suffix makes the key unguessable — an unlisted, shareable link.
set -euo pipefail

proofPath="${1:?usage: publish-s3.sh <proofPath> [slug]}"
[ -f "$proofPath" ] || { echo "publish-s3: file not found: $proofPath" >&2; exit 1; }
slug="${2:-$(basename "$proofPath" .html)}"

# --- Resolve config from the nearest project .env (real env vars still win) ---
find_env() {
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
envfile="$(find_env || true)"
if [ -n "${envfile:-}" ]; then
  envget() { grep -E "^${1}=" "$envfile" 2>/dev/null | tail -1 | cut -d= -f2- \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//'; }
  : "${PROVE_S3_BUCKET:=$(envget PROVE_S3_BUCKET)}"
  : "${PROVE_S3_REGION:=$(envget PROVE_S3_REGION)}"
  : "${PROVE_S3_PREFIX:=$(envget PROVE_S3_PREFIX)}"
  : "${PROVE_S3_PROFILE:=$(envget PROVE_S3_PROFILE)}"
  : "${PROVE_S3_USER:=$(envget PROVE_S3_USER)}"
fi

if [ -z "${PROVE_S3_BUCKET:-}" ]; then
  echo "publish-s3: PROVE_S3_BUCKET is not set (and none found in a project .env)." >&2
  echo "  Prescribe it once in your project's .env (finch → repo-root .env):" >&2
  echo "    PROVE_S3_BUCKET=staging-finch-proofs" >&2
  echo "    PROVE_S3_REGION=us-east-2" >&2
  echo "    PROVE_S3_PROFILE=finch-staging" >&2
  echo "  (or export them in your shell). The proof is still composed in builds/." >&2
  exit 2
fi

region="${PROVE_S3_REGION:-us-east-2}"
prefix="${PROVE_S3_PREFIX:-proofs}"

profile_arg=()
[ -n "${PROVE_S3_PROFILE:-}" ] && profile_arg=(--profile "$PROVE_S3_PROFILE")

# Per-user key segment: explicit override, else the last segment of the caller ARN
# (arn:aws:iam::…:user/yarik -> yarik ; assumed-role/…/<session> -> <session>), else "shared".
user="${PROVE_S3_USER:-}"
if [ -z "$user" ]; then
  arn="$(aws sts get-caller-identity "${profile_arg[@]}" --query Arn --output text 2>/dev/null || true)"
  user="${arn##*/}"
  [ -z "$user" ] || [ "$user" = "None" ] && user="shared"
fi
# sanitize to a safe key segment
user="$(printf '%s' "$user" | tr -c 'A-Za-z0-9._-' '-')"

rand="$(openssl rand -hex 4)"
key="${prefix}/${user}/${slug}-${rand}.html"

# --- Resolve the shared widget kit reference, if this page uses one ---
# A board references the kit as __FB_KIT_BASE__/board-widgets.v<N>.js rather than inlining it,
# so a published board can receive fixes. Publish time is the only moment bucket, region and
# prefix are all known, so substitution happens here rather than being guessed by the author.
# Pages with no token (an ordinary /prove proof) are untouched.
upload="$proofPath"
if grep -q '__FB_KIT_BASE__' "$proofPath"; then
  kitBase="https://${PROVE_S3_BUCKET}.s3.${region}.amazonaws.com/${prefix}/kit"
  upload="$(mktemp -t fb-board)"
  # Substitute into a COPY — the composed board in builds/ stays as authored, so a re-publish
  # to a different bucket resolves afresh instead of inheriting the first one's URL.
  sed "s|__FB_KIT_BASE__|${kitBase}|g" "$proofPath" > "$upload"
  trap 'rm -f "$upload"' EXIT
  echo "publish-s3: kit reference resolved → ${kitBase}" >&2
fi

# Upload. cp chatter → stderr; only the URL goes to stdout.
aws s3 cp "$upload" "s3://${PROVE_S3_BUCKET}/${key}" \
  "${profile_arg[@]}" \
  --content-type 'text/html; charset=utf-8' \
  --cache-control 'no-cache' >&2

printf 'https://%s.s3.%s.amazonaws.com/%s\n' "$PROVE_S3_BUCKET" "$region" "$key"
