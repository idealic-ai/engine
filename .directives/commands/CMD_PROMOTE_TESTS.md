### ¶CMD_PROMOTE_TESTS
**Definition**: Walks through test artifacts created during a session and offers to promote selected tests to the engine test suite. Follows the `§CMD_DISPATCH_APPROVAL` scan-present-execute pattern.
**Trigger**: Called by `§CMD_DESIGN_E2E_TEST` Step 5 (after test report), or standalone when a session contains test scripts worth preserving.

**Preconditions**:
*   Session directory contains test artifacts (`test-*.sh` files) from `§CMD_DESIGN_E2E_TEST` or manual creation.
*   Tests have already been executed and results reported (Step 4 of `§CMD_DESIGN_E2E_TEST`).

---

## Algorithm

### Step 1: Scan Test Artifacts

Find test scripts in the session directory:

```bash
TEST_FILES=$(find "[sessionDir]/" -maxdepth 1 -name "test-*.sh" -type f | sort)
```

**If no test files found**: Skip silently. No user prompt. Return.

### Step 2: Classify Tests

For each test file, determine its type by scanning content:

**Contains `invoke_claude` or `claude -p`** — Behavioral test
**Contains `engine ` commands, `assert_contains`, `setup_fake_home`** — Mechanical test
**Both indicators present** — Mechanical (primary classification)
**Neither indicator** — Mechanical (default)

Build a summary table:

```
| # | File | Type | Description |
|---|------|------|-------------|
| 1 | test-phase-proof.sh | Mechanical | Tests proof validation on phase transition |
| 2 | test-behavioral-resume.sh | Behavioral | Tests agent resume behavior after overflow |
```

### Step 3: Present Promotion Menu

Execute `AskUserQuestion` (multiSelect: false):

> "Found [N] test artifact(s) in session. Promote to engine test suite?"
> - **"Promote all [N] tests"** — Copy all test files to the engine test directory
> - **"Select individually"** — Walk through each test to decide
> - **"Keep in session"** — No promotion. Tests stay in the session directory only.

### Step 4: Execute Promotion

**"Promote all"**:
For each test file:
```bash
cp "[sessionDir]/[test-file]" ~/.claude/engine/scripts/tests/[test-file]
```

**"Select individually"**:
Batch test files into groups of 4 (matching `AskUserQuestion`'s max questions). For each batch, execute `AskUserQuestion` (one question per file, multiSelect: false per question):

> **Question per file**: "[test-file] ([type]) — Promote?"
> - **"Promote"** — Copy to engine test suite
> - **"Skip"** — Keep in session only

Execute promotion for each "Promote" selection.

**"Keep in session"**: No action. Return.

### Step 5: Report

Output promotion summary in chat with clickable file links:

```markdown
## Test Promotion Summary

| # | File | Action | Destination |
|---|------|--------|-------------|
| 1 | test-phase-proof.sh | Promoted | cursor://file/ABSOLUTE/PATH |
| 2 | test-behavioral-resume.sh | Skipped | — |

Promoted: [N]. Skipped: [M].
```

---

## Constraints

*   **No tag resolution**: This command promotes test files only. Tag lifecycle management (`#needs-*` → `#done-*`) is the caller's responsibility.
*   **Scan current session only**: Does not search other sessions or global directories.
*   **Idempotent promotion**: If a file already exists at the destination, overwrite it (the session version is newer).
*   **Skip if empty**: If no `test-*.sh` files exist, return silently without prompting.
*   **File permissions**: Preserve executable bit on promoted files (`cp -p`).
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions MUST use `AskUserQuestion`.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in the promotion summary and destination references MUST be clickable URLs.

---

## PROOF FOR §CMD_PROMOTE_TESTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "testsFound": {
      "type": "string",
      "description": "Count and types of tests found (e.g., '3 tests: 2 mechanical, 1 behavioral')"
    },
    "testsPromoted": {
      "type": "string",
      "description": "Count and names of promoted tests (e.g., '2 promoted: test-phase-proof, test-resume')"
    },
    "testsSkipped": {
      "type": "string",
      "description": "Count of tests kept in session only"
    }
  },
  "required": ["testsFound", "testsPromoted", "testsSkipped"],
  "additionalProperties": false
}
```
