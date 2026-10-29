#!/bin/bash
# tests/test-loom-manager-chain.sh — a loom conductor escalates to its manager, not to the operator.
#
# Run: bash ~/.claude/engine/scripts/tests/test-loom-manager-chain.sh
#      ENGINE_DIR=<a copy> bash …   reads skills/loom/ from that copy instead (how plants are run
#                                   from outside without writing the shared files).
#
# WHAT THIS COVERS (IDE-231, LOOMESC)
#   `skills/loom/SKILL.md` § The manager chain, and every site in that file and in
#   `skills/loom/assets/LOOM_AGENT_DIRECTIONS.md` that used to say an escalation "reaches you"
#   (the hard floor, a MUST-FIX, the ticket disposition, a deadlock, a loopback, a fork). Each
#   such site now says it reaches "your manager (the operator if you have none)" and CITES the
#   section rather than restating it. Also the Escalation route disposition (operator 01:00):
#   its count in the Setup ask, its carve-out in the invariant, and how *straight* and *both*
#   route; and the Setup / loop-gate path of a seat with a parent (critique M2, S1).
#
# WHY A GREP-SHAPED CONTRACT AND NOT AN EXECUTION PROBE
#   The thing specified is text a conductor reads. The mechanism it routes through — the hop
#   (`skills/coordinate/scripts/hop.sh`) and the /ask file (`scripts/ask.sh`) — has its own
#   execution tests (`test-coordinate-hop.sh`, `test-ask-sh.sh`). What can rot here is the TEXT.
#   Every check below is reddened by at least one plant in part P (critique Q1–Q9, builder P1–P5,
#   M1, and the re-review's X1–X6), each of which must turn the aggregate check red. The checks
#   assert what a rule SAYS (which exit maps to what, which answer binds, what follows `rule`),
#   not only that a keyword is present (re-review SHOULD-4).
#
# THE CONTROL
#   C1 counts "conductor" in both files in the same run. A zero there means the instrument read
#   nothing, and every "absent" below would then be a lie.
#
# No network. Plants are written to a temp dir; nothing inside the engine checkout is written.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"
source "$(dirname "$0")/lib-search-first-nudge.sh"

ENGINE="${ENGINE_DIR:-$HOME/.claude/engine}"
SKILL="$ENGINE/skills/loom/SKILL.md"
DIRS="$ENGINE/skills/loom/assets/LOOM_AGENT_DIRECTIONS.md"
TPL="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_LOG.md"

for f in "$SKILL" "$DIRS" "$TPL"; do
  [ -f "$f" ] || { echo "missing file under test: $f" >&2; exit 1; }
done
echo "under test: $ENGINE/skills/loom/{SKILL.md, assets/LOOM_AGENT_DIRECTIONS.md, assets/TEMPLATE_LOOM_LOG.md}"

# The section's name is the one string every citing site must carry, so it is written once.
SECTION='The manager chain'

# Destination phrases the rewrite retired. Each named the operator ("you", "the user") as the
# only rung above a conductor. Case-insensitive, extended regex. "reached you" (a lane being
# told a critique finding reached it) is not a destination and is deliberately not matched.
OLD_PHRASES='always reach(es)? (you|the user)([^a-z]|$)|reach(es)? you([^a-z]|$)|escalates? to (you|the user)([^a-z]|$)|genuinely yours|reach(es)? the user|surfaced to you|decision only the operator can make|contact the user directly'

# A site that routes an escalation through the chain. Every line matching it must cite SECTION.
# (The frontmatter description says "up its manager chain" in one self-contained clause and is
# held to OLD_PHRASES only: a trigger line is not the place for a section cite.)
SITE_PHRASE="reach(es)? (your|the conductor's) manager"

# The Forbidden clause of ¶INV_LOOM_ESCALATES_UP_THE_CHAIN must carry this carve-out, or the
# invariant forbids two of the three positions of the disposition it ships with (critique M1).
CARVE_OUT='unless the Escalation route disposition is *straight to the operator* or *both*'

# ── helpers ───────────────────────────────────────────────────────────────────────────────────

section_body() {  # the text from the section heading to the next ##/### heading
  awk -v h="### $SECTION" 'index($0,h)==1 {f=1; next} f && /^##+ / {exit} f' "$1"
}

word_to_num() {
  case "$1" in
    twelve) echo 12 ;; thirteen) echo 13 ;; fourteen) echo 14 ;; fifteen) echo 15 ;;
    sixteen) echo 16 ;; *) echo "?" ;;
  esac
}

# ── checks, each printing one line per violation so the plants can reuse them ────────────────

check_no_old_phrases() {  # $1 skill $2 dirs
  grep -n -i -E "$OLD_PHRASES" "$1" "$2" 2>/dev/null | cut -c1-160
}

check_sites_cite_section() {  # each "reaches your manager" line outside the section cites it
  local f
  for f in "$1" "$2"; do
    awk -v h="### $SECTION" -v s="$SECTION" -v re="$SITE_PHRASE" -v n="$(basename "$f")" '
      index($0,h)==1 {in_s=1; next}
      in_s && /^##+ / {in_s=0}
      !in_s && tolower($0) ~ re && index($0,s)==0 {print n ":" NR ": uncited site: " substr($0,1,120)}
    ' "$f"
  done
}

check_operator_destinations() {  # Q6: "reaches the operator" outside the section and the bullet
  # The section and the Escalation route bullet are where routing to the operator is defined;
  # anywhere else, "reaches the operator" is a destination that bypasses the chain.
  local f
  for f in "$1" "$2"; do
    awk -v h="### $SECTION" -v n="$(basename "$f")" '
      index($0,h)==1 {in_s=1; next}
      in_s && /^##+ / {in_s=0}
      !in_s && index($0,"*   **Escalation route** — ")!=1 && tolower($0) ~ /reach(es)? the operator/ \
        {print n ":" NR ": operator destination past the chain: " substr($0,1,120)}
    ' "$f"
  done
}

