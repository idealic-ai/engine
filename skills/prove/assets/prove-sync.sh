#!/usr/bin/env bash
# prove-sync.sh <doc> — the agent-owned CAS fold. Drains events/<doc>/ into state/<doc>.json:
# for each event object, CAS-append it (state-append.sh) then delete it — but ONLY the keys
# captured at the start of the run, so a new event landing mid-fold is left for the next sync.
# A delete happens only after a successful append, so a failed fold leaves the event for retry.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

doc="${1:?usage: prove-sync.sh <doc>}"
: "${PROVE_S3_BUCKET:?prove-sync: PROVE_S3_BUCKET not set (env or project .env)}"
eprefix="${PROVE_S3_EVENTS_PREFIX}/${doc}/"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Snapshot the event keys up front (delete only these; newer ones wait for the next run).
aws s3api list-objects-v2 ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} --bucket "$PROVE_S3_BUCKET" \
  --prefix "$eprefix" --query 'Contents[].Key' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^None$' | grep -v '^$' > "$tmp/keys" || true

folded=0; failed=0
while IFS= read -r key; do
  [ -z "$key" ] && continue
  if ! aws s3api get-object ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} --bucket "$PROVE_S3_BUCKET" \
        --key "$key" "$tmp/ev.json" >/dev/null 2>&1; then
    failed=$((failed+1)); continue
  fi
  if "$here/state-append.sh" "$doc" "$tmp/ev.json" >/dev/null 2>&1; then
    aws s3api delete-object ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} --bucket "$PROVE_S3_BUCKET" \
      --key "$key" >/dev/null 2>&1 || true
    folded=$((folded+1))
  else
    failed=$((failed+1))                      # leave the event in place for the next sync
  fi
done < "$tmp/keys"

echo "prove-sync: folded ${folded} event(s) into ${PROVE_S3_STATE_PREFIX}/${doc}.json$([ "$failed" -gt 0 ] && echo " (${failed} left for retry)")"
