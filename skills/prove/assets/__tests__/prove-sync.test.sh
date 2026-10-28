#!/usr/bin/env bash
# Offline harness for prove-sync.sh, the fold that drains events/<doc>/ into the state doc.
#
# The defect this exists for: the listing ran with `2>/dev/null … || true`, so a listing that
# FAILED (wrong store, refused credential, store down) printed "folded 0 event(s)" and exited 0 —
# word for word what an empty inbox prints. And two folds of one doc could run at once.
#
# The fold under test is the REAL file, copied beside a stub state-append.sh so that no state doc
# is written anywhere. `aws` is a shim on PATH for every case but one: the unreachable-store case
# runs the real CLI against a closed loopback port, so the failure text is the CLI's own.
#
# Run:  ~/.claude/engine/skills/prove/assets/__tests__/prove-sync.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

tmp="$(mktemp -d -t prove-sync)"
trap 'rm -rf "$tmp"' EXIT

# The fold, copied so its `$here/state-append.sh` resolves to the stub below.
mkdir -p "$tmp/assets" "$tmp/bin" "$tmp/locks"
cp "$assets/prove-sync.sh" "$assets/_prove-s3-env.sh" "$tmp/assets/"
cat > "$tmp/assets/state-append.sh" <<'STUB'
#!/usr/bin/env bash
# Records which event it was handed; optionally holds the fold open so a second run can collide.
cat "$2" >> "${SHIM_APPENDED:-/dev/null}"; echo >> "${SHIM_APPENDED:-/dev/null}"
if [ -n "${SHIM_APPEND_HOLD:-}" ]; then
  : > "$SHIM_APPEND_HOLD.entered"
  while [ ! -e "$SHIM_APPEND_HOLD.release" ]; do sleep 0.05; done
fi
exit 0
STUB
chmod +x "$tmp/assets/prove-sync.sh" "$tmp/assets/state-append.sh"
sync="$tmp/assets/prove-sync.sh"

cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SHIM_AWS_LOG:-/dev/null}"
case "$*" in
  *"list-objects-v2"*)
    case "${SHIM_LIST:-empty}" in
      fail)  echo "An error occurred (AccessDenied) when calling the ListObjectsV2 operation: Access Denied" >&2; exit 254 ;;
      empty) echo "None" ;;
      keys)  tr '\n' '\t' < "$SHIM_KEYS"; echo ;;
    esac ;;
  *"get-object"*)
    out="${*: -1}"
    key=""; prev=""
    for a in "$@"; do [ "$prev" = "--key" ] && key="$a"; prev="$a"; done
    printf '{"id":"%s"}' "${key##*/}" > "$out" ;;
  *"delete-object"*) : ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"

# Pinned config: no project .env can name a real store here.
export PROVE_S3_ENV=/nonexistent
export PROVE_S3_BUCKET=test-bucket
export PROVE_S3_REGION=us-east-9
export PROVE_S3_EVENTS_PREFIX=events
export PROVE_S3_STATE_PREFIX=state
export PROVE_SYNC_LOCK_DIR="$tmp/locks"
# `aws` is the resolver's own sentinel for "no endpoint": without it a manifest default could aim
# every case below at a real local store.
export PROVE_S3_ENDPOINT=aws
unset PROVE_S3_PROFILE PROVE_S3_PUBLIC_BASE AWS_ENDPOINT_URL
shimPATH="$tmp/bin:$PATH"

echo "== a listing that fails is a failure, not an empty inbox =="
PATH="$shimPATH" SHIM_LIST=fail "$sync" doc-a >"$tmp/a.out" 2>"$tmp/a.err"; rc=$?
if [ "$rc" -ne 0 ]; then ok "failed listing exits non-zero (rc=$rc)"; else no "failed listing exits non-zero" "rc=0"; fi
if ! grep -q "folded" "$tmp/a.out"; then ok "…and prints no 'folded N' line for a caller to misread"
else no "…and prints no 'folded N' line" "$(cat "$tmp/a.out")"; fi
if have "$(cat "$tmp/a.err")" "s3://test-bucket/events/doc-a/" && have "$(cat "$tmp/a.err")" "AccessDenied"; then
  ok "…and the sentence names the store and the store's own error"
