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
