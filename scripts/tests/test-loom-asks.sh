#!/bin/bash
# tests/test-loom-asks.sh — the loom asks its forks through /ask instead of publishing /decide boards.
#
# Run: bash ~/.claude/engine/scripts/tests/test-loom-asks.sh
#      ENGINE_DIR=<a checkout> bash …   reads every file from that checkout instead of the installed
#                                       engine (how a worktree is tested before it lands).
#
# WHAT THIS COVERS (IDE-255, LOOMASK)
#   1. The decide pass writes asks (`engine ask new`, routed per § The manager chain), never a board
#      unless the operator asks for one; /decide is composed, not retired.
#   2. The `🗳️ Boards` register is now `🗳️ Asks`, and the Board-fold trigger is an Asks read
#      (`engine ask list --seat`, then `engine ask read`, which stamps readAt).
#   3. `decisionPasses` and the hand-over (`LOOM_INHERITANCE.md`) carry open asks.
#   4. LOOM_AGENT_DIRECTIONS tells a lane how to raise a question for the conductor.
#   Plus: no sentence in the loom's files, COMMANDS.md, /next, /dehydrate or the vision doc still
#   names the register `🗳️ Boards`, and the two scripts that parse the heading (sweep-check,
#   loom-page) read `🗳️ Asks` while still reading an old log's `🗳️ Boards`.
#
# WHY GREP-SHAPED
#   The rules are text a conductor reads; the ask CLI has its own execution tests (test-ask-sh.sh).
#   Each text check is reddened by at least one plant in part P, run on a temp copy. The script
#   checks run the real scripts on fixture logs, and plant E9 runs a copy of sweep-check with the
#   new word removed to show E1 can go red.
#
# THE CONTROL
#   C1 counts "conductor" in the skill and the directions. A zero means the instrument read nothing.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE="${ENGINE_DIR:-$HOME/.claude/engine}"
SKILL="$ENGINE/skills/loom/SKILL.md"
DIRS="$ENGINE/skills/loom/assets/LOOM_AGENT_DIRECTIONS.md"
TPL="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_LOG.md"
INH="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md"
DEB="$ENGINE/skills/loom/assets/TEMPLATE_LOOM.md"
READERS=(
  "$ENGINE/.directives/COMMANDS.md"
  "$ENGINE/skills/next/SKILL.md"
  "$ENGINE/skills/dehydrate/SKILL.md"
  "$ENGINE/docs/CYCLICAL_LOOM_VISION.md"
)
SWEEP="$ENGINE/scripts/sweep-check.sh"
PAGE="$ENGINE/scripts/loom-page.sh"

for f in "$SKILL" "$DIRS" "$TPL" "$INH" "$DEB" "${READERS[@]}" "$SWEEP" "$PAGE"; do
  [ -f "$f" ] || { echo "missing file under test: $f" >&2; exit 1; }
done
echo "under test: $ENGINE"

OLD_REGISTER='🗳️? ?Boards'

# ── helpers ───────────────────────────────────────────────────────────────────────────────────

trigger_block() {  # $1 file, $2 trigger name: the `*   **<name>**` bullet up to the next blank line
  awk -v h="*   **$2**" 'index($0,h)==1 {f=1; print; next} f && /^$/ {exit} f {print}' "$1"
}

inv_line() {  # $1 file, $2 invariant name: its definition line
  grep -F "*   **\`$2\`**:" "$1"
}

# ── checks: each prints one line per violation, so the plants can reuse them ─────────────────

check_no_board_register() {  # $@ files
  local f
  for f in "$@"; do
    grep -n -E "$OLD_REGISTER" "$f" 2>/dev/null | sed "s|^|$(basename "$f"): names the old register: |" | cut -c1-200
  done
}

check_asks_register_declared() {  # $1 log template $2 inheritance $3 debrief
  grep -q -E '^## 🗳️ Asks' "$1" || echo "log template: no '## 🗳️ Asks' register"
  grep -q -E '^## 🗳️ Asks' "$2" || echo "inheritance: no '## 🗳️ Asks' section"
  grep -q -E '^### Asks' "$3" || echo "debrief: no '### Asks' section"
  grep -A3 -E '^## 🗳️ Asks' "$1" | grep -q -F 'engine ask read' || echo "log template: the Asks register does not say a row is read with engine ask read"
}

