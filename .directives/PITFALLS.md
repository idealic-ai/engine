# Hook & Engine Pitfalls

⚠️ **Provenance of the entries landed on 2026-10-23: the author is unknown, and that is a
measurement rather than a placeholder.** Every live seat was asked and eliminated, each on its own
record, so whoever wrote them is a session that has since ended. They were kept rather than reverted
because the rules are sound and nobody can reconstruct them, and the attribution was recorded as
`unknown` rather than guessed. **Which entries**: the ones carried by the commit that also carries
this paragraph — `git show --stat` on it is the measurement, and no number is written here, per
`§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP`. The elimination of the live seats is the ruling
session's finding, held in its own register; this file carries the conclusion, not the workings.
**The note retires the moment a seat claims any of them** — a claimant is exactly the observation
that would make `unknown` wrong, and none had arrived when this was written at 15:13 on 2026-10-23.
A file that warns this much about provenance cannot carry a hole in its own and leave it to be
inferred.

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

*   **¶PTF_PENDING_PRELOADS_STALE**: a preload that is DELIVERED without being RECORDED is re-delivered on every tool call — reachable by a bookkeeping bug and by an ordinary one-line edit
    *   **Context**: When hooks add files to both `pendingPreloads` and `preloadedFiles` simultaneously
    *   **Trap**: `_claim_and_preload` skips files already in `preloadedFiles` (dedup) but the skip path never removes from `pendingPreloads`. Stale entries remain forever — causing repeated re-delivery on every tool call.
    *   **Mitigation**: Track stale entries and clean them from `pendingPreloads` even when nothing new is claimed
    *   **Trap — the authoring form: A CHANGE TO THE SessionStart PRELOAD SET IS AN EDIT IN EVERY FILE THAT HOLDS A COPY OF THE LIST, NEVER ONE — AND THAT SET OF FILES HAS GROWN EVERY TIME ANYBODY COUNTED IT.** *(The heading used to say "four edits in four files". A fifth site then turned up, which is the entry's own subject happening to the entry; the count is gone rather than incremented, per `§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP`.)* Each site answers a different question, and an author who knows only the first has a change that looks finished:
        1.  `hooks/session-start-restore.sh` — the standards print loop. **Delivers the bytes.** It now iterates `get_session_start_seeds`, so it holds no list of its own.
        2.  `scripts/lib.sh:get_session_start_seeds` — **what PostToolUse dedup reads.** A path delivered but missing here is recorded nowhere, leaving the preload rule free to re-deliver it for the rest of the session, **and the cost per re-delivery is the file's whole size** — `wc -c` on this file gave 72,731 bytes at 11:45 on 2026-10-23 and 78,147 by 12:10, because writing this entry grew it. ⭐ **Run the size; never quote one.** Recording a size here *changes* it, so every number written in is behind before it is read — **the regress is the argument, and chasing it is the mistake.** An in-hook append onto `PRELOAD_SEEDS` ahead of the flush registers a path too, so **reading the array alone can undercount**; `docs/TOC.md` arrives that way. `PITFALLS.md` is no longer seeded: on 2026-10-23 the operator moved it to on demand, represented at session start by an index that `generate_pitfalls_index` builds from the file.
        3.  `scripts/session.sh:ACTIVATE_SEEDS` — **what activation seeds.** Now a call to `get_session_start_seeds`, not a second list; it used to be held in lockstep **by convention, with nothing enforcing it.** Update one and not the other and the tree boots one way and activates another — a sharper failure than a stale doc, because both halves are live code and neither looks wrong on its own.
        4.  `scripts/tests/test-preload-seed.sh` — now derives its expected set from `get_session_start_seeds` instead of holding counts.
        5.  `scripts/tests/test-preload-pipeline.sh` — ⛔ **the site that was never counted, and it was a TEST THAT COMPOSED ITS OWN COPY OF THE LIST** (it now derives its fixture from `get_session_start_seeds`). At `:56-58` it builds a six-element seed array with a literal `jq -n` and writes it into a fabricated `.state.json`, then asserts against that fixture: `assert_eq "6" "$before"` (`:110`), `"grew from 6 to 7"` (`:124`), `"(6 seeds + AGENTS.md)"` (`:207`), `"preloaded still 6"` (`:280`), under a file comment reading *"where preloadedFiles stays stuck at 6 seeds despite delivery"* (`:6`). ✅ *Site, line numbers and literals confirmed by reading the file; the live set's size is relayed and deliberately not restated here — run the print loop, per the ⭐ above.*
        6.  `scripts/tests/test-session-start-skill-delivery.sh` — **a sixth copy, missed by the five-site count.** Its test 9 asserted by literal content that `SIGILS.md` and `CMD_PARSE_PARAMETERS.md` were preloaded. It now derives the set from `get_session_start_seeds`. **The parity test** — the files the hook prints equal the list it records — is `scripts/tests/test-session-start-preload-set.sh`; the branch's own parity test, `test_standards_print_loop_matches_seed_list` (`df245d3`), was dropped at the merge with main because one array now feeds both the print loop and the record, so there are no longer two lists for it to compare. The Stop hook's atom, `¶CMD_CONTINUE_ON_STOP`, is defined inline in `COMMANDS.md`, so it is in context from SessionStart rather than arriving on the first stop.
    *   ⛔ **The instance is this rule's own tree, and it closed while the rule was being written.** At **11:45 on 2026-10-23** the sites disagreed: the print loop injected 8, `get_session_start_seeds` held 7, `ACTIVATE_SEEDS` (`scripts/session.sh:599`) held 7 with `PITFALLS.md` absent, and `test-preload-seed.sh` asserted 7 and 8 — because the lane that added `PITFALLS.md` to the print loop held a two-file partition and **could not reach sites 3 or 4.** By **11:58** all four agreed at 8: other seats landed `lib.sh` at 11:48, the test at 11:49 and `ACTIVATE_SEEDS` at 11:50.
    *   ⭐ **Both halves are the evidence, and the second is the stronger.** A gap that takes three further files and other people's hands to close is a gap worth a rule — and **those thirteen minutes are its cost**: through them the tree booted one way and activated another with nothing reporting the disagreement. ⚠️ The counts above are pinned to a **clock time, not a date**, because a fact that moves in minutes cannot be stamped by a day — and this entry's own first draft was stale within quarter of an hour of being written.
    *   ⛔⛔ **AND THAT CLOSURE WAS PREMATURE, WHICH IS THE SHARPEST THING IN THIS ENTRY: the inventory was wrong, so "all four agreed" was a true statement about an incomplete list.** Site 5 above sat uncounted through the whole reconciliation — audited by two lanes and the conductor, none of whom had it on the list. **An inventory of duplicated-fact sites must include the tests**, and the reason is asymmetric: **a production copy drifts into a FAILURE, a test copy drifts in SILENCE.** ⭐ **A test that composes its own copy of the list it tests has no instrument pointed at the list** — site 5 fabricates its fixture rather than reading the live set, so the live set could double and nothing there would redden.
        *   ⚠️ **Stated precisely, because the obvious wording overclaims and the precision is the useful part.** Site 5's assertions are **not** vacuous: they genuinely exercise the dedup mechanism — delivery grows the count by one, redelivery skips — and that is a real property, correctly covered, legitimately green. **The suite is a live instrument for the MECHANISM and a dead one for the INVENTORY**, while its comment and its assertion names (*"starts with 6 seeds"*, *"stuck at 6 seeds"*) read as though it covered both. That is why nobody suspected it: there was nothing wrong to find in the part it tests.
        *   ⛔ **The green was then spent on the wider question, and whose hands it passed through is part of the instance rather than a detail to spare anyone.** A 31/31 pass was cited as evidence about the seed inventory **twice in one day by the conductor**, who had not read what the suite asserts, and once by the very lane that reconciled the other four sites. *Figures relayed from a review lane; the conductor's own record of it is itself a correction.* ⭐ **The remedy was already written in this file and available to all three** — `§PTF_CORRECTNESS_THAT_TERMINATES_A_SEARCH`: *for any green, name the observation that would have been different had the thing been broken.* Here the answer is *none, about the inventory* — and the question was not asked, by anyone, including after reading it.
        *   ⚠️ **Was stated, not enforced.** Nothing reddened when a test composed its own copy of a list; no invocation compared site 5's fixture to the live set. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`. **Since built**: the fixtures derive their seeds from the function site 2 reads, and `scripts/tests/test-session-start-preload-set.sh` fails if the set the hook prints differs from that function's output. A self-composed fixture is the defect, not the stale number inside it.
    *   **Mitigation**: change the set in `SESSION_START_SEED_FILES` (`scripts/lib.sh`), the one list the sites above now read, and treat `docs/PRELOADS.md` as another whenever it states a count — it no longer states one, which is the durable fix rather than a correction. **A new copy of the list, in a hook or a test, is the defect to look for**; run `test-session-start-preload-set.sh` and check every in-hook append. On the same day `docs/PRELOADS.md` said six in fifteen separate places while the hook injected eight, and it was clean in git throughout, so nothing anywhere disagreed with it. A set that prints more than it registers is the defect, and no gate reports it.

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
    *   ⛔ **The same defect in a GUARD rather than a cleanup, and the docblock is what stops anyone checking: A GUARD THAT WALKS ONE DIRECTORY LEVEL IS SILENT OVER EVERY NESTED PACKAGE.** A roster or inventory check that enumerates one level reports on that level truthfully and says nothing about a package nested below it — so a tree whose nested packages are entirely unchecked reads as a checked tree. ⭐ **What makes it durable is not the traversal, it is the DOCBLOCK: a comment that reports the parent's state as the subtree's converts the gap into a documented guarantee**, and a reader who meets that sentence has no reason to look further. Same family as the entry above — the scope you checked is narrower than the scope that matters — and the same remedy: state the traversal depth in the guard's own output, so a green names the levels it covered (`§INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO`). ⚠️ **Stated, not enforced** — nothing compares a guard's declared scope to its actual traversal.

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
    *   ⛔ **A third manufacturer, and the easiest to walk into: OPTIONAL WHITESPACE INSIDE A MULTI-TOKEN PATTERN.** Measured on a review lane's own integrity pass: `grep -c "prefers-color-scheme: dark"` returned **0** on a page that carried all three theme states, **because the page omits the space after the colon.** The lane's own words — *"the instrument moved and reported absence, and the absence was in the pattern."* *Relayed, not re-run.* ⭐ **Any corpus whose whitespace is optional is this trap**: CSS and at-rules, minified or formatted output, JSON, YAML flow style, SQL. **Search one side of the separator** (`prefers-color-scheme`) and read the hits, or match the gap (`grep -E 'prefers-color-scheme: *dark'`) — never type the spacing you would have written yourself.
    *   ⛔⛔ **A FOURTH MANUFACTURER, and the only one that is a property of the TOOL rather than of the pattern: THE DEFAULT `grep` HONOURS `.gitignore`.** Here `grep` resolves to a **shell function** from the Claude shell snapshot which re-invokes the claude binary as **ugrep** with a fixed flag set including **`--ignore-files`**, so it obeys `.gitignore`. A recursive search from a repository root therefore **silently skips every ignored tree and returns 0 hits at exit 0**. ✅ **Measured 2026-10-23 in `~/Projects/kit`, four readings, control first, stderr NOT suppressed**: a tracked-file string from `.` → **2**, so the traversal is *not* failing; an ignored-tree string from `.` → **0**; the same pattern with **`--no-ignore-files`** → **30**; the same pattern with the path named → **30**. The only variable that moves the count off zero is whether the ignored path is reached. **Independently reproduced by a second seat on its own tooling**, with `type grep` confirming the shell function — fleet-wide, not a BSD quirk.
        *   ⭐ **Why it outranks the three above**: those are properties of the PATTERN, so re-reading what you typed can catch them. This is a property of the TOOL'S DEFAULT FLAGS, **invisible in the command you typed** — nothing in `grep -rl foo .` says it declined to enter half the tree.
        *   ⚠️ **And it hides better than its git sibling.** On a gitignored path `git status` is simply out of scope and prints nothing that reads as a measurement (`§INV_ESTABLISH_THE_SUBJECT_IS_IN_SCOPE_OF_THE_CHECK`); a **zero-hit grep looks exactly like a result and exits 0**. The cost is specific: session directories are routinely gitignored — `sessions/` at `.gitignore:79` in kit — and **session artifacts are most of what a lane cites**, so any absence claim taken from a repo root about one is unproven.
        *   **Redirection — NAME THE SUBTREE.** That is the practical remedy. `--no-ignore-files` is correct but walks the ignored trees too, `node_modules` included: from this repo's root it **exceeded 120s** where the path-named form returned instantly. And **brace the zero with a control that lands INSIDE the ignored tree** — a control over tracked files passes while the blindness persists, which is `§INV_A_CONTROL_DRAWN_FROM_WHAT_YOU_JUST_FIXED_IS_NOT_A_CONTROL`'s shape applied to traversal rather than to a fix.
        *   ⛔⛔ **THE FLAG IS `--no-ignore-files`, NOT `--no-ignore`, AND GETTING THAT WRONG MANUFACTURES THE EXACT ZERO THIS ENTRY IS ABOUT.** `--no-ignore` is **not a valid option**: ugrep rejects it, prints a suggestion list to stderr and **exits 2 with no matches**. Under a habitual `2>/dev/null` that is indistinguishable from a true zero — *and from a working `--no-ignore-files`*, so it reads as *the ignore rules were not the cause*, which is the opposite of the truth. ⭐ **Measured by this entry's own author while verifying this entry**: the first draft prescribed `--no-ignore` and cited a reading of **2** for it, a figure **relayed from a lane rather than run**. Re-run before committing, it returned **0** — the invalid-flag zero — and the correct flag returns **30**. **A remedy for false zeros, which was itself a false zero, caught only because the numbers were re-run rather than re-read.**
        *   ⛔ **A withdrawn first mechanism, kept because the withdrawal is the lesson.** The lane that found this first reported the wrapper *"swallows an oversized traversal and reports silence"*, inferred from `/usr/bin/grep -rIl` over the same root not finishing in 120s. That run later **completed at exit 0 and found the content**. **Slow is not broken, and a timeout is not a result.** Three absence strikes in one lane in one evening — a pattern (a sentence missed to a hard line-wrap), an instrument (this one), and **a plausible story about the instrument** — plus the author's own fourth above. A zero is not evidence; neither is a slow command; neither is a confident mechanism for a zero you have not isolated.
        *   ⚠️ **Stated, not enforced** — nothing reddens when a root-recursive grep backs an absence claim, or when an invalid flag is silently swallowed by `2>/dev/null`. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
    *   ⛔ **A FIFTH MANUFACTURER, and it eats the very corpus it is pointed at: A MARKDOWN BULLET RENDERS IN A DIFF AS `-- `, SO `grep -E '^[-+][^-+]'` EXCLUDES ITS OWN TARGET.** The idiom exists to read a diff's changed lines while skipping the `---`/`+++` headers, and it does that by requiring the character after the marker **not** to be `-` or `+`. A removed markdown bullet is `-` (the diff marker) followed by `-` (the bullet), so the pattern drops **exactly** the lines a directive-file or documentation diff is made of — and drops them silently, leaving a plausible short list rather than an error. ⭐ **The tell is a diff you know is large returning a handful of lines, all of them prose.** **Redirection**: anchor on the marker alone (`^[-+]`) and exclude the headers by their full spelling (`^---`/`^+++`), or read `--numstat` for the shape and the diff for the content. ⚠️ **Stated, not enforced** — the pattern returns a clean subset, so nothing reddens. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
    *   ⛔ **A SIXTH MANUFACTURER, and the only one whose source answered correctly: AN UNANCHORED, CASE-WRONG MATCH OVER OUTPUT THAT WAS RIGHT.** The tool did not fail and did not lie — it was MISCOUNTED, which tells the same lie as an error with none of an error's warning signs, because every row still looks like a successful reading. ✅ Over `engine lane-stall . --all --minutes 30`: an anchored count gives **STALE=147, ok=7** across **154** lanes, while a case-sensitive substring `/stale/` over the identical captured file matches **0** and the lowercase-folded form matches 147 — an unanchored wrong-case pattern turned 147 stalled lanes into a clean fleet. ⭐ **The `ok=7` arm is the control and it is what makes the zero diagnosable**: the instrument plainly reads rows, so the zero is a property of the pattern's case and of nothing else. *Figures relayed from the conductor's run; verified here is the mechanism — `scripts/lane-stall.sh` prints the flag as the line-LEADING field and spells it `STALE` / `RETIRED` / `ok`.* **Redirection: anchor every count on the producing tool's documented line prefix** (`^STALE`, `^ok`), never a substring — a prefix is part of the tool's contract, a substring is not, and these rows also carry `state=`, `retired=` and a `logpath=` whose text you do not control. Then **cross-check the count against the tool's own summary line**: `lane-stall` prints `lanes=N retired=M` and exits **3** when anything is stale, so a zero beside exit 3 is a contradiction the tool hands you for free. ⚠️ And that cross-check is exactly what `§PTF_A_PIPELINE_REPORTS_THE_LAST_COMMANDS_STATUS` destroys — read through `head` or `wc`, the 3 becomes the pager's 0 and the free contradiction disappears.
    *   **Symptom signature**: A zero that is *convenient* — it confirms the hypothesis you already had, or it makes a plan step unnecessary. Also: a zero about something the surrounding code clearly depends on. Both are tells; a genuine absence is usually surprising, not tidy.
    *   **Mitigation**: **Open the file before reporting a zero.** A negative claim costs one Read to confirm and costs a wrong diagnosis if you skip it. Search for the *shortest distinctive stem* (`recordReceipt`, `State doc`) rather than the full formatted phrase, and grep case-insensitively when the identifier could be emphasized or wrapped. When the negative is load-bearing — it changes a plan, a report, or a ticket — confirm by reading, then say *how* you confirmed. Cross-ref `§PTF_SILENT_NO_OP_TOOLING` (same class: a confident false zero, there from repo-root-relative paths rather than pattern shape).

*   **¶PTF_HEAD_MOVES_UNDER_YOU**: On a shared branch, `HEAD` read in one tool call is not `HEAD` in the next — and a commit-rewriting operation aimed at "my last commit" can land on someone else's
    *   **Context**: Any operation that modifies an existing commit rather than adding one — `git commit --amend`, `rebase`, a reset that discards a commit — on a branch several agents/lanes are committing to. Especially after a gap: filling in a checklist, writing a debrief, waiting on a subagent.
    *   **Trap**: The mental model is "the commit I just made is the tip". On a shared branch it stops being the tip the moment another lane commits, and nothing notifies you. A real instance: an amend was prepared to add an `engine doctor` result to a commit message; `rev-parse HEAD` — run out of habit, not suspicion — showed HEAD had advanced to a sibling lane's commit during the intervening checklist work. The amend would have rewritten **their** commit, silently, with the original recoverable only from reflog. The window was a few minutes of ordinary non-git work.
    *   **Symptom signature**: There is none before the fact — that is the whole problem. Afterwards: a sibling lane's commit carrying your message, or a branch whose history no longer contains a commit someone else made.
    *   **Mitigation**: **Re-read `git rev-parse HEAD` immediately before any commit-rewriting command and compare it to the sha you actually intend to modify** — never rely on a sha captured earlier in the session, and never say "HEAD" when you mean a specific commit. When the target is no longer the tip, do not rewrite: prefer an **additive** fix (a follow-up commit, or `git notes` — with the caveat below) which is safe regardless of what landed on top. ⚠️ **`git notes add`/`append` is additive but NOT concurrency-safe, which matters precisely here because this entry's whole context is several lanes committing to one branch.** Two lanes adding a note to the same object race on the notes ref and one write is lost, with nothing reporting it — the same shape as this entry's own trap, one level down. Land a note through a read-modify-`update-ref` compare-and-swap on `refs/notes/*` so a lost update is refused rather than silent, or prefer the follow-up commit, which git serialises for you. *(Rule relayed by a `domain:Studio` lane and verified here only as a contradiction with this line's previous wording — the CAS remedy itself is not measured.)* Cross-ref `§INV_NO_DESTRUCTIVE_GIT` (this is its write-side companion) and `§PTF_DIRTY_TREE_DEFEATS_ATTRIBUTION` (the read-side sibling: that one is about misattributing a diff, this one about overwriting a commit).

*   **¶PTF_A_GIT_READING_ANSWERS_THE_QUESTION_ITS_SPELLING_ASKS**: Two git commands that look like they ask the same thing often do not, and two spellings of one command often return incomparable answers. Both produce a confident reading about a commit that is wrong in a way the output cannot show.
    *   **Context**: Any claim about where a commit lives or whether two commits are the same work — "this is the only copy", "that never landed", "these are identical" — on a repository with many branches and remotes.
    *   ⛔ **Trap one, the wrong question.** `git merge-base --is-ancestor <sha> origin/main` answers **"not on main"**. It does **not** answer **"not on any remote"**, and the two are routinely conflated because the alarming reading is the one that feels like diligence. Use `git branch -r --contains <sha>` for the second question.
        *   **Measured 2026-10-24, two seats independently**: both concluded that four commits were single-copy, each from `--is-ancestor` exits. `git branch -r --contains` put all four on `origin/invizko/reactor-preserve-20261023`. The gap is wide rather than an edge case — `git branch -r --no-merged origin/main | wc -l` → **66**. On `426e3186e`, `--is-ancestor` exits 1 while `--contains` finds it on a remote branch.
        *   ⭐ **And the specimen must come from `--no-merged`, not from a guess.** A verifying lane's first candidate was `5df9b34f9`, the tip of `origin/feature/reactor` — which turned out to be **on** main, exit 0, and would have demonstrated nothing. A rule about a wide gap needs a specimen drawn from the gap.
    *   ⛔ **Trap two, incomparable spellings of one question.** A patch-id is only comparable against the **same spelling**. On one commit, measured: `git show --text <c> \| git patch-id --stable` → one id · `--unstable` and bare → a second · `git format-patch --stdout -1 \| git patch-id --stable` → a third · `git diff <base> <head> \| git patch-id --stable` → a fourth. A path-scoped form (`git show --text <c> -- <dir>`) gives yet another.
        *   **The cost is specific: a mismatched spelling manufactures a false CONTENT mismatch that reads as evidence against a peer.** Measured — a resolved commit's two stated ids failed to reproduce until the owner's own spelling was found, at which point both matched exactly. ⭐ **What saved it was that BOTH stated ids failed**: one failing points at the commit, two failing points at the method.
    *   **Mitigation**: name the question before the command, and **state the spelling beside any patch-id you publish** so a reader with a different one gets a mismatch they can diagnose rather than believe. Where a count of remotes is the claim, cite `--contains`; where "not yet on the trunk" is the claim, `--is-ancestor` is correct and should say so.
    *   **Distinct from `§PTF_PROVE_THE_INSTRUMENT_RAN`**: there the instrument never ran or ran elsewhere. Here it ran correctly and answered a neighbouring question, so a positive control fires and proves nothing. Same family as `§PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION`, in git's vocabulary.
    *   ⚠️ **Stated, not enforced.** Nothing reddens when `--is-ancestor` backs a no-remote claim, or when a patch-id is published without its spelling. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

*   **¶PTF_PROVE_THE_INSTRUMENT_RAN**: A measurement aimed at the wrong target, or one that never executed at all, returns the same clean result as a measurement that ran and found nothing wrong
    *   **Context**: Any check whose result is about to become a claim — a sweep for remaining references, a test suite proving a fix, a probe proving a behaviour, a count backing "N files". Distinct from `§PTF_A_ZERO_IS_NOT_EVIDENCE`, which is about a pattern that RAN and failed to match; this is about an instrument that ran somewhere else, or did not run.
    *   **Trap**: Ten instances in one session, every one green, none a reasoning error:
        *   **Wrong tree** — swept `.claude/skills` for a renamed reference on the working branch, where that path differs from the PR's base; `2>/dev/null` ate the error. Reported "no project-local copies" to the user; a reviewer then found three. The sweep returned empty for the wrong reason.
        *   **Wrong store** — a proof publish from a session directory that resolves under more than one project takes whichever project's `.env` the helper reaches first. Pin `PROVE_S3_ENV` to the intended project's `.env` in every brief that publishes. Without it the upload lands in the other project's store and still exits 0 with a content-verified read-back, so nothing refuses it. Measured 2026-10-23: a refresh lane's first proof went to finch's MinIO on :9010 because its brief omitted `PROVE_S3_ENV`, and the page key stayed there for the operator to decide on. The same trap was recorded on 2026-10-18 and hit another lane's page in between.
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
*   ⛔ **A plant that breaks the module's LOADING is reported as "no tests", not as red.** A planted defect severe enough to stop the module importing gives vitest no cases to run, and a run with zero cases is not a failing run — so **a green-looking plant run can be a load failure**. Check the run actually executed the cases before reading its colour. Same family as the inert mutation above and a different mechanism: there the edit touched nothing that runs, here the edit stopped anything from running at all, and the harness reports the second as success. *Relayed from another fleet's IDE-18 lane and its reviewer, whose grep against this file was run; I did not re-run their drill.* ⚠️ **Stated, not enforced** — nothing compares a plant run's case count against the baseline's.
*   ⛔ **Where a property is held by MORE THAN ONE LAYER, a plant on one layer stays green — so plant every layer before calling a drill blind.** Redundant enforcement is the thing that makes a single-layer plant uninformative, and it is invisible from the plant site. Measured by that lane on its own system: the spend ceiling is held by **both** the pickup gate and the drain's allowance read, and double-running is prevented by `SKIP LOCKED`, the status filter, **and** holder hooks minted only for assigned jobs — so a plant on any one of those passes while the property still holds. ⭐ **The tell is a green plant on a property the system is proud of**: the properties most worth drilling are the ones most likely to be defended twice. *Relayed, not re-measured here.* ⚠️ **Stated, not enforced.**

**Reason**: captured 2026-09-12 across three sessions. ⭐ **The load-bearing half is not the mechanism, it is the indistinguishability**: an inert mutation reads exactly like a genuine survivor, a truncated list reads exactly like an absence, and a stale symbol reads exactly like a typo. In each case the wrong conclusion is the confident one, and acting on it destroys something that works. Related: `§PTF_A_ZERO_IS_NOT_EVIDENCE` and `§PTF_PROVE_THE_INSTRUMENT_RAN`, which this generalises — both are special cases of an instrument aimed at a question adjacent to the one being asked.

## [2026-09-12 20:12:15] Addendum to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — a fourth instance, and the filter variant
*   ⛔ **A FILTER TOO NARROW TO RECOGNISE A REPAIR AS THE SAME KIND OF REPAIR.** ✅ MEASURED 2026-09-12: checking whether a dirty file carried another lane's work, a diff filter excluding the known repair keywords returned one line that looked foreign — a path correction in a package we had never touched. **It was a fifth instance of the SAME repair**, in the same edit, at the same minute. One message away from telling a peer the file was mixed and handing them a false ownership answer.
*   ⭐ **The generalisation, `domain:Scope`'s and better than the instance**: *a filter too narrow to recognise a repair as the same kind of repair is the same failure as a search too narrow to see its own subject.* **And the only thing that catches it is re-reading the tree rather than trusting the filter.**
*   ⚠️ **Why it belongs here rather than beside `§PTF_A_ZERO_IS_NOT_EVIDENCE`**: the filter was not wrong and returned no zero. It answered *"which lines lack these keywords"* truthfully, while the question being asked was *"which lines are not mine"* — adjacent, and not the same.
*   ⛔ **AND THE ECHO HABIT THAT COMPOUNDS IT, committed three times in one session**: writing `echo "(empty = clean)"` AFTER a command, so the label asserts a conclusion before anyone has read whether the output was empty. **All three times output followed the label.** The label is written while predicting the result, which is exactly when it is worth nothing.
*   ⭐⭐ **WHERE THE LABEL GOES — the positive form, because the prohibition above demonstrably does not fire.** Recurrence measured 2026-10-23: a thread that had read this entry an hour earlier committed the habit **three more times**, and the lane sent to strengthen this very clause committed a fourth within minutes of reading it. Four more instances against a standing *never* is evidence about the instruction, not about the agents. The form that is checkable: **a label asserting what output MEANS belongs AFTER that output, inside the sentence that spends the value — never in an `echo` placed before or beside the command.** An `echo` may carry the command, the pattern or the question; it may not carry the answer. Print the count or the lines and let the sentence that uses them draw the conclusion. **Two tells that you are doing it anyway**: the label sits in a different tool call from the output it describes, or it would print unchanged if the command's result flipped.
*   ⭐ **A THIRD TELL, and it is the one that survives into a durable file: THE LABEL NAMES A DIFFERENT SUBJECT THAN THE CONDITION TESTS.** Measured on this entry's own neighbour at 14:13 on 2026-10-23: a probe written `if [ -f "$d/.git" ] … else echo "path absent"` printed *path absent* for a directory that **was present** and merely had no `.git` — the test asked about a file inside the path, the label spoke about the path. The false sentence was then **written into a pitfall entry and landed**, where it read as a measurement because it was one, of something else. ⛔ **Caught by a peer lane re-running it, not by its author** — and the author had read this clause an hour earlier. ⭐ **The cheap fix is to print the subject beside the verdict** (`dir:present .git:ABSENT`), which makes the two questions impossible to conflate; a bare branch label cannot distinguish them and never says so.
*   ⛔ **THE NAMED COST, which is not embarrassment — it is a manufactured green on the one property the work rested on.** Of those three: `(above: empty means PITFALLS is named nowhere)` printed over non-empty output; `(empty diffstat = lib.sh is at HEAD, untouched)` printed over **54 foreign insertions** — a false ownership answer about another seat's file; and `MATCH — dedup keys agree` computed from **two empty strings** after a suppressed `source` failure, where **key agreement was the exact correctness property that thread's edit depended on, and the label asserted it while neither side existed.**
*   ⚠️ **That third one is a variant needing its own guard: an equality label is vacuously true when both sides are empty.** `MATCH`, `agree`, `identical`, `in sync` assert a difference collapsed to zero and cannot distinguish *equal* from *absent*. **Print the two values beside the verdict**, never the verdict alone — and if either prints blank, the reading is an instrument fault, not a match. Same mechanism as `§PTF_AN_INSTRUMENT_BUILT_ON_A_DIFFERENCE_FAILS_SILENTLY_WHEN_THE_DIFFERENCE_COLLAPSES`.

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
*   ⭐ **AND THE SHAPE THAT NEEDS TWO READINGS RATHER THAN ONE RE-RUN — a DISPOSITION claim.** *Stale* · *abandoned* · *nobody needs this* · *that checkout is dead* are not observations, they are **predictions about whether something will change again**, and a single reading cannot carry one: the empty directory above read identically for *"has not written yet"* and *"will never write."* **The cheapest instrument that separates a dead checkout from a live one is two readings separated in time, with the clock printed in the same invocation as the reading** — same command, twice, and the timestamps beside the values rather than remembered. One reading plus confidence is the thing it replaces. *Relayed: four minutes bought the second reading, and it overturned a row that had survived four hand-overs and three corrections — a figure I did not re-run.*
    *   ⚠️ **Print the clock in the same invocation, not in the sentence afterwards.** A reading whose time you supply from memory is `§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP`'s fabricated-timestamp case wearing a second reading's clothes, and two readings whose separation you cannot evidence are one reading.
    *   ⚠️ **Stated, not enforced** — no invocation reddens on a one-reading disposition claim. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
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
*   **The tell is CPU time — OF THE PROCESS TREE, never of the one process you grep for.** A job whose
    **tree** has consumed seconds over minutes is stalled, not slow. The same reading taken on the parent
    alone carries nothing. *(The original figure here — 1.8 seconds across eleven minutes — was recorded
    without saying which of the two it measured, so read it as the shape and not as a tree reading.)*
    *   ⛔ **A parent waiting on a busy child reads as perfectly stalled.** ✅ **Measured here rather than
        relayed, 2026-10-23**: a `bash` parent whose only job was to `wait` printed `TIME 0:00.00` against
        `ELAPSED 00:05` — **zero CPU over five seconds** — while its compute child printed `0:04.71` over
        the identical elapsed, both lines from one `ps`. By the tell as it was previously written that
        parent was stalled, and it was a correctly-working wait. *The incident that forced the correction
        is relayed: a `git push` at 2m44s elapsed on 0.05s CPU was called stalled, and the work was in a
        pre-push hook's child the `ps` pattern never matched.*
    *   ⭐ **The parent is structurally blind, not merely unlucky**: a child's CPU joins its parent's
        cumulative time only when the child is **reaped**, and the stalled-or-slow question is always
        asked while the thing is still running — exactly when that addition has not happened. This is
        `§INV_ESTABLISH_THE_SUBJECT_IS_IN_SCOPE_OF_THE_CHECK`: the parent's `TIME` field cannot speak
        about a live descendant at all, and prints a reassuring zero whether or not one exists.
    *   **The instrument, one invocation**: `ps -o pid,ppid,time,etime,comm -g "$(ps -o pgid= -p <pid> | tr -d ' ')"`
        prints every process in the group with its own CPU beside its own elapsed, so a burning descendant
        arrives on its own line. `pgrep -P <pid>` reaches one generation; the group reaches the tree.
        **Read the lines, not a sum** — summing reproduces the original error in the other direction, by
        hiding which process is working.
    *   ⚠️ **Stated, not enforced.** Nothing reddens when a stall verdict is taken from a single `ps -p`.
        Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
*   **Redirection**: redirect to a real file rather than inheriting a pipe, and **wait inside the turn** with a bounded poll rather than ending the turn and returning later. If you must background across a turn, the first thing to check on return is the **tree's** CPU time, not the output file and not the parent's.
*   **The cousin already on record in the same session's handoff**: a suite run chained behind a `git log` was backgrounded whole, its output lost, and the handoff said *"re-measure"* instead of carrying a number. **Same family: a long command's output is lost to the shape of the turn, and the loss looks like patience.**

## [2026-09-17 02:10:00] Addendum 6 to ¶PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION — five instances in one night, and the test that separates them from a real green

*   **⭐ THE SHARPEST STATEMENT OF THE FAMILY YET, and it replaces "could this have failed?"**: ask ***"what would have to be true of the world for this to be green, and is that the thing I care about?"*** Every instance below had a **passing positive control**. The control proves an instrument can MOVE; it never proves what it moves in RESPONSE to. *(Credit: `domain:Scope`, reformulating a rule three sessions had each hit independently.)*
*   **The corollary, which is the one that catches a differential**: ***two derivations of one corrupted input agreeing is not corroboration.*** A gate comparing two halves cannot see them wrong in the same direction. A third reference — the ORIGINAL, not another derivation — is the only thing that can.
*   ⭐⭐ **AND THE READING THAT SAVES YOU WHEN THE CONTROL CANNOT: AN IMPLAUSIBLE CONTROL IS AN
    INSTRUMENT FAULT, NOT A FINDING.** The corollary above needs a third reference you may not have.
    What you always have is a sense of what the control's value *ought to be* — so when the subject
    and its control come back **equally improbable**, stop reading the world and read the reader.
    A control is usually consulted only for its direction (did it fire); **its magnitude is the free
    signal nobody spends.**
    *   ✅ **MEASURED HERE, and it is a trap in the RECORD rather than in a command.** A transcript holds
        **more than one** `prompt_snapshot` attachment, and the first one carries no `tools` key at all —
        so a naive read that takes the first snapshot reports a near-empty tool set for every transcript
        it touches, subject and control alike. **RAN** over the newest 25 transcripts under
        `~/.claude/projects/<project>/`: every transcript that carried snapshots carried more than one,
        the **first** snapshot's `tools` field was **absent in all 25**, and the later snapshots carried
        real tool sets. ⛔ The relayed version of this said the first snapshot has `tools: null`;
        **re-measured it is ABSENT, not null** — which is not pedantry, because `x.get('tools')` returns
        `None` for both while `'tools' in x` separates them, so whether the naive read can notice at all
        depends on which spelling it reached for. *(The figure the original lane reported — both arms at
        1/672 — is relayed; I did not re-run its instrument, only the snapshot shape beneath it.)*
    *   ⭐ **It was caught because the CONTROL was implausible too.** The read would have produced a
        dispatch-shape split between two groups of lanes that does not exist, and the thing that stopped
        it was not a failing control — the control fired correctly — but a control whose *number* could
        not be true of a working fleet. **A control that fires at an impossible magnitude has passed its
        own test and failed yours.**
    *   **Redirection**: when a record may hold repeats of the unit you are reading, **count the units
        first and print the count beside the reading**, then say which one you took and why. And ask of
        every control not only *did it fire* but *is its value one the world could produce*.
    *   ⚠️ **Stated, not enforced** — nothing reddens on a first-match read of a repeated record. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`. ⭐ *Kept on one line deliberately: an earlier draft wrapped this very marker across a line break, and the line-oriented grep verifying that every landing carried one returned a **false absence** for it — `§PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION`'s spanning-tag false zero, committed inside the check for it. Where a marker is what a grep looks for, do not let it wrap.*
*   **The five, each a different instrument answering a narrower question than its reader took it for:**
    *   **A control satisfied by the bug it was meant to catch.** `grep -qa "$(printf '\000')"` — command substitution strips NUL, so the pattern was the EMPTY STRING and matched every file. The positive control passed **for the same reason the false positive fired**. ⭐ *A control that cannot fail is not a control.*
    *   **A mutation that reddened for the wrong reason.** A malformed edit produced a `SyntaxError`, so the gate failed at IMPORT and said nothing about the behaviour under test. ⭐ *A mutation that reds is not evidence until you know WHICH arm it red and why.*
    *   **A derived check measuring its own parser.** A gate deriving expected exports from a barrel read prose inside `export { … }` braces as export names, reported 74 where 69 was right, and listed a paragraph of documentation as "absent from dist". *A derived check is only as good as its derivation; cross-check the derived number against an independent one.*
    *   **A pattern silently transformed into a different pattern.** An unescaped `$` inside a **double-quoted** grep pattern is read as an end-anchor, so `grep -- "\$ref: …"` matches nothing **and reports it as absence**. Hits every `$`-carrying JSON-Schema keyword. ⚠️ **Not a BSD quirk — `grep` is a shell function from the Claude snapshot resolving to ugrep, so the whole fleet inherits it.** Single-quote the pattern.
        *   ⛔⛔ **THE SAME MECHANISM DESTROYS A GIT REFSPEC, AND THE MANGLED REF STILL LOOKS LIKE A
            REF** — which is why it is worth its own paragraph rather than a mention. **zsh applies
            history-style MODIFIERS to an unbraced parameter expansion**, so in `"$H:refs/heads/main"`
            the `:r` is eaten as the *root* modifier and the `r` vanishes from the string.
            ✅ **RAN, 2026-10-23**, one file under zsh and under bash: `zsh -f` printed
            `unbraced: abc123defefs/heads/main` while `bash --noprofile --norc` printed
            `unbraced: abc123def:refs/heads/main`, and the braced form `${H}:refs/heads/main` was intact
            under both. The mechanism confirmed in the same run: `zsh -fc 'H=a.b.c; echo "$H:r"'` → `a.b`
            and `"$H:e"` → `c`, while `"${H}:r"` stays the literal `a.b.c:r`.
            *   ⚠️ **It is NOT history expansion, and that correction matters operationally**: history
                expansion is off in a non-interactive shell, so *"scripts are safe"* is the wrong
                conclusion — `zsh -f` with history expansion disabled mangled it anyway, because this is
                parameter-expansion syntax. **Braces are the fix**, and they are the fix in every shell.
            *   ⭐ **What makes it expensive is the failure's shape, not its cause.** `git push` answers
                `error: src refspec … does not match any`, which reads as *the ref is missing* and sends
                you to look at branches. The ref named in the error is **one character short of the one
                you wrote** and still looks like a plausible ref, so the string nobody re-reads is the
                string that is wrong. **Echo the refspec before pushing it**, or brace every
                `$var:`-adjacent expansion on sight.
            *   ⚠️ **Stated, not enforced.** Nothing reddens on an unbraced expansion followed by a colon — the shell is behaving as documented, and `git` reports a real error about the string it was actually handed. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
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
*   **⛔ Verify a hunk-isolated stage BYTE FOR BYTE, never by line set.** Compare the staged blob against the intended file — `git ls-files -s <path>` against `git hash-object <intended>`, or `cmp <intended> <(git show :<path>)` — because a line-set comparison cannot see order. Measured 2026-10-28 (PRDRAFT): a line-set check passed a stage that had one line in the wrong place. ⚠️ **Stated, not enforced** — nothing reddens when a stage is verified by line set. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-09-19 02:12:00] ¶PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP

**A mark recording THAT something was verified, and never WHEN, is worse than no mark: it buys trust it cannot justify, while an unmarked claim at least gets re-checked.** *Promoted from `resource-kernel/.directives/PITFALLS.md`; formulation by `meta:Reports`.*

*   **Trap**: a durable file — a ledger, a leftovers list, an architecture note — carries an entry tagged *"verified by me"*. It was true when written. The tree then moves faster than the file does, and **the tag is what stops anyone re-measuring.** The mark converts a point-in-time observation into a standing fact: `§INV_POINT_IN_TIME_CHECKS_EXPIRE` performed by the artifact rather than by a person.
*   ⭐⭐ **The remedy is NOT to keep the file true — every such file drifts. Put the instruction in the brief instead**: *treat every sentence above as a claim to re-measure, not a brief to act on.* **Measured across one wave of parallel lanes: every brief carried a false load-bearing claim lifted from entries marked verified — in two lanes the PREMISE itself, in the third the stated REASONS while the premise held. Every lane found a live defect the brief had not named.** ⛔ An earlier wording of this entry said all three refused their premise and scored it *three times out of three* — **a stated count, wrong about the third lane, inside the very entry warning against confidence that is not earned.** Briefing for skepticism still beat briefing for accuracy; it never needed a score.
*   **The writer's share, which the blanket instruction does not cover**: per-claim provenance — each load-bearing sentence marked *measured by me at HH:MM* / *relayed from X* / *inferred*. Three words per claim, paid by the writer, and it tells the reader **which** sentence to spend time on instead of all of them. ⛔ It must not harden into *briefs are expected to be wrong*, which is where the writer stops trying because the reader is supposed to catch it.
*   ⛔ **A fabricated timestamp is worse than an absent one.** A lane invented five plausible minutes rather than reading the clock; one became the freshness evidence inside a grant and propagated into another party's decision.
*   ⭐⭐ **COMPUTE AN AGE, NEVER READ ONE — a stamp in `Z` eyeballed against local time is wrong by the
    whole offset, silently, and in the direction that manufactures staleness.** ✅ **Measured here,
    2026-10-23**: `date -u` printed `08:16:19Z` in the same invocation as `date` printing
    `16:16:19+0800`, and `utcoffset()` returned `8.0`. Heartbeats are written in `Z`; this machine is
    **UTC+8**. Comparing the two by eye overstates every age by eight hours. ⛔ **The measured cost**: a
    false *"all three loom slot files are stale"* on a set where one had been written **two minutes**
    earlier. **The fix is arithmetic, not care** — subtract two epoch seconds (`date -u +%s` minus the
    stamp parsed as UTC) and print the difference, in the same invocation as the reading per the clause
    above. ⚠️ **Why no amount of attention closes it**: both strings are correct, both are plausible
    local times, and **the difference reads as a believable age** rather than as an error — this is
    `§PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION` wearing a clock. A staleness verdict is also a
    DISPOSITION claim, so it owes the two readings that entry's Addendum 4 requires, and an eight-hour
    offset corrupts both of them identically so their agreement proves nothing.
    *   ⚠️ **Stated, not enforced.** No invocation reddens when an age is eyeballed rather than
        subtracted. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
*   ⭐⭐ **THE MIRROR CASE, AND IT IS THE ONE THIS ENTRY WAS MISSING: A ROW ASSERTING A DEFECT OWES ITS
    INSTRUMENT, NOT ONLY ITS LOCATION.** Everything above governs a mark claiming something is *right*.
    A register row claiming something is **wrong** — a stale doc line, a false claim, an owed repair —
    rots the same way and is read far more trustingly, because a negative finding reads as work already
    done. **A row carrying only a path and a line number cannot be re-checked against a repair**: the
    path still resolves, the line still exists, and nothing in the row says what made the claim false,
    so the row survives its own subject being fixed and keeps sending people to a repaired file.
    ⛔ **Measured, relayed in part**: a row outlived the repair of its subject, which had been committed
    as `b5e3607` — *(**RAN**: `git log --oneline -1 b5e3607` → "the echo-label rule gains its positive
    form, and a doc stops stating a count", so the repair is real and dated; that the row survived it is
    relayed from the lane that found it, and the only instrument that discovered the staleness was a
    dispatched lane re-reading the subject.)* **Redirection: write the sha or the command that
    established the claim false into the row**, beside the path, so closing the row is a re-run rather
    than a re-reading. A row whose evidence is a command retires itself; a row whose evidence is a
    location cannot.
    *   ⚠️ **Stated, not enforced**, and the register-row template that would carry it is not mine to
        edit — rowed as still owed in this lane's report. Per
        `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
*   ⭐ **A COUNT IS A PROVENANCE MARK, AND IT ALMOST NEVER CARRIES ITS TIMESTAMP.** *"Eight seeds"*, *"four call sites"*, *"eleven pages"* each record that somebody counted and never when — buying the same trust this entry is about, and **a count restated in prose in more than one place is wrong in all of them at once**, because the copies agree with each other and nothing disagrees with them. The fix is not a correction: **name the command that measures it and delete the number**, and where a number must appear, **pin it to a clock time rather than a date** — a set that moves in minutes cannot be stamped by a day.
    *   ⛔ **Do not re-derive the instance here; it is already written.** `§PTF_PENDING_PRELOADS_STALE` carries the measurement — a doc stating six in fifteen separate places while the live set was eight, clean in git throughout, so nothing anywhere contradicted it — and the standing form *"Run the size; never quote one."* **This bullet exists only to join the two**, because a reader arriving with *"my document states a count"* has no reason to open an entry about hook preloads. *Both that measurement and the reported recurrence — the same defect four more times inside one lane's own edits within an hour — are relayed; I re-ran neither.*
    *   ⚠️ **Stated, not enforced** per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`. A count in prose has no failing arm anywhere in this engine; the only thing that reddens is a human reading two copies side by side.

## [2026-09-19 02:12:10] ¶PTF_CORRECTNESS_THAT_TERMINATES_A_SEARCH

**A careful, well-reasoned, genuinely CORRECT piece of work is the best available cover for a defect beside it — because it satisfies the reader who came to check and ends their search there.** *Promoted; disclosure species found and named by `meta:Reports`.*

*   **The species, none resembling the others at the point of use** — *the list is deliberately not counted, so adding one is an edit rather than a correction*:
    *   **A deliberate guard beside a careless one.** An error vocabulary collapsed two causes into one sentence *on purpose*, so a verb could not enumerate a table. Twelve lines away the results slot handed back exactly what that sentence withheld. **An auditor checking disclosure finds the deliberate refusal, reads its justification, and stops.**
    *   **A test named for the property it does not check.** A case titled *"answers for a target it could not reach, and the caller is told"* asserted density and refusal and never asked what sat in the slot. Green.
    *   **A confident heading over an honest caveat.** The caveat is true, present, and neutralises nothing: the reader acts on the heading.
    *   ⛔ **A docstring over a body that does less than it says.** A docstring is an **instrument claim about the code beneath it**, and it is the text an auditor reads *instead of* the body — so a `verify()` still status-code-only, now behind a docstring reading as if it were not, survives the review that came to check exactly that. *Relayed from another lane, not re-run.* Cousin of Addendum 3 above: there a NAME is taken for a behaviour, here a DESCRIPTION is, and in both **nobody experiences the text as an instrument**, so nothing triggers the instinct to check it. ⚠️ **Stated, not enforced** — no gate compares a docstring to its body, and the only control is to read the body and name what it would do differently were the docstring true.
    *   ⛔⛔ **A MECHANISM KEYED ON A STATE NOTHING CAN REACH — and this one does not merely terminate a
        search, it LOOKS INSTALLED.** A retirement sweep, a reaper, a cleanup pass, an auto-close: the
        code is correct, the invocation runs, the exit is zero, and **the state it fires on is unreachable
        by construction**, so it retires nothing. Nobody re-opens the question, because the mechanism is
        visibly there and visibly green. ⭐ **The distinguishing property against everything else in this
        list: the other species mislead a READER, this one misleads the SYSTEM OF RECORD** — the backlog
        stays exactly as full as before and the green is what certifies it handled.
        *   ✅ **MEASURED HERE, 2026-10-23 at 16:30 local**: a lane-state field whose `done` value fires
            only on a hand-back tool call that the lanes in question **cannot load at all** read `done`
            for **not one** lane in a whole weave, so nothing was ever retired by it. **RAN**
            `engine lane-stall <sessionDir> --all --minutes 1`, tallying the printed `state=` values; the
            header also reported `retired=0` independently. ⭐ **The control is the sibling value, and it
            is the right one**: a fifth of those same rows read `state=running`, so the field is live and
            the instrument discriminates — **the zero is specific to `done`, not a dead walk or an
            unparsed field**, and every row read carried a `state=` at all. *(No count restated, per
            `§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP`: the population moved between the relaying lane's
            reading and mine, which is exactly why the command and not the number is what is written here.
            The tool's own docblock at `scripts/lane-stall.sh:22-34` carries the finding at its site.)*
        *   ⭐ **The check that separates it from a working mechanism is not a control, it is a
            CONSTRUCTION ARGUMENT**: name the code path that *writes* the state the mechanism reads, and
            establish that path is reachable by the population the mechanism is pointed at. A control
            proves the mechanism fires when the state is present; **nothing a control can do establishes
            that the state ever arrives.** `§INV_AN_ASSERTION_WHOSE_SIDES_CANNOT_DIVERGE_IS_NOT_COVERAGE`
            asks what input would make an assertion fail; this asks what event would make a mechanism
            *act*, and an answer of *none* is the whole finding.
        *   ⚠️ **Stated, not enforced.** No invocation reddens on a mechanism whose trigger state is
            unreachable — its green is indistinguishable from a working one. Per
            `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
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
    *   ⛔⛔ **AND THE HARDER CASE, WHERE BOTH SPELLINGS ANSWER THE *SAME* QUESTION AND STILL DISAGREE.**
        Above, two numbers differ because they count different units, so stating the pattern reconciles
        them. **A `diff | wc -l` figure differs with no such excuse: a minimal edit script is not unique,
        so two correct diffs of one pair of inputs may have different lengths.** *Relayed, not re-run:
        `git show … | diff - <f>` gave **127** and `diff <captured> <f>` gave **129**, each stable over
        three runs, on inputs `cmp` called identical.* ⭐ **The sharp part is that `cmp` said identical** —
        the disagreement is manufactured entirely by the invocation, so there is no "right" number to
        find and re-running cannot converge them.
    *   **Redirection**: **a diff length is not a measurement of difference — quote sizes and hashes
        instead**, which are properties of the bytes rather than of the algorithm that walked them. Where
        a diff count genuinely must be quoted, name the exact spelling that produced it, in the same
        sentence, the way this bullet does. **Stated, not enforced** per
        `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

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

## [2026-10-23 13:55:00] ¶PTF_AN_UNTRACKED_DIRECTORY_MAY_BE_A_REGISTERED_WORKTREE

**A directory `git status` prints as untracked may be a registered worktree, and removing it does not
delete junk — it leaves the main repository holding administrative state that points at a path no longer
on disk.** A linked worktree's `.git` is a *file*, not a directory, and the half that matters lives inside
the main clone, so the bytes you can see are not the whole of what you break.

*   ⛔ **The tell is that there is none.** An untracked directory and a registered worktree are
    indistinguishable in `git status`, and the worktree's contents genuinely are an unversioned copy of a
    tree — which is exactly what makes "nothing here is tracked, so nothing can be lost" feel safe.
*   **The check is one command, before any removal**: `git worktree list --porcelain`, grepped for the
    path. ⭐ **Grep the porcelain spelling, not the human one** — the human form column-aligns and appends
    `[branch] locked`, while porcelain emits a bare `worktree <abspath>` line per entry that a fixed-string
    grep can match. *(Both forms RAN, 2026-10-23.)*
*   ✅ **Measured here rather than relayed**, in this fleet's `kit` clone. The healthy shape:
    `/private/tmp/act020/.git` is a **FILE** containing `gitdir: …/kit/.git/worktrees/act020`.
    ⭐ **Do not read the figures below as current — re-run the command.** At **14:13:41 on 2026-10-23**
    that clone registered **655** worktrees, **175** of them under `/private/tmp/` — so the population
    that looks like junk is measured in the hundreds rather than hypothetical — with **60** registered
    paths absent from disk and **26** more present but holding no `.git`. The one-liner that produces all
    four: `git worktree list --porcelain | awk '/^worktree /{print $2}'`, then test each path for `-d`
    and for `-e "$p/.git"`. ⚠️ **Pinned to a clock time, not a date, and for cause**: the registered count
    read 645, 648, 651 and 655 across twenty-three minutes while this entry was being written, measured
    four times by two parties. A date would have stamped a number that moved every few minutes.
*   ⛔ **TWO END STATES, and they are different repairs — a sentence naming one and measuring the other
    is how this entry's first draft was wrong.** A registered path **absent from disk** is the dangling
    case `git worktree prune` clears. A registered directory **present while its `.git` is gone** is a
    *broken* worktree, not a dangling one: the contents are still there and the pointer into
    `.git/worktrees/` is what was lost. ⚠️ **Neither count establishes a cause** — a removal that skipped
    `git worktree remove`, or the OS clearing `/private/tmp`, both fit, and nothing on disk distinguishes
    them. *The original sighting — a directory that looked like junk and was a registered worktree — is
    **relayed** from another lane; I ran the mechanism, not the incident.*
*   **Why `§INV_NO_DESTRUCTIVE_GIT` does not already cover this.** That invariant forbids `git clean
    -f`/`-d`/`-x` and names the cost as *a peer's uncommitted work with no git-recoverable trace*. **This
    cost is different in kind — the repository's own bookkeeping — and it is the case the invariant's hook
    is weakest on**: by that invariant's own text the block is one-strike and lifts on a deliberate retry,
    which is precisely what an agent does once it has decided a directory is junk. *(One-strike behaviour
    relayed from the invariant's text, not measured.)*
*   ⚠️ **Stated, not enforced.** Nothing goes red when the `worktree list` check is skipped — the hook
    refuses the command, it does not ask the question. Per
    `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
*   ⛔⛔ **After the fact — AND THIS BULLET USED TO BE WRONG IN THE DESTRUCTIVE DIRECTION, so read it rather
    than the model you arrived with.** For a **dangling** entry (path absent from disk) `git worktree prune`
    clears the registration, and that working copy's uncommitted contents are already gone with no
    git-recoverable trace. **For a BROKEN one (directory present, `.git` file missing) prune does NOT skip
    it — it DEREGISTERS it**, destroying the admin dir that still holds HEAD and the index, and orphaning
    contents that are still on disk. On a detached one that admin dir was the only record of its tip.
    ✅ **MEASURED on git 2.43.0, six arms in a throwaway repo**: git marks a broken worktree `prunable=1`
    **with the same reason string as an absent one** (`gitdir file points to non-existent location`) because
    it tests the `.git` **file**, not the directory — so the two are indistinguishable to prune, and
    `prune --verbose` removed the broken arm alongside the absent one, 6 registrations down to 4.
    ⭐ **`git worktree repair` is the repair, and the order is load-bearing: REPAIR FIRST, PRUNE SECOND,
    NEVER THE REVERSE.** Repair restored a still-registered broken arm (`status` exits 0 after) and could do
    nothing for the arm pruned moments earlier. **And repair itself removes the prune hazard** — on an
    unlocked arm `prunable` goes 1 → 0 (re-run unlocked, because a lock suppresses `prunable` by itself and
    the first run had every arm locked, which would have confounded it). Cost at live size, 35 worktrees:
    **110 ms total, 5,451 bytes written, zero objects created, 35/35 restored, every lock intact**; expect
    two noisy stderr lines per worktree, which are not failures. *Measured, not relayed — this bullet's
    provenance goes DOWN from relayed to run.*
*   ⚠️ **A lock is not a guard, and on this machine it is the only thing standing between a broken
    registration and the next prune.** A locked worktree does not report `prunable`, so a lock incidentally
    protects it. ✅ **Measured**: of 35 broken registrations in one repo, **35 of 35 were locked** — every
    one with a *lane* reason (`MORPHCI lane`, `PLANEXEC spike`, one empty), **none with a janitor's own
    hold-for-review reason.** The protection is a lane habit rather than anything designed, so it
    evaporates the first time somebody tidies lock reasons.

## [2026-10-23 21:45:23] ¶PTF_APPROVING_A_RULE_DOES_NOT_INSTALL_IT

**Holding a rule, approving one, authoring one, and actively practising one all fail to install it.** Four instances in one evening across three seats, each violating a rule the violator had in hand at the time.

*   ⭐ **The gradient, and the last member is the one that matters**: *holding* < *approving* < *authoring* < **actively practising**. Practising is the strongest member **because it is the one everybody assumes is enough.**
*   **Measured 2026-10-23 — four instances, three seats, no seat named because three seats in one evening is the finding rather than any one seat's problem:**
    *   **Approved, then violated inside twenty minutes.** A seat gave a go to a strengthened `¶PTF_A_PIPELINE_REPORTS_THE_LAST_COMMANDS_STATUS`, then read a command through a `head` pipe, saw an error beside `exit=0`, and was one message from telling a peer their freshly-merged code silently lost writes. Bare, that command exits **5** and is entirely correct.
    *   **Quoted at three peers, then violated.** A seat quoted *"a fact you did not measure yourself is expired until you re-measure it"* at three peers, then wrote a **relayed** figure into a directive entry as its own measurement.
    *   **Authored, then violated inside two hours.** The same seat committed the truncated-list rule — *if the conclusion is none, the command ends in `wc -l`, never `head`* — and two hours later read a **2,811-character** line through `cut -c1-700` and told a peer their correct citation was wrong.
    *   ⛔⛔ **Practised all evening, then violated — and this is the one that would have SHIPPED damage.** A seat that had labelled every figure `ran` or `relayed` all evening wrote a **relayed** sweep row into a brief **marked as measured**. Executing that brief **would have reverted a ticket to a worse version than the one already filed** — a confident overwrite of a better artifact by an agent faithfully following instructions. It was caught only by a fence its own author had written **for a different hazard**. ⭐ **So the cost of this shape is not a wrong sentence; it is a faithful agent destroying better work.**
*   ⭐⭐ **What the four do NOT argue, and this correction is what keeps the rule honest**: not that reading, approving or authoring rules is pointless. **Every one of the four was caught BY the rule** — the pipeline error by the rule just approved, the others by rules just written or just quoted. **A rule nobody had read would have caught none of them.** So these acts install the **recognition** and not the **reflex**: a rule earns its keep at the **catch**, not at the prevention. Budget for that — expect to violate the rules you know best, and expect the knowing to be what catches you.
*   **Redirection**: do not resolve to hold the rule harder, which is the act that just failed four times. Make the **check** cheap at the moment of the claim — one re-run, printed beside the claim — because the catch is where the rule actually works. And **write the fence even when its reason feels thin**: one of these four was caught by a fence put in for something else entirely.
*   ⚠️ **Stated, not enforced** — nothing reddens when a rule's own author violates it, and every one of these was caught by a person or a lane re-measuring rather than by an instrument. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`, of which this is the human half: that entry governs a rule no check can fail, this one a rule its own holder does not fire.

## [2026-10-23 23:22:12] ¶PTF_REMOVED_WITHOUT_SAYING_REMOVED_AS_WHAT

**A doc sentence saying a symbol was "removed" is read as "not present", so it must say removed *as what*.** *Found by a `/revise` lane while repairing the sentence; mechanism and wording theirs.*

*   ⛔ **The trap is that the narrow claim and the broad claim SHARE THEIR VOCABULARY.** An author who deleted the last read of a symbol in the file under their cursor writes *"removed"* meaning **removed from here**, and the sentence as published asserts **removed from everywhere**. ⭐ **Nothing in the author's own verification catches it, because grepping the file they changed returns exactly the zero they expected.**
*   ✅ **Measured here, 2026-10-23.** `docs/SESSION_LIFECYCLE.md:639` read *"The `FLEET_PANE_ID` env var was **removed** — `fleet.sh pane-id` is now called directly by `session.sh find` on each lookup."* The consumer half is **true**: `scripts/session.sh` holds **0** occurrences of `FLEET_PANE_ID` against **27** of `FLEET_PANE` in the same invocation as positive control. The rest is false — `scripts/worker.sh:372` is `export FLEET_PANE_ID="$PANE_ID"`, so the variable **is set in every running seat**, and `scripts/run.sh:155` computes its own copy fresh from `fleet.sh pane-id`. **Two seats independently hit the contradiction** — the variable is plainly in their environment, the doc says it is gone — and spent time reconciling a wording problem as though it were a code problem.
*   **Redirection: a removal claim owes THREE facts** — the consumer that went away, the producer that did not, and whether anything reads the value now. A claim carrying only the first is the one that costs time. Write *"removed as a consumer in `session.sh`"*, then name what still writes it and what still reads it.
*   ⭐ **A zero in the file you edited is not a zero in the tree.** `§PTF_A_ZERO_IS_NOT_EVIDENCE`'s sibling case, and the one that bites an author rather than a reader: before writing a removal sentence, grep the symbol across the **sibling** scripts and not only the one under the cursor. If the count is non-zero anywhere, the word *removed* needs its scope attached.
*   ⚠️ **Stated, not enforced.** Nothing reddens when a doc says *removed* of a symbol another file still exports, and the author's own check returns the reassuring zero. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## ¶PTF_MAJORITY_RULE_IS_AN_INSTRUMENT_AND_THE_MAJORITY_CAN_BE_THE_ERROR

**Counting which form is more common tells you what is common, never what is correct — and a lane that fixes the minority to match the majority has propagated the defect with the confidence of a consistency pass.** *Found by a `/revise` lane inverting its own sub-lane's finding, then its own landed edit.*

*   ✅ **Measured here, 2026-10-23.** A sub-lane reported `skills/loom/SKILL.md:177` as the odd one out for spelling an invariant `§INV_SLOT_CAP_IS_GLOBAL` against **13 pilcrow uses to 1 section-sign** elsewhere (occurrences via `grep -ro | wc -l`, so the counts replicate). ⛔ **The reading is backwards.** `.directives/SIGILS.md` rules it on `¶INV_SIGIL_SEMANTICS`'s authority: **`¶` marks a DEFINITION, `§` marks a REFERENCE**, for every sigiled noun, and **discovery depends on it** — `grep '§CMD_'` is what finds usage sites. The declaration carries `¶` correctly; `:177` is a citation, so **it is the only one of the thirteen that is right.** The instrument was majority-rule and the majority was the error.
*   ⛔⛔ **AND THE SAME LANE HAD ALREADY INHERITED IT.** Its own landed bullet cited the pilcrow form, taken from a majority it had not checked, **one line above a sibling bullet that cites the reference form correctly.** It found that by ruling against the sub-lane rather than by re-reading its own work — so the defect was caught by the argument, not by an audit.
*   ⭐ **Why this shape is worse than an ordinary wrong edit: it arrives dressed as a CONSISTENCY pass**, which is the one kind of change a reviewer waves through. A lane reporting *"twelve say X and one says Y, I made them all X"* has produced a diff that reads as tidying and is a regression, and the count in its report is correct, which is what makes it persuasive.
*   **Redirection: find the RULE before counting the forms.** Where a convention is written down — a `SIGILS.md`, a style file, a schema — the written rule is the authority and the distribution is evidence about compliance, not about correctness. **Ask what the minority form would be RIGHT about**, and only then count. If no rule is written, a majority is a reason to go and get one ruled, never to edit toward it.
*   ⚠️ **Stated, not enforced.** No invocation reddens on an edit that moves a minority form to the majority, and the diff is small and uniform. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-23 23:28:40] ¶PTF_A_TEXT_PATTERN_OVER_SOURCE_COUNTS_WHAT_IS_WRITTEN_AS_TEXT_AND_SILENTLY_OMITS_THE_REST

**Counting the members of a registry with a pattern over its source text counts only the members written AS text, and silently omits every one the language computes — a getter, a spread, anything else.** *Found and measured by an `IDE117` build lane; wording and figures theirs.*

*   ⛔ **The omission is not noisy.** The count comes back **plausible, stable, and confidently wrong**, and it **stays wrong across re-runs — so repetition reads as corroboration.** ⭐ **Count a registry by IMPORTING it and reading its keys; a pattern over the file is a different measurement of a different thing.**
*   ⭐ **The signature to watch for: two readings of one registry that differ by a constant, where the smaller reading is a strict SUBSET of the larger.** Establish the subset relation with `comm`, never by eyeballing — it is what distinguishes *"one instrument is broken"* from *"these instruments answer different questions"*, and it **proves** it rather than asserting it.
*   ✅ **The measured instance, ran at `ec0e73d2`.** `tree/src/jslt/functions.ts`'s `TABLE` has **52** entries by `Object.keys(FUNCTIONS).length`. A 2-space-indent key pattern counted by occurrences returns **38**, every one of its names a member of the 52. The missing **14** are written `get round() { … }`, `get 'is-array'() { … }` (`functions.ts:863, 865, 983, 1114`). **A getter is an own-enumerable property: `Object.keys` counts it, no text pattern can.**
*   ⛔⛔ **The 38 had already been reported as the registry's size TWICE before anyone re-measured it**, and a check built on grep would have reported 38 forever **while being structurally unable to fail in the direction it exists to fail in.** ⭐ **Proved rather than argued: planting a getter left the text instrument at 38, blind to it, while the importing check went red** — which is `§INV_NEGATIVE_CASE_IS_THE_NEAREST_NEIGHBOUR` applied to an instrument instead of a guard, since the planted getter is the nearest legal neighbour to the defect that produced the 38.
*   **A third instrument in the same incident was not broken and not rival either**: a documentation table's **45** rows, where rows are not one-per-name — two pairs share a row, two more have prose sections, one name is absent from that file. **So three instruments answered three different questions and only one was defective**, which is a reading no amount of re-running the two numbers would have produced.
*   ⚠️ **Stated, not enforced.** Nothing reddens when a registry is counted by grep; the count is simply smaller and nothing says so. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 16:40:00] ¶PTF_A_PIPELINE_REPORTS_THE_LAST_COMMANDS_STATUS

