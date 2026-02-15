### ¶CMD_DESIGN_E2E_TEST
**Definition**: Designs and runs an e2e reproduction test for changes made during the session. Creates a sandbox environment, reproduces the "before" (broken) behavior, applies the fix, and demonstrates "after" (improved) behavior. Protocol-level TDD: red → green.
**Trigger**: Called by skill protocols during a test/verification phase, after changes have been applied. Currently used by `/improve-protocol` Phase 4.

**Preconditions**:
*   Changes have been applied to protocol/engine files during a prior phase.
*   The session log contains a record of what was changed (findings, edits, file paths).

---

## Algorithm

### Step 0: Testability Assessment

1.  **Scan Applied Changes**: Review the session log for applied findings/edits. Classify each into one of three tiers:
    *   **Mechanically testable**: Changes to engine scripts, hooks, phase enforcement, session lifecycle, tag operations, proof validation — anything that produces observable output from `engine` commands. **Also includes**: protocol command changes (CMD_*.md) that describe engine-enforced behavior (phase transitions, session state rules, proof requirements) — test by creating fake `.state.json` with the scenario state and asserting on `engine session phase` acceptance/rejection. See `test-phase-enforcement.sh` for the canonical pattern. Test via bash scripts in a sandbox.
    *   **Behaviorally testable**: Changes to protocol commands, skill phases, constraints, or behavioral guidelines — changes that affect LLM agent behavior. Test via `claude -p` with haiku model (`--max-turns 1`) in a sandbox. The test feeds the modified protocol file to a fresh agent and checks whether the agent's behavior matches the fix intent.
    *   **Untestable**: Pure template text updates, formatting changes, documentation improvements with no behavioral impact — changes where no test (mechanical or behavioral) would meaningfully verify the fix. **Burden of proof**: For each finding classified as untestable, explain what you considered testing and why no test would meaningfully verify the fix. "Prose changes only" is NOT a valid justification if the prose describes engine-enforced behavior. The default assumption is testable — untestable requires explicit justification.
2.  **Present Assessment**: Output the classification table in chat, then execute `AskUserQuestion` (multiSelect: false):
    > "Testability assessment complete. [N] mechanically testable, [M] behaviorally testable, [K] untestable. Proceed?"
    > - **"Run all testable"** — Design and run tests for mechanical + behavioral findings.
    > - **"Run mechanical only"** — Skip behavioral (`claude -p`) tests. Run only engine command tests.
    > - **"Skip to synthesis"** — No testing. User confirms the assessment and proceeds.
3.  **If user selects "Skip"**: Log "Phase skipped — user confirmed assessment" and return.
4.  **If user selects a test option**: Continue to Step 1 with the selected scope.

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

#### 2A. Mechanical Tests (engine commands, hooks, scripts)

For each mechanically testable finding, design a bash reproduction case using `test-helpers.sh`. For protocol command changes (CMD_*.md), follow the pattern in `~/.claude/engine/scripts/tests/test-phase-enforcement.sh` — create fake `.state.json` with scenario state, run `engine session phase` or other engine commands, and assert on acceptance/rejection/output:

```bash
#!/bin/bash
# test-[finding-name].sh — Reproduction test for [finding summary]
set -uo pipefail
source ~/.claude/engine/scripts/tests/test-helpers.sh

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  mock_fleet_sh "$FAKE_HOME"
  disable_fleet_tmux
  export PROJECT_ROOT="$TMP_DIR/project"
  mkdir -p "$PROJECT_ROOT"
}
teardown() { teardown_fake_home; rm -rf "$TMP_DIR"; }

test_finding() {
  cat > "$PROJECT_ROOT/.state.json" << 'STATE'
  { ... state that triggers the behavior ... }
STATE
  local output
  output=$(engine [command] [args] 2>&1) || true
  assert_contains "expected" "$output" "description"
}

run_test test_finding
exit_with_results
```

#### 2B. Behavioral Tests (protocol commands, constraints, guidelines)

For each behaviorally testable finding, design a `claude -p` test using the e2e infrastructure from `~/.claude/engine/scripts/tests/test-e2e-claude-hooks.sh`.

**Key infrastructure** (source both `test-helpers.sh` and the e2e setup functions from `test-e2e-claude-hooks.sh`):
*   `setup_claude_e2e_env SESSION_NAME` — Creates sandboxed Claude environment with real hooks, scripts, directives, custom `settings.json`, mock fleet/search tools.
*   `invoke_claude PROMPT [JSON_SCHEMA] [TOOLS] [MAX_TURNS]` — Calls `claude -p --model haiku` with sandboxed settings. Returns JSON output. Tools: `"none"` disables all tools (context-only response), `"Bash,Read"` enables specific tools, `""` enables all.
*   `extract_result JSON_OUTPUT` — Extracts result text from Claude's structured JSON output.

