# Hooks Architecture (v3)

Hook RPC handlers in `src/rpc/`. Called by bash shim hooks via the daemon's Unix socket. Each hook is a single RPC round-trip: bash sends event data, daemon returns decisions + content, bash acts on the response.

**Source of truth**: `~/.claude/engine/docs/SQLITE_DAEMON_VISION.md` (§5 Hook Architecture).

---

## Three-Layer Model

Hooks operate across three distinct state layers. Each hook touches one or more layers.

### Session Layer (Context Window)

Ephemeral. 1:1 with a Claude process. Created on start, ended on overflow or natural close. **Never resumed** — effort resumption replaces session resumption.

*   **DB table**: `sessions` (id, effort_id, prev_session_id, heartbeat_counter, context_usage, loaded_files, dehydration_payload)
*   **Owns**: heartbeat counter, context usage tracking, loaded files list, dehydration payload
*   **Lifecycle**: created → active → ended. No "resumed" state.

### Effort Layer (Skill Invocation)

Persistent across sessions. Running `/brainstorm`, `/implement`, or `/fix` creates an effort. Survives context overflow — new sessions inherit the same effort.

*   **DB table**: `efforts` (id, task_id, skill, mode, ordinal, lifecycle, current_phase, discovered_directives, metadata)
*   **Owns**: phase progression, discovered directives, skill config, artifacts (logs, plans, debriefs), dehydrated context (for resumption)
*   **Lifecycle**: active → finished. Binary.

### Task Layer (Work Container)

Permanent. Identified by directory path. Accumulates efforts. **Never finishes** — active/dormant derived from efforts.

*   **DB table**: `tasks` (dir_path, project_id, title, keywords)
*   **Owns**: nothing mutable. Pure container.

---

## Shared Infrastructure

### Common Fields (`hookBase`)

All 15 hook events receive these 5 fields from Claude Code on stdin (snake_case, auto-transformed to camelCase by `transformKeys`):

| Field | Type | Description |
|-------|------|-------------|
| `sessionId` | `string` | Claude's session UUID. **Not** the engine's numeric session ID. |
| `transcriptPath` | `string` | Path to the conversation transcript file. |
| `cwd` | `string` | Current working directory (project path). |
| `permissionMode` | `string` | Claude Code permission mode (e.g., `default`). |
| `hookEventName` | `string` | Event name (e.g., `PreToolUse`, `PostToolUse`). |

Defined in `src/rpc/hook-base-schema.ts`. Handlers extend these via `hookSchema()`.

### `hookSchema(shape)` Helper

Builds a Zod schema for a hook event by extending `hookBase` with event-specific fields. Applies `transformKeys` (snake_case to camelCase) as a Zod preprocess step automatically.

```ts
import { hookSchema } from "./hook-base-schema.js";

const schema = hookSchema({
  toolName: z.string(),
  toolInput: z.record(z.string(), z.unknown()),
  toolUseId: z.string(),
});
```

### `resolveEngineIds(cwd, ctx)` Utility

Bridges Claude Code's `cwd` to the engine's numeric IDs: `cwd` -> `projectId` -> `effortId` -> `engineSessionId`. Defined in `src/rpc/resolve-engine-ids.ts`.

*   **Agent-aware**: Reads `AGENT_ID` from `ctx.env` (injected per-request by `rpc-cli`) to resolve agent-specific efforts in multi-agent fleet scenarios. Falls back to latest effort when no `AGENT_ID` is set.
*   **Fail-open**: Returns `{ projectId: null, effortId: null, engineSessionId: null }` for any unresolvable link in the chain. Handlers must guard against null IDs.

---

## Hook Reference (by Layer)

### Session-Layer Hooks

These create, monitor, or end context windows.

*   **hooks.sessionStart** (`hooks-session-start.ts`)
  *   **Fires**: Claude process startup (new window or after `/clear`)
  *   **Input**: hookBase + `{ source, model?, agentType? }`
  *   **Behavior**: Resolve engine IDs via `resolveEngineIds(cwd, ctx)`. Find active effort by agentId. If found, find or create session for that effort. Return effort context (skill, phase, filesToPreload, dehydratedContext, skillConfig).
  *   **Returns**: `{ found, effortId, sessionId, skill, phase, filesToPreload, dehydratedContext, skillConfig }`
  *   **Layer touches**: Session (create), Effort (read), Agent (read)
  *   **Key invariant**: Always creates a new session. Sessions are never resumed.

*   **hooks.sessionEnd** (`hooks-session-end.ts`) — STUB
  *   **Fires**: Claude session ends (interrupt or natural)
  *   **Input**: hookBase + `{ reason }`
  *   **Planned behavior**: Set `sessions.ended_at`. Update `agents.status = 'done'`. Notify fleet.
  *   **Layer touches**: Session (end), Agent (status update)

