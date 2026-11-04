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
# The kit in THIS tree, not the installed one: a kit file added in a branch is otherwise checked
# against an install that does not have it yet. KIT_SRC points it elsewhere on purpose.
kitSrc="${KIT_SRC:-$(cd "$here/../../../intake/assets" && pwd)}"

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
      *test-bucket.s3.us-east-9.amazonaws.com*|http://127.0.0.1:9440/proofs/*) printf '200' ;;
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
export PROVE_S3_ENDPOINT=aws   # the manifest defaults to the local MinIO; these cases pin AWS S3
unset PROVE_S3_PROFILE PROVE_S3_PUBLIC_BASE

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

echo "== publish-s3.sh: local MinIO defaults =="
# No bucket/endpoint/user in the environment: the prove manifest defaults must route the publish to
# the local MinIO, path-style, with the dev credentials and the login name as the user segment.
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
printf '%s|AK=%s|SK=%s\n' "$*" "${AWS_ACCESS_KEY_ID:-}" "${AWS_SECRET_ACCESS_KEY:-}" >> "$AWS_SHIM_LOG"
case "$*" in
  *"sts get-caller-identity"*) echo "arn:aws:iam::000000000000:user/should-not-be-asked" ;;
  *"s3api head-object"*|*"s3api get-object"*) exit 1 ;;
  *"s3api list-objects-v2"*) echo '{}' ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"
export AWS_SHIM_LOG="$tmp/minio.log"; : > "$AWS_SHIM_LOG"
# The MinIO login comes from the kit's own variables, here set to test values: never a literal.
localUrl="$(KIT_PROOFS_MINIO_USER=kit-user-under-test KIT_PROOFS_MINIO_PASSWORD=kit-pass-under-test \
  env -u PROVE_S3_BUCKET -u PROVE_S3_REGION -u PROVE_S3_ENDPOINT -u PROVE_S3_USER -u AWS_PROFILE \
  -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY "$assets/publish-s3.sh" "$src" 2>"$tmp/minio.err")"
me="$(printf "%s" "$(id -un)" | tr -c "A-Za-z0-9._-" "-")"
case "$localUrl" in
  "http://127.0.0.1:9440/proofs/proofs/${me}/sample-proof-"*.html) ok "default publish URL is path-style on the local MinIO, user = id -un" ;;
  *) no "local MinIO URL" "got: $localUrl ($(tail -2 "$tmp/minio.err"))" ;;
esac
grep -q -- '--endpoint-url http://127.0.0.1:9440' "$AWS_SHIM_LOG" \
  && ok "the upload is sent to the MinIO endpoint" || no "endpoint-url on upload" "$(head -2 "$AWS_SHIM_LOG")"
grep -q 'AK=kit-user-under-test|SK=kit-pass-under-test' "$AWS_SHIM_LOG" \
  && ok "unset AWS credentials take the kit's KIT_PROOFS_MINIO_* login" || no "kit MinIO login used" "$(head -2 "$AWS_SHIM_LOG")"
grep -q 'no credentials for the local store' "$tmp/minio.err" \
  && no "no missing-login warning when the kit login is set" "$(cat "$tmp/minio.err")" \
  || ok "no missing-login warning when the kit login is set"
# Control: nothing set anywhere -> no login is invented, and the warning names the variables to set.
export AWS_SHIM_LOG="$tmp/minio-none.log"; : > "$AWS_SHIM_LOG"
env -u PROVE_S3_BUCKET -u PROVE_S3_ENDPOINT -u PROVE_S3_USER -u AWS_PROFILE -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY -u KIT_PROOFS_MINIO_USER -u KIT_PROOFS_MINIO_PASSWORD \
  "$assets/publish-s3.sh" "$src" >/dev/null 2>"$tmp/minio-none.err"
if ! grep -q 's3 cp' "$AWS_SHIM_LOG"; then
  no "no login is invented when none is set" "the upload never reached the aws shim"
elif grep 's3 cp' "$AWS_SHIM_LOG" | grep -qv '|AK=|SK=$'; then
  no "no login is invented when none is set" "$(grep 's3 cp' "$AWS_SHIM_LOG" | head -1)"