**`$?` after a pipeline is the LAST command's status, so a command read through `head`, `tail`, `grep` or `wc` reports the PAGER's success and the real exit code is destroyed before anyone can read it.** The output you do see is a true excerpt of a run whose verdict you no longer hold.

*   ⛔⛔ **This entry had no definition until now, and a neighbouring entry has been citing it for two days.** `¶PTF_APPROVING_A_RULE_DOES_NOT_INSTALL_IT` opens its first instance with *"A seat gave a go to a strengthened `¶PTF_A_PIPELINE_REPORTS_THE_LAST_COMMANDS_STATUS`"* — a rule approved, violated twenty minutes later, written into an entry **about** it, and never written down **as** it. ✅ **Measured here**: heading-level and bullet-level searches for the name both return nothing, against a same-invocation control on `¶PTF_A_ZERO_IS_NOT_EVIDENCE` that finds its definition at `:175`. **The strongest possible instance of its own neighbour's thesis** — the rule describing how approval fails to install a rule was itself installed nowhere.
*   ⭐ **The tell is that the verdict and the output disagree in SHAPE: you are holding an error message and a zero exit.** Not a subtle discrepancy — a printed refusal beside `exit=0`. Nothing else produces that pairing, so it is worth reacting to on sight rather than reasoning about.
*   ✅ **Three instances in one session, 2026-10-25, by one agent that held this file in context throughout** — which is why they are recorded rather than fixed quietly:
    *   **The expensive one.** `git push origin <sha>:refs/heads/main | tail -4` printed the pre-push hook's refusal **and `push exit=0`**. Read directly it was **1**, and `git ls-remote` showed the remote unmoved. Believing the status would have told a peer seat their three branches were live on `main` while the ref had not budged — *a false landing claim about another seat's work, which is the costliest shape an agent can report.*
    *   **A gate read.** Three test harnesses piped through `| tail -1` returned **three blank lines**. Re-run with redirection and read by exit code: `18 ok exit 0`, `40 ok exit 0`, `8 ok 2 FAIL exit 1`. An empty line where a summary belongs is not a passing gate and not a failing one — it is no reading at all.
    *   **A sweep.** A lane-stall sweep read through `head` reported the pager's success, so the sweep's own exit **3** — its *lanes are stale* finding, not a failure — was lost.
