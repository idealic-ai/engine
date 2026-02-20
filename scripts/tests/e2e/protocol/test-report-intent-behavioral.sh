#!/bin/bash
# test-report-intent-behavioral.sh — Two-pass behavioral test for §CMD_REPORT_INTENT
#
# Verifies that Claude, given a skill protocol context with §CMD_REPORT_INTENT,
# ACTUALLY produces a blockquote intent report (not just self-reports that it would).
#
# Two-pass design:
#   Pass A: No --json-schema — captures real text output. Greps for blockquote, phase, steps.
#           This proves Claude actually produces the intent report in its output.
#   Pass B: With --json-schema — captures self-reflective diagnostic (directive found, quote, reasoning).
#           This explains how Claude found and interpreted the directive.
#
# Requirements:
#   - Claude CLI installed and authenticated
#   - Each pass invokes haiku (cheapest model) with $0.15 budget cap
#
# Origin session: sessions/2026_02_14_IMPROVE_PROTOCOL_TEST (improve-protocol)
# Related: §CMD_REPORT_INTENT definition in COMMANDS.md
#
# Run: bash ~/.claude/engine/scripts/tests/protocol/test-report-intent-behavioral.sh

set -uo pipefail
source "$(dirname "$0")/../test-helpers.sh"

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
# Sandbox Setup (mirrors test-e2e-claude-hooks.sh infrastructure)
# ============================================================

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

  cp "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
  chmod +x "$FAKE_HOME/.claude/scripts/session.sh"
  ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  mkdir -p "$FAKE_HOME/.claude/engine"
  ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh"

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

  (cd "$PROJECT_DIR" && HOME="$REAL_HOME" claude "${args[@]}" 2>/dev/null) || true
}

extract_result() {
  local json="$1"
  echo "$json" | jq '.structured_output // empty' 2>/dev/null || echo "$json"
}

cleanup() {
  teardown_fake_home
  rm -rf "${TMP_DIR:-}"
}
trap cleanup EXIT

echo "======================================"
echo "§CMD_REPORT_INTENT Behavioral Test"
echo "======================================"
echo ""

# ============================================================
# Setup
# ============================================================

setup_claude_e2e_env "e2e_report_intent"

cat > "$TEST_SESSION/.state.json" <<STATE_EOF
{
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "3: Planning",
  "contextUsage": 0.10,
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200
}
STATE_EOF

# ============================================================
# Pass A: Real text output (no --json-schema)
# Proves Claude ACTUALLY produces the intent report
# ============================================================

echo "--- Pass A: Real text output (no --json-schema) ---"

PROMPT_A='You are an agent following the workflow engine protocol. You are in Phase 3: Planning of an /implement session. The task is to add a logout button to the header component.

Your system context contains COMMANDS.md which defines §CMD_REPORT_INTENT. Execute it now. Produce ONLY the intent report — nothing else.'

RESULT_A=$(invoke_claude "$PROMPT_A" "" "none" "2" "--disable-slash-commands" 2>&1) || true
RESULT_TEXT=$(echo "$RESULT_A" | jq -r '.result // ""' 2>/dev/null)

# Save transcript for inspection
echo "$RESULT_A" > "$PROJECT_DIR/pass-a-transcript.json"

if [ -z "$RESULT_TEXT" ] || [ "$RESULT_TEXT" = "null" ]; then
  fail "Pass A: Claude returned no text output"
  echo "  Raw (first 300 chars): $(echo "$RESULT_A" | head -c 300)"
