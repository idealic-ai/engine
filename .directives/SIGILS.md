# Sigil & Tag Reference

This document defines the five sigils used across the workflow engine and the semantic tag system for cross-session communication and lifecycle tracking.

---

## Sigil Inventory

Six sigils encode distinct semantic namespaces. Each is greppable and non-colliding.

*   **`§`**
  *   **Name**: Section sign
  *   **Semantics**: **Reference** — cites something defined elsewhere
  *   **Examples**: `§CMD_APPEND_LOG`, `§INV_SIGIL_SEMANTICS`, `§FEED_ALERTS`

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

*   **`SRC_ACTIVE_ALERTS`**
  *   Produced by: `engine session activate`
  *   Contains: Active alert files (thematic search)

*   **`SRC_OPEN_DELEGATIONS`**
  *   Produced by: `engine session activate`
  *   Contains: `#next-*` tagged items in session

*   **`SRC_PRIOR_SESSIONS`**
  *   Produced by: `engine session activate`
  *   Contains: Semantically similar past sessions

*   **`SRC_RELEVANT_DOCS`**
  *   Produced by: `engine session activate`
  *   Contains: Semantically similar project docs

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

*   **`§CMD_MANAGE_ALERTS`**
  *   **Tag Noun**: alert
  *   **Lifecycle Tags**: `#active-alert` -> `#done-alert`

**Exceptions**:
*   **Alerts** (`#active-alert` / `#done-alert`): 2-state lifecycle. Alerts use different semantics ("ongoing situation" vs "resolved"), not the delegation lifecycle.
*   **Reviews** (`#needs-review` / `#done-review`): 2-state lifecycle. Reviews are processed by `/review` directly, not via daemon dispatch.

**Immediate path**: Any tag noun above (except alerts and reviews) also supports the immediate path: `#needs-X` → `#next-X` → `#claimed-X` → `#done-X`. The `#next-X` state is set during `§CMD_DISPATCH_APPROVAL` when the user selects "Claim for next skill." The next skill auto-claims matching `#next-X` items on activation.

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

### ¶CMD_FIND_TAGGED_FILES
**Definition**: To locate files carrying specific semantic tags (on the Tags line or as intentional inline tags), filtering out backtick-escaped references.
**Algorithm**:
1.  **Identify**: Determine the target tag (e.g., `#active-alert`).
2.  **Execute**:
    ```bash
    engine tag find '#tag-name'
    ```
    *   Searches `sessions/` by default. Pass a path argument to override.
    *   Two-pass search: Tags line (high precision) + inline body (backtick-filtered).
    *   Add `--context` for line numbers and surrounding text (useful before `remove --inline` or `swap --inline`).
3.  **Output**: A list of file paths (one per line) that carry the tag. Each path should be a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant).
4.  **Goal**: Identify active alerts, pending reviews, or other tagged artifacts.

### ¶CMD_TAG_FILE
**Definition**: To add a semantic tag to a Markdown file.
**Constraint**: Tags live on a dedicated `**Tags**:` line immediately after the H1 heading (line 2). Never on the H1 itself.
**Format**: `**Tags**: #tag1 #tag2`
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag add "$FILE" '#tag-name'
    ```
    *   Ensures `**Tags**:` line exists after H1, then appends tag idempotently.
    *   Safe to run multiple times.

### ¶CMD_UNTAG_FILE
**Definition**: To remove a semantic tag from a Markdown file.
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag remove "$FILE" '#tag-name'
    ```

### ¶CMD_SWAP_TAG_IN_FILE
**Definition**: To atomically replace one tag with another (e.g., `#needs-review` → `#done-review`).
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag swap "$FILE" '#old-tag' '#new-tag'
    ```
    *   Supports comma-separated old tags for multi-swap: `'#tag-a,#tag-b'`

### ¶CMD_HANDLE_INLINE_TAG
**Definition**: When a user types `#needs-xxx` (e.g., `#needs-brainstorm`, `#needs-research`, `#needs-documentation`) in response to a question or during discussion, the agent must capture it as an inline tag in the active artifact.

