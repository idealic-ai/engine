#!/bin/bash
# tests/test-loom-proof-rule.sh — a loom thread proves only when a human would want to read the page,
# and a lane that proves hands back the lessons the proving pass turned up.
#
# Run: bash ~/.claude/engine/scripts/tests/test-loom-proof-rule.sh
#      ENGINE_DIR=<a checkout> bash …   reads every file from that checkout instead of the installed
#                                       engine (how a worktree is tested before it lands).
#
# WHAT THIS COVERS (operator ruling 2026-10-31 01:00 and 01:01, lane PROOFBAR)
#   R1. ¶INV_LOOM_EVERY_THREAD_PROVES states the reader test, the `no page — <what it was>` row form,
#       that the reader test wins over the no-page list, the Lessons from proving block, and that a
#       lesson leaves the `scrutiny` cell unchanged.
#   R2. LOOM_AGENT_DIRECTIONS § Your last act asks for the `no page` line and a `## Lessons from
#       proving` block that says `none` rather than being omitted.
#   R3. The ledger and the inheritance Threads table carry a `📄 proof` cell with the lessons reading.
#   R4. The experiment lanes' directions carry the Lessons block too.
#   R5. The retired wording stays gone from every file that states the rule: "proves like one",
#       "never exempt", "size may not be cited", "every round", the conductor re-gating a page,
#       "a proof page per thread", and a lesson writing the scrutiny cell.
#
# Each check is reddened by a plant in part P, run on a temp copy. C1 is the control.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE="${ENGINE_DIR:-$HOME/.claude/engine}"
SKILL="$ENGINE/skills/loom/SKILL.md"
DIRS="$ENGINE/skills/loom/assets/LOOM_AGENT_DIRECTIONS.md"
TPL="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_LOG.md"
INH="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md"
XSKILL="$ENGINE/skills/loom-experiment/SKILL.md"
XDIRS="$ENGINE/skills/loom-experiment/assets/EXPERIMENT_DIRECTIONS.md"

for f in "$SKILL" "$DIRS" "$TPL" "$INH" "$XSKILL" "$XDIRS"; do
  [ -f "$f" ] || { echo "missing file under test: $f" >&2; exit 1; }
done
echo "under test: $ENGINE"

INV_PREFIX='*   **`¶INV_LOOM_EVERY_THREAD_PROVES`**:'

# ── checks: each prints one line per violation, nothing when clean ─────────────────────────────

check_invariant() {  # $1 skill
  local l; l=$(grep -F -- "$INV_PREFIX" "$1")
  [ -n "$l" ] || { echo "invariant line not found"; return; }
  local need
  for need in 'a human would want to read it' 'no page — <what it was>' 'the reader test wins over the list' \
              'Lessons from proving' 'leaving the `scrutiny` cell unchanged' 'lessons: <n> unrouted'; do
    printf '%s' "$l" | grep -qF -- "$need" || echo "invariant lacks: $need"
  done
}

check_directions() {  # $1 directions
  local sec; sec=$(sed -n '/^## Your last act/,/^## Measuring/p' "$1")
  [ -n "$sec" ] || { echo "directions: no Your last act section"; return; }
  printf '%s' "$sec" | grep -qF -- '## Lessons from proving' || echo "directions: no Lessons from proving block"
  printf '%s' "$sec" | grep -qF -- 'the block says `none`' || echo "directions: the Lessons block may be omitted"
  printf '%s' "$sec" | grep -qF -- 'no page — <what it was>' || echo "directions: no 'no page' hand-back line"
  printf '%s' "$sec" | grep -qF -- 'land, merge, push, rebase or re-pick' || echo "directions: landings are not named as no-page"
}

check_registers() {  # $1 log template, $2 inheritance template
  grep -qF -- '| 🔍 scrutiny | 📄 proof | PR | status |' "$1" || echo "ledger: no 📄 proof column"
  grep -qF -- 'lessons: routed' "$1" || echo "ledger: no lessons reading"
  grep -qF -- '| 🔍 scrutiny | 📄 proof | reach it by' "$2" || echo "inheritance Threads: no 📄 proof column"
  grep -qF -- 'lessons: <n> unrouted' "$2" || echo "inheritance: an unrouted lesson does not keep the row open"
}

