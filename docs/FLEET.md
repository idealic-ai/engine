# Fleet System Documentation

The Fleet system manages multiple Claude Code agents in a tmux workspace with session persistence, context overflow recovery, and coordinated dispatch.

**Related**: `~/.claude/docs/SESSION_LIFECYCLE.md` (session state machine), `~/.claude/docs/CONTEXT_GUARDIAN.md` (overflow protection), `~/.claude/docs/DIRECTIVES_SYSTEM.md` (behavioral specification — commands, invariants, tags), `ORCHESTRATION.md` (multi-chapter project orchestration), `COORDINATE.md` (single-session coordinator mechanics)

## Overview

Fleet provides:
- **Multi-agent workspace**: Multiple Claude instances in tmux panes
- **Session persistence**: Resume Claude conversations after restart
- **Context overflow recovery**: Automatic dehydration and restart at 90% context
- **Coordinated dispatch**: Route work to agents via tags

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Fleet Architecture                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   tmux session (socket: fleet)                                              │
│   ┌─────────────┬─────────────┬─────────────┐                              │
│   │ Main        │ Research    │ SDK         │  ← pane labels               │
│   │             │             │             │                              │
│   │ Claude Code │ Claude Code │ Claude Code │  ← Claude instances          │
│   │             │             │             │                              │
│   │ .state.json │ .state.json │ .state.json │  ← workflow sessions         │
│   │ sessionId:  │ sessionId:  │ sessionId:  │  ← Claude session IDs        │
│   │ abc123...   │ def456...   │ ghi789...   │                              │
│   └─────────────┴─────────────┴─────────────┘                              │
│                                                                             │
│   statusline.sh ─────────────────────────────────────────────────────────  │
│   ↓ captures session_id from Claude, writes to .state.json                  │
│                                                                             │
│   overflow hook ─────────────────────────────────────────────────────────  │
│   ↓ at 90% context: dehydrate → kill → restart with --resume <sessionId>    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. tmux Sessions (Per-Workgroup Sockets)

Fleet uses dedicated tmux sockets to isolate from user's regular tmux. Each workgroup gets its own socket for full isolation:

```bash
# Socket naming convention:
# Default fleet:    socket "fleet"          → session "{user}-fleet"
# Workgroup fleet:  socket "fleet-{group}"  → session "{user}-{group}"

# Detection: any socket named "fleet" or "fleet-*" is a fleet socket
is_fleet_socket() { [[ "$1" == "fleet" || "$1" == fleet-* ]]; }
```

**Config**: `~/.claude/skills/fleet/assets/tmux.conf` (shared across all fleet sockets)
- Pane borders with labels (`pane-border-status top`)
- Disabled auto-rename (pane titles stay as configured)
- Standard Ctrl+b prefix
- run-shell hooks use bare `tmux` (no `-L` flag) to target the current server

### 2. Workflow Sessions (`.state.json`)

Each Claude instance is tied to a workflow session in `sessions/YYYY_MM_DD_TOPIC/`:

```json
{
  "pid": 12345,
  "skill": "implement",
  "currentPhase": "Phase 5: Build Loop",
  "status": "active",
  "contextUsage": 0.42,
  "lastHeartbeat": "2026-02-06T15:30:00Z",
  "sessionId": "c92ac34d-94a2-48b4-b3a5-87bbe1d0f5a9",
  "fleetPaneId": "Main"
}
```

**Key fields**:
- `pid`: Claude's process ID (for ownership tracking)
- `skill`: Current skill being executed
- `currentPhase`: Phase within the skill protocol
- `contextUsage`: 0.0-1.0 (raw from Claude, ~0.80 = 100% effective)
- `sessionId`: **Claude Code's internal session UUID** (for resume)
- `fleetPaneId`: **Fleet pane name** (for finding last session per pane)

### 3. Statusline Script

`~/.claude/tools/statusline.sh` is called by Claude Code to render the status line.

**Input** (JSON from Claude):
```json
{
  "context_window": {
    "used_percentage": 42.5,
    ...
  },
  "session_id": "c92ac34d-94a2-48b4-b3a5-87bbe1d0f5a9"
}
```

**Actions**:
1. Extracts `session_id` from Claude
2. Finds matching `.state.json` by PID
3. Updates `.state.json` with `contextUsage`, `lastHeartbeat`, `sessionId`
4. Returns formatted status: `TOPIC [skill/phase] 42%`

### 4. Context Overflow Hook

`~/.claude/hooks/pre-tool-use-overflow.sh` runs before each tool use.

