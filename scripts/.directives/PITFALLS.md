# Pitfalls

Known gotchas and traps when working with engine scripts. Read before modifying any script.

### ¶PTF_SUBSHELL_STATE_LOST — shell-var state set inside `$(...)` is discarded; EXIT traps don't fire there
**Context**: A script keeps mutable state (a call counter, an accumulator) in a shell variable, and reads/mutates it from functions invoked inside command substitution — e.g. `pid=$(_resolve …)` where `_resolve` calls `_graphql` which bumps a counter.
**Trap**: A command substitution `$(...)` runs in a **subshell**. Any variable increment inside it is lost when the subshell exits — the parent never sees it. So a "process-global" counter bumped inside `$(_resolve …)` resets for the next `$(_fetch …)`, silently re-serving stale state (in project.sh's fixture seam this re-served fixture #1 and looked like "project not found"). Conversely, an `EXIT` trap set in the top-level shell does **not** fire in those subshells (they reset traps) — which is what makes a single top-level cleanup trap safe.
**Mitigation**: For state that must persist across command-substitution boundaries, back it with a **file** (path in an exported var set once at top level), not a shell variable — every subshell reads/writes the same file. Set cleanup traps only in the top-level shell.

### ¶PTF_ISO_LEXICOGRAPHIC_COMPARE — string-comparing ISO8601 timestamps breaks across mixed precision
**Context**: Filtering/sorting Linear (or any API) timestamps with a raw `>` / `<` string compare in jq or bash.
**Trap**: Lexicographic order only equals chronological order when both strings are the **same width**. `"…00:00:00.000Z"` vs a fraction-less `"…00:00:00Z"` compare on the char after the seconds: `'.'` (0x2E) < `'Z'` (0x5A), so the millisecond form sorts BEFORE the plain form — a boundary item is mis-included/excluded. Bites whenever a human-supplied `--since` (no ms) meets API values that carry `.SSS`.
**Mitigation**: Normalize both sides to a fixed-width canonical form before comparing (strip `Z`, split on `.`, pad/truncate the fraction to exactly 3 digits, re-append `Z`) — then a lexicographic compare is chronologically correct. See `normTs` in `project.sh`.

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

### `local` at hook script top level silently exits via ERR trap
**Context**: Hook scripts run under `set -euo pipefail`. The `local` keyword is only valid inside functions — using it at script top level is a syntax error in strict mode.
**Trap**: `local var="value"` at hook script scope returns exit code 1, which triggers the ERR trap and silently kills the script. No error message is printed — the hook just stops executing. Subsequent code (including state writes and output) never runs.
**Mitigation**: Use plain variable assignment (`var="value"`) at hook script top level. Reserve `local` for inside functions only.

### jq `//` (alternative) operator has lower precedence than `|` (pipe)
**Context**: jq's `//` (alternative) operator provides a fallback when the left side is null/false. It's often used in patterns like `(.a | first) // (.b | first)`.
**Trap**: In `(.a | map(...) | first) // (.b | map(...) | first)`, the `//` binds after the first `|` chain completes, but the second alternative receives the output of the first chain as input — NOT the original root input. This means `.b` is searched inside the Phase object, not the root SKILL.md JSON.
**Mitigation**: Use explicit binding with `as $var` or parenthesize both alternatives: `(($x | map(...) | first) // ($x | map(...) | first))` where `$x` is bound to the input via `as $x`.

### lib.sh functions are sourced — they share the caller's shell state
**Context**: `lib.sh` provides shared functions (`ensure_jq`, `read_state`, `write_state`, etc.) that are sourced via `. lib.sh` into other scripts.
**Trap**: Variables set in `lib.sh` functions (like `$SESSION_DIR`, `$STATE_FILE`) persist in the caller's scope and can collide with the caller's own variables. Similarly, `set -e` in `lib.sh` affects the caller's error handling.
**Mitigation**: Use local variables (`local var=...`) in all `lib.sh` functions. Never set global options (`set -e`, `set -u`) inside sourced functions — let the caller control those.

### mkdir-spinlock leaks if the holder dies mid-critical-section — reclaim by PID, not a trap
**Context**: `safe_json_write` / `safe_json_update` / `_atomic_claim_preload` guard state writes with a `mkdir "${file}.lock"` spinlock, released via `rmdir` on the function's return.
**Trap**: A process killed between `mkdir` (acquire) and `rmdir` (release) strands the lock — nothing releases it. A wall-clock stale sweep alone is insufficient: when the waiter's retry budget (~1s) is shorter than the stale threshold (10s), every waiter errors `lock timeout` for the whole gap while the leaked lock sits there. A `trap`-based release is NOT the fix — a trap set inside a sourced `lib.sh` function leaks into the caller's shell (see the sourced-state pitfall above) and can't catch `SIGKILL` anyway.
**Mitigation**: Route every lock through the shared `_acquire_lock` / `_release_lock` helpers. `_acquire_lock` stamps the holder PID into `${lock}/pid`; a waiter reclaims deterministically when `! pid_exists "$holder"` (covers `SIGKILL` — a dead PID can never release), with the age sweep kept only as a PID-reuse backstop. Never hand-roll a bare `mkdir`/`rmdir` lock — the pid file makes a bare `rmdir` fail, and `_release_lock` is what cleans it.
