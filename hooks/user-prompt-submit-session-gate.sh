#!/bin/bash
# ~/.claude/engine/hooks/user-prompt-submit-session-gate.sh — UserPromptSubmit hook
#
# Two responsibilities:
#   1. Skill signal: On skill detection (/skill-name at start of prompt), emits a short
#      additionalContext telling the agent to activate the skill. Actual preloading happens
#      in post-tool-use-templates.sh when the Skill tool fires.
#   2. Session gate: Injects boot instructions when no active session exists.
#
# Hook receives JSON on stdin with: prompt, session_id, transcript_path
# Output: JSON with hookSpecificOutput.additionalContext, or empty for pass-through

set -euo pipefail

source "$HOME/.claude/scripts/lib.sh"

# Gate check: if SESSION_REQUIRED is not set or not "1", pass through
if [ "${SESSION_REQUIRED:-}" != "1" ]; then
  exit 0
fi

# Read hook input
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

# Find session once (used by gate check)
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")

# --- Skill signal removed ---
# Previously emitted "Dont forget to activate /X as a tool call, IMPORTANT" but this is
# no longer needed: post-tool-use-templates.sh now loads Phase 0 CMDs + SKILL.md refs
# on engine session activate/continue regardless of whether the Skill tool was used.
SKILL_ADDITIONAL_CONTEXT=""

# --- Session gate: inject boot instructions if no active session ---
GATE_MESSAGE=""
if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ] && jq empty "$SESSION_DIR/.state.json" 2>/dev/null; then
  LIFECYCLE=$(jq -r '.lifecycle // "active"' "$SESSION_DIR/.state.json" 2>/dev/null || echo "active")

  if [ "$LIFECYCLE" != "active" ] && [ "$LIFECYCLE" != "dehydrating" ] && [ "$LIFECYCLE" != "resuming" ] && [ "$LIFECYCLE" != "restarting" ]; then
    # Completed session — inject continuation prompt
    SKILL=$(jq -r '.skill // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
    SESSION_NAME=$(basename "$SESSION_DIR")
    GATE_MESSAGE="§CMD_REQUIRE_ACTIVE_SESSION: Previous session '$SESSION_NAME' (skill: $SKILL) is completed.\nUse AskUserQuestion to ask: 'Your previous session ($SESSION_NAME / $SKILL) is complete. Continue it, start a new session (/do for quick tasks, or /implement, /analyze, etc.), or describe new work?'"
  fi
else
  # No session at all — inject skill selection instruction
  GATE_MESSAGE="§CMD_REQUIRE_ACTIVE_SESSION: No active session.\nUse AskUserQuestion to ask: 'No active session. Use /do for quick tasks, or pick a skill (/implement, /analyze, /fix, /test), or describe new work.'"
fi

# --- Output: combine skill signal + gate message ---
COMBINED=""
if [ -n "$SKILL_ADDITIONAL_CONTEXT" ]; then
  COMBINED="$SKILL_ADDITIONAL_CONTEXT"
fi
if [ -n "$GATE_MESSAGE" ]; then
  GATE_MESSAGE=$(printf '%b' "$GATE_MESSAGE")
  if [ -n "$COMBINED" ]; then
    COMBINED="${COMBINED}\n\n${GATE_MESSAGE}"
  else
    COMBINED="$GATE_MESSAGE"
  fi
fi

if [ -n "$COMBINED" ]; then
  jq -n --arg msg "$COMBINED" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
fi

exit 0
