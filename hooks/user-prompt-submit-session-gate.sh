#!/bin/bash
# ~/.claude/engine/hooks/user-prompt-submit-session-gate.sh — UserPromptSubmit hook
#
# Two responsibilities:
#   1. Skill preloading: On skill detection (/skill-name in prompt), extracts Phase 0 CMD
#      files + templates via extract_skill_preloads() and delivers directly via additionalContext.
#      If a session exists, also queues to pendingPreloads for dedup tracking.
#   2. Session gate: Injects boot instructions when no active session exists.
#
# Directive discovery is NOT done here — directives are discovered organically by
# _run_discovery() in pre-tool-use-overflow-v2.sh when the agent reads skill files.
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

# Find session once (used by both skill preloading and gate check)
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")

# --- Preload gate: skip skill preloading when context is near overflow ---
# At 90%+ context, injecting SKILL.md content pushes past overflow threshold.
# Instead, inject a short warning so the agent knows to dehydrate first.
CONTEXT_HIGH=false
if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  CTX_USAGE=$(jq -r '.contextUsage // 0' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")
  if [ "$(echo "$CTX_USAGE >= 0.90" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
    CONTEXT_HIGH=true
  fi
fi

# --- Skill preloading: detect /skill-name and deliver SKILL.md + suggestions ---
# Strategy: SKILL.md is priority. If it fits in the 10K budget, deliver it and list
# Phase 0 CMDs + templates as suggestions. If SKILL.md is too large, deliver CMDs/templates
# up to budget and suggest SKILL.md. Suggestions are path-only (agent reads them later).
SKILL_ADDITIONAL_CONTEXT=""
if [ -n "$PROMPT" ]; then
  # Detect raw /skill-name pattern (only mechanism — <command-name> tags don't appear in hook prompt)
  SKILL_NAME=$(echo "$PROMPT" | sed -n 's|^/\([a-z][a-z-]*\).*|\1|p' 2>/dev/null || true)
  if [ -n "$SKILL_NAME" ] && [ -d "$HOME/.claude/skills/$SKILL_NAME" ]; then
    # Preload gate: at 90%+ context, skip file delivery to prevent overflow
    if [ "$CONTEXT_HIGH" = "true" ]; then
      SKILL_ADDITIONAL_CONTEXT="[block: preload-gate] Context at 90%+. Skill /$SKILL_NAME detected but preloading skipped to prevent overflow. Execute §CMD_DEHYDRATE before starting new skill."
    else
    SKILL_FILE="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"
    BUDGET=9000  # Safety margin under 10K truncation limit (pitfall #11)
    PRELOADED_JSON="[]"
    SUGGESTIONS=""

    if [ -f "$SKILL_FILE" ]; then
      SKILL_CONTENT=$(cat "$SKILL_FILE" 2>/dev/null || true)
      SKILL_SIZE=${#SKILL_CONTENT}
      NORM_SKILL_PATH=$(normalize_preload_path "$SKILL_FILE")

      # Get Phase 0 CMDs + templates
      PRELOAD_PATHS=$(extract_skill_preloads "$SKILL_NAME")

      if [ "$SKILL_SIZE" -lt "$BUDGET" ]; then
        # SKILL.md fits — deliver it, suggest Phase 0 CMDs + templates
        SKILL_ADDITIONAL_CONTEXT="[Preloaded: $NORM_SKILL_PATH]\n$SKILL_CONTENT"
        PRELOADED_JSON=$(echo "$PRELOADED_JSON" | jq --arg f "$NORM_SKILL_PATH" '. + [$f]')

        if [ -n "$PRELOAD_PATHS" ]; then
          while IFS= read -r p; do
            [ -n "$p" ] || continue
            SUGGESTIONS="${SUGGESTIONS}\n- $p"
          done <<< "$PRELOAD_PATHS"
        fi
      else
        # SKILL.md too large — suggest it, deliver Phase 0 CMDs + templates up to budget
        SUGGESTIONS="\n- $NORM_SKILL_PATH"
        USED=0

        if [ -n "$PRELOAD_PATHS" ]; then
          while IFS= read -r norm_path; do
            [ -n "$norm_path" ] || continue
            abs_path="${norm_path/#\~/$HOME}"
            [ -f "$abs_path" ] || continue
            content=$(cat "$abs_path" 2>/dev/null || true)
            [ -n "$content" ] || continue
            content_size=${#content}
            overhead=$((${#norm_path} + 20))
            NEW_USED=$((USED + content_size + overhead))
            if [ "$NEW_USED" -lt "$BUDGET" ]; then
              SKILL_ADDITIONAL_CONTEXT="${SKILL_ADDITIONAL_CONTEXT}${SKILL_ADDITIONAL_CONTEXT:+\n\n}[Preloaded: $norm_path]\n$content"
              PRELOADED_JSON=$(echo "$PRELOADED_JSON" | jq --arg f "$norm_path" '. + [$f]')
              USED=$NEW_USED
            else
              SUGGESTIONS="${SUGGESTIONS}\n- $norm_path"
            fi
          done <<< "$PRELOAD_PATHS"
        fi
      fi
    fi

    # Append suggestions list (path-only — agent reads them, not counted as preloaded)
    if [ -n "$SUGGESTIONS" ]; then
      SKILL_ADDITIONAL_CONTEXT="${SKILL_ADDITIONAL_CONTEXT}${SKILL_ADDITIONAL_CONTEXT:+\n\n}[Suggested — read these files for full context]:${SUGGESTIONS}"
    fi

    # Track preloaded files in .state.json (suggestions are NOT tracked)
    PRELOADED_COUNT=$(echo "$PRELOADED_JSON" | jq 'length')
    if [ "$PRELOADED_COUNT" -gt 0 ] && [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ] && jq empty "$SESSION_DIR/.state.json" 2>/dev/null; then
      jq --argjson paths "$PRELOADED_JSON" '
        (.preloadedFiles // []) as $already |
        ($paths | map(select(. as $f | $already | any(. == $f) | not))) as $new |
        .preloadedFiles = ($already + $new) |
        if ($new | length) > 0 then .pendingPreloads = ((.pendingPreloads // []) + $new | unique) else . end
      ' "$SESSION_DIR/.state.json" | safe_json_write "$SESSION_DIR/.state.json"
    fi
    fi  # end CONTEXT_HIGH else branch
  fi
fi

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

# --- Output: combine skill preloads + gate message ---
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
