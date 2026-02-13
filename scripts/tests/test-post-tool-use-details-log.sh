#!/bin/bash
# ~/.claude/engine/scripts/tests/test-post-tool-use-details-log.sh
# Tests for the PostToolUse DETAILS.md auto-logging hook (post-tool-use-details-log.sh)
#
# Tests: single question, multi-question, no session, structured answers,
# preamble extraction from transcript, missing transcript, "Other" free-text,
# non-AskUserQuestion tools (guard check).
#
# Run: bash ~/.claude/engine/scripts/tests/test-post-tool-use-details-log.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK_SH="$HOME/.claude/engine/hooks/post-tool-use-details-log.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"
LOG_SH="$HOME/.claude/scripts/log.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""
ORIGINAL_PWD=""
SESSION_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  ORIGINAL_PWD="$PWD"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/hooks"
  mkdir -p "$HOME/.claude/engine/hooks"

  # Link lib.sh into fake home
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  # Link log.sh into fake home
  ln -sf "$LOG_SH" "$HOME/.claude/scripts/log.sh"
  # Link the hook into fake home (engine path)
  ln -sf "$HOOK_SH" "$HOME/.claude/engine/hooks/post-tool-use-details-log.sh"

  # Create a fake session dir
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"
  echo '{"skill":"implement","currentPhase":"4: Build Loop"}' > "$SESSION_DIR/.state.json"

  # Create a fake session.sh that returns our test session dir
  cat > "$HOME/.claude/scripts/session.sh" <<SCRIPT
#!/bin/bash
if [ "\${1:-}" = "find" ]; then
  echo "$SESSION_DIR"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  cd "$TEST_DIR"
}

teardown() {
  cd "$ORIGINAL_PWD"
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the hook with given JSON input
run_hook() {
  local input="$1"
  echo "$input" | bash "$HOME/.claude/engine/hooks/post-tool-use-details-log.sh" 2>/dev/null
}

# Helper: read DETAILS.md content
read_details() {
  if [ -f "$SESSION_DIR/DETAILS.md" ]; then
    cat "$SESSION_DIR/DETAILS.md"
  else
    echo ""
  fi
}

# ============================================================
# Test 1: Single question with single-select
# ============================================================
test_single_question() {
  run_hook '{
    "tool_name": "AskUserQuestion",
    "tool_input": {
      "questions": [
        {
          "question": "How deep should interrogation go?",
          "header": "Depth",
          "options": [
            {"label": "Short (3+)", "description": "Well-understood task"},
            {"label": "Medium (6+)", "description": "Some unknowns"}
          ],
          "multiSelect": false
        }
      ]
    },
    "tool_response": "Short (3+)",
    "session_id": "test123",
    "tool_use_id": "toolu_01ABC"
  }'

  local details
  details=$(read_details)

  assert_contains "## " "$details" "T1: DETAILS.md has heading"
  assert_contains "Depth" "$details" "T1: Header appears in heading"
  assert_contains "How deep should interrogation go?" "$details" "T1: Question text present"
  assert_contains "Short (3+)" "$details" "T1: Option labels present"
  assert_contains "Medium (6+)" "$details" "T1: Second option present"
  assert_contains "Q&A (auto-logged)" "$details" "T1: Type tag present"
  assert_contains "Short (3+)" "$details" "T1: User response present"
}

# ============================================================
# Test 2: Multiple questions
# ============================================================
test_multi_question() {
  run_hook '{
    "tool_name": "AskUserQuestion",
    "tool_input": {
      "questions": [
        {
          "question": "What enforcement model?",
          "header": "Model",
          "options": [
            {"label": "Block", "description": "Block immediately"},
            {"label": "Warn", "description": "Warn only"}
          ],
          "multiSelect": false
        },
        {
          "question": "Which scope?",
          "header": "Scope",
          "options": [
            {"label": "All calls", "description": "Every AskUserQuestion"},
            {"label": "Interrogation only", "description": "Only during interrogation"}
          ],
          "multiSelect": false
        }
      ]
    },
    "tool_response": "Block, All calls",
    "session_id": "test123",
    "tool_use_id": "toolu_02ABC"
  }'

  local details
  details=$(read_details)

  assert_contains "Q1:" "$details" "T2: First question numbered"
  assert_contains "Q2:" "$details" "T2: Second question numbered"
  assert_contains "What enforcement model?" "$details" "T2: Q1 text present"
  assert_contains "Which scope?" "$details" "T2: Q2 text present"
}

