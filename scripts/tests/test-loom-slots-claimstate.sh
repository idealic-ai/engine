#!/usr/bin/env bash
# tests/test-loom-slots-claimstate.sh — the `in-pr` claim state and slot-file `note=` lines in
# `engine loom-slots`.
# Run: bash ~/.claude/engine/scripts/tests/test-loom-slots-claimstate.sh
#      bash ~/.claude/engine/scripts/tests/run-all.sh test-loom-slots-claimstate.sh
#
# WHAT THIS COVERS
#   A claim used to be `working` or `done-uncommitted`, so a loom whose work was committed, pushed and
#   sitting in an open PR looked exactly like a loom holding uncommitted work: a second loom read
#   "at risk" where the truth was "in review". `in-pr <PR#>` names that state and carries the PR.
#   Separately, a conductor's `note=` line (idealic:runner keeps an interim marker there) survived
#   --heartbeat but was printed by no report. Both are pinned here.
#
#   Every case runs against a SANDBOX directory (`LOOM_SLOTS_DIR`), never the live one.
#   `LOOM_SLOTS_READER` points the suite at another copy of the script, which is how a planted
#   defect is run against it. The sibling suite for the older states lives at
#   skills/loom/assets/__tests__/slot-claims.test.sh.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$here/../.." && pwd)"
READER="${LOOM_SLOTS_READER:-$ENGINE/scripts/loom-slots.sh}"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/loom-slots-claimstate.XXXXXX")"
GIT="$(mktemp -d "${TMPDIR:-/tmp}/loom-slots-claimstate-git.XXXXXX")"
trap 'rm -rf "$SB" "$GIT"' EXIT
REPO="$GIT/repo"
mkdir -p "$REPO" && git -C "$REPO" init -q && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$REPO" || exit 1

