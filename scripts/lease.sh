#!/bin/bash
# lease.sh — the landing lease (v2): a short, self-expiring lease on a trunk, held for one PUSH.
#
# Usage:
#   engine lease show
#   engine lease take <seat> [--repo R] [--branch B] [--what "one line"]
#   engine lease release <seat>
#   engine lease check <seat> [--repo R] [--branch B]
#                                  may <seat> push to R's B now? 0 yes (nobody holds a live lease that covers it,
#                                  or <seat> does); 3 no (another seat holds one; the holder and its time left go
#                                  to stderr). A lease covers R/B when its repo= is empty or R, and its branch= is
#                                  empty or B; a check that names no --repo (or --branch) counts every lease.
#
# The protocol is kit sessions/2026_10_14_LAND_TREE_BRANCHES/builds/LANDING_LEASE_DRAFT.md (in force by the
# operator's ruling of 2026-10-28; made blocking by the ruling of 2026-10-30, leasegate). This script carries out
# its mechanics and nothing more:
#   - one file per seat under $LANDING_LEASE_DIR (default ~/.claude/engine/.landing-lease/); a writer writes
#     only its own file and reads everyone's
#   - taken=/expires= are UTC with a trailing Z; expires is taken + 10 minutes, absolute, never renewed
#   - a row whose expires= has passed is not a lease; nothing reaps it. The ceiling is enforced on read too:
#     a taken= in the future (a local-time stamp written as Z) or an expires= past taken + 10 minutes is not
#     trusted
#   - of two live rows the EARLIER taken= holds; a later taker deletes its own file and waits. Takes through
#     this command serialise on a mkdir lock, and the re-read after the write catches a hand-written file
#   - `take` creates the directory (and says so, for the landing record); `show` reports what is on disk at
#     read time: ABSENT says nothing about who holds a lease, EMPTY says nobody does
#   - $LEASE_DIR/history.log is the lease's holder history, append-only, one line per event:
#       <UTC Z> take seat=S repo=R branch=B expires=<UTC Z> what=TEXT     (a take that won)
#       <UTC Z> release seat=S                                             (a release that removed a file)
#       <UTC Z> override seat=S repo=R branch=B sha=SHA why=TEXT reason=TEXT
#     The override line is written by kit's .husky/pre-push, not by this script: when a seat sets
#     KIT_LEASE_CHECK_OVERRIDE and the hook could not ask the lease, the hook appends it here or refuses.
#     take/release append best-effort (a failed append never fails them); nothing here truncates or reads it
#     back, and `show` does not report it as a stray file
# It blocks through kit's pre-push hook, not through this script. By the operator's ruling of 2026-10-30
# (leasegate, reversing the 2026-10-28 "advisory" ruling), kit's .husky/pre-push runs
# `engine lease check <seat> --repo kit --branch main` on a push to refs/heads/main and refuses the push on exit 3.
# `check` itself stays read-only: it reads the lease files and writes nothing, so it neither takes nor renews a
# lease. Where a seat is named and this script cannot answer (any exit but 0 or 3, or `engine` off PATH), the hook
# refuses with exit 2 unless KIT_LEASE_CHECK_OVERRIDE carries a reason it can append to history.log; a pusher with
# no seat (a person or CI) is not checked. The seat is a name, not an identity: every seat runs as the same OS
# user, so the lease orders pushes between cooperating seats and grants nothing. Release after the remote-side
# verification, never on the push's exit code.
#
# Exit: 0 ok · 1 refused (another seat holds a live lease, this seat already holds one, or a release names a
# seat whose name maps to another seat's file) · 2 usage/IO error. `show` exits 0 whether or not the lease is
# held; its text is the interface.

set -uo pipefail

