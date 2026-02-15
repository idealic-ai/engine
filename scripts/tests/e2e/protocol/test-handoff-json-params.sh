#!/bin/bash
# test-handoff-json-params.sh — Verifies handoff parameters use JSON format, not prose
#
# Static grep test (no Claude invocation). Checks that:
#   - CMD_HANDOFF_TO_AGENT.md uses JSON code blocks for parameters
#   - CMD_PARALLEL_HANDOFF.md uses JSON code blocks for parameters
#   - All SKILL.md handoff sections use JSON format, not prose-style backtick bullets
#
# Origin session: sessions/2026_02_14_IMPROVE_PROTOCOL_TEST (improve-protocol)
# Fix: Fix 4 from sessions/2026_02_13_PROTOCOL_IMPROVEMENT_RUN — prose to JSON conversion (9 files)
#
# Run: bash ~/.claude/engine/scripts/tests/protocol/test-handoff-json-params.sh

set -uo pipefail
source "$(dirname "$0")/../test-helpers.sh"

REAL_ENGINE_DIR="$HOME/.claude/engine"
REAL_DIRECTIVES_DIR="$HOME/.claude/.directives"

echo "=== Handoff JSON Parameters Verification ==="
echo ""

# --- CMD_HANDOFF_TO_AGENT.md has JSON block ---
echo "--- CMD files use JSON parameters ---"
HANDOFF_CMD="$REAL_DIRECTIVES_DIR/commands/CMD_HANDOFF_TO_AGENT.md"
if [ -f "$HANDOFF_CMD" ]; then
  if grep -q '```json' "$HANDOFF_CMD" 2>/dev/null; then
    pass "CMD_HANDOFF_TO_AGENT.md has JSON code block"
  else
    fail "CMD_HANDOFF_TO_AGENT.md missing JSON code block"
  fi
  # Should NOT have prose-style backtick-bullet params
  if grep -qE '^\*\s+`[a-zA-Z]+`:\s+`' "$HANDOFF_CMD" 2>/dev/null; then
    fail "CMD_HANDOFF_TO_AGENT.md still has prose-style backtick-bullet params"
  else
    pass "CMD_HANDOFF_TO_AGENT.md has no prose-style params"
  fi
else
  fail "CMD_HANDOFF_TO_AGENT.md not found at $HANDOFF_CMD"
fi

# --- CMD_PARALLEL_HANDOFF.md has JSON block ---
PARALLEL_CMD="$REAL_DIRECTIVES_DIR/commands/CMD_PARALLEL_HANDOFF.md"
if [ -f "$PARALLEL_CMD" ]; then
  if grep -q '```json' "$PARALLEL_CMD" 2>/dev/null; then
    pass "CMD_PARALLEL_HANDOFF.md has JSON code block"
  else
    fail "CMD_PARALLEL_HANDOFF.md missing JSON code block"
  fi
else
  fail "CMD_PARALLEL_HANDOFF.md not found at $PARALLEL_CMD"
fi

# --- SKILL.md handoff sections use JSON ---
echo ""
echo "--- SKILL.md handoff sections use JSON ---"

# These 7 skills were converted in Fix 4
HANDOFF_SKILLS=(analyze implement fix brainstorm direct document test)

for skill in "${HANDOFF_SKILLS[@]}"; do
  SKILL_FILE="$REAL_ENGINE_DIR/skills/$skill/SKILL.md"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$skill/SKILL.md not found"
    continue
  fi

  # Check for JSON code block in handoff section (anywhere in file)
  # The handoff section contains agentName, agentPrompt, etc. as JSON
  if grep -A5 -i "handoff\|agent.*handoff\|CMD_HANDOFF" "$SKILL_FILE" 2>/dev/null | grep -q '```json\|"agentName"\|"agentPrompt"' 2>/dev/null; then
    pass "$skill/SKILL.md handoff uses JSON format"
  else
    # Check if it even has a handoff section
    if grep -qi "handoff" "$SKILL_FILE" 2>/dev/null; then
      fail "$skill/SKILL.md handoff section exists but may not use JSON"
    else
      pass "$skill/SKILL.md has no handoff section (OK — not all skills use handoff)"
    fi
  fi
done

# --- Negative check: no prose-style params in converted skills ---
echo ""
echo "--- No prose-style backtick-bullet params in handoff sections ---"

PROSE_FOUND=0
for skill in "${HANDOFF_SKILLS[@]}"; do
  SKILL_FILE="$REAL_ENGINE_DIR/skills/$skill/SKILL.md"
  [ -f "$SKILL_FILE" ] || continue

  # Look for old prose pattern: `*   `paramName`: `"value"`
  if grep -E '^\*\s+`(agentName|agentPrompt|agentModel|taskSummary)`:\s+`' "$SKILL_FILE" 2>/dev/null; then
    fail "$skill/SKILL.md still has prose-style handoff params"
    PROSE_FOUND=1
  fi
done

if [ "$PROSE_FOUND" -eq 0 ]; then
  pass "No skills have prose-style handoff params (all converted to JSON)"
fi

echo ""
exit_with_results
