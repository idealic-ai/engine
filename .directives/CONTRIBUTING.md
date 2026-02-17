# Development Guide

How to extend and maintain the workflow engine.

## Adding a New Skill

Skills are user-invoked via `/skill-name`. Each skill lives in `skills/<name>/` with a protocol and templates.

### Structure

```
skills/<skill-name>/
├── SKILL.md                    # Protocol (frontmatter + phases)
└── assets/
    ├── TEMPLATE_<TYPE>.md      # Debrief template
    ├── TEMPLATE_<TYPE>_LOG.md  # Log template
    └── TEMPLATE_<TYPE>_PLAN.md # Plan template (optional)
```

### SKILL.md Frontmatter

Every `SKILL.md` starts with YAML frontmatter that Claude Code reads:

```yaml
---
description: Short description shown in skill discovery
---
```

### Naming Conventions

- **Skill folder**
  Convention: verb, kebab-case
  Example: `analyze`, `implement`, `delegate`

- **Templates**
  Convention: `TEMPLATE_` + noun, UPPER_SNAKE
  Example: `TEMPLATE_ANALYSIS.md`, `TEMPLATE_ANALYSIS_LOG.md`

- **Light commands**
  Convention: verb, kebab-case flat file
  Example: `commands/find-sessions.md`

- **Agents**
  Convention: role noun, lowercase
  Example: `agents/builder.md`, `agents/debugger.md`

- **Hooks**
  Convention: event-description, kebab-case
  Example: `hooks/pre-tool-use-overflow.sh`

- **Scripts**
  Convention: tool name, kebab-case
  Example: `scripts/session.sh`, `scripts/tag.sh`

### Skill Protocol Phases

Skills follow a phased protocol. Common phases:

1. **Setup** — Load standards, parse parameters, activate session
2. **Context Ingestion** — Load project files, RAG context
3. **Interrogation/Research** — Gather information, ask questions
4. **Planning** — Create a plan (for implementation/testing skills)
5. **Execution** — Do the work
6. **Synthesis** — Write debrief, report artifacts, prompt next skill

Phase transitions are mechanically enforced via `engine session phase`. Non-sequential transitions require `--user-approved`.

### Required Protocol Elements

Every skill protocol MUST include:

- **Boot sequence**: Load `COMMANDS.md`, `INVARIANTS.md`, `SIGILS.md`, project `INVARIANTS.md`
- **`§CMD_PARSE_PARAMETERS`**: Activate session with JSON params
- **`§CMD_INGEST_CONTEXT_BEFORE_WORK`**: Context menu in Phase 2
- **`§CMD_GENERATE_DEBRIEF`**: Synthesis output
- **`§CMD_CLOSE_SESSION`**: Session deactivation to idle state
- **`§CMD_PRESENT_NEXT_STEPS`**: Post-synthesis routing menu
- **Mode presets** (for multi-mode skills): Role, goal, mindset, research topics, calibration topics
- **`§CMD_REPORT_INTENT`**: Phase transition intent blockquote
- **Walk-through config**: For finding triage in Phase 5b
- **`phases` array**: Declared at activation for enforcement

### Quick Scaffolding

Use `/edit-skill <name>` to scaffold a new skill with all the boilerplate. Use `/share-skill` to promote a project-local skill to the shared engine.

## Adding a New Agent

Agents are sub-agent personas loaded via `engine run --agent <name>` or used as `subagent_type` in the Task tool.

### Structure

Each agent is a single markdown file in `agents/`:

```markdown
---
name: myagent
description: What this agent does
model: opus
---

# Agent Name (The Role Title)

You are a **Senior [Role]** doing [what].

## Your Contract
...

## Execution Loop
...

## Boundaries
...
```

### Frontmatter Fields

- **`name`**
  **Required**: Yes
  **Values**: lowercase
  **Purpose**: Agent identifier

- **`description`**
  **Required**: Yes
  **Values**: string
  **Purpose**: Shown in Task tool agent selection

- **`model`**
  **Required**: No
  **Values**: `opus`, `sonnet`, `haiku`
  **Purpose**: Model preference

### How Agents Are Loaded

1. **Via `engine run --agent <name>`**: Agent content is appended to Claude's system prompt. Full toolset preserved.
2. **Via Task tool `subagent_type`**: Claude Code natively supports agents defined in `~/.claude/agents/`. The frontmatter `name` maps to `subagent_type`.

See [agents/README.md](agents/README.md) for the full agent reference.

## Adding a Hook

Hooks integrate with Claude Code's lifecycle events. Each hook is a shell script in `hooks/`.

### Available Hook Events

