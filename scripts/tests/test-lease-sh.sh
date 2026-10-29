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
# LEASE_SH points the suite at a modified copy, which is how each case was watched going red before it was
# trusted. The plant table (one plant per rule, each red) is in the LEASE build report of
# kit sessions/2026_10_28_DOMAIN_MANAGER_LOOM/builds/LEASE_REPORT.md; for example:
#   lease_show's absent test `! -e` -> `-f`            an empty, present directory reads as absent (L1)
#   epoch_to_iso without -u (local time written as Z)  L12
#   take's post-write re-read removed                  L14
#   the take lock removed                              L15
#   the settle sleep removed                           L14

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
# zz has the earlier taken= but the LATER expires= and the later file name, so neither name order nor
# expires order can pass this by coincidence.
printf 'seat=zz\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-3)))" "$(iso_at $((now+597)))" > "$DIR/zz.lease"
printf 'seat=aa\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-2)))" "$(iso_at $((now+200)))" > "$DIR/aa.lease"
out="$(run show 2>&1)"
assert_contains "lease: held by zz" "$out" "L8  of two live rows the EARLIER taken= holds, not the earlier name or the earlier expires"
assert_contains "aa" "$out" "L8  the later row is still listed"

# L9 — a seat name with a colon (the fleet's form) maps to a safe file name and keeps its name inside.
reset
run take manager:domain --repo engine --branch b >/dev/null 2>&1
assert_file_exists "$DIR/manager_domain.lease" "L9  'manager:domain' writes manager_domain.lease"
out="$(run show 2>&1)"
assert_contains "held by manager:domain" "$out" "L9  show prints the seat's real name"
run release manager:domain >/dev/null 2>&1
assert_file_not_exists "$DIR/manager_domain.lease" "L9  release by the same name finds the file"

# L10 — M2: a local-time stamp written with a Z (UTC+8 here) reads 8h in the future. It is not a lease.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now+28800)))" "$(iso_at $((now+29400)))" > "$DIR/ui.lease"
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L10 a taken= 8h in the future (local time written as Z) is not a holder"
assert_contains "not a lease" "$out" "L10 the future row is listed as not a lease"
out="$(run take studio --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L10 take over a future-stamped row succeeds"

# L11 — M2: expires= further than the 10-minute ceiling after taken= is capped on read, not trusted.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-700)))" "$(iso_at $((now+3600)))" > "$DIR/ui.lease"
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L11 a row taken 700s ago is dead whatever its expires= says"
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-10)))" "$(iso_at $((now+3600)))" > "$DIR/ui.lease"
out="$(run show 2>&1)"
left="$(printf '%s' "$out" | sed -n 's/.*, \(-\{0,1\}[0-9]*\)s left.*/\1/p' | head -1)"
assert_contains "held by ui" "$out" "L11 a row 10s old with expires= 1h out is live"
[ -n "$left" ] && [ "$left" -le 590 ] && pass "L11 its time left is capped at the ceiling ($left s)" || fail "L11 time left capped at the ceiling" "<= 590" "$left"

# L12 — the writer stamps UTC, even when the caller's TZ is not UTC.
reset
LANDING_LEASE_DIR="$DIR" TZ=Asia/Shanghai bash "$LEASE" take studio --repo kit --branch main >/dev/null 2>&1
taken="$(sed -n 's/^taken=//p' "$DIR/studio.lease" 2>/dev/null)"
te="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$taken" +%s 2>/dev/null || date -u -d "$taken" +%s 2>/dev/null || echo 0)"
d=$(( $(date -u +%s) - te )); [ "$d" -lt 0 ] && d=$((-d))
[ "$d" -le 10 ] && pass "L12 under TZ=Asia/Shanghai taken= is UTC (off by ${d}s)" || fail "L12 taken= is UTC under a non-UTC TZ" "within 10s of now" "off by ${d}s ($taken)"

# L13 — a stamp that does not END in Z is not a lease, even where date(1) would parse a prefix of it.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s+08:00\nexpires=%s+08:00\nwhat=x\n' "$(iso_at $((now-5)))" "$(iso_at $((now+595)))" > "$DIR/ui.lease"
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L13 a 'Z+08:00' stamp is not a lease"
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(date -r $((now-5)) +%Y-%m-%dT%H:%M:%S+08:00 2>/dev/null)" "$(date -r $((now+595)) +%Y-%m-%dT%H:%M:%S+08:00 2>/dev/null)" > "$DIR/ui.lease"
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L13 a '+08:00' stamp is not a lease"

