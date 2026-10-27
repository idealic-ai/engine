#!/bin/bash
# test-next-prefetch.sh — Tests for the state pre-warmer.
#
# EVERY GUARD IS A PAIR. Each pair's two arms differ in exactly ONE thing — the condition the
# guard tests — so neither can pass vacuously and breaking the guard reddens one of them. Where
# the pair is about a side effect (a tool that must not run on the cheap path), the arms are the
# presence and the absence of that tool's sentinel file rather than a line of output.
#
# The property under test above all others: UNREAD is not empty. The UNREAD-0x and FINDING-0x
# pairs hold stdout IDENTICAL between arms and vary only the exit code, which is the only way to
# show that the status came from the code and not from the (absent) output.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SUT="${NEXT_PREFETCH_UNDER_TEST:-$HOME/.claude/engine/scripts/next-prefetch.sh}"

setup() {
  setup_test_env "test_next_prefetch"
  SUT_ABS="$SUT"
  STUBS="$TMP_DIR/stubs"
  mkdir -p "$STUBS"
  SENTINELS="$TMP_DIR/sentinels"
  mkdir -p "$SENTINELS"

  # Benign defaults: every engine tool the warmer reaches exists, exits 0, says nothing.
  # Each test then varies ONE of them.
  stub open-asks 0
  stub sweep-check 0
  stub loom-page 0
  stub lane-stall 0
  stub ticket-search 0

  REPO_A="$TMP_DIR/repo-a"
  make_repo "$REPO_A" branch-a
}

teardown() { cleanup_test_env; }

# stub NAME RC [STDOUT_HEREDOC_BODY] — writes an executable stub that touches a sentinel named
# after itself (so "was this invoked?" is answerable), prints BODY, and exits RC.
stub() {
  local name="$1" rc="$2" body="${3:-}"
  cat > "$STUBS/$name.sh" <<STUB
#!/bin/bash
touch "$SENTINELS/$name"
printf '%s' "\$*" > "$SENTINELS/$name.args"
cat <<'BODY'
$body
BODY
exit $rc
STUB
  chmod +x "$STUBS/$name.sh"
}

# A stub whose only distinguishing feature is how long it takes.
slow_stub() {
  local name="$1" secs="$2"
  cat > "$STUBS/$name.sh" <<STUB
#!/bin/bash
touch "$SENTINELS/$name"
sleep $secs
exit 0
STUB
  chmod +x "$STUBS/$name.sh"
}

make_repo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q 2>/dev/null
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  git -C "$dir" checkout -q -b "$branch" 2>/dev/null
  echo one > "$dir/f.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
}

# write_state '<jq filter appended to the base object>'
write_state() {
  local extra="${1:-}"
  jq -n '{pid: 99999999, lifecycle: "active", skill: "loom"}'"$extra" > "$TEST_SESSION/.state.json"
}

# Runs the warmer. stdout captured; rc discarded (3 is the ordinary "something unread" code).
run_pf() {
  ENGINE_SCRIPTS_DIR="$STUBS" bash "$SUT_ABS" "$TEST_SESSION" "$@" 2>/dev/null || true
}

# row NAME <<< output — the one rendered row for a source, or "" if the row is missing.
row() { echo "$2" | awk -v n="$1" '$2 == n {print; exit}'; }

# ── GUARD: a source that could not be read is UNREAD, never empty ───────────────
# The arms hold stdout identical (both stubs print nothing) and differ ONLY in the exit code.
# With the guard broken (an `|| true` around the call) both would read OK and UNREAD-02 reds.
test_unread_vs_empty_rc0() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub open-asks 0
  local out; out=$(run_pf)
  assert_contains "OK      asks" "$out" "UNREAD-01: a tool that exits 0 with no output is OK with a zero value"
  assert_contains "open=0" "$out" "UNREAD-01b: and its zero is spelled as a value, not as silence"
}
run_test test_unread_vs_empty_rc0