*   **Redirection, and it is mechanical rather than attentional**: send the command's output to a file, read `$?` on the next line, then page the file. `cmd > /tmp/out 2>&1; echo "exit=$?"; head /tmp/out`. Do not reach for `PIPESTATUS` — it is **empty under zsh**, which is this fleet's shell, so the portable-looking fix is another false reading.
*   ⚠️ **Where the pipe is unavoidable, read the printed VERDICT and never the status.** A gate that prints `FAIL` is legible through a pager; its exit code is not.
*   **Distinct from its neighbours**: `§PTF_A_ZERO_IS_NOT_EVIDENCE` governs a pattern that ran and matched nothing; `§PTF_PROVE_THE_INSTRUMENT_RAN` governs an instrument that ran elsewhere or never ran. **Here the instrument ran correctly and its verdict was discarded in transit** — the output is genuine and the status belongs to a different program, so a positive control passes and proves nothing about the number you are reading.
*   ⚠️ **Stated, not enforced.** Nothing reddens when an exit code is read through a pipe; the status is simply somebody else's. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 17:20:00] ¶PTF_A_DIFFERING_PATCH_ID_IS_NOT_EVIDENCE_THE_WORK_IS_ABSENT

**A patch-id answers *is this exact diff present*, never *is this work present*.** So a differing id is not evidence of absence, and offering patch-id comparison as the cheap way to detect work that landed by another route **manufactures a false negative** on any work that was rebased, reformatted, split, expanded or improved on its way in.

