#!/usr/bin/env bash
# Bake Linear ticket metadata for a /prove page — as a SIBLING tickets.json (the published path)
# and/or as the inline <script id="prove-tickets"> blob (the offline path).
#
# Usage:
#   bake-tickets.sh --scan   <page.html> [--json]
#   bake-tickets.sh --emit   <page.html> [--tickets <in.json>|-] [--out <tickets.json>|-]
#   bake-tickets.sh --inject <page.html> [--tickets <in.json>|-] [--out <path>|-]
#
# WHY THIS IS THREE MODES AND NOT ONE COMMAND.
# proof-ticket.js NEVER calls the TRACKER from a browser — that is a hard design gate, not an
# optimisation (a shared S3 page has no credential and no CORS route to Linear, and a component
# that called it would leak the reader's identity to the tracker). It does, since v4, fetch ONE
# thing: its own ticket-data JSON, published beside it on the same bucket. Either way something at
# publish time has to ASSEMBLE that metadata, and that something is an MCP call to the Linear
# server, which a shell script cannot make. Pretending otherwise — shelling out to a `linear` CLI
# that is not installed, or worse, emitting plausible-looking metadata — would produce a page that
# LOOKS baked and states wrong statuses, which is the one failure mode a proof page must never have.
#
# So this script owns the mechanical halves and leaves the tracker call to the orchestrator:
#
#   --scan    reads the page, emits the deduped FIN keys it mentions (one per line, or --json).
#             The ORCHESTRATOR then fetches each via §CMD_READ_RELATED_TICKET (get_issue +
#             list_comments) and normalises to the entry shape below.
#   --emit    validates that map and writes a standalone <page-stem>.tickets.json — the artifact
#             publish-s3.sh uploads BESIDE the page and the component fetches at read time (same
#             bucket ⇒ same-origin for the canonical copy). ONE json can serve MANY pages.
#   --inject  writes the same payload INTO the page as an inline blob. Still supported and still
#             the right tool for one job: the component prefers an inline blob over any fetch, so
#             an injected page reads correctly OFFLINE — saved to disk, mailed as an attachment,
#             opened over file://. Use --inject for the local builds/ artifact, --emit for the
#             published one. They are two audiences, not two alternatives; running both is normal.
#
# THE BAKED CONTRACT (authoritative copy: intake/assets/KIT_README.md §2b — this is a restatement
# for the operator's convenience; if the two ever disagree, KIT_README.md wins):
#   { "bakedAt": "<ISO8601>",
#     "tickets": {
#       "FIN-3519": {
#         "title": …, "status": "In Progress", "statusType": "started",
#         "priority": …, "assignee": …, "project": …,
#         "url": "https://linear.app/finchclaims/issue/FIN-3519",
#         "updatedAt": …, "lastActivityAt": …,      // lastActivityAt drives freshness
#         "description": "…trimmed snippet…",
#         "relations": [ { "key": …, "type": …, "title": … } ],
#         "activity":  [ { "author": …, "ts": …, "kind": "comment"|"state", "text": … } ]
#       } } }
#   lastActivityAt = max(updatedAt, newest comment ts). activity = the NEWEST 5 events only, each
#   text trimmed. statusType ∈ started|completed|canceled|backlog|unstarted|triage.
#
# Degradation is the component's job, not this script's: absent data, an unknown key, or a
# {title,status}-only entry all still render a working link. So both write modes VALIDATE loudly
# and WARN rather than refusing on a thin entry — a partial bake beats no bake. They are fatal only
# on things the browser would swallow in silence (unparseable JSON, a blob that could close its own
# <script>, a file they cannot write).
#
# Idempotent by construction: --inject REPLACES an existing #prove-tickets blob rather than adding
# a second one (two blobs and getElementById picks the first — the stale one — forever). --emit
# overwrites its output file wholesale for the same reason.
set -euo pipefail

self="$(basename "$0")"
usage() {
  echo "usage: $self --scan   <page.html> [--json]" >&2
  echo "       $self --emit   <page.html> [--tickets <in.json>|-] [--out <tickets.json>|-]" >&2
  echo "       $self --inject <page.html> [--tickets <in.json>|-] [--out <path>|-]" >&2
  exit 2
}