**Rule**: The user typing `#needs-xxx` means: "I can't answer this now. Tag it so it can be addressed later by the appropriate skill (e.g., `/brainstorm`, `/research`, `/document`)."

**Algorithm**:
1.  **Detect**: The user's response contains a `#needs-xxx` tag.
2.  **Tag the Source**: Add the tag **inline** in the relevant location of the **active work artifact** (the log entry, plan section, or debrief section currently being discussed). Place it naturally — next to the heading, in the paragraph, or as a bold marker:
    *   *In a log entry*: `### [timestamp] 🚧 Block — [Topic] #needs-brainstorm`
    *   *In a plan step*: `*   [ ] **Step 3**: [Action] #needs-brainstorm`
    *   *In a debrief section*: Add to the relevant paragraph or as a bullet.
3.  **Log to DIALOGUE.md**: Execute `§CMD_LOG_INTERACTION` recording the user's deferral (the question asked, the `#needs-xxx` response, and the context).
4.  **Do NOT Duplicate**: The tag should appear in **exactly one** work artifact (the log OR the debrief section — whichever is active when the user defers). Do NOT propagate the tag from DIALOGUE.md into the debrief automatically. If the debrief has a "Pending Decisions" or "Open Questions" section, list it there as a **reference** (one-liner with source path), not a full copy.
5.  **Tag the File**: If the work artifact is a debrief (final output), also add the `#needs-xxx` tag to the file's `**Tags**:` line via `§CMD_TAG_FILE`.
6.  **Tag Reactivity** (`¶INV_WALKTHROUGH_TAGS_ARE_PASSIVE`): Determine the current context and react accordingly:
    *   **During `§CMD_WALK_THROUGH_RESULTS`**: Tags are **passive**. The walkthrough protocol handles triage. Do NOT offer `/delegation-create` — the tag is protocol-placed, not a user-initiated deferral. Record and move on.
    *   **All other contexts** (interrogation, QnA, ad-hoc chat, side discovery): Tags are **reactive**. After recording the tag, invoke `/delegation-create` via the Skill tool: `Skill(skill: "delegation-create", args: "[tag] [context summary]")`. The `/delegation-create` skill handles mode selection (async/blocking/silent) and REQUEST filing. The user can always decline via "Other" in the delegate prompt.
7.  **Continue**: Resume the session. Do not halt or change phases — the deferral is recorded (and optionally delegated), move on.

**Constraint**: **Once Only**. Each deferred item appears as an inline tag in ONE place. The DIALOGUE.md captures the verbatim exchange. The debrief may list it in a "Pending" section as a pointer. Never three copies.

---

**Note**: All feeds below use `sessions/` as their location. When `WORKSPACE` is set, this resolves to `$WORKSPACE/sessions/`. Tag discovery (`engine tag find`) searches both workspace and global sessions directories.

## ¶FEED_ALERTS
*   **Tags**: `#active-alert`, `#done-alert`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#active-alert` — Active. Created by `§CMD_MANAGE_ALERTS` during synthesis. Any document with this tag is considered "Active" and must be loaded into the context of every new agent session (unless explicitly reset).
    *   `#done-alert` — Resolved. Swapped by `§CMD_MANAGE_ALERTS` after the work is verified and aligned.

## ¶FEED_REVIEWS
*   **Tags**: `#needs-review`, `#done-review`, `#needs-rework`
*   **Location**: `sessions/`
*   **Lifecycle** (2-state — no delegation dispatch):
    *   `#needs-review` — Unvalidated. Auto-applied at debrief creation by `§CMD_GENERATE_DEBRIEF`.
    *   `#done-review` — User-approved via `/review`. No further action needed.
    *   `#needs-rework` — User-rejected via `/review`. Contains `## Rework Notes` with rejection context. Re-presented on next review run.

*   **Independence**: This feed is fully independent from `§FEED_ALERTS`. The two systems are parallel — a file (e.g., `ALERT_RAISE.md`) may carry both `#active-alert` and `#needs-review` simultaneously, resolved by different commands.
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







