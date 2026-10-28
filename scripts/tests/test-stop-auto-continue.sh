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
# The atom the reason cites, read from the same tree as the hook under test.
ENGINE_UNDER_TEST="${STOP_ENGINE_UNDER_TEST:-$(cd "$(dirname "$REAL_HOOK")/.." && pwd)}"
ATOM_FILE="$ENGINE_UNDER_TEST/.directives/commands/CMD_CONTINUE_ON_STOP.md"
COMMANDS_FILE="$ENGINE_UNDER_TEST/.directives/COMMANDS.md"

setup() {
  setup_test_env "test_stop_ac"
  mkdir -p "$FAKE_HOME/.claude/engine/hooks"
  ln -sf "$REAL_HOOK" "$FAKE_HOME/.claude/engine/hooks/stop-auto-continue.sh"
  HOOK="$FAKE_HOME/.claude/engine/hooks/stop-auto-continue.sh"

  # PROJECT_SLUG is derived from $PWD, which setup_test_env set to TMP_DIR.
  PROJ_DIR="$FAKE_HOME/.claude/projects/$(echo "$PWD" | sed 's|/|-|g')"
  mkdir -p "$PROJ_DIR"

  # Lay the atom out the way production does: the real file under engine/.directives,
  # reached through the ~/.claude/.directives symlink the hook names. normalize_preload_path
  # only resolves that symlink for a file that EXISTS, so without this the PRELOAD arms
  # match an incidental spelling production never queues.
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  cp "$ATOM_FILE" "$FAKE_HOME/.claude/engine/.directives/commands/CMD_CONTINUE_ON_STOP.md"
  ln -sfn "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"
  ATOM_RESOLVED="$(cd "$FAKE_HOME/.claude/engine/.directives/commands" && pwd -P)/CMD_CONTINUE_ON_STOP.md"
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

# Two complaints, one arm. First: woken agents answered "nothing to advance until you
# answer my questions" instead of asking. Then, once they asked, they hand-rolled the
# question instead of dispatching the skill that owns it — which is the substitution a
# loom forbids for /interrogate and which cost this programme a fork left unasked for
# hours. So the wake must route BOTH ways by the boundary the skills themselves declare:
# gathers information -> /interrogate, unblocks work -> /decide.
# The full guidance moved out of the reason into §CMD_CONTINUE_ON_STOP, so the arm now
# asserts it twice: the two-line reason still names both routes, and the atom it cites
# still carries every clause the long reason used to, unweakened.
test_prompt_routes_questions_to_their_skill() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  if [[ "$out" == *"/interrogate"* ]] && [[ "$out" == *"/decide"* ]] && [[ "$out" == *"never a hand-rolled ask"* ]]; then
    pass "ASK-01: the wake routes a pending question to /interrogate or /decide, never a hand-rolled ask"
  else
    fail "ASK-01: the wake routes a pending question to /interrogate or /decide, never a hand-rolled ask" \
      "a reason routing to /interrogate or /decide, and refusing a hand-rolled ask" "$out"
  fi
}
run_test test_prompt_routes_questions_to_their_skill

test_atom_carries_the_whole_guidance() {
  local atom; atom=$(cat "$ATOM_FILE" 2>/dev/null || true)
  local missing="" clause
  for clause in \
    '### ¶CMD_CONTINUE_ON_STOP' \
    '## PROOF FOR §CMD_CONTINUE_ON_STOP' \
    'part-way through the sequence it named, carry on with its next step' \
    '`🔓 Open claims`, `📚 Docs owed` or `🗳️ Boards`' \
    'Otherwise invoke `/next`' \
    'blocking-first' \
    'do NOT hand-roll an `AskUserQuestion`' \
    'GATHERS INFORMATION** is `/interrogate`' \
    'UNBLOCKS WORK** — a decision only they can make — is `/decide`' \
    'waiting on your answers' \
    'which is the substitution a loom forbids' \
    'Do not manufacture work' \
    'say so in one line and stop'; do
    [[ "$atom" == *"$clause"* ]] || missing="$missing [$clause]"
  done
  if [ -z "$missing" ]; then
    pass "ATOM-01: CMD_CONTINUE_ON_STOP.md carries every clause the long reason carried"
  else
    fail "ATOM-01: CMD_CONTINUE_ON_STOP.md carries every clause the long reason carried" \
      "all clauses present in $ATOM_FILE" "missing:$missing"
  fi
}
run_test test_atom_carries_the_whole_guidance

test_atom_is_registered() {
  if grep -qF '### [¶CMD_CONTINUE_ON_STOP](commands/CMD_CONTINUE_ON_STOP.md)' "$COMMANDS_FILE"; then
    pass "ATOM-02: COMMANDS.md registers the atom, so its summary rides the SessionStart preload"
  else
    fail "ATOM-02: COMMANDS.md registers the atom, so its summary rides the SessionStart preload" \
      "a ### [¶CMD_CONTINUE_ON_STOP](commands/...) entry" "none in $COMMANDS_FILE"
  fi
}
run_test test_atom_is_registered