# L14 — the post-write tiebreak: a row with an earlier taken= that appears AFTER take's first look still wins,
# and the later taker deletes its own file and refuses. The settle window is widened so the plant is deterministic.
reset; mkdir -p "$DIR"
( LANDING_LEASE_DIR="$DIR" LANDING_LEASE_SETTLE=3 bash "$LEASE" take studio --repo kit --branch main > "$TMP_DIR/l14.out" 2>&1; echo $? > "$TMP_DIR/l14.rc" ) &
i=0; while [ ! -f "$DIR/studio.lease" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-30)))" "$(iso_at $((now+570)))" > "$DIR/ui.lease"
wait
assert_eq 1 "$(cat "$TMP_DIR/l14.rc")" "L14 a take that is overtaken by an earlier taken= after its write is refused"
assert_contains "lost the tiebreak" "$(cat "$TMP_DIR/l14.out")" "L14 the refusal says it lost the tiebreak"
assert_file_not_exists "$DIR/studio.lease" "L14 the loser deletes its own file"
assert_file_exists "$DIR/ui.lease" "L14 the winner's file is untouched"

# L15 — M1: two seats taking at the same moment get exactly one winner, over many concurrent pairs.
# Before this fix 04b85c6 showed both-hold in 6/60 and 1/100 pairs (LEASE_CRITIQUE.md M1). With only a 1s settle
# and 80 takers at once, a write can land seconds after its stamp, and the suite then saw 1 bad pair in 40. The
# take-lock is what makes this deterministic. A failing pair prints both takes' output.
TRIALS=40; bad=0
for n in $(seq 1 $TRIALS); do
  D="$TMP_DIR/race/$n"; mkdir -p "$D"
  ( LANDING_LEASE_DIR="$D" bash "$LEASE" take aa > "$D/.out-aa" 2>&1; echo $? > "$D/.rc-aa" ) &
  ( LANDING_LEASE_DIR="$D" bash "$LEASE" take zz > "$D/.out-zz" 2>&1; echo $? > "$D/.rc-zz" ) &
done
wait
for n in $(seq 1 $TRIALS); do
  D="$TMP_DIR/race/$n"; w=0
  [ "$(cat "$D/.rc-aa")" = 0 ] && w=$((w+1)); [ "$(cat "$D/.rc-zz")" = 0 ] && w=$((w+1))
  [ "$w" = 1 ] || { bad=$((bad+1)); echo "  L15 trial $n: aa rc=$(cat "$D/.rc-aa") zz rc=$(cat "$D/.rc-zz")"; cat "$D/.out-aa" "$D/.out-zz" 2>/dev/null | sed 's/^/    /'; }
done
assert_eq 0 "$bad" "L15 $TRIALS concurrent take pairs each have exactly one winner"

# L16 — S2: a file the command cannot read as a lease is listed, and the directory is not called empty.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-5)))" "$(iso_at $((now+595)))" > "$DIR/ui"
out="$(run show 2>&1)"
assert_not_contains "nobody holds a lease" "$out" "L16 a hand-named file stops show saying nobody holds a lease"
assert_contains "unrecognised file" "$out" "L16 the hand-named file is listed as unrecognised"

# L17 — N4: two seat names that map to one file do not share it.
reset
run take a_b >/dev/null 2>&1
out="$(run take a/b 2>&1)"; rc=$?
assert_neq 0 "$rc" "L17 a second seat whose name maps to the same file is refused"
assert_contains "held by a_b" "$out" "L17 and the refusal names the real holder, not 'already holds'"
out="$(run release a/b 2>&1)"; rc=$?
assert_neq 0 "$rc" "L17 release by a colliding name is refused"
assert_file_exists "$DIR/a_b.lease" "L17 the real holder's file survives the colliding release"

# L18 — S1: every message line starts on its own line.
reset; run take ui >/dev/null 2>&1
out="$(run take studio 2>&1)"
assert_eq 2 "$(printf '%s\n' "$out" | grep -c '^lease: ')" "L18 a refusal prints its two lease: lines on separate lines"