mode=""
page=""
ticketsPath="-"
outPath=""
asJson=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scan)    mode="scan";   page="${2:-}"; [ -n "$page" ] || usage; shift 2 ;;
    --emit)    mode="emit";   page="${2:-}"; [ -n "$page" ] || usage; shift 2 ;;
    --inject)  mode="inject"; page="${2:-}"; [ -n "$page" ] || usage; shift 2 ;;
    --tickets) ticketsPath="${2:?--tickets needs a path or -}"; shift 2 ;;
    --out)     outPath="${2:?--out needs a path or -}"; shift 2 ;;
    --json)    asJson=1; shift ;;
    -h|--help) usage ;;
    *)         echo "$self: unknown argument: $1" >&2; usage ;;
  esac
done

[ -n "$mode" ] || usage
[ -f "$page" ] || { echo "$self: page not found: $page" >&2; exit 1; }

if [ "$mode" = "scan" ]; then
  AS_JSON="$asJson" python3 - "$page" <<'PY'
import json, os, re, sys

page = open(sys.argv[1], encoding="utf-8").read()

# Strip what is never rendered before scanning. <script> matters most: a re-scan of an
# already-baked page would otherwise harvest every relation key out of our own blob and grow the
# fetch list on each run. <style>/<textarea>/comments are stripped for the same reason the
# component's SKIP_TAGS holds them — nothing there is a reader-visible ticket reference.
for tag in ("script", "style", "textarea"):
    page = re.sub(r"<%s\b[^>]*>.*?</%s\s*>" % (tag, tag), " ", page, flags=re.I | re.S)

# The scan must mirror the component's SKIP_TAGS exactly, or it bakes entries nothing can read.
# <a>, <code> and <pre> are the ones that bite: a key hand-written as its own anchor —
# <a href="…/issue/FIN-2226">FIN-2226</a> — is skipped by the scanner at render time, so it never
# becomes a chip and metadata fetched for it is dead weight in a blob that ships inline in every
# byte of the page. Counted rather than silently dropped: a key that can never render is an
# AUTHORING defect the author should hear about, not a saving to pocket quietly.
skipped = []
def _bank(m):
    skipped.extend(re.findall(r"\bFIN-\d+\b", m.group(0)))
    return " "
for tag in ("a", "code", "pre"):
    page = re.sub(r"<%s\b[^>]*>.*?</%s\s*>" % (tag, tag), _bank, page, flags=re.I | re.S)
page = re.sub(r"<!--.*?-->", " ", page, flags=re.S)

KEY = re.compile(r"\bFIN-\d+\b")

def in_url(text, at):
    """True when the key sits inside a URL (…/issue/FIN-3519). The key's own permalink is not a
    reference TO the ticket that needs metadata — the anchor already carries it, and the component
    skips <a> anyway. Detected by walking back over the unbroken run of URL-ish characters and
    asking whether it contains a scheme."""
    i = at
    while i > 0 and text[i - 1] not in " \t\r\n\"'<>()[]{}`":
        i -= 1
    return "://" in text[i:at]

seen = []
for m in KEY.finditer(page):
    if in_url(page, m.start()):
        continue
    if m.group(0) not in seen:
        seen.append(m.group(0))

# Numeric sort, so a re-run of the same page emits the same list in the same order and a diff of
# two scans is readable.
seen.sort(key=lambda k: int(k.split("-")[1]))

if os.environ.get("AS_JSON") == "1":
    print(json.dumps(seen))
else:
    for k in seen:
        print(k)
sys.stderr.write("bake-tickets: %d distinct ticket key(s) to fetch\n" % len(seen))

# Report, don't hide. A key living only inside <a>/<code>/<pre> renders as a plain link forever,
# however faithfully the bake runs — the fix is in the markup, not here.
unreachable = sorted({k for k in skipped if k not in seen}, key=lambda k: int(k.split("-")[1]))
if unreachable:
    sys.stderr.write(
        "bake-tickets: %d key(s) appear ONLY inside <a>/<code>/<pre> and can never render as a "
        "chip — the component skips those tags. Write them as bare text to fix: %s\n"
        % (len(unreachable), " ".join(unreachable)))
PY
  exit 0
fi