iso_ago() { date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 minutes" +%Y-%m-%dT%H:%M:%SZ; }
mk_loom() { # file-stem sessionDir cap lanes heartbeat
  printf 'sessionDir=%s\ncap=%s\nliveLanes=%s\nheartbeat=%s\n' "$2" "$3" "$4" "$5" > "$SB/$1.slots"
}
run() { LOOM_SLOTS_DIR="$SB" "$READER" "$@"; }
reset() { rm -rf "$SB"/*; }

OTHER="/tmp/sessions/RUNNER_LOOM"; OF="$SB/tmp-sessions-RUNNER_LOOM.slots"
ME="/tmp/sessions/DOMAIN_LOOM"; MF="$SB/tmp-sessions-DOMAIN_LOOM.slots"

printf '\n== Setting and reading in-pr ==\n'

reset
mk_loom "tmp-sessions-DOMAIN_LOOM" "$ME" 4 "L1" "$(iso_ago 1)"
run --claim "$ME" IDE-201 >/dev/null 2>&1
run --claim-state "$ME" IDE-201 in-pr 482 >/dev/null 2>&1; rc=$?
line="$(grep '^claims=' "$MF")"
if [ "$rc" -eq 0 ] && printf '%s' "$line" | grep -q '^claims=IDE-201|in-pr:482|[0-9TZ:-]*$'; then
  ok "P1  --claim-state <dir> IDE-201 in-pr 482 exits 0 and stores the claim as IDE-201|in-pr:482|<stamp>"
else
  no "P1  in-pr is written with its PR number" "rc=$rc line=[$line]"
fi

out="$(run --self "$ME" 2>&1)"
row="$(printf '%s\n' "$out" | grep 'IDE-201')"
if printf '%s' "$row" | grep -q 'in-pr' && printf '%s' "$row" | grep -q 'PR #482' && printf '%s' "$row" | grep -q '(this loom)'; then
  ok "P2  --self reports the in-pr claim on its own row, naming PR #482, marked as this loom"
else
  no "P2  --self shows in-pr and the PR number" "row=[$row]"
fi

run --claim-state "$ME" IDE-201 in-pr '#517' >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^claims=IDE-201|in-pr:517|' "$MF" && [ "$(grep -o 'IDE-201' "$MF" | wc -l | tr -d ' ')" = 1 ]; then
  ok "P3  a PR given as '#517' is accepted, and re-stating in-pr replaces the claim rather than adding a second"
else
  no "P3  '#517' is normalised and the claim stays single" "rc=$rc file: $(grep claims= "$MF")"
fi

before="$(cat "$MF")"
o1="$(run --claim-state "$ME" IDE-201 in-pr 2>&1)"; r1=$?
o2="$(run --claim-state "$ME" IDE-201 in-pr abc 2>&1)"; r2=$?
o3="$(run --claim-state "$ME" IDE-201 in-pr 0 2>&1)"; r3=$?
if [ "$r1" -ne 0 ] && [ "$r2" -eq 1 ] && [ "$r3" -eq 1 ] && [ "$before" = "$(cat "$MF")" ]; then
  ok "P4  in-pr with no PR number, a non-numeric one, or 0 is refused and the file is untouched"
else
  no "P4  in-pr demands a PR number" "missing rc=$r1 [$o1] abc rc=$r2 zero rc=$r3"
fi

o4="$(run --claim-state "$ME" NOT-CLAIMED in-pr 9 2>&1)"; r4=$?
if [ "$r4" -eq 1 ] && [ "$before" = "$(cat "$MF")" ]; then
  ok "P5  in-pr on an item that is not claimed is refused (exit 1), like the other states"
else
  no "P5  in-pr on an unclaimed item" "rc=$r4 [$o4]"
fi

run --claim-state "$ME" IDE-201 landed >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'claims=' "$MF"; then
  ok "P6  landed removes an in-pr claim"
else
  no "P6  landed removes in-pr" "rc=$rc file: $(grep claims= "$MF")"
fi

printf '\n== Overlap wording ==\n'

reset
mk_loom "tmp-sessions-RUNNER_LOOM" "$OTHER" 4 "R1" "$(iso_ago 1)"
mk_loom "tmp-sessions-DOMAIN_LOOM" "$ME" 4 "L1" "$(iso_ago 1)"
run --claim "$OTHER" IDE-301 IDE-302 >/dev/null 2>&1
run --claim-state "$OTHER" IDE-301 in-pr 482 >/dev/null 2>&1
run --claim-state "$OTHER" IDE-302 done-uncommitted >/dev/null 2>&1

err="$(run --quiet --dispatching IDE-301 --self "$ME" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 4 ] && printf '%s' "$err" | grep -q 'in review in PR 482' && ! printf '%s' "$err" | grep -q 'uncommitted at risk'; then
  ok "O1  dispatching into another loom's in-pr claim still exits 4, and the warning says 'in review in PR 482', not 'uncommitted at risk'"
else
  no "O1  in-pr overlap wording" "rc=$rc err=[$err]"
fi

err="$(run --quiet --dispatching IDE-302 --self "$ME" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 4 ] && printf '%s' "$err" | grep -q 'uncommitted at risk' && ! printf '%s' "$err" | grep -q 'in review'; then
  ok "O2  control: a done-uncommitted overlap exits 4 and says 'uncommitted at risk', never 'in review'"
else
  no "O2  done-uncommitted overlap wording" "rc=$rc err=[$err]"
fi

run --claim "$ME" IDE-401 >/dev/null 2>&1
run --claim-state "$ME" IDE-401 in-pr 600 >/dev/null 2>&1
run --quiet --dispatching IDE-401 --self "$ME" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "O3  a loom's own in-pr claim does not count as an overlap against itself (exit 0)"
else
  no "O3  own in-pr claim is not an overlap" "rc=$rc"
fi

printf '\n== in-pr survives heartbeat and a stale row ==\n'

reset
mk_loom "tmp-sessions-RUNNER_LOOM" "$OTHER" 4 "R1,R2" "$(iso_ago 400)"
run --claim "$OTHER" IDE-501 >/dev/null 2>&1
run --claim-state "$OTHER" IDE-501 in-pr 731 >/dev/null 2>&1
before="$(grep '^claims=' "$OF")"
run --heartbeat "$OTHER" --cap 4 --lanes '' >/dev/null 2>&1; rc=$?
after="$(grep '^claims=' "$OF")"
if [ "$rc" -eq 0 ] && [ -n "$before" ] && [ "$before" = "$after" ] && printf '%s' "$after" | grep -q 'IDE-501|in-pr:731|'; then
  ok "H1  --heartbeat leaves the in-pr claim, PR number included, byte-identical"
else
  no "H1  in-pr survives --heartbeat" "rc=$rc before=[$before] after=[$after]"
fi

# Age the row: heartbeat 400 minutes old, no lanes. The claim must still be reported with its PR.
sed -i.bak "s/^heartbeat=.*/heartbeat=$(iso_ago 400)/" "$OF" && rm -f "$OF.bak"
touch -t "$(date -v-7H +%Y%m%d%H%M 2>/dev/null || date -d '-7 hours' +%Y%m%d%H%M)" "$OF"
out="$(run --self "$ME" 2>&1)"
row="$(printf '%s\n' "$out" | grep 'IDE-501')"
if printf '%s' "$row" | grep -q 'in-pr' && printf '%s' "$row" | grep -q 'PR #731' && printf '%s' "$row" | grep -q 'stale'; then
  ok "H2  on a row stale for 400 minutes with no lanes, the in-pr claim is still reported with PR #731 and the row marked stale"
else
  no "H2  in-pr on a stale row" "row=[$row]"
fi
err="$(run --quiet --minutes 1 --dispatching IDE-501 --self "$ME" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 4 ] && printf '%s' "$err" | grep -q 'in review in PR 731'; then
  ok "H3  the stale row's in-pr claim still blocks a dispatch (exit 4) — in-pr never ages out"
else
  no "H3  in-pr does not age out" "rc=$rc err=[$err]"
fi

printf '\n== note= lines ==\n'

reset
mk_loom "tmp-sessions-RUNNER_LOOM" "$OTHER" 4 "R1" "$(iso_ago 1)"
mk_loom "tmp-sessions-DOMAIN_LOOM" "$ME" 4 "L1" "$(iso_ago 1)"
printf 'note=interim: IDE-77 rebasing onto main, do not dispatch into apps/api\nnote=second marker = with equals\n' >> "$OF"
run --heartbeat "$OTHER" >/dev/null 2>&1
out="$(run --self "$ME" 2>&1)"
notes="$(printf '%s\n' "$out" | sed -n '/== Notes/,$p')"
if printf '%s' "$notes" | grep -q 'RUNNER_LOOM' \
   && printf '%s' "$notes" | grep -qF 'interim: IDE-77 rebasing onto main, do not dispatch into apps/api' \
   && printf '%s' "$notes" | grep -qF 'second marker = with equals'; then
  ok "N1  --self prints every note= line from another loom's slot file, after --heartbeat, under its loom's name"
else
  no "N1  note= lines reach the report" "notes=[$notes]"
fi

reset
mk_loom "tmp-sessions-DOMAIN_LOOM" "$ME" 4 "L1" "$(iso_ago 1)"
out="$(run --self "$ME" 2>&1)"
if ! printf '%s' "$out" | grep -q '== Notes'; then
  ok "N2  control: with no note= line anywhere, no Notes section is printed"
else
  no "N2  no notes, no section" "out=[$out]"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
