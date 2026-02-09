# Pitfalls

Known gotchas and traps when working with hooks. Read before modifying any hook.

### Hook ordering in the array matters — session gate MUST be first
**Context**: PreToolUse hooks execute in array order. The session gate (`pre-tool-use-session-gate.sh`) must run before heartbeat and overflow hooks because those hooks read `.state.json` which only exists after session activation.
**Trap**: Reordering the hooks array (in `settings.json` or during engine setup) so the session gate runs after heartbeat causes heartbeat to read a non-existent `.state.json`, producing silent `jq` errors or null values that bypass enforcement.
**Mitigation**: The hook array order is: 1) session-gate, 2) overflow, 3) heartbeat. After any hook array modification, verify this order in the installed `settings.json`.

### Hooks receive JSON on stdin — parse with jq, not grep
**Context**: Claude Code passes a JSON object on stdin with fields like `tool_name`, `tool_input`, `session_id`, `transcript_path`. Hooks must parse this to make allow/deny decisions.
**Trap**: Using `grep` or string matching on the raw JSON is brittle — field ordering is not guaranteed, and values may contain the search string in unexpected fields (e.g., `tool_input` containing "session.sh" as a string literal, not a command). This causes false positives in whitelist checks.
**Mitigation**: Always use `jq -r '.tool_name'`, `jq -r '.tool_input.command'` etc. to extract specific fields before matching.

### Hooks must exit 0 (allow) or output a deny message — there is no "warn" exit code
**Context**: PreToolUse hooks communicate via stdout. Empty stdout = allow. Non-empty stdout = deny (the message is shown to the agent). There is no separate warn channel.
**Trap**: A hook that prints a warning message but intends to allow the action will actually BLOCK it, because any stdout output is treated as a deny reason. This is the most common bug when adding new hooks.
**Mitigation**: For warnings, write to stderr (agent doesn't see it) or use a structured approach: the heartbeat hook uses a `reason` field in `.state.json` to track warn state across calls while still allowing the action.

### Fleet/tmux calls must be guarded — hooks run outside tmux too
**Context**: `¶INV_TMUX_AND_FLEET_OPTIONAL` requires all tmux interactions to fail gracefully. Hooks run in every Claude Code environment, not just fleet tmux sessions.
**Trap**: A hook that calls `tmux display-message` or `fleet.sh` without checking `$TMUX` will error when run in a plain terminal or VSCode, potentially blocking tool use if the error message goes to stdout.
**Mitigation**: Guard with `[ -n "${TMUX:-}" ]` before any tmux/fleet call, and always append `|| true` to fleet.sh invocations.

### Heredoc bodies trigger pattern matching — strip before grep
**Context**: Safety hooks use `grep -qE` with word-boundary patterns to detect destructive commands (e.g., `\brm\b.*-rf`, `\bgit\b.*push.*--force`). The hook receives the full bash command string including heredoc content.
**Trap**: Commands like `engine log sessions/.../LOG.md <<'EOF'\n## Entry\n*   Ran rm -rf to clean up\nEOF` trigger false positives because `rm -rf` appears in the heredoc body — which is data (log content), not an executable command. This is especially common with `engine log` calls that document destructive commands in session logs.
**Mitigation**: Strip heredoc bodies before pattern matching: `CMD="${CMD%%<<*}"`. This removes everything from the first `<<` onward. The stripping is greedy but safe — content after `<<` in Claude Code tool calls is always heredoc body, never executable commands.

### Per-agent counters use transcript_path as key — don't use PID
**Context**: The heartbeat hook tracks tool call counts per agent using `transcript_path` basename as the key in `.state.json`. This isolates main agent counts from sub-agent counts.
**Trap**: Using PID as the counter key fails because sub-agents launched via the Task tool may share the parent's PID in some execution models, or PIDs may be reused across context overflow restarts. Transcript paths are guaranteed unique per agent instance.
**Mitigation**: Always key per-agent state on `transcript_path`, not PID or session_id.
