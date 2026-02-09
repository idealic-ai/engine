# Contributing to Hooks

Guide for creating, modifying, and testing workflow engine hooks.

## Anatomy of a Hook

Every hook is a bash script that receives tool call context via environment variables:

| Variable | Content | Available In |
|----------|---------|-------------|
| `TOOL_NAME` | Tool being called (e.g., `Bash`, `Read`, `Write`) | PreToolUse, PostToolUse |
| `TOOL_INPUT` | JSON string of tool parameters | PreToolUse, PostToolUse |
| `TOOL_OUTPUT` | Tool result (stdout) | PostToolUse only |
| `SESSION_DIR` | Active session directory (if any) | All hooks |

### Hook Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Early exit — fast no-op for irrelevant tool calls
TOOL="${TOOL_NAME:-}"
[[ "$TOOL" == "Read" || "$TOOL" == "Glob" || "$TOOL" == "Grep" ]] && exit 0

# 2. Source shared utilities
source "$(dirname "$0")/../scripts/lib.sh" 2>/dev/null || true

# 3. Read session state (handle absence)
STATE_FILE="${SESSION_DIR:+$SESSION_DIR/.state.json}"
if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  exit 0  # No session — no-op
fi

# 4. Your hook logic here
# For PreToolUse: output to stdout to DENY, silent exit 0 to ALLOW
# For PostToolUse: fire-and-forget, exit code ignored
```

## Creating a New Hook

1. **Write the script** in `~/.claude/engine/hooks/` following the template above
2. **Make it executable**: `chmod +x hooks/my-hook.sh`
3. **Register in settings.json**: Add to the appropriate hook array in `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         { "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/my-hook.sh" }] }
       ]
     }
   }
   ```
4. **Test it**: Write tests in `scripts/tests/test-my-hook.sh` following the patterns in `TESTING.md`
5. **Document it**: Add an entry to the Hook Catalog table in `hooks/README.md`

## Ordering Rules

- **PreToolUse**: Order matters. Session gate MUST be first. See `¶INV_HOOK_ORDERING_MATTERS` in `INVARIANTS.md`.
- **PostToolUse**: Order generally doesn't matter — hooks are fire-and-forget.
- **UserPromptSubmit**: Order matters for state injection — `state-injector` should run before `session-gate`.

## Modifying Existing Hooks

1. **Read PITFALLS.md first** — known gotchas that apply to hook modifications
2. **Run existing tests** before and after changes: `bash scripts/tests/test-<hook-name>.sh`
3. **Preserve idempotency** — see `¶INV_HOOK_IDEMPOTENT` in `INVARIANTS.md`
4. **Test with fleet** (if applicable): hooks that interact with tmux/fleet must fail gracefully without it (`¶INV_TMUX_AND_FLEET_OPTIONAL`)

## Debugging Hooks

- **Check stderr**: Hook stderr goes to Claude Code's debug log. Add `echo "DEBUG: ..." >&2` for diagnostics.
- **Temporary logging**: `echo "$(date): hook fired" >> /tmp/hook-debug.log`
- **Simulate tool calls**: Set `TOOL_NAME` and `TOOL_INPUT` environment variables, then run the hook directly:
  ```bash
  TOOL_NAME=Bash TOOL_INPUT='{"command":"ls"}' bash hooks/my-hook.sh
  ```

## Related Files

- `README.md` — Hook catalog and execution model
- `INVARIANTS.md` — Behavioral rules for hooks
- `PITFALLS.md` — Known gotchas
- `TESTING.md` — Testing guide
- `~/.claude/engine/scripts/tests/test-helpers.sh` — Test infrastructure
