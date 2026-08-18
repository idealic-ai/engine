#!/usr/bin/env bash
# Publish a self-contained /prove HTML to S3 and print its public URL (stdout ONLY).
#
# Usage:  publish-s3.sh <proofPath> [<slug>]
#
# Config resolution (first wins), via the shared engine resolver:
#   1. real environment variables (PROVE_S3_*)
#   2. the current session's project root: .env.local then .env
#      (PROVE_S3_ENV overrides both with ONE authoritative file)
#   3. the prove manifest's defaults (skills/prove/assets/credentials.json)
#   4. otherwise: poke the user (never guesses a bucket)
# Duplicate keys in one file resolve FIRST-NON-EMPTY, the engine-wide rule.
#
# Keys:
#   PROVE_S3_BUCKET   (required) target bucket, e.g. staging-finch-proofs
#   PROVE_S3_REGION   (default us-east-2) region for the virtual-hosted URL
#   PROVE_S3_PREFIX   (default proofs)    key prefix; MUST match the bucket's public-read policy prefix
#   PROVE_S3_PROFILE  (optional) AWS CLI profile for the upload, e.g. finch-staging
#   PROVE_S3_SIGNER_PROFILE (optional) profile used ONLY to sign the board's write grant; defaults
#                     to PROVE_S3_PROFILE. Point it at a narrow long-lived key (PutObject on the
#                     events prefix only) to get a board that still accepts votes days from now —
#                     a presign expires with the credential that signed it, so a session token
#                     yields a board that is write-dead within the hour.
#   PROVE_S3_USER     (optional) per-user key segment; else derived from the AWS caller identity
#   PROVE_TICKETS_JSON (optional) path to the ticket-data JSON to publish beside the page. Default:
#                     <proofPath with .html stripped>.tickets.json, i.e. what bake-tickets.sh --emit
#                     writes with no --out. Absent ⇒ no ticket data is published (the page's refs
#                     degrade to plain links, loudly, at read time).
#   PROVE_TICKETS_KEY (optional) an EXPLICIT bucket key for that JSON, e.g. proofs/yarik/wave3.tickets.json.
#                     This is the opt-in to ONE json serving MANY pages. Default is the page's own
#                     key stem, which inherits the page key's <rand8> unguessability; a shared key
#                     is by construction predictable, so the object becomes a public index of every
#                     ticket it carries. Worth it for a wave; say so deliberately, not by default.
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

# --- Resolve config through THE shared resolver (real env vars still win) ---
# This used to be a private `envget()` — a second KEY= parser with its own walk-up and
# `tail -1` (LAST-match) semantics, while every other engine credential resolves
# FIRST-NON-EMPTY. /prove therefore answered differently depending on which script you
# entered through. _prove-s3-env.sh is now the ONE place prove config is resolved; it
# loads the `prove` manifest via env_load_domain and honours PROVE_S3_ENV as an
# authoritative single-file override. (It also sets PROFILE_ARG, which this script does
# not use — it builds its own profile_arg below, including the signer variant.)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

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

# Publishing and signing want DIFFERENT identities. The upload is a person putting a page in a
# bucket; the presign mints a write grant that is handed to strangers and lives for up to a week.
# A presign cannot outlive its signer, so a durable board needs a long-lived key — and a long-lived
# key that could also write PROVE_S3_PREFIX could overwrite any published board with anything.
# Hence a separate profile for signing only, defaulting to the publishing one so a config that
# sets neither behaves exactly as before.
signer_profile_arg=(${profile_arg[@]+"${profile_arg[@]}"})
[ -n "${PROVE_S3_SIGNER_PROFILE:-}" ] && signer_profile_arg=(--profile "$PROVE_S3_SIGNER_PROFILE")

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

