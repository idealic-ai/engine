#!/bin/bash
# ~/.claude/engine/scripts/tests/test-user-prompt-submit-session-gate.sh
# Tests for the UserPromptSubmit session-gate hook's skill signal and gate behavior.
#
# UPS is now lightweight: detects /skill-name at prompt start, emits a signal.
# Actual preloading is handled by post-tool-use-templates.sh.
#
# Tests:
#   S1: Skill signal emitted for valid /skill-name at prompt start
#   S2: No signal for /skill-name in middle of prompt
#   S3: Signal works with leading whitespace
#   S4: No signal for unknown skill directory
#   S5: Gate message when no active session
#   S6: Gate message when session completed
#   S7: No gate message when session active
#   S8: Skill signal + gate message combined
#   S9: No .state.json modification (UPS is read-only now)
#   S10: No output when SESSION_REQUIRED is not set
#
# Run: bash ~/.claude/engine/scripts/tests/test-user-prompt-submit-session-gate.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths BEFORE HOME switch
UPS_HOOK_REAL="$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh"
LIB_SH_REAL="$HOME/.claude/scripts/lib.sh"

TEST_DIR=""
ORIGINAL_HOME=""
SESSION_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/hooks"
  mkdir -p "$HOME/.claude/engine/hooks"

  # Symlink the hook and lib.sh
  ln -sf "$UPS_HOOK_REAL" "$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh"
  ln -sf "$LIB_SH_REAL" "$HOME/.claude/scripts/lib.sh"

  # Create a fake session dir with valid .state.json
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"
  echo '{"pid":99999,"skill":"implement","lifecycle":"active","currentPhase":"2: Build"}' > "$SESSION_DIR/.state.json"

  # Create skill directory
  mkdir -p "$HOME/.claude/skills/mtest"
  echo "# Test Skill" > "$HOME/.claude/skills/mtest/SKILL.md"

  # Mock session.sh — returns our test session dir for "find"
  cat > "$HOME/.claude/scripts/session.sh" <<MOCK
#!/bin/bash
case "\${1:-}" in
  find) echo "$SESSION_DIR" ;;
  *)    exit 0 ;;
esac
MOCK
  chmod +x "$HOME/.claude/scripts/session.sh"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the UPS hook with a given prompt
run_ups_hook() {
  local prompt="$1"
  (
    export SESSION_REQUIRED=1
    printf '{"prompt":"%s","session_id":"test"}\n' "$prompt" \
      | bash "$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh" 2>/dev/null
  )
}

# ============================================================
# S1: Skill signal emitted for /skill-name at prompt start
# ============================================================
test_signal_emitted_for_valid_skill() {
  local output
  output=$(run_ups_hook "/mtest implement something" 2>/dev/null || true)
  local has_base_dir
  has_base_dir=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null | grep -c "Dont forget to activate" || true)
  assert_gt "$has_base_dir" 0 "S1: signal contains 'Dont forget to activate'"
}

# ============================================================
# S2: No signal for /skill-name in middle of prompt
# ============================================================
test_no_signal_for_mid_prompt_skill() {
  local output
  output=$(run_ups_hook "please run /mtest now" 2>/dev/null || true)
  local ac
  ac=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_base_dir
  has_base_dir=$(echo "$ac" | grep -c "Dont forget to activate" || true)
  assert_eq "0" "$has_base_dir" "S2: no skill signal for mid-prompt /skill"
}

# ============================================================
# S3: Signal works with leading whitespace
# ============================================================
test_signal_with_leading_whitespace() {
  local output
  output=$(run_ups_hook "  /mtest do something" 2>/dev/null || true)
  local has_base_dir
  has_base_dir=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null | grep -c "Dont forget to activate" || true)
  assert_gt "$has_base_dir" 0 "S3: signal emitted with leading whitespace"
}

# ============================================================
# S4: No signal for unknown skill directory
# ============================================================
test_no_signal_for_unknown_skill() {
  local output
  output=$(run_ups_hook "/nonexistent do something" 2>/dev/null || true)
  # Should produce either empty output or only gate message (no skill signal)
  local ac
  ac=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_base_dir
  has_base_dir=$(echo "$ac" | grep -c "Dont forget to activate" || true)
  assert_eq "0" "$has_base_dir" "S4: no signal for nonexistent skill"
}

