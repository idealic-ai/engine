# Tests — Engine Scripts

Bash test suites for the workflow engine scripts. Auto-plugged into agent context via `¶INV_DIRECTIVE_STACK`.

## Quick Start

```bash
# Run all tests
bash ~/.claude/engine/scripts/tests/run-all.sh

# Run verbose
bash ~/.claude/engine/scripts/tests/run-all.sh -v

# Run one suite
bash ~/.claude/engine/scripts/tests/run-all.sh test-session-sh.sh
```

## Infrastructure

| File | Purpose |
|------|---------|
| `test-helpers.sh` | Shared test library — assertions, counters, mock infrastructure. Sourced by all test files. NOT a test suite. |
| `run-all.sh` | Test runner — discovers and runs `test-*.sh` files. Supports `-v` flag and specific suite names. |

## Conventions

- **One test file per script**: `test-session-sh.sh` tests `session.sh`, `test-tag-sh.sh` tests `tag.sh`, etc.
- **Naming**: `test_script_feature_case()` — lowercase, underscore-separated.
- **Isolation**: Every test uses `setup_fake_home` to create a sandboxed `$HOME`. No test touches real files.
- **No `set -e`**: Use `set -uo pipefail`. Handle exit codes explicitly.
- **Source test-helpers.sh**: `source "$(dirname "$0")/test-helpers.sh"` at the top of every test file.

## Key Assertions

`assert_eq`, `assert_contains`, `assert_not_contains`, `assert_empty`, `assert_not_empty`, `assert_json`, `assert_file_exists`, `assert_file_not_exists`, `assert_dir_exists`, `assert_symlink`, `assert_gt`, `assert_ok`, `assert_fail`.

See `test-helpers.sh` for signatures and `TESTING.md` for the full reference table.

## Before Modifying Engine Scripts

1. Run the full suite: `bash ~/.claude/engine/scripts/tests/run-all.sh`
2. Check PITFALLS.md for known gotchas
3. After changes, run again to verify no regressions
