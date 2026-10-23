#!/bin/bash
# tests/test-loom-handover-register.sh — a topic handed to another seat is a row, not a message.
#
# Run: bash ~/.claude/engine/scripts/tests/test-loom-handover-register.sh
#
# WHAT THIS COVERS
#   /loom now declares a verb for handing a topic to another seat and a `## 📨 Seat handovers`
#   register the handover is written into. See `skills/loom/SKILL.md` § Constraints
#   (`¶INV_HANDOVER_IS_A_ROW`, `¶INV_HANDOVER_CLOSES_ON_ACK`) and the matching blocks in
#   `assets/TEMPLATE_LOOM_LOG.md` and `assets/TEMPLATE_LOOM_INHERITANCE.md`.
#
# WHY A DOCUMENT PROBE RATHER THAN AN EXECUTION ONE
#   The thing specified is a protocol a conductor follows, and no engine command writes or reads
#   this register yet — `scripts/sweep-check.sh` carries a hardcoded list of five register names
#   and `scripts/loom-page.sh` renders from its own. Both sit outside this lane's partition, so
#   the register is DECLARED here and READ by nothing, and part E says so as a skipped case
#   rather than leaving the gap to be discovered. Parts A–D redden if the specification is
#   deleted or hollowed out, which is the failure this file can actually detect.
#
# THE FOUR SURFACES, and why a probe per surface rather than one
#   A register in /loom is not one block. `dff556d` states the rule in its own message —
#   "Every new register touches the template, the receipt count and the gate proof, and this one
#   touched two of the three." A probe that checked only the template would pass on exactly the
#   defect that commit was fixing. So: the log block (A), the inheritance copy (B), the gate
#   proof and receipt count (C), the verb and its invariants (D).
#
# Part E is the case against the rule for the part that cannot run: that a register declared in
#   the template is actually READ at a gate. Skipped, per `§INV_A_KNOWN_DEFECT_SHIPS_AS_A_SKIPPED_CASE`.
#
# THE CONDITION THAT UN-SKIPS PART E (it arms itself — nobody has to remember)
#   `scripts/sweep-check.sh` comes to carry a "Seat handovers" entry in its REGISTERS list.
#   ARMED WITH THE ENTRY PRESENT BUT NOT MATCHING THE TEMPLATE'S HEADING IS A FAILURE, not a
#   skip: that red is the point — it says the register became readable and the two spellings
#   disagree, which is the divergence that makes a check pass while reading nothing.
#
# No network. No writes anywhere inside the engine checkout.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE="${ENGINE_DIR:-$HOME/.claude/engine}"
SKILL="$ENGINE/skills/loom/SKILL.md"
LOGT="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_LOG.md"
INHT="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md"
SWEEP="$ENGINE/scripts/sweep-check.sh"

for f in "$SKILL" "$LOGT" "$INHT"; do
  [ -f "$f" ] || { echo "missing file under test: $f" >&2; exit 1; }
done
echo "under test: skills/loom/{SKILL.md, assets/TEMPLATE_LOOM_LOG.md, assets/TEMPLATE_LOOM_INHERITANCE.md}"

# The heading is the one string every surface has to agree on, so it is written once here.
HEADING='📨 Seat handovers'

# ── Part A — the live register block in the log template ──────────────────────

test_A1_log_template_declares_the_block() {
  if grep -qF "## $HEADING" "$LOGT"; then
    pass "A1: the log template declares '## $HEADING'"
  else
    fail "A1: log template declares the register" "a '## $HEADING' heading" "absent"
  fi
}

test_A2_block_carries_every_column_the_ticket_names() {
  # IDE-162 acceptance: "a row with the target seat, the topic and its member links, and the
  # sent time". Plus the ack the row closes on, and the direction that makes an inbound ask a
  # row of its own. A block missing a column is a row the receiving seat cannot act on.
  local block missing=""
  block=$(awk -v h="## $HEADING" '$0 ~ h {f=1} f && /^## / && $0 !~ h && NR>1 {if(c++)exit} f' "$LOGT")
  for col in 'direction' 'seat' 'the topic' 'member links' 'sent' 'ack'; do
    printf '%s' "$block" | grep -qF "$col" || missing="$missing $col"
  done
  if [ -z "$missing" ]; then
    pass "A2: the block names all six columns"
  else
    fail "A2: every column present" "direction/seat/topic/member links/sent/ack" "missing:$missing"
  fi
}

