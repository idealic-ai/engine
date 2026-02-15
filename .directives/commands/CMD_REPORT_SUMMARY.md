### ¶CMD_REPORT_SUMMARY
**Definition**: Produces a dense 2-paragraph narrative summary of the session's work.
**Rule**: Must be executed immediately after `§CMD_REPORT_ARTIFACTS`.
**Algorithm**:
1.  **Reflect**: Review all work performed during this session — decisions made, problems solved, artifacts created, and key outcomes.
2.  **Compose**: Write exactly 2 dense paragraphs:
    *   **Paragraph 1 (What & Why)**: What was the goal, what approach was taken, and what was accomplished. Include specific technical details — files changed, patterns applied, problems solved. When referencing files inline, use **Compact** (`§`) or **Location** (`file:line`) links per `¶INV_TERMINAL_FILE_LINKS`.
    *   **Paragraph 2 (Outcomes & Next)**: What the current state is, what works, what doesn't yet, and what the logical next steps are. Flag any risks, open questions, or tech debt introduced.
3.  **Output**: Print under the header "## Session Summary".

**Constraints**:
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration in the summary paragraphs.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths referenced inline in the summary MUST be clickable URLs.

---

## PROOF FOR §CMD_REPORT_SUMMARY

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    }
  },
  "required": ["executed"],
  "additionalProperties": false
}
```
