#!/bin/bash
# tests/test-envision-skill.sh — a loom writes and decomposes a vision through /envision, and the
# loom's one vision call and its vision-deviation destination name /envision rather than /direct.
#
# Run: bash ~/.claude/engine/scripts/tests/test-envision-skill.sh
#      ENGINE_DIR=<a checkout> bash …   reads every file from that checkout instead of the installed
#                                       engine (how a worktree is tested before it lands).
#
# WHAT THIS COVERS (IDE-364; operator rulings on ask meta:engine/envision-shape, 2026-11-04)
#   E1. skills/envision/SKILL.md exists, is named envision, rides its host (§INV_RIDE_NEVER_ACTIVATES),
#       declares the four actions, writes docs/<NAME>_VISION.md, decomposes into
#       builds/<slug>_ENVISION_TOPICS.md in /groom's topic format, and files no ticket and edits no
#       fleet config.
#   E2. The vision template's chapter block carries every field the loom reads.
#   E3. The loom's Vision reconcile trigger runs Skill(envision, "reconcile …"), its vision-deviation
#       row names `/envision` — reconcile, and no `Skill(direct` call survives in the loom skill.
#   E4. The inheritance template's Docs owed destination names /envision, not /direct.
#   E5. TEMPLATE_LOOM_LOG.md declares the 📚 Docs owed and ⚖️ Rules owed blocks the triggers read.
#   E6. /direct carries one line pointing a loom at /envision (BESIDE: /direct stays for standalone).
#   E7. reconcile may write into an existing _DIRECT.md vision (M1 of the ENVISION critique): the skill
#       says so, and no sentence forbids rewriting a _DIRECT.md; renames and moves stay forbidden.
#   N1-N4. Negative checks: the skill carries no instruction that breaks a ruling — no Skill(ticket or
#       save_issue call (DECOMP), no `engine session activate|phase` outside a "never" sentence
#       (ride), no fleet yml or @pane_parent write (PROPOSE), no rename or move of a _DIRECT file
#       (DOCS). Each has a plant that ADDS the forbidden line, not one that deletes a token.
#   S2. An ask shaped as draft step 5 says (opening with the chapter list, a two-sentence paragraph
#       under each fork) files through `ask.sh new`'s floor into a scratch ASK_ROOT with no live
#       session to deliver to; the same ask with a six-word paragraph under its second fork is
#       refused (the control that shows the floor ran). Step 5 states the paragraph rule.
#
# Each check is reddened by a plant in part P, run on a temp copy. C1 is the control.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE="${ENGINE_DIR:-$HOME/.claude/engine}"
ENV_SKILL="$ENGINE/skills/envision/SKILL.md"
ENV_TPL="$ENGINE/skills/envision/assets/TEMPLATE_ENVISION_VISION.md"
LOOM="$ENGINE/skills/loom/SKILL.md"
LOG_TPL="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_LOG.md"
INH="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md"
DIRECT="$ENGINE/skills/direct/SKILL.md"

for f in "$ENV_SKILL" "$ENV_TPL" "$LOOM" "$LOG_TPL" "$INH" "$DIRECT"; do
  [ -f "$f" ] || { echo "missing file under test: $f" >&2; exit 1; }
done
echo "under test: $ENGINE"

FIELDS=('**Thread**' '**Ticket**' '**Status**' '**Plain terms**' '**Goal**' '**Wrong today**'
        '**Acceptance signals**' '**First step**' '**Not in scope**' '**Size**' '**Depends on**'
        '**Wave**' '**Owner**' '**Paths**' '**Open questions**')

# ── checks: each prints one line per violation, nothing when clean ─────────────────────────────

check_skill() {  # $1 envision SKILL.md
  grep -qx 'name: envision' "$1" || echo "skill: frontmatter is not 'name: envision'"
  local need
  for need in '§INV_RIDE_NEVER_ACTIVATES' '### draft' '### revise' '### reconcile' '### decompose' \
              'docs/<NAME>_VISION.md' 'builds/<slug>_ENVISION_TOPICS.md' 'TEMPLATE_GROOM_TOPICS.md' \
              'PROPOSED' '¶INV_ENVISION_FILES_NO_TICKET' '¶INV_ENVISION_PROPOSES_OWNERS_ONLY' \
              'Skill(ask' 'never renamed'; do
    grep -qF -- "$need" "$1" || echo "skill lacks: $need"
  done
}

