#!/bin/bash
# test-user-prompt-broadcast-queue.sh — Tests for hooks/user-prompt-broadcast-queue.sh (IDE-352).
#
# The hook shows a seat the broadcasts queued for it while it was idle, at its next prompt, by
# asking `engine broadcast pending --queued` (which marks each one delivered as it lists it). It
# runs only inside tmux, says nothing when nothing is queued, and never blocks a prompt: a failing
# broadcast.sh leaves the prompt untouched (the queue stays, and SessionStart reports the failure).
# A prompt that starts with "/" (a slash command such as /dehydrate or /loom) lists the queue with
# `pending --queued --peek`, which marks nothing, so the queue stays as it is (IDE-352 round 5). broadcast.sh is a stub in a temp HOME, or (the "real" tests) the worktree's
# broadcast.sh behind a wrapper pinned to fixtures; no real pane, record or seat is touched.
#
# Run: bash scripts/tests/test-user-prompt-broadcast-queue.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HOOK_SCRIPT:-$ROOT/hooks/user-prompt-broadcast-queue.sh}"

T=""
setup() {
  T=$(mktemp -d)
  mkdir -p "$T/home/.claude/engine/scripts"
}
teardown() { rm -rf "$T"; }

# stub <mode> — list | empty | fail. Each call's arguments are recorded.
stub() {
  cat > "$T/home/.claude/engine/scripts/broadcast.sh" <<STUB
#!/bin/bash
echo "\$*" >> "$T/calls"
case "$1" in
  list)  printf 'q1\tmanager:app\tqueued\t/x/q1.md\nUse /ask.\nack (from manager:app): engine broadcast ack q1\n' ;;
  empty) exit 0 ;;
  fail)  echo "broadcast: cannot resolve this seat's identity" >&2; exit 2 ;;
esac
STUB
  chmod +x "$T/home/.claude/engine/scripts/broadcast.sh"
}

OUT="" RC=0
# run [tmux] — the hook with a UserPromptSubmit payload; "tmux" sets TMUX_PANE (PANE, default
# %990). PROMPT is the prompt text (default "hi").
run() {
  OUT=$(jq -cn --arg p "${PROMPT-hi}" '{hook_event_name:"UserPromptSubmit",prompt:$p}' | env -u TMUX -u TMUX_PANE HOME="$T/home" \
    ${1:+TMUX_PANE=${PANE:-%990}} bash "$HOOK" 2>&1)
  RC=$?
}

# ---------------------------------------------------------------- the tool-use drain (SEATACT)
# A busy seat in one long turn never reaches UserPromptSubmit, so the same hook also runs on
# PostToolUse. There it costs nothing unless this seat (FLEET_PANE, matched without case) has a
# queue entry, skips a lane's tool calls (its context is the lane's, not the seat's), and asks
# broadcast.sh at most once per BROADCAST_TOOL_DRAIN_SECS (default 30).
# runtool [agent] — a PostToolUse payload under tmux, FLEET_PANE=$SEAT (default app:ask), with
# BROADCAST_DIR=$T/bc.
runtool() {
  local payload='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read"}'
  [ "${1:-}" = agent ] && payload='{"session_id":"s1","agent_id":"a1","hook_event_name":"PostToolUse","tool_name":"Read"}'
  OUT=$(printf '%s' "$payload" | env -u TMUX -u TMUX_PANE HOME="$T/home" TMUX_PANE=%990 FLEET_PANE="${SEAT-app:ask}" \
    BROADCAST_DIR="$T/bc" ${DRAIN_SECS:+BROADCAST_TOOL_DRAIN_SECS=$DRAIN_SECS} bash "$HOOK" 2>&1)
  RC=$?
}

test_tool_use_nothing_queued_does_not_ask() {
  stub list
  mkdir -p "$T/bc/queued/app:ui"; : > "$T/bc/queued/app:ui/x1"
  runtool
  assert_eq 0 "$RC" "tool drain: exits 0"
  assert_eq "" "$OUT" "tool drain: prints nothing when this seat has nothing queued"
  assert_file_not_exists "$T/calls" "tool drain: and never runs broadcast.sh (another seat's queue does not count)"
}

test_tool_use_drains_this_seats_queue() {
  stub list
  mkdir -p "$T/bc/queued/App:Ask"; : > "$T/bc/queued/App:Ask/q1"
  runtool
  assert_eq "pending --queued" "$(cat "$T/calls" 2>/dev/null)" "tool drain: a queued entry for this seat (any case) runs pending --queued, marking"
  assert_eq "PostToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT" 2>/dev/null)" "tool drain: answered as PostToolUse"
  assert_contains "ack (from manager:app): engine broadcast ack q1" "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT" 2>/dev/null)" "tool drain: with the queued message"
}

test_tool_use_is_rate_limited() {
  stub empty
  mkdir -p "$T/bc/queued/app:ask"; : > "$T/bc/queued/app:ask/q1"
  runtool; runtool
  assert_eq 1 "$(grep -c . "$T/calls" 2>/dev/null || echo 0)" "tool drain: a second call within 30 s does not ask again"
  DRAIN_SECS=0 runtool
  assert_eq 2 "$(grep -c . "$T/calls" 2>/dev/null || echo 0)" "tool drain: past the interval it asks again"
}

