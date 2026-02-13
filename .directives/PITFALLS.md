# Hook & Engine Pitfalls

## 1. hook_allow / hook_deny exit immediately
`hook_allow` and `hook_deny` (from lib.sh) call `exit 0`. Any code after them in the same branch NEVER runs. When multiple checks can match the same input, ordering determines which fires. Put side-effect logic (state clearing, counter resets) BEFORE stateless whitelists.

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

## 9. Deactivation gate tests need `currentPhase` set to a synthesis phase
When `.state.json` has no `currentPhase`, session.sh defaults to phase 0 → `EARLY_PHASE=true` → checklist gate and other synthesis-time gates are silently bypassed. Tests that exercise deactivation behavior (e.g., "blocks when checkPassed is not set") must set `"currentPhase": "4: Synthesis"` (or similar non-early phase) in the test's `.state.json` setup, or the gate under test will never fire.