else
  ok "no login is invented when none is set (the upload sees empty keys)"
fi
grep -q 'KIT_PROOFS_MINIO_USER and KIT_PROOFS_MINIO_PASSWORD' "$tmp/minio-none.err" \
  && ok "a missing login is named, with the variables to set" || no "missing-login message" "$(cat "$tmp/minio-none.err")"
# Plant: the retired dev password must never come back into this skill. Pattern split so this file
# does not match itself.
retired="kitminio""-dev-secret"
if grep -rlF -- "$retired" "$assets/.." >/dev/null 2>&1; then
  no "the retired MinIO dev password is not committed in skills/prove" "$(grep -rlF -- "$retired" "$assets/..")"
else
  ok "the retired MinIO dev password is not committed in skills/prove"
fi
grep -q -- '--profile' "$AWS_SHIM_LOG" && no "no AWS profile on a local publish" "a --profile reached the aws CLI" \
  || ok "no AWS profile is passed for the local MinIO"
grep -q 'sts get-caller-identity' "$AWS_SHIM_LOG" && no "no STS lookup on a local publish" "sts was called" \
  || ok "no STS caller-identity lookup on a loopback endpoint"
export AWS_SHIM_LOG="$tmp/minio2.log"; : > "$AWS_SHIM_LOG"
AWS_ACCESS_KEY_ID=mine AWS_SECRET_ACCESS_KEY=mysecret env -u PROVE_S3_ENDPOINT -u PROVE_S3_BUCKET \
  "$assets/publish-s3.sh" "$src" >/dev/null 2>&1
grep -q 'AK=mine|SK=mysecret' "$AWS_SHIM_LOG" \
  && ok "explicit AWS credentials win over the MinIO default" || no "explicit credentials win" "$(head -1 "$AWS_SHIM_LOG")"
cat > "$tmp/proofs-sync-ev.json" <<'JSON'
{"kind":"vote"}
JSON
export AWS_SHIM_LOG="$tmp/minio3.log"; : > "$AWS_SHIM_LOG"
env -u PROVE_S3_ENDPOINT -u PROVE_S3_BUCKET "$assets/state-append.sh" demo-doc "$tmp/proofs-sync-ev.json" >/dev/null 2>&1
grep -q 'put-object.*--endpoint-url http://127.0.0.1:9440 --bucket proofs' "$AWS_SHIM_LOG" \
  && ok "state-append.sh writes to the MinIO endpoint" || no "state-append endpoint" "$(cat "$AWS_SHIM_LOG")"

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

echo "== publish-s3.sh: markdown is rendered, never uploaded as one block (loopback store) =="
# A storing stub (objects kept under $mdStore) so the assertions read the bytes that were UPLOADED,
# not the argv. Loopback config, with PROVE_S3_PROFILE set as well as PROVE_S3_ENV: the publisher's
# dev-pair fallback only applies to a clean environment (¶PTF_THE_PROOF_PUBLISHERS_DEV_PAIR_FALLBACK…).
mdStub="$tmp/mdbin"; mdStore="$tmp/mdstore"; mkdir -p "$mdStub" "$mdStore"
cat > "$mdStub/aws" <<'STUB'
#!/usr/bin/env bash
store="${STUB_STORE:?}"; args=("$@"); bucket=""; key=""
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in --bucket) bucket="${args[$((i+1))]}" ;; --key) key="${args[$((i+1))]}" ;; esac
done
case "$1 $2" in
  "s3 cp") dst="${4#s3://}"; mkdir -p "$store/$(dirname "$dst")"; cp "$3" "$store/$dst" ;;
  "s3api get-object") out="${args[$((${#args[@]}-1))]}"; [ -f "$store/$bucket/$key" ] || exit 1; cp "$store/$bucket/$key" "$out" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$mdStub/aws"
