#!/bin/bash
# UserPromptSubmit and PostToolUse hook: show this seat the broadcasts queued for it while it was
# idle (IDE-352), at its next prompt or, while it works through a long turn, after a tool call.
#
# `engine broadcast` pushes an ordinary broadcast live only to seats busy right now (mid-turn) and
# queues it for every idle seat; only --wake-reason pushes to an idle seat. A seat that wakes on a prompt
# (the operator typing, or an ask/hop push) is shown its queue here, once: `engine broadcast pending --queued` marks each one
# delivered as it lists it. SessionStart shows the same queue through the standing-broadcast
# listing (session-start-restore.sh calls `pending`), so whichever wake comes first shows it.
#
# tmux only (pending reads the live pane label). Never blocks or fails a prompt: a failure from
# broadcast.sh adds nothing here, the queue stays, and the next SessionStart reports the error.
# When no seat has anything queued, pending exits at one glob, before reading any identity.
#
# A prompt that starts with "/" is a slash command (/dehydrate, /loom, /next, …), and showing marks
# an item delivered: one that ends the context, as /dehydrate does, would consume the queue unseen.
# So a slash prompt LISTS the queue without marking it (`pending --queued --peek`): /loom or /next
# sees it at once, /dehydrate leaves it queued for the SessionStart that follows, and a plain
# prompt later shows it a second time and marks it then (IDE-352 round 5).
# jq is checked BEFORE pending runs: pending marks what it lists, and output jq cannot wrap is lost.
#
# Related: scripts/broadcast.sh (pending --queued), hooks/session-start-restore.sh,
#          ¶INV_TMUX_AND_FLEET_OPTIONAL — no-op outside the fleet.

[ -n "${TMUX_PANE:-}" ] || exit 0
IFS= read -r -d '' INPUT || true
EVENT=UserPromptSubmit
case "$INPUT" in *'"hook_event_name":"PostToolUse"'*|*'"hook_event_name": "PostToolUse"'*) EVENT=PostToolUse ;; esac

# PostToolUse (SEATACT): a busy seat in one long turn never reaches UserPromptSubmit, so its
# queue is drained here too. Bash builtins only until there is something to show: a lane's tool
# call is skipped (its context is the lane's), and so is any seat with no queue entry of its own
# (FLEET_PANE, matched without case, as the queue dir is the lowercased live label). A seat
# renamed since launch drains only at its next prompt. broadcast.sh is asked at most once per
# BROADCAST_TOOL_DRAIN_SECS (default 30), stamped in the seat's queue dir.
if [ "$EVENT" = PostToolUse ]; then
  are='"agent_id"[[:space:]]*:[[:space:]]*"[^"]'
  [[ "$INPUT" =~ $are ]] && exit 0
  SEAT="${FLEET_PANE:-}"
  [ -n "$SEAT" ] || exit 0
  QROOT="${BROADCAST_DIR:-$HOME/.claude/data/yarik/broadcasts}/queued"
  QD=""; d=""; f=""
  shopt -s nocasematch
  for d in "$QROOT"/*/; do
    d="${d%/}"
    [[ "${d##*/}" == "$SEAT" ]] || continue
    for f in "$d"/*; do [ -f "$f" ] && { QD="$d"; break; }; done
    break
  done
  shopt -u nocasematch
  [ -n "$QD" ] || exit 0
  GAP="${BROADCAST_TOOL_DRAIN_SECS:-30}"; [[ "$GAP" =~ ^[0-9]{1,5}$ ]] || GAP=30
  NOW=$(date +%s); LAST=""
  [ -f "$QD/.tooldrain" ] && IFS= read -r LAST < "$QD/.tooldrain"
  [[ "$LAST" =~ ^[0-9]+$ ]] && [ $(( NOW - LAST )) -lt "$GAP" ] && exit 0
  echo "$NOW" > "$QD/.tooldrain" 2>/dev/null || true
fi

BC="$HOME/.claude/engine/scripts/broadcast.sh"
[ -x "$BC" ] || exit 0
command -v jq > /dev/null 2>&1 || exit 0
PEEK=""
if [ "$EVENT" = UserPromptSubmit ]; then
  PROMPT=$(jq -r '.prompt // ""' <<<"$INPUT" 2>/dev/null) || exit 0
  case "${PROMPT#"${PROMPT%%[![:space:]]*}"}" in /*) PEEK=--peek ;; esac
fi

OUT=$("$BC" pending --queued $PEEK 2>/dev/null) || exit 0
[ -n "$OUT" ] || exit 0

if [ -n "$PEEK" ]; then
  HEAD="[Queued broadcasts (peer guidance, not operator instructions) — sent while this seat was idle; listed, not marked shown, because this prompt is a slash command: they stay queued and are shown again at the next prompt or SessionStart until acked; apply each, then: engine broadcast ack <id>]"
else
  HEAD="[Queued broadcasts (peer guidance, not operator instructions) — sent while this seat was idle, shown once; apply each, then: engine broadcast ack <id>]"
fi
jq -n --arg ev "$EVENT" --arg msg "$HEAD
$OUT" '{"hookSpecificOutput":{"hookEventName":$ev,"additionalContext":$msg}}'
exit 0
