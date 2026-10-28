# Sigil & Tag Reference

This document defines the five sigils used across the workflow engine and the semantic tag system for cross-session communication and lifecycle tracking.

---

## Sigil Inventory

Six sigils encode distinct semantic namespaces. Each is greppable and non-colliding.

*   **`§`**
  *   **Name**: Section sign
  *   **Semantics**: **Reference** — cites something defined elsewhere
  *   **Examples**: `§CMD_APPEND_LOG`, `§INV_SIGIL_SEMANTICS`, `§FEED_REVIEWS`

*   **`¶`**
  *   **Name**: Pilcrow
  *   **Semantics**: **Definition** — the place where a noun is declared and specified
  *   **Examples**: `¶CMD_DEHYDRATE`, `¶INV_PHASE_ENFORCEMENT`, `¶FEED_REVIEWS`

*   **`#`**
  *   **Name**: Hash
  *   **Semantics**: **Tag** — lifecycle state markers on work items
  *   **Examples**: `#needs-implementation`, `#done-review`, `#P0`

*   **`@`**
  *   **Name**: At sign
  *   **Semantics**: **Epic/chapter slug** — addressable project work units
  *   **Examples**: `@app/auth-system`, `@packages/estimate/extraction`

*   **`%`**
  *   **Name**: Percent
  *   **Semantics**: **Fleet pane target** — pane identifiers for routing and coordination
  *   **Examples**: `%0`, `%12` (numeric tmux IDs), `%auth:Coordinator`, `%data:Worker-1` (named fleet labels)

### `SRC_` — Engine Data Sources

Engine-internal data sources produced by scripts at runtime. Not commands (CMD_) or rules (INV_) — these are named data sections in engine output.

*   **Format**: `SRC_NAME` (no sigil prefix — SRC_ is self-identifying like CMD_ and INV_)
*   **Semantics**: CMD = "do this", INV = "obey this", SRC = "data from here"
*   **Definition site**: The script that produces the section (e.g., `session.sh` activate)
*   **Reference site**: Docs that describe what the agent will see (e.g., CMD files)
*   **Discovery**: `grep 'SRC_'` finds all references
*   **Current sources**:

*   **`SRC_OPEN_DELEGATIONS`**
  *   Produced by: `engine session activate`
  *   Contains: `#next-*` tagged items in session

*   **`SRC_PRIOR_SESSIONS`**
  *   Produced by: `engine session activate`
  *   Contains: Semantically similar past sessions

*   **`SRC_RELEVANT_DOCS`**
  *   Produced by: `engine session activate`
  *   Contains: Semantically similar project docs

*   **`SRC_RELATED_TICKETS`**
  *   Produced by: `engine session activate`
  *   Contains: Related Linear tickets (thematic search over taskSummary)

*   **`SRC_DELEGATION_TARGETS`**
  *   Produced by: `engine session activate`
  *   Contains: Skill-to-tag mapping table

### `§` and `¶` — Definition vs Reference

See `¶INV_SIGIL_SEMANTICS` in INVARIANTS.md for the authoritative rule.

*   **`¶` (pilcrow)** marks a **definition** — the heading where a command, invariant, feed, or tag section is declared.
*   **`§` (section sign)** marks a **reference** — a citation of something defined elsewhere.
*   **Applies to**: All sigiled nouns — `CMD_`, `INV_`, `FEED_`, `TAG_`, `PTF_`. (`SRC_` uses no sigil prefix — it is self-identifying.)
*   **Discovery**: `grep '¶CMD_'` finds definition sites; `grep '§CMD_'` finds usage sites.

### `PTF_` — Pitfall Identifiers

Named pitfall entries in `.directives/PITFALLS.md` files. Each pitfall gets a stable identifier for cross-referencing.

*   **Format**: `PTF_UPPER_SNAKE_CASE` (e.g., `PTF_HOOK_EXIT_AFTER_ALLOW`, `PTF_BASH32_COMPATIBILITY`)
*   **Semantics**: `¶PTF_NAME` = definition (in the PITFALLS.md file where the pitfall is declared). `§PTF_NAME` = reference (citations from other files).
*   **Definition site**: `.directives/PITFALLS.md` files at any directory level.
*   **Reference site**: Body text in logs, debriefs, other directives. Always backtick-escaped when used as a mention (`` `§PTF_NAME` ``).
*   **Naming**: Derive from the pitfall's trap essence — capture what goes wrong in UPPER_SNAKE_CASE. No scope prefix (file location provides scope).
*   **Discovery**: `grep '¶PTF_'` finds all pitfall definitions; `grep '§PTF_'` finds all references.

