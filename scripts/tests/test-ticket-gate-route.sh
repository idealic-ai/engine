#!/bin/bash
# test-ticket-gate-route.sh — /ticket must not stall a seat that has a parent.
#
# Every gate in /ticket used to be an AskUserQuestion, so a seat whose operator was not at its
# terminal waited on it forever. The operator's ruling (ruling-ticket-tier, 2026-10-29 01:11) sends
# a routine ticket's confirm to the seat's manager as an ask, a scope-level one to the operator as
# a reserved ask, and keeps AskUserQuestion only for a seat with no parent whose operator is at the
# terminal. These arms hold the skill text to that:
#
#   1. skills/ticket/SKILL.md has a "## Gate route" section naming hop.sh target, the exit-code
#      rule it follows, engine ask new --to / engine ask read, and the operator reservation.
#   2. No line outside that section names AskUserQuestion — so no gate can reach it except through
#      the route's operator-present branch. A gate written with a bare AskUserQuestion goes red.
#   3. Every line inside the section that names AskUserQuestion also names `operator`, i.e. it is
#      the no-parent branch, not a fallback any seat could take.
#   4. /snapshot states that --yes never creates a ticket.
#
# DECLARED BOUNDARY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): these arms read skill TEXT. They prove the
# skill no longer instructs a parented seat to call AskUserQuestion at any gate; they cannot prove
# a model obeys the text. Arms 2 and 4 each have a control on a temp copy that must go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TICKET="$ENGINE_DIR/skills/ticket/SKILL.md"
SNAPSHOT="$ENGINE_DIR/skills/snapshot/SKILL.md"

# The body of the "## Gate route" section (heading line through the line before the next "## ").
route_section() {
  awk '/^## Gate route/{on=1; print; next} on && /^## /{on=0} on{print}' "$1"
}

# Lines OUTSIDE the route section, skipping the YAML frontmatter, that name AskUserQuestion.
askuserquestion_outside_route() {
  awk '
    NR==1 && /^---$/ {fm=1; next}
    fm && /^---$/ {fm=0; next}
    fm {next}
    /^## Gate route/ {on=1; next}
    on && /^## / {on=0}
    !on && /AskUserQuestion/ {n++}
    END {print n+0}
  ' "$1"
}

# Lines INSIDE the route section that name AskUserQuestion without naming `operator`.
unconditioned_inside_route() {
  route_section "$1" | grep 'AskUserQuestion' | grep -vc 'operator' || true
}

snapshot_states_no_new_ticket() {
  grep -cE -- '`--yes` never creates a ticket' "$1" || true
}

# ------------------------------------------------------------
test_route_section_names_its_parts() {
  local sec; sec=$(route_section "$TICKET")
  if [ -z "$sec" ]; then
    fail "skills/ticket/SKILL.md has a '## Gate route' section" "a section" "none"
    return
  fi
  pass "skills/ticket/SKILL.md has a '## Gate route' section"
  local needle
  for needle in 'hop.sh target' '§CMD_CONTINUE_ON_STOP' 'engine ask new --to' 'engine ask read' \
                '--reserved-for operator' 'Rendered description (postable)' 'ONE ask'; do
    if printf '%s\n' "$sec" | grep -qF -- "$needle"; then
      pass "the gate route names: $needle"
    else
      fail "the gate route names: $needle" "present" "absent"
    fi
  done
}

test_no_askuserquestion_outside_route() {
  local n; n=$(askuserquestion_outside_route "$TICKET")
  if [ "$n" -eq 0 ]; then
    pass "no /ticket gate names AskUserQuestion outside the gate route"
  else
    awk '/^## Gate route/{on=1;next} on&&/^## /{on=0} !on&&/AskUserQuestion/{print "  offending line " NR ": " substr($0,1,120)}' "$TICKET"
    fail "no /ticket gate names AskUserQuestion outside the gate route" "0" "$n"
  fi
}

# Control for arm 2: a gate that calls AskUserQuestion directly must go red.
test_no_askuserquestion_outside_route_control() {
  local tmp n; tmp=$(mktemp)
  awk '{print} /^## 3\. Calibrate/{print "Then confirm the draft with `AskUserQuestion`."}' "$TICKET" > "$tmp"
  n=$(askuserquestion_outside_route "$tmp")
  rm -f "$tmp"
  if [ "$n" -ge 1 ]; then
    pass "control: arm 2 flags a calibration gate that calls AskUserQuestion directly"
  else
    fail "control: arm 2 flags a calibration gate that calls AskUserQuestion directly" ">=1" "$n"
  fi
}

test_route_askuserquestion_is_operator_only() {
  local n; n=$(unconditioned_inside_route "$TICKET")
  if [ "$n" -eq 0 ]; then
    pass "every AskUserQuestion line in the gate route is the operator-present branch"
  else
    fail "every AskUserQuestion line in the gate route is the operator-present branch" "0" "$n"
  fi
}

test_snapshot_yes_never_files() {
  local n; n=$(snapshot_states_no_new_ticket "$SNAPSHOT")
  if [ "$n" -ge 1 ]; then
    pass "/snapshot states that --yes never creates a ticket"
  else
    fail "/snapshot states that --yes never creates a ticket" ">=1 line" "$n"
  fi
}

# Control for arm 4: the statement removed, the arm must go red.
test_snapshot_yes_never_files_control() {
  local tmp n; tmp=$(mktemp)
  grep -vF -- '`--yes` never creates a ticket' "$SNAPSHOT" > "$tmp"
  n=$(snapshot_states_no_new_ticket "$tmp")
  rm -f "$tmp"
  if [ "$n" -eq 0 ]; then
    pass "control: arm 4 goes red with the statement removed"
  else
    fail "control: arm 4 goes red with the statement removed" "0" "$n"
  fi
}

# ------------------------------------------------------------
run_discovered_tests
