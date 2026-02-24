# Dehydration — 2026_02_23_IDEAS_REBRAND

## What Was Built

### Transcript Message Ingestion Pipeline
Transcript JSONL is the single source of truth for messages. Periodic ingestion reads new lines using a byte-offset waterline, inserts into DB, advances offset.

**33 tests passing** across 3 test files.

#### New Files
| File | Purpose |
|------|---------|
| `tools/db/src/rpc/db-messages-upsert.ts` | Bulk insert messages for a session. Input: `{sessionId, messages[]}` |
| `tools/db/src/rpc/db-session-set-transcript.ts` | Store/update `transcript_path` and `transcript_offset` on session row |
| `tools/agent/src/rpc/agent-messages-ingest.ts` | Orchestrator: opens JSONL at byte offset, parses lines, bulk inserts, advances waterline |
| `tools/hooks/src/rpc/transform-hook-input.ts` | `transformKeys()` — snake_case→camelCase for raw Claude Code hook JSON. Used in `z.preprocess()` |
| `tools/db/src/rpc/__tests__/db-messages-upsert.test.ts` | Tests for bulk insert + setTranscript (8 tests) |
| `tools/agent/src/rpc/__tests__/agent-messages-ingest.test.ts` | Tests for waterline, incremental reads, partial lines, missing file (9 tests) |

#### Modified Files
| File | What Changed |
|------|-------------|
| `tools/db/src/schema.ts` | Added `transcript_path TEXT`, `transcript_offset INTEGER DEFAULT 0` to sessions. SCHEMA_VERSION 6→7 |
| `tools/db/src/rpc/types.ts` | Added `transcriptPath: string \| null`, `transcriptOffset: number` to Session interface |
| `tools/db/src/rpc/registry.ts` | Added imports for `db-messages-upsert.js`, `db-session-set-transcript.js` |
| `tools/agent/src/rpc/registry.ts` | Added import for `agent-messages-ingest.js` |
| `tools/hooks/src/rpc/hooks-post-tool-use.ts` | See details below |
| `tools/hooks/src/rpc/hooks-user-prompt.ts` | See details below |
| `tools/hooks/src/rpc/__tests__/hooks-post-tool-use.test.ts` | Updated for new behavior, added agent namespace to test context |