### `@` — Epic and Chapter Slugs

Epic and chapter references use path-based semantic slugs mirroring project structure.

*   **Format**: `@scope/slug` (e.g., `@app/auth-system`, `@packages/sdk/types`)
*   **Workspace alignment**: Epic slugs double as workspace directory paths. `@apps/estimate-viewer/extraction` is both an epic reference and a valid `WORKSPACE` value.
*   **Epic folders**: Epic directories coexist alongside source code directories (e.g., `src/`) within package folders. This is an accepted convention — epics are organizational, not code.
*   **Usage**: Chapter headings, dependency graphs, inline references, workspace arguments.
*   **Discovery**: `grep '@app/' docs/` finds all epics in the `app` scope.

### `%` — Fleet Pane Targets

The `%` sigil identifies fleet panes. Two formats exist:

*   **Numeric** (`%N`): Raw tmux pane IDs (e.g., `%0`, `%12`). Used internally by tmux and fleet scripts for pane state tracking.
*   **Named** (`%window:label`): Human-readable fleet pane labels (e.g., `%auth:Coordinator`, `%data:Worker-1`). Used in tags for targeted delegation — `#delegated-implementation %auth:Worker-1` routes work to a specific pane.

**Scope**:
*   Numeric `%N` — tmux internals, `--panes` filters, `@pane_last_coordinated`.
*   Named `%window:label` — tag targeting (`FLEET_TARGETED_CLAIMS`), fleet.yml pane identity, `FLEET_PANE` env var values.
*   `await-next` matches named `%` targets in tags via literal string grep against the pane's `FLEET_PANE` value.
*   **Not a sigil in documents**: Unlike `§`, `¶`, `#`, and `@`, the `%` sigil does not appear in Markdown prose. It exists in tmux state, fleet scripts, and as inline modifiers on delegation tags.

### `FLEET_*` — Capability Env Vars

Five environment variables define a fleet agent's identity and responsibilities. Sourced by `run.sh` from tmux pane options (which are set by `fleet.sh start` from `fleet.yml`). Identity is capability-based, not role-based — a "worker" is `FLEET_CLAIMS` + no `FLEET_MANAGES`; a "coordinator" is `FLEET_CLAIMS` + `FLEET_MANAGES`. No role enum exists (`¶INV_CAPABILITY_OVER_ROLE`).

**Sourcing pipeline**: `fleet.yml` → `fleet.sh start` writes tmux `@pane_*` options → `run.sh` reads tmux options → exports `FLEET_*` env vars → launches Claude.

*   **`FLEET_PANE`**
  *   **Semantics**: Self-identity. The `window:label` of this pane.
  *   **Format**: `window:label` (e.g., `auth:Coordinator`, `data:Worker-1`)
  *   **Set by**: `run.sh` from `@pane_label` + tmux window name
  *   **Used by**: `await-next` tag matching — matches `%window:label` targets in delegation tags

*   **`FLEET_PARENT`**
  *   **Semantics**: Parent pane label for escalation signaling.
  *   **Format**: `window:label` (e.g., `main:Director`)
  *   **Set by**: `run.sh` from `@pane_parent`
  *   **Used by**: Child-wake signal routing — `tmux wait-for -S` to wake parent on state change

*   **`FLEET_CLAIMS`**
  *   **Semantics**: Untargeted skill types this agent accepts.
  *   **Format**: Comma-separated nouns (e.g., `documentation,chores`)
  *   **Set by**: `run.sh` from `@pane_claims`
  *   **Used by**: `await-next` tag scanning — matches `#delegated-{noun}` tags without a `%` target

*   **`FLEET_TARGETED_CLAIMS`**
  *   **Semantics**: Targeted assignments with `%pane-id`.
  *   **Format**: Comma-separated nouns (e.g., `implementation,fix`)
  *   **Set by**: `run.sh` from `@pane_targeted_claims`
  *   **Used by**: `await-next` tag scanning — matches `#delegated-{noun} %{FLEET_PANE}` tags

