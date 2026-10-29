#!/usr/bin/env bash
# The board's read-back grant, checked against a REAL store: sign-post.py's `listUrl` must list the
# board's own events prefix, and a tampered copy of it must be refused — otherwise "stored at" on
# the page would rest on a URL nobody had ever seen answer.
#
# LOCAL STORE ONLY. It talks to the kit's loopback MinIO (default http://127.0.0.1:9440, the port
# IS the store's identity) with that store's login, writes one object under a throwaway doc id
# and deletes it. The login is SIGN_LIST_AK/SIGN_LIST_SK, else the kit's KIT_PROOFS_MINIO_USER /
# KIT_PROOFS_MINIO_PASSWORD (the variables the publisher reads); no login is written in this file.
# If that store is not answering, or no login is set, the store half says SKIP and exits 0 — it
# never reaches for another endpoint or another credential.
#
# Run:  ~/.claude/engine/skills/prove/assets/__tests__/sign-list.test.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"
EP="${SIGN_LIST_ENDPOINT:-http://127.0.0.1:9440}"
BUCKET="${SIGN_LIST_BUCKET:-proofs}"
export AWS_ACCESS_KEY_ID="${SIGN_LIST_AK:-${KIT_PROOFS_MINIO_USER:-}}" AWS_SECRET_ACCESS_KEY="${SIGN_LIST_SK:-${KIT_PROOFS_MINIO_PASSWORD:-}}"
export AWS_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true
unset AWS_PROFILE AWS_SESSION_TOKEN

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# Offline, before any store: a doc id with '/' would widen the grant over nested docs.
if out="$(PROVE_S3_BUCKET=b AWS_ACCESS_KEY_ID=A AWS_SECRET_ACCESS_KEY=S python3 -I "$assets/sign-post.py" "doc/sub" 60 2>&1)"; then
  no "a doc id with '/' is refused" "signed: $(printf '%s' "$out" | head -c 120)"
else ok "a doc id with '/' is refused, nothing signed"; fi
if PROVE_S3_BUCKET=b AWS_ACCESS_KEY_ID=A AWS_SECRET_ACCESS_KEY=S python3 -I "$assets/sign-post.py" "doc-ok" 60 >/dev/null 2>&1; then
  ok "…and its nearest legal neighbour, a one-segment id, still signs"
else no "one-segment doc id signs"; fi

code="$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$EP/" || true)"
if [ -z "$code" ] || [ "$code" = 000 ]; then
  echo "SKIP sign-list (store half): no store answering at $EP"; echo "sign-list: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?
fi
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "SKIP sign-list (store half): no login for $EP — set KIT_PROOFS_MINIO_USER and KIT_PROOFS_MINIO_PASSWORD (or SIGN_LIST_AK/SIGN_LIST_SK)"; echo "sign-list: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?
fi

doc="boardrcpt-selftest-$$-$RANDOM"
key="events/${doc}/1-test.json"
tmp="$(mktemp -d)"; trap 'aws s3api delete-object --endpoint-url "$EP" --bucket "$BUCKET" --key "$key" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
echo '{"id":"selftest"}' > "$tmp/ev.json"
if ! aws s3api put-object --endpoint-url "$EP" --bucket "$BUCKET" --key "$key" --body "$tmp/ev.json" >/dev/null 2>"$tmp/put.err"; then
  no "seed object written to $EP" "$(cat "$tmp/put.err")"; echo "sign-list: $pass passed, $fail failed"; exit 1
fi

mint() {  # mint <prefix> -> listUrl for the local store, signed by sign-post.py's own function
  python3 - "$assets/sign-post.py" "$EP/$BUCKET/" "$1" <<'PY'
import importlib.util, sys, os, datetime
spec = importlib.util.spec_from_file_location("signpost", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
now = datetime.datetime.now(datetime.timezone.utc)
print(m._presign_list(sys.argv[2], sys.argv[3], "us-east-1", os.environ["AWS_ACCESS_KEY_ID"], os.environ["AWS_SECRET_ACCESS_KEY"], None, now, 300))
PY
}

url="$(mint "events/${doc}/")"
c="$(curl -s -m 5 -o "$tmp/list.xml" -w '%{http_code}' "$url")"
if [ "$c" = 200 ] && grep -q "<Key>${key}</Key>" "$tmp/list.xml"; then ok "listUrl lists the board's own prefix and returns the stored key (HTTP 200)"
else no "listUrl returns the stored key" "HTTP $c $(head -c 300 "$tmp/list.xml")"; fi

empty="$(mint "events/${doc}-none/")"
c="$(curl -s -m 5 -o "$tmp/empty.xml" -w '%{http_code}' "$empty")"
if [ "$c" = 200 ] && ! grep -q "<Key>" "$tmp/empty.xml"; then ok "a prefix holding nothing answers 200 with no <Key> — the 'not stored' shape the page reads"
else no "empty prefix lists nothing" "HTTP $c $(head -c 300 "$tmp/empty.xml")"; fi

# Controls: the same URL, one thing changed. Each must be refused, or the 200 above proves nothing.
bad="${url%?}$( [ "${url: -1}" = 0 ] && echo 1 || echo 0 )"
c="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$bad")"
if [ "$c" = 403 ]; then ok "control: one flipped signature digit is refused (403)"; else no "tampered signature refused" "HTTP $c"; fi
widened="$(printf '%s' "$url" | sed "s#prefix=events%2F${doc}%2F#prefix=events%2F#")"
c="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$widened")"
if [ "$c" = 403 ]; then ok "control: widening the prefix to all of events/ is refused (403) — the grant is this board's only"
else no "widened prefix refused" "HTTP $c"; fi

echo
echo "sign-list: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
