#!/bin/bash
# tests/test-session-gate.sh — Tests for pre-tool-use-session-gate.sh hook
#
# Tests:
#   1. Gate disabled when SESSION_REQUIRED != 1
#   2. AskUserQuestion whitelisted (always allowed)
#   3. Skill whitelisted (always allowed)
#   4. Bash: session.sh/log.sh/tag.sh/glob.sh whitelisted
#   5. Bash: non-whitelisted command denied when no session
#   6. Read: ~/.claude/* paths whitelisted
#   7. Read: .claude/ project paths whitelisted
#   8. Read: CLAUDE.md whitelisted
#   9. Read: memory paths whitelisted
#  10. Read: session .md artifacts whitelisted
#  11. Read: non-whitelisted path denied when no session
#  12. Active session → all tools allowed
#  13. Dehydrating session → all tools allowed
#  14. Completed session → denied with continuation prompt
#  15. No session at all → denied with selection instructions
#
# Uses HOME override for full isolation (prevents concurrent jq writes
# to real .state.json files from PID claiming logic).
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-gate.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/hooks/pre-tool-use-session-gate.sh"
SESSION_SH="$HOME/.claude/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

TMP_DIR=$(mktemp -d)

# Disable fleet/tmux and clear inherited SESSION_REQUIRED from run.sh
unset TMUX 2>/dev/null || true
unset TMUX_PANE 2>/dev/null || true
unset SESSION_REQUIRED 2>/dev/null || true

# Use a dead PID for isolation (won't conflict with real sessions)
export CLAUDE_SUPERVISOR_PID=99999999

# Create fake HOME to isolate session.sh find from real sessions
FAKE_HOME="$TMP_DIR/fake-home"
mkdir -p "$FAKE_HOME/.claude/scripts"
mkdir -p "$FAKE_HOME/.claude/hooks"
mkdir -p "$FAKE_HOME/.claude/tools/session-search"
mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

# Symlink real scripts into fake home
ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"
ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"
ln -sf "$HOOK" "$FAKE_HOME/.claude/hooks/pre-tool-use-session-gate.sh"

# Stub fleet.sh (no fleet)
cat > "$FAKE_HOME/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  pane-id) echo ""; exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
chmod +x "$FAKE_HOME/.claude/scripts/fleet.sh"

# Stub search tools
for tool in session-search doc-search; do
  cat > "$FAKE_HOME/.claude/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
  chmod +x "$FAKE_HOME/.claude/tools/$tool/$tool.sh"
done

# Save original HOME and switch
ORIGINAL_HOME="$HOME"
export HOME="$FAKE_HOME"

# Work in TMP_DIR so session.sh find scans our test sessions
cd "$TMP_DIR"

# Test session — absolute path
TEST_SESSION="$TMP_DIR/sessions/test_gate"
mkdir -p "$TEST_SESSION"

# Resolved hook path (symlinked in fake home)
RESOLVED_HOOK="$FAKE_HOME/.claude/hooks/pre-tool-use-session-gate.sh"

cleanup() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run hook with given tool_name and optional tool_input
# Uses printf for proper JSON construction (avoids double-quote escaping issues)
run_hook() {
  local tool_name="$1"
  local tool_input="${2:-\{\}}"
  local session_required="${3-1}"
  (
    export SESSION_REQUIRED="$session_required"
    printf '{"tool_name":"%s","tool_input":%s}\n' "$tool_name" "$tool_input" \
      | "$RESOLVED_HOOK" 2>/dev/null
  )
}

echo "======================================"
echo "Session Gate Hook Tests"
echo "======================================"
echo ""

# --- 1. Gate disabled ---
echo "--- 1. Gate disabled (SESSION_REQUIRED != 1) ---"

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x"}' "")
assert_contains '"allow"' "$OUT" "SESSION_REQUIRED empty → allow"

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x"}' "0")
assert_contains '"allow"' "$OUT" "SESSION_REQUIRED=0 → allow"

echo ""

# --- 2-3. Tool whitelist (AskUserQuestion, Skill) ---
echo "--- 2-3. Tool whitelist ---"

export SESSION_REQUIRED=1
# No active session — these should still be allowed

OUT=$(run_hook "AskUserQuestion" '{}')
assert_contains '"allow"' "$OUT" "AskUserQuestion always allowed"

OUT=$(run_hook "Skill" '{"skill":"implement"}')
assert_contains '"allow"' "$OUT" "Skill always allowed"

echo ""

# --- 4. Bash whitelist ---
echo "--- 4. Bash whitelist ---"

OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/session.sh find"}')
assert_contains '"allow"' "$OUT" "Bash: session.sh whitelisted"

OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/log.sh foo/LOG.md"}')
assert_contains '"allow"' "$OUT" "Bash: log.sh whitelisted"

OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/tag.sh find #needs-review"}')
assert_contains '"allow"' "$OUT" "Bash: tag.sh whitelisted"

OUT=$(run_hook "Bash" '{"command":"~/.claude/scripts/glob.sh *.md sessions/"}')
assert_contains '"allow"' "$OUT" "Bash: glob.sh whitelisted"

echo ""

# --- 4b. Bash whitelist: engine CLI shorthand ---
echo "--- 4b. Bash whitelist: engine CLI ---"

