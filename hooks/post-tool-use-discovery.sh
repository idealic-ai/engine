#!/bin/bash
# ~/.claude/hooks/post-tool-use-discovery.sh — PostToolUse hook for directory-aware discovery
#
# Tracks directories touched by Read/Edit/Write tools. When a new directory is encountered,
# runs discover-instructions.sh to find README.md, INVARIANTS.md (soft suggestions) and
# CHECKLIST.md (hard enforcement at session deactivation).
#
# State in .state.json:
#   touchedDirs: { "/abs/path": ["README.md"], "/other": [] }
#     Keys = directories encountered. Values = instruction files already suggested.
#   discoveredChecklists: ["/abs/path/CHECKLIST.md"]
#     All CHECKLIST.md files found — compared against processedChecklists at deactivate.
#
# Behavior:
#   - Only fires on Read, Edit, Write tools (matcher restricts to these)
#   - Extracts directory from tool_input.file_path
#   - If directory already in touchedDirs: skip (no re-discovery)
#   - If new directory: run discover-instructions.sh --walk-up --type soft
#   - Soft files (README.md, INVARIANTS.md): inject suggestion message
#   - Hard files (CHECKLIST.md): silently add to discoveredChecklists (enforced at deactivate)
#   - If no active session: skip (no state to write to)
#
# Related:
#   Scripts: (~/.claude/scripts/)
#     discover-instructions.sh — Core discovery logic
#     session.sh — Session state management
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_DIRECTORY_AWARENESS — Agents must be aware of directive markdown files
#     ¶INV_CHECKLIST_BEFORE_CLOSE — Session can't close with unprocessed checklists
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Graceful degradation without fleet

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Only process Read, Edit, Write tools
case "$TOOL_NAME" in
  Read|Edit|Write) ;;
  *) exit 0 ;;
esac

# Extract file_path from tool_input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
[ -n "$FILE_PATH" ] || exit 0

# Get directory from file path
DIR_PATH=$(dirname "$FILE_PATH")
[ -n "$DIR_PATH" ] || exit 0

# Skip engine/standards files — these are infrastructure, not project code
[[ "$DIR_PATH" != "$HOME/.claude/"* ]] || exit 0

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
  exit 0
fi

# New directory — register it in touchedDirs with empty array
jq --arg dir "$DIR_PATH" \
  '(.touchedDirs //= {}) | .touchedDirs[$dir] = []' \
  "$STATE_FILE" | safe_json_write "$STATE_FILE"

# Run discovery for soft files (README.md, INVARIANTS.md)
SOFT_FILES=$("$HOME/.claude/scripts/discover-instructions.sh" "$DIR_PATH" --walk-up --type soft 2>/dev/null || echo "")

# Run discovery for hard files (CHECKLIST.md)
HARD_FILES=$("$HOME/.claude/scripts/discover-instructions.sh" "$DIR_PATH" --walk-up --type hard 2>/dev/null || echo "")

# Track which soft files are new (not already suggested for another dir)
NEW_SOFT_FILES=()
if [ -n "$SOFT_FILES" ]; then
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Check if this file was already suggested via any other touchedDir
    already_suggested=$(jq -r --arg file "$(basename "$file")" \
      '[(.touchedDirs // {}) | to_entries[] | .value[] | select(. == $file)] | length > 0' \
      "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$already_suggested" != "true" ]; then
      NEW_SOFT_FILES+=("$file")
    fi
  done <<< "$SOFT_FILES"
fi

# Update touchedDirs with the files we're about to suggest
if [ ${#NEW_SOFT_FILES[@]} -gt 0 ]; then
  # Build JSON array of unique basenames
  FILENAMES_JSON="[]"
  for f in "${NEW_SOFT_FILES[@]}"; do
    FILENAMES_JSON=$(echo "$FILENAMES_JSON" | jq --arg name "$(basename "$f")" '. + [$name] | unique')
  done
  jq --arg dir "$DIR_PATH" --argjson names "$FILENAMES_JSON" \
    '(.touchedDirs //= {}) | .touchedDirs[$dir] = $names' \
    "$STATE_FILE" | safe_json_write "$STATE_FILE"
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
    "message": "¶INV_DIRECTORY_AWARENESS: Directive files discovered near ${DIR_PATH}:${FILE_LIST}\nConsider reading these for context relevant to your current work."
  }
}
HOOKEOF
  exit 0
fi

# No new suggestions — silent exit
exit 0
