#!/bin/bash
# test-report-intent-rename.sh — Verifies §CMD_REPORT_INTENT_TO_USER → §CMD_REPORT_INTENT rename
#
# Static grep test (no Claude invocation). Checks that:
#   - Old name is absent from all active engine files
#   - New name is defined in COMMANDS.md with correct structure
#   - New name is referenced across SKILL.md files
#
# Origin session: sessions/2026_02_14_IMPROVE_PROTOCOL_TEST (improve-protocol)
# Fix: Fix 3 from sessions/2026_02_13_PROTOCOL_IMPROVEMENT_RUN — 23 files, 77 occurrences
#
# Run: bash ~/.claude/engine/scripts/tests/protocol/test-report-intent-rename.sh

set -uo pipefail
source "$(dirname "$0")/../test-helpers.sh"

REAL_ENGINE_DIR="$HOME/.claude/engine"
REAL_SKILLS_DIR="$HOME/.claude/skills"
REAL_DIRECTIVES_DIR="$HOME/.claude/.directives"

echo "=== §CMD_REPORT_INTENT Rename Verification ==="
echo ""

# --- Old name absent from engine directives ---
OLD_HITS=$(grep -r "CMD_REPORT_INTENT_TO_USER" "$REAL_DIRECTIVES_DIR" --include="*.md" 2>/dev/null | grep -v "\.jsonl" || true)
if [ -z "$OLD_HITS" ]; then
  pass "No old name in ~/.claude/.directives/"
else
  fail "Old name found in directives"
  echo "  $OLD_HITS" | head -3
fi

# --- Old name absent from engine skills ---
OLD_HITS=$(grep -r "CMD_REPORT_INTENT_TO_USER" "$REAL_ENGINE_DIR/skills" --include="*.md" 2>/dev/null || true)
if [ -z "$OLD_HITS" ]; then
  pass "No old name in engine skills/"
else
  fail "Old name found in engine skills"
  echo "  $OLD_HITS" | head -3
fi

# --- Old name absent from shared skills (symlinks) ---
OLD_HITS=$(grep -r "CMD_REPORT_INTENT_TO_USER" "$REAL_SKILLS_DIR" --include="*.md" 2>/dev/null || true)
if [ -z "$OLD_HITS" ]; then
  pass "No old name in ~/.claude/skills/"
else
  fail "Old name found in shared skills"
  echo "  $OLD_HITS" | head -3
fi

# --- Old name absent from command files ---
OLD_HITS=$(grep -r "CMD_REPORT_INTENT_TO_USER" "$REAL_ENGINE_DIR/.directives/commands" --include="*.md" 2>/dev/null || true)
if [ -z "$OLD_HITS" ]; then
  pass "No old name in engine commands/"
else
  fail "Old name found in commands"
  echo "  $OLD_HITS" | head -3
fi

# --- New name defined in COMMANDS.md ---
if grep -q "### §CMD_REPORT_INTENT" "$REAL_DIRECTIVES_DIR/COMMANDS.md" 2>/dev/null; then
  pass "§CMD_REPORT_INTENT defined in COMMANDS.md"
else
  fail "§CMD_REPORT_INTENT NOT found as heading in COMMANDS.md"
fi

# --- New name referenced in SKILL.md files ---
SKILL_REFS=$(grep -rl "CMD_REPORT_INTENT" "$REAL_ENGINE_DIR/skills" --include="SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$SKILL_REFS" -ge 5 ]; then
  pass "§CMD_REPORT_INTENT referenced in $SKILL_REFS SKILL.md files (>= 5)"
else
  fail "Only referenced in $SKILL_REFS SKILL.md files (expected >= 5)"
fi

# --- No SKILL.md uses old name ---
OLD_REFS=$(grep -rl "CMD_REPORT_INTENT_TO_USER" "$REAL_ENGINE_DIR/skills" --include="SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$OLD_REFS" -eq 0 ]; then
  pass "No SKILL.md references old name"
else
  fail "$OLD_REFS SKILL.md files still reference old name"
fi

# --- Definition has correct structure ---
if grep -A2 "### §CMD_REPORT_INTENT" "$REAL_DIRECTIVES_DIR/COMMANDS.md" 2>/dev/null | grep -q "Definition"; then
  pass "§CMD_REPORT_INTENT has **Definition** field"
else
  fail "Missing **Definition** field in COMMANDS.md"
fi

echo ""
exit_with_results
