#!/bin/bash
# ~/.claude/engine/scripts/tests/test-user-prompt-submit-session-gate.sh
# Tests for the UserPromptSubmit session-gate hook's skill preload and gate behavior.
#
# M2 regression tests: verify safe_json_write + skill preload queuing.
#
# Tests:
#   M2.1: Skill preload path survives malformed .state.json
#   M2.2: Skill preload preserves existing fields when adding pendingPreloads
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
  mkdir -p "$HOME/.claude/engine/.directives/commands"

  # Symlink the hook and lib.sh
  ln -sf "$UPS_HOOK_REAL" "$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh"
  ln -sf "$LIB_SH_REAL" "$HOME/.claude/scripts/lib.sh"

  # Create a fake session dir with valid .state.json
  SESSION_DIR="$TEST_DIR/sessions/m2-test"
  mkdir -p "$SESSION_DIR"
  echo '{"pid":99999,"skill":"test","lifecycle":"active","currentPhase":"2: Build"}' > "$SESSION_DIR/.state.json"

  # Create the skill directory with a SKILL.md containing Phase 0 commands
  mkdir -p "$HOME/.claude/skills/mtest"
  cat > "$HOME/.claude/skills/mtest/SKILL.md" <<'SKILL'
---
name: mtest
description: "Test skill for M2 regression tests"
---
# M2 Test Skill

```json
{
  "taskType": "TEST",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_M2TEST"],
      "commands": []}
  ]
}
```
SKILL

  # Create the CMD file that extract_skill_preloads will find
  echo "# M2 Test Command" > "$HOME/.claude/engine/.directives/commands/CMD_M2TEST.md"

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
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: run the UserPromptSubmit hook with a /skill-name prompt
run_ups_hook() {
  local skill_name="$1"
  (
    export SESSION_REQUIRED=1
    printf '{"prompt":"/%s","session_id":"test"}\n' "$skill_name" \
      | bash "$HOME/.claude/engine/hooks/user-prompt-submit-session-gate.sh" 2>/dev/null
  )
}

# ============================================================
# M2.1: Skill preload survives malformed .state.json
# ============================================================
test_preload_graceful_on_malformed_state() {
  # Write malformed JSON — jq will fail to parse this
  echo '{invalid json' > "$SESSION_DIR/.state.json"

  # Trigger the hook — should still produce additionalContext (direct delivery works
  # without session state). The hook exits 0 because skill preload succeeds even
  # when session queuing fails.
  local output
  output=$(run_ups_hook "mtest" 2>/dev/null || true)
  local has_preloaded
  has_preloaded=$(echo "$output" | grep -c "Preloaded:" || true)
  assert_gt "$has_preloaded" 0 "M2.1: hook outputs additionalContext despite malformed .state.json"
}

# ============================================================
# M2.2: Skill preload preserves existing fields
# ============================================================
test_preload_preserves_existing_fields() {
  # Write valid .state.json with custom fields
  cat > "$SESSION_DIR/.state.json" <<'JSON'
{"pid":99999,"skill":"test","lifecycle":"active","currentPhase":"2: Build","customField":"keep-me"}
JSON

  # Trigger the hook — should add pendingPreloads without losing other fields
  run_ups_hook "mtest" || true

  # Assert all original fields survived
  assert_json "$SESSION_DIR/.state.json" '.skill' "test" "M2.2: .skill field preserved"
  assert_json "$SESSION_DIR/.state.json" '.lifecycle' "active" "M2.2: .lifecycle field preserved"
  assert_json "$SESSION_DIR/.state.json" '.currentPhase' "2: Build" "M2.2: .currentPhase field preserved"
  assert_json "$SESSION_DIR/.state.json" '.customField' "keep-me" "M2.2: .customField preserved"

  # Assert pendingPreloads was added — SKILL.md fits <9K budget so it's preloaded first
  local pending_len
  pending_len=$(jq -r '.pendingPreloads // [] | length' "$SESSION_DIR/.state.json" 2>/dev/null || echo "0")
  assert_gt "$pending_len" 0 "M2.2: pendingPreloads contains skill file"

  local first_preload
  first_preload=$(jq -r '.pendingPreloads[0] // ""' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
  assert_eq "~/.claude/skills/mtest/SKILL.md" "$first_preload" "M2.2: pendingPreloads[0] is SKILL.md (budget-aware preload)"
}

# ============================================================
# Run all tests
# ============================================================
echo "=== UserPromptSubmit Session Gate — M2 Regression Tests ==="
echo ""

run_test test_preload_graceful_on_malformed_state
run_test test_preload_preserves_existing_fields

exit_with_results
