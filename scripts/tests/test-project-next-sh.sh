#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FXDIR="$SRC_DIR/tests/fixtures/project-next"
# UUID project arg → _resolve_project_id passes it through, so only _q_next fires (1 fixture/call).
PID="11111111-1111-1111-1111-111111111111"

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux
  ln -sf "$SRC_DIR/project.sh" "$FAKE_HOME/.claude/scripts/project.sh"
  ln -sf "$SRC_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  ln -sf "$SRC_DIR/linear-lib.sh" "$FAKE_HOME/.claude/scripts/linear-lib.sh"
  PS="$FAKE_HOME/.claude/scripts/project.sh"
  unset LINEAR_API_KEY LINEAR_FIXTURE PROJECT_FETCH_FIXTURE 2>/dev/null || true
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# ---- Cases ----

test_projectnext_usage() {
  local out
  out=$("$PS" next --help 2>&1) || true
  assert_contains "project next" "$out" "usage mentions the subcommand"
}

# Importance = flat global rank order milestone→priority→blocked. Blocked sinks in-tier;
# priority 0 (None) sorts last; no-milestone sorts last of all.
test_projectnext_importance_order() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '[.importance[].identifier] | join(",")' \
    "FIN-902,FIN-901,FIN-904,FIN-906,FIN-903,FIN-905" "milestone→priority→blocked order"
}

# Blocked = an inverseRelations 'blocks' edge whose source issue is OPEN.
test_projectnext_blocked_detection() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-904") | .blocked' "true" "open blocker → blocked"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-901") | .blocked' "false" "completed blocker → not blocked"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-902") | .blocked' "false" "related (non-blocks) → not blocked"
}

test_projectnext_worktype_grouping() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-901") | .workType' "bug" "Bug label → bug"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-902") | .workType' "feature" "Feature label → feature"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-903") | .workType' "chore" "chore label → chore"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-905") | .workType' "docs" "docs label → docs"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-906") | .workType' "other" "no label → other"
}

# No --query → adjacency empty (a second list with no seed is meaningless); not degraded here.
test_projectnext_no_query_no_adjacency() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.adjacency | length' "0" "no --query → empty adjacency"
  assert_json "$tmp" '.overlap | length' "0" "no adjacency → no overlap"
  assert_json "$tmp" '.degraded' "false" "milestones present → not degraded"
}

# Never-blend: the two orderings are separate arrays; no single merged score field.
test_projectnext_two_arrays_never_blended() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '(has("importance") and has("adjacency"))' "true" "two separate lists present"
  assert_json "$tmp" '.importance[0] | has("score")' "false" "importance rows carry no blended score"
}

# Degraded: no milestones → degraded flag + priority→blocked order.
test_projectnext_degraded_path() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/degraded.json" "$PS" next "22222222-2222-2222-2222-222222222222" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.degraded' "true" "no milestones → degraded"
  assert_json "$tmp" '[.importance[].identifier] | join(",")' "FIN-802,FIN-801,FIN-803" "priority order when degraded"
}

# --query drives adjacency (term-overlap on title+labels); importance still present.
test_projectnext_query_adjacency() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --query "crop guard" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.adjacency[0].identifier' "FIN-901" "best term-overlap (Fix the crop guard) ranks first in adjacency"
  assert_json "$tmp" '.adjacency | length > 0' "true" "adjacency populated with a query"
  assert_json "$tmp" '.importance | length' "6" "importance list still fully present"
}

# Overlap = identifiers in BOTH lists' top-limit.
test_projectnext_overlap_marked() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --query "crop guard bug" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" 'any(.overlap[]; . == "FIN-901")' "true" "FIN-901 appears in both lists → overlap"
}

test_projectnext_limit_caps_each_list() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --limit 2 --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.importance | length' "2" "--limit caps the importance list"
}

# Read-only: exactly ONE GraphQL read for a UUID + no --query. A 2nd call would exhaust the
# single-entry fixture list and surface a loud error — its absence proves no extra query fired.
test_projectnext_single_read_no_mutation() {
  local err rc
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >/dev/null 2>"$TMP_DIR/err"; rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "0" "$rc" "single read succeeds"
  assert_not_contains "fixture list exhausted" "$err" "no extra GraphQL call fired (read-only, one query)"
}