# Does this page COLLECT DECISIONS? This gates the state config below, whose write half is a real
# presigned credential handed to everyone who gets the link — so the question has to be "can this
# page submit anything", not "does it look like a board".
#
# The gate used to be `grep __FB_KIT_BASE__`, on the reasoning that referencing the kit was the one
# durable marker of a board. That stopped being true the moment EVERY /prove page began referencing
# the kit for its theme and block catalog: a pure read-only evidence page — no votes, no inputs,
# nothing to submit — would have been published carrying a week-long write grant it has no code to
# spend. A credential nothing can spend is still a credential that left the machine.
#
# So the marker is the DECISION MARKUP itself, taken from both consumers: board-widgets.js's
# payload attributes (data-fb-board/item/voter/submit/payload) and kit-behaviors.js's decision
# layer (data-decision-item, its legacy .dxsec, and the .submitbtn[data-submit] cluster).
# Deliberately NOT data-fb-state-config — that is the element THIS SCRIPT injects, so matching it
# would let a republished page qualify itself on the strength of its own previous publish.
isBoard=0
if grep -qE 'data-fb-(board|item|voter|submit|payload)|data-decision-item|data-submit=|dxsec' "$upload"; then
  isBoard=1
fi

# --- Resolve the shared widget kit reference, if this page uses one ---
# A page references the kit as __FB_KIT_BASE__/<file>.v<N>.<ext> rather than inlining it, so a
# published page can receive fixes. Publish time is the only moment bucket, region and prefix are
# all known, so substitution happens here rather than being guessed by the author. Boards reference
# board-widgets; proof pages reference proof-theme / proof-blocks / proof-ticket / kit-behaviors —
# one substitution serves both, because the token resolves to the kit BASE, not to a file.
# Pages with no token are untouched.
if grep -q '__FB_KIT_BASE__' "$upload"; then
  kitBase="https://${PROVE_S3_BUCKET}.s3.${region}.amazonaws.com/${prefix}/kit"
  sed "s|__FB_KIT_BASE__|${kitBase}|g" "$upload" > "${work}/kit.html"
  mv "${work}/kit.html" "$upload"
  echo "publish-s3: kit reference resolved → ${kitBase}" >&2
  # A surviving token is the one failure this step can produce that NOTHING downstream reports: the
  # page uploads fine, the browser requests a literal `__FB_KIT_BASE__/…` path, and the reader gets
  # a page whose stylesheets and behaviour are simply absent — no console error a sharer would see,
  # no non-zero exit anywhere. Assert it away rather than trusting sed.
  if grep -q '__FB_KIT_BASE__' "$upload"; then
    echo "publish-s3: the kit token survived substitution — refusing to upload a page whose kit references would 404" >&2
    exit 1
  fi

  # --- Optional: PIN each kit reference to a content address ---
  # The substitution above resolves the token to the kit BASE, so the page ends up asking for
  # proof-blocks.v2.css — a VERSION. A version is a name, and a name does not pin bytes: that same
  # address served 113,188 B while the kit held 236,995 B, so 52 published pages were each getting
  # 47.8% of the block catalog they linked, with nothing anywhere to say so.
  #
  # PROVE_KIT_PIN=1 rewrites each reference to its content address (proof-blocks.v2.<sha12>.css),
  # read from the kit's published index. The page then receives the exact bytes it was composed
  # against, forever — and, by exactly the same mechanism, stops receiving fixes. That is the whole
  # trade and it belongs to the page, not to this script, which is why it is opt-in and per-publish
  # rather than a global setting: an evidence page that must still read correctly in a year wants
  # pinning; a living board that should pick up a hue fix does not.
  if [ "${PROVE_KIT_PIN:-0}" = "1" ]; then
    if curl -fsS --max-time 20 "${kitBase}/kit-manifest.json" -o "${work}/kit-manifest.json"; then
      KIT_BASE="$kitBase" python3 - "$upload" "${work}/kit-manifest.json" > "${work}/pinned.html" <<'PY'
import json, os, sys

page = open(sys.argv[1], encoding="utf-8").read()
manifest = json.load(open(sys.argv[2], encoding="utf-8"))
base = os.environ["KIT_BASE"].rstrip("/")

# Longest alias first: proof-ticket.v4.css must not be rewritten by a rule for proof-ticket.v4.js,
# and a shorter alias that is a prefix of a longer one would otherwise corrupt it.
pins = sorted(((a["alias"], a["contentAddress"]) for a in manifest["assets"]),
              key=lambda p: -len(p[0]))
done = []
for alias, cas in pins:
    src, dst = "%s/%s" % (base, alias), "%s/%s" % (base, cas)
    if src in page:
        page = page.replace(src, dst)
        done.append("%s -> %s" % (alias, cas))

