#!/bin/bash
# tests/test-intake-announce-sh.sh — Tests for intake-announce.sh (engine intake-announce)
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-intake-announce-sh.sh
#
# The composer turns wave FACTS into the announce's Block Kit. What is worth
# asserting is not "it produced JSON" but the three things that carry design
# meaning and would fail silently: the block skeleton per state, the two degrade
# rules the composer enforces on the caller's behalf, and that `[n]` comes from
# the facts rather than array position (a threaded reply cites `[n]`, so a
# renumber across states would break replies with nothing to show for it).

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ANNOUNCE="$HOME/.claude/engine/scripts/intake-announce.sh"

FACTS='{
  "project":"Email Classification","pass":3,"operator":"Yarik","drained":11,
  "window":"07-28 → 07-31","gap":"4d ago","closed":"07-31",
  "boardUrl":"https://example.test/board.html",
  "updateUrl":"https://linear.test/project/x/activity",
  "watermark":"2026-07-31T09:38:06Z",
  "decisionsOpen":8,"filed":4,"folded":6,"parked":1,
  "overview":"*What'"'"'s in this pass* — signal drained in one sitting.",
  "outcome":"*What changed* — four filed, six folded, one parked.",
  "counts":[{"label":"Items in","value":11},{"label":"New tickets proposed","value":4}],
  "refs":[{"n":7,"id":"finding:FIN-3297","label":"Fabrication cap \"reads\" as covered","why":"2,583 emails unlinked"},
          {"n":2,"id":"finding:FIN-3461","label":"Baseline before resync","why":"one query"}],
  "moreCount":3,
  "waiting":[{"name":"Justin","slackId":"U0APMSEJXHV","slug":"justin","count":3},
             {"name":"Dana Placeholder","slug":"dana","count":1}],
  "signal":[{"emoji":"🔴","slug":"observed-problems","count":2},
            {"emoji":"🔵","slug":"requirements","count":0}],
  "quiet":"five of eight channels quiet"
}'

compose() { printf '%s' "$FACTS" | "$ANNOUNCE" --state "$1" 2>/dev/null; }

# IA-01 — decision state: the 10-block skeleton, in order.
test_decision_skeleton() {
  local out; out=$(compose decision)
  assert_eq "10" "$(printf '%s' "$out" | jq -r '.blocks | length')" "IA-01: decision state has 10 blocks"
  assert_eq "header,context,callout,section,table,container,container,context,divider,context" \
    "$(printf '%s' "$out" | jq -r '[.blocks[].type] | join(",")')" "IA-01b: decision block type order"
}

# IA-02 — outcomes state adds ONE block (the outcome paragraph), it does not swap.
# The added block IS the design: the closed message keeps what it said and adds
# what happened, so the record grows rather than being replaced.
test_outcomes_adds_one_block() {
  local out; out=$(compose outcomes)
  assert_eq "11" "$(printf '%s' "$out" | jq -r '.blocks | length')" "IA-02: outcomes state has 11 blocks"
  assert_eq "2" "$(printf '%s' "$out" | jq -r '[.blocks[] | select(.type=="section")] | length')" \
    "IA-02b: outcomes carries BOTH prose paragraphs"
}

# IA-03 — the state indicator flips colour, which is how the edit announces itself.
test_callout_state_colour() {
  assert_eq "orange" "$(compose decision | jq -r '.blocks[] | select(.type=="callout") | .background_color')" \
    "IA-03: decision callout is orange"
  assert_eq "green" "$(compose outcomes | jq -r '.blocks[] | select(.type=="callout") | .background_color')" \
    "IA-03b: outcomes callout is green"
}

# IA-04 — DEGRADE RULE: no slackId => plain name and NO mention.
# An unresolved @name notifies nobody while looking like an ask; an invented one
# manufactures an obligation for a person who does not exist. Enforced here, not
# trusted to the caller.
test_no_slackid_renders_no_mention() {
  local waiting
  waiting=$(compose decision | jq -r '.blocks[] | select(.title.text=="Waiting on") | .child_blocks[0].text.text')
  assert_contains "<@U0APMSEJXHV>" "$waiting" "IA-04: a known slackId renders a real mention"
  assert_contains "Dana Placeholder" "$waiting" "IA-04b: an unknown id renders the plain name"
  assert_eq "1" "$(printf '%s' "$waiting" | grep -c '<@' || true)" \
    "IA-04c: exactly ONE mention — the nameless entry produced no <@"
}

