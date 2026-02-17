#!/bin/bash
# ~/.claude/engine/hooks/user-prompt-submit-freeform-chat.sh — UserPromptSubmit hook
#
# Captures free-form user chat messages (>50 chars) into the session's DIALOGUE.md.
# Complements post-tool-use-details-log.sh which handles AskUserQuestion interactions.
#
# Input (stdin): UserPromptSubmit JSON with: prompt, session_id, transcript_path
# Output: empty (no additionalContext needed — this is a silent logger)
#
# Filters:
#   - Messages starting with / (skill invocations)
#   - Messages <= 50 characters
#   - No active session
#
# Related:
#   Hooks: post-tool-use-details-log.sh — AskUserQuestion auto-logging (same target file)
#   Templates: TEMPLATE_DIALOGUE.md (formerly TEMPLATE_DETAILS.md)

set -euo pipefail

source "$HOME/.claude/scripts/lib.sh"

# Escape lifecycle tag references (¶INV_ESCAPE_BY_DEFAULT)
escape_tags() {
  perl -pe 's/(?<!`)#((?:needs|delegated|next|claimed|done)-\w+|active-alert)(?![\w-])(?!`)/`#$1`/g'
}

# Read hook input
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")

# --- Filters ---

# Skip empty
[ -n "$PROMPT" ] || exit 0

# Skip slash commands
case "$PROMPT" in
  /*) exit 0 ;;
esac

# Skip short messages (<=50 chars)
[ ${#PROMPT} -gt 50 ] || exit 0

# --- Find active session ---
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] || exit 0
[ -f "$SESSION_DIR/.state.json" ] || exit 0

# Check lifecycle — only log for active sessions
LIFECYCLE=$(state_read "$SESSION_DIR/.state.json" "lifecycle" "active")
if [ "$LIFECYCLE" != "active" ] && [ "$LIFECYCLE" != "resuming" ]; then
  exit 0
fi

# --- Extract agent's preceding text response from transcript ---
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
AGENT_CONTEXT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Get last assistant text entry. If it looks like a Q&A block (from AskUserQuestion),
  # just note it as a reference instead of duplicating.
  LAST_TEXT=$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null | \
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | \
    tail -n 1 || echo "")

  if [ -n "$LAST_TEXT" ]; then
    # Check if the preceding message was a Q&A interaction (contains AskUserQuestion markers)
    if echo "$LAST_TEXT" | grep -q "AskUserQuestion\|User has answered your questions" 2>/dev/null; then
      AGENT_CONTEXT="*(Follows a Q&A interaction — see previous DIALOGUE.md entry)*"
    else
      # Truncate to ~1500 chars
      if [ ${#LAST_TEXT} -gt 1500 ]; then
        LAST_TEXT="${LAST_TEXT:0:1500}..."
      fi
      AGENT_CONTEXT="$LAST_TEXT"
    fi
  fi
fi

# --- Build heading from first 60 chars of user message ---
FIRST_LINE=$(echo "$PROMPT" | head -n 1)
HEADING_TEXT="${FIRST_LINE:0:60}"
[ ${#FIRST_LINE} -gt 60 ] && HEADING_TEXT="${HEADING_TEXT}..."

# --- Escape tags in all content ---
HEADING_TEXT=$(printf '%s' "$HEADING_TEXT" | escape_tags)
PROMPT_ESCAPED=$(printf '%s' "$PROMPT" | escape_tags)
AGENT_CONTEXT=$(printf '%s' "$AGENT_CONTEXT" | escape_tags)

# --- Build the DIALOGUE.md entry ---
ENTRY="## User Note — ${HEADING_TEXT}"$'\n'
ENTRY="${ENTRY}**Type**: Chat (auto-logged)"$'\n'
ENTRY="${ENTRY}"$'\n'

# Add agent context if available
if [ -n "$AGENT_CONTEXT" ]; then
  AGENT_QUOTED=$(echo "$AGENT_CONTEXT" | sed 's/^/> /')
  ENTRY="${ENTRY}**Agent**:"$'\n'
  ENTRY="${ENTRY}${AGENT_QUOTED}"$'\n'
  ENTRY="${ENTRY}"$'\n'
fi

ENTRY="${ENTRY}**User**:"$'\n'
USER_QUOTED=$(echo "$PROMPT_ESCAPED" | sed 's/^/> /')
ENTRY="${ENTRY}${USER_QUOTED}"$'\n'
ENTRY="${ENTRY}"$'\n'
ENTRY="${ENTRY}---"

# Append to DIALOGUE.md via engine log
printf '%s\n' "$ENTRY" | "$HOME/.claude/scripts/log.sh" "$SESSION_DIR/DIALOGUE.md"

exit 0
