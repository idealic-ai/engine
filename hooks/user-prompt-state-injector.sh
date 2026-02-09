#!/bin/bash
# UserPromptSubmit hook: Dynamic state injection
# Injects current time, active session path, skill, phase, and heartbeat counter
# into every user prompt. Keeps Claude aware of runtime context across compaction.
#
# Only injects when a session IS active (complements session-gate which handles no-session).
# Injection is < 100 tokens per INV_AUGMENTER_MINIMAL.
#
# Hook receives JSON on stdin with: session_id, transcript_path
# Output: JSON with hookSpecificOutput.message to inject system message, or empty for pass-through

set -euo pipefail

source "$HOME/.claude/scripts/lib.sh"

# Gate check: if SESSION_REQUIRED is not set or not "1", pass through
if [ "${SESSION_REQUIRED:-}" != "1" ]; then
  exit 0
fi

# Try to find an active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")

# No active session → exit silently (let session-gate handle it)
if [ -z "$SESSION_DIR" ] || [ ! -f "$SESSION_DIR/.state.json" ]; then
  exit 0
fi

STATE_FILE="$SESSION_DIR/.state.json"

# Check lifecycle — only inject for active sessions
LIFECYCLE=$(state_read "$STATE_FILE" "lifecycle" "active")
if [ "$LIFECYCLE" != "active" ]; then
  exit 0
fi

# Read state fields with defaults
SKILL=$(state_read "$STATE_FILE" "skill" "")
CURRENT_PHASE=$(state_read "$STATE_FILE" "currentPhase" "")
HEARTBEAT_COUNT=$(state_read "$STATE_FILE" "toolCallsSinceLastLog" "0")
HEARTBEAT_MAX=$(state_read "$STATE_FILE" "toolUseWithoutLogsBlockAfter" "10")

# Get current time and session name
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_NAME=$(basename "$SESSION_DIR")

# Build compact single-line message
MESSAGE="[Session Context] Time: ${CURRENT_TIME} | Session: ${SESSION_NAME}"

if [ -n "$SKILL" ]; then
  MESSAGE="${MESSAGE} | Skill: ${SKILL}"
fi

if [ -n "$CURRENT_PHASE" ]; then
  MESSAGE="${MESSAGE} | Phase: ${CURRENT_PHASE}"
fi

MESSAGE="${MESSAGE} | Heartbeat: ${HEARTBEAT_COUNT}/${HEARTBEAT_MAX}"

# Output JSON with proper escaping
jq -n --arg msg "$MESSAGE" '{"hookSpecificOutput":{"message":$msg}}'
