#!/bin/bash
# ~/.claude/engine/hooks/post-tool-use-injections.sh — PostToolUse injection delivery
#
# Delivers allow-urgency injections stashed by PreToolUse (pre-tool-use-overflow-v2.sh).
# PreToolUse evaluates injection rules and stashes allow-urgency content to
# .state.json:pendingAllowInjections. This hook reads the stash, delivers via
# PostToolUse additionalContext (which Claude Code surfaces to the model as
# <system-reminder> tags), and clears the stash.
#
# Flow:
#   1. Find active session directory
#   2. Read pendingAllowInjections from .state.json
#   3. If non-empty: join content, output as additionalContext, clear stash
#   4. If empty: silent exit
#
# Related:
#   PreToolUse: pre-tool-use-overflow-v2.sh (_deliver_allow_rules stashes here)
#   Invariants: ¶INV_TMUX_AND_FLEET_OPTIONAL (no tmux dependency)

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [injections] $*" >> "$DEBUG_LOG"
  fi
}

source "$HOME/.claude/scripts/lib.sh"

# Find active session
session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
if [ -z "$session_dir" ] || [ ! -f "$session_dir/.state.json" ]; then
  exit 0
fi

state_file="$session_dir/.state.json"

# Read pending allow injections
pending=$(jq -r '.pendingAllowInjections // [] | length' "$state_file" 2>/dev/null || echo "0")

if [ "$pending" -eq 0 ]; then
  exit 0
fi

# Join all stashed content entries with double newlines
context=$(jq -r '[.pendingAllowInjections // [] | .[].content] | join("\n\n")' "$state_file" 2>/dev/null || echo "")

if [ -z "$context" ]; then
  exit 0
fi

# Clear the stash
jq '.pendingAllowInjections = []' "$state_file" | safe_json_write "$state_file"

# Deliver via PostToolUse additionalContext
cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $(echo "$context" | jq -Rs .)
  }
}
HOOKEOF