*   ✅ **Measured, and it false-negatived three for three.** A lane checking whether two threads' work had landed found all three path-scoped `patch-id --stable` readings disagreeing — reviewed `31c7ba46`, regenerated `c57e5d9d`, **landed `854f7a86`** — while the work was unambiguously present, live in five files. Had it stopped at the id check it would have reported both threads owed and rewritten text already at the trunk in a later and better form.
*   ⛔ **This corrects a recommendation, which is why it is written as a rule rather than a note.** The conductor's own dispatch brief offered the id comparison as the cheap check, citing a real precedent where five of six commits were byte-identical at the target. **That precedent is true and does not generalise**: byte-identical work has a matching id, so the check's *hits* are sound. Its *misses* carry nothing, and a check whose zeros are worthless is worse than no check when the zero is what you act on.
*   ⭐ **The asymmetry is the whole rule: a MATCH proves landed, a NON-MATCH proves nothing.** Use it to confirm, never to refute.
*   ⛔ **Except on a binary path, where a MATCH proves nothing either.** `git patch-id --stable` does not hash a binary change faithfully, even fed `git show --text`: two branches changing `logo.png` to different blobs (`b7d03283…`, `330e0393…`) gave one path+text id, `08c8fd1d9901…`, so a go recorded for one cleared the other (kit `sessions/2026_10_07_LIVE_MARKET_LOOM/builds/RECEIPTS_RC.md:28-36`). A commit touching a path that `git diff-tree --numstat` prints as `-\t-` is bound by its **blob ids** (`git ls-tree <commit> -- <path>`), never by its patch-id. ⚠️ **Stated, not enforced**: the receipt tooling still accepts a patch-id there, and its fix is parked.
*   **Redirection**: settle presence **by content at the target, per claim, with a firing control.** Grep the distinctive symbol or sentence in the destination tree and prove the instrument discriminates in the same invocation. That is what settled all three here.
*   ⚠️ **Stated, not enforced.** Nothing reddens when a non-match is read as absence; the ids genuinely differ. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 17:20:10] ¶PTF_A_GO_RECORDED_AS_A_COUNT_MUST_NOT_BE_RELAYED_AS_AN_ENUMERATION

