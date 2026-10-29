#!/bin/bash
# test-snapshot-ticket-guard.sh — /snapshot §1's wrong-ticket cross-check under an explicit key.
#
# Every loom runs `/snapshot --yes` when a thread lands, from a LANE branch (runner/wave1b,
# writer/ide150-archetype) that never equals Linear's canonical gitBranchName. The old §1 made any
# branch mismatch an abort under --yes, so every lane snapshot aborted. The rule now:
#   * an EXPLICIT key (the `-- <KEY>` argument, the session's .state.json tickets[], or a key the
#     snapshotted commits carry) + a branch that is not the canonical one → WARN and proceed,
#     for status-only runs and commits alike, with the branch recorded in a trailer and the comment;
#   * the branch naming a DIFFERENT key than the explicit one, or the explicit sources disagreeing
#     → still ABORT under --yes;
#   * no explicit key → unchanged (a mismatch aborts under --yes).
#
# TEXT CONTRACT ONLY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): these arms read skills/snapshot/SKILL.md.
# They do not run a live /snapshot; that an agent obeys the prose is not checked here.
# SNAPSHOT_SKILL overrides the file read, so a planted copy can be shown to go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="${SNAPSHOT_SKILL:-$ENGINE_DIR/skills/snapshot/SKILL.md}"

has_fixed() {
  if printf '%s\n' "$2" | grep -qF -- "$1"; then pass "$3"; else fail "$3" "contains '$1'" "absent"; fi
}
lacks_fixed() {
  if printf '%s\n' "$2" | grep -qF -- "$1"; then fail "$3" "lacks '$1'" "present"; else pass "$3"; fi
}

# The §1 cross-check: its bullet plus its nested sub-bullets, up to the next top-level bullet.
cross_check() {
  awk '/^- \*\*Wrong-ticket cross-check:\*\*/ {on=1; print; next} on && /^- / {exit} on && /^#/ {exit} on {print}' "$SKILL"
}
# The abort-list paragraph in § Unattended runs.
abort_list() { grep -m1 -F 'situations abort the run' "$SKILL"; }
# §3 step 2, the batch confirm line.
confirm_line() { grep -m1 -F '2. **Batch confirm**' "$SKILL"; }

test_cross_check_exists() {
  assert_not_empty "$(cross_check)" "§1 has a Wrong-ticket cross-check bullet"
}

# The three explicit-key sources are named in §1.
test_explicit_key_sources() {
  local cc; cc=$(cross_check)
  has_fixed "**explicit ticket key**" "$cc" "§1 defines an explicit ticket key"
  has_fixed '`-- <KEY>`' "$cc" "§1: the argument is an explicit source"
  has_fixed '`tickets[]`' "$cc" "§1: the session's .state.json tickets[] is an explicit source"
  has_fixed "subjects or trailers" "$cc" "§1: a key carried by the snapshotted commits is an explicit source"
}

# RED on the old text: a lane-branch mismatch under an explicit key warns and proceeds.
test_lane_branch_warns() {
  local cc; cc=$(cross_check)
  has_fixed "**Explicit key, branch is not the ticket's canonical one → WARN and proceed**" "$cc" \
    "§1: explicit key + non-canonical branch warns and proceeds"
  has_fixed "a status-only run and a commit alike" "$cc" "§1: the warn case covers commits, not only status-only runs"
  has_fixed '`Snapshot-Branch: <branch>`' "$cc" "§1: the branch is recorded in a commit trailer"
  has_fixed "the comment names the branch" "$cc" "§1: the branch is recorded in the ticket comment"
  lacks_fixed "**Under \`--yes\` a mismatch ABORTS**" "$cc" "§1 no longer makes every branch mismatch an abort"
}

# The different-key case keeps aborting (would go red if it were relaxed into a warning).
test_different_key_aborts() {
  local cc; cc=$(cross_check)
  has_fixed "**Explicit key, branch names a different key → ABORT under \`--yes\`**" "$cc" \
    "§1: a branch naming a different key than the explicit one aborts"
  has_fixed '`ide-312-x` with key `IDE-313` aborts' "$cc" "§1 gives the different-key example"
  has_fixed "**Explicit sources disagree → ABORT under \`--yes\`**" "$cc" "§1: disagreeing explicit sources abort"
}

# No explicit key: unchanged.
test_no_explicit_key_unchanged() {
  local cc; cc=$(cross_check)
  has_fixed "**No explicit key → unchanged:**" "$cc" "§1: the no-explicit-key case is unchanged"
  has_fixed "**under \`--yes\` a mismatch ABORTS**" "$cc" "§1: with no explicit key a mismatch still aborts under --yes"
}

# The abort list says the same thing as §1.
test_abort_list_agrees() {
  local al; al=$(abort_list)
  lacks_fixed "the §1 **wrong-ticket cross-check mismatches**" "$al" "abort list no longer aborts on any cross-check mismatch"
  has_fixed "branch names a different ticket key than the explicit one" "$al" "abort list: a different-key branch aborts"
  has_fixed "the explicit sources disagree" "$al" "abort list: disagreeing explicit sources abort"
  has_fixed "a lane branch under an explicit key only warns" "$al" "abort list: a lane branch under an explicit key warns"
}

# The §3 confirm header distinguishes the warning from the wrong-ticket warning.
test_confirm_header_agrees() {
  local cl; cl=$(confirm_line)
  has_fixed "branch-mismatch note" "$cl" "§3 header carries a branch-mismatch note for an explicit key"
  has_fixed "different key" "$cl" "§3 header keeps the prominent wrong-ticket warning for a different key"
}

run_discovered_tests
