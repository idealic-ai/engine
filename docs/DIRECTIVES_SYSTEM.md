# Directives System

The behavioral specification layer that governs all LLM agent interactions. Three documents define the "operating system" for Claude Code sessions: commands, invariants, and tags.

**Related**: `~/.claude/docs/SESSION_LIFECYCLE.md` (session state machine), `~/.claude/docs/FLEET.md` (multi-agent workspace), `~/.claude/docs/CONTEXT_GUARDIAN.md` (overflow protection), `~/.claude/docs/writeups/2026_02_07_COMMANDS_COMPARATIVE_ANALYSIS.md` (positioning vs other approaches)

---

## 1. What Is the Directives System?

The directives system is a three-document behavioral specification that sits between skill protocols (what to do) and the LLM runtime (how to execute). It defines named, composable operations that agents call during session execution.

### The Three Documents

| Document | Role | Prefix | Contents |
|----------|------|--------|----------|
| `COMMANDS.md` | Instruction set | `§CMD_` | 32 named commands across 4 layers — the operations agents execute |
| `INVARIANTS.md` | Constitution | `¶INV_` | 23 universal rules that cannot be overridden — the laws of the system |
| `TAGS.md` | Communication protocol | `§FEED_` | 6 tag feeds for cross-session state and work routing |

Together they define approximately 1,100 lines of behavioral specification loaded into every agent session. COMMANDS.md provides the verbs (what to do), INVARIANTS.md provides the constraints (what never to violate), and TAGS.md provides the nouns (how to communicate state across sessions).

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

COMMANDS.md organizes its 32 commands into four layers. Each layer has a distinct responsibility and maps to an operating system concept.

```
┌─────────────────────────────────────────────────────────────────────┐
│  COMMANDS.md — Four-Layer Architecture                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Layer 4: Composites ("The Shortcuts")                              │
│  ├── Multi-step workflows built from lower layers                   │
│  ├── §CMD_INGEST_CONTEXT_BEFORE_WORK                                │
│  ├── §CMD_GENERATE_DEBRIEF_USING_TEMPLATE                           │
│  └── ... (11 commands)                                              │
│                                                                     │
│  Layer 3: Interaction ("The Conversation")                          │
│  ├── User-facing I/O and question protocols                         │
│  ├── §CMD_ASK_USER_IF_STUCK                                         │
│  ├── §CMD_ASK_ROUND_OF_QUESTIONS                                    │
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
│  ├── §CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE                        │
│  ├── §CMD_POPULATE_LOADED_TEMPLATE                                   │
│  └── ... (4 commands)                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### OS Analogy

The four layers map to an operating system stack. This is not a forced metaphor — it emerged from the document's structure.

| COMMANDS.md Layer | OS Equivalent | Key Parallel |
|-------------------|---------------|--------------|
| Layer 1: File Operations | Kernel I/O syscalls | `§CMD_APPEND_LOG` = `write()`, `§CMD_POPULATE_LOADED_TEMPLATE` = `creat()` |
| Layer 2: Process Control | Process scheduler + signal handlers | `§CMD_REFUSE_OFF_COURSE` = signal handler, `§CMD_WAIT_FOR_USER_CONFIRMATION` = `waitpid()` |
| Layer 3: Interaction | User-space IPC / terminal I/O | `§CMD_ASK_USER_IF_STUCK` = blocking `read()` on stdin |
| Layer 4: Composites | Shell builtins / coreutils | `§CMD_INGEST_CONTEXT_BEFORE_WORK` = `source`, `§CMD_SESSION_CONTINUE_AFTER_RESTART` = checkpoint/restore |

Supporting structures complete the analogy:

| System Component | OS Equivalent |
|------------------|---------------|
| `.state.json` | Process table (PID, phase, skill, status) |
| `session.sh activate --pid "$PPID"` | `fork()` + `exec()` with PID registration |
| Tags (`#needs-X` / `#claimed-X` / `#done-X`) | IPC message queues |
| INVARIANTS.md | Kernel parameters (`sysctl.conf`) |
| Skill protocols | User-space applications |
| The LLM | The CPU |

---

## 3. Command Inventory

All 32 `§CMD_` commands in COMMANDS.md, organized by layer. Each command has a name, definition, algorithm, and constraints — functioning as a typed behavioral function.

### Layer 1: File Operations (4 commands)