check_experiment() {  # $1 experiment directions
  grep -qF -- '## Lessons from proving' "$1" || echo "experiment directions: no Lessons block"
  grep -qF -- 'no page — <what it was>' "$1" || echo "experiment directions: no 'no page' line"
}

RETIRED=(
  'proves like one'
  'never exempt'
  'size may not be cited'
  'may not be cited as one'
  'every round'
  'Every "done"'
  're-gates the published page'
  'a proof page per thread'
  'The `scrutiny` cell records it'
)
check_retired() {  # files…
  local f p
  for f in "$@"; do
    for p in "${RETIRED[@]}"; do
      grep -n -i -F -- "$p" "$f" | sed "s|^|$(basename "$f"): retired '$p' at line |" | cut -c1-200
    done
  done
}

all_violations() {  # $1 skill $2 dirs $3 tpl $4 inh $5 xskill $6 xdirs
  check_invariant "$1"; check_directions "$2"; check_registers "$3" "$4"; check_experiment "$6"
  check_retired "$1" "$2" "$3" "$4" "$5" "$6"
}

report() {  # $1 label, $2 violations
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "no violations" "$2"; fi
}

# ── C — the control ───────────────────────────────────────────────────────────────────────────

test_C1_control_the_instrument_reads_the_files() {
  local a b; a=$(grep -c -i 'proof' "$SKILL"); b=$(grep -c -i 'proof' "$DIRS")
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then pass "C1: control — 'proof' found in the skill ($a) and the directions ($b)"
  else fail "C1: control" "non-zero counts" "skill=$a directions=$b"; fi
}

# ── R — the rule ──────────────────────────────────────────────────────────────────────────────

test_R1_invariant_states_the_reader_test() { report "R1: the invariant states the reader test, the no-page row, its precedence, the Lessons block and the untouched scrutiny cell" "$(check_invariant "$SKILL")"; }
test_R2_directions_ask_for_no_page_and_lessons() { report "R2: the lane directions ask for the no-page line and a Lessons block that is never omitted" "$(check_directions "$DIRS")"; }
test_R3_registers_carry_the_proof_cell() { report "R3: the ledger and the inheritance Threads table carry a 📄 proof cell with the lessons reading" "$(check_registers "$TPL" "$INH")"; }
test_R4_experiment_lanes_hand_back_lessons() { report "R4: the experiment lanes' directions carry the Lessons block and the no-page line" "$(check_experiment "$XDIRS")"; }
test_R5_retired_wording_stays_gone() { report "R5: no file that states the rule carries the retired wording" "$(check_retired "$SKILL" "$DIRS" "$TPL" "$INH" "$XSKILL" "$XDIRS")"; }

# ── P — plants: each must turn the aggregate red ──────────────────────────────────────────────

plant_dir=""
setup() {
  plant_dir=$(mktemp -d "${TMPDIR:-/tmp}/loom-proof-plant.XXXXXX")
  cp "$SKILL" "$plant_dir/S.md"; cp "$DIRS" "$plant_dir/D.md"; cp "$TPL" "$plant_dir/T.md"
  cp "$INH" "$plant_dir/I.md"; cp "$XSKILL" "$plant_dir/XS.md"; cp "$XDIRS" "$plant_dir/XD.md"
}
teardown() { [ -n "$plant_dir" ] && rm -rf "$plant_dir"; plant_dir=""; }

perl_in() {  # $1 file, $2 literal to find, $3 replacement — first occurrence, one required
  FIND="$2" REPL="$3" perl -0pi -e 'my $n = s/\Q$ENV{FIND}\E/$ENV{REPL}/; die "plant missed\n" unless $n' "$1"
}
perl_on_invariant() {  # $1 file, $2 literal on the invariant line, $3 replacement
  FIND="$2" REPL="$3" PFX="$INV_PREFIX" perl -pi -e 'BEGIN{$n=0} if (index($_,$ENV{PFX})==0) { $n += s/\Q$ENV{FIND}\E/$ENV{REPL}/ } END{ die "plant missed\n" unless $n }' "$1"
}

