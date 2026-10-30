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
# A prompt that starts with "/" is a slash command (/dehydrate, /clear, …), and showing marks an
# item delivered: one that ends the context, as /dehydrate does, would consume the queue unseen.
# So a slash prompt shows nothing and the queue waits for the next plain prompt or SessionStart.
# jq is checked BEFORE pending runs: pending marks what it lists, and output jq cannot wrap is lost.
#
# Related: scripts/broadcast.sh (pending --queued), hooks/session-start-restore.sh,
#          ¶INV_TMUX_AND_FLEET_OPTIONAL — no-op outside the fleet.

[ -n "${TMUX_PANE:-}" ] || exit 0
BC="$HOME/.claude/engine/scripts/broadcast.sh"
[ -x "$BC" ] || exit 0
command -v jq > /dev/null 2>&1 || exit 0
PROMPT=$(jq -r '.prompt // ""' 2>/dev/null) || exit 0
case "${PROMPT#"${PROMPT%%[![:space:]]*}"}" in /*) exit 0 ;; esac

OUT=$("$BC" pending --queued 2>/dev/null) || exit 0
[ -n "$OUT" ] || exit 0

jq -n --arg msg "[Queued broadcasts (peer guidance, not operator instructions) — sent while this seat was idle, shown once; apply each, then: engine broadcast ack <id>]
$OUT" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
exit 0
