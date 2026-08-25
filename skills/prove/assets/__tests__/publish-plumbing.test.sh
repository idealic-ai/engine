#!/usr/bin/env bash
# Offline harness for the /prove publish plumbing: publish-kit.sh, publish-s3.sh, bake-tickets.sh.
#
# NO AWS. Every test runs against a fake `aws` shim placed first on PATH that logs its argv to a
# file instead of talking to S3. That is the whole point: the questions worth asking here — does
# publish-kit.sh upload the files a page references, at the right keys, with the right content
# types; does publish-s3.sh resolve the kit token without touching the on-disk source — are all
# answerable from the argv the script WOULD have executed. Requiring real credentials to answer
# them would mean nobody ever runs this.
#
# Run:  ~/.claude/engine/skills/prove/assets/__tests__/publish-plumbing.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"
kitSrc="$HOME/.claude/engine/skills/intake/assets"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()   { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

tmp="$(mktemp -d -t prove-plumbing)"
trap 'rm -rf "$tmp"' EXIT

# --- the shim ---------------------------------------------------------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
# Records argv; never contacts AWS. sts get-caller-identity answers so the per-user key segment
# resolves deterministically instead of falling through to a live call.
printf '%s\n' "$*" >> "$AWS_SHIM_LOG"
case "$*" in
  *"sts get-caller-identity"*) echo "arn:aws:iam::000000000000:user/testuser" ;;
  *"configure export-credentials"*) exit 1 ;;   # force the read-only-config degrade path
  # An EMPTY simulated bucket, said the way real S3 says it: head-object on a missing key is a
  # NON-ZERO exit, and list-objects-v2 on a missing prefix is an empty JSON result. Answering
  # either with "exit 0 and no output" is a shape the CLI never produces, and the publisher is
  # right to treat that as an unreadable answer rather than as "absent".
  *"s3api head-object"*) exit 1 ;;
  *"s3api list-objects-v2"*) echo '{}' ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"

# curl shim. The harness simulates a HEALTHY bucket, so every address under it answers 200; the
# refusal path (a declared address that does not resolve) has its own test below pointing at a
# different host. Baking the failure into the shared shim would instead make every other test in
# this file assert the refusal path by accident, which is what "17 failing, all the same cause"
# looked like before this existed.
cat > "$tmp/bin/curl" <<'CSHIM'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a";; esac; done
case " $* " in
  *" -w "*)
    case "$url" in
      *test-bucket.s3.us-east-9.amazonaws.com*) printf '200' ;;
      *) printf '404' ;;
    esac ;;
esac
exit 0
CSHIM
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"

# Pin config so no project .env can leak in and change the expected keys.
export PROVE_S3_ENV=/nonexistent
export PROVE_S3_BUCKET=test-bucket
export PROVE_S3_REGION=us-east-9
export PROVE_S3_PREFIX=proofs
export PROVE_S3_USER=testuser
unset PROVE_S3_PROFILE

echo "== publish-kit.sh: uploads =="
export AWS_SHIM_LOG="$tmp/kit.log"
: > "$AWS_SHIM_LOG"
if kitBase="$("$assets/publish-kit.sh" "$kitSrc" 2>"$tmp/kit.err")"; then
  ok "publish-kit.sh exits 0 against the real kit dir"
else
  no "publish-kit.sh exits 0" "$(tail -3 "$tmp/kit.err")"
fi
log="$(cat "$AWS_SHIM_LOG")"

# The versions are read from source, so the expected keys are derived the same way rather than
# hardcoded — a test that hardcodes v3 starts failing the day the component legitimately bumps.
tv="$(grep -oE 'PROOF_TICKET_VERSION[[:space:]]*=[[:space:]]*[0-9]+' "$kitSrc/proof-ticket.js" | grep -oE '[0-9]+' | head -1)"
sv="$(grep -oE 'SCHEMA_VERSION[[:space:]]*=[[:space:]]*[0-9]+' "$kitSrc/board-widgets.js" | grep -oE '[0-9]+' | head -1)"
for expect in \
  "board-widgets.v${sv}.js" "board-widgets.v${sv}.css" "board-warm-overrides.v${sv}.css" \
  "proof-theme.v2.css" "proof-ticket.v${tv}.js" \
  "proof-ticket.v${tv}.css" "proof-blocks.v2.css" "kit-behaviors.v1.js"