test_unread_vs_empty_rc2() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub open-asks 2
  local out; out=$(run_pf)
  assert_contains "UNREAD  asks" "$out" "UNREAD-02: the SAME empty output with exit 2 is UNREAD"
  assert_contains "open-asks_exit_2" "$out" "UNREAD-02b: and names why it could not be read"
  local footer; footer=$(echo "$out" | awk '/^UNREAD  *[a-z]/ && /NOT read/ {print}')
  assert_contains "asks" "$footer" "UNREAD-02c: the footer that calls them not-read names it"
  assert_contains "NOT read" "$footer" "UNREAD-02d: and says in words that these are not empty"
}
run_test test_unread_vs_empty_rc2

# ── GUARD: exit 3 is a finding, exit 2 is a fault ───────────────────────────────
# Identical stdout in both arms. Only the code differs. Collapse the two and one arm reds.
FIND_ROWS='OPEN ## [A] ❓ Ask a1: x · logpath=/l
OPEN ## [B] ❓ Ask b1: y · logpath=/l'

test_rc3_is_a_finding() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub open-asks 3 "$FIND_ROWS"
  local out; out=$(run_pf)
  assert_contains "OK      asks" "$out" "FINDING-01: exit 3 is a reading with findings, not a fault"
  assert_contains "open=2" "$out" "FINDING-01b: and the findings are counted"
}
run_test test_rc3_is_a_finding

test_rc2_with_rows_is_still_a_fault() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub open-asks 2 "$FIND_ROWS"
  local out; out=$(run_pf)
  assert_contains "UNREAD  asks" "$out" "FINDING-02: exit 2 is a fault even when rows were printed"
}
run_test test_rc2_with_rows_is_still_a_fault

# ── GUARD: row counts anchor on the producing tool's line prefix ────────────────
# This is the pair for the defect that reported 147 stale lanes as zero and 6 unrowed decisions
# as 7. Arm 01 carries a header line that MENTIONS the token mid-line; arm 02 does not. Both must
# count 1. Unanchor the match and 01 counts 2 and reds while 02 stays green.
test_anchored_count_ignores_header_mention() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub sweep-check 3 'claim: temporal only. UNROWED = no register block was written after it.
UNROWED  L41  some decision  [no register block after it]'
  local out; out=$(run_pf)
  assert_contains "certainly_unrowed=1" "$out" "ANCHOR-01: a mid-line mention in the tool's own header is not a finding"
}
run_test test_anchored_count_ignores_header_mention

test_anchored_count_without_header() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub sweep-check 3 'UNROWED  L41  some decision  [no register block after it]'
  local out; out=$(run_pf)
  assert_contains "certainly_unrowed=1" "$out" "ANCHOR-02: the control — the same single row with no header still counts 1"
}
run_test test_anchored_count_without_header

# ── GUARD: the expensive tier never runs on the cheap path ─────────────────────
# The arms differ ONLY in the --refresh-digest flag, and the evidence is the stub's sentinel.
# This is the guard that keeps a 22-41s scan off a synchronous path.
test_lane_stall_not_invoked_on_cheap_path() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  run_pf >/dev/null
  assert_file_not_exists "$SENTINELS/lane-stall" "TIER-01: a plain run never invokes lane-stall"
}
run_test test_lane_stall_not_invoked_on_cheap_path

test_lane_stall_invoked_on_refresh() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  run_pf --refresh-digest >/dev/null
  assert_file_exists "$SENTINELS/lane-stall" "TIER-02: the control — --refresh-digest does invoke it"
}
run_test test_lane_stall_invoked_on_refresh

# write_digest READ_AT VALUE_JSON — a one-entry digest holding only `lanes`.
write_digest() {
  local readAt="$1" value="$2"
  mkdir -p "$TEST_SESSION/.next-prefetch"
  jq -n --argjson r "$readAt" --argjson v "$value" \
    '{writtenAt:$r, writtenAtIso:"x", entries:[{name:"lanes",status:"OK",reason:"",value:$v,tookMs:10,readAt:$r}]}' \
    > "$TEST_SESSION/.next-prefetch/digest.json"
}