check_decide_pass_writes_asks() {  # $1 skill
  local b; b=$(trigger_block "$1" 'Decide pass')
  [ -n "$b" ] || { echo "skill: no Decide pass trigger"; return; }
  printf '%s' "$b" | grep -q -F 'engine ask new' || echo "Decide pass: does not write an ask (engine ask new)"
  printf '%s' "$b" | grep -q -F '**Publishes**: no' || echo "Decide pass: still publishes"
  printf '%s' "$b" | grep -q -F 'only when the operator asks for one' || echo "Decide pass: a board is not limited to the operator's request"
  printf '%s' "$b" | grep -q -F '/decide` §1–§3 and §6' || echo "Decide pass: does not compose /decide's mining, cards and record"
  grep -q -F 'renders its board at that gate' "$1" && echo "skill: a pass still renders its board at the gate"
  grep -q -F 'The board stays the page a fork is asked on' "$1" && echo "manager chain: the board is still the asking surface"
}

check_asks_read_trigger() {  # $1 skill
  local b; b=$(trigger_block "$1" 'Asks read')
  [ -n "$b" ] || { echo "skill: no Asks read trigger"; return; }
  printf '%s' "$b" | grep -q -F 'engine ask list --seat' || echo "Asks read: no engine ask list --seat"
  printf '%s' "$b" | grep -q -F 'engine ask read' || echo "Asks read: no engine ask read"
  printf '%s' "$b" | grep -q -F 'never a read' || echo "Asks read: a delivered push is not said to be unread"
  printf '%s' "$b" | grep -q -F 'never on a watcher or a poll loop' || echo "Asks read: no no-timer clause"
  [ -n "$(trigger_block "$1" 'Board fold')" ] && echo "skill: the Board fold trigger is still declared"
}

check_invariants() {  # $1 skill
  grep -q -F 'INV_LOOM_BOARD_AT_A_BOUNDARY' "$1" && echo "skill: INV_LOOM_BOARD_AT_A_BOUNDARY still present"
  local a; a=$(inv_line "$1" '¶INV_LOOM_ASKS_AT_A_BOUNDARY')
  [ -n "$a" ] || echo "skill: ¶INV_LOOM_ASKS_AT_A_BOUNDARY is not defined"
  local s; s=$(inv_line "$1" '¶INV_LOOM_SURFACES_FORKS_UNASKED')
  printf '%s' "$s" | grep -q -F '**`decisionPasses` gates on every open ask too**' \
    || echo "SURFACES_FORKS_UNASKED: decisionPasses does not key on open asks"
  local p; p=$(inv_line "$1" '¶INV_LOOM_PASS_ON_NEVER_DISCARD')
  printf '%s' "$p" | grep -q -F 'an ask still unanswered' || echo "PASS_ON_NEVER_DISCARD: an open ask is not named as inherited"
}

check_handover_carries_asks() {  # $1 inheritance
  local b; b=$(awk '/^## 🗳️ Asks/ {f=1; next} f && /^## / {exit} f' "$1")
  [ -n "$b" ] || { echo "inheritance: no Asks section body"; return; }
  printf '%s' "$b" | grep -q -F 'may not be discarded' || echo "inheritance: Asks rows may be discarded"
  printf '%s' "$b" | grep -q -F '<seat>/<id>' || echo "inheritance: an Asks row does not carry the ask's ref"
}

check_lane_raises_a_question() {  # $1 directions
  local p; p=$(grep -F '**To raise a question for the conductor**' "$1")
  [ -n "$p" ] || { echo "directions: no 'To raise a question for the conductor' rule"; return; }
  printf '%s' "$p" | grep -q -F 'SendMessage' || echo "directions: the rule does not say SendMessage"
  printf '%s' "$p" | grep -q -F 'never `engine ask new`' || echo "directions: the rule lets a lane write an ask file"
  printf '%s' "$p" | grep -q -F 'never `AskUserQuestion`' || echo "directions: the rule lets a lane block on AskUserQuestion"
}

all_violations() {  # $1 skill $2 dirs $3 log tpl $4 inheritance $5 debrief
  check_no_board_register "$1" "$2" "$3" "$4" "$5"
  check_asks_register_declared "$3" "$4" "$5"
  check_decide_pass_writes_asks "$1"
  check_asks_read_trigger "$1"
  check_invariants "$1"
  check_handover_carries_asks "$4"
  check_lane_raises_a_question "$2"
}

report() {  # $1 label, $2 violations
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "no violations" "$2"; fi
}

# ── C — the control ───────────────────────────────────────────────────────────────────────────