*   **`FLEET_MANAGES`**
  *   **Semantics**: Child panes this agent monitors.
  *   **Format**: Comma-separated `window:label` values (e.g., `auth:Worker-1,auth:Worker-2`)
  *   **Set by**: `run.sh` from `@pane_manages`
  *   **Used by**: `await-next` child-wake channel — monitors managed panes for state changes

### `#` — Tags

Lifecycle state markers on work items. Full documentation follows in the sections below.

---

## Tag Convention

All tags follow a lifecycle pattern where X is a **noun** that maps to a command **verb**. Two paths exist:

```
Daemon path (async):
  #needs-X → #delegated-X → #claimed-X → #done-X
     │           │              │           │
   staging    approved       worker      resolved
   (human     for daemon     picked up
    review)   dispatch       & working

Immediate path (next-skill):
  #needs-X → #next-X → #claimed-X → #done-X
     │          │           │           │
   staging   claimed     worker      resolved
   (human    for next    picked up
    review)  skill       & working
```

**States**:
*   `#needs-X` — Staging. Work identified, pending human review. Daemon ignores.
*   `#delegated-X` — Approved for daemon dispatch. Daemon may pick up.
*   `#next-X` — Claimed for immediate next-skill execution. Not yet started. Daemon ignores.
*   `#claimed-X` — Worker has picked up and is actively working. Breadcrumbs written.
*   `#done-X` — Resolved. Work complete.

**Actors**:
*   **Requester** (any skill agent): Creates `#needs-X` via `§CMD_HANDLE_INLINE_TAG` or REQUEST file creation.
*   **Requester** (human, during synthesis): Approves `#needs-X` → `#delegated-X` via `§CMD_DISPATCH_APPROVAL`.
*   **Requester** (human, during dispatch): Claims `#needs-X` → `#next-X` via `§CMD_DISPATCH_APPROVAL` "Claim for next skill" option.
*   **Worker** (`/delegation-claim` skill): Claims `#delegated-X` → `#claimed-X` before starting work.
*   **Next skill** (on activation): Auto-claims `#next-X` → `#claimed-X` for matching tag nouns, writes breadcrumbs.
*   **Worker** (target skill): Resolves `#claimed-X` → `#done-X` upon completion.

*   **`/brainstorm`**
  *   **Tag Noun**: brainstorm
  *   **Lifecycle Tags**: `#needs-brainstorm` -> `#delegated-brainstorm` -> `#claimed-brainstorm` -> `#done-brainstorm`

*   **`/research`**
  *   **Tag Noun**: research
  *   **Lifecycle Tags**: `#needs-research` -> `#delegated-research` -> `#claimed-research` -> `#done-research`

*   **`/implement`**
  *   **Tag Noun**: implementation
  *   **Lifecycle Tags**: `#needs-implementation` -> `#delegated-implementation` -> `#claimed-implementation` -> `#done-implementation`

*   **`/chores`**
  *   **Tag Noun**: chores
  *   **Lifecycle Tags**: `#needs-chores` -> `#delegated-chores` -> `#claimed-chores` -> `#done-chores`

*   **`/document`**
  *   **Tag Noun**: documentation
  *   **Lifecycle Tags**: `#needs-documentation` -> `#delegated-documentation` -> `#claimed-documentation` -> `#done-documentation`

*   **`/fix`**
  *   **Tag Noun**: fix
  *   **Lifecycle Tags**: `#needs-fix` -> `#delegated-fix` -> `#claimed-fix` -> `#done-fix`

*   **`/loop`**
  *   **Tag Noun**: loop
  *   **Lifecycle Tags**: `#needs-loop` -> `#delegated-loop` -> `#claimed-loop` -> `#done-loop`

*   **`/review`**
  *   **Tag Noun**: review
  *   **Lifecycle Tags**: `#needs-review` -> `#done-review` (or `#needs-rework`)

**Exceptions**:
*   **Reviews** (`#needs-review` / `#done-review`): 2-state lifecycle. Reviews are processed by `/review` directly, not via daemon dispatch.

