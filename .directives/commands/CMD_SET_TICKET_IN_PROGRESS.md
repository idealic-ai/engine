### ¶CMD_SET_TICKET_IN_PROGRESS
**Definition**: When the active session has an associated Linear ticket, advance that ticket's workflow status to **In Progress** as execution begins. A non-regressing, silent status transition — never a comment, notify, or backlink.
**Rule**: Fired as a phase step at the moment work starts (the Execution gateway of `/fix` and `/implement`, alongside `§CMD_SELECT_EXECUTION_PATH`). Resolves the ticket from the session's **explicit** association only; with no associated ticket it is a silent no-op.

**Prerequisites**:
*   **An active engine session with a ticket association** — reads `.state.json:tickets[].key` (seeded from session-params `tickets[]` on activate, e.g. `/fix FIN-2833`). No associated ticket → silent no-op (echo the scan, skip). No git-branch / session-slug inference.
*   **Linear MCP present** (`mcp__linear-server__*`). Headless / no-MCP → skip, report `skipped — no Linear MCP`, never hang.

**Parameters**: none — the ticket(s) come from session state.

**Algorithm**:
1.  **Resolve** the associated ticket key(s) from `.state.json:tickets[].key` (`engine ticket list --json`, or jq the state file). Empty → `ticketAdvanced = "skipped — no ticket associated"`; echo the scan and stop. For each associated key:
2.  **Read current state**: `mcp__linear-server__get_issue({ id: "<KEY>" })` → capture the issue's current `state.name` and its `team`.
3.  **Classify** the current state: `mcp__linear-server__list_issue_statuses({ team: "<team>" })` → each status carries a `type` (`triage | backlog | unstarted | started | completed | canceled`). Match the current state's name to find its type.
    *   type ∈ {`started`, `completed`, `canceled`} → **no-op** (`ticketAdvanced = "no-op — already <state>"`). Never move a ticket backward or re-open a finished one. Continue to the next key.
    *   type ∈ {`triage`, `backlog`, `unstarted`} → advance (step 4).
4.  **Pick target**: from the same status list, choose the `started`-type state named "In Progress" if present, else the first `started`-type state. Capture its id/name.
5.  **Advance**: `mcp__linear-server__save_issue({ id: "<KEY>", state: "<target state id or exact name>" })`.
6.  **Report** one line to chat — `<KEY>: <old state> → In Progress`. No comment, no `engine ticket notify`, no link/attachment.

**Constraints**:
*   **Non-regressing.** Only advances a ticket sitting in an unstarted-type state (triage/backlog/unstarted). A ticket already In Progress, Done, or Canceled is left untouched — so a re-run (overflow resume, a second `/fix` on a shipped ticket) is a safe no-op. **The state guard IS the idempotency** — no `.state.json` marker is needed.
*   **Silent status flip, not an outward post.** This changes only the ticket's workflow column. It never posts a comment, adds a link/attachment, or notifies siblings — deliberately *does not* start references. Report the flip in one chat line; no per-invocation confirm (the behavior is opt-in by having attached a ticket to the session).
*   **Explicit association only.** Resolves from `.state.json:tickets[]`, never from the git branch or session slug — it acts solely on a ticket the user actually attached to the session.
*   **Best-effort.** A get / list / save failure is reported (`ticketAdvanced = "error — <reason>"`) and never aborts the phase; the work proceeds.
*   **Multiple tickets.** If several are associated, apply steps 2–6 to each and report one line per key; `ticketAdvanced` summarizes all (e.g. `FIN-1: Todo→In Progress; FIN-2: no-op — already Done`).
*   **Not a comment path.** This is distinct from `§CMD_POST_TICKET_COMMENT` (which posts + notifies). Do not route status changes through that atom, and do not add a comment here.

---

## PROOF FOR §CMD_SET_TICKET_IN_PROGRESS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "ticketAdvanced": {
      "type": "string",
      "description": "Outcome per associated ticket: '<KEY>: <old>→In Progress', 'no-op — already <state>', 'skipped — no ticket associated', or 'skipped — no Linear MCP'"
    }
  },
  "required": ["ticketAdvanced"],
  "additionalProperties": false
}
```
