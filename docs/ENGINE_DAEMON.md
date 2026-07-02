# Engine v3 Daemon (SQLite RPC Server)

The engine daemon is a persistent process that provides the RPC API for sessions, search, hooks, fleet, and all engine commands. It runs a wa-sqlite database (WASM build with sqlite-vec) and listens on both a Unix socket (for CLI/hooks) and an optional HTTP server (for the web UI).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Engine v3 Daemon                          │
│                                                               │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │ Unix Socket  │    │  HTTP Server  │    │   SSE Event    │  │
│  │  (NDJSON)    │    │  (REST + RPC) │    │     Bus        │  │
│  │ :socket.sock │    │  :http-port   │    │  /api/events   │  │
│  └──────┬───────┘    └──────┬────────┘    └───────┬────────┘  │
│         │                   │                     │           │
│         └────────┬──────────┘                     │           │
│                  ▼                                │           │
│  ┌──────────────────────────────┐                │           │
│  │       RPC Dispatch            │    emit() ◄───┘           │
│  │  Zod validate → middleware    │                            │
│  │  → handler                    │                            │
│  └──────────────┬────────────────┘                            │
│                 │                                              │
│  ┌──────────────▼────────────────┐                            │
│  │     Middleware Chain           │                            │
│  │  fsBuffer (outer) → tx (inner)│                            │
│  └──────────────┬────────────────┘                            │
│                 │                                              │
│  ┌──────────────▼────────────────┐                            │
│  │   wa-sqlite (WASM + vec)      │                            │
│  │   .claude/.ideas.db           │                            │
│  └───────────────────────────────┘                            │
│                                                               │
│  Namespaces: db · hooks · agent · search · fs · ai ·         │
│              commands · fleet                                  │
└──────────────────────────────────────────────────────────────┘
```

## Transport Layer

### Unix Socket (Primary)

The daemon listens on a Unix domain socket using newline-delimited JSON (NDJSON). CLI tools and hooks connect here.

*   **Socket path**: `/tmp/ideas-daemon-{hash}.sock` (hash = MD5 of project root, first 8 chars)
*   **Protocol**: One JSON object per line. Responses are also newline-delimited JSON.
*   **Two message types**:
    *   `{cmd, args, env}` — routed to RPC dispatch (Zod validation → middleware → handler)
    *   `{sql, params, format, single}` — routed to raw SQL execution

**Source**: `tools/daemon/src/daemon.ts:96-117`

### HTTP Server (Optional)

Enabled with `--http-port`. Serves the web UI and provides REST + RPC endpoints.

*   **Static files**: Serves from `--static-dir` (typically `tools/web/dist/`). SPA fallback to `index.html`.
*   **CORS**: Permissive (`*`) for local development.

**Source**: `tools/daemon/src/http/server.ts`

## HTTP API Routes

*   **`GET /api/agents`** — Lists all agents via the `fleet_status` DB view. Returns `{ok, agents: [{agent, label, status, skill, current_phase, heartbeat_counter, context_usage, cost}]}`.

*   **`GET /api/agents/:id/messages`** — Recent messages for an agent's active session. Joins messages → sessions → efforts → agents. Query param: `?limit=50`. Returns `{ok, messages: [...]}` (chronological order).

*   **`GET /api/events`** — SSE stream (Server-Sent Events). Subscribes to the in-memory event bus. Each event: `event: {type}\ndata: {json}\n\n`. Connection kept alive with initial SSE comment.

*   **`POST /api/rpc`** — Generic RPC passthrough. Body: `{cmd, args, env}`. Sets `AGENT_ID: "web-ui"` as default env. Routes through the same dispatch as the Unix socket.

## Database

### Engine

wa-sqlite — a WebAssembly build of SQLite with sqlite-vec statically linked for vector search. Persists to disk via NodeAsyncVFS (file-backed WASM).

*   **DB path**: `{projectRoot}/.claude/.ideas.db`
*   **Schema version**: Managed via `PRAGMA user_version`. Current: 11.
*   **Foreign keys**: Enabled (`PRAGMA foreign_keys = ON`).

### Tables (10)

*   **`projects`** — Engine installation identity. Fields: `id`, `path` (UNIQUE), `name`, `created_at`.

*   **`skills`** — Cached SKILL.md parse (per-project). Fields: `id`, `project_id` (FK → projects), `name`, `phases` (JSONB), `modes` (JSONB), `templates` (JSONB), `cmd_dependencies` (JSONB), `next_skills` (JSONB), `directives` (JSONB), `version`, `description`, `updated_at`. UNIQUE on `(project_id, name)`.

*   **`tasks`** — Persistent work containers keyed by directory path. Fields: `dir_path` (PK), `project_id` (FK → projects), `workspace`, `title`, `description`, `keywords`, `created_at`.

*   **`efforts`** — Skill invocations (FK → tasks, ordinal-based). Fields: `id`, `task_id` (FK → tasks), `skill`, `mode`, `ordinal`, `lifecycle` (default 'active'), `current_phase`, `discovered_directives` (JSONB), `discovered_directories` (JSONB), `metadata` (JSONB), `created_at`, `finished_at`. UNIQUE on `(task_id, ordinal)`.

*   **`sessions`** — Ephemeral context windows (FK → tasks, efforts). Fields: `id`, `task_id` (FK → tasks), `effort_id` (FK → efforts), `prev_session_id` (FK → sessions), `pid`, `heartbeat_counter`, `heartbeat_interval` (default 10), `last_heartbeat`, `context_usage`, `cost` (default 0), `loaded_files` (JSONB), `preloaded_files` (JSONB), `pending_injections` (JSONB), `discovered_directives` (JSONB), `discovered_directories` (JSONB), `dehydration_payload` (JSONB), `interaction` (JSONB), `transcript_path`, `transcript_offset`, `created_at`, `ended_at`.

*   **`phase_history`** — Audit trail of phase transitions. Fields: `id`, `effort_id` (FK → efforts), `phase_label`, `proof` (JSONB), `created_at`.

*   **`messages`** — Conversation transcripts. Fields: `id`, `session_id` (FK → sessions), `role`, `content`, `tool_name`, `timestamp`.

*   **`agents`** — Fleet agent identity. Fields: `id` (PK, text), `label`, `claims`, `targeted_claims`, `manages`, `parent`, `effort_id` (FK → efforts), `status`.

*   **`chunks`** — Search chunk metadata (content-hash dedup). Fields: `id`, `source_type`, `source_path`, `section_title`, `chunk_text`, `content_hash`, `updated_at`. UNIQUE on `(source_path, section_title)`.

*   **`embeddings`** — Search vectors keyed by content hash. Fields: `content_hash` (PK), `embedding` (BLOB), `updated_at`.

### Views (4)

*   **`fleet_status`** — Joins agents → efforts → tasks → sessions. Shows: `agent`, `label`, `status`, `skill`, `current_phase`, `heartbeat_counter`, `context_usage`, `cost`. Used by `GET /api/agents`.

*   **`task_summary`** — Tasks with effort count and last activity date.

*   **`active_efforts`** — Efforts where `lifecycle = 'active'`.

*   **`stale_sessions`** — Sessions with no heartbeat in 5+ minutes (ended_at IS NULL).

### Indexes

*   `idx_efforts_task_lifecycle` — `efforts(task_id, lifecycle)`
*   `idx_sessions_effort_ended` — `sessions(effort_id, ended_at)`
*   `idx_messages_session_ts` — `messages(session_id, timestamp)`

## RPC Dispatch

### Mechanism

All RPC commands follow `namespace.group.method` naming (3-level) or `namespace.method` (2-level). The dispatch system provides:

1. **Zod validation** — Every command has a Zod schema. Invalid args return `VALIDATION_ERROR`.
2. **Middleware chain** — Top-level dispatch runs: `fsBufferMiddleware` (outer) → `txMiddleware` (inner) → handler. Internal dispatch (inter-namespace calls) skips middleware.
3. **Namespace proxies** — Handlers call across namespaces via typed proxies: `ctx.db.session.start(...)`, `ctx.ai.embed(...)`.

### Error Taxonomy

*   **`UNKNOWN_COMMAND`** — cmd string doesn't match any registered handler
*   **`VALIDATION_ERROR`** — args failed Zod schema validation (caller bug)
*   **`HANDLER_ERROR`** — handler threw (db constraint, FS error, logic error)

### Middleware

*   **`fsBufferMiddleware`** (outer) — Collects FS operations (write, append, mkdir, unlink) during handler execution. Flushes after the inner tx commits. Prevents partial writes on rollback.
*   **`txMiddleware`** (inner) — Wraps handler in `BEGIN`/`COMMIT`/`ROLLBACK`.

### Per-Request Environment

Each request can include an `env` object (validated by Zod):

*   `CWD` — Working directory of the calling process (default: daemon's cwd)
*   `AGENT_ID` — Agent identifier. Solo: `"default"`. Fleet: `"window:label"`.
*   `CLAUDE_PLUGIN_ROOT` — Plugin root directory (fleet-only, optional)
*   `AGENT_CLAIMS` — Untargeted skill types (fleet-only, optional)
*   `AGENT_TARGETED_CLAIMS` — Targeted skill types with %pane-id (fleet-only, optional)
*   `AGENT_MANAGES` — Child pane labels (fleet-only, optional)
*   `AGENT_PARENT` — Parent pane label for escalation (fleet-only, optional)

## RPC Command Catalog

### `db.*` (28 commands)

**effort** (effort lifecycle):
*   `db.effort.start` — Create a new effort for a task
*   `db.effort.finish` — Mark an effort as finished
*   `db.effort.get` — Get effort by ID
*   `db.effort.list` — List efforts (with filters)
*   `db.effort.findActive` — Find active efforts
*   `db.effort.getMetadata` — Get effort metadata JSONB
*   `db.effort.updateMetadata` — Update effort metadata JSONB
*   `db.effort.phase` — Record a phase transition with proof

**session** (context window lifecycle):
*   `db.session.start` — Create a new session for an effort
*   `db.session.finish` — End a session
*   `db.session.get` — Get session by ID
*   `db.session.find` — Find sessions (with filters)
*   `db.session.heartbeat` — Update heartbeat timestamp and counter
*   `db.session.updateContextUsage` — Update context usage percentage
*   `db.session.updateLoadedFiles` — Update loaded files JSONB
*   `db.session.updatePreloadedFiles` — Update preloaded files JSONB
*   `db.session.setTranscript` — Set transcript path and offset
*   `db.session.getInjections` — Get pending injections JSONB
*   `db.session.updateInjections` — Update pending injections JSONB

**agents** (fleet identity):
*   `db.agents.register` — Register a fleet agent
*   `db.agents.get` — Get agent by ID
*   `db.agents.list` — List all agents
*   `db.agents.findByEffort` — Find agents working on an effort
*   `db.agents.updateStatus` — Update agent status

**messages** (conversation transcripts):
*   `db.messages.append` — Append a message to a session
*   `db.messages.list` — List messages for a session
*   `db.messages.upsert` — Upsert a message (idempotent)

**task** (work containers):
*   `db.task.upsert` — Create or update a task
*   `db.task.list` — List tasks (with filters)
*   `db.task.find` — Find a task by dir_path

**project** (engine identity):
*   `db.project.find` — Find project by path
*   `db.project.upsert` — Create or update a project

**skills** (SKILL.md cache):
*   `db.skills.get` — Get skill by ID
*   `db.skills.find` — Find skill by name and project
*   `db.skills.list` — List skills (with filters)
*   `db.skills.upsert` — Create or update a skill parse
*   `db.skills.delete` — Delete a skill

### `hooks.*` (13 commands)

Claude Code hook handlers — called by the hook system at specific lifecycle events:

*   `hooks.sessionStart` — Session initialization (preloads standards, dehydrated context, skill files)
*   `hooks.sessionEnd` — Session teardown
*   `hooks.preToolUse` — Pre-tool-use guard (heartbeat, directive gate, session gate)
*   `hooks.postToolUse` — Post-tool-use processing (discovery, directive tracking, template preloading)
*   `hooks.postToolUseFailure` — Post-tool-use failure handling
*   `hooks.userPromptSubmit` — User prompt processing (freeform chat logging, context injection)
*   `hooks.preCompact` — Pre-compaction handler
*   `hooks.subagentStart` — Subagent spawn tracking
*   `hooks.subagentStop` — Subagent completion tracking
*   `hooks.taskCompleted` — Task completion handler
*   `hooks.teammateIdle` — Fleet teammate idle detection
*   `hooks.statusline` — Status line rendering
*   `hooks.permissionRequest` — Permission request handler
*   `hooks.notification` — Notification delivery
*   `hooks.fleet-start` — Fleet startup orchestration
*   `hooks.fleet-stop` — Fleet teardown
*   `hooks.stop` — Daemon stop handler

### `agent.*` (10 commands)

Agent workspace operations — directives, messages, interactions, skills:

*   `agent.messages.ingest` — Ingest conversation messages from a transcript
*   `agent.messages.watch` — Start watching a transcript file for new messages
*   `agent.messages.unwatch` — Stop watching a transcript file
*   `agent.directives.discover` — Walk-up directory search for `.directives/` files
*   `agent.directives.resolve` — Resolve `§CMD_*` and `§INV_*` references to file paths
*   `agent.directives.dereference` — Dereference a sigiled reference to its content
*   `agent.interaction.ask` — Submit a question to an agent (cross-agent communication)
*   `agent.interaction.answer` — Submit an answer from an agent
*   `agent.interaction.prompt` — Send a prompt to an agent (hot inject via pending_injections or cold spawn via `claude -p --resume`)
*   `agent.interaction.interrupt` — Force-stop a running agent via SIGINT
*   `agent.skills.parse` — Parse a SKILL.md file into structured data
*   `agent.skills.list` — List available skills for a project

### `search.*` (7 commands)

Semantic vector search over sessions, docs, and code:

*   `search.query` — Vector similarity search (returns ranked results with distance scores)
*   `search.upsert` — Upsert a chunk with embedding
*   `search.delete` — Delete a chunk by path
*   `search.status` — Search index status (chunk counts, staleness)
*   `search.reindex` — Trigger full reindex
*   `search.sessions.reindex` — Reindex session artifacts
*   `search.docs.reindex` — Reindex project documentation

### `fs.*` (5 commands)

Filesystem operations (sandboxed to project scope):

*   `fs.files.read` — Read file contents
*   `fs.files.stat` — Get file metadata (size, mtime, type)
*   `fs.files.append` — Append content to a file
*   `fs.dirs.list` — List directory contents
*   `fs.paths.resolve` — Resolve a path (handles `~`, relative, workspace)

### `ai.*` (2 commands)

AI model operations:

*   `ai.embed` — Generate an embedding vector for text (used by search indexing)
*   `ai.generate` — Generate text via an AI model (used by external model execution)

### `commands.*` (3 commands)

High-level orchestration commands (compose multiple RPC calls):

*   `commands.log.append` — Append to a log file with timestamp injection
*   `commands.effort.start` — Start a new effort (project upsert + task upsert + effort create + session start + agent register)
*   `commands.efforts.resume` — Resume an existing effort after context overflow

### `fleet.*` (5 commands)

Fleet management — multi-agent workspace operations:

*   `fleet.status` — Get fleet status (all panes with agent state)
*   `fleet.list` — List fleet panes
*   `fleet.start` — Start a fleet from a YAML config
*   `fleet.attach` — Attach an agent to a fleet pane
*   `fleet.stop` — Stop the fleet (teardown all panes)

## CLI Reference

The `ideas-db` CLI provides two commands:

### `ideas-db daemon start|stop|status`

*   **`start`** — Start the daemon. Socket path and DB path are auto-derived from project root. Writes a PID file at `{socket}.pid`. Blocks (keeps process alive).
*   **`stop`** — Stop the daemon. Reads PID from `{socket}.pid`, sends SIGTERM, cleans up PID file.
*   **`status`** — Check if daemon is running. Probes socket with `SELECT 1`. Outputs `running (PID: N)` or `stopped` (exit 1).

### `ideas-db query 'SQL' [params...] [--single] [--format=json|tsv|scalar]`

Execute SQL against the daemon via the Unix socket.

*   `--format=json` (default) — JSON array of row objects
*   `--format=tsv` — Tab-separated values with header row
*   `--format=scalar` — Single value from first column of first row
*   `--single` — Return first row only (not array)
*   Params are positional args after SQL. Numbers auto-parsed.
*   SQL can also be piped via stdin (heredoc).

## SSE Event Bus

Simple in-memory pub/sub for real-time updates to the web UI.

*   `emit(event)` — Broadcast to all connected SSE clients. Event: `{type: string, data: Record<string, unknown>}`.
*   `subscribe(cb)` — Register a listener. Returns unsubscribe function.
*   Injected into `ctx.emit` when the HTTP server is active. Handlers can emit events for UI reactivity.

**Source**: `tools/daemon/src/http/event-bus.ts`

## Configuration

*   **`--socket`** — Unix socket path. Default: `/tmp/ideas-daemon/ideas.sock` (main.ts) or `/tmp/ideas-daemon-{hash}.sock` (cli.ts, project-scoped).
*   **`--db`** — Database file path. Default: `/tmp/ideas-daemon/ideas.db` (main.ts) or `{projectRoot}/.claude/.ideas.db` (cli.ts).
*   **`--http-port`** — HTTP server port. Optional. When set, enables the HTTP server alongside the Unix socket.
*   **`--static-dir`** — Path to built web UI assets (e.g., `tools/web/dist/`). Optional. Enables static file serving with SPA fallback.

## Entry Points

Two entry points exist:

*   **`main.ts`** — Direct invocation with explicit flags. Used for development.
    ```bash
    npx tsx main.ts --socket /tmp/ideas.sock --db /tmp/ideas.db --http-port 3001
    ```

*   **`cli.ts`** — Subcommand-based CLI (`ideas-db`). Auto-derives paths from project root. Used in production.
    ```bash
    ideas-db daemon start
    ideas-db query 'SELECT * FROM tasks' --format=tsv
    ```

## Files

```
tools/daemon/src/
├── main.ts              # Direct entry point (--socket, --db, --http-port flags)
├── cli.ts               # CLI entry point (ideas-db daemon|query subcommands)
├── daemon.ts            # Core: startDaemon(), stopDaemon(), handleQuery()
├── registry.ts          # Master RPC registry (imports all 7 namespace registries)
└── http/
    ├── server.ts        # HTTP server (4 API routes + static serving)
    └── event-bus.ts     # SSE pub/sub (emit + subscribe)

