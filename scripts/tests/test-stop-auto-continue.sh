#!/bin/bash
# test-stop-auto-continue.sh — Tests for the loom-aware Stop hook.
#
# The arms that matter are TRANSCRIPT-01/02: the hook must tail THIS session's
# transcript, not the most recently modified one in a project directory several
# sessions share. They are written as a pair that differs only in which file
# carries the AskUserQuestion, so neither can pass vacuously.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

# Defaults to the hook in the tree this suite lives in, so the hook and the COMMANDS.md it
# cites are read from one tree; STOP_HOOK_UNDER_TEST points it elsewhere.
REAL_HOOK="${STOP_HOOK_UNDER_TEST:-$(cd "$(dirname "$0")/../.." && pwd)/hooks/stop-auto-continue.sh}"
# The atom the reason cites is the ¶CMD_CONTINUE_ON_STOP section of COMMANDS.md, read from the
# same tree as the hook under test. COMMANDS.md is the file the hook preloads and the one that
# lands in the transcript, so the anchor checks read all of it; the clause checks read the section.
ENGINE_UNDER_TEST="${STOP_ENGINE_UNDER_TEST:-$(cd "$(dirname "$REAL_HOOK")/.." && pwd)}"
COMMANDS_FILE="$ENGINE_UNDER_TEST/.directives/COMMANDS.md"
ATOM_FILE="$COMMANDS_FILE"
atom_section() { awk '/^### ¶CMD_CONTINUE_ON_STOP$/{f=1;print;next} f&&/^### /{exit} f' "$COMMANDS_FILE"; }

setup() {
  setup_test_env "test_stop_ac"
  mkdir -p "$FAKE_HOME/.claude/engine/hooks"
  ln -sf "$REAL_HOOK" "$FAKE_HOME/.claude/engine/hooks/stop-auto-continue.sh"
  HOOK="$FAKE_HOME/.claude/engine/hooks/stop-auto-continue.sh"

  # PROJECT_SLUG is derived from $PWD, which setup_test_env set to TMP_DIR.
  PROJ_DIR="$FAKE_HOME/.claude/projects/$(echo "$PWD" | sed 's|/|-|g')"
  mkdir -p "$PROJ_DIR"

  # Lay COMMANDS.md out the way production does: the real file under engine/.directives,
  # reached through the ~/.claude/.directives symlink the hook names. normalize_preload_path
  # only resolves that symlink for a file that EXISTS, so without this the PRELOAD arms
  # match an incidental spelling production never queues.
  mkdir -p "$FAKE_HOME/.claude/engine/.directives/commands"
  cp "$COMMANDS_FILE" "$FAKE_HOME/.claude/engine/.directives/COMMANDS.md"
  ln -sfn "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"
  ATOM_RESOLVED="$(cd "$FAKE_HOME/.claude/engine/.directives" && pwd -P)/COMMANDS.md"
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
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_q1","name":"AskUserQuestion","input":{}}]}}' > "$PROJ_DIR/sibling.jsonl"   # newer, another session
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
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_q1","name":"AskUserQuestion","input":{}}]}}' > "$PROJ_DIR/mine.jsonl"
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
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_q1","name":"AskUserQuestion","input":{}}]}}' > "$elsewhere/mine.jsonl"
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
  local out reason first missing="" clause
  out=$(run_hook)
  reason=$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)
  first=$(printf '%s\n' "$reason" | sed -n 1p)
  # Operator 02:17: nobody may be at the terminal, so /interrogate and /decide (both
  # AskUserQuestion at this terminal) cannot be the wake's route. The route is an ask
  # addressed up the chain; the two skills survive only as the operator-present exception.
  for clause in \
    '`engine ask new --to <the first word hop.sh target prints: your parent seat, or operator>`' \
    'never a hand-rolled ask' \
    'only for an operator present at this terminal' \
    'never from a seat with a parent'; do
    [[ "$first" == *"$clause"* ]] || missing="$missing [$clause]"
  done
  [[ "$first" == *'route a question for the user to `/interrogate` or `/decide`'* ]] && missing="$missing [old route still present]"
  if [ -z "$missing" ]; then
    pass "ASK-01: line 1 routes an operator-only question to an ask up the chain, /interrogate and /decide only for an operator at this terminal"
  else
    fail "ASK-01: line 1 routes an operator-only question to an ask up the chain, /interrogate and /decide only for an operator at this terminal" \
      "every ask-route clause, and no old route" "missing:$missing :: $first"
  fi
}
run_test test_prompt_routes_questions_to_their_skill

