# Workflow Engine User Guide

How a human developer uses the workflow engine day-to-day: opening agents, running skills, chaining sessions, coordinating fleets, and recovering from context overflow.

**Related**: `~/.claude/docs/SESSION_LIFECYCLE.md` (session state machine), `~/.claude/docs/FLEET.md` (fleet multi-agent workspace), `~/.claude/docs/CONTEXT_GUARDIAN.md` (overflow protection), `~/.claude/docs/DIRECTIVES_SYSTEM.md` (behavioral specification), `~/.claude/docs/DAEMON.md` (dispatch daemon)

---

## 1. Overview

The workflow engine is a session-gated, phase-enforced skill execution system that turns Claude Code into a disciplined development partner. Three concepts define how it works:

- **Skills** are protocols. Each skill (`/implement`, `/test`, `/fix`, `/analyze`, `/document`, `/brainstorm`, `/loop`, `/review`) defines a multi-phase procedure with interrogation, planning, execution, and synthesis stages. The protocol IS the task — the user's request is an input parameter.
- **Sessions** are containers. A session directory (`sessions/YYYY_MM_DD_TOPIC/`) holds all artifacts: logs, plans, debriefs, and state. Sessions are multi-modal — the same directory can host `/implement` followed by `/test`.
- **Phases** are checkpoints. Each skill defines numbered phases (Setup, Interrogation, Planning, Execution, Synthesis). Phase transitions are mechanically enforced — agents cannot skip phases without user approval.

**The core loop**: Open agent → pick skill → work through phases → debrief → chain to next skill → repeat. An agent can run indefinitely, chaining skills without human restarts.

---

## 2. Bootstrap & Setup

Run the engine setup script to install all components (hooks, tools, status line, symlinks):

```bash
~/.claude/engine/engine.sh
```

For multi-agent workspaces, configure fleet tmux layouts in your Google Drive assets folder. Each fleet config defines a tmux session with labeled panes, one Claude instance per pane.

See `~/.claude/docs/ENGINE_CLI.md` for full setup details, environment variable injection, migration system, and testability.

---

## 3. Session Lifecycle

Every interaction with the workflow engine happens inside a session. The session gate (`pre-tool-use-session-gate.sh`) blocks all non-whitelisted tools until a session is activated — you MUST invoke a skill to start working.

### Activation

When you invoke a skill (e.g., `/implement`), the skill protocol calls `engine session activate`, which:
1. Creates or reuses a session directory under `sessions/`
2. Writes `.state.json` with PID, skill name, phase tracking, and logging enforcement thresholds
3. Sets `lifecycle=active`, enabling all tools

### Phases

Each skill defines a sequence of phases. The agent transitions between them via `engine session phase`, which updates `.state.json` and the status line. Phase enforcement is mechanical — non-sequential transitions (skip forward or backward) require explicit user approval via `--user-approved`.

### Deactivation

After synthesis (writing the debrief), the skill calls `engine session deactivate`, which:
1. Sets `lifecycle=completed` — the session gate re-engages
2. Stores a description and search keywords for future RAG discoverability
3. Runs a RAG search returning related past sessions
4. Presents the "Next Skill" menu

### State Tracking

`.state.json` is the coordination contract. Key fields:

| Field | Purpose |
|-------|---------|
| `pid` | Process identity (guards one-Claude-per-session) |
| `skill` | Current skill name |
| `currentPhase` | Phase for status line + restart recovery |
| `lifecycle` | `active` / `completed` / `dehydrating` / `restarting` / `resuming` |
| `overflowed` | Sticky flag — blocks `--resume` until fresh activation |
| `contextUsage` | Raw context percentage (0.0–1.0) |

See `~/.claude/docs/SESSION_LIFECYCLE.md` for the full state machine, all 11 scenarios, race conditions, and component responsibilities.

---

## 4. The Skill System

### Available Skills

