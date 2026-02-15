#!/bin/bash
# SubagentStart hook: Inject targeted context into sub-agents
#
# Fires when a sub-agent (Task tool) starts. Injects log template and
# discovered directives from the parent session. Does NOT inject standards
# (COMMANDS.md, INVARIANTS.md, SIGILS.md) — those are for the main agent only.
#
# Input (stdin): {"agent_id":"...","agent_type":"task","session_id":"...","transcript_path":"...","cwd":"..."}
# Output (stdout): {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}
#
# Fast exit if no active session (¶INV_HOOK_FAST_EXIT).
# Read-only — no writes to .state.json (¶INV_HOOK_IDEMPOTENT).

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Find the active session directory via session.sh find
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null) || exit 0

STATE_FILE="$SESSION_DIR/.state.json"
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Source lib.sh for state_read utility
source "$HOME/.claude/scripts/lib.sh"

# Read state fields
SKILL=$(state_read "$STATE_FILE" "skill" "")
LOG_TEMPLATE=$(state_read "$STATE_FILE" "logTemplate" "")

# Standards paths to exclude from sub-agent injection
# These are injected by SessionStart for the main agent only
STANDARDS_PATTERN="/.directives/COMMANDS.md|/.directives/INVARIANTS.md|/.directives/SIGILS.md"

# Build additionalContext
ADDITIONAL_CONTEXT=""

# 1. Log template injection
if [ -n "$LOG_TEMPLATE" ] && [ -n "$SKILL" ]; then
  TEMPLATE_PATH="$HOME/.claude/skills/$SKILL/$LOG_TEMPLATE"
  if [ -f "$TEMPLATE_PATH" ]; then
    TEMPLATE_CONTENT=$(cat "$TEMPLATE_PATH" 2>/dev/null || true)
    if [ -n "$TEMPLATE_CONTENT" ]; then
      ADDITIONAL_CONTEXT="[Preloaded: $TEMPLATE_PATH]
$TEMPLATE_CONTENT

"
    fi
  fi
fi

# 2. CMD_APPEND_LOG injection — sub-agents need to know HOW to log
CMD_APPEND_LOG_PATH="$HOME/.claude/engine/.directives/commands/CMD_APPEND_LOG.md"
if [ -f "$CMD_APPEND_LOG_PATH" ]; then
  CMD_CONTENT=$(cat "$CMD_APPEND_LOG_PATH" 2>/dev/null || true)
  if [ -n "$CMD_CONTENT" ]; then
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}[Preloaded: $CMD_APPEND_LOG_PATH]
$CMD_CONTENT

"
  fi
fi

# 3. Discovered directives injection (from preloadedFiles, excluding standards)
PRELOADED_COUNT=$(jq '.preloadedFiles // [] | length' "$STATE_FILE" 2>/dev/null || echo "0")
if [ "$PRELOADED_COUNT" -gt 0 ]; then
  while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue

    # Skip standards — sub-agents don't need protocol rules
    if echo "$filepath" | grep -qE "$STANDARDS_PATTERN"; then
      continue
    fi

    # Read and inject the file
    if [ -f "$filepath" ]; then
      FILE_CONTENT=$(cat "$filepath" 2>/dev/null || true)
      if [ -n "$FILE_CONTENT" ]; then
        ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}[Preloaded: $filepath]
$FILE_CONTENT

"
      fi
    fi
  done < <(jq -r '.preloadedFiles // [] | .[]' "$STATE_FILE" 2>/dev/null)
fi

# Output JSON if we have context to inject
if [ -n "$ADDITIONAL_CONTEXT" ]; then
  jq -n --arg ctx "$ADDITIONAL_CONTEXT" \
    '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":$ctx}}'
fi

exit 0