do
  if have "$log" "s3://test-bucket/proofs/kit/${expect}"; then ok "uploads $expect"
  else no "uploads $expect" "not in the shim log"; fi
done

# The three new objects must carry the same content-type discipline as the five that existed.
newCss=0; newJs=0
while IFS= read -r line; do
  case "$line" in
    *proof-ticket.v*.css*|*proof-blocks.v*.css*) have "$line" "text/css; charset=utf-8" && newCss=$((newCss+1)) ;;
    *kit-behaviors.v*.js*) have "$line" "text/javascript; charset=utf-8" && newJs=$((newJs+1)) ;;
  esac
done < "$AWS_SHIM_LOG"
# Each asset publishes at TWO addresses — the mutable version alias and the immutable content
# address — so two stylesheets are four uploads and one script is two. Counting one-per-asset here
# is what this assertion did before dual addressing existed.
[ "$newCss" = 4 ] && ok "both new stylesheets carry text/css; charset=utf-8 (alias + CAS)" \
                  || no "new stylesheet content-types" "matched $newCss of 4"
[ "$newJs" = 2 ] && ok "kit-behaviors.js carries text/javascript; charset=utf-8 (alias + CAS)" \
                 || no "kit-behaviors.js content-type" "matched $newJs of 2"

cacheMisses="$(grep -c 's3 cp' "$AWS_SHIM_LOG")"
cacheHits="$(grep -c "cache-control no-cache" "$AWS_SHIM_LOG")"
[ "$cacheMisses" = "$cacheHits" ] && ok "every upload sets --cache-control no-cache ($cacheHits/$cacheMisses)" \
  || no "cache-control on every upload" "$cacheHits of $cacheMisses"

[ "$kitBase" = "https://test-bucket.s3.us-east-9.amazonaws.com/proofs/kit" ] \
  && ok "stdout is the kit base url only" \
  || no "stdout is the kit base url only" "got: $kitBase"

echo "== publish-kit.sh: fail-loud on a missing file =="
mkdir -p "$tmp/partial"
# Everything the kit table names EXCEPT kit-behaviors.js. Derived from the table rather than
# hand-listed, so an asset added to the kit cannot make this test fail on the WRONG missing file —
# which is exactly what happened when proof-creative.css and proof-module.css joined the table.
sed -n '/^KIT_TABLE=/,/^.$/p' "$assets/kit-manifest.sh" | cut -d'|' -f1 | grep -E '\.(css|js)$' \
  | grep -v '^kit-behaviors\.js$' | sort -u | while IFS= read -r f; do
  [ -f "$kitSrc/$f" ] && cp "$kitSrc/$f" "$tmp/partial/$f"
done
cp "$kitSrc"/proof-icons.v*.woff2 "$tmp/partial/" 2>/dev/null || true
export AWS_SHIM_LOG="$tmp/partial.log"; : > "$AWS_SHIM_LOG"
if "$assets/publish-kit.sh" "$tmp/partial" >/dev/null 2>"$tmp/partial.err"; then
  no "missing kit-behaviors.js is fatal" "publish-kit.sh exited 0 with the file absent"
else
  grep -q 'kit-behaviors.js not found' "$tmp/partial.err" \
    && ok "missing kit-behaviors.js is fatal, and says which file" \
    || no "missing-file message names the file" "$(tail -1 "$tmp/partial.err")"
fi

echo "== publish-s3.sh: __FB_KIT_BASE__ substitution =="
mkdir -p "$tmp/builds"
src="$tmp/builds/sample-proof.html"
cat > "$src" <<'HTML'
<!doctype html><html><head>
<link rel="stylesheet" href="__FB_KIT_BASE__/proof-theme.v2.css">
<link rel="stylesheet" href="__FB_KIT_BASE__/proof-blocks.v2.css">
<script defer src="__FB_KIT_BASE__/kit-behaviors.v1.js"></script>
</head><body><p>Fixed in FIN-3566.</p></body></html>
HTML
before="$(shasum "$src" | cut -d' ' -f1)"
export AWS_SHIM_LOG="$tmp/s3.log"; : > "$AWS_SHIM_LOG"
url="$("$assets/publish-s3.sh" "$src" 2>"$tmp/s3.err")"
after="$(shasum "$src" | cut -d' ' -f1)"