test_A3_the_arrow_is_kept_out_of_the_grammar() {
  # The ticket's own implementation trap: `→` is a live DISPOSITION marker that hides a drained
  # inbox root. A handover row that spends it couples two meanings onto one marker. The table
  # rows are read, not the prose — the prose must be free to EXPLAIN the exclusion, and an
  # earlier draft of this probe would have reddened on the warning that states the rule.
  local rows
  rows=$(awk -v h="## $HEADING" '$0 ~ h {f=1} f && /^## / && $0 !~ h && NR>1 {if(c++)exit} f' "$LOGT" | grep '^|')
  if [ -z "$rows" ]; then
    fail "A3: the block has a table" "at least one '|' row" "none"
  elif printf '%s' "$rows" | grep -q '→'; then
    fail "A3: no → in the row grammar" "the arrow absent from every table row" "$(printf '%s' "$rows" | grep -n '→' | head -2)"
  else
    pass "A3: → appears in no table row of the block"
  fi
}

test_A4_the_exclusion_of_the_arrow_is_stated_not_merely_obeyed() {
  # A3 passing is also what a block that never considered the marker looks like. This is the
  # discriminating arm: the block has to SAY the arrow is excluded, so the next editor adding a
  # column does not reach for it. A rule obeyed by accident is not a rule.
  if grep -qF 'may not be put into it' "$LOGT" && grep -qF 'INV_GROOM_MARKS_WHAT_IT_WRITES' "$LOGT"; then
    pass "A4: the block states the → exclusion and cites the invariant that owns the marker"
  else
    fail "A4: the exclusion is stated" "the prohibition plus §INV_GROOM_MARKS_WHAT_IT_WRITES" "not both present"
  fi
}

test_A5_cited_invariants_are_real_not_fabricated() {
  # A name cited with nothing behind it is the worse half of the same defect class the weave
  # logged against itself (`doctor.sh` FAIL SG-02 on broken §INV_ pointers). Every INV_ name
  # these three files cite must be DEFINED somewhere under the engine with a ¶ sigil.
  local broken=""
  local names
  names=$(grep -ohE '[¶§]INV_[A-Z0-9_]+' "$LOGT" "$INHT" | sed 's/^.//' | sort -u)
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    grep -rqF "¶$n" "$ENGINE" --include='*.md' 2>/dev/null || broken="$broken $n"
  done <<< "$names"
  if [ -z "$broken" ]; then
    pass "A5: every invariant the two templates cite has a ¶ definition"
  else
    fail "A5: no fabricated invariant names" "every cited name defined somewhere" "undefined:$broken"
  fi
}

# ── Part B — the inheritance copy ─────────────────────────────────────────────

test_B1_inheritance_template_carries_the_block() {
  # The paired-failure argument, in the inheritance template's own words: "A row kind lives in
  # both places or it is lost at one of the two moments that matter." A register declared only
  # in the log is counted on a hand-over receipt with nowhere to put it.
  if grep -qF "## $HEADING" "$INHT"; then
    pass "B1: the inheritance template carries the matching block"
  else
    fail "B1: the register survives a hand-over" "a '## $HEADING' block in the inheritance template" "absent"
  fi
}

test_B2_inheritance_row_carries_an_owner_column() {
  # Every other inheritance block leads with `owner`, because a successor merging two roots has
  # to know which session wrote a row.
  local block
  block=$(awk -v h="## $HEADING" '$0 ~ h {f=1} f && /^## / && $0 !~ h && NR>1 {if(c++)exit} f' "$INHT")
  if printf '%s' "$block" | grep -q '^| owner'; then
    pass "B2: the inheritance row leads with owner, like its siblings"
  else
    fail "B2: owner column present" "a header row starting '| owner'" "$(printf '%s' "$block" | grep -m1 '^|')"
  fi
}

