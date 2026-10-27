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

test_missing_key_falls_back() {
  jq -n '{pid: 99999999, lifecycle: "active", skill: "loom", currentPhase: "1: Loom"}' \
    > "$TEST_SESSION/.state.json"
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "TRANSCRIPT-03: no primaryTranscriptKey still reaches a decision"
  else
    fail "TRANSCRIPT-03: no primaryTranscriptKey still reaches a decision" "a block decision" "$out"
  fi
}
run_test test_missing_key_falls_back

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

exit_with_results
