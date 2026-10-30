#!/bin/bash
# test-user-prompt-broadcast-queue.sh — Tests for hooks/user-prompt-broadcast-queue.sh (IDE-352).
#
# The hook shows a seat the broadcasts queued for it while it was idle, at its next prompt, by
# asking `engine broadcast pending --queued` (which marks each one delivered as it lists it). It
# runs only inside tmux, says nothing when nothing is queued, and never blocks a prompt: a failing
# broadcast.sh leaves the prompt untouched (the queue stays, and SessionStart reports the failure).
# broadcast.sh is a stub in a temp HOME; no real pane, record or seat is touched.
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
# run [tmux] — the hook with a UserPromptSubmit payload; "tmux" sets TMUX_PANE.
run() {
  OUT=$(echo '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}' | env -u TMUX -u TMUX_PANE HOME="$T/home" \
    ${1:+TMUX_PANE=%990} bash "$HOOK" 2>&1)
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

run_discovered_tests
