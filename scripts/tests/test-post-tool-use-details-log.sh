#!/bin/bash
# Integration test: post-tool-use-details-log.sh (full hook pipeline)
# Tests the complete flow: JSON input → content extraction → tag escaping → DIALOGUE.md output
#
# Strategy:
#   - Override $HOME to an isolated temp dir
#   - Provide real lib.sh, real log.sh, real hook script
#   - Stub session.sh (returns controlled session dir)
#   - Each test: create temp session dir, pipe JSON, verify DIALOGUE.md
set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# --- Setup ---
REAL_HOME="$HOME"
TEST_ROOT=$(mktemp -d)
FAKE_HOME="$TEST_ROOT/fakehome"
SCRIPTS_DIR="$FAKE_HOME/.claude/scripts"
HOOKS_DIR="$FAKE_HOME/.claude/hooks"
mkdir -p "$SCRIPTS_DIR" "$HOOKS_DIR"

# Copy real scripts into fake HOME
cp "$REAL_HOME/.claude/scripts/lib.sh" "$SCRIPTS_DIR/lib.sh"
cp "$REAL_HOME/.claude/scripts/log.sh" "$SCRIPTS_DIR/log.sh"
cp "$REAL_HOME/.claude/hooks/post-tool-use-details-log.sh" "$HOOKS_DIR/hook.sh"
chmod +x "$SCRIPTS_DIR/log.sh" "$HOOKS_DIR/hook.sh"

# Active session dir (overridden per test via stub session.sh)
ACTIVE_SESSION=""

# Create stub session.sh — returns $ACTIVE_SESSION
cat > "$SCRIPTS_DIR/session.sh" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "find" ]; then
  cat "$HOME/.claude/_test_session_dir" 2>/dev/null || echo ""
  exit 0
fi
exit 0
STUB
chmod +x "$SCRIPTS_DIR/session.sh"

# Alias for engine command (log.sh is called via "$HOME/.claude/scripts/log.sh")
# The hook calls log.sh directly, so we just need the scripts dir to be correct

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

# --- Helpers ---

assert_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -qF "$pattern" "$file" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    local actual
    actual=$(cat "$file" 2>/dev/null || echo "(file not found)")
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected to contain: $pattern\n    file contents:\n$(echo "$actual" | head -20 | sed 's/^/      /')"
    echo "  FAIL: $label"
    echo "    expected to contain: $pattern"
  fi
}

assert_not_contains() {
  local label="$1" file="$2" pattern="$3"
  if ! grep -qF "$pattern" "$file" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    should NOT contain: $pattern"
    echo "  FAIL: $label"
    echo "    should NOT contain: $pattern"
  fi
}

assert_file_not_exists() {
  local label="$1" file="$2"
  if [ ! -f "$file" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    file should not exist: $file"
    echo "  FAIL: $label"
    echo "    file should not exist: $file"
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected exit code: $expected\n    actual exit code: $actual"
    echo "  FAIL: $label"
    echo "    expected exit: $expected, actual: $actual"
  fi
}

# setup_session: create a temp session dir with .state.json, set it as active
setup_session() {
  local session_dir="$TEST_ROOT/session_$(date +%s%N)"
  mkdir -p "$session_dir"
  echo '{"skill":"test","currentPhase":"3: Testing Loop"}' > "$session_dir/.state.json"
  ACTIVE_SESSION="$session_dir"
  echo "$session_dir" > "$FAKE_HOME/.claude/_test_session_dir"
  echo "$session_dir"
}

# run_hook: pipe JSON to the hook with fake HOME
run_hook() {
  local json="$1"
  local exit_code=0
  echo "$json" | HOME="$FAKE_HOME" bash "$HOOKS_DIR/hook.sh" 2>/dev/null || exit_code=$?
  echo "$exit_code"
}

# --- Tests ---

echo "=== Integration Tests: post-tool-use-details-log.sh ==="

# --- Case 1: Bare tags in question text → escaped ---
echo ""
echo "Case 1: Bare tags in question text are escaped"
SESSION=$(setup_session)
INPUT=$(cat <<'JSON'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Dispatch",
      "question": "Review the #needs-review tag on this file?",
      "multiSelect": false,
      "options": [{"label": "Yes"}, {"label": "No"}]
    }]
  },
  "tool_response": "Yes",
  "transcript_path": ""
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_contains "question tag escaped in body" "$SESSION/DIALOGUE.md" '`#needs-review`'
assert_not_contains "heading has no bare tag" "$SESSION/DIALOGUE.md" '## Dispatch — Review the #needs-review'

