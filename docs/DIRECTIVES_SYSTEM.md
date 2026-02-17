# Directives System

The behavioral specification layer that governs all LLM agent interactions. Three documents define the "operating system" for Claude Code sessions: commands, invariants, and tags.

**Related**: `~/.claude/docs/SESSION_LIFECYCLE.md` (session state machine), `~/.claude/docs/FLEET.md` (multi-agent workspace), `~/.claude/docs/CONTEXT_GUARDIAN.md` (overflow protection), `~/.claude/docs/writeups/2026_02_07_COMMANDS_COMPARATIVE_ANALYSIS.md` (positioning vs other approaches)

---

## 1. What Is the Directives System?

The directives system is a three-document behavioral specification that sits between skill protocols (what to do) and the LLM runtime (how to execute). It defines named, composable operations that agents call during session execution.

### The Three Documents

- **`COMMANDS.md`** — Instruction set
  - **Prefix**: `¶CMD_`
  - **Contents**: 45+ named commands across 4 layers — the operations agents execute

- **`INVARIANTS.md`** — Constitution
  - **Prefix**: `¶INV_`
  - **Contents**: 30+ universal rules that cannot be overridden — the laws of the system

- **`SIGILS.md`** — Communication protocol
  - **Prefix**: `¶FEED_`
  - **Contents**: Tag feeds for cross-session state and work routing (most use `§FEED_GENERIC`)

**Sigil convention**: `¶` (pilcrow) marks **definitions** — where a command, invariant, or feed is declared. `§` (section sign) marks **references** — citations of something defined elsewhere. So `COMMANDS.md` uses `¶CMD_` headings (definitions), while `SKILL.md` uses `§CMD_` references (citations). See `¶INV_SIGIL_SEMANTICS` in `INVARIANTS.md` for the full rule.

Together they define approximately 1,500+ lines of behavioral specification loaded into every agent session. COMMANDS.md provides the verbs (what to do), INVARIANTS.md provides the constraints (what never to violate), and SIGILS.md provides the nouns (how to communicate state across sessions).

### Where It Sits

```
Skill Protocols (SKILL.md)     <-- "Programs" -- what to do, in what order
        |
        | calls §CMD_ operations
        v
Standards (COMMANDS + INVARIANTS + TAGS)  <-- "Instruction Set" -- how each operation works
        |
        | interpreted by
        v
LLM Runtime (Claude, etc.)    <-- "Processor" -- executes the instructions
```

A skill protocol says "execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`" without specifying how many tool calls that takes. The standards document defines the algorithm. The LLM interprets it. This separation means skill authors write against a stable API — they do not need to know the implementation details of each command.

---

## 2. Architecture — The Four-Layer Taxonomy

COMMANDS.md organizes its 45+ commands into four layers. Each layer has a distinct responsibility and maps to an operating system concept.

```
┌─────────────────────────────────────────────────────────────────────┐
│  COMMANDS.md — Four-Layer Architecture                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Layer 4: Composites ("The Shortcuts")                              │
│  ├── Multi-step workflows built from lower layers                   │
│  ├── §CMD_INGEST_CONTEXT_BEFORE_WORK                                │
│  ├── §CMD_GENERATE_DEBRIEF                           │
│  └── ... (36 commands)                                              │
│                                                                     │
│  Layer 3: Interaction ("The Conversation")                          │
│  ├── User-facing I/O and question protocols                         │
│  ├── §CMD_ASK_USER_IF_STUCK                                         │
│  ├── §CMD_ASK_ROUND                                    │
│  └── ... (2 commands)                                               │
│                                                                     │
│  Layer 2: Process Control ("The Guards")                            │
│  ├── Execution flow, deviation handling, session management         │
│  ├── §CMD_REFUSE_OFF_COURSE                                         │
│  ├── §CMD_MAINTAIN_SESSION_DIR                                      │
│  └── ... (15 commands)                                              │
│                                                                     │
│  Layer 1: File Operations ("The Physics")                           │
│  ├── Primitive I/O — create, append, report                         │
│  ├── §CMD_APPEND_LOG                        │
│  ├── §CMD_WRITE_FROM_TEMPLATE                                   │
│  └── ... (4 commands)                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### OS Analogy

The four layers map to an operating system stack. This is not a forced metaphor — it emerged from the document's structure.

- **Layer 1: File Operations** — Kernel I/O syscalls
  - `§CMD_APPEND_LOG` = `write()`, `§CMD_WRITE_FROM_TEMPLATE` = `creat()`
- **Layer 2: Process Control** — Process scheduler + signal handlers
  - `§CMD_REFUSE_OFF_COURSE` = signal handler, `§CMD_WAIT_FOR_USER_CONFIRMATION` = `waitpid()`
- **Layer 3: Interaction** — User-space IPC / terminal I/O
  - `§CMD_ASK_USER_IF_STUCK` = blocking `read()` on stdin
- **Layer 4: Composites** — Shell builtins / coreutils
  - `§CMD_INGEST_CONTEXT_BEFORE_WORK` = `source`, `§CMD_RESUME_SESSION` = checkpoint/restore

Supporting structures complete the analogy:

- **`.state.json`** — Process table (PID, phase, skill, status)
- **`engine session activate`** — `fork()` + `exec()` with PID registration
- **Tags (`#needs-X` / `#claimed-X` / `#done-X`)** — IPC message queues
- **INVARIANTS.md** — Kernel parameters (`sysctl.conf`)
- **Skill protocols** — User-space applications
- **The LLM** — The CPU