#### hooks-post-tool-use.ts Changes
1. Added `z.preprocess(transformKeys, ...)` — accepts raw Claude Code snake_case JSON
2. Made `effortId` and `sessionId` optional with DB resolution fallback
3. Added `.passthrough()` to schema (don't strip unknown Claude Code fields)
4. Added `transcriptPath`, `toolResponse`, `cwd` to schema
5. Fire-and-forget ingestion: `ctx.agent.messages.ingest({...}).catch(() => {})`
6. **Removed** `db.messages.append` call for AskUserQuestion dialogue (transcript is source of truth)
7. Kept `formatDialogueEntry()` for response value (bash hook uses it for DIALOGUE.md)

#### hooks-user-prompt.ts Changes
1. Added `z.preprocess(transformKeys, ...)` — accepts raw Claude Code snake_case JSON
2. Made `effortId` optional with DB resolution fallback
3. Added `.passthrough()`, `transcriptPath`, `cwd` to schema
4. Fire-and-forget ingestion when sessionId is available

---

## Open Issues / Tech Debt

### 1. `effortId` is a vestige in hook schemas
Claude Code's hook JSON does NOT contain `effort_id`. The field is always `undefined` from the plugin path. The DB resolution fallback always runs. Should remove `effortId` from both hook schemas entirely and always resolve from DB. Cleaner contract — accept what Claude Code sends, nothing more.

### 2. `sessionId` resolution gap
Claude Code sends `session_id` as a UUID string. Our DB uses integer IDs. The current resolution finds the active session from the active effort. But this means we can't distinguish between multiple concurrent sessions for the same effort (e.g., fleet agents). Future: may need to store Claude Code's UUID on the session row and look up by that.

### 3. Other hooks still expect old format
Only `hooks.postToolUse` and `hooks.userPrompt` have the snake→camel transform. Other hooks in `tools/hooks/src/rpc/` still expect camelCase + internal IDs:
- `hooks-session-start.ts`
- `hooks-pre-tool-use.ts`
- `hooks-post-tool-use-failure.ts`
- `hooks-permission-request.ts`
- `hooks-notification.ts`
- `hooks-subagent-start.ts` / `hooks-subagent-stop.ts`
- `hooks-stop.ts`
- `hooks-pre-compact.ts`
- `hooks-session-end.ts`
- etc.

The `transformKeys` utility in `transform-hook-input.ts` is ready to apply to all of them.

### 4. `db.effort.list` resolution is naive
The current effort resolution (`efforts.find(e => e.lifecycle === "active")`) returns the first active effort. If multiple efforts are active (fleet), this picks arbitrarily. Should filter by `cwd` → project → task → effort chain for accuracy.

---

## Pending Work — Next Sessions

### A. SubagentStart Hook Enhancement
**Context**: User wants subagents to get proper session setup.

Requirements:
- Create a DB session for each subagent (like SessionStart does for main agent)
- Add `subagent_type TEXT` and `subagent_id TEXT` columns to sessions table (schema v8)
- Selective preloading:
  - LOG templates: YES
  - CMD files: NO
  - Directives: YES but filtered by subagent type
- Directive filtering rules:
  - `Explore` agent: skip TESTING.md, load AGENTS.md
  - `builder` agent: load TESTING.md, PITFALLS.md
  - Other agents: TBD

Claude Code SubagentStart input:
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/Users/...",
  "hook_event_name": "SubagentStart",
  "agent_id": "agent-abc123",
  "agent_type": "Explore"
}
```

### B. Skills-as-Tools via Plugin skills_dir
**Context**: User wants to move from CLI commands to LLM-invocable skills.

Vision:
- `commands.effort.log` → `tools/plugin/skills/effort.log.md` → Tool(effort.log)
- `commands.effort.start` → `tools/plugin/skills/effort.start.md` → Tool(effort.start)
- `commands.effort.resume` → `tools/plugin/skills/effort.resume.md` → Tool(effort.resume)
- Skills are thin one-liners: "Log your progress periodically"
- Body is just `engine-rpc commands.log.append $ARGUMENTS`
- Daemon RPCs do the actual work
- PreToolUse fires naturally on Skill tool invocations
- Skills become documentation/guidance, not interactive prompts
- No MCP needed — plugin's skill discovery handles registration

Key insight: Skills become no-ops. The daemon RPC registry IS the tool registry. Skills just provide the description that tells the LLM when to invoke.

### C. Apply snake→camel transform to all remaining hooks
Straightforward but tedious — apply `z.preprocess(transformKeys, ...)` and `.passthrough()` to all hook schemas listed in Open Issue #3.

---

## Architecture Reference

### Waterline Mechanism
```
Session row: transcript_path="/path/to/uuid.jsonl", transcript_offset=4096
                                                            │
agent.messages.ingest(sessionId)                            │
  1. Read session → get path + offset                       │
  2. fs.openSync → fs.readSync(fd, buf, 0, size-offset, offset)
  3. Split on \n, keep only complete lines                  │
  4. Parse each JSON line → {role, content, toolName}       │
  5. db.messages.upsert(sessionId, messages[])              │
  6. db.session.setTranscript(sessionId, newOffset)  ───────┘
```

### Hook Input Flow (Plugin Path)
```
Claude Code event → stdin JSON (snake_case)
  → engine-rpc hooks.postToolUse (raw JSON as args)
  → daemon dispatch → z.preprocess(transformKeys) → camelCase
  → Zod validation (.passthrough() keeps extra fields)
  → handler(args, ctx)
    → resolve effortId from DB (args.effortId always undefined)
    → resolve sessionId from effort
    → fire-and-forget ingestion
    → return {heartbeatCount, pendingInjections, dialogueEntry}
```

### Test Commands
```bash
cd ~/.claude/engine/tools
npx vitest run db/src/rpc/__tests__/db-messages-upsert.test.ts
npx vitest run agent/src/rpc/__tests__/agent-messages-ingest.test.ts
npx vitest run hooks/src/rpc/__tests__/hooks-post-tool-use.test.ts
# All 33 tests should pass
```