# ── GUARD: an absent digest is UNREAD, not an absent row ───────────────────────
test_missing_digest_is_unread() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  rm -f "$TEST_SESSION/.next-prefetch/digest.json"
  local out; out=$(run_pf)
  assert_contains "UNREAD  lanes" "$out" "NODIGEST-01: with no digest the lane slot is UNREAD"
  assert_contains "no_digest" "$out" "NODIGEST-01b: and says the digest is what is missing"
}
run_test test_missing_digest_is_unread

test_present_digest_is_read() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  write_digest "$(date +%s)" '"stalled=3 at=/x"'
  local out; out=$(run_pf)
  assert_contains "OK      lanes" "$out" "NODIGEST-02: the control — a present digest reads OK"
  assert_not_contains "no_digest" "$out" "NODIGEST-02b: and the no_digest reason is gone"
}
run_test test_present_digest_is_read

# ── GUARD: a digest entry past the staleness bound is labelled, not dropped ────
# The arms differ ONLY in readAt. Drop the age comparison and STALE-02 reds; drop the value from
# the stale branch and STALE-02b reds.
test_fresh_digest_entry_is_ok() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", digestStaleMinutes: 30}'
  : > "$TEST_SESSION/L_LOG.md"
  write_digest "$(date +%s)" '"stalled=3 at=/x"'
  local out; out=$(run_pf)
  assert_contains "OK      lanes" "$out" "STALE-01: an entry inside the bound is OK"
  assert_not_contains "STALE   lanes" "$out" "STALE-01b: and is not labelled stale"
}
run_test test_fresh_digest_entry_is_ok

test_old_digest_entry_is_stale_but_kept() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", digestStaleMinutes: 30}'
  : > "$TEST_SESSION/L_LOG.md"
  write_digest "$(( $(date +%s) - 7200 ))" '"stalled=3 at=/x"'
  local out; out=$(run_pf)
  assert_contains "STALE   lanes" "$out" "STALE-02: an entry past the bound is labelled STALE"
  assert_contains "stalled=3" "$out" "STALE-02b: and its value is KEPT, not dropped"
  assert_contains "2h0m" "$out" "STALE-02c: and it states its own age"
}
run_test test_old_digest_entry_is_stale_but_kept

# ── GUARD: a slot the digest was written without is UNREAD, not omitted ────────
test_slot_absent_from_digest() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  write_digest "$(date +%s)" '"stalled=3 at=/x"'   # holds `lanes` only
  local out; out=$(run_pf)
  assert_contains "absent_from_digest" "$out" "SLOTGAP-01: a slot the digest lacks is UNREAD with its own reason"
  assert_contains "UNREAD  tickets" "$out" "SLOTGAP-01b: and the row is present rather than omitted"
}
run_test test_slot_absent_from_digest

test_slot_present_in_digest() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  local now; now=$(date +%s)
  mkdir -p "$TEST_SESSION/.next-prefetch"
  jq -n --argjson r "$now" '{writtenAt:$r,writtenAtIso:"x",entries:[
     {name:"lanes",status:"OK",reason:"",value:"stalled=3",tookMs:1,readAt:$r},
     {name:"tickets",status:"OK",reason:"",value:"hits=4",tookMs:1,readAt:$r},
     {name:"rag_sessions",status:"OK",reason:"",value:"hits=2",tookMs:1,readAt:$r}]}' \
    > "$TEST_SESSION/.next-prefetch/digest.json"
  local out; out=$(run_pf)
  assert_not_contains "absent_from_digest" "$out" "SLOTGAP-02: the control — a complete digest leaves no gap"
  assert_contains "hits=4" "$out" "SLOTGAP-02b: and each slot's value comes through"
}
run_test test_slot_present_in_digest

# ── GUARD: no owner means NOT SEARCHED, and nothing is searched unscoped ──────
# The arms differ ONLY in whether prefetch.owner is set. The evidence is both the row AND the
# ticket-search stub's sentinel: a guard that printed the right row but still ran the search
# unscoped would pass on output alone, so OWNER-01b is the one that actually binds it.
test_absent_owner_does_not_search() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf --refresh-digest)
  assert_contains "owner_unset" "$out" "OWNER-01: no owner is reported as not-searched, with the reason"
  assert_file_not_exists "$SENTINELS/ticket-search" "OWNER-01b: and no unscoped search was run"
  assert_contains "owner=UNSET" "$out" "OWNER-01c: the config header says the seat is unknown"
}
run_test test_absent_owner_does_not_search