check_template() {  # $1 vision template
  local f
  for f in "${FIELDS[@]}"; do grep -qF -- "$f" "$1" || echo "template chapter lacks field: $f"; done
}

check_loom() {  # $1 loom SKILL.md
  grep -qF -- 'Skill(envision, "reconcile <vision path> — <what moved>")' "$1" || echo "loom: Vision reconcile trigger does not run /envision"
  grep -qF -- 'names `/envision` as its destination' "$1" || echo "loom: trigger condition does not name /envision"
  grep -qF -- '**`/envision` — reconcile**' "$1" || echo "loom: vision-deviation row does not name /envision"
  grep -nF -- 'Skill(direct' "$1" | sed 's|^|loom: Skill(direct call survives at line |'
  grep -nF -- '`/direct` — reconcile' "$1" | sed 's|^|loom: /direct — reconcile destination survives at line |'
}

check_inheritance() {  # $1 inheritance template
  grep -qF -- '`/envision` — reconcile' "$1" || echo "inheritance: Docs owed destination does not name /envision"
  grep -nF -- '`/direct` — reconcile' "$1" | sed 's|^|inheritance: /direct — reconcile survives at line |'
}

check_log_template() {  # $1 loom log template
  grep -q '^## 📚 Docs owed' "$1" || echo "log template: no ## 📚 Docs owed block"
  grep -q '^## ⚖️ Rules owed' "$1" || echo "log template: no ## ⚖️ Rules owed block"
  grep -qF -- '`/envision` — reconcile' "$1" || echo "log template: Docs owed destination does not offer /envision"
}

check_direct() {  # $1 direct SKILL.md
  grep -qF -- 'Inside a loom, use `/envision`' "$1" || echo "direct: no line pointing a loom at /envision"
}

check_direct_reconcile() {  # $1 envision SKILL.md — a reconcile of a _DIRECT.md fixture is allowed
  local fixture='docs/LIVE_MARKET_DIRECT.md'
  case "$fixture" in *_DIRECT.md) ;; *) echo "fixture is not a _DIRECT.md path"; return ;; esac
  grep -qF -- '**`reconcile` writes to any vision file, a `_DIRECT.md` included**' "$1" \
    || echo "skill: reconcile of $fixture is not allowed (no 'writes to any vision file, a _DIRECT.md included')"
  grep -niE '_DIRECT[^ ]* .*(rewritten|never (touch|write|edit)).*by this skill|never renamed, moved or rewritten' "$1" \
    | sed 's|^|skill: a sentence forbids reconciling a _DIRECT.md at line |'
}

check_step5_paragraph_rule() {  # $1 envision SKILL.md
  grep -qF -- 'a paragraph of at least two sentences' "$1" || echo "skill: step 5 does not require a two-sentence paragraph under every fork"
  grep -qF -- 'it does not explain any fork' "$1" || echo "skill: step 5 lets the chapter list stand in for a fork's paragraph"
}

check_negatives() {  # $1 envision SKILL.md — forbidden instructions, one line per hit
  grep -nE 'Skill\(ticket|save_issue' "$1" | sed 's|^|DECOMP broken: ticket filing at line |'
  grep -nE 'engine session (activate|phase)' "$1" | grep -viE 'never|no `engine session' | sed 's|^|ride broken: session write at line |'
  grep -nE 'fleet-[A-Za-z0-9_-]*\.ya?ml|@pane_parent' "$1" | grep -viE 'never' | sed 's|^|PROPOSE broken: fleet write at line |'
  grep -nE '_DIRECT' "$1" | grep -E 'git mv|\bmv |renam' | grep -viE 'never|no renames' | sed 's|^|DOCS broken: _DIRECT rename at line |'
}

all_violations() {  # $1 skill $2 tpl $3 loom $4 logtpl $5 inh $6 direct
  check_direct_reconcile "$1"; check_negatives "$1"; check_step5_paragraph_rule "$1"
  check_skill "$1"; check_template "$2"; check_loom "$3"; check_log_template "$4"; check_inheritance "$5"; check_direct "$6"
}

report() {  # $1 label, $2 violations
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "no violations" "$2"; fi
}

# ── C — the control ───────────────────────────────────────────────────────────────────────────

