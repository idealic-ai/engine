---
name: delegation-claim
description: "Worker-side claiming of delegated work items. Scans #delegated-X tags, presents items for claiming, routes to target skills. Triggers: \"claim work\", \"pick up delegated items\", \"what's available to work on\", \"delegation claim\"."
version: 2.0
tier: lightweight
---

Worker-side claiming of delegated work items. Scans `#delegated-X` tags, presents items for claiming, and routes to target skills.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

**Note**: This is a utility skill — no session activation. Operates within the caller's session or standalone. Can be spawned by the daemon or invoked manually.

### GATE CHECK — Do NOT proceed until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT proceed until every blank is filled.

# Delegation Claim Protocol (The Worker's Pickup)

Lightweight utility for claiming delegated work items and routing them to the appropriate target skill. The worker-side counterpart to `/delegation-review` (requester-side approval). No session activation, no log file, no debrief.

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This is a utility skill with a single-phase protocol. Follow the steps below exactly.

---

## 0. Parse Arguments (Tag Filter)

Check if a tag filter argument was provided:

- **No argument** (`/delegation-claim`): Scan ALL `#delegated-*` tags.
- **Noun argument** (`/delegation-claim implementation`): Resolve to `#delegated-implementation`. Scan only that tag.
- **Full tag argument** (`/delegation-claim #delegated-implementation`): Use as-is. Scan only that tag.

**Resolution logic**:
1. If argument starts with `#delegated-`: use directly.
2. If argument starts with `#`: strip `#` prefix, prepend `#delegated-`. (e.g., `#implementation` → `#delegated-implementation`)
3. Otherwise: prepend `#delegated-`. (e.g., `implementation` → `#delegated-implementation`)

Store the resolved tag pattern for Step 1.

---

## 1. Scan for Delegated Work

Scan for `#delegated-*` tags (or the filtered tag from Step 0):

```bash
# If no filter (scan all):
engine tag find '#delegated-*' sessions/ --tags-only --context

# If filtered to a specific tag:
engine tag find '#delegated-[noun]' sessions/ --tags-only --context
```

If no `#delegated-*` tags found:
> "No delegated work items found. Nothing to claim."

Return control. Skill is done.

---

## 2. Group by Tag Type

Organize results by tag noun (e.g., all `#delegated-implementation` together, all `#delegated-chores` together). For each group, note:
- **Tag type**: e.g., `#delegated-implementation`
- **Target skill**: e.g., `/implement` (from `§TAG_DISPATCH`)
- **File count**: How many items in this group
- **Files**: List of file paths carrying the tag

---

## 3. Read Request Context

For each file in each group, read enough context to present a meaningful summary:
- **REQUEST files** (filename contains `REQUEST`): Read Topic, Context, and Expectations fields
- **Debrief/other files**: Read the H1 heading and first paragraph for summary
- **Inline tags**: Read the surrounding section (nearest heading above to next heading)

---

## 4. Present Claiming Menu

For each tag-type group, present via `AskUserQuestion` (multiSelect: true):

Provide context before the question — list each item with a 1-line summary:
> **`#delegated-[noun]` — [N] items available:**
> 1. `[file1.md]` — [1-line summary from request context]
> 2. `[file2.md]` — [1-line summary from request context]

Then ask:
> "Which `#delegated-[noun]` items should I claim?"
> - **"Claim all [N] items"** — Claim all and route to `/[skill]`
> - **"Claim selected" (if >1)** — Pick specific items to claim
> - **"Skip this group"** — Leave all as `#delegated-[noun]` for later

---

## 5. Claim and Route

For each claimed item:

1. **Claim** (`¶INV_CLAIM_BEFORE_WORK`): Swap tag via `tag.sh swap`:
   ```bash
   engine tag swap '[file_path]' '#delegated-[noun]' '#claimed-[noun]'
   ```
   - **Race safety**: `tag.sh swap` errors (exit 1) if the old tag is already gone. This means another worker already claimed it. If this happens:
     > "Item already claimed by another worker: `[file_path]`. Skipping."
     Continue with remaining items.

2. **Route to target skill**: After claiming all approved items in a group, invoke the target skill:
   ```
   Skill(skill: "[target-skill]", args: "[file_path or session_dir]")
   ```
   - If multiple items were claimed for the same skill, pass the session directory so the skill can find all claimed items.

---

## 6. Report and Return

After all groups are processed:

> **Claim summary:**
> - Claimed: [N] items ([list tag types])
> - Skipped: [M] items
> - Already claimed by others: [K] items
> - Routed to: [list of target skills invoked]

**Return control**. No debrief. No session deactivation. No next-skill menu.

---

## Constraints

- **No session activation** (`¶INV_DELEGATE_IS_NESTABLE` pattern): This skill does not call `session.sh activate`. It can be invoked from any context — daemon-spawned, standalone, or mid-skill.
- **No REQUEST/RESPONSE templates**: `/delegation-claim` does not accept delegation requests itself. It IS the delegation resolver.
- **Always interactive**: Even when spawned by the daemon, `/delegation-claim` presents items to the human via `AskUserQuestion`. The human monitoring the daemon terminal approves what gets claimed. No auto-claiming.
- **Race-safe claiming**: Uses `tag.sh swap` which errors if the old tag is gone. Worker must handle this gracefully — skip the item, do not crash.
- **Daemon batching**: When spawned by the daemon, `/delegation-claim` may see items that were batch-collected after the 3s debounce (`¶INV_DAEMON_DEBOUNCE`). Process all items in a single invocation — do not spawn separate `/delegation-claim` instances per item.
- **Graceful degradation** (`¶INV_GRACEFUL_DEGRADATION`): If no fleet is running, the user can invoke `/delegation-claim` manually to pick up `#delegated-*` items at their convenience. Tags persist on disk regardless of infrastructure.
