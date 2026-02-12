#!/bin/bash
# ~/.claude/hooks/post-tool-use-details-log.sh — PostToolUse hook for auto-logging AskUserQuestion
#
# Automatically logs every AskUserQuestion interaction to the session's DETAILS.md.
# Captures: agent's preamble (from transcript), questions, options, and user's answers.
# Removes the agent's burden of manual §CMD_LOG_INTERACTION for Q&A logging.
#
# Input (stdin): PostToolUse JSON with tool_name, tool_input, tool_response, transcript_path
# Output: Appends formatted entry to [sessionDir]/DETAILS.md via engine log
#
# Matcher: "AskUserQuestion" in settings.json (only fires for this tool)
#
# Related:
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_LOG_INTERACTION — Manual logging this hook replaces
#   Templates: (~/.claude/skills/_shared/TEMPLATE_DETAILS.md)
#   Hooks: (~/.claude/engine/hooks/)
#     post-tool-use-discovery.sh — Reference PostToolUse pattern

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Escape lifecycle tag references to prevent tag.sh find pollution (¶INV_ESCAPE_BY_DEFAULT)
# Wraps bare #needs-*, #delegated-*, #next-*, #claimed-*, #done-*, #active-alert in backticks.
# Skips already-backticked tags. Uses perl for negative lookbehind (BSD sed lacks it).
escape_tags() {
  perl -pe 's/(?<!`)#((?:needs|delegated|next|claimed|done)-\w+|active-alert)(?![\w-])(?!`)/`#$1`/g'
}

# Read hook input from stdin
INPUT=$(cat)

# Parse tool name — guard against non-AskUserQuestion calls
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
[ "$TOOL_NAME" = "AskUserQuestion" ] || exit 0

# Find active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] || exit 0

STATE_FILE="$SESSION_DIR/.state.json"
[ -f "$STATE_FILE" ] || exit 0

# Extract transcript path for preamble capture
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

# --- Extract preamble from transcript ---
PREAMBLE=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # tail last 200 lines, find the last assistant entry with text content (not tool_use)
  # Parse backward: last assistant message before the AskUserQuestion tool_use
  PREAMBLE=$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null | \
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | \
    tail -n 1 || echo "")

  # Truncate to ~2000 chars if very long
  if [ ${#PREAMBLE} -gt 2000 ]; then
    PREAMBLE="${PREAMBLE:0:2000}..."
  fi
fi

# --- Extract questions and answers ---
# Get the first question's header for the DETAILS.md heading
HEADER=$(echo "$INPUT" | jq -r '.tool_input.questions[0].header // "Q&A"' 2>/dev/null || echo "Q&A")

# Get first question text, truncated for heading
FIRST_Q=$(echo "$INPUT" | jq -r '.tool_input.questions[0].question // ""' 2>/dev/null || echo "")
FIRST_Q_SHORT="${FIRST_Q:0:60}"
[ ${#FIRST_Q} -gt 60 ] && FIRST_Q_SHORT="${FIRST_Q_SHORT}..."

# Format all questions with options
QUESTIONS_BLOCK=""
Q_COUNT=$(echo "$INPUT" | jq -r '.tool_input.questions | length' 2>/dev/null || echo "0")

for ((i=0; i<Q_COUNT; i++)); do
  Q_TEXT=$(echo "$INPUT" | jq -r ".tool_input.questions[$i].question // \"\"" 2>/dev/null || echo "")
  Q_MULTI=$(echo "$INPUT" | jq -r ".tool_input.questions[$i].multiSelect // false" 2>/dev/null || echo "false")

  # Build options list: "label1 / label2 / label3"
  OPTIONS=$(echo "$INPUT" | jq -r ".tool_input.questions[$i].options[]?.label // empty" 2>/dev/null | awk '{printf "%s%s", sep, $0; sep=" / "}' || echo "")

  if [ "$Q_COUNT" -gt 1 ]; then
    QUESTIONS_BLOCK="${QUESTIONS_BLOCK}> Q$((i+1)): ${Q_TEXT}"$'\n'
  else
    QUESTIONS_BLOCK="${QUESTIONS_BLOCK}> ${Q_TEXT}"$'\n'
  fi

  if [ -n "$OPTIONS" ]; then
    QUESTIONS_BLOCK="${QUESTIONS_BLOCK}> Options: ${OPTIONS}"$'\n'
  fi
  if [ "$Q_MULTI" = "true" ]; then
    QUESTIONS_BLOCK="${QUESTIONS_BLOCK}> *(multi-select)*"$'\n'
  fi
  if [ "$i" -lt $((Q_COUNT - 1)) ]; then
    QUESTIONS_BLOCK="${QUESTIONS_BLOCK}>"$'\n'
  fi
done

# Extract user response
USER_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
# If tool_response is a JSON object (structured answers), stringify it nicely
if echo "$USER_RESPONSE" | jq empty 2>/dev/null; then
  # It's valid JSON — check if it's a string or object
  RESPONSE_TYPE=$(echo "$INPUT" | jq -r '.tool_response | type' 2>/dev/null || echo "string")
  if [ "$RESPONSE_TYPE" = "object" ]; then
    USER_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response | to_entries | map("\(.key): \(.value)") | join("\n")' 2>/dev/null || echo "$USER_RESPONSE")
  fi
fi

# --- Escape tag references in all content sources (¶INV_ESCAPE_BY_DEFAULT) ---
PREAMBLE=$(printf '%s' "$PREAMBLE" | escape_tags)
QUESTIONS_BLOCK=$(printf '%s' "$QUESTIONS_BLOCK" | escape_tags)
USER_RESPONSE=$(printf '%s' "$USER_RESPONSE" | escape_tags)
HEADER=$(printf '%s' "$HEADER" | escape_tags)
FIRST_Q_SHORT=$(printf '%s' "$FIRST_Q_SHORT" | escape_tags)

# --- Build the DETAILS.md entry ---
ENTRY="## ${HEADER} — ${FIRST_Q_SHORT}"$'\n'
ENTRY="${ENTRY}**Type**: Q&A (auto-logged)"$'\n'
ENTRY="${ENTRY}"$'\n'

# Add premise if available
if [ -n "$PREAMBLE" ]; then
  # Prefix each line with > for blockquote
  PREMISE_QUOTED=$(echo "$PREAMBLE" | sed 's/^/> /')
  ENTRY="${ENTRY}**Premise**:"$'\n'
  ENTRY="${ENTRY}${PREMISE_QUOTED}"$'\n'
  ENTRY="${ENTRY}"$'\n'
fi

ENTRY="${ENTRY}**Agent**:"$'\n'
ENTRY="${ENTRY}${QUESTIONS_BLOCK}"$'\n'
ENTRY="${ENTRY}**User**:"$'\n'
# Quote user response
USER_QUOTED=$(echo "$USER_RESPONSE" | sed 's/^/> /')
ENTRY="${ENTRY}${USER_QUOTED}"$'\n'
ENTRY="${ENTRY}"$'\n'
ENTRY="${ENTRY}---"

# Append to DETAILS.md via engine log
"$HOME/.claude/scripts/log.sh" "$SESSION_DIR/DETAILS.md" <<LOGEOF
${ENTRY}
LOGEOF

exit 0
