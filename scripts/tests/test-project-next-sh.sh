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

run_discovered_tests
