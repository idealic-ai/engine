#!/bin/bash
# test-snapshot-ticket-guard.sh — /snapshot §1's wrong-ticket cross-check under an explicit key.
#
# Every loom runs `/snapshot --yes` when a thread lands, from a LANE branch (runner/wave1b,
# writer/ide150-archetype) that never equals Linear's canonical gitBranchName. The old §1 made any
# branch mismatch an abort under --yes, so every lane snapshot aborted. The rule now:
#   * the EXPLICIT key IS the target: a run has one only when the target equals the `-- <KEY>`
#     argument or a key carried by the snapshotted commits (the branch's commits not on its
#     upstream base, minus the commit §3 drafts, read as a set). Every explicit source present
#     must name the target, or --yes aborts. tickets[] corroborates and is never a source;
#   * explicit key + a branch that is not the canonical one → WARN and proceed, for status-only
#     runs and commits alike, with the branch in a Snapshot-Branch trailer and the comment;
#   * the branch key naming a DIFFERENT key (configured § Tracker prefix only) → ABORT under --yes;
#   * no explicit key → unchanged (a mismatch aborts under --yes).
# The callers (/loom's landed-thread snapshot, /next's checkpoint) pass `-- <KEY>`.
#
# TEXT CONTRACT ONLY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): these arms read skill files. They do
# not run a live /snapshot; that an agent obeys the prose is not checked here. Needles are matched
# case-insensitively with bold markers stripped, so a copy-edit of emphasis or capitalisation
# does not turn an arm red. SNAPSHOT_SKILL / SNAPSHOT_TEMPLATE / LOOM_SKILL / NEXT_SKILL override
# the files read, so a planted copy can be shown to go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="${SNAPSHOT_SKILL:-$ENGINE_DIR/skills/snapshot/SKILL.md}"
TEMPLATE="${SNAPSHOT_TEMPLATE:-$ENGINE_DIR/skills/snapshot/assets/TEMPLATE_SNAPSHOT.md}"
LOOM="${LOOM_SKILL:-$ENGINE_DIR/skills/loom/SKILL.md}"
NEXT="${NEXT_SKILL:-$ENGINE_DIR/skills/next/SKILL.md}"

# norm strips bold markers. Matched through a here-string, not a pipe: under pipefail, grep -q
# closing early SIGPIPEs the writer on a large input and the pipeline reads as no match.
norm() { printf '%s\n' "$1" | sed 's/\*\*//g'; }
has_fixed() {
  if grep -qiF -- "$1" <<<"$(norm "$2")"; then pass "$3"; else fail "$3" "contains '$1'" "absent"; fi
}
lacks_fixed() {
  if grep -qiF -- "$1" <<<"$(norm "$2")"; then fail "$3" "lacks '$1'" "present"; else pass "$3"; fi
}

# A top-level bullet of §1 by its bold lead, with its nested lines, up to the next top-level bullet.
bullet() {
  awk -v lead="$1" 'index($0, "- **" lead) == 1 {on=1; print; next} on && /^- / {exit} on && /^#/ {exit} on {print}' "$SKILL"
}
target_bullet() { bullet "Target ticket"; }
cross_check() { bullet "Wrong-ticket cross-check:"; }
# One nested sub-bullet of the cross-check, by the start of its bold lead.
sub_bullet() { cross_check | grep -m1 -F -- "  - **$1"; }
# The abort-list paragraph in § Unattended runs.
abort_list() { grep -m1 -F 'situations abort the run' "$SKILL"; }
# §3 step 2, the batch confirm line.
confirm_line() { grep -m1 -F '2. **Batch confirm**' "$SKILL"; }
# §2's reviewer prompt: the blockquoted lines of § 2.
reviewer_prompt() { awk '/^## 2\./ {on=1; next} on && /^## / {exit} on && /^>/ {print}' "$SKILL"; }

test_cross_check_exists() {
  assert_not_empty "$(cross_check)" "§1 has a Wrong-ticket cross-check bullet"
  assert_not_empty "$(target_bullet)" "§1 has a Target ticket bullet"
}

# M1 — the explicit key is the target, and only the argument and the commits make it explicit.
test_explicit_key_is_the_target() {
  local cc; cc=$(cross_check)
  has_fixed "the explicit key is the target" "$cc" "M1: §1 says the explicit key is the target"
  has_fixed '`-- <KEY>` argument' "$cc" "M1: the argument is an explicit source"
  has_fixed "subjects or trailers" "$cc" "M1: a key carried by the snapshotted commits is an explicit source"
  lacks_fixed "every explicit source present must name the target" "$cc" "R2-S1: the all-commits-name-the-target rule is gone"
  has_fixed '`tickets[]` corroborates and is never a source on its own' "$cc" "M1: tickets[] corroborates, never a source"
  lacks_fixed "contains neither" "$cc" "M1/S3: no abort on tickets[] containing neither key"
  lacks_fixed 'named in the active session' "$cc" "M1: tickets[] membership no longer makes a key explicit"
}