sys.stderr.write("publish-s3: pinned %d kit reference(s) to content addresses\n" % len(done))
for d in done:
    sys.stderr.write("publish-s3:   %s\n" % d)
sys.stdout.write(page)
PY
      mv "${work}/pinned.html" "$upload"
    else
      echo "publish-s3: PROVE_KIT_PIN=1 but ${kitBase}/kit-manifest.json could not be read — refusing to publish a page that asked to be pinned and would silently not be" >&2
      exit 1
    fi
  fi

  # --- Every kit address this page DECLARES must actually resolve ---
  # The surviving-token check above catches one failure mode out of five. This catches the rest, and
  # they are the ones that were live: proof-module.css could not be published at all (the publisher
  # enumerated twelve files by hand and that was not one of them) while 142 files referenced it, and
  # proof-creative.v2.css 403s because no code path ever mints a v2 key. Both fail exactly the way
  # the token failure does — the page uploads fine, the browser gets nothing for those requests, and
  # the reader sees an unstyled page with no console error a sharer would ever look at.
  #
  # Read back the way a READER reads: anonymous, no credential. An object under a key the bucket
  # policy does not serve is a 200 to the uploader and a 403 to everyone else.
  if command -v curl >/dev/null 2>&1; then
    dangling=0
    for ref in $(grep -oE "${kitBase//./\\.}/[A-Za-z0-9._-]+" "$upload" | sort -u); do
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -I "$ref" 2>/dev/null || echo 000)"
      if [ "$code" != "200" ]; then
        echo "publish-s3: DECLARED KIT ADDRESS DOES NOT RESOLVE — HTTP ${code}: ${ref}" >&2
        dangling=$((dangling + 1))
      fi
    done
    if [ "$dangling" -gt 0 ]; then
      echo "publish-s3: refusing to publish a page with ${dangling} kit reference(s) that a reader cannot fetch." >&2
      echo "  Publish the kit first: publish-kit.sh   (it will name anything missing)." >&2
      exit 1
    fi
  fi
fi

# --- Mint + inject the shared-state config on every board ---
# Publish is the only moment the bucket, the doc id and a signable credential all exist at once,
# so the config is minted here. EVERY board gets one: nothing upstream ever asked for it, so a
# board that depended on being asked was mute by construction — teammates had no way to vote in it
# and a council run had nowhere to seed records. The placeholder is a PLACEMENT hint, not a
# request; a board that carries none gets the element appended. Pages with NO decision markup — a
# read-only evidence proof, however much of the kit it links — are untouched: no config, no
# credential, byte-identical. An author who wants state on such a page says so with the placeholder.
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
  elif ! creds="$(aws configure export-credentials ${signer_profile_arg[@]+"${signer_profile_arg[@]}"} --format env 2>"${work}/cred.err")"; then
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
    # Why the window is the length it is, carried on the page rather than left on the signer's
    # stdout. A board that says "closes in 12 minutes" without saying "because it was signed with
    # a temporary credential" reproduces the confusion this whole config exists to end. .get() so
    # an older signer's output degrades to null instead of failing the publish.
    for k in ("expirySeconds", "expiryRequested", "expiryClampedBy"):
        cfg[k] = presign.get(k)
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
else
  # Say so, and only in the case that is actually surprising: a page that links the kit but carries
  # nothing to decide. Silence here is what would send an author hunting for a broken bucket when
  # the page simply never asked to collect anything.
  if grep -q "${prefix}/kit" "$upload"; then
    echo "publish-s3: no decision markup — publishing read-only (no state config, no write grant)" >&2
  fi
fi