## ¶TAG_DISPATCH
*   **Purpose**: Maps `#needs-*` tags to their resolving skills and defines daemon dispatch behavior. Used by `/delegation-claim`, daemon, and `/find-tagged` to route deferred work to the correct skill.
*   **Rule**: Every `#needs-X` tag maps to exactly one skill `/X`. See `¶INV_1_TO_1_TAG_SKILL`.
*   **Daemon monitors**: `#delegated-*` only (NOT `#needs-*` or `#next-*`). See `¶INV_NEEDS_IS_STAGING`, `¶INV_NEXT_IS_IMMEDIATE`.
*   **Registry**:

*   **brainstorm**
  *   **Resolving Skill**: `/brainstorm`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 1 (exploration unblocks decisions)

*   **direct**
  *   **Resolving Skill**: `/direct`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 1.5 (vision unblocks coordinator)

*   **research**
  *   **Resolving Skill**: `/research`
  *   **Mode**: async (Gemini)
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 2 (queue early)

*   **fix**
  *   **Resolving Skill**: `/fix`
  *   **Mode**: interactive/agent
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 3 (bugs block progress)

*   **implementation**
  *   **Resolving Skill**: `/implement`
  *   **Mode**: interactive/agent
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 4

*   **loop**
  *   **Resolving Skill**: `/loop`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 4.5 (iteration workloads)

*   **chores**
  *   **Resolving Skill**: `/chores`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 5 (quick wins, filler)

*   **documentation**
  *   **Resolving Skill**: `/document`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 6

*   **review**
  *   **Resolving Skill**: `/review`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: No (user-invoked only)
  *   **Priority**: 7

*   **rework**
  *   **Resolving Skill**: `/review`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: No (user-invoked only)
  *   **Priority**: 7

*   **Extensibility**: To add a new dispatchable tag, add a row to this table and create the corresponding `§FEED_*` section above. The tag noun MUST match the skill name (`¶INV_1_TO_1_TAG_SKILL`).
*   **Priority**: Resolves in priority order (1 first). Brainstorming unblocks decisions; research is async so queue early; fixes unblock progress; implementation is the main work; chores fill gaps; documentation after code; review last.
*   **Daemon-Dispatchable**: Only tags marked "Yes" will be picked up by the daemon when in `#delegated-*` state. Tags marked "No" are resolved manually by the user.
*   **Immediate path**: Any daemon-dispatchable tag also supports `#next-X` (immediate next-skill execution). `#next-X` items are auto-claimed by the matching skill on activation. `/delegation-review` surfaces stale `#next-X` items for re-routing.

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

### ¶FMT_CONTEXT_BLOCK

