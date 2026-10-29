#!/usr/bin/env bash
# Can a published board's write grant reach a destination the operator did not choose, or be
# shipped without anyone ever having spent it? Those are the two ways operator answers go missing,
# and this file fails if either becomes possible again.
#
# The first is the dangerous one: a grant whose POST target is derived independently of the resolved
# read destination hands every reader a form that mails their answer to somebody else's account. The
# second is the quiet one: a grant that points at the right place and is signed by an identity the
# destination does not know is minted, reported as success, and refused on the reader's click.
#
# NO NETWORK for the destination cases — sign-post.py is pure stdlib and takes its target from the
# environment, so the target can be asserted directly. The grant-probe cases run against a local
# HTTP server this file starts and stops itself, because the point of the probe is that it talks to
# the destination, and a shimmed probe would assert nothing.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$here/../../skills/prove/assets"
signer="$assets/sign-post.py"
prober="$assets/_grant-probe.py"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

tmp="$(mktemp -d -t prove-grant)"
cleanup() { [ -n "${srv_pid:-}" ] && kill "$srv_pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

mint() { # mint <endpoint> <public_base> <out> ; empty endpoint = the AWS arm
  PROVE_S3_BUCKET=proofs PROVE_S3_REGION=us-east-1 PROVE_S3_EVENTS_PREFIX=events \
  PROVE_S3_ENDPOINT_URL="$1" PROVE_S3_PUBLIC_URL="$2" \
  AWS_ACCESS_KEY_ID=TESTKEY AWS_SECRET_ACCESS_KEY=testsecret \
  python3 "$signer" testdoc 600 > "$3" 2>"$tmp/mint.err"
}
post_url_of() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["postUrl"])' "$1"; }

printf '\n== ONE CHOSEN DESTINATION · the grant target follows the resolved endpoint, never a hardcoded host ==\n'

if mint "http://127.0.0.1:9440" "http://127.0.0.1:9440" "$tmp/kit.json"; then
  got="$(post_url_of "$tmp/kit.json")"
  [ "$got" = "http://127.0.0.1:9440/proofs/" ] \
    && ok "a loopback endpoint gets a path-style target on its own base" \
    || no "a loopback endpoint gets a path-style target on its own base" "got $got"
  case "$got" in
    *amazonaws.com*) no "the loopback grant names NO cloud host" "got $got" ;;
    *)               ok "the loopback grant names NO cloud host" ;;
  esac
else
  no "the signer runs for a loopback endpoint" "$(cat "$tmp/mint.err")"
fi

# The discriminator the whole trap turns on: two different endpoints must produce two different
# targets. A hardcoded host passes any single-case assertion by accident.
if mint "http://127.0.0.1:9010" "http://127.0.0.1:9010" "$tmp/other.json"; then
  a="$(post_url_of "$tmp/kit.json")"; b="$(post_url_of "$tmp/other.json")"
  [ "$a" != "$b" ] \
    && ok "two endpoints that differ ONLY by port produce two different grant targets" \
    || no "two endpoints that differ ONLY by port produce two different grant targets" "both $a"
fi

# PROVE_S3_PUBLIC_URL is the reader-facing base and the page is served from it, so the grant must
# follow it rather than the admin endpoint — otherwise the POST leaves the page's origin.
if mint "http://10.0.0.5:9000" "https://proofs.example.test" "$tmp/split.json"; then
  got="$(post_url_of "$tmp/split.json")"
  [ "$got" = "https://proofs.example.test/proofs/" ] \
    && ok "the grant follows the READER-facing base, not the admin endpoint" \
    || no "the grant follows the READER-facing base, not the admin endpoint" "got $got"
fi

# The cloud arm must still be reachable BY NAMING IT — a fix that simply killed it would pass
# every assertion above while breaking every real publish.
if mint "" "" "$tmp/aws.json"; then
  got="$(post_url_of "$tmp/aws.json")"
  [ "$got" = "https://proofs.s3.amazonaws.com/" ] \
    && ok "an explicitly empty endpoint still reaches AWS (the arm is chosen, not dead)" \
    || no "an explicitly empty endpoint still reaches AWS" "got $got"
fi

printf '\n== the publisher re-derives the SAME one target, so a regressed signer is caught ==\n'
# Asserted against publish-s3.sh's own text because the gate is the thing under test: it must
# compare, and it must drop the grant rather than publish it.
pub="$assets/publish-s3.sh"
if grep -q 'expectedPostUrl' "$pub" && grep -q 'gotPostUrl' "$pub"; then
  ok "publish-s3.sh derives an expected target and reads the signer's own"
else
  no "publish-s3.sh derives an expected target and reads the signer's own"
fi
if grep -A3 'if \[ "\$gotPostUrl" != "\$expectedPostUrl" \]' "$pub" | grep -q 'signed=""'; then
  ok "a mismatched grant is DROPPED, not published"
else
  no "a mismatched grant is DROPPED, not published" "the gate no longer clears \$signed"
fi

printf '\n== A MINTED GRANT IS NOT AN ACCEPTED GRANT · three verdicts, never two ==\n'
if [ ! -f "$prober" ]; then
  no "_grant-probe.py exists beside publish-s3.sh" "not found at $prober"