test_atom_carries_the_whole_guidance() {
  local atom; atom=$(atom_section)
  local missing="" clause
  for clause in \
    '### ¶CMD_CONTINUE_ON_STOP' \
    '## PROOF FOR §CMD_CONTINUE_ON_STOP' \
    'part-way through the sequence it named, carry on with its next step' \
    '`🔓 Open claims`, `📚 Docs owed` or `🗳️ Asks`' \
    'Otherwise invoke `/next`' \
    'blocking-first' \
    'do NOT hand-roll an `AskUserQuestion`' \
    '`bash ~/.claude/engine/skills/coordinate/scripts/hop.sh target`' \
    '`engine ask new --to <that target>`' \
    'one-line row under `🔓 Open claims`' \
    'an operator who is present at this terminal' \
    'A seat with a parent never uses them' \
    'waiting on your answers' \
    'which is the substitution a loom forbids' \
    'Do not manufacture work' \
    'say so in one line and stop'; do
    [[ "$atom" == *"$clause"* ]] || missing="$missing [$clause]"
  done
  if [ -z "$missing" ]; then
    pass "ATOM-01: COMMANDS.md's ¶CMD_CONTINUE_ON_STOP section carries every clause the long reason carried"
  else
    fail "ATOM-01: COMMANDS.md's ¶CMD_CONTINUE_ON_STOP section carries every clause the long reason carried" \
      "all clauses present in the section of $COMMANDS_FILE" "missing:$missing"
  fi
}
run_test test_atom_carries_the_whole_guidance

test_atom_is_registered() {
  if grep -qxF '### ¶CMD_CONTINUE_ON_STOP' "$COMMANDS_FILE" \
     && ! grep -qF '](commands/CMD_CONTINUE_ON_STOP.md)' "$COMMANDS_FILE"; then
    pass "ATOM-02: COMMANDS.md defines the atom inline, so all of it rides the SessionStart preload"
  else
    fail "ATOM-02: COMMANDS.md defines the atom inline, so all of it rides the SessionStart preload" \
      "an un-linked ### ¶CMD_CONTINUE_ON_STOP heading and no link to a separate file" "$(grep -n 'CMD_CONTINUE_ON_STOP' "$COMMANDS_FILE" | head -3)"
  fi
}
run_test test_atom_is_registered

# COMMANDS.md, which carries the atom, is in the transcript Guard 3b reads, so no part of it may
# carry the counter fragment; and it names AskUserQuestion/ExitPlanMode only in prose, never in
# the compact form Guard 3 suppresses on or a form an agent could paste as a call.
test_atom_has_no_anchor_or_call_form() {
  local bad=""
  grep -qF 'auto-continues;' "$COMMANDS_FILE" && bad="$bad [auto-continues;]"
  grep -qE 'AskUserQuestion *\(|"name" *: *"(AskUserQuestion|ExitPlanMode)"' "$COMMANDS_FILE" && bad="$bad [AskUserQuestion/ExitPlanMode call form]"
  if [ -z "$bad" ]; then
    pass "ATOM-03: the atom carries no Guard 3b anchor and no AskUserQuestion call form"
  else
    fail "ATOM-03: the atom carries no Guard 3b anchor and no AskUserQuestion call form" "neither" "found:$bad"
  fi
}
run_test test_atom_has_no_anchor_or_call_form

