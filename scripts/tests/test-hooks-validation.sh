#!/bin/bash
# Test: Hooks validation — fixes from 2026_02_12_HOOKS_VALIDATION session
#
# Fix 1: Double-load prevention (preloadedFiles dedup in overflow preload handler)
# Fix 2: Descriptive deny message (rule IDs in deny reason)
# Fix 3a: Discovery hook local-outside-function bug
# Fix 3b: directive-autoload urgency allow (non-blocking)
#
# Per ¶INV_TEST_SANDBOX_ISOLATION: Uses temp sandbox, no real project/GDrive writes.

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# --- Setup sandbox ---
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Create minimal session structure
SESSION_DIR="$SANDBOX/sessions/2026_01_01_TEST"
mkdir -p "$SESSION_DIR"

# Source lib.sh for shared utilities
source "$HOME/.claude/scripts/lib.sh"

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected: $expected\n    actual:   $actual"
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected to contain: $needle\n    actual: $haystack"
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    should NOT contain: $needle\n    actual: $haystack"
    echo "  FAIL: $label"
    echo "    should NOT contain: $needle"
    echo "    actual: $haystack"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  fi
}

# ============================================================
# TEST GROUP 1: One-strike hook (rm -rf, git push --force, etc.)
# ============================================================
echo ""
echo "=== Test 1: One-strike hook patterns ==="

ONE_STRIKE="$HOME/.claude/hooks/pre-tool-use-one-strike.sh"
WARNED_DIR="$SANDBOX/warned"
mkdir -p "$WARNED_DIR"

run_one_strike() {
  local cmd="$1"
  local input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}"
  echo "$input" | CLAUDE_SUPERVISOR_PID=$$ CLAUDE_HOOK_WARNED_DIR="$WARNED_DIR" bash "$ONE_STRIKE" 2>/dev/null
}

# Clean warned files
rm -f "$WARNED_DIR"/claude-hook-warned-*