test_C1_control_the_instrument_reads_the_files() {
  local a b; a=$(grep -c 'Vision reconcile' "$LOOM"); b=$(grep -c 'vision' "$ENV_SKILL")
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then pass "C1: control — 'Vision reconcile' in the loom ($a), 'vision' in /envision ($b)"
  else fail "C1: control" "non-zero counts" "loom=$a envision=$b"; fi
}

# ── E — the contract ──────────────────────────────────────────────────────────────────────────

test_E1_envision_skill_contract() { report "E1: /envision rides, has four actions, writes docs/<NAME>_VISION.md, decomposes to groom topics, files nothing" "$(check_skill "$ENV_SKILL")"; }
test_E2_chapter_fields() { report "E2: the vision template's chapter carries every field the loom reads" "$(check_template "$ENV_TPL")"; }
test_E3_loom_names_envision() { report "E3: the loom's reconcile trigger and deviation row name /envision, and no Skill(direct call survives" "$(check_loom "$LOOM")"; }
test_E4_inheritance_names_envision() { report "E4: the inheritance Docs owed destination names /envision" "$(check_inheritance "$INH")"; }
test_E5_log_template_registers() { report "E5: the loom log template declares 📚 Docs owed and ⚖️ Rules owed" "$(check_log_template "$LOG_TPL")"; }
test_E7_reconcile_may_write_a_direct_vision() { report "E7: reconcile is allowed on a _DIRECT.md fixture, and no sentence forbids it" "$(check_direct_reconcile "$ENV_SKILL")"; }
test_N_no_instruction_breaks_a_ruling() { report "N: no ticket filing, session write, fleet write or _DIRECT rename instruction in /envision" "$(check_negatives "$ENV_SKILL")"; }
test_E6_direct_points_looms_at_envision() { report "E6: /direct points a loom at /envision" "$(check_direct "$DIRECT")"; }