**Immediate path**: Any tag noun above (except reviews) also supports the immediate path: `#needs-X` → `#next-X` → `#claimed-X` → `#done-X`. The `#next-X` state is set during `§CMD_DISPATCH_APPROVAL` when the user selects "Claim for next skill." The next skill auto-claims matching `#next-X` items on activation.

---

## Escaping Convention

Tags in body text must be distinguished from actual tags to prevent false positives in discovery (`engine tag find`).

### The Rule
*   **Bare `#tag`** = actual tag. Placed on the Tags line (`**Tags**: #needs-review`) or intentionally inline (per `§CMD_HANDLE_INLINE_TAG`).
*   **Backticked `` `#tag` ``** = reference/discussion. NOT an actual tag. Filtered out by `engine tag find`.
*   **Lifecycle tags**: `#needs-*`, `#delegated-*`, `#next-*`, `#claimed-*`, `#done-*` — all five states follow this escaping convention.

### When Writing (Agents)
*   **Tags line**: Always bare. `**Tags**: #needs-review #needs-documentation`
*   **Inline tags** (intentional): Bare. `### 🚧 Block — Widget API #needs-brainstorm`
*   **References in body/logs/chat**: Always backtick-escape. Write `` `#needs-review` `` not `#needs-review`.

### When Reading (User Input)
*   User types bare `#needs-xxx` → treat as tag action (`§CMD_HANDLE_INLINE_TAG`).
*   User types backticked `` `#needs-xxx` `` → reference only. Preserve backticks. No tag action.

### Examples
```markdown
# Good — Tags line (bare)
**Tags**: #needs-review #needs-documentation

# Good — Intentional inline tag (bare)
### [2026-02-03] 🚧 Block — Auth Flow #needs-brainstorm

# Good — Reference in body text (backtick-escaped)
The `#needs-review` tag is auto-applied at debrief creation.
We swapped `#needs-review` → `#done-review` on 42 files.

# Bad — Unescaped reference (creates noise in engine tag find)
The #needs-review tag is auto-applied at debrief creation.
```

### Behavioral Rule (§CMD_ESCAPE_TAG_REFERENCES)
**Scope**: Applies to ALL agent output — files (logs, debriefs, analysis, plans) AND chat messages.

**Reading User Input**:
*   Bare `#needs-xxx` from user → tag action (execute `§CMD_HANDLE_INLINE_TAG` below).
*   Backticked `` `#needs-xxx` `` from user → reference only. Preserve backticks. No tag action.

**Writing Output**:
*   **Tags line** (`**Tags**: #tag1 #tag2`): Always bare. Never backtick on the Tags line.
*   **Body text / logs / debriefs / chat**: Always backtick-escape tag references. Write `` `#needs-review` `` not `#needs-review`.
*   **Intentional inline tags** (per `§CMD_HANDLE_INLINE_TAG`): Bare. These are actual tags placed at specific locations for discovery.

---

## Tag Discoverability (Escape-by-Default)

All `.md` file types are discoverable by `engine tag find`. Bare inline tags are treated as intentional — the `engine session check` gate (`¶INV_ESCAPE_BY_DEFAULT`) enforces this by requiring agents to promote or acknowledge every bare inline tag before synthesis completes.

### Discovery Rules

*   **Pass 1**
  *   **Scope**: `**Tags**:` line (line 2)
  *   **What it finds**: Structured tags on the Tags line
  *   **Filtering**: None — always authoritative

*   **Pass 2**
  *   **Scope**: Inline body text
  *   **What it finds**: Bare tags in any `.md` file
  *   **Filtering**: Backtick-escaped references filtered out

### Excluded Files (Non-Text)

Only non-text data files are excluded from discovery:

*   **Binary DBs**
  *   **Pattern**: `*.db`, `*.db.bak`
  *   **Excluded From**: Pass 1 + Pass 2
  *   **Rationale**: SQLite files — grep matches encoded text, always false positives

*   **Session state**
  *   **Pattern**: `.state.json`
  *   **Excluded From**: Pass 2
  *   **Rationale**: Serialized JSON — contains tag names as data, not intentional tags

### Check Gate Enforcement (¶INV_ESCAPE_BY_DEFAULT)

During synthesis, `engine session check` scans session artifacts for bare unescaped inline lifecycle tags (`#needs-*`, `#delegated-*`, `#next-*`, `#claimed-*`, `#done-*`). For each bare tag found:

1. **PROMOTE** — Create a REQUEST file from the skill's template + backtick-escape the inline tag
2. **ACKNOWLEDGE** — Mark as intentional (tag stays bare, agent opts in)

The check gate blocks synthesis until every inline tag is addressed. This replaces the previous file-type blacklist approach — instead of hiding tags, agents are required to handle them explicitly.

### Key Principle

**Tags-line entries are always authoritative.** Inline bare tags are also authoritative *after* the check gate passes — every surviving bare tag was either placed intentionally (on the Tags line or as an inline work item) or explicitly acknowledged by the agent.

---

## Tag Operations

Each tag operation is its own command file under `commands/`, so a `§CMD_` citation delivers it with the skill that cites it:

*   `§CMD_FIND_TAGGED_FILES` — `commands/CMD_FIND_TAGGED_FILES.md`
*   `§CMD_TAG_FILE` — `commands/CMD_TAG_FILE.md`
*   `§CMD_UNTAG_FILE` — `commands/CMD_UNTAG_FILE.md`
*   `§CMD_SWAP_TAG_IN_FILE` — `commands/CMD_SWAP_TAG_IN_FILE.md`
*   `§CMD_HANDLE_INLINE_TAG` — `commands/CMD_HANDLE_INLINE_TAG.md`

---

**Note**: All feeds below use `sessions/` as their location. When `WORKSPACE` is set, this resolves to `$WORKSPACE/sessions/`. Tag discovery (`engine tag find`) searches both workspace and global sessions directories.

## ¶FEED_REVIEWS
*   **Tags**: `#needs-review`, `#done-review`, `#needs-rework`
*   **Location**: `sessions/`
*   **Lifecycle** (2-state — no delegation dispatch):
    *   `#needs-review` — Unvalidated. Auto-applied at debrief creation by `§CMD_GENERATE_DEBRIEF`.
    *   `#done-review` — User-approved via `/review`. No further action needed.
    *   `#needs-rework` — User-rejected via `/review`. Contains `## Rework Notes` with rejection context. Re-presented on next review run.

*   **Review Command**: `/review` discovers all `#needs-review` and `#needs-rework` files, performs cross-session analysis, and walks the user through structured approval.
*   **Note**: Reviews use a 2-state lifecycle (no `#delegated-review` or `#claimed-review`) because `/review` is always invoked directly by the user, not via daemon dispatch.

## ¶FEED_GENERIC
*   **Applies to**: documentation, research, brainstorm, chores, fix, loop, implementation, direct
*   **Tags**: `#needs-{NOUN}`, `#delegated-{NOUN}`, `#next-{NOUN}`, `#claimed-{NOUN}`, `#done-{NOUN}`
*   **Location**: `sessions/`
*   **Lifecycle** (5-state, two paths):
    *   `#needs-{NOUN}` — Staging. Work identified, pending human review via `§CMD_DISPATCH_APPROVAL`.
    *   `#delegated-{NOUN}` — Dispatch-approved. Human approved. Daemon may now pick up.
    *   `#next-{NOUN}` — Claimed for immediate next-skill execution. Daemon ignores. Auto-claimed by matching skill on activation.
    *   `#claimed-{NOUN}` — In-flight. Worker swapped tag before starting work.
    *   `#done-{NOUN}` — Complete. Swapped by the resolving skill after verification.
*   **Application**: Tags can be applied inline within work artifacts or on the `**Tags**:` line of debriefs. Discovered via `engine tag find`.
*   **Independence**: Each feed is independent from all other feeds. A file may carry multiple `#needs-*` tags simultaneously.







## §TAG_DISPATCH

Defined in `tags/TAG_DISPATCH.md`; a bare `§TAG_DISPATCH` citation delivers it.

## ¶TAG_WEIGHTS
Weight tags express urgency and effort for work items. They are optional metadata — absence means default priority (P2) and unknown effort.

### Priority Tags
*   **`#P0`**
  *   Meaning: Critical
  *   Scheduling: Blocks everything. Process immediately.

*   **`#P1`**
  *   Meaning: Important
  *   Scheduling: Should be done soon. Higher queue priority.

*   **`#P2`**
  *   Meaning: Normal
  *   Scheduling: Default priority. FIFO within priority class.