test_B3_inheritance_row_admits_UNKNOWN() {
  # `¶INV_INCOMPLETE_ROW_FAILS_LOUD`: a successor handed a partial row must be able to see it is
  # partial. A blank cell reads as "nothing owed"; `UNKNOWN —` reads as "stop and report".
  local block
  block=$(awk -v h="## $HEADING" '$0 ~ h {f=1} f && /^## / && $0 !~ h && NR>1 {if(c++)exit} f' "$INHT")
  if printf '%s' "$block" | grep -qF 'UNKNOWN'; then
    pass "B3: the inheritance row admits UNKNOWN rather than a blank cell"
  else
    fail "B3: UNKNOWN is a legitimate cell" "UNKNOWN in the block" "absent"
  fi
}

test_B4_the_two_handover_registers_say_they_are_not_each_other() {
  # `## 🤝 Hand-over written` is a conductor handing state to its OWN SUCCESSOR; this register
  # is one seat handing a topic to a PEER. IDE-162's Non-goals draw that line explicitly. Two
  # blocks a reader can confuse are one block with two meanings, which is the defect restated.
  local ok=0
  grep -qF 'Hand-over written' "$LOGT" && \
    awk -v h="## $HEADING" '$0 ~ h {f=1} f && /^## / && $0 !~ h && NR>1 {if(c++)exit} f' "$LOGT" \
      | grep -qF 'Hand-over written' && ok=1
  if [ "$ok" = 1 ]; then
    pass "B4: the seat-handover block distinguishes itself from the successor receipt"
  else
    fail "B4: the two registers are told apart" "the seat block naming '🤝 Hand-over written'" "no disambiguation"
  fi
}

# ── Part C — the gate proof and the receipt count ─────────────────────────────

test_C1_gate_proof_flag_is_declared() {
  # Without this the register is a block nothing gates on, and a loom reaches Synthesis having
  # handed out topics with no row for any of them.
  if grep -qF '"seatHandovers"' "$SKILL"; then
    pass "C1: seatHandovers is in the Loom phase proof array"
  else
    fail "C1: the register gates Loom→Synthesis" '"seatHandovers" in phases[1].proof' "absent"
  fi
}

test_C2_proof_flag_sits_in_the_loom_phase_not_merely_in_prose() {
  # The discriminating arm for C1: the string could appear only in a sentence about the gate.
  # It has to be inside the JSON array the harness reads.
  local line
  line=$(grep -m1 '"threadsWoven"' "$SKILL")
  if printf '%s' "$line" | grep -qF '"seatHandovers"'; then
    pass "C2: the flag is in the same proof array as threadsWoven"
  else
    fail "C2: flag is in the Loom proof array" "seatHandovers beside threadsWoven" "$line"
  fi
}

test_C3_handover_receipt_counts_the_new_row_kind() {
  # The half `dff556d` found missing: a register declared in the template and absent from the
  # receipt makes a handing-over close either discard the row or fail its own count.
  if grep -qF 'seat handovers N' "$LOGT"; then
    pass "C3: the 🤝 receipt's 'Rows carried' line counts seat handovers"
  else
    fail "C3: receipt counts the row kind" "'seat handovers N' in the Rows carried line" "absent"
  fi
}

test_C4_the_carry_every_open_row_list_names_it() {
  # SKILL.md's own instruction for writing the inheritance enumerates the kinds. A kind absent
  # from that sentence is a kind a conductor following the sentence does not carry.
  if grep -qF 'seat handovers' "$SKILL"; then
    pass "C4: SKILL.md's carry-every-open-row list names seat handovers"
  else
    fail "C4: the carry list names it" "'seat handovers' in SKILL.md" "absent"
  fi
}

