#!/usr/bin/env bash
# Derive the kit's UPLOAD SET from the kit directory, and fail if the directory holds a file the
# set does not account for.
#
# Usage:  kit-manifest.sh [<kitDir>]        # TSV to stdout, diagnostics to stderr
#         kitDir defaults to ~/.claude/engine/skills/intake/assets
#
# Output (TSV, one row per published object, stable order):
#   localName <TAB> aliasName <TAB> casName <TAB> sha256 <TAB> bytes <TAB> contentType
#
# Why this file exists. publish-kit.sh used to carry twelve hand-written `aws s3 cp` stanzas. The
# publisher therefore enumerated what it KNEW and the directory enumerated what EXISTED, and nothing
# compared the two — so proof-module.css sat in the kit unpublishable while 142 files referenced it,
# and no run of anything said a word. A list that is maintained by hand is a list that silently goes
# short; the only fix is to stop keeping one.
#
# So the set is derived, and the derivation is TOTAL: every regular file at the top level of the kit
# dir must land in exactly one of three buckets —
#   PUBLISH   it is in the version table below, or it is a versioned iconset face
#   EXCLUDE   it matches a declared exclusion rule, WITH a stated reason
#   neither   → HARD ERROR, naming the file
# "Neither" is the bucket that matters. A new asset dropped into the kit is unreachable until someone
# says what it is, and the failure arrives at publish time — not months later as a 404 in a reader's
# console. Adding an asset is deliberately a two-line edit here rather than a silent success.
#
# TWO ADDRESSES PER ASSET, and they answer different questions:
#
#   alias  <stem>.v<N>.<ext>              — "the current v<N>". Mutable by design: this is what the
#                                           published corpus references, and republishing it is how a
#                                           fix reaches pages nobody will recompose. It names a
#                                           VERSION, and a version does not pin bytes.
#   cas    <stem>.v<N>.<sha12>.<ext>      — "exactly these bytes". Immutable by construction: the name
#                                           is derived from the content, so it can never denote
#                                           anything else. This is the identity.
#
# Both are published on every run. The alias keeps 142 already-published pages working; the CAS
# address is what a page pins when it wants the bytes it was composed against and not a later fix.
# The choice is per-reference and belongs to the page, not to this script (publish-s3.sh PROVE_KIT_PIN).
#
# The sha12 sits BEFORE the extension and AFTER the version on purpose: the version stays legible to
# a human reading the URL, the extension stays last so S3's content-type sniffing and every editor
# still see a .css, and the hash is unmissable in between.
set -euo pipefail

kitDir="${1:-$HOME/.claude/engine/skills/intake/assets}"
[ -d "$kitDir" ] || { echo "kit-manifest: kit dir not found: $kitDir" >&2; exit 1; }

# --- Version table -------------------------------------------------------------------------------
# localName | version constant | file the constant is DECLARED IN | content type
#
# The constant is read from the source, never passed in — a flag would let the published key disagree
# with what the file actually declares, which is the one thing versioning must prevent.
#
# A companion (board-widgets.css, board-warm-overrides.css, proof-ticket.css, board-swipe.css) reads
# its version from its PARTNER's file rather than declaring its own. That is not laziness: each of
# those pairs is one component whose halves cannot drift — the .js injects no <style>, so a page that
# pairs v2 behaviour with v1 selectors renders a half-styled control with nothing anywhere to explain
# it. One component, one version, read from one place.
KIT_TABLE='
board-widgets.js|SCHEMA_VERSION|board-widgets.js|text/javascript; charset=utf-8
board-widgets.css|SCHEMA_VERSION|board-widgets.js|text/css; charset=utf-8
board-warm-overrides.css|SCHEMA_VERSION|board-widgets.js|text/css; charset=utf-8
proof-theme.css|PROOF_THEME_VERSION|proof-theme.css|text/css; charset=utf-8
proof-ticket.js|PROOF_TICKET_VERSION|proof-ticket.js|text/javascript; charset=utf-8
proof-ticket.css|PROOF_TICKET_VERSION|proof-ticket.js|text/css; charset=utf-8
proof-blocks.css|PROOF_BLOCKS_VERSION|proof-blocks.css|text/css; charset=utf-8
proof-creative.css|PROOF_CREATIVE_VERSION|proof-creative.css|text/css; charset=utf-8
proof-module.css|PROOF_MODULE_VERSION|proof-module.css|text/css; charset=utf-8
kit-behaviors.js|KIT_BEHAVIORS_VERSION|kit-behaviors.js|text/javascript; charset=utf-8
board-swipe.js|BOARD_SWIPE_VERSION|board-swipe.js|text/javascript; charset=utf-8
board-swipe.css|BOARD_SWIPE_VERSION|board-swipe.js|text/css; charset=utf-8
'

# --- Exclusion rules -----------------------------------------------------------------------------
# glob | reason. The reason is not decoration — it is the thing a future reader checks when they
# wonder why their new file did not publish, and it is what keeps this list from becoming a
# junk-drawer that quietly swallows a real asset.
KIT_EXCLUDE='
*.md|documentation — read from the checkout, never fetched by a page
*.mjs|build-time tooling (kit-digest, theme-roles) — run from the checkout, never served
*.json|build-time data/config — consumed by the tooling, not linked by a page
*.html|galleries and specs (CREATIVE_LAYOUTS, PROOF_BLOCKS) — sources, not served assets
*.manifest|credential inventory — must never leave the machine
*.pre-glyph-cut|superseded editor backup
*.bak|editor backup
*.orig|merge residue
*.tmp|scratch
.*|dotfile
'

