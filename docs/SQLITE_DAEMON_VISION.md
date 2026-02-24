# SQLite Daemon: Engine v3 Architecture

> Vision document synthesizing the three-layer data model design from `sessions/2026_02_20_DAEMON_SQL_SCHEMA_BRAINSTORM/` (20 rounds, 14 sections).
> Supersedes v2 architecture (2-layer tasks+sessions model).
> Sources: v3 brainstorm + prior sessions (`SQLITE_DAEMON_BRAINSTORM`, `SQLITE_HOOK_MIGRATION`, `DAEMON_RPC_FRAMEWORK`).

### Implementation Status (Snapshot: 2026-02-23)

*   **v3 Schema**: COMPLETE — 9 tables, 4 views, 3 indexes. `SCHEMA_VERSION = 3`.
*   **v3 RPCs**: 57 RPCs built across 8 namespaces (+1 planned), 386+ tests passing across 52 test files.
    *   `db.*` (24 built, 1 planned): project(1), task(3), skills(5), effort(4 + validate planned), session(6), agents(3), messages(2)
    *   `hooks.*` (15 RPCs): session-start, pre/post-tool-use, user-prompt, plus 11 lifecycle hooks — COMPLETE
    *   `commands.*` (3 RPCs): effort.start, session.continue, log.append — COMPLETE (with rollback + hardening)
    *   `search.*` (5 RPCs): upsert, query, delete, status, reindex — COMPLETE
    *   `fs.*` (3 RPCs): files.read, files.append, paths.resolve — COMPLETE
    *   `ai.*` (2 RPCs): generate, embed — COMPLETE (provider-agnostic, raw HTTP)
    *   `agent.*` (5 RPCs): directives.discover/dereference/resolve, skills.parse/list — COMPLETE
*   **Hook RPCs**: COMPLETE — 4 core hooks (sessionStart, preToolUse, postToolUse, userPrompt) plus 11 lifecycle hooks.
*   **Bash compound commands**: COMPLETE — `commands.effort.start` (with rollback on failure), `commands.session.continue`, `commands.log.append` (refactored to use `fs.files.append` RPC).
*   **Code Location**: `~/.claude/engine/tools/` (workspace monorepo: db, commands, fs, shared, agent, ai, daemon, search packages)
*   **Architecture Quality**: Excellent — consistent Zod validation, transaction discipline, self-registering handlers, RpcContext typed dispatch, provider-agnostic AI namespace.
*   **Hardening**: Compound commands tested with adversarial edge cases (null skill degradation, rollback verification, corrupt JSON, Zod validation, zero-effort recovery).

---

## 1. Problem Statement

### v1 Problems (Unchanged)

The workflow engine manages session state via scattered `.state.json` files accessed through jq-based reads and mkdir spinlocks. Four compounding failure modes:

*   **Concurrency**: Multiple hooks fire per tool call (3-4 pre-tool-use, 2-3 post-tool-use). Each reads and writes `.state.json` independently. mkdir spinlocks provide advisory locking but fail silently under contention.
*   **Query Performance**: Cross-session queries require iterating every `.state.json` file and parsing with jq. A fleet dashboard query touches 20+ files.
*   **Data Integrity**: Read-modify-write cycles on JSON files create race windows. Two hooks can read the same state, make independent changes, and one clobbers the other.
*   **Schema Evolution**: Adding a field requires updating every jq call site (578 jq calls + 84 safe_json_write calls). No migration path, no validation, no schema enforcement.

### v2 Limitations (Discovered During M1)

The v2 two-layer model (tasks + sessions) introduced its own issues:

*   **Conflation**: A "task" combines three distinct concepts — the persistent work container, the skill invocation, and phase progression. Running brainstorm then implement on the same directory requires overwriting the task's skill and resetting its phases.
*   **PID Fragility**: PID-based session ownership breaks across Claude restarts. `claude --resume` reuses the same context window but gets a new PID, causing ownership mismatches.
*   **Phase Scoping**: `phase_history` FK→tasks means all skill invocations share one phase timeline. Brainstorm phases and implementation phases are interleaved in the same history.
*   **No Multi-Skill Support**: A task can only have one active skill at a time. Fleet scenarios where different agents run different skills on the same work directory are impossible.

### The Three-Layer Answer

Separate the three concepts cleanly:
*   **Tasks** = persistent work containers (what are we working toward?)
*   **Efforts** = skill invocations (what skill is being applied, and how far along?)
*   **Sessions** = context windows (which Claude instance is running, and what has it loaded?)

---

## 2. Architecture Overview

