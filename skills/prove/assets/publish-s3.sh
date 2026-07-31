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
# macOS ships bash 3.2, where "${arr[@]}" on an EMPTY array under `set -u` is an "unbound
# variable" fatal — so every array expansion below uses the ${arr[@]+"${arr[@]}"} guard. Without
# it this script dies on any config with no PROVE_S3_PROFILE, which is a supported config.
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
  : "${PROVE_S3_STATE_PREFIX:=$(envget PROVE_S3_STATE_PREFIX)}"
  : "${PROVE_S3_EVENTS_PREFIX:=$(envget PROVE_S3_EVENTS_PREFIX)}"
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
  arn="$(aws sts get-caller-identity ${profile_arg[@]+"${profile_arg[@]}"} --query Arn --output text 2>/dev/null || true)"
  user="${arn##*/}"
  [ -z "$user" ] || [ "$user" = "None" ] && user="shared"
fi
# sanitize to a safe key segment
user="$(printf '%s' "$user" | tr -c 'A-Za-z0-9._-' '-')"

rand="$(openssl rand -hex 4)"
stem="${slug}-${rand}"
key="${prefix}/${user}/${stem}.html"

# --- The working copy: made ONCE, unconditionally, under ONE trap ---
# Every publish-time substitution below edits this copy and never $proofPath. Two reasons, and
# the second is the sharp one:
#   1. The composed board in builds/ stays as authored, so a re-publish to a different bucket
#      resolves afresh instead of inheriting the first publish's URLs.
#   2. The state config carries a LIVE PRESIGNED CREDENTIAL. builds/ lives under sessions/, which
#      is a symlink into a shared Google Drive — writing the credential there would sync it.
# Unconditional and single-trap on purpose: an alias that only becomes a copy inside one branch
# points at the authored source on every other path, and a second `trap … EXIT` REPLACES the
# first (bash does not stack them), silently leaking the earlier temp file.
work="$(mktemp -d -t fb-publish)"
trap 'rm -rf "$work"' EXIT
upload="${work}/board.html"
cp "$proofPath" "$upload"

# Board-ness is decided HERE, before the kit token is substituted away: a board is a page that
# references the shared widget kit, and that is the only durable marker of one. It gates the state
# config below, so an ordinary /prove proof never receives a presigned credential it has no code to
# use — the config's write half is a real grant, not decoration.
isBoard=0
if grep -q '__FB_KIT_BASE__' "$upload"; then isBoard=1; fi

# --- Resolve the shared widget kit reference, if this page uses one ---
# A board references the kit as __FB_KIT_BASE__/board-widgets.v<N>.js rather than inlining it,
# so a published board can receive fixes. Publish time is the only moment bucket, region and
# prefix are all known, so substitution happens here rather than being guessed by the author.
# Pages with no token (an ordinary /prove proof) are untouched.
if grep -q '__FB_KIT_BASE__' "$upload"; then
  kitBase="https://${PROVE_S3_BUCKET}.s3.${region}.amazonaws.com/${prefix}/kit"
  sed "s|__FB_KIT_BASE__|${kitBase}|g" "$upload" > "${work}/kit.html"
  mv "${work}/kit.html" "$upload"
  echo "publish-s3: kit reference resolved → ${kitBase}" >&2
fi