**Flow**:
1. Reads `contextUsage` from `.state.json`
2. At 90%+ context:
   - Blocks the tool call
   - Triggers `/session dehydrate` → saves state to `DEHYDRATED_CONTEXT.md`
   - Triggers `engine session restart` → kills Claude, relaunches with recovery

## Session Persistence

### How Claude Session ID is Captured

1. Claude Code sends `session_id` to statusline on every render
2. `statusline.sh` writes it to `.state.json` as `sessionId`
3. This happens continuously during normal operation

### How Fleet Pane ID is Set

1. `engine session activate` auto-detects if running inside fleet tmux
2. Reads the `@pane_label` from tmux if socket is named "fleet"
3. Writes `fleetPaneId` to `.state.json` automatically
4. No manual `--fleet-pane` flag needed — detection is automatic

### Fleet Pane Resume Flow

When a fleet pane starts:

```bash
run.sh  # Auto-detects fleet pane from tmux @pane_label
```

1. `run.sh` auto-detects pane label if running in fleet tmux socket
2. Searches `sessions/*/.state.json` for matching `fleetPaneId`
3. Sorts by mtime (newest first)
4. Reads `sessionId` from the most recent match
5. Launches `claude --resume <sessionId>`

This allows fleet panes to automatically resume their last Claude conversation.

### How Resume Works

When restarting (context overflow or manual):

```bash
# Read Claude session ID from workflow session
SESSION_DIR="sessions/2026_02_06_MY_TOPIC"
CLAUDE_SESSION_ID=$(jq -r '.sessionId // empty' "$SESSION_DIR/.state.json")

# Resume the Claude conversation
if [ -n "$CLAUDE_SESSION_ID" ]; then
  claude --resume "$CLAUDE_SESSION_ID" "/session continue --session $SESSION_DIR --skill implement --phase 'Phase 5' --continue"
else
  claude "/session continue --session $SESSION_DIR --skill implement --phase 'Phase 5' --continue"
fi
```

**Key insight**: `--resume <uuid>` restores Claude's conversation history. `/session continue` restores the agent's workflow context (standards, templates, dehydrated state).

## Context Overflow Recovery

### The Problem
Claude Code has a ~200k token context window. At ~80% (160k), it auto-compacts. Beyond that, context degrades. We want to restart before quality suffers.

### The Solution

```
┌─────────────────────────────────────────────────────────────────┐
│  Context Overflow Flow                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Agent works normally...                                     │
│     ↓                                                           │
│  2. statusline.sh updates contextUsage: 0.42 → 0.85 → 0.91     │
│     ↓                                                           │
│  3. pre-tool-use-overflow.sh detects 90%+                      │
│     ↓                                                           │
│  4. BLOCK tool call (return error to Claude)                   │
│     ↓                                                           │
│  5. Claude sees "Context overflow - dehydrating..."             │
│     ↓                                                           │
│  6. /session dehydrate:                                         │
│     - Writes DEHYDRATED_CONTEXT.md (goal, state, next steps)   │
│     - Records current phase                                     │
│     ↓                                                           │
│  7. engine session restart:                                         │
│     - Reads sessionId from .state.json                          │
│     - Kills old Claude process                                  │
│     - Launches: claude --resume <sessionId> "/session continue" │
│     ↓                                                           │
│  8. New Claude starts with:                                     │
│     - Full conversation history (via --resume)                  │
│     - Restored workflow context (via /session continue)         │
│     - Picks up exactly where it left off                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Dehydrated Context

`DEHYDRATED_CONTEXT.md` captures:
- Ultimate goal and strategy
- Last action and outcome
- Required files list (for reloading)
- Next steps

The new Claude reads this to understand where it was.

## File Locations

### Engine Files (`~/.claude/`)

```
~/.claude/
├── scripts/
│   ├── fleet.sh              # Fleet CLI commands
│   ├── session.sh            # Session management (activate, restart, phase)
│   ├── user-info.sh          # User identity from Google Drive path
│   └── ...
├── tools/
│   └── statusline.sh         # Status line renderer (captures session_id)
├── hooks/
│   └── pre-tool-use-overflow.sh  # Context overflow detection
├── skills/
│   └── fleet/
│       ├── references/FLEET.md   # Skill protocol (interview)
│       └── assets/
│           └── tmux.conf         # Fleet tmux config
└── docs/
    └── FLEET.md              # This document