| Skill | Purpose | Tier |
|-------|---------|------|
| `/implement` | Feature implementation with TDD | Protocol |
| `/test` | Test design and coverage | Protocol |
| `/fix` | Bug diagnosis and repair | Protocol |
| `/analyze` | Code/architecture analysis | Protocol |
| `/document` | Documentation updates | Protocol |
| `/brainstorm` | Ideation and trade-off analysis | Protocol |
| `/loop` | Prompt/schema iteration (TDD for LLMs) | Protocol |
| `/review` | Cross-session work validation | Protocol |
| `/chores` | Routine maintenance tasks | Utility |
| `/delegation-create` | Task delegation between agents | Utility |
| `/delegation-claim` | Worker-side claiming of delegated work | Utility |
| `/delegation-review` | Dispatch approval for `#needs-X` tags | Utility |

**Protocol skills** run the full session lifecycle: Setup → Interrogation → Planning → Execution → Synthesis. **Utility skills** are lighter — they perform focused operations without the full ceremony.

### Skill Anatomy

Every protocol skill follows this structure:

1. **Boot sequence**: Load directives (COMMANDS.md, INVARIANTS.md, SIGILS.md), output boot proof
2. **Phase 1: Setup**: Parse parameters, create/reuse session directory, assume role, load templates
3. **Interrogation** (optional but enforced): 3+ rounds of structured questioning to validate assumptions. Depth selection: Short (3+), Medium (6+), Long (9+), Absolute (until all resolved)
4. **Phase 2: Planning**: Ingest context, survey the problem space, write a plan artifact, present for user approval
5. **Phase 3: Execution**: Execute the plan with continuous logging. Every 3-4 tool calls, log progress to `_LOG.md`
6. **Phase 4: Synthesis**: Write the debrief, manage TOC, process checklists, report artifacts, present next-skill menu

### Mode Presets

Many skills offer mode presets that configure their scope and approach. For example, `/document` offers Surgical (targeted fixes), Comprehensive (full rewrite), and Audit (read-only verification). `/analyze` offers Explore, Audit, Improve, and Custom. Modes are selected in Phase 1 via `AskUserQuestion`.

---

## 5. Skill Chaining (The Endless Session)

The most powerful pattern in the workflow engine is **skill chaining**: completing one skill and immediately starting another, all within the same agent session and (optionally) the same session directory.

### How It Works

1. A skill completes its synthesis phase and writes a debrief
2. The debrief protocol (`§CMD_GENERATE_DEBRIEF`) runs post-synthesis steps: TOC management, invariant capture, side discovery tagging, leftover work reporting
3. `§CMD_CLOSE_SESSION` deactivates the session and presents the "Next Skill" menu
4. Each skill defines its own recommended next steps. For example, `/implement` recommends `/test`, `/test` recommends `/document`, `/document` recommends `/review`
5. The user selects a skill (or types a skill name via "Other"), and the Skill tool invokes it
6. The new skill runs `engine session activate` — which detects the existing session directory and offers to reuse it

### The Endless Agent Pattern

An agent can chain indefinitely:

```
/implement → /test → /document → /review → /implement → ...
```

Each skill uses its own log file (`IMPLEMENTATION_LOG.md`, `TESTING_LOG.md`, `DOCUMENTATION_LOG.md`, etc.) within the same session directory. The directory accumulates artifacts across skills, building a complete record of the work.

### Session Reuse vs New Session

When a new skill activates in an existing session directory:
- If **no artifacts** from the new skill type exist: proceed normally (sessions are multi-modal)
- If **artifacts already exist** (e.g., `IMPLEMENTATION_LOG.md` from a previous `/implement`): the agent asks whether to continue the existing skill phase or start a new session with a distinguishing suffix

### Post-Synthesis Continuation

If the user sends a message after synthesis (without choosing a skill), `§CMD_RESUME_AFTER_CLOSE` fires: it reactivates the session, logs a continuation header, and works on the user's request. When done, the debrief is regenerated (not appended) to maintain coherence.

---

## 6. Fleet Coordination & Delegation

### Fleet = Multi-Agent Workspace

A fleet is multiple Claude instances running in tmux panes, each on a different task. Fleet provides:
- **Session persistence**: Each pane's Claude conversation resumes after fleet restart (via `sessionId` in `.state.json`)
- **Pane identity**: Stable `fleetPaneId` (e.g., `yarik-fleet:company:SDK`) survives process restarts
- **Socket isolation**: Each workgroup runs on its own tmux socket (`fleet`, `fleet-project`, etc.)