test_projectnext_human_format() {
  local out
  out=$(LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" 2>/dev/null)
  assert_contains "FIN-902" "$out" "top item present in human output"
  assert_contains "blocked" "$out" "blocked item is marked in human output"
}

# Human output WITH a query must render the adjacency section + ★ overlap marker, exit 0.
# (Regression guard: the overlap star used `index(.identifier)` where `.` was the overlap array.)
test_projectnext_human_adjacency_renders() {
  local out rc
  out=$(LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --query "crop guard" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "human mode with a query exits 0 (no jq index error)"
  assert_contains "Adjacency" "$out" "adjacency section rendered"
  assert_contains "★" "$out" "overlap star marker rendered"
}

test_projectnext_empty_exit_zero() {
  local rc tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/empty.json" "$PS" next "33333333-3333-3333-3333-333333333333" --json >"$tmp" 2>/dev/null; rc=$?
  assert_eq "0" "$rc" "empty project exits 0"
  assert_json "$tmp" '.importance | length' "0" "empty importance array"
}

test_projectnext_graphql_error_fails_closed() {
  local out err rc
  out=$(LINEAR_FIXTURE="$FXDIR/errors.json" "$PS" next "$PID" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "graphql error → non-zero"
  assert_empty "$out" "no stdout on error"
  assert_contains "GraphQL error" "$err" "error surfaced on stderr"
}

# No project arg AND no inferable branch key (run from a non-git temp dir) → clear error.
test_projectnext_no_project_errors() {
  local err rc
  ( cd "$TMP_DIR" && LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next >/dev/null 2>"$TMP_DIR/err" ); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "no project + no branch key → non-zero"
  assert_contains "project" "$err" "error mentions the missing project"
}

# ---- Relations + --tickets anchor ----

RID="44444444-4444-4444-4444-444444444444"

# Per-item linkage fields emitted on every importance row.
test_projectnext_per_item_linkage() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/relations.json" "$PS" next "$RID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-A1") | .relatedTo | join(",")' "FIN-A2" "A1 relatedTo from its own relations"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-A1") | .blocks | join(",")' "FIN-A3" "A1 blocks (what it unblocks)"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-A1") | .parent' "FIN-A0" "A1 parent"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-A2") | .relatedTo | join(",")' "FIN-A1" "A2 relatedTo from inverseRelations (both directions collected)"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-A2") | .blockedBy | join(",")' "FIN-A9" "A2 blockedBy"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-A4") | .duplicateOf' "FIN-A2" "A4 duplicateOf"
}

# Backward compat: existing intake fixture still yields blocked bool + now blockedBy, empty relatedTo/parent.
test_projectnext_linkage_backcompat() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-904") | .blocked' "true" "904 still blocked (backcompat)"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-904") | .blockedBy | join(",")' "FIN-999" "904 blockedBy populated"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-901") | .blocked' "false" "901 completed-blocker → not blocked (backcompat)"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-903") | .relatedTo | length' "0" "no relations in old fixture → empty relatedTo"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-903") | .parent' "null" "no parent in old fixture → null"
  # FIN-902's inverseRelations carries a 'related' edge → surfaced (both-directions collection).
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-902") | .relatedTo | join(",")' "FIN-980" "related inverse edge surfaced"
}

# Estimate (effort) surfaced on every importance row — a scalar, null when unset. Drives
# the /inbox-next effort-grouping ("bunch small things" vs "take a bigger task").
test_projectnext_estimate() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/intake.json" "$PS" next "$PID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-902") | .estimate' "5" "FIN-902 estimate surfaced"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-903") | .estimate' "2" "FIN-903 estimate surfaced"
  assert_json "$tmp" '.importance[] | select(.identifier=="FIN-906") | .estimate' "null" "unset estimate → null (grouping must handle it)"
  assert_json "$tmp" '.importance[0] | has("estimate")' "true" "estimate present on every importance row"
}

