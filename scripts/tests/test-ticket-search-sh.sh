#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FXDIR="$SRC_DIR/tests/fixtures/ticket-search"
# A prose taskSummary the reduction must distil to keywords.
PARAGRAPH="Please add a new flat detector for the recap table so that the extraction pipeline handles FIN-3447 correctly"

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux
  ln -sf "$SRC_DIR/ticket-search.sh" "$FAKE_HOME/.claude/scripts/ticket-search.sh"
  ln -sf "$SRC_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  TS="$FAKE_HOME/.claude/scripts/ticket-search.sh"
  unset LINEAR_API_KEY 2>/dev/null || true
  unset TICKET_SEARCH_FIXTURE 2>/dev/null || true
  unset TICKET_SEARCH_DEBUG 2>/dev/null || true
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# ---- Cases ----

test_ticketsearch_usage_and_no_query() {
  local out rc
  out=$("$TS" --help 2>&1); assert_contains "engine ticket-search" "$out" "usage lists the command"
  "$TS" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "no query exits non-zero"
}

# Case 1 — happy path: 3 excerpt lines, [KEY] title · state · score + snippet.
test_ticketsearch_happy_path_human() {
  local out
  out=$(TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" 2>/dev/null)
  assert_eq "6" "$(printf '%s\n' "$out" | grep -c .)" "3 hits → 6 non-empty lines (line + snippet each)"
  assert_contains "1. [FIN-200] Flat detector for recap · In Progress" "$out" "hit line: rank/key/title/state, no score"
  assert_contains "flat detector to the recap table" "$out" "snippet from description present"
}

# Case 2 — JSON mode: valid structured rows.
test_ticketsearch_json_mode() {
  local out tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" --json >"$tmp" 2>/dev/null
  assert_ok "json is a valid array" jq -e 'type == "array"' "$tmp"
  assert_json "$tmp" '.[0].identifier' "FIN-200" "top row identifier"
  assert_json "$tmp" '.[0].state' "In Progress" "top row state name"
  assert_json "$tmp" '.[0].stateType' "started" "top row state type"
  assert_json "$tmp" '.[0].project' "Extraction" "top row project"
  assert_json "$tmp" '.[0].score' "1" "top row overlap score"
  assert_json "$tmp" '.[0].url' "https://linear.app/x/issue/FIN-200" "top row url"
  assert_json "$tmp" '(.[0].snippet | contains("flat detector"))' "true" "top row snippet"
  assert_json "$tmp" '(.[0] | has("scoreLabel"))' "false" "internal scoreLabel not leaked to json"
}

# Case 3 — state flag drives the dup split: a Done ticket vs an open one.
test_ticketsearch_state_labels() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.[] | select(.identifier=="FIN-300") | .state' "Done" "done ticket labelled Done"
  assert_json "$tmp" '.[] | select(.identifier=="FIN-300") | .stateType' "completed" "done ticket type completed"
  assert_json "$tmp" '.[] | select(.identifier=="FIN-200") | .stateType' "started" "open ticket type started"
}

# Case 3b — --no-include-closed / --open-only drops completed/canceled via state.type post-filter.
test_ticketsearch_open_only_drops_done() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "detector" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" 'any(.[]; .identifier=="FIN-300")' "true" "done ticket present by default (include-closed ON)"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "detector" --open-only --json >"$tmp" 2>/dev/null
  assert_json "$tmp" 'any(.[]; .identifier=="FIN-300")' "false" "--open-only drops the completed ticket"
  assert_json "$tmp" 'any(.[]; .identifier=="FIN-200")' "true" "--open-only keeps the started ticket"
}

# Case 4 — ranking: fixture nodes are out of relevance order; _rank must reorder.
test_ticketsearch_ranking_reorders() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '[.[].identifier] | join(",")' "FIN-200,FIN-300,FIN-100" "ranked by overlap desc, not fixture order"
  assert_json "$tmp" '.[0].score' "1" "best match scores highest"
  assert_json "$tmp" '.[2].score' "0" "zero-overlap match scores lowest"
}