```
§FLOWGRAPH: Engine v3 Stack

[Bash Hooks (shims)] -->|Unix Socket NDJSON| [TS Daemon (Node.js + sql.js)]
[engine CLI (bash)] -->|Unix Socket NDJSON| [TS Daemon (Node.js + sql.js)]
[Status Line / fleet.sh] <--|events| [TS Daemon (Node.js + sql.js)]
[TS Daemon (Node.js + sql.js)] -->|read/write| [SQLite WASM (.claude/.engine.db)]
[TS Daemon (Node.js + sql.js)] -->|API calls| [Embedding Pipeline (Gemini API)]
[Bash Hooks (shims)] -->|read/write| [Filesystem (sessions/, .directives/, docs/, SKILL.md)]
[engine CLI (bash)] -->|read/write| [Filesystem (sessions/, .directives/, docs/, SKILL.md)]
```

**Core Principle (v3 — STRONGER than v2)**: The daemon owns state (SQLite). The daemon touches ONLY SQLite — zero filesystem reads, zero filesystem writes. All filesystem I/O is performed by the bash CLI layer. Hooks and CLI orchestrate by calling daemon RPCs for data and doing FS I/O locally.

**Two-Tier Design**:
*   **Daemon RPCs (`db.*`)**: Pure database operations. Zod-validated, return JSON. Zero FS dependency.
*   **Bash compound commands**: Orchestrate filesystem I/O and daemon RPCs. Handle all file reading (skills, templates, directives) and writing (logs, artifacts, debriefs).

**Technology Stack** (unchanged from v2):
*   **Runtime**: TypeScript on Node.js via tsx (no build step)
*   **SQLite**: sql.js (WASM) — no native bindings, portable
*   **IPC**: Unix domain socket with NDJSON protocol (extended for RPC)
*   **Validation**: Zod schemas on every RPC command
*   **Location**: `~/.claude/engine/tools/db/`

---

## 3. Data Model: The Three Layers

### 3.1 Conceptual Definitions

**Task** — The persistent work container. Identified by directory path (natural key). Belongs to a project. Accumulates efforts over time. Tasks NEVER finish — they exist as long as the directory exists. Active/dormant status is DERIVED from whether any efforts are active, not stored as a lifecycle column.

**Effort** — A skill invocation applied to a task. Running `/brainstorm`, `/implement`, or `/fix` on a task each creates an effort. Binary lifecycle (active/finished). Each effort owns its own phase progression. Multiple efforts per task allowed, including multiple invocations of the same skill (brainstorm → implement → brainstorm again). Efforts are ordered by creation ordinal, which drives artifact naming.

**Session** — A context window. One Claude Code instance's lifetime — from creation to context overflow or natural end. Belongs to a task (FK) and serves exactly one effort at a time (effort_id NOT NULL). Context overflow creates a new session with `prev_session_id` link, forming a continuation chain. Tracks ephemeral state: heartbeat, context usage, loaded files.

### 3.2 Relationship Diagram

```
§FLOWGRAPH: Entity Relationships

[projects (1)] --> [skills (N per project)]
[projects (1)] --> [tasks (N per project)]
[tasks] --> [efforts (N per task, ordered by ordinal)]
[efforts] --> [phase_history (N per effort)]
[tasks] --> [sessions (N per task)]
[sessions] --> [messages (N per session)]
[agents] -->|effort_id FK, 1:1| [efforts]
[sessions] -->|effort_id FK, NOT NULL| [efforts]
[sessions] -->|prev_session_id, self-ref| [sessions]
```

### 3.3 How the Three Layers Interact

**Normal flow**: User invokes `/brainstorm` → task created (or found) → effort #1 created (skill=brainstorm, ordinal=1) → session created → work happens → effort finished → user invokes `/implement` → effort #2 created (skill=implement, ordinal=2) → same session continues (if context allows) or new session created.

**Context overflow**: Mid-effort, context fills up → current session gets `dehydration_payload` and `ended_at` → new session created with `prev_session_id` pointing to old session → new session loads effort's required files → work resumes at the same phase.

**Session continuity across efforts**: A single session (context window) can span multiple efforts. Finishing brainstorm and starting implementation does NOT require a new session — the same context window continues. The session's `effort_id` updates to the new effort.