check_section_names() {  # $1 skill — each required element the section lacks
  local body; body=$(section_body "$1")
  [ -n "$body" ] || { echo "section '### $SECTION' absent or empty"; return; }
  has() { printf '%s' "$body" | grep -qF -- "$1" || echo "section lacks: $2"; }
  has 'reserved-for: operator' "the reserved-for: operator mark"
  has '@pane_parent' "the live @pane_parent"
  has 'FLEET_PARENT' "the FLEET_PARENT cross-check"
  has '/ask' "the /ask carrier"
  has "timers aren't" "the manual re-ping ruling"
  has 'orientation' "orientation questions"
  # Q1: the en dash, literally. A regex 'A.D' matched "and" and made this check vacuous.
  has 'A–D' "grant v1's delegated classes A–D"
  has 'Manager mode' "A–D limited to Manager mode (N1)"
  # Q3: the fallback stated positively, and never inverted.
  printf '%s' "$body" | grep -q -E 'with \*\*no parent\*\* escalates to the \*\*operator\*\*' \
    || echo "section lacks: the no-parent -> operator fallback"
  printf '%s' "$body" | grep -q -i -E 'never (escalates|goes) to the operator|drops? the question' \
    && echo "section inverts the fallback (drops the question / never the operator)"
  has 'names the broken edge' "the broken-edge -> operator fallback"
  # S4: the hop read, its exits, the recorded chain, the first token.
  has 'hop.sh target' "the hop.sh target read"
  has 'hop.sh chain' "the recorded chain (hop.sh chain)"
  has '--chain-file' "--chain-file on target"
  has 'Step 5' "the cite of /coordinate Step 5's exit table"
  has 'exit 2' "exit 2 mapped"
  has 'exit 3' "exit 3 mapped"
  has 'exit 5' "exit 5 mapped"
  has 'first token' "to: takes the first token of target's output"
  # Q7 / S3: how straight and both route.
  has '--to operator' "straight's explicit --to operator"
  has '--related' "both's copies linked by --related"
  has 'answeredAt' "both's earliest-answeredAt rule"
  has 'never `--dependsOn`' "both's copies not linked by dependsOn"
  # S2: the mark is the only net.
  has 'only enforcement' "the mark stated as the only enforcement"
  # S1: gate items that need an answer route by /ask with a parent.
  has 'loop gate' "the loop gate's own question routed by /ask"
  has 'merge confirm' "the wave merge confirm routed by /ask"
  has '`/snapshot` and `/pr` confirms' "the /snapshot and /pr confirms routed by /ask"
  has 'Open claims' "a re-put Open-claims row routed by /ask"
  # N6: the receiving half for a conductor that manages seats.
  has 'hop.sh inbox' "the receiving half (hop.sh inbox)"
  has 'hop.sh may-rule' "the receiving half (hop.sh may-rule)"
  # M2: the Setup carve-back of AskUserQuestion is no longer "Setup always has an operator".
  printf '%s' "$body" | grep -qF 'such as the Setup dispositions and the loop gate' \
    && echo "section still says Setup and the loop gate always have an operator (M2)"
}

check_no_blocking_ask_to_parent() {  # Q5: a sentence pairing AskUserQuestion with a parent/manager
  # Sentence-scoped: every sentence that names AskUserQuestion together with a parent or a
  # manager must be a prohibition or a no-parent condition. The exemption names the actual
  # prohibition phrases; a bare "not " exempted almost any sentence (re-review X5).
  awk -v n="$(basename "$1")" '
    { line=$0; gsub(/\. /, ".\n", line); k=split(line, s, "\n")
      for (i=1; i<=k; i++) if (s[i] ~ /AskUserQuestion/ && s[i] ~ /(parent|manager)/ \
          && s[i] !~ /(never (as|by|blocks|aimed|on)|only when|no parent|Forbidden|does not block|instead[^a-z])/) \
        print n ":" NR ": AskUserQuestion aimed at a parent: " substr(s[i],1,120) }
  ' "$1"
}

manager_bullet() {  # $1 skill — the "When you are the manager" bullet and its indented sub-bullets
  awk 'index($0,"*   **When you are the manager.**")==1 {f=1; print; next} f && /^    / {print; next} f {exit}' "$1"
}

check_receiving_half() {  # MUST-1, SHOULD-3, X1, X6: what each outcome of the hop check means
  local b; b=$(manager_bullet "$1")
  [ -n "$b" ] || { echo "no 'When you are the manager' bullet"; return; }
  need() { printf '%s' "$b" | grep -qF -- "$1" || echo "receiving half lacks: $2"; }
  need '`hop.sh inbox`' "the inbox read"
  need '**`inbox` exit 2**' "inbox exit 2 mapped"
  need 'log it and continue the gate' "inbox exit 2 -> log and continue"
  need '**`--reserved-for operator` when the inbox line carries the mark**' "the mark passed to may-rule"
  need '**any other exit, which fails closed and marked**' "any other may-rule exit fails closed and marked"
  need "**Step 3.1, the category check against the config's \`alwaysEscalate\`**" "rule continues to Step 3.1's category check"
  need 'escalates "merge approval into fleet-owned ground" even when it is classed B' "R6's merge backstop escalates even when classed B"
  printf '%s' "$b" | grep -q -i -E 'waived|is ruled once' && echo "receiving half waives R6's backstop"
  need 'Only a question that clears all of them is answered' "answering only after Step 3"
  need 'classes A–D in Manager mode' "rulings bounded to A–D in Manager mode"
  need 'director ruling R7' "the R7 citation for the Manager-mode grant"
  need 'IDE-232 acceptance 1' "the IDE-232 acceptance 1 citation"
  printf '%s' "$b" | grep -q -i -E 'rule on it as orientation|whatever its class' \
    && echo "receiving half rules without the category check or fails open"
}