# --tickets anchor → the linked list (relation-tagged, cross-project resolved).
test_projectnext_tickets_anchor_linked() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/relations.json:$FXDIR/anchor-a1.json" "$PS" next "$RID" --tickets FIN-A1 --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.linked | length' "4" "4 linked tickets (related+blocks+parent+child)"
  assert_json "$tmp" '.linked[] | select(.identifier=="FIN-A2") | .relation' "related" "A2 tagged related"
  assert_json "$tmp" '.linked[] | select(.identifier=="FIN-A2") | .project' "Other Project" "A2 cross-project surfaced"
  assert_json "$tmp" '.linked[] | select(.identifier=="FIN-A2") | .title' "Related two" "A2 title resolved"
  assert_json "$tmp" '.linked[] | select(.identifier=="FIN-A3") | .relation' "blocks" "A3 tagged blocks"
  assert_json "$tmp" '.linked[] | select(.identifier=="FIN-A0") | .relation' "parent" "A0 tagged parent"
  assert_json "$tmp" '.linked[] | select(.identifier=="FIN-A5") | .relation' "child" "A5 tagged child"
  assert_json "$tmp" 'all(.linked[]; .anchor=="FIN-A1")' "true" "every linked row records its anchor"
}

# No --tickets → linked absent/empty; the three lists stay separate (never blended).
test_projectnext_linked_empty_without_tickets() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/relations.json" "$PS" next "$RID" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.linked | length' "0" "no --tickets → empty linked"
  assert_json "$tmp" '(has("importance") and has("adjacency") and has("linked"))' "true" "three separate lists present"
}

# --tickets + --query → BOTH adjacency and linked populated, never merged.
test_projectnext_tickets_and_query() {
  local tmp="$TMP_DIR/out.json"
  LINEAR_FIXTURE="$FXDIR/relations.json:$FXDIR/anchor-a1.json" "$PS" next "$RID" --tickets FIN-A1 --query "anchor one" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.linked | length > 0' "true" "linked populated from --tickets"
  assert_json "$tmp" '.adjacency | length > 0' "true" "adjacency populated from --query"
  assert_json "$tmp" '.adjacency[0] | has("relation")' "false" "adjacency rows are term-matched, not relation-tagged (not blended)"
}

# ---- Team resolution: the repository's § Tracker config (TICKETFLOW) ----
#
# Every seat runs on `main`, which carries no ticket key. Before this, a bare `next` there exited 1
# and `--all` took the team from the branch name (`main` -> MAIN) and returned 0 rows at exit 0, a
# zero that reads as an empty backlog. Now the team comes from `## Tracker` in the repository's
# CLAUDE.md, and every team is checked against Linear's teams before any issue is read.
#
# Fixture order for a team-wide run: call 1 = the teams read (teams.json), call 2 = the issues.

# make_repo DIR [CLAUDE.md body] — a git repo on branch `main` (no ticket key), optional CLAUDE.md.
make_repo() {
  local dir="$1" body="${2:-}"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main 2>/dev/null || { git -C "$dir" init -q && git -C "$dir" checkout -q -b main; }
  if [ -n "$body" ]; then printf '%s\n' "$body" > "$dir/CLAUDE.md"; fi
}

TRACKER_IDE='# demo

## Tracker

- **Tracker**: Linear (via the `linear` MCP)
- **Issue-key prefix**: `IDE` (keys look like `IDE-118`)
- **Team**: Idealic
- **PR base branch**: `main`

## Owners

- **Team**: NotThisOne'

# Positive control for every zero below: the fixture route returns rows when the team is right.
test_projectnext_team_explicit_known_ranks() {
  local tmp="$TMP_DIR/out.json" rc
  make_repo "$TMP_DIR/repo"
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --team IDE --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  assert_eq "0" "$rc" "--all --team IDE exits 0"
  assert_json "$tmp" '.project.name' "(team IDE)" "ranked team IDE"
  assert_json "$tmp" '.importance | length' "2" "both team issues ranked (control: the route yields rows)"
}

