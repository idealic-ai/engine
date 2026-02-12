# Session Lifecycle

Comprehensive reference for session startup, restart, restore, and rehydration — all scenarios, state transitions, identity fields, and race conditions.

**Related**: `~/.claude/docs/CONTEXT_GUARDIAN.md` (overflow subsystem), `~/.claude/docs/FLEET.md` (fleet management), `~/.claude/docs/DIRECTIVES_SYSTEM.md` (behavioral specification — commands, invariants, tags)

---

## 1. What Is a Session?

A **session** is a working directory under `sessions/` (e.g., `sessions/2026_02_07_MY_TOPIC/`) that tracks one logical unit of work. The session's state is stored in `.state.json` — a JSON file that acts as the coordination contract between all components.

### Components That Read/Write `.state.json`

| Component | Role | Reads | Writes |
|-----------|------|-------|--------|
| `session.sh activate` | Creates session, sets identity | Existing `.state.json` | pid, skill, lifecycle, loading (→ true), overflowed (→ false), killRequested (→ false), fleetPaneId, startedAt, toolCallsSinceLastLog (→ 0), toolUseWithoutLogsWarnAfter (→ 3), toolUseWithoutLogsBlockAfter (→ 10) |
| `session.sh find` | Locates active session (read-only) | fleetPaneId, pid across all `.state.json` files | — (read-only, no writes) |
| `session.sh phase` | Updates phase tracking | — | currentPhase, lastHeartbeat, loading (deleted), toolCallsByTranscript (reset to {}) |
| `session.sh deactivate` | Marks session completed (gate re-engages) | — | lifecycle (→ completed), lastHeartbeat, sessionDescription (from stdin), keywords (from --keywords flag) |
| `session.sh restart` | Initiates restart (state-only — does not kill) | skill, currentPhase | killRequested (→ true), restartPrompt, contextUsage (→ 0), sessionId (deleted) |
| `statusline.sh` | Binds sessionId, updates context | pid/fleetPaneId (lookup), killRequested, overflowed | sessionId, contextUsage, lastHeartbeat, pid (claim) |
| `pre-tool-use-overflow.sh` | Blocks tools at overflow | sessionId/fleetPaneId/pid (lookup), contextUsage, overflowed, lifecycle | overflowed (→ true), lifecycle (→ dehydrating when /session dehydrate invoked) |
| `run.sh` | Process supervisor, restart loop | fleetPaneId (fleet resume), killRequested, restartPrompt, sessionId, overflowed | pid (reset to 0), lifecycle (→ resuming, → restarting) |
| Restart Watchdog (run.sh) | Kills Claude on restart signal | — (receives USR1 signal from session.sh restart) | — (sends SIGTERM to sibling processes via process group kill) |
| `pre-tool-use-heartbeat.sh` | Logging discipline enforcement | loading, toolCallsByTranscript, toolUseWithoutLogsWarnAfter, toolUseWithoutLogsBlockAfter, skill | toolCallsByTranscript (increment/reset per transcript key) |
| `pre-tool-use-session-gate.sh` | Blocks tools when no active session (SESSION_REQUIRED gate) | SESSION_REQUIRED env, lifecycle (via session.sh find) | — (read-only, denies/allows) |
| `user-prompt-submit-session-gate.sh` | Injects boot instructions when no active session | SESSION_REQUIRED env, lifecycle (via session.sh find) | — (read-only, injects message) |
| `/session dehydrate` subcommand | Saves context to file | session dir contents | DEHYDRATED_CONTEXT.md (separate file) |
| `/session continue` subcommand | Restores context after restart | DEHYDRATED_CONTEXT.md, session artifacts | (calls session.sh activate → clears overflowed, killRequested) |

---

## 2. Identity Fields

Three fields identify "who owns this session." They serve different purposes and are set at different times.

### `pid` — Process Identity

- **Set by**: `session.sh activate` (reads `$CLAUDE_SUPERVISOR_PID` env var, fallback `$PPID`)
- **Value**: Claude's OS process ID (specifically run.sh's PID via `$CLAUDE_SUPERVISOR_PID`)
- **Purpose**: Guards against two Claudes using the same session simultaneously. Also used by the restart watchdog to scope kill signals.
- **Lifecycle**: Set at activation. Becomes stale when Claude exits (PID no longer running). Checked via `kill -0 $pid`.
- **Limitation**: Changes on every restart. Cannot survive fleet stop/start cycles.

### `sessionId` — Claude Internal Session Identity

