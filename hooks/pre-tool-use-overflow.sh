#!/bin/bash
# ~/.claude/hooks/pre-tool-use-overflow.sh — PreToolUse hook for context overflow protection
#
# This hook is called before every tool use. It checks the session's .state.json
# for context usage and blocks all tools if usage >= 78% (~97.5% of Claude's 80% auto-compact threshold).
#
# Hook receives JSON on stdin with: tool_name, tool_input, session_id, transcript_path
#
# To register this hook, add to ~/.claude/settings.local.json:
# {
#   "hooks": {
#     "PreToolUse": [
#       { "command": "~/.claude/hooks/pre-tool-use-overflow.sh" }
#     ]
#   }
# }
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — Primary reference for overflow protection
#     SESSION_LIFECYCLE.md — Lifecycle state integration
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet notification graceful degradation

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Source shared config (threshold constant)
# The hook may live in ~/.claude/hooks/ (regular file) or ~/.claude/engine/hooks/ (engine source)
# Try both locations: engine dir derived from script path, then explicit engine path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${ENGINE_DIR}/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="$HOME/.claude/engine/config.sh"
fi
# shellcheck source=../config.sh
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi
OVERFLOW_THRESHOLD="${OVERFLOW_THRESHOLD:-0.76}"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info early (needed for dehydrate detection)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
SKILL_ARG=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

# Whitelist critical dehydration commands - these must ALWAYS be allowed
# even during overflow, otherwise the agent can't save context or restart
if [ "$TOOL_NAME" = "Bash" ]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  # Allow log.sh and session.sh (dehydration scripts)
  if [[ "$BASH_CMD" == *"/.claude/scripts/log.sh"* ]] || \
     [[ "$BASH_CMD" == *"/.claude/scripts/session.sh"* ]]; then
    hook_allow
  fi
fi

# Find the session directory using session.sh find (single source of truth)
# session.sh find uses: fleet.sh pane-id → CLAUDE_SUPERVISOR_PID/$PPID
find_session_dir() {
  "$HOME/.claude/scripts/session.sh" find 2>/dev/null
}

# Main logic
main() {
  # Send working notification on any tool use
  notify_fleet working
  # Find session directory
  local session_dir
  if ! session_dir=$(find_session_dir); then
    # No session found, allow the tool
    hook_allow
  fi

  local agent_file="$session_dir/.state.json"

  if [ ! -f "$agent_file" ]; then
    # No .state.json, allow the tool
    hook_allow
  fi

  # Read context usage
  local context_usage
  context_usage=$(state_read "$agent_file" contextUsage "0")

  # Read state fields (orthogonal decomposition)
  local lifecycle killRequested
  lifecycle=$(state_read "$agent_file" lifecycle "active")
  killRequested=$(state_read "$agent_file" killRequested "false")

  # If dehydrate skill is being invoked, set lifecycle to "dehydrating" and allow
  if [ "$TOOL_NAME" = "Skill" ] && [ "$SKILL_ARG" = "dehydrate" ]; then
    jq '.lifecycle = "dehydrating"' "$agent_file" | safe_json_write "$agent_file"
    hook_allow
  fi

  # Allow all tools during dehydration/restart flow
  # - dehydrating: dehydrate skill is running, needs Read/Write/Bash access
  # - killRequested: restart has been triggered, allowing final cleanup
  if [ "$lifecycle" == "dehydrating" ] || [ "$killRequested" == "true" ]; then
    hook_allow
  fi

  # Check if context usage is at overflow threshold
  # OVERFLOW_THRESHOLD is sourced from ~/.claude/engine/config.sh
  # When raw context >= threshold, dehydration is forced
  local threshold="$OVERFLOW_THRESHOLD"
  local is_overflow
  is_overflow=$(echo "$context_usage >= $threshold" | bc -l 2>/dev/null || echo "0")

  if [ "$is_overflow" == "1" ]; then
    # Block the tool - context overflow
    local skill
    skill=$(state_read "$agent_file" skill "unknown")

    # Set overflowed flag (sticky — only cleared by session.sh activate)
    jq '.overflowed = true' "$agent_file" | safe_json_write "$agent_file"

    # Notify error state (tool denied)
    notify_fleet error

    hook_deny \
      "CONTEXT OVERFLOW — You MUST invoke the dehydrate skill NOW." \
      "Use: Skill(skill: \"dehydrate\", args: \"restart\"). Do NOT use Bash or session.sh. The Skill tool is required. This will save your context and restart with fresh context to continue the $skill session." \
      ""
  fi

  # Allow the tool
  hook_allow
}

main
