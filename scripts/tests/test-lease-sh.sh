#!/bin/bash
# tests/test-lease-sh.sh — Tests for lease.sh (`engine lease take|release|show|check`), the landing lease v2, per
# (repo, branch) since L40.
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
f="$DIR/studio@kit@main.lease"
assert_file_exists "$f" "L3  take writes the seat's own file for its scope (<seat>@<repo>@<branch>.lease)"
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
assert_file_not_exists "$DIR/ui@kit@main.lease" "L4  the refused seat leaves no file behind"
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
assert_file_exists "$DIR/manager_domain@engine@b.lease" "L9  'manager:domain' writes manager_domain@engine@b.lease"
out="$(run show 2>&1)"
assert_contains "held by manager:domain" "$out" "L9  show prints the seat's real name"
run release manager:domain >/dev/null 2>&1
assert_file_not_exists "$DIR/manager_domain@engine@b.lease" "L9  release by the same name finds the file"

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
taken="$(sed -n 's/^taken=//p' "$DIR/studio@kit@main.lease" 2>/dev/null)"
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
i=0; while [ ! -f "$DIR/studio@kit@main.lease" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-30)))" "$(iso_at $((now+570)))" > "$DIR/ui.lease"
wait
assert_eq 1 "$(cat "$TMP_DIR/l14.rc")" "L14 a take that is overtaken by an earlier taken= after its write is refused"
assert_contains "lost the tiebreak" "$(cat "$TMP_DIR/l14.out")" "L14 the refusal says it lost the tiebreak"
assert_file_not_exists "$DIR/studio@kit@main.lease" "L14 the loser deletes its own file"
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

# L28 — check --repo: a lease taken for another repo's trunk does not stop this repo's push; one for this repo does,
# and a check that names no repo counts every lease (the one-slot answer it gave before --repo existed).
reset; mkdir -p "$DIR"; run take runner --repo engine --branch main --what "engine PR" >/dev/null 2>&1
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L28 a lease for another repo does not stop a push to kit"
out="$(run check handbook --repo engine --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L28 a lease for the same repo still stops it"
assert_contains "runner" "$out" "L28 and names the holder"
out="$(run check handbook 2>&1)"; rc=$?
assert_eq 3 "$rc" "L28 a check that names no repo counts every lease"

# L29 — check --branch: a lease for another branch of the same repo does not count; the same branch does.
reset; mkdir -p "$DIR"; run take runner --repo kit --branch dev >/dev/null 2>&1
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L29 a lease on kit/dev does not stop a push to kit/main"
out="$(run check handbook --repo kit --branch dev 2>&1)"; rc=$?
assert_eq 3 "$rc" "L29 a lease on kit/dev stops a push to kit/dev"

# L30 — a lease taken with no --repo (or no --branch) names no scope, so it counts for every repo (fail closed on
# the lease, as before --repo existed).
reset; mkdir -p "$DIR"; run take runner >/dev/null 2>&1
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L30 an unscoped lease counts for kit/main"
reset; mkdir -p "$DIR"; run take runner --repo kit >/dev/null 2>&1
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L30 a lease with a repo and no branch counts for every branch of that repo"

# L31 — check's argument errors are usage errors (exit 2), so a gate cannot read a typo as "free".
out="$(run check handbook --repo 2>&1)"; rc=$?
assert_eq 2 "$rc" "L31 --repo with no value is exit 2"
out="$(run check handbook --what x 2>&1)"; rc=$?
assert_eq 2 "$rc" "L31 an unknown argument is exit 2"

# L32 — history.log: take and release append one line each; check appends nothing; show does not read it as a
# stray lease file. Kit's pre-push appends its override lines here too (KIT_LEASE_CHECK_OVERRIDE).
reset
run take runner --repo kit --branch main --what "PR 9" >/dev/null 2>&1
h="$DIR/history.log"
assert_file_exists "$h" "L32 take creates history.log"
assert_contains "$(printf '\ttake\tseat=runner\trepo=kit\tbranch=main\t')" "$(cat "$h")" "L32 take appends a take line"
before="$(cat "$h")"
run check handbook --repo kit --branch main >/dev/null 2>&1
assert_eq "$before" "$(cat "$h")" "L32 check appends nothing"
out="$(run show 2>&1)"
assert_not_contains "history.log" "$out" "L32 show does not report history.log as an unrecognised file"
run release runner >/dev/null 2>&1
assert_eq 2 "$(wc -l < "$h" | tr -d ' ')" "L32 release appends a second line"
assert_contains "$(printf '\trelease\tseat=runner')" "$(tail -1 "$h")" "L32 the release line names the seat"
run release runner >/dev/null 2>&1
assert_eq 2 "$(wc -l < "$h" | tr -d ' ')" "L32 a release that held nothing appends nothing"
reset; mkdir -p "$DIR"; printf 'x\n' > "$DIR/history.log"; run release runner >/dev/null 2>&1
out="$(run show 2>&1)"
assert_contains "nobody holds a lease" "$out" "L32 a directory holding only history.log reads as empty"