| Command | Purpose |
|---------|---------|
| `§CMD_POPULATE_LOADED_TEMPLATE` | Create an artifact by populating a template already in context (no disk read) |
| `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` | Append to log files via `log.sh` — blind write, no re-reading |
| `§CMD_REPORT_FILE_CREATION_SILENTLY` | Report file creation as a clickable link — never echo content to chat |
| `§CMD_AWAIT_TAG` | Block on a filesystem watcher until a tag appears (async coordination) |

### Layer 2: Process Control (15 commands)

| Command | Purpose |
|---------|---------|
| `§CMD_NO_MICRO_NARRATION` | Suppress internal monologue in chat — just call the tool |
| `§CMD_ESCAPE_TAG_REFERENCES` | Backtick-escape tag references in body text to prevent false positives |
| `§CMD_THINK_IN_LOG` | Write reasoning to the log file, not the chat |
| `§CMD_ASSUME_ROLE` | Anchor to a persona (e.g., TDD, Skeptic, Rigor) for the session |
| `§CMD_INIT_OR_RESUME_LOG_SESSION` | Create or reconnect to a session log file |
| `§CMD_WAIT_FOR_USER_CONFIRMATION` | Hard stop — end turn and wait for user input before proceeding |
| `§CMD_REFUSE_OFF_COURSE` | Deviation router — surface conflicts instead of silently skipping steps |
| `§CMD_PARSE_PARAMETERS` | Parse session inputs against a JSON schema (the "function signature" of a session) |
| `§CMD_MAINTAIN_SESSION_DIR` | Anchor to a session directory for the duration of the task |
| `§CMD_UPDATE_PHASE` | Update `.state.json` with the current skill phase |
| `§CMD_SESSION_CONTINUE_AFTER_RESTART` | Re-initialize context after a context overflow restart |
| `§CMD_LOAD_AUTHORITY_FILES` | Load system-critical files into context (check-before-read) |
| `§CMD_USE_ONLY_GIVEN_CONTEXT` | Phase-specific constraint — no filesystem exploration during setup |
| `§CMD_AVOID_WASTING_TOKENS` | Prevent redundant reads and operations |
| `§CMD_USE_TODOS_TO_TRACK_PROGRESS` | Maintain an internal TODO list for session progress |

### Layer 3: Interaction (2 commands)

| Command | Purpose |
|---------|---------|
| `§CMD_ASK_USER_IF_STUCK` | Halt and ask when progress is stalled or ambiguity is high |
| `§CMD_ASK_ROUND_OF_QUESTIONS` | Structured questioning protocol — 3-5 targeted questions per round |

### Layer 4: Composites (11 commands)

| Command | Purpose |
|---------|---------|
| `§CMD_INGEST_CONTEXT_BEFORE_WORK` | Dedicated phase for RAG search + user confirmation before execution |
| `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` | Create a standardized debrief with tags, related sessions, and reindexing |
| `§CMD_GENERATE_PLAN_FROM_TEMPLATE` | Create a standardized plan artifact from template |
| `§CMD_REPORT_INTENT_TO_USER` | State current phase and intent before transitioning |
| `§CMD_LOG_TO_DETAILS` | Record Q&A interactions to the session's `DETAILS.md` |
| `§CMD_EXECUTE_INTERROGATION_PROTOCOL` | Multi-round Ask-Log loop with minimum 3 rounds |
| `§CMD_HAND_OFF_TO_AGENT` | Standardized handoff from parent command to autonomous agent |
| `§CMD_REPORT_RESULTING_ARTIFACTS` | Final artifact inventory with clickable links |
| `§CMD_REPORT_SESSION_SUMMARY` | Dense 2-paragraph narrative of session work |
| `§CMD_CONTINUE_OR_CLOSE_SESSION` | Re-anchor and continue logging after a skill completes |
| `§CMD_PROMPT_INVARIANT_CAPTURE` | Review session for insights worth capturing as permanent invariants |

### Command Composition

Commands compose — higher-layer commands call lower-layer commands. Key composition chains:

```
§CMD_GENERATE_DEBRIEF_USING_TEMPLATE
  └── §CMD_POPULATE_LOADED_TEMPLATE (Layer 1)
  └── §CMD_REPORT_FILE_CREATION_SILENTLY (Layer 1)
  └── §CMD_PROMPT_INVARIANT_CAPTURE (Layer 4)

§CMD_INGEST_CONTEXT_BEFORE_WORK
  └── §CMD_WAIT_FOR_USER_CONFIRMATION (Layer 2) [twice — hard stops]
  └── §CMD_LOAD_AUTHORITY_FILES (Layer 2)

§CMD_EXECUTE_INTERROGATION_PROTOCOL
  └── §CMD_ASK_ROUND_OF_QUESTIONS (Layer 3)
  └── §CMD_LOG_TO_DETAILS (Layer 4)

§CMD_MAINTAIN_SESSION_DIR
  └── §CMD_POPULATE_LOADED_TEMPLATE (Layer 1) [if creating]
  └── §CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE (Layer 1) [if resuming]
```

