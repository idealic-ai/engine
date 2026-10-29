#!/usr/bin/env bash
# state-cas-race.sh [N] — fire N parallel state-append against ONE fresh doc, then assert
# the doc ends with exactly N events. This is the CAS gate: with the conditional PUT, a real
# concurrent race must lose zero updates. Run with NAIVE=1 to prove the test has teeth
# (last-writer-wins loses updates → the assertion fails, as it should).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/../_prove-s3-env.sh"
: "${PROVE_S3_BUCKET:?PROVE_S3_BUCKET not set (env or project .env)}"

N="${1:-10}"
doc="cas-race-$$-${RANDOM}"
key="$(prove_state_key "$doc")"
# bash 3.2 expands "${arr[@]}" on an EMPTY array as an unbound-variable FATAL under `set -u`, so
# every expansion takes the ${arr[@]+…} guard the shipped scripts already use. Without it this gate
# died at the verify step on any config with no PROVE_S3_PROFILE — which is the supported local
# config — so it has never actually asserted anything there.
# ENDPOINT_ARG is not optional either: an `aws s3 cp` without it goes to AWS, whatever endpoint the
# rest of the run resolved. A test that reaches a real cloud account is a worse failure than a test
# that does not run.
awsargs=(${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} ${ENDPOINT_ARG[@]+"${ENDPOINT_ARG[@]}"})
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT

echo "racing N=$N appenders → s3://$PROVE_S3_BUCKET/$key  (NAIVE=${NAIVE:-0})"
for i in $(seq 1 "$N"); do
  printf '{"n":%d}' "$i" > "$d/ev-$i.json"
  ( "$here/../state-append.sh" "$doc" "$d/ev-$i.json" >/dev/null 2>&1 ) &
done
wait

aws s3 cp "s3://$PROVE_S3_BUCKET/$key" "$d/final.json" ${awsargs[@]+"${awsargs[@]}"} >/dev/null 2>&1 \
  || { echo "FAIL — doc was never created"; exit 1; }
got="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("events",[])))' "$d/final.json")"
aws s3 rm "s3://$PROVE_S3_BUCKET/$key" ${awsargs[@]+"${awsargs[@]}"} >/dev/null 2>&1 || true

echo "appenders=$N  events-landed=$got"
if [ "$got" = "$N" ]; then
  echo "PASS — zero lost updates"; exit 0
else
  echo "FAIL — lost $((N - got)) update(s)"; exit 1
fi
