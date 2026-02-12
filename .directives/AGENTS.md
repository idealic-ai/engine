# Workflow Engine

The workflow engine is a structured skill-and-session system layered on top of Claude Code. It provides session lifecycle management, directive-based context injection, tag-driven delegation, and multi-agent coordination.

## Key Subsystems

| Subsystem | Entry Point | What It Does |
|-----------|-------------|-------------|
| **Sessions** | `engine session` | Activate/deactivate sessions, phase tracking, heartbeat, context overflow recovery |
| **Logging** | `engine log` | Append-only session logs with auto-timestamps |
| **Tags** | `engine tag` | Tag lifecycle management — add, remove, swap, find across session artifacts |
| **Discovery** | `engine discover-directives` | Walk-up search for `.directives/` files from touched directories to project root |
| **Search** | `engine session-search`, `engine doc-search` | Semantic search over past sessions and documentation (RAG) |
| **Hooks** | PreToolUse/PostToolUse | Heartbeat enforcement, directive gate, context overflow protection, details logging |
| **Skills** | `~/.claude/skills/*/SKILL.md` | Structured protocols (implement, analyze, fix, test, brainstorm, etc.) |

## The Directive System

Agent-facing context files in `.directives/` subfolders at any level of the project hierarchy. This is the primary mechanism for feeding context to agents.

**8 directive types** (3 tiers):
- **Core** (always discovered): `AGENTS.md`, `INVARIANTS.md`, `ARCHITECTURE.md`
- **Hard gate** (blocks deactivation): `CHECKLIST.md`
- **Skill-filtered** (loaded when skill declares them): `TESTING.md`, `PITFALLS.md`, `CONTRIBUTING.md`, `TEMPLATE.md`

**Inheritance**: Directives stack cumulatively child-to-root. Package directives extend project directives extend engine directives — never shadow.

**Discovery**: `discover-directives.sh` walks up from touched directories. PostToolUse hook tracks touched dirs and warns about pending directives. PreToolUse hook blocks after threshold if unread.

**End-of-session management**: `§CMD_MANAGE_DIRECTIVES` runs 3 passes — AGENTS.md updates (auto-mention new directives), invariant capture, pitfall capture.

**Templates**: Scaffolding for new directive files lives in `~/.claude/engine/.directives/templates/TEMPLATE_*.md` (one per type).

## Do Not Use Claude Code's Built-in Memory Feature

Use `.directives/` files instead of Claude Code's built-in memory feature (`/memory`, `MEMORY.md`). The directive system is structured, discoverable by the engine, and version-controlled. The memory feature stores unstructured notes in `~/.claude/projects/*/memory/MEMORY.md` — this file should remain empty.

## Core Standards (The "Big Three")

Loaded at every session boot — these define the engine's fundamental operations:
- `COMMANDS.md` — All `§CMD_` command definitions (file ops, process control, workflows)
- `INVARIANTS.md` — Shared `¶INV_` rules (testing, architecture, code, communication, engine physics)
- `TAGS.md` — Tag lifecycle (`§FEED_`), escaping, operations, dispatch routing
