#!/bin/bash
# ~/.claude/hooks/post-tool-use-discovery.sh — PostToolUse hook for directory-aware discovery
#
# Tracks directories touched by Read/Edit/Write tools. When a new directory is encountered,
# runs discover-directives.sh to find directive files.
#
# Directive tiers:
#   Soft (suggested): AGENTS.md, INVARIANTS.md, TESTING.md, PITFALLS.md, TEMPLATE.md
#   Hard (enforced at deactivation): CHECKLIST.md
#
# Skill filtering:
#   Core directives (AGENTS.md, INVARIANTS.md, CHECKLIST.md) are always discovered.
#   Skill directives (TESTING.md, PITFALLS.md) are only suggested when the active skill
#   declares them in the `directives` field of session parameters.
#
# State in .state.json:
#   touchedDirs: { "/abs/path": ["/abs/path/.directives/AGENTS.md"], "/other": [] }
#     Keys = directories encountered. Values = full paths of directive files already suggested.
#   discoveredChecklists: ["/abs/path/CHECKLIST.md"]
#     All CHECKLIST.md files found — compared against processedChecklists at deactivate.
#   directives: ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"]
#     Skill-declared directive types (from session parameters).
#   pendingDirectives: ["/abs/path/AGENTS.md", "/abs/path/INVARIANTS.md"]
#     Directive files discovered but not yet read by the agent. Cleared by
#     pre-tool-use-directive-gate.sh when the agent reads each file.
#   directiveReadsWithoutClearing: 0
#     Counter of tool calls since pendingDirectives was last populated. Used by
#     the directive gate hook for escalating enforcement.
#
# Behavior:
#   - Only fires on Read, Edit, Write tools (matcher restricts to these)
#   - Extracts directory from tool_input.file_path
#   - If directory already in touchedDirs: skip (no re-discovery)
#   - If new directory: run discover-directives.sh --walk-up
#   - Core soft files (AGENTS.md, INVARIANTS.md): always inject suggestion
#   - Skill soft files (TESTING.md, PITFALLS.md): only suggest if in `directives` array
#   - Hard files (CHECKLIST.md): silently add to discoveredChecklists (enforced at deactivate)
#   - If no active session: skip (no state to write to)
#
# Related:
#   Scripts: (~/.claude/scripts/)
#     discover-directives.sh — Core discovery logic
#     session.sh — Session state management
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_DIRECTIVE_STACK — Agents must be aware of directive markdown files
#     ¶INV_CHECKLIST_BEFORE_CLOSE — Session can't close with unprocessed checklists
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Graceful degradation without fleet

set -euo pipefail

# Debug logging — enable with HOOK_DEBUG=1 or check /tmp/hooks-debug-enabled
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [discovery] $*" >> "$DEBUG_LOG"
  fi
}

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Only process Read, Edit, Write tools
case "$TOOL_NAME" in
  Read|Edit|Write) ;;
  *) debug "skip: tool=$TOOL_NAME (not Read/Edit/Write)"; exit 0 ;;
esac

# Extract file_path from tool_input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
[ -n "$FILE_PATH" ] || exit 0

# Get directory from file path
DIR_PATH=$(dirname "$FILE_PATH")
[ -n "$DIR_PATH" ] || exit 0
debug "tool=$TOOL_NAME file=$FILE_PATH dir=$DIR_PATH"

# Multi-root: if path is under ~/.claude/, pass --root to cap walk-up
ROOT_ARG=""
if [[ "$DIR_PATH" == "$HOME/.claude/"* ]]; then
  ROOT_ARG="--root $HOME/.claude"
  debug "multi-root: using --root $HOME/.claude"
fi

# Find active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] || exit 0

STATE_FILE="$SESSION_DIR/.state.json"
[ -f "$STATE_FILE" ] || exit 0

# Auto-track checklist reads: if this Read targets a file in discoveredChecklists, mark it read
if [ "$TOOL_NAME" = "Read" ]; then
  IS_DISCOVERED_CHECKLIST=$(jq -r --arg fp "$FILE_PATH" \
    '(.discoveredChecklists // []) | any(. == $fp)' "$STATE_FILE" 2>/dev/null || echo "false")
  if [ "$IS_DISCOVERED_CHECKLIST" = "true" ]; then
    ALREADY_READ=$(jq -r --arg fp "$FILE_PATH" \
      '(.readChecklists // []) | any(. == $fp)' "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$ALREADY_READ" != "true" ]; then
      jq --arg fp "$FILE_PATH" \
        '(.readChecklists //= []) | .readChecklists += [$fp] | .readChecklists |= unique' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi
  fi
fi

# Check if this directory is already tracked in touchedDirs
ALREADY_TRACKED=$(jq -r --arg dir "$DIR_PATH" \
  '(.touchedDirs // {}) | has($dir)' "$STATE_FILE" 2>/dev/null || echo "false")

if [ "$ALREADY_TRACKED" = "true" ]; then
  debug "skip: dir already tracked"
  exit 0
fi
debug "NEW dir — running discovery"

