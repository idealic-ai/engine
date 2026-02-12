---
name: delegation-review
description: "Standalone dispatch approval — scans #needs-X tags, presents grouped approval menu, executes tag transitions. Triggers: \"review delegations\", \"dispatch approval\", \"what needs dispatching\", \"delegation review\"."
version: 3.0
tier: lightweight
---

Standalone dispatch approval for reviewing pending `#needs-X` and stale `#next-X` tags across sessions.
**Note**: This is a utility skill — no session activation. Operates standalone or within an existing session context. Can be invoked manually at any time.

### GATE CHECK — Do NOT proceed until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT proceed until every blank is filled.

# Delegation Review Protocol (The Dispatcher's Console)

Lightweight utility for reviewing pending `#needs-X` tags and approving them for daemon dispatch (`#delegated-X`) or immediate next-skill execution (`#next-X`). The requester-side counterpart to `/delegation-claim` (worker-side claiming). No session activation, no log file, no debrief.


---

## 0. Parse Arguments (Scope Filter)

Check if a scope argument was provided:

- **No argument** (`/delegation-review`): Scan ALL `#needs-*` tags + ALL stale `#next-*` tags across `sessions/`.
- **Session argument** (`/delegation-review sessions/2026_02_10_TOPIC`): Scope to that session directory only.
- **Tag argument** (`/delegation-review #needs-implementation`): Scan only that specific tag across `sessions/`.

Store the resolved scope and tag filter for Step 1.

---

## 1. Scan for Pending Work

Scan for `#needs-*` tags (excluding `#needs-review` and `#needs-rework`, which are handled by `/review`):

```bash
# Scan all #needs-* (default scope: sessions/)
engine tag find '#needs-*' [scope] --tags-only --context

# Also scan for stale #next-* items (claimed for next-skill but never picked up)
engine tag find '#next-*' [scope] --tags-only --context
```

If no `#needs-*` or `#next-*` tags found:
> "No pending delegation items found. Nothing to review."

Return control. Skill is done.

---

## 2. Group by Tag Type

Organize results into two categories:

### A. Pending Dispatch (`#needs-X`)
Group by tag noun (e.g., all `#needs-implementation` together, all `#needs-chores` together). For each group, note:
- **Tag type**: e.g., `#needs-implementation`
- **Target skill**: e.g., `/implement` (from `§TAG_DISPATCH`)
- **File count**: How many items in this group
- **Files**: List of file paths carrying the tag

### B. Stale Next-Skill Items (`#next-X`)
Group by tag noun. These are items that were claimed for immediate next-skill execution but never picked up. For each:
- **Tag type**: e.g., `#next-implementation`
- **Target skill**: e.g., `/implement`
- **Age**: How long since the tag was applied (from file mtime)
- **Files**: List of file paths

---

## 3. Read Request Context

For each file in each group, read enough context to present a meaningful summary:
- **REQUEST files** (filename contains `REQUEST`): Read Topic, Context, and Expectations fields
- **Debrief/other files**: Read the H1 heading and first paragraph for summary
- **Inline tags**: Read the surrounding section (nearest heading above to next heading)

---

## 4. Present Dispatch Approval

### A. Pending Dispatch Groups (`#needs-X`)

For each tag-type group, execute `§CMD_DISPATCH_APPROVAL` algorithm:

Provide context before the question — list each item with a 1-line summary:
> **`#needs-[noun]` — [N] items pending:**
> 1. `[file1.md]` — [1-line summary]
> 2. `[file2.md]` — [1-line summary]

Then present via `AskUserQuestion` (multiSelect: false):
> "Dispatch approval — `#needs-[noun]` ([N] items):"
> - **"Approve all [N] for daemon dispatch -> `#delegated-[noun]`"** — Flip all items for async daemon processing
> - **"Claim all [N] for next skill -> `#next-[noun]`"** — Mark for immediate execution in the next skill session
> - **"Review individually"** — Walk through each item to approve/claim/defer/dismiss
> - **"Defer all"** — Leave as `#needs-[noun]` for later

**Execute choices**:
*   **Approve all**: For each file, `engine tag swap [file] '#needs-[noun]' '#delegated-[noun]'`.
*   **Claim all for next skill**: For each file, `engine tag swap [file] '#needs-[noun]' '#next-[noun]'`. Then write state passing to DETAILS.md (per `§CMD_DISPATCH_APPROVAL` step 5a) if a session is active.
*   **Review individually**: For each file, present: Approve (`#delegated-X`) / Claim for next skill (`#next-X`) / Defer (keep `#needs-X`) / Dismiss (remove tag entirely).
*   **Defer all**: No action. Tags remain as `#needs-X`.

### B. Stale Next-Skill Items (`#next-X`)

For each stale `#next-X` group, present via `AskUserQuestion` (multiSelect: false):

> "Stale `#next-[noun]` — [N] items never picked up:"
> 1. `[file1.md]` — [1-line summary] (age: [N] hours/days)

> "What should happen to these stale `#next-[noun]` items?"
> - **"Re-route to daemon -> `#delegated-[noun]`"** — Swap to daemon dispatch path
> - **"Keep as `#next-[noun]`"** — Leave for next skill pickup
> - **"Dismiss all"** — Remove tags (work no longer needed)

**Execute choices**:
*   **Re-route**: For each file, `engine tag swap [file] '#next-[noun]' '#delegated-[noun]'`.
*   **Keep**: No action.
*   **Dismiss**: For each file, `engine tag remove [file] '#next-[noun]'`.

---

## 5. Report and Return

After all groups are processed:

> **Dispatch review summary:**
> - Approved for daemon: [N] items
> - Claimed for next skill: [M] items
> - Re-routed from stale: [K] items
> - Deferred: [P] items
> - Dismissed: [Q] items

**Return control**. No debrief. No session deactivation. No next-skill menu.

---

## Constraints

- **No session activation** (`¶INV_DELEGATE_IS_NESTABLE` pattern): This skill does not call `engine session activate`. It can be invoked standalone or mid-skill.
- **No REQUEST/RESPONSE templates**: `/delegation-review` does not accept delegation requests itself. It IS the dispatch approver.
- **Human approval required** (`¶INV_DISPATCH_APPROVAL_REQUIRED`): Every `#needs-X` -> `#delegated-X` or `#needs-X` -> `#next-X` transition requires explicit user approval. No auto-flipping.
- **Excludes review/rework tags**: `#needs-review` and `#needs-rework` are handled by `/review`, not this skill. Filter them out of scan results.
- **Stale detection**: `#next-X` items older than 24 hours are considered "stale" and surfaced for re-routing. This is a soft heuristic — the user decides.
- **Graceful degradation** (`¶INV_GRACEFUL_DEGRADATION`): Works without fleet/daemon. Tags persist on disk. The user can invoke `/delegation-review` at any time to process accumulated `#needs-X` items manually.
