# Pitfalls

Known gotchas and traps in this area. Read before working here.

### Test sandbox symlinks must be updated on script renames
**Context**: Engine test files create fake HOME directories and symlink scripts (session.sh, discover-directives.sh, lib.sh) into them for isolation.
**Trap**: When an engine script is renamed, all test sandbox `setup()` functions that symlink it must be updated simultaneously. The old symlink silently points to a deleted file (`ln -sf` succeeds even if the target doesn't exist), causing tests to fail with "command not found" or empty output instead of a clear rename error. Grep for the old script name across all `test-*.sh` files.
**Mitigation**: After renaming any script in `~/.claude/scripts/` or `~/.claude/hooks/`, immediately grep all test files for the old name: `grep -r "old-name" ~/.claude/engine/scripts/tests/`. Update every `ln -sf` and variable reference.

### test-helpers.sh `pass()` and `fail()` already increment TESTS_RUN — don't double-count
**Context**: `test-helpers.sh` provides `pass()` and `fail()` functions that each increment both their specific counter (`TESTS_PASSED`/`TESTS_FAILED`) AND `TESTS_RUN`.
**Trap**: If you call `pass()`/`fail()` AND separately increment `TESTS_RUN` in your test, the count is double. The summary will report more tests than actually ran, and the numbers won't add up (`passed + failed ≠ total`).
**Mitigation**: Never manually increment `TESTS_RUN`. Only call `pass()` or `fail()` — they handle all counter updates. If you need a custom assertion, build it on top of `pass()`/`fail()` (see `assert_eq` as a pattern).

### Use `RESET` not `NC` for color reset — test-helpers.sh convention
**Context**: `test-helpers.sh` defines `RESET='\033[0m'` for color reset. Some older test files may have used `NC` (No Color) as the variable name.
**Trap**: Using `NC` in a test file that sources `test-helpers.sh` will produce an "unbound variable" error under `set -u` because `NC` is not defined — only `RESET` is. The error message (`NC: unbound variable`) doesn't immediately suggest a color reset issue.
**Mitigation**: Always use `$RESET` for color reset. If migrating old code, search-and-replace `NC` → `RESET`.