test_C5_the_sweep_check_blindness_is_declared_with_the_right_arithmetic() {
  # `sweep-check` reads five of the registers and the file states that count. A new register
  # that does not correct the count leaves a true-sounding sentence that is now false — and the
  # count is the one thing a reader uses to decide whether their register is covered.
  local line
  line=$(grep -m1 'registers:' "$SKILL")
  if printf '%s' "$line" | grep -qF 'five of the eight' && printf '%s' "$line" | grep -qF "$HEADING"; then
    pass "C5: the sweep-check caveat is corrected to eight and names the new register"
  else
    fail "C5: sweep-check caveat is accurate" "'five of the eight' naming $HEADING" "$line"
  fi
}

# ── Part D — the verb and its two invariants ──────────────────────────────────

test_D1_the_verb_is_declared_in_conducting() {
  # IDE-162 acceptance 4: "/loom declares a verb for handing a topic to another seat."
  if grep -qF 'Hand a topic to another seat' "$SKILL"; then
    pass "D1: § Conducting declares the verb"
  else
    fail "D1: the verb is declared" "a 'Hand a topic to another seat' bullet" "absent"
  fi
}

test_D2_the_verb_orders_the_row_before_the_send() {
  # The ordering IS the rule. A row written after the send is the row the failure mode deletes,
  # because the send is where a context most often ends. A verb that merely mentions both is
  # satisfied by the ad-hoc message this register exists to replace.
  if grep -qiF 'ROW IT, THEN SEND IT' "$SKILL"; then
    pass "D2: the verb states row-then-send as its order"
  else
    fail "D2: the ordering is specified" "row-before-send stated in the verb's own heading" "absent"
  fi
}

test_D3_both_invariants_are_defined_here_with_a_pedilcrow() {
  local missing=""
  for n in INV_HANDOVER_IS_A_ROW INV_HANDOVER_CLOSES_ON_ACK; do
    grep -qF "¶$n" "$SKILL" || missing="$missing $n"
  done
  if [ -z "$missing" ]; then
    pass "D3: both invariants carry a ¶ definition in loom's SKILL.md"
  else
    fail "D3: the invariants are defined" "¶ definitions for both" "missing:$missing"
  fi
}

test_D4_the_definitions_live_only_in_the_skill_not_restated_in_the_templates() {
  # `§INV_SIGIL_SEMANTICS`: ¶ asserts "defined here". A second ¶ on the same name asserts that
  # falsely, and a rule restated beside its own definition is what `§INV_ONE_EXCLUSION_STATEMENT`
  # is about. The templates must POINT (§), never redefine.
  local bad=""
  for f in "$LOGT" "$INHT"; do
    grep -qE '¶INV_HANDOVER_(IS_A_ROW|CLOSES_ON_ACK)' "$f" && bad="$bad $(basename "$f")"
  done
  if [ -z "$bad" ]; then
    pass "D4: the templates cite the invariants with § and redefine neither"
  else
    fail "D4: one definition site" "§ pointers in the templates" "¶ found in:$bad"
  fi
}

test_D5_the_sender_may_not_close_its_own_row() {
  # `INV_HANDOVER_CLOSES_ON_ACK`'s whole content. A register whose sender can mark it done on
  # sending records "I sent it", which is what the narrative log already did.
  if grep -qF 'may not' "$SKILL" && grep -qiE 'sender (may not|cannot) close' "$SKILL"; then
    pass "D5: the sender is forbidden from closing its own row"
  else
    fail "D5: close-on-ack is specified" "an explicit prohibition on the sender closing" "absent"
  fi
}

test_D6_a_decline_closes_the_row() {
  # Acceptance 6 turns on this: Scope's "already shipped" answer has to LAND as an ack rather
  # than leave the row open forever. A register where only a take closes is a register that
  # accumulates rows nobody can resolve.
  local ok=0
  grep -qF 'already done' "$SKILL" && grep -qF 'declined' "$SKILL" && ok=1
  if [ "$ok" = 1 ]; then
    pass "D6: declined and already-done are closing acks, not open rows"
  else
    fail "D6: a decline closes the row" "'declined' and 'already done' as closing values" "absent"
  fi
}

test_D7_an_ack_in_chat_alone_is_refused() {
  # "An ack that is only a peer message is the bug restated" — IDE-162's third implementation
  # trap, and the exact shape of today's instance: five acks came back and none reached a row.
  if grep -qiE 'ack that (is only|reached only|arrives as)' "$SKILL"; then
    pass "D7: an ack that stays in the sender's chat is explicitly not an ack"
  else
    fail "D7: the ack must reach the row" "a clause refusing a chat-only ack" "absent"
  fi
}

