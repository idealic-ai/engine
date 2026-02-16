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

set -uo pipefail

# Global kill switch: DISABLE_TOOL_USE_HOOK=1 skips all post-tool-use hooks
[ "${DISABLE_TOOL_USE_HOOK:-}" = "1" ] && exit 0

# Defensive: ensure exit 0 regardless of internal failures (Pitfall #2)
trap 'exit 0' ERR

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
lock_dir="${state_file}.lock"

# Atomic read+clear under lock (fixes TOCTOU race when parallel PostToolUse hooks fire)
# Without this, N parallel hooks all read the same stash before any clears it → N× duplicate injection.
retries=0
max_retries=100
while ! mkdir "$lock_dir" 2>/dev/null; do
  retries=$((retries + 1))
  if [ "$retries" -ge "$max_retries" ]; then
    debug "lock timeout"
    exit 0
  fi
  if [ -d "$lock_dir" ]; then
    lock_mtime=$(stat -f "%m" "$lock_dir" 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    lock_age=$((now_epoch - lock_mtime))
    if [ "$lock_age" -gt 10 ]; then
      rmdir "$lock_dir" 2>/dev/null || true
      continue
    fi
  fi
  sleep 0.01
done

# --- Under lock: read + clear atomically ---
pending=$(jq -r '.pendingAllowInjections // [] | length' "$state_file" 2>/dev/null || echo "0")

if [ "$pending" -eq 0 ]; then
  rmdir "$lock_dir" 2>/dev/null || true
  exit 0
fi

context=$(jq -r '[.pendingAllowInjections // [] | .[].content] | join("\n\n")' "$state_file" 2>/dev/null || echo "")

if [ -z "$context" ]; then
  rmdir "$lock_dir" 2>/dev/null || true
  exit 0
fi

# Clear stash and write atomically (under same lock)
tmp_file="${state_file}.tmp.$$"
jq '.pendingAllowInjections = []' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
rmdir "$lock_dir" 2>/dev/null || true
# --- End locked section ---

# Deliver via PostToolUse additionalContext
cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $(echo "$context" | jq -Rs .)
  }
}
HOOKEOF
