#!/bin/bash
# ~/.claude/engine/hooks/pre-compact-kill.sh — PreCompact hook
#
# Intercepts auto-compaction to prevent lossy context compression.
# Flow:
#   1. Find active session via session.sh find
#   2. Check for dehydratedContext in .state.json — generate mini-dehydration if missing
#   3. Delegate to session.sh restart (marks state, signals watchdog)
#
# This hook cannot BLOCK compaction (PreCompact doesn't support blocking).
# Instead, it races against the compaction by marking state and triggering
# a kill+restart. The watchdog (if running) handles the actual SIGKILL.
# Without a watchdog, the restart prompt is written for manual recovery.
#
# Matcher: "auto" only (manual /compact is intentional — don't interfere)
# TEST_MODE=1 for dry-run (prints actions, no kill)
#
# Related:
#   session.sh restart — marks killRequested, writes restartPrompt, signals watchdog
#   overflow-v2.sh — dehydrates at 76% (belt), this is the suspenders at ~95%
#   ¶INV_TMUX_AND_FLEET_OPTIONAL — works without tmux

set -euo pipefail

source "$HOME/.claude/scripts/lib.sh"

# Read hook input
INPUT=$(cat)
MATCHER=$(echo "$INPUT" | jq -r '.event // ""' 2>/dev/null || echo "")

# Only intercept auto-compaction, not manual /compact
if [ "$MATCHER" = "manual" ]; then
  exit 0
fi

# --- Step 1: Find active session ---
SESSION_DIR=""
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null) || true

if [ -z "$SESSION_DIR" ] || [ ! -f "$SESSION_DIR/.state.json" ]; then
  # No session = nothing to preserve
  if [ "${TEST_MODE:-}" = "1" ]; then
    echo "TEST: No active session found. Exiting."
  fi
  exit 0
fi

STATE_FILE="$SESSION_DIR/.state.json"

# --- Step 2: Check for dehydratedContext in .state.json ---
HAS_DEHYDRATED=$(jq -r '.dehydratedContext // null | type' "$STATE_FILE" 2>/dev/null)

if [ "$HAS_DEHYDRATED" != "object" ]; then
  # Generate mini-dehydration directly into .state.json
  TASK_SUMMARY=$(jq -r '.taskSummary // "Unknown task"' "$STATE_FILE")
  CURRENT_PHASE=$(jq -r '.currentPhase // "Unknown"' "$STATE_FILE")

  # Collect session artifact paths as requiredFiles
  REQUIRED_FILES="[]"
  for f in "$SESSION_DIR"/*.md; do
    [ -f "$f" ] || continue
    local_name=$(basename "$f")
    # Use sessions-relative path
    session_name=$(basename "$SESSION_DIR")
    REQUIRED_FILES=$(echo "$REQUIRED_FILES" | jq --arg p "sessions/$session_name/$local_name" '. + [$p]')
  done

  # Cap at 8
  REQUIRED_FILES=$(echo "$REQUIRED_FILES" | jq '.[:8]')

  if [ "${TEST_MODE:-}" = "1" ]; then
    echo "TEST: Generating mini-dehydration in .state.json"
  fi

  MINI_JSON=$(jq -n \
    --arg summary "$TASK_SUMMARY" \
    --arg phase "$CURRENT_PHASE" \
    --argjson files "$REQUIRED_FILES" \
    '{
      summary: $summary,
      lastAction: "PreCompact hook triggered — auto-compaction intercepted. Session killed to prevent lossy compression.",
      nextSteps: ["Check session artifacts for detailed state", ("Resume at " + $phase)],
      handoverInstructions: "This is an emergency mini-dehydration. Check session logs and plan for full context.",
      requiredFiles: $files
    }')

  jq --argjson ctx "$MINI_JSON" '.dehydratedContext = $ctx' "$STATE_FILE" | safe_json_write "$STATE_FILE"
fi

# --- Step 3: Delegate to session.sh restart ---
# session.sh restart handles: mark killRequested, write restartPrompt, signal watchdog
if [ "${TEST_MODE:-}" = "1" ]; then
  echo "TEST: Would call session.sh restart $SESSION_DIR"
  echo "TEST: Session dir: $SESSION_DIR"
  echo "TEST: Dehydrated context in .state.json: $([ "$HAS_DEHYDRATED" = "object" ] && echo "exists" || echo "generated")"
  exit 0
fi

"$HOME/.claude/scripts/session.sh" restart "$SESSION_DIR" 2>/dev/null || true

exit 0