test_D8_an_inbound_ask_is_a_row_of_its_own() {
  # Measured on 2026-10-23: a peer asked this seat, as a file's owner, to make a change; the
  # full ask→verify→commit→report-the-sha round trip was recorded as a 🔧 Progress narrative and
  # left no row. A one-way register leaves that case exactly as unrowed as the outbound batch.
  if grep -qF 'received' "$SKILL" && grep -qiE 'first-class row|Row what arrives' "$SKILL"; then
    pass "D8: direction: received is a first-class row"
  else
    fail "D8: inbound asks are rowed" "'received' declared as a row of its own" "absent"
  fi
}

test_D9_seat_is_carried_with_its_pane_id() {
  # Hooks and sessions resolve by pane name (`yarik-fleet:domain:<Seat>`). A from-name that no
  # longer resolves to a pane is a handover sent nowhere that reads exactly like one sent, and
  # IDE-162's fourth trap is that nothing turns red when it happens.
  if grep -qF 'yarik-fleet:domain:' "$LOGT" && grep -qF 'yarik-fleet:domain:' "$INHT"; then
    pass "D9: both blocks carry the pane id beside the from-name"
  else
    fail "D9: the pane id travels with the name" "yarik-fleet:domain: in both blocks" "absent from one or both"
  fi
}

test_D10_the_delivery_reading_is_not_a_boolean() {
  # Measured today: "all seven queued. A queued send is not a read... Silence is not agreement."
  # A `sent: yes` column would record the sender's intent rather than the message's fate.
  local block
  block=$(awk -v h="## $HEADING" '$0 ~ h {f=1} f && /^## / && $0 !~ h && NR>1 {if(c++)exit} f' "$LOGT")
  if printf '%s' "$block" | grep -qF 'queued' && printf '%s' "$block" | grep -qF 'never a boolean'; then
    pass "D10: sent carries a delivery reading and says it is not a boolean"
  else
    fail "D10: delivery is a reading" "'queued' plus 'never a boolean' in the block" "absent"
  fi
}

# ── Part E — the case that cannot run yet ─────────────────────────────────────

test_E1_the_register_is_read_at_a_gate() {
  # `scripts/sweep-check.sh` carries a hardcoded REGISTERS list; `scripts/loom-page.sh` renders
  # from its own. Both are outside this lane's partition, so the register is declared and read
  # by nothing. This case arms itself the moment somebody adds the entry.
  local armed=0
  [ -f "$SWEEP" ] && grep -qiF 'Seat handovers' "$SWEEP" && armed=1

  if [ "$armed" = 0 ]; then
    skip "E1: no engine command reads the register yet (sweep-check's list is hardcoded to five)"
    return
  fi

  # Armed. The spelling in the reader must match the heading in the template, or the check runs
  # against a name no log contains and passes while reading nothing — a false absence, whose
  # consequence is believing a gate covers a register it never sees.
  if grep -qF 'Seat handovers' "$SWEEP"; then
    pass "E1: sweep-check reads the register under the template's own name"
  else
    fail "E1: reader and template agree on the name" "'Seat handovers' as spelled in the template" "a different spelling"
  fi
}

test_E2_the_blindness_is_declared_while_it_lasts() {
  # The other side of E1's skip: while no command reads the register, the file has to SAY so.
  # An undeclared blind spot is the one a reader assumes away, and this one is load-bearing —
  # a conductor could otherwise take a clean sweep-check exit as evidence its handovers were
  # rowed, which is precisely the inference it does not support.
  if grep -qF 'hardcoded in `scripts/sweep-check.sh`' "$SKILL"; then
    pass "E2: the register's invisibility to sweep-check is stated, with the reason"
  else
    fail "E2: the blind spot is declared" "a clause naming scripts/sweep-check.sh's hardcoded list" "absent"
  fi
}

run_discovered_tests