step5_ask() {  # $1 the paragraph under the second fork
  cat <<EOF
This vision plans the ask app's batch mode, in two chapters. The chapters are listed for context:
- \`@app/readback\` (READBACK): show who read an answer — proposed
- \`@app/kinds\` (KINDS): richer question kinds — ripe

## ¶ASK_SCOPE: Choose one: Does the read-back chapter stay in this vision?
The read-back chapter decides whether answers show who read them, which touches the store's read stamps. Today the line reads \`READBACK — proposed (fork SCOPE)\`, and each option below would write it as shown.
Lean: KEEP
Counter: read stamps already exist, so the chapter may be a finding rather than a chunk.
- [ ] [KEEP] Keep the chapter as a chunk
  The line becomes \`READBACK — ripe\`, and it is decomposed with the others.
  Cost: one more thread in the wave.
- [ ] [DROP] Drop it to an inbox finding
  The line becomes \`READBACK — dropped (finding)\`.
  Cost: the read-back gap waits for the next grooming pass.

## ¶ASK_OWNER: Choose one: Which seat owns the kinds chapter?
$1
Lean: UI
- [ ] [UI] The UI seat
  The chapter becomes a seat handover to the UI seat.
  Cost: a handover round trip before it starts.
- [ ] [HERE] This loom's seat
  The chapter becomes a thread in this loom.
  Cost: this loom carries one more lane.
EOF
}
file_step5_ask() {  # $1 scratch root, $2 id, $3 paragraph — prints the exit code
  mkdir -p "$1/askroot" "$1/sessions"
  step5_ask "$3" | ASK_ROOT="$1/askroot" ASK_SESSIONS_DIR="$1/sessions" FLEET_PANE=test:envision TMUX= \
    bash "$ENGINE/scripts/ask.sh" new --id "$2" --to test:nobody --why "the vision draft waits on two choices" \
      --importance low --stakes "a wrong pick moves one chapter" --lean "KEEP" --falsifier "a chapter that needs the other scope" \
      >"$1/$2.out" 2>&1
  echo $?
}
test_S2_step5_shape_files_through_the_floor() {
  local d; d=$(mktemp -d "${TMPDIR:-/tmp}/envision-ask.XXXXXX")
  local good bad
  good=$(file_step5_ask "$d" envision-good 'The ownership line does not name the ask parser, so this chapter has no owner yet. The seat named here runs it, as a thread here or as a handover.
Counter: the parser lives in the ask app, which the engine seat already holds.')
  bad=$(file_step5_ask "$d" envision-bad 'Pick the seat for this chapter.')  # the critic's case: Lean only, six words
  if [ "$good" = 0 ] && [ "$bad" != 0 ] && [ -f "$d/askroot/test:envision/envision-good.md" ]; then
    pass "S2: a step-5 ask files through the floor (exit 0, nothing delivered), and a six-word fork paragraph is refused (exit $bad)"
  else
    fail "S2: a step-5 ask files through the floor" "good=0, bad≠0, file written" "good=$good bad=$bad; $(tail -3 "$d/envision-good.out" | tr '\n' ' ')"
  fi
  rm -rf "$d"
}
test_S2b_step5_states_the_paragraph_rule() { report "S2b: step 5 requires a two-sentence paragraph under every fork" "$(check_step5_paragraph_rule "$ENV_SKILL")"; }

# ── P — plants: each must turn the aggregate red ──────────────────────────────────────────────

plant_dir=""
setup() {
  plant_dir=$(mktemp -d "${TMPDIR:-/tmp}/envision-plant.XXXXXX")
  cp "$ENV_SKILL" "$plant_dir/E.md"; cp "$ENV_TPL" "$plant_dir/V.md"; cp "$LOOM" "$plant_dir/L.md"
  cp "$LOG_TPL" "$plant_dir/T.md"; cp "$INH" "$plant_dir/I.md"; cp "$DIRECT" "$plant_dir/D.md"
}
teardown() { [ -n "$plant_dir" ] && rm -rf "$plant_dir"; plant_dir=""; }

perl_in() {  # $1 file, $2 literal to find, $3 replacement — first occurrence, one required
  FIND="$2" REPL="$3" perl -0pi -e 'my $n = s/\Q$ENV{FIND}\E/$ENV{REPL}/; die "plant missed\n" unless $n' "$1"
}
plant_violations() { all_violations "$plant_dir/E.md" "$plant_dir/V.md" "$plant_dir/L.md" "$plant_dir/T.md" "$plant_dir/I.md" "$plant_dir/D.md"; }
assert_plant_reddens() {
  if [ -n "$(plant_violations)" ]; then pass "P: plant '$1' reddens the contract"
  else fail "P: plant '$1' reddens the contract" "at least one violation" "none — the check cannot see this defect"; fi
}
setup_missed() { fail "$1: SETUP FAILED — the planted string was not found, so this plant did not run (not a detection)" "the string present" "missing: $2"; }

test_P0_unplanted_copy_is_clean() { report "P0: the unplanted copy passes the aggregate check" "$(plant_violations)"; }

test_P1_loom_trigger_back_to_direct() {
  perl_in "$plant_dir/L.md" 'Skill(envision, "reconcile' 'Skill(direct, "reconcile' 2>/dev/null || { setup_missed "P1" "the envision reconcile call"; return; }
  assert_plant_reddens "P1 the loom's reconcile trigger calls /direct again"
}
test_P2_deviation_row_back_to_direct() {
  perl_in "$plant_dir/L.md" '**`/envision` — reconcile**' '**`/direct` — reconcile**' 2>/dev/null || { setup_missed "P2" "the deviation destination"; return; }
  assert_plant_reddens "P2 the deviation row names /direct again"
}
test_P3_chapter_loses_a_field() {
  perl_in "$plant_dir/V.md" '**Wrong today**' '**Problem**' 2>/dev/null || { setup_missed "P3" "the Wrong today field"; return; }
  assert_plant_reddens "P3 the chapter loses its Wrong today field"
}
test_P4_log_template_loses_docs_owed() {
  perl_in "$plant_dir/T.md" '## 📚 Docs owed' '## Docs' 2>/dev/null || { setup_missed "P4" "the Docs owed heading"; return; }
  assert_plant_reddens "P4 the log template drops 📚 Docs owed"
}
test_P5_skill_files_tickets() {
  perl_in "$plant_dir/E.md" '¶INV_ENVISION_FILES_NO_TICKET' '¶INV_ENVISION_FILES_TICKETS' 2>/dev/null || { setup_missed "P5" "the files-no-ticket invariant"; return; }
  perl -pi -e 's/¶INV_ENVISION_FILES_NO_TICKET/¶INV_ENVISION_FILES_TICKETS/g' "$plant_dir/E.md"
  assert_plant_reddens "P5 /envision loses its files-no-ticket invariant"
}
test_P6_skill_stops_riding() {
  perl_in "$plant_dir/E.md" '§INV_RIDE_NEVER_ACTIVATES' '§INV_OWNS_A_SESSION' 2>/dev/null || { setup_missed "P6" "the ride invariant"; return; }
  perl -pi -e 's/§INV_RIDE_NEVER_ACTIVATES/§INV_OWNS_A_SESSION/g' "$plant_dir/E.md"
  assert_plant_reddens "P6 /envision no longer cites the ride invariant"
}
test_P7_direct_loses_pointer() {
  perl_in "$plant_dir/D.md" 'Inside a loom, use `/envision`' 'Inside a loom, use this skill' 2>/dev/null || { setup_missed "P7" "the pointer line"; return; }
  assert_plant_reddens "P7 /direct loses its pointer to /envision"
}
test_P8_inheritance_back_to_direct() {
  grep -qF -- '`/envision` — reconcile' "$plant_dir/I.md" || { setup_missed "P8" "the inheritance /envision destination"; return; }
  perl -pi -e 's/`\/envision` — reconcile/`\/direct` — reconcile/g' "$plant_dir/I.md"
  assert_plant_reddens "P8 the inheritance destination names /direct again"
}

add_line() { printf '%s\n' "$2" >> "$1"; }  # $1 file, $2 forbidden line to append

test_P9_adds_ticket_filing() {
  add_line "$plant_dir/E.md" '*   For each ripe chapter, call `Skill(ticket, "<chapter>")` so it is filed at once.'
  assert_plant_reddens "P9 a line telling /envision to file tickets"
}
test_P10_adds_save_issue() {
  add_line "$plant_dir/E.md" '*   Then `save_issue` each chapter into the project.'
  assert_plant_reddens "P10 a line calling save_issue"
}
test_P11_adds_session_activate() {
  add_line "$plant_dir/E.md" '*   Run `engine session activate` before drafting, so the record has a home.'
  assert_plant_reddens "P11 a line activating a session"
}
test_P12_adds_session_phase() {
  add_line "$plant_dir/E.md" '*   After writing, move to synthesis with `engine session phase`.'
  assert_plant_reddens "P12 a line moving the host phase"
}
test_P13_adds_fleet_edit() {
  add_line "$plant_dir/E.md" '*   Add the chapter owner to `fleet-yarik.yml` so the seat exists.'
  assert_plant_reddens "P13 a line editing the fleet file"
}
test_P14_adds_pane_parent_write() {
  add_line "$plant_dir/E.md" '*   Set `@pane_parent` on the owner seat to this loom.'
  assert_plant_reddens "P14 a line writing @pane_parent"
}
test_P15_adds_direct_rename() {
  add_line "$plant_dir/E.md" '*   `git mv docs/LIVE_MARKET_DIRECT.md docs/LIVE_MARKET_VISION.md` to bring it under one home.'
  assert_plant_reddens "P15 a line renaming a _DIRECT.md"
}
test_P16_forbids_reconciling_direct_again() {
  perl_in "$plant_dir/E.md" '**Existing `_DIRECT.md` visions are never renamed or moved**' '**An existing `_DIRECT.md` file is never renamed, moved or rewritten by this skill**' 2>/dev/null || { setup_missed "P16" "the M1 sentence"; return; }
  assert_plant_reddens "P16 the old 'never rewritten' sentence restored (M1)"
}
test_P17_drops_direct_reconcile_permission() {
  perl_in "$plant_dir/E.md" '**`reconcile` writes to any vision file, a `_DIRECT.md` included**' '`reconcile` writes to `_VISION.md` files' 2>/dev/null || { setup_missed "P17" "the reconcile permission"; return; }
  assert_plant_reddens "P17 reconcile limited to _VISION.md again"
}

test_P18_step5_drops_the_paragraph_rule() {
  perl_in "$plant_dir/E.md" 'a paragraph of at least two sentences' 'a short note' 2>/dev/null || { setup_missed "P18" "the paragraph rule"; return; }
  assert_plant_reddens "P18 step 5 drops the two-sentence paragraph rule"
}

run_discovered_tests