# ============================================================
# Test 3: No active session — should exit silently
# ============================================================
test_no_session() {
  # Override session.sh to return nothing
  cat > "$HOME/.claude/scripts/session.sh" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/session.sh"

  run_hook '{
    "tool_name": "AskUserQuestion",
    "tool_input": {
      "questions": [{"question": "Test?", "header": "Test", "options": [{"label": "A", "description": "a"}], "multiSelect": false}]
    },
    "tool_response": "A",
    "session_id": "test123",
    "tool_use_id": "toolu_03ABC"
  }'

  assert_file_not_exists "$SESSION_DIR/DETAILS.md" "T3: No DETAILS.md when no session"
}

# ============================================================
# Test 4: Non-AskUserQuestion tool — should exit immediately
# ============================================================
test_non_ask_tool() {
  run_hook '{
    "tool_name": "Bash",
    "tool_input": {"command": "echo hello"},
    "tool_response": "hello",
    "session_id": "test123",
    "tool_use_id": "toolu_04ABC"
  }'

  assert_file_not_exists "$SESSION_DIR/DETAILS.md" "T4: No DETAILS.md for non-AskUserQuestion"
}

# ============================================================
# Test 5: Multi-select question
# ============================================================
test_multiselect() {
  run_hook '{
    "tool_name": "AskUserQuestion",
    "tool_input": {
      "questions": [
        {
          "question": "Which features to enable?",
          "header": "Features",
          "options": [
            {"label": "Auto-log", "description": "Automatic logging"},
            {"label": "Blocking", "description": "Block on failure"},
            {"label": "Alerts", "description": "Send alerts"}
          ],
          "multiSelect": true
        }
      ]
    },
    "tool_response": "Auto-log, Alerts",
    "session_id": "test123",
    "tool_use_id": "toolu_05ABC"
  }'

  local details
  details=$(read_details)

  assert_contains "multi-select" "$details" "T5: Multi-select indicator present"
  assert_contains "Auto-log / Blocking / Alerts" "$details" "T5: All options listed"
}

# ============================================================
# Test 6: Preamble extraction from transcript
# ============================================================
test_preamble_from_transcript() {
  # Create a mock transcript with an assistant text block followed by tool_use
  local transcript_file="$TEST_DIR/transcript.jsonl"
  cat > "$transcript_file" <<'JSONL'
{"type":"human","message":{"content":[{"type":"text","text":"implement the hook"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will now ask about the enforcement model. Based on my analysis of the existing hooks, there are three approaches we could take."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Test?"}]}}]}}
JSONL

  run_hook "{
    \"tool_name\": \"AskUserQuestion\",
    \"tool_input\": {
      \"questions\": [{\"question\": \"Test?\", \"header\": \"Test\", \"options\": [{\"label\": \"A\", \"description\": \"a\"}], \"multiSelect\": false}]
    },
    \"tool_response\": \"A\",
    \"transcript_path\": \"$transcript_file\",
    \"session_id\": \"test123\",
    \"tool_use_id\": \"toolu_06ABC\"
  }"

  local details
  details=$(read_details)

  assert_contains "Premise" "$details" "T6: Premise section present"
  assert_contains "enforcement model" "$details" "T6: Preamble text extracted from transcript"
}

# ============================================================
# Test 7: Missing transcript — should still log without Premise
# ============================================================
test_missing_transcript() {
  run_hook '{
    "tool_name": "AskUserQuestion",
    "tool_input": {
      "questions": [{"question": "Quick test?", "header": "Quick", "options": [{"label": "Yes", "description": "y"}], "multiSelect": false}]
    },
    "tool_response": "Yes",
    "transcript_path": "/nonexistent/path/transcript.jsonl",
    "session_id": "test123",
    "tool_use_id": "toolu_07ABC"
  }'

  local details
  details=$(read_details)

  assert_contains "Quick test?" "$details" "T7: Question still logged without transcript"
  assert_not_contains "Premise" "$details" "T7: No Premise section when transcript missing"
}

