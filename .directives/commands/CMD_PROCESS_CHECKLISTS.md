### §CMD_PROCESS_CHECKLISTS
**Definition**: During synthesis, processes all discovered CHECKLIST.md files — reads each checklist, evaluates items against the session's work, then quotes results back to `engine session check` for mechanical validation. Ensures the deactivation gate (`¶INV_CHECKLIST_BEFORE_CLOSE`) will pass.
**Trigger**: Called by skill protocols during the synthesis phase, BEFORE `§CMD_GENERATE_DEBRIEF`. Read this file before executing.

**Algorithm**:
1.  **Check for Discovered Checklists**: Read `.state.json` field `discoveredChecklists` (array of absolute paths).
    *   If the array is empty or missing, skip silently. Return control to the caller.
2.  **Check for Already-Passed**: Read `.state.json` field `checkPassed`.
    *   If `checkPassed` is `true`, skip silently (already validated).
3.  **For Each Discovered Checklist**:
    a.  **Read**: Load the CHECKLIST.md file content.
    b.  **Evaluate**: Review each item in the checklist against the session's work:
        *   If the item was addressed by this session → mark `[x]` with brief evidence.
        *   If the item was NOT addressed but is relevant → mark `[ ]` with explanation.
        *   If the item is not applicable to this session → mark `[x]` with "N/A: [reason]".
    c.  **Build Quote-Back Block**: Construct a `## CHECKLIST:` block for this file:
        ```
        ## CHECKLIST: /absolute/path/to/CHECKLIST.md
        - [x] Item one — verified in src/foo.ts
        - [x] Item two — N/A: not relevant to this session
        - [ ] Item three — not addressed, pending for next session
        ```
    d.  **Present Summary**: Output a brief summary in chat:
        > **Checklist processed**: `[path]`
        > - Done: [N] items
        > - Pending: [N] items
    e.  **Log**: Append to the session's `_LOG.md`:
        ```bash
        engine log [sessionDir]/[LOG_NAME].md <<'EOF'
        ## 📋 Checklist Processed
        *   **File**: [absolute path]
        *   **Items**: [total] total — [done] done, [pending] pending
        *   **Pending Items**: [list of pending items, if any]
        EOF
        ```
4.  **Submit to engine session check**: Concatenate all quote-back blocks and pipe to `engine session check`:
    ```bash
    engine session check [sessionDir] <<'EOF'
    ## CHECKLIST: /path/to/first/CHECKLIST.md
    - [x] Verified item one
    - [x] Verified item two

    ## CHECKLIST: /path/to/second/CHECKLIST.md
    - [x] All items verified
    EOF
    ```
    *   On success: `engine session check` sets `checkPassed=true` in `.state.json`. The deactivation gate will pass.
    *   On failure: `engine session check` exits 1 with a descriptive error. Fix the missing blocks and retry.
5.  **Report Pending Items**: If any checklist items are marked `[ ]` (pending), flag them:
    *   Add a brief mention in the debrief's "Next Steps" section.
    *   If significant, tag with `#needs-implementation` via `§CMD_TAG_FILE`.

**Constraints**:
*   **Non-blocking on empty**: Skip silently if no discovered checklists. Only process when checklists exist.
*   **Quote-back pattern**: The agent MUST echo checklist items back via stdin to prove processing. `engine session check` validates that every `discoveredChecklists[]` path has a matching `## CHECKLIST:` block with at least one item.
*   **Belt-and-suspenders**: This command is the "belt" (protocol-level). The `engine session deactivate` gate is the "suspenders" (infrastructure-level). Both exist because agents skip protocol steps — the gate catches failures.
*   **Session state**: `checkPassed` (boolean) in `.state.json` is the source of truth. The deactivate gate checks `checkPassed == true` when `discoveredChecklists` is non-empty.
*   **Idempotent**: Safe to run multiple times. If `checkPassed` is already true, skips (step 2).