*   **hooks.preCompact** (`hooks-pre-compact.ts`) — STUB
  *   **Fires**: Before auto-compaction (matcher: `auto` only, not manual `/compact`)
  *   **Input**: hookBase + `{ trigger, customInstructions }`
  *   **Planned behavior**: Kill Claude. No dehydration — that's a preToolUse/postToolUse concern. Set `sessions.ended_at`. Write restart prompt.
  *   **Layer touches**: Session (end)
  *   **Key invariant**: preCompact = kill only. No dehydration logic.

### Effort-Layer Hooks

These monitor or update skill invocation state.

*   **hooks.preToolUse** (`hooks-pre-tool-use.ts`)
  *   **Fires**: Before every tool call
  *   **Input**: hookBase + `{ toolName, toolInput (object), toolUseId }`
  *   **Behavior**: Resolve engine IDs via `resolveEngineIds(cwd, ctx)`. Bypass for engine commands. Increment heartbeat. Check heartbeat threshold (block at 10). Check overflow (warn at 90%). Evaluate custom guard rules from effort metadata.
  *   **Returns**: `{ allow, heartbeatCount, contextUsage, overflowWarning, pendingPreloads, firedRules, reason? }`
  *   **Layer touches**: Session (heartbeat increment, context usage update), Effort (read metadata/guards)
  *   **Key invariant**: Fail-open — if effort or session not found, returns `allow: true`.

*   **hooks.postToolUse** (`hooks-post-tool-use.ts`)
  *   **Fires**: After every successful tool call
  *   **Input**: hookBase + `{ toolName, toolInput (object), toolResponse, toolUseId }`
  *   **Behavior**: Resolve engine IDs via `resolveEngineIds(cwd, ctx)`. Read heartbeat. Clear pending injections from effort metadata. If AskUserQuestion: format and store dialogue entry in messages table. (Planned: directive discovery via cross-namespace dispatch to `agent.directives.discover`.)
  *   **Returns**: `{ heartbeatCount, pendingInjections, dialogueEntry }`
  *   **Layer touches**: Session (read heartbeat), Effort (read/clear metadata), Messages (append dialogue)

*   **hooks.postToolUseFailure** (`hooks-post-tool-use-failure.ts`) — STUB
  *   **Fires**: When a tool call fails or is interrupted
  *   **Input**: hookBase + `{ toolName, toolInput (object), toolUseId, error, isInterrupt? }`
  *   **Planned behavior**: Update `agents.status = 'error'`. Log failure to messages table.
  *   **Layer touches**: Agent (status update), Messages (append)

*   **hooks.stop** (`hooks-stop.ts`) — STUB
  *   **Fires**: When Claude's turn ends (agent stops responding)
  *   **Input**: hookBase + `{ stopHookActive, lastAssistantMessage }`
  *   **Planned behavior**: Update `agents.status = 'done'`. Check for rate limit / context exhaustion in transcript (old stop-notify.sh logic).
  *   **Layer touches**: Agent (status update)

### Agent-Layer Hooks

These manage agent identity and fleet coordination.

*   **hooks.userPrompt** (`hooks-user-prompt.ts`)
  *   **Fires**: When user submits a message
  *   **Input**: hookBase + `{ prompt }`
  *   **Behavior**: Resolve engine IDs via `resolveEngineIds(cwd, ctx)`. Pure read. Assemble session context string (time, session, skill, phase, heartbeat). (Planned: update `agents.status = 'working'`.)
  *   **Returns**: `{ sessionContext, effortId, sessionId, taskDir, skill, phase, heartbeat }`
  *   **Layer touches**: Effort (read), Session (read), Agent (planned: status update)

*   **hooks.notification** (`hooks-notification.ts`) — STUB
  *   **Fires**: On permission_prompt, idle_prompt, elicitation_dialog
  *   **Input**: hookBase + `{ message, notificationType, title? }`
  *   **Planned behavior**: Update `agents.status = 'attention'`.
  *   **Layer touches**: Agent (status update)

*   **hooks.permissionRequest** (`hooks-permission-request.ts`) — STUB
  *   **Fires**: When Claude requests tool permission
  *   **Input**: hookBase + `{ toolName, toolInput (object), permissionSuggestions? }`
  *   **Planned behavior**: Update `agents.status = 'attention'`.
  *   **Layer touches**: Agent (status update)

*   **hooks.teammateIdle** (`hooks-teammate-idle.ts`) — STUB
  *   **Fires**: When an agent team teammate goes idle
  *   **Input**: hookBase + `{ teammateName, teamName }`
  *   **Planned behavior**: Update teammate's `agents.status = 'done'`. Signal coordinator if one exists.
  *   **Layer touches**: Agent (status update), Task (read for coordinator lookup)