### Effort Tags
*   **`#S`**
  *   Meaning: Small
  *   Time Estimate: < 30 minutes

*   **`#M`**
  *   Meaning: Medium
  *   Time Estimate: 30 min - 2 hours

*   **`#L`**
  *   Meaning: Large
  *   Time Estimate: > 2 hours

### Usage
*   Tags are separate and combinable: `#needs-implementation #P1 #M`
*   Scheduling: Priority-first (P0 > P1 > P2), FIFO within same priority
*   Effort is informational for human planning — does not affect daemon scheduling
*   Discovery: `engine tag find '#P0'` finds all critical items

### Examples
```markdown
# High-priority medium-effort implementation task
**Tags**: #needs-implementation #P0 #M

# Normal research request with unknown effort
**Tags**: #needs-research

# Low-priority small documentation task
**Tags**: #needs-documentation #P2 #S
```

---

## Item IDs (`/` Convention)

Hierarchical identifiers for addressable items across the protocol — findings, plan steps, questions, walk-through items, discoveries, and decision tree entries. Every item gets a stable ID at creation time, persisted in both artifacts and chat.

### Format

```
{phase-path}/{item}
```

*   **Phase path** (before `/`): Dotted segments mirroring the skill's phase hierarchy. Uses the same numbering as `engine session phase` labels.
*   **Item number** (after `/`): Sequential counter within that structural location. Starts at 1.
*   **Delimiter**: `/` separates structural location from leaf item. The `.` separates structural levels.

### Examples

*   `1.3/2` — Phase 1, Round 3, Question 2
*   `3.A.2/3` — Phase 3 Branch A, Plan Section 2, Step 3
*   `4.2.3/2` — Phase 4, Sub-phase 2 (Debrief), Section 3, Item 2
*   `0.1/4` — Phase 0, Round 1, Question 4

### Cross-Session References

Prefix with a session slug (UPPER_SNAKE derived from session topic) and `/`:

```
{SESSION_SLUG}/{phase-path}/{item}
```

*   `DOC_AUDIT/4.2.3/2` — Documentation Audit session, Phase 4.2, Section 3, Item 2
*   `ITEM_REF/2.3/1` — Item Referencing session, Phase 2, Round 3, Question 1

### Domain Mapping

How the convention applies to each command's item domain:

*   **Interrogation (`§CMD_INTERROGATE`)** — `{phase}.{round}/{question}`. Example: Phase 1, Round 3, Question 2 = `1.3/2`.
*   **Plan steps (`§CMD_GENERATE_PLAN`)** — `{skill-phase}.{plan-section}/{step}`. Example: Build Loop (3.A), Plan Section 2, Step 3 = `3.A.2/3`.
*   **Walk-through items (`§CMD_WALK_THROUGH_RESULTS`)** — `{phase}.{sub-phase}.{section}/{item}`. Example: Synthesis (4), Debrief (4.2), Section 3, Item 2 = `4.2.3/2`.
*   **Side discoveries (`§CMD_CAPTURE_SIDE_DISCOVERIES`)** — `{phase}/{discovery}`. Example: Build Loop discovery 2 = `3.A/2`.
*   **Dispatch items (`§CMD_DISPATCH_APPROVAL`)** — `{phase}/{file}`. Example: Pipeline file 3 = `4.3/3`.
*   **Decision tree (`§CMD_DECISION_TREE`)** — Inherits the caller's ID scheme. Batch headers use the source item's ID.
*   **Tag triage (`§CMD_TAG_TRIAGE`)** — Same as walk-through (inherits from caller).

### Rules

*   **Stability**: IDs are permanent. When items are filtered or reordered (e.g., walk-through shows 5 of 10 findings), IDs reflect the original artifact position. Gaps are expected and acceptable.
*   **Full IDs always**: No shorthand. Always write the full `{phase-path}/{item}` form, even within the same phase.
*   **Assigned at creation**: The agent writes the ID into the artifact (log entry, plan step, debrief section) when the item is first created. IDs are not retroactively assigned at presentation time.
*   **Chat + artifacts**: IDs appear in `AskUserQuestion` headers, context blocks, and are persisted in log entries, plan files, and debrief sections.
*   **AskUserQuestion headers**: Use the item ID as the `header` field. Example: `header: "1.3/2"` instead of `header: "Q2"`.

