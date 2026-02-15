### ¶CMD_RESOLVE_CROSS_SESSION_TAGS
**Definition**: During synthesis, traces fulfilled REQUEST files back to their requesting sessions and resolves the original inline tags there. Closes the loop: REQUEST fulfilled → source tag resolved.
**Classification**: STATIC

**Why**: When session B fulfills a REQUEST from session A, the REQUEST file's tag gets swapped to `#done-X` (enforced by `¶INV_REQUEST_BEFORE_CLOSE`). But the **original** inline tag in session A's debrief — where the user first said `#needs-implementation` — stays unresolved. This command follows the REQUEST→source chain to close that gap.

**Algorithm**:

1.  **Identify Fulfilled Requests**: Check `requestFiles` from `.state.json`. For each request file that this session fulfilled (tag is now `#done-*` or about to be):
    *   Read the REQUEST file to find the **requesting session** reference (typically in the `## Context` or `## Requesting Session` section).
    *   Extract the original tag noun (e.g., `implementation` from `#needs-implementation`).
2.  **Trace Back to Source**: For each requesting session found:
    *   Locate the requesting session's debrief file (IMPLEMENTATION.md, ANALYSIS.md, etc.).
    *   Search for the matching inline tag (`#needs-X` or `#delegated-X`) that originated the request.
    *   If the tag is on the `**Tags**:` line, use `engine tag swap`.
    *   If the tag is inline, use `engine tag swap --inline`.
3.  **If No Request Files**: Output in chat: "No request files to trace back." No log entry.
4.  **If Source Tags Found**: Present via `AskUserQuestion` (multiSelect: true):
    *   `question`: "These request source tags in other sessions can now be marked done. Resolve them?"
    *   `header`: "Source tags"
    *   `options` (up to 4, batch if more):
        *   `"Resolve: [source session]/[file] — [tag]"` — description: `"Swap to #done-* with breadcrumb"`
    *   For each selected:
        ```bash
        engine tag swap "$SOURCE_FILE" '#needs-X' '#done-X'
        ```
        Append breadcrumb near the resolved tag:
        `> Resolved by sessions/[CURRENT_SESSION] ([skill], [date])`
5.  **If Source Not Found**: Log: "Could not trace back to source for [request file]. Source session may be missing or debrief absent." Continue to next request.
6.  **Report**: "Resolved N source tags across M requesting sessions." or skip silently if none.

**Constraints**:
*   **Chain-only**: Only follows explicit REQUEST→source chains. No speculative scanning across all sessions.
*   **Breadcrumbs**: Every resolution must include a breadcrumb pointing to the resolving session.
*   **Graceful degradation**: If the requesting session's debrief doesn't exist or the source tag is already resolved, skip silently.
*   **No self-resolution**: Never resolve tags in the current session directory.
*   **Read-only on skip**: If the user deselects all options, no files are modified.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions MUST use `AskUserQuestion`.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output; bare tags only on `**Tags**:` lines or in `engine tag` commands.

---

## PROOF FOR §CMD_RESOLVE_CROSS_SESSION_TAGS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "requestsTraced": {
      "type": "string",
      "description": "Count and sessions traced (e.g., '2 requests traced to 2 sessions')"
    },
    "sourceTagsResolved": {
      "type": "string",
      "description": "Count of source tags resolved (e.g., '2 swapped to #done-*')"
    }
  },
  "required": ["executed"],
  "additionalProperties": false
}
```
