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

*   **¶PTF_ENGINE_ROOT_CONFIG_NOT_LINKED**: setup links engine SUBDIRS but not the loose config FILES at the engine root
    *   **Context**: `setup_engine_symlinks` links `~/.claude/{.directives,agents,scripts,hooks,skills/*,tools}` → active engine. Hooks/scripts source the hardcoded path `$HOME/.claude/engine/config.sh` (and read `guards.json`).
    *   **Trap**: `config.sh` and `guards.json` live at the engine ROOT, not in a linked subdir — so setup never links them. In local mode this is invisible (`~/.claude/engine` IS the git checkout, files physically present). But a remote/consumer install has no checkout: setup points the subdir symlinks at GDrive yet leaves `~/.claude/engine/` a stray real dir, so the two config files are simply ABSENT → every hook that sources them fails (compounded by `¶PTF_BASH32_COMPATIBILITY`, which makes the absence a silent fatal).
    *   **Mitigation**: setup now symlinks `config.sh` + `guards.json` from the active engine into `~/.claude/engine/` when the active engine lives elsewhere (skipped in local mode to avoid a self-link). `engine.db` (gitignored) and `.migrations` (machine-specific) are deliberately NOT linked — Drive-synced SQLite risks corruption; migration state differs per machine.

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

*   **¶PTF_DEFINCH_SCOPE_IS_THE_WHOLE_TREE**: De-finching a promoted skill by cleaning only the *explicitly-marked* items leaves domain content in everything unmarked
    *   **Context**: Promoting a project-local skill (e.g. `/council`) to the shared engine requires stripping project-specific content. A roster/index may `finch-local`-mark a couple of items — those marks are a *starting point*, not the full surface.
    *   **Trap**: Scoping the de-finch to only the marked items (2 personas) passes a narrow check but leaves insurance/finch framing in the *unmarked* siblings (other personas' examples, a persona's whole worldview), plus project-local hardcoded paths (`.claude/skills/<skill>/…` — which then resolve against the wrong cwd once relocated). The result looks promoted but silently role-plays the old domain and can even fail to load.
    *   **Symptom signature**: A post-promotion `grep -rinE 'finch|<domain-nouns>|apps/web|.claude/skills/<skill>'` over the WHOLE relocated tree returns hits the author "consciously left as out of scope."
    *   **Mitigation**: Treat de-finch scope as the ENTIRE tree, not the marked list. Verify with a full-tree grep for domain nouns AND project-local path literals, and run an adversarial pass (`/scrutinize` / a `critiquer`) whose explicit goal is "find residue" — a builder scoping to the named items will miss the rest by construction. Relocated skills must reference their own assets *relative to the skill dir*, never via a project-rooted `.claude/…` path.