# ------------------------------------------------------- emit / inject (shared validation)
if [ "$ticketsPath" != "-" ] && [ ! -f "$ticketsPath" ]; then
  echo "$self: tickets json not found: $ticketsPath" >&2
  exit 1
fi

work="$(mktemp -d -t bake-tickets)"
trap 'rm -rf "$work"' EXIT

if [ "$ticketsPath" = "-" ]; then
  cat > "$work/tickets.json"
else
  cp "$ticketsPath" "$work/tickets.json"
fi

# ONE validator for both write modes. Splitting it would let the published sibling and the offline
# blob drift into disagreeing about the same tickets, which is the exact class of bug the whole
# "one mechanism, not two" decision exists to avoid.
MODE="$mode" python3 - "$page" "$work/tickets.json" > "$work/out" <<'PY'
import datetime, json, os, re, sys

MODE = os.environ.get("MODE", "inject")
pagePath, ticketsPath = sys.argv[1], sys.argv[2]
page = open(pagePath, encoding="utf-8").read()
raw = open(ticketsPath, encoding="utf-8").read().strip()

def die(msg):
    sys.stderr.write("bake-tickets: %s\n" % msg)
    sys.exit(1)

def warn(msg):
    sys.stderr.write("bake-tickets: warning — %s\n" % msg)

if not raw:
    die("tickets json is empty — nothing to bake (omit the bake instead of writing an empty blob)")
try:
    doc = json.loads(raw)
except ValueError as e:
    die("tickets json does not parse (%s)" % e)
if not isinstance(doc, dict):
    die("tickets json must be an object")

# Accept both the full envelope and a bare key→entry map: the orchestrator assembles the map one
# get_issue at a time, and making it hand-write the wrapper is a step that exists only to be
# forgotten. Which one was read is announced, so a malformed envelope cannot pass as a bare map.
if "tickets" in doc and isinstance(doc["tickets"], dict):
    tickets = doc["tickets"]
    bakedAt = doc.get("bakedAt")
else:
    tickets = doc
    bakedAt = None
    sys.stderr.write("bake-tickets: input read as a bare key→entry map; wrapping it\n")

if not bakedAt:
    # bakedAt is the reference time every freshness bucket is measured against. Absent, the
    # component cannot age anything and every dot reads `unknown` — so it is filled, not omitted.
    bakedAt = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    sys.stderr.write("bake-tickets: no bakedAt supplied — stamping %s\n" % bakedAt)

KEY = re.compile(r"^FIN-\d+$")
STATUS_TYPES = {"started", "completed", "canceled", "backlog", "unstarted", "triage"}
ACTIVITY_CAP = 5

clean = {}
for key, entry in tickets.items():
    if not KEY.match(key):
        warn("dropping %r — not a FIN-<n> key" % key)
        continue
    if not isinstance(entry, dict):
        warn("dropping %s — entry is not an object" % key)
        continue
    if not entry.get("title"):
        warn("%s has no title — the card will render key-only" % key)
    if not entry.get("url"):
        warn("%s has no url — the inline ref falls back to the tracker default" % key)
    st = entry.get("statusType")
    if st is not None and st not in STATUS_TYPES:
        warn("%s statusType %r is outside the pill vocabulary — it will fall back to the base pill"
             % (key, st))
    if not entry.get("lastActivityAt") and not entry.get("updatedAt"):
        warn("%s carries no date — its freshness dot will read `unknown`" % key)
    act = entry.get("activity")
    if isinstance(act, list) and len(act) > ACTIVITY_CAP:
        # The component caps rendering at 5 anyway; trimming HERE is what keeps the blob — which
        # ships inline in every byte of the page — from carrying a full comment thread per ticket.
        warn("%s activity trimmed %d → %d" % (key, len(act), ACTIVITY_CAP))
        entry = dict(entry, activity=act[:ACTIVITY_CAP])
    clean[key] = entry

if not clean:
    die("no valid ticket entries survived validation — refusing to bake an empty blob")