**When a record states an approval's scope as a COUNT — *the three approved edits* — relaying it as an ENUMERATION invents the membership.** Relay the count and the pointer, or quote the record's own list. Never fill in the numbers.

*   ✅ **Measured on this engine's own conductor, 2026-10-25.** A dispatch brief said the go covered *"items 1, 2 and 3"*. The record says **1, 2 and 5**, in eight places across six files, and one of them says **"NOT item 3"** explicitly — item 3 being a script the operator declined. Control: the correct triple returns 8 hits in the same sweep, so the enumeration's absence is measured rather than assumed. **Acting on the brief would have written an unapproved script and left an approved entry unwritten — inverted at both ends.**
*   ⛔⛔ **The correct enumeration was in the conductor's OWN ledger at the time**, on a row stating *"Overseer's go received on items 1, 2 and 5"*. The count was taken from a hand-over summary and the enumeration was filled in from nowhere. **So this is not a failure of access; it is a failure of which field was read** — and that is why the remedy is mechanical rather than attentional.
*   ⭐ **The tell: you are about to write an enumeration you cannot point at a line for.** A count has one source; an enumeration has a list. If you cannot quote the list, you do not have one.
*   **Redirection**: write *"the three approved edits (see `<path>:<line>`)"* and let the executor read the list. A brief that relays a pointer cannot invent membership; a brief that relays numbers can.
*   **Why it is worse than an ordinary stale fact**: an enumeration reads as MORE precise than the count it replaced, so it invites less checking, and the executor has no signal that a number was manufactured. Cross-ref `§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP` — same shape, a mark buying trust it cannot justify.
*   ⚠️ **Stated, not enforced.** Nothing compares a brief's enumeration against its source. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 17:20:20] ¶PTF_A_WAIT_KEYED_TO_A_CHANNEL_CANNOT_SEE_AN_ARRIVAL_THAT_TOOK_ANOTHER_ROUTE