# M1 — the two wrong-ticket paths the critique found are named, and both abort.
test_reused_lane_stale_slug_aborts() {
  local cc; cc=$(cross_check)
  has_fixed 'slug names `IDE-313` while its commits carry `IDE-312`' "$cc" "M1(1): the reused-lane / stale-slug case is named"
  has_fixed 'commits carry `IDE-312` aborts' "$cc" "M1(1): the reused-lane / stale-slug case aborts"
}
test_stale_tickets_list_aborts() {
  local cc; cc=$(cross_check)
  has_fixed 'a key that is only in `tickets[]` is not explicit' "$cc" "M1(2): a key only in tickets[] is not explicit"
  has_fixed 'stale `tickets[]`' "$cc" "M1(2): the stale tickets[] case is named"
  has_fixed "falls to the no-explicit-key case and aborts under \`--yes\`" "$cc" "M1(2): the stale tickets[] case aborts under --yes"
}

# S4 — the commit range and set semantics.
test_commit_range_defined() {
  local cc; cc=$(cross_check)
  has_fixed '`git log --no-merges origin/<default branch>..HEAD`' "$cc" "R2-S1: the range is origin/<default branch>..HEAD, merges excluded"
  has_fixed 'never `@{u}`' "$cc" "R2-S1: the range never uses @{u}"
  lacks_fixed "not on its upstream base" "$cc" "R2-S1: the upstream-relative range is gone"
  has_fixed "excluding the commit §3 is about to draft" "$cc" "S4: the commit §3 drafts cannot vouch for the target"
  lacks_fixed "two different keys among them is a disagreement" "$cc" "R2-S1: two keys no longer always disagree"
}

# R2-S1 — with a -- key the commit key set must contain the target or be empty; other keys warn.
# Without --, two or more keys among the commits is ambiguous and aborts under --yes.
test_commit_key_set_rule() {
  local cc; cc=$(cross_check)
  has_fixed "the commits' key set must contain the target or be empty" "$cc" "R2-S1: with --, the commit keys contain the target or are empty"
  has_fixed "keys for other tickets in that set are only a warning" "$cc" "R2-S1: other tickets' keys only warn (wave and stacked lanes)"
  has_fixed "two or more keys among the commits is ambiguous and aborts under \`--yes\`" "$cc" "R2-S1: without --, two or more commit keys abort"
}

# The lane-branch mismatch under an explicit key warns and proceeds — and that bullet never aborts.
test_lane_branch_warns() {
  local w; w=$(sub_bullet "Explicit key, branch is not")
  assert_not_empty "$w" "§1 has the explicit-key / non-canonical-branch sub-bullet"
  has_fixed "WARN and proceed" "$w" "§1: explicit key + non-canonical branch warns and proceeds"
  has_fixed "a status-only run and a commit alike" "$w" "§1: the warn case covers commits, not only status-only runs"
  has_fixed '`Snapshot-Branch: <branch>`' "$w" "§1: the branch is recorded in a commit trailer"
  has_fixed "the comment names the branch" "$w" "§1: the branch is recorded in the ticket comment"
  lacks_fixed "abort" "$w" "§1: the warn sub-bullet does not abort (any case, any wording)"
}

# The different-key case keeps aborting, and only with a configured prefix (S6).
test_different_key_aborts() {
  local d; d=$(sub_bullet "Explicit key, branch key names a different key")
  assert_not_empty "$d" "§1 has the different-key sub-bullet"
  has_fixed "ABORT under \`--yes\`" "$d" "§1: a branch naming a different key than the explicit one aborts"
  has_fixed '`ide-312-x` with key `IDE-313` aborts' "$d" "§1 gives the different-key example"
  lacks_fixed "only with a configured § Tracker prefix" "$d" "R2-N1: the different-key abort is not limited to a configured prefix"
  has_fixed "in fallback mode a hyphenated \`<PREFIX>-NNNN\` branch key still aborts" "$d" "R2-N1: fallback keeps the abort for the hyphenated form"
  has_fixed "only the unhyphenated lane-name forms warn" "$d" "R2-N1: only the unhyphenated forms warn in fallback"
  local s; s=$(sub_bullet "Explicit sources disagree")
  has_fixed "ABORT under \`--yes\`" "$s" "§1: disagreeing explicit sources abort"
}

# N1 — one branch-key description, defined in Target ticket and referenced from the cross-check.
test_one_branch_key_description() {
  local n; n=$(grep -c -F '`<prefix>NNNN`' "$SKILL")
  assert_eq "1" "$n" "N1: the branch-key shape is written once in SKILL.md"
  has_fixed '`<prefix>NNNN`' "$(target_bullet)" "N1: the branch-key shape lives in Target ticket"
  has_fixed "branch key" "$(cross_check)" "N1: the cross-check uses the same branch key"
}

# S1/S2/N3 — the argument is high-confidence detection and clears the slug/branch flag.
test_argument_is_high_confidence() {
  local t; t=$(target_bullet)
  has_fixed 'a `-- <KEY>` argument is high-confidence' "$t" "S1: the -- argument is high-confidence detection"
  has_fixed "clears the branch-key ≠ slug-key flag" "$t" "S2: the argument clears the branch-key ≠ slug-key flag"
  has_fixed 'a bare key after `/snapshot --yes` with no `--` is not the argument' "$t" "N3: a bare key without -- is not the argument"
}