# --- Upload the sibling ticket-data JSON, and tell the page where it is ---
# proof-ticket.js v4 reads ticket metadata from a JSON published BESIDE the page. Same bucket ⇒
# same-origin for the canonical copy: no credential, no preflight. Two things happen here and both
# are load-bearing:
#
#   1. The JSON is uploaded at the page's OWN key stem (…/<slug>-<rand8>.tickets.json). That is
#      deliberate over a shared/predictable key: the page's rand8 IS the access-control model, and
#      a per-wave doc at a guessable key would be a public, enumerable index of every ticket title,
#      assignee and comment excerpt any proof has ever cited — a larger disclosure than the pages
#      it serves. An operator who wants the share can name it: PROVE_TICKETS_KEY=<bucket key>.
#   2. An ABSOLUTE <link rel="prove-tickets"> is injected. The component can derive the sibling
#      from its own address, but only while it IS at that address. A copy ATTACHED to a Linear
#      issue is served from Linear's host, where a derived sibling resolves to linear.app and 404s
#      forever. The absolute URL is what keeps an attached copy pointed back at the bucket — and
#      that cross-origin read is what needs the bucket CORS policy (docs: KIT_README §2b).
#
# Nothing here is fatal. A page with no ticket data publishes exactly as before; a JSON that fails
# to upload leaves a page that degrades LOUDLY at read time (working links + a stated reason),
# which is strictly better than refusing to publish the page at all.
ticketsJson=""
if [ -n "${PROVE_TICKETS_JSON:-}" ] && [ -f "${PROVE_TICKETS_JSON}" ]; then
  ticketsJson="$PROVE_TICKETS_JSON"
else
  candidate="$(printf '%s' "$proofPath" | sed -E 's/\.html?$//').tickets.json"
  [ -f "$candidate" ] && ticketsJson="$candidate"
fi

if [ -n "$ticketsJson" ]; then
  # An explicit shared key is taken verbatim (that is the whole point of it); otherwise the sibling
  # of the page key, which is exactly what the component derives when no <link> survives.
  ticketsKey="${PROVE_TICKETS_KEY:-${prefix}/${user}/${stem}${TICKETS_SUFFIX:-.tickets.json}}"
  ticketsUrl="https://${PROVE_S3_BUCKET}.s3.${region}.amazonaws.com/${ticketsKey}"

  if aws s3 cp "$ticketsJson" "s3://${PROVE_S3_BUCKET}/${ticketsKey}" \
      ${profile_arg[@]+"${profile_arg[@]}"} \
      --content-type 'application/json; charset=utf-8' \
      --cache-control 'no-cache' >&2; then
    TICKETS_URL="$ticketsUrl" python3 - "$upload" > "${work}/tickets.html" <<'PY'
import os, re, sys

page = open(sys.argv[1], encoding="utf-8").read()
url = os.environ["TICKETS_URL"]
# The href is a bucket URL this script just built from its own config — no user text reaches it —
# but quote-escaping it costs nothing and keeps a bucket name with a quote in it from breaking out
# of the attribute.
el = '<link rel="prove-tickets" href="%s">' % url.replace('"', "&quot;")

existing = re.search(r"<link\b[^>]*\brel=[\"'][^\"']*\bprove-tickets\b[^\"']*[\"'][^>]*>", page, re.I)
if existing:
    # REPLACE, never append: the component takes the FIRST match, so a second link means every
    # re-publish keeps serving the first publish's URL and silently does nothing.
    page = page[:existing.start()] + el + page[existing.end():]
    where = "replaced the existing link"
else:
    head = list(re.finditer(r"</head\s*>", page, re.I))
    if head:
        at, where = head[0].start(), "inserted before </head>"
    else:
        body = list(re.finditer(r"</body\s*>", page, re.I))
        at, where = (body[-1].start(), "inserted before </body>") if body else (len(page), "appended")
    page = page[:at] + el + "\n" + page[at:]

sys.stderr.write("publish-s3: ticket-data link %s\n" % where)
sys.stdout.write(page)
PY
    mv "${work}/tickets.html" "$upload"
    echo "publish-s3: ticket data uploaded → ${ticketsUrl}" >&2
    if [ -n "${PROVE_TICKETS_KEY:-}" ]; then
      echo "publish-s3: SHARED ticket-data key in use — this object now serves every page that points at it, and its bakedAt is what those pages will state" >&2
    fi
    echo "publish-s3: a copy ATTACHED elsewhere reads this cross-origin — the bucket needs a GET/HEAD CORS rule or that copy degrades to plain links" >&2
    # A successful PUT is not the same fact as a readable GET. The page fetches this URL with no
    # credential, so read it back the way a reader will: an upload that lands under a key the bucket
    # policy does not serve is invisible here and a failure banner at the reader.
    if command -v curl >/dev/null 2>&1; then
      readback="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$ticketsUrl" 2>/dev/null || echo 000)"
      if [ "$readback" != "200" ]; then
        echo "publish-s3: WARNING — the ticket data uploaded but reads back HTTP ${readback} for an anonymous reader" >&2
        echo "publish-s3:   the published page WILL fetch that URL and paint a failure banner. Fix the bucket read policy for ${ticketsKey} before sharing the link" >&2
      fi
    fi
  else
    echo "publish-s3: ticket data upload FAILED — the page still publishes; its ticket refs will degrade to links with a stated reason" >&2
  fi