**A wait watching a DELIVERY CHANNEL — a drop directory, an inbox, a hand-off path — is blind to the same work arriving by any other route, and reports *not yet* for as long as you leave it running.** Re-check the DESTINATION, never only the channel.

*   ✅ **Measured**: an empty drop directory was watched for **nine days** while the work it was waiting for landed as ordinary commits. The watcher was correct about its channel the whole time.
*   ⭐ **It reads as patience rather than as an error**, which is why it survives: an empty channel looks exactly like work that has not been done, and the longer it stays empty the more confident the *not yet* becomes.
*   **Redirection**: key the wait on the destination's own state — does the thing exist where it would exist if the work were done — and treat the channel as one possible route rather than as the definition of arrival.
*   **Same family as `§PTF_A_DIFFERING_PATCH_ID_IS_NOT_EVIDENCE_THE_WORK_IS_ABSENT`, above**: both ask about a *route* and get read as answering about *presence*.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 17:20:30] ¶PTF_SEVERAL_COUNTS_UNDER_ONE_LABEL_SHIFT_THEIR_ATTRIBUTION_WHEN_ONE_IS_ZERO

**Never read several count commands positionally under one shared label: a zero often prints NO LINE, so N counts emit fewer than N lines and every reading below the gap is attributed to the wrong subject.**

*   ✅ **Measured**: three counts printed **one line**, and the resulting reading was *exactly inverted* — nearly causing a rewrite of approved text that was already landed.
*   ⛔ **The output looks complete.** There is no gap, no blank, nothing marking the missing row — just a shorter list whose entries still look like answers, which is why it is read rather than questioned.
*   **Redirection**: **label each count on its own line and force a row on zero** — `printf '%s: %s\n' "<subject>" "$(cmd | wc -l)"` per subject, so a zero prints `subject: 0` instead of vanishing. Never `for x in …; do cmd; done` under one heading.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 17:35:00] ¶PTF_A_FIXTURE_THAT_RESTATES_WHAT_IT_PINS_CANNOT_SEE_THAT_VALUE_GO_STALE

**Where a test fixture hard-codes a value that live config also supplies, at least one assertion must READ the live config — otherwise the suite's green is evidence about the fixture and says nothing about the config.** The test and the thing it is meant to protect have been decoupled, and nothing in a passing run reports it.

*   ✅ **Measured, and both of the two pinning tests in scope shared the blind spot while fully green over a BROKEN CAPABILITY.** `publish-tag.test.mjs` passed **21/21** while every commit on the trunk was unpublishable — its `TABLE` hard-codes the branch at line 21, and the one test that does load the committed config asserts shapes, names, directories and scripts, **never the branch**. `kit-worktree.test.mjs` passed **37/37** while `DEFAULT_REF` pointed at a frozen branch, because line 86 pushed to *both* refs, so either value resolved.
*   ⛔⛔ **The decisive reading is what happened after the fix: repinning the config alone left both suites green.** So neither was ever discriminating in that direction — the green before and the green after carry the same information, which is none. **A test whose colour does not change when the thing it pins changes is not covering it.**
*   ⭐ **The tell: the fixture and the config both contain the value, and the test never crosses between them.** Grep the value — if it appears in the test file *and* in the config, ask which one the assertion reads. If the answer is "the fixture", the config is unguarded.
*   **Redirection**: do not delete the fixture, which is often there for speed. **Add one assertion that reads the live config** and compares it to the fixture, so the pair cannot drift silently. One case, and it converts both files into a single guarded fact.
*   **This is `§INV_AN_ASSERTION_WHOSE_SIDES_CANNOT_DIVERGE_IS_NOT_COVERAGE` in a specific and very common costume** — the two sides are the fixture and itself, with the config standing outside the comparison entirely. Worth its own entry because the fixture *looks* like the other side.
*   ⚠️ **Stated, not enforced.** Nothing compares a fixture's constants against the config they shadow. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 17:35:10] ¶PTF_COMM_OVER_AN_UNSORTED_GREP_LIST_RETURNS_A_WRONG_ANSWER_THAT_LOOKS_RIGHT

**`comm`, `join` and `uniq` require sorted input, and `grep -r` emits traversal order. Feeding one to the other produces a plausible wrong set with NO error and NO warning.**

*   ✅ **Measured**: a set difference over two `grep -rl` lists returned a **23-file** list that read as a finding. The totals were 38 and 25, so the answer had to be **13**; sorting both inputs first returned exactly 13. The wrong list never left scratch.
*   ⭐ **The tell is arithmetic, not inspection — and it is the generalisable half.** `comm` cannot report its own failure, so the only thing that catches it is **reconciling the set-difference count against the totals it came from.** A difference larger than either operand's share, or one that does not add up, is the signal. Inspecting the list does not help: every path in it is real.
*   **Redirection**: `sort` both inputs explicitly, and print the reconciliation beside the result — `total A, total B, difference, and A − B` — so a reader can see the arithmetic close. Prefer computing set operations in Python over a pipeline when the sets matter, for the same reason `§PTF_A_PIPELINE_INTO_WHILE_READ_CAN_LOSE_PATH_AND_EVERY_COMPARISON_THEN_RUNS_AGAINST_EMPTY` prefers it.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:18:00] ¶PTF_A_MULTI_REPO_CLEANUP_MUST_RE_CHECK_EVERY_REPOSITORY_ITS_SCAN_COVERED

**A cleanup pass whose keep list spans several repositories must run its apply-time re-check against every repository the scan covered, read from a list the scan itself wrote — never against a repository named literally in the code.** The asymmetry between a wide scan and a narrow re-check is invisible at the call site and deletes other repositories' live state.

*   ✅ **Confirmed from the code and then reproduced as destruction.** The scan opened one `keep-paths` file for all repositories and every scanned repo appended to it; the apply-time re-check, **one line before `rm -rf`**, asked a **single** repository by literal path whether a scratch directory still held a worktree. A red test against the pre-fix script: **5 passed, 5 failed**, with `repo2's worktree survived the scratch rm: got 'DESTROYED' want 'present'` while that worktree was still registered in repo2. **That is the damage, not a near miss.** After the fix: 10 of 10, the original suite unchanged at 41/41, and the control that still deletes an empty stale scratch directory firing.
*   ⛔⛔ **And there is a second path with NO timing race at all, which is the half a race-condition framing hides.** A `--only <name>` filter gated the *archive* phase while leaving the *scratch* phase unrestricted — and an archivable worktree is absent from the keep list **by construction**. So an archivable worktree of a non-covered repository in a stale scratch directory is deleted **deterministically**, not on an unlucky interleaving. An archive failure opens the same window.
*   ⭐ **The tell: a keep list built by many writers and consulted by one reader.** Grep for who appends and who reads; if the reader names a repository, a path or an environment while the writers do not, the gap is the defect.
*   **Redirection**: have the scan write the list of what it covered (`: > "$OUT/scanned-repos"` beside the keep list, each classifier appending its own), and have the re-check loop that file, matching by exact string prefix and logging which member holds the directory. **A re-check that cannot name what it did not check is the thing to fix**, not the matching.
*   ⚠️ **Stated, not enforced.** Nothing compares a cleanup's scan scope to its re-check scope. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:18:10] ¶PTF_CLOSE_IN_MAGNITUDE_IS_NOT_A_RECONCILIATION

**A reconciliation between a figure you measured and a figure you inherited may not rest on the two being close in magnitude.** Find the inherited figure's source and read what it counted, or report the gap as unexplained.

*   ✅ **Measured**: an all-repository sum of **608** was reconciled against an inherited **655** by treating the inherited number as a cross-repository aggregate — the two were close, so it read as a result. The source pinned **655 to one repository alone**, and that same repository read **722** nine hours later. **Magnitude discriminated nothing**: a wrong model and a right one produced numbers 7% apart, while the correct reading was a different population entirely.
*   ⭐ **Why proximity is actively misleading rather than merely weak evidence**: two counts of *different things* in the same system are usually within an order of magnitude of each other, so closeness is the expected outcome of almost any pairing and carries nearly no information. **Closeness feels like corroboration and is a prior.**
*   **Redirection**: open the inherited figure's source and read **what it counted and when** — the population, the repository, the clock time. Where the source cannot be found, the honest output is *unexplained gap* with both numbers and both scopes stated, which a later reader can close; a reconciliation invented from proximity cannot be told from a real one.
*   **Cross-ref `§PTF_A_PROVENANCE_MARK_WITHOUT_A_TIMESTAMP`**, whose count clause this sharpens: a count owes its scope as well as its clock, because the same instrument over two populations is two facts wearing one number.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:42:00] ¶PTF_THE_PROOF_PUBLISHERS_DEV_PAIR_FALLBACK_ONLY_APPLIES_TO_A_CLEAN_ENVIRONMENT

**When publishing to a loopback proof store, set `PROVE_S3_PROFILE` as well as `PROVE_S3_ENV`** — the publisher's development-pair fallback reads `${AWS_ACCESS_KEY_ID:-kitminio}`, so it applies **only when nothing has already put an AWS key in the environment**, and a session that carries one puts every publish in the failing arm.

*   ✅ **Measured in six arms.** With no ambient key and the profile unset the publish **succeeds** (rc 0). With an ambient `AWS_ACCESS_KEY_ID` present and the profile unset it **fails `InvalidAccessKeyId`** (rc 254) — the ambient key shadows the dev-pair fallback at `_prove-s3-env.sh:78`. With the same ambient key and `PROVE_S3_PROFILE=kit-proofs` named it **succeeds again** (rc 0). **And one project's `.env` sets such a key**, so every lane whose session is that project while its subject is another is already in the failing arm.
*   ⛔ **The error names the wrong thing, which is the expensive half.** `InvalidAccessKeyId` sends you to the store, the bucket, the port and the credential's value — none of which is wrong. **The defect is that a fallback did not apply**, and nothing in the message says a fallback was involved. Expect to lose the diagnosis rather than the publish.
*   **The credential and the port are a matched pair, not independent**: the local credential works only on its own store's port and the other project's credential only on its own (each read **254** when crossed). So a half-correct configuration fails exactly like a wrong store.
*   ⚠️ **A widely-read sentence asserts the opposite and is true only in the clean arm**: `/prove`'s own §4 prose reads *"No AWS profile is involved: credentials come from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, defaulting to the MinIO dev pair."* True with a clean environment, false with an ambient key, and it is the sentence that sends a lane to a failing publish believing the profile is irrelevant.
*   **Redirection**: pin both — `PROVE_S3_ENV` to the intended project's `.env` **and** `PROVE_S3_PROFILE` to that store's credential — and read the resolved endpoint back before trusting the URL. ⭐ **And check the environment DURING the helper's run rather than before it**: clean beforehand is not clean during, which is the distinction that makes this reproducible rather than intermittent.
*   **Cross-ref `§PTF_PROVE_THE_INSTRUMENT_RAN`'s wrong-store case**, which `PROVE_S3_ENV` alone answers. This is the second half: the env pin picks the right store, the profile pin makes the credential for it apply.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:46:00] ¶PTF_THE_DEFAULT_CHECKOUT_IS_THE_STALE_ONE_AND_EVERY_CASUAL_READ_LANDS_THERE