test_present_owner_searches_scoped() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", owner: "yarik", team: "FIN"}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf --refresh-digest)
  assert_file_exists "$SENTINELS/ticket-search" "OWNER-02: the control — a configured owner does run the search"
  assert_contains "yarik" "$(cat "$SENTINELS/ticket-search.args" 2>/dev/null)" \
    "OWNER-02b: and the seat is passed to it, so the search is scoped"
  assert_not_contains "owner_unset" "$out" "OWNER-02c: and the not-searched reason is gone"
}
run_test test_present_owner_searches_scoped

# ── GUARD: the repo comes from config, not from the engine root or the cwd ────
# Two real git repos whose ONLY difference is the branch name. Ignore the config and both arms
# report the same thing and one reds.
test_repo_from_config_a() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf)
  assert_contains "branch=branch-a" "$out" "REPO-01: git readings are taken in the configured repo"
}
run_test test_repo_from_config_a

test_repo_from_config_b() {
  local repo_b="$TMP_DIR/repo-b"
  make_repo "$repo_b" branch-b
  write_state ' | .prefetch = {repo: "'"$repo_b"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf)
  assert_contains "branch=branch-b" "$out" "REPO-02: a different configured repo moves the readings there"
  assert_not_contains "branch=branch-a" "$out" "REPO-02b: and the first repo is not read"
}
run_test test_repo_from_config_b

test_unresolvable_repo_is_unread() {
  write_state ' | .prefetch = {repo: "'"$TMP_DIR"'/nope", log: "'"$TEST_SESSION"'/L_LOG.md"} | .directoriesOfInterest = []'
  : > "$TEST_SESSION/L_LOG.md"
  cd "$TMP_DIR"
  local out; out=$(run_pf)
  # TMP_DIR is not a git repo, so no fallback can resolve one.
  if echo "$out" | grep -q "repo_unresolved" || echo "$out" | grep -q "branch="; then
    pass "REPO-03: an unresolvable repo is either UNREAD or honestly reports the fallback it found"
  else
    fail "REPO-03: an unresolvable repo is either UNREAD or honestly reports the fallback it found" \
      "repo_unresolved or a branch= row" "$out"
  fi
}
run_test test_unresolvable_repo_is_unread

# ── GUARD: no upstream is UNREAD, never ahead=0 ───────────────────────────────
# A branch tracking nothing has an UNKNOWABLE divergence. Reporting it as zero is the exact
# empty-for-unread confusion, in the source where it is most tempting.
test_no_upstream_is_unread() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf)
  assert_contains "no_upstream" "$out" "UPSTREAM-01: a branch tracking nothing is UNREAD"
  assert_not_contains "ahead=0 behind=0" "$out" "UPSTREAM-01b: and is NOT reported as zero divergence"
}
run_test test_no_upstream_is_unread

test_with_upstream_reports_divergence() {
  local up="$TMP_DIR/repo-up"
  git clone -q "$REPO_A" "$up" 2>/dev/null
  git -C "$up" config user.email t@t.t; git -C "$up" config user.name t
  echo two > "$up/g.txt"; git -C "$up" add -A; git -C "$up" commit -qm second
  write_state ' | .prefetch = {repo: "'"$up"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf)
  assert_contains "ahead=1" "$out" "UPSTREAM-02: the control — a tracked branch reports its real divergence"
  assert_not_contains "no_upstream" "$out" "UPSTREAM-02b: and the not-read reason is gone"
}
run_test test_with_upstream_reports_divergence

# ── GUARD: a source that overruns its budget is UNREAD, not a hang, not empty ─
# The arms differ ONLY in how long the stub takes. Remove the bound and BUDGET-01 either hangs
# or reports OK, and reds either way.
test_slow_source_times_out_as_unread() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", sourceBudgetSeconds: 1}'
  : > "$TEST_SESSION/L_LOG.md"
  slow_stub open-asks 5
  local out; out=$(run_pf)
  assert_contains "UNREAD  asks" "$out" "BUDGET-01: a source past its budget is UNREAD"
  assert_contains "timeout after 1s" "$out" "BUDGET-01b: and names the bound it broke"
}
run_test test_slow_source_times_out_as_unread