---

## 4. The Invariant System

INVARIANTS.md defines 23 universal rules organized into 7 categories. Invariants are constraints that hold across all sessions, all skills, and all projects. They are the constitution — commands implement behavior, invariants constrain it.

### Invariant Categories

| Category | Count | Scope |
|----------|-------|-------|
| Testing Physics | 2 | Test isolation and framework independence |
| Architecture & Task Decomposition | 2 | Spec-first design, atomic tasks |
| General Code Physics | 6 | Naming, dead code, TypeScript, config |
| Communication Physics | 4 | Skill invocation, protocol compliance, file links, chat conciseness |
| Development Philosophy | 5 | Data-first fixes, explicit config, DX priority, extend patterns |
| LLM Output Physics | 4 | Enum confidence, rule traceability, org context |
| Filesystem Physics | 1 | Symlink traversal workaround |

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

| Level | File | Scope | Example |
|-------|------|-------|---------|
| Shared | `~/.claude/.directives/INVARIANTS.md` | All projects | `¶INV_TYPESCRIPT_STRICT`, `¶INV_NO_DEAD_CODE` |
| Project | `.claude/.directives/INVARIANTS.md` | One project | `¶INV_NO_GIT_STATE_COMMANDS`, `¶INV_SCRATCHPAD_IN_TEMP` |

Project invariants extend the shared set. They cannot contradict shared invariants — they only add project-specific constraints.

---

## 5. The Tag System

TAGS.md defines a cross-session communication protocol using semantic tags. Tags are the IPC mechanism — they allow sessions to communicate state, request work, and coordinate parallel agents without shared memory.

### Tag Lifecycle Pattern

All tags follow a three-state lifecycle:

```
#needs-X  ──→  #claimed-X  ──→  #done-X
(pending)      (in flight)       (resolved)
```

The lifecycle is a finite state machine. An artifact in `#needs-review` can transition to `#done-review` or `#needs-rework` — but never backward to `#needs-implementation`.

### The Six Feeds

| Feed | Tags | Resolving Skill | Purpose |
|------|------|-----------------|---------|
| `§FEED_ALERTS` | `#active-alert`, `#done-alert` | `/alert-raise`, `/alert-resolve` | Active state loaded into every new session |
| `§FEED_REVIEWS` | `#needs-review`, `#done-review`, `#needs-rework` | `/review` | Quality gate for debriefs |
| `§FEED_DOCUMENTATION` | `#needs-documentation`, `#done-documentation` | `/document` | Doc debt tracking for code-changing sessions |
| `§FEED_RESEARCH` | `#needs-research`, `#claimed-research`, `#done-research` | `/research` | Async research via Gemini Deep Research |
| `§FEED_DECISIONS` | `#needs-decision`, `#done-decision` | `/decide` | Deferred decisions that block other work |
| `§FEED_IMPLEMENTATION` | `#needs-implementation`, `#claimed-implementation`, `#done-implementation` | `/implement` | Deferred implementation tasks |

### Dispatch Priority

When multiple tagged items exist, `§TAG_DISPATCH` defines processing order:

| Priority | Tag | Rationale |
|----------|-----|-----------|
| 1 | `#needs-decision` | Decisions unblock everything else |
| 2 | `#needs-research` | Async — queue early so results arrive by the time they are needed |
| 3 | `#needs-implementation` | Core work |
| 4 | `#needs-documentation` | Post-implementation cleanup |
| 5 | `#needs-review` / `#needs-rework` | Final quality gate |

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

**Mechanism**: `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` + `§CMD_AVOID_WASTING_TOKENS`

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

