# Context Guardian System

Automatic context overflow protection for Claude Code sessions.

## Overview

When a Claude session approaches context limits (76% raw, ~95% of the 80% auto-compact window), the Context Guardian:

1. **Detects** — Status line tracks context usage via `.state.json`
2. **Blocks** — PreToolUse hook denies all tool calls at threshold (76% raw = 100% normalized)
3. **Forces Dehydration** — Claude must run `/session dehydrate restart`
4. **Restarts** — Fresh Claude spawns with session continuation prompt
5. **Rehydrates** — New Claude reads `DEHYDRATED_CONTEXT.md` and resumes

## Components

### `~/.claude/scripts/run.sh` — Process Supervisor

Wrapper that supervises Claude and handles restarts.

```bash
# Use instead of calling claude directly
~/.claude/scripts/run.sh

# Or alias it
alias claude='~/.claude/scripts/run.sh'
```

**Features:**
- Spawns Claude as child process
- Catches SIGUSR1 signal for restart
- Reads restart prompt from `.state.json`
- Auto-activates session after restart (sets correct PID)
- Maintains terminal control across restarts

### `~/.claude/scripts/session.sh` — Session Management

Manages session state in `.state.json`.

```bash
# Activate session
session.sh activate sessions/2026_02_05_MY_SESSION brainstorm

# PID detection: session.sh reads $CLAUDE_SUPERVISOR_PID (set by run.sh)
# Fallback: $PPID. No --pid flag needed.

# Update context usage
session.sh update sessions/2026_02_05_MY_SESSION contextUsage 0.85

# Trigger restart (signals run.sh)
session.sh restart sessions/2026_02_05_MY_SESSION
```

### `~/.claude/hooks/pre-tool-use-overflow.sh` — Overflow Hook

PreToolUse hook that blocks tools when context is nearly full.

**Behavior:**
- Reads `contextUsage` from `.state.json`
- Sources `~/.claude/engine/config.sh` for `OVERFLOW_THRESHOLD` (default: 0.76)
- Allows tools if < threshold
- Blocks all tools if >= threshold with message: "CONTEXT OVERFLOW — You MUST run `/session dehydrate restart` NOW" (no percentage shown — threshold is already 100% normalized)
- Sets sticky `overflowed=true` flag in `.state.json` on first deny
- Sources `~/.claude/scripts/lib.sh` for shared utilities (`hook_allow`, `hook_deny`, `safe_json_write`)

### `~/.claude/engine/tools/statusline.sh` — Status Line Display

Shows session info in Claude's status line.

**Output format:** `SESSION_NAME [skill/phase] XX%`

**Example:** `CONTEXT_OVERFLOW_PROTECTION [implement/build-loop] 72%`

**Normalization:** Raw context is normalized to display (0-100%) using `OVERFLOW_THRESHOLD` from `~/.claude/engine/config.sh`. So threshold raw (76%) = 100% display. This means the user sees 100% right when dehydration triggers.

**Session Binding:** Also writes `sessionId` from Claude's input to `.state.json`, enabling the overflow hook to match sessions reliably. Skips `sessionId` binding when `killRequested=true`, `overflowed=true`, or `lifecycle=dehydrating` (R1 race protection).

**Dependencies:** Sources `~/.claude/scripts/lib.sh` for shared utilities (`timestamp`, `safe_json_write`).

## Shared Library (`~/.claude/scripts/lib.sh`)

Shared utility functions sourced by session.sh, all 3 PreToolUse hooks, and statusline.sh. Extracted to eliminate duplication of jq write patterns, hook responses, and timestamp generation.

### Functions

