#!/bin/bash
# test-stop-auto-continue.sh — Tests for the loom-aware Stop hook.
#
# The arms that matter are TRANSCRIPT-01/02: the hook must tail THIS session's
# transcript, not the most recently modified one in a project directory several
# sessions share. They are written as a pair that differs only in which file
# carries the AskUserQuestion, so neither can pass vacuously.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

REAL_HOOK="${STOP_HOOK_UNDER_TEST:-$HOME/.claude/engine/hooks/stop-auto-continue.sh}"

setup() {
  setup_test_env "test_stop_ac"
  mkdir -p "$FAKE_HOME/.claude/engine/hooks"
  ln -sf "$REAL_HOOK" "$FAKE_HOME/.claude/engine/hooks/stop-auto-continue.sh"
  HOOK="$FAKE_HOME/.claude/engine/hooks/stop-auto-continue.sh"

  # PROJECT_SLUG is derived from $PWD, which setup_test_env set to TMP_DIR.
  PROJ_DIR="$FAKE_HOME/.claude/projects/$(echo "$PWD" | sed 's|/|-|g')"
  mkdir -p "$PROJ_DIR"
}

teardown() { cleanup_test_env; }

# Writes the session state. $1 = extra jq assignments (may be empty).
write_state() {
  local extra="${1:-}"
  jq -n --arg k "mine.jsonl" '{
    pid: 99999999, lifecycle: "active", skill: "loom",
    currentPhase: "1: Loom", primaryTranscriptKey: $k
  }'"$extra" > "$TEST_SESSION/.state.json"
}

run_hook() { echo '{}' | bash "$HOOK" 2>/dev/null || true; }

# ── The toggle ──────────────────────────────────────────────────────────────
test_default_on_blocks() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  if [[ "$out" == *'"decision"'* ]] && [[ "$out" == *"block"* ]]; then
    pass "TOGGLE-01: absent autoContinue defaults ON and blocks"
  else
    fail "TOGGLE-01: absent autoContinue defaults ON and blocks" "a block decision" "$out"
  fi
}
run_test test_default_on_blocks

test_explicit_false_is_off() {
  write_state ' | .autoContinue = false'
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "TOGGLE-02: a literal false turns it off (jq falsy trap)"
}
run_test test_explicit_false_is_off

# ── The ceiling ─────────────────────────────────────────────────────────────
test_ceiling_stops_and_resets() {
  write_state ' | .autoContinueCount = 3 | .autoContinueMax = 3'
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "CEILING-01: at the ceiling the hook stops"
  assert_eq "0" "$(jq -r '.autoContinueCount' "$TEST_SESSION/.state.json")" \
    "CEILING-02: reaching the ceiling resets the counter"
}
run_test test_ceiling_stops_and_resets

test_counter_increments_on_block() {
  write_state ' | .autoContinueCount = 1'
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  run_hook >/dev/null
  assert_eq "2" "$(jq -r '.autoContinueCount' "$TEST_SESSION/.state.json")" \
    "CEILING-03: a block increments the consecutive counter"
}
run_test test_counter_increments_on_block

# ── Guard 3 reads THIS session's transcript ─────────────────────────────────
# The pair below differs ONLY in which file holds the AskUserQuestion. Before the
# selector named primaryTranscriptKey, both arms read the newest file and so both
# suppressed — TRANSCRIPT-01 is the arm that goes red on a regression.
test_reads_own_transcript_not_newest() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  sleep 1
  echo '{"name":"AskUserQuestion"}' > "$PROJ_DIR/sibling.jsonl"   # newer, another session
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "TRANSCRIPT-01: a sibling session's newer AskUserQuestion does not suppress"
  else
    fail "TRANSCRIPT-01: a sibling session's newer AskUserQuestion does not suppress" \
      "a block decision" "$out"
  fi
}
run_test test_reads_own_transcript_not_newest

test_own_transcript_tail_suppresses() {
  write_state
  echo '{"name":"AskUserQuestion"}' > "$PROJ_DIR/mine.jsonl"
  sleep 1
  echo '{"type":"assistant"}' > "$PROJ_DIR/sibling.jsonl"          # newer, benign
  local out; out=$(run_hook)
  assert_empty "$out" "TRANSCRIPT-02: this session's own AskUserQuestion does suppress"
}
run_test test_own_transcript_tail_suppresses

# Without a key there is no way to tell a turn that did work from one that woke,
# found nothing and said so — and the ceiling is not an answer to that, it only caps
# how many times we ask. The hook fails CLOSED. This arm replaces an earlier one that
# asserted the opposite; the newest-by-mtime fallback it protected is what let a
# sibling session's turn be read as this one's.
test_missing_key_fails_closed() {
  jq -n '{pid: 99999999, lifecycle: "active", skill: "loom", currentPhase: "1: Loom"}' \
    > "$TEST_SESSION/.state.json"
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "TRANSCRIPT-03: no primaryTranscriptKey stops rather than guessing"
}
run_test test_missing_key_fails_closed