# The defect: a bare `next` on `main` exited 1. Now it ranks the Tracker team, and says so.
test_projectnext_bare_on_main_takes_team_from_tracker() {
  local tmp="$TMP_DIR/out.json" rc err
  make_repo "$TMP_DIR/repo" "$TRACKER_IDE"
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "0" "$rc" "bare next on main with a Tracker team exits 0"
  assert_json "$tmp" '.project.name' "(team IDE)" "team taken from § Tracker's issue-key prefix"
  assert_json "$tmp" '.importance | length' "2" "team issues ranked"
  assert_contains "Tracker" "$err" "stderr says the team came from § Tracker"
  assert_contains "CLAUDE.md" "$err" "stderr names the file it read"
}

# The silent zero: `--all` on `main` guessed MAIN and returned 0 rows at exit 0.
test_projectnext_all_on_main_takes_team_from_tracker() {
  local tmp="$TMP_DIR/out.json" rc
  make_repo "$TMP_DIR/repo" "$TRACKER_IDE"
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  assert_eq "0" "$rc" "--all on main exits 0"
  assert_json "$tmp" '.project.name' "(team IDE)" "--all takes the Tracker team, not the branch name"
  assert_json "$tmp" '.importance | length' "2" "rows ranked, not a silent zero"
}

# An explicit team that Linear does not have fails loudly instead of returning 0 rows.
test_projectnext_unknown_explicit_team_fails_loudly() {
  local out rc err
  make_repo "$TMP_DIR/repo"
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --team MAIN --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "unknown team -> non-zero"
  assert_empty "$out" "no ranking printed for an unknown team"
  assert_contains "MAIN" "$err" "stderr names the team"
  assert_contains "not found" "$err" "stderr says it was not found"
}

# A Tracker prefix Linear does not know fails loudly too, naming where it came from.
test_projectnext_unknown_tracker_team_fails_loudly() {
  local out rc err
  make_repo "$TMP_DIR/repo" '## Tracker

- **Tracker**: Linear
- **Issue-key prefix**: `ZZZ`'
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "unknown Tracker team -> non-zero"
  assert_empty "$out" "no ranking printed"
  assert_contains "ZZZ" "$err" "stderr names the configured team"
  assert_contains "Tracker" "$err" "stderr names § Tracker as the source"
}

# Prefix and team name disagree with Linear: refuse rather than pick one.
test_projectnext_tracker_team_name_mismatch_fails() {
  local out rc err
  make_repo "$TMP_DIR/repo" '## Tracker

- **Tracker**: Linear
- **Issue-key prefix**: `IDE`
- **Team**: Acme'
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "prefix/team mismatch -> non-zero"
  assert_empty "$out" "no ranking printed"
  assert_contains "Acme" "$err" "stderr names the configured team"
  assert_contains "Idealic" "$err" "stderr names the team Linear has for that key"
}

# A Tracker block naming only the team resolves the key through Linear's teams.
test_projectnext_tracker_team_name_only_resolves_key() {
  local tmp="$TMP_DIR/out.json" rc
  make_repo "$TMP_DIR/repo" '## Tracker

- **Tracker**: Linear
- **Team**: idealic'
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  assert_eq "0" "$rc" "team name only exits 0"
  assert_json "$tmp" '.project.name' "(team IDE)" "team name resolved to its key"
}

# A tracker that is not Linear is refused by name.
test_projectnext_tracker_not_linear_fails() {
  local out rc err
  make_repo "$TMP_DIR/repo" '## Tracker

- **Tracker**: GitHub Issues
- **Issue-key prefix**: `GH`'
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "non-Linear tracker -> non-zero"
  assert_empty "$out" "no ranking printed"
  assert_contains "GitHub Issues" "$err" "stderr names the configured tracker"
  assert_contains "Linear" "$err" "stderr says only Linear is read"
}

# On `main` with no Tracker block there is nothing to rank: fail, and say what was looked for.
test_projectnext_bare_on_main_without_tracker_errors() {
  local out rc err
  make_repo "$TMP_DIR/repo"
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "no project, no key, no Tracker -> non-zero"
  assert_empty "$out" "nothing printed"
  assert_contains "Tracker" "$err" "stderr says no § Tracker team was found"
  assert_not_contains "MAIN" "$err" "the branch name is never taken as a team"
}

