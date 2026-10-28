#!/usr/bin/env bash
# prove-sync.sh <doc> — the agent-owned CAS fold. Drains events/<doc>/ into the state doc:
# for each event object, CAS-append it (state-append.sh) then delete it — but ONLY the keys
# captured at the start of the run, so a new event landing mid-fold is left for the next sync.
# A delete happens only after a successful append, so a failed fold leaves the event for retry.
#
# OUTPUT CONTRACT. stdout carries exactly one line, which callers read:
#   prove-sync: folded N event(s) into <state key> from s3://<bucket>/<events prefix> on <endpoint>[ (K left for retry)][ (S non-event key(s) skipped)]
# The store is on the line because a fold aimed at a reachable but WRONG store prints "folded 0"
# truthfully, and only the store's name tells that apart from an empty inbox.
# or, when another fold of the same doc holds the lock:
#   prove-sync: fold already running for <doc> (pid P) — not folding; run it again once that one ends
# Per-event progress and every error go to stderr.
#
# EXIT CODES. 0 the fold ran (some events may be left for retry, as the summary says) ·
# 2 the inbox could not be LISTED — nothing was folded, and "folded 0" is NOT printed, because a
#   listing that failed and an inbox that is empty used to print the same words (a board's answer
#   sat unfolded behind exactly that) ·
# 75 another fold of this doc is running (EX_TEMPFAIL: try again later) ·
# 1 usage / configuration.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

doc="${1:?usage: prove-sync.sh <doc>}"
# A doc id is one path segment. A '/' would make events/<doc>/ cover other boards' inboxes.
case "$doc" in
  */*|.|..|.*) echo "prove-sync: refusing doc id '${doc}' — a doc id is one path segment, with no '/' and no leading '.'" >&2; exit 1 ;;
esac
: "${PROVE_S3_BUCKET:?prove-sync: PROVE_S3_BUCKET not set (env or project .env)}"
# The key helpers and ENDPOINT_ARG come from _prove-s3-env.sh where that file defines them; the
# fallbacks are the layout this script has always used.
if type prove_events_key_prefix >/dev/null 2>&1; then eprefix="$(prove_events_key_prefix "$doc")"
else eprefix="${PROVE_S3_EVENTS_PREFIX:-events}/${doc}/"; fi
if type prove_state_key >/dev/null 2>&1; then statekey="$(prove_state_key "$doc")"
else statekey="${PROVE_S3_STATE_PREFIX:-state}/${doc}.json"; fi

# Which store, by the thing that tells stores apart — the endpoint (its port), not the bucket.
endpoint="${PROVE_S3_ENDPOINT_URL:-${AWS_ENDPOINT_URL_S3:-${AWS_ENDPOINT_URL:-}}}"
store="s3://${PROVE_S3_BUCKET}/${eprefix} on ${endpoint:-AWS S3}"
s3() { aws s3api ${PROFILE_ARG[@]+"${PROFILE_ARG[@]}"} ${ENDPOINT_ARG[@]+"${ENDPOINT_ARG[@]}"} "$@"; }

tmp="$(mktemp -d)"
lock=""
# Release only a lock that is still ours: after a take-over race the path may name another run.
cleanup() {
  rm -rf "$tmp"
  if [ -n "$lock" ] && [ "$(readlink "$lock" 2>/dev/null)" = "$$" ]; then rm -f "$lock"; fi
}
trap cleanup EXIT

# --- one fold per doc per store at a time ---------------------------------------------------------
# Two folds racing do not corrupt the doc (state-append is a CAS), but both list the same keys and
# both append them, so every answer lands twice and each run reports a count the other contradicts.
# The lock is a SYMLINK whose target is the holder's pid: `ln -s` creates the name and its content
# in one atomic step, so there is no moment where the lock exists without a pid for another run to
# read as stale (a mkdir-then-write lock has exactly that gap). macOS ships no flock(1).
lockdir="${PROVE_SYNC_LOCK_DIR:-${TMPDIR:-/tmp}}"
lockid="$(printf '%s' "${endpoint:-aws-s3}" | sed 's#^[a-z]*://##; s#[^A-Za-z0-9._-]#_#g')"
lockpath="${lockdir%/}/prove-sync.${lockid}.${PROVE_S3_BUCKET}.${doc}.lck"
mkdir -p "$lockdir"
take_lock() { ln -s "$$" "$lockpath" 2>/dev/null; }
# A pid is a live holder only if it is running AND is a prove-sync. A bare `kill -0` reads a
# recycled pid (any process that inherited the number) as the holder and wedges every fold until
# that process exits; it also fails with EPERM on another user's process, which is not "gone".
holder_cmd() { ps -p "$1" -o command= 2>/dev/null || true; }
is_fold() { case "$(holder_cmd "$1")" in *prove-sync*) return 0 ;; *) return 1 ;; esac; }
running() {
  echo "prove-sync: fold already running for ${doc} (pid $1) — not folding; run it again once that one ends"
  exit 75
}
if ! take_lock; then
  holder="$(readlink "$lockpath" 2>/dev/null || true)"
  case "$holder" in ''|*[!0-9]*) holder="" ;; esac
  if [ -n "$holder" ] && is_fold "$holder"; then running "$holder"; fi
  cmd="$(holder_cmd "${holder:-0}")"
  if [ -z "$holder" ]; then why="it names no pid"
  elif [ -z "$cmd" ]; then why="pid ${holder} is no longer running"
  else why="pid ${holder} is now a different process (${cmd%% *}), not a prove-sync"; fi
  echo "prove-sync: taking over a stale lock (${lockpath}: ${why})" >&2
  # Move the stale lock aside rather than deleting it, then check what was moved. If another run
  # took the lock over between our read and our move, we have just moved ITS live lock: put it
  # back (ln -s, which never overwrites) and stand down.
  aside="${lockpath}.stale.$$"
  if mv "$lockpath" "$aside" 2>/dev/null; then
    moved="$(readlink "$aside" 2>/dev/null || true)"
    if [ "$moved" != "${holder}" ] && [ -n "$moved" ] && is_fold "$moved"; then
      ln -s "$moved" "$lockpath" 2>/dev/null || true
      rm -f "$aside"
      running "$moved"
    fi
    rm -f "$aside"
  fi
  if ! take_lock; then running "$(readlink "$lockpath" 2>/dev/null || echo '?')"; fi
fi
lock="$lockpath"

# --- snapshot the event keys up front (delete only these; newer ones wait for the next run) ------
# The listing's own status decides. Its stderr is kept and quoted: the store's own words
# (AccessDenied, NoSuchBucket, connection refused) are the diagnosis.
if ! s3 list-objects-v2 --bucket "$PROVE_S3_BUCKET" --prefix "$eprefix" \
       --query 'Contents[].Key' --output text >"$tmp/list" 2>"$tmp/list.err"; then
  err="$(tr '\n' ' ' < "$tmp/list.err" | sed 's/  */ /g; s/^ //; s/ $//; s/\.$//' | cut -c1-400)"
  echo "prove-sync: could not list the events inbox ${store}: ${err:-the aws CLI failed and printed nothing}. Nothing was folded; an unreadable inbox is not an empty one." >&2
  exit 2
