# Tag System Reference (The Global Feeds)

This document defines the semantic tag system used across sessions for cross-session communication and lifecycle tracking.

## Tag Convention

All tags follow the `#needs-X` / `#active-X` / `#done-X` lifecycle pattern where X is a **noun** that maps to a command **verb**:

| Command (Verb) | Tag Noun | Lifecycle Tags |
|----------------|----------|----------------|
| `/brainstorm` | brainstorm | `#needs-brainstorm` -> `#active-brainstorm` -> `#done-brainstorm` |
| `/research` | research | `#needs-research` -> `#active-research` -> `#done-research` |
| `/implement` | implementation | `#needs-implementation` -> `#active-implementation` -> `#done-implementation` |
| `/chores` | chores | `#needs-chores` -> `#active-chores` -> `#done-chores` |
| `/document` | documentation | `#needs-documentation` -> `#done-documentation` |
| `/fix` | fix | `#needs-fix` -> `#active-fix` -> `#done-fix` |
| `/review` | review | `#needs-review` -> `#done-review` (or `#needs-rework`) |
| `§CMD_MANAGE_ALERTS` | alert | `#active-alert` -> `#done-alert` |

---

## Escaping Convention

Tags in body text must be distinguished from actual tags to prevent false positives in discovery (`tag.sh find`).

### The Rule
*   **Bare `#tag`** = actual tag. Placed on the Tags line (`**Tags**: #needs-review`) or intentionally inline (per `§CMD_HANDLE_INLINE_TAG`).
*   **Backticked `` `#tag` ``** = reference/discussion. NOT an actual tag. Filtered out by `tag.sh find`.

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

# Bad — Unescaped reference (creates noise in tag.sh find)
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

All `.md` file types are discoverable by `tag.sh find`. Bare inline tags are treated as intentional — the `session.sh check` gate (`¶INV_ESCAPE_BY_DEFAULT`) enforces this by requiring agents to promote or acknowledge every bare inline tag before synthesis completes.

### Discovery Rules

| Pass | Scope | What it finds | Filtering |
|------|-------|---------------|-----------|
| **Pass 1** | `**Tags**:` line (line 2) | Structured tags on the Tags line | None — always authoritative |
| **Pass 2** | Inline body text | Bare tags in any `.md` file | Backtick-escaped references filtered out |

### Excluded Files (Non-Text)

Only non-text data files are excluded from discovery:

| File Type | Pattern | Excluded From | Rationale |
|-----------|---------|---------------|-----------|
| **Binary DBs** | `*.db`, `*.db.bak` | Pass 1 + Pass 2 | SQLite files — grep matches encoded text, always false positives |
| **Session state** | `.state.json` | Pass 2 | Serialized JSON — contains tag names as data, not intentional tags |

### Check Gate Enforcement (¶INV_ESCAPE_BY_DEFAULT)

During synthesis, `session.sh check` scans session artifacts for bare unescaped inline lifecycle tags (`#needs-*`, `#active-*`, `#done-*`). For each bare tag found:

1. **PROMOTE** — Create a REQUEST file from the skill's template + backtick-escape the inline tag
2. **ACKNOWLEDGE** — Mark as intentional (tag stays bare, agent opts in)

The check gate blocks synthesis until every inline tag is addressed. This replaces the previous file-type blacklist approach — instead of hiding tags, agents are required to handle them explicitly.

### Key Principle

**Tags-line entries are always authoritative.** Inline bare tags are also authoritative *after* the check gate passes — every surviving bare tag was either placed intentionally (on the Tags line or as an inline work item) or explicitly acknowledged by the agent.

---

## Tag Operations

### §CMD_FIND_TAGGED_FILES
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

### §CMD_TAG_FILE
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

