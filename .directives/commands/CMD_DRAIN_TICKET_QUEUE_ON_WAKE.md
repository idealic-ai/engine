### ¶CMD_DRAIN_TICKET_QUEUE_ON_WAKE
**Definition**: The action to take when a background `engine ticket watch` wakes you — drain the queued ticket update, fetch its new comments, act on them, and re-arm the watcher. The watcher self-drains on wake: it advances the read watermark and writes the matched ticket key(s) + a per-ticket `since` timestamp to its output, so your job is to consume that output and continue. One place, cited by the watch gate and the watcher's wake-description.

**Trigger**: A background `engine ticket watch` completes and re-invokes you (a background-task wake). Whenever the session subscribes to tickets the gate keeps a live watcher armed, so you hit this on every cross-agent ticket update.

**Algorithm** (on wake):
1.  **Read the drained update.** The watcher's output is `ticket update — <KEY(s)>` followed by a `[{ticket, since}]` JSON array. Read it from the wake notification — and **if the harness truncated the output into a file** ("Output too large → saved to `<path>`"), open that file to get the full `{ticket, since}`. Always read one or the other; act on the payload, never on a bare "exit 0".
2.  **Fetch the new comments.** For each `{ticket, since}`, pull that Linear ticket's comments newer than `since` via the Linear MCP (`mcp__linear-server__list_comments` / `get_issue`), and act on them for your current task.
3.  **Re-arm.** Start a fresh background `engine ticket watch` (Bash `run_in_background: true`) whose wake-instruction description cites `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`, so the next wake resolves the same way.

**Constraints**:
*   **Watch for the output wherever it lands.** The drain payload is in the completion notification, or in the persisted-output file the harness writes when output is truncated — read one before acting.
*   **Re-arm via `run_in_background`, never a shell `&`.** A detached `&` fires but never wakes you.
*   **Sub-agents don't watch.** The gate exempts sub-agents — arming and draining the watcher is the orchestrator's job.
*   **Manual drain still exists.** `engine ticket read` performs an explicit drain if you ever need one outside the wake path; the wake path doesn't require it.

---

## PROOF FOR §CMD_DRAIN_TICKET_QUEUE_ON_WAKE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "ticketQueueDrained": {
      "type": "string",
      "description": "Wake outcome (e.g., 'read {FIN-123, since t} from wake output, fetched its new comments, re-armed the watcher')"
    }
  },
  "required": ["ticketQueueDrained"],
  "additionalProperties": false
}
```
