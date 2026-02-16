# Hook Pitfalls

Hook-specific pitfalls for `~/.claude/engine/hooks/`. See also `~/.claude/.directives/PITFALLS.md` for engine-wide pitfalls.

## 1. `hook_allow` / `hook_deny` exit immediately
`hook_allow` and `hook_deny` (from `lib.sh`) call `exit 0`. Any code after them in the same branch NEVER runs. When multiple checks can match the same input, ordering determines which fires. Put side-effect logic (state clearing, counter resets) BEFORE stateless whitelists.

**Bug found 2026-02-10**: In `pre-tool-use-directive-gate.sh`, the `~/.claude/*` whitelist called `hook_allow` before the `pendingDirectives` clearing logic. Directives under `~/.claude/` could never be cleared. Fixed by swapping block order.

## 2. Always end hooks with explicit `exit 0`
Under `set -euo pipefail`, the script exits with the last command's exit code. If that's `jq` or `tmux`, a malformed input or race condition on `.state.json` causes non-zero exit → "hook error" in Claude Code.

**Audit 2026-02-10**: All 17 hooks now end with explicit `exit 0`. 5 hooks were missing it:
- `pane-focus-style.sh` — ended with tmux command (REAL RISK: tmux failure leaks non-zero)
- `pre-tool-use-heartbeat.sh` — ended with `main` call (defensive: all paths exit internally)
- `pre-tool-use-overflow.sh` — ended with `main` call (defensive: all paths exit internally)
- `pre-tool-use-one-strike.sh` — ended with `hook_allow` (defensive: hook_allow exits internally)
- `pre-tool-use-session-gate.sh` — ended with `hook_deny` (defensive: hook_deny exits internally)

## 3. `set -euo pipefail` + macOS bash 3.2
- `((VAR++))` returns exit code 1 when VAR is 0 (expression = 0 = falsy). Use `VAR=$((VAR + 1))`.
- Empty arrays with `-u` (nounset): `"${arr[@]}"` fails when array is empty. Guard with `${arr[@]+"${arr[@]}"}`.
- Unquoted variables with `-u`: always use `"${VAR:-}"` for potentially unset vars.

## 4. Hook execution order matters
PreToolUse and PostToolUse hooks run in `settings.json` array order. Earlier hooks can block before later hooks run.

**PreToolUse** (current order):
1. `pre-tool-use-one-strike` — destructive command guard
2. `pre-tool-use-overflow-v2` — context overflow protection + heartbeat + directive gate (consolidated rule engine)
3. `pre-tool-use-session-gate` — session activation requirement

**PostToolUse** (current order):
1. `post-tool-use-injections` — delivers stashed allow-urgency content via `additionalContext`
2. `post-tool-use-discovery` — directive file discovery for touched directories
3. `post-tool-use-details-log` — auto-logs AskUserQuestion interactions to DETAILS.md
4. `post-tool-use-heartbeat` — heartbeat counter increment

**Implication**: PreToolUse hook 2 (overflow-v2) consolidates heartbeat, directive-gate, and overflow into a single rule engine. It can block BEFORE session-gate runs. Skills MUST activate before loading standards (so `loading=true` is set before overflow-v2 fires).

**Mitigation**: After any hook array modification, verify the order in the installed `settings.json`.

## 5. `.state.json` read-modify-write is not atomic
`safe_json_write` protects the write (mkdir lock + atomic mv), but the read-before-write is unprotected. Two hooks reading the same state, transforming independently, and writing back will lose the first write. High-frequency fields (`toolCallsByTranscript`, `pendingDirectives`) are most at risk.

## 6. `loading=true` is the bootstrap escape hatch
`engine session activate` sets `loading=true` in `.state.json`. Both heartbeat and directive-gate hooks skip ALL enforcement when this flag is set. Skills MUST activate before reading standards/templates, or the reads get counted toward heartbeat/directive thresholds. `engine session phase` clears the flag.

## 7. Hooks receive JSON on stdin — parse with jq, not grep
Claude Code passes a JSON object on stdin with fields like `tool_name`, `tool_input`, `session_id`, `transcript_path`. Hooks must parse this to make allow/deny decisions.
**Trap**: Using `grep` or string matching on the raw JSON is brittle — field ordering is not guaranteed, and values may contain the search string in unexpected fields (e.g., `tool_input` containing "session.sh" as a string literal, not a command). This causes false positives in whitelist checks.
**Mitigation**: Always use `jq -r '.tool_name'`, `jq -r '.tool_input.command'` etc. to extract specific fields before matching.