### §CMD_UNTAG_FILE
**Definition**: To remove a semantic tag from a Markdown file.
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag remove "$FILE" '#tag-name'
    ```

### §CMD_SWAP_TAG_IN_FILE
**Definition**: To atomically replace one tag with another (e.g., `#needs-review` → `#done-review`).
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag swap "$FILE" '#old-tag' '#new-tag'
    ```
    *   Supports comma-separated old tags for multi-swap: `'#tag-a,#tag-b'`

### §CMD_HANDLE_INLINE_TAG
**Definition**: When a user types `#needs-xxx` (e.g., `#needs-brainstorm`, `#needs-research`, `#needs-documentation`) in response to a question or during discussion, the agent must capture it as an inline tag in the active artifact.

**Rule**: The user typing `#needs-xxx` means: "I can't answer this now. Tag it so it can be addressed later by the appropriate skill (e.g., `/brainstorm`, `/research`, `/document`)."

**Algorithm**:
1.  **Detect**: The user's response contains a `#needs-xxx` tag.
2.  **Tag the Source**: Add the tag **inline** in the relevant location of the **active work artifact** (the log entry, plan section, or debrief section currently being discussed). Place it naturally — next to the heading, in the paragraph, or as a bold marker:
    *   *In a log entry*: `### [timestamp] 🚧 Block — [Topic] #needs-brainstorm`
    *   *In a plan step*: `*   [ ] **Step 3**: [Action] #needs-brainstorm`
    *   *In a debrief section*: Add to the relevant paragraph or as a bullet.
3.  **Log to DETAILS.md**: Execute `§CMD_LOG_TO_DETAILS` recording the user's deferral (the question asked, the `#needs-xxx` response, and the context).
4.  **Do NOT Duplicate**: The tag should appear in **exactly one** work artifact (the log OR the debrief section — whichever is active when the user defers). Do NOT propagate the tag from DETAILS.md into the debrief automatically. If the debrief has a "Pending Decisions" or "Open Questions" section, list it there as a **reference** (one-liner with source path), not a full copy.
5.  **Tag the File**: If the work artifact is a debrief (final output), also add the `#needs-xxx` tag to the file's `**Tags**:` line via `§CMD_TAG_FILE`.
6.  **Tag Reactivity** (`¶INV_WALKTHROUGH_TAGS_ARE_PASSIVE`): Determine the current context and react accordingly:
    *   **During `§CMD_WALK_THROUGH_RESULTS`**: Tags are **passive**. The walkthrough protocol handles triage. Do NOT offer `/delegate` — the tag is protocol-placed, not a user-initiated deferral. Record and move on.
    *   **All other contexts** (interrogation, QnA, ad-hoc chat, side discovery): Tags are **reactive**. After recording the tag, invoke `/delegate` via the Skill tool: `Skill(skill: "delegate", args: "[tag] [context summary]")`. The `/delegate` skill handles mode selection (async/blocking/silent) and REQUEST filing. The user can always decline via "Other" in the delegate prompt.
7.  **Continue**: Resume the session. Do not halt or change phases — the deferral is recorded (and optionally delegated), move on.

**Constraint**: **Once Only**. Each deferred item appears as an inline tag in ONE place. The DETAILS.md captures the verbatim exchange. The debrief may list it in a "Pending" section as a pointer. Never three copies.

---

## §FEED_ALERTS
*   **Tags**: `#active-alert`, `#done-alert`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#active-alert` — Active. Created by `§CMD_MANAGE_ALERTS` during synthesis. Any document with this tag is considered "Active" and must be loaded into the context of every new agent session (unless explicitly reset).
    *   `#done-alert` — Resolved. Swapped by `§CMD_MANAGE_ALERTS` after the work is verified and aligned.

## §FEED_REVIEWS
*   **Tags**: `#needs-review`, `#done-review`, `#needs-rework`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-review` — Unvalidated. Auto-applied at debrief creation by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`.
    *   `#done-review` — User-approved via `/review`. No further action needed.
    *   `#needs-rework` — User-rejected via `/review`. Contains `## Rework Notes` with rejection context. Re-presented on next review run.