check_exit_mapping() {  # X3: which hop.sh target exit maps to what
  local body; body=$(section_body "$1")
  printf '%s' "$body" | grep -qF -- '**exit 0**: stdout is the target' || echo "exit 0 not mapped to stdout"
  printf '%s' "$body" | grep -qF -- '**exit 3**: stdout is still the target' || echo "exit 3 not mapped to stdout"
  printf '%s' "$body" | grep -q -E '\*\*exit 2\*\*[^*]*\*\*exit 4\*\*[^*]*\*\*exit 5\*\*[^:]*: there is no target' \
    || echo "exits 2/4/5 not mapped to no-target"
  printf '%s' "$body" | grep -q -E '\*\*exit [03]\*\*: there is no target' && echo "exit 0 or 3 mapped to no-target"
  # HOPSELF (3c4aea1): exit 5 is an unusable live edge; a stale or unset FLEET_PARENT is a stderr note only.
  printf '%s' "$body" | grep -qF -- "**exit 5** (this seat's live edge cannot be read, or it names this seat or \`operator\`)" \
    || echo "exit 5 not mapped to an unusable live edge"
  printf '%s' "$body" | grep -qF -- 'A stale or unset `FLEET_PARENT` is only a stderr note, never exit 5.' \
    || echo "a stale or unset FLEET_PARENT not stated as a note only"
  printf '%s' "$body" | grep -q -E '\*\*exit 5\*\* \([^)]*FLEET_PARENT' && echo "exit 5 still mapped to FLEET_PARENT"
  printf '%s' "$body" | grep -qF -- 'move it aside' || echo "a partial chain file is not moved aside"
  printf '%s' "$body" | grep -qF -- '**only while that file exists**' || echo "--chain-file not limited to an existing file"
}

check_both_binding() {  # X2, SHOULD-2
  local body; body=$(section_body "$1")
  printf '%s' "$body" | grep -qF -- '**the earliest `answeredAt` across the two binds**' || echo "both: earliest answeredAt does not bind"
  printf '%s' "$body" | grep -qF -- 'copy of `<id>`; the first answer on either binds' || echo "both: the operator copy is not told it is a twin"
  printf '%s' "$body" | grep -q -E '(latest|last) `answeredAt`' && echo "both: a later answer binds"
}

check_parented_setup_semantics() {  # X4, MUST-2(c), SHOULD-1
  local b; b=$(grep -F -- '*   **Read the parent first;' "$1")
  [ -n "$b" ] || { echo "no parented-Setup sub-bullet"; return; }
  need() { printf '%s' "$b" | grep -qF -- "$1" || echo "parented Setup lacks: $2"; }
  need 'keeps working on the defaults until that ask is answered' "keeps working on the defaults"
  need '**Autonomy on *Careful***' "an Autonomy default"
  need '**Interrogation on *None* until that ask is answered**' "Interrogation None until answered"
  need 'The parented list is **exit 0 or 3 printing a seat**, **exit 3 printing `operator`** (the parent is dead), **exit 4** and **exit 5**: a manager launched this seat' "exits 3/4/5 take the parented path"
  need 'on 4 or 5 the edge could not be used, so it names the broken edge' "exits 4/5 name the broken edge"
  # SHOULD-5: exit 2 / exit 0+operator are no-parent only with an empty FLEET_PARENT and no stale note.
  need '**only when `FLEET_PARENT` is empty and stderr carries no stale `FLEET_PARENT` note**' "the FLEET_PARENT guard on the no-parent list"
  need 'sends its Setup ask `--to operator`' "the guarded case asks the operator by /ask"
  need '`HOP_CHAIN_FILE` pointing at a missing file' "HOP_CHAIN_FILE's exit 2 named"
  need 'This departs from `/coordinate` § 0 on purpose' "the departure from /coordinate's STOP named"
  # The two lists must be disjoint: no (exit, stdout) pair may sit on both.
  local np pa; np=$(printf '%s' "$b" | sed -nE 's/.*The no-parent list is (.*) and \*\*only when .*/\1/p')
  pa=$(printf '%s' "$b" | sed -nE 's/.*The parented list is (.*): a manager launched this seat.*/\1/p')
  [ -n "$np" ] && [ -n "$pa" ] || { echo "parented Setup: the two exit lists cannot be read"; return; }
  exit_keys() {  # each bold "exit …" item -> "<code>:<seat|operator|any>" lines
    printf '%s' "$1" | grep -o -E '\*\*exit [^*]+\*\*' | sed 's/\*\*//g' | while IFS= read -r it; do
      q=any; case "$it" in *"printing \`operator\`"*) q=operator ;; *"printing a seat"*) q=seat ;; esac
      for c in $(printf '%s' "$it" | sed -E 's/printing.*//' | grep -o -E '[0-9]'); do echo "$c:$q"; done
    done
  }
  local a b2
  for a in $(exit_keys "$np"); do for b2 in $(exit_keys "$pa"); do
    if [ "${a%%:*}" = "${b2%%:*}" ] && { [ "${a#*:}" = "${b2#*:}" ] || [ "${a#*:}" = any ] || [ "${b2#*:}" = any ]; }; then
      echo "parented Setup: exit ${a%%:*} is on both lists ($a / $b2)"
    fi
  done; done
  printf '%s' "$b" | grep -q -i -E 'dispatches no lane|blocks? until' && echo "parented Setup waits on its ask"
}