*   **hooks.taskCompleted** (`hooks-task-completed.ts`) — STUB
  *   **Fires**: When a Claude Code task (not our task table) completes
  *   **Input**: hookBase + `{ taskId, taskSubject, taskDescription?, teammateName?, teamName? }`
  *   **Planned behavior**: Potential effort lifecycle update.
  *   **Layer touches**: Task (read), Effort (potential update)

### Sub-Agent Hooks

These manage Task tool sub-agents.

*   **hooks.subagentStart** (`hooks-subagent-start.ts`) — STUB
  *   **Fires**: When a Task tool sub-agent spawns
  *   **Input**: hookBase + `{ agentId, agentType }`
  *   **Planned behavior**: Create a new session for the sub-agent, same effort as parent. Return context: log template, directives, effort metadata.
  *   **Layer touches**: Session (create), Effort (read)
  *   **Key invariant**: Sub-agents run their own sessions but share the parent's effort.

*   **hooks.subagentStop** (`hooks-subagent-stop.ts`) — STUB
  *   **Fires**: When a Task tool sub-agent completes
  *   **Input**: hookBase + `{ stopHookActive, agentId, agentType, agentTranscriptPath, lastAssistantMessage }`
  *   **Planned behavior**: End sub-agent's session. Merge loaded_files back to effort.
  *   **Layer touches**: Session (end)

### Infrastructure Hooks

*   **hooks.configChange** (`hooks-config-change.ts`) — STUB
  *   **Fires**: When Claude Code configuration changes
  *   **Input**: hookBase + `{ source, filePath? }`
  *   **Planned behavior**: No-op or invalidate cached skill data.
  *   **Layer touches**: None

---

## Lifecycle Flows

### Startup Flow

```
Claude starts
  → SessionStart bash hook fires
  → calls hooks.sessionStart RPC
  → RPC: find effort by agentId → find/create session → load skill config
  → bash: read filesToPreload from disk → inject as additionalContext
  → if dehydratedContext: inject recovery block
```

### Tool Call Flow

```
Agent calls a tool
  → PreToolUse bash hook fires
  → calls hooks.preToolUse RPC
  → RPC: increment heartbeat → check threshold → check overflow → evaluate guards
  → bash: if allow=false, block with injection message
  → bash: if allow=true, tool executes
  → PostToolUse bash hook fires
  → calls hooks.postToolUse RPC
  → RPC: read heartbeat → clear injections → log dialogue → discover directives
  → bash: deliver pendingInjections as additionalContext
```

### Overflow / Kill Flow

```
Context reaches 80-90%
  → preToolUse returns overflowWarning=true
  → bash injects dehydration instruction to agent
  → agent writes dehydrated context to effort (via engine command)
  → session.finish called with dehydration_payload

Auto-compaction triggered (context too full)
  → preCompact bash hook fires
  → kills Claude (no dehydration — too late)
  → watchdog restarts Claude
  → SessionStart fires → picks up effort → creates new session with prev_session_id
  → if dehydration_payload exists: inject it
  → if no payload: rehydrate by reading effort artifacts
```

### Fleet Notification Flow

```
Agent state changes
  → relevant hook updates agents.status in DB
  → tmux display reads agents.status (polling or event)
  → pane background color set based on status

Status priority: error > attention > working > checked > done
```

---

## Implementation Status

*   **Implemented** (4 core): sessionStart, preToolUse, postToolUse, userPrompt
*   **Stub** (11): preCompact, stop, sessionEnd, subagentStart, subagentStop, notification, permissionRequest, postToolUseFailure, teammateIdle, taskCompleted, configChange

### Implementation Priority

1. **preCompact** + **stop** + **sessionEnd** — session lifecycle + agents.status pattern
2. **notification** + **permissionRequest** — agents.status for attention state
3. **subagentStart** + **subagentStop** — sub-agent session management
4. **postToolUseFailure** — error state tracking
5. **teammateIdle** + **taskCompleted** — fleet coordination
6. **configChange** — low priority, likely stays no-op

---

## Key Differences from Old Hooks (v1 Shell Scripts)

*   **`.state.json` eliminated** — all state in SQLite via daemon RPCs
*   **PID eliminated** — agentId (fleet pane identity) is the ownership key
*   **18 shell hooks → 15 RPC handlers** — consolidation via batched RPCs
*   **5 PostToolUse hooks → 1** — injections, phase-commands, templates, details-log, discovery all in one RPC
*   **3 PreToolUse hooks → 1** — session-gate, heartbeat, directive-gate all in one RPC
*   **DIALOGUE.md eliminated** — messages table in DB
*   **Artifacts belong to efforts** — not sessions. Ordinal-prefixed: `1_BRAINSTORM_LOG.md`
*   **Tmux notifications become DB-backed** — `agents.status` column, tmux as read-only display
*   **Directive discovery moves inside postToolUse** — cross-namespace dispatch, single round-trip
