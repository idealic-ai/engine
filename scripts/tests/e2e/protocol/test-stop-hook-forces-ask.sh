#!/bin/bash
# test-stop-hook-forces-ask.sh — E2E behavioral test for Stop hook gate
#
# Verifies that when the Stop hook returns decision:"block", Claude is forced
# to invoke the AskUserQuestion tool instead of silently stopping.
#
# Design:
#   1. Set up a sandbox with a Stop hook that always blocks (returns decision:"block")
#   2. Give Claude a trivial task with --max-turns 3
#   3. Claude completes the task, tries to stop → hook blocks → Claude must use AskUserQuestion
#   4. Verify the output contains evidence of AskUserQuestion invocation
#
# The Stop hook script is a simple shell script that outputs JSON with
# decision:"block" and a reason instructing Claude to use AskUserQuestion.
# It respects stop_hook_active to prevent infinite loops.
#
# Requirements:
#   - Claude CLI installed and authenticated
#   - Each invocation uses haiku (cheapest model) with $0.15 budget cap
#
# Origin session: sessions/2026_02_25_STOP_HOOK_IMPL (implement → test)
#
# Run: bash ~/.claude/engine/scripts/tests/e2e/protocol/test-stop-hook-forces-ask.sh

set -uo pipefail
source "$(dirname "$0")/../../test-helpers.sh"

# Capture real paths BEFORE any HOME switch
REAL_HOME="$HOME"
REAL_ENGINE_DIR="$HOME/.claude/engine"
REAL_HOOKS_DIR="$HOME/.claude/hooks"
REAL_SCRIPTS_DIR="$HOME/.claude/scripts"
REAL_DIRECTIVES_DIR="$HOME/.claude/.directives"

if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found in PATH"
  exit 0
fi

# ============================================================
# Sandbox Setup
# ============================================================

setup_stop_hook_env() {
  TMP_DIR=$(mktemp -d)
  PROJECT_DIR="$TMP_DIR/project"
  mkdir -p "$PROJECT_DIR"
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux

  # Copy auth credentials
  if [ -f "$REAL_HOME/.claude.json" ]; then
    cp "$REAL_HOME/.claude.json" "$FAKE_HOME/.claude.json"
  fi
  unset CLAUDECODE 2>/dev/null || true

  # ---- Scripts ----
  cp "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
  chmod +x "$FAKE_HOME/.claude/scripts/session.sh"
  ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  # ---- Engine config ----
  mkdir -p "$FAKE_HOME/.claude/engine"
  ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh"

  # ---- Create the Stop hook script ----
  # This script reads stdin JSON, checks stop_hook_active, and returns
  # decision:"block" if the agent should not stop.
  mkdir -p "$FAKE_HOME/.claude/hooks"
  cat > "$FAKE_HOME/.claude/hooks/stop-gate.sh" <<'HOOK_EOF'
#!/bin/bash
# Stop hook gate — blocks stop unless stop_hook_active is true
INPUT=$(cat)

# Extract stop_hook_active from input JSON
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)

if [ "$STOP_ACTIVE" = "true" ]; then
  # Allow stop — prevent infinite loop
  exit 0
fi

