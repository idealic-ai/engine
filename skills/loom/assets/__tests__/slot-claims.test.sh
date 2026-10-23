#!/usr/bin/env bash
# Work claims in the loom slot file — does a claim outlive the lanes that made it?
#
# WHAT THIS COVERS
#   `¶INV_SLOT_CAP_IS_GLOBAL` carries a `claims=` line per loom: the tickets and paths that loom has
#   taken, each `working` or `done-uncommitted`. The case it exists for: a loom whose lanes have all
#   ended and whose heartbeat has gone stale still holds finished, uncommitted work, and a second
#   loom reading the directory must see that before it dispatches into the same tickets.
#
#   Every case runs against a SANDBOX directory (`LOOM_SLOTS_DIR`), never the live one.
#   `LOOM_SLOTS_READER` points the file at another copy of the script, which is how each case's
#   planted failure is run.
#
# Run:  ~/.claude/engine/skills/loom/assets/__tests__/slot-claims.test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$here/../../../.." && pwd)"
READER="${LOOM_SLOTS_READER:-$ENGINE/scripts/loom-slots.sh}"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/loom-slot-claims.XXXXXX")"
# Repositories live beside the slot directory, not in it, so reset() never removes them. Relative
# claim paths resolve against the working directory's repository, so every case runs from REPO.
GIT="$(mktemp -d "${TMPDIR:-/tmp}/loom-slot-claims-git.XXXXXX")"
trap 'rm -rf "$SB" "$GIT"' EXIT
REPO="$GIT/finch"; REPO2="$GIT/other-repo"; WT="$GIT/finch-wt"
for r in "$REPO" "$REPO2"; do
  mkdir -p "$r/packages/estimate/src" "$r/apps/api/src/msft"
  git -C "$r" init -q && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
done
git -C "$REPO" worktree add -q "$WT" 2>/dev/null
cd "$REPO" || exit 1

