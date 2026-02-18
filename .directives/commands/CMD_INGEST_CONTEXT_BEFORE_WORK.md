### ¶CMD_INGEST_CONTEXT_BEFORE_WORK
**Definition**: Present discovered context as a category-level multi-select menu before work begins. Uses `§CMD_DECISION_TREE` with `§ASK_CONTEXT_INGESTION`.
**Rule**: STOP after init. Enter this phase. Do NOT load files until user responds.

**Source sections**: Activate outputs: `## SRC_ACTIVE_ALERTS`, `## SRC_OPEN_DELEGATIONS`, `## SRC_PRIOR_SESSIONS`, `## SRC_RELEVANT_DOCS`, `## SRC_DELEGATION_TARGETS`. Each contains file paths with distance scores (one per line) or `(none)`, except delegation targets which outputs a table.

**Algorithm**:
1.  Auto-load `contextPaths` from session parameters (explicitly requested — no menu needed).
2.  Parse activate's sections. Group into **3 categories**:
    *   **Sessions**: `SRC_PRIOR_SESSIONS` results
    *   **Docs**: `SRC_RELEVANT_DOCS` results
    *   **Operational**: `SRC_ACTIVE_ALERTS` + `SRC_OPEN_DELEGATIONS` combined
3.  **Curate** — For each non-empty category, select the **top 3** results by distance score (lower = more similar). Drop results that are clearly off-topic despite low distance. No discretionary expansion — fixed top 3.
4.  **All-empty check** — If all 3 categories are empty after curation, skip the menu: announce "No context discovered. Working with contextPaths only." and return.
5.  **Present** — Invoke §CMD_DECISION_TREE with `§ASK_CONTEXT_INGESTION`:
    *   **Hide empty categories** — Only include categories that have curated results. `[SKIP]` is always shown (ensures minimum 2 options).
    *   **Dynamic labels** — Agent appends counts to labels at runtime: `"Sessions (3 found)"`, `"Docs (2 found)"`, `"Operational (1 alert, 2 delegations)"`.
    *   **Compact preamble** — Counts only per category. No expanded file lists in the preamble.
    *   **ABC extras** — Agent-generated contextual suggestion packages (combos of categories). Examples: `A: Sessions + Operational | B: Just sessions | C: Pick individual files`. These are convenience bundles — overlap with checkbox options is fine.
6.  **Load** — For each selected category, load all curated items within it. Also load any `@path` inputs from the Other field. If `[SKIP]` is the only selection, load nothing.
    *   **Multi-select priority**: If `[SKIP]` is selected alongside categories, categories win — `[SKIP]` is ignored. `[SKIP]` only takes effect as the sole selection.

---

### ¶ASK_CONTEXT_INGESTION
Trigger: after session activation when RAG discovers non-empty context categories
Extras: [agent-generated contextual suggestion packages — combos of categories based on what's available and the task type]

## Decision: Context Ingestion
- [ ] Sessions
  Top 3 RAG session matches by relevance (curated from SRC_PRIOR_SESSIONS)
- [ ] Docs
  Top 3 RAG doc matches by relevance (curated from SRC_RELEVANT_DOCS)
- [ ] Operational
  All active alerts + open delegations (SRC_ACTIVE_ALERTS + SRC_OPEN_DELEGATIONS)
- [SKIP] [ ] Skip context
  Don't load any RAG results — work with contextPaths only

**Dynamic behavior**: Categories with zero curated results are hidden from the presented options. `[SKIP]` is always shown. Agent populates labels with counts at runtime. The `@` universal prefix works in the Other field for adding specific file paths.

---

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **`¶INV_TRUST_CACHED_CONTEXT`**: Do not re-read files already loaded via `contextPaths` or prior menu selections.
*   **Fixed top 3**: Each category loads at most 3 curated items. No discretionary expansion beyond 3.
*   **`@` escape hatch**: User can type `@path/to/file` in Other to add specific files beyond the curated set. Agent can also offer "Pick individual files" as an ABC extra when the curated set may be insufficient.
*   **Category independence**: Each checkbox is one category — independent, non-overlapping. No option is a superset of another (unlike individual-file options which can overlap).

---

## PROOF FOR §CMD_INGEST_CONTEXT_BEFORE_WORK

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "contextSourcesPresented": {
      "type": "string",
      "description": "Summary of context sources offered to the user (e.g., '3 categories: Sessions (3), Docs (2), Operational (1)')"
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
