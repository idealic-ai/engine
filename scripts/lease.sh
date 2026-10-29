#!/bin/bash
# lease.sh — the landing lease (v2): a short, self-expiring, advisory lease on a trunk, held for one PUSH.
#
# Usage:
#   engine lease show
#   engine lease take <seat> [--repo R] [--branch B] [--what "one line"]
#   engine lease release <seat>
#
# The protocol is kit sessions/2026_10_14_LAND_TREE_BRANCHES/builds/LANDING_LEASE_DRAFT.md (in force by the
# operator's ruling of 2026-10-28). This script carries out its mechanics and nothing more:
#   - one file per seat under $LANDING_LEASE_DIR (default ~/.claude/engine/.landing-lease/); a writer writes
#     only its own file and reads everyone's
#   - taken=/expires= are UTC with a trailing Z; expires is taken + 10 minutes, absolute, never renewed
#   - a row whose expires= has passed is not a lease; nothing reaps it
#   - of two live rows the EARLIER taken= holds; a later taker deletes its own file and waits
#   - `take` creates the directory (and says so, for the landing record); `show` reports what is on disk at
#     read time: ABSENT says nothing about who holds a lease, EMPTY says nobody does
# It is advisory and fails open: it never blocks a push, and a seat that cannot run it lands anyway and says so
# in its landing record. Release after the remote-side verification, never on the push's exit code.
#
# Exit: 0 ok · 1 refused (another seat holds a live lease, or this seat already holds one) · 2 usage/IO error.

set -uo pipefail

LEASE_DIR="${LANDING_LEASE_DIR:-$HOME/.claude/engine/.landing-lease}"
CEILING=600

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
seat_file() { printf '%s/%s.lease' "$LEASE_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; }
field() { sed -n "s/^$1=//p" "$2" | head -1; }

# live_rows — one line per live lease: "<taken_epoch> <expires_epoch> <file>", earliest taken first.
# A row with an unreadable or non-UTC stamp is not a lease (fail open), and is reported by `show`.
live_rows() {
  local f t e now
  now="$(now_epoch)"
  [ -d "$LEASE_DIR" ] || return 0
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    t="$(iso_to_epoch "$(field taken "$f")")" || continue
    e="$(iso_to_epoch "$(field expires "$f")")" || continue
    [ "$e" -gt "$now" ] && printf '%s %s %s\n' "$t" "$e" "$f"
  done | sort -n -k1,1 -k3,3
}

# holder_file — the file of the live lease that holds the trunk (earliest taken=), or nothing.
holder_file() { live_rows | head -1 | cut -d' ' -f3-; }

describe() {
  local f="$1" e now
  now="$(now_epoch)"; e="$(iso_to_epoch "$(field expires "$f")")"
  printf '%s (repo=%s branch=%s taken=%s expires=%s, %ss left) %s\n' "$(field seat "$f")" "$(field repo "$f")" \
    "$(field branch "$f")" "$(field taken "$f")" "$(field expires "$f")" "$((e - now))" "$(field what "$f")"
}

lease_show() {
  if [ ! -d "$LEASE_DIR" ]; then
    printf 'lease: %s is absent. That says nothing about who holds a lease (ABSENT is not EMPTY); `engine lease take` creates it.\n' "$LEASE_DIR"
    return 0
  fi
  [ -r "$LEASE_DIR" ] || die "cannot read $LEASE_DIR (fail open: land anyway and note it in the landing record)"
  local h rows f live_count=0
  rows="$(live_rows)"
  h="$(printf '%s\n' "$rows" | head -1 | cut -d' ' -f3-)"
  if [ -z "$h" ]; then
    printf 'lease: %s exists and nobody holds a lease.\n' "$LEASE_DIR"
  else
    printf 'lease: held by %s' "$(describe "$h")"
    while IFS= read -r line; do
      f="${line#* * }"; [ -n "$f" ] && [ "$f" != "$h" ] || continue
      printf '  later take (yields to the holder): %s' "$(describe "$f")"
    done <<< "$rows"
  fi
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    live_count=0
    printf '%s\n' "$rows" | grep -qF -- " $f" && live_count=1
    [ "$live_count" = 1 ] || printf '  not a lease (expired or unreadable stamp): %s taken=%s expires=%s\n' \
      "$(field seat "$f")" "$(field taken "$f")" "$(field expires "$f")"
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
  h="$(holder_file)"
  if [ -n "$h" ]; then
    if [ "$h" = "$mine" ] || [ "$(field seat "$h")" = "$seat" ]; then
      printf 'lease: refused, %s already holds a live lease: %s' "$seat" "$(describe "$h")" >&2
    else
      printf 'lease: refused, held by %s' "$(describe "$h")" >&2
      printf 'lease: wait until %s, then take again.\n' "$(field expires "$h")" >&2
    fi
    return 1
  fi
  local t; t="$(now_epoch)"
  printf 'seat=%s\nrepo=%s\nbranch=%s\ntaken=%s\nexpires=%s\nwhat=%s\n' "$seat" "$repo" "$branch" \
    "$(epoch_to_iso "$t")" "$(epoch_to_iso $((t + CEILING)))" "$what" > "$mine" || die "cannot write $mine"
  h="$(holder_file)"
  if [ "$h" != "$mine" ]; then
    rm -f "$mine"
    printf 'lease: refused, lost the tiebreak (earlier taken= wins) to %s' "$(describe "$h")" >&2
    printf 'lease: wait until %s, then take again.\n' "$(field expires "$h")" >&2
    return 1
  fi
  printf 'lease: taken by %s' "$(describe "$mine")"
}

lease_release() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease release <seat>"
  local mine; mine="$(seat_file "$seat")"
  if [ -f "$mine" ]; then
    rm -f "$mine" || die "cannot remove $mine"
    printf 'lease: released by %s\n' "$seat"
  else
    printf 'lease: %s held no lease file (%s)\n' "$seat" "$mine"
  fi
}

cmd="${1:-show}"; [ $# -gt 0 ] && shift
case "$cmd" in
  show) lease_show ;;
  take) lease_take "$@" ;;
  release) lease_release "$@" ;;
  -h|--help|help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $cmd (take|release|show)" ;;
esac
