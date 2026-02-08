# Tag System Reference (The Global Feeds)

This document defines the semantic tag system used across sessions for cross-session communication and lifecycle tracking.

## Tag Convention

All tags follow the `#needs-X` / `#active-X` / `#done-X` lifecycle pattern where X is a **noun** that maps to a command **verb**:

| Command (Verb) | Tag Noun | Lifecycle Tags |
|----------------|----------|----------------|
| `/research` | research | `#needs-research` -> `#active-research` -> `#done-research` |
| `/review` | review | `#needs-review` -> `#done-review` (or `#needs-rework`) |
| `/document` | documentation | `#needs-documentation` -> `#done-documentation` |
| `/decide` | decision | `#needs-decision` -> `#done-decision` |
| `/implement` | implementation | `#needs-implementation` -> `#active-implementation` -> `#done-implementation` |
| `/alert-raise` + `/alert-resolve` | alert | `#active-alert` -> `#done-alert` |

---

## Escaping Convention

Tags in body text must be distinguished from actual tags to prevent false positives in discovery (`tag.sh find`).

### The Rule
*   **Bare `#tag`** = actual tag. Placed on the Tags line (`**Tags**: #needs-review`) or intentionally inline (per `§CMD_HANDLE_INLINE_TAG`).
*   **Backticked `` `#tag` ``** = reference/discussion. NOT an actual tag. Filtered out by `tag.sh find`.

### When Writing (Agents)
*   **Tags line**: Always bare. `**Tags**: #needs-review #needs-documentation`
*   **Inline tags** (intentional): Bare. `### 🚧 Block — Widget API #needs-decision`
*   **References in body/logs/chat**: Always backtick-escape. Write `` `#needs-review` `` not `#needs-review`.

### When Reading (User Input)
*   User types bare `#needs-xxx` → treat as tag action (`§CMD_HANDLE_INLINE_TAG`).
*   User types backticked `` `#needs-xxx` `` → reference only. Preserve backticks. No tag action.

### Examples
```markdown
# Good — Tags line (bare)
**Tags**: #needs-review #needs-documentation

# Good — Intentional inline tag (bare)
### [2026-02-03] 🚧 Block — Auth Flow #needs-decision

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

## Tag Operations

### §CMD_FIND_TAGGED_FILES
**Definition**: To locate files carrying specific semantic tags (on the Tags line or as intentional inline tags), filtering out backtick-escaped references.
**Algorithm**:
1.  **Identify**: Determine the target tag (e.g., `#active-alert`).
2.  **Execute**:
    ```bash
    ~/.claude/scripts/tag.sh find '#tag-name'
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
    ~/.claude/scripts/tag.sh add "$FILE" '#tag-name'
    ```
    *   Ensures `**Tags**:` line exists after H1, then appends tag idempotently.
    *   Safe to run multiple times.

### §CMD_UNTAG_FILE
**Definition**: To remove a semantic tag from a Markdown file.
**Algorithm**:
1.  **Execute**:
    ```bash
    ~/.claude/scripts/tag.sh remove "$FILE" '#tag-name'
    ```

### §CMD_SWAP_TAG_IN_FILE
**Definition**: To atomically replace one tag with another (e.g., `#needs-review` → `#done-review`).
**Algorithm**:
1.  **Execute**:
    ```bash
    ~/.claude/scripts/tag.sh swap "$FILE" '#old-tag' '#new-tag'
    ```
    *   Supports comma-separated old tags for multi-swap: `'#tag-a,#tag-b'`

### §CMD_HANDLE_INLINE_TAG
**Definition**: When a user types `#needs-xxx` (e.g., `#needs-decision`, `#needs-research`, `#needs-documentation`) in response to a question or during discussion, the agent must capture it as an inline tag in the active artifact.

**Rule**: The user typing `#needs-xxx` means: "I can't answer this now. Tag it so it can be addressed later by the appropriate command (e.g., `/decide`, `/research`, `/document`)."

**Algorithm**:
1.  **Detect**: The user's response contains a `#needs-xxx` tag.
2.  **Tag the Source**: Add the tag **inline** in the relevant location of the **active work artifact** (the log entry, plan section, or debrief section currently being discussed). Place it naturally — next to the heading, in the paragraph, or as a bold marker:
    *   *In a log entry*: `### [timestamp] 🚧 Block — [Topic] #needs-decision`
    *   *In a plan step*: `*   [ ] **Step 3**: [Action] #needs-decision`
    *   *In a debrief section*: Add to the relevant paragraph or as a bullet.