**Fleet scenario**: Multiple agents work on the same task. Each agent owns one effort. Agent A runs brainstorm (effort #1), Agent B runs implementation (effort #2) concurrently. Both have their own sessions. The agents table tracks which effort each agent is working on.

### 3.4 Schema DDL

```sql
-- ═══════════════════════════════════════════════════════════
-- Engine v3 Schema — 9 tables
-- ═══════════════════════════════════════════════════════════

-- Engine installation identity. Shared daemon, per-project skills and tasks.
CREATE TABLE projects (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    path        TEXT NOT NULL UNIQUE,    -- absolute path to project root
    name        TEXT,                    -- human-readable
    created_at  TEXT DEFAULT (datetime('now'))
);

-- Cached parse of SKILL.md files. Per-project. Updated periodically by bash
-- scanning engine directory and calling db.skills.upsert.
CREATE TABLE skills (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      INTEGER NOT NULL REFERENCES projects(id),
    name            TEXT NOT NULL,       -- 'brainstorm', 'implement', etc.
    phases          TEXT,                -- JSON array of phase definitions
    modes           TEXT,                -- JSON object of mode definitions
    templates       TEXT,                -- JSON object of template paths
    cmd_dependencies TEXT,               -- JSON array of CMD file paths
    next_skills     TEXT,                -- JSON array of follow-up skills
    directives      TEXT,                -- JSON array of directive file types
    updated_at      TEXT DEFAULT (datetime('now')),
    UNIQUE(project_id, name)
);

-- Pure work containers. NO lifecycle column (derived from efforts).
-- NO skill column (lives on efforts). Tasks never finish.
CREATE TABLE tasks (
    dir_path    TEXT PRIMARY KEY,        -- natural key: sessions/2026_02_20_TOPIC
    project_id  INTEGER NOT NULL REFERENCES projects(id),
    workspace   TEXT,                    -- e.g., 'apps/estimate-viewer/extraction'
    title       TEXT,
    description TEXT,
    keywords    TEXT,                    -- comma-separated, for search
    created_at  TEXT DEFAULT (datetime('now'))
);

-- Skill invocations. The core new table. Binary lifecycle.
-- Ordinal-prefixed artifacts.
CREATE TABLE efforts (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id                 TEXT NOT NULL REFERENCES tasks(dir_path) ON DELETE CASCADE,
    skill                   TEXT NOT NULL,       -- 'brainstorm', 'implement', etc.
    mode                    TEXT,                -- 'focused', 'tdd', 'hotfix'. Nullable
    ordinal                 INTEGER NOT NULL,    -- auto-incremented per task
    lifecycle               TEXT NOT NULL DEFAULT 'active',  -- 'active' or 'finished'
    current_phase           TEXT,                -- e.g., "1: Dialogue Loop"
    discovered_directives   TEXT,                -- JSON array of directive paths
    discovered_directories  TEXT,                -- JSON array of touched dirs
    metadata                TEXT,                -- JSON blob (taskSummary, scope, etc.)
    created_at              TEXT DEFAULT (datetime('now')),
    finished_at             TEXT,
    UNIQUE(task_id, ordinal)
);

-- Context windows. Purely ephemeral.
CREATE TABLE sessions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id             TEXT NOT NULL REFERENCES tasks(dir_path) ON DELETE CASCADE,
    effort_id           INTEGER NOT NULL REFERENCES efforts(id),
    prev_session_id     INTEGER REFERENCES sessions(id),  -- continuation chain
    pid                 INTEGER,            -- informational only (not for ownership)
    heartbeat_counter   INTEGER DEFAULT 0,
    last_heartbeat      TEXT,
    context_usage       REAL,               -- 0.0 to 1.0
    loaded_files        TEXT,               -- JSON array (populated from Read tool hooks)
    dehydration_payload TEXT,               -- JSON blob (replaces dehydration_snapshots)
    created_at          TEXT DEFAULT (datetime('now')),
    ended_at            TEXT
);

-- Phase audit trail. FK → efforts (NOT tasks — this is the key v3 change).
CREATE TABLE phase_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    effort_id   INTEGER NOT NULL REFERENCES efforts(id) ON DELETE CASCADE,
    phase_label TEXT NOT NULL,
    proof       TEXT,                    -- JSON object of proof fields
    created_at  TEXT DEFAULT (datetime('now'))
);

-- Real-time conversation transcripts. Replaces DIALOGUE.md.
CREATE TABLE messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role        TEXT NOT NULL,           -- 'user', 'assistant', 'system', 'tool'
    content     TEXT NOT NULL,
    tool_name   TEXT,                    -- populated when role='tool'
    timestamp   TEXT DEFAULT (datetime('now'))
);

-- Fleet agent identity. Agent→effort binding for ownership.
CREATE TABLE agents (
    id          TEXT PRIMARY KEY,        -- agent identity (tmux pane label)
    label       TEXT,
    claims      TEXT,                    -- skill types this agent accepts
    effort_id   INTEGER REFERENCES efforts(id)  -- current effort (1:1 at a time)
);

-- Unified search. Unchanged from v2.
CREATE TABLE embeddings (
    id          INTEGER PRIMARY KEY,
    source_type TEXT NOT NULL,           -- 'session', 'doc', 'directive'
    source_path TEXT NOT NULL,
    chunk_text  TEXT,
    embedding   BLOB,                   -- Float32Array (3072-dim, Gemini text-embedding-004)
    updated_at  TEXT DEFAULT (datetime('now'))
);
```

**Key design decisions**:
*   **efforts.ordinal** assigned atomically by daemon: `MAX(ordinal WHERE task_id) + 1`. Single-threaded daemon eliminates races.
*   **sessions.effort_id NOT NULL** — every session must serve an effort. Even ad-hoc `/do` work creates a lightweight effort.
*   **sessions.pid is informational only** — not used for ownership. Agent-based ownership via agents.effort_id.
*   **sessions.loaded_files** populated in real-time from PostToolUse hook when Read tool is used. Important for "don't re-read" optimizations on session.continue.
*   **sessions.dehydration_payload** replaces the separate dehydration_snapshots table. One dehydration per session is sufficient.
*   **efforts.discovered_directives/discovered_directories** moved from session to effort — directives are skill-specific, not context-window-specific.
*   **Skill data NOT duplicated to effort rows**. Efforts reference skills by name + project. On resume, the skill's current SKILL.md is re-parsed — no stale snapshots.

### 3.5 Views

```sql
-- Fleet monitoring: who is doing what
CREATE VIEW fleet_status AS
    SELECT a.id AS agent, a.label, e.skill, e.current_phase,
           s.heartbeat_counter, s.context_usage
    FROM agents a
    JOIN efforts e ON a.effort_id = e.id
    JOIN tasks t ON e.task_id = t.dir_path
    LEFT JOIN sessions s ON s.effort_id = e.id AND s.ended_at IS NULL;

-- Task dashboard
CREATE VIEW task_summary AS
    SELECT t.*, COUNT(e.id) AS effort_count,
           MAX(e.skill) AS latest_skill,
           MAX(e.created_at) AS last_activity
    FROM tasks t LEFT JOIN efforts e ON e.task_id = t.dir_path
    GROUP BY t.dir_path;

-- Active efforts
CREATE VIEW active_efforts AS
    SELECT e.*, s.name AS skill_name
    FROM efforts e JOIN skills s ON e.skill = s.name
    WHERE e.lifecycle = 'active';

-- Stuck detection
CREATE VIEW stale_sessions AS
    SELECT s.*, t.dir_path AS task_dir
    FROM sessions s JOIN tasks t ON s.task_id = t.dir_path
    WHERE s.ended_at IS NULL
      AND s.last_heartbeat < datetime('now', '-5 minutes');
```

### 3.6 Compound Indexes

```sql
CREATE INDEX idx_efforts_task_lifecycle ON efforts(task_id, lifecycle);
CREATE INDEX idx_sessions_effort_ended ON sessions(effort_id, ended_at);
CREATE INDEX idx_messages_session_ts ON messages(session_id, timestamp);
```

---

## 4. RPC Architecture

### 4.1 Daemon RPCs (`db.*`) — Pure Database Operations

All RPCs are Zod-validated and return JSON. The daemon touches ONLY SQLite.

**Project RPCs (1)**:
*   `db.project.upsert(path, name?)` — Idempotent create or update project by absolute path.

**Task RPCs (3)**:
*   `db.task.upsert(dir_path, workspace?, title?)` — Idempotent create or update. Resolves project_id from dir_path prefix.
*   `db.task.find(query)` — Search tasks by keyword, workspace, project.
*   `db.task.list(project?)` — List all tasks, optionally filtered by project.

**Effort RPCs (4 built, 1 planned)**:
*   `db.effort.start(task_id, skill, mode?, metadata?)` — Create effort row. Assigns ordinal atomically (MAX+1). Returns effort row including artifact prefix (e.g., `"1_BRAINSTORM"`).
*   `db.effort.finish(effort_id, keywords?)` — Set lifecycle='finished', finished_at=now. Update task keywords if provided.
*   `db.effort.phase(effort_id, label, proof?)` — Atomic phase transition: sequential enforcement against skill's phases array, proof validation and storage in phase_history, heartbeat reset. Sub-phase auto-append. Re-enter same phase = no-op.
*   `db.effort.list(task_id)` — List all efforts for a task, ordered by ordinal.
*   `db.effort.validate(effort_id)` — *(planned)* Validate effort artifacts: bare tag scan, checklist processing, request file verification. Returns pass/fail per check.

**Session RPCs (6)**:
*   `db.session.start(task_id, effort_id, pid?, prev_session_id?)` — Create session row. End any previous active session for the same agent. Session ID derived from Claude's native session ID.
*   `db.session.finish(session_id, dehydration_payload?)` — Set ended_at. Store dehydration payload if context overflow.
*   `db.session.heartbeat(session_id)` — Increment heartbeat_counter, update last_heartbeat.
*   `db.session.updateContextUsage(session_id, usage)` — Update context_usage float. Pushed by status line.
*   `db.session.updateLoadedFiles(session_id, files)` — Update loaded_files JSON array. Called when Read tool is used.
*   `db.session.find(query)` — Search sessions by task, effort, or agent criteria.

**Skills RPCs (5)**:
*   `db.skills.upsert(name, project_id, phases, modes, templates, ...)` — Insert or update skill definition. Called by bash after parsing SKILL.md.
*   `db.skills.get(name, project_id)` — Get skill definition by name and project.
*   `db.skills.list(project_id)` — List all skills for a project.
*   `db.skills.delete(name, project_id)` — Remove a skill definition.
*   `db.skills.find(query, project_id?)` — Search skills by name or keyword.

**Messages RPCs (2)**:
*   `db.messages.append(session_id, role, content, tool_name?)` — Append message to transcript. Real-time streaming.
*   `db.messages.list(session_id, limit?, offset?)` — Query messages for a session. Paginated.

**Agents RPCs (3)**:
*   `db.agents.register(id, label, claims)` — Register or update agent identity.
*   `db.agents.get(id)` — Get agent by ID with current effort assignment.
*   `db.agents.list()` — List all registered agents with their current effort assignments.

**Search RPCs (5)**:
*   `search.upsert(source_type, source_path, chunk_text)` — Insert or update embedding for a content chunk.
*   `search.query(query, source_type?, project_id?)` — Semantic search over embeddings. Filterable by source type and project.
*   `search.delete(source_path)` — Remove embeddings for a source path.
*   `search.status(project_id?)` — Get embedding index statistics.
*   `search.reindex(source_type?, project_id?)` — Rebuild embeddings for a source type or project.

### 4.2 Hook RPCs (`hooks.*`) — Batched Hook Operations

Called by bash hook scripts. Daemon processes hook state and returns decisions + injection content.

*   `hooks.sessionStart(agent_id, pid)` — Creates or finds session using Claude's session ID. Returns: session row, effort context (phases, current phase, required files as paths), dehydration payload if resuming.
*   `hooks.preToolUse(session_id, tool, args)` — Batched guard check. Returns: `{allow: true}` or `{block: true, reason, injection}`. Checks: heartbeat threshold, directive gate. **Replaces 3 separate bash hooks** (session-gate, heartbeat, directive-gate).
*   `hooks.postToolUse(session_id, tool, result)` — Batched state update. Returns: `{injections[], updated state}`. Updates: heartbeat, loaded_files (on Read), discovered directories. **Replaces 4 separate bash hooks** (discovery, details-log, templates, phase-commands).
*   `hooks.userPrompt(session_id, prompt)` — Receives user prompt text. Appends to messages table. Returns formatted content for bash to write (if needed).

### 4.3 Bash Compound Commands (3)

These orchestrate filesystem I/O and daemon RPCs. The bash layer handles all file operations.

*   **`engine effort start <dir> <skill>`** — Full orchestration:
    1. Scan SKILL.md from FS, parse skill data
    2. Call `db.task.upsert` + `db.effort.start` + `db.session.start`
    3. Run RAG search (`search.sessions`, `search.docs`)
    4. Discover directives for directories of interest
    5. Format markdown output (`## SRC_*` sections) for LLM consumption
    Returns same markdown format as current `engine session activate`.

*   **`engine session continue <dir?>`** — Context overflow recovery:
    1. Find agent's last session
    2. Create new session with `prev_session_id`
    3. Load effort's required files from FS
    4. Format context output
    Same markdown format as current `engine session continue`.

*   **`engine log <file> <<content`** — Logging:
    1. Call daemon for effort metadata (prefix, ordinal)
    2. Format content with timestamp
    3. Write to effort-prefixed file (e.g., `1_BRAINSTORM_LOG.md`)

---

## 5. Hook Architecture

### 5.1 Four Hook Events

```
§FLOWGRAPH: Hook Event Flow

[SessionStart] -->|hooks.sessionStart| [Daemon: create/find session]
[Daemon: create/find session] -->|session + effort context| [Hook: inject standards + required files]

[UserPromptSubmit] -->|hooks.userPrompt| [Daemon: append messages, format]
[Daemon: append messages, format] -->|formatted content| [Hook: write to FS if needed]

[PreToolUse] -->|hooks.preToolUse (batched)| [Daemon: heartbeat + directive gate]
[Daemon: heartbeat + directive gate] -->|allow or block + injection| [Hook: pass-through or block]

[PostToolUse] -->|hooks.postToolUse (batched)| [Daemon: heartbeat + loaded_files + dirs]
[Daemon: heartbeat + loaded_files + dirs] -->|injections[]| [Hook: write content to FS]
```

**General pattern**: RPC formats content, hook writes FS.

**SessionStart**: Fires when a new Claude Code instance starts. Creates or finds session, returns effort context. Injects standards (COMMANDS.md, INVARIANTS.md, SIGILS.md) + effort required files. If resuming: loads dehydrated context from prev_session's dehydration_payload.

**UserPromptSubmit**: Fires when user sends a message. Appends to messages table (real-time streaming). Returns formatted content for bash to write if needed.

**PreToolUse**: Fires before every tool call. Single batched RPC replaces 3 separate bash hooks (session-gate, heartbeat, directive-gate). Returns allow/block decision with optional injection content.

**PostToolUse**: Fires after every tool call. Single batched RPC replaces 4 separate bash hooks (discovery, details-log, templates, phase-commands). Updates heartbeat, loaded_files (on Read), discovered directories. Returns injection instructions (new directives, template preloads).

### 5.2 Session ID from Claude

All hooks derive session_id from Claude's native session ID. The SessionStart hook registers this with the daemon. All subsequent hook calls pass it automatically. No manual session tracking needed.

---

## 6. Fleet Coordination and Ownership

### 6.1 PID Elimination

v3 eliminates PID as an ownership concept entirely. In v2, PID guards on RPCs prevented agents from accidentally operating on another agent's task. In v3, ownership is agent-based:

*   `agents.effort_id` FK — the agent's current effort assignment
*   Efforts cannot be stolen by other agents
*   Agent can only have 1 active effort at a time
*   No PID guards on any RPC

### 6.2 Session Acquisition Flow

```
§FLOWGRAPH: Session Acquisition

[Fresh Start] --> [User invokes skill]
[User invokes skill] --> [engine effort start: task + effort + session]
[engine effort start: task + effort + session] --> [Work proceeds]

[Context Overflow] --> [session.finish with dehydration_payload]
[session.finish with dehydration_payload] --> [Engine checks agent's last session]
[Engine checks agent's last session] -->|session open| [claude --resume (same context)]
[Engine checks agent's last session] -->|session closed| [New session + SessionStart hook]
[New session + SessionStart hook] --> [Picks up from last session via prev_session_id]

[Skill Transition] --> [effort.finish (brainstorm done)]
[effort.finish (brainstorm done)] --> [effort.start (new skill, ordinal=2)]
[effort.start (new skill, ordinal=2)] --> [Same session continues (effort_id updated)]
```

**Context Preservation via --resume**: The `claude --resume` flag enables reusing the SAME context window across Claude restarts. Instead of creating a new session every time, the engine can resume the exact context state. Fewer session rows, no context loss on minor restarts, dehydration only needed for true overflow.

### 6.3 Fleet Monitoring

The `fleet_status` view gives "who is doing what" in one query:

```sql
SELECT a.id AS agent, a.label, e.skill, e.current_phase,
       s.heartbeat_counter, s.context_usage
FROM agents a
JOIN efforts e ON a.effort_id = e.id
LEFT JOIN sessions s ON s.effort_id = e.id AND s.ended_at IS NULL;
```

---

## 7. Embeddings and Search

Unchanged from v2. The embeddings table provides unified search across sessions, docs, and directives.

*   **Model**: Gemini text-embedding-004 (3072-dim Float32Array)
*   **Source types**: 'session', 'doc', 'directive'
*   **Search RPCs**: `search.sessions`, `search.docs`, `search.directives` — all project-scoped by default
*   **Cross-project search**: Available as opt-in, not default

**Open question**: Should messages table content be indexed in embeddings? The 'dialogue' source_type from v2 may be revisited since DIALOGUE.md is eliminated — messages table content could be indexed instead. Deferred — evaluate after messages table is populated with real data.

---

## 8. Observability

### 8.1 Status Line

Status line shows effort ordinal only when > 1:

*   First effort: `[brainstorm:P1]`
*   Second effort: `[2:impl:P3]`
*   Third effort: `[3:brainstorm:P2]`

### 8.2 Artifact Naming Convention

All effort artifacts are prefixed with the effort ordinal and skill name in UPPER_SNAKE:

*   `1_BRAINSTORM.md` — first effort's debrief
*   `1_BRAINSTORM_LOG.md` — first effort's log
*   `2_IMPLEMENTATION.md` — second effort's debrief
*   `2_IMPLEMENTATION_LOG.md` — second effort's log
*   `2_IMPLEMENTATION_PLAN.md` — second effort's plan
*   `3_BRAINSTORM.md` — third effort (second brainstorm) debrief

### 8.3 Cross-Effort Discovery

When a new effort starts, it auto-discovers debriefs from prior efforts in the same task. The daemon queries efforts by task_id and returns finished efforts' debrief paths. The bash layer reads these files and includes them as context for the new effort.

### 8.4 Health Monitoring

The `stale_sessions` view detects stuck agents:

```sql
SELECT s.*, t.dir_path AS task_dir
FROM sessions s JOIN tasks t ON s.task_id = t.dir_path
WHERE s.ended_at IS NULL
  AND s.last_heartbeat < datetime('now', '-5 minutes');
```

---

## 9. Invariants

### Kept (Unchanged)

*   **INV_DAEMON_IS_THE_LOCK** — Single-threaded event loop serializes all mutations.
*   **INV_ONE_ACCESS_PATH** — All DB access through daemon RPC or `engine query`.
*   **INV_NO_DAEMON_RECURSION** — Daemon must never call itself.
*   **INV_HARD_FAILURE** — Daemon down = exit 1. No silent fallback.

### Kept (Updated Scope)

*   **INV_SESSIONS_ARE_EPHEMERAL** — Sessions track context windows. Even more ephemeral in v3 — sessions are just Claude instance lifetimes, with no lifecycle management responsibilities.
*   **INV_TASKS_ARE_PERSISTENT** — Tasks are permanent containers. Updated: tasks NEVER finish. Active/dormant derived from efforts.

### Replaced

*   **INV_DAEMON_READS_FS_ONLY → INV_DAEMON_IS_PURE_DB** — Stronger than v2. The daemon touches ONLY SQLite. Zero filesystem reads. Zero filesystem writes. Bash handles all FS. This is the absolute boundary.
*   **INV_PID_OWNERSHIP → INV_AGENT_OWNS_EFFORT** — Agent-based ownership via agents.effort_id FK. Agent can have 1 active effort. Efforts cannot be stolen. No PID guards.

### New

*   **INV_EFFORTS_OWN_PHASES** — Phases belong to efforts, not tasks. phase_history FK→efforts. Brainstorm effort #1 and implementation effort #2 have completely independent phase histories.
*   **INV_EFFORT_ORDINAL_ARTIFACTS** — Artifacts prefixed with effort ordinal: `{ordinal}_{SKILL}_{type}.md`. Enables multiple skills' artifacts to coexist in one task directory.
*   **INV_DB_PRIMARY_FOR_TRANSCRIPTS** — Messages table is source of truth for conversation history. DIALOGUE.md eliminated entirely. "FS is truth for artifacts, DB is truth for operational data."
*   **INV_BASH_OWNS_FS** — All filesystem I/O through bash CLI, never daemon. Compound commands orchestrate FS + RPC.
*   **INV_SESSION_CONTINUITY** — Prefer `claude --resume` over creating new sessions. Preserve context windows where possible. Fewer sessions = less churn.

---

## 10. Migration Strategy

### Approach: Rewrite in Place

Pre-production tooling. No backward compatibility needed.

*   Replace v2 schema (tasks/sessions/agents/phase_history/dehydration_snapshots — 5 tables) with v3 (9 tables)
*   Replace `db.session.*` RPCs with `db.task.*`, `db.effort.*`, `db.session.*` RPCs
*   Update hook scripts to call new RPCs
*   Update bash compound commands (`engine effort start`, `engine session continue`, `engine log`)
*   Break existing tests, fix them

### What Changes for the LLM

**For now, nothing.** The CLI output format (`## SRC_*` markdown sections) stays the same. SKILL.md references to `engine session activate` stay the same. The internal implementation changes, but the LLM-facing interface is preserved until a separate protocol update session.

### Schema Migration

No ALTER TABLE logic. Schema change = drop and recreate. Acceptable for pre-production.

---

## 11. Paradigm Shifts from v2

### DB-Primary for Transcripts

*   **v2**: DIALOGUE.md is the source of truth for conversation history (filesystem artifact).
*   **v3**: Messages table is the source of truth (database). DIALOGUE.md is eliminated entirely.
*   **Implication**: Some data now lives only in the DB. The rule "FS is truth, DB is index" becomes "FS is truth for artifacts, DB is truth for operational data (transcripts)."

### Skills as First-Class DB Entities

*   **v2**: Skills are strings on the task row. Skill metadata lives only in SKILL.md files.
*   **v3**: Skills table caches parsed SKILL.md data. The daemon understands skill structure (phases, modes, templates, dependencies).
*   **Implication**: The daemon can answer "what phases does this skill have?" without reading the filesystem. Bash parses SKILL.md and feeds data to the daemon.

### Effort-Scoped Phases

*   **v2**: phase_history FK→tasks. Phases belong to the task.
*   **v3**: phase_history FK→efforts. Phases belong to skill invocations.
*   **Implication**: Different skills have different phases — brainstorm and implement each get their own independent phase timeline. This is the correct model.

### Agent-Based Ownership

*   **v2**: PID-based session ownership. PID guards on RPCs.
*   **v3**: Agent-based effort ownership via agents.effort_id FK. No PID guards.
*   **Implication**: `claude --resume` enables context window reuse. Ownership is stable across Claude restarts. "Who owns what" is answered by the agents table, not by PID matching.

---

## 12. Open Items (Deferred)

*   **TASK.md generation**: Agent writes TASK.md during effort debrief pipeline. Daemon provides data via a future `task.summarize` RPC. Not critical for v3 core.
*   **Fleet event model**: Polling vs event-driven notification when efforts finish. Polling is sufficient for now.
*   **Embeddings for messages**: Whether messages table content should be indexed. Evaluate after messages table is populated with real data.
*   **Schema migration tooling**: No ALTER TABLE logic. Drop and recreate. Acceptable for pre-production.
*   **fs.* RPC cluster**: RESOLVED — `fs.files.read`, `fs.files.append`, `fs.paths.resolve` built as workspace package `tools/fs/`. `commands.log.append` refactored to use `fs.files.append` via dispatch.

---

## Appendix: Decision Registry (20 Rounds)

### Round 1: Three-Layer Decomposition
Sessions span efforts. Effort lifecycle replaces session lifecycle. Phase history moves to per-effort.

### Round 2: Session-Effort Binding
Session tracks which effort it serves (effort_id on session, not reverse). Multiple concurrent efforts per task allowed (fleet).

### Round 3: Effort Lifecycle and Artifacts
Binary lifecycle (active/finished). Multiple same-skill efforts allowed. Ordinal-prefixed artifacts. Auto-discover prior effort debriefs.

### Round 4: RPC Restructuring
No task.finish — tasks are permanent. Consistent start/finish verbs, all idempotent. Four RPC namespaces.

### Round 5: Schema Crystallization
session.effort_id NOT NULL. UNIQUE(task_id, ordinal). Dehydration moves to session column.

### Round 6: Compound Flows and CLI
Two-tier RPC naming. One CLI entry point: `engine effort start`. Session auto-start on overflow via hook.

### Round 7: Fleet and Agents
Agent owns effort (1:1). Status line shows ordinal only if > 1.

### Round 8: Migration and CLI
Rewrite in place. Hooks use `engine rpc` (batched). SKILL.md docs untouched for now.

### Round 9: Hook Architecture
General pattern: RPC formats content, hook writes FS. PreToolUse replaces 3 hooks. PostToolUse replaces 4 hooks.

### Round 10: Fleet Events
Fleet monitoring is primary query pattern. Event model deferred (polling sufficient).

### Round 11: Devil's Advocate
Three layers confirmed as worth the complexity. DB-primary for transcripts accepted. Task lifecycle derived, not stored.

### Round 12: Deep Dive — DB Transcripts
Messages table (separate, not blob). Real-time streaming. Dehydration stays separate. DIALOGUE.md eliminated.

### Round 13: Gaps Resolution
Tags stay in filesystem. Engine log through daemon. Cross-effort context only via debriefs. Skills table proposed.

### Round 14: Skills Table and Projects
Projects table for shared daemon. Skills per-project. Phases NOT duplicated to effort row.

### Round 15: Messages and Projects Detail
Messages minimal (id, session_id, role, content, tool_name, timestamp). Project derived from dir_path. Search project-scoped.

### Round 16: effort.start Deep Dive
One atomic transaction. Daemon returns file paths, hook reads content. Same markdown output format. Missing skill = error.

### Round 17: FS/DB Separation
Daemon = pure DB. Zero FS. Bash orchestrates: read FS → call daemon RPC → write FS.

### Round 18: Views and Indexes
Fleet monitoring as primary query pattern. Compound indexes. Dynamic SQL views.

### Round 19: Complete RPC Inventory
session_id from Claude's native session ID. 27 daemon + 4 hook + 3 bash compound commands.

### Round 20: PID Elimination
Agent-based ownership. `claude --resume` for context preservation. Session acquisition by agent_id lookup.

---

## Appendix: Compound Flow Examples

### effort.start Flow

```
§FLOWGRAPH: effort.start Compound Flow

[Bash: read SKILL.md from FS] --> [Bash: parse skill data]
[Bash: parse skill data] --> [Daemon: db.task.upsert (idempotent)]
[Daemon: db.task.upsert (idempotent)] --> [Daemon: db.effort.start (ordinal assigned)]
[Daemon: db.effort.start (ordinal assigned)] --> [Daemon: db.session.start]
[Daemon: db.session.start] --> [Bash: returns to bash with effort row]
[Bash: returns to bash with effort row] --> [Bash: read prior effort debriefs from FS]
[Bash: read prior effort debriefs from FS] --> [Daemon: search.sessions + search.docs (RAG)]
[Daemon: search.sessions + search.docs (RAG)] --> [Bash: discover directives from FS]
[Bash: discover directives from FS] --> [Bash: format markdown output for LLM]
```

### engine log Flow

```
§FLOWGRAPH: engine log Flow

[Bash: receive content via heredoc] --> [Daemon: query effort metadata (ordinal, skill)]
[Daemon: query effort metadata (ordinal, skill)] --> [Bash: receives prefix e.g. 1_BRAINSTORM]
[Bash: receives prefix e.g. 1_BRAINSTORM] --> [Bash: inject timestamp, write to 1_BRAINSTORM_LOG.md]
```

### Context Overflow Recovery Flow

```
§FLOWGRAPH: Context Overflow Recovery

[Context fills up] --> [session.finish with dehydration_payload]
[session.finish with dehydration_payload] --> [Engine checks agent's last session]
[Engine checks agent's last session] -->|open| [claude --resume (exact same context)]
[Engine checks agent's last session] -->|closed| [New session created]
[New session created] --> [SessionStart hook fires]
[SessionStart hook fires] --> [hooks.sessionStart: new session with prev_session_id]
[hooks.sessionStart: new session with prev_session_id] --> [Load effort's required files from FS]
[Load effort's required files from FS] --> [Resume at saved phase]
```