*   **Independence**: This feed is fully independent from `§FEED_ALERTS`. The two systems are parallel — a file (e.g., `ALERT_RAISE.md`) may carry both `#active-alert` and `#needs-review` simultaneously, resolved by different commands.
*   **Review Command**: `/review` discovers all `#needs-review` and `#needs-rework` files, performs cross-session analysis, and walks the user through structured approval.

## §FEED_DOCUMENTATION
*   **Tags**: `#needs-documentation`, `#done-documentation`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-documentation` — Pending. Auto-applied at debrief creation by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` for code-changing sessions (`IMPLEMENTATION`, `DEBUG`, `ADHOC`, `TESTING`).
    *   `#done-documentation` — Documentation pass complete. Swapped via `/document` or manually after verifying docs are current.
*   **Discovery**: `§CMD_FIND_TAGGED_FILES` for `#needs-documentation` returns all sessions with pending doc work.
*   **Independence**: This feed is independent from both `§FEED_ALERTS` and `§FEED_REVIEWS`. A debrief may carry `#needs-review #needs-documentation` simultaneously, resolved by different commands.

## §FEED_RESEARCH
*   **Tags**: `#needs-research`, `#active-research`, `#done-research`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-research` — Open request. Created by `/research-request` or `/research`. Discoverable by `§CMD_DISCOVER_OPEN_RESEARCH`.
    *   `#active-research` — In-flight. Swapped when the Gemini API call starts. The request file contains an `## Active Research` section with the Interaction ID. If the polling session dies, another agent can find `#active-research` requests, read the ID, and resume.
    *   `#done-research` — Fulfilled. Swapped when the report is received. The request file contains a `## Response` breadcrumb linking to the response document.
*   **File Convention**:
    *   Requests: `RESEARCH_REQUEST_[TOPIC].md` (in requesting session dir)
    *   Responses: `RESEARCH_RESPONSE_[TOPIC].md` (in responding session dir)
    *   Follow-ups: `RESEARCH_REQUEST_[TOPIC]_2.md`, `_3.md`, etc. — each carries the previous Interaction ID.
*   **Independence**: This feed is independent from all other feeds.
*   **API**: Uses Gemini Deep Research (`deep-research-pro-preview-12-2025`) via `engine research`. Requires `$GEMINI_API_KEY`.

## §FEED_BRAINSTORM
*   **Tags**: `#needs-brainstorm`, `#active-brainstorm`, `#done-brainstorm`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-brainstorm` — Deferred. Applied inline by any agent when a topic needs exploration, trade-off analysis, or a decision that requires structured dialogue.
    *   `#active-brainstorm` — In-flight. Swapped when `/brainstorm` begins working on the tagged item.
    *   `#done-brainstorm` — Complete. Swapped by `/brainstorm` after the session produces a `BRAINSTORM.md`.
*   **Application**: Like `#needs-implementation`, this tag can be applied **inline** within work artifacts (log entries, plan steps, debrief sections). The agent discovers these via `tag.sh find`.
*   **Output**: `/brainstorm` creates a `BRAINSTORM.md` in its session directory. For decision-focused brainstorms, use the Focused mode.
*   **Independence**: This feed is independent from all other feeds.

## §FEED_CHORES
*   **Tags**: `#needs-chores`, `#active-chores`, `#done-chores`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-chores` — Pending. A small, self-contained task that has all context in place and doesn't need full `/implement` overhead.
    *   `#active-chores` — Claimed. Swapped when `/chores` picks up the item from its queue.
    *   `#done-chores` — Complete. Swapped after verification.
*   **Context Model**: Tags are applied inline. The chores skill reads the full surrounding section (nearest heading above to next heading) to understand the task. No separate request file needed for inline tags, but request files are supported for explicit delegation.
*   **Application**: Applied inline within work artifacts when the agent identifies a small task. Can also appear on the Tags line of debriefs for tasks that emerged during a session.
*   **Independence**: This feed is independent from all other feeds.