check_composed_skill_residuals() {  # MUST-2(a)(b)
  local body; body=$(section_body "$1")
  need() { printf '%s' "$body" | grep -qF -- "$1" || echo "section lacks: $2"; }
  need 'invoke `/snapshot --yes`' "/snapshot --yes after a yes on the marked ask"
  need 'pr SKILL.md:108' "the /pr residual"
  need 'interrogate SKILL.md:78' "the /interrogate residual"
  need 'decide SKILL.md:17' "the /decide residual"
  need 'never runs them at an unwatched terminal' "held, not run unwatched"
  need "owed by that skill's owner" "the waiver owed to each owner"
  need '`⚖️ Rules owed` block, where the conductor rows the three under **WAIVERS**' "the residuals' destination (Rules owed: WAIVERS)"
  # SHOULD-6 / Z1: the gate confirms carry the mark — the only thing that stops a manager ruling on them.
  need 'the merge confirm (H) and the `/snapshot` and `/pr` confirms (G) carry `reserved-for: operator`' "the gate confirms carry reserved-for: operator"
}

check_proof_variants() {  # the variant line names every /prove sibling a loom may pick
  local l; l=$(grep -F -- '*   **🎚️ Pick the VARIANT by the shape of the answer' "$1")
  [ -n "$l" ] || { echo "no proof-variant line"; return; }
  for v in '`/prove`' '`/prove-explore`' '`/prove-visionary`' '`/prove-plan` lays out a route already decided' '`/prove-explanation` teaches one mechanism to a newcomer'; do
    printf '%s' "$l" | grep -qF -- "$v" || echo "proof-variant line lacks: $v"
  done
  # ¶INV_LOOM_EVERY_THREAD_PROVES lists the variants too, and must list all five.
  l=$(grep -F -- '*   **`¶INV_LOOM_EVERY_THREAD_PROVES`**:' "$1")
  for v in '`/prove` for' '`/prove-explore` for' '`/prove-visionary` where' '`/prove-plan` for' '`/prove-explanation` for'; do
    printf '%s' "$l" | grep -qF -- "$v" || echo "¶INV_LOOM_EVERY_THREAD_PROVES lacks: $v"
  done
  # /prove names none of its siblings; the old "only /prove-explore names them" reason is false wherever it appears.
  grep -n -F 'only `/prove-explore` names its siblings' "$1" | sed 's/^/false reason for owning the variant: /' | cut -c1-120
}

check_cited_invariants_defined() {  # each ¶INV the section cites has a Constraints entry
  # A definition is a Constraints bullet that opens with the bolded tag and states what it
  # forbids. A tag cited as another skill's (written "`/coordinate` `¶INV_…`") is skipped.
  local tag
  section_body "$1" | grep -o -E '(`/[a-z-]+` `)?¶INV_[A-Z_]*' | grep -v '^`/' | sort -u | while IFS= read -r tag; do
    grep -F -- "*   **\`$tag\`**:" "$1" | grep -qF 'Forbidden' || echo "cited but not defined: $tag"
  done
}

check_invariant_carve_out() {  # M1
  grep -F -- '*   **`¶INV_LOOM_ESCALATES_UP_THE_CHAIN`**:' "$1" | grep -qF -- "$CARVE_OUT" \
    || echo "¶INV_LOOM_ESCALATES_UP_THE_CHAIN forbids the straight/both positions (no carve-out)"
}

check_disposition_count() {  # Q4b: the asked list, the bullets, the spelled count and the splits
  local s="$1" bullets line list spelled spelled_np split split_np sum sum_np
  bullets=$(awk '/^### The Setup dispositions/{f=1;next} f&&/^##+ /{exit} f&&/^\*   \*\*[^*]+\*\* — /{n++} END{print n+0}' "$s")
  line=$(grep -F -- '*   **Ask the dispositions**' "$s")
  [ -n "$line" ] || { echo "no 'Ask the dispositions' Setup step"; return; }
  list=$(printf '%s' "$line" | sed -E 's/.*one question per disposition — ([^;]*);.*/\1/' | awk -F' · ' '{print NF}')
  spelled=$(word_to_num "$(printf '%s' "$line" | sed -E 's/.*; \*\*([a-z]+) of them.*/\1/')")
  spelled_np=$(word_to_num "$(printf '%s' "$line" | sed -nE 's/.*\(([a-z]+) when the seat has no parent.*/\1/p')")
  split=$(printf '%s' "$line" | grep -o -E '[0-9]/[0-9]/[0-9]/[0-9]' | sed -n 1p)
  split_np=$(printf '%s' "$line" | grep -o -E '[0-9]/[0-9]/[0-9]/[0-9]' | sed -n 2p)
  sum=$(printf '%s' "$split" | tr '/' '\n' | awk '{t+=$1} END{print t+0}')
  sum_np=$(printf '%s' "$split_np" | tr '/' '\n' | awk '{t+=$1} END{print t+0}')
  [ "$list" = "$bullets" ] || echo "asked list names $list dispositions, the section has $bullets"
  [ "$spelled" = "$list" ] || echo "spelled count $spelled != listed $list"
  [ "$sum" = "$list" ] || echo "call split '$split' sums to $sum, not $list"
  [ "$spelled_np" = "$((list - 1))" ] || echo "no-parent count '$spelled_np' != $((list - 1))"
  [ "$sum_np" = "$((list - 1))" ] || echo "no-parent split '$split_np' sums to $sum_np, not $((list - 1))"
}

check_setup_with_a_parent() {  # M2
  local s="$1" t="$2"
  grep -qF 'chosen by: default' "$s" || echo "Setup does not record 'chosen by: default' for a seat with a parent"
  grep -qF 'ONE non-blocking /ask' "$s" || echo "Setup does not put the dispositions up as one non-blocking /ask"
  grep -F -- '*   **Escalation route**: ' "$t" | grep -qF 'default' || echo "template's chosen-by cell has no 'default' value"
  grep -F -- '*   **Dispositions**: ' "$t" | grep -qF 'Autonomy=Careful, Interrogation=None until answered' \
    || echo "template's Dispositions line has no chosen-by slot for the parented defaults"
}