### Artifact Format

In written artifacts, prefix items with their ID in bold:

```markdown
## Phase 1: Interrogation
*   **1.1/1**: What is the scope boundary for this feature?
*   **1.1/2**: Are there existing patterns we should follow?
*   **1.1/3**: What's the testing strategy?

## Build Plan — Phase 3.A
*   [ ] **3.A.1/1**: Create the schema types
*   [ ] **3.A.1/2**: Write failing test for parser
*   [ ] **3.A.2/1**: Implement parser logic
```

---

## Formatting Conventions (`FMT_*`)

Three named list density levels that replace markdown tables. Referenced via `§FMT_*` when used, `¶FMT_*` at their definition here.

### ¶FMT_LIGHT_LIST

**When to use**: Simple 1-2 field entries. Lookup tables, glossaries, short mappings.

**Rules**: No blank lines between items. Bold key, dash separator, value on same line.

```markdown
*   **`session.sh`** — Session lifecycle (activate, phase, deactivate, restart, find)
*   **`log.sh`** — Append-only file writing with timestamp injection
*   **`tag.sh`** — Tag management (add, remove, swap, find)
```

### ¶FMT_MEDIUM_LIST

**When to use**: 3-4 field entries. Registry entries, option menus, hook descriptions.

**Rules**: Blank line between items. Bold key as title line, indented fields below (2-space indent).

```markdown
*   **brainstorm**
  *   Resolving skill: `/brainstorm`
  *   Mode: interactive
  *   Priority: 1 (exploration unblocks decisions)

*   **research**
  *   Resolving skill: `/research`
  *   Mode: async (Gemini)
  *   Priority: 2 (queue early)

*   **fix**
  *   Resolving skill: `/fix`
  *   Mode: interactive/agent
  *   Priority: 3 (bugs block progress)
```

### ¶FMT_HEAVY_LIST

**When to use**: 5+ field entries or complex metadata. Full registry records, detailed subsystem docs, multi-field state descriptions.

**Rules**: Blank line between items. Bold key as title line, indented key-value pairs below (2-space indent). Use bold for sub-keys.

```markdown
*   **Sessions**
  *   **Entry Point**: `engine session`
  *   **What It Does**: Activate/deactivate sessions, phase tracking, heartbeat, context overflow recovery
  *   **Key Files**: `session.sh`, `.state.json`
  *   **Dependencies**: `lib.sh`, `json-schema-validate/`
  *   **Notes**: Core subsystem — all other subsystems depend on session state

*   **Tags**
  *   **Entry Point**: `engine tag`
  *   **What It Does**: Tag lifecycle management — add, remove, swap, find across session artifacts
  *   **Key Files**: `tag.sh`
  *   **Dependencies**: `lib.sh`
  *   **Notes**: Stateless coordination primitive for multi-agent work
```

### Density Selection Heuristic

*   **1-2 fields per item** → `§FMT_LIGHT_LIST` (no blank lines, inline values)
*   **3-4 fields per item** → `§FMT_MEDIUM_LIST` (blank lines between items, indented fields)
*   **5+ fields per item** → `§FMT_HEAVY_LIST` (blank lines between items, bold sub-keys)

### §FMT_CONTEXT_BLOCK

Defined in `formats/FMT_CONTEXT_BLOCK.md`; a bare `§FMT_CONTEXT_BLOCK` citation delivers it.

### §FMT_ANSWER_GRADATION

Defined in `formats/FMT_ANSWER_GRADATION.md`; a bare `§FMT_ANSWER_GRADATION` citation delivers it.

### §FMT_FILE_LINK

Defined in `formats/FMT_FILE_LINK.md`; a bare `§FMT_FILE_LINK` citation delivers it.

### §FMT_TICKET_LINK

Defined in `formats/FMT_TICKET_LINK.md`; a bare `§FMT_TICKET_LINK` citation delivers it.

### §FMT_TICKET_COMMENT_LINK

Defined in `formats/FMT_TICKET_COMMENT_LINK.md`; a bare `§FMT_TICKET_COMMENT_LINK` citation delivers it.

### §FMT_DECISION_CARD

Defined in `formats/FMT_DECISION_CARD.md`; a bare `§FMT_DECISION_CARD` citation delivers it.