# IA-05 — DEGRADE RULE: zero-count channels are dropped by the composer, so a
# caller cannot ship "🔵 0". The quiet line is what carries their absence.
test_zero_counters_dropped() {
  local signal
  signal=$(compose decision | jq -r '.blocks[] | select(.type=="context") | .elements[0].text' | grep "Signal in")
  assert_contains "🔴" "$signal" "IA-05: a non-zero counter is present"
  assert_not_contains "🔵" "$signal" "IA-05b: the zero-count counter was dropped"
  assert_contains "five of eight channels quiet" "$signal" "IA-05c: the quiet summary carries the absence"
}

# IA-06 — `[n]` comes from the FACTS, not from array position. The first ref
# declares n=7; a position-derived number would render [1] and silently break
# every threaded reply citing [7].
test_ref_numbers_come_from_facts() {
  local refs
  refs=$(compose decision | jq -r '.blocks[] | select(.title.text=="Pull these first") | .child_blocks[0].text.text')
  assert_contains "*[7]*" "$refs" "IA-06: ref number is taken from facts.n, not array index"
  assert_not_contains "*[1]*" "$refs" "IA-06b: no position-derived numbering leaked in"
}

# IA-07 — the refs block carries NO mentions. A person owning three decisions
# would otherwise appear three times and the list would stop being scannable as
# a list of decisions; addressing is the "Waiting on" block's job.
test_refs_carry_no_mentions() {
  local refs
  refs=$(compose decision | jq -r '.blocks[] | select(.title.text=="Pull these first") | .child_blocks[0].text.text')
  assert_not_contains "<@" "$refs" "IA-07: refs block contains no @-mentions"
}

# IA-08 — the two board view params the announce depends on.
test_view_params_emitted() {
  local out; out=$(compose decision)
  assert_contains "?user=justin" "$out" "IA-08: per-person board link carries ?user="
  assert_contains "?inbox=observed-problems" "$out" "IA-08b: counter links carry ?inbox="
  assert_contains "#finding:FIN-3297" "$out" "IA-08c: ref links anchor on the item id"
}

# IA-09 — injection safety: a label containing a double quote must survive.
test_quotes_survive() {
  local refs
  refs=$(compose decision | jq -r '.blocks[] | select(.title.text=="Pull these first") | .child_blocks[0].text.text')
  assert_contains 'Fabrication cap "reads" as covered' "$refs" "IA-09: a quote in a label survives intact"
}

# IA-10 — a wave with nothing to say in a slot is a NORMAL wave: missing fields
# drop their block rather than failing.
test_minimal_facts_degrade() {
  local out rc
  out=$(printf '{"project":"Bare"}' | "$ANNOUNCE" --state decision 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "IA-10: minimal facts still compose"
  assert_contains "Bare" "$out" "IA-10b: the project name is carried"
  assert_eq "0" "$(printf '%s' "$out" | jq -r '[.blocks[] | select(.type=="table")] | length')" \
    "IA-10c: no counts => no table block rather than an empty one"
}

# IA-11 — argument validation.
test_state_required() {
  local rc
  printf '%s' "$FACTS" | "$ANNOUNCE" >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "IA-11: missing --state exits 1"
  printf '%s' "$FACTS" | "$ANNOUNCE" --state sideways >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "IA-11b: an unknown --state exits 1"
  printf 'not json' | "$ANNOUNCE" --state decision >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "IA-11c: non-JSON stdin exits 1"
  printf '{"pass":3}' | "$ANNOUNCE" --state decision >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "IA-11d: facts without project exits 1"
}

# IA-12 — the output is what the poster accepts, end to end.
test_pipes_into_poster() {
  local out
  out=$(compose decision | "$HOME/.claude/engine/scripts/slack-post.sh" --dry-run --channel "C0123ABCD" --blocks - 2>/dev/null)
  assert_eq "10" "$(printf '%s' "$out" | jq -r '.blocks | length')" "IA-12: composer output survives the poster"
  assert_contains "Email Classification" "$(printf '%s' "$out" | jq -r '.text')" \
    "IA-12b: notification text derives from the header"
}

run_discovered_tests