plant_violations() { all_violations "$plant_dir/S.md" "$plant_dir/D.md" "$plant_dir/T.md" "$plant_dir/I.md" "$plant_dir/XS.md" "$plant_dir/XD.md"; }

assert_plant_reddens() {  # $1 label
  if [ -n "$(plant_violations)" ]; then pass "P: plant '$1' reddens the contract"
  else fail "P: plant '$1' reddens the contract" "at least one violation" "none — the check cannot see this defect"; fi
}
setup_missed() { fail "$1: SETUP FAILED — the planted string was not found, so this plant did not run (not a detection)" "the string present" "missing: $2"; }

test_P0_unplanted_copy_is_clean() { report "P0: the unplanted copy passes the aggregate check" "$(plant_violations)"; }

test_P1_invariant_loses_the_lessons_block() {
  perl_on_invariant "$plant_dir/S.md" 'Lessons from proving' 'closing notes' 2>/dev/null || { setup_missed "P1" "Lessons from proving on the invariant line"; return; }
  assert_plant_reddens "P1 the invariant drops the Lessons block"
}
test_P2_invariant_loses_the_precedence() {
  perl_on_invariant "$plant_dir/S.md" 'the reader test wins over the list' 'the list is final' 2>/dev/null || { setup_missed "P2" "the precedence clause"; return; }
  assert_plant_reddens "P2 the invariant drops 'the reader test wins'"
}
test_P3_old_conductor_pass_sentence_restored() {
  perl_in "$plant_dir/S.md" 'is judged by the same test.**' 'is a thread, and proves like one.**' 2>/dev/null || { setup_missed "P3" "the conductor-pass heading"; return; }
  assert_plant_reddens "P3 'proves like one' restored"
}
test_P4_size_ban_restored_in_directions() {
  perl_in "$plant_dir/D.md" 'If you are unsure, compose the page' 'Size may not be cited. If you are unsure, compose the page' 2>/dev/null || { setup_missed "P4" "the unsure sentence"; return; }
  assert_plant_reddens "P4 'size may not be cited' restored in the directions"
}
test_P5_conductor_regate_restored() {
  perl_in "$plant_dir/D.md" 'Nobody re-gates your page after you' 'The conductor then re-gates the published page' 2>/dev/null || { setup_missed "P5" "the no-regate sentence"; return; }
  assert_plant_reddens "P5 the conductor re-gating a page restored"
}
test_P6_ledger_loses_the_proof_cell() {
  perl_in "$plant_dir/T.md" '| 🔍 scrutiny | 📄 proof | PR | status |' '| 🔍 scrutiny | PR | status |' 2>/dev/null || { setup_missed "P6" "the ledger header"; return; }
  assert_plant_reddens "P6 the ledger drops the 📄 proof column"
}
test_P7_experiment_directions_lose_lessons() {
  perl_in "$plant_dir/XD.md" '## Lessons from proving' '## Notes' 2>/dev/null || { setup_missed "P7" "the experiment Lessons block"; return; }
  assert_plant_reddens "P7 the experiment directions drop the Lessons block"
}
test_P8_lesson_writes_the_scrutiny_cell() {
  perl_in "$plant_dir/S.md" '**The `scrutiny` cell is unchanged by a lesson**' 'The `scrutiny` cell records it' 2>/dev/null || { setup_missed "P8" "the unchanged-cell sentence"; return; }
  assert_plant_reddens "P8 a lesson writes the scrutiny cell again"
}
test_P9_directions_allow_omitting_lessons() {
  perl_in "$plant_dir/D.md" 'the block says `none`' 'you may leave the block out' 2>/dev/null || { setup_missed "P9" "the none clause"; return; }
  assert_plant_reddens "P9 the directions let the Lessons block be omitted"
}

run_discovered_tests
