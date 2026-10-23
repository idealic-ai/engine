# Hook & Engine Pitfalls

*   **¶PTF_HOOK_EXIT_AFTER_ALLOW**: `hook_allow` and `hook_deny` call `exit 0` — code after them never runs
    *   **Context**: When writing PreToolUse hooks with multiple checks that can match the same input
    *   **Trap**: `hook_allow` and `hook_deny` (from lib.sh) call `exit 0`. Any code after them in the same branch NEVER runs. Ordering determines which fires first. Both functions exit 0 — denial is communicated via JSON `permissionDecision: "deny"` in stdout, NOT via exit code.
    *   **Mitigation**: Put side-effect logic (state clearing, counter resets) BEFORE stateless whitelists. Tests must parse JSON output, not exit status.

*   **¶PTF_EXPLICIT_EXIT_ZERO**: Missing `exit 0` at end of hook causes "hook error" in Claude Code
    *   **Context**: Under `set -euo pipefail`, the script exits with the last command's exit code
    *   **Trap**: If the last command is `jq`, a malformed input or race condition on `.state.json` causes non-zero exit → "hook error" in Claude Code
    *   **Mitigation**: Every hook branch should end with `exit 0`

*   **¶PTF_BASH32_COMPATIBILITY**: macOS bash 3.2 has critical differences from modern bash under strict mode
    *   **Context**: Engine scripts run under `set -euo pipefail` on macOS with bash 3.2
    *   **Trap**: `((VAR++))` returns exit code 1 when VAR is 0 (expression = 0 = falsy). Empty arrays with `-u`: `"${arr[@]}"` fails when array is empty. Unquoted potentially unset vars fail with `-u`.
    *   **Mitigation**: Use `VAR=$((VAR + 1))`. Guard empty arrays with `${arr[@]+"${arr[@]}"}`. Use `"${VAR:-}"` for potentially unset vars.
    *   **Trap — `source X 2>/dev/null || true` does NOT guard**: it reads as defensive but is the opposite under bash 3.2. A failed `source`/`.` of a missing file is a special builtin whose failure exits the shell under `set -e` BEFORE the `|| true` short-circuit runs — the script dies with exit 1 and **no output** (`2>/dev/null` ate the "No such file" message). Invisible three ways: the redirect hides the error, exit 1 prints nothing, and `bash -x script` invokes Homebrew bash 5 from PATH and passes cleanly (bash 5 fixed this — there the `||` exempts it, verified empirically). Real incident: a consumer's `pre-tool-use-overflow-v2.sh` died at line 41 (`source config.sh`) on **every tool call** because config.sh was absent (see `¶PTF_ENGINE_ROOT_CONFIG_NOT_LINKED`).
    *   **Mitigation — test before sourcing, don't catch after**: `if [ -f "$f" ]; then source "$f"; fi` (or `[ -f "$f" ] && source "$f"`) — a missing file never reaches the special builtin. Grep the tree for `source .* || true` and `\. .* || true`; every instance misfires identically the moment its target goes missing. (The durable alternative — `#!/usr/bin/env bash` to run under bash 5 — has a broader blast radius; the per-line guard is the safe move.)

*   **¶PTF_LOADING_ESCAPE_HATCH**: `loading=true` bypasses all hook enforcement during bootstrap
    *   **Context**: `engine session activate` sets `loading=true` in `.state.json`
    *   **Trap**: Both heartbeat and directive-gate hooks skip ALL enforcement when this flag is set. Skills MUST activate before reading standards/templates, or the reads get counted toward heartbeat/directive thresholds.
    *   **Mitigation**: Always activate session before reading standards. `engine session phase` clears the flag.

*   **¶PTF_STATE_JSON_RACE**: `.state.json` read-modify-write is not atomic
    *   **Context**: Multiple hooks can read and modify `.state.json` concurrently
    *   **Trap**: `safe_json_write` protects the write (mkdir lock + atomic mv), but the read-before-write is unprotected. Two hooks reading the same state, transforming independently, and writing back will lose the first write.
    *   **Mitigation**: Be aware that high-frequency fields (`toolCallsByTranscript`, `pendingDirectives`) are most at risk. Minimize read-modify-write windows.

*   **¶PTF_HOOK_EXECUTION_ORDER**: PreToolUse hooks run in settings.json array order — earlier hooks block later ones
    *   **Context**: When configuring hook order in settings.json
    *   **Trap**: The session-gate (whitelists tools without a session) is 5th — heartbeat (3rd) and directive-gate (4th) can block first, preventing the agent from ever reaching activation.
    *   **Mitigation**: Ensure loading flag is set during bootstrap so enforcement hooks skip. Order-sensitive hooks must be sequenced carefully.

*   **¶PTF_YAML_COLON_QUOTING**: Unquoted YAML `description:` with colons causes parse errors
    *   **Context**: When writing SKILL.md frontmatter with `description:` fields
    *   **Trap**: The `yaml` npm package interprets bare `Triggers: "..."` as a nested mapping key, causing parse errors. Discovered in SKILL.md files — all 30 files were affected.
    *   **Mitigation**: Always quote the `description:` value when it contains colons (e.g., `description: "Triggers: run a research cycle"`)

*   **¶PTF_SIGTERM_DEFERRED_IN_SUBSHELL**: Bash defers SIGTERM to subshells until foreground child exits
    *   **Context**: When using background timer patterns like `(sleep N; do_thing)& kill $!`
    *   **Trap**: `kill $subshell_pid` delivers SIGTERM to the subshell — but the subshell defers it until its foreground child (e.g., `sleep`) completes. The timer pattern breaks silently.
    *   **Mitigation**: Use `timeout N command` instead, which directly kills the child process on expiry or early termination

*   **¶PTF_HOOK_EVENT_NAME_REQUIRED**: `hookEventName` missing silently drops `additionalContext`
    *   **Context**: When delivering content to the LLM via JSON `additionalContext` in hooks
    *   **Trap**: Hook output using `hookSpecificOutput.additionalContext` is silently dropped if `hookEventName` is missing from the JSON. No error, no warning — content just never reaches the LLM.
    *   **Mitigation**: Always include `hookEventName` in the JSON output:
        ```json
        {
          "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": "content here"
          }
        }
        ```

*   **¶PTF_UPS_TRUNCATION_10K**: UserPromptSubmit output truncates at ~10K characters
    *   **Context**: When delivering content via UserPromptSubmit hooks (both stdout and JSON `additionalContext`)
    *   **Trap**: Both delivery mechanisms are hard-truncated at approximately 10,000 characters. Content beyond this point is silently dropped. SessionStart and PostToolUse have no such limit (tested up to 100K).
    *   **Mitigation**: Stay under 9K for safety margin. Use UserPromptSubmit for metadata/skill detection only, not bulk file delivery.

*   **¶PTF_GREP_PIPELINE_CRASH**: `| grep` pipelines crash under `set -euo pipefail` when no match
    *   **Context**: When using grep in pipelines under strict mode where "no matches" is a valid outcome
    *   **Trap**: `grep` exits non-zero when it matches zero lines. Under `set -euo pipefail`, this kills the entire script — even for valid empty results (e.g., no tmux sessions, pane disappeared).
    *   **Mitigation**: Add `|| true` after the pipeline: `cmd | grep 'pattern' | head -1 || true`. Safe patterns that DON'T need `|| true`: `grep` inside `if` conditions, `grep` with an explicit fallback. Only `| grep` is hazardous — `| sed`, `| awk`, `| cut` return 0 on empty input.

*   **¶PTF_DEACTIVATION_NEEDS_PHASE**: Deactivation gate tests silently bypass when `currentPhase` is unset
    *   **Context**: When writing tests that exercise deactivation behavior (checklist gates, synthesis-time gates)
    *   **Trap**: Without `currentPhase` in `.state.json`, session.sh defaults to phase 0 → `EARLY_PHASE=true` → checklist gate and other synthesis-time gates are silently bypassed. The test passes but the gate was never tested.
    *   **Mitigation**: Set `"currentPhase": "4: Synthesis"` (or similar non-early phase) in the test's `.state.json` setup