else no "…and the sentence names the store and the error" "$(cat "$tmp/a.err")"; fi

echo "== the nearest legal neighbour: an empty inbox is still 'folded 0', exit 0 =="
PATH="$shimPATH" SHIM_LIST=empty "$sync" doc-b >"$tmp/b.out" 2>"$tmp/b.err"; rc=$?
if [ "$rc" -eq 0 ] && grep -Eq "^prove-sync: folded 0 event\(s\) into (proofs/)?state/doc-b\.json from s3://test-bucket/events/doc-b/ on AWS S3$" "$tmp/b.out"; then
  ok "empty inbox: exit 0, the summary keeps its shape and now names the store it listed"
else no "empty inbox: exit 0 + unchanged summary" "rc=$rc out=$(cat "$tmp/b.out") err=$(cat "$tmp/b.err")"; fi

echo "== per-event progress, and stdout stays one parseable line =="
printf 'events/doc-c/1-aa.json\nevents/doc-c/2-bb.json\nevents/doc-c/.grant-probe.json\n' > "$tmp/keys"
PATH="$shimPATH" SHIM_LIST=keys SHIM_KEYS="$tmp/keys" SHIM_APPENDED="$tmp/c.appended" "$sync" doc-c >"$tmp/c.out" 2>"$tmp/c.err"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$tmp/c.out" | tr -d ' ')" = 1 ] && grep -Eq "^prove-sync: folded 2 event\(s\) into (proofs/)?state/doc-c\.json" "$tmp/c.out"; then
  ok "two events: one stdout line, 'folded 2'"
else no "two events: one stdout line, 'folded 2'" "rc=$rc out=$(cat "$tmp/c.out")"; fi
if grep -q "\[1/2\] folded events/doc-c/1-aa.json" "$tmp/c.err" && grep -q "\[2/2\] folded events/doc-c/2-bb.json" "$tmp/c.err"; then
  ok "…and each event's progress is printed (stderr), numbered against the snapshot"
else no "…per-event progress lines" "$(cat "$tmp/c.err")"; fi
if ! grep -q "grant-probe" "$tmp/c.appended" 2>/dev/null; then ok "…and a dot-named probe key is not folded as an answer"
else no "…dot-named probe key skipped" "$(cat "$tmp/c.appended")"; fi

echo "== two folds of one doc: the second says so and leaves =="
hold="$tmp/hold"
printf 'events/doc-d/1-aa.json\n' > "$tmp/keysd"
PATH="$shimPATH" SHIM_LIST=keys SHIM_KEYS="$tmp/keysd" SHIM_APPEND_HOLD="$hold" "$sync" doc-d >"$tmp/d1.out" 2>"$tmp/d1.err" &
first=$!
for _ in $(seq 1 200); do [ -e "$hold.entered" ] && break; sleep 0.05; done
if [ -e "$hold.entered" ]; then
  PATH="$shimPATH" SHIM_LIST=keys SHIM_KEYS="$tmp/keysd" SHIM_AWS_LOG="$tmp/d2.aws" "$sync" doc-d >"$tmp/d2.out" 2>"$tmp/d2.err"; rc2=$?
  : > "$hold.release"; wait "$first"; rc1=$?
  if [ "$rc2" -eq 75 ] && grep -q "fold already running" "$tmp/d2.out"; then
    ok "second concurrent run prints 'fold already running' and exits 75"
  else no "second run: 'fold already running', exit 75" "rc2=$rc2 out=$(cat "$tmp/d2.out") err=$(cat "$tmp/d2.err")"; fi
  if [ ! -s "$tmp/d2.aws" ]; then ok "…without listing, reading or deleting anything"
  else no "…second run touched the store" "$(cat "$tmp/d2.aws")"; fi
  if [ "$(readlink "$PROVE_SYNC_LOCK_DIR/prove-sync.aws-s3.test-bucket.doc-d.lck" 2>/dev/null)" = "$first" ] || grep -q "pid $first" "$tmp/d2.out"; then
    ok "…the lock carries the holder's pid from the instant it exists (a symlink to the pid, made in one step)"
  else no "lock names the holder pid" "first=$first d2=$(cat "$tmp/d2.out")"; fi
  if [ "$rc1" -eq 0 ] && grep -q "folded 1 event" "$tmp/d1.out"; then ok "…while the first run finishes its fold normally"
  else no "first run finished" "rc1=$rc1 $(cat "$tmp/d1.out")"; fi
