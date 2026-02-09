# Testing Standards — Engine Scripts

Rules for writing and maintaining tests for `engine/scripts/`. These tests use a custom bash test framework built on `test-helpers.sh`, not Jest.

## 1. Sandbox Isolation Is Non-Negotiable

*   **Rule**: Every test file must create a temp directory in `setup()` and clean it in `teardown()`. Override `HOME`, `PROJECT_ROOT`, and `PATH` to point into the sandbox. See `¶INV_TEST_SANDBOX_ISOLATION`.
*   **Why**: Engine scripts create symlinks at `$PROJECT_ROOT/sessions` and write to `~/.claude/`. Without isolation, tests corrupt the real project and Google Drive.
*   **Pattern**: Use `setup_fake_home` from `test-helpers.sh`:
    ```bash
    setup() {
      TMP_DIR=$(mktemp -d)
      setup_fake_home "$TMP_DIR"
      # ... symlink scripts under test, set PROJECT_ROOT, etc.
    }
    teardown() {
      teardown_fake_home
      rm -rf "$TMP_DIR"
    }
    ```

## 2. Use test-helpers.sh Mock Infrastructure

*   **Rule**: Source `test-helpers.sh` at the top of every test file. Use its built-in mock functions instead of writing manual mock scripts.
*   **Why**: `test-helpers.sh` provides battle-tested mock infrastructure that handles all the common patterns — fake HOME, fleet stubs, search tool stubs, tmux disabling.
*   **Available mock functions**:
    | Function | Purpose |
    |----------|---------|
    | `setup_fake_home "$TMP_DIR"` | Create isolated `$HOME/.claude/` structure, export `HOME` |
    | `teardown_fake_home` | Restore original `$HOME` |
    | `mock_fleet_sh "$FAKE_HOME"` | Create no-op `fleet.sh` stub |
    | `mock_search_tools "$FAKE_HOME"` | Create no-op `session-search.sh` and `doc-search.sh` stubs |
    | `disable_fleet_tmux` | Unset `TMUX`/`TMUX_PANE`, set `FLEET_SETUP_DONE=1` |
*   **Pattern**:
    ```bash
    source "$(dirname "$0")/test-helpers.sh"

    setup() {
      TMP_DIR=$(mktemp -d)
      setup_fake_home "$TMP_DIR"
      mock_fleet_sh "$FAKE_HOME"
      mock_search_tools "$FAKE_HOME"
      disable_fleet_tmux
      # symlink the script under test
      ln -sf "$REAL_SCRIPT" "$FAKE_HOME/.claude/scripts/my-script.sh"
    }
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

# Run with verbose output (shows all PASS/FAIL lines)
bash ~/.claude/engine/scripts/tests/run-all.sh -v

# Run a single test file
bash ~/.claude/engine/scripts/tests/run-all.sh test-session-sh.sh

# Run a single test file verbose
bash ~/.claude/engine/scripts/tests/run-all.sh -v test-session-sh.sh
```

**Pre-flight check**: `run-all.sh` verifies that `test-helpers.sh` exists before running any suites. If missing, all tests are blocked.

## 7. Key Infrastructure Files

| File | Role |
|------|------|
| `test-helpers.sh` | Shared test library — colors, counters, assertions, `run_test()`, mock infrastructure. Sourced by every test file. NOT a test suite itself (skipped by `run-all.sh`). |
| `run-all.sh` | Test runner — discovers and runs all `test-*.sh` files. Supports `-v` flag for verbose output and specific suite names as arguments. |
| `test-session-sh.sh` | Reference example for new test files — demonstrates sandbox setup, mock creation, exit code checking, JSON validation, multi-subcommand coverage. |

## 8. Assertions Reference

`test-helpers.sh` provides these assertion functions:

| Assertion | Signature | Purpose |
|-----------|-----------|---------|
| `assert_eq` | `expected actual msg` | Exact string equality |
| `assert_contains` | `pattern actual msg` | Substring or regex match |
| `assert_not_contains` | `pattern actual msg` | Substring absence |
| `assert_empty` | `actual msg` | Value is empty string |
| `assert_not_empty` | `actual msg` | Value is non-empty |
| `assert_json` | `file field expected msg` | JSON field value via jq |
| `assert_file_exists` | `path msg` | File exists |
| `assert_file_not_exists` | `path msg` | File does not exist |
| `assert_dir_exists` | `path msg` | Directory exists |
| `assert_symlink` | `path msg` | Path is a symlink |
| `assert_not_symlink` | `path msg` | Path is not a symlink |
| `assert_gt` | `a b msg` | Integer `a > b` |
| `assert_ok` | `desc command...` | Command exits 0 |
| `assert_fail` | `desc command...` | Command exits non-zero |

Use `pass "msg"` and `fail "msg" [expected] [got]` for custom assertions.
