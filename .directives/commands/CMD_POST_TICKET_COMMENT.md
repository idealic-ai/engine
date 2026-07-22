### ¶CMD_POST_TICKET_COMMENT
**Definition**: The ONE canonical path for posting a comment to a Linear ticket. Bundles the subscribe-check + the post + the sibling-notify into a single atom so the notify (which wakes other local agents) can never be forgotten.
**Rule**: Any skill or agent about to post a ticket comment routes it through here — never a bare `save_comment` + hand-rolled notify. See `¶INV_TICKET_COMMENT_VIA_CMD` (AGENTS.md).

**Prerequisites**:
*   **An active engine session** (the subscribe-check reads/writes its `.state.json:tickets[]`). Standalone (no session) → the post still lands, but the subscribe-check + notify are skipped (no local siblings to wake); say so.
*   **Linear MCP present** (`mcp__linear-server__*`). Headless / no-MCP → cannot post; report the skipped post and stop, never hang.

**Parameters**:
```json
{
  "ticketKey": "<PREFIX>-NNNN — resolved from § Tracker / args / session tickets[]",
  "body": "the comment body, Markdown, plain content (real newlines, no escaped \\n)",
  "note": "decision-grade one-liner for the sibling notify (see step 3)"
}
```

**Algorithm**:
1.  **Subscribe-check** (idempotent): `engine ticket subscribe <ticketKey>`. This ensures the current session is in its own `tickets[]` so it hears any reply on the same ticket. Safe to run every time — a no-op if already subscribed. Skip only when standalone (no active session).
2.  **Post**: resolve `<ticketKey>` → Linear issue id if needed (`mcp__linear-server__get_issue`), then post the body via `mcp__linear-server__save_comment({ issueId: "<ticketKey>", body })` — the same create/update-comment tool the skills use. Pin the `issueId`; capture the returned comment URL.
3.  **Notify**: `engine ticket notify <ticketKey> "<note>" --from <this-session>` — wakes every *other* local session subscribed to the ticket (never yourself). **Write the note decision-grade**: on wake a sibling drains ONLY this note (no Linear fetch), so it must answer *"do I need to act?"* alone — include the **commit SHA** if one landed, the **one-phrase what-changed**, and an **affects-you verdict** (`no action` / `rebase onto <sha>` / `your files untouched` / `needs your reply`). One line, terse. E.g. `engine ticket notify FIN-2833 "2db0ecea6: entities/ scaffold committed; scope.ts left for FIN-2737 — no action for you"`. Best-effort: a notify failure is reported, never aborts the post. Skip when standalone.

**Constraints**:
*   **Notify is not optional.** The whole point of this atom is that the notify fires whenever a comment posts — bundling it with the post is what stops it being forgotten. It is a **local dirty-flag, not an outward post**: no separate confirm, best-effort, always after the post lands.
*   **Never overwrite the caller's confirm.** This atom is the *mechanism*; the caller owns whether to post at all (e.g. `/snapshot`'s batch confirm). Don't add a second gate — post when the caller says post.
*   **Single source of the subscribe+notify behavior.** `/communicate`, `/snapshot`, `/pr` and any ad-hoc post reference this atom so the three steps stay identical across callers. This operationalizes AGENTS.md §"Notify when you post a ticket comment" at the exact operative step.

---

## PROOF FOR §CMD_POST_TICKET_COMMENT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "ticketKey": {
      "type": "string",
      "description": "The <PREFIX>-NNNN key the comment posted to"
    },
    "commentPosted": {
      "type": "string",
      "description": "Comment URL if posted, or 'skipped — <reason>' (e.g. no Linear MCP)"
    },
    "notified": {
      "type": "string",
      "description": "The decision-grade note sent, or 'skipped — standalone / no siblings'"
    }
  },
  "required": ["ticketKey", "commentPosted", "notified"],
  "additionalProperties": false
}
```