## 8. Hooks must exit 0 (allow) or output a deny message — there is no "warn" exit code
PreToolUse hooks communicate via stdout. Empty stdout = allow. Non-empty stdout = deny (the message is shown to the agent). There is no separate warn channel.
**Trap**: A hook that prints a warning message but intends to allow the action will actually BLOCK it, because any stdout output is treated as a deny reason. This is the most common bug when adding new hooks.
**Mitigation**: For warnings, write to stderr (agent doesn't see it) or use a structured approach: the heartbeat hook uses a `reason` field in `.state.json` to track warn state across calls while still allowing the action.

## 9. Fleet/tmux calls must be guarded — hooks run outside tmux too
`¶INV_TMUX_AND_FLEET_OPTIONAL` requires all tmux interactions to fail gracefully. Hooks run in every Claude Code environment, not just fleet tmux sessions.
**Trap**: A hook that calls `tmux display-message` or `fleet.sh` without checking `$TMUX` will error when run in a plain terminal or VSCode, potentially blocking tool use if the error message goes to stdout.
**Mitigation**: Guard with `[ -n "${TMUX:-}" ]` before any tmux/fleet call, and always append `|| true` to fleet.sh invocations.

## 10. Heredoc bodies trigger pattern matching — strip before grep
Safety hooks use `grep -qE` with word-boundary patterns to detect destructive commands (e.g., `\brm\b.*-rf`, `\bgit\b.*push.*--force`). The hook receives the full bash command string including heredoc content.
**Trap**: Commands like `engine log sessions/.../LOG.md <<'EOF'\n## Entry\n*   Ran rm -rf to clean up\nEOF` trigger false positives because `rm -rf` appears in the heredoc body — which is data (log content), not an executable command. This is especially common with `engine log` calls that document destructive commands in session logs.
**Mitigation**: Strip heredoc bodies before pattern matching: `CMD="${CMD%%<<*}"`. This removes everything from the first `<<` onward. The stripping is greedy but safe — content after `<<` in Claude Code tool calls is always heredoc body, never executable commands.

## 11. UserPromptSubmit stdout causes "hook error" display — use additionalContext JSON
`UserPromptSubmit` hooks can inject context into Claude's conversation. The docs say "stdout is added as context" on exit 0, and JSON with `hookSpecificOutput.additionalContext` is "added more discretely."
**Trap**: ANY stdout from a `UserPromptSubmit` hook — even valid JSON, even with exit 0 — causes Claude Code to display "UserPromptSubmit hook error" in the terminal. This is a known bug ([#13912](https://github.com/anthropics/claude-code/issues/13912), dupes #12151, #10964). The `{"hookSpecificOutput":{"message":$msg}}` pattern (undocumented field) triggers it on every prompt.
**Mitigation**: Use the documented `additionalContext` field with `hookEventName`:
```bash
jq -n --arg msg "$MESSAGE" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
```
This injects context without the error label. If the bug is fixed upstream, plain stdout may also work, but `additionalContext` is the safer path.
**Discovered**: 2026-02-10 in `user-prompt-state-injector.sh` and `user-prompt-submit-session-gate.sh`.

## 12. `permissionDecisionReason` from allow-path hooks does NOT reach model context
PreToolUse hooks that return `exit 0` (allow) can set `permissionDecisionReason` in their JSON output. This field appears in Claude Code's internal permission system but is NOT surfaced as a `system-reminder` to the model.
**Trap**: Building content injection rules with `urgency: "allow"` in `injections.json` — the content is prepared, the rule evaluates, but the model never sees it. The allow path silently drops content.
**Mitigation (original)**: Use `urgency: "block"` with a whitelist for content delivery. The block path places content in the error message, which IS visible to the model as a `system-reminder`. Whitelist critical tools (logging, session management, standards reads) so they bypass the block.
**Fix (2026-02-12)**: Implemented stash-and-deliver via PostToolUse `additionalContext`. PreToolUse `_deliver_allow_rules()` now stashes content to `.state.json:pendingAllowInjections`. New `post-tool-use-injections.sh` hook reads the stash, delivers via PostToolUse `additionalContext` (which IS surfaced as `<system-reminder>`), and clears the stash. This resolves the allow-path dead end for all 4 affected injection rules.
**Discovered**: 2026-02-11, audit of `directive-autoload` injection rule.

## 16. SessionStart preloadedFiles must match directive-autoload paths exactly
After `session-start-restore.sh` clears and re-seeds `preloadedFiles` in `.state.json`, the paths must use the same tilde-prefix format (`~/.claude/...`) that `directive-autoload` in `overflow-v2.sh` checks against.
**Trap**: If SessionStart records absolute paths (e.g., `/Users/name/.claude/.directives/COMMANDS.md`) but directive-autoload compares against tilde paths (`~/.claude/.directives/COMMANDS.md`), the dedup check fails silently and standards get injected twice — wasting ~900 lines of context per duplicate.
**Mitigation**: Always use tilde-prefix paths in `preloadedFiles`. The existing `overflow-v2.sh` preload dedup (lines 609-617) normalizes to tilde for comparison — match that format in SessionStart seeding.
**Discovered**: 2026-02-12, during SessionStart dedup fix implementation.

## 13. PostToolUse discovery deduplicates by basename, not full path
`post-tool-use-discovery.sh` checks if a directive file is already in `pendingDirectives` or `discoveredDirectives` by comparing basenames (e.g., `INVARIANTS.md`). If a parent-level `INVARIANTS.md` was already discovered, a child-level `INVARIANTS.md` with different content is silently skipped.
**Trap**: Projects with multi-level `.directives/` structures (e.g., `packages/sdk/.directives/INVARIANTS.md` and `.directives/INVARIANTS.md`) won't get child-level overrides loaded. This violates `¶INV_DIRECTIVE_STACK` which requires cumulative loading.
**Mitigation**: Change deduplication to use full paths instead of basenames. Until fixed, child-level directives with the same filename as already-discovered parent directives will be invisible.
**Discovered**: 2026-02-11, audit of hook injection chain.

## 14. Two PreToolUse hooks cause double "error" noise per tool call
The engine has both `pre-tool-use-heartbeat.sh` and `pre-tool-use-overflow-v2.sh` registered as separate PreToolUse hooks. Both fire on every tool call, and both write diagnostic output to stderr. Claude Code labels each stderr output as "PreToolUse:Bash hook error" — so users see 2 "error" messages per Bash call even when everything is working.
**Trap**: Users interpret "hook error" as something broken. The double-fire also doubles evaluation overhead.
**Mitigation**: Consolidate heartbeat into the unified rule engine (`overflow-v2.sh`) as a rule in `injections.json`. This eliminates the standalone heartbeat hook and the double-fire pattern.
**Discovered**: 2026-02-11, user observation during audit session.

## 17. settings.json hook paths must resolve — missing file = silent "hook error"
`settings.json` registers hooks by file path (e.g., `~/.claude/hooks/my-hook.sh` or `~/.claude/engine/hooks/my-hook.sh`). If the file doesn't exist at that path (missing symlink, wrong directory), Claude Code gets exit 127 (file not found) and displays "PostToolUse:X hook error" or "PreToolUse:X hook error" in the terminal.
**Trap**: The hook itself is fine — it's just not where `settings.json` says it is. The error is invisible in tests (which invoke the hook directly) and invisible in the transcript (Claude Code doesn't log it as a system-reminder). You only see it in the terminal UI. For PostToolUse hooks, the error may be masked by other hooks that succeed for the same tool — it's only visible for tools where the broken hook is the only one producing output.
**Mitigation**: After adding or moving hooks, verify the path in `settings.json` resolves to a real file. Run `engine doctor` which checks all registered hook paths. Two path conventions exist: `~/.claude/hooks/` (symlinked, per-file override support) and `~/.claude/engine/hooks/` (direct path to engine). Don't mix them for the same hook.
**Discovered**: 2026-02-15 — `post-tool-use-injections.sh` was registered at `~/.claude/engine/hooks/` but had no symlink at `~/.claude/hooks/`. Caused "PostToolUse:Skill hook error" on every Skill tool invocation.

## 18. `local` keyword is illegal inside subshells — use plain variables
Bash `local` is only valid inside functions. A `( ... )` subshell is NOT a function — `local` inside it triggers `local: can only be used in a function` under `set -euo pipefail` (and silently fails with `|| true`). Variables in subshells are already scoped — they don't leak to the parent.
**Bug found 2026-02-15**: `post-tool-use-templates.sh` lines 81-93 used `local` inside a `( ... ) || true` subshell. `set -u` caught unbound variables after `local` failed, subshell crashed, `|| true` silenced everything. `pendingPreloads` and `§` ref scanning never ran. Fix: remove all `local` keywords from the subshell block.
**Mitigation**: Audit any `( ... )` blocks for `local` usage. If you need scoped variables in a subshell, just assign them — subshell scoping handles it. Only use `local` inside `function_name() { ... }` bodies.

## 19. `pendingPreloads` entries persist forever if file is already in `preloadedFiles`
`_claim_and_preload` in `pre-tool-use-overflow-v2.sh` skips files already in `preloadedFiles` (dedup) — but the skip path never removes the file from `pendingPreloads`. When one hook adds to both `preloadedFiles` AND `pendingPreloads` simultaneously (e.g., `post-tool-use-templates.sh` line 73), the preload rule fires every tool call, finds nothing to claim, and the stale entries remain forever — causing repeated re-delivery of the same CMD files.
**Bug found 2026-02-15**: Caused by the subshell fix (#18). Before the fix, the subshell crashed silently so `pendingPreloads` was never populated. After the fix, it populated correctly — but exposed this pre-existing race in the claim logic.
**Fix**: `_claim_and_preload` now tracks `stale_pending` files (already preloaded but still in pendingPreloads) and removes them even when nothing new is claimed.

## 20. Hook files lose +x permission when overwritten — Claude Code can't execute them
Claude Code executes hooks as commands (not via `zsh <file>`). If a hook file is overwritten (e.g., by the Write tool, which creates files with `644` permissions), the execute bit is lost. Claude Code gets `EACCES` or exit 126/127 and displays "{event}:{tool} hook error" on every matching tool call.
**Trap**: Manual testing via `zsh ~/.claude/hooks/my-hook.sh` PASSES because the interpreter is specified explicitly — the file doesn't need +x. The error only manifests in production (Claude Code executing the hook directly). This makes the bug invisible during development.
**Mitigation**: After editing hook files, run `chmod +x <file>`. Or use Edit tool (preserves permissions) instead of Write tool (resets to 644). Add a `chmod +x` step to any hook-creation workflow.
**Discovered**: 2026-02-16 — `post-tool-use-templates.sh` was overwritten during implementation, lost +x. "PostToolUse:Bash hook error" appeared on every Bash call. Debug traces never appeared because the hook was never invoked.

## 21. PostToolUse hooks receive data via stdin JSON, not env vars
PostToolUse hooks receive a JSON object on stdin with `tool_name`, `tool_input`, `tool_response` fields. The env vars `TOOL_NAME` and `TOOL_INPUT` are NOT set for PostToolUse hooks (they may be set for PreToolUse).
**Trap**: A hook that reads `${TOOL_NAME:-}` from env gets empty string, misclassifies the tool, and exits early. The hook appears to work (exits 0, no errors) but never processes any tool calls. Combined with pitfall #20 (lost +x), the hook silently does nothing — no errors, no output, no effect.
**Mitigation**: Read tool info from stdin: `INPUT=$(cat); TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')`. See `post-tool-use-phase-commands.sh` for the correct pattern.
**Discovered**: 2026-02-16 — `post-tool-use-templates.sh` used env vars. After fixing +x, the hook fired but `TOOL` was always empty. Fixed by reading from stdin.

## 15. Per-agent counters use transcript_path as key — don't use PID
The heartbeat hook tracks tool call counts per agent using `transcript_path` basename as the key in `.state.json`. This isolates main agent counts from sub-agent counts.
**Trap**: Using PID as the counter key fails because sub-agents launched via the Task tool may share the parent's PID in some execution models, or PIDs may be reused across context overflow restarts. Transcript paths are guaranteed unique per agent instance.
**Mitigation**: Always key per-agent state on `transcript_path`, not PID or session_id.
