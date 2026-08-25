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
# Contract — the upload set is DERIVED from the kit directory by kit-manifest.sh, never listed here.
# This script used to carry twelve hand-written `aws s3 cp` stanzas, which meant the publisher
# enumerated what it knew while the directory enumerated what existed and nothing compared the two.
# proof-module.css sat in the kit unpublishable while 142 files referenced it. That list is gone; a
# kit file that is neither published nor explicitly excluded is now a hard error at publish time.
#
# Every asset lands at TWO keys under $PROVE_S3_PREFIX/kit/, answering different questions:
#   <stem>.v<N>.<ext>           alias — "the current v<N>". Mutable by design: republishing it is
#                               how a fix reaches pages nobody will recompose.
#   <stem>.v<N>.<sha12>.<ext>   CAS   — "exactly these bytes". Immutable by construction, because
#                               the name is derived from the content and cannot denote anything else.
# plus one index, $PROVE_S3_PREFIX/kit/kit-manifest.json, recording what each alias currently
# resolves to (version, sha256, bytes, CAS key, publish time). The alias is what the already-published
# corpus references; the CAS address is what a page pins when it wants the bytes it was composed
# against and not a later fix. That choice is per-reference and belongs to the page.
#
# Served same-origin with the boards, at
#   https://$PROVE_S3_BUCKET.s3.$PROVE_S3_REGION.amazonaws.com/$PROVE_S3_PREFIX/kit/…
#
# OVERWRITE GUARD (in publish.sh — this script only stages). Before it existed, twelve unconditional
# PutObjects meant a declared version did not pin bytes: published proof-blocks.v2.css was 113,188 B
# against 236,995 B on disk, so 52 pages were each receiving 47.8% of the block catalog they linked.
# Now every address is probed first — absent uploads, identical is a NO-OP, different is REFUSED and
# the run stops before writing anything. A CAS address is never overridable. An ALIAS may be
# deliberately replaced with --force, which is the §5 retint path (a spacing or hue fix republishes
# v1 in place and reaches every page pinned to it). That path stays open, but it is now an explicit
# act that names every address it moves and prints both hashes, rather than the silent default.
#
# It sits UNDER $PROVE_S3_PREFIX deliberately: the bucket's public-read policy is scoped to
# that prefix, so a kit published anywhere else is a 403 and every board silently loses its
# behaviour. Do not "tidy" it to the bucket root.
#
# Versioning: the kit's major version tracks the PAYLOAD version it emits (kit v2 emits the
# v2 event stream). A breaking payload change mints v3 at a new key and leaves every v2 board
# working against the old one; a bug fix republishes v2 in place and reaches them all.
#
# board-warm-overrides.css rides along at the SAME version as board-widgets: it is board-widgets'
# presentation companion (it maps the kit's --fb-* seam onto the proof-theme tokens), so it is
# bound to the kit's major, not versioned apart. A v2 board pulls board-warm-overrides.v2.css.
#
# proof-theme.css carries its OWN version (PROOF_THEME_VERSION, default 1) — it is the design-system
# token layer the whole system consumes (block catalog, proof-ticket.js, and the board overrides),
# not board-widgets' payload, so it turns over on its own cadence. It declares no version constant
# today, so this defaults to 1; declare `PROOF_THEME_VERSION = <n>` in the file and this picks it up.
#
# proof-ticket.js rides along at its OWN version, deliberately decoupled from the kit's. It shares
# nothing with board-widgets.js — disjoint namespace, no data-fb-* , emits no payload — so binding
# the two versions would only mean every kit fix churns the ticket kit's address and vice-versa.
# It declares `PROOF_TICKET_VERSION = <n>` (3 today) and this picks it up with no change here; a
# file that declares none defaults to 1 and says so.
#
# proof-ticket.css rides at the SAME version as proof-ticket.js. It is not an optional restyle: the
# component is BEHAVIOR-ONLY and injects no <style>, so proof-ticket.v<M>.css is the ONLY source of
# its appearance — a page that links the js without the css renders the ticket unstyled. Behaviour
# and appearance ship as one component, so they carry one version; splitting them would let a page
# pair v3 behaviour with v2 selectors and get a half-styled card with nothing anywhere to explain it.
#
# proof-blocks.css carries its OWN version (PROOF_BLOCKS_VERSION, default 1) — it is the .mod block
# catalog (decision layer, affordance rail, popovers), consumed by hand-authored proof pages that
# reference no kit JS at all. Its cadence is the catalog's, not board-widgets' payload's.
#
# proof-creative.css carries its OWN version (PROOF_CREATIVE_VERSION) — the 25 creative layout
# patterns across six .fam-* families, extracted from CREATIVE_LAYOUTS.html so a page can OBTAIN a
# pattern's geometry instead of retyping 500-odd scoped rules out of a gallery. It is published for
# RELIABILITY, not maintenance: an authoring agent cannot dependably reproduce that CSS from prose,
# and §INV_PROVE_COMPOSE_FROM_KIT forbids it from trying. Its version binds to the pattern CLASS
# CONTRACT, not the paint — a renamed class or a changed required wrapper mints v2 and leaves every
# v1 page rendering as it shipped; a spacing or hue fix republishes v1 in place and reaches them all.
# Deliberately NOT bound to proof-blocks.css: the block catalog is the decision layer, this is the
# page's geometry, and a page routinely links one without the other.
#
# kit-behaviors.js carries its OWN version (KIT_BEHAVIORS_VERSION, default 1) — vote / clear /
# dirty-tracking / submit / beforeunload / note / copy-anchor / view-filter for the decision layer.
# It is proof-blocks.css's behavior counterpart but is NOT bound to it: the two are wired by
# convention (data-attributes + kit classes), so a pure catalog restyle must not churn the script's
# address, and a behaviour fix must not force every page to re-pull the stylesheet.
#
# Both of the above declare no version constant today, so each defaults to 1 with a warning; declare
# `PROOF_BLOCKS_VERSION = <n>` / `KIT_BEHAVIORS_VERSION = <n>` in the file and this picks it up.
#
# board-swipe.js + board-swipe.css carry their OWN version (BOARD_SWIPE_VERSION) — the drag
# accelerator for BINARY decision items. Deliberately NOT bound to board-widgets' SCHEMA_VERSION
# even though it drives board-widgets' inputs: it emits no payload of its own (it commits through
# input.click(), so the kit produces the event), and board-widgets.{js,css} are the cannot-drift
# byte-compared pair — binding the two would force a payload-version bump for a gesture tweak and
# put pressure on exactly the files that must not move. The css rides the js's version for the same
# reason proof-ticket.css rides proof-ticket.js: the js injects no <style>, so a page pairing v2
# behaviour with v1 selectors renders a half-styled control with nothing anywhere to explain it.
#
# proof-icons.v<I>.woff2 is the subsetted MONOCHROME Noto Emoji face that proof-theme.css's
# @font-face claims by unicode-range. Its version comes from PROOF_ICONS_VERSION, declared in
# proof-theme.css rather than in the font — a .woff2 cannot carry a constant, and the stylesheet
# is the only thing that binds it. Deliberately NOT bound to PROOF_THEME_VERSION: re-cutting the
# subset must not mint a new theme key, because every published page pins the theme version it
# was composed against and a theme bump would strand them all on the old font.
#
# The @font-face src is RELATIVE ("./proof-icons.v<I>.woff2"), which resolves against the
# STYLESHEET's url — i.e. this same kit/ prefix — so the bucket is hardcoded nowhere and the
# same file works unchanged from a local checkout. Same-origin with the boards, so no CORS
# headers are needed; a font served cross-origin without them fails silently and the page
# quietly falls back to platform emoji, which is exactly the failure this layout avoids.
#
# Cache: no-cache — revalidate, not never-cache. With S3's ETag a repeat load is a cheap 304,
# and a fix lands on the next page load rather than waiting out a TTL. Matches publish-s3.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

