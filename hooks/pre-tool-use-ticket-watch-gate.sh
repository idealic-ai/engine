#!/bin/bash
# PreToolUse hook: auto-watch hard gate.
# Forces any session subscribed to tickets[] to keep a live background
# `engine ticket watch` running, so cross-agent ticket notifies actually wake it.
#
# Armed = .state.json:watchTaskId.pid present AND kill -0 (liveness is the truth;
# cmd_watch's EXIT trap is only a graceful fast-path, so a SIGKILL leaves a stale
# field which this gate clears opportunistically).
#
# Anti-deadlock: the arming call is itself a tool call, so the spawn command
# (engine ticket watch), AskUserQuestion, Skill, and engine bookkeeping are always
# allowed, and the first few gated calls pass under a PID-scoped grace counter.
#
# NOOP (silent exit 0) when there is no active session; otherwise emits an explicit
# allow/deny PreToolUse decision.
#
# Related:
#   Registers watchTaskId: scripts/ticket.sh cmd_watch
#   Nudge sibling: hooks/post-tool-use-ticket-watch.sh
#   Gate precedent: hooks/pre-tool-use-one-strike.sh (PID-scoped warn/grace files)

set -uo pipefail
trap 'exit 0' ERR

source "$HOME/.claude/scripts/lib.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# No active session → truly idle; stay silent (INV_HOOKS_NOOP_WHEN_IDLE).
session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
{ [ -n "$session_dir" ] && [ -f "$session_dir/.state.json" ]; } || exit 0
state="$session_dir/.state.json"

# Only gate sessions that actually subscribe to tickets.
tickets_len=$(jq -r '(.tickets // []) | length' "$state" 2>/dev/null || echo 0)
[ "${tickets_len:-0}" -gt 0 ] || hook_allow

# Whitelist: never lock the agent out of asking, invoking a skill, arming the watcher,
# or driving the ticket/session/log bookkeeping it needs.
case "$TOOL_NAME" in
  AskUserQuestion|Skill) hook_allow ;;
esac
if [ "$TOOL_NAME" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  CMD="${CMD%%<<*}"
  if is_engine_cmd "$CMD" "ticket" || is_engine_cmd "$CMD" "session" || is_engine_cmd "$CMD" "log"; then
    hook_allow
  fi
fi

# Armed? Liveness via kill -0; a dead pid is cleared and treated as unarmed.
watch_pid=$(jq -r '.watchTaskId.pid // empty' "$state" 2>/dev/null || echo "")
if [ -n "$watch_pid" ]; then
  if pid_exists "$watch_pid"; then
    hook_allow
  else
    safe_json_update "$state" 'del(.watchTaskId)' 2>/dev/null || true
  fi
fi

# Unarmed: allow a small grace window (anti-deadlock), then hard-block.
SUPERVISOR_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"
GRACE_DIR="${CLAUDE_HOOK_WARNED_DIR:-/tmp}"
GRACE_MAX="${CLAUDE_TICKET_WATCH_GRACE:-3}"
counter_file="${GRACE_DIR}/claude-ticket-watch-grace-${SUPERVISOR_PID}"
count=0
[ -f "$counter_file" ] && count=$(cat "$counter_file" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$counter_file" 2>/dev/null || true

if [ "$count" -le "$GRACE_MAX" ]; then
  hook_allow
fi

ticket_list=$(jq -r '[(.tickets // [])[].key] | join(", ")' "$state" 2>/dev/null || echo "")
hook_deny \
  "[block: ticket-watch] This session subscribes to ticket(s) ${ticket_list} but has no live background watcher — cross-agent notifies would be missed." \
  "Arm one now: run \`engine ticket watch\` via Bash with run_in_background:true, then retry. It blocks until a real update (no timeout by default, so no fake-wakes). (AskUserQuestion, Skill, and engine ticket/session/log stay allowed.)" \
  "watchTaskId pid absent/dead; grace ${count}/${GRACE_MAX} exhausted for pid ${SUPERVISOR_PID}"