# Cross-check against the page, in BOTH modes. A key the page never mentions is dead weight the
# reader pays for; a key the page mentions and the bake omits renders as a bare link forever with
# nothing anywhere saying why. Neither is fatal (a shared json legitimately covers several pages),
# but neither should be silent either.
try:
    body = page
    for tag in ("script", "style", "textarea"):
        body = re.sub(r"<%s\b[^>]*>.*?</%s\s*>" % (tag, tag), " ", body, flags=re.I | re.S)
    onPage = set(re.findall(r"\bFIN-\d+\b", body))
    extra = sorted(set(clean) - onPage, key=lambda k: int(k.split("-")[1]))
    missing = sorted(onPage - set(clean), key=lambda k: int(k.split("-")[1]))
    if extra:
        warn("%d baked key(s) are not mentioned by %s — fine for a SHARED json, dead weight for a "
             "per-page one: %s" % (len(extra), os.path.basename(pagePath), " ".join(extra)))
    if missing:
        warn("%d key(s) on the page have NO entry and will render as bare links: %s"
             % (len(missing), " ".join(missing)))
except Exception:
    pass

envelope = {"bakedAt": bakedAt, "tickets": clean}

if MODE == "emit":
    # A standalone .json file, so none of the <script>-context escaping below applies — and must
    # not be applied: `<\/` is valid JSON but would put a stray backslash into every url the
    # component then renders. This is why emit returns here rather than sharing the blob path.
    sys.stderr.write("bake-tickets: %d ticket(s) emitted, bakedAt %s\n" % (len(clean), bakedAt))
    sys.stdout.write(json.dumps(envelope, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
    sys.exit(0)

blob = json.dumps(envelope, ensure_ascii=False)
# The blob is JSON living inside a <script> element, where the HTML parser — not the JSON parser —
# reads first: a literal </script> anywhere in any string (a title quoting markup, a pasted log)
# terminates the element early and shreds the rest of the page. Splitting every `</` is the same
# guard publish-s3.sh uses on the state config, and is invisible to JSON.parse.
blob = blob.replace("</", "<\\/")
if re.search(r"</\s*script", blob, re.I):
    die("blob still contains a literal </script after escaping — refusing to write a page that "
        "would truncate itself")

el = ('<script id="prove-tickets" type="application/json">\n' + blob + "\n</script>")

existing = re.search(
    r"<script\b[^>]*\bid=[\"']prove-tickets[\"'][^>]*>.*?</script\s*>", page, re.I | re.S)
if existing:
    # REPLACE, never append. getElementById returns the FIRST match, so a second blob means the
    # page keeps serving the stale one and every re-bake silently does nothing.
    page = page[:existing.start()] + el + page[existing.end():]
    where = "replaced the existing blob"
else:
    head = list(re.finditer(r"</head\s*>", page, re.I))
    body = list(re.finditer(r"</body\s*>", page, re.I))
    if head:
        at = head[0].start()
        where = "inserted before </head>"
    elif body:
        at = body[-1].start()
        where = "inserted before </body>"
    else:
        at = len(page)
        where = "appended (page has neither </head> nor </body>)"
    page = page[:at] + el + "\n" + page[at:]

sys.stderr.write("bake-tickets: %d ticket(s) baked, %s\n" % (len(clean), where))
sys.stdout.write(page)
PY

if [ "$mode" = "emit" ]; then
  if [ "$outPath" = "-" ]; then
    cat "$work/out"
  else
    # The default is the sibling key the COMPONENT derives on its own (page.html →
    # page.tickets.json). Defaulting to anything else would mean every publish had to pass --out
    # correctly or ship a page whose convention fallback points at a file that is not there.
    dest="$outPath"
    [ -n "$dest" ] || dest="$(printf '%s' "$page" | sed -E 's/\.html?$//').tickets.json"
    cat "$work/out" > "$dest"
    echo "bake-tickets: wrote $dest" >&2
    echo "bake-tickets: publish-s3.sh uploads this beside the page and injects the absolute <link rel=\"prove-tickets\">" >&2
  fi
  exit 0
fi

if [ "$outPath" = "-" ]; then
  cat "$work/out"
elif [ -n "$outPath" ]; then
  cat "$work/out" > "$outPath"
  echo "bake-tickets: wrote $outPath" >&2
else
  # In place. Unlike the kit base URL — which is publish-environment-specific and must never be
  # burned into builds/ — the baked blob IS durable page content: it is what makes the page
  # readable offline, so the local artifact should carry it.
  cat "$work/out" > "$page"
  echo "bake-tickets: updated $page in place" >&2
fi
