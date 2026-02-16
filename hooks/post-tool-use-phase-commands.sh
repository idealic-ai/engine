#!/bin/bash
# ~/.claude/hooks/post-tool-use-phase-commands.sh — PostToolUse hook for §CMD_ command file autoloading
#
# When `engine session phase` runs and outputs "Phase: N: Name", discovers which
# §CMD_ command files the new phase needs and queues them via preload_ensure(next).
#
# Uses resolve_phase_cmds() for unified Phase 0/N CMD extraction, and
# preload_ensure() for dedup + atomic tracking + auto-expand.

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [phase-cmds] $*" >> "$DEBUG_LOG"
  fi
}

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

HOOK_NAME="phase-cmds"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info — only process Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ "$TOOL_NAME" != "Bash" ]; then
  debug "skip: tool=$TOOL_NAME (not Bash)"
  exit 0
fi

# Get tool output — extract stdout from Bash tool_response object
STDOUT=$(echo "$INPUT" | jq -r '
  if .tool_response | type == "object" then .tool_response.stdout // ""
  else .tool_response // ""
  end' 2>/dev/null || echo "")
if [ -z "$STDOUT" ]; then
  STDOUT="${TOOL_OUTPUT:-}"
fi

# Check if stdout starts with "Phase:" (engine session phase output)
if [ "${STDOUT:0:6}" != "Phase:" ]; then
  debug "skip: stdout doesn't start with Phase:"
  exit 0
fi
debug "phase transition detected: ${STDOUT%%$'\n'*}"

# Find active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] || exit 0

STATE_FILE="$SESSION_DIR/.state.json"
[ -f "$STATE_FILE" ] || exit 0

# Read skill and currentPhase from .state.json
SKILL_NAME=$(jq -r '.skill // ""' "$STATE_FILE" 2>/dev/null || echo "")
[ -n "$SKILL_NAME" ] || exit 0

CURRENT_PHASE=$(jq -r '.currentPhase // ""' "$STATE_FILE" 2>/dev/null || echo "")
[ -n "$CURRENT_PHASE" ] || exit 0

# Extract phase label from "N: Name" or "N.M: Name" format
PHASE_LABEL=$(echo "$CURRENT_PHASE" | sed -E 's/^([0-9]+(\.[0-9]+)?[A-Z]?):.*$/\1/')
[ -n "$PHASE_LABEL" ] || exit 0

debug "skill=$SKILL_NAME phase_label=$PHASE_LABEL"

# Get CMD file paths for this phase via unified resolution
CMD_PATHS=$(resolve_phase_cmds "$SKILL_NAME" "$PHASE_LABEL")
[ -n "$CMD_PATHS" ] || exit 0

debug "CMD paths: $(echo "$CMD_PATHS" | tr '\n' ', ')"

# Queue each CMD file via preload_ensure(next) — handles dedup + atomic tracking
QUEUED=0
while IFS= read -r cmd_path; do
  [ -n "$cmd_path" ] || continue
  preload_ensure "$cmd_path" "phase-cmds($PHASE_LABEL)" "next"
  if [ "$_PRELOAD_RESULT" = "queued" ]; then
    QUEUED=$((QUEUED + 1))
    debug "QUEUED: $cmd_path"
  else
    debug "SKIP: $cmd_path (result=$_PRELOAD_RESULT)"
  fi
done <<< "$CMD_PATHS"

debug "queued $QUEUED CMD files for phase $PHASE_LABEL"

exit 0