| Function | Signature | Purpose |
|----------|-----------|---------|
| `safe_json_write` | `echo '...' \| safe_json_write FILE` | Reads JSON from stdin, validates with `jq empty`, writes atomically with mkdir-based locking (10s stale lock cleanup). Prevents concurrent `.state.json` corruption. |
| `hook_allow` | `hook_allow` | Outputs `{"result":"allow"}` JSON for PreToolUse hooks. |
| `hook_deny` | `hook_deny <reason> <guidance> <debug_info>` | Outputs `{"result":"deny","reason":...}` JSON for PreToolUse hooks. All 3 args required (pass `""` for empty debug). |
| `timestamp` | `timestamp` | Outputs UTC ISO 8601 timestamp (`date -u +"%Y-%m-%dT%H:%M:%SZ"`). |
| `pid_exists` | `pid_exists <pid>` | Returns exit 0 if PID is alive (`kill -0`), exit 1 otherwise. |
| `notify_fleet` | `notify_fleet STATE` | Sends fleet notification if running in fleet tmux. Parses TMUX socket name — only calls `fleet.sh notify` for sockets named "fleet" or "fleet-*". No-ops safely outside fleet. |
| `state_read` | `state_read FILE FIELD [DEFAULT]` | Reads a field from a JSON file via jq with fallback. Returns field value if found, DEFAULT if field missing or file unreadable, empty string if no default provided. |

### Usage

```bash
source "$HOME/.claude/scripts/lib.sh"

# Atomic state update (pipe JSON to stdin)
jq --arg ts "$(timestamp)" '.contextUsage = 0.85 | .lastHeartbeat = $ts' "$STATE_FILE" \
  | safe_json_write "$STATE_FILE"

# Hook responses
hook_allow
hook_deny "CONTEXT OVERFLOW" "You MUST run /session dehydrate restart NOW" ""

# Fleet notification (no-ops outside fleet tmux)
notify_fleet "working"

# Read state with fallback
skill=$(state_read "$STATE_FILE" "skill" "unknown")
```

### Consumers

- `~/.claude/scripts/session.sh` — `safe_json_write`, `timestamp`, `pid_exists`
- `~/.claude/hooks/pre-tool-use-heartbeat.sh` — `hook_allow`, `hook_deny`, `safe_json_write`
- `~/.claude/hooks/pre-tool-use-session-gate.sh` — `hook_allow`, `hook_deny`
- `~/.claude/hooks/pre-tool-use-overflow.sh` — `hook_allow`, `hook_deny`, `safe_json_write`
- `~/.claude/engine/tools/statusline.sh` — `timestamp`, `safe_json_write`

## Session Binding

The system uses two-stage binding to reliably track sessions across restarts:

```
┌────────────────────────────────────────────────────────────────────┐
│                     SESSION BINDING FLOW                           │
├────────────────────────────────────────────────────────────────────┤
│  1. session.sh activate                                            │
│     └── Creates .state.json with PID                               │
│                                                                    │
│  2. statusline.sh (runs on every render)                           │
│     ├── Finds session by PID match                                 │
│     ├── Writes sessionId from Claude's input                       │
│     └── Updates contextUsage + lastHeartbeat                       │
│                                                                    │
│  3. pre-tool-use-overflow.sh (runs before every tool)              │
│     ├── Primary: Match by sessionId                                │
│     └── Fallback: Match by PID (for new sessions)                  │
└────────────────────────────────────────────────────────────────────┘
```

**Why two identifiers?**
- `pid` is known at session activation time
- `sessionId` is Claude's internal identifier, only available via hook/statusline input
- Statusline binds them together; overflow hook can use either

## `.state.json` Schema

Located at `sessions/<session>/.state.json`:

```json
{
  "pid": 12345,
  "sessionId": "abc-123-def",
  "skill": "implement",
  "lifecycle": "active",
  "overflowed": false,
  "killRequested": false,
  "contextUsage": 0.72,
  "currentPhase": "Phase 5: Build Loop",
  "startedAt": "2026-02-05T14:30:00Z",
  "lastHeartbeat": "2026-02-05T15:45:00Z",
  "restartPrompt": "..."
}
```

### Field Details (Simplified)

