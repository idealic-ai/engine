#!/bin/bash
# ~/.claude/engine/hooks/post-tool-use-templates.sh — PostToolUse hook for skill template preloading
#
# Two paths:
#   Skill tool: Delivers SKILL.md + Phase 0 CMDs + templates + auto-expanded refs
#   Bash(engine session activate/continue): Delivers Phase 0 CMDs + templates + auto-expanded
#     SKILL.md refs only (SKILL.md itself arrives via command expansion or dehydration requiredFiles)

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
BASH_CMD=""

if [ "$TOOL" = "Skill" ]; then
  # Path 1: Skill tool → extract skill name from tool_input
  SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
elif [ "$TOOL" = "Bash" ]; then
  # Path 2: Bash tool with engine session activate/continue → read skill from .state.json
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  debug "BASH_CMD='${BASH_CMD:0:120}'"
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

# Resolve SKILL.md path
skill_md="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"
skill_md_norm=""
if [ -f "$skill_md" ]; then
  skill_md_norm=$(normalize_preload_path "$skill_md")
fi

# Build list of files to preload
PRELOAD_PATHS=""

# Skill tool path: deliver SKILL.md itself
# Bash path: skip SKILL.md (arrives via command expansion or dehydration requiredFiles)
if [ "$TOOL" = "Skill" ] && [ -n "$skill_md_norm" ]; then
  PRELOAD_PATHS="$skill_md_norm"
fi

# Get Phase 0 CMD files + templates (always — both paths need these)
PHASE0_PATHS=$(extract_skill_preloads "$SKILL_NAME")
if [ -n "$PHASE0_PATHS" ]; then
  PRELOAD_PATHS="${PRELOAD_PATHS}${PRELOAD_PATHS:+
}${PHASE0_PATHS}"
fi

# Deliver files via preload_ensure(immediate)
ADDITIONAL_CONTEXT=""
if [ -n "$PRELOAD_PATHS" ]; then
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
fi

# Bash path: discover SKILL.md prose refs (orchestrator CMDs, FMTs, INVs)
# even though SKILL.md itself wasn't delivered by this hook
if [ "$TOOL" = "Bash" ] && [ -n "$skill_md_norm" ]; then
  state_file=$(find_preload_state)
  if [ -n "$state_file" ]; then
    # Track SKILL.md in preloadedFiles (it's in context via other mechanisms)
    jq --arg p "$skill_md_norm" '
      (.preloadedFiles //= []) |
      if (.preloadedFiles | index($p)) then .
      else .preloadedFiles += [$p]
      end
    ' "$state_file" | safe_json_write "$state_file"
    # Discover refs — _auto_expand_refs queues them to pendingPreloads
    _auto_expand_refs "$skill_md_norm" "$state_file" "templates($SKILL_NAME)"
    debug "EXPAND: $skill_md_norm (refs discovered)"

    # Drain pendingPreloads immediately — don't wait for overflow-v2
    PENDING=$(jq -r '.pendingPreloads // [] | .[]' "$state_file" 2>/dev/null || echo "")
    if [ -n "$PENDING" ]; then
      DRAINED=""
      while IFS= read -r pend_path; do
        [ -n "$pend_path" ] || continue
        preload_ensure "$pend_path" "templates($SKILL_NAME):drain" "immediate"
        if [ "$_PRELOAD_RESULT" = "delivered" ] && [ -n "$_PRELOAD_CONTENT" ]; then
          ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}${ADDITIONAL_CONTEXT:+\n\n}$_PRELOAD_CONTENT"
          DRAINED="yes"
          debug "DRAIN: $pend_path"
        fi
      done <<< "$PENDING"
      # Clear drained items from pendingPreloads
      if [ -n "$DRAINED" ]; then
        jq '.pendingPreloads = []' "$state_file" | safe_json_write "$state_file"
      fi
    fi
  fi
fi

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