# ── The transcript is resolved by NAME, not by the cwd's slug ───────────────
# A seat working in a worktree has a cwd whose slug names a project directory that
# does not exist. Deriving the directory from $PWD skipped every guard below it, so
# the hook injected on every stop up to the ceiling with nothing to show it had never
# run. The pair differs only in WHERE the transcript lives.
#
# CWD-02 is the binding arm, and the plant is what established that rather than the
# reasoning: restoring the cwd-derived resolution reddens CWD-02 ALONE. CWD-01 expects
# silence, and a hook that cannot resolve the key is silent too — so it passes
# vacuously under exactly the defect it was written for. It still covers the
# suppression path; it just cannot be the regression arm, which is why the pair exists.
test_resolves_transcript_outside_cwd_slug() {
  write_state
  local elsewhere="$FAKE_HOME/.claude/projects/-Some-Other-Project"
  mkdir -p "$elsewhere"
  echo '{"name":"AskUserQuestion"}' > "$elsewhere/mine.jsonl"
  rm -rf "$PROJ_DIR"                      # the cwd-derived directory does not exist
  local out; out=$(run_hook)
  assert_empty "$out" "CWD-01: a transcript outside the cwd's slug is still found and still suppresses"
  mkdir -p "$PROJ_DIR"
}
run_test test_resolves_transcript_outside_cwd_slug

# CWD-02 is its discriminating pair: same absent slug directory, same resolution by
# name, benign content. It must still reach a decision — so CWD-01's silence is the
# marker being seen, not the hook failing closed on a key it could not resolve.
test_resolution_by_name_still_decides() {
  write_state
  local elsewhere="$FAKE_HOME/.claude/projects/-Some-Other-Project"
  mkdir -p "$elsewhere"
  echo '{"type":"assistant"}' > "$elsewhere/mine.jsonl"
  rm -rf "$PROJ_DIR"
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "CWD-02: a benign transcript outside the cwd's slug still reaches a decision"
  else
    fail "CWD-02: a benign transcript outside the cwd's slug still reaches a decision" \
      "a block decision" "$out"
  fi
  mkdir -p "$PROJ_DIR"
}
run_test test_resolution_by_name_still_decides

# ── An inactive session has nothing to continue ─────────────────────────────
test_idle_session_noop() {
  write_state ' | .lifecycle = "idle"'
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "LIFECYCLE-01: a non-active session is a no-op"
}
run_test test_idle_session_noop


# ── Guard 3b: a wake that accomplished nothing must not be repeated ──────────
# The pair differs ONLY in whether a tool_use follows our own injection. If the
# guard works, both arms flip; if it is dead, both arms block and BACKOFF-01 reds.
test_backoff_when_last_wake_did_nothing() {
  write_state
  {
    echo '{"type":"user","content":"(1 of 3 auto-continues; set autoContinue false)"}'
    echo '{"type":"assistant","content":"Nothing to advance until the perf run reports back."}'
  } > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "BACKOFF-01: a wake that produced no tool call is not repeated"
  assert_eq "0" "$(jq -r '.autoContinueCount' "$TEST_SESSION/.state.json")" \
    "BACKOFF-02: backing off resets the counter"
}
run_test test_backoff_when_last_wake_did_nothing

test_no_backoff_when_last_wake_worked() {
  write_state
  {
    echo '{"type":"user","content":"(1 of 3 auto-continues; set autoContinue false)"}'
    echo '{"type":"assistant","content":[{"type":"tool_use","name":"Bash"}]}'
    echo '{"type":"assistant","content":"Committed the four paths."}'
  } > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "BACKOFF-03: a wake that DID work still gets a next one (the control)"
  else
    fail "BACKOFF-03: a wake that DID work still gets a next one (the control)" "a block decision" "$out"
  fi
}
run_test test_no_backoff_when_last_wake_worked


# The regression the operator caught: with SEVERAL injections in the window, a tool call
# made after an EARLY one must not mask an idle turn after the LATEST one.
test_backoff_anchors_on_last_injection() {
  write_state
  {
    echo '{"type":"user","content":"(1 of 3 auto-continues; set autoContinue false)"}'
    echo '{"type":"assistant","content":[{"type":"tool_use","name":"Bash"}]}'
    echo '{"type":"user","content":"(2 of 3 auto-continues; set autoContinue false)"}'
    echo '{"type":"assistant","content":"Nothing to advance."}'
    echo '{"type":"user","content":"(3 of 3 auto-continues; set autoContinue false)"}'
    echo '{"type":"assistant","content":"Still nothing to advance."}'
  } > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "BACKOFF-04: an early tool call does not mask an idle turn after the LAST injection"
}
run_test test_backoff_anchors_on_last_injection

exit_with_results