test_commands_entry_names_the_ask_route() {
  local entry; entry=$(atom_section)
  if [[ "$entry" == *'engine ask new --to'* ]] && [[ "$entry" == *'the first word `hop.sh target` prints'* ]] \
     && [[ "$entry" == *'`engine open-asks`'* ]] \
     && [[ "$entry" == *'present at this terminal'* ]] && [[ "$entry" != *'auto-continues;'* ]]; then
    pass "ATOM-04: the COMMANDS.md entry routes an operator-only question to an ask, the skills only for an operator present"
  else
    fail "ATOM-04: the COMMANDS.md entry routes an operator-only question to an ask, the skills only for an operator present" \
      "engine ask new --to, the first word hop.sh target prints, engine open-asks, present at this terminal" "$entry"
  fi
}
run_test test_commands_entry_names_the_ask_route

# Step 4.1 decides who an operator-only question reaches. hop.sh target prints
# "<seat> <pane>", so the whole line as --to files the ask to a seat with a space in its
# name. Its exit 5 sometimes names a usable FLEET_PARENT and sometimes names a seat in a
# stale note that must not be taken (stopmsg2 critique M1/M2). Pin each exit's routing, the
# first-word rule, the broken-hop body, and the two lane/conductor pointer registers.
test_atom_pins_hop_exit_routing() {
  local atom; atom=$(atom_section)
  local missing="" clause
  for clause in \
    'It prints `<seat> <pane>`, or `operator`' \
    'the **first word** of what it prints' \
    '**Exit 0:** that seat.' \
    '**Exit 3:** still that seat' \
    "names \`FLEET_PARENT='<seat>'\`, address that \`<seat>\`" \
    "\`FLEET_PARENT='unset'\`" \
    'Do not take a seat from hop'"'"'s `is stale; using the live @pane_parent` note' \
    '**Exit 2 or 4**' \
    'start the ask'"'"'s body with `broken hop: <hop'"'"'s stderr>`' \
    '`/coordinate` Step 5 still sends every exit 5 to the operator' \
    'A lane logs a `## [TAG] ❓ Ask <id>: …` heading' \
    '`engine open-asks`'; do
    [[ "$atom" == *"$clause"* ]] || missing="$missing [$clause]"
  done
  # The retired wording sent every exit 5 to operator and called the output "your parent seat".
  [[ "$atom" == *'When it prints nothing (exit 2, 4 or 5), address `operator`'* ]] && missing="$missing [old exit-5 rule still present]"
  [[ "$atom" == *'ASK_AUTHOR_GUIDE.md'* ]] && missing="$missing [untracked guide cited]"
  if [ -z "$missing" ]; then
    pass "ATOM-05: step 4.1 routes each hop.sh exit, takes the first word, and starts a non-zero exit's ask with broken hop:"
  else
    fail "ATOM-05: step 4.1 routes each hop.sh exit, takes the first word, and starts a non-zero exit's ask with broken hop:" \
      "every exit-routing clause, no retired rule" "missing:$missing"
  fi
}
run_test test_atom_pins_hop_exit_routing

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
  if [ -n "$reason" ] && [ "$lines" -eq 2 ] && [[ "$(printf '%s\n' "$reason" | sed -n 1p)" == *'§CMD_CONTINUE_ON_STOP'* ]]; then
    pass "SHAPE-01: the reason is exactly 2 lines and line 1 cites §CMD_CONTINUE_ON_STOP"
  else
    fail "SHAPE-01: the reason is exactly 2 lines and line 1 cites §CMD_CONTINUE_ON_STOP" \
      "2 lines, line 1 containing §CMD_CONTINUE_ON_STOP" "$lines line(s): $reason"
  fi
  local second; second=$(printf '%s\n' "$reason" | sed -n 2p)
  local want='(1 of 3 auto-continues; set `autoContinue: false` in .state.json, or the loom Auto-continue disposition to off, to stop.)'
  if [[ "$second" == "$want" ]]; then
    pass "SHAPE-02: line 2 is the counter suffix Guard 3b reads back, byte for byte"
  else
    fail "SHAPE-02: line 2 is the counter suffix Guard 3b reads back, byte for byte" \
      "$want" "$second"
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
  local got; got=$(jq -r '[.pendingPreloads // [] | .[] | select(endswith("/.directives/COMMANDS.md"))] | join(",")' "$TEST_SESSION/.state.json")
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
# BACKOFF-05 delivers the whole of COMMANDS.md, the file that carries the atom, so it reddens on
# the text, not a fixture.
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

