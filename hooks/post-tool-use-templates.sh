#!/bin/bash
# ~/.claude/engine/hooks/post-tool-use-templates.sh — PostToolUse hook for skill template preloading
#
# When the Skill tool or engine session activate/continue fires:
# 1. Extracts Phase 0 CMD files + templates via extract_skill_preloads()
# 2. Uses preload_ensure(immediate) for dedup + atomic tracking + delivery
# 3. Auto-expands § references via _auto_expand_refs() inside preload_ensure()

set -uo pipefail

# Defensive: ensure exit 0 regardless of internal failures (Pitfall #2)
trap 'exit 0' ERR

# Debug logging
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [templates] $*" >> "$DEBUG_LOG"
  fi
}

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

HOOK_NAME="templates"

# Read hook input from stdin — PostToolUse hooks receive JSON via stdin
INPUT=$(cat)

# Parse tool info from stdin JSON (env vars are NOT set for PostToolUse hooks)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
debug "INVOKE: TOOL=$TOOL PID=$$"

SKILL_NAME=""

if [ "$TOOL" = "Skill" ]; then
  # Path 1: Skill tool → extract skill name from tool_input
  SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
elif [ "$TOOL" = "Bash" ]; then
  # Path 2: Bash tool with engine session activate/continue → read skill from .state.json
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [[ "$BASH_CMD" == *"engine session activate"* ]] || [[ "$BASH_CMD" == *"engine session continue"* ]]; then
    local_session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
    if [ -n "$local_session_dir" ] && [ -f "$local_session_dir/.state.json" ]; then
      SKILL_NAME=$(jq -r '.skill // ""' "$local_session_dir/.state.json" 2>/dev/null || echo "")
      debug "bash-trigger: session=$local_session_dir skill=$SKILL_NAME"
    fi
  fi
else
  exit 0
fi

[ -n "$SKILL_NAME" ] || exit 0
debug "skill=$SKILL_NAME (via $TOOL)"

# Build list of files to preload
PRELOAD_PATHS=""

# Always include SKILL.md itself
skill_md="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"
if [ -f "$skill_md" ]; then
  skill_md_norm=$(normalize_preload_path "$skill_md")
  PRELOAD_PATHS="$skill_md_norm"
fi

# Get Phase 0 CMD files + templates
PHASE0_PATHS=$(extract_skill_preloads "$SKILL_NAME")
if [ -n "$PHASE0_PATHS" ]; then
  PRELOAD_PATHS="${PRELOAD_PATHS}${PRELOAD_PATHS:+
}${PHASE0_PATHS}"
fi

[ -n "$PRELOAD_PATHS" ] || exit 0

# Use preload_ensure(immediate) for each file — handles dedup, tracking, auto-expand
ADDITIONAL_CONTEXT=""
while IFS= read -r norm_path; do
  [ -n "$norm_path" ] || continue
  preload_ensure "$norm_path" "templates($SKILL_NAME)" "immediate"
  if [ "$_PRELOAD_RESULT" = "delivered" ] && [ -n "$_PRELOAD_CONTENT" ]; then
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}${ADDITIONAL_CONTEXT:+\n\n}$_PRELOAD_CONTENT"
    debug "DIRECT: $norm_path"
  else
    debug "SKIP: $norm_path (result=$_PRELOAD_RESULT)"
  fi
done <<< "$PRELOAD_PATHS"

# Output as direct additionalContext
if [ -n "$ADDITIONAL_CONTEXT" ]; then
  cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $(printf '%s' "$ADDITIONAL_CONTEXT" | jq -Rs .)
  }
}
HOOKEOF
fi

exit 0