# ---- Branch ticket keys (TICKETFLOW fix round: F1, F2) ----
#
# Widen to the team only when the branch carries NO ticket key. A key whose issue has no project,
# a missing issue, or a failed read is a named failure, never "no branch ticket key" at exit 0.
# A key is matched at the start of the branch or after a `/` (Linear's `invizko/ide-118-…`).

# on_branch DIR BRANCH — move the repo made by make_repo onto BRANCH (needs one commit).
on_branch() {
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$1" checkout -q -b "$2"
}

test_projectnext_key_without_project_fails_named() {
  local out rc err
  make_repo "$TMP_DIR/repo" "$TRACKER_IDE"; on_branch "$TMP_DIR/repo" ide-118-foo
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/issue-noproject.json:$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "branch key whose issue has no project -> non-zero"
  assert_empty "$out" "no team-wide list in place of the project's"
  assert_contains "IDE-118" "$err" "stderr names the branch key"
  assert_contains "no project" "$err" "stderr says the issue has no project"
  assert_not_contains "no branch ticket key" "$err" "never claims there was no key"
}

test_projectnext_key_missing_issue_fails_named() {
  local out rc err
  make_repo "$TMP_DIR/repo" "$TRACKER_IDE"; on_branch "$TMP_DIR/repo" ide-118-foo
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/issue-missing.json:$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "branch key with no such issue -> non-zero"
  assert_empty "$out" "nothing ranked"
  assert_contains "IDE-118" "$err" "stderr names the branch key"
  assert_not_contains "no branch ticket key" "$err" "never claims there was no key"
}

test_projectnext_key_failed_read_fails_named() {
  local out rc err
  make_repo "$TMP_DIR/repo" "$TRACKER_IDE"; on_branch "$TMP_DIR/repo" ide-118-foo
  out=$(cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/errors.json:$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --json 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "failed Linear read for the branch key -> non-zero"
  assert_empty "$out" "nothing ranked"
  assert_contains "IDE-118" "$err" "stderr names the branch key"
  assert_not_contains "no branch ticket key" "$err" "never claims there was no key"
}

# Kit's branch shape: the key follows a `user/` prefix.
test_projectnext_prefixed_branch_key_finds_project() {
  local tmp="$TMP_DIR/out.json" rc
  make_repo "$TMP_DIR/repo" "$TRACKER_IDE"; on_branch "$TMP_DIR/repo" invizko/ide-118-foo
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/issue-project.json:$FXDIR/intake.json" "$PS" next --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  assert_eq "0" "$rc" "prefixed branch key exits 0"
  assert_json "$tmp" '.project.name' "Product: Intake System" "the key's project is ranked, not the team"
}

# --all with no Tracker falls back to a branch key's prefix, prefixed or not.
test_projectnext_all_branch_key_fallback() {
  local tmp="$TMP_DIR/out.json" rc
  make_repo "$TMP_DIR/repo"; on_branch "$TMP_DIR/repo" fin-7-thing
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  assert_eq "0" "$rc" "--all on fin-7-thing exits 0"
  assert_json "$tmp" '.project.name' "(team FIN)" "team from the branch key's prefix"
}

test_projectnext_all_prefixed_branch_key_fallback() {
  local tmp="$TMP_DIR/out.json" rc
  make_repo "$TMP_DIR/repo"; on_branch "$TMP_DIR/repo" someone/fin-7-thing
  ( cd "$TMP_DIR/repo" && LINEAR_FIXTURE="$FXDIR/teams.json:$FXDIR/team-issues.json" "$PS" next --all --json >"$tmp" 2>"$TMP_DIR/err" ); rc=$?
  assert_eq "0" "$rc" "--all on someone/fin-7-thing exits 0"
  assert_json "$tmp" '.project.name' "(team FIN)" "team from a prefixed branch key"
}

run_discovered_tests