# L33 — check matches a lease's scope regardless of how the repo is cased or the branch is spelled: `Kit` is kit and
# `refs/heads/main` is main, on take and on check, in both directions. An exact-string match let a seat push inside a
# live lease taken as `--repo Kit` (fail open on spelling).
reset; mkdir -p "$DIR"; run take runner --repo Kit --branch main >/dev/null 2>&1
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L33 a lease taken as --repo Kit stops a check for kit"
reset; mkdir -p "$DIR"; run take runner --repo kit --branch main >/dev/null 2>&1
out="$(run check handbook --repo Kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L33 a lease taken as --repo kit stops a check for Kit"
reset; mkdir -p "$DIR"; run take runner --repo kit --branch refs/heads/main >/dev/null 2>&1
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L33 a lease taken on refs/heads/main stops a check for main"
reset; mkdir -p "$DIR"; run take runner --repo kit --branch main >/dev/null 2>&1
out="$(run check handbook --repo kit --branch refs/heads/main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L33 a lease taken on main stops a check for refs/heads/main"
reset; mkdir -p "$DIR"; t=$(date -u +%s)
printf 'seat=runner\nrepo=KIT\nbranch=refs/heads/main\ntaken=%s\nexpires=%s\nwhat=hand\n' "$(iso_at "$t")" "$(iso_at $((t + 600)))" > "$DIR/runner.lease"
out="$(run check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L33 a lease file that spells repo=KIT branch=refs/heads/main (not written by take) still covers kit/main"
reset; mkdir -p "$DIR"; run take runner --repo engine --branch main >/dev/null 2>&1
out="$(run check handbook --repo Kit --branch refs/heads/main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L33 folding does not widen: engine's lease still does not stop Kit"

# L34 — history.log is best-effort: a failed append never fails take or release (here history.log is a directory).
reset; mkdir -p "$DIR/history.log"
out="$(run take runner --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L34 take succeeds when history.log cannot be appended to"
assert_file_exists "$DIR/runner@kit@main.lease" "L34 and the lease is held"
out="$(run release runner 2>&1)"; rc=$?
assert_eq 0 "$rc" "L34 release succeeds when history.log cannot be appended to"

# L35 — an empty --repo or --branch is a usage error, not "every repo" (a gate passing an empty variable must not
# read as a check of nothing in particular).
reset; mkdir -p "$DIR"
out="$(run check handbook --repo "" --branch main 2>&1)"; rc=$?
assert_eq 2 "$rc" "L35 check --repo '' is exit 2"
out="$(run check handbook --repo kit --branch "" 2>&1)"; rc=$?
assert_eq 2 "$rc" "L35 check --branch '' is exit 2"

# L36 — of several live leases that cover the asked trunk, the EARLIEST taken= is the holder, as take decides it.
reset; mkdir -p "$DIR"; t=$(date -u +%s)
printf 'seat=first\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=a\n' "$(iso_at $((t - 120)))" "$(iso_at $((t + 480)))" > "$DIR/first.lease"
printf 'seat=second\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=b\n' "$(iso_at $((t - 60)))" "$(iso_at $((t + 540)))" > "$DIR/second.lease"
out="$(run check first --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L36 the earliest of two covering leases may push"
out="$(run check second --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L36 the later of two covering leases may not"
assert_contains "held by first" "$out" "L36 and is told the earliest holds it"
out="$(run check third --repo kit --branch main 2>&1)"; rc=$?
assert_contains "held by first" "$out" "L36 a third seat is told the earliest holds it"

# L37 — a history line is TAB-separated `<UTC Z>\t<event>\tkey=value…`, and no value carries a control byte: a
# newline, TAB or ESC in --what is folded to a space, so one take is exactly one line with the fields where they belong.
reset
run take runner --repo kit --branch main --what "$(printf 'one\ntwo\tthree\033[31mred')" >/dev/null 2>&1
h="$DIR/history.log"
assert_eq 1 "$(wc -l < "$h" | tr -d ' ')" "L37 a --what holding a newline still appends one line"
assert_eq 7 "$(awk -F'\t' '{print NF}' "$h")" "L37 the take line has seven TAB-separated fields"
assert_eq "what=one two three [31mred" "$(awk -F'\t' '{print $7}' "$h")" "L37 the control bytes in what= are folded to spaces"
assert_eq 0 "$(LC_ALL=C tr -d '\t\n' < "$h" | LC_ALL=C tr -d '[:print:]' | wc -c | tr -d ' ')" "L37 the line holds no control byte but its TABs and newline"

# L38 — with HOME and LANDING_LEASE_DIR both unset there is no lease store to read: a usage/IO error (exit 2), not a
# shell fault (exit 1, which a caller may read as something else).
out="$(env -u HOME -u LANDING_LEASE_DIR bash "$LEASE" check handbook --repo kit --branch main 2>&1)"; rc=$?
assert_eq 2 "$rc" "L38 check with no HOME and no LANDING_LEASE_DIR is exit 2"
assert_contains "LANDING_LEASE_DIR" "$out" "L38 and says the lease store cannot be found"

