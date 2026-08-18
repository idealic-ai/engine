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

## [2026-07-30 00:36:47] ### ¶PTF_NESTED_GRAPHQL_FIRST_MULTIPLIES_COMPLEXITY — inlined child-connection `first:` values multiply into the server's query-complexity cap
**Context**: A GraphQL query fetches a paginated parent connection and inlines paginated child connections on each node — e.g. `issues(first: N){ nodes { comments(first: M) history(first: M) attachments(first: M) } }`.
**Trap**: Providers (Linear) compute query complexity as roughly `parent_first × Σ(child_first) × field-weight`, BEFORE any data is fetched. So `issues(250)` × three `child(250)` connections ≈ 250 × 750 × ~3.4 ≈ 634k, blowing Linear's 10,000 cap — and it fails on EVERY populated project. A `--since`/filter can't help: complexity is computed from the query SHAPE (the `first:` literals), not the result size. Offline fixtures can't catch it either — a canned response never computes complexity.
**Mitigation**: Keep the NESTED `first:` values small (they multiply) and paginate each child connection PER-ISSUE in a separate flat follow-up query (`issue(id){ comments(first: 250, after) }` — flat, so 250 is cheap there). Bound the product `parent_first × Σ(child_first)` well under the cap with margin. Verify against the live API — the offline suite cannot. See `project.sh` `_q_issues` (small nested caps) + `_fetch_remaining_{comments,history,attachments}` (per-issue pagination).

### ¶PTF_READ_T_FAILS_WITHOUT_TRAILING_NEWLINE — proof piped to `session phase` from a file with no final newline reads as empty
**Context**: `session.sh` reads STDIN proof with `if [ ! -t 0 ]; then IFS= read -r -t 1 _first_line; then _rest=$(cat); ...`. A heredoc (`<<'EOF'`) always appends a trailing newline, so interactive/`engine log` callers never hit this.
**Trap**: `read` returns **non-zero when it reaches EOF before the line delimiter**, even though it DID populate the variable. So proof written by `printf '%s'`, `JSON.stringify(obj)` (no trailing `\n`), or `echo -n` fails the `if read` guard → `PROOF_INPUT` stays empty → `§CMD_UPDATE_PHASE: Proof required … but no STDIN provided`, as if nothing was piped. Worse for tests: that error message **lists every required proof field**, so a negative test asserting "the rejection names field X" passes *spuriously* on empty stdin, masking the bug — only the positive (accept) path catches it.
**Mitigation**: Always terminate piped proof with a newline — `JSON.stringify(obj) + "\n"`, `printf '%s\n'`, or a heredoc. In tests, assert the SUCCESS path (exit 0) too, never only that a rejection names the missing field. Discovered building `skills/intake/assets/__tests__/proof-gates.test.mjs`.

### ¶PTF_TEST_SUITES_SYMLINK_LIBS — a `BASH_SOURCE`-relative sibling lookup breaks under the suites' fake HOME, and the covering suite is the one that can't see it
**Context**: Several `scripts/tests/*.sh` suites stage the engine into a temp `HOME` by **symlinking** individual libs (`linear-lib.sh`, `slack-lib.sh`, …) rather than copying the tree. A lib that resolves a sibling with `dirname "${BASH_SOURCE[0]}"` therefore resolves to the *symlink's* directory, where the sibling does not exist.
**Trap**: The `source` fails **mid-file**, and a failed `source` does not abort the caller — it silently drops every function defined after that line. The failure surfaces far away as `command not found` (`_load_key`, `_graphql`, `LINEAR_JQ_DEFS` all vanish). Worse, the suite covering the NEW code passes: adding `env-lib.sh` left `test-intake-sh.sh` at **53/53 green** while `test-project-sh.sh` sat at 11/91, `test-ticket-fetch-sh.sh` at 4/29 and `test-project-next-sh.sh` at 6/65. The suite you wrote the change for is structurally the least able to detect how you broke everything else.
**Mitigation**: Walk the symlink chain before resolving a sibling — `while [ -L "$src" ]; do …; done`, then `cd -P "$(dirname "$src")"`. And when touching a **shared** lib, run the NEIGHBOUR suites, not just the one covering your change: they are the blast-radius detector. Cheap rule — a shared-lib edit is not verified until every suite that sources it is green.