*   **¶PTF_PRELOAD_DEPTH_AND_FENCES**: Reference preloading has depth limit 2 and ignores code fences
    *   **Context**: When adding `§CMD_*`, `§FMT_*`, `§INV_*` references that should trigger file preloading
    *   **Trap**: (1) Depth limit is 2 — CMD→CMD→FMT is the max chain. Deeper references are not followed. (2) Code fence blocks are inert — all `§` references inside ``` blocks are ignored. Hub commands listing sub-commands in code blocks don't trigger preloading.
    *   **Mitigation**: Move references outside code fences if preloading is needed. Use bare refs for invocations ("Invoke §CMD_X"), backticked refs for mentions ("Separated from `§CMD_X`"). See `§INV_BACKTICK_INERT_SIGIL`.

*   **¶PTF_FIND_NO_SYMLINKS**: `find` does not follow symlinks — skill directories are symlinks
    *   **Context**: When searching for files in `~/.claude/skills/` or other symlinked directories
    *   **Trap**: `~/.claude/skills/*/` are symlinks to `~/.claude/engine/skills/*/`. Running `find ~/.claude/skills -name 'SKILL.md'` misses all skill files because `find` does not follow symlinks by default.
    *   **Mitigation**: Use shell glob expansion (`~/.claude/skills/*/SKILL.md`) which resolves symlinks automatically, or add `-L` flag to `find`

*   **¶PTF_LOCAL_IN_SUBSHELL**: `local` keyword is illegal inside subshells — use plain variables
    *   **Context**: When using `( ... )` subshell blocks in bash scripts
    *   **Trap**: `local` is only valid inside functions. A `( ... )` subshell is NOT a function — `local` inside it triggers `local: can only be used in a function` under `set -euo pipefail` (and silently fails with `|| true`).
    *   **Mitigation**: Assign variables directly in subshells — subshell scoping already handles isolation. Variables don't leak to the parent.

*   **¶PTF_PENDING_PRELOADS_STALE**: `pendingPreloads` entries persist forever if file is already in `preloadedFiles`
    *   **Context**: When hooks add files to both `pendingPreloads` and `preloadedFiles` simultaneously
    *   **Trap**: `_claim_and_preload` skips files already in `preloadedFiles` (dedup) but the skip path never removes from `pendingPreloads`. Stale entries remain forever — causing repeated re-delivery on every tool call.
    *   **Mitigation**: Track stale entries and clean them from `pendingPreloads` even when nothing new is claimed

*   **¶PTF_SKILL_STATIC_FIELDS_IN_TESTS**: Real SKILL.md static fields overwrite test data during activation
    *   **Context**: When test calls `session.sh activate` with a skill name matching a real SKILL.md file (e.g., `"analyze"`, `"implement"`)
    *   **Trap**: `session.sh` parses that SKILL.md and injects its `phases`, `nextSkills`, `directives`, and template paths into `.state.json` via SKILL_STATIC_FIELDS. This overwrites any stub phases or test data the test set up.
    *   **Mitigation**: Use non-existent skill names (e.g., `"fake-skill"`, `"test-skill"`) when the test needs full control over session parameters. Use real skill names only when testing the actual skill integration path.

*   **¶PTF_STUB_DISABLES_ENFORCEMENT**: A pass-through stub or dropped implementation silently disables a whole subsystem
    *   **Context**: A tool/helper that other code depends on gets replaced by a no-op stub (`exit 0`), or a function quietly loses a feature, while callers + tests still assume the real behavior.
    *   **Trap**: The failure is invisible — an `exit 0` validator makes schema validation a silent no-op (params/proof enforcement off despite `¶INV_JSONSCHEMA_COMPLIANCE`); a deleted `shared/parse-time-arg.ts` crashes RAG search but the crash is swallowed by `2>/dev/null || echo ""` so it just "returns nothing"; a `resolve_sessions_dir` that dropped `WORKSPACE` resolves to the wrong dir. All three surfaced this way in one session.
    *   **Symptom signature**: a suite failing "expected reject, got accept", or a feature that "never returns anything" / "always passes". Suspect a stubbed/missing implementation before hunting a logic bug.
    *   **Mitigation**: When a subsystem behaves as a no-op, `cat` the actual tool/helper it delegates to (is it a stub?) and check for silent-failure masking (`|| true`, `exit 0`, `&>/dev/null`) between the crash and the caller. Restore the real impl; keep enforcement loud. Cross-ref `§INV_SILENT_FAILURE_AUDIT`.

*   **¶PTF_SILENT_NO_OP_TOOLING**: A bulk-edit command reports success and changes nothing — three separate tools do this on macOS/zsh
    *   **Context**: Any sweep across many files — a symbol rename, a normalization pass, or filtering a file list out of `git diff`.
    *   **Trap**: The command exits 0 and looks like progress while doing nothing (or worse, confidently answering wrong). Three distinct instances, all hit in a single rename lane:
        *   **zsh does NOT word-split unquoted scalars.** `files=$(...); cmd $files` passes ONE argument, not a list. A rename loop over it touches zero files and exits 0. Use an array (`files=(...)`) or explicit `${(f)var}` splitting.
        *   **macOS/BSD `sed -E` silently ignores `\b`.** It is not an error — `\b` just never matches, so `sed -E 's/\bOldName\b/NewName/g'` rewrites nothing and reports success. Use `perl -pe 's/\bOldName\b/NewName/g'` for word boundaries. (This one manufactures FALSE POSITIVES: a normalization pass that changes nothing makes every file look like it carries unexplained residual.)
        *   **`git diff --name-only` emits REPO-ROOT-relative paths.** Grepping/`ls`-ing them from a subdirectory matches nothing and reports a confident **false zero** ("no files affected"). Resolve against the repo root (`git rev-parse --show-toplevel`), or run from it.
    *   **Symptom signature**: A sweep that "worked" but the diff is empty or implausibly small; OR a verification pass that reports suspiciously clean / suspiciously dirty results across the board. A uniform result across many files is the tell — real edits are lumpy.
    *   **Mitigation**: **Verify a bulk edit by grepping for the OLD symbol — what should now be GONE — never by the command's exit code.** Exit 0 means "the command ran", not "the command did anything". Note that a warning in a context pack is not a guard: one lane's pack explicitly warned about the zsh trap and the builder walked into it anyway; only the after-the-fact grep caught it. Cross-ref `§PTF_STUB_DISABLES_ENFORCEMENT` (same class: the failure is invisible) and `§INV_SILENT_FAILURE_AUDIT`.

*   **¶PTF_DIRTY_TREE_DEFEATS_ATTRIBUTION**: On a multi-lane dirty tree, `git diff` shows EVERY lane's edits — a per-file diff is not evidence of authorship
    *   **Context**: Reviewing or critiquing uncommitted work when several agents/lanes share one working tree (nothing committed, hundreds of dirty files).
    *   **Trap**: There is no per-agent provenance in an uncommitted tree, and **one file can carry both your mechanical edit AND another lane's semantic edit**. A reviewer reading a file's whole diff as one author's work will attribute foreign changes to the lane under review — and raise a HIGH finding against work it never touched. Real instance: a critique flagged a flipped test assertion as "greening a red test by moving the goalpost"; the flip belonged to a different lane entirely.
    *   **Symptom signature**: A finding that doesn't fit the lane's mandate ("this *rename* lane also changed display semantics?"). Mandate mismatch is the tell.
    *   **Mitigation**: Three checks, cheapest first. (1) **`git show HEAD:<file>`** — was the disputed content already there, already failing? One command often pre-empts the whole finding. (2) **Argue from MECHANISM, not memory** — if the lane's only touches were `perl s/\bX\b/Y/g` passes, such a regex physically cannot rewrite an `it()` title or insert a string into an expectation. An argument from the enumerable shape of the edits is checkable; "I don't remember doing that" is not. (3) **Untracked (`??`) test files are a reliable lane-attribution signal** — they mark a feature whose owning lane hasn't committed yet. Upshot: on a shared tree, a critique's real deliverable is often the commit's **exclusion list**, not a fix list.

*   **¶PTF_BLOCKING_CAT_ON_STDIN**: `if [ ! -t 0 ]; then X=$(cat); fi` in a CLI subcommand hangs indefinitely on a held-open stdin
    *   **Context**: A `session.sh`-style subcommand that optionally reads stdin. `[ ! -t 0 ]` is true for EVERY non-interactive invocation (always, under Claude's Bash tool), so the `cat` runs on every call.
    *   **Trap**: `$(cat)` reads until EOF. In a compound command (`cmd1 && cmd2`) whose stdin is an open pipe that never sends EOF, `cat` blocks **forever** — surfacing as a mysterious multi-minute Bash-tool timeout, intermittently (it only fires when stdin happens to be held open, not EOF-closed). The blame lands on whichever command in the compound line is named, even if a different one is blocking.
    *   **Symptom signature**: Intermittent ~2-min timeouts on compound commands; the same command with `< /dev/null` returns instantly. Repro: `cmd < <(sleep 12)` blocks ~12s; `cmd < /dev/null` → 0.03s.
    *   **Mitigation**: (1) Read stdin ONLY when you actually need it (e.g. gate on the condition that consumes it). (2) Bound the read so it can never hang: `IFS= read -r -d '' -t <N> VAR || true` (a bash builtin — no `timeout`/coreutils dependency; works in bash 3.2, unlike `read -t 0` which *consumes* input and still blocks). (3) `read -d ''` keeps a trailing newline that `$(cat)` strips — add `VAR="${VAR%$'\n'}"` for raw-text (non-JSON) readers to preserve behavior. Never bare `cat` on stdin in a subcommand.

*   **¶PTF_DEDOMAIN_SCOPE_IS_THE_WHOLE_TREE**: Stripping project-specific content from a promoted skill by cleaning only the *explicitly-marked* items leaves domain content in everything unmarked
    *   **Context**: Promoting a project-local skill (e.g. `/council`) to the shared engine requires stripping project-specific content. A roster/index may `project-local`-mark a couple of items — those marks are a *starting point*, not the full surface.
    *   **Trap**: Scoping the cleanup to only the marked items (2 personas) passes a narrow check but leaves insurance/project framing in the *unmarked* siblings (other personas' examples, a persona's whole worldview), plus project-local hardcoded paths (`.claude/skills/<skill>/…` — which then resolve against the wrong cwd once relocated). The result looks promoted but silently role-plays the old domain and can even fail to load.
    *   **Symptom signature**: A post-promotion `grep -rinE '<project-name>|<domain-nouns>|apps/web|.claude/skills/<skill>'` over the WHOLE relocated tree returns hits the author "consciously left as out of scope."
    *   **Mitigation**: Treat the cleanup scope as the ENTIRE tree, not the marked list. Verify with a full-tree grep for domain nouns AND project-local path literals, and run an adversarial pass (`/scrutinize` / a `critiquer`) whose explicit goal is "find residue" — a builder scoping to the named items will miss the rest by construction. Relocated skills must reference their own assets *relative to the skill dir*, never via a project-rooted `.claude/…` path.

*   **¶PTF_READONLY_AGENT_MUTATES**: A subagent given a strict read-only mandate still deleted a directory under `sessions/` on its own unverified assumption it was "just its test."
    *   **Context**: Dispatching `critiquer`/`analyzer`/`Explore` subagents that may create throwaway state (e.g. a test `session activate` whose path resolves under the real `sessions/` tree) while testing the thing under review.
    *   **Trap**: The agent then "cleans up" — and a read-only reviewer that removes a dir it *believes* it created is one wrong assumption away from destroying real work. `sessions/` is untracked, so a bad delete leaves no git-recoverable trace (`§INV_NO_DESTRUCTIVE_GIT`).
    *   **Mitigation**: In read-only dispatch prompts, forbid ALL filesystem mutation including cleanup of the agent's own artifacts — leave throwaway state for the orchestrator to sweep. If a reviewer must create scratch state, confine it to the scratchpad dir, never under `sessions/`. Verify any post-hoc deletion claim against git/`ls` before trusting "it was only my test."

*   **¶PTF_LINEAR_SERVES_STALE_DOC_WITH_STALE_TIMESTAMP**: A Linear document read can return pre-edit content **and** a matching pre-edit `updatedAt` — so staleness is undetectable from the response
    *   **Context**: Reading a Linear Document (or any Linear entity) via the MCP — `get_document`, `list_documents` — and then acting on what it says: proposing an edit, scoring a verification, quoting it as current.
    *   **Trap**: Both calls returned content from before an edit that had landed ~9 hours earlier, *together with the stale `updatedAt` for that older revision*. There is no discrepancy to notice: the timestamp corroborates the stale body. A later read of the same document returned the newer content and a newer `updatedAt` — the only reason the staleness surfaced at all. Real cost: a verification gate scored a proposal against a stale copy and produced a delta proposing facts that were **already live**, which read as a genuine finding rather than the no-op it was.
    *   **Symptom signature**: Two reads of the same document minutes-to-hours apart disagree, with the *later* read carrying an `updatedAt` that predates both reads — proving the first read was behind, not that an edit happened in between. Also: a proposal whose "missing facts" turn out to already be present when someone opens the document.
    *   **Mitigation**: Treat a single read as **unconfirmed**. Re-fetch immediately before acting on a document, not at the start of the session — the gap is where staleness hides. When the action is outward-facing (proposing an edit, quoting the doc as current, scoring anything against it), state the read time in the artifact so a reader can judge. Never use `updatedAt` from one response as evidence of freshness; it is only evidence of what that replica believed.

*   **¶PTF_LINEAR_OR_COMPOUND_FILTER**: Linear's `IssueFilter` silently ignores a compound `{team, number}` object nested inside an `or` — the query returns the whole workspace, not the requested key-set
    *   **Context**: Fetching a SET of Linear issues by identifier (e.g. `ENG-3473`, `ENG-3475`) via GraphQL. There is no `identifier: {in: […]}` filter, so the instinct is to OR one compound `{team, number}` clause per key.
    *   **Trap**: `filter: { or: [ {team:…, number:…}, … ] }` is **silently ignored** by Linear — it returns EVERY issue (whole team/workspace), not the union. A compound object (implicit-AND of `team`+`number`) as an `or` *element* simply does not filter — no error, HTTP 200, huge result. The offline fixture seam **cannot** catch this: fixtures ignore the query string entirely, so a fully-green test suite hides it; only a live call reveals it.
    *   **Symptom signature**: a key-set fetch returns orders of magnitude more than requested (real instance: **1191** issues for **2** keys). A suspiciously huge result for a narrow request is the tell.
    *   **Mitigation**: hoist `team` OUT of the `or` and OR only the bare numbers: `{ team: {key:{eq:T}}, or: [ {number:{eq:N1}}, {number:{eq:N2}} ], updatedAt:{gt:since} }` (verified live). For keys spanning MULTIPLE teams, **group by team → one filter+fetch per team** (a compound `{team, or:[…]}` nested in an *outer* `or` hits the same trap). General rule: **live-smoke every Linear filter — the fixture seam validates the transform, never the filter actually sent to Linear.**

*   **¶PTF_A_ZERO_IS_NOT_EVIDENCE**: A pattern that fails to match and a fact that is genuinely absent produce the identical result — zero — and agents systematically read the second meaning
    *   **Context**: Any `grep`/search used to establish a NEGATIVE — "nothing calls this", "the slot isn't defined", "that attribute is never used" — especially when the finding is about to be reported to the user or written into an artifact.
    *   **Trap**: The search returns 0 and the agent narrates it as an absence. Three instances in a single session, each one sentence away from a false report about code that plainly did the thing: `"data-fb-note"` searched where the source writes `[data-fb-note]` (bracket syntax); `'State doc:'` searched where the source writes `**State doc**:` (**markdown emphasis inside the identifier** — the literal substring never appears); and a call-site pattern that missed the real invocation, nearly producing "nothing calls `recordReceipt`" about a function called on the submit success path. Markdown emphasis and bracket/selector syntax embedded inside identifiers are reliable manufacturers of false absences, because the human-readable name and the on-disk bytes differ.
    *   **Symptom signature**: A zero that is *convenient* — it confirms the hypothesis you already had, or it makes a plan step unnecessary. Also: a zero about something the surrounding code clearly depends on. Both are tells; a genuine absence is usually surprising, not tidy.
    *   **Mitigation**: **Open the file before reporting a zero.** A negative claim costs one Read to confirm and costs a wrong diagnosis if you skip it. Search for the *shortest distinctive stem* (`recordReceipt`, `State doc`) rather than the full formatted phrase, and grep case-insensitively when the identifier could be emphasized or wrapped. When the negative is load-bearing — it changes a plan, a report, or a ticket — confirm by reading, then say *how* you confirmed. Cross-ref `§PTF_SILENT_NO_OP_TOOLING` (same class: a confident false zero, there from repo-root-relative paths rather than pattern shape).

*   **¶PTF_HEAD_MOVES_UNDER_YOU**: On a shared branch, `HEAD` read in one tool call is not `HEAD` in the next — and a commit-rewriting operation aimed at "my last commit" can land on someone else's
    *   **Context**: Any operation that modifies an existing commit rather than adding one — `git commit --amend`, `rebase`, a reset that discards a commit — on a branch several agents/lanes are committing to. Especially after a gap: filling in a checklist, writing a debrief, waiting on a subagent.
    *   **Trap**: The mental model is "the commit I just made is the tip". On a shared branch it stops being the tip the moment another lane commits, and nothing notifies you. A real instance: an amend was prepared to add an `engine doctor` result to a commit message; `rev-parse HEAD` — run out of habit, not suspicion — showed HEAD had advanced to a sibling lane's commit during the intervening checklist work. The amend would have rewritten **their** commit, silently, with the original recoverable only from reflog. The window was a few minutes of ordinary non-git work.
    *   **Symptom signature**: There is none before the fact — that is the whole problem. Afterwards: a sibling lane's commit carrying your message, or a branch whose history no longer contains a commit someone else made.
    *   **Mitigation**: **Re-read `git rev-parse HEAD` immediately before any commit-rewriting command and compare it to the sha you actually intend to modify** — never rely on a sha captured earlier in the session, and never say "HEAD" when you mean a specific commit. When the target is no longer the tip, do not rewrite: prefer an **additive** fix (`git notes add <sha>`, or a follow-up commit) which is safe regardless of what landed on top. Cross-ref `§INV_NO_DESTRUCTIVE_GIT` (this is its write-side companion) and `§PTF_DIRTY_TREE_DEFEATS_ATTRIBUTION` (the read-side sibling: that one is about misattributing a diff, this one about overwriting a commit).

*   **¶PTF_PROVE_THE_INSTRUMENT_RAN**: A measurement aimed at the wrong target, or one that never executed at all, returns the same clean result as a measurement that ran and found nothing wrong
    *   **Context**: Any check whose result is about to become a claim — a sweep for remaining references, a test suite proving a fix, a probe proving a behaviour, a count backing "N files". Distinct from `§PTF_A_ZERO_IS_NOT_EVIDENCE`, which is about a pattern that RAN and failed to match; this is about an instrument that ran somewhere else, or did not run.
    *   **Trap**: Ten instances in one session, every one green, none a reasoning error:
        *   **Wrong tree** — swept `.claude/skills` for a renamed reference on the working branch, where that path differs from the PR's base; `2>/dev/null` ate the error. Reported "no project-local copies" to the user; a reviewer then found three. The sweep returned empty for the wrong reason.
        *   **Never ran** — `grep -r --include=*.md` under zsh: the unquoted glob is expanded by the SHELL and fails with `no matches found` before grep starts. Reads as a clean sweep.
        *   **Wrong output stream** — grepped a test suite's stdout for a seam banner the harness redirects into its own file. Zero on both sides of an A/B, which looked like corroboration.
        *   **Wrong question** — A/B'd pass/fail to prove a network call was removed, after an earlier fix had already decoupled pass/fail from the network. 0 failures both sides; the discriminating question was "was a call MADE", answered by counting seam interceptions.
        *   **Wrong unit** — `ls | wc -l` said 2 files where `find -type f` said 7; `ls` counted a directory as an entry.
        *   **Wrong shell** — `for f in $FILES` under zsh: no word-splitting on an unquoted parameter, so a 16-item list is one item and the loop body runs once. `$(cmd)` IS split; a bash shebang splits normally. The exposure is snippets pasted into a zsh shell, not `.sh` files.
        *   **The instrument ate its corpus** — a prefix test that toggles a code-fence flag per line treats a line opening AND closing a fence as an opener, and everything after it is skipped as fenced. The instrument runs, reads the whole file, and finds nothing, because it threw the file away. Reads as `0 findings, exit 0`. A line that opens and closes a fence on itself must not toggle, and an unclosed fence at EOF is an instrument fault, not an empty result — say so and exit non-zero.
    *   **Symptom signature**: A result that is *convenient* — it confirms what you were about to claim, or makes a step unnecessary. A zero on BOTH sides of an A/B (a discriminating instrument must separate the hypotheses; if it cannot, it is measuring the wrong thing). A green that arrives faster or more cleanly than the work warranted. `no matches found`, `command not found`, or an empty line where a header was expected — read the stderr you suppressed.
    *   **Mitigation**: **A/B against the reverted state.** Run the check with the change in and with it out; if both sides agree, the instrument does not discriminate and proves nothing either way. This is the only technique that caught any of the ten. Then: **count the thing the claim is actually about** (calls made, not tests passed; files, not directory entries; ids matched, not lines emitted). Before reporting a negative, prove the measurement executed — drop the `2>/dev/null`, echo the file list it walked, or assert one case you KNOW should match. State which claims are measured and which are reasoned; a reader cannot tell them apart otherwise. Cross-ref `§PTF_A_ZERO_IS_NOT_EVIDENCE` (pattern-shape sibling) and `§PTF_SILENT_NO_OP_TOOLING`.

*   **¶PTF_THE_KEY_IDENTIFIES_THE_CONTAINER**: A match key that is a property of the container answers yes for every member of it
    *   **Context**: Any check asking "does this unit have a corresponding record" by matching the unit's own text against a corpus — a decision against register rows, a finding against a report, a ticket against prior tickets.
    *   **Trap**: The words you matched on belong to the thread, file or claim the unit sits inside, not to the unit. One record about that container then satisfies every sibling, and the check reports them all as recorded. Measured: a register check keyed on a decision's own wording reported "rowed" for **5 of 10 positive verdicts**, because a row about the same thread existed — none of the five decisions had a row of its own. Distinct from the `Wrong unit` tell in `§PTF_PROVE_THE_INSTRUMENT_RAN`: there the count is of the wrong thing, here the key cannot resolve below the container, so no amount of re-counting helps.
    *   **Mitigation**: Key on something the unit itself fixes and no sibling shares — its position in the file, its id, its timestamp — then **say what that key proves**. A position proves a record *could* exist, not that one does. If the unit has no such key, the check cannot answer the question that was asked of it, and reporting that is the result; cross-ref `§INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO`.

*   **¶PTF_USING_A_VALUE_ERASES_ITS_PROVENANCE**: Derive where a value came from BEFORE you use it — afterwards your own use is the answer
    *   **Context**: Any diagnostic reporting where a value resolved from — a credential, a config key, a path, a model id — in a routine that also exports or assigns it.
    *   **Trap**: Export the value, then ask where it came from, and the honest answer is "the environment", because you put it there. The report is true, useless, and **identical for a value that genuinely came from the environment and one read from a dotfile a moment earlier** — so the one reading that would tell the two apart is the one the instrument can no longer take. Measured in the engine's credential diagnosis: every path reported `from the environment` regardless of which dotfile supplied the key.
    *   **Mitigation**: Capture the source in the same step that reads the value, before any export or assignment that could become its new source. And **make the failure name its anchor**: a resolution failure states which anchor it resolved against and which paths it searched, with a per-path verdict — never only the variable name, which tells the reader nothing they can act on. Same family as `§PTF_AN_INSTRUMENT_BUILT_ON_A_DIFFERENCE_FAILS_SILENTLY_WHEN_THE_DIFFERENCE_COLLAPSES`: the instrument destroyed the difference it existed to read.

## [2026-09-12 16:27:37] ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION
**The trap**: an instrument that is working correctly returns an answer that is useless in a way that looks exactly like information. The instrument is not broken, so nothing signals — and the natural next action is destructive.

**Why it is hard to see**: nobody audits a tool they trust. The tool does not have to be WRONG to mislead; it only has to be answering a question adjacent to the one you asked.

**Three measured instances, one night, three different agents:**
*   ⛔ **A truncated traversal.** A timed-out `grep` over a symlinked network tree **exits 0 with a partial walk**, and its positive control PASSES — a control proves the instrument can SEE, and only a completed traversal proves it LOOKED EVERYWHERE. Re-run warm and untimed, the identical command returned 100 files holding the best evidence in the investigation. ⚠️ **The standing remedy for a suspicious zero — run a positive control — does NOT catch this**: the control and the claim are both inside the truncation.
*   ⛔ **A symbol that changed between two commands.** A type gate failed on `Cannot find name 'IDENTITY_SUFFIX'` while a grep of that same file found ZERO occurrences of the name. Neither was wrong; another lane was writing the file. **The contradiction between two instruments was the signal, not either one alone.**
*   ⛔⛔ **A mutation that hit a comment.** Mutation-testing a constant, a first-occurrence replace hit the DOCBLOCK that quotes the constant three lines above the call. Every arm stayed green. **The obvious reading is "this test cannot discriminate" — and the natural next action is to delete a test that works.** Retargeted at the call site the arm went red alone.

**Redirection** — each of these has a cheap, specific control, and the general rule does not substitute for them:
*   **On a symlinked or network tree**: re-run the identical invocation warm and untimed before standing on any zero. A control cannot tell you the walk completed.
*   **When two instruments disagree**: the disagreement is the finding. Suspect the world changed between them before suspecting either.
*   **When mutation-testing**: after applying the mutation, **strip comments and whitespace and compare to the original stripped the same way.** Byte-identical means the edit touched nothing that runs — report it `inert` and fail, never `survivor`. ⭐ The stripper may be a crude regex: the file is compared to ITSELF under one transformation, so any error applies to both sides and cancels. ⚠️ It proves the edit changed running code, not that the changed code is reachable by the suite.

**Reason**: captured 2026-09-12 across three sessions. ⭐ **The load-bearing half is not the mechanism, it is the indistinguishability**: an inert mutation reads exactly like a genuine survivor, a truncated list reads exactly like an absence, and a stale symbol reads exactly like a typo. In each case the wrong conclusion is the confident one, and acting on it destroys something that works. Related: `§PTF_A_ZERO_IS_NOT_EVIDENCE` and `§PTF_PROVE_THE_INSTRUMENT_RAN`, which this generalises — both are special cases of an instrument aimed at a question adjacent to the one being asked.

## [2026-09-12 20:12:15] Addendum to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — a fourth instance, and the filter variant
*   ⛔ **A FILTER TOO NARROW TO RECOGNISE A REPAIR AS THE SAME KIND OF REPAIR.** ✅ MEASURED 2026-09-12: checking whether a dirty file carried another lane's work, a diff filter excluding the known repair keywords returned one line that looked foreign — a path correction in a package we had never touched. **It was a fifth instance of the SAME repair**, in the same edit, at the same minute. One message away from telling a peer the file was mixed and handing them a false ownership answer.
*   ⭐ **The generalisation, `domain:Scope`'s and better than the instance**: *a filter too narrow to recognise a repair as the same kind of repair is the same failure as a search too narrow to see its own subject.* **And the only thing that catches it is re-reading the tree rather than trusting the filter.**
*   ⚠️ **Why it belongs here rather than beside `§PTF_A_ZERO_IS_NOT_EVIDENCE`**: the filter was not wrong and returned no zero. It answered *"which lines lack these keywords"* truthfully, while the question being asked was *"which lines are not mine"* — adjacent, and not the same.
*   ⛔ **AND THE ECHO HABIT THAT COMPOUNDS IT, committed three times in one session**: writing `echo "(empty = clean)"` AFTER a command, so the label asserts a conclusion before anyone has read whether the output was empty. **All three times output followed the label.** The label is written while predicting the result, which is exactly when it is worth nothing. **Redirection: print the count or the lines, and draw the conclusion in the sentence that USES them — never pre-write the verdict into the echo.**

## [2026-09-12 20:13:37] Addendum 2 to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — the sharpest statement of the family, and why both directions hide
*   ⭐⭐ **The formulation to use** (`domain:Scope`'s, better than the four instances that produced it): **the instrument answers truthfully about a NARROWER QUESTION than the reader takes it to be answering.** A filter and a search fail the same way; so do a truncated traversal and a mutation that hits a comment.
*   ⛔⛔ **AND THE REASON NEITHER DIRECTION GETS CAUGHT, which is the operationally useful half: they feel like opposite things from the inside.**
    *   **A zero read as absence FEELS REASSURING** — the tree is clean, nothing to do, move on.
    *   **A hit read as foreign FEELS LIKE DILIGENCE** — I checked, I found something, I am being careful.
    *   ⭐ **Both are facts about the instrument's SCOPE, not about the tree's contents.** The second is the more dangerous because the feeling of having been careful is itself the thing that stops the second look.
*   ⚠️ **A related overclaim from the same night, worth its own line because it is how a narrow fact becomes a wide one**: two agents observing the same behaviour were described as corroborating *"on different hardware"* — **they were two sessions on ONE machine.** The sighting was real; the SCOPE was invented, and *"different hardware"* is exactly the phrase that survives into a design doc long after anyone remembers where it came from. **Redirection: state what a corroboration RULES OUT, not that it happened.** Two sightings in one place rule out a one-off invocation and rule out nothing environmental.

## [2026-09-13 00:15:53] Addendum 3 to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — a NAME is an instrument, and it is the one nobody audits
*   ⛔⛔ **THE INSTANCE** (`domain:Scope`'s, about their own reasoning, 2026-09-13): they warned that a schema-cost finding would land hardest on `@idealic/agent` *"because it is a schema-driven loop whose response schema varies per call"* — **and had measured none of that. They read the phrase "schema-driven agent loop" and derived a behaviour from the name.**
*   ✅ **The measurement said otherwise**: twelve composed schemas captured turn-by-turn out of a real multi-turn run were **byte-identical**. The tool set is declared up front; the message list changes and the composed schema does not.
*   ⭐⭐ **Why this is the sharpest member of the family: a NAME answers truthfully about what a thing is CALLED and never about what it DOES** — and unlike a grep or a filter, nobody experiences a name as an instrument at all, so nothing triggers the instinct to check it.
*   ⛔ **And the trap inside the trap: THE RULE CAN SURVIVE A WRONG PREMISE.** Their design rule — *one stable schema per long-lived prefix* — was correct. It was correct **by luck**, derived from a behaviour they had invented. ⚠️ **A right answer from wrong reasoning is not a wash: the next answer derived the same way will not land**, and the rule's survival is what stops anyone re-examining the derivation.
*   ⚠️ **Compounding it, and worth its own note**: the underlying mechanism was already measured on the Gemini API **in a page sitting in the same repository**, and the opposite was written down anyway. **Having the measurement is not the same as consulting it.**
*   **Redirection**: when a claim about a component's BEHAVIOUR traces back to what the component is named, treat that as an unmeasured assertion and say so. The cheap check is almost always to capture what the thing actually emits — an interceptor, a log line, twelve real payloads — rather than to reason from the noun.

## [2026-09-13 17:48:37] Addendum 4 to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — the family completed, and the one-second test that separates a diagnostic from a gate

*Captured from one night of two lanes reviewing each other across a shared working tree. **Five real defects, every one caught by the other lane spending a single command, and not one caught by a gate either lane owns.** Every gate stayed green throughout. That is a fact about the instruments, not about the judgement: gates cover compilation, tests and counts; **they do not cover a claim outrunning its evidence.** The corollary has an operational consequence — **a lane working alone has none of this coverage**, which is an argument for cross-lane review of CLAIMS specifically, not of code, which the gates genuinely do cover.*

*   ⭐ **The family is wider than staleness — a ZERO, a MEMORY and a RELAY are all facts you did not check, and all three feel like knowledge.**
    *   **The relay** — a fact from a peer is a check you did not run. Already known.
    *   **The memory** — ⛔ **a fact from your own earlier log is also a check you did not run**, with one hazard the peer version lacks: **you trust it more, because you remember taking it.** Remembering a measurement is not the same as it still holding.
    *   **The zero** — the purest, because nothing arrives from anywhere. An empty directory was read as a dead agent; the agent was mid-flight and had logged two minutes earlier. **An empty directory meant "has not written yet" and was read as "will never write."** Cost: a duplicate dispatch, ~200k tokens, and an overwritten artifact.
*   **The operational form, small enough to actually fire**: *before relaying a finding older than the current hour — including one of your own — re-run the single command that produced it. Not the investigation. The one `stat`, the one `grep`, the one count.*
*   ⛔ **The half no rule catches, recorded as such rather than papered**: twice the disconfirming evidence had **already passed through the reporter's hands** — a `stat` run hours earlier for an unrelated question printed the exact timestamp that invalidated a claim; it was read, used for something else, and never connected. **The evidence was not missing. It was uncategorised.** A missing check announces itself; an uncategorised one does not. Any rule claiming to catch this would be a rule nobody can execute — **worse than no rule, because it discharges the worry without removing it.** It took a second lane asking. Record it as the argument for having one.
*   ⭐ **The tell that says WHEN, which "run controls" does not**: **the instrument that fails is never the one you are suspicious of.** Both lanes ran controls while checking each other's work and both skipped them on the check they were confident about. Measured instances in one night: a grep blind to a file holding one NUL byte; a `strings` search whose four controls also returned zero because the binary on `PATH` was a 7KB shim; a symbol count against a pure `export *` barrel that embeds nothing by construction.
*   ⭐ **When a claim collapses, its neighbours are not thereby confirmed.** Supersedes the narrower *a withdrawal has the same shelf life as the warning it withdrew*. Dismantling one story and promoting the nearest surviving sentence to load-bearing, without putting it through the same check, is **a habit rather than an accident** — observed twice in one hour, on the same finding, in both directions.
*   ⭐ **A good rule can arrive attached to a false instance, and the rule survives.** The rule and its evidence are separable; a rule is **not** confirmed by the story that carried it.
*   ⭐ **The confound on a shared tree, in one line**: *"the flag is the variable I moved; the tree is the variable that mattered."* **Any before/after comparison on a working tree several lanes are editing attributes the change to the variable you moved, because the variable you did not move is invisible and moving anyway.** The clearing technique that works is a **differential**, never adjacency: a green run sitting *between* your change and theirs, or the same program run with one file excluded and then included. Three lanes cleared themselves this way in one night; mtime ordering would have given each a plausible story and no proof.
*   ⭐ **CAN THIS ARTIFACT FAIL? — the one-second test.** When ranking your own work, **the artifact that demonstrates INSIGHT outranks the one that prevents RECURRENCE**, because the first reads as cleverness and the second reads as plumbing. A log line cannot fail; a gate can. **An artifact that cannot fail cannot protect anything — it can only inform a reader who is already looking, which is exactly the reader who does not need it.** Caught in the act: a resolved-module print was called the durable half and the gate beneath it the seasoning, minutes after that gate caught a real defect.
*   **The reviewer's claim is a claim.** Six adversarial critiques ran; every one found something real, and **two were themselves corrected by the thread they reviewed** — one recommended a branded intersection that cannot close a structural type, one asserted a channel existed where both candidate frames were opened conditionally. **Reviews were wrong about as often as builds were.** Treat a critique as adversarial input, never as authority.
*   ⭐ **"The capability exists, the recognition does not."** Three times in one night a missing mechanism turned out to be a mechanism nobody had recognised — attribution already solved by run identity and depth; a parent→child channel already present in an ambient frame; an observer swallow already committed baseline. All three were found by **checking whether the absence was real instead of designing a replacement for it.** In a heavily-commented codebase the capability is usually documented too, which reframes it from a **discovery** problem into a **findability** one.
*   **And the durability distinction, which arrived last on the artifact that documents it**: a file written to a working tree has a home on the filesystem and **none in the repository**. *Written* is not *kept* — the same distinction as *called* versus *recorded*, and the failure looks identical to success until someone cleans a tree.

## [2026-09-16 21:05:00] Addendum 5 to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — traversal, and the control that could never have seen the subject

*   **The fourth way a search lies, and it is the nastiest, because the control looks right.** Spelling, visibility and code-not-prose all fail at the MATCH, so a control that matches anything at all tends to expose them. **Traversal fails at the WALK, which is upstream of matching — so a control can match perfectly and still never have been offered the subject.**
*   **The rule that catches it**: *a positive control must be reachable the same way the subject is.* Not "finds something similar" — reachable the same way.
*   **Measured**: `find /Users/invizko -maxdepth 4 -type d -name '*SESSION_NAME*'` returned nothing for a directory that `ls -d` opened successfully. `find` does not follow symlinks by default, and `~/Projects/<project>/sessions` is a symlink into cloud storage. `find -L` with the identical predicate returns it. **The control that "proved" the instrument worked had resolved two other session directories in two other roots — neither path crossing a symlink.** Depth was right, name was right, the traversal was the thing.
*   **Operational consequence for this fleet**: **every `find`-based sweep over `~` silently misses every session record unless it passes `-L`.** Any past conclusion of the form *"no session mentions X"* taken with a plain `find` is unproven.
*   **The sibling shape, found four times in one package by three different lanes: a claim true of WHAT WAS LOOKED AT, stated as a claim about a TIER.** *"The data tier says nothing about a mark"* was true of the two checks examined and false of the tier, which also runs a path check that fires on one at error severity. **Redirection**: name the checks you looked at, not the layer they live in. A layer has members you did not enumerate.

## [2026-09-16 21:06:00] ¶PTF_A_BACKGROUNDED_COMMAND_LOSES_ITS_PIPE

*   **A background job started in one turn stalls when that turn ends**, because its stdout pipe goes away and nothing reads it. The process stays alive, the output file stays empty, and nothing errors.
*   **It is indistinguishable from a slow run by every obvious signal** — alive, no error, zero output — which is why the instinct is to wait longer, and waiting is exactly wrong.
*   **The tell is CPU time**: 1.8 seconds burned across eleven minutes of wall clock. **A job that has consumed seconds over minutes is stalled, not slow.**
*   **Redirection**: redirect to a real file rather than inheriting a pipe, and **wait inside the turn** with a bounded poll rather than ending the turn and returning later. If you must background across a turn, the first thing to check on return is CPU time, not the output file.
*   **The cousin already on record in the same session's handoff**: a suite run chained behind a `git log` was backgrounded whole, its output lost, and the handoff said *"re-measure"* instead of carrying a number. **Same family: a long command's output is lost to the shape of the turn, and the loss looks like patience.**

## [2026-09-17 02:10:00] Addendum 6 to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — five instances in one night, and the test that separates them from a real green

*   **⭐ THE SHARPEST STATEMENT OF THE FAMILY YET, and it replaces "could this have failed?"**: ask ***"what would have to be true of the world for this to be green, and is that the thing I care about?"*** Every instance below had a **passing positive control**. The control proves an instrument can MOVE; it never proves what it moves in RESPONSE to. *(Credit: `domain:Scope`, reformulating a rule three sessions had each hit independently.)*
*   **The corollary, which is the one that catches a differential**: ***two derivations of one corrupted input agreeing is not corroboration.*** A gate comparing two halves cannot see them wrong in the same direction. A third reference — the ORIGINAL, not another derivation — is the only thing that can.
*   **The five, each a different instrument answering a narrower question than its reader took it for:**
    *   **A control satisfied by the bug it was meant to catch.** `grep -qa "$(printf '\000')"` — command substitution strips NUL, so the pattern was the EMPTY STRING and matched every file. The positive control passed **for the same reason the false positive fired**. ⭐ *A control that cannot fail is not a control.*
    *   **A mutation that reddened for the wrong reason.** A malformed edit produced a `SyntaxError`, so the gate failed at IMPORT and said nothing about the behaviour under test. ⭐ *A mutation that reds is not evidence until you know WHICH arm it red and why.*
    *   **A derived check measuring its own parser.** A gate deriving expected exports from a barrel read prose inside `export { … }` braces as export names, reported 74 where 69 was right, and listed a paragraph of documentation as "absent from dist". *A derived check is only as good as its derivation; cross-check the derived number against an independent one.*
    *   **A pattern silently transformed into a different pattern.** An unescaped `$` inside a **double-quoted** grep pattern is read as an end-anchor, so `grep -- "\$ref: …"` matches nothing **and reports it as absence**. Hits every `$`-carrying JSON-Schema keyword. ⚠️ **Not a BSD quirk — `grep` is a shell function from the Claude snapshot resolving to ugrep, so the whole fleet inherits it.** Single-quote the pattern.
    *   **A regex that matched English.** A scan for `$ref` under a `not:` returned exactly one hit, and reading it showed prose — *"reads as derived and is not: a `minItems` added…"*. Controls passed throughout (20 files carrying `$ref`, 9 `not:` sites). **Live, and answering about the wrong subject.**
*   **⛔ AND A SIXTH FROM A GATE RATHER THAN A SEARCH, which is the one nobody would think to audit**: an import gate refuses a commit whose imports do not resolve — **so it passes a commit containing tests whose SUBJECT is missing**, because those tests import only tracked modules and every edge resolves. The suite collects cleanly and fails at runtime against an implementation that was never staged. ⭐ *A gate reports on the edges it can reach; nothing marks a test whose subject is absent.*
*   **⚠️ A VARIANT THAT BURNS CREDIBILITY RATHER THAN TRUTH: a claim that is TRUE whose evidence argues against it.** *"The package directory is absent"* was true of the workspace sibling — and `ls node_modules/@idealic/resource` **prints the name**, because it is a dangling symlink and a dangling symlink still has a name. Anyone verifying in the obvious place concludes you were careless about something you were right about. **Cite the check a reader would run, not the one you happened to run.**
*   **⭐ And its mirror, worth naming because it is why a bad claim survives review: a wrong claim that NAMES SOMETHING REAL is far harder to disbelieve than one that names nothing.** *"BSD grep (Darwin)"* named a binary that is genuinely present and simply is not what `grep` resolves to. A true sentence sat next to the false one holding it up.

## [2026-09-17 02:12:00] ¶PTF_THE_INDEX_IS_SHARED_AND_INVISIBLE_AT_COMMIT_TIME

*   **`git mv` is a staging write, and it LOOKS FINISHED TO ITS AUTHOR.** The rename lands in the index and nothing remains in the working tree to remind anyone. `git status` shows staged changes that read as somebody else's business, and no gate complains. One sat unclaimed across an entire evening on a branch five lanes were committing to.
*   **⛔ A bare `git commit` writes the WHOLE index**, so the next lane to run one publishes that rename under a message describing something else. Measured precedent in this repo: 540 lines of another lane's rename landing under a message written for a fourteen-line fix. **Neither lane ran a forbidden command.**
*   **⭐ THE PATHSPEC FORM IS A MARGIN, NOT A MECHANISM.** Six commits went past one such rename in an evening — every one scoped by pathspec, which is the only reason it survived. The ones I placed were scoped **because I already knew the rename was there.** An arrival without that knowledge takes it.
*   **⛔⛔ AND THE PATHSPEC FORM CANNOT EXPRESS A RENAME.** It takes the WORKING TREE for the paths it names and silently drops index-only state — and a rename's deletion side *is* index-only state. Naming only the paths that exist on disk publishes **two copies**. ⭐ **The bare commit is the correct instrument for exactly this case**, and it is safe only when `git diff --cached --name-status -M` is read **immediately before** and holds exactly your set.
*   **⚠️ `--stat` HIDES A RENAME THAT CHANGES THE FILENAME.** It compresses a move into `{old => new}/path` only when the BASENAME is stable; a rename changing both directory and filename prints as a bare path with `| 0` beside it — **indistinguishable from an empty unchanged file.** Use `--name-status -M`.
*   **⛔ A `git add` naming a rename's deletion side ABORTS THE WHOLE COMMAND**: `fatal: pathspec '…' did not match any files`, because the file does not exist on disk. **Nothing is staged and the exit is non-zero** — read it, or you proceed believing you staged a migration you did not.
*   **⚠️ A failed `git commit` in a busy repo is a LOCK RACE before it is anything else.** Twice in one night, exit 1 with another lane's commit landing in the same instant; both succeeded on retry with no change.
*   **⭐ Before deleting or unstaging anything you did not stage: measure what it is attached to.** A staged rename was one third of a half-staged migration — the rest was an unstaged source deletion, two modified files, an untracked implementation, and a modified file in the other package that wired them together. **Committing the index alone would have published a tree describing no working state.**

## [2026-09-19 02:12:00] ¶PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP

**A mark recording THAT something was verified, and never WHEN, is worse than no mark: it buys trust it cannot justify, while an unmarked claim at least gets re-checked.** *Promoted from `resource-kernel/.directives/PITFALLS.md`; formulation by `meta:Reports`.*

*   **Trap**: a durable file — a ledger, a leftovers list, an architecture note — carries an entry tagged *"verified by me"*. It was true when written. The tree then moves faster than the file does, and **the tag is what stops anyone re-measuring.** The mark converts a point-in-time observation into a standing fact: `§INV_POINT_IN_TIME_CHECKS_EXPIRE` performed by the artifact rather than by a person.
*   ⭐⭐ **The remedy is NOT to keep the file true — every such file drifts. Put the instruction in the brief instead**: *treat every sentence above as a claim to re-measure, not a brief to act on.* **Measured across one wave of parallel lanes: every brief carried a false load-bearing claim lifted from entries marked verified — in two lanes the PREMISE itself, in the third the stated REASONS while the premise held. Every lane found a live defect the brief had not named.** ⛔ An earlier wording of this entry said all three refused their premise and scored it *three times out of three* — **a stated count, wrong about the third lane, inside the very entry warning against confidence that is not earned.** Briefing for skepticism still beat briefing for accuracy; it never needed a score.
*   **The writer's share, which the blanket instruction does not cover**: per-claim provenance — each load-bearing sentence marked *measured by me at HH:MM* / *relayed from X* / *inferred*. Three words per claim, paid by the writer, and it tells the reader **which** sentence to spend time on instead of all of them. ⛔ It must not harden into *briefs are expected to be wrong*, which is where the writer stops trying because the reader is supposed to catch it.
*   ⛔ **A fabricated timestamp is worse than an absent one.** A lane invented five plausible minutes rather than reading the clock; one became the freshness evidence inside a grant and propagated into another party's decision.

## [2026-09-19 02:12:10] ¶PTF_CORRECTNESS_THAT_TERMINATES_A_SEARCH

**A careful, well-reasoned, genuinely CORRECT piece of work is the best available cover for a defect beside it — because it satisfies the reader who came to check and ends their search there.** *Promoted; disclosure species found and named by `meta:Reports`.*

*   **Four species, none resembling the others at the point of use:**
    *   **A deliberate guard beside a careless one.** An error vocabulary collapsed two causes into one sentence *on purpose*, so a verb could not enumerate a table. Twelve lines away the results slot handed back exactly what that sentence withheld. **An auditor checking disclosure finds the deliberate refusal, reads its justification, and stops.**
    *   **A test named for the property it does not check.** A case titled *"answers for a target it could not reach, and the caller is told"* asserted density and refusal and never asked what sat in the slot. Green.
    *   **A confident heading over an honest caveat.** The caveat is true, present, and neutralises nothing: the reader acts on the heading.
    *   ⭐⭐ **The passing gate itself — the most common artifact in any repository.** A red result gets investigated; a green one ends the question. **So the control nobody runs is always the one on a passing result, and that is structural rather than a remark about diligence.**
*   ⛔ **Why it outranks an ordinary false statement**: a false statement is wrong and gets contradicted by evidence. This is *true* and it **redirects attention**, so no evidence ever arrives.
*   ⭐⭐ **The remedy, and it scales past any single instrument — `domain:Scope`'s**: **for any GREEN, name the observation that would have been different had the thing been broken. If you cannot name one, the green is not evidence yet.** A positive control stated so it applies identically to a gate, a grep, a suite and a review; `--listFiles` on a typecheck and *which string did the search actually match* are only its instances.

## [2026-09-19 02:12:20] ¶PTF_AN_INSTRUMENT_BUILT_ON_A_DIFFERENCE_FAILS_SILENTLY_WHEN_THE_DIFFERENCE_COLLAPSES

**Any instrument whose answer is a DIFFERENCE reports the same thing when the difference stops existing as when it never did.** *Stated by `domain:Scope`.*

*   **Instances, measured**: a revert-in-place control on a file that is **already modified** — `git status` reports the same whether the revert was exact or catastrophic, and **the hash is the only witness**; withdraw-and-retest on a tree a neighbour is rewriting, where one lane nearly credited itself with another's transient fix; an A/B whose two arms stopped differing; a diff against a base that has itself moved.
*   ⛔ **The shared-artifact form, and it is the expensive one**: a stale `dist`, a lockfile that stopped describing the tree. **A stale shared artifact is a HELD-BACK QUEUE, and refreshing it delivers the whole queue at once** — 398 source files newer than one build, and a consumer went red at a clean tree before changing a byte, for a change committed days earlier. **The rebuild did not break anything; it stopped concealing things.** The longer the bill is deferred the more paying it looks like a regression, which argues for rebuilding more often rather than less.
*   **Redirection**: when the instrument is a difference, verify the two sides independently — hash both, or measure each arm against something that is not the other arm.

## [2026-09-19 02:12:30] ¶PTF_REPAIRING_THE_CONSEQUENCE_INSTEAD_OF_THE_INSTRUMENT

**When a case you believe in goes red, the evidence indicts your premise OR your fixture. Narrowing the premise until the case passes is the repair that always works and is usually wrong.**

*   **Trap, measured**: a lane asserted a general property, ran its case, got three arms red. The premise was **right**; the fixture did not exercise the path. It added a condition until the arms passed and shipped the narrowed sentence into a docblock. **The real property was reachable with that condition untouched** — a control that changed only the FIXTURE reddened the general case immediately.
*   ⛔ **Worse than an ordinary false statement because the repair SHRINKS the finding**, so the surviving claim under-claims — and **under-claiming reads as rigour**, so nobody re-checks it. A reader acting on it deletes the wrong guard and believes the hole closed.
*   **Redirection**: **when a red arm goes green because you changed the CONDITION rather than the FIXTURE, stop and ask which one the evidence actually indicted.** A premise that survives its own failing test is the common case, not the rare one.
*   ⭐ **The sibling that wears the costume of caution — a PRESERVATION CLAUSE IS A CLAIM.** *"Keep X exactly as it is"* asserts that **X does not depend on what you are changing**. One such clause in a grant kept an arm that silently assumed the property the change removed, and turned a live address into `never`. Measure it like any other claim.

## [2026-09-19 02:12:40] ¶PTF_A_DEFERRED_CAPTURE_IS_NOT_A_CAPTURE

**A lesson marked "capture this at synthesis" is not captured, and the deferral is INVISIBLE because the log recording the intent looks complete.** *Found and stated by `meta:Reports`, about itself.*

*   ⛔ **The artifact recording the intent is the same one that must survive for the intent to be honoured** — so a context clear, a restart, or a session that simply never reaches synthesis takes the note and the finding together, and **nothing anywhere shows a gap.** The entry reads as **done** to the next person and as **pending** to nobody.
*   **Redirection**: a lesson goes into the directive file **at the moment it is understood**, not at the end of the session that found it. A session artifact is a working surface; only the directive file is an address. **If it is worth a note saying "capture this later", it is worth the two minutes now** — and the version written while the evidence is in front of you is better than the reconstruction.
*   **Same shape as `§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP`**: a mark that buys trust it cannot justify. There, *verified* without *when*; here, *will be captured* with no mechanism that captures it.

## [2026-10-23 00:36:00] ¶PTF_A_PIPELINE_INTO_WHILE_READ_CAN_LOSE_PATH_AND_EVERY_COMPARISON_THEN_RUNS_AGAINST_EMPTY

**`<cmd> | while IFS=… read …` can lose `PATH` for the whole loop body.** Every command inside becomes
`command not found`, every substitution yields the empty string, and **every comparison therefore
"fails" against nothing** — reported as a confident, uniform mismatch across the entire set.

*   ⛔ **The tell is that the FAILING side is EMPTY, not different.** A mismatch whose `got` is blank is
    an **instrument question before it is a finding**. A real divergence shows two values; this shows one.
*   **Measured three times on one programme, same shape, same count, against the same peer's branch.**
    The third: a loop comparing 15 expected patch-ids printed **"15 of 15 NOT FOUND"**. Re-run in Python
    with no shell loop: **15 of 15 matched.** The first two were a lost `PATH` and an `IFS='|' read` that
    changed word-splitting for the whole body so an unquoted `$paths` split on `|` rather than whitespace.
*   **It is uniquely dangerous between seats**: the output is a confident accusation that another lane's
    work is broken. Twice it was one message away from being sent.
*   **Redirection — do not "be careful" with the loop; do not use the loop.** Compute the inputs into a
    file with a `for` loop, then do the comparison in Python reading that file, or run the whole
    comparison in Python. A `for` loop over command substitution does not exhibit this.
*   **Distinct from `¶PTF_A_BACKGROUNDED_COMMAND_LOSES_ITS_PIPE`**: that one loses the pipe, this one
    loses the environment inside an intact pipe. Both report success-shaped output.

## [2026-10-23 00:36:10] ¶PTF_AUDITING_A_STRUCTURAL_ELEMENT_BY_ITS_VOCABULARY_COUNTS_PROSE_AS_COMPLIANCE

**When asking whether a set of pages carries a structural element, match a string only that element's
own markup produces — never the element's vocabulary — and state which pattern produced the number.**
A word used in prose for an unrelated reason reports a non-compliant page as compliant.

*   **Measured 2026-10-22 over 11 published pages.** Asking which carried a retirement banner, the
    pattern `retired|retirement|superseded` returned non-zero on **9**. The true count was **7**. The two
    false positives were prose: one page discussing a retired *spelling* quoted from a compiler refusal,
    another discussing a retired *method* in a named commit.
*   ⛔ **And the designated control was itself one of the false positives.** The page handed over as the
    control proving the pattern had no false positives was a page whose only hit was prose. **A control
    drawn from the same vocabulary as the instrument shares its defect.**
*   **The instrument that worked**: three independent signatures the banner's own markup emits — its
    title string, its body string, and its inline `background:#fdf6ec` — agreeing exactly on 7 and 0,
    with `<!doctype html` firing on all 11 as the positive control and a nonsense sentinel silent on all
    11 as the negative.
*   **State the pattern with the count.** Two true answers to two different questions look identical as
    numbers: `grep -c` counts matching *lines*, `grep -o | wc -l` counts *occurrences*. A reported 2
    against a reported 3 over the same bytes was exactly this, and settled as a non-finding once both
    patterns were stated.

## [2026-10-23 00:36:20] ¶PTF_A_LENGTH_FILTERING_EXTRACTOR_CANNOT_PRODUCE_A_COUNT_OR_AN_ABSENCE

**A text extractor that drops units below a minimum length must never be used to produce a count, or to
support a claim that something is absent** — because the filter removes exactly the shortest units, and
the shortest units are what headings, labels and field names are.

*   **Measured 2026-10-22**: an extractor with a **25-character minimum** silently dropped the
    **24-character** heading `Being wrong continuously`, turning six short-edition sections into five and
    making a false *"the short edition states none of it"* claim look like a clean result. The dropped
    section in fact stated the absence in a sentence and carried the vocabulary split the claim denied.
*   ⭐ **The error looked clean because the comparison arm was unaffected** — the long edition's headings
    are all longer than the threshold, so its count of 23 was correct. **A threshold that bites one side
    of a comparison and not the other produces a plausible ratio and a false conclusion.**
*   **Caught by a second pass re-running the extraction, not by the author.** The finding survived,
    narrowed; the "says nothing" claim did not.
*   **Redirection**: when a count is the deliverable, extract with no filter and filter afterwards if at
    all — and name the threshold next to the number so a reader can see what it could not see.