**When to use**: The complete context that goes **inside** an `AskUserQuestion` question body — what the user needs to decide, framed so the body stands alone. Consumed by `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` (every question), `§CMD_INTERROGATE` (each round's body), `§CMD_WALK_THROUGH_RESULTS` (per-item body).

**Rules**: The context lives **in the question body**, NOT in a separate chat block rendered before it — that duality (context up top, terse options below) is exactly what `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` kills. Frame the decision completely: what's being decided, why it matters, whatever's needed to choose in-place. Substantive, not stubs. **No length cap** — AskUserQuestion bodies render long content fine; the old "exactly 2 paragraphs" existed only for a removed length limit. Two well-framed paragraphs is a good default; a rich decision uses a full `§FMT_DECISION_CARD` as the body.

```markdown
[in the AskUserQuestion `question` field:]
**[Context]**: what the user needs to know — background / recap / scope.
**[The decision]**: the specific choice with concrete details. The user decides from THIS, in place.
```

**Anti-pattern**: a separate context block in chat followed by a terse `AskUserQuestion` — the user then has to map options back to context above. Put the context in the body.

### ¶FMT_ANSWER_GRADATION

**When to use**: compact, at-a-glance gradation tags leading an `AskUserQuestion` **option label** — so the user reads risk / data-certainty / effort / recommendation right on the choice. Generalizes the old "(Recommended)" suffix. A **closed** set (like the `§CMD_FLOWGRAPH` glyphs — defined once, never freehand). Show **only the 1–2 dimensions that actually differentiate this answer set**; omit any dimension uniform across all options.

**The set** (fixed row order, packed — no spaces inside the cluster, one space before the label):
*   **risk** — `△` low · `◭` med · `▲` high  *(triangle = caution)*
*   **confidence** — `○` thin · `◑` med · `●` solid  *(certainty in the GATHERED DATA behind the call — "how much more analysis to verify"; fullness = evidence completeness)*
*   **effort** — `Ⓢ` small · `Ⓜ` med · `Ⓛ` large
*   **★** — the agent's recommendation, **last** in the row, ≤1 per set
*   *(rare optional)* `‡` — one-way / irreversible; appended only when genuinely relevant, not part of the default row

**Row order**: `risk · confidence · effort · ★` → e.g. `△●Ⓢ★ `, then the label text.

```markdown
[AskUserQuestion option labels:]
"△●Ⓢ★ Cherry-pick onto a fresh branch"    (low risk · solid data · small · recommended)
"▲◑Ⓢ Push the mixed branch as-is"          (high risk · medium data · small)
"◭○Ⓜ Rebase after a spike"                 (med risk · thin data—verify first · med effort)
```

**Anti-pattern**: tagging every dimension even when uniform across options (soup); freehand emoji/glyphs outside the closed set; putting the tags in the option `description` instead of leading the `label`.

### ¶FMT_FILE_LINK

**When to use**: EVERY reference to a file/artifact — in chat or in a `.md` artifact — renders as a **labeled clickable link**, never a bare URL and never a dead relative path. Labeled links now render clickable in-terminal (the old bare-URL mandate existed only because they didn't).

**Rules** (smart-by-type):
*   **Editable** (code, `.md`, `.ts`/`.js`, `.json`, session artifacts, configs) → `[<label>](cursor://file/<abs-path>)` — opens in the editor.
*   **Viewable** (images `.png`/`.jpg`, `.pdf`, `.html`) → `[<label>](file:///<abs-path>)` — opens in the default viewer (Preview, browser). (`file://` opens Finder for editable files — so only use it for view-only kinds.)
*   **Label** = the basename or a short description (`[EDIT_SKILL.md]`, `[the debrief]`).
*   **Absolute path always** (resolve `~`/relative). Never a bare `cursor://…` / `file://…` blob in the prose.

```markdown
See [EDIT_SKILL.md](cursor://file/Users/me/proj/sessions/X/EDIT_SKILL.md).
Overlay: [overlay-3.png](file:///Users/me/proj/out/overlay-3.png).
```

**Anti-pattern**: a bare `cursor://file/…` URL dumped in text; a non-clickable relative path (`sessions/X/foo.md`); `file://` for a code file (opens Finder, not the editor).

### ¶FMT_DECISION_CARD

**When to use**: The richer successor to `§FMT_CONTEXT_BLOCK` for disclosing the agent's own judgment per item. Used by `§CMD_ELICIT` (and, via it, `§CMD_WALK_THROUGH_RESULTS` results mode) — front-loading what the user reliably asks for next so they judge from context instead of interrogating. **The fields are generalized off the fix-shape** so one card fits a proposed **fix**, a raw **idea**, or a neutral **observation** — not only findings-to-fix. One card per item.

**Rendering as the question body (plain text — NO markdown)**: the card renders **as the `AskUserQuestion` question body** (via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`), not as separate chat text before a terse question. **AskUserQuestion bodies do not render markdown** — `**bold**`, `` `code` ``, `####` show literally. So in the body use **plain text with whitespace-aligned columns**: field name on the left (padded to a consistent width), value to its right; multi-line values indent under the value column. Unicode renders fine (`·`, the `§FMT_ANSWER_GRADATION` glyphs `△●Ⓢ★`). The markdown card layout above is for **chat** rendering only.

**Drop the Options field in the body** — the `AskUserQuestion`'s **answers ARE the options**, so re-listing them in the body is redundant. The body carries only the *analysis*: What's-at-stake, How-to-verify, My-lean, Confidence, plus any context/subtitle (`itemId · Title`, `scope · △●Ⓜ`). Each **answer** is a disposition whose label leads with `§FMT_ANSWER_GRADATION` (`△●Ⓢ★ short action`) and whose **description carries that option's trade-off**; **My lean** becomes the `★` on the recommended answer. The user reads the analysis and picks in one place — no scroll, no redundancy.

```
[3.2/1]  Update the sticky PR comment on failing tests
scope: comment-builder · △ low · ● solid · Ⓜ med

At stake   failing tests are invisible in the PR summary — reviewers miss them
Verify     grep the comment builder for the failures block
My lean    add a failures section — one comment stays clean · cost: builder branches
Confidence high — verified against the real comment output, not a fixture
```
*(answers, carrying the options: `△●Ⓢ★ Add a failures section` · `◭●Ⓜ Separate comment per failure` · `△●Ⓢ Leave the summary as-is`)*

**Rules**: A named-list card (never a table — `¶INV_LISTS_INSTEAD_OF_TABLES`). Card **depth scales with the triage bucket**: `FYI` = a one-liner (what + why-no-action); `I've-got-this` = a one-line what + why (never a bare count); `Your-call` = the full card, every required field below. On a `Your-call`, order the body **options-first-neutral, then the defeasible lean** (`§CMD_ELICIT` anti-anchor rule) — the POV lives in the lean, never in a separate recommendation-first field.

**Layout**: each `Your-call` card leads with a markdown **heading** — `#### [itemId] · [Title]` (or larger when a card stands alone) — immediately followed by a **subtitle line** carrying `file:line`/scope + confidence + any *optional* fields. Then the body fields, each on its own line. **No blank line after a heading; one blank line before it** (blocks separate above, not below — keeps cards tight).

**Required fields** (a `Your-call`):
*   **What's at stake** — the concrete consequence if left unaddressed: who/what it hits, how widely (a fix's failure, an idea's missed upside, an observation's implication).
*   **Options** — 2–4 framed trade-offs: *A → risk X; B → risk Y, gain Z*; **always the honest do-nothing / defer** where it's real. Neutral, before the lean.
*   **Complexity / cost to act** — does acting add surface / muddy the design / bloat the build? (orthogonal to correctness).
*   **How to verify / validate** — the low-cost check that confirms or *sizes* it (a read-only count, a one-line repro, a grep, a quick spike).
*   **Confidence** — the agent's honest confidence in its own read (load-bearing — gates the triage). Goes on the subtitle line.
*   **My lean** — the agent's defeasible POV, *after* the options: what it recommends + its paired **trade-off / cost** + the strongest case against it (the anti-anchor rule; the POV lives here, never in a recommendation-first field).
*   **Engagement** — the advisory triage verdict: `I've-got-this` | `Your-call` | `FYI`.
*   **Why you'd want to understand this** — one line, on `Your-call`s (folds into the Engagement line): a one-way door? a load-bearing assumption? a domain rule?

**Optional fields** — render **only when they carry signal** (keep the core lean): **effort** (rough size ~S/M/L or time), **blast-radius / scope** (how many affected — rows / callers / users), **reversibility** (one-way door?), **depends-on / blocks** (sequencing vs. other items). When present, ride them on the **subtitle line** next to `file:line`, not as separate body blocks.

```markdown
#### [itemId] · [Title]
`[file:line or scope]` — confidence **[high|med|low]** · effort **[~S/M/L]** · blast-radius **[scope]**

**What's at stake**
[concrete consequence — who/what, how widely]

**Options**
- **A** — [risk X]
- **B** — [risk Y, gain Z]
- **C** — do nothing → [what stays unaddressed]

**Complexity / cost to act**
[low | real — adds/muddies X]

**How to verify**
[the low-cost confirm/size check]

**My lean**
**B**, because […] — cost: […] — strongest counter: […]

**Engagement**
Your-call — [one line: why it's worth your attention]
```

**Anti-pattern**: a neutral dump with no lean; a recommendation-first framing that anchors before the options; a lean without its paired trade-off; a bare count for the `I've-got-this` / `FYI` buckets; a full expensive card spent on an `FYI`; **a blank line jammed after every heading** (blank before headings, not after).