- **`PreToolUse`**
  When: Before any tool call
  Use case: Context overflow protection, heartbeat enforcement, directive gate

- **`PostToolUse`**
  When: After successful tool call
  Use case: Details logging, phase command preloading, template injection

- **`Notification`**
  When: Permission prompt, idle, elicitation
  Use case: Fleet attention notifications

- **`UserPromptSubmit`**
  When: User sends a message
  Use case: Session gate, state injection, fleet working state

- **`SessionStart`**
  When: Claude process starts
  Use case: Standards injection, dehydration context restore

- **`SubagentStart`**
  When: Sub-agent (Task tool) starts
  Use case: Session context injection into sub-agents

- **`PreCompact`**
  When: Before context compaction
  Use case: Trigger dehydration restart instead of lossy compaction

- **`Stop`**
  When: Agent stops
  Use case: Fleet done notification

- **`SessionEnd`**
  When: Session ends
  Use case: Fleet cleanup

### Hook Protocol

Hooks receive JSON on stdin. For PreToolUse hooks, output determines behavior:

```bash
# Allow the tool call (exit 0, empty or JSON output)
hook_allow    # from lib.sh

# Block the tool call (exit 0 with JSON deny message)
hook_deny "title" "message" "detail"    # from lib.sh
```

### Current Hooks (16)

**Guard hooks** (PreToolUse — block/allow tool calls):

- **`pre-tool-use-overflow-v2.sh`**
  Event: PreToolUse
  Purpose: Context overflow protection — blocks tools at threshold, forces dehydration

- **`pre-tool-use-one-strike.sh`**
  Event: PreToolUse
  Purpose: Combined heartbeat enforcement + directive gate — warns then blocks

**Context injection hooks** (inject content into agent context):

- **`session-start-restore.sh`**
  Event: SessionStart
  Purpose: Standards injection (COMMANDS.md, INVARIANTS.md, SIGILS.md), dehydration context restore, directive preload

- **`post-tool-use-phase-commands.sh`**
  Event: PostToolUse
  Purpose: Preloads CMD files referenced in current phase steps

- **`post-tool-use-details-log.sh`**
  Event: PostToolUse
  Purpose: Auto-logs AskUserQuestion interactions to DIALOGUE.md

- **`post-tool-use-templates.sh`**
  Event: PostToolUse
  Purpose: Convention-based skill template preloading on Skill invocation

- **`user-prompt-state-injector.sh`**
  Event: UserPromptSubmit
  Purpose: Injects session state, phase info, heartbeat counters into context

- **`user-prompt-submit-session-gate.sh`**
  Event: UserPromptSubmit
  Purpose: Session gate enforcement — blocks tools without active session

- **`subagent-start-context.sh`**
  Event: SubagentStart
  Purpose: Injects session context (log template, directives) into sub-agents

**Fleet notification hooks** (tmux pane state management):

- **`notification-attention.sh`**
  Event: Notification
  Purpose: Sends "unchecked" (orange) fleet state on permission prompts

- **`notification-idle.sh`**
  Event: Notification
  Purpose: Sends "idle" fleet state

- **`user-prompt-working.sh`**
  Event: UserPromptSubmit
  Purpose: Sends "working" fleet state

- **`stop-notify.sh`**
  Event: Stop
  Purpose: Sends "done" fleet state

- **`session-end-notify.sh`**
  Event: SessionEnd
  Purpose: Fleet cleanup

**Lifecycle hooks**:

- **`pre-compact-kill.sh`**
  Event: PreCompact
  Purpose: Triggers dehydration restart instead of lossy context compaction

- **`pane-focus-style.sh`**
  Event: tmux after-select-pane
  Purpose: Pane visual state management (focus/unfocus colors)

### Registering Hooks

Hooks are registered in `~/.claude/settings.json` by `engine setup`. Per-hook symlinks allow local overrides.

## Adding a Script

Scripts are shell utilities in `scripts/`. They're symlinked to `~/.claude/scripts/` and auto-whitelisted with `Bash(~/.claude/scripts/*)`.

### Shared Library (`lib.sh`)

All scripts source `~/.claude/scripts/lib.sh` which provides:

- `timestamp` — ISO timestamp
- `pid_exists <pid>` — Check if PID is alive
- `safe_json_write <file>` — Atomic JSON write (stdin pipe)
- `state_read <file> <key> <default>` — Read from `.state.json`
- `hook_allow` / `hook_deny` — Hook response helpers
- `notify_fleet <state>` — Fleet notification (no-op outside tmux)

### Key Scripts

