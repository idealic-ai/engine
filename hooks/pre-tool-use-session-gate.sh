#!/bin/bash
# ~/.claude/hooks/pre-tool-use-session-gate.sh — PreToolUse hook for session activation gate
#
# Blocks all non-whitelisted tools when SESSION_REQUIRED=1 and no active session.
# Forces agents to formally activate a session via skill invocation before doing any work.
#
# This hook MUST be FIRST in the PreToolUse hook array (before overflow and heartbeat hooks).
#
# Gate logic:
#   1. If SESSION_REQUIRED != 1 → allow (gate disabled)
#   2. If tool is whitelisted → allow
#   3. If session.sh find succeeds AND lifecycle is active/dehydrating → allow
#   4. Otherwise → deny with session selection instructions
#
# Whitelist (allowed without active session):
#   - Bash: session.sh, log.sh, tag.sh commands
#   - AskUserQuestion: always (for skill/session selection dialogue)
#   - Skill: always (skill invocation activates session)
#   - Read: paths under ~/.claude/ (standards, skills, docs, engine)
#   - Read: paths under .claude/ relative to CWD (project standards)
#   - Read: */CLAUDE.md files (project instructions)
#
# Environment:
#   SESSION_REQUIRED=1  — set by run.sh (default ON)
#
# Hook receives JSON on stdin with: tool_name, tool_input, session_id, transcript_path
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — Session lifecycle, activation gate
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_SKILL_PROTOCOL_MANDATORY — Skills require formal session activation
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet notification graceful degradation
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_REQUIRE_ACTIVE_SESSION — This hook enforces it

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Gate check: if SESSION_REQUIRED is not set or not "1", allow everything
if [ "${SESSION_REQUIRED:-}" != "1" ]; then
  hook_allow
fi

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# --- Whitelist checks (no session required) ---

# AskUserQuestion: always allowed (for session/skill selection)
if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  hook_allow
fi

# Skill: always allowed (skill invocation triggers session activation)
if [ "$TOOL_NAME" = "Skill" ]; then
  hook_allow
fi

# Bash: whitelist session.sh, log.sh, tag.sh, glob.sh
if [ "$TOOL_NAME" = "Bash" ]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [[ "$BASH_CMD" == *"/.claude/scripts/session.sh"* ]] || \
     [[ "$BASH_CMD" == *"/.claude/scripts/log.sh"* ]] || \
     [[ "$BASH_CMD" == *"/.claude/scripts/tag.sh"* ]] || \
     [[ "$BASH_CMD" == *"/.claude/scripts/glob.sh"* ]]; then
    hook_allow
  fi
fi

# Read: whitelist ~/.claude/* paths (standards, skills, docs, engine)
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
  # Allow reads under ~/.claude/ (home directory engine files)
  if [[ "$FILE_PATH" == "$HOME/.claude/"* ]]; then
    hook_allow
  fi
  # Allow reads under .claude/ relative to CWD (project standards)
  if [[ "$FILE_PATH" == *"/.claude/"* ]]; then
    hook_allow
  fi
  # Allow CLAUDE.md files (project instructions)
  if [[ "$FILE_PATH" == *"/CLAUDE.md" ]]; then
    hook_allow
  fi
  # Allow MEMORY.md (auto memory)
  if [[ "$FILE_PATH" == *"/memory/"* ]] || [[ "$FILE_PATH" == *"/MEMORY.md" ]]; then
    hook_allow
  fi
  # Allow session artifacts (.md files under CWD/sessions/)
  # Needed for reading DEHYDRATED_CONTEXT.md before session activation
  if [[ "$FILE_PATH" == "$PWD/sessions/"*".md" ]]; then
    hook_allow
  fi
fi

# --- Session check ---

# Try to find an active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")

if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  LIFECYCLE=$(jq -r '.lifecycle // "active"' "$SESSION_DIR/.state.json" 2>/dev/null || echo "active")

  # Active or dehydrating sessions allow all tools
  if [ "$LIFECYCLE" = "active" ] || [ "$LIFECYCLE" = "dehydrating" ]; then
    hook_allow
  fi

  # Completed session — gate re-engages
  # Fall through to deny
fi

# --- DENY: No active session ---

# Build context message for the agent
DENY_REASON="§CMD_REQUIRE_ACTIVE_SESSION: No active session. Tool use blocked."
DENY_GUIDANCE=""

if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  LIFECYCLE=$(jq -r '.lifecycle // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  SKILL=$(jq -r '.skill // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  SESSION_NAME=$(basename "$SESSION_DIR")
  if [ "$LIFECYCLE" = "completed" ]; then
    DENY_REASON="§CMD_REQUIRE_ACTIVE_SESSION: Previous session '$SESSION_NAME' (skill: $SKILL) is completed. Tool use blocked."
    DENY_GUIDANCE="Use AskUserQuestion to ask the user: 'Your previous session ($SESSION_NAME / $SKILL) is complete. Would you like to continue it, or start a new session with a different skill?'"
  fi
else
  DENY_GUIDANCE="Use AskUserQuestion to ask the user which skill they want to use and in which session."
fi

DENY_GUIDANCE="${DENY_GUIDANCE}\n\nWhitelisted tools (available now): Read(~/.claude/*), Bash(session.sh/log.sh/tag.sh), AskUserQuestion, Skill."

hook_deny "$DENY_REASON" "$DENY_GUIDANCE" ""
