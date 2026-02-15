### ¶CMD_RUN_TESTS
**Definition**: Agent instructions for deciding what tests to run and how to run them. This is a decision tree — the agent reads it, determines context, and executes the appropriate test commands.
**Trigger**: Called by skill protocols during build phases (after code changes) or verification steps (before synthesis). Skills reference this in their `commands[]` arrays.

---

## Algorithm

### Step 1: Determine Test Context

Identify which test world(s) are relevant based on files touched in this session:

- **Engine files** (`~/.claude/engine/`, `~/.claude/scripts/`, `~/.claude/hooks/`): Run **engine tests** (Step 2).
- **App files** (`packages/*`, `apps/*`, `src/*`): Run **app tests** (Step 3).
- **Both**: Run both suites sequentially (Step 2, then Step 3).
- **Neither**: Skip tests. Log "No testable changes detected."

### Step 2: Engine Tests (Bash)

The engine uses a custom bash test framework. Tests live in `~/.claude/engine/scripts/tests/`.

**Full suite**:
```bash
engine test
```
Runs `run-all.sh` — discovers and executes all `test-*.sh` files in the tests directory. Reports pass/fail counts.

**Filtered by file name**:
```bash
engine test test-session-sh.sh
```
Runs a single test suite by filename.

**Filtered by pattern** (`--grep`):
```bash
engine test --grep session
```
Runs all test suites whose filename matches the pattern. Useful after changing a specific script (e.g., changed `session.sh` → `engine test --grep session`).

**E2E tests** (expensive — real API calls):
```bash
engine test-e2e
```
Runs all tests in `tests/e2e/` recursively. These include behavioral/protocol tests and integration tests that make real API calls (~$0.15 each). Only run when:
- Protocol behavior changed
- E2E test files were modified
- Full verification requested

**Verbose output** (shows individual PASS/FAIL lines):
```bash
engine test -v
engine test -v test-session-sh.sh
```

### Step 3: App Tests (Jest)

The app uses Jest via Yarn workspaces and Turborepo.

**All packages**:
```bash
yarn test
```
Runs `turbo run test` across all workspaces.

**Single package**:
```bash
yarn workspace @finch/estimate test
yarn workspace @finch/api test
yarn workspace @finch/shared test
```

**Single test file**:
```bash
yarn workspace @finch/estimate test -- --testPathPattern="path/to/test"
```

**Watch mode** (during active development):
```bash
yarn workspace @finch/estimate test -- --watch
```

**E2E tests** (if configured):
```bash
yarn workspace @finch/api test:e2e
```

### Step 4: Interpret Results

- **All pass**: Log "Tests pass" and continue.
- **Failures**: Read the failure output. Determine if failures are:
  - **Related to changes**: Fix before proceeding.
  - **Pre-existing**: Note in the log as pre-existing failures. Do not block progress.
- **Timeouts**: Engine tests should complete in seconds. App tests may take longer for large packages. If a test hangs, check for missing mocks or async issues.

### Step 5: Report

Log test results to the session log via `§CMD_APPEND_LOG`:
```
## Test Results
*   **Engine**: [N pass / M fail] (or "skipped — no engine changes")
*   **App**: [N pass / M fail] (or "skipped — no app changes")
*   **Failures**: [list any failures and whether pre-existing or new]
```

---

## Quick Reference

**When to run which**:

- Changed `session.sh` → `engine test --grep session`
- Changed `tag.sh` → `engine test --grep tag`
- Changed any engine script → `engine test` (full suite)
- Changed protocol behavior → `engine test-e2e`
- Changed `packages/estimate` code → `yarn workspace @finch/estimate test`
- Changed `apps/api` code → `yarn workspace @finch/api test`
- Changed shared schemas → `yarn workspace @finch/shared test` then downstream packages
- Unsure what changed → `engine test && yarn test` (run everything)

---

## Constraints

- **Do NOT skip tests silently**: If tests are relevant, run them. Log the decision either way.
- **Pre-existing failures**: Check the session log or prior sessions for known failures. Do not chase pre-existing issues unless they are the focus of the current task.
- **E2E cost awareness**: Engine e2e tests make real API calls. Only run when behavior changes warrant it.
- **Sandbox isolation**: Engine tests use sandbox isolation (`§INV_TEST_SANDBOX_ISOLATION`). They do not touch the real project or Google Drive.
- **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — report results, no micro-narration of test execution steps.

---

## PROOF FOR §CMD_RUN_TESTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "testsRun": {
      "type": "string",
      "description": "Which test suites were executed (e.g., 'engine: full suite, app: @finch/estimate')"
    },
    "testResults": {
      "type": "string",
      "description": "Pass/fail summary (e.g., '54 pass, 0 fail')"
    }
  },
  "required": ["testsRun", "testResults"],
  "additionalProperties": false
}
```