```

### Fleet Configs (Google Drive)

```
{gdrive}/{username}/assets/fleet/
├── {username}-fleet.yml        # Default fleet (socket: fleet)
├── {username}-project.yml      # Project workgroup (socket: fleet-project)
├── {username}-domain.yml       # Domain workgroup (socket: fleet-domain)
└── ...                         # Each config → its own tmux socket
```

Each config's `tmux_command` specifies its socket: `tmux -L fleet-{workgroup} -f tmux.conf`

### Workflow Sessions (Project)

```
{project}/sessions/
└── 2026_02_06_MY_TOPIC/
    ├── .state.json           # Session state (pid, skill, phase, sessionId)
    ├── IMPLEMENTATION_LOG.md # Work log
    ├── IMPLEMENTATION.md     # Debrief
    ├── DETAILS.md            # Q&A record
    └── DEHYDRATED_CONTEXT.md # Overflow recovery state
```

## Commands

### fleet.sh

```bash
fleet.sh start [workgroup]    # Start fleet on socket "fleet" or "fleet-{workgroup}"
fleet.sh stop [workgroup]     # Stop fleet (scoped to workgroup's socket)
fleet.sh status               # Show all configs with running/stopped status
fleet.sh list                 # List configs with ●/○ indicators
fleet.sh attach [session]     # Attach to fleet (auto-detects socket)
fleet.sh wait                 # Reserved slot mode (press 'a' to activate)
fleet.sh activate [name]      # Activate a reserved slot
fleet.sh config-path [group]  # Output path to fleet yml config
fleet.sh pane-id              # Output composite pane ID (session:window:label)
```

### Coordination

Commands used by the `/coordinate` skill. See `COORDINATE.md` for full decision engine details and `ORCHESTRATION.md` for multi-chapter orchestration.

```bash
# Core loop primitive — blocks until a pane needs attention
fleet.sh coordinate-wait [timeout_seconds]              # Auto-discovers managed panes from @pane_manages
fleet.sh coordinate-wait [timeout_seconds] --panes ID1,ID2  # Explicit pane list

# Lifecycle (internal to coordinate-wait — callers should NOT use directly)
fleet.sh coordinator-connect <pane_id>      # Set @pane_coordinator_active=1, apply purple bg
fleet.sh coordinator-disconnect <pane_id>   # Clear @pane_coordinator_active, revert bg

# Pane capture
fleet.sh capture-pane <pane_id>             # Structured JSON: question, options, preamble, terminal content
```

**coordinate-wait v2 behavior**: Each call auto-disconnects the previous pane, sweeps for actionable panes (skip focused, skip already-managed), picks highest priority (`error` > `unchecked` > `done`), auto-connects the selected pane (purple bg), captures content, and returns. Callers never call `coordinator-connect`/`coordinator-disconnect` directly (`§INV_COORDINATE_WAIT_LIFECYCLE`).

**Return values**:

*   **Normal** — `pane_id|state|label|location` on line 1, capture JSON on line 2+
*   **`TIMEOUT`** — No actionable panes within timeout. Second line: `STATUS total=N working=N done=N idle=N`
*   **`FOCUSED`** — All actionable panes are user-focused. Second line: `STATUS total=N working=N done=N focused=N`

### session.sh

```bash
engine session activate <dir> <skill> --pid "$PPID"  # Register Claude with session (auto-detects fleet pane)
engine session phase <dir> "Phase N: Name"           # Update current phase
engine session deactivate <dir>                      # Mark session completed
engine session restart <dir>                         # Kill and relaunch Claude
```

### run.sh

```bash
run.sh                   # Plain Claude (auto-detects fleet pane if in fleet tmux)
run.sh --agent operator  # With agent persona
```

## Notification States

Fleet panes and window tabs use color-coded backgrounds to indicate agent state. The notification system helps you spot which agents need attention at a glance.

### State Colors

| State     | Meaning              | Foreground | Background (tint) | Selected Tab |
|-----------|----------------------|------------|-------------------|--------------|
| **error** | Agent hit an error   | #f38ba8    | #3d2020 (red)     | #802020      |
| **unchecked** | Needs attention  | #70e0a0    | #081a10 (mint)    | #208050      |
| **working** | Agent is busy      | #5080b0    | #080c10 (blue)    | #204060      |
| **checked** | Seen/acknowledged  | #506850    | #0a1005 (sage)    | #304020      |
| **done** | Idle, no status      | #505050    | #0a0a0a (gray)    | #303030      |

### Visual Hierarchy

- **Unchecked (mint green)**: Bright, demands attention — agent finished work you haven't reviewed
- **Checked (sage green)**: Dim, acknowledged — you've seen the output, no action needed
- **Working (blue)**: Neutral, in progress — agent is actively processing
- **Error (red)**: Alert, problem — agent encountered an issue requiring intervention

### State Transitions

```
working → unchecked    # Agent completes a task (fleet.sh notify unchecked)
unchecked → checked    # User focuses the pane (auto-transition via focus hook)
checked → working      # Agent starts new work (fleet.sh notify working)
* → error              # Agent encounters an error (fleet.sh notify error)
* → done               # Clear notification state (fleet.sh notify done)
```

### Coordinator Layer

The coordinator adds two orthogonal state dimensions on top of the notify state. Together with notify, they form a three-dimensional state model (see `COORDINATE.md` §3 for the full interaction matrix).

*   **`@pane_coordinator_active`** — Set to `1` when `coordinate-wait` auto-connects a pane (purple bg applied). Cleared on the next `coordinate-wait` call (auto-disconnect) or on focus override. Callers never set this directly.
*   **`@pane_user_focused`** — Set to `1` by the `pane-focus-in` tmux hook when the user focuses a pane. Cleared on `pane-focus-out`. `coordinate-wait` skips focused panes — the user has priority.

**Purple visual**: When `@pane_coordinator_active = 1`, the pane background turns dark purple (`#1a0a2e`), indicating the coordinator is actively processing it. Reverts to the notify-state color on disconnect.

