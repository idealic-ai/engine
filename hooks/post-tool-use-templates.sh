#!/bin/bash
# ~/.claude/engine/hooks/post-tool-use-templates.sh — PostToolUse hook for skill template preloading
#
# When the Skill tool is invoked:
# 1. Extracts Phase 0 CMD files + templates via extract_skill_preloads()
# 2. Delivers directly via PostToolUse additionalContext (zero latency)
# 3. If a session exists, queues to pendingPreloads + tracks in preloadedFiles for dedup

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [templates] $*" >> "$DEBUG_LOG"
  fi
}

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info — only process Skill tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ "$TOOL_NAME" != "Skill" ]; then
  exit 0
fi

# Extract skill name from tool_input
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
[ -n "$SKILL_NAME" ] || exit 0
debug "skill=$SKILL_NAME"

# Get preload paths via shared extraction function (CMDs + templates)
PRELOAD_PATHS=$(extract_skill_preloads "$SKILL_NAME")
[ -n "$PRELOAD_PATHS" ] || exit 0

# Build additionalContext with file contents (direct delivery)
ADDITIONAL_CONTEXT=""
while IFS= read -r norm_path; do
  [ -n "$norm_path" ] || continue
  # Resolve tilde path to absolute for reading
  abs_path="${norm_path/#\~/$HOME}"
  [ -f "$abs_path" ] || continue
  debug "DIRECT: $norm_path"
  content=$(cat "$abs_path" 2>/dev/null || true)
  [ -n "$content" ] || continue
  ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}${ADDITIONAL_CONTEXT:+\n\n}[Preloaded: $norm_path]\n$content"
done <<< "$PRELOAD_PATHS"

# If session exists: queue to pendingPreloads + track in preloadedFiles for dedup
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ] && jq empty "$SESSION_DIR/.state.json" 2>/dev/null; then
  PATHS_JSON="[]"
  while IFS= read -r norm_path; do
    [ -n "$norm_path" ] || continue
    PATHS_JSON=$(echo "$PATHS_JSON" | jq --arg f "$norm_path" '. + [$f]')
  done <<< "$PRELOAD_PATHS"

  PATHS_COUNT=$(echo "$PATHS_JSON" | jq 'length')
  if [ "$PATHS_COUNT" -gt 0 ]; then
    jq --argjson paths "$PATHS_JSON" '
      (.preloadedFiles // []) as $already |
      ($paths | map(select(. as $f | $already | any(. == $f) | not))) as $new |
      .preloadedFiles = ($already + $new) |
      if ($new | length) > 0 then .pendingPreloads = ((.pendingPreloads // []) + $new | unique) else . end
    ' "$SESSION_DIR/.state.json" | safe_json_write "$SESSION_DIR/.state.json"
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