check_mark_claim() {  # S2
  grep -n -F 'still caught there' "$1" | sed 's/^/false safety net: /'
}

check_tickets_in_ask_body() {  # N3
  grep -F -- '*   **`¶INV_TICKETS_PRESENTED_BEFORE_ASKED`**:' "$1" | grep -qF 'ask body' \
    || echo "¶INV_TICKETS_PRESENTED_BEFORE_ASKED does not put the list in the ask body"
}

check_lanes_never_contact_up() {  # Q9: a lane is never told to contact the operator or a manager
  grep -n -i -E 'contact(s|ing)? (the operator|the user|a manager|your manager|the manager)' "$1" \
    | grep -v -i 'never' | sed 's/^/lane told to contact past its conductor: /' | cut -c1-160
  grep -qF 'Escalate to the **conductor**' "$1" || echo "lanes no longer 'Escalate to the **conductor**'"
}

all_violations() {  # $1 skill $2 dirs $3 template
  check_no_old_phrases "$1" "$2"
  check_sites_cite_section "$1" "$2"
  check_operator_destinations "$1" "$2"
  check_section_names "$1"
  check_no_blocking_ask_to_parent "$1"
  check_cited_invariants_defined "$1"
  check_invariant_carve_out "$1"
  check_disposition_count "$1"
  check_setup_with_a_parent "$1" "$3"
  check_mark_claim "$1"
  check_tickets_in_ask_body "$1"
  check_lanes_never_contact_up "$2"
  check_receiving_half "$1"
  check_exit_mapping "$1"
  check_both_binding "$1"
  check_parented_setup_semantics "$1"
  check_composed_skill_residuals "$1"
  check_proof_variants "$1"
}

report() {  # $1 label, $2 violations
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "no violations" "$2"; fi
}

# ── C — the control ───────────────────────────────────────────────────────────────────────────

test_C1_control_the_instrument_reads_both_files() {
  local a b
  a=$(grep -c -i 'conductor' "$SKILL"); b=$(grep -c -i 'conductor' "$DIRS")
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then
    pass "C1: control — 'conductor' found in both files ($a, $b lines)"
  else
    fail "C1: control" "'conductor' > 0 in both" "SKILL=$a DIRS=$b"
  fi
}

# ── S — the section ───────────────────────────────────────────────────────────────────────────

test_S1_the_section_exists_exactly_once() {
  # Anchored: a '#### The manager chain' line must not count (N5).
  assert_eq "1" "$(grep -c -E "^### $SECTION\$" "$SKILL" | tr -d ' ')" "S1: '### $SECTION' appears once in SKILL.md"
}

test_S2_the_section_names_everything_it_must() {
  report "S2: the section names the mark, the fallback, the hop and its exits, the carrier, straight/both, the gate items, the receiving half and what a manager may rule" \
    "$(check_section_names "$SKILL")"
}

test_S3_the_section_is_defined_only_in_SKILL() {
  assert_eq "0" "$(grep -c -E "^#+ $SECTION" "$DIRS" | tr -d ' ')" "S3: the directions do not restate the section"
}

test_S4_every_invariant_the_section_cites_is_defined() {
  local n bad
  n=$(section_body "$SKILL" | grep -o -E '(`/[a-z-]+` `)?¶INV_[A-Z_]*' | grep -v '^`/' | sort -u | wc -l | tr -d ' ')
  bad=$(check_cited_invariants_defined "$SKILL")
  if [ "$n" -ge 2 ] && [ -z "$bad" ]; then
    pass "S4: all $n invariants the section cites are defined in Constraints with what they forbid"
  else
    fail "S4: cited invariants defined" ">= 2 cited, each defined with Forbidden" "cited=$n; $bad"
  fi
}

test_S5_the_route_is_a_declared_disposition() {
  local missing=""
  section_body "$SKILL" | grep -qF '**Escalation route**' || missing="$missing [section does not point at the disposition]"
  grep -qF '*   **Escalation route** — ' "$SKILL" || missing="$missing [no disposition bullet]"
  grep -qF '**And a seventh, `Escalation route`**' "$SKILL" || missing="$missing [ledger-field reason]"
  grep -qF '*   **Escalation route**: ' "$TPL" || missing="$missing [TEMPLATE_LOOM_LOG header line]"
  report "S5: Escalation route is a disposition, given a ledger field, templated, and the section points at it" "$missing"
}

test_S6_the_disposition_count_matches_the_list() {
  report "S6: the asked list, the bullets, the spelled count and the 4/4/4/r splits agree (with and without a parent)" \
    "$(check_disposition_count "$SKILL")"
}

test_S7_the_invariant_carves_out_straight_and_both() {
  report "S7: ¶INV_LOOM_ESCALATES_UP_THE_CHAIN carves out the straight and both positions" \
    "$(check_invariant_carve_out "$SKILL")"
}

test_S8_a_seat_with_a_parent_does_not_block_Setup() {
  report "S8: a seat with a parent takes the default, records chosen by: default, and asks one non-blocking /ask" \
    "$(check_setup_with_a_parent "$SKILL" "$TPL")"
}

test_S9_no_false_safety_net() {
  report "S9: the mark is not claimed to be backed by may-rule's floor list" "$(check_mark_claim "$SKILL")"
}

test_S10_tickets_go_in_the_ask_body() {
  report "S10: the ticket list goes in the ask body when the carrier is an /ask" "$(check_tickets_in_ask_body "$SKILL")"
}