[ "$before" = "$after" ] && ok "the builds/ source file is byte-identical after publish" \
  || no "builds/ source is not mutated" "sha changed $before -> $after"
grep -q '__FB_KIT_BASE__' "$src" && ok "the on-disk source KEEPS the unresolved token" \
  || no "source keeps the token" "the token was burned into builds/"
case "$url" in
  https://test-bucket.s3.us-east-9.amazonaws.com/proofs/testuser/sample-proof-*.html)
    ok "stdout is the unguessable per-user proof URL only" ;;
  *) no "stdout is the proof URL only" "got: $url" ;;
esac
grep -q 'kit reference resolved' "$tmp/s3.err" \
  && ok "substitution is announced on stderr, not stdout" \
  || no "substitution announced on stderr" "$(tail -2 "$tmp/s3.err")"
have "$(cat "$AWS_SHIM_LOG")" "content-type text/html; charset=utf-8" \
  && ok "the upload sets --content-type text/html; charset=utf-8" \
  || no "html content-type" "not in the shim log"

echo "== publish-s3.sh: the transformed output actually resolves =="
# Re-run with a shim that KEEPS the uploaded bytes, so the substitution is proved on content and
# not merely on a log line.
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_SHIM_LOG"
case "$*" in
  *"sts get-caller-identity"*) echo "arn:aws:iam::000000000000:user/testuser" ;;
  *"configure export-credentials"*) exit 1 ;;
  *"s3 cp"*) set -- $*; [ -f "$3" ] && cp "$3" "$CAPTURE" ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"
export CAPTURE="$tmp/uploaded.html"
export AWS_SHIM_LOG="$tmp/s3b.log"; : > "$AWS_SHIM_LOG"
"$assets/publish-s3.sh" "$src" >/dev/null 2>>"$tmp/s3.err"
if [ -f "$CAPTURE" ]; then
  grep -q '__FB_KIT_BASE__' "$CAPTURE" \
    && no "uploaded bytes carry no token" "the token survived into the uploaded page" \
    || ok "the uploaded bytes carry NO unresolved token"
  grep -q 'https://test-bucket.s3.us-east-9.amazonaws.com/proofs/kit/proof-blocks.v2.css' "$CAPTURE" \
    && ok "the token resolved to the real kit base url" \
    || no "token resolved to the kit base" "expected href not found in the uploaded page"
else
  no "the uploaded page was captured" "shim never saw an s3 cp with a readable source"
fi

echo "== publish-s3.sh: the write grant is gated on DECISION MARKUP, not on the kit reference =="
# The regression this locks: every /prove page now references the kit, so a gate that keyed on
# __FB_KIT_BASE__ handed a week-long presigned write grant to read-only evidence pages. $src above
# is exactly that page — kit refs, zero decision markup.
grep -q 'no decision markup' "$tmp/s3.err" \
  && ok "a read-only proof that links the kit gets NO state config and says so" \
  || no "read-only proof gets no config" "$(tail -3 "$tmp/s3.err")"
grep -q 'state config injected' "$tmp/s3.err" \
  && no "read-only proof gets no config" "a state config was injected into a page with nothing to submit" \
  || ok "no state config element reached the read-only page"
grep -q 'prove-state-config' "$CAPTURE" \
  && no "no config element in the uploaded bytes" "the uploaded read-only page carries a state config" \
  || ok "the uploaded read-only bytes carry no state config at all"

# …and the other direction: a page that DOES collect decisions must still get one, from either
# consumer's markup. Both are asserted, because the two halves of the system mark up differently.
mkdir -p "$tmp/dec"
printf '%s\n' '<!doctype html><html><head></head><body><div data-fb-item="a" data-fb-voter="rm">x</div></body></html>' > "$tmp/dec/board.html"
printf '%s\n' '<!doctype html><html><head></head><body><section data-decision-item><button class="submitbtn" data-submit="rm">go</button></section></body></html>' > "$tmp/dec/proof.html"
for f in board proof; do
  export AWS_SHIM_LOG="$tmp/dec-$f.log"; : > "$AWS_SHIM_LOG"
  export CAPTURE="$tmp/dec/$f-up.html"
  "$assets/publish-s3.sh" "$tmp/dec/$f.html" >/dev/null 2>"$tmp/dec/$f.err"
  grep -q 'state config injected' "$tmp/dec/$f.err" \
    && ok "a page with $f decision markup still gets a state config" \
    || no "$f decision markup still gates in" "$(tail -2 "$tmp/dec/$f.err")"
  grep -q 'data-fb-state-config' "$tmp/dec/$f-up.html" \
    && ok "the $f page's uploaded bytes carry the config element the kit reads" \
    || no "$f config element present" "not in the uploaded bytes"
  grep -q 'submitDisabledReason' "$tmp/dec/$f-up.html" \
    && ok "the $f page degrades read-only (with a reason) when signing fails" \
    || no "$f read-only degrade" "no submitDisabledReason in a config minted with no credential"