echo ""
echo "Case 1a: rm -rf blocked on first call"
RESULT=$(run_one_strike "rm -rf /tmp/foo")
DECISION=$(echo "$RESULT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo "error")
assert_eq "rm -rf first call denied" "deny" "$DECISION"

echo ""
echo "Case 1b: rm -rf allowed on second call (one-strike)"
RESULT=$(run_one_strike "rm -rf /tmp/foo")
DECISION=$(echo "$RESULT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo "error")
assert_eq "rm -rf second call allowed" "allow" "$DECISION"

# Reset warned files
rm -f "$WARNED_DIR"/claude-hook-warned-*

echo ""
echo "Case 1c: git push --force blocked on first call"
RESULT=$(run_one_strike "git push --force origin main")
DECISION=$(echo "$RESULT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo "error")
assert_eq "git push --force denied" "deny" "$DECISION"

echo ""
echo "Case 1d: safe command always allowed"
RESULT=$(run_one_strike "ls /tmp")
DECISION=$(echo "$RESULT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo "error")
assert_eq "ls always allowed" "allow" "$DECISION"

echo ""
echo "Case 1e: rm without flags allowed (no hyphenated names — regex matches -file as -f)"
RESULT=$(run_one_strike "rm /tmp/test.txt")
DECISION=$(echo "$RESULT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo "error")
assert_eq "rm without flags allowed" "allow" "$DECISION"

# Reset warned files for heredoc test
rm -f "$WARNED_DIR"/claude-hook-warned-*

echo ""
echo "Case 1f: heredoc body stripped — force-push text in heredoc doesn't trigger"
RESULT=$(run_one_strike "engine log file.md <<'EOF'\n## Note\nforce-pushing overwrites history\nEOF")
DECISION=$(echo "$RESULT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo "error")
assert_eq "heredoc body stripped" "allow" "$DECISION"

# ============================================================
# TEST GROUP 2: Engine command matching (lib.sh)
# ============================================================
echo ""
echo "=== Test 2: Engine command matching (is_engine_*_cmd) ==="

echo ""
echo "Case 2a: is_engine_log_cmd matches basic"
if is_engine_log_cmd "engine log sessions/foo/LOG.md"; then
  PASS=$((PASS + 1)); echo "  PASS: basic engine log"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: basic engine log"
  ERRORS="${ERRORS}\n  FAIL: basic engine log"
fi

echo ""
echo "Case 2b: is_engine_log_cmd matches with --overwrite"
if is_engine_log_cmd "engine log --overwrite sessions/foo/LOG.md"; then
  PASS=$((PASS + 1)); echo "  PASS: engine log --overwrite"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: engine log --overwrite"
  ERRORS="${ERRORS}\n  FAIL: engine log --overwrite"
fi

echo ""
echo "Case 2c: is_engine_log_cmd rejects engine session"
if is_engine_log_cmd "engine session activate foo"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: should reject engine session"
  ERRORS="${ERRORS}\n  FAIL: should reject engine session"
else
  PASS=$((PASS + 1)); echo "  PASS: rejects engine session"
fi

echo ""
echo "Case 2d: is_engine_log_cmd matches with heredoc"
if is_engine_log_cmd "engine log sessions/foo/LOG.md <<'EOF'
## Entry
content
EOF"; then
  PASS=$((PASS + 1)); echo "  PASS: engine log with heredoc"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: engine log with heredoc"
  ERRORS="${ERRORS}\n  FAIL: engine log with heredoc"
fi

echo ""
echo "Case 2e: is_engine_session_cmd matches"
if is_engine_session_cmd "engine session activate sessions/foo fix"; then
  PASS=$((PASS + 1)); echo "  PASS: engine session activate"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: engine session activate"
  ERRORS="${ERRORS}\n  FAIL: engine session activate"
fi

# ============================================================
# TEST GROUP 3: Discovery hook removed — verify no-op
# ============================================================
echo ""
echo "=== Test 3: Discovery hook — removed (discovery moved to PreToolUse) ==="

echo ""
echo "Case 3a: post-tool-use-discovery.sh no longer exists in engine/hooks/"
if [ ! -f "$HOME/.claude/engine/hooks/post-tool-use-discovery.sh" ]; then
  assert_eq "discovery hook removed from engine/hooks" "removed" "removed"
else
  assert_eq "discovery hook removed from engine/hooks" "removed" "still exists"
fi

# ============================================================
# TEST GROUP 4: preload rule configuration (formerly directive-autoload)
# ============================================================
echo ""
echo "=== Test 4: preload guard rule ==="

GUARDS="$HOME/.claude/engine/guards.json"

echo ""
echo "Case 4a: preload urgency is allow (not block)"
URGENCY=$(jq -r '.[] | select(.id == "preload") | .urgency' "$GUARDS")
assert_eq "preload urgency is allow" "allow" "$URGENCY"

echo ""
echo "Case 4b: preload mode is preload"
MODE=$(jq -r '.[] | select(.id == "preload") | .mode' "$GUARDS")
assert_eq "preload mode is preload" "preload" "$MODE"

echo ""
echo "Case 4c: preload has no whitelist (not needed for allow)"
HAS_WHITELIST=$(jq '.[] | select(.id == "preload") | has("whitelist")' "$GUARDS")
assert_eq "preload has no whitelist" "false" "$HAS_WHITELIST"

echo ""
echo "Case 4d: preload trigger is discovery/pendingPreloads"
TRIGGER_FIELD=$(jq -r '.[] | select(.id == "preload") | .trigger.condition.field' "$GUARDS")
assert_eq "trigger field is pendingPreloads" "pendingPreloads" "$TRIGGER_FIELD"

# ============================================================
# TEST GROUP 5: evaluate_rules — preload fires correctly
# ============================================================
echo ""
echo "=== Test 5: evaluate_rules with preload ==="

echo ""
echo "Case 5a: preload fires when pendingPreloads non-empty"
cat > "$SESSION_DIR/.state.json" <<'JSON'
{
  "lifecycle": "active",
  "contextUsage": 0.3,
  "pendingPreloads": ["/some/file.md"],
  "preloadedFiles": [],
  "injectedRules": {}
}
JSON

RESULT=$(bash -c "
  source '$HOME/.claude/scripts/lib.sh'
  evaluate_rules '$SESSION_DIR/.state.json' '$GUARDS'
" 2>/dev/null)
HAS_PRELOAD=$(echo "$RESULT" | jq '[.[] | select(.ruleId == "preload")] | length' 2>/dev/null || echo "0")
assert_eq "preload fires" "1" "$HAS_PRELOAD"

echo ""
echo "Case 5b: preload does NOT fire when pendingPreloads empty"
cat > "$SESSION_DIR/.state.json" <<'JSON'
{
  "lifecycle": "active",
  "contextUsage": 0.3,
  "pendingPreloads": [],
  "preloadedFiles": [],
  "injectedRules": {}
}
JSON

RESULT=$(bash -c "
  source '$HOME/.claude/scripts/lib.sh'
  evaluate_rules '$SESSION_DIR/.state.json' '$GUARDS'
" 2>/dev/null)
HAS_PRELOAD=$(echo "$RESULT" | jq '[.[] | select(.ruleId == "preload")] | length' 2>/dev/null || echo "0")
assert_eq "preload does not fire" "0" "$HAS_PRELOAD"

echo ""
echo "Case 5c: preload urgency is allow in evaluated output"
cat > "$SESSION_DIR/.state.json" <<'JSON'
{
  "lifecycle": "active",
  "contextUsage": 0.3,
  "pendingPreloads": ["/some/file.md"],
  "preloadedFiles": [],
  "injectedRules": {}
}
JSON

RESULT=$(bash -c "
  source '$HOME/.claude/scripts/lib.sh'
  evaluate_rules '$SESSION_DIR/.state.json' '$GUARDS'
" 2>/dev/null)
EVAL_URGENCY=$(echo "$RESULT" | jq -r '.[] | select(.ruleId == "preload") | .urgency' 2>/dev/null || echo "error")
assert_eq "evaluated urgency is allow" "allow" "$EVAL_URGENCY"

# ============================================================
# TEST GROUP 6: Whitelist matching (lib.sh)
# ============================================================
echo ""
echo "=== Test 6: Whitelist matching ==="

echo ""
echo "Case 6a: Bare tool name matches"
if match_whitelist_entry "AskUserQuestion" "AskUserQuestion" ""; then
  PASS=$((PASS + 1)); echo "  PASS: bare tool match"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: bare tool match"
  ERRORS="${ERRORS}\n  FAIL: bare tool match"
fi

echo ""
echo "Case 6b: Glob pattern matches"
if match_whitelist_entry "Read($HOME/.claude/*)" "Read" "$HOME/.claude/foo.md"; then
  PASS=$((PASS + 1)); echo "  PASS: glob pattern match"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: glob pattern match"
  ERRORS="${ERRORS}\n  FAIL: glob pattern match"
fi

echo ""
echo "Case 6c: Glob pattern rejects non-match"
if match_whitelist_entry "Read($HOME/.claude/*)" "Read" "/other/path.md"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: should reject non-match"
  ERRORS="${ERRORS}\n  FAIL: should reject non-match"
else
  PASS=$((PASS + 1)); echo "  PASS: glob rejects non-match"
fi

echo ""
echo "Case 6d: Wrong tool name rejects"
if match_whitelist_entry "Read($HOME/.claude/*)" "Edit" "$HOME/.claude/foo.md"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: should reject wrong tool"
  ERRORS="${ERRORS}\n  FAIL: should reject wrong tool"
else
  PASS=$((PASS + 1)); echo "  PASS: wrong tool rejected"
fi

echo ""
echo "Case 6e: Engine command glob matches"
if match_whitelist_entry "Bash(engine session *)" "Bash" "engine session activate foo"; then
  PASS=$((PASS + 1)); echo "  PASS: engine session glob"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: engine session glob"
  ERRORS="${ERRORS}\n  FAIL: engine session glob"
fi

echo ""
echo "Case 6f: match_whitelist with JSON array"
if match_whitelist '["AskUserQuestion","Bash(engine log *)"]' "Bash" '{"command":"engine log file.md"}'; then
  PASS=$((PASS + 1)); echo "  PASS: JSON whitelist match"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: JSON whitelist match"
  ERRORS="${ERRORS}\n  FAIL: JSON whitelist match"
fi

echo ""
echo "Case 6g: Empty whitelist rejects all"
if match_whitelist '[]' "Bash" '{"command":"engine log file.md"}'; then
  FAIL=$((FAIL + 1)); echo "  FAIL: empty whitelist should reject"
  ERRORS="${ERRORS}\n  FAIL: empty whitelist should reject"
else
  PASS=$((PASS + 1)); echo "  PASS: empty whitelist rejects"
fi

# --- Summary ---
echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
if [ "$FAIL" -gt 0 ]; then
  printf "$ERRORS\n"
  exit 1
fi
exit 0
