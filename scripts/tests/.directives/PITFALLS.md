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

### Bash JSON encoding in test helpers — use `jq -n --arg`, not string interpolation
**Context**: Test helpers that construct JSON payloads (e.g., `make_bash_json()` for hook tests) need to encode command strings containing backslashes, quotes, newlines, or special characters.
**Trap**: Using string interpolation (`"command": "$cmd"`) inside a JSON template produces invalid JSON when the command contains special characters. The test appears to work for simple commands but silently generates malformed JSON for edge cases, causing spurious failures that look like hook bugs rather than test bugs.
**Mitigation**: Always use `jq -n --arg cmd "$cmd" --arg tool "$tool" '{tool_name: $tool, tool_input: {command: $cmd}}'` for constructing JSON in bash. The `--arg` flag handles all escaping correctly.

### Capture ALL real script paths BEFORE `setup_fake_home` — HOME switch creates circular symlinks
**Context**: `setup_fake_home` overrides `HOME` to `$FAKE_HOME`. Tests then symlink real scripts into the fake home for isolation (e.g., `ln -sf "$SESSION_SH" "$FAKE_HOME/.claude/scripts/session.sh"`).
**Trap**: If you reference `$HOME/.claude/scripts/foo.sh` as the symlink target AFTER `setup_fake_home` has run, `$HOME` is already `$FAKE_HOME` — so you create a symlink from the file to itself. The `ln -sf` succeeds silently, but executing the symlink produces "Too many levels of symbolic links". If the hook suppresses errors (`2>/dev/null || true`), the failure is completely invisible.
**Mitigation**: Capture every real script path as a variable BEFORE calling `setup_fake_home`, following the existing `SESSION_SH`/`LIB_SH` pattern. Then use the captured variable in `ln -sf`. Example: `DISCOVER_SH="$HOME/.claude/scripts/discover-directives.sh"` (before HOME switch), then `ln -sf "$DISCOVER_SH" "$FAKE_HOME/.claude/scripts/discover-directives.sh"` (after).

### Tests calling `session.sh restart` or `dehydrate` must set `TEST_MODE=1` — tmux keystroke injection kills the test runner
**Context**: Both `session.sh restart` and `session.sh dehydrate` have tmux keystroke injection paths that send `Esc` + `/clear` + Enter + restart prompt via `tmux send-keys` to `$TMUX_PANE`. This is how they restart Claude in production.
**Trap**: When a test calls either command inside tmux without `TEST_MODE=1`, `$TMUX` is inherited from the test runner's environment. The background subshell fires and sends `/clear` + a `/session continue ...` command to the test runner's pane, killing it. Redirecting stdout/stderr (`> /dev/null 2>&1`) does NOT prevent this — the `tmux send-keys` commands run in a `disown`ed background subshell.
**Mitigation**: Either `export TEST_MODE=1` at the top of the test file, or prefix individual calls: `TEST_MODE=1 "$SESSION_SH" restart "$DIR" > /dev/null 2>&1`. This makes the restart/dehydrate action echo dry-run info instead of injecting keystrokes. Note: `unset WATCHDOG_PID` only protects the watchdog signal path — the tmux path is a separate branch that requires `TEST_MODE=1`.

### Use `RESET` not `NC` for color reset — test-helpers.sh convention
**Context**: `test-helpers.sh` defines `RESET='\033[0m'` for color reset. Some older test files may have used `NC` (No Color) as the variable name.
**Trap**: Using `NC` in a test file that sources `test-helpers.sh` will produce an "unbound variable" error under `set -u` because `NC` is not defined — only `RESET` is. The error message (`NC: unbound variable`) doesn't immediately suggest a color reset issue.
**Mitigation**: Always use `$RESET` for color reset. If migrating old code, search-and-replace `NC` → `RESET`.
