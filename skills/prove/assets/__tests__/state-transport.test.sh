#!/usr/bin/env bash
# Offline harness for the shared-state transport: where the state document lives, where a write
# grant is allowed to point, and that a page with nothing to decide is still left alone.
#
# Nothing here reaches a store. The gates under test all answer their question before or beside the
# upload, so `aws` and `curl` are shims on PATH — which also means a PASS can never be a publish
# that quietly went somewhere. Every negative case is paired with its nearest LEGAL neighbour (the
# same tree, the same config, one thing changed), because a gate proved only against something
# obviously wrong tells you nothing about what it will be handed.
#
# Run:  ~/.claude/engine/skills/prove/assets/__tests__/state-transport.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

tmp="$(mktemp -d -t prove-state)"
trap 'rm -rf "$tmp"' EXIT

# --- shims --------------------------------------------------------------------------------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SHIM_AWS_LOG:-/dev/null}"
case "$*" in
  *"list-objects-v2"*) exit 0 ;;                       # no prior state docs
  *"sts get-caller-identity"*) echo "arn:aws:iam::000000000000:user/testuser" ;;
  *"configure export-credentials"*) echo "CREDS SHOULD NOT BE EXPORTED ON A LOCAL STORE" >&2; exit 1 ;;
esac
exit 0
SHIM
# The readback is the whole point of one case below, so the code it answers is a knob.
cat > "$tmp/bin/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "${SHIM_CURL_CODE:-200}"
exit 0
SHIM
chmod +x "$tmp/bin/aws" "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"

envfile() { # envfile <name> <KEY=VAL>… -> path
  local f="$tmp/$1.env"; shift
  : > "$f"
  for kv in "$@"; do printf '%s\n' "$kv" >> "$f"; done
  printf '%s' "$f"
}
LOCAL_ENV="$(envfile local \
  PROVE_S3_BUCKET=proofs PROVE_S3_REGION=us-east-1 PROVE_S3_PREFIX=proofs \
  PROVE_S3_STATE_PREFIX=state PROVE_S3_EVENTS_PREFIX=events \
  PROVE_S3_ENDPOINT=http://127.0.0.1:9440)"

board() { # board <name> -> path to a page carrying decision markup
  local f="$tmp/$1.html"
  cat > "$f" <<'HTML'
<!doctype html><html><body data-fb-board="t" data-fb-wave="w">
<div data-fb-item="i"><input data-fb-key="k"></div>
<script id="prove-state-config" data-fb-state-config type="application/json">__PROVE_STATE_CONFIG__</script>
</body></html>
HTML
  printf '%s' "$f"
}

