# Workflow Engine

A structured skill system for Claude Code that turns AI-assisted development into a repeatable, auditable process. Distributed via Google Drive and symlinked into each project.

## Quick Start

```bash
# From your project root:
~/Library/CloudStorage/GoogleDrive-you@company.com/Shared\ drives/finch-os/engine/engine.sh

# Or if engine is local:
~/.claude/engine/engine.sh myproject
```

Setup creates symlinks from `~/.claude/` to the engine, creates session/report directories on Google Drive, and configures Claude Code permissions and hooks.

## The Happy Path

Most features follow this workflow. Each step is a separate Claude Code session with its own log and debrief — the output of one step feeds directly into the next.

1. **Analyze** (`/analyze`) — Understand the terrain. Read code, docs, patterns. Produce a research report.
2. **Brainstorm** (`/brainstorm`) — Explore the problem space. Socratic dialogue. Challenge assumptions. Converge on decisions.
3. **Document** (`/document`) — Write the docs BEFORE the code. The docs become the spec.
4. **Implement** (`/implement`) — Build it. TDD. Plan, red, green, refactor. Every decision recorded.
5. **Test** (`/test`) — Verify it. Edge cases, regressions, integration. Fill coverage gaps.
6. **Evangelize** (`/evangelize`) — Sell the work. Frame it for stakeholders.
7. **Review** (`/review`) — End-of-day review. Approve or reject debriefs. Cross-session conflict detection.
8. **Report** (`/summarize-progress`) — Progress summary. What shipped, what's pending, what's blocked.

Not every feature needs all 8 steps. The point is that each skill slots into a known position — you always know what comes next.

### Session Handoff

Any step can end with `/dehydrate`, which serializes the session state and copies it to your clipboard. Paste into the next command to resume: `/implement <paste>`. Works across machines and team members.

## Architecture

The engine has seven layers, from low-level utilities to user-facing commands:

```
Layer 7: Skills        /analyze, /implement, /debug, ...    (user-invoked protocols)
Layer 6: Agents        builder, debugger, analyzer, ...     (sub-agent personas)
Layer 5: Commands      find-sessions, details, fleet, ...   (light utility commands)
Layer 4: Directives    COMMANDS.md, INVARIANTS.md, TAGS.md  (rules and templates)
Layer 3: Tools         statusline.sh, dispatch-daemon       (background services)
Layer 2: Hooks         overflow, notifications, gating      (Claude Code lifecycle)
Layer 1: Scripts       session.sh, tag.sh, log.sh, ...      (shell utilities)
```

### Key Infrastructure

| Component | Purpose |
|-----------|---------|
| `session.sh` | Session lifecycle: activate, phase tracking, deactivate, restart |
| `run.sh` | Claude process supervisor with restart loop and agent loading |
| `fleet.sh` | Multi-agent tmux workspace management |
| `worker.sh` | Fleet worker daemon — watches for tagged work, spawns agents |
| `statusline.sh` | Status line: session name, skill/phase, context usage % |
| `pre-tool-use-overflow.sh` | Context overflow protection — blocks tools at threshold, forces `/dehydrate` |
| `dispatch-daemon.sh` | Watches `sessions/` for `#needs-*` tags, auto-spawns agents |

## Skills, Tags & Sessions

The engine includes 30+ skills organized into core workflow (`/analyze`, `/implement`, `/debug`, `/test`, `/document`, `/brainstorm`, `/refine`), session management (`/chores`, `/review`, `/dehydrate`), cross-session communication (`/research`, `/delegate`), and engine management (`/edit-skill`, `/fleet`).

Cross-session coordination uses semantic tags with a lifecycle: `#needs-X` → `#active-X` → `#done-X`. Sessions are directories (`sessions/YYYY_MM_DD_TOPIC/`) containing logs, plans, debriefs, and `.state.json`.

**See [docs/WORKFLOW.md](docs/WORKFLOW.md)** for the full user guide — skill reference, tag system, session lifecycle, skill chaining, fleet coordination, context overflow protection, and standards discipline.

## Distribution Model

The engine lives as a git repo on a Google Drive Shared Drive. Two modes:

| Mode | Engine Location | Use Case |
|------|----------------|----------|
| **remote** | Google Drive `Shared drives/finch-os/engine/` | Default — shared across team |
| **local** | `~/.claude/engine/` (git clone) | Development — edit engine locally, sync separately |

`engine.sh` creates per-item symlinks so project-specific overrides can coexist with shared engine files. Skills and agents use per-directory/per-file symlinks; local overrides take priority.

## Directory Structure

```
engine/
├── agents/                  # Sub-agent personas (11 .md files)
├── commands/                # Light utility commands (flat .md files)
├── docs/                    # Engine-specific docs (INVARIANTS.md)
├── hooks/                   # Claude Code lifecycle hooks (13 .sh files)
├── scripts/                 # Shell utilities (17 scripts + tests/)
├── skills/                  # Skill protocols (30 directories)
│   └── <skill-name>/
│       ├── SKILL.md         # Entry point (frontmatter + protocol)
│       └── assets/          # Templates (TEMPLATE_*.md)
├── directives/              # Shared authority files (behavioral directives)
│   ├── COMMANDS.md          # Command index (all §CMD_* references)
│   ├── INVARIANTS.md        # System invariants (¶INV_*)
│   ├── TAGS.md              # Tag system reference (§FEED_*)
│   ├── HANDOFF.md           # Agent coordination reference
│   └── commands/            # Reusable command definitions
├── tools/                   # Background services
│   ├── statusline.sh        # Status line display
│   └── dispatch-daemon/     # Automatic tag processor
├── config.sh                # Central config (overflow threshold)
├── engine.sh                 # One-time project setup
├── .mode                    # "local" or "remote"
├── .user.json               # Cached user identity
├── .migrations              # Applied migration state
└── README.md                # This file
```

## Further Reading

- **[DEVELOPMENT.md](DEVELOPMENT.md)** — How to add skills, agents, hooks, scripts. Architecture details, testing, migrations.
- **[AGENTS.md](AGENTS.md)** — Full agent reference: all 11 agents, when to use each, how they're loaded.
- **[directives/COMMANDS.md](directives/COMMANDS.md)** — All `§CMD_*` protocol building blocks.
- **[directives/INVARIANTS.md](directives/INVARIANTS.md)** — System invariants (`¶INV_*`).
- **[directives/TAGS.md](directives/TAGS.md)** — Tag system and lifecycle feeds.
- **[directives/HANDOFF.md](directives/HANDOFF.md)** — Inter-agent coordination patterns.
- **[scripts/README.md](scripts/README.md)** — Script reference with usage examples.
- **[tools/dispatch-daemon/README.md](tools/dispatch-daemon/README.md)** — Automatic tag processor.
