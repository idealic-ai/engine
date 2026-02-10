# Testing Standards — Hooks

Rules for testing PreToolUse, PostToolUse, and lifecycle hooks. Tests live in `engine/scripts/tests/`, not in this directory.

## 1. Test File Mapping

| Hook | Test File |
|------|-----------|
| `pre-tool-use-heartbeat.sh` | `test-heartbeat.sh` |
| `pre-tool-use-overflow.sh` | `test-overflow.sh` |
| `pre-tool-use-session-gate.sh` | `test-session-gate.sh` |
| `post-tool-use-discovery.sh` | `test-post-tool-use-discovery.sh` |
| `user-prompt-submit-session-gate.sh` | `test-prompt-gate.sh` |
| `notification-*.sh`, `session-end-notify.sh` | `test-tmux.sh` (fleet notify integration) |

## 2. Running Hook Tests

```bash
# Run a single hook's tests
bash ~/.claude/engine/scripts/tests/test-heartbeat.sh

# Run all engine tests (includes hooks)
bash ~/.claude/engine/scripts/tests/run-all.sh
```

## 3. Hook Input Protocol

Hooks receive JSON on stdin from Claude Code. Tests must simulate this by piping JSON:

```bash
echo '{"tool_name": "Bash", "tool_input": {"command": "ls"}}' | bash "$HOOK"
```

*   **Allow**: Hook exits 0 with empty stdout.
*   **Deny**: Hook exits 0 with non-empty stdout (the message is shown to the agent).
*   **Important**: Any stdout output = deny. Write warnings to stderr, not stdout.

## 4. Sandbox Isolation (FAKE_HOME Pattern)

Hooks read `.state.json` via `session.sh find`, which resolves the active session from `$HOME/.claude/`. Tests MUST override HOME to prevent reading real sessions:

```bash
FAKE_HOME="$TMP_DIR/fake-home"
mkdir -p "$FAKE_HOME/.claude/scripts"
mkdir -p "$FAKE_HOME/.claude/hooks"
mkdir -p "$FAKE_HOME/.claude/tools/session-search"
mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

# Symlink real scripts into fake home
ln -sf "$REAL_HOME/.claude/engine/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
# ... etc

export HOME="$FAKE_HOME"
```

See `test-heartbeat.sh` for the full FAKE_HOME setup pattern.

## 5. `.state.json` Fixtures

Most hooks read fields from `.state.json`. Create minimal fixtures:

```bash
# Minimal .state.json for heartbeat tests
cat > "$SESSION_DIR/.state.json" <<JSON
{
  "pid": $$,
  "skill": "test",
  "loading": false,
  "currentPhase": "4: Testing Loop",
  "heartbeat": { "toolCallsSinceLog": 0 }
}
JSON
```

Update specific fields between assertions using `jq`:

```bash
jq '.heartbeat.toolCallsSinceLog = 5' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
```

## 6. Tmux/Fleet Guards

Hooks that call `fleet.sh` or tmux must be tested in two modes:

*   **Without tmux**: `unset TMUX; unset TMUX_PANE` — verify the hook degrades gracefully (`¶INV_TMUX_AND_FLEET_OPTIONAL`).
*   **With tmux**: Use `tmux -L "fleet-test$$"` test sockets — same pattern as `test-tmux.sh`.

## 7. Common Pitfalls

See `PITFALLS.md` in this directory for known gotchas. Key ones:

*   Hook ordering matters — session gate must be first in the array
*   Any stdout = deny (even accidental `echo` for debugging)
*   Use `jq` to parse stdin JSON, not grep
*   Guard all tmux calls with `[ -n "${TMUX:-}" ]`