# Case 5 — empty: zero nodes → clean empty output, exit 0.
test_ticketsearch_empty_exit_zero() {
  local out rc
  out=$(TICKET_SEARCH_FIXTURE="$FXDIR/empty.json" "$TS" "flat detector" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "empty result exits 0 (not an error)"
  assert_empty "$out" "empty result → no stdout"
}

# Case 5b — empty in JSON mode → valid empty array.
test_ticketsearch_empty_json_array() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/empty.json" "$TS" "flat detector" --json >"$tmp" 2>/dev/null
  assert_ok "empty json is a valid array" jq -e 'type == "array"' "$tmp"
  assert_json "$tmp" 'length' "0" "empty array"
}

# Case 6 — GraphQL error: non-zero exit + stderr, no stdout garbage.
test_ticketsearch_graphql_error_fails_closed() {
  local out err rc
  out=$(TICKET_SEARCH_FIXTURE="$FXDIR/errors.json" "$TS" "flat detector" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "graphql error → non-zero exit"
  assert_empty "$out" "no stdout on error"
  assert_contains "GraphQL error" "$err" "error message on stderr"
}

# Case 7 — no key (live path, no fixture): clear key-required error, non-zero.
test_ticketsearch_missing_key_fails() {
  local out err rc
  unset LINEAR_API_KEY
  out=$(HOME="$TMP_DIR/nohome" "$TS" "flat detector" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_neq "0" "$rc" "missing key → non-zero exit"
  assert_empty "$out" "no stdout without key"
  assert_contains "LINEAR_API_KEY" "$err" "key-required message on stderr"
}

# Case 8 — query reduction: a paragraph is distilled to salient terms.
test_ticketsearch_query_reduction() {
  local err
  TICKET_SEARCH_DEBUG=1 TICKET_SEARCH_FIXTURE="$FXDIR/empty.json" "$TS" "$PARAGRAPH" >/dev/null 2>"$TMP_DIR/err"
  err=$(cat "$TMP_DIR/err")
  assert_contains "ticket-search: terms:" "$err" "reduced terms echoed under debug"
  assert_contains "FIN-3447" "$err" "FIN-key preserved"
  assert_contains "detector" "$err" "salient noun preserved"
  assert_not_contains "please" "$err" "stopword dropped"
  assert_not_contains " the " "$err" "article dropped"
}

# Case 8b — the reduced term drives relevance ranking through the pipeline.
test_ticketsearch_paragraph_finds_hit() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "$PARAGRAPH" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.[0].identifier' "FIN-200" "paragraph query still ranks the flat-detector ticket first"
}

# Tolerance — a node missing description/state does not crash; snippet degrades gracefully.
test_ticketsearch_missing_fields_tolerated() {
  local out tmp="$TMP_DIR/out.json"
  out=$(TICKET_SEARCH_FIXTURE="$FXDIR/missing-fields.json" "$TS" "anything" 2>/dev/null)
  assert_contains "[FIN-400] No description or state · ?" "$out" "missing state renders as ?"
  assert_contains "(no description)" "$out" "missing description renders placeholder snippet"
  TICKET_SEARCH_FIXTURE="$FXDIR/missing-fields.json" "$TS" "anything" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.[0].state' "null" "missing state → null in json"
}

# Snippet — literal backslash-n (as stored in some Linear descriptions) is stripped, not shown.
test_ticketsearch_literal_newline_stripped() {
  local out tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/literal-newline.json" "$TS" "line" --json >"$tmp" 2>/dev/null
  assert_json "$tmp" '.[0].snippet | test("\\\\n") | not' "true" "snippet contains no literal backslash-n"
  assert_json "$tmp" '.[0].snippet | startswith("First line. Second line")' "true" "literal-\\n replaced with space"
}

# Team scope — --team keeps only matching identifier prefixes.
test_ticketsearch_team_filter() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" --team FIN --json >"$tmp" 2>/dev/null
  assert_json "$tmp" 'length' "3" "all FIN-* hits kept with --team FIN"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" --team ENG --json >"$tmp" 2>/dev/null
  assert_json "$tmp" 'length' "0" "no ENG-* hits → empty under --team ENG"
}

# Limit — caps the number of hits.
test_ticketsearch_limit_caps() {
  local tmp="$TMP_DIR/out.json"
  TICKET_SEARCH_FIXTURE="$FXDIR/search-3hits.json" "$TS" "flat detector" --limit 1 --json >"$tmp" 2>/dev/null
  assert_json "$tmp" 'length' "1" "--limit 1 returns a single hit"
  assert_json "$tmp" '.[0].identifier' "FIN-200" "the single hit is the top-ranked one"
}

run_discovered_tests