# L19 — N1: a regular file at the directory's path is not reported absent.
reset; touch "$DIR"
out="$(run show 2>&1)"; rc=$?
assert_eq 2 "$rc" "L19 a regular file at the lease path is an error, exit 2"
assert_not_contains "absent" "$out" "L19 and is not reported absent"
rm -f "$DIR"

# L20 — the take lock is released after a take and is never listed as an unrecognised file.
reset; run take ui >/dev/null 2>&1
[ -d "$DIR/.take.lock" ] && fail "L20 the take lock is released" "no $DIR/.take.lock" "present" || pass "L20 the take lock is released after a take"
mkdir "$DIR/.take.lock"; out="$(run show 2>&1)"; rmdir "$DIR/.take.lock"
assert_not_contains "take.lock" "$out" "L20 show does not list a held take lock as a file"

# L21 — N3: a seat name starting with '.' still writes a file the lease glob sees.
reset
out="$(run take .hidden 2>&1)"; rc=$?
assert_eq 0 "$rc" "L21 a seat named '.hidden' can take"
assert_contains "held by .hidden" "$(run show 2>&1)" "L21 and show sees its lease"

# L22 — N7: a live a.lease.lease does not hide an expired a.lease from the not-a-lease list.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=x\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-5)))" "$(iso_at $((now+595)))" > "$DIR/a.lease.lease"
printf 'seat=old\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-1200)))" "$(iso_at $((now-600)))" > "$DIR/a.lease"
assert_contains "not a lease (expired" "$(run show 2>&1)" "L22 the expired a.lease is listed even beside a live a.lease.lease"

# L23 — N2: a directory that can be read but not searched is an error, not "nobody holds".
reset; mkdir -p "$DIR"; run take ui >/dev/null 2>&1; chmod 644 "$DIR"
out="$(run show 2>&1)"; rc=$?; chmod 755 "$DIR"
assert_eq 2 "$rc" "L23 an unsearchable lease directory is exit 2"
assert_not_contains "nobody holds" "$out" "L23 and is not reported as nobody holding"

# L24 — take waits for the take lock: while another take holds it, no lease file is written; once it is
# released the take proceeds. This is the deterministic guard for the lock that L15 relies on.
reset; mkdir -p "$DIR/.take.lock"
( LANDING_LEASE_DIR="$DIR" bash "$LEASE" take studio > "$TMP_DIR/l21.out" 2>&1; echo $? > "$TMP_DIR/l21.rc" ) &
sleep 1.5
assert_file_not_exists "$DIR/studio.lease" "L24 take writes nothing while another take holds the lock"
rmdir "$DIR/.take.lock"; wait
assert_eq 0 "$(cat "$TMP_DIR/l21.rc")" "L24 take proceeds once the lock is released"

# L25 — check: another seat's live lease means "may not push" (exit 3), naming the holder, and writes nothing.
reset; mkdir -p "$DIR"; run take runner --repo kit --branch main --what "PR 3" >/dev/null 2>&1
before="$(ls -A "$DIR" | sort)"
out="$(run check handbook 2>&1)"; rc=$?
assert_eq 3 "$rc" "L25 check by another seat while a lease is held is exit 3"
assert_contains "runner" "$out" "L25 and names the holder"
assert_contains "left" "$out" "L25 and says how long it has left"
assert_eq "$before" "$(ls -A "$DIR" | sort)" "L25 check writes nothing"

# L26 — check by the holder itself, on a free directory, and on an absent one: all may push (exit 0).
out="$(run check runner 2>&1)"; rc=$?
assert_eq 0 "$rc" "L26 the holder may push"
run release runner >/dev/null 2>&1
out="$(run check handbook 2>&1)"; rc=$?
assert_eq 0 "$rc" "L26 a released lease is free"
reset
out="$(run check handbook 2>&1)"; rc=$?
assert_eq 0 "$rc" "L26 an absent directory is free"
assert_file_not_exists "$DIR" "L26 check does not create the directory"

# L27 — an expired lease does not block: the same rule take uses.
reset; mkdir -p "$DIR"; t=$(( $(date -u +%s) - 900 ))
printf 'seat=runner\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=old\n' "$(iso_at "$t")" "$(iso_at $((t + 600)))" > "$DIR/runner.lease"
out="$(run check handbook 2>&1)"; rc=$?
assert_eq 0 "$rc" "L27 an expired lease does not stop a push"

exit_with_results