---

## 3. Command Inventory

All 45+ `§CMD_` commands in COMMANDS.md, organized by layer. Each command has a name, definition, algorithm, and constraints — functioning as a typed behavioral function.

### Layer 1: File Operations (4 commands)

- **`§CMD_WRITE_FROM_TEMPLATE`** — Create an artifact by populating a template already in context (no disk read)
- **`§CMD_APPEND_LOG`** — Append to log files via `log.sh` — blind write, no re-reading
- **`§CMD_LINK_FILE`** — Report file creation as a clickable link — never echo content to chat
- **`§CMD_AWAIT_TAG`** — Block on a filesystem watcher until a tag appears (async coordination)

### Layer 2: Process Control

- **`§CMD_NO_MICRO_NARRATION`** — Suppress internal monologue in chat — just call the tool
- **`§CMD_ESCAPE_TAG_REFERENCES`** — Backtick-escape tag references in body text to prevent false positives
- **`§CMD_THINK_IN_LOG`** — Write reasoning to the log file, not the chat
- **`§CMD_ASSUME_ROLE`** — Anchor to a persona (e.g., TDD, Skeptic, Rigor) for the session
- **`§CMD_INIT_LOG`** — Create or reconnect to a session log file
- **`§CMD_WAIT_FOR_USER_CONFIRMATION`** — Hard stop — end turn and wait for user input before proceeding
- **`§CMD_REFUSE_OFF_COURSE`** — Deviation router — surface conflicts instead of silently skipping steps
- **`§CMD_PARSE_PARAMETERS`** — Parse session inputs against a JSON schema (the "function signature" of a session)
- **`§CMD_MAINTAIN_SESSION_DIR`** — Anchor to a session directory for the duration of the task
- **`§CMD_UPDATE_PHASE`** — Update `.state.json` with the current skill phase
- **`§CMD_RESUME_SESSION`** — Resume after overflow or manual restart
- **`§CMD_FREEZE_CONTEXT`** — Phase-specific constraint — no filesystem exploration during setup
- **`§CMD_TRACK_PROGRESS`** — Maintain an internal TODO list for session progress
- **`§CMD_LOG_BETWEEN_TOOL_USES`** — Log reasoning between tool calls
- **`§CMD_REQUIRE_ACTIVE_SESSION`** — Gate that blocks work without an active session
- **`§CMD_DEBUG_HOOKS_IF_PROMPTED`** — Hook debugging when user reports issues
- **`§CMD_SESSION_CLI`** — Session management CLI interface

### Layer 3: Interaction (2 commands)

- **`§CMD_ASK_USER_IF_STUCK`** — Halt and ask when progress is stalled or ambiguity is high
- **`§CMD_ASK_ROUND`** — Structured questioning protocol — 3-5 targeted questions per round

### Layer 4: Composites (36 commands)