test_fast_source_under_same_budget() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", sourceBudgetSeconds: 1}'
  : > "$TEST_SESSION/L_LOG.md"
  slow_stub open-asks 0
  local out; out=$(run_pf)
  assert_contains "OK      asks" "$out" "BUDGET-02: the control — the same stub under the same budget, only quick, is OK"
}
run_test test_fast_source_under_same_budget

# ── GUARD: the whole cheap tier's budget is configurable and exhaustion is named ─
test_zero_cheap_budget_names_exhaustion() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", cheapBudgetSeconds: 0}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf)
  assert_contains "budget_exhausted" "$out" "CAP-01: an exhausted cheap budget names the sources it skipped"
  assert_file_not_exists "$SENTINELS/open-asks" "CAP-01b: and they really were not attempted"
}
run_test test_zero_cheap_budget_names_exhaustion

test_ample_cheap_budget_reads_everything() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", cheapBudgetSeconds: 60}'
  : > "$TEST_SESSION/L_LOG.md"
  local out; out=$(run_pf)
  assert_not_contains "budget_exhausted" "$out" "CAP-02: the control — an ample budget skips nothing"
  assert_file_exists "$SENTINELS/open-asks" "CAP-02b: and every cheap source really ran"
}
run_test test_ample_cheap_budget_reads_everything

# ── GUARD: read-only ───────────────────────────────────────────────────────────
# The control is inside the test: the run MUST have written its own cache (so the check is not
# passing because nothing happened) and MUST have left the work repo's git state untouched.
test_read_only_outside_its_cache() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md", owner: "yarik"}'
  : > "$TEST_SESSION/L_LOG.md"
  local git_before git_after head_before head_after before after
  git_before=$(git -C "$REPO_A" status --porcelain)
  head_before=$(git -C "$REPO_A" rev-parse HEAD)
  before=$(find "$TEST_SESSION" -not -path "*/.next-prefetch*" | sort)
  run_pf --refresh-digest >/dev/null
  git_after=$(git -C "$REPO_A" status --porcelain)
  head_after=$(git -C "$REPO_A" rev-parse HEAD)
  after=$(find "$TEST_SESSION" -not -path "*/.next-prefetch*" | sort)
  assert_eq "$git_before" "$git_after" "RO-01: the work repo's tree is untouched"
  assert_eq "$head_before" "$head_after" "RO-02: and its HEAD is untouched"
  assert_eq "$before" "$after" "RO-03: nothing was created outside the cache directory"
  assert_file_exists "$TEST_SESSION/.next-prefetch/digest.json" \
    "RO-04: the control — the run DID write its own digest, so RO-01..03 are not vacuous"
}
run_test test_read_only_outside_its_cache

# ── GUARD: the JSON view agrees with the text view ────────────────────────────
test_json_names_the_unread() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub open-asks 2
  local out; out=$(run_pf --json)
  # Embedding the output in a shell string would break on any apostrophe in a reason, so the
  # JSON goes through a file.
  printf '%s' "$out" > "$TMP_DIR/out.json"
  assert_ok "JSON-01: --json emits valid JSON" jq -e . "$TMP_DIR/out.json"
  assert_contains "asks" "$(printf '%s' "$out" | jq -r '.unread[]' 2>/dev/null)" \
    "JSON-02: and the unread list names the source that could not be read"
}
run_test test_json_names_the_unread

test_json_omits_the_read() {
  write_state ' | .prefetch = {repo: "'"$REPO_A"'", log: "'"$TEST_SESSION"'/L_LOG.md"}'
  : > "$TEST_SESSION/L_LOG.md"
  stub open-asks 0
  local out; out=$(run_pf --json)
  assert_not_contains '"asks"' "$(printf '%s' "$out" | jq -c '.unread' 2>/dev/null)" \
    "JSON-03: the control — a source that WAS read is not in the unread list"
}
run_test test_json_omits_the_read

exit_with_results