done

# The injected element must not become its own qualification: republishing an already-published
# page must not gate in on the data-fb-state-config THIS SCRIPT wrote last time.
printf '%s\n' '<!doctype html><html><head></head><body><p>read only</p><script id="prove-state-config" data-fb-state-config type="application/json">{}</script></body></html>' > "$tmp/dec/republish.html"
export AWS_SHIM_LOG="$tmp/dec-re.log"; : > "$AWS_SHIM_LOG"
export CAPTURE="$tmp/dec/re-up.html"
"$assets/publish-s3.sh" "$tmp/dec/republish.html" >/dev/null 2>"$tmp/dec/re.err"
grep -q 'state config injected' "$tmp/dec/re.err" \
  && no "an injected config does not self-qualify" "republishing gated in on its own previous config element" \
  || ok "a previously-injected config element does NOT self-qualify a read-only page"

echo "== bake-tickets.sh: --scan =="
scanSrc="$tmp/scan.html"
cat > "$scanSrc" <<'HTML'
<!doctype html><html><head><title>FIN-3566 proof</title></head><body>
<p>Fixed in FIN-3566, follow-up FIN-3520, and again FIN-3566 (dup).</p>
<p>See <a href="https://linear.app/finchclaims/issue/FIN-9999">the ticket</a>.</p>
<script id="prove-tickets" type="application/json">{"tickets":{"FIN-7777":{}}}</script>
<script>var x = "FIN-8888";</script>
</body></html>
HTML
keys="$("$assets/bake-tickets.sh" --scan "$scanSrc" 2>/dev/null)"
[ "$keys" = "FIN-3520
FIN-3566" ] && ok "--scan dedups, sorts numerically, and finds only the page's own keys" \
  || no "--scan key list" "got: $(echo "$keys" | tr '\n' ' ')"
echo "$keys" | grep -q 'FIN-9999' && no "--scan skips URL-embedded keys" "FIN-9999 leaked" \
  || ok "--scan skips a key that sits inside a URL"
echo "$keys" | grep -qE 'FIN-(7777|8888)' \
  && no "--scan ignores <script> content" "a key from a script block leaked" \
  || ok "--scan ignores <script> content (incl. an existing prove-tickets blob)"
jsonKeys="$("$assets/bake-tickets.sh" --scan "$scanSrc" --json 2>/dev/null)"
[ "$jsonKeys" = '["FIN-3520", "FIN-3566"]' ] && ok "--scan --json emits a JSON array" \
  || no "--scan --json" "got: $jsonKeys"

echo "== bake-tickets.sh: --inject =="
cat > "$tmp/tickets.json" <<'JSON'
{ "bakedAt": "2026-07-31T12:00:00Z",
  "tickets": {
    "FIN-3566": { "title": "Decision layer </script> in the title",
      "status": "In Progress", "statusType": "started", "priority": "Medium",
      "assignee": "yf", "project": "Prove", "url": "https://linear.app/finchclaims/issue/FIN-3566",
      "updatedAt": "2026-07-30T18:24:00Z", "lastActivityAt": "2026-07-30T18:24:00Z",
      "description": "snippet",
      "relations": [ { "key": "FIN-3520", "type": "related", "title": "t" } ],
      "activity": [ {"author":"yf","ts":"2026-07-30T18:24:00Z","kind":"comment","text":"a"},
                    {"author":"yf","ts":"2026-07-30T18:23:00Z","kind":"state","text":"b"},
                    {"author":"yf","ts":"2026-07-30T18:22:00Z","kind":"comment","text":"c"},
                    {"author":"yf","ts":"2026-07-30T18:21:00Z","kind":"comment","text":"d"},
                    {"author":"yf","ts":"2026-07-30T18:20:00Z","kind":"comment","text":"e"},
                    {"author":"yf","ts":"2026-07-30T18:19:00Z","kind":"comment","text":"OVERFLOW"} ] },
    "FIN-3520": { "title": "sibling", "status": "Todo", "statusType": "nonsense",
      "url": "https://linear.app/finchclaims/issue/FIN-3520" },
    "NOT-A-KEY": { "title": "dropped" }
  } }
JSON
baked="$tmp/baked.html"
"$assets/bake-tickets.sh" --inject "$scanSrc" --tickets "$tmp/tickets.json" --out "$baked" \
  2>"$tmp/bake.err"

python3 - "$baked" <<'PY' && ok "the injected blob parses as the KIT_README §2b contract" || no "injected blob parses" "see stderr"
import json, re, sys
p = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<script id="prove-tickets" type="application/json">(.*?)</script>', p, re.S)
assert m, "no #prove-tickets element in the output"
d = json.loads(m.group(1).replace("<\\/", "</"))
assert d["bakedAt"] == "2026-07-31T12:00:00Z", d["bakedAt"]
assert set(d["tickets"]) == {"FIN-3566", "FIN-3520"}, set(d["tickets"])
assert len(d["tickets"]["FIN-3566"]["activity"]) == 5, "activity was not capped at 5"
assert "OVERFLOW" not in m.group(1), "the trimmed 6th activity event survived"
PY

grep -c 'id="prove-tickets"' "$baked" | grep -qx 1 \
  && ok "--inject REPLACED the page's existing blob (exactly one remains)" \
  || no "exactly one blob" "found $(grep -c 'id="prove-tickets"' "$baked")"
python3 -c '
import re,sys
p=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r"<script id=\"prove-tickets\"[^>]*>(.*?)</script>",p,re.S)
sys.exit(0 if not re.search(r"</\s*script",m.group(1),re.I) else 1)' "$baked" \
  && ok "a literal </script> in a ticket title is escaped inside the blob" \
  || no "</script> escaping" "the blob can close its own element"