- **`§CMD_INGEST_CONTEXT_BEFORE_WORK`** — Dedicated phase for RAG search + user confirmation
- **`§CMD_GENERATE_DEBRIEF`** — Standardized debrief with tags and reindexing
- **`§CMD_GENERATE_PLAN`** — Create a standardized plan artifact
- **`§CMD_RUN_SYNTHESIS_PIPELINE`** — Multi-step synthesis orchestrator
- **`§CMD_CLOSE_SESSION`** — Session deactivation to idle state
- **`§CMD_SELECT_MODE`** — Mode selection (3 named + Custom)
- **`§CMD_SUGGEST_EXTERNAL_MODEL`** — External model selection (Gemini)
- **`§CMD_EXECUTE_EXTERNAL_MODEL`** — Execute via external model with fallback
- **`§CMD_REPORT_INTENT`** — Phase transition intent blockquote
- **`§CMD_LOG_INTERACTION`** — Record Q&A to DIALOGUE.md
- **`§CMD_INTERROGATE`** — Multi-round Ask-Log loop
- **`§CMD_EXECUTE_SKILL_PHASES`** — Top-level phase orchestrator
- **`§CMD_EXECUTE_PHASE_STEPS`** — Per-phase step runner
- **`§CMD_EXECUTE_PHASE_STEPS`** — Per-phase step runner with automatic phase boundary gate
- **`§CMD_SELECT_EXECUTION_PATH`** — Execution path chooser (inline/agent/parallel)
- **`§CMD_HANDOFF_TO_AGENT`** — Synchronous sub-agent launch
- **`§CMD_PARALLEL_HANDOFF`** — Multi-agent parallel execution
- **`§CMD_DESIGN_E2E_TEST`** — E2E reproduction test design
- **`§CMD_WALK_THROUGH_RESULTS`** — Finding triage / plan review
- **`§CMD_CAPTURE_KNOWLEDGE`** — Parameterized knowledge capture (invariants, pitfalls)
- **`§CMD_VALIDATE_ARTIFACTS`** — Session artifact validation
- **`§CMD_PROCESS_CHECKLISTS`** — Checklist processing at deactivation
- **`§CMD_RESOLVE_BARE_TAGS`** — Bare inline tag resolution
- **`§CMD_MANAGE_DIRECTIVES`** — AGENTS.md updates, invariant + pitfall capture
- **`§CMD_CAPTURE_SIDE_DISCOVERIES`** — Side-discovery tagging
- **`§CMD_DELEGATE`** — Write delegation REQUEST files
- **`§CMD_DISPATCH_APPROVAL`** — Approve `#needs-X` to `#delegated-X` transitions
- **`§CMD_PROCESS_DELEGATIONS`** — Scan for unresolved inline `#needs-X` tags
- **`§CMD_RESOLVE_CROSS_SESSION_TAGS`** — Cross-session tag resolution
- **`§CMD_MANAGE_BACKLINKS`** — Cross-document link management (auto-apply)
- **`§CMD_REPORT_LEFTOVER_WORK`** — Unfinished work report
- **`§CMD_REPORT_ARTIFACTS`** — Final artifact inventory with clickable links
- **`§CMD_REPORT_SUMMARY`** — Dense narrative of session work
- **`§CMD_RESUME_AFTER_CLOSE`** — Re-anchor after skill completion
- **`§CMD_DEHYDRATE`** — Context overflow dehydration
- **`§CMD_PRESENT_NEXT_STEPS`** — Post-synthesis routing menu
- **`§CMD_DECISION_TREE`** — Declarative decision tree collector
- **`§CMD_TAG_TRIAGE`** — Tag-based item triage

### Command Composition

Commands compose — higher-layer commands call lower-layer commands. Key composition chains:

```
§CMD_GENERATE_DEBRIEF
  └── §CMD_WRITE_FROM_TEMPLATE (Layer 1)
  └── §CMD_LINK_FILE (Layer 1)

§CMD_RUN_SYNTHESIS_PIPELINE
  └── §CMD_GENERATE_DEBRIEF (Layer 4)
  └── §CMD_MANAGE_DIRECTIVES (Layer 4)
  └── §CMD_CAPTURE_SIDE_DISCOVERIES (Layer 4)
  └── §CMD_REPORT_LEFTOVER_WORK (Layer 4)
  └── §CMD_VALIDATE_ARTIFACTS (Layer 4)

§CMD_INGEST_CONTEXT_BEFORE_WORK
  └── AskUserQuestion multichoice menu (context sources)

§CMD_INTERROGATE
  └── §CMD_ASK_ROUND (Layer 3)
  └── §CMD_LOG_INTERACTION (Layer 4)

§CMD_MAINTAIN_SESSION_DIR
  └── §CMD_WRITE_FROM_TEMPLATE (Layer 1) [if creating]
  └── §CMD_APPEND_LOG (Layer 1) [if resuming]
```