# --- Case 2: Bare tags in option labels → escaped ---
echo ""
echo "Case 2: Bare tags in option labels are escaped"
SESSION=$(setup_session)
INPUT=$(cat <<'JSON'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Approve",
      "question": "What to do with this item?",
      "multiSelect": false,
      "options": [
        {"label": "Approve for #delegated-implementation"},
        {"label": "Defer"}
      ]
    }]
  },
  "tool_response": "Approve for #delegated-implementation",
  "transcript_path": ""
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_contains "option tag escaped" "$SESSION/DIALOGUE.md" '`#delegated-implementation`'

# --- Case 3: Bare tags in user response → escaped ---
echo ""
echo "Case 3: Bare tags in user response are escaped"
SESSION=$(setup_session)
INPUT=$(cat <<'JSON'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Action",
      "question": "What should we do next?",
      "multiSelect": false,
      "options": [{"label": "Continue"}, {"label": "Stop"}]
    }]
  },
  "tool_response": "I think we need #needs-brainstorm for this topic",
  "transcript_path": ""
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_contains "response tag escaped" "$SESSION/DIALOGUE.md" '`#needs-brainstorm`'

# --- Case 4: Bare tags in preamble (transcript) → escaped ---
echo ""
echo "Case 4: Bare tags in preamble are escaped"
SESSION=$(setup_session)
# Create a mock transcript file with an assistant message containing a bare tag
TRANSCRIPT="$TEST_ROOT/transcript_$(date +%s%N).jsonl"
cat > "$TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"The #active-alert tag indicates an ongoing issue."}]}}
JSONL
INPUT=$(cat <<JSON
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Alert",
      "question": "Acknowledge the alert?",
      "multiSelect": false,
      "options": [{"label": "Yes"}, {"label": "No"}]
    }]
  },
  "tool_response": "Yes",
  "transcript_path": "$TRANSCRIPT"
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_contains "preamble tag escaped" "$SESSION/DIALOGUE.md" '`#active-alert`'

# --- Case 5: Already-backticked tags NOT double-escaped ---
echo ""
echo "Case 5: Already-backticked tags not double-escaped"
SESSION=$(setup_session)
INPUT=$(cat <<'JSON'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Check",
      "question": "The `#needs-review` tag is already escaped here.",
      "multiSelect": false,
      "options": [{"label": "OK"}]
    }]
  },
  "tool_response": "OK",
  "transcript_path": ""
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_contains "single backtick escape present" "$SESSION/DIALOGUE.md" '`#needs-review`'
assert_not_contains "no double backtick" "$SESSION/DIALOGUE.md" '``#needs-review``'
assert_not_contains "no triple backtick" "$SESSION/DIALOGUE.md" '```#needs-review```'

# --- Case 6: Multiple tags across different sources ---
echo ""
echo "Case 6: Multiple tags across different sources"
SESSION=$(setup_session)
TRANSCRIPT6="$TEST_ROOT/transcript6_$(date +%s%N).jsonl"
cat > "$TRANSCRIPT6" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"We should check #claimed-fix status."}]}}
JSONL
INPUT=$(cat <<JSON
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Multi",
      "question": "Should we process #needs-fix items?",
      "multiSelect": false,
      "options": [
        {"label": "Process #delegated-chores too"},
        {"label": "Skip"}
      ]
    }]
  },
  "tool_response": "Yes, also handle #done-review ones",
  "transcript_path": "$TRANSCRIPT6"
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_contains "question tag escaped" "$SESSION/DIALOGUE.md" '`#needs-fix`'
assert_contains "option tag escaped" "$SESSION/DIALOGUE.md" '`#delegated-chores`'
assert_contains "response tag escaped" "$SESSION/DIALOGUE.md" '`#done-review`'
assert_contains "preamble tag escaped" "$SESSION/DIALOGUE.md" '`#claimed-fix`'

# --- Case 7: Non-AskUserQuestion tool → exits cleanly ---
echo ""
echo "Case 7: Non-AskUserQuestion tool exits cleanly"
SESSION=$(setup_session)
INPUT='{"tool_name": "Read", "tool_input": {"file_path": "/tmp/foo"}}'
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0" "0" "$EXIT_CODE"
assert_file_not_exists "no DIALOGUE.md created" "$SESSION/DIALOGUE.md"

# --- Case 8: Missing session → exits cleanly ---
echo ""
echo "Case 8: Missing session exits cleanly"
# Point session.sh to a non-existent dir
echo "" > "$FAKE_HOME/.claude/_test_session_dir"
INPUT=$(cat <<'JSON'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{
      "header": "Test",
      "question": "Should this work?",
      "multiSelect": false,
      "options": [{"label": "Yes"}]
    }]
  },
  "tool_response": "Yes",
  "transcript_path": ""
}
JSON
)
EXIT_CODE=$(run_hook "$INPUT")
assert_exit_code "exits 0 with no session" "0" "$EXIT_CODE"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  printf "$ERRORS\n"
  exit 1
fi
exit 0
