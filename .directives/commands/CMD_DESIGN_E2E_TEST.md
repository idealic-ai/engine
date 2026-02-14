### §CMD_DESIGN_E2E_TEST
**Definition**: Designs and runs an e2e reproduction test for changes made during the session. Creates a sandbox environment, reproduces the "before" (broken) behavior, applies the fix, and demonstrates "after" (improved) behavior. Protocol-level TDD: red → green.
**Trigger**: Called by skill protocols during a test/verification phase, after changes have been applied. Currently used by `/improve-protocol` Phase 4.

**Preconditions**:
*   Changes have been applied to protocol/engine files during a prior phase.
*   The session log contains a record of what was changed (findings, edits, file paths).

---

## Algorithm

### Step 0: Testability Assessment

1.  **Scan Applied Changes**: Review the session log for applied findings/edits. Classify each as:
    *   **Mechanically testable**: Changes to engine scripts, hooks, phase enforcement, session lifecycle, tag operations, proof validation — anything that produces observable output from `engine` commands or `claude -p` invocations.
    *   **Untestable**: Pure wording changes, template text updates, behavioral guidelines, documentation improvements — changes that only affect LLM interpretation, not mechanical behavior.
2.  **If ALL untestable**: Log "Phase skipped — no mechanically testable findings" and return immediately. No user prompt.
3.  **If ANY testable**: Continue to Step 1.

### Step 1: Sandbox Setup

Create an isolated environment that mirrors the engine structure:

```bash
# Create sandbox
SANDBOX_DIR="[sessionDir]/test-sandbox"
mkdir -p "$SANDBOX_DIR"

# Capture real paths
REAL_HOME="$HOME"
REAL_ENGINE_DIR="$HOME/.claude/engine"

# Create sandbox .claude structure
mkdir -p "$SANDBOX_DIR/.claude/scripts"
mkdir -p "$SANDBOX_DIR/.claude/hooks"
mkdir -p "$SANDBOX_DIR/.claude/skills"
mkdir -p "$SANDBOX_DIR/.claude/.directives"

# Symlink engine components into sandbox
ln -s "$REAL_ENGINE_DIR/scripts" "$SANDBOX_DIR/.claude/scripts"
ln -s "$REAL_ENGINE_DIR/hooks" "$SANDBOX_DIR/.claude/hooks"
ln -s "$REAL_ENGINE_DIR/skills" "$SANDBOX_DIR/.claude/skills"
ln -s "$REAL_ENGINE_DIR/.directives" "$SANDBOX_DIR/.claude/.directives"
```

**Sandbox scope**: The sandbox isolates session state (`.state.json`, session directories) while sharing engine scripts/hooks/skills via symlinks. This means tests exercise the *real* engine code (including just-applied changes) but don't pollute real session state.

### Step 2: Design Reproduction Cases

For each mechanically testable finding, design a reproduction case:

1.  **Identify the scenario**: What behavior was broken? What engine command or hook behavior was incorrect?
2.  **Craft the "before" state**: Create the `.state.json`, session files, or skill files that reproduce the old (broken) behavior. This may require:
    *   A `.state.json` with specific phase, lifecycle, or flag values
    *   Session artifact files (logs, debriefs) with specific tag or content patterns
    *   Skill files with the old (pre-fix) protocol text
3.  **Define the assertion**: What output, exit code, or file state demonstrates the fix works?
4.  **Write the test script**: A bash script in `[sessionDir]/` following the engine test pattern:

```bash
#!/bin/bash
# test-[finding-name].sh — Reproduction test for [finding summary]
set -uo pipefail

SANDBOX="[sessionDir]/test-sandbox"
export HOME="$SANDBOX"
export PROJECT_ROOT="$SANDBOX/project"
mkdir -p "$PROJECT_ROOT"

# --- BEFORE (reproduce broken behavior) ---
# Set up state that triggers the old behavior
cat > "$PROJECT_ROOT/.state.json" << 'STATE'
{ ... old state ... }
STATE

# Run the engine command that was broken
BEFORE_OUTPUT=$(engine [command] [args] 2>&1) || true
BEFORE_EXIT=$?

# Assert: the old behavior produced the wrong result
if [[ "$BEFORE_OUTPUT" != *"expected broken output"* ]]; then
  echo "FAIL: Could not reproduce old behavior"
  exit 1
fi
echo "REPRODUCED: Old behavior confirmed"

# --- AFTER (apply fix, verify improvement) ---
# Apply the fix (modify state, swap file, etc.)
# ...

AFTER_OUTPUT=$(engine [command] [args] 2>&1)
AFTER_EXIT=$?

# Assert: the new behavior is correct
if [[ "$AFTER_OUTPUT" != *"expected correct output"* ]]; then
  echo "FAIL: Fix did not produce expected behavior"
  exit 1
fi
echo "VERIFIED: Fix produces improved behavior"
echo "PASS"
```

### Step 3: Execute Tests

1.  **Run each test script**: Execute in the sandbox environment.
2.  **Log results**: For each test, append to the session log:
    ```bash
    engine log [sessionDir]/[LOG_NAME].md <<'EOF'
    ## 🧪 E2E Test Result
    *   **Finding**: [finding summary]
    *   **Test**: [test script path]
    *   **Before**: [reproduced broken behavior — what happened]
    *   **After**: [verified fix — what happens now]
    *   **Result**: PASS / FAIL
    EOF
    ```
3.  **Handle failures**: If a test fails:
    *   Log the failure with full output.
    *   Do NOT fix the issue — that belongs to the Apply phase.
    *   Continue running remaining tests.
    *   Report all failures at the end.

### Step 4: Report

Output a summary in chat:

```markdown
## Test Results

| # | Finding | Test | Before | After | Result |
|---|---------|------|--------|-------|--------|
| 1 | [summary] | [script] | [broken behavior reproduced] | [fix verified] | PASS |
| 2 | [summary] | — | — | — | SKIPPED (untestable) |
```

**If any FAIL**: Offer to loop back to Apply phase to address the failure:
> "Test(s) failed. Return to Phase 3: Apply to fix, or continue to Synthesis?"

---

## Constraints

*   **Sandbox isolation**: Tests MUST run in a sandbox. Never modify real session state or engine files during testing.
*   **Non-destructive**: The test phase reads and verifies — it does not apply fixes. If tests reveal issues, the agent reports them and optionally loops back to Apply.
*   **Autonomous**: No user approval gates during test design or execution. Agent designs, runs, and reports. User reviews in synthesis.
*   **Auto-skip on untestable**: If all findings are untestable, skip silently with a log entry. No user prompt.
*   **Test artifacts in session dir**: Test scripts go in `[sessionDir]/`. Not promoted to engine test suite unless explicitly requested.
*   **Engine test pattern**: Follow the conventions from `~/.claude/engine/scripts/tests/` — `set -uo pipefail`, sandbox HOME, symlinked engine dirs, exit code assertions.
*   **Budget-conscious**: If using `claude -p` for behavioral tests, use haiku model with `--max-turns 1` to minimize cost.

---

## PROOF FOR §CMD_DESIGN_E2E_TEST

```json
{
  "tests_designed": {
    "type": "number",
    "description": "Number of reproduction tests designed",
    "examples": [3, 0]
  },
  "tests_passed": {
    "type": "number",
    "description": "Number of tests that passed (before/after verified)",
    "examples": [2, 0]
  },
  "tests_failed": {
    "type": "number",
    "description": "Number of tests that failed",
    "examples": [0, 1]
  },
  "tests_skipped": {
    "type": "number",
    "description": "Number of findings skipped as untestable",
    "examples": [1, 5]
  }
}
```
