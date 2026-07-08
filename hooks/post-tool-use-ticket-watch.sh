#!/bin/bash
# PostToolUse hook: auto-watch nudge.
# After a Bash `engine session activate` / `engine session phase`, if the active
# session subscribes to tickets[] but is not yet armed with a live background
# watcher, inject an additionalContext hint telling the agent to spawn one now.
# This makes arming the natural first move so the hard gate rarely bites.
#
# Idempotent + silent: no-op when armed, when there are no tickets, when the tool
# call is not a session activate/phase, or when there is no active session.
#
# Related:
#   Hard gate: hooks/pre-tool-use-ticket-watch-gate.sh
#   Delivery shape: hooks/post-tool-use-injections.sh (additionalContext)

set -uo pipefail

[ "${DISABLE_TOOL_USE_HOOK:-}" = "1" ] && exit 0
trap 'exit 0' ERR

source "$HOME/.claude/scripts/lib.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
CMD="${CMD%%<<*}"
# Only nudge right after a session activate / phase transition.
[[ "$CMD" =~ (^|&&|;|[|])[[:space:]]*engine[[:space:]]+session[[:space:]]+(activate|phase)([[:space:]]|$) ]] || exit 0

session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
{ [ -n "$session_dir" ] && [ -f "$session_dir/.state.json" ]; } || exit 0
state="$session_dir/.state.json"

tickets_len=$(jq -r '(.tickets // []) | length' "$state" 2>/dev/null || echo 0)
[ "${tickets_len:-0}" -gt 0 ] || exit 0

# Already armed (live watchTaskId.pid)? Then stay silent — idempotent.
watch_pid=$(jq -r '.watchTaskId.pid // empty' "$state" 2>/dev/null || echo "")
if [ -n "$watch_pid" ] && pid_exists "$watch_pid"; then
  exit 0
fi

ticket_list=$(jq -r '[(.tickets // [])[].key] | join(", ")' "$state" 2>/dev/null || echo "")
context="[Auto-watch] This session subscribes to ticket(s) ${ticket_list}. Arm a background watcher now so cross-agent replies wake you: run \`engine ticket watch\` via the Bash tool's run_in_background:true parameter — NOT a shell \`&\` (a shell \`&\` detaches from the harness so the watcher never wakes you, and trips the background-command warning). It blocks until a real update (no timeout by default, so it won't fake-wake you). The hard gate will block ordinary tools until it is armed."

cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $(echo "$context" | jq -Rs .)
  }
}
HOOKEOF