3.  **Log to DETAILS.md**: Execute `§CMD_LOG_TO_DETAILS` recording the user's deferral (the question asked, the `#needs-xxx` response, and the context).
4.  **Do NOT Duplicate**: The tag should appear in **exactly one** work artifact (the log OR the debrief section — whichever is active when the user defers). Do NOT propagate the tag from DETAILS.md into the debrief automatically. If the debrief has a "Pending Decisions" or "Open Questions" section, list it there as a **reference** (one-liner with source path), not a full copy.
5.  **Tag the File**: If the work artifact is a debrief (final output), also add `#needs-decision` (or whichever tag) to the file's `**Tags**:` line via `§CMD_TAG_FILE`.
6.  **Continue**: Resume the session. Do not halt or change phases — the deferral is recorded, move on.

**Constraint**: **Once Only**. Each deferred item appears as an inline tag in ONE place. The DETAILS.md captures the verbatim exchange. The debrief may list it in a "Pending" section as a pointer. Never three copies.

---

## §FEED_ALERTS
*   **Tags**: `#active-alert`, `#done-alert`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#active-alert` — Active. Created by `/alert-raise`. Any document with this tag is considered "Active" and must be loaded into the context of every new agent session (unless explicitly reset).
    *   `#done-alert` — Resolved. Swapped by `/alert-resolve` after the work is verified and aligned.

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
*   **API**: Uses Gemini Deep Research (`deep-research-pro-preview-12-2025`) via `~/.claude/scripts/research.sh`. Requires `$GEMINI_API_KEY`.

## §FEED_DECISIONS
*   **Tags**: `#needs-decision`, `#done-decision`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-decision` — Deferred. Applied inline by any agent when the user responds with `#needs-decision` to a question, or when the agent encounters an unresolvable question. See `§CMD_HANDLE_INLINE_TAG` above.
    *   `#done-decision` — Decided. Swapped by `/decide` after the user records their decision. The originating file receives a `## Decision Recorded` breadcrumb.
*   **Application**: Unlike other feeds, `#needs-decision` is applied **inline** within the body of work artifacts (log entries, plan steps, debrief sections) — not just on the Tags line. The `/decide` command searches for both inline occurrences and Tags-line occurrences.
*   **Output**: `/decide` creates a `DECISIONS.md` in its own session directory, recording all decisions made.
*   **Independence**: This feed is independent from all other feeds. A debrief may carry `#needs-review #needs-decision` simultaneously.

## §FEED_IMPLEMENTATION
*   **Tags**: `#needs-implementation`, `#active-implementation`, `#done-implementation`
*   **Location**: `sessions/`
*   **Lifecycle**:
    *   `#needs-implementation` — Deferred. Applied inline by any agent when an actionable implementation task is identified but not immediately executed. Common during brainstorming, analysis, or decision sessions.
    *   `#active-implementation` — In-flight. Swapped when `/implement` begins working on the tagged item.
    *   `#done-implementation` — Complete. Swapped by `/implement` after the work is verified.
*   **Application**: Like `#needs-decision`, this tag is applied **inline** within work artifacts (brainstorm outputs, analysis reports, plan steps). The `/dispatch` command discovers these and routes to `/implement`.
*   **Independence**: This feed is independent from all other feeds.

## §TAG_DISPATCH
*   **Purpose**: Maps `#needs-*` tags to their resolving skills. Used by `/dispatch` to route deferred work to the correct skill.
*   **Registry**:

| Tag | Resolving Skill | Mode | Priority |
|-----|----------------|------|----------|
| `#needs-decision` | `/decide` | interactive | 1 (decisions unblock) |
| `#needs-research` | `/research` | async (Gemini) | 2 (queue early) |
| `#needs-implementation` | `/implement` | interactive/agent | 3 |
| `#needs-documentation` | `/document` | interactive | 4 |
| `#needs-review` | `/review` | interactive | 5 |
| `#needs-rework` | `/review` | interactive | 5 |

*   **Extensibility**: To add a new dispatchable tag, add a row to this table and create the corresponding `§FEED_*` section above.
*   **Priority**: When `/dispatch` processes "all", it resolves in priority order (1 first). Decisions unblock other work; research is async so queue early; implementation before documentation; review last.

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
