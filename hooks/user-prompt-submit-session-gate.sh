#!/bin/bash
# ~/.claude/hooks/user-prompt-submit-session-gate.sh — UserPromptSubmit hook for session gate
#
# Injects a system message instructing the agent to load standards and select a skill/session
# when no active session exists (or session is completed).
#
# This hook complements pre-tool-use-session-gate.sh:
#   - PreToolUse gate BLOCKS tools (reactive)
#   - UserPromptSubmit gate INSTRUCTS the agent (proactive)
#
# Logic:
#   1. If SESSION_REQUIRED != 1 → pass (no injection)
#   2. If session.sh find succeeds AND lifecycle is active/dehydrating → pass
#   3. Otherwise → inject boot sequence instructions
#
# Hook receives JSON on stdin with: session_id, transcript_path
# Output: JSON with hookSpecificOutput.message to inject system message, or empty for pass-through
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — Session lifecycle, activation gate
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_SKILL_PROTOCOL_MANDATORY — Skills require formal session activation
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_REQUIRE_ACTIVE_SESSION — This hook enforces it

set -euo pipefail

# Gate check: if SESSION_REQUIRED is not set or not "1", pass through
if [ "${SESSION_REQUIRED:-}" != "1" ]; then
  exit 0
fi

# Try to find an active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")

if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  LIFECYCLE=$(jq -r '.lifecycle // "active"' "$SESSION_DIR/.state.json" 2>/dev/null || echo "active")

  # Active or dehydrating sessions — no injection needed
  if [ "$LIFECYCLE" = "active" ] || [ "$LIFECYCLE" = "dehydrating" ]; then
    exit 0
  fi

  # Completed session — inject continuation prompt
  SKILL=$(jq -r '.skill // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  SESSION_NAME=$(basename "$SESSION_DIR")

  MESSAGE="§CMD_REQUIRE_ACTIVE_SESSION: Previous session '$SESSION_NAME' (skill: $SKILL) is completed."
  MESSAGE="$MESSAGE\n\nBoot sequence:\n1. Read ~/.claude/directives/COMMANDS.md, ~/.claude/directives/INVARIANTS.md, and ~/.claude/directives/TAGS.md\n2. Read .claude/directives/INVARIANTS.md (project standards)\n3. Use AskUserQuestion to ask: 'Your previous session ($SESSION_NAME / $SKILL) is complete. Would you like to continue it, or start a new session with a different skill?'"

  cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "message": "$MESSAGE"
  }
}
HOOKEOF
  exit 0
fi

# No session at all — inject full boot sequence
MESSAGE="§CMD_REQUIRE_ACTIVE_SESSION: No active session. You must activate a session before doing any work."
MESSAGE="$MESSAGE\n\nBoot sequence:\n1. Read ~/.claude/directives/COMMANDS.md, ~/.claude/directives/INVARIANTS.md, and ~/.claude/directives/TAGS.md\n2. Read .claude/directives/INVARIANTS.md (project standards)\n3. Use AskUserQuestion to ask which skill the user wants to use (e.g., /implement, /analyze, /fix, /brainstorm, /test)"

cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "message": "$MESSAGE"
  }
}
HOOKEOF
exit 0
