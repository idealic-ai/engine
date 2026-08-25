### ¶CMD_INGEST_CONTEXT_BEFORE_WORK
**Definition**: Present discovered context as a category-level multi-select menu before work begins. Uses `§CMD_DECISION_TREE` with `§ASK_CONTEXT_INGESTION`.
**Rule**: STOP after init. Enter this phase. Do NOT load files until user responds.

**Source sections**: Activate outputs: `## SRC_OPEN_DELEGATIONS`, `## SRC_PRIOR_SESSIONS`, `## SRC_RELEVANT_DOCS`, `## SRC_RELATED_TICKETS`, `## SRC_DELEGATION_TARGETS`. Each contains file paths with distance scores (one per line) or `(none)`, except `SRC_RELATED_TICKETS` (ticket excerpt lines `[KEY] title · state · score`) and delegation targets (a table).

**Algorithm**:
1.  Auto-load `contextPaths` from session parameters (explicitly requested — no menu needed).
2.  Parse activate's sections. Group into **5 categories**:
    *   **Sessions**: `SRC_PRIOR_SESSIONS` results
    *   **Docs**: `SRC_RELEVANT_DOCS` results
    *   **Operational**: `SRC_OPEN_DELEGATIONS`
    *   **Tickets**: `SRC_RELATED_TICKETS` results — related/duplicate Linear tickets. **Load-action differs**: selecting Tickets does NOT load a file (the other 3 do); it **dispatches the `/ticket-search` skill in startup mode** (see step 6), which navigates the SRC_RELATED_TICKETS candidates via its read-only subagent and returns the related/duplicate report.
    *   **Subscribed**: the session's own tickets from `.state.json:tickets[]` (auto-subscribed at activation from the `tickets` param). **Load-action = a cold read**: `engine ticket fetch <all subscribed keys>` with **no `--since`** (the full current thread — comment trees with reactions + lifecycle + attachments), written to a payload file you then read into context. Richer than the shallow `SRC_RELATED_TICKETS` snippet — it's the *complete* state of the tickets you're actually working. The cursor `W` is already seeded (subscribe stamped `.ticketCursor` at activation), so subsequent wake-drains ride this baseline (`¶INV_FULL_READ_SEEDS_CURSOR`). **Pre-select this category** when `.state.json:tickets[]` is non-empty — the user can prune it (`¶INV_OFFER_DONT_FORCE_SKILLS`).
3.  **Curate** — For each non-empty category, select the **top 3** results by distance score (lower = more similar; for Tickets, higher relevance score = better — take the top 3). Drop results that are clearly off-topic despite a good score. No discretionary expansion — fixed top 3.
4.  **All-empty check** — If all 4 categories are empty after curation, skip the menu: announce "No context discovered. Working with contextPaths only." and return.
5.  **Present** — Invoke §CMD_DECISION_TREE with `§ASK_CONTEXT_INGESTION`:
    *   **Hide empty categories** — Only include categories that have curated results. `[SKIP]` is always shown (ensures minimum 2 options).
    *   **Dynamic labels** — Agent appends counts to labels at runtime: `"Sessions (3 found)"`, `"Docs (2 found)"`, `"Operational (1 alert, 2 delegations)"`, `"Tickets (2 found)"`.
    *   **Compact preamble** — Counts only per category. No expanded file lists in the preamble.
    *   **ABC extras** — Agent-generated contextual suggestion packages (combos of categories). Examples: `A: Sessions + Operational | B: Just sessions | C: Pick individual files`. These are convenience bundles — overlap with checkbox options is fine.
6.  **Load** — For each selected category, load all curated items within it. Also load any `@path` inputs from the Other field. If `[SKIP]` is the only selection, load nothing.
    *   **Multi-select priority**: If `[SKIP]` is selected alongside categories, categories win — `[SKIP]` is ignored. `[SKIP]` only takes effect as the sole selection.
    *   **Tickets is a dispatch, not a file-load**: if **Tickets** is selected, do NOT read files — invoke `Skill(skill: "ticket-search")` with **no args**. The skill auto-detects **startup mode** from the `SRC_RELATED_TICKETS` block already in context (and frames its search from the session's `taskSummary`); do NOT pass `"startup"` or any query string as args — the skill reads args as the search *topic*, so an arg would mis-frame the navigation. The `/ticket-search` subagent then navigates the curated `SRC_RELATED_TICKETS` candidates (deep-reads each via `§CMD_READ_RELATED_TICKET`), writes its related/duplicate report to `builds/`, and you then triage. Load the other selected categories' files as usual alongside it.
    *   **Subscribed is a cold read**: if **Subscribed** is selected, run `engine ticket fetch <keys> --out <path>` over ALL `.state.json:tickets[].key` (no `--since` → full current thread), then read the payload file into context — the complete state of the tickets this session works. No curation (load all of the session's own tickets, not a top-3). No `--since`, no cursor write (subscribe already seeded `W`).

---

## ¶ASK_CONTEXT_INGESTION: Choose: Context Ingestion
Trigger: after session activation when RAG discovers non-empty context categories
Extras: [agent-generated contextual suggestion packages — combos of categories based on what's available and the task type]

- [ ] Sessions
  Top 3 RAG session matches by relevance (curated from SRC_PRIOR_SESSIONS)
- [ ] Docs
  Top 3 RAG doc matches by relevance (curated from SRC_RELEVANT_DOCS)
- [ ] Operational
  Open delegations (SRC_OPEN_DELEGATIONS)
- [ ] Tickets
  Related/duplicate Linear tickets (from SRC_RELATED_TICKETS) — selecting this dispatches the `/ticket-search` skill (not a file-load)
- [ ] Subscribed
  The session's own tickets (`.state.json:tickets[]`) — cold-read their full current thread via `engine ticket fetch` (no `--since`). Pre-selected when non-empty.
- [ ] [SKIP] Skip context
  Don't load any RAG results — work with contextPaths only

**Dynamic behavior**: Categories with zero curated results are hidden from the presented options. `[SKIP]` is always shown. Agent populates labels with counts at runtime. The `@` universal prefix works in the Other field for adding specific file paths.

---

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **`¶INV_TRUST_CACHED_CONTEXT`**: Do not re-read files already loaded via `contextPaths` or prior menu selections.
*   **Fixed top 3**: Each category loads at most 3 curated items. No discretionary expansion beyond 3.
*   **`@` escape hatch**: User can type `@path/to/file` in Other to add specific files beyond the curated set. Agent can also offer "Pick individual files" as an ABC extra when the curated set may be insufficient.
*   **Category independence**: Each checkbox is one category — independent, non-overlapping. No option is a superset of another (unlike individual-file options which can overlap).
*   **Cold-read on subscribe (newcomer rule)**: when you subscribe to a ticket *mid-session* (after this ingest ran — e.g. `/ticket-search` fold-into-scope, `/communicate`), pair the `engine ticket subscribe` with a one-off `engine ticket fetch <KEY>` (no `--since`) to load its current thread. That keeps the single shared cursor `W` a clean whole-set cursor: the newcomer is caught up immediately, then rides `W` with the rest — no per-ticket floor needed.

---

## PROOF FOR §CMD_INGEST_CONTEXT_BEFORE_WORK

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "contextSourcesPresented": {
      "type": "string",
      "description": "Summary of context sources offered to the user (e.g., '4 categories: Sessions (3), Docs (2), Operational (1), Tickets (2)')"
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