**Pattern**: Feed a scenario prompt to a sandboxed haiku agent and assert on structured JSON response:

```bash
#!/bin/bash
# test-behavioral-[finding-name].sh
set -uo pipefail
source ~/.claude/engine/scripts/tests/test-helpers.sh

# Source e2e functions (setup_claude_e2e_env, invoke_claude, extract_result)
# These are defined in the e2e test file — source only the function definitions
source ~/.claude/engine/scripts/tests/test-e2e-claude-hooks.sh

setup_claude_e2e_env "behavioral_test"

# Set up session state for the scenario
cat > "$TEST_SESSION/.state.json" << 'STATE'
{ "pid": 1, "skill": "implement", "lifecycle": "active",
  "currentPhase": "5.2: Debrief" }
STATE

# JSON schema for structured assertion
SCHEMA='{ "type": "object", "properties": {
  "offersCloseOption": { "type": "boolean" }
}, "required": ["offersCloseOption"] }'

# Prompt that triggers the behavior under test
OUTPUT=$(invoke_claude \
  "You are resuming a session at phase 5.2: Debrief. A debrief exists. What options do you present?" \
  "$SCHEMA" "none" 1)

RESULT=$(extract_result "$OUTPUT")
HAS_CLOSE=$(echo "$RESULT" | jq '.offersCloseOption')
[ "$HAS_CLOSE" = "false" ] && echo "PASS" || echo "FAIL: Agent still offers Close"
```

**Behavioral test constraints**:
*   Use `"none"` for tools — agent responds from context only.
*   Use `--max-turns 1` (default) — single prompt-response cycle.
*   Use JSON schema for structured output — easier to assert on than free text.
*   Budget cap `$0.15` is set by `invoke_claude`.
*   Results are non-deterministic — run 2-3 times if the first result is ambiguous.

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

Output a summary in chat. File paths per `¶INV_TERMINAL_FILE_LINKS`:

```markdown
## Test Results

| # | Finding | Test | Before | After | Result |
|---|---------|------|--------|-------|--------|
| 1 | [summary] | cursor://file/ABSOLUTE_PATH | [broken behavior reproduced] | [fix verified] | PASS |
| 2 | [summary] | — | — | — | SKIPPED (untestable) |
```

**If any FAIL**: Offer to loop back to Apply phase to address the failure:
> "Test(s) failed. Return to Phase 3: Apply to fix, or continue to Synthesis?"

### Step 5: Test Promotion

Offer to promote session test artifacts to the engine test suite for permanent regression coverage.

Execute `§CMD_PROMOTE_TESTS`. This scans `test-*.sh` files in the session directory, classifies them (mechanical vs behavioral), and presents a promotion walkthrough via `AskUserQuestion`. Promoted tests are copied to `~/.claude/engine/scripts/tests/`.

**Skip condition**: If Step 0 assessment resulted in "Skip to synthesis" (no tests designed), skip this step.

---

## Constraints

*   **Sandbox isolation**: Tests MUST run in a sandbox. Never modify real session state or engine files during testing.
*   **Non-destructive**: The test phase reads and verifies — it does not apply fixes. If tests reveal issues, the agent reports them and optionally loops back to Apply.
*   **Autonomous**: No user approval gates during test design or execution. Agent designs, runs, and reports. User reviews in synthesis.
*   **User-confirmed skip**: The testability assessment is ALWAYS presented to the user. The agent does NOT auto-skip — the user confirms the classification and chooses to skip or run tests.
*   **Test artifacts in session dir**: Test scripts go in `[sessionDir]/`. Not promoted to engine test suite unless explicitly requested.
*   **Engine test pattern**: Follow the conventions from `~/.claude/engine/scripts/tests/` — `set -uo pipefail`, sandbox HOME, symlinked engine dirs, exit code assertions.
*   **Budget-conscious**: Behavioral tests (`claude -p`) MUST use haiku model with `--max-turns 1` to minimize cost. Each behavioral test is a single prompt-response cycle — design the prompt to elicit the specific behavior being tested.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in test results and sandbox references MUST be clickable URLs.

---

## PROOF FOR §CMD_DESIGN_E2E_TEST

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "testsDesigned": {
      "type": "string",
      "description": "Count and scope of tests designed (e.g., '3 mechanical, 1 behavioral')"
    },
    "testsPassed": {
      "type": "string",
      "description": "Count and summary of passing tests"
    },
    "testsFailed": {
      "type": "string",
      "description": "Count and summary of failing tests (e.g., '0 failed' or '1 failed: proof validation')"
    },
    "testsSkipped": {
      "type": "string",
      "description": "Count and reason for skipped findings"
    }
  },
  "required": ["testsDesigned", "testsPassed", "testsFailed", "testsSkipped"],
  "additionalProperties": false
}
```
