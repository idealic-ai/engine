#!/usr/bin/env bash
# Publish the shared board widget kit to S3 at a STABLE, versioned key, and print its base URL.
#
# Usage:  publish-kit.sh [<kitDir>]
#         kitDir defaults to ~/.claude/engine/skills/intake/assets
#
# Why this exists: a board used to inline the kit, which meant a published board could never
# receive a fix — it carried the kit it was built with, forever. The kit now lives at one
# address that boards reference, so republishing it fixes every board pointing at that major.
#
# Contract — the kit lands at a key with NO random suffix (the whole point is a fixed address):
#   s3://$PROVE_S3_BUCKET/$PROVE_S3_PREFIX/kit/board-widgets.v<N>.js
#   s3://$PROVE_S3_BUCKET/$PROVE_S3_PREFIX/kit/board-widgets.v<N>.css
#   s3://$PROVE_S3_BUCKET/$PROVE_S3_PREFIX/kit/proof-ticket.v<M>.js
# and is served same-origin with the boards, at
#   https://$PROVE_S3_BUCKET.s3.$PROVE_S3_REGION.amazonaws.com/$PROVE_S3_PREFIX/kit/…
#
# It sits UNDER $PROVE_S3_PREFIX deliberately: the bucket's public-read policy is scoped to
# that prefix, so a kit published anywhere else is a 403 and every board silently loses its
# behaviour. Do not "tidy" it to the bucket root.
#
# Versioning: the kit's major version tracks the PAYLOAD version it emits (kit v2 emits the
# v2 event stream). A breaking payload change mints v3 at a new key and leaves every v2 board
# working against the old one; a bug fix republishes v2 in place and reaches them all.
#
# proof-ticket.js rides along at its OWN version, deliberately decoupled from the kit's. It shares
# nothing with board-widgets.js — disjoint namespace, no data-fb-* , emits no payload — so binding
# the two versions would only mean every kit fix churns the ticket kit's address and vice-versa.
# It carries no version declaration of its own today, so this defaults to 1 and says so; declare
# `PROOF_TICKET_VERSION = <n>` in the file and this picks it up with no change here.
#
# Cache: no-cache — revalidate, not never-cache. With S3's ETag a repeat load is a cheap 304,
# and a fix lands on the next page load rather than waiting out a TTL. Matches publish-s3.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

kitDir="${1:-$HOME/.claude/engine/skills/intake/assets}"
[ -d "$kitDir" ] || { echo "publish-kit: kit dir not found: $kitDir" >&2; exit 1; }

if [ -z "${PROVE_S3_BUCKET:-}" ]; then
  echo "publish-kit: PROVE_S3_BUCKET is not set (and none found in a project .env)." >&2
  echo "  Prescribe it once in your project's .env — see publish-s3.sh for the key list." >&2
  exit 2
fi

# The version is read from the kit source, never passed in — a flag would let the published
# key disagree with what the file actually emits, which is the one thing versioning must prevent.
ver="$(grep -oE 'SCHEMA_VERSION[[:space:]]*=[[:space:]]*[0-9]+' "$kitDir/board-widgets.js" \
       | grep -oE '[0-9]+' | head -1)"
[ -n "$ver" ] || { echo "publish-kit: could not read SCHEMA_VERSION from board-widgets.js" >&2; exit 1; }

# proof-ticket.js is optional-but-expected: a kitDir without it is a broken checkout, not a
# supported configuration, so this is fatal rather than a silent skip — a board referencing a
# ticket kit that was never uploaded 404s with nothing in any log to explain the dead tooltips.
[ -f "$kitDir/proof-ticket.js" ] || { echo "publish-kit: proof-ticket.js not found in $kitDir" >&2; exit 1; }

ticketVer="$(grep -oE 'PROOF_TICKET_VERSION[[:space:]]*=[[:space:]]*[0-9]+' "$kitDir/proof-ticket.js" 2>/dev/null \
             | grep -oE '[0-9]+' | head -1 || true)"
if [ -z "${ticketVer:-}" ]; then
  ticketVer=1
  echo "publish-kit: proof-ticket.js declares no PROOF_TICKET_VERSION — publishing as v1." >&2
  echo "  A breaking change to it will keep landing on v1 until the file declares its own." >&2
fi

base="${PROVE_S3_PREFIX}/kit"
jsKey="${base}/board-widgets.v${ver}.js"
cssKey="${base}/board-widgets.v${ver}.css"
ticketKey="${base}/proof-ticket.v${ticketVer}.js"

aws s3 cp "$kitDir/board-widgets.js" "s3://${PROVE_S3_BUCKET}/${jsKey}" \
  ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} \
  --content-type 'text/javascript; charset=utf-8' \
  --cache-control 'no-cache' >&2

aws s3 cp "$kitDir/board-widgets.css" "s3://${PROVE_S3_BUCKET}/${cssKey}" \
  ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} \
  --content-type 'text/css; charset=utf-8' \
  --cache-control 'no-cache' >&2

aws s3 cp "$kitDir/proof-ticket.js" "s3://${PROVE_S3_BUCKET}/${ticketKey}" \
  ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} \
  --content-type 'text/javascript; charset=utf-8' \
  --cache-control 'no-cache' >&2

# stdout is the BASE url only — publish-s3.sh substitutes it into a board's __FB_KIT_BASE__ token.
printf 'https://%s.s3.%s.amazonaws.com/%s\n' "$PROVE_S3_BUCKET" "$PROVE_S3_REGION" "$base"
