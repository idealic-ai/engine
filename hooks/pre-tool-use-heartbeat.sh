#!/bin/bash
# ~/.claude/hooks/pre-tool-use-heartbeat.sh — PreToolUse hook for logging heartbeat enforcement
#
# Tracks tool calls per agent (main + sub-agents) via per-transcript counters.
# Each agent's counter is isolated — sub-agent calls don't pollute main agent's count.
#
# Counter storage in .state.json:
#   toolCallsByTranscript: { "abc123.jsonl": 5, "agent-def456.jsonl": 3 }
#   Keyed by basename of transcript_path (unique per agent instance).
#
# Behavior:
#   - Loading mode: if .state.json has loading=true, skip ALL logic (pure passthrough)
#     Set by session.sh activate, cleared by session.sh phase
#   - Increments counter for THIS agent on each tool call
#   - If Bash command contains log.sh: resets THIS agent's counter to 0, allows
#   - If counter >= toolUseWithoutLogsWarnAfter (default 3): WARN but allow
#   - If counter >= toolUseWithoutLogsBlockAfter (default 10): BLOCK (deny)
#   - If no session active: allow (no enforcement)
#   - Whitelist (no counting, always allowed):
#       - Bash: log.sh and session.sh calls
#       - Read: any ~/.claude/* file (standards, skills, templates, docs)
#       - Read: TEMPLATE_*_LOG.md files (legacy fallback pattern)
#       - Task: sub-agent launches (they have their own transcript counters)
#       - Edit: same-file consecutive edits (only first edit counts)
#
# Warn/block messages include resolved log file path, template path, and log.sh command.
# Template message is imperative: "You MUST Read the template first".
#
# Thresholds are configurable in .state.json (written by session.sh activate):
#   toolUseWithoutLogsWarnAfter: 3   (default)
#   toolUseWithoutLogsBlockAfter: 10  (default)
#
# Hook receives JSON on stdin with: tool_name, tool_input, session_id, transcript_path
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — .state.json toolCallsByTranscript field
#   Invariants: (~/.claude/standards/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet notification graceful degradation
#   Commands: (~/.claude/standards/COMMANDS.md)
#     §CMD_LOG_BETWEEN_TOOL_USES — This hook enforces it
#     §CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE — Logging mechanism

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Parse common fields early — needed by both whitelist and main logic
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
TRANSCRIPT_KEY=$(basename "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")

# Loading mode: skip ALL heartbeat logic during session bootstrap
# Set by session.sh activate, cleared by session.sh phase
if [ -n "$TRANSCRIPT_PATH" ]; then
  session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
  if [ -n "$session_dir" ] && [ -f "$session_dir/.state.json" ]; then
    loading=$(jq -r '.loading // false' "$session_dir/.state.json" 2>/dev/null || echo "false")
    if [ "$loading" = "true" ]; then
      hook_allow
    fi
  fi
fi

# Whitelist: engine log and engine session calls always allowed without counting
if [ "$TOOL_NAME" = "Bash" ]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  is_log=false
  is_session=false
  if is_engine_log_cmd "$BASH_CMD"; then
    is_log=true
  fi
  if is_engine_session_cmd "$BASH_CMD"; then
    is_session=true
  fi
  if [ "$is_log" = true ] || [ "$is_session" = true ]; then
    # Reset THIS agent's counter on log calls (session calls just pass through)
    if [ "$is_log" = true ]; then
      session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
      if [ -n "$session_dir" ] && [ -f "$session_dir/.state.json" ]; then
        jq --arg key "$TRANSCRIPT_KEY" \
          '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = 0' \
          "$session_dir/.state.json" | safe_json_write "$session_dir/.state.json"
      fi
    fi
    hook_allow
  fi
fi

# Whitelist: Read of ~/.claude/ files — allow without counting
# Covers standards, skills, templates, docs — all engine infrastructure reads
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
  if [[ "$FILE_PATH" == "$HOME/.claude/"* ]] || [[ "$FILE_PATH" == *"/.claude/skills/"*"/assets/TEMPLATE_"*"_LOG.md" ]]; then
    hook_allow
  fi