- **Set by**: `statusline.sh` (extracts from Claude's status line JSON input, field `.session_id`)
- **Value**: Claude Code's internal conversation identifier (UUID-like)
- **Purpose**: Enables `--resume` flag to restore Claude's conversation history across restarts
- **Lifecycle**: Not available until first statusline render (after Claude starts). Written to `.state.json` by statusline on every tick.
- **Limitation**: Only exists while Claude is running. Deleted by `session.sh restart` to prevent resuming an overflow-killed session.
- **Race condition**: See R1 below.

### `fleetPaneId` — Fleet Pane Identity

- **Set by**: `session.sh activate` (auto-detected via `fleet.sh pane-id`)
- **Value**: Composite string `{tmux_session}:{window}:{pane_label}` (e.g., `yarik-fleet:company:SDK`)
- **Format**: Produced by `fleet.sh pane-id`, which reads tmux session name, window name, and `@pane_label` user variable
- **Purpose**: Stable identity that survives fleet restart cycles (PID changes, but pane label persists)
- **Lifecycle**: Set at activation. Persists in `.state.json` across restarts. Cleared from OTHER sessions when a new activation claims the same pane (one pane = one session).
- **Limitation**: Only available inside fleet tmux (socket name = `fleet`). Returns empty outside fleet.
- **Caveat**: Three components independently capture this value at different times (`run.sh` env at startup, `session.sh activate` at activation, `fleet.sh pane-id` live). They can diverge if pane labels change. See R6.

### Lookup Priority by Component

`session.sh find` is the **single source of truth** for session lookup. It implements two strategies in order:
1. **Fleet pane match**: Calls `fleet.sh pane-id` → scans `sessions/*/.state.json` for matching `fleetPaneId`
2. **PID match**: Uses `$CLAUDE_SUPERVISOR_PID` (fallback `$PPID`) → scans for matching `pid` (alive check via `kill -0`)

`session.sh find` is **read-only** — it never claims a PID or modifies `.state.json`. PID claiming remains in `statusline.sh`.

| Component | Lookup Method | Notes |
|-----------|--------------|-------|
| `statusline.sh` | `session.sh find` | PID claiming done separately in `update_session()` |
| `pre-tool-use-overflow.sh` | `session.sh find` | Replaced ~70-line inline `find_session_dir()` |
| `pre-tool-use-heartbeat.sh` | `session.sh find` | Same lookup for logging enforcement |
| `run.sh find_fleet_session()` | Direct fleetPaneId scan | Independent — runs before `session.sh` is available |
| Restart Watchdog | — (signal-driven) | Does not read `.state.json` |

---

## 3. State Fields — Orthogonal Decomposition

The session's runtime state is tracked by three independent fields in `.state.json`. Each field answers a single question and is managed by specific components.

**Design rationale**: The previous single `status` field conflated lifecycle phase, context overflow state, and kill signaling into one enum. This caused bugs where consumers couldn't distinguish "session is between processes" from "session was overflowed" — leading to overflowed sessions being incorrectly resumed via `--resume`.

### 3.1 Field Definitions

#### `lifecycle` — Where Is This Session in Its Life?

- **Type**: enum string
- **Values**: `active` | `dehydrating` | `restarting` | `resuming`
- **Default**: `active`

| Value | Meaning | Tools Allowed? |
|-------|---------|---------------|
| `active` | Normal operation | Yes |
| `completed` | Skill synthesis done, session gate re-engages | Whitelisted only (gate blocks non-whitelisted) |
| `dehydrating` | `/session dehydrate` is running, saving context | Yes (needs Read/Write/Bash) |
| `restarting` | run.sh picked up restart prompt, spawning new Claude | N/A (between processes) |
| `resuming` | Fleet restart detected previous session | N/A (before Claude starts) |

#### `overflowed` — Was Context Exhausted?

- **Type**: boolean
- **Default**: `false`
- **Sticky**: Set to `true` when context hits threshold. Only cleared by `session.sh activate` (which proves a new Claude with fresh context has taken over).
- **Purpose**: Prevents `--resume` on an overflowed conversation. The old context is too large — resuming would hit the same overflow immediately.

| Value | Meaning | `--resume` Allowed? |
|-------|---------|-------------------|
| `false` | Context is healthy | Yes |
| `true` | Context was exhausted (overflow occurred) | **No** — fresh start required |

#### `killRequested` — Should the Process Be Terminated?

- **Type**: boolean
- **Default**: `false`
- **Purpose**: Signal from `session.sh restart` to the restart watchdog that Claude should be terminated.
- **Cleared by**: `session.sh activate` (new Claude takes over) or `run.sh` (after processing restart).

| Value | Meaning | Watchdog Action |
|-------|---------|----------------|
| `false` | Normal — don't kill | No action |
| `true` | Kill Claude and prepare restart | Watchdog sends SIGTERM |

### 3.2 Writer Audit — Who Sets Each Field?

#### `lifecycle` Writers

| Writer | Sets To | When | Guard |
|--------|---------|------|-------|
| `session.sh activate` | `active` | New skill or reactivation | Checks PID ownership |
| `session.sh deactivate` | `completed` | Skill synthesis done | Checks .state.json exists |
| `pre-tool-use-overflow.sh` | `dehydrating` | Skill tool called with `session` (dehydrate subcommand) | Trusts tool name |
| `run.sh` restart loop | `restarting` | After reading restartPrompt | Checks killRequested + restartPrompt present |
| `run.sh find_fleet_session()` | `resuming` | Fleet restart, dead PID found | Checks PID is dead |

#### `overflowed` Writers

| Writer | Sets To | When | Guard |
|--------|---------|------|-------|
| `pre-tool-use-overflow.sh` | `true` | contextUsage >= 0.76 | Only if currently `false` (implicit) |
| `session.sh activate` | `false` | New Claude activates session | Always — fresh context means not overflowed |

**Key property**: Only ONE component sets `true` (overflow hook). Only ONE component clears it (activate). The flag survives across restarts, fleet stops, and process deaths. It can only be cleared by proving a new Claude has started.

#### `killRequested` Writers

| Writer | Sets To | When | Guard |
|--------|---------|------|-------|
| `session.sh restart` | `true` | `/session dehydrate` calls restart | Trusts caller |
| `session.sh activate` | `false` | New Claude activates | Always — new lifecycle |
| `run.sh` restart loop | `false` | After processing restart prompt | Checks killRequested was true |

### 3.3 Reader Audit — Who Reads Each Field and Why?

#### `lifecycle` Readers

| Reader | Reads | Branches On | Purpose |
|--------|-------|------------|---------|
| `pre-tool-use-session-gate.sh` | lifecycle | `active`/`dehydrating` → allow; `completed` → deny (gate re-engages) | Session activation enforcement |
| `user-prompt-submit-session-gate.sh` | lifecycle | `active`/`dehydrating` → pass; `completed` → inject boot instructions | Proactive agent instruction |
| `pre-tool-use-overflow.sh` | lifecycle | `dehydrating` → allow all tools | Let dehydration complete |
| `statusline.sh` | lifecycle | `dehydrating` → skip sessionId write | Don't resurrect sessionId during teardown |

#### `overflowed` Readers

| Reader | Reads | Branches On | Purpose |
|--------|-------|------------|---------|
| `pre-tool-use-overflow.sh` | overflowed | `true` → block tools (except `/session dehydrate`) | Enforce overflow handling |
| `statusline.sh` | overflowed | `true` → skip sessionId write | Don't resurrect sessionId after overflow |
| `run.sh find_fleet_session()` | overflowed | `true` → **do not return sessionId** | Prevent resuming overflowed conversation |
| `run.sh` restart loop | overflowed | `true` → skip `--resume` | Fresh start required |

#### `killRequested` Readers

| Reader | Reads | Branches On | Purpose |
|--------|-------|------------|---------|
| Restart Watchdog (USR1) | — (signal-driven, does not read state) | USR1 received → process group kill | External kill |
| `statusline.sh` | killRequested | `true` → skip sessionId write | Don't resurrect sessionId during kill |
| `run.sh` restart loop | killRequested | `true` → skip `--resume` | Fresh start required |

### 3.4 Mapping — Old `status` → New Fields

For migration reference. The old single `status` field maps to these field combinations:

| Old `status` | `lifecycle` | `overflowed` | `killRequested` |
|-------------|------------|-------------|----------------|
| `active` | `active` | `false` | `false` |
| (new) | `completed` | `false` | `false` |
| `overflow` | `active` | `true` | `false` |
| `dehydrating` | `dehydrating` | `true` | `false` |
| `ready-to-kill` | `active`* | `true` | `true` |
| `restarting` | `restarting` | `true` | `false`** |
| `resuming` | `resuming` | `false`*** | `false` |

\* lifecycle stays `active` because Claude is still running until the watchdog kills it.
\** killRequested cleared by run.sh after reading the restart prompt.
\*** resuming implies fleet restart (no overflow). If fleet killed Claude mid-overflow, `overflowed` would be `true` — and `find_fleet_session()` would refuse to return sessionId. This is the bug the decomposition fixes.

### 3.5 Lifecycle Flow Diagram

```
                    ┌──────────────────────────────────────────────────────┐
                    │              STATE TRANSITIONS                        │
                    ├──────────────────────────────────────────────────────┤
                    │                                                      │
  session.sh        │    ┌────────────────────────────┐                    │
  activate ────────►│    │ lifecycle: active           │                    │
                    │    │ overflowed: false            │◄──────────┐       │
                    │    │ killRequested: false         │           │       │
                    │    └──────────┬─────────────────┘           │       │
                    │               │                              │       │
                    │               │ contextUsage >= 0.76         │       │
                    │               │ (overflow hook)              │       │
                    │               ▼                              │       │
                    │    ┌────────────────────────────┐           │       │
                    │    │ lifecycle: active           │           │       │
                    │    │ overflowed: TRUE            │           │       │
                    │    │ killRequested: false         │           │       │
                    │    │ [tools blocked]             │           │       │
                    │    └──────────┬─────────────────┘           │       │
                    │               │ /session dehydrate invoked    │       │
                    │               ▼                              │       │
                    │    ┌────────────────────────────┐           │       │
                    │    │ lifecycle: dehydrating      │           │       │
                    │    │ overflowed: true            │           │       │
                    │    │ killRequested: false         │           │       │
                    │    │ [tools allowed]             │           │       │
                    │    └──────────┬─────────────────┘           │       │
                    │               │ session.sh restart           │       │
                    │               ▼                              │       │
                    │    ┌────────────────────────────┐           │       │
                    │    │ lifecycle: active*          │           │       │
                    │    │ overflowed: true            │           │       │
                    │    │ killRequested: TRUE          │           │       │
                    │    │ * still active until killed  │           │       │
                    │    └──────────┬─────────────────┘           │       │
                    │               │ watchdog kills Claude        │       │
                    │               │ run.sh detects exit          │       │
                    │               ▼                              │       │
                    │    ┌────────────────────────────┐           │       │
                    │    │ lifecycle: restarting       │───────────┘       │
                    │    │ overflowed: true            │ session.sh        │
                    │    │ killRequested: false         │ activate          │
                    │    └────────────────────────────┘ (new Claude)      │
                    │                                                      │
                    │                                                      │
                    │  session.sh    ┌────────────────────────────┐       │
                    │  deactivate ──►│ lifecycle: completed        │       │
                    │  (after        │ overflowed: false           │       │
                    │   synthesis)   │ killRequested: false        │       │
                    │                │ [gate blocks non-whitelist] │       │
                    │                └──────────┬─────────────────┘       │
                    │                           │ session.sh activate     │
                    │                           │ (user picks new skill   │
                    │                           │  or continues)          │
                    │                           └─────────────►active     │
                    │                                                      │
                    │    ┌────────────────────────────┐                    │
  run.sh fleet  ───►│    │ lifecycle: resuming         │──► active         │
  resume            │    │ overflowed: false*          │  session.sh       │
                    │    │ killRequested: false         │  activate         │
                    │    │ * false=safe to resume       │                   │
                    │    │   true=DON'T resume          │                   │
                    │    └────────────────────────────┘                    │
                    │                                                      │
                    └──────────────────────────────────────────────────────┘
```

### 3.6 Transition Guards

- **active → lifecycle=completed**: Only `session.sh deactivate` sets this, called by skill protocols after synthesis
- **completed → lifecycle=active**: Only `session.sh activate` resets this, when user picks a new skill or continues
- **active → overflowed=true**: Only the overflow hook sets this, and only when `contextUsage >= 0.76`
- **overflowed → lifecycle=dehydrating**: Only when the Skill tool is called with `skill: "session"` (dehydrate subcommand)
- **dehydrating → killRequested=true**: Only `session.sh restart` sets this
- **killRequested → lifecycle=restarting**: Only `run.sh` post-exit loop sets this (after clearing killRequested)
- **restarting → active (overflowed=false)**: Only `session.sh activate` from the NEW Claude resets everything
- **resuming → active**: Only `session.sh activate` from the NEW Claude sets this
- **overflowed=true blocks --resume**: `find_fleet_session()` refuses to return sessionId. `run.sh` restart loop skips `--resume`. Two independent guards.

---

## 4. Session Scenarios

### S1: Normal Startup (Non-Fleet)

**Trigger**: User runs `claude` or `~/.claude/scripts/run.sh` outside fleet tmux.

```
User runs run.sh
  → fleet.sh pane-id returns empty (not in fleet)
  → run.sh starts watchdog (signal-driven co-process, waits for USR1)
  → run.sh exports WATCHDOG_PID to environment
  → run.sh starts Claude with no --resume (Claude inherits WATCHDOG_PID)
  → Claude invokes a skill (e.g., /implement)
  → Skill calls session.sh activate sessions/... implement
  → .state.json created: { pid, skill, lifecycle: "active", overflowed: false, killRequested: false }
  → statusline.sh starts binding sessionId on each render tick
  → Normal operation
```

**Identity**: PID only. No fleetPaneId. sessionId bound after first statusline tick.

**On exit**: run.sh kills watchdog, checks for restart request in `.state.json`. If none found, exits loop. Session `.state.json` becomes stale (PID dead).

### S2: Normal Startup (Fleet, No Previous Session)

**Trigger**: Fleet tmux started fresh, pane launches `run.sh`.

```
Fleet starts → tmuxinator creates panes → each pane runs run.sh
  → fleet.sh pane-id returns "yarik-fleet:company:SDK"
  → run.sh calls find_fleet_session("yarik-fleet:company:SDK")
  → No .state.json has matching fleetPaneId → returns empty
  → run.sh starts watchdog + Claude fresh (no --resume)
  → Claude invokes a skill
  → session.sh activate sets fleetPaneId in .state.json
  → Normal operation
```

**Identity**: PID + fleetPaneId. sessionId bound after first statusline tick.

### S3: Fleet Restart (Fleet Stop/Start Cycle)

**Trigger**: User runs `fleet.sh stop` then `fleet.sh start`. All Claude processes die. New Claudes spawn in same pane layout.

```
fleet.sh stop → all Claude processes killed → all PIDs become stale
fleet.sh start → tmuxinator recreates panes → each pane runs run.sh

run.sh (in pane "SDK"):
  → fleet.sh pane-id returns "yarik-fleet:company:SDK"
  → find_fleet_session("yarik-fleet:company:SDK"):
      → Scans sessions/*/.state.json for fleetPaneId match
      → Found: sessions/2026_02_07_MY_SESSION/.state.json
      → Check PID: old PID is dead (fleet killed it) ✓
      → Check overflowed: false ✓ (context was healthy when fleet stopped)
      → Reset: pid=0, lifecycle="resuming"
      → Return sessionId from .state.json
  → run.sh starts watchdog + Claude with --resume <sessionId>
  → Claude resumes previous conversation (full context restored by Claude Code)
  → Claude picks up where it left off (same context window)
```

**Key point**: This is a **conversation resume**, not a rehydration. Claude Code's `--resume` flag restores the full conversation history. The session `.state.json` is re-claimed by the new Claude via `session.sh activate`.

**Requires**: `sessionId` was written to `.state.json` by statusline before the fleet stopped. If sessionId is missing, resume fails and Claude starts fresh.

**Important**: Context is NOT overflowed in this case. The previous Claude was killed externally (fleet stop), not by overflow. So the conversation can be resumed as-is.

**Guard**: If `overflowed=true` (fleet killed Claude mid-overflow), `find_fleet_session()` does NOT return sessionId. Claude starts fresh with `/session continue` if a restartPrompt exists, or fully fresh otherwise.

### S4: Context Overflow Restart

**Trigger**: Context usage reaches 76% of Claude's reported percentage (≈95% of the 80% auto-compact threshold).

```
Normal operation, context growing...
  → statusline.sh writes contextUsage=0.77 to .state.json
  → Claude tries to use a tool
  → pre-tool-use-overflow.sh fires:
      → Reads contextUsage >= 0.76
      → Sets overflowed = true
      → BLOCKS tool with message: "CONTEXT OVERFLOW — run /session dehydrate restart"
  → Claude invokes Skill(skill: "session", args: "dehydrate restart")
  → Overflow hook detects session dehydrate → sets lifecycle = "dehydrating" → allows
  → /session dehydrate:
      1. Inventories session from memory (minimal I/O)
      2. Writes DEHYDRATED_CONTEXT.md to session dir
      3. Calls session.sh phase to save current phase
      4. Calls session.sh restart:
          → Sets killRequested = true
          → Writes restartPrompt = "/session continue --session ... --skill ... --phase ... --continue"
          → Resets contextUsage = 0
          → Deletes sessionId (prevents stale resume)
          → Sends kill -USR1 $WATCHDOG_PID (signals watchdog)
      5. Restart watchdog receives USR1:
          → Kills all children of run.sh except itself (process group kill)
          → Sends SIGTERM first, escalates to SIGKILL after 1s
      6. If no watchdog active (WATCHDOG_PID unset): prints warning + manual restart instructions
  → run.sh detects Claude exit, kills watchdog
  → run.sh finds .state.json with killRequested=true + restartPrompt
  → run.sh clears killRequested, restartPrompt; sets lifecycle = "restarting"
  → run.sh checks overflowed:
      → overflowed=true → SKIPS sessionId (fresh start, no --resume)
  → run.sh spawns new watchdog + Claude with restart prompt (NO --resume)
  → New Claude receives /session continue prompt
  → /session continue:
      1. Activates session (session.sh activate → lifecycle="active", overflowed=false, killRequested=false, new PID)
      2. Loads standards
      3. Reads DEHYDRATED_CONTEXT.md
      4. Loads required files
      5. Loads skill protocol
      6. Resumes at saved phase
```

**Key point**: This is a **fresh context start** with **rehydration**. The old conversation is NOT resumed because context was overflowed. Instead, `/session continue` reconstructs the working context from `DEHYDRATED_CONTEXT.md` + required files.

**sessionId handling**: `session.sh restart` deletes sessionId to prevent `run.sh` from using `--resume` on an overflow session. `run.sh` also double-checks: if `overflowed=true`, it skips sessionId even if present (defense in depth against R1).

### S5: Claude Crash/Exit (No Overflow, No Restart Request)

**Trigger**: Claude crashes, user exits with `/exit` or Ctrl+C, or Claude completes normally.

```
Claude exits (any reason)
  → run.sh detects exit, kills watchdog
  → Sleeps 0.5s (settle time)
  → find_restart_agent_json():
      → Scans sessions/*/.state.json for killRequested=true + restartPrompt
      → Scoped by PID: only matches .state.json whose pid was a child of this run.sh
      → Nothing found (no restart was requested)
  → run.sh breaks out of loop
  → "Goodbye."
```

**Result**: Session `.state.json` remains with stale PID. Next activation (any Claude) will detect dead PID and clean up.

**Fleet behavior**: If in fleet, `run.sh` exits, and tmuxinator does NOT auto-restart panes (by default). The pane shows the goodbye message. On next `fleet.sh start`, find_fleet_session will find the stale `.state.json`, detect dead PID, check `overflowed=false`, and offer resume.

### S6: run.sh Restart After Overflow (With vs Without sessionId)

**Subcase A — sessionId was deleted (correct flow)**:
```
session.sh restart deleted sessionId
  → run.sh reads .state.json: killRequested=true, overflowed=true, no sessionId
  → Spawns Claude WITHOUT --resume (fresh conversation)
  → Claude gets /session continue prompt, starts from scratch with rehydration
```

**Subcase B — sessionId present (race condition R1 occurred)**:
```
statusline.sh wrote sessionId AFTER session.sh restart deleted it
  → run.sh reads .state.json: killRequested=true, overflowed=true, sessionId present
  → run.sh guard: skips sessionId because overflowed=true
  → Spawns Claude WITHOUT --resume (correct behavior despite race)
```

### S7: Manual Session Continuation (Post-Synthesis)

**Trigger**: A skill completes its synthesis phase (debrief written), and the user sends another message.

```
Skill completes → debrief written → user sends new message
  → §CMD_CONTINUE_OR_CLOSE_SESSION fires:
      1. Detects debrief exists in session dir
      2. Reactivates session: session.sh activate
      3. Announces continuation
      4. Logs continuation header to _LOG.md
      5. Executes user's request
      6. When done, regenerates debrief
```

**No restart involved**. Same Claude, same context. Just re-registration of the session.

### S8: Skill Switching Within Same Session

**Trigger**: User finishes one skill and invokes another in the same session dir.

```
/implement completes in sessions/2026_02_07_MY_TOPIC/
  → User invokes /test
  → /test calls session.sh activate ... test
  → Same PID detected → updates skill field, resets lifecycle to "active"
  → New log file: TESTING_LOG.md (separate from IMPLEMENTATION_LOG.md)
  → Normal operation continues
```

**Key point**: Session directory stays the same. Each skill owns its own log file. `.state.json` updates `skill` and `currentPhase` fields.

### S9: Fleet Kill During Overflow (The Bug the Decomposition Fixes)

**Trigger**: Fleet stops while Claude is mid-overflow (context exhausted but dehydration not complete).

```
Claude is in overflow state (overflowed=true, tools blocked)
  → fleet.sh stop kills all Claude processes
  → .state.json frozen: { lifecycle: "active", overflowed: true, killRequested: false }
  → fleet.sh start → run.sh in same pane
  → find_fleet_session():
      → Finds .state.json with matching fleetPaneId
      → Check PID: dead ✓
      → Check overflowed: TRUE → do NOT return sessionId
      → Return empty (no resume possible)
  → run.sh checks for restartPrompt: none (dehydration didn't finish)
  → run.sh starts Claude FRESH (no --resume, no /session continue)
  → Claude starts with clean context, no session
  → Previous session's .state.json has overflowed=true, stale PID
  → On next session.sh activate (any session), old .state.json is cleaned up
```

**Without decomposition (old bug)**: `find_fleet_session()` would see `status="overflow"`, set it to `"resuming"`, and return sessionId. run.sh would `--resume` an overflowed conversation. Claude would immediately hit overflow again. Infinite restart loop.

### S10: Session Gate — No Active Session (SESSION_REQUIRED)

**Trigger**: Claude starts via `run.sh` (which exports `SESSION_REQUIRED=1`). Agent tries to use a non-whitelisted tool before activating a session.

```
run.sh exports SESSION_REQUIRED=1
  → Claude starts, receives user prompt
  → UserPromptSubmit hook fires (user-prompt-submit-session-gate.sh):
      → SESSION_REQUIRED=1 → session.sh find → no active session → injects boot message
      → Message: "Load standards, then ask user which skill to use"
  → Claude reads standards (whitelisted: Read ~/.claude/*)
  → Claude uses AskUserQuestion (whitelisted) to ask about skill
  → User picks /implement → Skill tool invoked (whitelisted)
  → /implement calls session.sh activate → lifecycle="active"
  → PreToolUse gate: session.sh find succeeds, lifecycle="active" → allow all tools
  → Normal operation
```

### S11: Session Gate — Completed Session Re-Engagement

**Trigger**: Skill completes synthesis, calls `session.sh deactivate`. User sends next message.

```
Skill synthesis complete → session.sh deactivate → lifecycle="completed"
  → User sends new message
  → UserPromptSubmit hook fires:
      → SESSION_REQUIRED=1 → session.sh find → session found, lifecycle="completed"
      → Injects: "Previous session X (skill: Y) is completed. Load standards, ask about continuation."
  → Claude reads standards (whitelisted)
  → Claude uses AskUserQuestion (whitelisted) to offer continuation
  → User picks "continue" or "new skill"
  → Skill invocation → session.sh activate → lifecycle="active"
  → Gate opens → normal operation
```

**Key point**: `lifecycle=completed` makes the gate re-engage WITHOUT destroying session state. The session directory, logs, and debrief all remain intact. A new `session.sh activate` transitions back to `active`.

---

## 5. Race Conditions

### R1: statusline Writes sessionId During Restart

**The race**:
```
T1: session.sh restart → deletes sessionId, sets killRequested=true
T2: statusline.sh tick → reads .state.json, writes sessionId back
T3: run.sh reads .state.json → sees sessionId (resurrected!)
```

**Mitigation (current)**:
- `statusline.sh update_session()` checks `killRequested` and `overflowed` before writing: if either is true, it skips sessionId write (only updates contextUsage + heartbeat)
- `run.sh` restart loop double-checks: if `overflowed=true`, it skips sessionId even if present

**Residual risk**: Low. Two independent guards (statusline skip + run.sh skip). Both would need to fail simultaneously.

### R2: session.sh phase Overwrites State During Restart

**The race**:
```
T1: Overflow hook sets overflowed=true
T2: Claude calls session.sh phase "Phase 3: Execution" (queued tool call)
    → phase command updates currentPhase + lastHeartbeat
    → BUT does NOT touch overflowed or killRequested (safe — phase only writes currentPhase)
```

**Analysis**: Not actually a race. `session.sh phase` only writes `currentPhase` and `lastHeartbeat` — it does not modify state fields. The original concern was about jq read-modify-write atomicity on the whole file, but since `phase` uses `jq '.currentPhase = $phase | .lastHeartbeat = $ts'`, it preserves all other fields.

**However**: If `phase` and `restart` execute simultaneously (separate shell processes), the jq read→write is not atomic. One could overwrite the other's changes.

**Mitigation (current)**: The overflow hook blocks tools before `session.sh restart` runs, so no new `session.sh phase` calls can happen after overflow is triggered. `/session dehydrate` runs phase BEFORE restart.

**Residual risk**: Very low. Tool blocking prevents concurrent phase/restart calls.

### R3: Fleet Pane Claiming During Restart Window

**The race**:
```
T1: Fleet stops → all Claudes die
T2: Fleet starts → new Claude in pane "SDK"
T3: run.sh find_fleet_session() → finds old .state.json with fleetPaneId
T4: run.sh sets pid=0, lifecycle="resuming"
T5: Claude starts, invokes skill → session.sh activate
T6: session.sh activate claims fleet pane (clears fleetPaneId from OTHER sessions)
```

**Potential issue**: Between T4 and T6, the `.state.json` has pid=0 and lifecycle="resuming". If ANOTHER process scans `.state.json` during this window, it sees a session with no active owner.

**Mitigation (current)**:
- `session.sh activate` fleet pane claiming (step T6) greps for matching fleetPaneId in OTHER sessions and clears them. This is idempotent.
- `statusline.sh` fleet lookup will claim the session (update PID) on first tick after activation.

**Residual risk**: Low. The window is sub-second and fleet panes are 1:1 with sessions.

### R4: Overflow Hook Fires After Dehydration Started

**The race**:
```
T1: Overflow hook blocks a tool, overflowed=true
T2: Claude invokes /session dehydrate, hook sets lifecycle="dehydrating", allows
T3: /session dehydrate runs, uses Read/Write/Bash tools
T4: Each tool triggers overflow hook again
T5: Hook reads lifecycle="dehydrating" → allows (correct)
```

**Analysis**: Not a race. The hook explicitly checks for `dehydrating` lifecycle and allows all tools in that state. The Bash whitelist also allows `log.sh` and `session.sh` unconditionally.

**Residual risk**: None. The lifecycle-based allowlist is checked before the threshold check.

### R5: Non-Atomic jq Read-Modify-Write

**The race**:
```
T1: statusline.sh reads .state.json → JSON in memory
T2: session.sh phase reads .state.json → JSON in memory
T3: statusline.sh writes .state.json (with sessionId update)
T4: session.sh phase writes .state.json (with phase update, but stale sessionId)
```

**Analysis**: All jq operations follow the pattern `jq '...' file > file.tmp && mv file.tmp file`. The `mv` is atomic on POSIX, but the read-modify-write sequence is not. Two concurrent writers can lose each other's changes.

**Mitigation (current)**: None explicitly. In practice, collisions are rare because:
- statusline runs on a render tick (every few seconds)
- session.sh phase is called by Claude (between tool calls)
- These rarely overlap within the same millisecond

**Residual risk**: Low but real. A file lock (`flock`) would eliminate this.

### R6: Fleet Pane ID Divergence

**The race**:
Two independent captures of `fleetPaneId` can return different values:

| Source | When Captured | Example Value |
|--------|-------------|---------------|
| `session.sh activate` (`.state.json`) | At session activation | `yarik-fleet:meta:Sessions` |
| `fleet.sh pane-id` (live, called by `session.sh find`) | At lookup time | `yarik-fleet:company:Future` |

This happens when pane labels change between activation and lookup, or when a process migrates between panes.

**Note**: The `FLEET_PANE_ID` env var was **removed** — `fleet.sh pane-id` is now called directly by `session.sh find` on each lookup. This eliminates one source of divergence (stale env var cache) but the activation-vs-live divergence remains.

**Impact**: `session.sh find` fleet strategy may not match the session if pane ID changed since activation. Falls through to PID strategy.

**Mitigation**: `session.sh find` uses PID as fallback. The restart watchdog uses PID exclusively (never pane ID). Fleet pane is useful for the common case but not relied upon as the sole discriminator.

**Residual risk**: Low for kill chain (watchdog uses PID). Low for session lookup (`session.sh find` falls through to PID match).

### R7: Watchdog vs Normal Exit Race

**The race**:
```
T1: Claude exits normally (user quits)
T2: Watchdog tries to kill Claude (stale PID) at the same instant
```

**Analysis**: `kill -TERM` on a dead PID simply fails (`No such process`). The watchdog handles this gracefully (`2>/dev/null`). No harm done.

**Edge case**: PID recycling — if the OS recycles the PID to an unrelated process between Claude's exit and the watchdog's kill. On macOS, PIDs cycle through ~99999 before recycling. The window is milliseconds. Risk is negligible.

**Mitigation**: Watchdog uses `kill -TERM ... 2>/dev/null`. run.sh kills the watchdog after Claude exits (`kill "$WATCHDOG"`), limiting the exposure window.

**Residual risk**: Negligible. PID recycling within the sub-second cleanup window is astronomically unlikely.

---

## 6. Component Responsibilities

### `run.sh` — Process Supervisor

**Owns**: The Claude process lifecycle. Spawn, restart loop, fleet resume, watchdog management.

| Responsibility | Details |
|---------------|---------|
| Start Claude | Builds args, adds `--append-system-prompt`, adds `--resume` if fleet session found |
| PID export | Exports `CLAUDE_SUPERVISOR_PID=$$` — the canonical process identity used by `session.sh` and `statusline.sh`. Eliminates PID disagreements between different spawn paths (Bash tools vs statusline have different `$PPID` values). |
| Restart watchdog | Spawns signal-driven watchdog before each Claude invocation. Exports `WATCHDOG_PID` env var. Watchdog waits for USR1, kills Claude via process group kill. Killed + waited by run.sh when Claude exits. |
| Fleet resume | Calls `find_fleet_session()` to find previous session by fleetPaneId. Checks `overflowed` — refuses `--resume` if true. |
| Restart loop | After Claude exits, checks for `killRequested=true` + `restartPrompt` in `.state.json` (scoped by PID) |
| Clean restart | Clears `killRequested`, `restartPrompt`; sets lifecycle to `restarting`; respawns Claude with prompt |
| Overflow guard | Skips `--resume` if `overflowed=true` (overflow restart = fresh context) |

### `session.sh` — State Manager

**Owns**: `.state.json` creation, field updates, restart preparation.

| Command | Responsibility |
|---------|---------------|
| `activate` | Create/update `.state.json`. Set PID (from `$CLAUDE_SUPERVISOR_PID` env, fallback `$PPID`), skill, fleetPaneId. Reset lifecycle to `active`, loading to `true`, overflowed to `false`, killRequested to `false`. Write logging enforcement defaults: `toolCallsSinceLastLog=0`, `toolUseWithoutLogsWarnAfter=3`, `toolUseWithoutLogsBlockAfter=10`. Claim fleet pane (clear from other sessions). |
| `find` | Locate the active session for the current Claude process. **Read-only** — no PID claiming, no writes. Two strategies: (1) fleet pane match via `fleet.sh pane-id`, (2) PID match via `$CLAUDE_SUPERVISOR_PID`/`$PPID`. Returns session dir path or exit 1. Used by `statusline.sh`, `pre-tool-use-overflow.sh`, `pre-tool-use-heartbeat.sh`. |
| `phase` | Update `currentPhase` + `lastHeartbeat`. Clear `loading` flag (deleted). Reset `toolCallsByTranscript` to `{}`. Notify fleet (working/unchecked). |
| `deactivate` | Set `lifecycle=completed` + `lastHeartbeat`. Store `sessionDescription` (from stdin) and `keywords` (from `--keywords` flag). Run `session-search.sh` RAG query with keywords, return related sessions in stdout. Notify fleet (unchecked). Session gate re-engages, blocking non-whitelisted tools. |
| `restart` | State-only — set `killRequested=true`, write `restartPrompt`, reset `contextUsage`, delete `sessionId`. Signals watchdog via `kill -USR1 $WATCHDOG_PID`. If `WATCHDOG_PID` absent: prints warning + manual restart instructions. |
| `update` | Generic field update. |

### `statusline.sh` — Session Binder + Display

**Owns**: Binding `sessionId` to `.state.json`. Updating `contextUsage`. Display formatting.
**Sources**: `~/.claude/scripts/lib.sh` (`timestamp`, `safe_json_write`)

| Responsibility | Details |
|---------------|---------|
| Session lookup | `session.sh find` (centralized — see §7 requirement 11) |
| sessionId binding | Writes Claude's `.session_id` to `.state.json` on every tick |
| State guard | Skips sessionId write when `killRequested=true` OR `overflowed=true` OR `lifecycle=dehydrating` |
| PID claiming | In fleet mode, updates `pid` in `.state.json` to current Claude's PID |
| Display | Formats `SESSION_NAME · skill/phase · agent · $cost · %` |

### Restart Watchdog (run.sh co-process)

**Owns**: Killing Claude when a restart is requested. External to Claude's process tree.

| Responsibility | Details |
|---------------|---------|
| Signal reception | Waits for USR1 signal from `session.sh restart` (via `WATCHDOG_PID` env var) |
| Kill mechanism | Process group kill: sends SIGTERM to all children of run.sh (`pgrep -P $$`) except itself (`$BASHPID`). Escalates to SIGKILL after 1s. |
| Communication | `session.sh restart` → `kill -USR1 $WATCHDOG_PID`. No filesystem monitoring. |
| Lifecycle | Spawned before each Claude invocation. `WATCHDOG_PID` exported to environment. Killed + waited by run.sh after Claude exits (any reason). |
| Fallback | If `WATCHDOG_PID` is not set (not running under run.sh), `session.sh restart` prints warning + manual restart instructions. No self-kill fallback. |

### `pre-tool-use-overflow.sh` — Context Guardian

**Owns**: Tool blocking at context overflow. Dehydration allowlisting.
**Sources**: `~/.claude/scripts/lib.sh` (`hook_allow`, `hook_deny`, `safe_json_write`)

| Responsibility | Details |
|---------------|---------|
| Session lookup | `session.sh find` (centralized — see §7 requirement 11) |
| Threshold check | Blocks tools when `contextUsage >= 0.76` |
| State transitions | Sets `overflowed=true` when threshold hit. Sets `lifecycle=dehydrating` when `/session dehydrate` invoked. |
| Allowlisting | Always allows `log.sh`, `session.sh` (Bash whitelist). Allows all tools when `lifecycle=dehydrating` or `killRequested=true`. |

### `pre-tool-use-heartbeat.sh` — Logging Discipline Enforcer

**Owns**: Tracking tool calls between log entries. Warning and blocking agents who don't log.

| Responsibility | Details |
|---------------|---------|
| Loading mode | If `loading=true` in `.state.json`, skip ALL heartbeat logic — pure passthrough (`allow_tool` immediately). Set by `session.sh activate` on every activation (fresh + re-activation). Cleared by `session.sh phase` (which also resets all counters). Prevents false violations during bootstrap/session-continue when agent loads standards, templates, and context files. |
| Session lookup | `session.sh find` (single source of truth) |
| Counter management | Per-transcript counters in `toolCallsByTranscript` map (keyed by `basename(transcript_path)`). Each agent instance (main + sub-agents) gets an isolated counter. Increments on each tool call. Resets to 0 when `log.sh` detected in Bash command. |
| Transcript isolation | `transcript_path` (from hook input JSON) uniquely identifies each agent instance. `basename()` extracts the key (e.g., `abc123.jsonl`). Sub-agent tool calls don't pollute the main agent's counter. |
| Whitelist | `log.sh` and `session.sh` Bash calls pass through without counting. `log.sh` additionally resets the calling transcript's counter. Read of `TEMPLATE_*_LOG.md` files passes through without counting. |
| Warn threshold | When counter >= `toolUseWithoutLogsWarnAfter` (default 3): allows tool but emits warning with resolved log file path, template path, and `log.sh` command |
| Block threshold | When counter >= `toolUseWithoutLogsBlockAfter` (default 10): denies tool with "LOGGING HEARTBEAT VIOLATION" message including template requirement |
| Configurability | Thresholds read from `.state.json` with jq `// default` fallbacks. Skills can override via `session.sh update`. |

### `pre-tool-use-session-gate.sh` — Session Activation Gate

**Owns**: Blocking non-whitelisted tools when no active session exists or session is completed.

| Responsibility | Details |
|---------------|---------|
| Gate check | `SESSION_REQUIRED != 1` → allow everything (gate disabled) |
| Whitelist | Read(`~/.claude/*`, `.claude/*`, `*/CLAUDE.md`, `*/MEMORY.md`), Bash(`session.sh`/`log.sh`/`tag.sh`/`glob.sh`), AskUserQuestion, Skill |
| Session check | `session.sh find` → lifecycle `active`/`dehydrating` → allow; `completed` → deny |
| Deny message | Instructs agent to use AskUserQuestion for skill/session selection. Includes completed session context if applicable. |

### `user-prompt-submit-session-gate.sh` — Proactive Boot Instructions

**Owns**: Injecting system messages that instruct the agent to load standards and select a skill/session.

| Responsibility | Details |
|---------------|---------|
| Gate check | `SESSION_REQUIRED != 1` → pass (no injection) |
| Active session | `session.sh find` → lifecycle `active`/`dehydrating` → pass (no injection needed) |
| No session | Injects: "Load standards, then ask user which skill to use" |
| Completed session | Injects: "Previous session X (skill: Y) is completed. Load standards, ask about continuation." |

### `/session dehydrate` Subcommand — Context Archiver

**Owns**: Writing `DEHYDRATED_CONTEXT.md`, triggering restart.

| Responsibility | Details |
|---------------|---------|
| Context inventory | Lists session files, recalls loaded context from memory |
| Dehydrated context | Writes structured handover to `DEHYDRATED_CONTEXT.md` |
| Phase save | Calls `session.sh phase` to record current phase before restart |
| Restart trigger | Calls `session.sh restart` which sets `killRequested=true`, prepares restart prompt, and signals watchdog via `kill -USR1 $WATCHDOG_PID`. |

### `/session continue` Subcommand — Context Restorer

**Owns**: Rebuilding working context from `DEHYDRATED_CONTEXT.md` after overflow restart.

| Responsibility | Details |
|---------------|---------|
| Session activation | Calls `session.sh activate` to register new Claude (resets overflowed=false, killRequested=false, sets new PID) |
| Standards loading | Reads COMMANDS.md, INVARIANTS.md |
| Context restoration | Reads DEHYDRATED_CONTEXT.md, extracts required files list |
| File loading | Reads all required files (session artifacts, skill templates, source code) |
| Phase resume | Skips to saved phase, logs restart entry |

---

## 7. Requirements / Invariants

### Hard Requirements

1. **One session per pane**: In fleet mode, each pane owns at most one active session. `session.sh activate` enforces this by clearing `fleetPaneId` from other sessions.

2. **One Claude per session**: A session cannot be shared by two running Claude processes. `session.sh activate` rejects if a different living PID owns the session.

3. **Overflow must dehydrate**: When the overflow hook fires, Claude MUST run `/session dehydrate restart`. No other tool is allowed (except logging/session scripts).

4. **Overflow must never resume**: An overflowed session MUST NOT be resumed via `--resume`. This is enforced by `overflowed=true` which is checked by:
    - `run.sh` restart loop — skips `--resume` when `overflowed=true`
    - `run.sh find_fleet_session()` — refuses to return sessionId when `overflowed=true`
    - `statusline.sh` — skips sessionId write when `overflowed=true`
    Three independent guards. The `overflowed` flag is sticky — only cleared by `session.sh activate` (proving fresh context).

5. **Fleet restart = conversation resume (if not overflowed)**: A fleet stop/start cycle tries `--resume` with the stored `sessionId`, but ONLY if `overflowed=false`. If the session was mid-overflow when fleet stopped, Claude starts fresh.

6. **State fields must flow forward**: State transitions follow the flow diagram. No component should set fields to an earlier state except `session.sh activate` (which resets everything as the "new lifecycle" entry point).

7. **sessionId must not survive overflow restart**: `session.sh restart` deletes `sessionId`. `run.sh` and `statusline.sh` guard against resurrection. This is defense-in-depth alongside the `overflowed` flag.

8. **PID identity comes from `CLAUDE_SUPERVISOR_PID` (run.sh's PID)**: Claude spawns child processes via different paths — Bash tools go through a subprocess manager, statusline is spawned directly. Their `$PPID` values differ. `run.sh` exports `CLAUDE_SUPERVISOR_PID=$$` early, and all consumers (`session.sh activate`, `statusline.sh find_session_dir`) read it. This eliminates PID disagreements without fragile process-tree walking.

9. **Watchdog is signal-driven, not filesystem-driven**: The restart watchdog receives USR1 from `session.sh restart` via `WATCHDOG_PID` env var. It kills Claude via process group kill (siblings of watchdog). No `.state.json` reading, no pane ID scoping, no PID matching. The signal IS the scope — only the session.sh that knows `WATCHDOG_PID` can trigger it.

10. **Logging enforcement uses per-transcript counters**: `pre-tool-use-heartbeat.sh` tracks tool calls between log entries via `toolCallsByTranscript` — a map keyed by `basename(transcript_path)` that isolates each agent instance's counter. Sub-agent tool calls don't inflate the main agent's counter. Warn at `toolUseWithoutLogsWarnAfter` (default 3), block at `toolUseWithoutLogsBlockAfter` (default 10). Thresholds are written to `.state.json` by `session.sh activate` and readable with jq fallbacks for backward compatibility. Counter is reset to 0 whenever `log.sh` is detected in a Bash tool call. Read of `TEMPLATE_*_LOG.md` files is whitelisted (no counting).

11. **Session lookup is centralized in `session.sh find`**: All components that need to find "which session am I in?" call `session.sh find` instead of implementing their own lookup. `session.sh find` is read-only (no PID claiming, no writes). Two strategies: fleet pane match, then PID match. Returns session dir path or exit 1.

12. **Session activation is mandatory (SESSION_REQUIRED gate)**: When `SESSION_REQUIRED=1` (set by `run.sh`), the `pre-tool-use-session-gate.sh` hook blocks all non-whitelisted tools until the agent activates a session via skill invocation. Whitelisted: Read(`~/.claude/*`, `.claude/*`, `*/CLAUDE.md`), Bash(`session.sh`/`log.sh`/`tag.sh`/`glob.sh`), AskUserQuestion, Skill. The `user-prompt-submit-session-gate.sh` hook proactively injects boot instructions. After synthesis, `session.sh deactivate` sets `lifecycle=completed`, re-engaging the gate for the next skill cycle.

13. **Loading mode bypasses heartbeat during bootstrap**: `session.sh activate` sets `loading=true` on every activation (fresh and re-activation). While `loading=true`, the heartbeat hook skips ALL logic — no counting, no warnings, no blocks (pure passthrough). `session.sh phase` clears the loading flag and resets all `toolCallsByTranscript` counters to `{}`, giving the work phase a clean slate. This prevents false heartbeat violations during bootstrap/session-continue when the agent loads standards, templates, dehydrated context, and skill files.

### Soft Requirements (Aspirational)

1. **Atomic state transitions**: Currently, jq read-modify-write is not atomic. A `flock`-based wrapper would eliminate R5.

2. **Explicit pane-session binding table**: Instead of scanning all `.state.json` files, a single index file mapping `fleetPaneId → session_dir` would make lookups O(1) and race-free.

---

## 8. `.state.json` Full Schema

```json
{
  "pid": 12345,
  "sessionId": "abc-123-def",
  "skill": "implement",
  "lifecycle": "active",
  "loading": true,
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0.72,
  "currentPhase": "Phase 3: Execution",
  "fleetPaneId": "yarik-fleet:company:SDK",
  "targetFile": "IMPLEMENTATION_LOG.md",
  "sessionDescription": "Implemented SESSION_REQUIRED gate hook that blocks tool use until session activation.\nAdded lifecycle=completed state for post-synthesis re-engagement.\nUpdated SESSION_LIFECYCLE.md with new state, scenarios, and component docs.",
  "keywords": "auth,middleware,ClerkAuthGuard,session-management,NestJS",
  "startedAt": "2026-02-07T14:30:00Z",
  "lastHeartbeat": "2026-02-07T15:45:00Z",
  "restartPrompt": "/session continue --session ... --skill ... --phase ...",
  "toolCallsSinceLastLog": 0,
  "toolCallsByTranscript": { "abc123.jsonl": 5, "agent-def456.jsonl": 3 },
  "toolUseWithoutLogsWarnAfter": 3,
  "toolUseWithoutLogsBlockAfter": 10
}
```

| Field | Type | Set By | Cleared By | Purpose |
|-------|------|--------|-----------|---------|
| `pid` | number | `session.sh activate` (from `$CLAUDE_SUPERVISOR_PID`), `statusline.sh` (claim) | `run.sh` (set to 0 on fleet resume) | Process identity (run.sh's PID, not Claude binary's) |
| `sessionId` | string | `statusline.sh` | `session.sh restart` (deleted) | Claude conversation ID for `--resume` |
| `skill` | string | `session.sh activate` | — | Current skill name |
| `lifecycle` | string | Various (see §3.2) | `session.sh activate` (reset to active) | Session lifecycle phase |
| `loading` | boolean | `session.sh activate` (→ true) | `session.sh phase` (deleted via `del(.loading)`) | Bootstrap mode flag — heartbeat hook skips ALL logic when true. Set on every activation, cleared on first phase transition. |
| `overflowed` | boolean | `pre-tool-use-overflow.sh` (→ true) | `session.sh activate` (→ false) | Sticky overflow flag, blocks `--resume` |
| `killRequested` | boolean | `session.sh restart` (→ true) | `session.sh activate` (→ false), `run.sh` (→ false) | Kill signal for watchdog |
| `contextUsage` | number | `statusline.sh` | `session.sh restart` (reset to 0) | Raw context % (0.0–1.0) |
| `currentPhase` | string | `session.sh phase` | — | Skill phase for status line + restart recovery |
| `fleetPaneId` | string | `session.sh activate` | `session.sh activate` (cleared from OTHER sessions) | Stable fleet identity |
| `targetFile` | string | `session.sh target` | — | Clickable file in status line |
| `sessionDescription` | string | `session.sh deactivate` (from stdin) | — | 1-3 line summary of session work for RAG/search discovery |
| `keywords` | string | `session.sh deactivate` (from `--keywords` flag) | — | Comma-separated search keywords for RAG discoverability |
| `startedAt` | string | `session.sh activate` | — | Session creation timestamp |
| `lastHeartbeat` | string | `statusline.sh`, `session.sh` | — | Last activity timestamp |
| `restartPrompt` | string | `session.sh restart` | `run.sh` (deleted after reading) | Command for new Claude on restart |
| `toolCallsSinceLastLog` | number | `pre-tool-use-heartbeat.sh` (increment), `log.sh` detection resets to 0 | `session.sh activate` (→ 0) | Legacy counter for logging enforcement (deprecated — see `toolCallsByTranscript`) |
| `toolCallsByTranscript` | object | `pre-tool-use-heartbeat.sh` (increment per transcript key), `log.sh` detection resets calling key to 0 | `session.sh activate` (not set — grows lazily) | Per-agent counters keyed by `basename(transcript_path)`. Isolates main agent from sub-agents. |
| `toolUseWithoutLogsWarnAfter` | number | `session.sh activate` (default 3) | — | Threshold: warn after N tool calls without logging |
| `toolUseWithoutLogsBlockAfter` | number | `session.sh activate` (default 10) | — | Threshold: block after N tool calls without logging |

---

## 9. Decision Tree: Which Restart Path?

```
Claude exits
  ├── Was killRequested=true in .state.json?
  │   ├── YES → Overflow Restart (S4/S6)
  │   │   ├── Is overflowed=true?
  │   │   │   ├── YES → Fresh start (no --resume). /session continue rebuilds context.
  │   │   │   └── NO → Should not happen (killRequested without overflow is unexpected).
  │   │   └── run.sh clears killRequested, sets lifecycle="restarting", spawns Claude
  │   └── NO → Normal exit (S5)
  │       └── run.sh exits loop. Goodbye.
  │
Claude starts (via run.sh, SESSION_REQUIRED=1)
  ├── Pre-session: gate blocks non-whitelisted tools
  │   ├── UPS hook injects boot instructions
  │   ├── Agent loads standards (whitelisted Read)
  │   ├── Agent asks user about skill (whitelisted AskUserQuestion)
  │   └── Skill invoked → session.sh activate → gate opens
  │
  ├── Post-synthesis: session.sh deactivate → lifecycle=completed
  │   ├── Gate re-engages (blocks non-whitelisted)
  │   ├── UPS hook injects continuation prompt
  │   └── Agent asks user → new skill/continuation → activate → gate opens
  │
  ├── Is fleet.sh pane-id non-empty? (in fleet tmux)
  │   ├── YES → Fleet mode
  │   │   ├── find_fleet_session() found a session?
  │   │   │   ├── YES, overflowed=false, sessionId present → --resume <sessionId> (S3)
  │   │   │   ├── YES, overflowed=true → Fresh start, no resume (S9)
  │   │   │   ├── YES, no sessionId → Fresh start in same session dir
  │   │   │   └── NO → Fresh start, new session (S2)
  │   │   └── Claude starts
  │   └── NO → Non-fleet mode
  │       └── Fresh start (S1)
```