else
  # Blockquote lines in ACTUAL text output
  BQ_COUNT=$(echo "$RESULT_TEXT" | grep -c '^>' 2>/dev/null || true)
  if [ "$BQ_COUNT" -gt 0 ]; then
    pass "Pass A: Real output contains blockquote lines ($BQ_COUNT lines)"
  else
    fail "Pass A: Real output contains blockquote lines"
    echo "  Expected: lines starting with '>' in text output"
    echo "  Got (first 400 chars): $(echo "$RESULT_TEXT" | head -c 400)"
  fi

  # Phase reference in ACTUAL text output
  if echo "$RESULT_TEXT" | grep -qi "phase 3\|planning" 2>/dev/null; then
    pass "Pass A: Real output mentions Phase 3/Planning"
  else
    fail "Pass A: Real output mentions Phase 3/Planning"
    echo "  Got (first 400 chars): $(echo "$RESULT_TEXT" | head -c 400)"
  fi

  # Structured intent in ACTUAL text output (3-line blockquote: What/How/Not-what)
  INTENT_LINES=$(echo "$RESULT_TEXT" | grep -cE '^\s*>' 2>/dev/null || true)
  if [ "$INTENT_LINES" -ge 3 ]; then
    pass "Pass A: Real output has structured intent ($INTENT_LINES blockquote lines)"
  else
    fail "Pass A: Real output has structured intent"
    echo "  Expected: 3+ blockquote lines (> prefix)"
    echo "  Got (first 400 chars): $(echo "$RESULT_TEXT" | head -c 400)"
  fi

  echo ""
  echo "  Blockquote lines: $BQ_COUNT"
  echo "  Intent blockquote lines: $INTENT_LINES"
  echo "  Real text (first 500 chars):"
  echo "  $(echo "$RESULT_TEXT" | head -c 500)"
fi

# ============================================================
# Pass B: Self-reflective diagnostic (with --json-schema)
# Captures HOW Claude found and interpreted the directive
# ============================================================

echo ""
echo "--- Pass B: Diagnostic (--json-schema) ---"

SCHEMA_B='{
  "type": "object",
  "properties": {
    "directiveFound": {
      "type": "boolean",
      "description": "true if you found the §CMD_REPORT_INTENT definition in your preloaded context"
    },
    "directiveQuote": {
      "type": "string",
      "description": "Copy the first 2 sentences of the §CMD_REPORT_INTENT definition exactly as written in your context. If not found, explain what you searched for."
    },
    "reasoning": {
      "type": "string",
      "description": "Explain step-by-step: (1) How you found the directive, (2) What the directive told you to do, (3) How you decided on the format and content. If you did NOT produce an intent report, explain what prevented you."
    }
  },
  "required": ["directiveFound", "directiveQuote", "reasoning"],
  "additionalProperties": false
}'

PROMPT_B='You are an agent following the workflow engine protocol. You are in Phase 3: Planning of an /implement session. The task is to add a logout button to the header component.

Your system context contains COMMANDS.md which defines §CMD_REPORT_INTENT. Find that definition and report:

1. directiveFound: Did you find §CMD_REPORT_INTENT in your preloaded context?
2. directiveQuote: Quote the first 2 sentences of the definition exactly as they appear.
3. reasoning: Step-by-step explanation of how you found the directive, what it told you to do, and how you would decide on the format/content of the intent report.'

RESULT_B=$(invoke_claude "$PROMPT_B" "$SCHEMA_B" "none" "2" "--disable-slash-commands" 2>&1) || true
echo "$RESULT_B" > "$PROJECT_DIR/pass-b-transcript.json"

PARSED=$(extract_result "$RESULT_B")

if [ -z "$PARSED" ] || [ "$PARSED" = "null" ]; then
  fail "Pass B: Claude invocation returned empty result"
  echo "  Raw output: $(echo "$RESULT_B" | head -10)"
else
  DIR_FOUND=$(echo "$PARSED" | jq -r '.directiveFound // false')
  DIR_QUOTE=$(echo "$PARSED" | jq -r '.directiveQuote // ""')
  REASONING=$(echo "$PARSED" | jq -r '.reasoning // ""')

  assert_eq "true" "$DIR_FOUND" "Pass B: Directive found in context"
  assert_contains "Display-only announcement" "$DIR_QUOTE" "Pass B: Directive quote correct"

  echo ""
  echo "  Directive found: $DIR_FOUND"
  echo "  Directive quote: $(echo "$DIR_QUOTE" | head -c 150)"
  echo "  Reasoning (first 400 chars): $(echo "$REASONING" | head -c 400)"
fi

# ============================================================
# Scenario 2: Different phase + skill (Phase 1: Analysis Loop, /analyze)
# Verifies the intent report adapts to context, not hardcoded to Phase 3
# ============================================================