mdEnv="$tmp/md.env"
printf 'PROVE_S3_BUCKET=proofs\nPROVE_S3_ENDPOINT=http://127.0.0.1:9\nPROVE_S3_PUBLIC_BASE=http://127.0.0.1:9\nPROVE_S3_PREFIX=proofs\nPROVE_S3_USER=t\n' > "$mdEnv"
mdPublish() { # mdPublish <file> <tag> [slug]
  env PATH="$mdStub:$PATH" STUB_STORE="$mdStore" PROVE_S3_ENV="$mdEnv" PROVE_S3_PROFILE=loopback-test \
    PROVE_S3_BUCKET=proofs PROVE_S3_ENDPOINT=http://127.0.0.1:9 PROVE_S3_PUBLIC_BASE=http://127.0.0.1:9 PROVE_S3_USER=t \
    PROVE_SEAT=meta:engine bash "$assets/publish-s3.sh" "$1" ${3:+"$3"} > "$tmp/$2.out" 2> "$tmp/$2.err"
}
mdStored() { local url; url="$(cat "$tmp/$1.out")"; printf '%s/%s' "$mdStore" "${url#http://127.0.0.1:9/}"; }

cat > "$tmp/fixture-report.md" <<'MD'
# Council Report — fixture

## Verdict
**sound_with_fixes**, see [the ticket](https://linear.app/idealic/issue/IDE-1?a=1&b=2).

- first finding
- second finding

```bash
echo "hello"
```

| # | Tier | Finding |
|---|------|---------|
| 1 | MUST FIX | a root again |

<script>alert('md')</script>
MD
if mdPublish "$tmp/fixture-report.md" md1; then
  ok "a .md publishes (exit 0)"
  obj="$(mdStored md1)"
  grep -q '^http://127.0.0.1:9/proofs/proofs/t/fixture-report-[0-9a-f]\{8\}\.html$' "$tmp/md1.out" \
    && ok "the key drops .md and ends .html" || no "the key drops .md and ends .html" "$(cat "$tmp/md1.out")"
  grep -q 'rendered markdown fixture-report.md' "$tmp/md1.err" && ok "the publisher says it rendered markdown" \
    || no "the publisher says it rendered markdown" "$(head -5 "$tmp/md1.err")"
  grep -q '<h1>Council Report — fixture</h1>' "$obj" && ok "heading rendered" || no "heading rendered" "no <h1>"
  grep -q '<li>first finding</li>' "$obj" && ok "list rendered" || no "list rendered" "no <li>"
  grep -q '<pre class="language-bash"><code class="language-bash">echo &quot;hello&quot;</code></pre>' "$obj" \
    && ok "fenced code rendered with its language" || no "fenced code rendered with its language" "$(grep -o '<pre[^>]*>' "$obj" | head -3)"
  grep -q '<td>a root again</td>' "$obj" && ok "table rendered" || no "table rendered" "no <td>"
  grep -q '<a href="https://linear.app/idealic/issue/IDE-1?a=1&amp;b=2">the ticket</a>' "$obj" \
    && ok "link rendered, query escaped once" || no "link rendered" "$(grep -o '<a [^>]*>' "$obj" | head -3)"
  grep -q "&lt;script&gt;alert(&#x27;md&#x27;)&lt;/script&gt;" "$obj" && ok "a <script> line in the markdown is escaped to text" \
    || no "a <script> line is escaped" "escaped form missing"
  grep -q "<script>alert('md')" "$obj" && no "no raw <script> from the markdown reaches the page" "found it" \
    || ok "no raw <script> from the markdown reaches the page"
  grep -q 'verified by content' "$tmp/md1.err" && ok "the read-back verifies the rendered bytes" \
    || no "the read-back verifies" "$(tail -3 "$tmp/md1.err")"
  grep -q '^# Council Report' "$obj" && no "the raw markdown is not what was uploaded" "raw source uploaded" \
    || ok "the raw markdown is not what was uploaded"
else
  no "a .md publishes (exit 0)" "$(tail -5 "$tmp/md1.err")"
fi
[ "$(head -1 "$tmp/fixture-report.md")" = "# Council Report — fixture" ] && ok "the .md source on disk is untouched" \
  || no "the .md source on disk is untouched" "changed"

# An HTML page with no marked block: uploaded as authored (the only rewrites are the seat strip and the
# highlighter, both older than this change), and an
# UNMARKED language-markdown block stays source.
cat > "$tmp/plainpage.html" <<'HTML'
<!doctype html><html><head><title>plain</title></head><body><main>
<h1>Plain page</h1>
<pre class="language-markdown"><code class="language-markdown"># kept as source
- not a list</code></pre>
</main></body></html>
HTML
if mdPublish "$tmp/plainpage.html" html1; then
  obj="$(mdStored html1)"
  grep -q '<pre class="language-markdown"><code class="language-markdown"># kept as source' "$obj" \
    && ok "an .html upload keeps its unmarked markdown block as source" || no "unmarked block kept" "changed"
  grep -q 'md-render' "$obj" && no "an .html page with no marked block gets no md-render rewrite" "found md-render" \
    || ok "an .html page with no marked block gets no md-render rewrite"
  python3 - "$tmp/plainpage.html" "$obj" <<'PY' && ok "the .html upload equals its source once the seat strip is removed" || no "the .html upload equals its source minus the strip" "differs"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
got = open(sys.argv[2], encoding="utf-8").read()
got = re.sub(r"<!--prove-seat-strip:begin-->.*?<!--prove-seat-strip:end-->", "", got, flags=re.S)
# the kit highlighter rides inline on any page with a highlightable block (a rewrite that predates this change)
got = re.sub(r"<style data-proof-highlight[^>]*>.*?</style>\s*<script data-proof-highlight[^>]*>.*?</script>\n?", "", got, flags=re.S)
if got != src:
    import difflib
    sys.stderr.write("".join(difflib.unified_diff(src.splitlines(True), got.splitlines(True), "source", "uploaded-minus-strip")))
sys.exit(0 if got == src else 1)
PY
else
  no "a plain .html publishes" "$(tail -5 "$tmp/html1.err")"
fi

# An HTML page that embeds a markdown report in a marked block: rendered in place.
cat > "$tmp/embedpage.html" <<'HTML'
<!doctype html><html><head><title>embed</title></head><body><main>
<h1>Proof with a council report</h1>
<pre data-md-render><code class="language-markdown">## Embedded verdict
- point one
&lt;script&gt;alert(&#x27;e&#x27;)&lt;/script&gt;</code></pre>
</main></body></html>
HTML
if mdPublish "$tmp/embedpage.html" emb1; then
  obj="$(mdStored emb1)"
  grep -q '<div class="md-render">' "$obj" && ok "a marked block is rendered in place" || no "marked block rendered" "no md-render div"
  grep -q '<h2>Embedded verdict</h2>' "$obj" && grep -q '<li>point one</li>' "$obj" \
    && ok "the embedded markdown's heading and list render" || no "embedded heading/list" "missing"
  grep -q 'data-md-render>' "$obj" && no "no marked <pre> is left" "still there" || ok "no marked <pre> is left"
  grep -q "&lt;script&gt;alert(&#x27;e&#x27;)&lt;/script&gt;" "$obj" && ! grep -q "<script>alert('e')" "$obj" \
    && ok "a <script> inside embedded markdown stays escaped" || no "embedded script escaped" "raw or missing"
  grep -c '<style data-md-render-css>' "$obj" | grep -qx 1 && ok "one scoped stylesheet" || no "one scoped stylesheet" "count wrong"
else
  no "an embedding page publishes" "$(tail -5 "$tmp/emb1.err")"
fi

echo "== publish-s3.sh: link schemes, quotes, markup context, headings, other file types =="
# Hostile links, in BOTH modes: only http(s) becomes a link, and a quote in an href never closes it.
cat > "$tmp/links.md" <<'MD'
# Links

[js](javascript:alert(1)) [jsup](JavaScript:alert(2)) [dt](data:text/html,<b>x</b>) [q](http://a/"onmouseover="x) [ok](https://example.com/a?b=1)

It's a "quoted" line with ' onmouseover=alert(4) x='

## Using C#
### Closed heading ###
MD
linkChecks() { # linkChecks <file> <mode label>
  local f="$1" m="$2"
  grep -qi 'href="javascript' "$f" && no "$m: no javascript: href" "found one" || ok "$m: no javascript: href"
  grep -qi 'href="data' "$f" && no "$m: no data: href" "found one" || ok "$m: no data: href"
  grep -q '"on' "$f" && no "$m: no raw \"on… attribute from a quote in a URL" "$(grep -o '.\{20\}"on.\{20\}' "$f" | head -2)" \
    || ok "$m: no raw \"on… attribute from a quote in a URL"
  grep -q '<a href="http://a/&quot;onmouseover=&quot;x">q</a>' "$f" && ok "$m: the quote in an http href is &quot;" \
    || no "$m: the quote in an http href is &quot;" "$(grep -o '<a [^>]*>q' "$f")"
  grep -q '<a href="https://example.com/a?b=1">ok</a>' "$f" && ok "$m: an https link still renders" || no "$m: an https link still renders" "missing"
  grep -q '\[js\](javascript:alert(1))' "$f" && ok "$m: a javascript: link stays literal text" || no "$m: javascript: link literal" "missing"
  grep -q "It&#x27;s a &quot;quoted&quot; line with &#x27; onmouseover=alert(4) x=&#x27;" "$f" \
    && ok "$m: quotes in text are escaped (no attribute can be closed)" || no "$m: quotes in text escaped" "$(grep -o "It.\{0,60\}" "$f" | head -1)"
  grep -q '<h2>Using C#</h2>' "$f" && ok "$m: a heading keeps a trailing # that is part of the text (C#)" \
    || no "$m: heading keeps C#" "$(grep -o '<h2>Using[^<]*' "$f")"
  grep -q '<h3>Closed heading</h3>' "$f" && ok "$m: a closing # run after a space is dropped" || no "$m: closing # run dropped" "$(grep -o '<h3>[^<]*' "$f")"
}
if mdPublish "$tmp/links.md" lk1; then linkChecks "$(mdStored lk1)" "page mode"; else no "links.md publishes" "$(tail -3 "$tmp/lk1.err")"; fi
python3 - "$tmp/links.md" > "$tmp/linkembed.html" <<'PY'
import html, sys
md = open(sys.argv[1], encoding="utf-8").read()
print('<!doctype html><html><head><title>e</title></head><body>'
      f'<pre data-md-render><code class="language-markdown">{html.escape(md)}</code></pre></body></html>')
PY
if mdPublish "$tmp/linkembed.html" lk2; then linkChecks "$(mdStored lk2)" "embed mode"; else no "the link embed page publishes" "$(tail -3 "$tmp/lk2.err")"; fi

# A marker that is NOT a real <pre> element is data: inside an attribute, a comment, a script.
cat > "$tmp/ctx.html" <<'HTML'
<!doctype html><html><head><title>ctx</title></head><body>
<div title='<pre data-md-render>'>attr</div><p>' onmouseover=alert(1) x='</p></pre>
<!-- <pre data-md-render><code>in a comment</code></pre> --><p>after the comment</p>
<script>var s = '<pre data-md-render>';</script>
<pre data-md-render-css class="language-text">not a marker either</pre>
</body></html>
HTML
if mdPublish "$tmp/ctx.html" ctx1; then
  obj="$(mdStored ctx1)"
  grep -q 'md-render">' "$obj" && no "a marker outside markup context is not rendered" "$(grep -o '.\{30\}md-render">.\{30\}' "$obj" | head -2)" \
    || ok "a marker outside markup context is not rendered (attribute, comment, script, -css name)"
  grep -q "<div title='<pre data-md-render>'>attr</div>" "$obj" && ok "the critic's title-attribute repro is left as authored" \
    || no "title-attribute repro left as authored" "changed"
  grep -q '<p>after the comment</p>' "$obj" && ok "a marker in a comment does not swallow the rest of the page" || no "comment marker swallows page" "text after the comment is gone"
else
  no "the context page publishes" "$(tail -3 "$tmp/ctx1.err")"
fi
# The marker is matched case-insensitively as a real attribute.
printf '<!doctype html><html><head><title>u</title></head><body><PRE DATA-MD-RENDER><code class="language-markdown">## Upper case marker</code></PRE></body></html>\n' > "$tmp/upper.html"
if mdPublish "$tmp/upper.html" up1; then
  grep -q '<h2>Upper case marker</h2>' "$(mdStored up1)" && ok "an upper-case <PRE DATA-MD-RENDER> renders" || no "upper-case marker renders" "not rendered"
else no "the upper-case page publishes" "$(tail -3 "$tmp/up1.err")"; fi
# A page that only MENTIONS the marker keeps CRLF line endings byte for byte.
printf '<!doctype html>\r\n<html><head><title>c</title></head><body>\r\n<p>mentions data-md-render in text</p>\r\n</body></html>\r\n' > "$tmp/crlf.html"
python3 "$assets/_md-page.py" embed "$tmp/crlf.html" > "$tmp/crlf.out" 2>/dev/null
cmp -s "$tmp/crlf.html" "$tmp/crlf.out" && ok "embed prints an unmarked CRLF page byte-identical" || no "embed keeps CRLF" "bytes differ"

# Any other file type: escaped into a text page, never uploaded as HTML verbatim.
printf 'build started\n<script>alert("log")</script>\n<img src=x onerror=alert(5)>\ndone\n' > "$tmp/build.log"
if mdPublish "$tmp/build.log" log1; then
  obj="$(mdStored log1)"
  grep -q '^http://127.0.0.1:9/proofs/proofs/t/build.log-[0-9a-f]\{8\}\.html$' "$tmp/log1.out" && ok "a .log keys as <name>.log-<rand>.html" || no "log key" "$(cat "$tmp/log1.out")"
  grep -q 'uploaded as an escaped text page' "$tmp/log1.err" && ok "the publisher says it wrapped the .log as text" || no "says it wrapped" "$(head -3 "$tmp/log1.err")"
  grep -q '&lt;script&gt;alert(&quot;log&quot;)&lt;/script&gt;' "$obj" && ok "a <script> in a .log is escaped to text" || no "script in log escaped" "missing"
  grep -q '<script>alert("log")' "$obj" && no "no raw <script> from the .log reaches the page" "found it" || ok "no raw <script> from the .log reaches the page"
  grep -q '<img src=x' "$obj" && no "no raw <img onerror> from the .log" "found it" || ok "no raw <img onerror> from the .log"
  grep -q '<pre class="language-text"><code class="language-text">build started' "$obj" && ok "the .log shows as a language-text block" || no "log as language-text" "missing"
else
  no "a .log publishes (exit 0)" "$(tail -5 "$tmp/log1.err")"
fi
printf 'no extension, <script>x</script>\n' > "$tmp/NOTES"
if mdPublish "$tmp/NOTES" noext; then
  grep -q '<script>x</script>' "$(mdStored noext)" && no "a file with no extension is escaped too" "raw script" || ok "a file with no extension is escaped too"
else no "an extensionless file publishes" "$(tail -3 "$tmp/noext.err")"; fi
# Case-insensitive extensions: .MD renders and its slug drops .MD; .Html goes up as HTML.
cp "$tmp/fixture-report.md" "$tmp/UPPER.MD"
if mdPublish "$tmp/UPPER.MD" mdup; then
  grep -q '^http://127.0.0.1:9/proofs/proofs/t/UPPER-[0-9a-f]\{8\}\.html$' "$tmp/mdup.out" && ok "the slug drops an upper-case .MD" || no "slug drops .MD" "$(cat "$tmp/mdup.out")"
  grep -q '<h1>Council Report — fixture</h1>' "$(mdStored mdup)" && ok "an upper-case .MD renders" || no "upper .MD renders" "not rendered"
else no ".MD publishes" "$(tail -3 "$tmp/mdup.err")"; fi
cp "$tmp/plainpage.html" "$tmp/Mixed.Html"
if mdPublish "$tmp/Mixed.Html" mixh; then
  grep -q '<h1>Plain page</h1>' "$(mdStored mixh)" && ! grep -q 'Shown as text' "$(mdStored mixh)" \
    && ok "a mixed-case .Html still goes up as HTML" || no "mixed-case .Html as HTML" "wrapped or changed"
else no ".Html publishes" "$(tail -3 "$tmp/mixh.err")"; fi
# An explicit slug with a / no longer breaks the render (fixed temp name).
if mdPublish "$tmp/fixture-report.md" slash "team/report"; then ok "an explicit slug containing / still renders"; else no "slug with /" "$(tail -3 "$tmp/slash.err")"; fi

printf '\n%s\n' "-------------------------------------"
printf 'passed %d   failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