# --- Helpers -------------------------------------------------------------------------------------
read_version() { # <constantName> <declaringFile>
  grep -oE "${1}[[:space:]]*=[[:space:]]*[0-9]+" "$kitDir/$2" 2>/dev/null \
    | grep -oE '[0-9]+' | head -1 || true
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

bytes_of() { wc -c < "$1" | tr -d ' '; }

# --- Pass 1: the published set -------------------------------------------------------------------
rows=""
published_names=""

emit_row() { # <localName> <aliasName> <casName> <contentType>
  local p="$kitDir/$1" sha bytes
  sha="$(sha256_of "$p")"
  bytes="$(bytes_of "$p")"
  rows="${rows}${1}	${2}	${3}	${sha}	${bytes}	${4}
"
  published_names="${published_names} ${1} "
}

while IFS='|' read -r name const declaredIn ctype; do
  [ -n "$name" ] || continue
  # Fatal, not a skip. A kitDir missing one of these is a broken checkout, not a supported config:
  # a page referencing an object nobody uploaded 404s with nothing in any log to explain it, and
  # the failure reads as "the design never landed" rather than as an incomplete publish.
  [ -f "$kitDir/$name" ] || { echo "kit-manifest: $name not found in $kitDir" >&2; exit 1; }
  [ -f "$kitDir/$declaredIn" ] || { echo "kit-manifest: $declaredIn (version source for $name) not found in $kitDir" >&2; exit 1; }
  ver="$(read_version "$const" "$declaredIn")"
  if [ -z "$ver" ]; then
    ver=1
    echo "kit-manifest: $declaredIn declares no $const — publishing $name as v1." >&2
    echo "  A breaking change to it will keep landing on v1 until the file declares its own." >&2
  fi
  stem="${name%.*}"; ext="${name##*.}"
  emit_row "$name" "${stem}.v${ver}.${ext}" "${stem}.v${ver}.__SHA__.${ext}" "$ctype"
done <<EOF
$(printf '%s\n' "$KIT_TABLE" | sed '/^[[:space:]]*$/d')
EOF

# The iconset carries its version in its FILENAME — a .woff2 cannot hold a constant, and the
# @font-face src that claims it is RELATIVE ("./proof-icons.v<I>.woff2"), resolving against the
# stylesheet's own url. So the file's name IS its address, and every version present on disk is
# published under its own literal name: a page pinned to proof-theme.v1.css still asks for
# proof-icons.v1.woff2, and dropping the older face would silently revert every icon on it to
# platform colour emoji. Publishing only "the current one" is how a superseded face goes missing.
iconFound=0
for f in "$kitDir"/proof-icons.v*.woff2; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  emit_row "$n" "$n" "${n%.woff2}.__SHA__.woff2" "font/woff2"
  iconFound=1
done
[ "$iconFound" = 1 ] || { echo "kit-manifest: no proof-icons.v*.woff2 in $kitDir" >&2; exit 1; }

# The stylesheet must actually point at the version it declares, or the published pair 404s and the
# page quietly falls back to platform emoji. Check the pair rather than trusting it.
iconsVer="$(read_version PROOF_ICONS_VERSION proof-theme.css)"
if [ -n "$iconsVer" ]; then
  [ -f "$kitDir/proof-icons.v${iconsVer}.woff2" ] || {
    echo "kit-manifest: proof-theme.css declares PROOF_ICONS_VERSION=$iconsVer but proof-icons.v${iconsVer}.woff2 is not in $kitDir" >&2; exit 1; }
  grep -q "proof-icons\.v${iconsVer}\.woff2" "$kitDir/proof-theme.css" || {
    echo "kit-manifest: proof-theme.css declares PROOF_ICONS_VERSION=$iconsVer but its @font-face src does not name proof-icons.v${iconsVer}.woff2" >&2; exit 1; }
fi

# --- Pass 2: completeness ------------------------------------------------------------------------
# The whole point. Every top-level regular file must be accounted for; anything that is neither
# published nor explicitly excluded stops the publish and is named.
unaccounted=""
for f in "$kitDir"/* "$kitDir"/.[!.]*; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  case "$published_names" in *" $n "*) continue;; esac
  excluded=0
  while IFS='|' read -r glob _reason; do
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2254
    case "$n" in $glob) excluded=1; break;; esac
  done <<EOF
$(printf '%s\n' "$KIT_EXCLUDE" | sed '/^[[:space:]]*$/d')
EOF
  [ "$excluded" = 1 ] || unaccounted="${unaccounted}  ${n}
"
done

if [ -n "$unaccounted" ]; then
  echo "kit-manifest: HARD ERROR — kit files present on disk that the upload set does not account for:" >&2
  printf '%s' "$unaccounted" >&2
  echo "  Every top-level file must be either published (add it to KIT_TABLE in kit-manifest.sh)" >&2
  echo "  or explicitly excluded WITH a reason (add it to KIT_EXCLUDE). A silent skip is how" >&2
  echo "  proof-module.css sat in the kit unpublished while 142 files referenced it." >&2
  exit 1
fi

# --- Emit ----------------------------------------------------------------------------------------
# __SHA__ is substituted here rather than at emit_row so the CAS name is unambiguously derived from
# the very sha that ships in the same row — one source, no chance of the two disagreeing.
printf '%s' "$rows" | while IFS='	' read -r name alias cas sha bytes ctype; do
  [ -n "$name" ] || continue
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$alias" "${cas/__SHA__/${sha:0:12}}" "$sha" "$bytes" "$ctype"
done
