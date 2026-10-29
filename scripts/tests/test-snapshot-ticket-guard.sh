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

# IDE-341 (operator ruling 2026-10-30 03:06, round-4 rulings) — `--yes` on un-ticketed work files a
# ticket, but only once the run is known to proceed: every check that can abort runs first, any
# duplicate candidate aborts (never attach), /ticket's non-confirm gates run on the draft, the
# project comes from the work's repository first, and the filed key is recorded where §1 reads it.
autofile_para() { grep -m1 -F 'files a ticket only for work that has none' "$SKILL"; awk '/files a ticket only for work that has none/ {on=1; next} on && /situations abort the run/ {exit} on {print}' "$SKILL"; }
TICKET="${TICKET_SKILL:-$ENGINE_DIR/skills/ticket/SKILL.md}"
REGISTRY="${REGISTRY_FILE:-$ENGINE_DIR/skills/inbox-post/assets/INBOX_REGISTRY.md}"
FRONT="$(sed -n '1,/^---$/p' "$SKILL" | sed -n '2,$p')"
# step_no <needle> → the number of the auto-file list item that carries the needle (0 when none).
step_no() { autofile_para | awk -v n="$1" 'BEGIN{IGNORECASE=1} /^[0-9]+\. / { if (index(tolower($0), tolower(n))) { sub(/\..*/, ""); print; exit } }' | grep . || echo 0; }
# line_no <needle> → the first SKILL.md line carrying the needle (0 when none).
line_no() { grep -n -m1 -F -- "$1" "$SKILL" | cut -d: -f1 | grep . || echo 0; }
before() {  # before <a> <b> <msg> — a > 0, b > 0 and a < b
  if [ "$1" -gt 0 ] && [ "$2" -gt 0 ] && [ "$1" -lt "$2" ]; then pass "$3"; else fail "$3" "$1 < $2 (both > 0)" "$1 vs $2"; fi
}

test_autofile_replaces_never_creates() {
  lacks_fixed '`--yes` never creates a ticket' "$(cat "$SKILL")" "IDE-341: /snapshot no longer says --yes never creates a ticket"
  assert_not_empty "$(autofile_para)" "IDE-341: § Unattended runs has the auto-file paragraph"
}

test_autofile_new_key_in_commit() {
  local a; a=$(autofile_para)
  has_fixed "no explicit key" "$a" "IDE-341: auto-file needs no explicit key"
  has_fixed "§1 detects no key at any confidence" "$a" "IDE-341: auto-file fires only on work with no key at all"
  has_fixed "the commit message carries the new key" "$a" "IDE-341: un-ticketed work ends with the new key in the commit message"
  has_fixed "the run's explicit key from here on" "$a" "IDE-341: the new key is explicit, so a lane branch only warns"
  has_fixed '`auto-filed by /snapshot --yes`' "$a" "IDE-341: the body carries the auto-filed marker"
  has_fixed "routine, never reserved" "$a" "IDE-341: an auto-filed ticket is routine, never reserved"
  has_fixed "premise-first" "$a" "IDE-341: the draft is premise-first like /ticket"
}

# R3-M2 — any candidate aborts; never attach.
test_autofile_any_candidate_aborts() {
  local a; a=$(autofile_para)
  has_fixed '`/ticket-search --report`' "$a" "R3-M2: the duplicate search runs"
  has_fixed "file only when it returns no candidates" "$a" "R3-M2: filing needs zero candidates"
  has_fixed "on any candidate, abort and print each" "$a" "R3-M2: any candidate aborts and is printed"
  has_fixed "with its state" "$a" "R3-M2: candidates are printed with their states"
  has_fixed 'so the seat re-runs with `-- <KEY>`' "$a" "R3-M2: the seat re-runs with -- <KEY>"
  has_fixed "never attach" "$a" "R3-M2: never attach"
  has_fixed "never to a Done one" "$a" "R3-M2: never post to a Done ticket"
  lacks_fixed "attach the work to that ticket" "$a" "R3-M2: the attach path is gone"
}

# R3-S1 — /ticket's non-confirm gates run on the draft.
test_autofile_ticket_gates() {
  local a; a=$(autofile_para)
  has_fixed "Subject Gate" "$a" "R3-S1: the Subject Gate runs on the draft"
  has_fixed "a refusal by any of them aborts with its reason" "$a" "R3-S1: a refusal aborts with its reason"
  has_fixed "Ticketing Strategy" "$a" "R3-S1: the project's Ticketing Strategy applies"
  has_fixed "Size dial" "$a" "R3-S1: the Size dial applies"
  has_fixed "In plain terms" "$a" "R3-S1: the plain-terms opening"
  has_fixed 'state: "backlog"' "$a" "R3-S1: state backlog"
}

# R3-S2 + registry — the project comes from the work's repository first, then the session; team stated.
test_autofile_project_never_guessed() {
  local a; a=$(autofile_para)
  has_fixed "the work's own repository first" "$a" "R3-S2: the work's repository is the first project source"
  has_fixed "then the session's \`linearProject\` parameter" "$a" "R3-S2: the session is second"
  has_fixed "its project id alone resolves the project" "$a" "registry: a row's project id alone resolves the project"
  has_fixed "only means no handbook rules apply" "$a" "registry: a missing handbook only means no handbook rules"
  has_fixed "team Idealic" "$a" "R3-S2: the team is stated"
  has_fixed "name the source" "$a" "IDE-341: the run names the project source it used"
  has_fixed "neither resolves → abort and say so" "$a" "IDE-341: no project → abort, never guess"
  lacks_fixed "fleet config" "$a" "R3-S2: the fleet-config source is gone"
}

