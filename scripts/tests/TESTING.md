# Testing Standards — Engine Scripts

Rules for writing and maintaining tests for `engine/scripts/`. These tests use a custom bash test framework, not Jest.

## 1. Sandbox Isolation Is Non-Negotiable

*   **Rule**: Every test file must create a temp directory in `setup()` and clean it in `teardown()`. Override `HOME`, `PROJECT_ROOT`, and `PATH` to point into the sandbox. See `¶INV_TEST_SANDBOX_ISOLATION`.
*   **Why**: Engine scripts create symlinks at `$PROJECT_ROOT/sessions` and write to `~/.claude/`. Without isolation, tests corrupt the real project and Google Drive.
*   **Pattern**: See `test-session-sh.sh` — it creates `$TEST_DIR/bin/` with mock scripts and prepends it to `PATH`.

## 2. Mock External Dependencies

*   **Rule**: Create mock versions of `fleet.sh`, `jq`, `session-search.sh`, `doc-search.sh`, and any other external dependency in `$TEST_DIR/bin/`. Mock scripts should be minimal (echo expected output, exit 0).
*   **Why**: Tests must run without tmux, without Google Drive, without real session databases. Mocks make tests fast and deterministic.
*   **Pattern**:
    ```bash
    cat > "$TEST_DIR/bin/fleet.sh" <<'MOCK'
    #!/bin/bash
    case "${1:-}" in
      pane-id) echo ""; exit 0 ;;
      *) exit 0 ;;
    esac
    MOCK
    chmod +x "$TEST_DIR/bin/fleet.sh"
    ```

## 3. Test Function Naming Convention

*   **Rule**: Test functions follow `test_SCRIPT_FEATURE_CASE()` naming. Use `_` separators, lowercase.
*   **Examples**: `test_session_activate_fresh()`, `test_tag_swap_inline()`, `test_log_missing_heading()`.
*   **Why**: `run-all.sh` discovers and runs all `test_*` functions. Consistent naming makes grep and selective runs easy.

## 4. Don't Use `set -e` Globally

*   **Rule**: Use `set -uo pipefail` (not `set -euo pipefail`) at the top of test files. Handle return codes explicitly in each test.
*   **Why**: `set -e` causes the entire test file to abort on the first failure, skipping all subsequent tests. Tests need to capture and check exit codes without aborting.
*   **Pattern**:
    ```bash
    output=$(some_command 2>&1) || true
    if [[ $? -ne 0 ]]; then
      fail "Expected success, got failure"
    fi
    ```

## 5. Symlinks Must Be Updated When Scripts Rename

*   **Rule**: Test sandbox `setup()` functions symlink real scripts into `$TEST_DIR`. When an engine script is renamed, ALL test files that symlink it must be updated. See `engine/scripts/tests/PITFALLS.md` for details.
*   **After any rename**: `grep -r "old-name" ~/.claude/engine/scripts/tests/`

## 6. Running Tests

```bash
# Run all engine tests
bash ~/.claude/engine/scripts/tests/run-all.sh

# Run a single test file
bash ~/.claude/engine/scripts/tests/test-session-sh.sh

# Run with verbose output
VERBOSE=1 bash ~/.claude/engine/scripts/tests/test-session-sh.sh
```

## 7. Gold Standard Reference

Use `test-session-sh.sh` as the template for new test files. It demonstrates:
*   Proper sandbox setup/teardown
*   Mock script creation
*   Exit code checking
*   JSON output validation with jq
*   Multiple subcommand coverage in one file
