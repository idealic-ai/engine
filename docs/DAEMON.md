# Daemon Mode & Tag Dispatch

How `run.sh --monitor-tags` watches for tagged files, maps tags to skills, and spawns Claude to process them.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Daemon Dispatch (4-State)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Requester              Synthesis           Daemon              Worker  │
│   ─────────              ─────────           ──────              ──────  │
│                                                                          │
│   1. Agent creates       2. §CMD_DISPATCH_                              │
│      #needs-X tag           APPROVAL runs                               │
│      (REQUEST file or       during synthesis                            │
│       inline tag)              │                                         │
│                           3. User approves                               │
│                              #needs-X →                                  │
│                              #delegated-X                                │
│                                │                                         │
│                                └────────►  4. fswatch detects            │
│                                               file change                │
│                                                  │                       │
│                                            5. 3s debounce                │
│                                               (collect batch)            │
│                                                  │                       │
│                                            6. tag.sh find                │
│                                               '#delegated-*'             │
│                                               --tags-only                │
│                                                  │                       │
│                                            7. Spawn Claude  ──► /deleg.  │
│                                               with /deleg.       -claim  │
│                                               -claim             + routes│
│                                                  │                       │
│                                                  │     8. /delegation-   │
│                                                  │            swap tag   │
│                                                  │            #delegated │
│                                                  │            → #claimed │
│                                                  │               │       │
│                                                  │         9. Route to   │
│                                                  │            target     │
│                                                  │            skill      │
│                                                  │               │       │
│                                            10. Wait for    ◄── Claude    │
│                                                exit             exits    │
│                                                  │                       │
│                                            11. Loop: rescan             │
│                                                for more work             │
│                                                                          │
│   Ctrl+C: clean exit (signal-flag-polling pattern)                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# Start daemon watching for delegated work
~/.claude/scripts/run.sh --monitor-tags='#delegated-implementation'

# Watch multiple tags
~/.claude/scripts/run.sh --monitor-tags='#delegated-implementation,#delegated-chores'

# Create a request (from another agent session)
~/.claude/scripts/session.sh request-template '#needs-implementation' > REQUEST.md
# Edit REQUEST.md, then during synthesis /delegation-review flips #needs-X → #delegated-X
```

## The 4-State Tag Lifecycle

Tags ARE the work queue. No separate queue infrastructure.

```
#needs-X → #delegated-X → #claimed-X → #done-X
   │           │              │           │
 staging    approved       worker      resolved
 (human     for daemon     picked up
  review)   dispatch       & working
```

| Tag State | Meaning | Who Transitions |
|-----------|---------|-----------------|
| `#needs-X` | Work identified, pending review | Agent (any skill) creates |
| `#delegated-X` | Approved for daemon dispatch | Human via `/delegation-review` |
| `#claimed-X` | Worker claimed, in progress | `/delegation-claim` skill via `tag.sh swap` |
| `#done-X` | Completed | Target skill during synthesis |

**Key invariants**:
- `¶INV_NEEDS_IS_STAGING`: Daemons MUST NOT monitor `#needs-X`. Only `#delegated-X` triggers dispatch.
- `¶INV_DISPATCH_APPROVAL_REQUIRED`: The `#needs-X` → `#delegated-X` transition requires human approval.
- `¶INV_CLAIM_BEFORE_WORK`: Workers MUST swap `#delegated-X` → `#claimed-X` before starting work.
- `¶INV_DAEMON_DEBOUNCE`: 3s debounce before scanning — allows batch writes from `/delegation-review` to settle.

```bash
# Tag operations
tag.sh find '#delegated-implementation' sessions/ --tags-only  # Find approved work
tag.sh swap "$FILE" '#delegated-implementation' '#claimed-implementation'  # Claim
tag.sh swap "$FILE" '#claimed-implementation' '#done-implementation'  # Complete
```

## Creating Request Files

### 1. Get the template

```bash
# Outputs the REQUEST template for a tag to stdout
~/.claude/scripts/session.sh request-template '#needs-implementation'

# Agent workflow: get template, write file via log.sh
TEMPLATE=$(~/.claude/scripts/session.sh request-template '#needs-implementation')
# Fill in fields, write to session directory
```

### 2. Available templates

Each dispatchable skill has a `TEMPLATE_*_REQUEST.md` in its `assets/` directory. The tag is on the `**Tags**:` line — this is how discovery works.

| Tag | Skill | Template |
|-----|-------|----------|
| `#needs-implementation` | `/implement` | `implement/assets/TEMPLATE_IMPLEMENTATION_REQUEST.md` |
| `#needs-chores` | `/chores` | `chores/assets/TEMPLATE_CHORES_REQUEST.md` |
| `#needs-review` | `/review` | `review/assets/TEMPLATE_REVIEW_REQUEST.md` |
| `#needs-documentation` | `/document` | `document/assets/TEMPLATE_DOCUMENTATION_REQUEST.md` |
| `#needs-brainstorm` | `/brainstorm` | `brainstorm/assets/TEMPLATE_BRAINSTORM_REQUEST.md` |
| `#needs-research` | `/research` | `research/assets/TEMPLATE_RESEARCH_REQUEST.md` |

### 3. Template structure (minimal)

All REQUEST templates follow the same pattern:

```markdown
# [Skill] Request: [TOPIC]
**Tags**: #needs-xxx

## 1. Topic
*   **What**: [description]
*   **Why**: [motivation]

## 2. Context
*   **Relevant Files**: [paths]

## 3. Expectations
*   [what the skill should deliver]

## 4. Requesting Session
*   **Session**: sessions/[path]/
*   **Requester**: [agent or pane]
```

## Dynamic Discovery