### ¶PTF_CHECKER_SEARCH_SET_EXCEEDS_CONSUMER — a preflight that looks in more places than the executor certifies a broken setup
**Context**: `engine env doctor` verifies credentials that `engine slack-post` / `engine project fetch` later consume. Widening where the doctor looks (adding a dotfile, adding a global location) feels strictly safer — it can only find *more*.
**Trap**: It is not safer, and it fails in the expensive direction. When the doctor's search set became a **superset** of `slack-post`'s, the doctor reported `PASS` + exit 0 for a token `slack-post` could not read: `/intake` Phase 0 went green, the operator was told the setup was correct, and the wave died ~40 minutes later at the Phase-5 announce. The same widened check gated the wizard, which then printed `already set` and refused to prompt — so the supported onboarding path could not produce the line the executor needed.
**Mitigation**: **A checker's search set must be a SUBSET of its consumer's, never a superset.** Widen the consumer first (or in the same change), never the verifier alone. Any new credential reader routes through `scripts/env-lib.sh` so the sets cannot drift apart. A verifier that grants confidence the executor cannot honour is worse than no verifier.

### ¶PTF_TESTS_THAT_PIN_THE_BUG
**Context**: A test suite is green. Someone reports a defect in the covered path, or a critique names one with a reproduction.
**Trap**: **The green suite may be *asserting* the bug.** A test written from observed behaviour rather than intended behaviour encodes the defect as the contract — and then actively defends it, because fixing the code turns the suite red and the obvious reading is "my fix broke a test". Real instance: `engine project lint` returned exit 0 with an empty `unreachable` list when its registry was missing; **two tests asserted exactly that** (`unreachable | length == 1`, `"Could not check (1)"`). The suite had to be corrected *before* the fix could land, and the fixer only got there by reconstructing the pre-fix behaviour and measuring it rather than trusting green.
**Mitigation**: When a confirmed defect lives in a covered path, **read the covering tests before touching the code** and ask what they assert versus what the contract says. If a fix turns a test red, the first question is *which of the two is wrong* — not how to keep the test passing. Green means "code matches its tests", never "code is correct". Corollary: assertions written while staring at output are the highest-risk kind; write the expected value from the spec first.

### ¶PTF_FIXTURES_CANNOT_CATCH_WHAT_THEY_DO_NOT_CONTAIN
**Context**: Logic is tested against committed fixtures — fast, deterministic, no credentials. The standard and usually correct choice.
**Trap**: A fixture that is *structurally* unlike production is **incapable** of failing on a whole class of bug, and its passing count reads as coverage. Real instance: a peer-comparison function split its input at the first colon. Every real Linear project name contains one (`Product: Differ`), so the feature would have broken on all five live projects — **after passing 57/57**, because no fixture project name contained a colon. The pattern then **repeated one layer up**: no test drove the multi-project path at the CLI at all, so the accumulation, the count and the colon split were uncovered together. Both were found by a live check, never by the offline suite.
**Mitigation**: Audit fixtures for *shape*, not just coverage — do the identifiers, names and keys contain the punctuation, casing, length and duplication that production does? Copy at least one fixture from real data verbatim. And keep **one opt-in live smoke test** (env-gated) asserting only that the queries/inputs still have the expected shape: it closes the class of gap fixtures cannot, without a suite that breaks whenever someone legitimately edits the data.

### ¶PTF_SCHEMA_FROM_ONE_SAMPLE
**Context**: Writing a validator, a schema, or a canonical shape by reading existing artifacts to learn what "correct" looks like.
**Trap**: **Transcribe from one sample and the validator encodes that sample's idiosyncrasies as law — then teaches every correct artifact that it is wrong.** Real instance: a handbook section order was derived from one of five hand-synced copies, and that copy happened to be the one an earlier edit had perturbed. The linter then reported ordering drift on the **four** consistent copies. Twice more in the same session the same error appeared in a different guise, including a rule that would have flagged all 39 live channels.
**Mitigation**: Derive a canonical shape from **every** instance, not one — and when they disagree, the **majority is evidence about the population and the outlier is evidence about your sample**. Two tells that the schema is wrong rather than the content: a rule that fails most of the corpus, and — the sharper one — **N independent artifacts all omitting the same element**. Nine authors omitting one rule is evidence the rule is not real, not evidence of nine mistakes. Before "fix the content", price "fix the schema": it is usually one edit against many.