test_S11_the_receiving_half_runs_coordinate_step_3_before_ruling() {
  report "S11: the receiving half maps inbox exit 2, passes the mark, fails closed, and runs Step 3.1's category check before it rules" \
    "$(check_receiving_half "$SKILL")"
}

test_S12_each_hop_exit_maps_to_its_action() {
  report "S12: exits 0/3 use stdout, 2/4/5 have no target; a partial chain is moved aside; --chain-file only when it exists" \
    "$(check_exit_mapping "$SKILL")"
}

test_S13_both_binds_the_earliest_answer_and_says_so() {
  report "S13: under both, the earliest answeredAt binds and the operator copy says so" "$(check_both_binding "$SKILL")"
}

test_S14_parented_Setup_keeps_working_with_named_defaults() {
  report "S14: parented Setup keeps working, defaults Autonomy and Interrogation, and treats exits 3/4/5 as a parent" \
    "$(check_parented_setup_semantics "$SKILL")"
}

test_S15_composed_skill_residuals_are_named() {
  report "S15: /snapshot --yes after a yes; /pr, /interrogate, /decide held as residuals whose waivers their owners owe" \
    "$(check_composed_skill_residuals "$SKILL")"
}

test_S16_the_proof_variant_line_names_plan_and_explanation() {
  report "S16: the variant line and ¶INV_LOOM_EVERY_THREAD_PROVES name all five variants, and no line claims only /prove-explore names its siblings" "$(check_proof_variants "$SKILL")"
}

# ── R — the rewrite ───────────────────────────────────────────────────────────────────────────

test_R1_no_old_destination_phrase_survives() {
  report "R1: no 'reaches you' / 'reach the user' destination survives in either file" \
    "$(check_no_old_phrases "$SKILL" "$DIRS")"
}

test_R2_every_site_cites_the_section() {
  report "R2: every 'reaches your manager' site cites § $SECTION" "$(check_sites_cite_section "$SKILL" "$DIRS")"
}

test_R3_the_sites_are_actually_there() {
  # R2 passes vacuously on a file with no sites; a low count means sites were deleted.
  local s d
  s=$(grep -c -i -E "$SITE_PHRASE" "$SKILL"); d=$(grep -c -i -E "$SITE_PHRASE" "$DIRS")
  if [ "$s" -ge 12 ] && [ "$d" -ge 2 ]; then
    pass "R3: routed sites present (SKILL=$s lines, DIRS=$d lines)"
  else
    fail "R3: routed sites present" "SKILL >= 12, DIRS >= 2" "SKILL=$s DIRS=$d"
  fi
}

test_R4_the_floor_content_is_unchanged() {
  local floor missing=""
  floor=$(grep -F '¶INV_LOOM_HARD_ESCALATION_FLOOR`)**' "$SKILL")
  for item in 'ticket-disposition question' 'cyclic deadlock' 'build failing after retries' 'scrutinize MUST-FIX' 'thread loopback'; do
    printf '%s' "$floor" | grep -qF "$item" || missing="$missing [$item]"
  done
  report "R4: the hard floor still names all five items" "$missing"
}

test_R5_lanes_escalate_only_to_their_conductor() {
  report "R5: lanes escalate to the conductor and are never told to contact the operator or a manager" \
    "$(check_lanes_never_contact_up "$DIRS")"
}

test_R6_no_operator_destination_past_the_chain() {
  report "R6: no 'reaches the operator' outside the section and the disposition bullet" \
    "$(check_operator_destinations "$SKILL" "$DIRS")"
}

test_R7_no_AskUserQuestion_aimed_at_a_parent() {
  report "R7: no sentence aims AskUserQuestion at a parent or manager" "$(check_no_blocking_ask_to_parent "$SKILL")"
}

# ── N — search before you escalate (IDE-333 acceptance 3) ─────────────────────────────────────

NUDGE_HEADING='What you escalate (to the conductor)'

test_N1_lanes_search_before_escalating() {
  report "N1: the escalation section tells a lane to run session-search and doc-search, with working commands, before it escalates" \
    "$(search_nudge_violations "$DIRS" "$NUDGE_HEADING" "$ENGINE")"
}

# ── P — plants: each must turn the aggregate check red ────────────────────────────────────────

plant_dir=""
setup() {
  plant_dir=$(mktemp -d "${TMPDIR:-/tmp}/loom-chain-plant.XXXXXX")
  cp "$SKILL" "$plant_dir/S.md"; cp "$DIRS" "$plant_dir/D.md"; cp "$TPL" "$plant_dir/T.md"
}
teardown() { [ -n "$plant_dir" ] && rm -rf "$plant_dir"; plant_dir=""; }

in_section() {  # $1 awk statement applied to section lines only, of the plant copy S.md
  awk -v h="### $SECTION" "index(\$0,h)==1 {f=1; print; next} f && /^##+ / {f=0} f {$1} {print}" \
    "$plant_dir/S.md" > "$plant_dir/S2.md" && mv "$plant_dir/S2.md" "$plant_dir/S.md"
}

assert_plant_reddens() {  # $1 label
  local v; v=$(all_violations "$plant_dir/S.md" "$plant_dir/D.md" "$plant_dir/T.md")
  if [ -n "$v" ]; then
    pass "P: plant '$1' reddens the contract"
  else
    fail "P: plant '$1' reddens the contract" "at least one violation" "none — the check cannot see this defect"
  fi
}

test_P0_unplanted_copy_is_clean() {
  # The plants below mean something only if the same check on the same copy is green first.
  report "P0: the unplanted copy passes the aggregate check" \
    "$(all_violations "$plant_dir/S.md" "$plant_dir/D.md" "$plant_dir/T.md")"
}

