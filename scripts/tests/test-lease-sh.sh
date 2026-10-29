#!/bin/bash
# tests/test-lease-sh.sh — Tests for lease.sh (`engine lease take|release|show`), the landing lease v2.
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-lease-sh.sh
#      bash ~/.claude/engine/scripts/tests/test-lease-sh.sh
#
# The lease v2 text (kit sessions/2026_10_14_LAND_TREE_BRANCHES/builds/LANDING_LEASE_DRAFT.md) said, as
# measured, that ~/.claude/engine/.landing-lease/ "does not exist yet". The first take created it, and the
# sentence stayed, so a seat reading the lease was told the directory was absent while it sat there empty.
# The lease's own rule is that ABSENT is not EMPTY: absent says nothing about who holds a lease, empty says
# nobody does. L1/L2 hold `show` to reporting what is on disk at read time, and the rest hold take/release
# to the lease's rules (own file per seat, UTC Z stamps, 10-minute absolute ceiling, the earlier taken= wins).
#
# LEASE_SH points the suite at a modified copy, which is how L1 was watched going red before it was trusted:
#   the directory test in lease_show changed from `-d` to `-f`
#     -> an empty, present directory reads as absent (L1 goes red)

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

LEASE="${LEASE_SH:-$(cd "$(dirname "$0")/.." && pwd)/lease.sh}"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

DIR="$TMP_DIR/.landing-lease"
run() { LANDING_LEASE_DIR="$DIR" bash "$LEASE" "$@"; }
iso_at() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
reset() { rm -rf "$DIR"; }

# L1 — the false message: a present, empty directory must be reported as present and empty.
reset; mkdir -p "$DIR"
out="$(run show 2>&1)"; rc=$?
assert_eq 0 "$rc" "L1  show on an empty directory exits 0"
assert_contains "nobody holds a lease" "$out" "L1  show on an empty directory says nobody holds a lease"
assert_not_contains "does not exist" "$out" "L1  show on a present directory never says it does not exist"
assert_not_contains "absent" "$out" "L1  show on a present directory never calls it absent"

# L2 — the control: an absent directory is reported absent, and as saying nothing about holders.
reset
out="$(run show 2>&1)"; rc=$?
assert_eq 0 "$rc" "L2  show on an absent directory exits 0"
assert_contains "absent" "$out" "L2  show on an absent directory says it is absent"
assert_not_contains "nobody holds" "$out" "L2  an absent directory is not read as an empty one"

# L3 — take creates the directory, says it did, and writes UTC Z stamps 600s apart.
reset
out="$(run take studio --repo kit --branch main --what 'IDE-1 fix' 2>&1)"; rc=$?
assert_eq 0 "$rc" "L3  take on an absent directory succeeds"
assert_contains "created $DIR" "$out" "L3  take says it created the directory (the landing record must say so)"
f="$DIR/studio.lease"
assert_file_exists "$f" "L3  take writes the seat's own file"
taken="$(sed -n 's/^taken=//p' "$f")"; expires="$(sed -n 's/^expires=//p' "$f")"
assert_contains 'Z$' "$taken" "L3  taken= is UTC with a trailing Z"
te="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$taken" +%s 2>/dev/null || date -u -d "$taken" +%s)"
ee="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s 2>/dev/null || date -u -d "$expires" +%s)"
assert_eq 600 "$((ee - te))" "L3  expires= is taken= plus the 10-minute ceiling"

# L4 — a second seat is refused over an unexpired lease, and the refusal names the holder.
out="$(run take ui --repo kit --branch main --what 'other' 2>&1)"; rc=$?
assert_neq 0 "$rc" "L4  take over another seat's unexpired lease is refused"
assert_contains "studio" "$out" "L4  the refusal names the holder"
assert_contains "$expires" "$out" "L4  the refusal names when the lease expires"
assert_file_not_exists "$DIR/ui.lease" "L4  the refused seat leaves no file behind"
out="$(run show 2>&1)"
assert_contains "held by studio" "$out" "L4  show names the live holder"

# L5 — a seat holds at most one lease.
out="$(run take studio --repo kit --branch main 2>&1)"; rc=$?
assert_neq 0 "$rc" "L5  a seat already holding a live lease is refused a second"

# L6 — release deletes only the seat's own file; the trunk is then free.
run release studio >/dev/null 2>&1
assert_file_not_exists "$f" "L6  release deletes the seat's own file"
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L6  after release, show reports nobody holds a lease"

# L7 — an expired lease is not a lease: no reaper needed, any seat may take.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=old\n' "$(iso_at $((now-1200)))" "$(iso_at $((now-600)))" > "$DIR/ui.lease"
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L7  an expired row does not count as a holder"
out="$(run take studio --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L7  take over an expired lease succeeds"

# L8 — the tiebreak: when two live files exist, the EARLIER taken= wins and the later taker backs off.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=zz\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-3)))" "$(iso_at $((now+597)))" > "$DIR/zz.lease"
printf 'seat=aa\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-2)))" "$(iso_at $((now+598)))" > "$DIR/aa.lease"
out="$(run show 2>&1)"
assert_contains "held by zz" "$out" "L8  of two live rows the EARLIER taken= holds, not the first file name"
assert_contains "aa" "$out" "L8  the later row is still listed"

# L9 — a seat name with a colon (the fleet's form) maps to a safe file name and keeps its name inside.
reset
run take manager:domain --repo engine --branch b >/dev/null 2>&1
assert_file_exists "$DIR/manager_domain.lease" "L9  'manager:domain' writes manager_domain.lease"
out="$(run show 2>&1)"
assert_contains "held by manager:domain" "$out" "L9  show prints the seat's real name"
run release manager:domain >/dev/null 2>&1
assert_file_not_exists "$DIR/manager_domain.lease" "L9  release by the same name finds the file"

exit_with_results
