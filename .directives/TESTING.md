# Testing Standards — Workflow Engine

Unified testing directive for the workflow engine. Covers all test types and how to run them. For bash test framework specifics (sandbox setup, assertions, mock infrastructure), see the detailed guide at `scripts/tests/.directives/TESTING.md`.

## Test Taxonomy

The engine has three categories of tests:

### 1. Unit Tests (Bash)

**Location**: `scripts/tests/test-*.sh`
**Runner**: `engine test` (wraps `run-all.sh`)
**Framework**: Custom bash framework via `test-helpers.sh`
**Speed**: Fast — seconds for the full suite (~54 files)

Tests individual engine scripts (session.sh, tag.sh, log.sh, etc.) in sandbox isolation. Each test file creates a temp directory, overrides HOME and PROJECT_ROOT, and cleans up on exit.

**When to run**: After any change to `scripts/`, `hooks/`, or `engine.sh`.

### 2. E2E Tests (Bash)

**Location**: `scripts/tests/e2e/` (recursive)
**Runner**: `engine test-e2e`
**Cost**: Expensive — real API calls (~$0.15 each)

Integration tests that exercise real external services (Gemini API, Claude API). Includes behavioral/protocol tests that verify end-to-end agent behavior.

**When to run**: After protocol behavior changes, e2e test modifications, or when full verification is needed. Not part of the regular test loop.

### 3. App Tests (Jest)

**Location**: `packages/*/src/**/*.test.ts`, `apps/*/src/**/*.test.ts`
**Runner**: `yarn test` (via Turborepo) or per-workspace
**Framework**: Jest with TypeScript
**Speed**: Varies by package — seconds to minutes

Standard Node.js/TypeScript tests for the application code. Each package has its own jest config and test conventions (see per-package `.directives/TESTING.md` files).

**When to run**: After any change to `packages/` or `apps/` code.

## Running Tests

### Engine Tests

```bash
# Full suite
engine test

# Verbose (shows individual PASS/FAIL)
engine test -v

# Single suite by filename
engine test test-session-sh.sh

# Filter by pattern
engine test --grep session

# E2E tests only (expensive)
engine test-e2e
```

### App Tests

```bash
# All packages
yarn test

# Single package
yarn workspace @finch/estimate test
yarn workspace @finch/api test

# Single file
yarn workspace @finch/estimate test -- --testPathPattern="matching/pipeline"

# Watch mode
yarn workspace @finch/estimate test -- --watch
```

## Writing Engine Tests

For the full guide on writing bash tests (sandbox isolation, mock infrastructure, assertions, naming conventions), see:

**`scripts/tests/.directives/TESTING.md`**

Key rules (summary):
- **Sandbox isolation is non-negotiable** — `setup_fake_home`, override HOME/PROJECT_ROOT
- **Source `test-helpers.sh`** — use its mock functions and assertions
- **No `set -e` globally** — handle exit codes explicitly
- **Test function naming**: `test_SCRIPT_FEATURE_CASE()`
- **Update symlinks on rename** — grep test files after any script rename

## Test-to-Script Mapping

When you change an engine script, run the corresponding test:

- `session.sh` → `engine test --grep session`
- `tag.sh` → `engine test --grep tag`
- `log.sh` → `engine test --grep log`
- `setup-lib.sh` → `engine test --grep setup-lib`
- `setup-migrations.sh` → `engine test --grep setup-migrations`
- `find-sessions.sh` → `engine test --grep find-sessions`
- Hooks → `engine test --grep` + hook name keyword (heartbeat, overflow, session-gate, etc.)

## Pre-Existing Failures

Check the session log or prior sessions for known test failures before investigating. The analysis session (`sessions/2026_02_14_ANALYZE_TEST_WIRING`) documented 37/38 engine tests passing with 1 pre-existing failure in `test-debrief.sh`.

## Cross-Package Dependencies

When changing shared schemas (`@finch/shared`), run downstream package tests:
1. `yarn workspace @finch/shared test` (if tests exist)
2. `yarn workspace @finch/estimate test` (primary consumer)
3. `yarn workspace @finch/api test` (API consumer)
