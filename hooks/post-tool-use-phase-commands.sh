#!/bin/bash
# ~/.claude/hooks/post-tool-use-phase-commands.sh — PostToolUse hook for §CMD_ command file autoloading
#
# When `engine session phase` runs and outputs "Phase: N: Name", discovers which
# §CMD_ command files the new phase's proof fields reference and queues them for injection.
#
# Name resolution:
#   §CMD_GENERATE_DEBRIEF_file → strip §CMD_ → GENERATE_DEBRIEF_file
#   → strip lowercase suffix → GENERATE_DEBRIEF → CMD_GENERATE_DEBRIEF.md
#
# State in .state.json:
#   pendingCommands: ["/abs/path/CMD_FOO.md", ...]  — CMD files awaiting injection
#   preloadedFiles: ["/abs/path/CMD_FOO.md", ...]   — Already-injected files (dedup)

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

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info — only process Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ "$TOOL_NAME" != "Bash" ]; then
  debug "skip: tool=$TOOL_NAME (not Bash)"
  exit 0
fi

# Get tool output — try tool_response (stdin JSON), fall back to TOOL_OUTPUT env var
STDOUT=$(echo "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
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

# Read currentPhase from .state.json (already updated by engine session phase)
CURRENT_PHASE=$(jq -r '.currentPhase // ""' "$STATE_FILE" 2>/dev/null || echo "")
[ -n "$CURRENT_PHASE" ] || exit 0

# Extract major number from phase label (e.g., "4: Build Loop" → 4)
PHASE_MAJOR=$(echo "$CURRENT_PHASE" | sed -E 's/^([0-9]+).*/\1/')
[ -n "$PHASE_MAJOR" ] || exit 0

# Read proof fields for this phase from .state.json phases array
PROOF_FIELDS=$(jq -r --argjson major "$PHASE_MAJOR" \
  '[.phases // [] | .[] | select(.major == $major) | .proof // [] | .[]] | unique | .[]' \
  "$STATE_FILE" 2>/dev/null || echo "")

[ -n "$PROOF_FIELDS" ] || exit 0
debug "proof fields: $(echo "$PROOF_FIELDS" | tr '\n' ', ')"

# CMD files directory
CMD_DIR="$HOME/.claude/engine/.directives/commands"

# Already preloaded files (for dedup)
ALREADY_PRELOADED=$(jq -r '(.preloadedFiles // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")

# Process proof fields: filter §CMD_ prefixed, resolve to file paths, dedup
SEEN_CMDS=""
NEW_COMMANDS=()

while IFS= read -r proof; do
  [ -n "$proof" ] || continue

  # Skip non-§CMD_ prefixed fields
  case "$proof" in
    '§CMD_'*) ;;
    *) debug "skip proof: $proof (no §CMD_ prefix)"; continue ;;
  esac

  # Strip §CMD_ prefix: §CMD_GENERATE_DEBRIEF_file → GENERATE_DEBRIEF_file
  name="${proof#§CMD_}"

  # Strip lowercase suffix (proof sub-field): GENERATE_DEBRIEF_file → GENERATE_DEBRIEF
  name=$(echo "$name" | sed -E 's/_[a-z][a-z_]*$//')

  # Build CMD file path
  cmd_file="$CMD_DIR/CMD_${name}.md"

  # Dedup: skip if already seen this CMD name in this invocation
  case "$SEEN_CMDS" in
    *"|${name}|"*) debug "skip: CMD_${name}.md (dedup)"; continue ;;
  esac
  SEEN_CMDS="${SEEN_CMDS}|${name}|"

  # Skip if file doesn't exist on disk
  if [ ! -f "$cmd_file" ]; then
    debug "skip: $cmd_file (not found)"
    continue
  fi

  # Skip if already in preloadedFiles
  is_preloaded=false
  if [ -n "$ALREADY_PRELOADED" ]; then
    while IFS= read -r preloaded; do
      if [ "$preloaded" = "$cmd_file" ]; then
        is_preloaded=true
        break
      fi
    done <<< "$ALREADY_PRELOADED"
  fi
  if [ "$is_preloaded" = "true" ]; then
    debug "skip: $cmd_file (already in preloadedFiles)"
    continue
  fi

  NEW_COMMANDS+=("$cmd_file")
  debug "ADD: $cmd_file"
done <<< "$PROOF_FIELDS"

# Write new commands to pendingCommands in .state.json
if [ ${#NEW_COMMANDS[@]} -gt 0 ]; then
  for cmd in "${NEW_COMMANDS[@]}"; do
    jq --arg file "$cmd" \
      '(.pendingCommands //= []) | if (.pendingCommands | index($file)) then . else .pendingCommands += [$file] end' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"
  done
  debug "wrote ${#NEW_COMMANDS[@]} to pendingCommands"
fi

exit 0