# ── Guard 3 walks the turn, not a fixed window ──────────────────────────────
# Real tails, shaped like finch a28d5901 lines 621-630: when the question is the turn's
# LAST call, the harness writes PreToolUse hook lines, the tool_result, PostToolUse lines,
# queue operations, a token reminder and the closing text after it before Stop fires.
# The old `tail -8` lost the call in 9 of 15 measured Stop points. Each fixture below puts
# the call more than 8 lines from the end; the pair G3-01/G3-02 differs ONLY in which
# tool the turn called last.
g3_turn() {  # $1 = name of the turn's last tool call; writes a real-shaped turn tail
  local f="$PROJ_DIR/mine.jsonl" last="$1"
  {
    echo '{"parentUuid":"p0","type":"user","message":{"role":"user","content":"please check the loom and ask me what you need"},"uuid":"u0"}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a1","name":"AskUserQuestion","input":{}}]}}'
    echo '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_a1","type":"tool_result","content":"Your questions have been answered"}]}}'
    echo "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_z9\",\"name\":\"$last\",\"input\":{}}]}}"
    local i; for i in 1 2 3; do
      echo "{\"attachment\":{\"type\":\"hook_success\",\"hookName\":\"PreToolUse:$last\",\"toolUseID\":\"toolu_z9\",\"hookEvent\":\"PreToolUse\",\"content\":\"\"},\"type\":\"attachment\"}"
    done
    echo '{"promptId":"pr1","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_z9","type":"tool_result","content":"done"}]}}'
    echo "{\"attachment\":{\"type\":\"hook_success\",\"hookName\":\"PostToolUse:$last\",\"toolUseID\":\"toolu_z9\",\"hookEvent\":\"PostToolUse\",\"content\":\"\"},\"type\":\"attachment\"}"
    echo '{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>x</task-id>"}'
    echo '{"attachment":{"type":"total_tokens_reminder","text":"<total_tokens>14101031 tokens left</total_tokens>"},"type":"attachment"}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"wrap up"}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I have what I need and wrote it down."}]}}'
    echo '{"type":"queue-operation","operation":"dequeue"}'
  } > "$f"
}

test_g3_question_last_call_long_tail_suppresses() {
  write_state
  g3_turn AskUserQuestion
  local out; out=$(run_hook)
  assert_empty "$out" "G3-01: a question as the turn's last call suppresses, 10 lines from the end"
}
run_test test_g3_question_last_call_long_tail_suppresses

test_g3_other_last_call_still_blocks() {
  write_state
  g3_turn Bash
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "G3-02: an earlier question does not suppress once a later call ends the turn (the control)"
  else
    fail "G3-02: an earlier question does not suppress once a later call ends the turn (the control)" "a block decision" "$out"
  fi
}
run_test test_g3_other_last_call_still_blocks

test_g3_plan_mode_exit_suppresses() {
  write_state
  g3_turn ExitPlanMode
  local out; out=$(run_hook)
  assert_empty "$out" "G3-03: ExitPlanMode as the turn's last call suppresses too"
}
run_test test_g3_plan_mode_exit_suppresses

# A real user prompt starts a new turn: a question answered in the PREVIOUS turn must not
# suppress a turn that made no call at all. The Stop hook's own feedback is isMeta and is
# NOT a new prompt, so a question followed only by that feedback still suppresses.
test_g3_new_prompt_clears_question() {
  write_state
  g3_turn AskUserQuestion
  echo '{"promptId":"pr2","type":"user","message":{"role":"user","content":"thanks, now carry on"},"origin":{"kind":"human"}}' >> "$PROJ_DIR/mine.jsonl"
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."}]}}' >> "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  if [[ "$out" == *"block"* ]]; then
    pass "G3-04: a real user prompt after the question clears it"
  else
    fail "G3-04: a real user prompt after the question clears it" "a block decision" "$out"
  fi
}
run_test test_g3_new_prompt_clears_question

