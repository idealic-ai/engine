### ¶CMD_DISPATCH_APPROVAL
**Definition**: Reviews `#needs-X` tags in the current session and lets the user approve them for daemon dispatch (`#delegated-X`) or claim them for immediate next-skill execution (`#next-X`). The human gate between tag creation and processing.
**Classification**: CONSUMER

**Algorithm**:
1.  **Collect** (no independent scan): Gather `#needs-X` Tags-line items from two sources:
    *   **Step 2 output**: REQUEST files created by `§CMD_PROCESS_DELEGATIONS` in the current pipeline run (each carries `#needs-X` on its Tags line).
    *   **Agent context**: Pre-existing Tags-line `#needs-X` tags the agent already knows about — from debrief creation (`#needs-review` excluded), walkthrough triage, or manual tagging during the session.
    *   Exclude `#needs-review` (resolved by `/review`, not daemon dispatch)
    *   Exclude `#needs-rework` (resolved by `/review`)
    *   **Fallback**: If agent context is unavailable (e.g., post-overflow recovery without dehydrated context), fall back to `engine tag find '#needs-*' [sessionDir] --tags-only`.
2.  **Skip if empty**: If no `#needs-X` tags found (excluding review/rework), skip silently. No user prompt.
3.  **Group**: Organize results by tag type (e.g., all `#needs-implementation` together, all `#needs-chores` together).
4.  **Present**: For each group, invoke §CMD_DECISION_TREE with `§ASK_DISPATCH_GROUP`. Use preamble context to describe the group (`#needs-[noun]`, item count, and brief context per item).
5.  **Execute** (based on `§ASK_DISPATCH_GROUP` path):
    *   **`APR` (Approve all)**: For each file in the group, `engine tag swap [file] '#needs-[noun]' '#delegated-[noun]'`.
    *   **`CLM` (Claim all for next skill)**: For each file in the group, `engine tag swap [file] '#needs-[noun]' '#next-[noun]'`. Then execute **state passing** (step 5a).
    *   **`REV` (Review individually)**: Chunk files in the group into batches of **4** (matching `AskUserQuestion`'s max of 4 questions per call). Last batch gets the remainder (1-3 files). For each batch:

        1.  **Context Blocks (per-file, single chat message)**: Output ALL files' context in one message. Each file gets an ID per the Item IDs convention (SIGILS.md § Item IDs). Format: `{phase}/{file}` — e.g., if dispatch runs during synthesis sub-phase 5.3, the first file is `5.3/1`:

            > **{itemId}**: `[filename]`
            >
            > **What this is**: [1 sentence — the REQUEST file or debrief section this tag lives on]
            >
            > **Current tag**: `#needs-[noun]` — [1 sentence — what work this represents]

        2.  **Present Options**: Invoke §CMD_DECISION_TREE with `§ASK_DISPATCH_ITEM` in batch mode (up to 4 items per batch). Use per-item context blocks from step 1 as preamble context. Item IDs are passed through to §CMD_DECISION_TREE for use in `AskUserQuestion` headers.

        3.  **On Selection** (based on `§ASK_DISPATCH_ITEM` path): Process each file's answer independently:
            *   **`APR`**: `engine tag swap [file] '#needs-[noun]' '#delegated-[noun]'`
            *   **`CLM`**: `engine tag swap [file] '#needs-[noun]' '#next-[noun]'`. Execute state passing (step 5a) after batch.
            *   **`DEF`**: No action. Tag remains as `#needs-X`.
            *   **`OTH/DIS`**: Remove tag entirely via `engine tag remove [file] '#needs-[noun]'`.
            *   **`OTH/SPL`**: Follow-up to define sub-items, then create REQUEST files for each.
    *   **`OTH` path**:
        *   **`OTH/DEF` (Defer all)**: No action. Tags remain as `#needs-X`.
        *   **`OTH/DIS` (Dismiss all)**: Remove tags entirely from all files in the group.
5a. **State Passing** (after any "Claim for next skill" selections): Write claimed items to DETAILS.md so they survive in the context window for the next skill to pick up:
    ```bash
    engine log [sessionDir]/DETAILS.md <<'EOF'
    ## Claimed for Next Skill
    **Type**: State Passing

    **Items claimed for immediate execution:**
    *   `[file1]` — `#next-[noun]` (was `#needs-[noun]`)
    *   `[file2]` — `#next-[noun]` (was `#needs-[noun]`)

    **Action**: Next skill should auto-claim these on activation by swapping `#next-X` → `#claimed-X`.
    EOF
    ```
    This is a backup mechanism — the primary discovery path is `SRC_OPEN_DELEGATIONS` in `engine session activate`.
6.  **Report**: Output summary in chat: "Dispatched: [N] items. Claimed for next skill: [P] items. Deferred: [M] items. Dismissed: [K] items."

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **Current session only**: Does NOT scan other sessions. Cross-session dispatch is out of scope (use `/delegation-review` for cross-session).
*   **Human approval required** (`¶INV_DISPATCH_APPROVAL_REQUIRED`): Agents MUST NOT auto-flip `#needs-X` → `#delegated-X` or `#needs-X` → `#next-X`.
*   **Daemon monitors `#delegated-*` only** (`¶INV_NEEDS_IS_STAGING`, `¶INV_NEXT_IS_IMMEDIATE`): `#delegated-X` items become visible to the daemon. `#next-X` items are handled by the next skill, not the daemon.
*   **Group size (Review individually)**: Fixed at 4 files per batch (matching `AskUserQuestion`'s max questions). Last batch gets remainder (1-3 files). Files batched in discovery order.
*   **Follow-up on demand**: When a selection requires state passing (e.g., "Claim for next skill"), execute step 5a after the batch completes. Minimize round-trips — only follow up when the selected option requires additional action.
*   **Debounce-friendly**: Multiple `engine tag swap` calls in rapid succession are collected by the daemon's debounce window.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and context blocks; bare tags only on `**Tags**:` lines or in `engine tag` commands.

---

### ¶ASK_DISPATCH_GROUP
Trigger: during dispatch approval when presenting a group of same-type `#needs-X` items (except: when no `#needs-X` items exist — pipeline skips silently)
Extras: A: Show item details before deciding | B: Split group by priority | C: View related sessions

## Decision: Dispatch Group
- [APR] Approve all for daemon
  Flip all items to #delegated-X for async daemon processing
- [CLM] Claim all for next skill
  Mark all for immediate execution in next skill session
- [REV] Review individually
  Walk through each item to approve/claim/defer/dismiss
- [OTH] Other
  - [DEF] Defer all
    Leave as #needs-X for future triage
  - [DIS] Dismiss all
    Remove tags entirely — work is not needed

### ¶ASK_DISPATCH_ITEM
Trigger: during per-item review of `#needs-X` items (except: when group-level decision was Approve all, Claim all, or Defer all)
Extras: A: View item context in source file | B: View related sessions | C: Change priority tag

## Decision: Dispatch Item
- [APR] Approve for daemon
  Flip to #delegated-X for async daemon processing
- [CLM] Claim for next skill
  Mark for immediate execution in next skill session
- [DEF] Defer
  Leave as #needs-X for future triage
- [OTH] Other
  - [DIS] Dismiss
    Remove tag entirely — work is not needed
  - [SPL] Split item
    Break into multiple smaller work items

---

## PROOF FOR §CMD_DISPATCH_APPROVAL

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "itemsDispatched": {
      "type": "string",
      "description": "Count and targets dispatched (e.g., '2 dispatched: impl, chores')"
    },
    "itemsClaimed": {
      "type": "string",
      "description": "Count and skills claimed for (e.g., '1 claimed for /implement')"
    },
    "itemsDeferred": {
      "type": "string",
      "description": "Count of items deferred (e.g., '0 deferred')"
    }
  },
  "required": ["executed", "itemsDispatched", "itemsClaimed", "itemsDeferred"],
  "additionalProperties": false
}
```
