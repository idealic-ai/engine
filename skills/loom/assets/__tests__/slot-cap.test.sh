#!/usr/bin/env bash
# The global live-lane cap — is it ENFORCED, or merely RECORDED?
#
# WHAT THIS COVERS
#   `¶INV_SLOT_CAP_IS_GLOBAL` puts the count in `~/.claude/engine/.loom-slots/`, one file per loom,
#   one writer per file. Part A measures what the repository actually does with that directory.
#   Part B exercises `scripts/loom-slots.sh`, which computes the count, against a SANDBOX directory
#   (`LOOM_SLOTS_DIR`) — never the live one, which three looms are writing to right now.
#
# THE DISTINCTION THIS FILE IS BUILT AROUND
#   A record is not a cap. A cap needs three things: a count somebody can trust, a refusal at the
#   moment of dispatch, and a counter that is not the party being counted. The directory gives
#   VISIBILITY — which is real, and is the thing the ticket's escalation trigger asks about. It does
#   not give enforcement, and Part A is the measurement of that gap rather than an opinion about it.
#
# THE TRAP IT IS BUILT AROUND
#   The heartbeat stamps are `Z` and the machine this runs on is not UTC. Reading a Z stamp against
#   local time overstates every age by the offset, which once reported a 2-minute-old loom as stale
#   and all three looms as dead. Case B5 is that exact reading, with a genuinely old row in the same
#   invocation so a "nothing is stale" result cannot come from a broken comparison.
#
# Run:  ~/.claude/engine/skills/loom/assets/__tests__/slot-cap.test.sh
# No network. Writes only under $TMPDIR. Never reads or writes the live slot directory.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
loom="$(cd "$here/../.." && pwd)"
ENGINE="$(cd "$loom/../.." && pwd)"
SKILL="$loom/SKILL.md"
READER="$ENGINE/scripts/loom-slots.sh"