# --- Mint + inject the shared-state config on every board ---
# Publish is the only moment the bucket, the doc id and a signable credential all exist at once,
# so the config is minted here. EVERY board gets one: nothing upstream ever asked for it, so a
# board that depended on being asked was mute by construction — teammates had no way to vote in it
# and a council run had nowhere to seed records. The placeholder is a PLACEMENT hint, not a
# request; a board that carries none gets the element appended. Pages that are not boards (no kit
# reference — an ordinary /prove proof) are untouched: no config, no credential, byte-identical.
#
# THE SIGNER IS NEVER LOAD-BEARING FOR PUBLISHING. `set -e` is on, so every failure path here is
# explicitly caught: a missing signer, unavailable credentials, or a python error all degrade to
# a config that carries the READ url but no write grant. The board then polls (state/* is public
# read) and routes submissions to the copy bar with a stated reason. Publishing a broken board
# because signing broke would be strictly worse than publishing today's board.
if [ "$isBoard" = 1 ] || grep -q '__PROVE_STATE_CONFIG__' "$upload"; then
  statePrefix="${PROVE_S3_STATE_PREFIX:-state}"
  eventsPrefix="${PROVE_S3_EVENTS_PREFIX:-events}"
  # docId inherits the board's own entropy rather than being re-derived from the slug: a
  # predictable state/<slug>.json is a guessable public key AND collides across re-publishes
  # of the same wave, silently merging two boards' votes into one doc.
  docId="$stem"
  stateUrl="https://${PROVE_S3_BUCKET}.s3.${region}.amazonaws.com/${statePrefix}/${docId}.json"
  signer="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sign-post.py"

  signed=""
  signError="signing was not attempted"
  if [ ! -f "$signer" ]; then
    signError="sign-post.py not found beside publish-s3.sh"
  elif ! creds="$(aws configure export-credentials ${profile_arg[@]+"${profile_arg[@]}"} --format env 2>"${work}/cred.err")"; then
    signError="could not export AWS credentials for the presign ($(tr -d '\n' < "${work}/cred.err" | cut -c1-160))"
  elif ! signed="$( set +u; eval "$creds"; \
        PROVE_S3_BUCKET="$PROVE_S3_BUCKET" PROVE_S3_REGION="$region" \
        PROVE_S3_EVENTS_PREFIX="$eventsPrefix" \
        python3 "$signer" "$docId" "${PROVE_S3_STATE_EXPIRY:-604800}" 2>"${work}/sign.err" )"; then
    signed=""
    signError="sign-post.py failed ($(tr -d '\n' < "${work}/sign.err" | cut -c1-160))"
  fi

  printf '%s' "${signed:-}" > "${work}/signed.json"
  STATE_DOC_ID="$docId" STATE_URL="$stateUrl" SIGN_ERROR="$signError" \
    python3 - "$upload" "${work}/signed.json" > "${work}/state.html" <<'PY'
import json, os, re, sys

page = open(sys.argv[1], encoding="utf-8").read()
raw = open(sys.argv[2], encoding="utf-8").read().strip()

cfg = {"docId": os.environ["STATE_DOC_ID"], "stateUrl": os.environ["STATE_URL"], "pollMs": 20000}
try:
    presign = json.loads(raw) if raw else None
except ValueError:
    presign = None
if presign and presign.get("postUrl"):
    cfg["postUrl"] = presign["postUrl"]
    cfg["keyPrefix"] = presign["keyPrefix"]
    cfg["fields"] = presign["fields"]
    cfg["expiresAt"] = presign["expiresAt"]
else:
    # Read-only config. The kit shows the reason on the submit control rather than a dead button.
    cfg["submitDisabledReason"] = os.environ["SIGN_ERROR"]

# json.dumps, not sed: the policy field is base64 and the signature is hex, and sed's replacement
# text gives `&` and `\` their own meanings. `</` is split so the JSON can never close the
# <script> element that carries it.
blob = json.dumps(cfg).replace("</", "<\\/")

# The token stays a literal on both lines: the cross-file contract check greps publish-s3.sh for
# this exact replace() call, because naming a token is not substituting one.
if "__PROVE_STATE_CONFIG__" in page:
    page = page.replace("__PROVE_STATE_CONFIG__", blob)
else:
    # No placeholder: author the element the kit looks for, verbatim as the render spec writes it,
    # so an appended board is indistinguishable from an authored one. Position is not load-bearing
    # — the kit reads the config at DOMContentLoaded, by which point the whole document is parsed.
    el = ('<script id="prove-state-config" data-fb-state-config type="application/json">'
          + blob + "</script>\n")
    ends = list(re.finditer(r"</body\s*>", page, re.I))
    page = (page[:ends[-1].start()] + el + page[ends[-1].start():]) if ends else (page + el)
    sys.stderr.write("publish-s3: the board carried no placeholder — state config element appended\n")

sys.stdout.write(page)
PY
  mv "${work}/state.html" "$upload"
  if [ -n "$signed" ]; then
    echo "publish-s3: state config injected → ${stateUrl} (writes presigned)" >&2
  else
    echo "publish-s3: state config injected READ-ONLY → ${stateUrl}" >&2
    echo "publish-s3: no write grant — ${signError}; the board falls back to copy-back" >&2
  fi
fi

# Upload. cp chatter → stderr; only the URL goes to stdout.
aws s3 cp "$upload" "s3://${PROVE_S3_BUCKET}/${key}" \
  ${profile_arg[@]+"${profile_arg[@]}"} \
  --content-type 'text/html; charset=utf-8' \
  --cache-control 'no-cache' >&2

printf 'https://%s.s3.%s.amazonaws.com/%s\n' "$PROVE_S3_BUCKET" "$region" "$key"
