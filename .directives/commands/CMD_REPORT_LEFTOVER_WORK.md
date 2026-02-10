### §CMD_REPORT_LEFTOVER_WORK
**Definition**: At synthesis, extracts unfinished items from session artifacts and presents a concise report in chat — giving the user context before the next-skill menu.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 11, after `§CMD_CAPTURE_SIDE_DISCOVERIES` and before `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`.

**Algorithm**:
1.  **Identify Artifacts**: Locate the session's debrief, log, and plan files:
    *   Debrief: `[sessionDir]/*.md` matching skill type (e.g., `IMPLEMENTATION.md`, `ANALYSIS.md`, `DOCUMENTATION.md`)
    *   Log: `[sessionDir]/*_LOG.md`
    *   Plan: `[sessionDir]/*_PLAN.md`
    *   If any artifact is missing, skip that source (not all skills produce all three).
2.  **Extract Leftover Items** (from each source):
    *   **From Debrief**:
        *   Tech Debt items: Lines under headings containing "Debt" or prefixed with 💸
        *   Documentation impact: Unchecked `[ ]` items under headings containing "Documentation"
        *   Next Steps: Items under headings containing "Next Steps" or "Recommendations"
        *   Open questions: Items tagged with `#needs-brainstorm` or `#needs-research`
    *   **From Log**:
        *   Unresolved blocks: 🚧 Block entries that have no subsequent ✅ Success entry for the same item
        *   Parking lot items: 🗑️ Parking Lot entries
    *   **From Plan**:
        *   Unchecked steps: `- [ ]` items (steps that were planned but not completed)
3.  **If No Items Found**: Skip silently. Return control to the caller. Do NOT prompt the user.
4.  **If Items Found**: Output in chat as a structured report:
    ```markdown
    ## Leftover Work

    **Tech Debt** (from debrief):
    - 💸 [item summary]
    - 💸 [item summary]

    **Unresolved Blocks** (from log):
    - 🚧 [block summary]

    **Incomplete Plan Steps**:
    - [ ] Step N: [description]

    **Documentation Impact**:
    - [ ] [doc item]

    **Next Steps / Open Questions**:
    - [item]
    ```
    *   Omit empty categories. Only show categories that have items.
    *   Keep each item to a single line — concise summaries, not full quotes.
    *   When referencing files, use clickable links per `¶INV_TERMINAL_FILE_LINKS` (Compact `§` variant).
5.  **Append to Log**: Write the report to the session's `_LOG.md` for audit trail:
    ```bash
    engine log [sessionDir]/[LOG_NAME].md <<'EOF'
    ## 📋 Leftover Work Report
    *   **Tech Debt**: [N] items
    *   **Unresolved Blocks**: [N] items
    *   **Incomplete Steps**: [N] items
    *   **Doc Impact**: [N] items
    *   **Next Steps**: [N] items
    *   **Total**: [N] leftover items surfaced
    EOF
    ```

**Constraints**:
*   **Non-blocking**: This is a read-only report. No `AskUserQuestion` — just output. The user sees it and uses it to inform their next-skill choice.
*   **Generic extraction**: Pattern-match by emoji prefixes and heading keywords, not hardcoded section numbers. Different skill templates use different section structures.
*   **Concise**: Max 15 items total in the chat report. If more exist, show top 15 and note "... and N more items (see debrief for full list)."
*   **Skip silently**: If the session produced zero leftover items, output nothing. A clean session needs no report.