# A COPY of the asset tree per scenario: the signer is resolved as a sibling of publish-s3.sh, so
# the only way to exercise a regressed signer is to regress one beside its own publisher.
treecopy() { # treecopy <name> -> dir
  local d="$tmp/tree-$1"
  mkdir -p "$d"
  cp "$assets"/*.sh "$assets"/*.py "$assets"/credentials.json "$d/" 2>/dev/null
  # The grant probe POSTs to the real endpoint over the network, so with it present these cases
  # passed only when a live store on 127.0.0.1:9440 accepted the harness's login. The probe has
  # its own suite (scripts/tests/test-prove-grant-destination.sh); here it is left out so the
  # transport cases stay offline.
  rm -f "$d/_grant-probe.py"
  printf '%s' "$d"
}
run() { # run <tree> <page> <slug> [EXTRA=VAL…] -> prints nothing; status in rc, output in $tmp/run.out
  local tree="$1" page="$2" slug="$3"; shift 3
  ( export PROVE_S3_ENV="$LOCAL_ENV" PROVE_S3_USER=harness SHIM_AWS_LOG="$tmp/aws.log"
    # The local store's login comes from the kit's variables (never a literal in the loader); the
    # signer needs a key pair to sign the grant, so the harness supplies a test one here.
    export KIT_PROOFS_MINIO_USER=harness-user KIT_PROOFS_MINIO_PASSWORD=harness-pass
    for kv in "$@"; do export "${kv?}"; done
    : > "$tmp/aws.log"
    bash "$tree/publish-s3.sh" "$page" "$slug" > "$tmp/run.url" 2> "$tmp/run.err" )
  printf '%s' "$?" > "$tmp/run.rc"
  cat "$tmp/run.err" "$tmp/run.url" > "$tmp/run.out"
}
rc() { cat "$tmp/run.rc"; }

printf '\n== The state document is addressed where the page is served from ==\n'
# A top-level state/<doc>.json sits outside the prefix every public-read grant is written against,
# which is the whole reason the read half 403'd on the store in use. The key must nest.
keys="$(bash -c '
  PROVE_S3_PREFIX=proofs PROVE_S3_STATE_PREFIX=state
  . "'"$assets"'/_prove-s3-env.sh" >/dev/null 2>&1
  PROVE_S3_PREFIX=proofs PROVE_S3_STATE_PREFIX=state;      echo "A=$(prove_state_key d1)"
  PROVE_S3_PREFIX=proofs PROVE_S3_STATE_PREFIX=proofs/state; echo "B=$(prove_state_key d1)"
  PROVE_S3_PREFIX=pages  PROVE_S3_STATE_PREFIX=state;      echo "C=$(prove_state_key d1)"
  PROVE_S3_PREFIX=proofs PROVE_S3_EVENTS_PREFIX=events;    echo "D=$(prove_events_key_prefix d1)"
' 2>/dev/null)"
have "$keys" "A=proofs/state/d1.json" \
  && ok "the state key nests under the publish prefix, so the page's own read grant serves it" \
  || no "the state key nests under the publish prefix" "$keys"
have "$keys" "B=proofs/state/d1.json" \
  && ok "…and a prefix already inside it is left alone (no proofs/proofs/state)" \
  || no "an already-nested state prefix is idempotent" "$keys"
have "$keys" "C=pages/state/d1.json" \
  && ok "…and it follows a renamed publish prefix rather than hardcoding one" \
  || no "the nesting follows PROVE_S3_PREFIX" "$keys"
have "$keys" "D=events/d1/" \
  && ok "the EVENTS prefix stays OUTSIDE the public prefix — an event carries the voter's name" \
  || no "events stay outside the public prefix" "$keys"

printf '\n== A write grant may only point at the resolved destination ==\n'
clean="$(treecopy clean)"
planted="$(treecopy planted)"
# The plant is the file as it stood before endpoint support existed, and exactly what a careless
# edit would reintroduce: the signer ignores the endpoint and names the cloud provider's host.
python3 - "$planted/sign-post.py" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
body = '''    host = (f"{bucket}.s3.amazonaws.com" if region == "us-east-1"
            else f"{bucket}.s3.{region}.amazonaws.com")
    return f"https://{host}/"
'''
s2 = re.sub(r"(def _post_url\(bucket, region\):\n(?:    \"\"\".*?\"\"\"\n)?)(?:    .*\n|\n)*?(?=\n\ndef main)",
            lambda m: m.group(1) + body, s)
if s2 == s:
    sys.exit("plant site not found — the signer's shape changed; fix this harness")
open(p, "w").write(s2)
PY
pg="$(board plantpage)"
run "$planted" "$pg" tp
have "$(cat "$tmp/run.out")" "REFUSED by the destination gate" \
  && ok "a signer that names the cloud provider's host is REFUSED against a local endpoint" \
  || no "the destination gate refuses a mismatched POST target" "$(cat "$tmp/run.err")"
have "$(cat "$tmp/run.out")" "got https://proofs.s3.amazonaws.com/" \
  && ok "…and the refusal names BOTH targets, so the reader can see which layer lied" \
  || no "the refusal names the rejected target" "$(cat "$tmp/run.err")"
have "$(cat "$tmp/run.out")" "falls back to copy-back" \
  && ok "…and the board still publishes, read-only, with the reason on its submit control" \
  || no "a refused grant degrades rather than failing the publish" "$(cat "$tmp/run.err")"
[ "$(rc)" = "0" ] && ok "…and the publish itself exits 0 — the signer is never load-bearing" \
  || no "a refused grant must not fail the publish" "rc=$(rc)"

run "$clean" "$(board cleanpage)" tc
have "$(cat "$tmp/run.out")" "writes presigned → http://127.0.0.1:9440/proofs/" \
  && ok "CONTROL: the same tree with the shipped signer mints a grant at the LOCAL store" \
  || no "the shipped signer targets the resolved local endpoint" "$(cat "$tmp/run.err")"
have "$(cat "$tmp/run.out")" "REFUSED" \
  && no "the control must not be refused" "$(cat "$tmp/run.err")" \
  || ok "…and is not refused — the gate discriminates rather than refusing everything"

printf '\n== sign-post.py targets what the publish resolved, and only that ==\n'
sp() { # sp <ENV…> -> postUrl
  ( export PROVE_S3_BUCKET=proofs AWS_ACCESS_KEY_ID=k AWS_SECRET_ACCESS_KEY=s
    for kv in "$@"; do export "${kv?}"; done
    python3 "$assets/sign-post.py" doc1 60 2>/dev/null ) \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["postUrl"])'
}
u="$(sp PROVE_S3_ENDPOINT_URL=http://127.0.0.1:9440)"
[ "$u" = "http://127.0.0.1:9440/proofs/" ] \
  && ok "an endpoint yields a path-style POST on that endpoint" || no "endpoint ⇒ path-style" "$u"
u="$(sp PROVE_S3_ENDPOINT_URL=http://127.0.0.1:9440 PROVE_S3_PUBLIC_URL=http://board.local:8080)"
[ "$u" = "http://board.local:8080/proofs/" ] \
  && ok "…on the BROWSER-facing base when one is set, which is what keeps the POST same-origin" \
  || no "the public base wins for the POST target" "$u"
u="$(sp)"
[ "$u" = "https://proofs.s3.amazonaws.com/" ] \
  && ok "CONTROL: no endpoint still yields the AWS virtual-hosted host — the existing path is intact" \
  || no "no endpoint ⇒ AWS host" "$u"
u="$(sp PROVE_S3_ENDPOINT_URL=aws)"
[ "$u" = "https://proofs.s3.amazonaws.com/" ] \
  && ok "…and the resolver's 'aws' sentinel is honoured here too, not read as a hostname" \
  || no "the aws sentinel blanks the endpoint" "$u"
u="$(sp PROVE_S3_REGION=eu-west-1)"
[ "$u" = "https://proofs.s3.eu-west-1.amazonaws.com/" ] \
  && ok "…and a non-default region still gets its regional host" || no "regional AWS host" "$u"

printf '\n== The page says what the publish found, including when it found a problem ==\n'
run "$clean" "$(board readable)" tr1
have "$(cat "$tmp/run.out")" "reads back 200 anonymously" \
  && ok "a readable state document is reported as readable, from an actual credential-free GET" \
  || no "the readback is performed and reported" "$(cat "$tmp/run.err")"
run "$clean" "$(board refused)" tr2 SHIM_CURL_CODE=403
have "$(cat "$tmp/run.out")" "reads back HTTP 403 for an anonymous reader" \
  && ok "a state document that a reader cannot fetch is called out at publish time" \
  || no "an unreadable state document is reported" "$(cat "$tmp/run.err")"
have "$(cat "$tmp/run.out")" "the board will say so on the page rather than waiting silently" \
  && ok "…with the consequence stated: the page reports it instead of looking unfolded" \
  || no "the unreadable warning states the consequence" "$(cat "$tmp/run.err")"
[ "$(rc)" = "0" ] && ok "…and an unreadable state document does not fail the publish either" \
  || no "an unreadable state doc must not fail the publish" "rc=$(rc)"

printf '\n== Republishing in place keeps the document; a fresh identity re-points it ==\n'
run "$clean" "$(board inplace)" ti PROVE_DOC_ID=ti-deadbeef
have "$(cat "$tmp/run.url")" "ti-deadbeef.html" \
  && ok "PROVE_DOC_ID republishes to the SAME object key" || no "republish in place" "$(cat "$tmp/run.url")"
have "$(cat "$tmp/run.out")" "existing state doc and its answers are kept" \
  && ok "…and says so, because silently reusing a document that holds answers is the sharp case" \
  || no "republish-in-place is announced" "$(cat "$tmp/run.err")"
have "$(cat "$tmp/aws.log")" "--if-none-match *" \
  && ok "…and the state write is create-only, so a republish cannot overwrite collected answers" \
  || no "the state write is create-only" "$(cat "$tmp/aws.log")"
have "$(cat "$tmp/aws.log")" "list-objects-v2" \
  && no "an in-place republish must not hunt for boards to supersede" "$(cat "$tmp/aws.log")" \
  || ok "…and it does not stamp anything as superseded — nothing was replaced"
run "$clean" "$(board fresh)" tf
have "$(cat "$tmp/aws.log")" "list-objects-v2" \
  && ok "CONTROL: a FRESH identity does look for earlier boards of this slug to re-point" \
  || no "a fresh identity looks for superseded boards" "$(cat "$tmp/aws.log")"
have "$(cat "$tmp/run.out")" "republishing IN PLACE" \
  && no "a fresh identity must not claim to be in place" "$(cat "$tmp/run.err")" \
  || ok "…and does not claim to be a republish in place"

printf '\n== A page with nothing to decide is still left entirely alone ==\n'
plainpage="$tmp/plain.html"
printf '%s\n' '<!doctype html><html><body><h1>Evidence only</h1></body></html>' > "$plainpage"
run "$clean" "$plainpage" tplain
have "$(cat "$tmp/run.out")" "state config" \
  && no "a page with no decision markup must get no state config" "$(cat "$tmp/run.err")" \
  || ok "no state config is injected"
have "$(cat "$tmp/aws.log")" "put-object" \
  && no "a page with no decision markup must mint no state object" "$(cat "$tmp/aws.log")" \
  || ok "…no state object is written"
have "$(cat "$tmp/aws.log")" "s3 cp" \
  && ok "CONTROL: the page itself WAS uploaded — the two absences above are not an aborted run" \
  || no "the plain page still uploads" "$(cat "$tmp/aws.log")"

printf '\n== The AWS path is unchanged — the endpoint support did not become a requirement ==\n'
# The only consumer that cannot be exercised live from here. The shimmed `aws configure
# export-credentials` fails, which is the ordinary state of a machine with no usable profile, so
# this asserts the EXISTING degradation still happens on the AWS path and that the destination the
# gate would have demanded is the AWS host rather than a loopback one.
AWS_ENV="$(envfile aws \
  PROVE_S3_BUCKET=proofs PROVE_S3_REGION=us-east-2 PROVE_S3_PREFIX=proofs \
  PROVE_S3_STATE_PREFIX=state PROVE_S3_EVENTS_PREFIX=events \
  PROVE_S3_ENDPOINT=aws PROVE_S3_USER=harness)"
( export PROVE_S3_ENV="$AWS_ENV" PROVE_S3_USER=harness SHIM_AWS_LOG="$tmp/aws.log"
  : > "$tmp/aws.log"
  bash "$clean/publish-s3.sh" "$(board awspage)" ta > "$tmp/run.url" 2> "$tmp/run.err" )
printf '%s' "$?" > "$tmp/run.rc"
cat "$tmp/run.err" "$tmp/run.url" > "$tmp/run.out"
have "$(cat "$tmp/run.out")" "could not export AWS credentials" \
  && ok "with no endpoint the publish still goes through export-credentials and degrades on failure" \
  || no "the AWS credential path is unchanged" "$(cat "$tmp/run.err")"
# Not "does the AWS hostname appear" — it appears in the READ url on this path, which is correct.
# The thing that must be absent is a minted write target.
have "$(cat "$tmp/run.out")" "writes presigned" \
  && no "a degraded AWS publish must not advertise a POST target it never minted" "$(cat "$tmp/run.err")" \
  || ok "…and no POST target is advertised, because no grant was minted"
have "$(cat "$tmp/run.out")" "state config injected READ-ONLY → https://proofs.s3.us-east-2.amazonaws.com/proofs/state/" \
  && ok "…while the state doc is still addressed on AWS, nested under the publish prefix" \
  || no "the AWS state address nests under the publish prefix" "$(cat "$tmp/run.err")"
have "$(cat "$tmp/run.url")" "https://proofs.s3.us-east-2.amazonaws.com/" \
  && ok "CONTROL: the AWS object URL itself is untouched — the endpoint work did not retarget reads" \
  || no "the AWS read URL is unchanged" "$(cat "$tmp/run.url")"

printf '\n== SKIPPED: the events prefix must not be anonymously readable on ANY store ==\n'
# Written against the RULE, not against today's behaviour, and skipped because the fix is a bucket
# policy and no store this harness can reach satisfies it yet.
#
# The rule: an event object carries the voter's NAME. `events/<doc>/` is nested outside the public
# prefix precisely so a reader cannot enumerate who answered what, and STATE_TRANSPORT.md states
# that posture. Measured 2026-10-20 with a missing-key probe plus a present-key positive control in
# the same invocation: on the kit's MinIO (9440) the grant is `GetObject` on `<bucket>/proofs*`, so
# `/proofs/events/<anything>` is 403 and the posture HOLDS. On the other local store (9010) the
# grant is bucket-wide, so the same probe returns 404 — i.e. the key is simply absent, and an event
# published there WOULD be world-readable. The transport cannot close that from here: the fix is to
# narrow that bucket's statement from `proofs/*` to `proofs/proofs*`, which is store infrastructure
# and not a /prove change.
#
# UN-SKIP WHEN: every store the transport is published to answers an anonymous GET under its events
# prefix with 403 rather than 404. Then delete this block and assert it live: for each configured
# endpoint, probe `<public base>/<bucket>/<events prefix>/probe.json` and require 403, with a probe
# under the publish prefix returning 404 in the same invocation as the control that proves the
# instrument can tell a refusal from a miss.
skipped=1
printf '  skip %s\n' "events/* is anonymously readable on a bucket-wide-grant store — the fix is that bucket's policy, not this transport"

printf '\n-------------------------------------\n'
printf 'passed %d   failed %d   skipped %d\n' "$pass" "$fail" "${skipped:-0}"
[ "$fail" -eq 0 ]