---

## 4. The Invariant System

INVARIANTS.md defines 30+ universal rules organized into 7 categories. Invariants are constraints that hold across all sessions, all skills, and all projects. They are the constitution — commands implement behavior, invariants constrain it.

### Invariant Categories

- **Testing Physics** — Test isolation and framework independence
- **Architecture & Task Decomposition** — Spec-first design, atomic tasks
- **General Code Physics** — Naming, dead code, TypeScript, config
- **Communication Physics** — Skill invocation, protocol compliance, file links, chat conciseness
- **Development Philosophy** — Data-first fixes, explicit config, DX priority, extend patterns
- **LLM Output Physics** — Enum confidence, rule traceability, org context
- **Filesystem Physics** — Symlink traversal workaround

### Key Invariants for Agent Behavior

Several invariants directly govern how agents interact with the standards system:

- **`¶INV_SKILL_PROTOCOL_MANDATORY`**: The protocol is the task. Every step executes. No exceptions. If you want to skip a step, you fire `§CMD_REFUSE_OFF_COURSE` and let the user decide.
- **`¶INV_PROTOCOL_IS_TASK`**: The user's request is an input parameter to the protocol, not a replacement for it. "Implement X" means "execute the implementation protocol with X as the input."
- **`¶INV_REDIRECTION_OVER_PROHIBITION`**: Redirections ("do X instead") are more reliable than prohibitions ("don't do Y"). Pair every prohibition with a concrete alternative action.
- **`¶INV_SKILL_VIA_TOOL`**: Skills are invoked via the Skill tool, never via Bash.
- **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only. No narration, no micro-steps.
- **`¶INV_CLAIM_BEFORE_WORK`**: An agent must swap `#needs-X` to `#claimed-X` before starting work (multi-agent coordination).

### Shared vs. Project-Specific

Two levels of invariants exist:

- **Shared** — `~/.claude/.directives/INVARIANTS.md`
  - **Scope**: All projects
  - **Example**: `¶INV_TYPESCRIPT_STRICT`, `¶INV_NO_DEAD_CODE`

- **Project** — `.claude/.directives/INVARIANTS.md`
  - **Scope**: One project
  - **Example**: `¶INV_NO_GIT_STATE_COMMANDS`, `¶INV_SCRATCHPAD_IN_TEMP`

Project invariants extend the shared set. They cannot contradict shared invariants — they only add project-specific constraints.

---

## 5. The Tag System

SIGILS.md defines a cross-session communication protocol using semantic tags. Tags are the IPC mechanism — they allow sessions to communicate state, request work, and coordinate parallel agents without shared memory.

### Tag Lifecycle Pattern

All tags follow a 4-state lifecycle with two paths:

```
Daemon path (async):
  #needs-X → #delegated-X → #claimed-X → #done-X
   (staging)   (approved)     (worker)    (resolved)

Immediate path (next-skill):
  #needs-X → #next-X → #claimed-X → #done-X
   (staging)  (claimed)   (worker)   (resolved)
```

The `#needs-X` → `#delegated-X` transition requires human approval via `§CMD_DISPATCH_APPROVAL`. The `#needs-X` → `#next-X` transition is set when the user claims work for the next skill session.

### The Three Feed Types

*   **`§FEED_ALERTS`** — 2-state lifecycle (`#active-alert` → `#done-alert`). Active alerts are loaded into every new session. Managed by `§CMD_MANAGE_ALERTS`.

*   **`§FEED_REVIEWS`** — 2-state lifecycle (`#needs-review` → `#done-review` or `#needs-rework`). Quality gate for debriefs. Auto-applied at debrief creation. Processed by `/review`.

