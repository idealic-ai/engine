#!/bin/bash
# ~/.claude/engine/scripts/tests/test-user-prompt-submit-session-gate.sh
# Tests for the UserPromptSubmit session-gate hook's discovery write path.
#
# M2 regression tests: The hook writes to .state.json using raw
# "jq > .tmp && mv" instead of safe_json_write (no locking, no validation).
#
# Tests:
#   M2.1: Discovery path survives malformed .state.json
#   M2.2: Discovery path preserves existing fields when adding pendingDirectives
#
# Run: bash ~/.claude/engine/scripts/tests/test-user-prompt-submit-session-gate.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths BEFORE HOME switch (PITFALL: circular symlinks)
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
  # The hook sources lib.sh from $HOME/.claude/scripts/lib.sh
  ln -sf "$LIB_SH_REAL" "$HOME/.claude/scripts/lib.sh"

  # Create a fake session dir with valid .state.json
  SESSION_DIR="$TEST_DIR/sessions/m2-test"
  mkdir -p "$SESSION_DIR"
  echo '{"pid":99999,"skill":"test","lifecycle":"active","currentPhase":"2: Build"}' > "$SESSION_DIR/.state.json"

  # Create the skill directory so the hook enters the discovery path
  mkdir -p "$HOME/.claude/skills/m2skill"

  # Create a fake directive file that discover-directives will "find"
  echo "# Test Directive" > "$TEST_DIR/m2-directive.md"

  # Mock session.sh — returns our test session dir for "find", activate exits 0
  cat > "$HOME/.claude/scripts/session.sh" <<MOCK
#!/bin/bash
case "\${1:-}" in
  find) echo "$SESSION_DIR" ;;
  activate) exit 0 ;;
  *)    exit 0 ;;
esac
MOCK
  chmod +x "$HOME/.claude/scripts/session.sh"

  # Mock discover-directives.sh — outputs our fake directive path
  cat > "$HOME/.claude/scripts/discover-directives.sh" <<MOCK
#!/bin/bash
echo "$TEST_DIR/m2-directive.md"
MOCK
  chmod +x "$HOME/.claude/scripts/discover-directives.sh"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the UserPromptSubmit hook with a skill command prompt
run_ups_hook() {
  local skill_name="$1"
  (
    export SESSION_REQUIRED=1
    printf '{"prompt":"<command-name>/%s</command-name>","session_id":"test"}\n' "$skill_name" \
      | bash "$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh" 2>/dev/null
  )
}

# ============================================================
# M2.1: Discovery survives malformed .state.json
# ============================================================
test_discovery_survives_malformed_state() {
  # Write malformed JSON — jq will fail to parse this
  echo '{invalid json' > "$SESSION_DIR/.state.json"

  # Trigger the hook — jq should fail on malformed JSON, && prevents mv
  run_ups_hook "m2skill" || true

  # The original malformed content should survive (jq fails, && prevents mv)
  local content
  content=$(cat "$SESSION_DIR/.state.json")
  assert_eq '{invalid json' "$content" "M2.1: malformed .state.json not clobbered by failed jq"
}

# ============================================================
# M2.2: Discovery preserves existing fields
# ============================================================
test_discovery_preserves_existing_fields() {
  # Write valid .state.json with custom fields
  cat > "$SESSION_DIR/.state.json" <<'JSON'
{"pid":99999,"skill":"test","lifecycle":"active","currentPhase":"2: Build","customField":"keep-me"}
JSON

  # Trigger the hook — should add pendingDirectives without losing other fields
  run_ups_hook "m2skill" || true

  # Assert all original fields survived the raw jq write
  assert_json "$SESSION_DIR/.state.json" '.skill' "test" "M2.2: .skill field preserved"
  assert_json "$SESSION_DIR/.state.json" '.lifecycle' "active" "M2.2: .lifecycle field preserved"
  assert_json "$SESSION_DIR/.state.json" '.currentPhase' "2: Build" "M2.2: .currentPhase field preserved"
  assert_json "$SESSION_DIR/.state.json" '.customField' "keep-me" "M2.2: .customField preserved"

  # Assert pendingDirectives was added with the discovered file
  local pending_len
  pending_len=$(jq -r '.pendingDirectives // [] | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")
  assert_gt "$pending_len" 0 "M2.2: pendingDirectives contains discovered directive"

  local first_directive
  first_directive=$(jq -r '.pendingDirectives[0] // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  assert_eq "$TEST_DIR/m2-directive.md" "$first_directive" "M2.2: pendingDirectives[0] is the discovered file"
}

# ============================================================
# Run all tests
# ============================================================
echo "=== UserPromptSubmit Session Gate — M2 Regression Tests ==="
echo ""

run_test test_discovery_survives_malformed_state
run_test test_discovery_preserves_existing_fields

exit_with_results
