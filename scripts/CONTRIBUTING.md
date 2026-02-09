# Contributing — Engine Scripts

How to add new scripts and tests to `engine/scripts/`.

## Adding a New Script

1. **Create the file**: `~/.claude/engine/scripts/my-script.sh`
2. **Add shebang and safety**: Start with `#!/bin/bash` and `set -uo pipefail`
3. **Source setup-lib.sh** (if needed): `. "$(dirname "$0")/setup-lib.sh"` for shared bootstrap
4. **Register in engine.sh**: The `engine` CLI alias auto-routes `engine my-script [args]` to `my-script.sh` — no registration needed. The alias matches the filename minus `.sh`.
5. **Update README.md**: Add an entry to the Reference table in `scripts/README.md`
6. **Template**: Use `tag.sh` or `log.sh` as simple templates. Use `session.sh` as a complex template (subcommands, JSON state).

### Naming Convention
- Lowercase, hyphen-separated: `my-script.sh`
- Name should match the `engine` subcommand: `engine my-script` → `my-script.sh`
- If the script is only sourced by other scripts (not invoked directly), use a descriptive name like `lib.sh` or `setup-lib.sh`

### Script Structure Pattern
```bash
#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared library if needed
. "$SCRIPT_DIR/setup-lib.sh"

# Subcommand dispatch (if applicable)
case "${1:-}" in
  subcommand1) shift; handle_subcommand1 "$@" ;;
  subcommand2) shift; handle_subcommand2 "$@" ;;
  *) echo "Usage: $(basename "$0") <subcommand1|subcommand2> [args]" >&2; exit 1 ;;
esac
```

## Adding a New Test File

1. **Create the file**: `~/.claude/engine/scripts/tests/test-my-script.sh`
2. **Source test-helpers.sh**: `source "$(dirname "$0")/test-helpers.sh"`
3. **Define setup/teardown**: Use `setup_fake_home`, `mock_fleet_sh`, etc.
4. **Write test functions**: `test_my_script_feature_case()`
5. **Run tests at bottom**: Call `run_test` for each test function, then `exit_with_results`

### Test File Template
```bash
#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"
  disable_fleet_tmux

  # Symlink the script under test
  ln -sf "$SCRIPT_DIR/my-script.sh" "$FAKE_HOME/.claude/scripts/my-script.sh"

  # Symlink dependencies (lib.sh, etc.)
  ln -sf "$SCRIPT_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  export PROJECT_ROOT="$TMP_DIR/project"
  mkdir -p "$PROJECT_ROOT"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

test_my_script_basic() {
  local output
  output=$("$FAKE_HOME/.claude/scripts/my-script.sh" arg1 2>&1) || true
  assert_eq "expected" "$output" "basic invocation"
}

test_my_script_error_case() {
  local output
  output=$("$FAKE_HOME/.claude/scripts/my-script.sh" bad-arg 2>&1) || true
  assert_contains "error" "$output" "rejects bad input"
}

# Run
run_test test_my_script_basic
run_test test_my_script_error_case
exit_with_results
```

### Key References
- **test-helpers.sh** — All assertions, mock functions, and the test runner. Read this file first.
- **test-session-sh.sh** — The most comprehensive test file. Demonstrates sandbox setup, JSON validation, multi-subcommand coverage.
- **TESTING.md** — Full testing standards (naming, isolation, running tests).
- **PITFALLS.md** — Known gotchas (double-counting, color resets, symlink renames).