grep -q 'dropping .NOT-A-KEY' "$tmp/bake.err" && ok "a non-FIN key is dropped with a warning" \
  || no "non-FIN key dropped" "$(cat "$tmp/bake.err")"
grep -q "statusType 'nonsense' is outside the pill vocabulary" "$tmp/bake.err" \
  && ok "an out-of-vocabulary statusType warns (and still bakes)" \
  || no "statusType warning" "$(cat "$tmp/bake.err")"

echo "== bake-tickets.sh: round-trip + idempotency =="
"$assets/bake-tickets.sh" --inject "$baked" --tickets "$tmp/tickets.json" --out "$tmp/baked2.html" 2>/dev/null
cmp -s "$baked" "$tmp/baked2.html" && ok "re-baking the same tickets is a no-op (idempotent)" \
  || no "idempotent re-bake" "the second bake changed the page"
rescan="$("$assets/bake-tickets.sh" --scan "$baked" 2>/dev/null)"
[ "$rescan" = "$keys" ] && ok "re-scanning a baked page yields the SAME key list (no blob feedback)" \
  || no "re-scan is stable" "got: $(echo "$rescan" | tr '\n' ' ')"

echo "== bake-tickets.sh: fail-loud =="
"$assets/bake-tickets.sh" --inject /nonexistent/page.html --tickets "$tmp/tickets.json" >/dev/null 2>&1 \
  && no "missing page is fatal" "exited 0" || ok "a missing input page is fatal"
echo '{}' | "$assets/bake-tickets.sh" --inject "$scanSrc" --tickets - --out - >/dev/null 2>&1 \
  && no "empty ticket set is fatal" "exited 0" || ok "an empty ticket set refuses to bake"
echo 'not json' | "$assets/bake-tickets.sh" --inject "$scanSrc" --tickets - --out - >/dev/null 2>&1 \
  && no "unparseable json is fatal" "exited 0" || ok "unparseable tickets json is fatal"

printf '\n%s\n' "-------------------------------------"
printf 'passed %d   failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