iso_ago() { date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 minutes" +%Y-%m-%dT%H:%M:%SZ; }
mk_loom() { # file-stem sessionDir cap lanes heartbeat
  printf 'sessionDir=%s\ncap=%s\nliveLanes=%s\nheartbeat=%s\n' "$2" "$3" "$4" "$5" > "$SB/$1.slots"
}
run() { LOOM_SLOTS_DIR="$SB" "$READER" "$@"; }
reset() { rm -rf "$SB"/*; }

OTHER="/tmp/sessions/LAND_TREE_BRANCHES"
ME="/tmp/sessions/XACTIMATE"

printf '\n== Writing claims ==\n'

reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "L1" "$(iso_ago 1)"
before="$(grep -v '^claims=' "$SB/tmp-sessions-LAND_TREE_BRANCHES.slots")"
run --claim "$OTHER" IDE-129 packages/estimate/src >/dev/null 2>&1; rc=$?
line="$(grep '^claims=' "$SB/tmp-sessions-LAND_TREE_BRANCHES.slots" 2>/dev/null)"
after="$(grep -v '^claims=' "$SB/tmp-sessions-LAND_TREE_BRANCHES.slots" 2>/dev/null)"
if [ "$rc" -eq 0 ] && printf '%s' "$line" | grep -q 'IDE-129|working|' \
   && printf '%s' "$line" | grep -q 'packages/estimate/src|working|' && [ "$before" = "$after" ]; then
  ok "W1  --claim writes both items as working into the loom's own file and leaves sessionDir, cap, liveLanes and heartbeat byte-identical"
else
  no "W1  --claim writes a claims= line and preserves the rest" "rc=$rc line=[$line] rest-unchanged=$([ "$before" = "$after" ] && echo yes || echo no)"
fi

# A hand-written file whose name is NOT the slug (the live LAND_TREE_BRANCHES file keeps a space).
reset
SPACED="/tmp/Shared drives/sessions/SPACED"
mk_loom "tmp-Shared drives-sessions-SPACED" "$SPACED" 4 "" "$(iso_ago 1)"
run --claim "$SPACED" IDE-7 >/dev/null 2>&1
n="$(ls "$SB"/*.slots | wc -l | tr -d ' ')"
if [ "$n" = "1" ] && grep -q '^claims=IDE-7|working|' "$SB/tmp-Shared drives-sessions-SPACED.slots"; then
  ok "W2  a claim lands in the loom's existing file found by its sessionDir line, even when that file's name is not the slug — no second row is minted for the same loom"
else
  no "W2  a claim finds the loom's file by sessionDir" "files=$n: $(ls "$SB" | tr '\n' ' ')"
fi

reset
run --claim "$OTHER" IDE-9 >/dev/null 2>&1
# The name is whatever the script's slug produces; find the file by content, then prove it is one.
f="$(grep -lxF "sessionDir=$OTHER" "$SB"/*.slots 2>/dev/null | head -1)"
if [ "$(ls "$SB"/*.slots 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && [ -f "$f" ] && grep -qxF "sessionDir=$OTHER" "$f" && grep -q '^claims=IDE-9|working|' "$f"; then
  ok "W3  a claim from a loom with no file yet creates one carrying its sessionDir"
else
  no "W3  a claim creates the file when absent" "$(ls "$SB" | tr '\n' ' ')"
fi

out="$(run --claim "$OTHER" 'a|b' 2>&1)"; rc1=$?
out2="$(run --claim-state "$OTHER" IDE-9 finished 2>&1)"; rc2=$?
if [ "$rc1" -eq 1 ] && [ "$rc2" -eq 1 ] && grep -q '^claims=IDE-9|working|[^,]*$' "$f"; then
  ok "W4  an item containing the field separator '|', and a state outside working|done-uncommitted|landed, are refused (exit 1) and the file is untouched"
else
  no "W4  bad items and bad states are refused" "pipe rc=$rc1 state rc=$rc2; file: $(grep claims= "$f")"
fi

run --claim "$OTHER" IDE-10 >/dev/null 2>&1
if grep -q 'IDE-9|working|' "$f" && grep -q 'IDE-10|working|' "$f"; then
  ok "W5  a second --claim call on the same loom keeps the first call's claim (one claim per dispatch is the ordinary use)"
else
  no "W5  successive claims accumulate" "claims: $(grep claims= "$f")"
fi

run --claim "$OTHER" 'IDE-11,IDE-12' IDE-13 >/dev/null 2>&1
n="$(grep '^claims=' "$f" | tr ',' '\n' | grep -c 'IDE-1[123]|working|')"
if [ "$n" = 3 ]; then
  ok "W6  one --claim call takes a comma list and further arguments together (3 items, one write)"
else
  no "W6  --claim a,b c claims all three" "found $n; claims: $(grep claims= "$f")"
fi

perm="$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")"
if [ "$perm" = 644 ]; then
  ok "W7  a claim write leaves the file 0644, not mktemp's 0600"
else
  no "W7  the file stays 0644" "mode $perm"
fi

# Ten claims at once on one loom, as a conductor dispatching several lanes in one message makes them.
reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 1)"
for i in 1 2 3 4 5 6 7 8 9 10; do run --claim "$OTHER" "CONC-$i" >/dev/null 2>&1 & done
wait
n="$(grep '^claims=' "$SB/tmp-sessions-LAND_TREE_BRANCHES.slots" | tr ',' '\n' | grep -c 'CONC-[0-9]*|working|')"
locks="$(ls -a "$SB" | grep -c '\.lock$')"
if [ "$n" = 10 ] && [ "$locks" = 0 ]; then
  ok "W8  10 concurrent --claim calls on one loom leave all 10 claims, and no lock is left behind"
else
  no "W8  concurrent claims all survive" "survived $n of 10; locks left: $locks"
fi

# One session path a prefix of another must not share a row.
reset
# AB's file sorts first, so a prefix match would find it before A's.
mk_loom "1-AB" "/tmp/s/AB" 4 "" "$(iso_ago 1)"
mk_loom "2-A" "/tmp/s/A" 4 "" "$(iso_ago 1)"
run --claim /tmp/s/A PFX-1 >/dev/null 2>&1
if grep -q 'PFX-1' "$SB/2-A.slots" && ! grep -q 'PFX-1' "$SB/1-AB.slots"; then
  ok "W9  a claim for /tmp/s/A lands in A's row and not in /tmp/s/AB's"
else
  no "W9  session paths match whole, not by prefix" "A: $(grep claims= "$SB/2-A.slots") AB: $(grep claims= "$SB/1-AB.slots")"
fi

# Two spellings of one session directory: a symlink and the real path, plus a trailing slash.
reset
REAL="$SB/real/sessions/LOOM"; mkdir -p "$REAL"; ln -s "$SB/real" "$SB/link"
mk_loom "the-real-row" "$REAL" 4 "" "$(iso_ago 1)"
run --claim "$SB/link/sessions/LOOM/" SYM-1 >/dev/null 2>&1
rows="$(ls "$SB"/*.slots | wc -l | tr -d ' ')"
err="$(run --quiet --self "$REAL" --dispatching SYM-1 2>&1 >/dev/null)"; rc=$?
if [ "$rows" = 1 ] && grep -q 'SYM-1' "$SB/the-real-row.slots" && [ "$rc" -eq 0 ] && [ -z "$err" ]; then
  ok "W10 a claim made through a symlinked, trailing-slash spelling of the session lands on the loom's one row, and --self with the real spelling raises no warning about its own claim"
else
  no "W10 one loom, two spellings, one row" "rows=$rows rc=$rc stderr=[$err] files: $(ls "$SB" | tr '\n' ' ')"
fi

# A write that cannot happen exits 5, never 2 (which means "could not read").
reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 1)"
chmod 555 "$SB"
out="$(run --claim "$OTHER" RO-1 2>&1)"; rc=$?
chmod 755 "$SB"
if [ "$rc" -eq 5 ] && ! grep -q 'RO-1' "$SB/tmp-sessions-LAND_TREE_BRANCHES.slots"; then
  ok "W11 a claim into an unwritable directory exits 5 at once and writes nothing"
else
  no "W11 a failed write exits 5" "rc=$rc out=[$out]"
fi

f="$SB/tmp-sessions-LAND_TREE_BRANCHES.slots"

printf '\n== The incident: a stale row with no lanes still shows its claims ==\n'

reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 400)"
run --claim "$OTHER" IDE-129 >/dev/null 2>&1
run --claim-state "$OTHER" IDE-129 done-uncommitted >/dev/null 2>&1
out="$(run 2>&1)"
if printf '%s' "$out" | grep -q 'IDE-129' && printf '%s' "$out" | grep 'IDE-129' | grep -q 'done-uncommitted' \
   && printf '%s' "$out" | grep 'IDE-129' | grep -q 'stale'; then
  ok "S1  a row stale for 400 minutes with liveLanes empty still REPORTS its done-uncommitted claim, and marks the row stale beside it — the reading Xactimate's loom needed"
else
  no "S1  a stale, laneless row still reports its claim" "$(printf '%s' "$out" | tr '\n' '~' | cut -c1-400)"
fi

live="$(printf '%s' "$out" | sed -n 's/.*global live lanes *: *\([0-9]*\).*/\1/p')"
stale="$(printf '%s' "$out" | sed -n 's/.*stale loom rows *: *\([0-9]*\).*/\1/p')"
if [ "${live:-x}" = 0 ] && [ "${stale:-x}" = 1 ]; then
  ok "S2  writing a claim does not refresh liveness: the row is still counted 0 and reported stale (1)"
else
  no "S2  a claim write leaves the liveness reading alone" "live=${live:-?} stale=${stale:-?}"
fi

# A stanza with no heartbeat falls back to file mtime; a claim write must not make it look fresh.
reset
printf 'sessionDir=%s\ncap=6\nliveLanes=A,B\n' "$OTHER" > "$f"
touch -t "$(date -v-400M +%Y%m%d%H%M 2>/dev/null || date -d '-400 minutes' +%Y%m%d%H%M)" "$f"
run --claim "$OTHER" IDE-1 >/dev/null 2>&1
live="$(run 2>&1 | sed -n 's/.*global live lanes *: *\([0-9]*\).*/\1/p')"
if [ "${live:-x}" = 0 ]; then
  ok "S3  on a row with no heartbeat stamp, a claim write keeps the file's old mtime, so the asserted lanes stay uncounted"
else
  no "S3  a claim write keeps the mtime fallback stale" "live=${live:-?}; the claim write made 2 dead lanes count as live"
fi

printf '\n== Overlap with what is about to be dispatched ==\n'

reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 400)"
mk_loom "tmp-sessions-XACTIMATE" "$ME" 4 "" "$(iso_ago 1)"
run --claim "$OTHER" IDE-129 packages/estimate/src >/dev/null 2>&1
run --claim "$ME" IDE-500 >/dev/null 2>&1

err="$(run --quiet --dispatching ide-129 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 4 ] && printf '%s' "$err" | grep -q 'IDE-129' && printf '%s' "$err" | grep -q 'LAND_TREE_BRANCHES'; then
  ok "O1  dispatching a ticket another loom claimed warns (case-insensitive key match), names the holding loom, and exits 4 — on stderr, so --quiet still carries it"
else
  no "O1  a ticket-key overlap warns and exits 4" "rc=$rc stderr=[$(printf '%s' "$err" | tr '\n' '~' | cut -c1-300)]"
fi

err="$(run --quiet --dispatching packages/estimate/src/assembler.ts 2>&1 >/dev/null)"; rc_child=$?
err_parent="$(run --quiet --dispatching packages/ 2>&1 >/dev/null)"; rc_parent=$?
err_sib="$(run --quiet --dispatching packages/estimate/srcx 2>&1 >/dev/null)"; rc_sib=$?
if [ "$rc_child" -eq 4 ] && [ "$rc_parent" -eq 4 ] && [ "$rc_sib" -eq 0 ] && [ -z "$err_sib" ]; then
  ok "O2  a path overlaps by prefix in either direction (a file under a claimed area, an area holding a claimed path) and only at a path boundary — 'src' does not claim 'srcx'"
else
  no "O2  path-prefix overlap at a boundary" "child rc=$rc_child parent rc=$rc_parent sibling rc=$rc_sib sibling-stderr=[$err_sib]"
fi

err="$(run --quiet --dispatching IDE-777,apps/web 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
  ok "O3  a dispatch overlapping nothing is silent and exits 0 — the existing reading"
else
  no "O3  no overlap stays silent" "rc=$rc stderr=[$err]"
fi

err="$(run --quiet --self "$ME" --dispatching IDE-500 2>&1 >/dev/null)"; rc_self=$?
err2="$(run --quiet --dispatching IDE-500 2>&1 >/dev/null)"; rc_noself=$?
if [ "$rc_self" -eq 0 ] && [ -z "$err" ] && [ "$rc_noself" -eq 4 ]; then
  ok "O4  --self excludes the reading loom's own claims from the overlap check (and without it they still warn)"
else
  no "O4  --self excludes own claims" "with --self rc=$rc_self stderr=[$err]; without rc=$rc_noself"
fi

out="$(run --self "$ME" 2>&1)"
if printf '%s' "$out" | grep 'IDE-500' | grep -q 'this loom'; then
  ok "O5  the report labels the reading loom's own claims as 'this loom'"
else
  no "O5  own claims are labelled" "$(printf '%s' "$out" | grep IDE-500)"
fi

# Cap wins the exit code, but the overlap is still said.
reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 1 "L1" "$(iso_ago 1)"
run --claim "$OTHER" IDE-129 >/dev/null 2>&1
err="$(run --quiet --dispatching IDE-129 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$err" | grep -q 'IDE-129'; then
  ok "O6  at cap AND overlapping exits 3 (the cap's existing code) and still prints the overlap on stderr"
else
  no "O6  cap exit wins, overlap still printed" "rc=$rc stderr=[$err]"
fi

printf '\n== One ticket or path, typed several ways ==\n'

reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 400)"
run --claim "$OTHER" fin-3141-fix-the-thing FIN-2 packages/estimate/src "$REPO/apps/api/src/msft" >/dev/null 2>&1
line="$(grep '^claims=' "$f")"
if printf '%s' "$line" | grep -q 'FIN-3141|working|' && ! printf '%s' "$line" | grep -qi 'fix-the-thing'; then
  ok "N1  a claim made with a branch name is stored as its ticket key (FIN-3141)"