fi

# Whitelist: Task tool launches — sub-agents have their own transcript counters
if [ "$TOOL_NAME" = "Task" ]; then
  hook_allow
fi

# Main logic
main() {
  # Find session directory via session.sh find (single source of truth)
  local session_dir
  if ! session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null); then
    hook_allow
  fi

  local agent_file="$session_dir/.state.json"

  if [ ! -f "$agent_file" ]; then
    hook_allow
  fi

  # Read THIS agent's counter and shared thresholds
  local counter warn_after block_after skill
  counter=$(jq -r --arg key "$TRANSCRIPT_KEY" '(.toolCallsByTranscript // {})[$key] // 0' "$agent_file" 2>/dev/null || echo "0")
  warn_after=$(jq -r '.toolUseWithoutLogsWarnAfter // 3' "$agent_file" 2>/dev/null || echo "3")
  block_after=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$agent_file" 2>/dev/null || echo "10")
  skill=$(jq -r '.skill // "unknown"' "$agent_file" 2>/dev/null || echo "unknown")

  # Derive log file path and template path from .state.json logTemplate
  # e.g., logTemplate: "~/.claude/skills/test/assets/TEMPLATE_TESTING_LOG.md"
  #   → template_path = that value, log_file = session_dir/TESTING_LOG.md
  local log_template log_file template_path
  log_template=$(jq -r '.logTemplate // ""' "$agent_file" 2>/dev/null || echo "")
  if [ -z "$log_template" ]; then
    # No logTemplate set — skip heartbeat enforcement
    hook_allow
  fi
  local log_basename="${log_template##*/}"
  local log_name="${log_basename#TEMPLATE_}"
  log_file="${session_dir}/${log_name}"
  template_path="$log_template"

  # Same-file edit suppression: if Edit tool targets the same file as last edit, don't increment
  if [ "$TOOL_NAME" = "Edit" ]; then
    local edit_file
    edit_file=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
    local last_edit_key="lastEditFile_${TRANSCRIPT_KEY}"
    local last_edit_file
    last_edit_file=$(jq -r --arg key "$last_edit_key" '.[$key] // ""' "$agent_file" 2>/dev/null || echo "")
    # Update lastEditFile tracking
    jq --arg key "$last_edit_key" --arg val "$edit_file" \
      '.[$key] = $val' \
      "$agent_file" | safe_json_write "$agent_file"
    if [ "$edit_file" = "$last_edit_file" ] && [ -n "$edit_file" ]; then
      # Same file as last edit — don't increment, just allow
      hook_allow
    fi
  else
    # Not an Edit — clear lastEditFile tracking
    local last_edit_key="lastEditFile_${TRANSCRIPT_KEY}"
    jq --arg key "$last_edit_key" 'del(.[$key])' \
      "$agent_file" | safe_json_write "$agent_file"
  fi

  # Increment THIS agent's counter
  local new_counter=$((counter + 1))
  jq --arg key "$TRANSCRIPT_KEY" --argjson tc "$new_counter" \
    '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = $tc' \
    "$agent_file" | safe_json_write "$agent_file"

  # Block threshold — deny the tool
  if [ "$new_counter" -ge "$block_after" ]; then
    hook_deny \
      "§CMD_LOG_BETWEEN_TOOL_USES: $new_counter tool calls without logging. Tool DENIED." \
      "You MUST Read the log template first, then log your progress before making any more tool calls.\nLog command: engine log $log_file <<'EOF'\n## [YYYY-MM-DD HH:MM:SS] [Entry Type]\n*   **Item**: ...\nEOF\nYou MUST Read this template for the required format: $template_path" \
      ""
  fi

  # Warn threshold — allow but with reminder
  if [ "$new_counter" -ge "$warn_after" ]; then
    cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "§CMD_LOG_BETWEEN_TOOL_USES: $new_counter/$block_after tool calls without logging. Log soon.\nLog command: engine log $log_file\nTemplate (MUST Read first): $template_path"
  }
}
HOOKEOF
    exit 0
  fi

  # Under threshold — allow silently
  hook_allow
}

main
