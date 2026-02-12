#!/bin/bash
# tests/test-precompact-hook.sh — Tests for the PreCompact kill hook
#
# Tests:
#   PC1: Mini-dehydration generated in .state.json when dehydratedContext missing
#   PC2: Existing dehydratedContext in .state.json preserved (not overwritten)
#   PC3: Session marked as restarting via session.sh restart
#   PC4: No-ops when no session is active
#   PC5: Manual compaction (matcher=manual) exits immediately
#
# Run: bash ~/.claude/engine/scripts/tests/test-precompact-hook.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Capture real paths before fake home
REAL_SCRIPTS_DIR="$HOME/.claude/scripts"
REAL_ENGINE_DIR="$HOME/.claude/engine"

TMP_DIR=$(mktemp -d)
export CLAUDE_SUPERVISOR_PID=$$

setup_fake_home "$TMP_DIR"
disable_fleet_tmux

# Create engine dirs in fake home
mkdir -p "$FAKE_HOME/.claude/engine/hooks"
mkdir -p "$FAKE_HOME/.claude/engine/scripts"

# Symlink core scripts
ln -sf "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$REAL_ENGINE_DIR/hooks/pre-compact-kill.sh" "$FAKE_HOME/.claude/engine/hooks/pre-compact-kill.sh"
ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh" 2>/dev/null || true

# Stub fleet and search tools
mock_fleet_sh "$FAKE_HOME"
mock_search_tools "$FAKE_HOME"

# Work in TMP_DIR
cd "$TMP_DIR"

# Test session
TEST_SESSION="$TMP_DIR/sessions/test_precompact"
mkdir -p "$TEST_SESSION"

HOOK="$FAKE_HOME/.claude/engine/hooks/pre-compact-kill.sh"

cleanup() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Helper: create an active session state
create_active_state() {
  cat > "$TEST_SESSION/.state.json" <<STATEEOF
{
  "activePid": $$,
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "4: Build Loop",
  "taskSummary": "Test task for PreCompact",
  "contextUsage": 0.90,
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0
}
STATEEOF
}

# Helper: run hook in TEST_MODE
run_precompact() {
  local event="${1:-auto}"
  local input
  input=$(jq -n --arg e "$event" '{event: $e}')
  echo "$input" | TEST_MODE=1 bash "$HOOK" 2>/dev/null
}

echo "======================================"
echo "PreCompact Hook Tests"
echo "======================================"
echo ""

# PC1: Mini-dehydration generated in .state.json when dehydratedContext missing
echo "--- PC1: Mini-dehydration generation ---"
create_active_state

# Create a dummy log file so artifact listing has content
echo "# Implementation Log" > "$TEST_SESSION/IMPLEMENTATION_LOG.md"

OUT=$(run_precompact "auto")

# Verify dehydratedContext was written to .state.json
HAS_CTX=$(jq -r '.dehydratedContext // null | type' "$TEST_SESSION/.state.json" 2>/dev/null)
if [ "$HAS_CTX" = "object" ]; then
  pass "PC1a: dehydratedContext written to .state.json"
else
  fail "PC1a: dehydratedContext written to .state.json" "object" "$HAS_CTX"
fi

CTX_SUMMARY=$(jq -r '.dehydratedContext.summary // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_contains "Test task for PreCompact" "$CTX_SUMMARY" "PC1b: dehydratedContext contains taskSummary"

CTX_LAST=$(jq -r '.dehydratedContext.lastAction // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_contains "PreCompact hook triggered" "$CTX_LAST" "PC1c: dehydratedContext contains lastAction marker"

CTX_STEPS=$(jq -r '.dehydratedContext.nextSteps // [] | join(" ")' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_contains "4: Build Loop" "$CTX_STEPS" "PC1d: dehydratedContext nextSteps references currentPhase"

CTX_FILES=$(jq -r '.dehydratedContext.requiredFiles // [] | join(" ")' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_contains "IMPLEMENTATION_LOG.md" "$CTX_FILES" "PC1e: dehydratedContext requiredFiles lists session artifacts"

echo ""

# PC2: Existing dehydratedContext in .state.json preserved
echo "--- PC2: Existing dehydration preserved ---"
# Create state WITH existing dehydratedContext
cat > "$TEST_SESSION/.state.json" <<STATEEOF
{
  "activePid": $$,
  "pid": $$,
  "skill": "implement",
  "lifecycle": "active",
  "currentPhase": "4: Build Loop",
  "taskSummary": "Test task for PreCompact",
  "contextUsage": 0.90,
  "dehydratedContext": {
    "summary": "DO NOT OVERWRITE — existing dehydration",
    "lastAction": "original action",
    "nextSteps": ["original step"],
    "requiredFiles": []
  },
  "toolCallsByTranscript": {},
  "toolCallsSinceLastLog": 0
}
STATEEOF

OUT=$(run_precompact "auto")
CTX_SUMMARY=$(jq -r '.dehydratedContext.summary // ""' "$TEST_SESSION/.state.json" 2>/dev/null)
assert_contains "DO NOT OVERWRITE" "$CTX_SUMMARY" "PC2: Existing dehydratedContext not overwritten"

echo ""

# PC3: TEST_MODE reports would-call session.sh restart
echo "--- PC3: Session restart delegation ---"
create_active_state
rm -f "$TEST_SESSION/DEHYDRATED_CONTEXT.md"

OUT=$(run_precompact "auto")
assert_contains "Would call session.sh restart" "$OUT" "PC3a: TEST_MODE reports restart intent"
assert_contains "$TEST_SESSION" "$OUT" "PC3b: Reports correct session directory"

echo ""

# PC4: No-ops when no session is active
echo "--- PC4: No-op without session ---"
# Remove the test session state to simulate no session
rm -f "$TEST_SESSION/.state.json"

OUT=$(run_precompact "auto")
assert_contains "No active session" "$OUT" "PC4: No-ops gracefully when no session found"

# Restore for next tests
create_active_state

echo ""

# PC5: Manual compaction exits immediately
echo "--- PC5: Manual compaction ignored ---"
create_active_state

OUT=$(run_precompact "manual")
HAS_CTX=$(jq -r '.dehydratedContext // null | type' "$TEST_SESSION/.state.json" 2>/dev/null)
if [ "$HAS_CTX" = "null" ]; then
  pass "PC5: Manual compaction does not trigger hook (no dehydratedContext in .state.json)"
else
  fail "PC5: Manual compaction does not trigger hook (no dehydratedContext in .state.json)" "null" "$HAS_CTX"
fi

echo ""

# ============================================================
# Results
# ============================================================
exit_with_results
