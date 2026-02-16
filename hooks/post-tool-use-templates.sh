#!/bin/bash
# ~/.claude/engine/hooks/post-tool-use-templates.sh — PostToolUse hook for skill template preloading
#
# When the Skill tool is invoked:
# 1. Extracts Phase 0 CMD files + templates via extract_skill_preloads()
# 2. Delivers directly via PostToolUse additionalContext (zero latency)
# 3. If a session exists, tracks in preloadedFiles for dedup (NOT pendingPreloads — already delivered)

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

# Read hook input from stdin — PostToolUse hooks receive JSON via stdin
INPUT=$(cat)

# Parse tool info from stdin JSON (env vars are NOT set for PostToolUse hooks)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
debug "INVOKE: TOOL=$TOOL PID=$$"

SKILL_NAME=""
_cached_session_dir=""

if [ "$TOOL" = "Skill" ]; then
  # Path 1: Skill tool → extract skill name from tool_input
  SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
elif [ "$TOOL" = "Bash" ]; then
  # Path 2: Bash tool with engine session activate/continue → read skill from .state.json
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [[ "$BASH_CMD" == *"engine session activate"* ]] || [[ "$BASH_CMD" == *"engine session continue"* ]]; then
    _cached_session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
    if [ -n "$_cached_session_dir" ] && [ -f "$_cached_session_dir/.state.json" ]; then
      SKILL_NAME=$(jq -r '.skill // ""' "$_cached_session_dir/.state.json" 2>/dev/null || echo "")
      debug "bash-trigger: session=$_cached_session_dir skill=$SKILL_NAME"
    fi
  fi
else
  exit 0
fi

[ -n "$SKILL_NAME" ] || exit 0
debug "skill=$SKILL_NAME (via $TOOL)"

# Get preload paths via shared extraction function (CMDs + templates)
PRELOAD_PATHS=$(extract_skill_preloads "$SKILL_NAME")

# For Bash trigger: also include SKILL.md itself (Skill tool path gets it via UserPromptSubmit)
if [ "$TOOL" = "Bash" ]; then
  skill_md="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"
  if [ -f "$skill_md" ]; then
    skill_md_norm=$(normalize_preload_path "$skill_md")
    PRELOAD_PATHS="${skill_md_norm}${PRELOAD_PATHS:+
$PRELOAD_PATHS}"
  fi
fi

[ -n "$PRELOAD_PATHS" ] || exit 0

# Filter out files already preloaded — checks session state, falls back to SessionStart seeds.
SESSION_DIR="${_cached_session_dir:-$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")}"
if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  ALREADY_LOADED=$(jq -r '(.preloadedFiles // []) | .[]' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  if [ -n "$ALREADY_LOADED" ]; then
    FILTERED_PATHS=""
    while IFS= read -r norm_path; do
      [ -n "$norm_path" ] || continue
      skip=false
      while IFS= read -r loaded; do
        [ -n "$loaded" ] || continue
        if [ "$norm_path" = "$loaded" ]; then
          skip=true
          debug "SKIP (already preloaded): $norm_path"
          break
        fi
      done <<< "$ALREADY_LOADED"
      if [ "$skip" = false ]; then
        FILTERED_PATHS="${FILTERED_PATHS}${FILTERED_PATHS:+
}${norm_path}"
      fi
    done <<< "$PRELOAD_PATHS"
    PRELOAD_PATHS="$FILTERED_PATHS"
  fi
else
  # No active session — filter against SessionStart seeds (shared function in lib.sh)
  PRELOAD_PATHS=$(filter_preseeded_paths "$PRELOAD_PATHS")
  debug "filtered against SessionStart seeds (no active session)"
fi
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
# Wrapped in subshell with || true — .state.json update is best-effort dedup tracking.
# Failure here must NOT block additionalContext delivery (Pitfall #2, #5).
SESSION_DIR="${_cached_session_dir:-$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")}"
if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  (
    jq empty "$SESSION_DIR/.state.json" 2>/dev/null || exit 0

    PATHS_JSON="[]"
    while IFS= read -r norm_path; do
      [ -n "$norm_path" ] || continue
      PATHS_JSON=$(echo "$PATHS_JSON" | jq --arg f "$norm_path" '. + [$f]')
    done <<< "$PRELOAD_PATHS"

    PATHS_COUNT=$(echo "$PATHS_JSON" | jq 'length')
    if [ "$PATHS_COUNT" -gt 0 ]; then
      # Track in preloadedFiles for dedup only — do NOT add to pendingPreloads.
      # These files are already delivered via additionalContext in this hook invocation.
      # Adding to pendingPreloads would cause overflow-v2 to re-deliver them.
      jq --argjson paths "$PATHS_JSON" '
        (.preloadedFiles // []) as $already |
        ($paths | map(select(. as $f | $already | any(. == $f) | not))) as $new |
        .preloadedFiles = ($already + $new)
      ' "$SESSION_DIR/.state.json" | safe_json_write "$SESSION_DIR/.state.json"
    fi

    # --- Resolve § references in delivered files (recursive preloading) ---
    # Scan each preloaded file for §CMD_*, §FMT_*, §INV_* references.
    # Discovered refs are queued in pendingPreloads for lazy loading on next tool call.
    # Also scans SKILL.md itself — UserPromptSubmit delivers it but doesn't call resolve_refs.
    # NOTE: No 'local' in this block — we're inside a subshell ( ... ), not a function.
    all_new_refs=""
    current_loaded=$(jq '.preloadedFiles // []' "$SESSION_DIR/.state.json" 2>/dev/null || echo '[]')

    # Build scan list: Phase 0 CMDs + SKILL.md itself
    scan_paths="$PRELOAD_PATHS"
    skill_md_path="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"
    if [ -f "$skill_md_path" ]; then
      skill_md_norm=$(normalize_preload_path "$skill_md_path")
      scan_paths="${scan_paths}
${skill_md_norm}"
    fi

    while IFS= read -r norm_path; do
      [ -n "$norm_path" ] || continue
      abs_path="${norm_path/#\~/$HOME}"
      [ -f "$abs_path" ] || continue
      refs=$(resolve_refs "$abs_path" 2 "$current_loaded") || true
      if [ -n "$refs" ]; then
        all_new_refs="${all_new_refs}${all_new_refs:+
}${refs}"
        while IFS= read -r rpath; do
          [ -n "$rpath" ] || continue
          current_loaded=$(echo "$current_loaded" | jq --arg p "$rpath" '. + [$p]')
        done <<< "$refs"
      fi
    done <<< "$scan_paths"

    if [ -n "$all_new_refs" ]; then
      refs_json="[]"
      while IFS= read -r ref_path; do
        [ -n "$ref_path" ] || continue
        refs_json=$(echo "$refs_json" | jq --arg f "$ref_path" '. + [$f]')
      done <<< "$all_new_refs"

      jq --argjson refs "$refs_json" '
        (.preloadedFiles // []) as $pf |
        (.pendingPreloads //= []) |
        reduce ($refs[]) as $r (.;
          if ($pf | any(. == $r)) then .
          elif (.pendingPreloads | index($r)) then .
          else .pendingPreloads += [$r]
          end
        )
      ' "$SESSION_DIR/.state.json" | safe_json_write "$SESSION_DIR/.state.json"
    fi
  ) 2>/dev/null || true
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