## §FEED_FIX
*   **Tags**: `#needs-fix`, `#active-fix`, `#done-fix`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-fix` — Deferred. Applied inline by any agent when a bug, failure, or regression is identified but not immediately addressed. Common during implementation, testing, or analysis sessions.
    *   `#active-fix` — In-flight. Swapped when `/fix` begins working on the tagged item.
    *   `#done-fix` — Complete. Swapped by `/fix` after the fix is verified.
*   **Application**: Applied **inline** within work artifacts (test logs, implementation debriefs, analysis reports). Agents discover these via `tag.sh find` and route to `/fix`.
*   **Independence**: This feed is independent from all other feeds.

## §FEED_IMPLEMENTATION
*   **Tags**: `#needs-implementation`, `#active-implementation`, `#done-implementation`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-implementation` — Deferred. Applied inline by any agent when an actionable implementation task is identified but not immediately executed. Common during brainstorming, analysis, or decision sessions.
    *   `#active-implementation` — In-flight. Swapped when `/implement` begins working on the tagged item.
    *   `#done-implementation` — Complete. Swapped by `/implement` after the work is verified.
*   **Application**: Like `#needs-brainstorm`, this tag is applied **inline** within work artifacts (brainstorm outputs, analysis reports, plan steps). Agents discover these via `tag.sh find` and route to `/implement`.
*   **Independence**: This feed is independent from all other feeds.

## §TAG_DISPATCH
*   **Purpose**: Maps `#needs-*` tags to their resolving skills. Used by workers and `/find-tagged` to route deferred work to the correct skill.
*   **Rule**: Every `#needs-X` tag maps to exactly one skill `/X`. See `¶INV_1_TO_1_TAG_SKILL`.
*   **Registry**:

| Tag | Resolving Skill | Mode | Priority |
|-----|----------------|------|----------|
| `#needs-brainstorm` | `/brainstorm` | interactive | 1 (exploration unblocks decisions) |
| `#needs-research` | `/research` | async (Gemini) | 2 (queue early) |
| `#needs-fix` | `/fix` | interactive/agent | 3 (bugs block progress) |
| `#needs-implementation` | `/implement` | interactive/agent | 4 |
| `#needs-chores` | `/chores` | interactive | 5 (quick wins, filler) |
| `#needs-documentation` | `/document` | interactive | 6 |
| `#needs-review` | `/review` | interactive | 7 |
| `#needs-rework` | `/review` | interactive | 7 |

*   **Extensibility**: To add a new dispatchable tag, add a row to this table and create the corresponding `§FEED_*` section above. The tag noun MUST match the skill name (`¶INV_1_TO_1_TAG_SKILL`).
*   **Priority**: Resolves in priority order (1 first). Brainstorming unblocks decisions; research is async so queue early; fixes unblock progress; implementation is the main work; chores fill gaps; documentation after code; review last.

## §TAG_WEIGHTS
Weight tags express urgency and effort for work items. They are optional metadata — absence means default priority (P2) and unknown effort.

### Priority Tags
| Tag | Meaning | Scheduling |
|-----|---------|------------|
| `#P0` | Critical | Blocks everything. Process immediately. |
| `#P1` | Important | Should be done soon. Higher queue priority. |
| `#P2` | Normal | Default priority. FIFO within priority class. |

### Effort Tags
| Tag | Meaning | Time Estimate |
|-----|---------|---------------|
| `#S` | Small | < 30 minutes |
| `#M` | Medium | 30 min - 2 hours |
| `#L` | Large | > 2 hours |

### Usage
*   Tags are separate and combinable: `#needs-implementation #P1 #M`
*   Scheduling: Priority-first (P0 > P1 > P2), FIFO within same priority
*   Effort is informational for human planning — does not affect daemon scheduling
*   Discovery: `tag.sh find '#P0'` finds all critical items

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

## §FEED_AGGREGATION
*   When starting a new session, the agent should search for `#active-alert` and read the relevant files to understand the "Recent State of the Codebase" beyond what is in the main documentation.
*   This is especially critical during periods of high churn or complex debugging.