*   **`§FEED_GENERIC`** — 4-state lifecycle (two paths above). Covers all delegation-capable tag nouns: brainstorm, direct, research, fix, implementation, loop, chores, documentation. Each tag noun maps 1:1 to a resolving skill (`¶INV_1_TO_1_TAG_SKILL`).

### Dispatch Priority

When multiple tagged items exist, `§TAG_DISPATCH` defines processing order:

*   **Priority 1** — `#needs-brainstorm` → `/brainstorm` — Exploration unblocks decisions
*   **Priority 1.5** — `#needs-direct` → `/direct` — Vision unblocks coordination
*   **Priority 2** — `#needs-research` → `/research` — Async, queue early
*   **Priority 3** — `#needs-fix` → `/fix` — Bugs block progress
*   **Priority 4** — `#needs-implementation` → `/implement` — Core work
*   **Priority 4.5** — `#needs-loop` → `/loop` — Iteration workloads
*   **Priority 5** — `#needs-chores` → `/chores` — Quick wins, filler
*   **Priority 6** — `#needs-documentation` → `/document` — Post-code cleanup
*   **Priority 7** — `#needs-review` → `/review` — Final quality gate (user-invoked only)

### Weight Tags

Optional metadata for urgency and effort estimation:

- **Priority**: `#P0` (critical, blocks everything), `#P1` (important), `#P2` (normal, default)
- **Effort**: `#S` (< 30 min), `#M` (30 min - 2 hrs), `#L` (> 2 hrs)
- **Combinable**: `#needs-implementation #P1 #M`

### Escaping Convention

Tags in body text must be backtick-escaped to prevent false discovery:

- **Bare `#tag`**: Actual tag — on the Tags line or as an intentional inline marker
- **Backticked `` `#tag` ``**: Reference only — filtered out by `tag.sh find`

This distinction prevents `tag.sh find '#needs-review'` from returning every document that discusses the review process, rather than just documents that are actually pending review.

---

## 6. Design Principles

Six design patterns collectively define the system's character. They are interdependent — removing one weakens the others.

### Redirect Over Prohibit

When the agent feels the impulse to skip a step, that impulse becomes the trigger to ask the user. The skip-impulse becomes the ask-impulse. This channels the LLM's helpfulness drive into a compliant action rather than suppressing it.

**Mechanism**: `§CMD_REFUSE_OFF_COURSE` + `¶INV_REDIRECTION_OVER_PROHIBITION`

**Why it works**: Prohibitions ("don't skip") compete with the LLM's training to be helpful and efficient. Redirections ("ask the user instead") give the LLM something to do, which is easier to follow than doing nothing.

### Dual-Channel Architecture

Strict separation of brain (filesystem) and mouth (chat). All reasoning goes to the log file; only conclusions and questions reach the user.

**Mechanism**: `§CMD_THINK_IN_LOG` + `§CMD_NO_MICRO_NARRATION` + `¶INV_CONCISE_CHAT`

**Why it works**: Prevents the "thinking aloud" antipattern that wastes tokens and creates loops where the agent narrates actions instead of executing them.

### Blind Write Token Economy

Append-only logging with no re-reading. The agent writes to the log via `log.sh` and never sees its accumulated output. This creates a write-heavy, read-light I/O pattern.

**Mechanism**: `§CMD_APPEND_LOG` + `§INV_TRUST_CACHED_CONTEXT`

**Why it works**: A typical session might append 20-40 log entries. Without blind writes, each append would require reading the entire log first (read-modify-write), consuming thousands of tokens. Blind appends cost only the new content.

### Protocol Is The Task

The user's request is an input parameter to the protocol, not a replacement for it. "Implement X" means "execute the implementation protocol with X as the input" — not "write code for X and skip the ceremony."

**Mechanism**: `¶INV_PROTOCOL_IS_TASK` + `¶INV_SKILL_PROTOCOL_MANDATORY`

**Why it works**: Without this framing, the LLM treats the protocol as overhead wrapping the "real" task and optimizes it away. Reframing the protocol as the task itself prevents the most common failure mode.

### Behavioral API Naming

Named, composable behavioral specifications using the `§CMD_` and `¶INV_` prefix system. Each command is a first-class citizen with an identifier, documentation, implementation, and composition rules.

