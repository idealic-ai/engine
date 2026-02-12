# Pitfalls

Known gotchas and traps when working with engine scripts. Read before modifying any script.

### engine session activate reads stdin — pipe JSON or use `< /dev/null`
**Context**: `engine session activate` accepts optional JSON parameters on stdin (piped via heredoc). It uses this to populate `.state.json` with session parameters.
**Trap**: Calling `engine session activate path skill` without explicit stdin causes it to hang waiting for input. This is especially insidious in hooks or other scripts that call activate programmatically — the hang looks like a freeze, not an error.
**Mitigation**: For re-activation without new parameters, always use `engine session activate path skill < /dev/null`. For fresh activation, pipe the JSON via heredoc.

### log.sh requires a `## ` heading in append content — or it exits 1
**Context**: `log.sh` auto-injects timestamps into the first `## ` heading of each appended block. It enforces this by checking for the heading pattern.
**Trap**: Appending plain text without a `## ` heading causes a silent exit 1. The content is not appended, and the calling script may not check the exit code. This leads to "missing log entries" that are hard to debug.
**Mitigation**: Every `log.sh` heredoc must start with `## [Heading]`. Never append bare text.

### tag.sh swap operates on the Tags line by default — use `--inline` for body tags
**Context**: `tag.sh swap` replaces one tag with another. By default it operates on the `**Tags**:` line (line 2 of the file). Inline body tags require the `--inline <line>` flag.
**Trap**: Running `tag.sh swap file '#needs-X' '#done-X'` when the tag is inline (not on the Tags line) silently succeeds but changes nothing — the tag stays bare in the body. The inverse is also a trap: using `--inline` on a Tags-line tag.
**Mitigation**: Use `tag.sh find '#tag' --context` first to determine whether the tag is on the Tags line or inline, then choose the appropriate swap mode.

### discover-directives.sh walks UP, not down — it finds parent directives
**Context**: Given a directory, `discover-directives.sh` walks from that directory upward to the project root, collecting directive files (README.md, CHECKLIST.md, PITFALLS.md, INVARIANTS.md) at each level.
**Trap**: Expecting it to find directives in child directories (e.g., passing `engine/` expecting it to find `engine/skills/PITFALLS.md`). It only walks up. For child directory discovery, you need to call it for each child directory separately.
**Mitigation**: Pass the most specific directory the agent is working in (e.g., `engine/skills/implement/`), and it will find directives at `skills/implement/`, `skills/`, `engine/`, and root.

### Bash glob `*/` skips broken symlinks — use `find -type l` instead
**Context**: When iterating symlinks with `for item in dir/*/;`, bash expands the glob using `stat`. Broken (dangling) symlinks — where the target has been deleted — fail `stat` and are silently excluded from the expansion.
**Trap**: Cleanup loops that use `*/` to iterate symlinks will miss broken symlinks entirely. The loop sees valid symlinks and real directories, but broken symlinks are invisible. This was the root cause of STALE-06.
**Mitigation**: Use `find "$dir" -maxdepth 1 -type l` to iterate ALL symlinks (both valid and broken). `find -type l` matches on the link itself, not its target, so broken links are included. Combine with `readlink` for target inspection — `readlink` returns the stored path even when the target doesn't exist.

### `sleep infinity` fails on macOS BSD sleep — use `read` or `sleep 86400`
**Context**: GNU coreutils `sleep` accepts `infinity` as a duration. macOS ships BSD `sleep`, which only accepts numeric values.
**Trap**: `sleep infinity` silently fails with "invalid number: infinity" and exits non-zero. In scripts with `set -e`, this kills the entire script. Without `set -e`, the command after `sleep infinity` runs immediately.
**Mitigation**: Use `read` (blocks on stdin forever) or `sleep 86400` (24h). Never use `sleep infinity` in scripts that must run on macOS.

### tmux destroys panes/windows when the shell command exits — use a blocking command
**Context**: `tmux new-window` and `split-window` accept a shell command argument. When that command's process exits (for any reason), tmux destroys the pane. If it was the last pane, the window is also destroyed.
**Trap**: `new-window` returns exit 0 (window created successfully), but if the command fails immediately after, the window is destroyed before the next tmux query runs. `list-panes` returns empty, `list-windows` may not find it — a race condition with no error message. Combined with `sleep infinity` on macOS, this produces "ghost windows" that exist for milliseconds.
**Mitigation**: Placeholder panes must use a command that blocks indefinitely: `read`, `cat`, or `while true; do sleep 3600; done`. Test by running `list-panes` immediately after `new-window` to verify the pane persists.

### lib.sh functions are sourced — they share the caller's shell state
**Context**: `lib.sh` provides shared functions (`ensure_jq`, `read_state`, `write_state`, etc.) that are sourced via `. lib.sh` into other scripts.
**Trap**: Variables set in `lib.sh` functions (like `$SESSION_DIR`, `$STATE_FILE`) persist in the caller's scope and can collide with the caller's own variables. Similarly, `set -e` in `lib.sh` affects the caller's error handling.
**Mitigation**: Use local variables (`local var=...`) in all `lib.sh` functions. Never set global options (`set -e`, `set -u`) inside sourced functions — let the caller control those.