test_C1_control_the_instrument_reads_the_files() {
  local a b
  a=$(grep -c -i 'conductor' "$SKILL"); b=$(grep -c -i 'conductor' "$DIRS")
  if [ "$a" -gt 10 ] && [ "$b" -gt 5 ]; then
    pass "C1: control — 'conductor' read $a times in SKILL.md and $b in the directions"
  else
    fail "C1: control" ">10 and >5" "$a and $b"
  fi
}

# ── A — the rules, on the files under test ─────────────────────────────────────────────────────

test_A1_decide_pass_writes_asks_never_a_board() { report "A1: the decide pass writes asks, a board only on the operator's ask" "$(check_decide_pass_writes_asks "$SKILL")"; }
test_A2_register_is_asks() { report "A2: the register is 🗳️ Asks in the log, the inheritance and the debrief" "$(check_asks_register_declared "$TPL" "$INH" "$DEB")"; }
test_A3_asks_read_replaces_board_fold() { report "A3: the Asks read trigger replaces the Board fold" "$(check_asks_read_trigger "$SKILL")"; }
test_A4_invariants_key_on_open_asks() { report "A4: decisionPasses and pass-on key on open asks" "$(check_invariants "$SKILL")"; }
test_A5_handover_carries_open_asks() { report "A5: LOOM_INHERITANCE carries open asks" "$(check_handover_carries_asks "$INH")"; }
test_A6_lane_raises_a_question() { report "A6: the directions tell a lane how to raise a question" "$(check_lane_raises_a_question "$DIRS")"; }
test_A7_no_file_names_the_old_register() {
  report "A7: no loom file or reader names the register 🗳️ Boards" \
    "$(check_no_board_register "$SKILL" "$DIRS" "$TPL" "$INH" "$DEB" "${READERS[@]}")"
}

# ── E — the two scripts that parse the heading ───────────────────────────────────────────────

fixture_dir=""
make_fixture() {  # $1 register word → a log with a decision then that register block
  fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/loom-asks-fx.XXXXXX")
  printf '# Loom log\n\n## [2026-01-01 10:00:00] 💡 Decision — pick A\n*   x\n\n## [2026-01-01 10:05:00] 🗳️ %s (live)\n| ask |\n|---|\n| a/b |\n' "$1" > "$fixture_dir/LOOM_LOG.md"
}