**Mechanism**: The `§CMD_` / `¶INV_` / `§FEED_` namespace convention

**Why it works**: Named commands are referenceable. A skill protocol can say "execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`" and both the agent and the author know exactly what behavior is expected. This is prompt engineering elevated to software engineering — specifications with identifiers, contracts, and composition.

### Session Lifecycle Management

A complete process lifecycle from birth to post-synthesis continuation. Sessions are born (`§CMD_PARSE_PARAMETERS`), activated (`§CMD_MAINTAIN_SESSION_DIR`), executed through phases (`§CMD_UPDATE_PHASE`), debriefed (`§CMD_GENERATE_DEBRIEF`), and optionally continued (`§CMD_RESUME_AFTER_CLOSE`) or restarted after overflow (`§CMD_RECOVER_SESSION`).

**Mechanism**: `.state.json` as the process table, PID tracking, phase tracking, dehydration/session continue for overflow recovery

**Why it works**: Creates a process manager for LLM agents built entirely in Markdown and shell scripts. The agent has a persistent identity (PID), knows where it is (phase), and can recover from crashes (session continue). See `~/.claude/docs/SESSION_LIFECYCLE.md` for the full state machine.

### Interdependence

These six patterns reinforce each other:

- Redirect-over-prohibit only works because of protocol-is-task (the protocol must be worth defending)
- Dual-channel only works because of blind-write (the log channel must be cheap)
- Session lifecycle only works because of behavioral API naming (phases need composable operations)
- Blind-write only works because of dual-channel (there must be a separate place for reasoning)

---

## 7. How Skills Use the Standards

Skills are the "user-space applications" that run on top of the standards system. Each skill has a `SKILL.md` protocol that defines phases and steps. Those steps call `§CMD_` commands.

### The Relationship

```
┌──────────────────────────────────────────────────┐
│  /implement SKILL.md                              │
│                                                   │
│  Phase 1: Setup                                   │
│    → §CMD_PARSE_PARAMETERS                         │
│    → §CMD_MAINTAIN_SESSION_DIR                     │
│                                                   │
│  Phase 2: Context Ingestion                       │
│    → §CMD_INGEST_CONTEXT_BEFORE_WORK               │
│                                                   │
│  Phase 3: Planning                                │
│    → §CMD_INTERROGATE           │
│    → §CMD_GENERATE_PLAN              │
│                                                   │
│  Phase N: Synthesis                               │
│    → §CMD_GENERATE_DEBRIEF          │
│    → §CMD_REPORT_ARTIFACTS               │
│    → §CMD_REPORT_SUMMARY                   │
│                                                   │
│  Invariants enforced throughout:                  │
│    ¶INV_SKILL_PROTOCOL_MANDATORY                   │
│    ¶INV_PROTOCOL_IS_TASK                           │
│    ¶INV_CONCISE_CHAT                               │
│                                                   │
│  Tags applied at debrief:                         │
│    #needs-review (always)                         │
│    #needs-documentation (if code changed)         │
│                                                   │
└──────────────────────────────────────────────────┘
```

### What Skills Do NOT Do

Skills do not define how to write to a log file, how to handle deviations, how to manage sessions, or how to coordinate with other agents. These are all handled by the standards system. A skill protocol is a sequence of "what" — the standards provide the "how."

This separation means:
- New skills can be created by composing existing commands
- Changing a command's algorithm updates all skills that use it
- Skills remain concise — they specify phases, not implementations

---

## 8. The Emergent Type System

The standards system contains what amounts to a type system, though it was not designed as one. Three subsystems converge on typed, structured behavior:

### Input Types (Session Parameters)

`§CMD_PARSE_PARAMETERS` defines a JSON schema with required fields, typed properties (`string`, `array`, `enum`), and structured defaults. Every session begins by parsing inputs against this schema — runtime type-checking of session parameters.

### Output Types (Template Fidelity)

The "STRICT TEMPLATE FIDELITY" constraint in `§CMD_WRITE_FROM_TEMPLATE` means debrief and plan templates define the return type of a session. The agent cannot add or remove sections — only populate the predefined structure. This is structural typing: the output must conform to the template's shape.

### State Types (Tag Lifecycles)