# N1 + director (a) + R3-M1 record.
test_autofile_label_record_and_rerun() {
  local a; a=$(autofile_para)
  has_fixed 'the label `auto-filed`' "$a" "N1: the auto-filed label"
  has_fixed "create it in team Idealic if missing" "$a" "N1: the label is created if missing"
  has_fixed '`<sessionDir>/.snapshot-autofiled`' "$a" "R3-M1: the filed key is recorded in the session dir"
  has_fixed "Ruled below you" "$a" "director (a): a settled ask record for Ruled below you"
  has_fixed "answered by the seat" "$a" "director (a): the record is answered by the seat"
  has_fixed '.snapshot-autofiled`' "$(target_bullet)" "R3-M1: §1 reads the record first on a re-run"
  has_fixed "read first" "$(target_bullet)" "R3-M1: §1 reads it first"
}

# R3-S4 — a single commit key with no -- is low-confidence and aborts rather than files.
test_single_commit_key_low_confidence() {
  has_fixed "a single key carried by the commits being snapshotted, with no \`--\`, is a low-confidence detection" "$(target_bullet)" "R3-S4: a single commit key is a low-confidence detection"
  has_fixed "aborts rather than files" "$(target_bullet)" "R3-S4: it aborts rather than files"
}

# R3-M1 — ORDER: every abort check comes before the filing, in the list and in §3.
test_autofile_order_in_list() {
  local f; f=$(step_no "**File**")
  before "$(step_no "§1 decides")" "$f" "order: §1's checks come before the filing"
  before "$(step_no "§2 reviews")" "$f" "order: §2's review and gates come before the filing"
  before "$(step_no "Subject Gate")" "$f" "order: the Subject Gate comes before the filing"
  before "$(step_no "/ticket-search --report")" "$f" "order: the duplicate search comes before the filing"
  before "$(step_no "staged-content check")" "$f" "order: §3's staged-content check comes before the filing"
  before "$f" "$(step_no "Commit and post")" "order: the filing comes before the commit and post"
}
test_autofile_order_in_section_3() {
  local z; z=$(line_no "**[0] Auto-file")
  before "$(line_no "**Inspect the staged CONTENT before committing:**")" "$z" "§3 order: the staged-content check precedes [0] Auto-file"
  before "$(line_no "**Green re-check (TOCTOU):**")" "$z" "§3 order: the green re-check precedes [0] Auto-file"
  before "$z" "$(line_no "- **Commit** with the approved message")" "§3 order: [0] Auto-file precedes the commit"
  before "$(line_no "## 2. Review")" "$z" "§3 order: §2 precedes [0] Auto-file"
}

# R3-M1 — ":33": an abort posts nothing, commits nothing and files nothing.
test_abort_files_nothing() {
  has_fixed "files nothing" "$(abort_list)" "R3-M1: an abort files nothing"
  has_fixed "comes after every check that can abort" "$(abort_list)" "R3-M1: the abort list says why"
}

# R3-S3 — the other statements agree.
test_other_statements_agree() {
  local t; t=$(cat "$TICKET")
  has_fixed '`/snapshot --yes` auto-filing work that has no ticket at all' "$t" "IDE-341: /ticket names the /snapshot --yes exception"
  has_fixed "scope-level reservation still applies to every ticket a seat files deliberately through \`/ticket\`" "$t" "IDE-341: /ticket keeps scope-level reservation"
  has_fixed "a ticket is the exception a human asks for, or the one \`/snapshot --yes\` files" "$(grep -F 'A finding is a signal; a chunk of work is a ticket' "$TICKET")" "R3-S3: ticket:217 names the auto-file"
  has_fixed "except the one \`/snapshot --yes\` auto-files" "$(grep -F 'The user owns every ticket' "$TICKET")" "R3-S3: ticket:219 names the auto-file"
  has_fixed "the one filing that does not ask" "$(grep -F 'keep theirs' "$LOOM")" "R3-S3: loom:73 names the auto-file"
  has_fixed "the \`/snapshot --yes\` auto-file of un-ticketed work aside" "$(grep -F 'No position of *Interruption* reaches this card' "$LOOM")" "R3-S3: loom:280 names the auto-file"
  has_fixed "files a ticket for it instead" "$(grep -F 'Say this plainly in the header' "$NEXT")" "R3-S3: next:88 says no key at all files a ticket"
  has_fixed "files one ticket for un-ticketed work" "$FRONT" "R3-S3: the snapshot frontmatter names the auto-file"
}

# Registry rows.
test_registry_rows() {
  local r; r=$(cat "$REGISTRY")
  has_fixed '| Product: Orchestration |' "$r" "registry: Orchestration has a handbook row"
  has_fixed '`83a9a7d7-fecf-4135-b47b-75514e9f3b6e` · `1ff5597c997b`' "$r" "registry: Orchestration's doc id and slugId"
  has_fixed '| Product: Market & Jobs |' "$r" "registry: Market & Jobs has a handbook row"
  has_fixed '`163b1b3d-74e0-4f14-a169-ad448c295c60` · `4b8c10a1ebe7`' "$r" "registry: Market & Jobs' doc id and slugId"
  has_fixed '`8716ada7-01c9-49b7-a882-51e7c2352960`' "$r" "registry: Orchestration's project id"
  has_fixed "a row's project id alone resolves the project" "$r" "registry: says the project id alone resolves the project"
  has_fixed "only means no handbook rules apply" "$r" "registry: says a missing handbook only means no handbook rules"
}

run_discovered_tests