LEASE_DIR="${LANDING_LEASE_DIR:-$HOME/.claude/engine/.landing-lease}"
CEILING=600
# A taken= further than SKEW seconds in the future is not a lease: it is how a local-time stamp written with a
# Z reads on a machine east of UTC (v2's 8h10m hold on this UTC+8 machine).
SKEW=60
# Two `engine lease take` runs never interleave: each holds a mkdir lock ($LEASE_DIR/.take.lock) from its first
# look to its verdict, so of two concurrent takes exactly one wins (a lock older than 60s is a dead taker's and is
# broken). The lock binds only takers that use this command. A lease file written by hand is caught by the re-read
# SETTLE seconds after the write. That re-read is v2's accepted race, which it settles with a winner.
SETTLE="${LANDING_LEASE_SETTLE:-1}"
TAKE_LOCK=""
release_take_lock() { [ -n "$TAKE_LOCK" ] && rmdir "$TAKE_LOCK" 2>/dev/null; TAKE_LOCK=""; }
take_take_lock() {
  local l="$LEASE_DIR/.take.lock" i=0 m
  while ! mkdir "$l" 2>/dev/null; do
    i=$((i+1))
    if [ $((i % 20)) -eq 0 ]; then
      m="$(stat -f %m "$l" 2>/dev/null || stat -c %Y "$l" 2>/dev/null || echo "")"
      [ -n "$m" ] && [ $(( $(now_epoch) - m )) -gt 60 ] && rmdir "$l" 2>/dev/null
    fi
    [ "$i" -ge 1200 ] && return 1
    sleep 0.05
  done
  TAKE_LOCK="$l"; trap release_take_lock EXIT
}

die() { printf 'lease: %s\n' "$1" >&2; exit 2; }
now_epoch() { date -u +%s; }
epoch_to_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
iso_to_epoch() {
  local s="$1" e
  case "$s" in *Z) ;; *) return 1 ;; esac
  e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null)" && { printf '%s' "$e"; return 0; }
  e="$(date -u -d "$s" +%s 2>/dev/null)" && { printf '%s' "$e"; return 0; }
  return 1
}
seat_file() { printf '%s/%s.lease' "$LEASE_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^\./_/')"; }
field() { sed -n "s/^$1=//p" "$2" | head -1; }
# history — append one event line to $LEASE_DIR/history.log, best-effort: the lease itself is the seat files.
history() { printf '%s %s\n' "$(epoch_to_iso "$(now_epoch)")" "$1" >> "$LEASE_DIR/history.log" 2>/dev/null || true; }

# live_rows — one line per live lease: "<taken_epoch> <expires_epoch> <file>", earliest taken first, ties by path.
# A row is live only while taken <= now + SKEW and now < min(expires, taken + CEILING): the ceiling is enforced on
# read, not trusted from expires=. A row with an unreadable, non-UTC, future or over-ceiling stamp is not a lease
# (fail open), and is reported by `show`.
live_rows() {
  local f t e now
  now="$(now_epoch)"
  [ -d "$LEASE_DIR" ] || return 0
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    t="$(iso_to_epoch "$(field taken "$f")")" || continue
    e="$(iso_to_epoch "$(field expires "$f")")" || continue
    [ "$t" -le $((now + SKEW)) ] || continue
    [ "$e" -le $((t + CEILING)) ] || e=$((t + CEILING))
    [ "$e" -gt "$now" ] && printf '%s %s %s\n' "$t" "$e" "$f"
  done | sort -k1,1n -k3,3
}

# holder_file — the file of the live lease that holds the trunk (earliest taken=), or nothing.
holder_file() { live_rows | head -1 | cut -d' ' -f3-; }

# describe — one line (no trailing newline; callers add it) naming a row's holder and its effective time left.
describe() {
  local f="$1" t e now
  now="$(now_epoch)"; t="$(iso_to_epoch "$(field taken "$f")")"; e="$(iso_to_epoch "$(field expires "$f")")"
  [ "$e" -le $((t + CEILING)) ] || e=$((t + CEILING))
  printf '%s (repo=%s branch=%s taken=%s expires=%s, %ss left) %s' "$(field seat "$f")" "$(field repo "$f")" \
    "$(field branch "$f")" "$(field taken "$f")" "$(epoch_to_iso "$e")" "$((e - now))" "$(field what "$f")"
}

