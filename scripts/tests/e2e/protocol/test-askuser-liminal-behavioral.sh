#!/bin/bash
# test-behavioral-askuser-liminal.sh — Behavioral test for F4+F6
#
# Tests that Claude uses AskUserQuestion (not plain text) when presenting
# routing options in liminal spaces (between sessions, before activation).
#
# Finding: ¶INV_QUESTION_GATE_OVER_TEXT_GATE scope was broadened from
# "in skill protocols" to "in ALL agent interactions".
#
# Run: bash sessions/2026_02_14_TESTABILITY_AND_QUESTION_TOOL/test-behavioral-askuser-liminal.sh

set -uo pipefail
source ~/.claude/engine/scripts/tests/test-helpers.sh

# ============================================================
# E2E Infrastructure (inlined from test-e2e-claude-hooks.sh)
# Cannot source that file directly — it runs inline tests.
# ============================================================

REAL_HOME="$HOME"
REAL_ENGINE_DIR="$HOME/.claude/engine"
REAL_HOOKS_DIR="$HOME/.claude/hooks"
REAL_SCRIPTS_DIR="$HOME/.claude/scripts"
REAL_DIRECTIVES_DIR="$HOME/.claude/.directives"

if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found in PATH"
  exit 0
fi

setup_claude_e2e_env() {
  local session_name="${1:-test_e2e}"

  TMP_DIR=$(mktemp -d)
  PROJECT_DIR="$TMP_DIR/project"
  mkdir -p "$PROJECT_DIR"

  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux

  if [ -f "$REAL_HOME/.claude.json" ]; then
    cp "$REAL_HOME/.claude.json" "$FAKE_HOME/.claude.json"
  fi
  unset CLAUDECODE 2>/dev/null || true

  # Scripts
  cp "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
  chmod +x "$FAKE_HOME/.claude/scripts/session.sh"
  ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  # Engine config
  mkdir -p "$FAKE_HOME/.claude/engine"
  ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh"
  ln -sf "$REAL_ENGINE_DIR/guards.json" "$FAKE_HOME/.claude/engine/guards.json"

  # Hooks
  mkdir -p "$FAKE_HOME/.claude/hooks"
  for hook in "$REAL_HOOKS_DIR"/*.sh; do
    [ -f "$hook" ] || continue
    local hook_name real_hook
    hook_name=$(basename "$hook")
    real_hook=$(readlink -f "$hook" 2>/dev/null || echo "$hook")
    ln -sf "$real_hook" "$FAKE_HOME/.claude/hooks/$hook_name"
  done
  mkdir -p "$FAKE_HOME/.claude/engine/hooks"
  for hook in "$REAL_ENGINE_DIR/hooks"/*.sh; do
    [ -f "$hook" ] || continue
    ln -sf "$hook" "$FAKE_HOME/.claude/engine/hooks/$(basename "$hook")"
  done

  # Directives
  mkdir -p "$FAKE_HOME/.claude/.directives/commands"
  for f in "$REAL_DIRECTIVES_DIR"/*.md; do
    [ -f "$f" ] || continue
    ln -sf "$f" "$FAKE_HOME/.claude/.directives/$(basename "$f")"
  done
  for f in "$REAL_DIRECTIVES_DIR/commands"/*.md; do
    [ -f "$f" ] || continue
    ln -sf "$f" "$FAKE_HOME/.claude/.directives/commands/$(basename "$f")"
  done

  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"

  TEST_SESSION="$PROJECT_DIR/sessions/$session_name"
  mkdir -p "$TEST_SESSION"

  SETTINGS_FILE="$FAKE_HOME/.claude/settings.json"
  cat > "$SETTINGS_FILE" <<SETTINGS_EOF
{
  "permissions": {
    "allow": [
      "Bash(engine *)",
      "Bash(${FAKE_HOME}/.claude/scripts/*)"
    ]
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${FAKE_HOME}/.claude/hooks/session-start-restore.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${FAKE_HOME}/.claude/hooks/user-prompt-state-injector.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${FAKE_HOME}/.claude/engine/hooks/post-tool-use-injections.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "env": {
    "DISABLE_AUTO_COMPACT": "1"
  }
}
SETTINGS_EOF
}

invoke_claude() {
  local prompt="$1"
  local schema="${2:-}"
  local tools="${3:-}"
  local max_turns="${4:-2}"
  local extra_flags="${5:-}"

  local args=(
    -p "$prompt"
    --model haiku
    --output-format json
    --max-turns "$max_turns"
    --max-budget-usd 0.15
    --dangerously-skip-permissions
    --no-session-persistence
    --settings "$SETTINGS_FILE"
  )

  if [ "$tools" = "none" ]; then
    args+=(--tools "")
  elif [ -n "$tools" ]; then
    args+=(--tools "$tools")
  fi

  if [ -n "$schema" ]; then
    args+=(--json-schema "$schema")
  fi

  if [ -n "$extra_flags" ]; then
    # shellcheck disable=SC2206
    args+=($extra_flags)
  fi

  (cd "$PROJECT_DIR" && HOME="$REAL_HOME" claude "${args[@]}" 2>/dev/null)
}

extract_result() {
  local json="$1"
  echo "$json" | jq '.structured_output // empty' 2>/dev/null || echo "$json"
}

cleanup() {
  teardown_fake_home 2>/dev/null || true
  rm -rf "${TMP_DIR:-}"
}
trap cleanup EXIT

# ============================================================
# Test: F4+F6 — AskUserQuestion in liminal spaces
# ============================================================

echo "======================================"
echo "Behavioral Test: AskUserQuestion in Liminal Spaces (F4+F6)"
echo "======================================"
echo ""

setup_claude_e2e_env "behavioral_askuser_liminal"

# Completed session = liminal state (between sessions)
cat > "$TEST_SESSION/.state.json" <<STATE_EOF
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "completed",
  "currentPhase": "5.4: Close",
  "contextUsage": 0.50,
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200
}
STATE_EOF

SCHEMA='{
  "type": "object",
  "properties": {
    "wouldUseAskUserQuestion": {
      "type": "boolean",
      "description": "true if the agent would use the AskUserQuestion tool to present options"
    },
    "wouldUsePlainText": {
      "type": "boolean",
      "description": "true if the agent would present options as plain text in chat"
    },
    "reasoning": {
      "type": "string",
      "description": "Brief explanation of why the agent chose this approach"
    }
  },
  "required": ["wouldUseAskUserQuestion", "wouldUsePlainText", "reasoning"],
  "additionalProperties": false
}'

PROMPT='You are between sessions — a previous implementation session just completed. The user says: "I want to work on something new."

You need to present the user with options: start a new /implement session, run /analyze, or do /chores.

IMPORTANT: Do NOT actually call any tools. Instead, report your INTENTION:
- Would you use the AskUserQuestion tool to present these options?
- Or would you write them as plain text in chat (e.g., "1. /implement 2. /analyze 3. /chores")?

Consider the invariant ¶INV_QUESTION_GATE_OVER_TEXT_GATE which says user-facing option menus in ALL agent interactions must use AskUserQuestion.'

echo "--- F4+F6: AskUserQuestion in liminal spaces ---"
echo "  (Running claude -p with haiku — may take 10-20s)"

RESULT=$(invoke_claude "$PROMPT" "$SCHEMA" "none" 2 "--disable-slash-commands" 2>&1) || true
PARSED=$(extract_result "$RESULT")

if [ -z "$PARSED" ] || [ "$PARSED" = "null" ]; then
  fail "F4+F6: Claude invocation returned empty result"
  echo "  Raw output: $(echo "$RESULT" | head -5)"
else
  WOULD_ASK=$(echo "$PARSED" | jq -r '.wouldUseAskUserQuestion // false')
  WOULD_TEXT=$(echo "$PARSED" | jq -r '.wouldUsePlainText // false')
  REASONING=$(echo "$PARSED" | jq -r '.reasoning // ""')

  if [ "$WOULD_ASK" = "true" ] && [ "$WOULD_TEXT" = "false" ]; then
    pass "F4+F6: Agent would use AskUserQuestion in liminal space (correct)"
  elif [ "$WOULD_ASK" = "true" ]; then
    pass "F4+F6: Agent recognizes AskUserQuestion (with mixed signal)"
  else
    fail "F4+F6: Agent would use plain text instead of AskUserQuestion" \
      "wouldUseAskUserQuestion=true" "wouldUseAskUserQuestion=$WOULD_ASK"
  fi

  echo ""
  echo "  Would use AskUserQuestion: $WOULD_ASK"
  echo "  Would use plain text: $WOULD_TEXT"
  echo "  Reasoning: $REASONING"
fi

echo ""
exit_with_results