fi
tr '\t' '\n' < "$tmp/list" | grep -v '^None$' | grep -v '^$' > "$tmp/keys" || true
total="$(grep -cv '/\.[^/]*$' "$tmp/keys" || true)"
echo "prove-sync: ${total} event(s) to fold from ${store}" >&2

folded=0; failed=0; skipped=0; n=0; ndel=0
while IFS= read -r key; do
  [ -z "$key" ] && continue
  # A dot-prefixed basename is not an event. The publisher spends the board's write grant once
  # against the real destination before shipping it, and that probe object lands in this prefix;
  # folding it would append a phantom answer to the board. The publisher deletes it, so this is
  # the second defence, for the run where the delete did not land.
  case "${key##*/}" in
    .*) skipped=$((skipped+1)); echo "prove-sync: skipped ${key} (not an event)" >&2; continue ;;
  esac
  n=$((n+1))
  if ! s3 get-object --bucket "$PROVE_S3_BUCKET" --key "$key" "$tmp/ev.json" >/dev/null 2>"$tmp/get.err"; then
    failed=$((failed+1))
    echo "prove-sync: [${n}/${total}] left ${key} for retry — read failed: $(tr '\n' ' ' < "$tmp/get.err" | cut -c1-200)" >&2
    continue
  fi
  if "$here/state-append.sh" "$doc" "$tmp/ev.json" >/dev/null 2>"$tmp/append.err"; then
    folded=$((folded+1))
    if s3 delete-object --bucket "$PROVE_S3_BUCKET" --key "$key" >/dev/null 2>"$tmp/del.err"; then
      echo "prove-sync: [${n}/${total}] folded ${key}" >&2
    else
      ndel=$((ndel+1))
      echo "prove-sync: [${n}/${total}] folded ${key}, but could not delete it ($(tr '\n' ' ' < "$tmp/del.err" | cut -c1-200)); the next fold appends it again, which readers dedupe by id" >&2
    fi
  else
    failed=$((failed+1))                      # leave the event in place for the next sync
    echo "prove-sync: [${n}/${total}] left ${key} for retry — append failed: $(tr '\n' ' ' < "$tmp/append.err" | cut -c1-200)" >&2
  fi
done < "$tmp/keys"

echo "prove-sync: folded ${folded} event(s) into ${statekey} from ${store}$([ "$failed" -gt 0 ] && echo " (${failed} left for retry)")$([ "$skipped" -gt 0 ] && echo " (${skipped} non-event key(s) skipped)")"