lease_show() {
  if [ ! -e "$LEASE_DIR" ]; then
    printf 'lease: %s is absent. That says nothing about who holds a lease (ABSENT is not EMPTY); `engine lease take` creates it.\n' "$LEASE_DIR"
    return 0
  fi
  [ -d "$LEASE_DIR" ] || die "$LEASE_DIR exists but is not a directory (fail open: land anyway and note it in the landing record)"
  [ -r "$LEASE_DIR" ] && [ -x "$LEASE_DIR" ] || die "cannot read $LEASE_DIR (fail open: land anyway and note it in the landing record)"
  local h rows f paths others=0
  rows="$(live_rows)"
  paths="$(printf '%s\n' "$rows" | cut -d' ' -f3-)"
  h="$(printf '%s\n' "$paths" | head -1)"
  for f in "$LEASE_DIR"/* "$LEASE_DIR"/.[!.]*; do
    [ -e "$f" ] || continue
    case "$f" in *.lease) [ -f "$f" ] && continue ;; */.take.lock|*/history.log) continue ;; esac
    others=$((others + 1))
  done
  if [ -n "$h" ]; then
    printf 'lease: held by %s\n' "$(describe "$h")"
    while IFS= read -r f; do
      [ -n "$f" ] && [ "$f" != "$h" ] || continue
      printf '  later take (yields to the holder): %s\n' "$(describe "$f")"
    done <<< "$paths"
  elif [ "$others" -eq 0 ]; then
    printf 'lease: %s exists and nobody holds a lease.\n' "$LEASE_DIR"
  else
    printf 'lease: %s holds no lease this command can read, and %s other file(s) that may be hand-written leases:\n' "$LEASE_DIR" "$others"
  fi
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    printf '%s\n' "$paths" | grep -qxF -- "$f" || printf '  not a lease (expired, future, over-ceiling or unreadable stamp): %s taken=%s expires=%s\n' \
      "$(field seat "$f")" "$(field taken "$f")" "$(field expires "$f")"
  done
  for f in "$LEASE_DIR"/* "$LEASE_DIR"/.[!.]*; do
    [ -e "$f" ] || continue
    case "$f" in *.lease) [ -f "$f" ] && continue ;; */.take.lock|*/history.log) continue ;; esac
    printf '  not a lease (unrecognised file; a lease is <seat>.lease with seat= repo= branch= taken= expires= what= lines): %s\n' "$(basename "$f")"
  done
  return 0
}

lease_take() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease take <seat> [--repo R] [--branch B] [--what TEXT]"
  shift
  local repo="" branch="" what=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --branch) branch="${2:-}"; shift 2 ;;
      --what) what="${2:-}"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  if [ ! -d "$LEASE_DIR" ]; then
    mkdir -p "$LEASE_DIR" 2>/dev/null || die "cannot create $LEASE_DIR (fail open: land anyway and note it in the landing record)"
    printf 'lease: created %s (say so in the landing record)\n' "$LEASE_DIR"
  fi
  local mine h
  mine="$(seat_file "$seat")"
  take_take_lock || die "another take has held $LEASE_DIR/.take.lock for over a minute (fail open: land anyway and note it in the landing record)"
  h="$(holder_file)"
  if [ -n "$h" ]; then
    if [ "$(field seat "$h")" = "$seat" ]; then
      printf 'lease: refused, %s already holds a live lease: %s\n' "$seat" "$(describe "$h")" >&2
    else
      printf 'lease: refused, held by %s\n' "$(describe "$h")" >&2
      printf 'lease: wait until it expires, then take again.\n' >&2
    fi
    return 1
  fi
  local t; t="$(now_epoch)"
  printf 'seat=%s\nrepo=%s\nbranch=%s\ntaken=%s\nexpires=%s\nwhat=%s\n' "$seat" "$repo" "$branch" \
    "$(epoch_to_iso "$t")" "$(epoch_to_iso $((t + CEILING)))" "$what" > "$mine" || die "cannot write $mine"
  sleep "$SETTLE"
  h="$(holder_file)"
  [ -n "$h" ] || { rm -f "$mine"; die "wrote $mine but cannot read it back as a lease"; }
  if [ "$h" != "$mine" ]; then
    rm -f "$mine"
    printf 'lease: refused, lost the tiebreak (earlier taken= wins) to %s\n' "$(describe "$h")" >&2
    printf 'lease: wait until it expires, then take again.\n' >&2
    return 1
  fi
  printf 'lease: taken by %s\n' "$(describe "$mine")"
  history "take seat=$seat repo=$repo branch=$branch expires=$(field expires "$mine") what=$what"
}