test_g3_meta_feedback_is_not_a_prompt() {
  write_state
  g3_turn AskUserQuestion
  echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nsomething else"}}' >> "$PROJ_DIR/mine.jsonl"
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Noted."}]}}' >> "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "G3-05: Stop-hook feedback (isMeta) is not a new prompt, so the question still suppresses"
}
run_test test_g3_meta_feedback_is_not_a_prompt

# Two harness lines look like prompts and are not. Measured on 15 real Stop points where a
# question was the last call: 6 were REJECTED or interrupted, and the harness then wrote a
# "[Request interrupted by user" line and/or background task-notifications (origin kind
# task-notification) as "type":"user" lines. Counting them as prompts lost all 6.
test_g3_interrupt_marker_is_not_a_prompt() {
  write_state
  g3_turn AskUserQuestion
  echo '{"promptId":"pr3","type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}' >> "$PROJ_DIR/mine.jsonl"
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Understood."}]}}' >> "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "G3-06: the harness's interrupt marker after a rejected question is not a new prompt"
}
run_test test_g3_interrupt_marker_is_not_a_prompt

test_g3_task_notification_is_not_a_prompt() {
  write_state
  g3_turn AskUserQuestion
  echo '{"promptId":"pr4","type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>a1</task-id>"},"origin":{"kind":"task-notification"}}' >> "$PROJ_DIR/mine.jsonl"
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Noted the task finished."}]}}' >> "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook)
  assert_empty "$out" "G3-07: a background task-notification is not a new prompt"
}
run_test test_g3_task_notification_is_not_a_prompt

# ── The transcript comes from the hook input first ─────────────────────────
# Measured on kit e58778b2 (2026-10-29): after a /clear the harness writes a NEW
# conversation file, but primaryTranscriptKey still names the file of the first counted
# tool call. Guard 3b tailed that stale file, never found its own injection, and woke an
# idle agent three times in a row (transcript lines 711/716/721, no tool_use between).
# The Stop hook input carries transcript_path; it names the live file. STDIN-01 is the
# repro; STDIN-02 is its control (same files swapped), so neither passes vacuously.
run_hook_with() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null || true; }

idle_wake_transcript() {  # $1 = file; our injection, then a one-line reply, no tool_use
  {
    jq -cn --arg r "Stop hook feedback:
Follow §CMD_CONTINUE_ON_STOP ...
(2 of 3 auto-continues; set ...)" '{type:"user",isMeta:true,message:{role:"user",content:$r}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Nothing to do."}]}}'
  } > "$1"
}

test_stdin_transcript_wins_over_stale_key() {
  write_state ' | .autoContinueCount = 2'
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"         # stale: the pre-/clear file
  idle_wake_transcript "$PROJ_DIR/live.jsonl"                   # live: after the /clear
  local out; out=$(run_hook_with "{\"session_id\":\"live\",\"transcript_path\":\"$PROJ_DIR/live.jsonl\",\"hook_event_name\":\"Stop\"}")
  assert_empty "$out" "STDIN-01: an idle wake in the hook input's transcript is not repeated, whatever the stale key names"
  assert_eq "0" "$(jq -r '.autoContinueCount' "$TEST_SESSION/.state.json")" \
    "STDIN-01b: backing off on the live transcript resets the counter"
}
run_test test_stdin_transcript_wins_over_stale_key

test_stdin_transcript_control() {
  write_state ' | .autoContinueCount = 1'
  idle_wake_transcript "$PROJ_DIR/mine.jsonl"                   # the key names an idle wake
  echo '{"type":"assistant"}' > "$PROJ_DIR/live.jsonl"          # the input names a benign turn
  local out; out=$(run_hook_with "{\"transcript_path\":\"$PROJ_DIR/live.jsonl\"}")
  if [[ "$out" == *"block"* ]]; then
    pass "STDIN-02: the hook input's transcript is the one read, not the key's (the control)"
  else
    fail "STDIN-02: the hook input's transcript is the one read, not the key's (the control)" "a block decision" "$out"
  fi
}
run_test test_stdin_transcript_control

