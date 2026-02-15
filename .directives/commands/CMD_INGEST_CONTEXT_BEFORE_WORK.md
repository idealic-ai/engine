### ¶CMD_INGEST_CONTEXT_BEFORE_WORK
**Definition**: Present discovered context as a multichoice menu before work begins.
**Rule**: STOP after init. Enter this phase. Do NOT load files until user responds.

**Categories**: Activate outputs sections: `## SRC_ACTIVE_ALERTS`, `## SRC_OPEN_DELEGATIONS`, `## SRC_PRIOR_SESSIONS`, `## SRC_RELEVANT_DOCS`, `## SRC_DELEGATION_TARGETS`. Each contains file paths (one per line) or `(none)`, except delegation targets which outputs a table.

**Algorithm**:
1.  Auto-load `contextPaths` from session parameters (explicitly requested — no menu needed).
2.  Parse activate's sections. Drop empty categories and already-loaded paths.
3.  **Curate** — For each non-empty category (Sessions, Docs), select **up to 3 best** results:
    *   **Primary signal**: Distance score (lower = more similar). Rank by score.
    *   **Secondary signal**: Agent judgment — does the result's topic/content actually relate to the current task? A low-distance result about an unrelated topic should be skipped in favor of a slightly higher-distance result that's on-topic.
    *   **Discretion**: Include **more than 3** if additional results are genuinely relevant (e.g., multiple prior sessions that each contributed to the current feature). The default is 3; extras require justification.
    *   **Fewer than 3 available**: Show all of them. No filtering needed.
    *   Alerts and delegations are NOT curated — always include all (they are operational, not search results).
4.  Build a single `AskUserQuestion` (multiSelect: true, max 4 options) from the **curated** set:
    *   Each curated item is a separate option (label=clickable path per `¶INV_TERMINAL_FILE_LINKS`, description=category + relevance note).
    *   If total curated options > 4, promote largest categories to bulk until ≤ 4.
    *   **All empty** → skip menu, prompt for free-text paths via "Other".
5.  Load selected items + any "Other" free-text paths.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **`¶INV_TRUST_CACHED_CONTEXT`**: Do not re-read files already loaded via `contextPaths` or prior menu selections.

---

## PROOF FOR §CMD_INGEST_CONTEXT_BEFORE_WORK

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "contextSourcesPresented": {
      "type": "string",
      "description": "Summary of context sources offered to the user"
    },
    "filesLoaded": {
      "type": "string",
      "description": "Count or list of files loaded into context"
    }
  },
  "required": ["contextSourcesPresented", "filesLoaded"],
  "additionalProperties": false
}
```