- **`session.sh`** — Session lifecycle (activate, phase, deactivate, restart, find)
- **`run.sh`** — Claude process supervisor with restart loop
- **`fleet.sh`** — Fleet tmux management (start, stop, status, pane-id)
- **`worker.sh`** — Fleet worker daemon
- **`log.sh`** — Append-only file writing with timestamp injection
- **`tag.sh`** — Tag management (add, remove, swap, find)
- **`find-sessions.sh`** — Session discovery by date, topic, tag
- **`glob.sh`** — Symlink-aware file globbing
- **`research.sh`** — Gemini Deep Research API wrapper
- **`config.sh`** — User-level config management
- **`write.sh`** — Clipboard writer (used by `/session dehydrate`)
- **`account-switch.sh`** — Claude account credential rotation (save, switch, rotate, list, status, remove)
- **`escape-tags.sh`** — Retroactive tag escaping
- **`user-info.sh`** — User identity from GDrive path
- **`engine.sh`** — Project setup (called by engine `engine.sh`)
- **`setup-lib.sh`** — Pure setup functions (testable)
- **`setup-migrations.sh`** — Numbered idempotent migrations

## Setup System

### How Setup Works

`engine/engine.sh` is the entry point. It:

1. Infers user identity from the GDrive mount path
2. Creates `sessions/` and `reports/` directories on GDrive
3. Creates symlinks from `~/.claude/` to engine directories
4. Links individual skills, agents, hooks (per-file for override support)
5. Creates project `.claude/.directives/INVARIANTS.md` stub
6. Updates `.gitignore`
7. Configures `~/.claude/settings.json` (permissions, hooks, statusline)
8. Runs pending migrations

### Symlink Strategy

- **`commands/`**
  Strategy: Whole-dir symlink
  Override support: No

- **`.directives/`**
  Strategy: Whole-dir symlink
  Override support: No

- **`agents/`**
  Strategy: Whole-dir symlink
  Override support: No

- **`scripts/`**
  Strategy: Per-file symlinks
  Override support: Yes — add local file

- **`hooks/`**
  Strategy: Per-file symlinks
  Override support: Yes — add local file

- **`skills/`**
  Strategy: Per-skill dir symlinks
  Override support: Yes — add local skill dir

- **`tools/`**
  Strategy: Whole-dir symlink
  Override support: No

### Modes

- **remote**
  Engine location: Google Drive Shared Drive
  `.mode` file: absent or `remote`

- **local**
  Engine location: `~/.claude/engine/`
  `.mode` file: `local`

Local mode is for engine development. The engine is a git repo at `~/.claude/engine/` with its own `.git/`.

### Migrations

Numbered idempotent migrations in `setup-migrations.sh`. State tracked in `.migrations`.

```bash
# Migration format
MIGRATIONS=(
  "001:perfile_scripts_hooks"    # Whole-dir → per-file symlinks
  "002:perfile_skills"           # Whole-dir → per-skill symlinks
  "003:state_json_rename"        # .agent.json → .state.json
)
```

To add a migration:
1. Add entry to `MIGRATIONS` array
2. Write `migration_NNN_name()` function
3. Add tests in `tests/test-setup-migrations.sh`

## Testing

### Script Tests

Tests live in `scripts/tests/`. Run all tests:

```bash
bash ~/.claude/engine/scripts/tests/run-all.sh
```

Individual test files:

- **`test-session-sh.sh`** — Session lifecycle, activation, phase enforcement
- **`test-tag-sh.sh`** — Tag add/remove/swap/find operations
- **`test-log-sh.sh`** — Append-only logging, timestamp injection
- **`test-glob-sh.sh`** — Symlink-aware globbing
- **`test-config-sh.sh`** — Config get/set/list
- **`test-setup-lib.sh`** — Setup library functions
- **`test-setup-migrations.sh`** — Migration runner and idempotency
- **`test-phase-enforcement.sh`** — Phase transition rules
- **`test-overflow.sh`** — Context overflow detection
- **`test-session-gate.sh`** — Session gate hook
- **`test-statusline.sh`** — Status line output
- **`test-run-sh.sh`** — Process supervisor lifecycle
- **`test-run-lifecycle.sh`** — Run/restart loop
- **`test-heartbeat.sh`** — Heartbeat monitoring
- **`test-threshold.sh`** — Overflow threshold
- **`test-prompt-gate.sh`** — Prompt gating
- **`test-tmux.sh`** — Tmux integration
- **`test-user-info-sh.sh`** — User identity detection
- **`test-find-sessions-sh.sh`** — Session discovery
- **`test-completed-skills.sh`** — Skill completion tracking

### Test Safety