**Where a repository's primary working directory sits on a branch that is thousands of commits behind the trunk, every read that does not NAME A REF lands in the stale copy — and a stale copy's answers are confident, internally consistent, and clean in `git status`.** Name the ref or read a worktree you created; never read "the repo".

*   ✅ **Four instances in one weave, one afternoon, across four different agents — which is what makes this environmental rather than carelessness:**
    *   A repin lane's first sweep for nine reported sites returned *"No such file or directory"* for three of them, because half the files exist only on the trunk. **Had git's warnings been quieter it would have reported a peer's findings as imaginary.**
    *   The conductor's own 40-file census of a string, taken in the same stale copy, came back as **25** when re-measured against the trunk.
    *   **The conductor then CORRECTED A LANE from that copy** — reading an ownership line at one number with two names absent, where the trunk and even the stale branch's own *remote* carry a later revision with both present. The lane re-measured and refused the correction; **the clearance the conductor was about to hand its operator was false.**
    *   A verification lane's first gate-board census read the same checkout, **1,888 commits behind and missing 10 rows** — caught by a `shasum` differing from the pinned revision's.
*   ⛔⛔ **Nothing in the stale copy looks wrong.** `git status --porcelain` on the path is **empty**, because the divergence is committed history rather than a local edit. So the three signals an agent reaches for — the file exists, it parses, the tree is clean — all pass. ⭐ **And knowing the tree is stale does not help**: the conductor above had itself measured that checkout as 342 commits behind, logged it as a lesson, and read it anyway twice more. **Awareness is not the remedy; naming the ref is.**
*   ⭐ **The tell is a disagreement with somebody whose brief NAMED a ref.** When a peer cites `origin/main` and you cite "the file", you are not disagreeing about the content — you are reading two revisions, and theirs is the one with a name on it.
*   **Redirection**: read `git show <ref>:<path>` rather than opening the file, pipe that into the count, and print the ref beside the number. Where a tree must be walked, create a worktree **at a named ref** and walk that. **Treat a bare path in a multi-branch repository as missing its most important argument.**
*   ⚠️ **Stated, not enforced.** Nothing marks a read as having come from a stale checkout, and the reading is a valid answer about a revision nobody asked about — `§PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION` with a branch as the wrong question.

## [2026-10-29 01:51:32] ¶PTF_A_CANDIDATE_TREE_TESTED_AGAINST_THE_LIVE_ENGINE_IS_NOT_TESTED

**A commit candidate's suites run on an archive of the candidate tree with `ENGINE_SCRIPTS=<tree>/scripts`, or they have not tested the candidate.** Unpinned, the resolver falls back to `$HOME/.claude/engine/scripts`, reads the live checkout's dirty manifests, and goes green for content the commit does not carry.

*   ✅ **Measured 2026-10-29 (IDE129COMMIT)**: the same 17 blobs gave **5/5** suites green unpinned and **1/5** pinned, and swapping in the single dirty manifest file restored 5/5. *Source: that lane's `IDE129COMMIT_REPORT.md`; relayed, not re-run here.*
*   **Distinct from `§PTF_THE_DEFAULT_CHECKOUT_IS_THE_STALE_ONE_AND_EVERY_CASUAL_READ_LANDS_THERE`**: there the unnamed read lands on old committed history; here it lands on uncommitted edits that are newer than the commit, so the green is borrowed from work the candidate does not contain.
*   ⚠️ **Stated, not enforced.** Nothing reddens when a candidate's suite resolves the live engine. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-29 22:31:48] ¶PTF_A_SUBAGENT_FROM_A_PREVIOUS_CONVERSATION_IS_RESUMABLE_BY_COPYING_ITS_TRANSCRIPT

**After a process exit, a restart or a reboot, an old agent id is not lost: copy its transcript into the current conversation and resume it.** `SendMessage` to the old id fails with *"No transcript found"*, which reads as the agent being gone. It is not gone; it is filed under the conversation that spawned it. **A `/clear` in the same Claude process is not this case**: the id stays addressable there and needs no copy.

*   ✅ **Measured 2026-10-29**: copying `<proj>/<old-conv>/subagents/agent-<id>.{jsonl,meta.json}` into `<proj>/<current-conv>/subagents/` made each agent resumable with its full context — **6 of 6 lanes resumed**. *Relayed by manager:director*: those ids were lost to a process restart (an engine session dehydrate/restart, a pane relaunch, a crash), not to a `/clear`.
*   ✅ **Measured 2026-10-30 (meta:engine, `sessions/2026_10_29_META_ENGINE/LOOM_LOG.md`, "Agents survive /clear in the same process")**: at a 15:31 `/clear` in the same process, lanes dispatched in the old conversation kept writing and their hand-backs arrived in the new one; at 17:50 `SendMessage` to an id dispatched before the clear (`ab089c2ec80ad85eb`) resumed it, and it replied *"[ASKOVERRULE] reachable after /clear"*. No transcript was copied.
*   ⛔ **Re-dispatching from scratch is the forbidden move.** It reads as the safe recovery, but the new agent starts without the old one's context and re-does work the old one already holds.
*   **Redirection**: on *"No transcript found"* after a process exit, restart or reboot, find the old conversation's `subagents/` directory, copy both files for the id, and send the message again.
*   ⚠️ **Stated, not enforced.** Nothing suggests the copy when the resume fails. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-29 22:31:58] ¶PTF_A_LANE_SAYING_IT_LEFT_A_FILE_UNTOUCHED_IS_A_CLAIM_ABOUT_THAT_FILE

**A report that a file was left untouched is checked on that file, not on its neighbours.** Hashing the sources beside it confirms the sources; it says nothing about the path the claim names.

*   ✅ **Measured 2026-10-29**: a lane reported *"dist never touched, sha256 unchanged"*. On disk, `tools/ask-app/dist/.build-id` equalled that lane's own build id, and a `dist.v1-backup-*` directory carried the same timestamp, so the dist had been rebuilt. The conductor relaying the claim had hashed three source files, not `dist`.
*   ⭐ **It has the shape of `§INV_A_CONTROL_DRAWN_FROM_WHAT_YOU_JUST_FIXED_IS_NOT_A_CONTROL`**: the check that passed was drawn from files the claim was never about, so it could not have failed.
*   **Redirection**: re-hash or `stat` the exact path the claim names, in the same invocation as the relay, and print that path beside the result.
*   ⚠️ **Stated, not enforced.** Nothing ties a relayed "untouched" to a reading of the named path. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:46:10] ¶PTF_AN_AMBIGUOUS_WORD_IN_A_LEFTOVERS_ROW_READS_AS_A_CONTRADICTION

**A leftovers row states the thing's STATE, never an adjective that spans two states.** One ambiguous word makes two accurate records look like a disagreement, and the disagreement is what gets investigated.

*   ✅ **Measured**: a ledger claimed a ticket's work `done-uncommitted` while a sweep row reported *"four **unguarded** sites"* remaining. Both were true. The row's full wording was **"Corrected by hand, scanned by nothing"** — so `unguarded` meant **unscanned**, not **uncorrected**. The four sites had been fixed and were simply read by no check. **It cost a thread a hold and a lane its first task**, and the settlement was one content reading with a firing control.
*   ⭐ **`unguarded`, `unhandled`, `uncovered`, `open`, `unresolved` and `not done` are each two claims wearing one word** — *the thing is wrong* and *nothing watches the thing*. A reader who needs to act cannot tell which, and the two imply opposite work: fix it, versus leave it alone and point a check at it.
*   **Redirection**: write the state, not the adjective — *"corrected; scanned by nothing"* rather than *"unguarded"*. Where a row must be short, the discriminator is cheaper than the word: say which of **fixed** and **watched** is false.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:46:20] ¶PTF_NARROWING_A_GUARDS_EXCLUSION_IS_A_CLAIM_ABOUT_THE_OLD_RULES_SILENCE

**Narrowing a guard's exclusion asserts that the old rule was BLIND to something. That is a claim about the old rule, so run BOTH rules over the same planted input in one invocation and report both readings** — the new rule going red proves only that the new rule works.

*   ✅ **Measured, and the unplanted corpus proves nothing either way**: over 14 unplanted pages the two rules are **indistinguishable** — 4 sites, the same 2 files. Only the old rule run **on the plant** shows what was at stake: it was blind to a backticked count, **and its own census silently dropped 4 → 3**. So the same edit it failed to catch would have **lowered the guard's anti-blindness floor**, and a page asserting a wrong total would have passed green while weakening the thing meant to notice.
*   ⛔ **A red on the new rule alone is the weakest useful evidence here**, because the interesting quantity is not *does the new rule fire* but *what did the old one let through*. Shipping the first reading is how a narrowing gets credited with a hole it did not close.
*   **Redirection**: keep the old predicate reachable long enough to run it, put both columns in one invocation, and state both. `§INV_A_CONTROL_DRAWN_FROM_WHAT_YOU_JUST_FIXED_IS_NOT_A_CONTROL` applied to a rule change: the old rule is the only available control, and it stops existing the moment you delete it.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 18:46:30] ¶PTF_AN_UNGUARDED_OBJECT_INDEX_ADMITS_CONSTRUCTOR_AS_A_VALUE

**A check that classifies a token by indexing a plain object must guard the lookup with `Object.hasOwn`, or use a null-prototype map.** An unguarded index returns a **function** for `constructor`, `toString`, `valueOf` and friends, and the numeric reject that normally follows is false against a function — so the token is admitted as a value.

*   ✅ **Measured**: `readNumber('constructor')` returned **`Object`**, and the check went on to print `states function Object() { [native code] }`. **Unreachable for the check's entire life and reachable the instant its corpus grew by one directory** — the new directory simply contained a file with that word in it.
*   ⭐ **The shape worth recognising: a latent defect whose trigger is a CORPUS change rather than a code change.** Nothing about the lookup changed; the set of tokens reaching it did. So the usual instinct — *what did I just edit* — points at the wrong half, and a bisect over the code finds nothing.
*   **Redirection**: `Object.hasOwn(map, key)` at every lookup site, or build the map with `Object.create(null)`. Prefer the null prototype where the map is yours to construct, because it removes the whole class rather than each site.
*   ⚠️ **Stated, not enforced.** Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 19:36:00] ¶PTF_A_CLEARANCE_FOR_ONE_CHANGE_IS_NOT_A_CLAIM_ON_THE_GROUND

**Being cleared to make one change in someone's ground is not ownership of it, and a record that cannot tell the two apart grows an owner per incident.** When writing an ownership map, a CODEOWNERS file or any durable record of who holds what, the input is each holder's own claim — never the list of who was recently permitted to touch something.

*   ✅ **Measured, and the correction came from the seat that would have GAINED the ground.** Rebuilding an ownership map, a conductor put three files into one seat's column because an operator had cleared that seat to edit them an hour earlier for an unrelated repair. **The seat refused them**: *"That's a clearance for one change, not ownership."* Every incentive in the moment ran the other way, and nothing in the conductor's reading would have caught it — a permission and a claim look identical in a log.
*   ⭐ **Three things are routinely conflated and only one belongs in the record.** On one afternoon: an operator **clearing** a seat to edit files it does not own; a change **entailed** by a ruled decision landing in another seat's ground (a test tracking an index after a page moved); and a seat **claiming** its own ground. The first two are events, the third is a fact. **A map built from events assigns everything to whoever touched it last**, which is how it rots into something nobody can satisfy.
*   ⛔ **The failure direction is accretion, not loss.** Nobody notices a map gaining an owner, because each addition had a real justification behind it. The map stays plausible while becoming wrong, and it is only discovered when somebody tries to USE it to find an owner — by which time several rows name whoever last had a reason to be there.
*   **Redirection**: ask each holder what it owns and write only that. Where a one-off clearance needs recording, record it as a **clearance with its date and its reason**, somewhere that is not the ownership record. And **prefer pointing at a living table over copying it** — a map clause that cites the owner table rather than restating it cannot drift from it, which is the same reason a citation beats a copy everywhere else.
*   ⭐ **A seat saying *"my row is only stale"* is a stronger claim than *"my row is correct"***, and worth eliciting explicitly: it distinguishes a dead name from a wrong assignment, and those are different repairs.
*   ⚠️ **Stated, not enforced.** Nothing distinguishes a permission from a claim in any record either produces. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-25 21:02:00] ¶PTF_A_CLAIM_ABOUT_ALL_REMOTES_REQUIRES_ENUMERATING_REFS_NOT_CHECKING_THE_TWO_YOU_WERE_TOLD

**Checking the refs somebody named you is not a claim about every ref.** A reading of `origin/main` and one other branch is a true answer about those two and carries nothing about the remote; the instrument for *"is this anywhere on the remote"* is `git for-each-ref refs/remotes/<remote>` and a loop, never a hand-written list.

*   ✅ **Measured, and the escalation reached an operator before it was caught.** A seat reported a package as existing *"on no remote trunk"* — **true**. The conductor checked `origin/main` and `origin/feature/reactor`, **got the right answer for both**, and reported to its operator that the package was *"held nowhere but one working copy"* — a single-copy hazard at package scale. Enumerated properly: **5 of 82 remote refs carry it**, three of them pushed that same day by the seat that reported it. Control in the same invocation: `agent/` reads 926 on main and 369 on one of the carrying branches, so the instrument saw both refs and discriminated.
*   ⛔⛔ **Two correct readings, one wrong conclusion, and nothing in either reading was at fault.** The conductor's grep worked, its pair of refs was exactly the pair it had been given, and its answer about them was right. **The defect is that a two-ref reading was spent as an all-refs claim** — a scope error rather than a measurement error, which is why re-running the measurement would have confirmed it forever.
*   ⭐ **`trunk` and `remote` are different words and the relay blurred them.** The source sentence said *no remote **trunk***, which is a narrow true claim; the conductor acted on *no remote*. **Where a claim's scope is one adjective away from a much bigger claim, the adjective is the load-bearing part** — and a reader under time pressure drops it. Say the set you measured, not the property you inferred.
*   ⭐⭐ **And the deeper half, from the seat that made the original error: fixing the instrument did not fix the scope.** They had got the right diff on their second attempt and *still* handed over a sentence whose scope was too wide. **"The diff was the easy half."** So a rule about picking the right command does not reach this; what reaches it is naming the SET a claim covers in the same sentence as the claim.
*   **Redirection**: for any *anywhere / nowhere / all / none* claim over refs, branches, files or hosts, **print the size of the set you enumerated beside the answer** — *"5 of 82 remote refs"*, not *"on the remote"*. A reader can then see the denominator and so can you.
*   ⚠️ **Stated, not enforced.** Nothing marks a two-element reading spent as a universal claim; both halves look like results. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-27 21:45:00] ¶PTF_GREP_Q_IN_A_PIPELINE_INVERTS_A_GUARD_ONCE_THE_PRODUCER_OUTRUNS_THE_PIPE_BUFFER