OUT=$(run_hook "Bash" '{"command":"engine session activate sessions/foo test"}')
assert_contains '"allow"' "$OUT" "Bash: engine session whitelisted"

OUT=$(run_hook "Bash" '{"command":"engine log sessions/foo/LOG.md"}')
assert_contains '"allow"' "$OUT" "Bash: engine log whitelisted"

OUT=$(run_hook "Bash" '{"command":"engine tag find #needs-review"}')
assert_contains '"allow"' "$OUT" "Bash: engine tag whitelisted"

OUT=$(run_hook "Bash" '{"command":"engine glob *.md sessions/"}')
assert_contains '"allow"' "$OUT" "Bash: engine glob whitelisted"

# Edge cases: engine with extra whitespace, partial match
OUT=$(run_hook "Bash" '{"command":"engine  session  phase foo"}')
assert_contains '"allow"' "$OUT" "Bash: engine session with extra spaces"

# Adversarial: engine without subcommand should NOT be whitelisted
OUT=$(run_hook "Bash" '{"command":"engine"}')
assert_contains '"deny"' "$OUT" "Bash: bare engine denied without session"

# Adversarial: engine with non-whitelisted subcommand
OUT=$(run_hook "Bash" '{"command":"engine setup"}')
assert_contains '"deny"' "$OUT" "Bash: engine setup denied without session"

# Adversarial: something that starts with 'engine' but isn't the CLI
OUT=$(run_hook "Bash" '{"command":"engineering-tool run"}')
assert_contains '"deny"' "$OUT" "Bash: engineering-tool not whitelisted"

echo ""

# --- 5. Bash non-whitelisted denied ---
echo "--- 5. Bash non-whitelisted ---"

OUT=$(run_hook "Bash" '{"command":"git status"}')
assert_contains '"deny"' "$OUT" "Bash: git status denied without session"

echo ""

# --- 6-10. Read whitelist ---
echo "--- 6-10. Read whitelist ---"

OUT=$(run_hook "Read" '{"file_path":"'"$FAKE_HOME"'/.claude/directives/COMMANDS.md"}')
assert_contains '"allow"' "$OUT" "Read: ~/.claude/ path whitelisted"

OUT=$(run_hook "Read" '{"file_path":"/Users/invizko/Projects/finch/.claude/directives/INVARIANTS.md"}')
assert_contains '"allow"' "$OUT" "Read: .claude/ project path whitelisted"

OUT=$(run_hook "Read" '{"file_path":"/Users/invizko/Projects/finch/CLAUDE.md"}')
assert_contains '"allow"' "$OUT" "Read: CLAUDE.md whitelisted"

OUT=$(run_hook "Read" '{"file_path":"'"$FAKE_HOME"'/.claude/projects/foo/memory/MEMORY.md"}')
assert_contains '"allow"' "$OUT" "Read: memory path whitelisted"

OUT=$(run_hook "Read" '{"file_path":"'"$TMP_DIR"'/sessions/foo/DEHYDRATED_CONTEXT.md"}')
assert_contains '"allow"' "$OUT" "Read: session .md artifact whitelisted"

echo ""

# --- 11. Read non-whitelisted denied ---
echo "--- 11. Read non-whitelisted ---"

OUT=$(run_hook "Read" '{"file_path":"/tmp/random-file.ts"}')
assert_contains '"deny"' "$OUT" "Read: non-whitelisted path denied"

echo ""

# --- 12-13. Active/dehydrating session allows all ---
echo "--- 12-13. Active session allows all ---"

# Activate test session within isolated environment
export CLAUDE_SUPERVISOR_PID=$$
"$FAKE_HOME/.claude/scripts/session.sh" activate "$TEST_SESSION" test < /dev/null >/dev/null 2>&1

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x"}')
assert_contains '"allow"' "$OUT" "Active session → Edit allowed"

OUT=$(run_hook "Bash" '{"command":"git status"}')
assert_contains '"allow"' "$OUT" "Active session → Bash allowed"

# Set lifecycle to dehydrating
jq '.lifecycle = "dehydrating"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x"}')
assert_contains '"allow"' "$OUT" "Dehydrating session → Edit allowed"

echo ""

# --- 14. Completed session → denied ---
echo "--- 14. Completed session ---"

jq '.lifecycle = "completed"' "$TEST_SESSION/.state.json" > "$TEST_SESSION/.state.json.tmp" \
  && mv "$TEST_SESSION/.state.json.tmp" "$TEST_SESSION/.state.json"

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x"}')
assert_contains '"deny"' "$OUT" "Completed session → denied"
assert_contains 'completed' "$OUT" "Deny message mentions completed"

echo ""

# --- 15. No session at all → denied ---
echo "--- 15. No session ---"

# Remove test session state so find returns nothing
rm -f "$TEST_SESSION/.state.json"
export CLAUDE_SUPERVISOR_PID=99999999

OUT=$(run_hook "Write" '{"file_path":"/tmp/x","content":"foo"}')
assert_contains '"deny"' "$OUT" "No session → denied"
assert_contains '§CMD_REQUIRE_ACTIVE_SESSION' "$OUT" "Deny message says §CMD_REQUIRE_ACTIVE_SESSION"

echo ""

exit_with_results