Tests MUST use sandbox isolation (`§INV_TEST_SANDBOX_ISOLATION`):
- Export `PROJECT_ROOT` to a temp directory
- Override `HOME` to isolate `~/.claude/` writes
- Never touch the real project root or Google Drive

## Shared Commands (§CMD_*)

Protocol building blocks that skills call during their phases. Unlike skills (user-invoked), shared commands are agent-invoked.

### Inline Commands (in COMMANDS.md)

Core commands defined directly in `.directives/COMMANDS.md`:

- **`§CMD_PARSE_PARAMETERS`** — Parse session params, activate session
- **`§CMD_MAINTAIN_SESSION_DIR`** — Session directory management
- **`§CMD_UPDATE_PHASE`** — Phase tracking and enforcement
- **`§CMD_REPORT_INTENT`** — Phase transition announcements
- **`§CMD_APPEND_LOG`** — Append-only log writing
- **`§CMD_WRITE_FROM_TEMPLATE`** — Template instantiation
- **`§CMD_GENERATE_DEBRIEF`** — Full synthesis pipeline
- **`§CMD_CLOSE_SESSION`** — Session deactivation to idle state
- **`§CMD_INGEST_CONTEXT_BEFORE_WORK`** — Context ingestion menu
- **`§CMD_INTERROGATE`** — Ask/log loop
- **`§CMD_RESUME_AFTER_CLOSE`** — Post-synthesis continuation
- **`§CMD_RESUME_SESSION`** — Resume after overflow or manual restart

### External Commands (in .directives/commands/)

Complex commands with their own reference files:

- **`§CMD_HANDOFF_TO_AGENT`**
  File: `CMD_HANDOFF_TO_AGENT.md`
  Purpose: Synchronous sub-agent launch

- **`§CMD_PARALLEL_HANDOFF`**
  File: `CMD_PARALLEL_HANDOFF.md`
  Purpose: Multi-agent parallel execution

- **`§CMD_WALK_THROUGH_RESULTS`**
  File: `CMD_WALK_THROUGH_RESULTS.md`
  Purpose: Finding triage / plan review

- **`§CMD_CAPTURE_KNOWLEDGE`**
  File: `CMD_CAPTURE_KNOWLEDGE.md`
  Purpose: Parameterized knowledge capture loop (invariants, pitfalls)

- **`§CMD_CAPTURE_SIDE_DISCOVERIES`**
  File: `CMD_CAPTURE_SIDE_DISCOVERIES.md`
  Purpose: Side-discovery tagging

- **`§CMD_REPORT_LEFTOVER_WORK`**
  File: `CMD_REPORT_LEFTOVER_WORK.md`
  Purpose: Unfinished work report

- **`§CMD_RESOLVE_CROSS_SESSION_TAGS`**
  File: `CMD_RESOLVE_CROSS_SESSION_TAGS.md`
  Purpose: Cross-session tag resolution

- **`§CMD_MANAGE_BACKLINKS`**
  File: `CMD_MANAGE_BACKLINKS.md`
  Purpose: Cross-document link management

- **`§CMD_AWAIT_TAG`**
  File: `CMD_AWAIT_TAG.md`
  Purpose: Async tag watcher

- **`§CMD_RESUME_SESSION`**
  File: `CMD_RESUME_SESSION.md`
  Purpose: Resume after overflow or manual restart

- **`§CMD_PRESENT_NEXT_STEPS`**
  File: `CMD_PRESENT_NEXT_STEPS.md`
  Purpose: Post-synthesis routing menu

- **`§CMD_DECISION_TREE`**
  File: `CMD_DECISION_TREE.md`
  Purpose: Declarative decision tree collector

- **`§CMD_TAG_TRIAGE`**
  File: `CMD_TAG_TRIAGE.md`
  Purpose: Tag-based item triage

## Fleet System

The fleet is a tmux-based multi-agent workspace.

### Components

- **`fleet.sh`** — Manages tmux sessions with fleet configs from GDrive
- **`worker.sh`** — Daemon process that watches for tagged work and spawns Claude agents
- **`dispatch-daemon.sh`** — Legacy standalone daemon (deprecated)
- **`/fleet` skill** — Interactive fleet designer

### Fleet Configs

Stored in GDrive: `{gdrive}/{username}/assets/fleet/`. Define tmux layouts with panes, projects, and agent assignments.

### Worker Lifecycle

```
register → #idle → #has-work → #working → (complete) → rescan → #idle
```

Workers accept specific tag types (e.g., `#needs-implementation,#needs-brainstorm`) and only process matching work.

## Configuration