The `#needs-X` to `#claimed-X` to `#done-X` progression is a finite state machine with defined transitions. An artifact can only move forward through its lifecycle. This is an enum-based state machine type.

### The Gap

This type system is enforced by LLM compliance, not by a machine checker. At 90%+ compliance the system works in practice, but there is no static analysis that validates "this skill only calls commands that exist" or "this template's fields match the schema's output." The LLM is the type checker.

---

## 9. External Dependencies

The standards system references shell scripts that implement its operations. The behavioral specification (COMMANDS.md) and the implementation (scripts) are separate layers.

*   **`log.sh`**
  *   Called by: `§CMD_APPEND_LOG`
  *   Purpose: Append-only log writes with timestamp injection

*   **`session.sh`**
  *   Called by: `§CMD_MAINTAIN_SESSION_DIR`, `§CMD_UPDATE_PHASE`, `§CMD_RESUME_SESSION`
  *   Purpose: Session state management (activate, phase, deactivate, restart)

*   **`tag.sh`**
  *   Called by: `§CMD_TAG_FILE`, `§CMD_UNTAG_FILE`, `§CMD_SWAP_TAG_IN_FILE`, `§CMD_FIND_TAGGED_FILES`
  *   Purpose: Tag lifecycle operations (add, remove, swap, find)

*   **`user-info.sh`**
  *   Called by: `¶INV_INFER_USER_FROM_GDRIVE`
  *   Purpose: User identity detection from GDrive mount path

*   **`glob.sh`**
  *   Called by: `¶INV_GLOB_THROUGH_SYMLINKS`
  *   Purpose: Symlink-aware file globbing

*   **`session-search.sh`**
  *   Called by: `§CMD_INGEST_CONTEXT_BEFORE_WORK`
  *   Purpose: Semantic (RAG) search over session history

*   **`doc-search.sh`**
  *   Called by: `§CMD_INGEST_CONTEXT_BEFORE_WORK`
  *   Purpose: Semantic (RAG) search over project documentation

*   **`research.sh`**
  *   Called by: `/research` skill
  *   Purpose: Gemini Deep Research API wrapper

---

## 10. Key Metrics

*   **Named commands** — 45+ (COMMANDS.md inline) + 5 (SIGILS.md tag operations) + 45 extracted CMD files
  *   Source: COMMANDS.md Section 3, `.directives/commands/`

*   **Named invariants** — 30+ (shared) + project-specific
  *   Source: INVARIANTS.md (14 categories)

*   **Tag feeds** — 3 types (Alerts, Reviews, Generic) covering 10 tag nouns
  *   Source: SIGILS.md

*   **Architectural layers** — 4
  *   Source: COMMANDS.md section headers

*   **Total specification lines** — ~6,300 (~1,460 in the Big Three + ~4,870 across 45 extracted CMD files)
  *   Source: COMMANDS.md + INVARIANTS.md + SIGILS.md + `.directives/commands/`

*   **Context cost per session** — ~530 lines upfront (COMMANDS.md) + per-phase CMD file loading via hooks
  *   Source: SessionStart hook loads Big Three; PostToolUse hook loads phase-specific CMD files on demand

---

## 11. Further Reading

- **Session state machine**: `~/.claude/docs/SESSION_LIFECYCLE.md` — All restart/restore/rehydration scenarios, race conditions, identity fields
- **Multi-agent workspace**: `~/.claude/docs/FLEET.md` — Fleet tmux management, pane coordination, dispatch
- **Overflow protection**: `~/.claude/docs/CONTEXT_GUARDIAN.md` — Context overflow detection, dehydration, restart flow
- **Session skill**: `~/.claude/docs/SESSION_SKILL.md` — Usage guide for `/session` (dehydrate, continue, search, status)
- **Document indexing**: `~/.claude/docs/DOCUMENT_INDEXING.md` — RAG search infrastructure used by `§CMD_INGEST_CONTEXT_BEFORE_WORK`
- **Comparative analysis**: `~/.claude/docs/writeups/2026_02_07_COMMANDS_COMPARATIVE_ANALYSIS.md` — How COMMANDS.md compares to Cursor .cursorrules, system prompts, and JSON schema approaches
- **The source files**: `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, `~/.claude/.directives/SIGILS.md`