tools/shared/src/
├── dispatch.ts          # RPC dispatch (top-level with middleware, internal without)
├── context.ts           # RpcContext type + rpcEnvSchema
├── middleware.ts         # Middleware chain (fsBuffer + tx)
├── namespace-builder.ts # Builds typed proxy objects from registry
└── rpc-types.ts         # Type infrastructure (Registered, NamespaceOf, ArgsOf, DataOf)

tools/db/src/
├── schema.ts            # Database schema (10 tables, 4 views, 3 indexes)
├── db-wrapper.ts        # wa-sqlite wrapper (createDb)
└── rpc/                 # db.* namespace handlers (28 commands)

tools/{hooks,agent,search,fs,ai,commands,fleet}/src/rpc/
└── registry.ts          # Per-namespace registry (imports all handlers)
```

## See Also

*   [DAEMON.md](DAEMON.md) — Tag dispatch daemon (fswatch + `#delegated-*` tag scanning). Different system.
*   [FLEET.md](FLEET.md) — Fleet configuration and multi-agent workspace
*   [HOOKS.md](HOOKS.md) — Hook system architecture
*   [SESSION_LIFECYCLE.md](SESSION_LIFECYCLE.md) — Session lifecycle (efforts, phases, heartbeat)
*   [SQLITE_DAEMON_VISION.md](SQLITE_DAEMON_VISION.md) — Original vision document for the v3 daemon