# ============================================================
# Test 8: "Other" free-text response
# ============================================================
test_other_freetext() {
  run_hook '{
    "tool_name": "AskUserQuestion",
    "tool_input": {
      "questions": [{"question": "Which approach?", "header": "Approach", "options": [{"label": "A", "description": "a"}, {"label": "B", "description": "b"}], "multiSelect": false}]
    },
    "tool_response": "I want a completely different approach using websockets",
    "session_id": "test123",
    "tool_use_id": "toolu_08ABC"
  }'

  local details
  details=$(read_details)

  assert_contains "completely different approach" "$details" "T8: Free-text Other response captured"
}

# ============================================================
# Test H1.1: Heredoc preserves dollar variables (regression)
# ============================================================
test_heredoc_preserves_dollar_vars() {
  local input
  input=$(jq -n \
    --arg resp 'My path is $HOME/docs and $USER is me' \
    '{
      tool_name: "AskUserQuestion",
      tool_input: {
        questions: [{question: "Where are your files?", header: "Location", options: [{label: "Default", description: "d"}], multiSelect: false}]
      },
      tool_response: $resp,
      session_id: "test123",
      tool_use_id: "toolu_H1_1"
    }')

  run_hook "$input"

  local details
  details=$(read_details)

  assert_contains '$HOME' "$details" "H1.1: Literal \$HOME preserved in DETAILS.md"
  assert_contains '$USER' "$details" "H1.1: Literal \$USER preserved in DETAILS.md"
  assert_not_contains "$ORIGINAL_HOME" "$details" "H1.1: \$HOME was NOT expanded to real path"
}

# ============================================================
# Test H1.2: Heredoc preserves command substitutions (regression)
# ============================================================
test_heredoc_preserves_command_substitution() {
  local input
  input=$(jq -n \
    --arg resp 'Run `whoami` or use $(date) for timestamps' \
    '{
      tool_name: "AskUserQuestion",
      tool_input: {
        questions: [{question: "How to get user info?", header: "UserInfo", options: [{label: "Default", description: "d"}], multiSelect: false}]
      },
      tool_response: $resp,
      session_id: "test123",
      tool_use_id: "toolu_H1_2"
    }')

  run_hook "$input"

  local details
  details=$(read_details)

  assert_contains '$(date)' "$details" "H1.2: Literal \$(date) preserved in DETAILS.md"
  assert_contains 'whoami' "$details" "H1.2: Backtick-whoami text preserved in DETAILS.md"
  # If $(date) was expanded, it would produce output like "Thu Feb 13 ..." in the user response line.
  # We check the User response line specifically for the literal form.
  local user_line
  user_line=$(echo "$details" | grep 'use .*(date)' || true)
  assert_not_empty "$user_line" "H1.2: User response line with date reference exists"
  assert_contains '$(date)' "$user_line" "H1.2: \$(date) in user response is literal, not expanded"
}

# ============================================================
# Test H1.3: Heredoc preserves backslashes (regression)
# ============================================================
test_heredoc_preserves_backslashes() {
  local input
  input=$(jq -n \
    --arg resp 'Use \n for newlines and \t for tabs' \
    '{
      tool_name: "AskUserQuestion",
      tool_input: {
        questions: [{question: "How to format output?", header: "Formatting", options: [{label: "Default", description: "d"}], multiSelect: false}]
      },
      tool_response: $resp,
      session_id: "test123",
      tool_use_id: "toolu_H1_3"
    }')

  run_hook "$input"

  local details
  details=$(read_details)

  # Check for literal backslash-n and backslash-t in the user response line.
  # Use grep with fixed string to avoid interpreting \n as a newline.
  local user_line
  user_line=$(echo "$details" | grep -F 'Use \n for newlines' || true)
  assert_not_empty "$user_line" "H1.3: User response contains literal backslash-n"
  local user_line_t
  user_line_t=$(echo "$details" | grep -F '\t for tabs' || true)
  assert_not_empty "$user_line_t" "H1.3: User response contains literal backslash-t"
}

# ============================================================
# Run all tests
# ============================================================
echo "=== PostToolUse DETAILS.md Auto-Logger Tests ==="
echo ""

run_test test_single_question
run_test test_multi_question
run_test test_no_session
run_test test_non_ask_tool
run_test test_multiselect
run_test test_preamble_from_transcript
run_test test_missing_transcript
run_test test_other_freetext
run_test test_heredoc_preserves_dollar_vars
run_test test_heredoc_preserves_command_substitution
run_test test_heredoc_preserves_backslashes

exit_with_results
