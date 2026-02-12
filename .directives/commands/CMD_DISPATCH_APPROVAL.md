### §CMD_DISPATCH_APPROVAL
**Description**: Reviews `#needs-X` tags in the current session and lets the user approve them for daemon dispatch (`#delegated-X`) or claim them for immediate next-skill execution (`#next-X`). The human gate between tag creation and processing.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF` step 10 (after `§CMD_PROCESS_DELEGATIONS`, before `§CMD_CAPTURE_SIDE_DISCOVERIES`). Also callable standalone via `/delegation-review`.

**Algorithm**:
1.  **Scan**: Find all `#needs-X` tags in the current session directory:
    *   `engine tag find '#needs-*' [sessionDir] --tags-only` — Tags-line entries on REQUEST files and debriefs
    *   Exclude `#needs-review` (resolved by `/review`, not daemon dispatch)
    *   Exclude `#needs-rework` (resolved by `/review`)
2.  **Skip if empty**: If no `#needs-X` tags found (excluding review/rework), skip silently. No user prompt.
3.  **Group**: Organize results by tag type (e.g., all `#needs-implementation` together, all `#needs-chores` together).
4.  **Present**: For each group, execute `AskUserQuestion` (multiSelect: true):
    > "Dispatch approval — `#needs-[noun]` ([N] items):"
    > - **"Approve all [N] for daemon dispatch → `#delegated-[noun]`"** — Flip all items in this group for async daemon processing
    > - **"Claim all [N] for next skill → `#next-[noun]`"** — Mark for immediate execution in the next skill session
    > - **"Review individually"** — Walk through each item to approve/claim/defer/dismiss
    > - **"Defer all"** — Leave as `#needs-[noun]` (will appear in next session's dispatch approval)
5.  **Execute**:
    *   **Approve all**: For each file in the group, `engine tag swap [file] '#needs-[noun]' '#delegated-[noun]'`.
    *   **Claim all for next skill**: For each file in the group, `engine tag swap [file] '#needs-[noun]' '#next-[noun]'`. Then execute **state passing** (step 5a).
    *   **Review individually**: For each file, present: Approve (`#delegated-X`) / Claim for next skill (`#next-X`) / Defer (keep `#needs-X`) / Dismiss (remove tag entirely).
    *   **Defer all**: No action. Tags remain as `#needs-X`.
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
    This is a backup mechanism — the primary discovery path is `§CMD_SURFACE_OPEN_DELEGATIONS` in `engine session activate`.
6.  **Report**: Output summary in chat: "Dispatched: [N] items. Claimed for next skill: [P] items. Deferred: [M] items. Dismissed: [K] items."

**Constraints**:
*   **Current session only**: Does NOT scan other sessions. Cross-session dispatch is out of scope (use `/delegation-review` for cross-session).
*   **Human approval required** (`¶INV_DISPATCH_APPROVAL_REQUIRED`): Agents MUST NOT auto-flip `#needs-X` → `#delegated-X` or `#needs-X` → `#next-X`.
*   **Daemon monitors `#delegated-*` only** (`¶INV_NEEDS_IS_STAGING`, `¶INV_NEXT_IS_IMMEDIATE`): `#delegated-X` items become visible to the daemon. `#next-X` items are handled by the next skill, not the daemon.
*   **Debounce-friendly**: Multiple `engine tag swap` calls in rapid succession are collected by the daemon's 3s debounce (`¶INV_DAEMON_DEBOUNCE`).
