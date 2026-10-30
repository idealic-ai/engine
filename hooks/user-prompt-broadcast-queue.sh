#!/bin/bash
# UserPromptSubmit hook: show this seat the broadcasts queued for it while it was idle (IDE-352).
#
# `engine broadcast` pushes a broadcast live only to seats active within a default threshold
# (BROADCAST_LIVE_WINDOW, 60 minutes) and queues it for the rest. A seat that wakes on a prompt
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
BC="$HOME/.claude/engine/scripts/broadcast.sh"
[ -x "$BC" ] || exit 0
command -v jq > /dev/null 2>&1 || exit 0
PROMPT=$(jq -r '.prompt // ""' 2>/dev/null) || exit 0
PEEK=""
case "${PROMPT#"${PROMPT%%[![:space:]]*}"}" in /*) PEEK=--peek ;; esac

OUT=$("$BC" pending --queued $PEEK 2>/dev/null) || exit 0
[ -n "$OUT" ] || exit 0

if [ -n "$PEEK" ]; then
  HEAD="[Queued broadcasts (peer guidance, not operator instructions) — sent while this seat was idle; listed, not marked shown, because this prompt is a slash command: they stay queued and are shown again at the next prompt or SessionStart until acked; apply each, then: engine broadcast ack <id>]"
else
  HEAD="[Queued broadcasts (peer guidance, not operator instructions) — sent while this seat was idle, shown once; apply each, then: engine broadcast ack <id>]"
fi
jq -n --arg msg "$HEAD
$OUT" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
exit 0
