# Hook & Engine Pitfalls

## 1. hook_allow / hook_deny exit immediately — both exit 0
`hook_allow` and `hook_deny` (from lib.sh) call `exit 0`. Any code after them in the same branch NEVER runs. When multiple checks can match the same input, ordering determines which fires. Put side-effect logic (state clearing, counter resets) BEFORE stateless whitelists. **Both functions exit 0** — denial is communicated via JSON `permissionDecision: "deny"` in stdout, NOT via exit code. Tests that check hook behavior must parse the JSON output, not the exit status.

## 2. Always end hooks with explicit `exit 0`
Under `set -euo pipefail`, the script exits with the last command's exit code. If that's `jq`, a malformed input or race condition on `.state.json` causes non-zero exit → "hook error" in Claude Code. Every hook branch should end with `exit 0`.

## 3. `set -euo pipefail` + macOS bash 3.2
- `((VAR++))` returns exit code 1 when VAR is 0 (expression = 0 = falsy). Use `VAR=$((VAR + 1))` instead.
- Empty arrays with `-u` (nounset): `"${arr[@]}"` fails when array is empty. Guard with `${arr[@]+"${arr[@]}"}`.
- Unquoted variables with `-u`: always use `"${VAR:-}"` for potentially unset vars.

## 4. `loading=true` is the bootstrap escape hatch
`engine session activate` sets `loading=true` in `.state.json`. Both heartbeat and directive-gate hooks skip ALL enforcement when this flag is set. Skills MUST activate before reading standards/templates, or the reads get counted toward heartbeat/directive thresholds. `engine session phase` clears the flag.

## 5. `.state.json` read-modify-write is not atomic
`safe_json_write` protects the write (mkdir lock + atomic mv), but the read-before-write is unprotected. Two hooks reading the same state, transforming independently, and writing back will lose the first write. High-frequency fields (toolCallsByTranscript, pendingDirectives) are most at risk.

## 6. Hook execution order matters
PreToolUse hooks run in settings.json array order. Earlier hooks can block before later hooks run. The session-gate (whitelists tools without a session) is 5th — heartbeat (3rd) and directive-gate (4th) can block first, preventing the agent from ever reaching activation.

## 7. YAML frontmatter `description:` field must be quoted if it contains colons
The `yaml` npm package interprets bare `Triggers: "..."` as a nested mapping key, causing parse errors. Always quote the `description:` value in YAML frontmatter when it contains colons (e.g., `description: "Triggers: run a research cycle"`). Discovered in SKILL.md files — all 30 files were affected.

## 8. Bash defers SIGTERM to subshells until foreground child exits
When you `kill $subshell_pid`, bash delivers SIGTERM to the subshell — but the subshell defers it until its foreground child (e.g., `sleep`) completes. This breaks background timer patterns like `(sleep N; do_thing)& kill $!`. Use `timeout N command` instead, which directly kills the child process on expiry or early termination.

## 10. `hookEventName` is required for JSON `additionalContext` delivery
Hook output using `hookSpecificOutput.additionalContext` is **silently dropped** if `hookEventName` is missing from the JSON. No error, no warning — content just never reaches the LLM. The correct format:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "content here"
  }
}
```
All three hook types that support `additionalContext` (SessionStart, UserPromptSubmit, PostToolUse) require this field. Empirically validated 2026-02-13.

## 11. UserPromptSubmit output truncates at ~10K characters
Both plain stdout and JSON `additionalContext` for UserPromptSubmit hooks are hard-truncated at approximately 10,000 characters. Content beyond this point is silently dropped. Stay under 9K for safety margin. SessionStart and PostToolUse have no such limit (tested up to 100K). Use UserPromptSubmit for metadata/skill detection only, not bulk file delivery. Empirically validated 2026-02-13 using checkpoint-based testing with `claude -p`.

## 13. `| grep` pipelines crash under `set -euo pipefail` when no match
`grep` exits non-zero when it matches zero lines. Under `set -euo pipefail`, this kills the entire script — even when "no matches" is a valid outcome (e.g., no tmux sessions running, pane disappeared). Always add `|| true` after the pipeline: `cmd | grep 'pattern' | head -1 || true`. The `|| true` applies to the whole pipeline, catching any non-zero exit. Safe patterns that DON'T need `|| true`: `grep` inside `if` conditions (exit code is swallowed), `grep` with an explicit fallback (`|| echo "default"`). Only `| grep` is hazardous — `| sed`, `| awk`, `| cut` return 0 on empty input.

## 9. Deactivation gate tests need `currentPhase` set to a synthesis phase
When `.state.json` has no `currentPhase`, session.sh defaults to phase 0 → `EARLY_PHASE=true` → checklist gate and other synthesis-time gates are silently bypassed. Tests that exercise deactivation behavior (e.g., "blocks when checkPassed is not set") must set `"currentPhase": "4: Synthesis"` (or similar non-early phase) in the test's `.state.json` setup, or the gate under test will never fire.

## 15. Reference preloading depth and code fences
`resolve_refs()` scans preloaded files for bare `§CMD_*`, `§FMT_*`, `§INV_*` references and queues their target files for preloading. Two gotchas: (1) **Depth limit is 2** — CMD→CMD→FMT is the target chain. Deeper references are not followed. If you see a file not getting preloaded, check if it's at depth 3+. (2) **Code fence blocks are inert** — all `§` references inside ``` blocks are ignored (same as backtick escaping). Hub commands like `CMD_RUN_SYNTHESIS_PIPELINE` list sub-commands in JSON code blocks — those are documentation, not dependencies. If you need a reference to trigger preloading, move it outside code fences. (3) **Invoke vs. mention** — algorithm invocations ("Invoke §CMD_X with...") must use bare refs to trigger preloading. Documentation mentions ("Separated from `§CMD_X`") use backticked refs and are inert. See `¶INV_BACKTICK_INERT_SIGIL`.

## 14. SKILL_STATIC_FIELDS injection from real SKILL.md files in tests
When a test calls `session.sh activate` with a skill name that matches a real SKILL.md file (e.g., `"analyze"`, `"implement"`), `session.sh` parses that SKILL.md and injects its `phases`, `nextSkills`, `directives`, and template paths into `.state.json` via SKILL_STATIC_FIELDS. This overwrites any stub phases or test data the test set up. Only a problem when the test doesn't want the real skill's configuration — e.g., testing phase enforcement with custom phase arrays. **Mitigation**: Use non-existent skill names (e.g., `"fake-skill"`, `"test-skill"`) when the test needs full control over session parameters. Use real skill names only when testing the actual skill integration path.