**Focus override**: If the user focuses a pane the coordinator is processing (`coordinator_active=1` AND `user_focused=1`), the coordinator aborts, disconnects, sets notify back to `unchecked`, and yields.

### Commands

```bash
fleet.sh notify <state>       # Set pane notification state
fleet.sh notify-check <pane>  # Transition unchecked→checked (focus hook)
fleet.sh notify-clear         # Clear to done state
```

### Configuration

Colors are defined in:
- `~/.claude/skills/fleet/assets/tmux.conf` — Window tabs, pane borders, init script
- `~/.claude/engine/scripts/fleet.sh` — Runtime notify command
- `~/.claude/hooks/pane-focus-style.sh` — Focus hook tints

## Pane Labels

Fleet panes show labels in the tmux border:

```
┌─ Main ──────────────────────────────────────────────────────────┐
│                                                                 │
│  Claude Code session...                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**For non-operator agents**, the label includes the agent type:
```
┌─ Research (analyzer) ───────────────────────────────────────────┐
```

**Set dynamically**:
```bash
tmux -L fleet set-option -p @pane_label "MyLabel"
```

## Reserved Slots (Placeholders)

Placeholder panes show a dim "Reserved slot" message and wait for activation:

```
      ⏸  Reserved Slot

      Press 'a' to activate
```

**Activation flow**:
1. Press `a` in the pane
2. `fleet.sh activate` launches Claude with `/fleet activate` skill
3. Claude interviews to configure the slot
4. Updates pane label and optionally the yml config

## Integration Points

### With Workflow Engine

- `session.sh` manages workflow sessions (skill tracking, phase updates)
- `.state.json` is the bridge between workflow state and Claude session ID
- `statusline.sh` continuously syncs Claude's session ID to workflow state

### With Dispatch Daemon

The dispatch daemon (if running) routes tagged work to fleet workers:

```bash
# Tag appears in a session artifact
#needs-implementation

# Daemon detects, routes to worker with matching accepts list
# Worker claims work by swapping: #needs-implementation → #claimed-implementation
```

### With /session continue

On context overflow restart:
1. `engine session restart` invokes `/session continue`
2. `/session continue` loads standards, dehydrated context, skill protocol
3. Resumes at saved phase without repeating earlier work

## Invariants

- **Session ID binding**: `sessionId` in `.state.json` must match the running Claude's session
- **PID ownership**: Only the Claude with matching PID owns the `.state.json`
- **Fleet socket naming**: Default fleet uses `fleet` socket; workgroups use `fleet-{name}` sockets. Detection via `is_fleet_socket()`: `fleet` or `fleet-*`
- **Socket isolation**: Each fleet config runs on its own tmux socket for full process isolation
- **Config loading**: `tmux source-file` in `on_project_start` ensures config applies

## Troubleshooting

### Pane labels not showing
```bash
# Verify config loaded
tmux -L fleet show-option -g pane-border-status
# Should show: pane-border-status top

# If "off", source config manually:
tmux -L fleet source-file ~/.claude/skills/fleet/assets/tmux.conf
```

### Session not resuming
```bash
# Check if sessionId exists
jq '.sessionId' sessions/*/. agent.json

# Verify Claude session exists
ls -la ~/.claude/projects/-*/$(jq -r '.sessionId' sessions/2026_02_06_MY_TOPIC/.state.json).jsonl
```

### Context not being tracked
```bash
# Check statusline is configured
cat ~/.claude/settings.json | jq '.statusLine'

# Verify .state.json is being updated
watch -n1 'jq . sessions/2026_02_06_MY_TOPIC/.state.json'
```