# No explicit key: unchanged.
test_no_explicit_key_unchanged() {
  local u; u=$(sub_bullet "No explicit key")
  has_fixed "unchanged" "$u" "§1: the no-explicit-key case is unchanged"
  has_fixed "under \`--yes\` a mismatch ABORTS" "$u" "§1: with no explicit key a mismatch still aborts under --yes"
  has_fixed "conversation" "$u" "N3: a conversation key is an inferred key"
}

# The abort list says the same thing as §1.
test_abort_list_agrees() {
  local al; al=$(abort_list)
  lacks_fixed "wrong-ticket cross-check mismatches" "$al" "abort list no longer aborts on any cross-check mismatch"
  has_fixed "names a different ticket key than the explicit one" "$al" "abort list: a different-key branch aborts"
  has_fixed "an explicit source does not name the target" "$al" "abort list: an explicit source not naming the target aborts"
  has_fixed "a lane branch under an explicit key only warns" "$al" "abort list: a lane branch under an explicit key warns"
}

# The §3 confirm header distinguishes the note from the wrong-ticket warning (tightened :94, N2).
test_confirm_header_agrees() {
  local cl; cl=$(confirm_line)
  has_fixed "branch-mismatch note" "$cl" "§3 header carries a branch-mismatch note for an explicit key"
  has_fixed "a branch key naming a different key" "$cl" "§3 header keeps the wrong-ticket warning for a different branch key"
  has_fixed "disagreeing sources were already asked in §1" "$cl" "N2: §3 says where the disagreeing-sources ask happens"
}

# S5 — the reviewer prompt and the template carry the trailer and the comment's branch line.
test_trailer_reaches_the_draft() {
  local rp; rp=$(reviewer_prompt)
  has_fixed 'Snapshot-Branch: <branch>' "$rp" "S5: the reviewer prompt drafts the Snapshot-Branch trailer"
  has_fixed "Branch:" "$rp" "S5: the reviewer prompt drafts the comment's branch line"
  local tp; tp=$(cat "$TEMPLATE")
  has_fixed 'Snapshot-Branch: <branch>' "$tp" "S5: the template's commit proposal carries the trailer"
  has_fixed "Branch: \`<branch>\`" "$tp" "S5: the template's comment carries the branch line"
}

# S1 — the callers pass the key.
test_callers_pass_the_key() {
  local l; l=$(cat "$LOOM")
  has_fixed '`/snapshot --yes -- <thread KEY>`' "$l" "S1: /loom's Automatic path passes -- <thread KEY>"
  has_fixed 'invoke `/snapshot --yes` with `-- <thread KEY>`' "$l" "S1: /loom's answered-ask path passes -- <thread KEY>"
  lacks_fixed 'invokes `/snapshot --yes` ' "$l" "S1: no /loom call line runs /snapshot --yes without the key"
  local n; n=$(cat "$NEXT")
  has_fixed '`/snapshot --yes -- <KEY>`' "$n" "S1: /next's checkpoint passes -- <KEY>"
}

# every_line_has <file> <call needle> <clause> <msg> — each line carrying the call also carries the clause.
every_line_has() {
  local file=$1 call=$2 clause=$3 msg=$4 line n=0 bad=0
  while IFS= read -r line; do
    n=$((n+1))
    grep -qiF -- "$clause" <<<"$(norm "$line")" || bad=$((bad+1))
  done < <(grep -F -- "$call" "$file")
  if [ "$n" -gt 0 ] && [ "$bad" -eq 0 ]; then pass "$msg ($n line(s))"; else fail "$msg" "all $n call line(s) carry '$clause'" "$bad lack it"; fi
}

# R2-M1 — /next names where <KEY> comes from, never tickets[], and falls back to bare --yes.
test_next_key_sources() {
  every_line_has "$NEXT" '/snapshot --yes -- <KEY>' "the session slug's key, a keyed branch, or the lane log's thread key" "R2-M1: /next names the key's three sources"
  every_line_has "$NEXT" '/snapshot --yes -- <KEY>' 'never from `tickets[]`' "R2-M1: /next never takes the key from tickets[]"
  every_line_has "$NEXT" '/snapshot --yes -- <KEY>' 'bare `--yes` otherwise' "R2-M1: /next falls back to bare --yes"
}

# R2-S2 — /loom passes the key only for a thread with its own ticket, never an umbrella key.
test_loom_key_fallback() {
  every_line_has "$LOOM" '-- <thread KEY>`' "only when the thread has its own ticket" "R2-S2: /loom passes the key only for a ticketed thread"
  every_line_has "$LOOM" '-- <thread KEY>`' 'bare `--yes` otherwise' "R2-S2: /loom falls back to bare --yes"
  every_line_has "$LOOM" '-- <thread KEY>`' "never an umbrella key" "R2-S2: /loom never passes an umbrella key"
}

run_discovered_tests