else
  # A destination that answers 403 the way S3 does. The probe must call that REFUSED and name the
  # code, because a refusal is what has to strip the grant off the page.
  cat > "$tmp/server.py" <<'PY'
import http.server, sys
CODE = int(sys.argv[1])
BODY = b'<?xml version="1.0"?><Error><Code>InvalidAccessKeyId</Code></Error>'
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(CODE)
        if CODE >= 400:
            self.send_header("Content-Type", "application/xml")
            self.send_header("Content-Length", str(len(BODY)))
            self.end_headers(); self.wfile.write(BODY)
        else:
            self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[2])), H).serve_forever()
PY
  probe_against() { # probe_against <http_code> ; echoes the verdict line
    local code="$1" port=18129 i=0
    python3 "$tmp/server.py" "$code" "$port" & srv_pid=$!
    while [ "$i" -lt 50 ]; do
      if python3 -c 'import socket,sys;s=socket.socket();s.settimeout(0.2);sys.exit(0 if s.connect_ex(("127.0.0.1",'"$port"'))==0 else 1)'; then break; fi
      i=$((i+1))
    done
    mint "http://127.0.0.1:$port" "http://127.0.0.1:$port" "$tmp/live.json"
    python3 "$prober" "$tmp/live.json" "events/testdoc/.grant-probe-test.json" 2>/dev/null
    kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; srv_pid=""
  }

  v="$(probe_against 204)"
  case "$v" in
    accepted*) ok "a destination that TAKES the write reads as accepted ($v)" ;;
    *)         no "a destination that TAKES the write reads as accepted" "got '$v'" ;;
  esac

  v="$(probe_against 403)"
  case "$v" in
    refused*InvalidAccessKeyId*) ok "a destination that REFUSES the write reads as refused, naming its code ($v)" ;;
    *)                           no "a destination that refuses reads as refused with its code" "got '$v'" ;;
  esac

  # Nothing listening: never-reached is its OWN verdict. Collapsing it into refused would strip a
  # working grant off a board for a network blip; collapsing it into accepted is the defect this
  # whole probe exists to end.
  mint "http://127.0.0.1:18130" "http://127.0.0.1:18130" "$tmp/dead.json"
  v="$(python3 "$prober" "$tmp/dead.json" "events/testdoc/.grant-probe-test.json" 2>/dev/null)"
  case "$v" in
    unverified*) ok "a destination that never answers reads as unverified, not as either other verdict ($v)" ;;
    *)           no "a destination that never answers reads as unverified" "got '$v'" ;;
  esac

  # The probe must send the body the WIDGET sends. A probe with a different field order or a
  # missing signed field could be accepted where the widget's own post is refused by the policy.
  if grep -q 'part("key"' "$prober" && grep -q 'name="file"' "$prober" \
     && [ "$(grep -n 'part("key"' "$prober" | cut -d: -f1)" -lt "$(grep -n 'name="file"' "$prober" | cut -d: -f1)" ]; then
    ok "the probe posts key BEFORE file, the order the widget's FormData uses"
  else
    no "the probe posts key before file" "a different multipart shape proves nothing about the widget's post"
  fi

  if grep -q 'refused\*' "$pub" && grep -A4 'refused\*' "$pub" | grep -q 'signed=""'; then
    ok "publish-s3.sh DROPS a refused grant rather than shipping it"
  else
    no "publish-s3.sh drops a refused grant" "a refused grant would still reach the page"
  fi
  if grep -q 'GRANT_VERIFIED' "$pub" && grep -q 'grantVerified' "$pub"; then
    ok "whether the grant was spent reaches the page, so a conductor can read it"
  else
    no "whether the grant was spent reaches the page"
  fi
fi

printf '\n== A REFUSAL IS NOT AN EMPTY STATE · never-reached is its own fact on the read half too ==\n'
if grep -q 'could not be reached at all' "$pub"; then
  ok "a state document that was never answered is NOT reported as a read-policy refusal"
else
  no "a 000 read is distinguished from a policy refusal" "the reader would be sent to edit a grant nobody consulted"
fi
# The CODE line, not a comment that quotes the old form: the fallback only concatenates when it
# sits inside the same substitution as the curl that already printed its own 000.
if grep -E 'curl .*\|\| echo 000' "$pub" >/dev/null 2>&1; then
  no "the readback code is a single code" "curl prints 000 itself, so a '|| echo 000' inside its own substitution concatenates into 000000"
else
  ok "the readback code cannot concatenate into a nonsense HTTP code"
fi

printf '\n== the fold never counts a grant probe as somebody'"'"'s answer ==\n'
sync="$assets/prove-sync.sh"
if grep -q '\.\*) skipped' "$sync"; then
  ok "prove-sync skips a dot-prefixed key, so an uncleaned probe cannot become a phantom event"
else
  no "prove-sync skips a dot-prefixed key" "a probe whose delete failed would be folded as an answer"
fi

printf '\n-------------------------------------\n'
printf 'passed %-4s failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