echo ""
echo "======================================"
echo "Scenario 2: Phase 1 Analysis Loop"
echo "======================================"
echo ""

# Rewrite .state.json for different phase/skill
cat > "$TEST_SESSION/.state.json" <<STATE_EOF
{
  "pid": $$,
  "skill": "analyze",
  "lifecycle": "active",
  "currentPhase": "1: Analysis Loop",
  "contextUsage": 0.10,
  "toolCallsSinceLastLog": 0,
  "toolUseWithoutLogsWarnAfter": 100,
  "toolUseWithoutLogsBlockAfter": 200
}
STATE_EOF

# ---- Scenario 2 Pass A: Real text output ----
echo "--- Scenario 2 Pass A: Real text output ---"

PROMPT_S2A='You are an agent following the workflow engine protocol. You are in Phase 1: Analysis Loop of an /analyze session. The task is to audit the authentication middleware for security vulnerabilities.

Your system context contains COMMANDS.md which defines §CMD_REPORT_INTENT. Execute it now. Produce ONLY the intent report — nothing else.'

RESULT_S2A=$(invoke_claude "$PROMPT_S2A" "" "none" "2" "--disable-slash-commands" 2>&1) || true
RESULT_S2_TEXT=$(echo "$RESULT_S2A" | jq -r '.result // ""' 2>/dev/null)

echo "$RESULT_S2A" > "$PROJECT_DIR/s2-pass-a-transcript.json"

if [ -z "$RESULT_S2_TEXT" ] || [ "$RESULT_S2_TEXT" = "null" ]; then
  fail "S2 Pass A: Claude returned no text output"
  echo "  Raw (first 300 chars): $(echo "$RESULT_S2A" | head -c 300)"
else
  # Blockquote format
  S2_BQ_COUNT=$(echo "$RESULT_S2_TEXT" | grep -c '^>' 2>/dev/null || true)
  if [ "$S2_BQ_COUNT" -gt 0 ]; then
    pass "S2 Pass A: Real output contains blockquote lines ($S2_BQ_COUNT lines)"
  else
    fail "S2 Pass A: Real output contains blockquote lines"
    echo "  Got (first 400 chars): $(echo "$RESULT_S2_TEXT" | head -c 400)"
  fi

  # Phase reference — must mention Phase 1 or Analysis, NOT Phase 3 or Planning
  if echo "$RESULT_S2_TEXT" | grep -qi "phase 1\|analysis" 2>/dev/null; then
    pass "S2 Pass A: Real output mentions Phase 1/Analysis (correct phase)"
  else
    fail "S2 Pass A: Real output mentions Phase 1/Analysis (correct phase)"
    echo "  Got (first 400 chars): $(echo "$RESULT_S2_TEXT" | head -c 400)"
  fi

  # Should NOT mention Phase 3/Planning (would indicate hardcoded behavior)
  if echo "$RESULT_S2_TEXT" | grep -qi "phase 3\|planning" 2>/dev/null; then
    fail "S2 Pass A: Output does NOT mention Phase 3/Planning (wrong phase leaked)"
    echo "  Intent report contains Phase 3/Planning reference — may be hardcoded"
  else
    pass "S2 Pass A: Output does NOT mention Phase 3/Planning (no cross-contamination)"
  fi

  # Structured intent (3-line blockquote: What/How/Not-what)
  S2_INTENT_LINES=$(echo "$RESULT_S2_TEXT" | grep -cE '^\s*>' 2>/dev/null || true)
  if [ "$S2_INTENT_LINES" -ge 3 ]; then
    pass "S2 Pass A: Real output has structured intent ($S2_INTENT_LINES blockquote lines)"
  else
    fail "S2 Pass A: Real output has structured intent"
    echo "  Expected: 3+ blockquote lines (> prefix)"
    echo "  Got (first 400 chars): $(echo "$RESULT_S2_TEXT" | head -c 400)"
  fi

  echo ""
  echo "  Blockquote lines: $S2_BQ_COUNT"
  echo "  Intent blockquote lines: $S2_INTENT_LINES"
  echo "  Real text (first 500 chars):"
  echo "  $(echo "$RESULT_S2_TEXT" | head -c 500)"
fi

echo ""
exit_with_results