### Engine Config (`config.sh`)

Central constants sourced by scripts and hooks:

```bash
OVERFLOW_THRESHOLD=0.76    # Context overflow trigger (0.0-1.0)
```

### User Config (`scripts/config.sh`)

```bash
engine config get terminalLinkProtocol    # cursor://file (default)
engine config set terminalLinkProtocol vscode://file
engine config list                         # Show all config
```

### Identity (`.user.json`)

Cached user identity, auto-detected from GDrive path:

```json
{"username":"yarik","email":"yarik@finchclaims.com","domain":"finchclaims.com","source":"cached"}
```

## Code Standards & Development Philosophy

Rules for writing code. These apply across all code-writing skills (implement, fix, test).

### Testing

*   **¶INV_HEADLESS_LOGIC**: Business logic MUST be testable without the framework.
    *   **Rule**: Core domain logic (calculations, state transitions) should be pure functions or classes that don't import framework specifics.
    *   **Reason**: Tests run in milliseconds, not seconds.

*   **¶INV_ISOLATED_STATE**: Tests MUST NOT share mutable state.
    *   **Rule**: Each test case starts with a fresh mock/database transaction/workflow ID.
    *   **Reason**: Flaky tests destroy developer confidence.

### Architecture

*   **¶INV_SPEC_FIRST**: Complex logic MUST be specified before implementation.
    *   **Requirement**: Major system components require a written Spec derived from the standard template.
    *   **Rule**: Do not write the code until the Spec (Context, Sequence Diagram, Failure Analysis) is written and reviewed.
    *   **Reason**: It is 10x cheaper to fix a design flaw in Markdown than in code.

*   **¶INV_ATOMIC_TASKS**: Units of work should do ONE thing well.
    *   **Bad**: `processAndEmailAndBill()`
    *   **Good**: `calculateBill()`, `chargeCard()`, `sendReceiptEmail()`
    *   **Reason**: Granular tasks allow for targeted retries and better observability.

### Code Hygiene

*   **¶INV_NO_DEAD_CODE**: Delete it, don't comment it out.
    *   **Rule**: Git is your history. The codebase is the current state.
    *   **Reason**: Commented code rots and confuses readers.

*   **¶INV_NO_LEGACY_CODE**: No Legacy Code.
    *   **Rule**: Migrate immediately, clean up, update tests. Don't leave legacy codepaths.
    *   **Reason**: Legacy code increases technical debt and complexity.

*   **¶INV_ENV_CONFIG**: Configuration comes from Environment Variables.
    *   **Rule**: No hardcoded secrets or API keys in code.
    *   **Reason**: Security and portability across environments (Dev/Stage/Prod).

### Philosophy

*   **¶INV_DATA_LAYER_FIRST**: Fix problems at the data layer, not the view.
    *   **Rule**: If a problem can be solved by correcting the schema or upstream data, do that instead of adding view-layer patches or transformer workarounds.
    *   **Rule**: Single source of truth — generate/derive from canonical data, don't duplicate.
    *   **Reason**: View-layer patches accumulate as tech debt and hide the real problem.

*   **¶INV_EXPLICIT_OVER_IMPLICIT**: Prefer explicit configuration over implicit inference.
    *   **Rule**: Caching invalidation, feature flags, and state transitions should use explicit signals (override maps, checksums), not automatic hash-based derivation.
    *   **Rule**: When code and documentation diverge, update documentation to match working code — code is reality.
    *   **Reason**: Implicit behavior is hard to debug and leads to "magic" that breaks unexpectedly.

*   **¶INV_DX_OVER_PERF**: Optimize for developer velocity when performance is acceptable.
    *   **Rule**: If a solution is marginally slower but significantly easier to debug/iterate on, choose it.
    *   **Rule**: Local-first tools (CLI, scripts) over server dependencies where possible.
    *   **Reason**: Developer time is the bottleneck, not CPU time.

*   **¶INV_COMPREHENSIVE_FOUNDATION**: Build foundational systems comprehensively.
    *   **Rule**: For infrastructure/framework code, implement the full feature set rather than a minimal slice.
    *   **Rule**: Test fixtures should cover all patterns — "all of the above" is often correct.
    *   **Reason**: Foundational shortcuts create tech debt that compounds over time.

*   **¶INV_EXTEND_EXISTING_PATTERNS**: Extend existing patterns before inventing new ones.
    *   **Rule**: Check if the project already has a similar pattern before inventing a new abstraction.
    *   **Rule**: Extract shared utilities instead of duplicating code across modules.
    *   **Reason**: Consistent patterns reduce cognitive load and maintenance burden.