# L39 — the Unicode line separators U+0085 (NEL), U+2028 and U+2029 are folded to a space as well, so a reader that
# splits lines on them (Python splitlines, JS line terminators) still sees one take as one line.
reset
run take runner --repo kit --branch main --what "$(printf 'a\302\205b\342\200\250c\342\200\251d')" >/dev/null 2>&1
h="$DIR/history.log"
assert_eq "what=a b c d" "$(awk -F'\t' '{print $7}' "$h")" "L39 NEL, LS and PS in what= are folded to spaces"
assert_eq 0 "$(LC_ALL=C grep -c "$(printf '\302\205')\|$(printf '\342\200\250')\|$(printf '\342\200\251')" "$h")" "L39 history.log holds none of the three"

# L40-L47 — the lease is per (repo, branch). A live lease refuses a take only where its scope overlaps the taker's:
# the same normalised repo and branch, or a lease that names no repo (or no branch), which covers every repo (or
# every branch) exactly as `check` counts it (L30). A file with no repo=/branch= lines (written before scopes, or by
# hand) is therefore a lease on everything until it expires. Before this, take refused on ANY live lease, so an
# engine landing held kit's trunk and the reverse.

# L40 — an engine/main holder does not block a kit/main take, and both leases are then live.
reset
run take meta:engine --repo engine --branch main --what "engine PR" >/dev/null 2>&1
out="$(run take core:world --repo kit --branch main --what "kit PR" 2>&1)"; rc=$?
assert_eq 0 "$rc" "L40 a kit/main take succeeds while engine/main is held"
assert_contains "taken by core:world" "$out" "L40 and says it was taken"
assert_file_exists "$DIR/meta_engine@engine@main.lease" "L40 the engine/main lease is still on disk"
assert_file_exists "$DIR/core_world@kit@main.lease" "L40 the kit/main lease has its own file"
out="$(run check ui --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L40 a third seat's kit/main check now sees core:world"
assert_contains "core:world" "$out" "L40 and names core:world, not the engine holder"
out="$(run check ui --repo engine --branch main 2>&1)"; rc=$?
assert_contains "meta:engine" "$out" "L40 an engine/main check names meta:engine"

# L41 — a kit/main holder still blocks a second kit/main take, however the second spells the scope.
reset
run take core:world --repo kit --branch main >/dev/null 2>&1
out="$(run take packages:schemistry --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L41 a second kit/main take is refused"
assert_contains "held by core:world" "$out" "L41 and the refusal names the holder"
assert_file_not_exists "$DIR/packages_schemistry@kit@main.lease" "L41 the refused seat leaves no file"
out="$(run take packages:schemistry --repo Kit --branch refs/heads/main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L41 a take spelled --repo Kit --branch refs/heads/main is the same scope and is refused"
out="$(run take packages:schemistry --repo kit --branch dev 2>&1)"; rc=$?
assert_eq 0 "$rc" "L41 a kit/dev take is another scope and succeeds"
out="$(run take packages:schemistry --repo kit 2>&1)"; rc=$?
assert_eq 1 "$rc" "L41 a take with --repo kit and no branch covers kit/main and is refused"
out="$(run take packages:schemistry 2>&1)"; rc=$?
assert_eq 1 "$rc" "L41 a take with no scope covers every trunk and is refused"

