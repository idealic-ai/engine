### ¶CMD_DRAIN_TICKET_QUEUE_ON_WAKE
**Definition**: The action to take when a background `engine ticket watch` wakes you — read the ticket delta the watcher already fetched, act on it, and re-arm the watcher. The watcher **auto-drains** on wake: it fetches the matched tickets from Linear since the shared cursor `W` into a payload **file** (one `engine ticket fetch` payload — comment trees with reactions + normalized lifecycle + attachments), advances `W`, clears the acked queue, and writes the matched key(s) + the payload-file **path** to its output. So your job is to read that file and continue — no per-comment API calls. One place, cited by the watch gate and the watcher's wake-description.

**Trigger**: A background `engine ticket watch` completes and re-invokes you (a background-task wake). Whenever the session subscribes to tickets the gate keeps a live watcher armed, so you hit this on every cross-agent ticket update.

**Algorithm** (on wake):
1.  **Read the wake output.** The watcher's output is `ticket update — <KEY(s)>` followed by a one-line JSON object `{ keys, since, payload }` (read it from the wake notification, or from the persisted-output file if the harness truncated it). `payload` is a **file path** — the watcher already fetched the delta there; the tiny stdout never carries the comments, so it can't be truncated.
2.  **Read the payload file.** Open `payload` (a `ticket fetch` JSON: `{ since, fetchedAt, keys, tickets: [ { identifier, comments: <tree w/ reactions>, lifecycle, attachments, … } ] }`) and act on the new activity for your current task. The watcher has already advanced `W` and cleared the queue — no fetch, no `read`, no per-comment MCP call on your side.
3.  **Handle a failed drain.** If the output says `FETCH FAILED (since=…) — cursor NOT advanced`, the watcher's fetch failed (network/auth) and `W` was deliberately left un-advanced (`¶INV_WRITE_BEFORE_WATERMARK`). Just re-arm — the next wake re-drains the same window. If it keeps failing, check `LINEAR_API_KEY`.
4.  **Re-arm.** Start a fresh background `engine ticket watch` (Bash `run_in_background: true`) whose wake-instruction description cites `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`, so the next wake resolves the same way.

**Constraints**:
*   **Read the payload FILE, not stdout.** The comments live in the file the watcher wrote; stdout carries only its path (+ keys). This is deliberate — shell stdout truncates under the harness, a file does not.
*   **Re-arm via `run_in_background`, never a shell `&`.** A detached `&` fires but never wakes you.
*   **Sub-agents don't watch.** The gate exempts sub-agents — arming and draining the watcher is the orchestrator's job.
*   **Manual drain still exists.** `engine ticket read` performs a local queue drain (advances the cursor, clears the queue) if you ever need one outside the wake path; and `engine ticket fetch <KEY(s)> [--since]` fetches a ticket delta on demand.

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
