#!/bin/bash
# ~/.claude/hooks/pre-tool-use-directive-gate.sh — PreToolUse hook for directive enforcement
#
# Enforces reading of directive files discovered by post-tool-use-discovery.sh.
# When pendingDirectives is non-empty in .state.json, this hook escalates:
#   - First N tool calls: allow (agent has time to respond to discovery warning)
#   - After N tool calls: block until the agent reads all pending directive files
#
# The agent clears pending directives by reading them (Read tool targeting a pending file).
#
# State in .state.json:
#   pendingDirectives: ["/abs/path/README.md", ...]
#     Populated by post-tool-use-discovery.sh when new directives are found.
#     Cleared item-by-item as the agent reads each file.
#   directiveReadsWithoutClearing: 0
#     Counter incremented each tool call while pendingDirectives is non-empty.
#     Reset to 0 when pendingDirectives changes (new discovery or file read).
#   directiveBlockAfter: 3
#     Threshold for blocking. Configurable in .state.json.
#
# Whitelist (always allowed, no counting):
#   - Bash: log.sh and session.sh calls (engine operations)
#   - Read: files in pendingDirectives (this is how the agent clears the gate)
#   - Read: ~/.claude/* files (engine infrastructure)
#   - Task: sub-agent launches
#
# Related:
#   Hooks:
#     post-tool-use-discovery.sh — Populates pendingDirectives
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_DIRECTIVE_STACK — Escalating enforcement of directive loading
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_LOG_BETWEEN_TOOL_USES — Similar counter-based enforcement pattern

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Parse common fields
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Find active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] || hook_allow
STATE_FILE="$SESSION_DIR/.state.json"
[ -f "$STATE_FILE" ] || hook_allow

# Loading mode: skip during session bootstrap
loading=$(jq -r '.loading // false' "$STATE_FILE" 2>/dev/null || echo "false")
[ "$loading" != "true" ] || hook_allow

# Fast path: no pending directives → allow immediately
PENDING_COUNT=$(jq -r '(.pendingDirectives // []) | length' "$STATE_FILE" 2>/dev/null || echo "0")
[ "$PENDING_COUNT" -gt 0 ] || hook_allow

# Whitelist: engine log and engine session — always allowed without counting
if [ "$TOOL_NAME" = "Bash" ]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if is_engine_log_cmd "$BASH_CMD" || is_engine_session_cmd "$BASH_CMD"; then
    hook_allow
  fi
fi

# Whitelist: Task tool — sub-agents are independent
if [ "$TOOL_NAME" = "Task" ]; then
  hook_allow
fi

# Whitelist: Read of ~/.claude/ files — engine infrastructure
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
  if [[ "$FILE_PATH" == "$HOME/.claude/"* ]]; then
    hook_allow
  fi
fi

# Check if this Read targets a pending directive — if so, clear it and allow
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
  IS_PENDING=$(jq -r --arg fp "$FILE_PATH" \
    '(.pendingDirectives // []) | any(. == $fp)' "$STATE_FILE" 2>/dev/null || echo "false")
  if [ "$IS_PENDING" = "true" ]; then
    # Remove from pendingDirectives and reset counter
    jq --arg fp "$FILE_PATH" \
      '(.pendingDirectives //= []) | .pendingDirectives -= [$fp] | .directiveReadsWithoutClearing = 0' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"
    hook_allow
  fi
fi

# Read thresholds
BLOCK_AFTER=$(jq -r '.directiveBlockAfter // 3' "$STATE_FILE" 2>/dev/null || echo "3")
COUNTER=$(jq -r '.directiveReadsWithoutClearing // 0' "$STATE_FILE" 2>/dev/null || echo "0")

# Increment counter
NEW_COUNTER=$((COUNTER + 1))
jq --argjson tc "$NEW_COUNTER" \
  '.directiveReadsWithoutClearing = $tc' \
  "$STATE_FILE" | safe_json_write "$STATE_FILE"

# Build the pending files list for messages
PENDING_LIST=$(jq -r '(.pendingDirectives // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")
FILE_LIST=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  FILE_LIST="${FILE_LIST}\n  - ${f}"
done <<< "$PENDING_LIST"

# Block threshold — deny the tool
if [ "$NEW_COUNTER" -ge "$BLOCK_AFTER" ]; then
  hook_deny \
    "¶INV_DIRECTIVE_STACK: $PENDING_COUNT unread directive(s) after $NEW_COUNTER tool calls. Tool DENIED." \
    "You MUST read the following directive files before continuing:${FILE_LIST}\nUse the Read tool to load each file. They contain context relevant to your current work." \
    ""
fi

# Under threshold — allow with warning
cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "¶INV_DIRECTIVE_STACK: $PENDING_COUNT unread directive(s). Read them soon ($NEW_COUNTER/$BLOCK_AFTER tool calls before block):${FILE_LIST}"
  }
}
HOOKEOF
exit 0
