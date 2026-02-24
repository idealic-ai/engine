# Hook RPC Handler Pitfalls

Known gotchas when working with hook RPC handlers in `src/rpc/`.

## 1. `sessionId` naming collision -- Claude's string vs engine's number

Claude Code sends `sessionId` as a string UUID on every hook event (part of `hookBase`). The engine stores sessions with numeric IDs in SQLite. Both are called "sessionId" in different contexts.

**Trap**: Using `input.sessionId` (Claude's UUID string) where the engine expects a numeric ID causes silent type mismatches. Queries return no results instead of erroring.

**Mitigation**: Use `resolveEngineIds(cwd, ctx)` to get the engine's numeric `engineSessionId`. Never pass `input.sessionId` to DB queries that expect a number. Name the engine's ID `engineSessionId` in handler code to avoid ambiguity.

## 2. `toolInput` is an object, not a string -- extract `.command` for Bash detection

Claude Code sends `toolInput` as a parsed JSON object (`z.record(z.string(), z.unknown())`), not a raw string. For Bash tool calls, the command text is at `toolInput.command`.

**Trap**: Treating `toolInput` as a string (e.g., `toolInput.includes("engine")`) fails silently -- objects don't have `.includes()`. The check returns `undefined` (falsy), and engine-command bypass logic never triggers.

**Mitigation**: For Bash tool calls, access `toolInput.command` as a string. For other tools, iterate `toolInput` keys/values. Always type-check: `typeof toolInput.command === "string"` before string operations.

## 3. `ctx.agent` may be undefined in tests -- use optional chaining

`RpcContext` includes an `agent` field for fleet identity, but it is not guaranteed to be populated in test environments or solo (non-fleet) usage.

**Trap**: Accessing `ctx.agent.id` without guarding throws a runtime TypeError that crashes the handler. Since hooks are fail-open by convention, this crash silently converts to an allow/no-op response, masking the bug.

**Mitigation**: Always use optional chaining: `ctx.agent?.id`. In tests, either mock `ctx.agent` or verify the handler degrades gracefully when it is `undefined`.

## 4. `transformKeys` only transforms top-level keys

The `transformKeys` preprocessor (applied by `hookSchema`) converts snake_case to camelCase on the top-level object only. Nested objects (like `toolInput` contents) are passed through as-is.

**Trap**: Expecting `toolInput.filePath` when Claude Code sent `tool_input.file_path` -- the outer key `tool_input` becomes `toolInput`, but the inner key `file_path` stays snake_case.

**Mitigation**: Access nested object keys in their original snake_case form: `toolInput.file_path`, not `toolInput.filePath`. Only top-level hook event fields are camelCase.

## 5. Fail-open: `resolveEngineIds` returns nulls -- handlers must guard

`resolveEngineIds` returns `{ projectId: null, effortId: null, engineSessionId: null }` when any link in the `cwd -> project -> effort -> session` chain is unresolvable. This is by design (fail-open).

**Trap**: Passing `null` IDs to DB queries without checking causes SQL errors or silent no-ops. A handler that assumes IDs are always valid will break for new projects, projects without active efforts, or during the gap between session creation and effort activation.

**Mitigation**: Guard every ID before use: `if (!ids.effortId) return defaultResponse;`. Follow the fail-open pattern established in `hooks-pre-tool-use.ts` -- return a permissive default when IDs are missing.