# ============================================================
# S5: Gate message when no active session
# ============================================================
test_gate_no_session() {
  # Mock session.sh to return nothing
  cat > "$HOME/.claude/scripts/session.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$HOME/.claude/scripts/session.sh"

  local output
  output=$(run_ups_hook "hello" 2>/dev/null || true)
  local ac
  ac=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_gate
  has_gate=$(echo "$ac" | grep -c "No active session" || true)
  assert_gt "$has_gate" 0 "S5: gate message when no session"
}

# ============================================================
# S6: Gate message when session completed
# ============================================================
test_gate_completed_session() {
  echo '{"pid":99999,"skill":"implement","lifecycle":"completed","currentPhase":"5: Done"}' > "$SESSION_DIR/.state.json"
  local output
  output=$(run_ups_hook "hello" 2>/dev/null || true)
  local ac
  ac=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_gate
  has_gate=$(echo "$ac" | grep -c "is completed" || true)
  assert_gt "$has_gate" 0 "S6: gate message for completed session"
}

# ============================================================
# S7: No gate message when session active
# ============================================================
test_no_gate_when_active() {
  echo '{"pid":99999,"skill":"implement","lifecycle":"active","currentPhase":"2: Build"}' > "$SESSION_DIR/.state.json"
  local output
  output=$(run_ups_hook "hello" 2>/dev/null || true)
  local ac
  ac=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_gate
  has_gate=$(echo "$ac" | grep -c "CMD_REQUIRE_ACTIVE_SESSION" || true)
  assert_eq "0" "$has_gate" "S7: no gate message when session is active"
}

# ============================================================
# S8: Skill signal + gate message combined
# ============================================================
test_signal_plus_gate_combined() {
  echo '{"pid":99999,"skill":"implement","lifecycle":"completed","currentPhase":"5: Done"}' > "$SESSION_DIR/.state.json"
  local output
  output=$(run_ups_hook "/mtest implement" 2>/dev/null || true)
  local ac
  ac=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
  local has_base_dir has_gate
  has_base_dir=$(echo "$ac" | grep -c "Dont forget to activate" || true)
  has_gate=$(echo "$ac" | grep -c "is completed" || true)
  assert_gt "$has_base_dir" 0 "S8: skill signal present"
  assert_gt "$has_gate" 0 "S8: gate message present"
}

# ============================================================
# S9: No .state.json modification
# ============================================================
test_no_state_modification() {
  local before_md5
  before_md5=$(md5 -q "$SESSION_DIR/.state.json" 2>/dev/null || md5sum "$SESSION_DIR/.state.json" | cut -d' ' -f1)
  run_ups_hook "/mtest do stuff" || true
  local after_md5
  after_md5=$(md5 -q "$SESSION_DIR/.state.json" 2>/dev/null || md5sum "$SESSION_DIR/.state.json" | cut -d' ' -f1)
  assert_eq "$before_md5" "$after_md5" "S9: .state.json not modified by UPS"
}

# ============================================================
# S10: No output when SESSION_REQUIRED not set
# ============================================================
test_no_output_without_session_required() {
  local output
  output=$(
    unset SESSION_REQUIRED
    printf '{"prompt":"/mtest","session_id":"test"}\n' \
      | bash "$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh" 2>/dev/null
  )
  assert_eq "" "$output" "S10: no output when SESSION_REQUIRED unset"
}

# ============================================================
# Run all tests
# ============================================================
echo "=== UserPromptSubmit Session Gate Tests ==="
echo ""

run_test test_signal_emitted_for_valid_skill
run_test test_no_signal_for_mid_prompt_skill
run_test test_signal_with_leading_whitespace
run_test test_no_signal_for_unknown_skill
run_test test_gate_no_session
run_test test_gate_completed_session
run_test test_no_gate_when_active
run_test test_signal_plus_gate_combined
run_test test_no_state_modification
run_test test_no_output_without_session_required

exit_with_results