A complete process lifecycle from birth to post-synthesis continuation. Sessions are born (`§CMD_PARSE_PARAMETERS`), activated (`§CMD_MAINTAIN_SESSION_DIR`), executed through phases (`§CMD_UPDATE_PHASE`), debriefed (`§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`), and optionally continued (`§CMD_CONTINUE_OR_CLOSE_SESSION`) or restarted after overflow (`§CMD_SESSION_CONTINUE_AFTER_RESTART`).

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
│    → §CMD_LOAD_AUTHORITY_FILES                     │
│    → §CMD_PARSE_PARAMETERS                         │
│    → §CMD_MAINTAIN_SESSION_DIR                     │
│                                                   │
│  Phase 2: Context Ingestion                       │
│    → §CMD_INGEST_CONTEXT_BEFORE_WORK               │
│                                                   │
│  Phase 3: Planning                                │
│    → §CMD_EXECUTE_INTERROGATION_PROTOCOL           │
│    → §CMD_GENERATE_PLAN_FROM_TEMPLATE              │
│                                                   │
│  Phase N: Synthesis                               │
│    → §CMD_GENERATE_DEBRIEF_USING_TEMPLATE          │
│    → §CMD_REPORT_RESULTING_ARTIFACTS               │
│    → §CMD_REPORT_SESSION_SUMMARY                   │
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

The "STRICT TEMPLATE FIDELITY" constraint in `§CMD_POPULATE_LOADED_TEMPLATE` means debrief and plan templates define the return type of a session. The agent cannot add or remove sections — only populate the predefined structure. This is structural typing: the output must conform to the template's shape.

### State Types (Tag Lifecycles)

The `#needs-X` to `#claimed-X` to `#done-X` progression is a finite state machine with defined transitions. An artifact can only move forward through its lifecycle. This is an enum-based state machine type.

### The Gap

This type system is enforced by LLM compliance, not by a machine checker. At 90%+ compliance the system works in practice, but there is no static analysis that validates "this skill only calls commands that exist" or "this template's fields match the schema's output." The LLM is the type checker.

---

## 9. External Dependencies

The standards system references shell scripts that implement its operations. The behavioral specification (COMMANDS.md) and the implementation (scripts) are separate layers.

| Script | Called By | Purpose |
|--------|-----------|---------|
| `log.sh` | `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` | Append-only log writes |
| `session.sh` | `§CMD_MAINTAIN_SESSION_DIR`, `§CMD_UPDATE_PHASE`, `§CMD_SESSION_CONTINUE_AFTER_RESTART` | Session state management |
| `tag.sh` | `§CMD_TAG_FILE`, `§CMD_UNTAG_FILE`, `§CMD_SWAP_TAG_IN_FILE`, `§CMD_FIND_TAGGED_FILES` | Tag operations |
| `user-info.sh` | `¶INV_INFER_USER_FROM_GDRIVE` | User identity detection |
| `glob.sh` | `¶INV_GLOB_THROUGH_SYMLINKS` | Symlink-aware file globbing |
| `session-search.sh` | `§CMD_INGEST_CONTEXT_BEFORE_WORK` | RAG search over session history |
| `doc-search.sh` | `§CMD_INGEST_CONTEXT_BEFORE_WORK` | RAG search over documentation |
| `research.sh` | `§FEED_RESEARCH` | Gemini Deep Research API |

---

## 10. Key Metrics

| Metric | Value | Source |
|--------|-------|--------|
| Named commands | 32 (COMMANDS.md) + 5 (TAGS.md tag operations) | COMMANDS.md, TAGS.md |
| Named invariants | 23 (shared) + project-specific | INVARIANTS.md |
| Tag feeds | 6 | TAGS.md |
| Architectural layers | 4 | COMMANDS.md section headers |
| Total specification lines | ~1,100 | COMMANDS.md + INVARIANTS.md + TAGS.md |
| Reported compliance rate | 90%+ | Author-reported empirical observation |
| Context cost per session | ~700 lines (COMMANDS.md alone) | Upfront load |

---

## 11. Further Reading

- **Session state machine**: `~/.claude/docs/SESSION_LIFECYCLE.md` — All restart/restore/rehydration scenarios, race conditions, identity fields
- **Multi-agent workspace**: `~/.claude/docs/FLEET.md` — Fleet tmux management, pane coordination, dispatch
- **Overflow protection**: `~/.claude/docs/CONTEXT_GUARDIAN.md` — Context overflow detection, dehydration, restart flow
- **Session skill**: `~/.claude/docs/SESSION_SKILL.md` — Usage guide for `/session` (dehydrate, continue, search, status)
- **Document indexing**: `~/.claude/docs/DOCUMENT_INDEXING.md` — RAG search infrastructure used by `§CMD_INGEST_CONTEXT_BEFORE_WORK`
- **Comparative analysis**: `~/.claude/docs/writeups/2026_02_07_COMMANDS_COMPARATIVE_ANALYSIS.md` — How COMMANDS.md compares to Cursor .cursorrules, system prompts, and JSON schema approaches
- **The source files**: `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, `~/.claude/.directives/TAGS.md`