# Usage: publish-kit.sh [<kitDir>] [--dry-run] [--force] [...]
# Flags are forwarded to publish.sh untouched, so the kit publishes with the same surface, the same
# output shape and the same exit codes as any other directory.
kitDir="$HOME/.claude/engine/skills/intake/assets"
KIT_ARGS=()
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then kitDir="$1"; shift; fi
while [ $# -gt 0 ]; do KIT_ARGS+=("$1"); shift; done
[ -d "$kitDir" ] || { echo "publish-kit: kit dir not found: $kitDir" >&2; exit 1; }

if [ -z "${PROVE_S3_BUCKET:-}" ]; then
  echo "publish-kit: PROVE_S3_BUCKET is not set (and none found in a project .env)." >&2
  echo "  Prescribe it once in your project's .env — see publish-s3.sh for the key list." >&2
  exit 2
fi

# --- Derive the upload set, stage it, hand it to publish ------------------------------------------
# Nothing below names an asset. kit-manifest.sh walks the kit directory and fails if any file in it
# is neither published nor explicitly excluded — that check is the whole point, and it is why the
# twelve hand-written `aws s3 cp` stanzas that used to live here are gone.
manifest="$("$here/kit-manifest.sh" "$kitDir")"
[ -n "$manifest" ] || { echo "publish-kit: kit-manifest.sh produced no rows" >&2; exit 1; }

# Staging is where the NAMING policy lives: on-disk `proof-blocks.css` becomes the alias
# `proof-blocks.v2.css` AND the content address `proof-blocks.v2.<sha12>.css`. It is a copy into a
# temp dir, so the kit source is never touched — this script uploads kit files, it must never edit
# them, and a staging step that wrote back into the kit would be the one way it could.
stage="$(mktemp -d -t fb-kit-stage)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/kit"

rowsTsv="$stage/.rows.tsv"
printf '%s\n' "$manifest" > "$rowsTsv"

while IFS='	' read -r name alias cas sha bytes ctype; do
  [ -n "$name" ] || continue
  cp "$kitDir/$name" "$stage/kit/$alias"
  cp "$kitDir/$name" "$stage/kit/$cas"
done < "$rowsTsv"

KIT_BASE_URL="https://${PROVE_S3_BUCKET}.s3.${PROVE_S3_REGION}.amazonaws.com/${PROVE_S3_PREFIX}/kit" \
  python3 "$here/_kit-manifest-json.py" "$rowsTsv" > "$stage/kit/kit-manifest.json"
rm -f "$rowsTsv"

staged="$(find "$stage/kit" -type f | wc -l | tr -d ' ')"
echo "publish-kit: staged ${staged} objects from ${kitDir}" >&2

# Transport, the overwrite guard and the read-back all live in publish.sh; this script decides only
# WHAT the kit publishes and under WHICH names. Flags reach publish.sh verbatim, so
# `publish-kit.sh --dry-run` and `publish-kit.sh --force` behave exactly as they do for any other
# directory — there is no kit-specific publishing behaviour to learn.
# --flat is not negotiable here. publish now versions the DIRECTORY it is handed, which is right for
# a bundle of HTML and catastrophic for the kit: kit files already carry their version in their own
# name (proof-blocks.v2.css) and ~142 published pages reference them at exactly those keys, so
# nesting them one level deeper under a unit directory would 404 every one of them at once.
"$here/publish.sh" "$stage" --to "s3://${PROVE_S3_BUCKET}/${PROVE_S3_PREFIX}" --flat \
  ${KIT_ARGS[@]+"${KIT_ARGS[@]}"} >&2

# stdout is the BASE url only — publish-s3.sh substitutes it into a page's __FB_KIT_BASE__ token.
printf 'https://%s.s3.%s.amazonaws.com/%s/kit\n' "$PROVE_S3_BUCKET" "$PROVE_S3_REGION" "$PROVE_S3_PREFIX"
