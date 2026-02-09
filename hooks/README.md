# Hooks

Claude Code lifecycle hooks for the workflow engine. Installed to `~/.claude/hooks/` via symlinks during engine setup.

## Execution Model

Hooks fire at specific points in the Claude Code lifecycle. PreToolUse hooks can **block** tool calls by outputting a deny message to stdout. Other hooks are fire-and-forget.

| Hook Type | Fires When | Can Block? |
|-----------|-----------|------------|
| `PreToolUse` | Before every tool call | Yes — non-empty stdout = deny |
| `PostToolUse` | After a tool call succeeds | No |
| `UserPromptSubmit` | When the user hits Enter | No |
| `Notification` | On attention state changes | No |
| `Stop` | When Claude's turn ends | No |
| `SessionEnd` | When the Claude session exits | No |

**Ordering matters for PreToolUse**: Hooks execute in array order from `settings.json`. The session gate must run first — other hooks read `.state.json` which only exists after session activation.

## Hook Catalog

### PreToolUse (6 hooks)

| Hook | Purpose |
|------|---------|
| `pre-tool-use-session-gate.sh` | Blocks non-whitelisted tools when no session is active. Forces `session.sh activate` before work begins. |
| `pre-tool-use-overflow.sh` | Blocks all tools when context usage exceeds the overflow threshold. Forces `/dehydrate` to save state. |
| `pre-tool-use-heartbeat.sh` | Tracks tool calls per agent via per-transcript counters. Warns, then blocks, if the agent hasn't logged recently. |
| `pre-tool-use-one-strike.sh` | Blocks destructive bash commands on first attempt with an educational warning. Allows on retry (same pattern type) within the session. |
| `pre-tool-use-directive-gate.sh` | Enforces reading of directive files discovered by `post-tool-use-discovery.sh`. Blocks after N tool calls if pending directives remain unread. |
| _installed order_ | session-gate → overflow → heartbeat → one-strike → directive-gate |

### PostToolUse (3 hooks)

| Hook | Purpose |
|------|---------|
| `post-tool-use-discovery.sh` | Tracks directories touched by tool calls. Discovers directive files (README, CHECKLIST, PITFALLS, INVARIANTS, TESTING) via walk-up search. |
| `post-tool-complete-notify.sh` | No-op placeholder — agent is still working between tool calls, so no notification state change. |
| `post-tool-failure-notify.sh` | No-op placeholder — tool failure doesn't stop the agent, so no notification state change. |

### UserPromptSubmit (3 hooks)

| Hook | Purpose |
|------|---------|
| `user-prompt-state-injector.sh` | Injects runtime context into the agent's prompt: current time, session info, skill/phase, heartbeat state. |
| `user-prompt-submit-session-gate.sh` | Instructs the agent to load standards and activate a session when no session is active. |
| `user-prompt-working.sh` | Sends "working" notification state when the user submits a prompt, before Claude processes. |

### Notification / Lifecycle (4 hooks)

| Hook | Purpose |
|------|---------|
| `notification-attention.sh` | Sends "unchecked" state when Claude needs user input. |
| `notification-idle.sh` | Clears working state when Claude is idle/waiting. |
| `pane-focus-style.sh` | Sets focused tmux pane to black background, unfocused to status tint. |
| `stop-notify.sh` | Sends "done" notification when Claude's turn ends. |
| `session-end-notify.sh` | Sends "done" notification when the Claude session exits. |

## Key Patterns

### Heredoc Stripping (one-strike hook)

The one-strike hook strips heredoc bodies before pattern matching:

```bash
CMD="${CMD%%<<*}"
```

**Why**: Commands like `engine log ... <<'EOF' ... rm -rf ... EOF` contain destructive patterns in the heredoc body (which is data, not executable commands). Without stripping, these trigger false positives. The `%%<<*` expansion removes everything after the first `<<`.

**Accepted trade-off**: Stripping is greedy — content after `<<` is always removed. This is safe because `<<` in Claude Code tool calls always introduces a heredoc, never a bitwise shift or comparison.

### One-Strike Warning Model

Destructive commands are blocked on first attempt with an educational message, then allowed on retry:

1. Agent calls `rm -rf /tmp/foo`
2. Hook blocks with explanation: "This is a destructive command. If you're sure, try again."
3. Agent retries `rm -rf /tmp/foo`
4. Hook allows (pattern already warned for this session)

State is PID-scoped: warning files at `/tmp/claude-hook-warned-$PID-pattern-$INDEX`. Each destructive pattern has a numeric index (0=rm, 1=git push --force, 2=git reset --hard, etc.).

### Session Gate Whitelisting

The session gate allows specific tools without session activation:

- `Read(~/.claude/*)` — Loading standards
- `Bash(engine *)` — Session/log/tag operations
- `AskUserQuestion` — User interaction
- `Skill` — Skill invocation

All other tool calls are blocked until `session.sh activate` succeeds.

## Testing

Hook tests live in `~/.claude/engine/scripts/tests/`:

| Test File | Hook | Tests |
|-----------|------|-------|
| `test-one-strike.sh` | `pre-tool-use-one-strike.sh` | 66 tests — destructive patterns, heredoc false-positives, boundary conditions |
| `test-state-injector.sh` | `user-prompt-state-injector.sh` | 18 tests — context injection, fleet detection |
| `test-session-gate.sh` | `pre-tool-use-session-gate.sh` | 30 tests — whitelisting, blocking, session lifecycle |
| `test-post-tool-use-discovery.sh` | `post-tool-use-discovery.sh` | 17 tests — tool filtering, dir tracking, soft/hard discovery, dedup |
| `test-pre-tool-use-directive-gate.sh` | `pre-tool-use-directive-gate.sh` | 15 tests — early exits, whitelists, pending clearing, counter enforcement |

Total: 161 tests across 5 hook suites.

## Related Files

- `PITFALLS.md` — Known gotchas when working with hooks
- `~/.claude/scripts/lib.sh` — Shared utilities sourced by hooks (fleet notification, JSON helpers)
- `~/.claude/engine/scripts/tests/test-helpers.sh` — Test infrastructure for hook testing