# ── The reason is short and cites the atom ──────────────────────────────────
# The operator's ask: at most two lines, naming the §CMD_ atom the way the ticket-watch
# gate names §CMD_DRAIN_TICKET_QUEUE_ON_WAKE. Line 2 is the counter suffix, whose
# "auto-continues;" text Guard 3b reads back, so SHAPE-02 pins it to its own line.
test_reason_is_two_lines_citing_atom() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out reason lines
  out=$(run_hook)
  reason=$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)
  lines=$(printf '%s\n' "$reason" | wc -l | tr -d ' ')
  if [ -n "$reason" ] && [ "$lines" -le 2 ] && [[ "$reason" == *'§CMD_CONTINUE_ON_STOP'* ]]; then
    pass "SHAPE-01: the reason is at most 2 lines and cites §CMD_CONTINUE_ON_STOP"
  else
    fail "SHAPE-01: the reason is at most 2 lines and cites §CMD_CONTINUE_ON_STOP" \
      "<=2 lines containing §CMD_CONTINUE_ON_STOP" "$lines line(s): $reason"
  fi
  local second; second=$(printf '%s\n' "$reason" | sed -n 2p)
  if [[ "$second" == "(1 of 3 auto-continues; "* ]]; then
    pass "SHAPE-02: line 2 is the intact counter suffix Guard 3b reads back"
  else
    fail "SHAPE-02: line 2 is the intact counter suffix Guard 3b reads back" \
      "(1 of 3 auto-continues; ..." "$second"
  fi
}
run_test test_reason_is_two_lines_citing_atom

# ── The cited atom reaches the agent ────────────────────────────────────────
# A cited atom that is not preloaded is a citation to nothing. The pair differs ONLY in
# whether preloadedFiles already holds the atom: PRELOAD-01 queues it, PRELOAD-02 does
# not re-queue it — so PRELOAD-01 cannot pass on a hook that queues blindly or not at all.
# Both match the path normalize_preload_path RESOLVES the hook's ~/.claude/.directives
# spelling to (engine/.directives, through the symlink setup lays down), which is the path
# preloadedFiles holds in production and the one its dedup compares against.
test_block_queues_atom_for_preload() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  run_hook >/dev/null
  local got; got=$(jq -r '[.pendingPreloads // [] | .[] | select(endswith("/commands/CMD_CONTINUE_ON_STOP.md"))] | join(",")' "$TEST_SESSION/.state.json")
  assert_eq "$ATOM_RESOLVED" "$got" "PRELOAD-01: a block queues the cited atom, at its resolved engine path"
}
run_test test_block_queues_atom_for_preload

test_already_preloaded_atom_not_requeued() {
  write_state " | .preloadedFiles = [\"$ATOM_RESOLVED\"]"
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  local n; n=$(jq '[.pendingPreloads // [] | .[]] | length' "$TEST_SESSION/.state.json")
  if [[ "$out" == *"block"* ]] && [ "$n" = "0" ]; then
    pass "PRELOAD-02: an atom already in context is not queued again (and the hook still blocks)"
  else
    fail "PRELOAD-02: an atom already in context is not queued again (and the hook still blocks)" \
      "a block and 0 pending" "pending=$n out=$out"
  fi
}
run_test test_already_preloaded_atom_not_requeued

# ── The delivered atom must not become Guard 3b's anchor ────────────────────
# The preload rule delivers the atom as a PostToolUse attachment, i.e. AFTER the wake's
# first tool_use. Guard 3b anchors on the LAST line carrying "auto-continues;" and counts
# tool calls after it, so an atom quoting that text resets the series after a wake that did
# exactly one useful call. The pair differs ONLY in whether the delivery line is present;
# BACKOFF-05 is built from the atom file itself, so it reddens on the text, not a fixture.
backoff_transcript() {  # $1 = include the atom's PostToolUse delivery (yes/no)
  local f="$PROJ_DIR/mine.jsonl"
  jq -cn --arg r "Follow §CMD_CONTINUE_ON_STOP ...
(1 of 3 auto-continues; set ...)" '{type:"user",message:{content:$r}}' > "$f"
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}' >> "$f"
  echo '{"type":"user","message":{"content":[{"type":"tool_result"}]}}' >> "$f"
  if [ "$1" = yes ]; then
    jq -cn --rawfile c "$ATOM_FILE" --arg p "$ATOM_RESOLVED" \
      '{type:"attachment",attachment:{type:"hook_additional_context",hookEvent:"PostToolUse",content:("[Preloaded: "+$p+"]\n"+$c)}}' >> "$f"
  fi
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done one step"}]}}' >> "$f"
}

test_one_call_wake_continues_without_atom() {
  write_state ' | .autoContinueCount = 1'
  backoff_transcript no
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "BACKOFF-06: a one-call wake continues (the control, no atom delivered)"
  else
    fail "BACKOFF-06: a one-call wake continues (the control, no atom delivered)" "a block decision" "$out"
  fi
}
run_test test_one_call_wake_continues_without_atom

test_one_call_wake_continues_after_atom_delivery() {
  write_state ' | .autoContinueCount = 1'
  backoff_transcript yes
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "BACKOFF-05: a one-call wake still continues after the atom was delivered behind it"
  else
    fail "BACKOFF-05: a one-call wake still continues after the atom was delivered behind it" \
      "a block decision" "empty: Guard 3b anchored on the atom (count=$(jq .autoContinueCount "$TEST_SESSION/.state.json"))"
  fi
}
run_test test_one_call_wake_continues_after_atom_delivery

exit_with_results
