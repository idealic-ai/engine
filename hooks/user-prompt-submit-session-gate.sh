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
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_SKILL_PROTOCOL_MANDATORY — Skills require formal session activation
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_REQUIRE_ACTIVE_SESSION — This hook enforces it

set -euo pipefail

# Gate check: if SESSION_REQUIRED is not set or not "1", pass through
if [ "${SESSION_REQUIRED:-}" != "1" ]; then
  exit 0
fi

# Read hook input for prompt field (needed for <command-name> detection)
INPUT=$(cat)

# Detect <command-name> in prompt and trigger skill directory discovery
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
if [ -n "$PROMPT" ]; then
  SKILL_NAME=$(echo "$PROMPT" | sed -n 's/.*<command-name>\([^<]*\)<\/command-name>.*/\1/p' 2>/dev/null || true)
  # Strip leading slash — <command-name> tags include it: <command-name>/fix</command-name>
  SKILL_NAME="${SKILL_NAME#/}"
  # Fallback: detect raw /skill-name pattern when no <command-name> tags present
  if [ -z "$SKILL_NAME" ]; then
    RAW_SKILL=$(echo "$PROMPT" | sed -n 's|^/\([a-z][a-z-]*\).*|\1|p' 2>/dev/null || true)
    if [ -n "$RAW_SKILL" ] && [ -d "$HOME/.claude/skills/$RAW_SKILL" ]; then
      SKILL_NAME="$RAW_SKILL"
    fi
  fi
  if [ -n "$SKILL_NAME" ]; then
    SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
    if [ -d "$SKILL_DIR" ]; then
      # Find active session to write pendingDirectives
      SESSION_DIR_FOR_DISCOVERY=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
      if [ -n "$SESSION_DIR_FOR_DISCOVERY" ] && [ -f "$SESSION_DIR_FOR_DISCOVERY/.state.json" ]; then
        # Run discover-directives on the skill directory, add results to pendingDirectives
        DISCOVERED=$("$HOME/.claude/scripts/discover-directives.sh" "$SKILL_DIR" --walk-up --root "$HOME/.claude/skills" 2>/dev/null || true)
        if [ -n "$DISCOVERED" ]; then
          # Parse discovered files (one per line) and add to pendingDirectives
          while IFS= read -r directive_file; do
            [ -z "$directive_file" ] && continue
            [ ! -f "$directive_file" ] && continue
            CURRENT=$(jq -r '.pendingDirectives // []' "$SESSION_DIR_FOR_DISCOVERY/.state.json" 2>/dev/null)
            # Check if already in pendingDirectives
            ALREADY=$(echo "$CURRENT" | jq --arg f "$directive_file" '[.[] | select(. == $f)] | length' 2>/dev/null || echo "0")
            if [ "$ALREADY" = "0" ]; then
              jq --arg f "$directive_file" '.pendingDirectives = ((.pendingDirectives // []) + [$f])' \
                "$SESSION_DIR_FOR_DISCOVERY/.state.json" > "$SESSION_DIR_FOR_DISCOVERY/.state.json.tmp" \
                && mv "$SESSION_DIR_FOR_DISCOVERY/.state.json.tmp" "$SESSION_DIR_FOR_DISCOVERY/.state.json"
            fi
          done <<< "$DISCOVERED"
        fi
      fi

      # --- Phase 0 CMD file extraction (same logic as post-tool-use-templates.sh) ---
      SKILL_FILE="$SKILL_DIR/SKILL.md"
      if [ -f "$SKILL_FILE" ]; then
        PARAMS_JSON=$(sed -n '/^```json$/,/^```$/p' "$SKILL_FILE" | sed '1d;$d' 2>/dev/null || echo "")
        if [ -n "$PARAMS_JSON" ]; then
          PHASE0_CMDS=$(echo "$PARAMS_JSON" | jq -r '
            (.phases // [])[0] |
            ((.steps // []) + (.commands // [])) |
            .[] | select(startswith("§CMD_"))
          ' 2>/dev/null || echo "")
          if [ -n "$PHASE0_CMDS" ]; then
            CMD_DIR="$HOME/.claude/engine/.directives/commands"
            SEEN_CMDS=""
            while IFS= read -r field; do
              [ -n "$field" ] || continue
              name="${field#§CMD_}"
              name=$(echo "$name" | sed -E 's/_[a-z][a-z_]*$//')
              case "$SEEN_CMDS" in *"|${name}|"*) continue ;; esac
              SEEN_CMDS="${SEEN_CMDS}|${name}|"
              cmd_file="$CMD_DIR/CMD_${name}.md"
              [ -f "$cmd_file" ] || continue
              content=$(cat "$cmd_file")
              SKILL_CMD_CONTEXT="${SKILL_CMD_CONTEXT:-}${SKILL_CMD_CONTEXT:+\n\n}[Preloaded: $cmd_file]\n$content"
            done <<< "$PHASE0_CMDS"
          fi
        fi
      fi
    fi
  fi
fi

# Try to find an active session
SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")

if [ -n "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.state.json" ]; then
  LIFECYCLE=$(jq -r '.lifecycle // "active"' "$SESSION_DIR/.state.json" 2>/dev/null || echo "active")

  # Active, dehydrating, or resuming sessions — no gate injection needed
  # But still deliver CMD files if we extracted any
  if [ "$LIFECYCLE" = "active" ] || [ "$LIFECYCLE" = "dehydrating" ] || [ "$LIFECYCLE" = "resuming" ]; then
    if [ -n "${SKILL_CMD_CONTEXT:-}" ]; then
      printf '%s' "$SKILL_CMD_CONTEXT" | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'
    fi
    exit 0
  fi

  # Completed session — inject continuation prompt
  SKILL=$(jq -r '.skill // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  SESSION_NAME=$(basename "$SESSION_DIR")

  MESSAGE="§CMD_REQUIRE_ACTIVE_SESSION: Previous session '$SESSION_NAME' (skill: $SKILL) is completed.\nUse AskUserQuestion to ask: 'Your previous session ($SESSION_NAME / $SKILL) is complete. Continue it, start a new session (/do for quick tasks, or /implement, /analyze, etc.), or describe new work?'"

  MESSAGE=$(printf '%b' "$MESSAGE")
  # Append CMD context if we extracted any
  if [ -n "${SKILL_CMD_CONTEXT:-}" ]; then
    CMD_TEXT=$(printf '%b' "$SKILL_CMD_CONTEXT")
    MESSAGE="${MESSAGE}

${CMD_TEXT}"
  fi
  jq -n --arg msg "$MESSAGE" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
  exit 0
fi

# No session at all — inject skill selection instruction
MESSAGE="§CMD_REQUIRE_ACTIVE_SESSION: No active session.\nUse AskUserQuestion to ask: 'No active session. Use /do for quick tasks, or pick a skill (/implement, /analyze, /fix, /test), or describe new work.'"

MESSAGE=$(printf '%b' "$MESSAGE")
# Append CMD context if we extracted any
if [ -n "${SKILL_CMD_CONTEXT:-}" ]; then
  CMD_TEXT=$(printf '%b' "$SKILL_CMD_CONTEXT")
  MESSAGE="${MESSAGE}

${CMD_TEXT}"
fi
jq -n --arg msg "$MESSAGE" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
exit 0