else
  : > "$hold.release"; wait "$first"
  no "the first fold never reached state-append" "$(cat "$tmp/d1.err")"
fi
PATH="$shimPATH" SHIM_LIST=empty "$sync" doc-d >"$tmp/d3.out" 2>&1; rc3=$?
if [ "$rc3" -eq 0 ]; then ok "…and once it is done the lock is released (a third run folds)"
else no "lock released after the first run" "rc=$rc3 $(cat "$tmp/d3.out")"; fi
# The lock a crashed run leaves behind: a symlink to a pid that is not running.
lkpath="$PROVE_SYNC_LOCK_DIR/prove-sync.aws-s3.test-bucket.doc-e.lck"
ln -s 999999 "$lkpath"
PATH="$shimPATH" SHIM_LIST=empty "$sync" doc-e >"$tmp/e.out" 2>"$tmp/e.err"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "no longer running" "$tmp/e.err"; then ok "a lock left by a dead run is taken over, and that is said"
else no "stale lock taken over" "rc=$rc err=$(cat "$tmp/e.err")"; fi
if [ ! -e "$lkpath" ] && [ ! -L "$lkpath" ]; then ok "…and released when that run ends"; else no "lock released after take-over" "$(ls -l "$lkpath")"; fi

echo "== a recycled pid: the number is alive, but it is not a fold =="
sleep 30 & sleeper=$!
lkpath="$PROVE_SYNC_LOCK_DIR/prove-sync.aws-s3.test-bucket.doc-g.lck"
ln -s "$sleeper" "$lkpath"
PATH="$shimPATH" SHIM_LIST=empty "$sync" doc-g >"$tmp/g.out" 2>"$tmp/g.err"; rc=$?
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null
if [ "$rc" -eq 0 ] && grep -q "not a prove-sync" "$tmp/g.err" && grep -q "folded 0" "$tmp/g.out"; then
  ok "a live pid that is not a prove-sync does not wedge the fold (taken over, rc 0)"
else no "recycled pid does not wedge" "rc=$rc out=$(cat "$tmp/g.out") err=$(cat "$tmp/g.err")"; fi

echo "== a doc id is one path segment =="
PATH="$shimPATH" SHIM_LIST=empty SHIM_AWS_LOG="$tmp/h.aws" "$sync" "doc-h/sub" >"$tmp/h.out" 2>"$tmp/h.err"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "one path segment" "$tmp/h.err" && [ ! -s "$tmp/h.aws" ]; then ok "a doc id with '/' is refused before any store call"
else no "doc id with '/' refused" "rc=$rc err=$(cat "$tmp/h.err")"; fi

echo "== the real CLI against a store that is not there =="
if command -v aws >/dev/null 2>&1; then
  AWS_ENDPOINT_URL=http://127.0.0.1:9 AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=y AWS_MAX_ATTEMPTS=1 \
    AWS_EC2_METADATA_DISABLED=true "$sync" doc-f >"$tmp/f.out" 2>"$tmp/f.err"; rc=$?
  if [ "$rc" -ne 0 ] && ! grep -q folded "$tmp/f.out" && grep -q "on http://127.0.0.1:9: " "$tmp/f.err"; then
    ok "real aws, closed port: non-zero, no 'folded', names the endpoint (rc=$rc)"
  else no "real aws, closed port" "rc=$rc out=$(cat "$tmp/f.out") err=$(cat "$tmp/f.err")"; fi
else
  ok "real-CLI case skipped: no aws on PATH"
fi

echo
echo "prove-sync: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