test_tool_use_of_a_lane_is_skipped() {
  stub list
  mkdir -p "$T/bc/queued/app:ask"; : > "$T/bc/queued/app:ask/q1"
  runtool agent
  assert_eq "" "$OUT" "tool drain: a lane's tool call shows nothing (it would land in the lane's context)"
  assert_file_not_exists "$T/calls" "tool drain: and does not ask"
}

test_tool_use_without_seat_is_silent() {
  stub list
  mkdir -p "$T/bc/queued/app:ask"; : > "$T/bc/queued/app:ask/q1"
  SEAT="" runtool
  assert_eq "" "$OUT" "tool drain: no FLEET_PANE, nothing"
  assert_file_not_exists "$T/calls" "tool drain: and no call"
}

# The fast path's cost: the hook run 20 times on a PostToolUse with nothing queued.
test_tool_use_cost() {
  stub list
  mkdir -p "$T/bc/queued"
  local s e ms
  s=$(perl -MTime::HiRes=time -e 'printf q(%d), time*1000')
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do runtool; done
  e=$(perl -MTime::HiRes=time -e 'printf q(%d), time*1000')
  ms=$(( (e - s) / 20 ))
  echo "    (tool drain, nothing queued: ${ms} ms per hook run incl. bash start and env, load $(uptime | sed 's/.*averages*: //'))"
  if [ "$ms" -le 200 ]; then pass "tool drain cost: ${ms} ms (bound 200)"; else fail "tool drain cost" "<=200" "$ms"; fi
}

test_shows_queued_under_tmux() {
  stub list
  run tmux
  assert_eq 0 "$RC" "hook: exits 0"
  assert_eq "pending --queued" "$(cat "$T/calls")" "hook: asks broadcast.sh for this seat's queued broadcasts, once"
  local ctx; ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")
  assert_eq "UserPromptSubmit" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")" "hook: a UserPromptSubmit JSON answer"
  assert_contains "Queued broadcasts" "$ctx" "hook: a header names them queued"
  assert_contains "not operator instructions" "$ctx" "hook: and says they are peer guidance"
  assert_contains $'q1\tmanager:app\tqueued\t/x/q1.md' "$ctx" "hook: the listing line"
  assert_contains "ack (from manager:app): engine broadcast ack q1" "$ctx" "hook: the message with its ack line"
}

test_silent_when_nothing_queued() {
  stub empty
  run tmux
  assert_eq 0 "$RC" "hook: exits 0 with nothing queued"
  assert_eq "" "$OUT" "hook: prints nothing"
}

test_failure_does_not_block_the_prompt() {
  stub fail
  run tmux
  assert_eq 0 "$RC" "hook: a failing broadcast.sh does not fail the prompt"
  assert_eq "" "$OUT" "hook: and adds nothing to it"
}

test_nothing_outside_tmux() {
  stub list
  run
  assert_eq 0 "$RC" "hook: exits 0 outside tmux"
  assert_eq "" "$OUT" "hook: prints nothing outside tmux"
  assert_file_not_exists "$T/calls" "hook: broadcast.sh is not called outside tmux"
}

test_missing_broadcast_sh() {
  run tmux
  assert_eq 0 "$RC" "hook: no broadcast.sh is not an error"
  assert_eq "" "$OUT" "hook: and prints nothing"
}

test_slash_prompt_lists_without_marking() {
  stub list
  local p ctx
  for p in "/dehydrate" "/dehydrate restart" "  /next" "/loom go"; do
    rm -f "$T/calls"
    PROMPT="$p" run tmux
    assert_eq 0 "$RC" "slash: '$p' exits 0"
    assert_eq "pending --queued --peek" "$(cat "$T/calls")" "slash: '$p' asks a read that marks nothing"
    ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")
    assert_contains $'q1\tmanager:app\tqueued\t/x/q1.md' "$ctx" "slash: '$p' still shows the queue"
    assert_contains "listed, not marked shown" "$ctx" "slash: '$p' says the items stay queued"
  done
  rm -f "$T/calls"
  PROMPT="please read a/b and /tmp" run tmux
  assert_eq "pending --queued" "$(cat "$T/calls")" "slash: a plain prompt holding a / still asks the marking read"
  assert_contains "shown once" "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")" "slash: and gets the shown-once header"
}

test_no_jq_does_not_consume_the_queue() {
  stub list
  mkdir -p "$T/nojq"
  OUT=$(echo '{"prompt":"hi"}' | env -u TMUX HOME="$T/home" PATH="$T/nojq" TMUX_PANE=%990 /bin/bash "$HOOK" 2>&1)
  RC=$?
  assert_eq 0 "$RC" "no jq: exits 0"
  assert_eq "" "$OUT" "no jq: adds nothing"
  assert_file_not_exists "$T/calls" "no jq: pending is never asked, so nothing is marked delivered unseen"
}