lease_release() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease release <seat>"
  local mine owner; mine="$(seat_file "$seat")"
  if [ -f "$mine" ]; then
    owner="$(field seat "$mine")"
    if [ "$owner" != "$seat" ]; then
      printf 'lease: refused, %s belongs to seat %s, whose name maps to the same file\n' "$mine" "$owner" >&2
      return 1
    fi
    rm -f "$mine" || die "cannot remove $mine"
    history "release seat=$seat"
    printf 'lease: released by %s\n' "$seat"
  else
    printf 'lease: %s held no lease file (%s)\n' "$seat" "$mine"
  fi
}

# lease_check — the read-only question a push gate asks. The holder is found exactly as `take` finds it, so a
# seat `check` lets through is a seat `take` would not have refused. It writes nothing; an absent directory
# means nobody holds a lease. Whether a caller fails open on exit 2 is the caller's choice, not this command's.
# With --repo/--branch it counts only the leases that cover that trunk: a lease taken for another
# repo's trunk no longer stops this one. `take` still keeps one slot across repos, so the earliest live lease of
# any repo is what `take` waits on; check's holder is the earliest live lease that covers the asked trunk.
lease_check() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease check <seat> [--repo R] [--branch B]"
  shift
  local repo="" branch=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] && [ -n "$2" ] || die "--repo needs a value"; repo="$2"; shift 2 ;;
      --branch) [ $# -ge 2 ] && [ -n "$2" ] || die "--branch needs a value"; branch="$2"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  if [ ! -e "$LEASE_DIR" ]; then
    printf 'lease: free (%s is absent, so nobody has taken a lease)\n' "$LEASE_DIR"
    return 0
  fi
  [ -d "$LEASE_DIR" ] && [ -r "$LEASE_DIR" ] && [ -x "$LEASE_DIR" ] || die "cannot read $LEASE_DIR"
  local h f r b
  h=""
  while read -r _ _ f; do
    [ -n "$f" ] || continue
    r="$(field repo "$f")"; b="$(field branch "$f")"
    [ -z "$repo" ] || [ -z "$r" ] || [ "$r" = "$repo" ] || continue
    [ -z "$branch" ] || [ -z "$b" ] || [ "$b" = "$branch" ] || continue
    h="$f"; break
  done <<< "$(live_rows)"
  if [ -z "$h" ]; then
    printf 'lease: free\n'
  elif [ "$(field seat "$h")" = "$seat" ]; then
    printf 'lease: held by %s, so %s may push\n' "$(describe "$h")" "$seat"
  else
    printf 'lease: %s may not push now; held by %s\n' "$seat" "$(describe "$h")" >&2
    return 3
  fi
}

cmd="${1:-show}"; [ $# -gt 0 ] && shift
case "$cmd" in
  show) lease_show ;;
  take) lease_take "$@" ;;
  release) lease_release "$@" ;;
  check) lease_check "$@" ;;
  -h|--help|help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $cmd (take|release|show|check)" ;;
esac
