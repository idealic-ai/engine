#!/usr/bin/env bash
# state-append.sh <doc> <event.json> — atomically append ONE event to state/<doc>.json
# using S3 conditional writes (compare-and-swap): GET the doc + its ETag, merge the event
# into .events, PUT with If-Match=<etag> (or If-None-Match=* to create). On 412 (someone
# raced us) re-read and retry. This is the CAS "owner" write — no lost updates.
#
# Config: PROVE_S3_BUCKET/REGION/PROFILE (env or project .env), PROVE_S3_STATE_PREFIX (default state).
# NAIVE=1 disables the conditional (last-writer-wins) — used ONLY by the race test to show
# that without CAS, concurrent appends lose updates.
#
# NOTE: macOS ships bash 3.2, where "${arr[@]}" on an EMPTY array under `set -u` throws
# "unbound variable". Every array expansion below uses the ${arr[@]+"${arr[@]}"} guard so an
# empty PROFILE_ARG / cond expands to nothing instead of crashing.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

doc="${1:?usage: state-append.sh <doc> <event.json>}"
event="${2:?usage: state-append.sh <doc> <event.json>}"
[ -f "$event" ] || { echo "state-append: event file not found: $event" >&2; exit 1; }
: "${PROVE_S3_BUCKET:?state-append: PROVE_S3_BUCKET not set (env or project .env)}"

key="${PROVE_S3_STATE_PREFIX}/${doc}.json"
naive="${NAIVE:-0}"
attempts="${PROVE_S3_CAS_ATTEMPTS:-30}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

for attempt in $(seq 1 "$attempts"); do
  if aws s3api get-object ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} --bucket "$PROVE_S3_BUCKET" \
       --key "$key" "$tmp/cur.json" >"$tmp/meta.json" 2>/dev/null; then
    exists=1
    etag="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ETag"])' "$tmp/meta.json")"
  else
    exists=0
  fi

  if [ "$exists" = 1 ]; then
    python3 - "$tmp/cur.json" "$event" > "$tmp/new.json" <<'PY'
import json,sys
cur=json.load(open(sys.argv[1])); ev=json.load(open(sys.argv[2]))
cur.setdefault("events",[]).append(ev)
json.dump(cur,sys.stdout)
PY
  else
    python3 - "$event" "$doc" > "$tmp/new.json" <<'PY'
import json,sys
ev=json.load(open(sys.argv[1]))
json.dump({"docId":sys.argv[2],"events":[ev]},sys.stdout)
PY
  fi

  cond=()
  if [ "$naive" = 1 ]; then
    cond=()                                   # no guard → races clobber each other
  elif [ "$exists" = 1 ]; then
    cond=(--if-match "$etag")
  else
    cond=(--if-none-match "*")
  fi

  if aws s3api put-object ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} --bucket "$PROVE_S3_BUCKET" \
       --key "$key" --body "$tmp/new.json" --content-type application/json \
       ${cond[@]+"${cond[@]}"} >/dev/null 2>"$tmp/err"; then
    exit 0
  fi
  [ "$naive" = 1 ] && { cat "$tmp/err" >&2; exit 1; }   # naive PUT should not fail on a condition
  if ! grep -qiE "PreconditionFailed|ConditionalRequestConflict|412|OperationAborted" "$tmp/err"; then
    cat "$tmp/err" >&2; exit 1                           # a real error, not a race — surface it
  fi
  sleep "0.$(printf '%02d' $(( (RANDOM % 40) + 10 )))"   # 0.10–0.49s jittered backoff, then retry
done

echo "state-append: CAS still contended after $attempts attempts for $key" >&2
exit 2