else
  no "N1  a branch-name claim is stored as its key" "[$line]"
fi

missed=""
for d in ' FIN-3141' 'FIN-3141 ' 'fin-3141-fix-the-thing' 'https://linear.app/finchclaims/issue/FIN-3141/slug' '[FIN-3141]' 'see [FIN-3141]'; do
  run --quiet --dispatching "$d" >/dev/null 2>&1; [ $? -eq 4 ] || missed="$missed [$d]"
done
run --quiet --dispatching 'FIN-77, FIN-2' >/dev/null 2>&1; [ $? -eq 4 ] || missed="$missed [FIN-77, FIN-2]"
if [ -z "$missed" ]; then
  ok "N2  FIN-3141 is found through surrounding spaces, a branch name, a Linear URL and a [KEY] link, and FIN-2 through a ', '-separated list"
else
  no "N2  ticket spellings all meet the claim" "missed:$missed"
fi

missed=""
# The not-there/../ spelling crosses a directory that does not exist, so only the lexical fold can
# remove it — resolving the existing part with pwd -P would hide a broken fold.
for d in "$REPO/packages/estimate/src/x.ts" 'packages//estimate/./src' "../$(basename "$REPO")/packages/estimate/src" 'not-there/../packages/estimate/src/z.ts' 'apps/api/src/msft' "$WT/packages/estimate/src/y.ts"; do
  run --quiet --dispatching "$d" >/dev/null 2>&1; [ $? -eq 4 ] || missed="$missed [$d]"