```bash
fleet.sh start              # Start default fleet
fleet.sh start project      # Start project workgroup fleet
fleet.sh stop               # Stop default fleet
fleet.sh status             # Show all fleets with running/stopped status
fleet.sh attach             # Attach to fleet tmux session
```

### Delegation (4-State Lifecycle)

Work delegation follows a 4-state tag lifecycle with clear actor separation:

```
#needs-X → #delegated-X → #claimed-X → #done-X
 (agent)    (human)         (worker)     (worker)
```

1. **Agent creates work**: Any skill agent tags a REQUEST file or inline location with `#needs-X` (e.g., `#needs-implementation`, `#needs-brainstorm`)
2. **Human approves dispatch**: During synthesis, `/delegation-review` presents pending `#needs-X` items for review. Approved items are flipped to `#delegated-X`
3. **Worker claims**: The `/delegation-claim` skill (invoked by daemon or manually) swaps `#delegated-X` → `#claimed-X` via `tag.sh swap` (race-safe — errors if already claimed)
4. **Worker completes**: The target skill resolves the work and swaps `#claimed-X` → `#done-X`

### Dispatch Daemon

The dispatch daemon (`run.sh --monitor-tags`) watches for `#delegated-*` tags and spawns Claude to process them:

```
Agent creates #needs-X tag during any skill
  → Human approves: #needs-X → #delegated-X (during synthesis)
  → Daemon (fswatch) detects #delegated-X
  → 3s debounce (collect batch writes)
  → Daemon spawns Claude with /delegation-claim
  → /delegation-claim: #delegated-X → #claimed-X (race-safe swap)
  → /delegation-claim routes to target skill (e.g., /implement)
  → Worker completes: #claimed-X → #done-X
  → Daemon rescans for more work
```

**Key**: The daemon monitors `#delegated-*` only (not `#needs-*`). Work must be human-approved before autonomous dispatch.

See `~/.claude/docs/FLEET.md` for full fleet documentation and `~/.claude/docs/DAEMON.md` for the dispatch architecture.

---

## 7. Review & Quality Loop

### The Review Skill

`/review` validates completed work across sessions. It discovers all files tagged `#needs-review` (auto-applied at debrief creation), performs cross-session analysis, and walks the user through structured approval:
- **Approve** → tag swapped to `#done-review`
- **Reject** → tag swapped to `#needs-rework`, rejection context added

### Progress Summaries

`/summarize-progress` generates cross-session reports — useful for end-of-day status updates or multi-day project tracking.

### Tag-Driven Quality

The tag system (`~/.claude/.directives/SIGILS.md`) provides asynchronous work routing via the 4-state lifecycle:

| Tag | Resolving Skill | When Applied | Daemon-Dispatchable |
|-----|----------------|--------------|---------------------|
| `#needs-review` | `/review` | Auto-applied at debrief creation | No (user-invoked) |
| `#needs-documentation` | `/document` | Applied for code-changing sessions | Yes |
| `#needs-implementation` | `/implement` | Applied inline when implementation work is deferred | Yes |
| `#needs-brainstorm` | `/brainstorm` | Applied inline when topics need exploration | Yes |
| `#needs-research` | `/research` | Applied for async Gemini Deep Research | Yes |
| `#needs-fix` | `/fix` | Applied inline when bugs are identified | Yes |
| `#needs-chores` | `/chores` | Applied for small self-contained tasks | Yes |

Tags marked "Daemon-Dispatchable" follow the full 4-state lifecycle: `#needs-X` (staging) → `#delegated-X` (human-approved) → `#claimed-X` (worker active) → `#done-X` (resolved). The `#needs-X` → `#delegated-X` transition requires human approval via `/delegation-review` during synthesis.

### End-of-Day Workflow

A typical end-of-day pattern:

```
/review              → Validate today's debriefs
/summarize-progress  → Generate status report
/delegation-claim    → Pick up any #delegated-* work items
```

---

## 8. Context Overflow & Recovery

Claude Code has a limited context window. When it fills up during long sessions, the Context Guardian system handles recovery automatically.