test_P1_old_phrase_reintroduced() {
  printf '\nA cyclic deadlock always reaches you, even under Automagic.\n' >> "$plant_dir/S.md"
  assert_plant_reddens "P1 old 'always reaches you' line"
}

test_P2_site_restates_without_citing() {
  printf '\nA MUST-FIX reaches your manager, or the operator.\n' >> "$plant_dir/D.md"
  assert_plant_reddens "P2 a site that does not cite the section"
}

test_P3_Q2_section_loses_reserved_mark() {
  # Section-scoped (the sites outside it keep the mark): proves the check reads the section.
  in_section 'gsub(/reserved-for: operator/, "reserved")'
  [ "$(grep -c -F 'reserved-for: operator' "$plant_dir/S.md")" -gt 0 ] \
    || { fail "P3/Q2: plant setup" "the mark survives outside the section" "it does not"; return; }
  assert_plant_reddens "P3/Q2 section without reserved-for: operator"
}

test_P4_section_loses_no_parent_fallback() {
  in_section 'gsub(/[Nn]o parent/, "a parent")'
  assert_plant_reddens "P4 section without the no-parent fallback"
}

test_P5_cited_invariant_loses_its_definition() {
  grep -v -F '*   **`¶INV_ESCALATION_DOES_NOT_BLOCK`**:' "$plant_dir/S.md" > "$plant_dir/S2.md" && mv "$plant_dir/S2.md" "$plant_dir/S.md"
  assert_plant_reddens "P5 a cited invariant with no definition"
}

test_Q1_section_loses_A_to_D() {
  in_section 'gsub(/A–D/, "the delegated ones")'
  assert_plant_reddens "Q1 section without A–D"
}

test_Q3_fallback_inverted() {
  in_section 'gsub(/escalates to the \*\*operator\*\*/, "never escalates to the operator and drops the question")'
  assert_plant_reddens "Q3 the no-parent fallback inverted"
}

test_Q4b_fifteenth_disposition_listed_count_kept() {
  sed -i '' 's/ · Escalation route; \*\*fourteen of them/ · Escalation route · Budget; **fourteen of them/' "$plant_dir/S.md"
  grep -qF '· Budget; **fourteen' "$plant_dir/S.md" || { fail "Q4b: plant setup" "list extended" "sed missed"; return; }
  assert_plant_reddens "Q4b a 15th item in the asked list, 'fourteen' kept"
}

test_Q5_blocking_ask_to_parent() {
  printf '\nA cyclic deadlock goes to the parent by a blocking `AskUserQuestion`.\n' >> "$plant_dir/S.md"
  assert_plant_reddens "Q5 AskUserQuestion aimed at the parent"
}

test_Q6_reaches_the_operator_directly() {
  printf '\nA scrutinize MUST-FIX reaches the operator directly, even when the seat has a parent.\n' >> "$plant_dir/S.md"
  assert_plant_reddens "Q6 an operator destination past the chain"
}

test_Q7_straight_and_both_semantics_deleted() {
  in_section 'if (index($0, "**Which route this loom takes**")) $0 = "*   **Which route this loom takes** is the **Escalation route** Setup disposition."'
  assert_plant_reddens "Q7 the straight/both routing deleted"
}

test_Q8_invariant_loses_forbidden() {
  sed -i '' '/^\*   \*\*`¶INV_LOOM_ESCALATES_UP_THE_CHAIN`\*\*:/s/\*\*Forbidden\*\*/**Disallowed**/' "$plant_dir/S.md"
  assert_plant_reddens "Q8 a cited invariant without Forbidden"
}

test_Q9_lane_told_to_contact_the_operator() {
  printf '\nIf the conductor is slow, contact the operator yourself.\n' >> "$plant_dir/D.md"
  assert_plant_reddens "Q9 a lane told to contact the operator"
}

test_M1_carve_out_removed() {
  sed -i '' 's/, unless the Escalation route disposition is \*straight to the operator\* or \*both\*//' "$plant_dir/S.md"
  assert_plant_reddens "M1 the invariant's carve-out removed"
}

perl_in() {  # $1 file, $2 literal to find, $3 replacement — literal, one occurrence required
  local f="$1"; FIND="$2" REPL="$3" perl -0pi -e 'my $n = s/\Q$ENV{FIND}\E/$ENV{REPL}/; die "plant missed\n" unless $n' "$f"
}

test_X1_receiving_half_fails_open() {
  perl_in "$plant_dir/S.md" ' and **`--reserved-for operator` when the inbox line carries the mark**' '' || { fail "X1: setup" "applied" "missed"; return; }
  perl_in "$plant_dir/S.md" '**any other exit, which fails closed and marked**' 'any other exit, rule on it as orientation' || { fail "X1: setup" "applied" "missed"; return; }
  assert_plant_reddens "X1 receiving half fails open (mark dropped, other exits ruled as orientation)"
}

test_X2_latest_answer_binds() {
  perl_in "$plant_dir/S.md" 'the earliest `answeredAt`' 'the latest `answeredAt`' || { fail "X2: setup" "applied" "missed"; return; }
  assert_plant_reddens "X2 under both, the latest answeredAt binds"
}

test_X3_exit_3_remapped_to_no_target() {
  perl_in "$plant_dir/S.md" '**exit 3**: stdout is still the target' '**exit 3**: there is no target; discard stdout, and the target' || { fail "X3: setup" "applied" "missed"; return; }
  assert_plant_reddens "X3 exit 3 re-mapped to no target"
}

test_X4_parented_Setup_waits() {
  perl_in "$plant_dir/S.md" 'and keeps working on the defaults until that ask is answered' 'and dispatches no lane until that ask is answered' || { fail "X4: setup" "applied" "missed"; return; }
  assert_plant_reddens "X4 parented Setup dispatches no lane until its ask is answered"
}

