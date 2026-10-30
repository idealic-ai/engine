#!/bin/bash
# test-user-prompt-broadcast-queue.sh — Tests for hooks/user-prompt-broadcast-queue.sh (IDE-352).
#
# The hook shows a seat the broadcasts queued for it while it was idle, at its next prompt, by
# asking `engine broadcast pending --queued` (which marks each one delivered as it lists it). It
# runs only inside tmux, says nothing when nothing is queued, and never blocks a prompt: a failing
# broadcast.sh leaves the prompt untouched (the queue stays, and SessionStart reports the failure).
# A prompt that starts with "/" (a slash command such as /dehydrate) shows nothing and leaves the
# queue as it is. broadcast.sh is a stub in a temp HOME, or (the "real" tests) the worktree's
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

test_slash_prompt_shows_nothing() {
  stub list
  local p
  for p in "/dehydrate" "/dehydrate restart" "  /clear" "/loom go"; do
    rm -f "$T/calls"
    PROMPT="$p" run tmux
    assert_eq 0 "$RC" "slash: '$p' exits 0"
    assert_eq "" "$OUT" "slash: '$p' adds nothing"
    assert_file_not_exists "$T/calls" "slash: '$p' never asks pending (which would mark the queue delivered)"
  done
  rm -f "$T/calls"
  PROMPT="please read a/b and /tmp" run tmux
  assert_eq "pending --queued" "$(cat "$T/calls")" "slash: a plain prompt holding a / still asks"
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
  cat > "$T/home/.claude/engine/scripts/broadcast.sh" <<WRAP
#!/bin/bash
exec env -u FLEET_PANE -u FLEET_PARENT HOP_LIVE_PANES="$f/live.txt" BROADCAST_DIR="$f/bc" BROADCAST_DELIVER="$f/deliver.sh" \\
  BROADCAST_PANE_PIDS="$f/panepids" BROADCAST_PS_FILE="$f/ps" ASK_SESSIONS_DIR="$f/sess" \\
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
  assert_eq "" "$OUT" "real /dehydrate: shows nothing"
  assert_file_exists "$T/fx/bc/queued/app:ask/hq1" "real /dehydrate: the item stays queued"
  if grep -q 'at-wake' "$T/fx/bc/hq1.md"; then fail "real /dehydrate: not marked delivered" "no at-wake" "$(cat "$T/fx/bc/hq1.md")"
  else pass "real /dehydrate: not marked delivered"; fi
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
