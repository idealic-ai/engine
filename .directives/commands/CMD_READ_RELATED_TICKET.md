### ¶CMD_READ_RELATED_TICKET
**Definition**: The ONE canonical path for reading a *related* Linear ticket READ-ONLY. Given a ticket KEY, it resolves the issue, reads its state, and pulls the comment thread into a single normalized object the caller can classify (related-for-context vs duplicate/overlapping-work). Bundles the get_issue + state-read + list_comments sequence into a single atom so every caller navigates a ticket identically.
**Rule**: Any skill or agent about to *read a candidate ticket for triage* routes it through here — never a bare `get_issue` with an ad-hoc shape. `/ticket-search` (its subagent), and inline callers (intake sweep, inbox-triage, ticket dedup — future convergence) all cite this atom so the read stays identical across sites.
**Constraint**: **READ-ONLY.** This atom NEVER writes — no create/update/comment/status-change/subscribe. Subscribing is a *separate* suggested action the caller may take via `engine ticket subscribe`; this atom does not do it and does not mutate any Linear or session state.

**Prerequisites**:
*   **Linear MCP present** (`mcp__linear__*`). Headless / no-MCP → cannot read; report the skipped read and stop, never hang.
*   **Deferred tools loaded**: the caller loads the read tools via `ToolSearch` before the first call — `select:mcp__linear__get_issue,mcp__linear__list_comments` (add `mcp__linear__get_issue_status` only if a distinct status read is warranted; the `state` on the issue payload usually suffices). Same tool-loading idiom as `/communicate` and `/probe`.
*   **No session required**: this is a pure read, so behavior is identical with or without an active engine session — no `.state.json` is read or written. (Contrast `§CMD_POST_TICKET_COMMENT`, whose subscribe-check needs a session.) When standalone, nothing is skipped — the read is the whole atom.

**Parameters**:
```json
{
  "ticketKey": "<PREFIX>-NNNN — resolved from § Tracker / args / a candidate list (e.g. SRC_RELATED_TICKETS)",
  "since": "OPTIONAL ISO datetime — client-side comment filter; there is NO server-side `since` on list_comments"
}
```

**Algorithm**:
1.  **Resolve + read the issue**: `mcp__linear__get_issue` with the `FIN-1234` KEY. Capture the normalized fields: `{ id, identifier, title, url, state{ name, type }, priority, description, assignee, project, updatedAt }`. Pin the returned issue `id` for the comment call.
2.  **Read the state** from that same payload — do NOT make a second call for it. Use `state.name` (human label, e.g. `In Progress`) **and** `state.type` (the machine bucket). `type` is load-bearing — it drives the caller's dup-callout split — so classify it **totally** across Linear's SIX `WorkflowState.type` values (never a partial enum, or the common case falls through):
    *   `completed` → **done, already built** → reuse/skip.
    *   `canceled` → **deliberately dropped** → investigate WHY before rebuilding (a canceled duplicate was abandoned, NOT built — do not tell the caller to "reuse" it).
    *   **everything else** (`triage`, `backlog`, `unstarted`, `started`) → **open / not-yet-built → coordinate, may be duplicating**. A backlog/triage ticket someone else already filed is *the* headline dup case — it must land in the open bucket, never fall through.
    Prefer the `state` already on the issue payload; `mcp__linear__get_issue_status` looks up a workflow-state *definition* (needs id+name+team) and is NOT a fallback for reading this issue's current state — don't use it for that.
3.  **Read the comment thread**: `mcp__linear__list_comments` on the pinned issue `id`. Note there is **no server-side `since` filter** — pass the whole thread through; if the caller supplied `since`, filter client-side (`comment.createdAt >= since`), the same idiom `/communicate` uses on wake.
4.  **Return normalized**: assemble the read into one object for the caller to classify — never a raw MCP payload:
    ```json
    {
      "key": "FIN-1234",
      "title": "…",
      "url": "https://linear.app/…",
      "state": "In Progress",
      "stateType": "started",
      "priority": 2,
      "description": "… (full body)",
      "assignee": "…",
      "project": "…",
      "updatedAt": "2026-07-29T…",
      "comments": [ { "author": "…", "at": "2026-07-…", "body": "…" } ]
    }
    ```

**Constraints**:
*   **Read-only, always.** The whole point of this atom is a side-effect-free navigation — no write tool is ever in its path. A caller that then wants to subscribe/comment/transition routes *that* through the dedicated atom (`engine ticket subscribe`, `§CMD_POST_TICKET_COMMENT`, `§CMD_SET_TICKET_IN_PROGRESS`) as a separate, explicit step.
*   **Single source of the read shape.** `/ticket-search` and any inline triage caller reference this atom so the `{ key, …, stateType, comments[] }` shape stays identical across sites — a caller must not hand-roll its own subset, or downstream classifiers drift.
*   **Never overwrite the caller's classification.** This atom is the *mechanism* (fetch + normalize); the caller owns the verdict (related-for-context vs duplicate/overlapping). Don't editorialize in the return — return the facts, let the caller judge.
*   **`state.type` confirmed** live on Linear's `Issue` (the `searchIssues` GraphQL path returns `state{name,type}` with real values — `completed`/`canceled`/`started`/`unstarted`/`backlog`), and ticket states read cleanly via the MCP path. Still: prefer the `state` on the issue payload and treat an unexpectedly-absent `.type` as **open + flag** (fail-open) rather than a silent drop — the CLI does the same.

---

## PROOF FOR §CMD_READ_RELATED_TICKET

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "ticketRead": {
      "type": "string",
      "description": "The <PREFIX>-NNNN key read, with state + comment count (e.g. 'FIN-1234: In Progress, 4 comments'), or 'skipped — <reason>' (e.g. no Linear MCP)"
    },
    "stateType": {
      "type": "string",
      "description": "The state.type bucket driving the caller's dup-callout split — one of Linear's six WorkflowState.type values (triage/backlog/unstarted/started = open; completed = built; canceled = dropped)"
    }
  },
  "required": ["ticketRead", "stateType"],
  "additionalProperties": false
}
```