test_X5_pr_confirm_to_manager_by_AskUserQuestion() {
  printf '\nWith a parent, the `/pr` confirm goes to the manager by `AskUserQuestion`, not as an ask file.\n' >> "$plant_dir/S.md"
  assert_plant_reddens "X5 the /pr confirm aimed at the manager by AskUserQuestion"
}

test_X6_rule_answers_whatever_its_class() {
  awk 'index($0,"    *   **`rule` is not yet a ruling.**")==1 {print "    *   On `rule`, answer it, whatever its class."; next} {print}' \
    "$plant_dir/S.md" > "$plant_dir/S2.md" && mv "$plant_dir/S2.md" "$plant_dir/S.md"
  grep -qF 'whatever its class' "$plant_dir/S.md" || { fail "X6: setup" "applied" "missed"; return; }
  assert_plant_reddens "X6 on rule, answer whatever its class (no category check)"
}

test_Y1_variant_line_loses_prove_plan() {
  perl_in "$plant_dir/S.md" ' · `/prove-plan` lays out a route already decided as a page of ordered steps, each with its check and its owner' '' || { fail "Y1: setup" "applied" "missed"; return; }
  assert_plant_reddens "Y1 the variant line loses /prove-plan"
}

test_Y2_variant_line_loses_prove_explanation() {
  perl_in "$plant_dir/S.md" ' · `/prove-explanation` teaches one mechanism to a newcomer, idea first, then a worked example with real values' '' || { fail "Y2: setup" "applied" "missed"; return; }
  assert_plant_reddens "Y2 the variant line loses /prove-explanation"
}

test_Y3_exit_5_mapped_to_FLEET_PARENT_again() {
  perl_in "$plant_dir/S.md" "**exit 5** (this seat's live edge cannot be read, or it names this seat or \`operator\`)" '**exit 5** (`FLEET_PARENT` disagrees with the live parent, or is unset)' || { fail "Y3: setup" "applied" "missed"; return; }
  assert_plant_reddens "Y3 exit 5 mapped back to FLEET_PARENT disagreeing or unset"
}

test_Y4_parented_Setup_treats_exit_5_as_no_parent() {
  perl_in "$plant_dir/S.md" ', **exit 4** and **exit 5**: a manager launched this seat' ' and **exit 4**: a manager launched this seat (exit 5 means FLEET_PARENT is unset, so take the no-parent branch)' || { fail "Y4: setup" "applied" "missed"; return; }
  assert_plant_reddens "Y4 parented Setup sends exit 5 down the no-parent branch"
}

test_Y5_invariant_lists_three_variants_again() {
  perl_in "$plant_dir/S.md" ', `/prove-plan` for a decided route laid out as ordered steps with their checks and owners, `/prove-explanation` for one mechanism taught to a newcomer;' ';' || { fail "Y5: setup" "applied" "missed"; return; }
  assert_plant_reddens "Y5 ¶INV_LOOM_EVERY_THREAD_PROVES back to three variants"
}

test_Y6_false_sibling_reason_reintroduced() {
  perl_in "$plant_dir/S.md" 'the conductor still owns the **variant** choice, because `/prove` names none of its siblings and silently absorbs a misroute,' 'the conductor still owns the **variant** choice, because only `/prove-explore` names its siblings,' || { fail "Y6: setup" "applied" "missed"; return; }
  assert_plant_reddens "Y6 'only /prove-explore names its siblings' reintroduced"
}

test_Z1_gate_confirms_go_unmarked() {
  perl_in "$plant_dir/S.md" 'confirms (G) carry `reserved-for: operator`, and every hard-floor item' 'confirms (G) go unmarked, so the manager may rule on them, and every hard-floor item' || { fail "Z1: setup" "applied" "missed"; return; }
  assert_plant_reddens "Z1 the merge, /snapshot and /pr confirms go unmarked"
}

test_Z2_R6_backstop_waived_when_classed_B() {
  perl_in "$plant_dir/S.md" 'escalates "merge approval into fleet-owned ground" even when it is classed B' 'is waived once "merge approval into fleet-owned ground" is classed B' || { fail "Z2: setup" "applied" "missed"; return; }
  assert_plant_reddens "Z2 R6's backstop inverted (waived when classed B)"
}

test_Z3_exit_4_on_both_lists() {
  perl_in "$plant_dir/S.md" 'and **exit 2** (no identity, a loom outside the fleet), and **only when' ', **exit 2** (no identity, a loom outside the fleet) and **exit 4** (the tree is unreadable), and **only when' || { fail "Z3: setup" "applied" "missed"; return; }
  assert_plant_reddens "Z3 exit 4 on both the no-parent and the parented list"
}

test_Z4_FLEET_PARENT_guard_removed() {
  perl_in "$plant_dir/S.md" ', and **only when `FLEET_PARENT` is empty and stderr carries no stale `FLEET_PARENT` note**' ', and **always**' || { fail "Z4: setup" "applied" "missed"; return; }
  assert_plant_reddens "Z4 the FLEET_PARENT guard on the no-parent list removed"
}

test_N2_plant_a_flag_the_CLI_does_not_have() {
  perl_in "$plant_dir/D.md" 'engine session-search query "<subject>" --limit 5' 'engine session-search query "<subject>" --top 5' || { fail "N2: setup" "applied" "missed"; return; }
  local v; v=$(search_nudge_violations "$plant_dir/D.md" "$NUDGE_HEADING" "$ENGINE")
  if printf '%s' "$v" | grep -qF 'flag --top is not in its CLI usage'; then
    pass "N2: plant '--top', a flag session-search does not have, reddens N1"
  else
    fail "N2: plant reddens N1" "flag --top is not in its CLI usage" "${v:-no violations}"
  fi
}

run_discovered_tests
