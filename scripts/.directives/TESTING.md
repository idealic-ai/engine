# Testing — Engine Scripts

How to run and maintain the engine script test suite.

## Running Tests

```bash
# Run all engine tests (quiet mode — failures only)
bash ~/.claude/engine/scripts/tests/run-all.sh

# Run all tests with verbose output
bash ~/.claude/engine/scripts/tests/run-all.sh -v

# Run a single test suite
bash ~/.claude/engine/scripts/tests/run-all.sh test-session-sh.sh

# Run a single suite verbose
bash ~/.claude/engine/scripts/tests/run-all.sh -v test-tag-sh.sh
```

## Test Framework

Tests use a custom bash framework built on `test-helpers.sh` — not Jest or any Node.js test runner.

### Key files
| File | Role |
|------|------|
| `tests/test-helpers.sh` | Shared library: assertions, counters, mock infrastructure, `run_test()` |
| `tests/run-all.sh` | Runner: discovers `test-*.sh` files, runs each, reports summary |

### How it works
1. Each test file sources `test-helpers.sh` for assertions and infrastructure
2. Test functions are named `test_script_feature_case()`
3. `run_test` wraps each function with automatic `setup()`/`teardown()` calls
4. `exit_with_results` prints the summary and exits 0 (all pass) or 1 (any fail)

## Directory Layout

```
tests/
├── test-helpers.sh          # Shared library (NOT a test suite)
├── run-all.sh               # Test runner
├── test-session-sh.sh       # Tests for session.sh
├── test-tag-sh.sh           # Tests for tag.sh
├── test-log-sh.sh           # Tests for log.sh
├── ...                      # One test file per script
├── TESTING.md               # Testing standards
├── PITFALLS.md              # Known gotchas
└── README.md                # Agent orientation
```

## Writing New Tests

See `CONTRIBUTING.md` in the parent `scripts/` directory for the full template and step-by-step guide.

## CI Notes

Tests are not currently wired into the project CI pipeline. They are run manually via `run-all.sh`. All 30 suites should pass before pushing changes to engine scripts.
