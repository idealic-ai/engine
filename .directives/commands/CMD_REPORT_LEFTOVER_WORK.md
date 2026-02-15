### ¶CMD_REPORT_LEFTOVER_WORK
**Definition**: At synthesis, extracts unfinished items from session artifacts and presents a concise report in chat — giving the user context before the next-skill menu.
**Classification**: SCAN

**Algorithm**:
1.  **Read Debrief Scan Output**: The `engine session debrief` output (run once at the start of N.3 per `§CMD_RUN_SYNTHESIS_PIPELINE`) contains a `## §CMD_REPORT_LEFTOVER_WORK (N)` section with pre-scanned results. Read the count and line references from this section. Do NOT re-scan the artifacts yourself.
    *   The engine scans for: unchecked `[ ]` in plan files, 🚧 Block entries in log files, and 💸 tech debt in debrief files.
    *   If count is 0: skip silently. Return control to the caller. Do NOT prompt the user.
2.  **If Items Found (count > 0)**: Read the referenced lines for context. Categorize into groups:
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
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration of the scan process.

---

## PROOF FOR §CMD_REPORT_LEFTOVER_WORK

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "itemsReported": {
      "type": "string",
      "description": "Count and categories of items reported (e.g., '4 items: 2 debt, 1 block, 1 step')"
    }
  },
  "required": ["executed", "itemsReported"],
  "additionalProperties": false
}
```