| Field | Set By | Purpose |
|-------|--------|---------|
| `pid` | `session.sh activate` | Claude process ID (from `$CLAUDE_SUPERVISOR_PID`) |
| `sessionId` | `statusline.sh` | Claude's internal session ID for hook matching |
| `skill` | `session.sh activate` | Current skill being executed |
| `lifecycle` | Various | `active` → `dehydrating` → `restarting` → `resuming` / `completed` |
| `overflowed` | `pre-tool-use-overflow.sh` | Sticky flag — blocks `--resume` until fresh activation |
| `killRequested` | `session.sh restart` | Signal for restart watchdog |
| `contextUsage` | `statusline.sh` | Raw context percentage (0.0-1.0) |
| `currentPhase` | `session.sh phase` | Skill phase for resume after restart |
| `lastHeartbeat` | `statusline.sh` | Timestamp of last status update |
| `restartPrompt` | `session.sh restart` | Command for new Claude to run |

*Full schema with all fields: see `~/.claude/docs/SESSION_LIFECYCLE.md` §8.*

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Normal Operation                          │
├─────────────────────────────────────────────────────────────┤
│  run.sh spawns Claude                                        │
│       ↓                                                      │
│  Skill calls session.sh activate                             │
│       ↓                                                      │
│  Status line updates contextUsage in .state.json             │
│       ↓                                                      │
│  Context grows... 50%... 70%... 75%...                       │
└─────────────────────────────────────────────────────────────┘
                           ↓ (context hits threshold / 100% normalized)
┌─────────────────────────────────────────────────────────────┐
│                    Overflow Triggered                        │
├─────────────────────────────────────────────────────────────┤
│  PreToolUse hook blocks ALL tools                            │
│       ↓                                                      │
│  Claude forced to run /session dehydrate restart              │
│       ↓                                                      │
│  /session dehydrate writes DEHYDRATED_CONTEXT.md             │
│       ↓                                                      │
│  session.sh restart writes restartPrompt, sends SIGUSR1      │
│       ↓                                                      │
│  run.sh catches signal, kills Claude, reads .state.json      │
│       ↓                                                      │
│  run.sh spawns fresh Claude with restart prompt              │
│       ↓                                                      │
│  run.sh calls session.sh activate (PID from env)              │
│       ↓                                                      │
│  New Claude reads DEHYDRATED_CONTEXT.md, resumes work        │
└─────────────────────────────────────────────────────────────┘
```

## Setup

Run the engine setup script to install all components:

```bash
~/.claude/engine/engine.sh
```

This will:
- Link hooks to `~/.claude/hooks/`
- Link tools to `~/.claude/tools/`
- Configure `settings.json` with hooks and statusLine

## Troubleshooting

### Status line shows wrong session

**Cause:** Session wasn't activated after restart or continuation.

**Fix:** Run `session.sh activate <session_dir> <skill>` manually, or ensure `run.sh` wrapper is being used.

### Hook blocks but Claude doesn't dehydrate

**Cause:** Claude may be stuck or confused by the block message.

**Fix:** The hook message explicitly tells Claude to run `/session dehydrate restart`. If Claude ignores it, there may be a prompt issue.

### Restart doesn't preserve session

**Cause:** `DEHYDRATED_CONTEXT.md` wasn't written or doesn't contain proper handover.

**Fix:** Check `/session dehydrate` subcommand is correctly writing the file. The file must include session path and continuation instructions.

### Multiple agents cause collision

**Cause:** Old bug where `find_agent_json()` didn't filter by PID.

**Fix:** This was fixed — `run.sh` now matches `.state.json` by the killed Claude's PID, not just most recent.

## Related Files

- `~/.claude/docs/SESSION_LIFECYCLE.md` — **Comprehensive session lifecycle reference** (all restart/restore/rehydration scenarios, state machine, race conditions)
- `~/.claude/docs/DIRECTIVES_SYSTEM.md` — Behavioral specification system (commands, invariants, tags) that governs session behavior
- `~/.claude/engine/skills/session/SKILL.md` — Session skill (dehydration + continuation protocols)
- `~/.claude/engine/skills/session/references/continue-protocol.md` — Rehydration protocol (post-restart context restoration)
- `~/.claude/.directives/COMMANDS.md` — `§CMD_CONTINUE_OR_CLOSE_SESSION` for reactivation
- `sessions/<session>/DEHYDRATED_CONTEXT.md` — Session handover document
