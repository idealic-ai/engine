# Dispatch Daemon (DEPRECATED)

> **Deprecated**: This standalone daemon has been superseded by `run.sh --monitor-tags` (daemon mode built into the Claude process supervisor). See `~/.claude/docs/DAEMON.md` for the current 4-state tag dispatch system.
>
> The standalone `dispatch-daemon.sh` script in this directory is no longer the recommended approach. Use `run.sh --monitor-tags '#delegated-implementation,#delegated-chores'` instead.

Automatic tag processor that watches `sessions/` for `#delegated-*` tags and spawns Claude agents to handle them.

## Quick Start

```bash
# Start the daemon (in project directory)
cd ~/Projects/myproject
~/.claude/tools/dispatch-daemon/dispatch-daemon.sh start

# Check status
~/.claude/tools/dispatch-daemon/dispatch-daemon.sh status

# Stop the daemon
~/.claude/tools/dispatch-daemon/dispatch-daemon.sh stop
```

## How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Dispatch Daemon                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. WATCH                 2. DETECT              3. ROUTE            │
│  ┌──────────┐            ┌──────────┐           ┌──────────┐        │
│  │ fswatch  │ ──event──> │ grep for │ ─#needs─> │ parse    │        │
│  │ sessions/│            │ #needs-* │           │ TAGS.md  │        │
│  └──────────┘            └──────────┘           └────┬─────┘        │
│                                                      │               │
│  4. CLAIM                 5. SPAWN                   │               │
│  ┌──────────┐            ┌──────────┐               │               │
│  │ tag.sh   │ <─────────┤ run.sh   │ <─skill────────┘               │
│  │ swap     │            │ /skill   │                                │
│  │ needs->  │            │ $FILE    │                                │
│  │ active   │            └──────────┘                                │
│  └──────────┘                │                                       │
│                              │                                       │
│  6. OBSERVE                  ▼                                       │
│  ┌──────────────────────────────────────────┐                       │
│  │ tmux session: dispatch                    │                       │
│  │ ├── agent-research-1707235200            │                       │
│  │ ├── agent-implement-1707235201           │                       │
│  │ └── agent-decide-1707235202              │                       │
│  └──────────────────────────────────────────┘                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Usage

### Starting the Daemon

```bash
# Start in current directory (must have sessions/ subdirectory)
dispatch-daemon.sh start

# Start for a specific project
dispatch-daemon.sh start --project ~/Projects/finch
```

The daemon will:
1. Scan existing files in `sessions/` for `#needs-*` tags
2. Spawn agents for any found tags
3. Watch for new/modified files
4. Continue processing until stopped

### Observing Agents

```bash
# List all running agent windows
tmux list-windows -t dispatch

# Attach to watch an agent live
tmux attach -t dispatch:agent-implement-1707235200

# Detach from tmux: Ctrl+B, then D
```

### Checking Status

```bash
dispatch-daemon.sh status
# Daemon is running (PID: 12345)
# Log: /tmp/dispatch-daemon.log
#
# Recent log entries:
# [2026-02-06 14:30:00] Detected #delegated-research in sessions/.../REQUEST.md
# [2026-02-06 14:30:00] Spawning /delegation-claim for batch dispatch
```

### Stopping the Daemon

```bash
dispatch-daemon.sh stop
# [2026-02-06 15:00:00] Stopping daemon (PID: 12345)...
# [2026-02-06 15:00:00] Daemon stopped.
```

**Note**: Stopping the daemon does NOT kill running agents. They continue in their tmux windows.

## Tag Routing

> **Note**: The current system watches `#delegated-*` tags (not `#needs-*`). See `¶INV_NEEDS_IS_STAGING`.

The daemon reads the `§TAG_DISPATCH` table from `~/.claude/directives/TAGS.md`:

| Tag | Skill | Notes |
|-----|-------|-------|
| `#delegated-brainstorm` | `/brainstorm` | Exploration and trade-off analysis |
| `#delegated-research` | `/research` | Gemini Deep Research |
| `#delegated-implementation` | `/implement` | Code implementation |
| `#delegated-chores` | `/chores` | Small self-contained tasks |
| `#delegated-documentation` | `/document` | Documentation pass |

To add new tag types, create a `TEMPLATE_*_REQUEST.md` in the skill's `assets/` directory (dynamic discovery).

## Coordination

### Tag Lifecycle

```
#needs-X → #delegated-X → #claimed-X → #done-X
```

The 4-state lifecycle requires human approval (`/delegation-review`) to transition `#needs-X` → `#delegated-X`. The daemon watches only `#delegated-X` tags. Workers claim via `/delegation-claim` (`#delegated-X` → `#claimed-X`) before starting work.

### Debouncing

The daemon ignores rapid-fire events on the same file (2-second window). This prevents duplicate spawns from editor save events.

### Parallelism

The daemon spawns agents in parallel — one per detected tag. There is no concurrency limit. System resources are the natural limit.

## Files

```
~/.claude/tools/dispatch-daemon/
├── dispatch-daemon.sh   # The daemon script
└── README.md            # This file

/tmp/
├── dispatch-daemon.pid  # PID file (daemon tracking)
└── dispatch-daemon.log  # Log file
```

## Dependencies

- **fswatch**: File system watcher. Install: `brew install fswatch`
- **tmux**: Terminal multiplexer. Install: `brew install tmux`
- **~/.claude/scripts/run.sh**: Claude process wrapper
- **~/.claude/scripts/tag.sh**: Tag operations

## Invariants

### ¶INV_DAEMON_STATELESS

The daemon MUST NOT maintain state beyond what tags encode.

- No database of running agents
- No tracking of completed work
- Tags ARE the state: `#active-X` means "claimed"

If the daemon crashes and restarts, it re-reads tags and continues correctly.

### ¶INV_CLAIM_BEFORE_WORK

A worker MUST swap `#delegated-X` → `#claimed-X` before starting work.

The `/delegation-claim` skill handles this via `tag.sh swap`. The swap errors (exit 1) if the old tag is already gone — race condition safety.

## Troubleshooting

### "fswatch not found"

```bash
brew install fswatch
```

### "tmux not found"

```bash
brew install tmux
```

### "Daemon already running"

```bash
# Check if actually running
dispatch-daemon.sh status

# If stale PID file, remove it
rm /tmp/dispatch-daemon.pid
```

### Agent spawned but did nothing

Check the agent's tmux window:
```bash
tmux attach -t dispatch:agent-implement-...
```

The agent may have errored. Check `~/.claude/scripts/run.sh` requirements.

### Tags not being detected

1. Verify the tag is on the `**Tags**:` line (not just in body text)
2. Verify the tag is bare, not backtick-escaped
3. Verify the tag has a routing entry in `§TAG_DISPATCH`
4. Check the log: `tail -f /tmp/dispatch-daemon.log`

## See Also

- `~/.claude/directives/HANDOFF.md` — Full coordination reference
- `~/.claude/directives/TAGS.md` — Tag system and routing
- `~/.claude/directives/COMMANDS.md` — `§CMD_*` primitives