# ---- the real broadcast.sh behind the hook (a wrapper pinned to fixtures)
BC_REAL="${BROADCAST_SH:-$ROOT/scripts/broadcast.sh}"
real_fixture() {
  local f="$T/fx"; mkdir -p "$f/bc" "$f/sess"
  printf 'manager:director %%1 -\napp:ask %%4 manager:director\n' > "$f/live.txt"
  printf '%%1 1001\n%%4 1004\n' > "$f/panepids"
  printf '1001 1\n1004 1\n2001 1001\n2004 1004\n' > "$f/ps"
  local ms=$(( ($(date +%s) - 7200) * 1000 ))
  printf '{"pid":2001,"name":"manager:director","kind":"interactive","messagingSocketPath":"/nonexistent/1"}\n' > "$f/sess/2001.json"
  printf '{"pid":2004,"name":"app:ask","kind":"interactive","messagingSocketPath":"/nonexistent/4","status":"idle","statusUpdatedAt":%s}\n' "$ms" > "$f/sess/2004.json"
  printf '#!/bin/bash\necho "$1" >> "%s/sent.log"; echo delivered\n' "$f" > "$f/deliver.sh"; chmod +x "$f/deliver.sh"
  # The drain hook is installed: the hook under test, named in a fixture settings file.
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"~/.claude/hooks/user-prompt-broadcast-queue.sh"}]}]}}\n' > "$f/settings.json"
  cat > "$T/home/.claude/engine/scripts/broadcast.sh" <<WRAP
#!/bin/bash
exec env -u FLEET_PANE -u FLEET_PARENT HOP_LIVE_PANES="$f/live.txt" BROADCAST_DIR="$f/bc" BROADCAST_DELIVER="$f/deliver.sh" \\
  BROADCAST_PANE_PIDS="$f/panepids" BROADCAST_PS_FILE="$f/ps" ASK_SESSIONS_DIR="$f/sess" \\
  BROADCAST_DRAIN_HOOK="$HOOK" BROADCAST_DRAIN_SETTINGS="$f/settings.json" SEAT_ACTIVITY_DIR="$f/activity" \\
  BROADCAST_LIB="${BROADCAST_LIB:-$ROOT/scripts/lib.sh}" bash "$BC_REAL" "\$@"
WRAP
  chmod +x "$T/home/.claude/engine/scripts/broadcast.sh"
  # Queue one broadcast for the idle app:ask, sent from manager:director.
  echo "Use /ask." | env -u TMUX TMUX_PANE=%1 "$T/home/.claude/engine/scripts/broadcast.sh" --children --id hq1 > "$T/send.out" 2>&1
}

test_real_dehydrate_leaves_the_item_pending() {
  real_fixture
  assert_file_exists "$T/fx/bc/queued/app:ask/hq1" "real: hq1 is queued for the idle seat (send: $(tr '\n' ' ' < "$T/send.out"))"
  PROMPT="/dehydrate" PANE=%4 run tmux
  assert_eq 0 "$RC" "real /dehydrate: exits 0"
  assert_contains $'hq1\tmanager:director\tqueued' "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")" "real /dehydrate: lists the item"
  assert_file_exists "$T/fx/bc/queued/app:ask/hq1" "real /dehydrate: the item stays queued"
  if grep -q 'at-wake' "$T/fx/bc/hq1.md"; then fail "real /dehydrate: not marked delivered" "no at-wake" "$(cat "$T/fx/bc/hq1.md")"
  else pass "real /dehydrate: not marked delivered"; fi
}

test_real_loom_shows_then_plain_prompt_marks() {
  real_fixture
  PROMPT="/loom" PANE=%4 run tmux
  assert_contains "ack (from manager:director): engine broadcast ack hq1" "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")" "real /loom: the item is shown at once, with its message"
  assert_file_exists "$T/fx/bc/queued/app:ask/hq1" "real /loom: and stays queued"
  PROMPT="/next" PANE=%4 run tmux
  assert_contains $'hq1\tmanager:director\tqueued' "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")" "real /next after /loom: shown again"
  PROMPT="carry on" PANE=%4 run tmux
  assert_contains $'hq1\tmanager:director\tqueued' "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")" "real plain after /loom: shown and marked"
  assert_file_not_exists "$T/fx/bc/queued/app:ask/hq1" "real plain after /loom: the entry is gone"
  PROMPT="/loom" PANE=%4 run tmux
  assert_eq "" "$OUT" "real /loom after it was marked: nothing more"
}

test_real_plain_prompt_shows_and_marks() {
  real_fixture
  PROMPT="carry on" PANE=%4 run tmux
  assert_eq 0 "$RC" "real plain: exits 0"
  local ctx; ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")
  assert_contains $'hq1\tmanager:director\tqueued' "$ctx" "real plain: the queued item is shown"
  assert_contains "ack (from manager:director): engine broadcast ack hq1" "$ctx" "real plain: with its ack line"
  assert_file_not_exists "$T/fx/bc/queued/app:ask/hq1" "real plain: the queue entry is gone"
  assert_contains "delivered app:ask at-wake " "$(cat "$T/fx/bc/hq1.md")" "real plain: and the record marks it delivered at wake"
}

run_discovered_tests