### Detection

The status line script (`statusline.sh`) tracks `contextUsage` in `.state.json`. The overflow hook (`pre-tool-use-overflow.sh`) fires before every tool call. When `contextUsage >= 0.76` (raw, which maps to ~95% of the 80% auto-compact threshold):

1. **Block**: All tools are blocked (except logging and session scripts)
2. **Force dehydration**: Claude must run `/session dehydrate restart`

### Dehydration

`/session dehydrate` writes `DEHYDRATED_CONTEXT.md` — a structured handover document containing:
- Ultimate goal and strategy
- Last action and outcome
- Required files list (for reloading in the new context)
- Next steps

### Restart

After dehydration, `engine session restart` signals the restart watchdog (via USR1). The watchdog kills the current Claude process. `run.sh` detects the exit, reads the restart prompt from `.state.json`, and spawns a fresh Claude with NO `--resume` (overflow means the old context is too large).

### Restoration

The new Claude receives `/session continue` as its first prompt. `/session continue`:
1. Activates the session (clears `overflowed`, sets new PID)
2. Loads directives (COMMANDS.md, INVARIANTS.md, SIGILS.md)
3. Reads `DEHYDRATED_CONTEXT.md`
4. Loads all required files (session artifacts, skill templates, source code)
5. Loads the original skill protocol
6. Resumes at the saved phase

**To the user, this is seamless**: the agent picks up exactly where it left off, with a fresh context window.

See `~/.claude/docs/CONTEXT_GUARDIAN.md` for component details and `~/.claude/docs/SESSION_LIFECYCLE.md` §4 (S4) for the full state transition flow.

---

## 9. Standards & Discipline

Three documents define the "operating system" for all agent interactions:

| Document | Prefix | Role |
|----------|--------|------|
| `COMMANDS.md` | `§CMD_` | 32 named operations — the instruction set agents execute |
| `INVARIANTS.md` | `¶INV_` | 23 universal rules — the laws that cannot be overridden |
| `SIGILS.md` | `§FEED_` | 6 tag feeds — cross-session communication protocol |

Together they define ~1,100 lines of behavioral specification loaded into every agent session.

### Logging Discipline

Agents must log every 3-4 tool calls to their `_LOG.md` file. This is mechanically enforced by `pre-tool-use-heartbeat.sh`:
- **Warn** at 3 tool calls without logging
- **Block** at 10 tool calls without logging (tool use denied until a log entry is appended)

The log is the agent's brain — unlogged work is invisible work. Each skill has its own log template defining structured entry types (e.g., Hypothesis/Attempt/Result for `/fix`, Incision/Bleeding/Suture for `/document`).

### Phase Enforcement

Phase transitions are tracked in `.state.json` via `engine session phase`. Non-sequential transitions (skipping a phase or going backward) are rejected unless `--user-approved` is passed with a reason citing the user's explicit approval. This prevents agents from silently skipping protocol steps they judge as "unnecessary."

See `~/.claude/docs/DIRECTIVES_SYSTEM.md` for the full architecture of the standards layer and how it relates to skill protocols.

---

## 10. Cross-Reference Table

| Topic | Detailed Documentation |
|-------|----------------------|
| Session state machine & scenarios | `~/.claude/docs/SESSION_LIFECYCLE.md` |
| Fleet multi-agent workspace | `~/.claude/docs/FLEET.md` |
| Context overflow protection | `~/.claude/docs/CONTEXT_GUARDIAN.md` |
| Dispatch daemon & workers | `~/.claude/docs/DAEMON.md` |
| Standards system architecture | `~/.claude/docs/DIRECTIVES_SYSTEM.md` |
| Engine CLI & migrations | `~/.claude/docs/ENGINE_CLI.md` |
| Engine script testing | `~/.claude/docs/ENGINE_TESTING.md` |
| Command definitions | `~/.claude/.directives/COMMANDS.md` |
| System invariants | `~/.claude/.directives/INVARIANTS.md` |
| Tag feeds & lifecycle | `~/.claude/.directives/SIGILS.md` |
| Individual skill protocols | `~/.claude/skills/[skill-name]/SKILL.md` |