**`grep -q` in a pipeline under `pipefail` returns the OPPOSITE of the truth once the producer outruns the pipe buffer.** `grep -q` exits on its first match; the producer is still writing, takes SIGPIPE, and `pipefail` hands the producer's death back as the pipeline's answer. A guard that finds its match EARLY therefore reports *no match*, while one that finds it late is correct — and because the trigger is a SIZE, no fixture-sized test can reach it.

*   ✅ **Measured at two seats on macOS, 2026-10-27.** `set -uo pipefail; <producer> | grep -qxF <match>` on a payload whose match is the FIRST line: exit **0** at 4 KB and 32 KB, **non-zero** at 128 KB and 280 KB. The crossover is the host's 64 KB pipe capacity. ⚠️ **A reading taken AT the boundary is not a reading to build on**: at exactly 64 KB the two seats disagree — one read 0, a re-run whose total crosses 64 KB by eight bytes read non-zero. The capacity is the variable, so size the fixture well past it and never at it.
*   ⛔ **The exit CODE depends on the producer, and not one of the codes means "no match".** A `git` producer is killed by the signal and gives **141**. A `python3` producer ignores SIGPIPE, raises `BrokenPipeError`, and gives **120** when the failure lands in the interpreter's shutdown flush (**1** from an uncaught raise mid-loop). ⭐ **Three codes, one wrong answer** — so the defect is not recognisable by its code, and a guard that special-cases 141 has not been fixed.
*   ⛔⛔ **The same defect fails one check CLOSED and its neighbour OPEN, which is why it is worth an entry rather than a patch.** In `engine worktree` the registration check refused **136 of 171** registered paths that git still listed — loud, and so it was found. The lock check has the identical shape and a false negative there waves a LOCKED tree through: the same dry run selected **171** before the fix and **83** after, and the 88 it stopped selecting were locked trees. Under `--apply` that is deleting the installs beneath 88 lanes' locks. *The 136-of-171 figure is written into the shipped test; the 171/83/88 pair is relayed, not re-run.*
*   ⭐ **91 green test arms could not see it, and the reason generalises: the fixture that proves a guard correct is the one guaranteed not to reach this.** An 8-worktree listing is about 1 KB. Any check whose correctness depends on the producer outliving the consumer needs a fixture sized PAST the pipe buffer, and that size asserted as a precondition rather than assumed.
*   ⛔ **And at this fleet's prompt the bug cannot be reproduced at all.** Bare `grep` resolves to a shell function from the Claude shell snapshot (`type grep` is the measurement, as in `§PTF_A_ZERO_IS_NOT_EVIDENCE`). ✅ **Measured here on one producer, two consumers**: through the wrapper, `-q` reads its input to EOF — the producer printed its completion marker on stderr and the pipeline exited **0 at 280 KB** — while `/usr/bin/grep -qxF` on the identical producer exited **120**. So a reproduction typed at the prompt PASSES while the same line inside a `.sh`, where the function does not exist, inverts. ⭐ **The inverse of the wrapper fault already recorded**: there the wrapper manufactures a false zero, here it manufactures a false all-clear for the test OF the guard. Reproduce with `/usr/bin/grep` or inside `bash -c`, never with bare `grep`.
*   **Redirection — take the answer from the DATA, never from a status.** `hit=$(producer | grep -xF "$needle"); [ -n "$hit" ]`. Any `awk` in the chain must read to EOF rather than `exit`ing at the stanza it wanted, for the same reason. Then add a lint arm that fails if a guard returns to `grep -q`, because the shape reads as idiomatic and will be reintroduced by anyone tidying the pipeline.
*   ✅ **Enforced for one script, verified against the shipped code.** `~/.claude/engine/scripts/worktree.sh` uses the capture-and-test shape in `is_registered` and `is_locked`, and its `wt_attrs` awk reads to EOF with that reason written beside it. `scripts/tests/test-worktree-dispose.sh` carries four arms: the fixture asserted larger than 65536 bytes (`PIPE-01`), the `grep -q` shape asserted NON-zero on a match that IS present (`PIPE-02`), the capture-and-test shape asserted 0 (`PIPE-03`), and a source lint over the comment-stripped script asserting it contains no `grep -q` (`PIPE-04`).
*   ⚠️ **Fleet-wide it is stated, not enforced.** **15 of 50** non-test scripts under `~/.claude/engine/scripts/` carry a piped `grep -q`, **13** of them under `pipefail`. That is a floor on exposure and not a defect count — whether each producer can outrun the buffer is unestablished — and nothing reddens for any of the 15. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
*   **Distinct from `§PTF_A_PIPELINE_REPORTS_THE_LAST_COMMANDS_STATUS`** — same family, opposite end of the pipe. There the status belongs to the PAGER: a program that succeeded stands in front of the verdict you wanted, and the tell is sharp — a printed error beside `exit=0`. Here the status belongs to a PRODUCER THE CONSUMER'S OWN SUCCESS KILLED, and there is no tell: no output, a plausible non-zero, and the guard's logic reading it as *not found*. Distinct again from `§PTF_GREP_PIPELINE_CRASH`, which is grep's own 1 on a genuine non-match: that entry's `|| true` does not reach this one and will hide it, since `|| true` makes every reading a success.

## [2026-10-29 03:21:43] ¶PTF_A_HOOK_THAT_CITES_AN_ATOM_MUST_PRELOAD_IT

**A hook whose message cites a `§CMD_` atom must make sure the atom itself reaches the agent. The `COMMANDS.md` entry is in context from SessionStart, but it carries only the atom's summary.** The agent that follows the citation is acting on that summary, not on the algorithm.

*   **Context**: A hook's `hook_deny` reason, Stop `reason`, or `additionalContext` tells the agent to follow `§CMD_X`, and `commands/CMD_X.md` is not among the SessionStart seeds.
*   **Trap**: The citation looks delivered. `COMMANDS.md` is preloaded, and its `### [¶CMD_X](commands/CMD_X.md)` heading and one-paragraph summary are in context, so the sigil resolves to text. The atom's numbered steps, constraints and proof schema are in the linked file, and nothing in the hook's path delivers that file. Reference preloading (`§PTF_PRELOAD_DEPTH_AND_FENCES`) follows `§` references inside files that are already preloaded. It does not follow a hook's emitted message.
*   **Mitigation**: In the same change that adds the citation, deliver the atom. Either call `preload_ensure "$HOME/.claude/.directives/commands/CMD_X.md" "<hook>" "<reason>"` from the hook, or add the atom to the SessionStart set, which is one edit to `SESSION_START_SEED_FILES` in `scripts/lib.sh`: the print loop in `hooks/session-start-restore.sh` and `get_session_start_seeds` both read that array (see `§PTF_PENDING_PRELOADS_STALE`). A per-call `preload_ensure` costs nothing in a seeded session because `preloadedFiles` dedup skips it.
*   ✅ **Fixed instance, `§CMD_CONTINUE_ON_STOP`.** The Stop hook's reason cites the atom, and the atom is defined inline in `COMMANDS.md`, one of the SessionStart seeds, so it is in context from the first message. The hook's `preload_ensure "$ATOM" "stop-auto-continue" "next"` (`hooks/stop-auto-continue.sh:169`, with `ATOM` set to `COMMANDS.md`) is the fallback for a session that lacks `COMMANDS.md`.
*   ⛔ **Open instance, `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`, measured in this tree on 2026-10-29.** `hooks/pre-tool-use-ticket-watch-gate.sh:88` cites it twice in its deny reason ("cites `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`", "follow `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`"). Neither that hook nor `hooks/post-tool-use-ticket-watch.sh` contains `preload`, and `commands/CMD_DRAIN_TICKET_QUEUE_ON_WAKE.md` is not in `get_session_start_seeds`. An agent blocked by the gate therefore receives the `COMMANDS.md:607` summary and not the drain steps. *This is a measured absence of a delivery path. A live session was not observed missing the atom.*
*   ⚠️ **Stated, not enforced.** No test compares the `§CMD_` sigils in hook messages with what the hooks preload or the seeds register. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-29 03:21:53] ¶PTF_A_SUB_AGENT_RUNNING_A_SESSION_HOOK_WRITES_ITS_PARENTS_SESSION

**A sub-agent that runs a session hook or a `session.sh` command inherits `CLAUDE_SUPERVISOR_PID` from its parent, so the engine resolves that call to the PARENT's live session and writes the parent's `.state.json`.** A sandbox `HOME` does not prevent this.

*   **Context**: A review or test lane runs `hooks/session-start-restore.sh`, `session.sh find|activate|continue`, or any hook that resolves "the current session", from inside a Claude sub-agent, usually under a scratch `HOME` it assumes is isolated.
*   **Trap**: `session.sh find` reads `CLAUDE_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"`, and its fast path is the per-PID cache `$SESSION_CACHE_DIR/claude-session-cache-$CLAUDE_PID` (default `/tmp`). That cache holds an absolute session path, and the session's own `.pid` matches, so the PID guard passes. `HOME` is in neither the key nor the path. SessionStart takes `sessions/` from the CWD's project root, not from `HOME`, then overwrites `preloadedFiles` in the session it found with the seeds resolved under the scratch `HOME` (`hooks/session-start-restore.sh`, the `.preloadedFiles = $stds` write). The parent loses the record of what it was delivered, so dedup re-delivers its standards, and nothing reports the change.
*   **Mitigation**: Prefix every such test command with `env -u CLAUDE_SUPERVISOR_PID` in addition to the sandbox `HOME`, and point `CLAUDE_SESSION_CACHE_DIR` into the sandbox when the suite supports it. Unsetting the variable closes the PID route. It does not close the fleet-pane route (`fleet.sh pane-id`) when that script resolves under the HOME in use; that route was not measured here.
*   ⛔ **Measured 2026-10-29 at about 03:00, relayed by the conductor and not re-run here.** A review run of `session-start-restore.sh` under a sandbox `HOME` reset the conductor's `preloadedFiles` to 8 scratch paths. *The resolution path above is read from the code in this tree. The incident is relayed.*
*   **Distinct from `§PTF_READONLY_AGENT_MUTATES`**: there the sub-agent chose to delete something. Here it changes nothing on purpose; the engine routes an ordinary test write to the parent's state.
*   ⚠️ **Stated, not enforced.** No hook or test refuses a run that inherited a live `CLAUDE_SUPERVISOR_PID` under a non-real `HOME`. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.

## [2026-10-28 23:05:00] ¶PTF_A_READ_ONLY_AGENT_TYPE_CANNOT_WRITE_ITS_REPORT_AND_THE_TRANSCRIPT_DOES_NOT_HOLD_IT

**`§INV_A_PROBE_WRITES_ITS_ANSWER_DOWN` is satisfied by the DISPATCH, not by the brief. Naming a report path does nothing when the agent TYPE has no write tool — and the report is then unrecoverable from the subagent transcript, which does not contain it.**

*   ⛔ **The trap is that the brief is correct.** A dispatch can carry the path, the skeleton-first instruction and the full rationale, and still produce a transcript-only answer, because the constraint that defeats it lives in the agent type rather than in the prose. The `Explore` type is documented as excluding `Write`, `Edit` and `NotebookEdit`; a probe dispatched that way **cannot** obey the invariant however well briefed. ⭐ **The tell is in the lane's own first line** — both lanes here opened by reporting the refusal, one citing `ToolSearch select:Write,Edit` → *"No matching deferred tools found"*. A lane that announces it could not write its report has told you the dispatch was wrong, not that it misbehaved.
*   ⛔⛔ **AND THE OBVIOUS RECOVERY DOES NOT WORK, WHICH IS THE HALF WORTH KNOWING.** The instinct is to mine the subagent's JSONL transcript for the report. ✅ **MEASURED here over two transcripts**: extracting the longest text block from each returned files that were **byte-identical at 43,072 chars, with zero `ran` marks and no `## Verdict` heading** — a shared preloaded hook block, not a report. Enumerating every text block over 2,000 chars showed each transcript holds only four: the harness preamble, the MCP instructions, the agent's system prompt, and **the conductor's own dispatch brief**. **The final report is delivered by the hand-back and is never written into the transcript file**, so there is nothing there to extract. ⭐ The identical byte counts across two differently-briefed lanes are what exposed it — *an implausible control is an instrument fault, not a finding* (`§PTF_A_TRUE_ANSWER_TO_THE_WRONG_QUESTION`, Addendum 6).
*   **Redirection, and it is mechanical rather than attentional**: choose the agent type by **what the brief asks the agent to produce**, not by what it asks it to read. A probe that must write a report needs a type with a write tool (`general-purpose`, `analyzer`, or a fork); `Explore` is for a sweep whose whole answer fits in the hand-back and is about to be consumed immediately. Where a read-only type is genuinely wanted, say in the brief that the answer returns by hand-back only, and **transcribe it on receipt before doing anything else** — the parent's context is then the only copy, and a clear or an overflow takes it.
*   ⚠️ **Stated, not enforced.** Nothing reddens when a brief names a path the dispatched type cannot write; the lane succeeds, the hand-back is complete and useful, and the only signal is a sentence inside the report. Per `§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`.
*   **Reason, measured**: two read-only probe lanes returned roughly 300KB of controlled analysis between them — 59 and 54 `ran` marks, positive controls on every zero — with neither report on disk. Recovering them cost a failed extraction, a diagnostic pass over both transcripts, and a full re-transcription from the parent's context. Had the parent's context ended first, both would have been lost with nothing on the filesystem or in the task list to show a gap.