# New directory — register it in touchedDirs with empty array
jq --arg dir "$DIR_PATH" \
  '(.touchedDirs //= {}) | .touchedDirs[$dir] = []' \
  "$STATE_FILE" | safe_json_write "$STATE_FILE"

# Run discovery for soft files (AGENTS.md, INVARIANTS.md, TESTING.md, PITFALLS.md)
SOFT_FILES=$("$HOME/.claude/scripts/discover-directives.sh" "$DIR_PATH" --walk-up --type soft $ROOT_ARG 2>/dev/null || echo "")

# Run discovery for hard files (CHECKLIST.md)
HARD_FILES=$("$HOME/.claude/scripts/discover-directives.sh" "$DIR_PATH" --walk-up --type hard $ROOT_ARG 2>/dev/null || echo "")

# Core directives are always suggested; skill directives need declaration
CORE_DIRECTIVES=("AGENTS.md" "INVARIANTS.md")

# Read skill-declared directives from .state.json
SKILL_DIRECTIVES=$(jq -r '(.directives // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")

# Track which soft files are new (not already suggested for another dir)
NEW_SOFT_FILES=()
if [ -n "$SOFT_FILES" ]; then
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    local_basename=$(basename "$file")

    # Check if this is a core directive (always suggested) or skill directive (needs declaration)
    is_core=false
    for core in "${CORE_DIRECTIVES[@]}"; do
      if [ "$local_basename" = "$core" ]; then
        is_core=true
        break
      fi
    done

    if [ "$is_core" = "false" ]; then
      # Skill directive — check if declared
      is_declared=false
      if [ -n "$SKILL_DIRECTIVES" ]; then
        while IFS= read -r declared; do
          if [ "$local_basename" = "$declared" ]; then
            is_declared=true
            break
          fi
        done <<< "$SKILL_DIRECTIVES"
      fi
      if [ "$is_declared" = "false" ]; then
        continue  # Skip — skill doesn't care about this directive type
      fi
    fi

    # Check if this exact file (full path) was already suggested via any other touchedDir
    already_suggested=$(jq -r --arg file "$file" \
      '[(.touchedDirs // {}) | to_entries[] | .value[] | select(. == $file)] | length > 0' \
      "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$already_suggested" != "true" ]; then
      NEW_SOFT_FILES+=("$file")
    fi
  done <<< "$SOFT_FILES"
fi

# Update touchedDirs with the files we're about to suggest
if [ ${#NEW_SOFT_FILES[@]} -gt 0 ]; then
  # Build JSON array of full paths (not basenames) for accurate dedup
  FILENAMES_JSON="[]"
  for f in "${NEW_SOFT_FILES[@]}"; do
    FILENAMES_JSON=$(echo "$FILENAMES_JSON" | jq --arg name "$f" '. + [$name] | unique')
  done
  jq --arg dir "$DIR_PATH" --argjson names "$FILENAMES_JSON" \
    '(.touchedDirs //= {}) | .touchedDirs[$dir] = $names' \
    "$STATE_FILE" | safe_json_write "$STATE_FILE"
fi

# Add new soft files to pendingDirectives for enforcement gate (skip already-preloaded)
if [ ${#NEW_SOFT_FILES[@]} -gt 0 ]; then
  for f in "${NEW_SOFT_FILES[@]}"; do
    # Skip if already preloaded (prevents double-loading after re-discovery)
    already_preloaded=$(jq -r --arg file "$f" \
      '(.preloadedFiles // []) | any(. == $file)' "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$already_preloaded" = "true" ]; then
      debug "SKIP pendingDirectives: $f (already in preloadedFiles)"
      continue
    fi
    debug "ADD pendingDirectives: $f"
    jq --arg file "$f" \
      '(.pendingDirectives //= []) | if (.pendingDirectives | index($file)) then . else .pendingDirectives += [$file] end' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"
  done
  # Reset the directive-read counter when new directives are added
  jq '.directiveReadsWithoutClearing = 0' "$STATE_FILE" | safe_json_write "$STATE_FILE"
fi

# Add new CHECKLIST.md files to discoveredChecklists
if [ -n "$HARD_FILES" ]; then
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Add to discoveredChecklists if not already there
    jq --arg file "$file" \
      '(.discoveredChecklists //= []) | if (.discoveredChecklists | index($file)) then . else .discoveredChecklists += [$file] end' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"
  done <<< "$HARD_FILES"
fi

# Output suggestion message for new soft files
if [ ${#NEW_SOFT_FILES[@]} -gt 0 ]; then
  # Build the suggestion message
  FILE_LIST=""
  for f in "${NEW_SOFT_FILES[@]}"; do
    FILE_LIST="${FILE_LIST}\n  - ${f}"
  done

  cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "message": "¶INV_DIRECTIVE_STACK: Directives discovered near ${DIR_PATH}:${FILE_LIST}\nConsider reading these for context relevant to your current work."
  }
}
HOOKEOF
  exit 0
fi

# No new suggestions — silent exit
exit 0