test_E1_sweep_check_reads_the_asks_heading() {
  make_fixture Asks
  local out rc; out=$(bash "$SWEEP" "$fixture_dir/LOOM_LOG.md" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q -E 'Asks L[0-9]'; then
    pass "E1: sweep-check reads '🗳️ Asks' as a register write (exit 0)"
  else
    fail "E1: sweep-check reads '🗳️ Asks'" "exit 0 and 'Asks L<n>'" "exit $rc; $(printf '%s' "$out" | grep 'latest register')"
  fi
  rm -rf "$fixture_dir"
}

test_E2_sweep_check_still_reads_an_old_boards_heading() {
  make_fixture Boards
  local rc; bash "$SWEEP" "$fixture_dir/LOOM_LOG.md" >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "E2: sweep-check still reads an old log's '🗳️ Boards' (exit 0)"
  rm -rf "$fixture_dir"
}

test_E3_loom_page_reads_the_asks_heading() {
  make_fixture Asks
  local out; out=$(bash "$PAGE" "$fixture_dir/LOOM_LOG.md" --text 2>&1 </dev/null)
  if printf '%s' "$out" | grep -q '^=== Asks' && ! printf '%s' "$out" | grep -q 'Asks: NOT FOUND'; then
    pass "E3: loom-page finds the '🗳️ Asks' register"
  else
    fail "E3: loom-page finds '🗳️ Asks'" "an Asks register, found" "$(printf '%s' "$out" | grep -i -E 'asks|boards' | head -3)"
  fi
  rm -rf "$fixture_dir"
}

# ── P — plants: each removal or inversion must turn the aggregate red ─────────────────────────

plant_dir=""
setup() {
  plant_dir=$(mktemp -d "${TMPDIR:-/tmp}/loom-asks-plant.XXXXXX")
  cp "$SKILL" "$plant_dir/S.md"; cp "$DIRS" "$plant_dir/D.md"; cp "$TPL" "$plant_dir/T.md"
  cp "$INH" "$plant_dir/I.md"; cp "$DEB" "$plant_dir/L.md"
}
teardown() { [ -n "$plant_dir" ] && rm -rf "$plant_dir"; plant_dir=""; }

perl_in() {  # $1 file, $2 literal to find, $3 replacement — one occurrence required
  FIND="$2" REPL="$3" perl -0pi -e 'my $n = s/\Q$ENV{FIND}\E/$ENV{REPL}/; die "plant missed\n" unless $n' "$1"
}

plant_violations() { all_violations "$plant_dir/S.md" "$plant_dir/D.md" "$plant_dir/T.md" "$plant_dir/I.md" "$plant_dir/L.md"; }

assert_plant_reddens() {  # $1 label
  if [ -n "$(plant_violations)" ]; then pass "P: plant '$1' reddens the contract"
  else fail "P: plant '$1' reddens the contract" "at least one violation" "none — the check cannot see this defect"; fi
}

test_P0_unplanted_copy_is_clean() { report "P0: the unplanted copy passes the aggregate check" "$(plant_violations)"; }

test_P1_decide_pass_publishes_a_board_again() {
  perl_in "$plant_dir/S.md" '**Publishes**: no — the forks are asked' '**Publishes**: ⛔ YES — the board is where the forks are asked' 2>/dev/null || { fail "P1: setup" "applied" "missed"; return; }
  assert_plant_reddens "P1 the decide pass publishes a board"
}

test_P2_asks_read_trigger_removed() {
  awk 'index($0,"*   **Asks read**")==1 {s=1; next} s && /^$/ {s=0; next} !s' "$plant_dir/S.md" > "$plant_dir/S2.md" && mv "$plant_dir/S2.md" "$plant_dir/S.md"
  assert_plant_reddens "P2 the Asks read trigger removed"
}

test_P3_register_renamed_back_to_boards() {
  perl_in "$plant_dir/T.md" '## 🗳️ Asks' '## 🗳️ Boards' 2>/dev/null || { fail "P3: setup" "applied" "missed"; return; }
  assert_plant_reddens "P3 the log template's register renamed back to Boards"
}

test_P4_decisionPasses_stops_keying_on_asks() {
  perl_in "$plant_dir/S.md" '**`decisionPasses` gates on every open ask too**' '`decisionPasses` gates on the passes' 2>/dev/null || { fail "P4: setup" "applied" "missed"; return; }
  assert_plant_reddens "P4 decisionPasses no longer keys on open asks"
}

test_P5_lane_rule_inverted() {
  perl_in "$plant_dir/D.md" 'never `engine ask new`' 'with `engine ask new`' 2>/dev/null || { fail "P5: setup" "applied" "missed"; return; }
  assert_plant_reddens "P5 the lane rule lets a lane write an ask file"
}

test_P6_timer_clause_removed() {
  perl_in "$plant_dir/S.md" 'never on a watcher or a poll loop' 'on a watcher every minute' 2>/dev/null || { fail "P6: setup" "applied" "missed"; return; }
  assert_plant_reddens "P6 the Asks read runs on a watcher"
}

test_P7_handover_may_discard_an_ask() {
  perl_in "$plant_dir/I.md" 'may not be discarded' 'may be dropped' 2>/dev/null || { fail "P7: setup" "applied" "missed"; return; }
  assert_plant_reddens "P7 the inheritance lets an open ask be dropped"
}

test_P8_board_only_on_request_removed() {
  perl_in "$plant_dir/S.md" 'a board publishes only when the operator asks for one, under its own confirm' 'a board publishes whenever the pass mined a fork' 2>/dev/null || { fail "P8: setup" "applied" "missed"; return; }
  assert_plant_reddens "P8 a board is published whenever a fork is mined"
}

test_P9_sweep_check_without_the_asks_word() {
  # The script check, planted: a copy of sweep-check that knows only `Boards` must miss the
  # Asks register and exit 3 on the same fixture E1 passes on.
  cp "$SWEEP" "$plant_dir/sweep.sh"
  perl_in "$plant_dir/sweep.sh" '(?:Asks|Boards)' 'Boards' 2>/dev/null || { fail "P9: setup" "applied" "missed"; return; }
  make_fixture Asks
  local rc; bash "$plant_dir/sweep.sh" "$fixture_dir/LOOM_LOG.md" >/dev/null 2>&1; rc=$?
  rm -rf "$fixture_dir"
  if [ "$rc" -ne 0 ]; then pass "P9: sweep-check without 'Asks' misses the register (exit $rc), so E1 can go red"
  else fail "P9: the plant reddens E1" "non-zero exit" "exit 0"; fi
}

run_discovered_tests