done
if [ -z "$missed" ]; then
  ok "N3  a path claim is found whether the dispatch spells it absolute or relative, with // or ./ or ../, or from another worktree of the same repository"
else
  no "N3  path spellings all meet the claim" "missed:$missed"
fi

# A file UNDER the claimed path in the other repository: an equal path would fail the prefix test
# whether or not the repositories are compared.
e1="$(run --quiet --dispatching "$REPO2/packages/estimate/src/x.ts" 2>&1 >/dev/null)"; r1=$?
e2="$(run --quiet --repo "$REPO2" --dispatching packages/estimate/src 2>&1 >/dev/null)"; r2=$?
run --quiet --repo "$REPO" --dispatching packages/estimate/src >/dev/null 2>&1; r3=$?
if [ "$r1" -eq 0 ] && [ -z "$e1" ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 4 ]; then
  ok "N4  the same relative path in a different repository does not collide (absolute, and through --repo), while --repo naming the claim's own repository still does"
else
  no "N4  two repositories never collide" "other-abs rc=$r1 other-repo rc=$r2 same-repo rc=$r3"
fi

run --quiet --dispatching FIN-3141-extra/notes.md >/dev/null 2>&1; r1=$?
run --quiet --dispatching FIN-31415 >/dev/null 2>&1; r2=$?
run --quiet --dispatching FIN-3141x >/dev/null 2>&1; r3=$?
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ]; then
  ok "N5  a path that merely starts with a key, a longer key, and a key with a letter run on (FIN-3141x) do not match FIN-3141"