elif grep -qE '(^|[^A-Za-z0-9-])FIN-[0-9]+' "$upload" >/dev/null 2>&1; then
  # Loud here too — and ACTIVE, because a warning alone is what let this ship. The component resolves
  # its data source link → meta → CONVENTION, and the convention is the page's own address with
  # .html swapped for .tickets.json. So a page published with ticket refs and no bake fetches a key
  # nobody uploaded, gets the bucket's 403, and paints a failure banner at the reader — while this
  # script's own warning claimed the refs would "render as plain links". They would not.
  #
  # Declaring the absence is the "don't inject a fetch you cannot serve" half: an EMPTY prove-tickets
  # meta is a source declared as none, which the component reads as `absent` (zero requests, no
  # banner, and the page states "no ticket data is attached"). It also REPLACES a link left by an
  # earlier publish, which would otherwise outlive the object it points at.
  # An INLINE blob wins over both and needs no network — leave such a page alone.
  python3 - "$upload" > "${work}/no-tickets.html" <<'PY'
import re, sys

page = open(sys.argv[1], encoding="utf-8").read()
if re.search(r"<script\b[^>]*\bid=[\"']prove-tickets[\"']", page, re.I):
    sys.stderr.write("publish-s3: page carries an INLINE ticket blob — offline-honest already, nothing declared\n")
    sys.stdout.write(page)
    raise SystemExit(0)

el = '<meta name="prove-tickets" content="">'
pat = r"""<link\b[^>]*\brel=["'][^"']*\bprove-tickets\b[^"']*["'][^>]*>|<meta\b[^>]*\bname=["']prove-tickets["'][^>]*>"""
found = list(re.finditer(pat, page, re.I))
if found:
    # Replace the FIRST (the one the component would take) and drop the rest, so nothing stale wins.
    for m in reversed(found[1:]):
        page = page[:m.start()] + page[m.end():]
    page = page[:found[0].start()] + el + page[found[0].end():]
    where = "replaced a stale ticket-data source with an explicit none"
else:
    head = list(re.finditer(r"</head\s*>", page, re.I))
    if head:
        at, where = head[0].start(), "declared no ticket data before </head>"
    else:
        body = list(re.finditer(r"</body\s*>", page, re.I))
        at, where = (body[-1].start(), "declared no ticket data before </body>") if body else (len(page), "declared no ticket data (appended)")
    page = page[:at] + el + "\n" + page[at:]

sys.stderr.write("publish-s3: %s\n" % where)
sys.stdout.write(page)
PY
  mv "${work}/no-tickets.html" "$upload"
  echo "publish-s3: the page references tickets but no <page>.tickets.json was found — publishing WITHOUT ticket data" >&2
  echo "publish-s3:   refs render as plain links and the page says so; it will NOT try to fetch a sibling that was never uploaded" >&2
  echo "publish-s3:   bake it with: bake-tickets.sh --scan <page> → fetch each key → bake-tickets.sh --emit <page> --tickets <in.json>" >&2
fi

# Upload. cp chatter → stderr; only the URL goes to stdout.
aws s3 cp "$upload" "s3://${PROVE_S3_BUCKET}/${key}" \
  ${profile_arg[@]+"${profile_arg[@]}"} \
  --content-type 'text/html; charset=utf-8' \
  --cache-control 'no-cache' >&2

printf 'https://%s.s3.%s.amazonaws.com/%s\n' "$PROVE_S3_BUCKET" "$region" "$key"