# Fallbacks reach a BLOCK on a benign key file: silence would not discriminate the key
# being read from the hook failing closed.
test_stdin_without_path_falls_back_to_key() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook_with '{"session_id":"x","hook_event_name":"Stop"}')
  if [[ "$out" == *"block"* ]]; then
    pass "STDIN-03: input with no transcript_path falls back to primaryTranscriptKey"
  else
    fail "STDIN-03: input with no transcript_path falls back to primaryTranscriptKey" "a block decision" "$out"
  fi
}
run_test test_stdin_without_path_falls_back_to_key

test_stdin_missing_file_falls_back_to_key() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local out; out=$(run_hook_with "{\"transcript_path\":\"$PROJ_DIR/gone.jsonl\"}")
  if [[ "$out" == *"block"* ]]; then
    pass "STDIN-04: a transcript_path naming a missing file falls back to the key"
  else
    fail "STDIN-04: a transcript_path naming a missing file falls back to the key" "a block decision" "$out"
  fi
  # And the fallback is the key's logic whole: the key's idle wake still backs off.
  write_state
  idle_wake_transcript "$PROJ_DIR/mine.jsonl"
  out=$(run_hook_with "{\"transcript_path\":\"$PROJ_DIR/gone.jsonl\"}")
  assert_empty "$out" "STDIN-05: through that fallback, the key's idle wake still backs off"
}
run_test test_stdin_missing_file_falls_back_to_key

test_stdin_non_regular_path_falls_back_to_key() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  mkdir -p "$PROJ_DIR/adir.jsonl"
  local out; out=$(run_hook_with "{\"transcript_path\":\"$PROJ_DIR/adir.jsonl\"}")
  if [[ "$out" == *"block"* ]]; then
    pass "STDIN-06: a transcript_path naming a directory is refused and falls back to the key"
  else
    fail "STDIN-06: a transcript_path naming a directory is refused and falls back to the key" "a block decision" "$out"
  fi
}
run_test test_stdin_non_regular_path_falls_back_to_key

test_stdin_bad_path_and_no_key_fails_closed() {
  jq -n '{pid: 99999999, lifecycle: "active", skill: "loom", currentPhase: "1: Loom"}' > "$TEST_SESSION/.state.json"
  local out; out=$(run_hook_with "{\"transcript_path\":\"$PROJ_DIR/gone.jsonl\"}")
  assert_empty "$out" "STDIN-07: no usable transcript_path and no key still fails closed"
}
run_test test_stdin_bad_path_and_no_key_fails_closed

# ¶PTF_BLOCKING_CAT_ON_STDIN: a writer that holds stdin open and sends nothing must not
# hang the hook. The holder is a background writer on a fifo, killed afterwards, so the
# timing is the hook's own and not a pipeline waiting on its other member.
test_stdin_held_open_does_not_hang() {
  write_state
  echo '{"type":"assistant"}' > "$PROJ_DIR/mine.jsonl"
  local fifo="$TMP_DIR/stdin.fifo"; mkfifo "$fifo"
  sleep 30 > "$fifo" &
  local holder=$!
  local start=$SECONDS out
  out=$(bash "$HOOK" < "$fifo" 2>/dev/null || true)
  local took=$((SECONDS - start))
  kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
  if [ "$took" -le 5 ] && [[ "$out" == *"block"* ]]; then
    pass "STDIN-08: stdin held open with no data does not hang the hook (${took}s), and it falls back to the key"
  else
    fail "STDIN-08: stdin held open with no data does not hang the hook" "<=5s and a block" "${took}s out=$out"
  fi
}
run_test test_stdin_held_open_does_not_hang

exit_with_results