# Block stop — force Claude to ask the user
cat <<JSON
{"decision": "block", "reason": "Do not stop. Use the AskUserQuestion tool to ask the user what they want to do next."}
JSON
HOOK_EOF
  chmod +x "$FAKE_HOME/.claude/hooks/stop-gate.sh"

  # ---- Minimal settings.json with Stop hook ----
  SETTINGS_FILE="$FAKE_HOME/.claude/settings.json"
  cat > "$SETTINGS_FILE" <<SETTINGS_EOF
{
  "permissions": {
    "allow": [
      "AskUserQuestion"
    ]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${FAKE_HOME}/.claude/hooks/stop-gate.sh",
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
  local max_turns="${2:-3}"
  local extra_flags="${3:-}"

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

  if [ -n "$extra_flags" ]; then
    # shellcheck disable=SC2206
    args+=($extra_flags)
  fi

  (cd "$PROJECT_DIR" && HOME="$REAL_HOME" claude "${args[@]}" 2>/dev/null) || true
}

cleanup() {
  teardown_fake_home
  rm -rf "${TMP_DIR:-}"
}
trap cleanup EXIT

echo "======================================"
echo "Stop Hook Forces AskUserQuestion — E2E"
echo "======================================"
echo ""

# ============================================================
# Setup
# ============================================================

setup_stop_hook_env

# ============================================================
# Test: Stop hook blocks → Claude invokes AskUserQuestion
# ============================================================

echo "--- Test: Stop hook blocks, Claude uses AskUserQuestion ---"
echo ""

# Give Claude a trivial task that it will complete quickly.
# After completing, it tries to stop → hook blocks → must use AskUserQuestion.
PROMPT='Answer this question: What is 2+2? After answering, you MUST stop. Do not use any tools.'

RESULT=$(invoke_claude "$PROMPT" "3" "--disable-slash-commands" 2>&1) || true

# Save transcript for inspection
echo "$RESULT" > "$PROJECT_DIR/stop-hook-transcript.json"

RESULT_TEXT=$(echo "$RESULT" | jq -r '.result // ""' 2>/dev/null)
NUM_TURNS=$(echo "$RESULT" | jq -r '.num_turns // 0' 2>/dev/null)
COST=$(echo "$RESULT" | jq -r '.cost_usd // "unknown"' 2>/dev/null)

echo "  Turns used: $NUM_TURNS"
echo "  Cost: \$$COST"

# ---- Assertion 1: Claude produced output ----
if [ -z "$RESULT_TEXT" ] || [ "$RESULT_TEXT" = "null" ]; then
  fail "Claude returned no text output"
  echo "  Raw (first 500 chars): $(echo "$RESULT" | head -c 500)"
else
  pass "Claude returned text output (${#RESULT_TEXT} chars)"
fi

# ---- Assertion 2: More than 1 turn used (hook forced continuation) ----
if [ "$NUM_TURNS" -gt 1 ]; then
  pass "Used $NUM_TURNS turns (hook forced continuation beyond initial response)"
else
  fail "Expected more than 1 turn — hook should force continuation" ">1" "$NUM_TURNS"
fi

# ---- Assertion 3: Output contains AskUserQuestion evidence ----
# When Claude invokes AskUserQuestion, the tool name appears in the JSON output.
# Check both the result text and the raw JSON for evidence.
ASK_IN_TEXT=false
ASK_IN_JSON=false

if echo "$RESULT_TEXT" | grep -qi "AskUserQuestion\|what.*do.*next\|what.*want.*do\|how.*proceed\|what.*like.*do" 2>/dev/null; then
  ASK_IN_TEXT=true
fi

if echo "$RESULT" | jq -r '.messages[]? | select(.role == "assistant") | .content[]? | select(.type == "tool_use") | .name' 2>/dev/null | grep -q "AskUserQuestion"; then
  ASK_IN_JSON=true
fi

if [ "$ASK_IN_JSON" = "true" ]; then
  pass "AskUserQuestion tool call found in message history"
elif [ "$ASK_IN_TEXT" = "true" ]; then
  pass "AskUserQuestion evidence found in text output"
else
  fail "No AskUserQuestion evidence found"
  echo "  Expected: AskUserQuestion tool invocation or reference in output"
  echo "  Result text (first 500 chars): $(echo "$RESULT_TEXT" | head -c 500)"
  echo ""
  echo "  Tool calls found:"
  echo "$RESULT" | jq -r '.messages[]? | select(.role == "assistant") | .content[]? | select(.type == "tool_use") | .name' 2>/dev/null | head -5
fi

# ---- Assertion 4: The hook reason propagated ----
# Check if Claude's response references the hook's instruction
if echo "$RESULT_TEXT" | grep -qi "what.*next\|what.*want\|how.*proceed\|what.*do\|anything.*else" 2>/dev/null; then
  pass "Claude asked the user a question (hook reason propagated)"
else
  # Not a hard failure — Claude may phrase it differently
  echo -e "${YELLOW}INFO${RESET}: Claude's text doesn't contain obvious user-directed question"
  echo "  Text (first 300 chars): $(echo "$RESULT_TEXT" | head -c 300)"
fi

echo ""
echo "  Full result text:"
echo "  $(echo "$RESULT_TEXT" | head -c 800)"
echo ""

exit_with_results