pass=0; fail=0; skipped=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no()   { fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
skip() { skipped=$((skipped+1)); printf '  skip  %s\n        un-skips when: %s\n' "$1" "${2:-}"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/loom-slot-cap.XXXXXX")"
cleanup() { rm -rf "$SB"; }
trap cleanup EXIT

printf '\n== Part A — what the repository DOES with the slot directory (the record/enforcement gap, measured) ==\n'

# The control for every absence claim in Part A: a stem that is certainly present in the same trees.
ctl_hits="$(grep -rl 'sessionDir\|lane-stall' "$ENGINE/hooks" "$ENGINE/scripts" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${ctl_hits:-0}" -gt 0 ]; then
  ok "A-control the grep reaches the hooks and scripts trees ($ctl_hits file(s) matched a present stem) — so a zero below is a reading, not a mistyped path"
else
  no "A-control the grep reaches the hooks and scripts trees" "a stem that must be present matched nothing; every zero in Part A is meaningless until this passes"
fi

exec_hits="$(grep -rl 'loom-slots' "$ENGINE/hooks" "$ENGINE/scripts" "$ENGINE/tools" 2>/dev/null | grep -v '/loom-slots.sh$' | wc -l | tr -d ' ')"
if [ "${exec_hits:-0}" -eq 0 ]; then
  ok "A1  no hook and no other script reads or writes the slot directory (0 files, control fired above) — the cap is a convention a model is asked to honour, not a gate"
else
  ok "A1  $exec_hits executable(s) outside the reader now touch the slot directory — the enforcement half has started landing; re-read this case's premise"
fi

if [ -f "$READER" ]; then
  ok "A2  a reader exists that COMPUTES the count (scripts/loom-slots.sh → \`engine loom-slots\`)"
else
  no "A2  a reader exists that computes the count" "not found at $READER — the count is asserted by the conductor by hand and nothing else can check it"
fi

# The refusal harness. A cap needs a deny at the dispatch moment, and the engine already has one.
guards="$ENGINE/guards.json"
if [ -f "$guards" ] && grep -q 'heartbeat-block' "$guards"; then
  ok "A3  the engine already has a declarative deny table with a precedent that blocks a tool call (guards.json: heartbeat-block) — so a refusal is a row in an existing table, not new infrastructure"
else
  no "A3  the engine has a declarative deny table with a blocking precedent" "guards.json missing or carries no heartbeat-block rule; the claim that a refusal needs no new infrastructure rests on this"
fi

if grep -q '"toolFilter"' "$guards" 2>/dev/null; then
  ok "A4  guard rows can already be scoped to one tool (toolFilter), which is what scopes a cap refusal to the dispatch call rather than to every tool"
else
  no "A4  guard rows can be scoped to one tool" "no toolFilter field in guards.json — a cap refusal would fire on every tool call"
fi

if grep -q 'globalSlotCap\|slotCap' "$guards" 2>/dev/null; then
  ok "A5  a slot-cap guard row is registered — the refusal has landed"
else
  skip "A5  a slot-cap guard row is registered" "a guards.json row with a slot-cap trigger exists. NOT landed by this lane deliberately: guards.json is read by pre-tool-use-overflow-v2.sh, which gates EVERY tool call of EVERY session on this machine, and the trigger types are a closed set of five implemented inside that hook. Arming it means editing the highest-blast-radius file in the engine while twelve lanes across three looms depend on it."
fi

if grep -q 'loom-slots' "$SKILL" 2>/dev/null; then
  ok "A6  the skill names the slot directory (the specification is present)"
else
  no "A6  the skill names the slot directory" "missing from SKILL.md — the whole mechanism is unspecified"
fi

printf '\n== Part B — the reader, against a SANDBOX slot directory (never the live one) ==\n'

if [ ! -x "$READER" ]; then
  no "B-control the reader is executable" "not executable at $READER — every case below is unreachable"
  printf '\n  %s ok, %s FAIL, %s skipped\n\n' "$pass" "$fail" "$skipped"
  exit 1
fi

# B-control: the sandbox is real and the reader is pointed at it, proven by the reader finding a row
# that only exists there. Without this, every reading below could be the reader quietly falling back
# to the live directory.
mk_loom() { # name cap lanes heartbeat-iso
  printf 'sessionDir=/tmp/sessions/%s\ncap=%s\nliveLanes=%s\nheartbeat=%s\n' "$1" "$2" "$3" "$4" > "$SB/$1.slots"
}
iso_ago() { # minutes-ago -> ISO Z
  local m="$1"
  date -u -v-"${m}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-${m} minutes" +%Y-%m-%dT%H:%M:%SZ
}

mk_loom "SANDBOX_ONLY_LOOM" 3 "L1,L2" "$(iso_ago 1)"
out="$(LOOM_SLOTS_DIR="$SB" "$READER" 2>&1)"; rc=$?
if printf '%s' "$out" | grep -q 'SANDBOX_ONLY_LOOM'; then
  ok "B-control the reader is reading the SANDBOX directory (a loom that exists only there was reported) — so no case below is accidentally measuring the live looms"
else
  no "B-control the reader is reading the sandbox directory" "SANDBOX_ONLY_LOOM was not in the output; LOOM_SLOTS_DIR is not being honoured and the live directory may be in play"
fi

if [ "$rc" -eq 0 ]; then ok "B1  under cap (2 lanes of 3) exits 0 — the reading a dispatch proceeds on"
else no "B1  under cap exits 0" "exit $rc"; fi

mk_loom "SANDBOX_ONLY_LOOM" 2 "L1,L2" "$(iso_ago 1)"
LOOM_SLOTS_DIR="$SB" "$READER" --quiet; rc=$?
if [ "$rc" -eq 3 ]; then ok "B2  AT cap (2 lanes of 2) exits 3 — the reading a refusal is built on, and --quiet carries it"
else no "B2  at cap exits 3" "exit $rc — a cap that cannot be read by exit status cannot gate anything"; fi

mk_loom "SANDBOX_ONLY_LOOM" 2 "L1,L2,L3" "$(iso_ago 1)"
LOOM_SLOTS_DIR="$SB" "$READER" --quiet; rc=$?
if [ "$rc" -eq 3 ]; then ok "B3  OVER cap (3 lanes of 2) exits 3 — over is not silently treated as under"
else no "B3  over cap exits 3" "exit $rc"; fi

# B4 — a stale loom row is REPORTED and NOT COUNTED, never silently dropped.
rm -f "$SB"/*.slots
mk_loom "FRESH" 4 "A,B" "$(iso_ago 2)"
mk_loom "ROTTED" 4 "X,Y,Z" "$(iso_ago 400)"
out="$(LOOM_SLOTS_DIR="$SB" "$READER" 2>&1)"
live="$(printf '%s' "$out" | sed -n 's/.*global live lanes *: *\([0-9]*\).*/\1/p')"
stale="$(printf '%s' "$out" | sed -n 's/.*stale loom rows *: *\([0-9]*\).*/\1/p')"
if [ "${live:-x}" = "2" ] && [ "${stale:-x}" = "1" ] && printf '%s' "$out" | grep -q 'ROTTED'; then
  ok "B4  a stale loom row is counted as 0, REPORTED as stale (1), and still NAMED in the table — a count that quietly discarded it would be indistinguishable from one that found nothing"
else
  no "B4  a stale loom row is reported and not counted" "live=${live:-?} stale=${stale:-?}; ROTTED named=$(printf '%s' "$out" | grep -c ROTTED)"
fi

# B5 — THE UTC TRAP. A Z stamp two minutes old must read FRESH on a machine that is not UTC, and a
# genuinely old one must read stale in the SAME invocation, so a clean result cannot come from a
# comparison that is broken in one direction.
rm -f "$SB"/*.slots
mk_loom "TWO_MINUTES_OLD" 4 "A" "$(iso_ago 2)"
mk_loom "EIGHT_HOURS_OLD" 4 "B" "$(iso_ago 480)"
out="$(LOOM_SLOTS_DIR="$SB" "$READER" 2>&1)"
live="$(printf '%s' "$out" | sed -n 's/.*global live lanes *: *\([0-9]*\).*/\1/p')"
offset="$(date +%z)"
if [ "${live:-x}" = "1" ]; then
  ok "B5  THE UTC TRAP — a Z heartbeat 2 minutes old reads FRESH and one 8 hours old reads STALE, on a machine at offset $offset. Both in one invocation, so 'nothing stale' cannot be a one-directional break. Eyeballing the Z stamp against local time here would have called the 2-minute row hours old."
else
  no "B5  THE UTC TRAP — a 2-minute-old Z heartbeat reads fresh" "global live=${live:-?}, expected 1. At offset $offset the ages are being computed against local time instead of epoch, which is the exact mistake that reported three live looms as dead."
fi

# B6 — the lane-side write: liveness asserted by the thing that is live.
#
# The lane directory's name must be the slug the READER computes, not one this test guesses: the
# first draft guessed a leading dash (the live files have none, since the slug strips it) and B6/B7/B8
# went red while B9 went GREEN on a file that had never existed. A pass that rests on an absence it
# did not create is worse than the three reds beside it, so LANEDIR is derived and then proven.
LANEDIR="tmp-sessions-LANEWRITE"
rm -f "$SB"/*.slots; rm -rf "$SB"/*/
mk_loom "$LANEDIR" 4 "STALE_ASSERTION,ANOTHER,THIRD" "$(iso_ago 1)"
LOOM_SLOTS_DIR="$SB" "$READER" --lane-alive "/tmp/sessions/LANEWRITE" "LANE-1" >/dev/null 2>&1
LOOM_SLOTS_DIR="$SB" "$READER" --lane-alive "/tmp/sessions/LANEWRITE" "LANE-2" >/dev/null 2>&1
if [ -f "$SB/$LANEDIR/LANE-1.live" ] && [ -f "$SB/$LANEDIR/LANE-2.live" ]; then
  ok "B6  --lane-alive writes one file per LANE, so the writer of a liveness claim is the lane it describes rather than the conductor the cap constrains"
else
  no "B6  --lane-alive writes one file per lane" "expected $SB/$LANEDIR/LANE-{1,2}.live; found: $(ls "$SB/$LANEDIR/" 2>&1 | tr '\n' ' ')"
fi

out="$(LOOM_SLOTS_DIR="$SB" "$READER" 2>&1)"
live="$(printf '%s' "$out" | sed -n 's/.*global live lanes *: *\([0-9]*\).*/\1/p')"
if [ "${live:-x}" = "2" ] && printf '%s' "$out" | grep -q 'observed'; then
  ok "B7  where lane files exist they WIN over the conductor's asserted list (2 observed, not 3 asserted) and the basis is printed as 'observed', so the disagreement is visible instead of silently resolved"
else
  no "B7  observed lane files win over the asserted list" "live=${live:-?} expected 2; basis line: $(printf '%s' "$out" | grep -c observed)"
fi

# B8 — a lane that dies stops refreshing, and its file ages out WITHOUT anyone noticing on its
# behalf. This is the property that makes the count self-correcting.
touch -t "$(date -v-400M +%Y%m%d%H%M 2>/dev/null || date -d '-400 minutes' +%Y%m%d%H%M)" "$SB/$LANEDIR/LANE-2.live"
out="$(LOOM_SLOTS_DIR="$SB" "$READER" 2>&1)"
live="$(printf '%s' "$out" | sed -n 's/.*global live lanes *: *\([0-9]*\).*/\1/p')"
slanes="$(printf '%s' "$out" | sed -n 's/.*stale lane files *: *\([0-9]*\).*/\1/p')"
if [ "${live:-x}" = "1" ] && [ "${slanes:-x}" = "1" ] && printf '%s' "$out" | grep -q 'LANE-2'; then
  ok "B8  a lane that stopped refreshing ages out of the count on its own (1 live, 1 stale, LANE-2 still named) — nobody had to remember to remove it, which is the failure mode the hand-maintained file has"
else
  no "B8  a dead lane ages out of the count by itself" "live=${live:-?} stale-lanes=${slanes:-?}; LANE-2 named=$(printf '%s' "$out" | grep -c 'LANE-2')"
fi

# B9 — --lane-done is the hand-back, and it must not need the conductor. The file is asserted to
# EXIST before it is removed: `! -f` alone passes loudest when nothing was ever there.
if [ -f "$SB/$LANEDIR/LANE-1.live" ]; then
  LOOM_SLOTS_DIR="$SB" "$READER" --lane-done "/tmp/sessions/LANEWRITE" "LANE-1" >/dev/null 2>&1
  if [ ! -f "$SB/$LANEDIR/LANE-1.live" ]; then
    ok "B9  --lane-done removes the lane's own file (which was confirmed present first), so a clean hand-back frees the slot immediately rather than waiting out the staleness window"
  else
    no "B9  --lane-done removes the lane's own file" "the file survived the removal"
  fi
else
  no "B9  --lane-done removes the lane's own file" "the file was never there to remove, so this case would have passed on an absence it did not create — the precondition is the assertion"
fi

# B10 — an unreadable directory must NOT read as an empty budget.
out="$(LOOM_SLOTS_DIR="$SB/definitely-not-here" "$READER" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'ONE lane at a time'; then
  ok "B10 an unreadable slot directory exits 2 and says to dispatch ONE lane at a time — it does not read as a clean budget, which is the failure the directory exists to prevent"
else
  no "B10 an unreadable slot directory exits 2 with the one-lane instruction" "exit $rc; output: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
fi

# B11 — an EMPTY but readable directory is a reading, not reassurance.
EMPTY="$(mktemp -d "${TMPDIR:-/tmp}/loom-slot-empty.XXXXXX")"
out="$(LOOM_SLOTS_DIR="$EMPTY" "$READER" 2>&1)"; rc=$?
rmdir "$EMPTY" 2>/dev/null
if printf '%s' "$out" | grep -q 'reading, not a clean budget'; then
  ok "B11 an empty-but-readable directory is reported as a reading rather than as a clean budget"
else
  no "B11 an empty directory is reported as a reading" "output: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
fi

printf '\n== Part C — the case against the rule: the cap actually REFUSED a dispatch ==\n'

# Armed by the existence of a registered refusal. Until one exists, this is the honest skip: the
# mechanism is not reachable, and §INV_A_KNOWN_DEFECT_SHIPS_AS_A_SKIPPED_CASE is what it ships as.
armed=0
grep -q 'globalSlotCap\|slotCap' "$guards" 2>/dev/null && armed=1
[ "${LOOM_SLOT_CAP_ARMED:-0}" = "1" ] && armed=1
if [ "$armed" = 1 ]; then
  if [ -n "${SLOT_REFUSAL_LOG:-}" ] && [ -f "${SLOT_REFUSAL_LOG}" ] && grep -q 'slot' "${SLOT_REFUSAL_LOG}"; then
    ok "C1  a dispatch was refused on the global count"
  else
    no "C1  a dispatch was refused on the global count" "ARMED (a slot-cap guard row is registered) and no SLOT_REFUSAL_LOG was supplied. The refusal is now reachable and no run of it has been shown."
  fi
else
  skip "C1  a dispatch was refused on the global count" "a guards.json row with a slot-cap trigger is registered, or LOOM_SLOT_CAP_ARMED=1. The count is computable today (Part B) and nothing consumes it, so the cap is VISIBLE and not ENFORCED — which is a different claim from the ticket's escalation trigger, and the one that actually fails."
fi

printf '\n  %s ok, %s FAIL, %s skipped\n\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ] || exit 1