# L42 — the tie-break within one scope: a row with an earlier taken= on the SAME scope that appears after the take's
# first look wins; the same plant on ANOTHER scope does not touch the take (the control that shows the tie-break is
# scoped, not global).
reset; mkdir -p "$DIR"
( LANDING_LEASE_DIR="$DIR" LANDING_LEASE_SETTLE=3 bash "$LEASE" take studio --repo kit --branch main > "$TMP_DIR/l42.out" 2>&1; echo $? > "$TMP_DIR/l42.rc" ) &
i=0; while [ ! -f "$DIR/studio@kit@main.lease" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
now=$(date -u +%s)
printf 'seat=ui\nrepo=kit\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-30)))" "$(iso_at $((now+570)))" > "$DIR/ui@kit@main.lease"
wait
assert_eq 1 "$(cat "$TMP_DIR/l42.rc")" "L42 a kit/main take overtaken by an earlier kit/main taken= is refused"
assert_contains "lost the tiebreak" "$(cat "$TMP_DIR/l42.out")" "L42 the refusal says it lost the tiebreak"
assert_file_not_exists "$DIR/studio@kit@main.lease" "L42 the loser deletes its own file"
reset; mkdir -p "$DIR"
( LANDING_LEASE_DIR="$DIR" LANDING_LEASE_SETTLE=3 bash "$LEASE" take studio --repo kit --branch main > "$TMP_DIR/l42b.out" 2>&1; echo $? > "$TMP_DIR/l42b.rc" ) &
i=0; while [ ! -f "$DIR/studio@kit@main.lease" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
now=$(date -u +%s)
printf 'seat=ui\nrepo=engine\nbranch=main\ntaken=%s\nexpires=%s\nwhat=x\n' "$(iso_at $((now-30)))" "$(iso_at $((now+570)))" > "$DIR/ui@engine@main.lease"
wait
assert_eq 0 "$(cat "$TMP_DIR/l42b.rc")" "L42 an earlier engine/main row does not win a kit/main tie-break"
assert_file_exists "$DIR/studio@kit@main.lease" "L42 and the kit/main take keeps its file"

# L43 — concurrent takes in two scopes both succeed, over many pairs; and the take lock is per scope, so a take is
# not held up by another scope's lock.
TRIALS=20; bad=0
for n in $(seq 1 $TRIALS); do
  D="$TMP_DIR/race2/$n"; mkdir -p "$D"
  ( LANDING_LEASE_DIR="$D" bash "$LEASE" take aa --repo kit --branch main > "$D/.out-aa" 2>&1; echo $? > "$D/.rc-aa" ) &
  ( LANDING_LEASE_DIR="$D" bash "$LEASE" take zz --repo engine --branch main > "$D/.out-zz" 2>&1; echo $? > "$D/.rc-zz" ) &
done
wait
for n in $(seq 1 $TRIALS); do
  D="$TMP_DIR/race2/$n"
  [ "$(cat "$D/.rc-aa")" = 0 ] && [ "$(cat "$D/.rc-zz")" = 0 ] || { bad=$((bad+1)); echo "  L43 trial $n: aa rc=$(cat "$D/.rc-aa") zz rc=$(cat "$D/.rc-zz")"; cat "$D/.out-aa" "$D/.out-zz" 2>/dev/null | sed 's/^/    /'; }
done
assert_eq 0 "$bad" "L43 $TRIALS concurrent kit/main + engine/main take pairs both succeed"
TRIALS=20; bad=0
for n in $(seq 1 $TRIALS); do
  D="$TMP_DIR/race3/$n"; mkdir -p "$D"
  ( LANDING_LEASE_DIR="$D" bash "$LEASE" take aa --repo kit --branch main > "$D/.out-aa" 2>&1; echo $? > "$D/.rc-aa" ) &
  ( LANDING_LEASE_DIR="$D" bash "$LEASE" take zz --repo KIT --branch refs/heads/main > "$D/.out-zz" 2>&1; echo $? > "$D/.rc-zz" ) &
done
wait
for n in $(seq 1 $TRIALS); do
  D="$TMP_DIR/race3/$n"; w=0
  [ "$(cat "$D/.rc-aa")" = 0 ] && w=$((w+1)); [ "$(cat "$D/.rc-zz")" = 0 ] && w=$((w+1))
  [ "$w" = 1 ] || { bad=$((bad+1)); echo "  L43 trial $n (same scope): aa rc=$(cat "$D/.rc-aa") zz rc=$(cat "$D/.rc-zz")"; }
done
assert_eq 0 "$bad" "L43 $TRIALS concurrent same-scope pairs (kit/main and KIT/refs/heads/main) each have exactly one winner"
reset; mkdir -p "$DIR/.take.lock@kit@main"
start=$(date -u +%s)
out="$(run take zz --repo engine --branch main 2>&1)"; rc=$?
took=$(( $(date -u +%s) - start ))
assert_eq 0 "$rc" "L43 an engine/main take succeeds while kit/main's take lock is held"
[ "$took" -le 3 ] && pass "L43 and does not wait on it (${took}s)" || fail "L43 an engine/main take does not wait on kit/main's lock" "<= 3s" "${took}s"
( LANDING_LEASE_DIR="$DIR" bash "$LEASE" take aa --repo Kit --branch refs/heads/main > "$TMP_DIR/l43.out" 2>&1; echo $? > "$TMP_DIR/l43.rc" ) &
sleep 1.5
assert_file_not_exists "$DIR/aa@kit@main.lease" "L43 a kit/main take writes nothing while kit/main's take lock is held"
rmdir "$DIR/.take.lock@kit@main"; wait
assert_eq 0 "$(cat "$TMP_DIR/l43.rc")" "L43 and proceeds once it is released"

# L44 — an old lease file with no repo=/branch= lines covers everything until it expires: it refuses a kit/main and an
# engine/main take alike, and once expired it refuses nothing.
reset; mkdir -p "$DIR"; now=$(date -u +%s)
printf 'seat=old\ntaken=%s\nexpires=%s\nwhat=pre-scope\n' "$(iso_at $((now-5)))" "$(iso_at $((now+595)))" > "$DIR/old.lease"
out="$(run take core:world --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L44 an old unscoped lease refuses a kit/main take"
assert_contains "held by old" "$out" "L44 and names it"
out="$(run take meta:engine --repo engine --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L44 an old unscoped lease refuses an engine/main take"
printf 'seat=old\ntaken=%s\nexpires=%s\nwhat=pre-scope\n' "$(iso_at $((now-900)))" "$(iso_at $((now-300)))" > "$DIR/old.lease"
out="$(run take core:world --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L44 once expired the old lease refuses nothing"

# L45 — show lists every live lease with its scope; --repo/--branch narrows it to the leases that cover that trunk.
reset
run take meta:engine --repo engine --branch main >/dev/null 2>&1
run take core:world --repo kit --branch main >/dev/null 2>&1
out="$(run show 2>&1)"
assert_contains "held by meta:engine (repo=engine branch=main" "$out" "L45 show lists the engine/main holder with its scope"
assert_contains "held by core:world (repo=kit branch=main" "$out" "L45 show lists the kit/main holder with its scope"
assert_not_contains "later take" "$out" "L45 two disjoint scopes are both holders, neither a later take"
out="$(run show --repo Kit --branch refs/heads/main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L45 show --repo --branch exits 0"
assert_contains "held by core:world" "$out" "L45 show --repo kit --branch main lists kit/main's holder"
assert_not_contains "meta:engine" "$out" "L45 and not engine/main's"
out="$(run show --repo kit --branch dev 2>&1)"
assert_contains "nobody holds a lease that covers kit/dev" "$out" "L45 show for a free scope says nobody holds that scope"
out="$(run show --what x 2>&1)"; rc=$?
assert_eq 2 "$rc" "L45 show with an unknown argument is exit 2"

# L46 — a seat may hold one lease per scope; release with a scope releases that scope only, and with no scope every
# lease the seat holds (LANDING.md's `engine lease release <seat>`). history.log keeps its format: one release line,
# seat= only, per file removed.
reset
run take runner --repo kit --branch main >/dev/null 2>&1
out="$(run take runner --repo engine --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L46 a seat holding kit/main may also take engine/main"
out="$(run take runner --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L46 but not a second kit/main"
assert_contains "already holds" "$out" "L46 and is told it already holds it"
run release runner --repo engine --branch main >/dev/null 2>&1
assert_file_not_exists "$DIR/runner@engine@main.lease" "L46 a scoped release removes that scope's file"
assert_file_exists "$DIR/runner@kit@main.lease" "L46 and leaves the seat's other scope held"
run take runner --repo engine --branch main >/dev/null 2>&1
run take ui --repo kit --branch dev >/dev/null 2>&1
lines_before=$(wc -l < "$DIR/history.log" | tr -d ' ')
out="$(run release runner 2>&1)"; rc=$?
assert_eq 0 "$rc" "L46 an unscoped release exits 0"
assert_contains "released by runner (repo=kit branch=main)" "$out" "L46 and names each scope it released"
assert_file_not_exists "$DIR/runner@kit@main.lease" "L46 an unscoped release removes the seat's kit/main lease"
assert_file_not_exists "$DIR/runner@engine@main.lease" "L46 and its engine/main lease"
assert_file_exists "$DIR/ui@kit@dev.lease" "L46 and nobody else's"
assert_eq $((lines_before + 2)) "$(wc -l < "$DIR/history.log" | tr -d ' ')" "L46 two files removed append two release lines"
assert_eq "release	seat=runner" "$(tail -1 "$DIR/history.log" | cut -f2-)" "L46 a release line is still release + seat= only"
out="$(run release ui --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L46 releasing a scope the seat does not hold exits 0"
assert_file_exists "$DIR/ui@kit@dev.lease" "L46 and removes nothing"

# L47 — the kit pre-push call, unchanged: `check <seat> --repo kit --branch main` sees kit/main's holder, ignores an
# engine/main holder, and lets the kit/main holder itself through.
reset
run take meta:engine --repo engine --branch main >/dev/null 2>&1
out="$(run check core:world --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L47 kit's pre-push check passes while only engine/main is held"
run take core:world --repo kit --branch main >/dev/null 2>&1
out="$(run check core:world --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L47 the kit/main holder passes its own check"
out="$(run check packages:schemistry --repo kit --branch main 2>&1)"; rc=$?
assert_eq 3 "$rc" "L47 another seat's kit/main check is refused"

# L48 — `engine lease check`'s stdout wording is an interface. kit's pre-push hook (core:ops, ops/leasehold) tells a
# free lease from the seat's own by these exact strings, and fails closed when they change, so a reword here must
# redden this case before it breaks the hook. Pinned: "lease: free" (a present store nobody holds), "lease: free ("
# (an absent store), and "lease: held by <holder> (…), so <seat> may push" (the seat's own lease). A refusal (exit 3)
# writes nothing on stdout, so the hook can never read "may push" for another seat's lease.
reset; mkdir -p "$DIR"
out="$(run check core:world --repo kit --branch main 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "L48 check on an empty store exits 0"
assert_eq "lease: free" "$out" "L48 check on an empty store prints exactly 'lease: free'"
reset
out="$(run check core:world --repo kit --branch main 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "L48 check on an absent store exits 0"
assert_eq "lease: free (" "${out:0:13}" "L48 check on an absent store starts with 'lease: free ('"
assert_eq "lease: free ($DIR is absent, so nobody has taken a lease)" "$out" "L48 the absent-store line is pinned whole"
reset; run take core:world --repo kit --branch main --what "PR 9" >/dev/null 2>&1
out="$(run check core:world --repo kit --branch main 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "L48 check by the holder exits 0"
held_re='^lease: held by core:world \(repo=kit branch=main taken=[0-9T:-]+Z expires=[0-9T:-]+Z, [0-9]+s left\) PR 9, so core:world may push$'
if [[ "$out" =~ $held_re ]]; then m=1; else m=0; fi
assert_eq 1 "$m" "L48 check by the holder prints 'lease: held by <holder> (…), so <seat> may push' (got: $out)"
out="$(run check ui --repo kit --branch main 2>/dev/null)"; rc=$?
assert_eq 3 "$rc" "L48 check by another seat exits 3"
assert_eq "" "$out" "L48 and prints nothing on stdout"
# On exit 3 the hook reads the holder's time left from stderr as ", <N>s left)".
err="$(run check ui --repo kit --branch main 2>&1 >/dev/null)"
left_re=', [0-9]+s left\)'
if [[ "$err" =~ $left_re ]]; then m=1; else m=0; fi
assert_eq 1 "$m" "L48 exit 3's stderr carries ', <N>s left)' (got: $err)"
# On exit 2 the hook tells a stale engine by "unknown argument: --repo" or "unknown subcommand: check" on stderr,
# so the two usage errors keep the form "lease: unknown argument: <arg>" and "lease: unknown subcommand: <cmd>".
err="$(run check ui --bogus x 2>&1 >/dev/null)"; rc=$?
assert_eq 2 "$rc" "L48 check with an unknown argument exits 2"
assert_eq "lease: unknown argument: --bogus" "${err:0:32}" "L48 and its stderr starts 'lease: unknown argument: <arg>'"
err="$(run nosuch 2>&1 >/dev/null)"; rc=$?
assert_eq 2 "$rc" "L48 an unknown subcommand exits 2"
assert_eq "lease: unknown subcommand: nosuch" "${err:0:33}" "L48 and its stderr starts 'lease: unknown subcommand: <cmd>'"

# L49 — a take that cannot create or write the store takes no lease and says not to push (exit 2). It used to say
# "fail open: land anyway", which under the operator's 00:21 rule (core:ops/leasegate-holder: a push needs the seat to
# HOLD the lease) told a seat to do the one thing the rule forbids.
reset; mkdir -p "$TMP_DIR/ro"; chmod 555 "$TMP_DIR/ro"
out="$(LANDING_LEASE_DIR="$TMP_DIR/ro/.landing-lease" bash "$LEASE" take core:world --repo kit --branch main 2>&1)"; rc=$?
chmod 755 "$TMP_DIR/ro"
assert_eq 2 "$rc" "L49 take on a store it cannot create is exit 2"
assert_contains "so no lease was taken; do not push, ask the operator" "$out" "L49 and says no lease was taken and not to push"
assert_not_contains "land anyway" "$out" "L49 and never tells anyone to land anyway"; assert_not_contains "fail open" "$out" "L49 nor to fail open"
reset; mkdir -p "$DIR"; chmod 555 "$DIR"
out="$(run take core:world --repo kit --branch main 2>&1)"; rc=$?
chmod 755 "$DIR"
assert_eq 2 "$rc" "L49 take on a store it cannot write is exit 2"
assert_contains "so no lease was taken; do not push, ask the operator" "$out" "L49 and says no lease was taken and not to push"
assert_not_contains "land anyway" "$out" "L49 and never tells anyone to land anyway"; assert_not_contains "fail open" "$out" "L49 nor to fail open"
assert_file_not_exists "$DIR/core_world@kit@main.lease" "L49 and leaves no lease file"
# The source carries no "land anyway" anywhere: the lock-timeout and write-failure paths take a minute or a race to
# reach, so this line is their guard.
assert_eq 0 "$(grep -c -i 'land anyway' "$LEASE")" "L49 lease.sh tells nobody to land anyway, on any path"
# Every take failure after the store check names the no-push tail: lock timeout, write failure, read-back failure.
assert_eq 5 "$(grep -c 'NO_TAKE"' "$LEASE")" "L49 all five take failure messages end in the no-push tail"

# L50-L61 — the FIFO waiting list (LEASEQ). A seat joins with `wait` (or `take --queue`); on release or expiry the
# next command hands the turn to the head by writing a reservation, an ordinary lease file for the seat
# `reserved-for:<head>` that expires when the head's grace ends. The head takes its turn with `take`; anyone else is
# refused until the grace ends; a head that lets its grace pass drops off. Nothing runs on a timer: every hand-off and
# drop is computed by the next lease command. `check` reads no queue at all.
qfile="$DIR/kit@main.queue"
age_lease() { # age_lease <file> <secs-ago-expired>: rewrite a lease so it expired that many seconds ago
  local f="$1" ago="$2" n; n=$(date -u +%s)
  sed -i.bak -e "s/^taken=.*/taken=$(iso_at $((n - 600 - ago)))/" -e "s/^expires=.*/expires=$(iso_at $((n - ago)))/" "$f"; rm -f "$f.bak"
}
age_queue() { # age_queue <secs-ago>: every waiter joined that many seconds ago (while the aged lease was still live)
  local n; n=$(date -u +%s)
  awk -F'\t' -v OFS='\t' -v j="$(iso_at $((n - $1)))" '$1=="entry"{$2=j} {print}' "$qfile" > "$qfile.tmp" && mv "$qfile.tmp" "$qfile"
}

# L50 — FIFO order, and `show` lists the queue in order.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
out="$(run wait b:two --repo kit --branch main --what 'fix B' 2>&1)"; rc=$?
assert_eq 0 "$rc" "L50 wait exits 0"
assert_contains "position 1" "$out" "L50 the first waiter is told it is position 1"
out="$(run wait c:three --repo kit --branch main 2>&1)"
assert_contains "position 2" "$out" "L50 the second waiter is position 2"
out="$(run show 2>&1)"
assert_contains "queue kit/main: 1. b:two" "$out" "L50 show lists the queue head first"
assert_contains "2. c:three" "$out" "L50 and the second waiter second"
out="$(run show --repo kit --branch dev 2>&1)"
assert_not_contains "queue kit/main" "$out" "L50 show for another trunk does not list kit/main's queue"

# L51 — joining twice keeps the first place.
out="$(run wait b:two --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L51 a second wait exits 0"
assert_contains "position 1" "$out" "L51 and keeps position 1"
assert_eq 1 "$(grep -c "	b:two	" "$qfile")" "L51 the queue holds b:two once"
assert_contains "1. b:two" "$(run show 2>&1)" "L51 b:two is still first"

# L52 — hand-off on release: the turn passes to the head, a non-head take is refused naming the head and when its
# grace ends, and the head's take succeeds and leaves the queue.
out="$(run release a:one 2>&1)"; rc=$?
assert_eq 0 "$rc" "L52 release exits 0"
assert_contains "turn passes to b:two" "$out" "L52 release says the turn passes to the head"
assert_file_exists "$DIR/reserved-for_b_two@kit@main.lease" "L52 the head's reservation is written"
out="$(run take c:three --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L52 a non-head take during the grace is refused (exit 1)"
assert_contains "reserved for b:two" "$out" "L52 the refusal names the head"
assert_contains "ends at 20" "$out" "L52 and says when the head's grace ends"
assert_file_not_exists "$DIR/c_three@kit@main.lease" "L52 the refused seat leaves no lease file"
out="$(run take b:two --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L52 the head's take succeeds"
assert_contains "taken by b:two" "$out" "L52 and it holds the lease"
assert_file_not_exists "$DIR/reserved-for_b_two@kit@main.lease" "L52 the reservation is gone"
assert_eq 0 "$(grep -c "	b:two	" "$qfile")" "L52 the head left the queue"
assert_contains "queue kit/main: 1. c:three" "$(run show 2>&1)" "L52 c:three is now first"

# L53 — a seat not in the queue is refused during another's grace, and `take --queue` joins on refusal.
run release b:two >/dev/null 2>&1
out="$(run take d:four --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L53 a seat outside the queue is refused during the head's grace"
assert_contains "reserved for c:three" "$out" "L53 and is told whose turn it is"
out="$(run take d:four --repo kit --branch main --queue 2>&1)"; rc=$?
assert_eq 1 "$rc" "L53 take --queue is still refused"
assert_contains "position 2" "$out" "L53 but joins the queue behind the head"
assert_contains "2. d:four" "$(run show 2>&1)" "L53 show lists d:four second"

# L54 — hand-off on expiry: a holder that never releases; once its lease expires the next command hands the turn on.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
run wait b:two --repo kit --branch main >/dev/null 2>&1
run wait c:three --repo kit --branch main >/dev/null 2>&1
age_lease "$DIR/a_one@kit@main.lease" 10
age_queue 300
out="$(run take c:three --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L54 after the holder's lease expires, a non-head take is refused"
assert_contains "reserved for b:two" "$out" "L54 because the turn passed to the head"
r="$DIR/reserved-for_b_two@kit@main.lease"
assert_file_exists "$r" "L54 the head's reservation was written by that command"
assert_eq "$(sed -n 's/^expires=//p' "$DIR/a_one@kit@main.lease")" "$(sed -n 's/^taken=//p' "$r")" "L54 the head's turn starts when the lease expired"

# L55 — the grace drop: a head that lets its grace pass drops off on the next command, and the turn moves on.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
run wait b:two --repo kit --branch main >/dev/null 2>&1
run wait c:three --repo kit --branch main >/dev/null 2>&1
age_lease "$DIR/a_one@kit@main.lease" 200
age_queue 500
out="$(run show 2>&1)"
assert_contains "queue kit/main: 1. c:three" "$out" "L55 show computes the drop: c:three is first"
assert_eq 1 "$(grep -c "	b:two	" "$qfile")" "L55 show writes nothing (b:two is still in the file)"
out="$(run take b:two --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L55 the dropped head's take is refused"
assert_contains "reserved for c:three" "$out" "L55 because the turn moved to c:three"
assert_eq 0 "$(grep -c "	b:two	" "$qfile")" "L55 b:two was dropped from the queue"
assert_contains "drop	seat=b:two" "$(cat "$DIR/history.log")" "L55 the drop is in history.log"
out="$(run take c:three --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L55 the new head takes its turn"

# L56 — leaving the queue; leaving as head passes the turn on.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
run wait b:two --repo kit --branch main >/dev/null 2>&1
run wait c:three --repo kit --branch main >/dev/null 2>&1
out="$(run leave c:three --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L56 leave exits 0"
assert_eq 0 "$(grep -c "	c:three	" "$qfile")" "L56 the seat is gone from the queue"
out="$(run leave c:three --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L56 leaving a queue one is not in exits 0"
run wait c:three --repo kit --branch main >/dev/null 2>&1
run release a:one >/dev/null 2>&1
out="$(run leave b:two --repo kit --branch main 2>&1)"
assert_file_not_exists "$DIR/reserved-for_b_two@kit@main.lease" "L56 a head that leaves takes its reservation with it"
assert_file_exists "$DIR/reserved-for_c_three@kit@main.lease" "L56 and the turn passes to the next seat"

# L57 — per-repo isolation: a kit/main queue and reservation do not touch engine/main.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
run wait b:two --repo kit --branch main >/dev/null 2>&1
run release a:one >/dev/null 2>&1
out="$(run take c:three --repo engine --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L57 an engine/main take succeeds during kit/main's reservation"
run wait d:four --repo engine --branch main >/dev/null 2>&1
assert_file_exists "$DIR/engine@main.queue" "L57 engine/main has its own queue file"
assert_eq 0 "$(grep -c "	d:four	" "$qfile")" "L57 and kit/main's queue does not hold its waiter"
out="$(run check c:three --repo engine --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L57 engine/main's holder still passes its own check"

# L58 — check during a reservation: nobody holds the lease, so every seat's push is refused with check's existing
# exit-3 wording (head included: it must take its turn first), nothing on stdout, and check writes nothing.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
run wait b:two --repo kit --branch main >/dev/null 2>&1
run wait c:three --repo kit --branch main >/dev/null 2>&1
run release a:one >/dev/null 2>&1
for s in c:three b:two; do
  out="$(run check "$s" --repo kit --branch main 2>/dev/null)"; rc=$?
  assert_eq 3 "$rc" "L58 check by $s during b:two's reservation exits 3"
  assert_eq "" "$out" "L58 and prints nothing on stdout"
  err="$(run check "$s" --repo kit --branch main 2>&1 >/dev/null)"
  m=0; [[ "$err" =~ ^lease:\ $s\ may\ not\ push\ now\;\ held\ by\ reserved-for:b:two\ \(repo=kit\ branch=main\ taken=.*,\ [0-9]+s\ left\) ]] && m=1
  assert_eq 1 "$m" "L58 and its stderr is the existing refusal line, naming the reservation (got: $err)"
done
age_lease "$DIR/reserved-for_b_two@kit@main.lease" 5
before="$(cd "$DIR" && ls -la; cat "$qfile")"
out="$(run check c:three --repo kit --branch main 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "L58 once the grace passed and no command ran, check reads the trunk free"
assert_eq "lease: free" "$out" "L58 with the pinned 'lease: free' line, which the hook refuses"
assert_eq "$before" "$(cd "$DIR" && ls -la; cat "$qfile")" "L58 check wrote nothing, even with a drop due"

# L59 — an older store (no queue file anywhere) behaves exactly as before and gains no queue file; and an older
# engine reading a store with a reservation fails safe: it refuses every take and every push during the turn.
reset
run take a:one --repo kit --branch main >/dev/null 2>&1
run show >/dev/null 2>&1; run check b:two --repo kit --branch main >/dev/null 2>&1
out="$(run take b:two --repo kit --branch main 2>&1)"; rc=$?
assert_eq 1 "$rc" "L59 with no queue a take over a live lease is refused as before"
assert_contains "wait until it expires, then take again" "$out" "L59 with the old wording"
run release a:one >/dev/null 2>&1
out="$(run take b:two --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L59 and the trunk is free after release, with no reservation"
assert_eq 0 "$(ls "$DIR" | grep -c '\.queue$')" "L59 no command wrote a queue file"
OLD="$TMP_DIR/lease-v2.sh"
if git -C "$(dirname "$0")" show 8d83237:scripts/lease.sh > "$OLD" 2>/dev/null; then
  reset
  run take a:one --repo kit --branch main >/dev/null 2>&1
  run wait b:two --repo kit --branch main >/dev/null 2>&1
  run release a:one >/dev/null 2>&1
  out="$(LANDING_LEASE_DIR="$DIR" bash "$OLD" take c:three --repo kit --branch main 2>&1)"; rc=$?
  assert_eq 1 "$rc" "L59 an older engine's take during the reservation is refused"
  out="$(LANDING_LEASE_DIR="$DIR" bash "$OLD" check b:two --repo kit --branch main 2>/dev/null)"; rc=$?
  assert_eq 3 "$rc" "L59 an older engine's check refuses the head's push too (exit 3)"
else
  fail "L59 the v2 lease.sh (8d83237) is readable from git" "readable" "missing"
fi

# L60 — queueing needs a trunk, and the reservation name cannot be taken by a seat.
reset
out="$(run wait b:two --repo kit 2>&1)"; rc=$?
assert_eq 2 "$rc" "L60 wait without --branch is a usage error"
out="$(run take reserved-for:x --repo kit --branch main 2>&1)"; rc=$?
assert_eq 2 "$rc" "L60 a seat named reserved-for:... is refused"
out="$(run wait b:two --repo kit --branch main 2>&1)"
assert_contains "take it now" "$out" "L60 a seat that joins an empty queue on a free trunk is told to take it now"
out="$(run take b:two --repo kit --branch main 2>&1)"; rc=$?
assert_eq 0 "$rc" "L60 and its take succeeds"

exit_with_results