else
  no "N5  near-miss spellings stay apart" "path rc=$r1 longer-key rc=$r2 key-plus-letter rc=$r3"
fi

printf '\n== Removing claims: only landed or an explicit release ==\n'

reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 1)"
run --claim "$OTHER" IDE-1 IDE-2 IDE-3 >/dev/null 2>&1
run --claim-state "$OTHER" IDE-1 landed >/dev/null 2>&1
run --release "$OTHER" IDE-2 >/dev/null 2>&1
line="$(grep '^claims=' "$f")"
if printf '%s' "$line" | grep -q 'IDE-3|working|' && ! printf '%s' "$line" | grep -q 'IDE-1|' \
   && ! printf '%s' "$line" | grep -q 'IDE-2|'; then
  ok "R1  'landed' removes IDE-1 and --release removes IDE-2, while IDE-3 (still working, file confirmed to hold it) survives both"
else
  no "R1  landed and release remove only their item" "claims line: [$line]"
fi

touch -t "$(date -v-2000M +%Y%m%d%H%M 2>/dev/null || date -d '-2000 minutes' +%Y%m%d%H%M)" "$f"
sed -i.bak "s/^heartbeat=.*/heartbeat=$(iso_ago 2000)/" "$f" && rm -f "$f.bak"
out="$(run 2>&1)"
if printf '%s' "$out" | grep -q 'IDE-3'; then
  ok "R2  a claim does not expire with age: 2000 minutes stale, IDE-3 is still reported"
else
  no "R2  claims survive age" "IDE-3 vanished from a 2000-minute-old row"
fi

run --claim-state "$OTHER" IDE-3 landed >/dev/null 2>&1
line="$(grep '^claims=' "$f")"
out="$(run 2>&1)"
if [ "$line" = "claims=" ] && ! printf '%s' "$out" | grep -q 'IDE-3'; then
  ok "R3  landing the last claim leaves an empty claims= line and the report no longer names it"
else
  no "R3  the last claim lands cleanly" "line=[$line]"
fi

reset
mk_loom "tmp-sessions-LAND_TREE_BRANCHES" "$OTHER" 6 "" "$(iso_ago 1)"
run --claim "$OTHER" IDE-1 >/dev/null 2>&1
before="$(cat "$f")"
out1="$(run --claim-state "$OTHER" NEVER-1 done-uncommitted 2>&1)"; rc1=$?
out2="$(run --release "$OTHER" IDE-1 NEVER-2 2>&1)"; rc2=$?
if [ "$rc1" -eq 1 ] && [ "$rc2" -eq 1 ] && printf '%s' "$out1" | grep -q 'not claimed' \
   && [ "$before" = "$(cat "$f")" ]; then
  ok "R4  --claim-state and --release on an item that was never claimed exit 1 and say so, and a release naming one unclaimed item changes nothing (IDE-1 kept)"
else
  no "R4  unclaimed items are refused" "claim-state rc=$rc1 release rc=$rc2 msg=[$out1] file changed=$([ "$before" = "$(cat "$f")" ] && echo no || echo yes)"
fi

printf '\n== Existing behaviour ==\n'

reset
mk_loom "PLAIN" "/tmp/sessions/PLAIN" 3 "L1,L2" "$(iso_ago 1)"
out="$(run 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qi 'claim'; then
  ok "E1  a directory with no claims prints no claims section and exits 0 as before"
else
  no "E1  no claims, no new output" "rc=$rc"
fi

printf '\n  %s ok, %s FAIL\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
