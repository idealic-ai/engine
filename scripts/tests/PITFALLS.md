# Pitfalls

Known gotchas and traps in this area. Read before working here.

### Test sandbox symlinks must be updated on script renames
**Context**: Engine test files create fake HOME directories and symlink scripts (session.sh, discover-directives.sh, lib.sh) into them for isolation.
**Trap**: When an engine script is renamed, all test sandbox `setup()` functions that symlink it must be updated simultaneously. The old symlink silently points to a deleted file (`ln -sf` succeeds even if the target doesn't exist), causing tests to fail with "command not found" or empty output instead of a clear rename error. Grep for the old script name across all `test-*.sh` files.
**Mitigation**: After renaming any script in `~/.claude/scripts/` or `~/.claude/hooks/`, immediately grep all test files for the old name: `grep -r "old-name" ~/.claude/engine/scripts/tests/`. Update every `ln -sf` and variable reference.