**No static maps.** Both the daemon and `session.sh request-template` discover tag-to-skill mappings by scanning `TEMPLATE_*_REQUEST.md` files:

```bash
# How discovery works (used by both run.sh and session.sh):
grep -rl "^\*\*Tags\*\*:.*#needs-implementation" \
  ~/.claude/skills/*/assets/TEMPLATE_*_REQUEST.md
# Returns: ~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_REQUEST.md
# Skill dir = "implement" → command = "/implement"
```

**Adding a new dispatchable skill**: Create `~/.claude/skills/YOUR_SKILL/assets/TEMPLATE_*_REQUEST.md` with the tag on its Tags line. Both the daemon and `session.sh request-template` will discover it automatically.

## Daemon Internals

### Dispatch Flow

The daemon no longer directly claims or routes work. Instead it:

1. **Watches** `sessions/` via `fswatch` for file changes
2. **Debounces** — waits 3 seconds after first detection to collect batch writes from `/delegation-review`
3. **Scans** for `#delegated-*` tags via `tag.sh find --tags-only`
4. **Spawns** a single Claude with `/delegation-claim` — the `/delegation-claim` skill handles all routing

### Work Scanning (`daemon_scan_with_debounce`)

After `fswatch` detects a change:
1. Runs `tag.sh find '#delegated-*' sessions/ --tags-only`
2. If matches found, sleeps 3 seconds (debounce)
3. Re-scans to collect any additional tags that appeared during the debounce window
4. Returns all `TAG:PATH` pairs to `daemon_process_work`

### Processing (`daemon_process_work`)

Receives the batch scan results and spawns a single Claude instance:
- Uses `claude --append-system-prompt "$PROMPT" "/delegation-claim"`
- The system prompt includes `DAEMON_MODE` instruction telling Claude to exit after skill completion
- `/delegation-claim` scans for `#delegated-*`, presents items, claims via `tag.sh swap`, and routes to target skill
- One Claude at a time (single foreground) — no parallel spawning

### The `/delegation-claim` Skill

`/delegation-claim` is a lightweight, nestable skill that handles the worker side:
1. Scans `#delegated-*` tags via `tag.sh find`
2. Groups by tag type (e.g., all `#delegated-implementation` together)
3. Reads request context from tagged files
4. Presents claiming menu to worker
5. Claims via `tag.sh swap '#delegated-X' '#claimed-X'` — errors on race condition (old tag already gone)
6. Routes to target skill (e.g., `/implement`)

### Signal Handling

Uses the signal-flag-polling pattern for clean Ctrl+C:
1. `trap` sets `DAEMON_EXIT=1` on SIGINT/SIGTERM
2. `fswatch` runs in a background subshell
3. Main loop polls the flag every 0.5s
4. When flag set → kill fswatch, exit loop

## Invariants

### ¶INV_NEEDS_IS_STAGING
`#needs-X` is a staging tag. Daemons MUST NOT monitor `#needs-X`. Only `#delegated-X` triggers autonomous dispatch. The transition requires human approval via `/delegation-review`.

### ¶INV_DISPATCH_APPROVAL_REQUIRED
The `#needs-X` → `#delegated-X` transition requires human approval. Agents MUST NOT auto-flip without presenting the dispatch approval walkthrough.

### ¶INV_CLAIM_BEFORE_WORK
A worker MUST swap `#delegated-X` → `#claimed-X` before starting work. Prevents double-processing. `tag.sh swap` errors (exit 1) when the old tag is already gone — race condition safety.

### ¶INV_DAEMON_DEBOUNCE
After detecting a `#delegated-X` tag, the daemon MUST wait 3 seconds before scanning and dispatching. Allows batch writes to settle.

### ¶INV_DAEMON_STATELESS
Daemon maintains no state beyond what tags encode. Crash and restart safely — tags are truth.

### ¶INV_DYNAMIC_DISCOVERY
Tag-to-skill mapping is discovered from templates, not hardcoded. Adding a new skill only requires creating a REQUEST template.

## Files

```
~/.claude/
├── scripts/
│   ├── run.sh              # Claude wrapper (--monitor-tags enables daemon mode)
│   ├── session.sh           # Session management (request-template command)
│   └── tag.sh               # Tag operations (find --tags-only, swap, etc.)
├── skills/
│   ├── delegation-claim/SKILL.md  # /delegation-claim skill (worker-side claiming + routing)
│   ├── implement/assets/TEMPLATE_IMPLEMENTATION_REQUEST.md
│   ├── chores/assets/TEMPLATE_CHORES_REQUEST.md
│   ├── review/assets/TEMPLATE_REVIEW_REQUEST.md
│   ├── document/assets/TEMPLATE_DOCUMENTATION_REQUEST.md
│   ├── brainstorm/assets/TEMPLATE_BRAINSTORM_REQUEST.md
│   └── research/assets/TEMPLATE_RESEARCH_REQUEST.md
└── docs/
    └── DAEMON.md            # This file
```

## See Also

- `~/.claude/.directives/TAGS.md` — Tag system and `§TAG_DISPATCH` routing
- `~/.claude/.directives/INVARIANTS.md` — `¶INV_NEEDS_IS_STAGING`, `¶INV_DISPATCH_APPROVAL_REQUIRED`, `¶INV_DAEMON_DEBOUNCE`, `¶INV_CLAIM_BEFORE_WORK`
- `~/.claude/.directives/COMMANDS.md` — `§CMD_DELEGATE` (low-level delegation primitive)
- `~/.claude/skills/delegation-claim/SKILL.md` — Worker-side claiming protocol
- `~/.claude/skills/delegation-review/SKILL.md` — Dispatch approval (synthesis pipeline)
- `~/.claude/skills/fleet/references/FLEET.md` — Fleet configuration protocol
