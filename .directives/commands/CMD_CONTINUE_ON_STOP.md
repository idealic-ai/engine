### ¶CMD_CONTINUE_ON_STOP
**Definition**: The action to take when the Stop hook (`hooks/stop-auto-continue.sh`) refuses to let your turn end and hands it back with a short `decision: block` reason that cites `§CMD_CONTINUE_ON_STOP`. Do the next thing you already know about; when you do not know one, ask `/next` for it; when the next thing is an answer only the user can give, dispatch the skill that owns the question instead of asking it inline; and when there is genuinely nothing, say so in one line and stop. One place, cited by the Stop hook's two-line reason.

**Trigger**: Your turn tried to end and came back with a reason naming this command and a counter suffix `(N of M auto-continues; …)`. The hook fires only in an active session whose `.state.json` does not carry `autoContinue: false`, at most `autoContinueMax` (default 3) times in a row.

**Algorithm** (on an auto-continue):
1.  **Finish the sequence you are in.** If you invoked `/next` recently and are part-way through the sequence it named, carry on with its next step.
2.  **In a live weave, look at the open rows.** If you are conducting a `/loom` that is in its live phase (Phase 1), the next thing is usually an open row — `🔓 Open claims`, `📚 Docs owed` or `🗳️ Boards` in the log.
3.  **Otherwise invoke `/next`.** It reads what state the work is actually in and runs the sequence that advances it, blocking-first.
4.  **Route a question to the skill that owns it.** If what you would wait on is an answer from the user, do NOT hand-roll an `AskUserQuestion` — dispatch the skill that owns it, so a loom's rules apply:
    *   a question that **GATHERS INFORMATION** is `/interrogate`;
    *   a fork that **UNBLOCKS WORK** — a decision only they can make — is `/decide`.

    Either beats stopping with "waiting on your answers", and either beats an inline round, which is the substitution a loom forbids.
5.  **Or stop, in one line.** If there is genuinely nothing to advance and nothing to ask, say so in one line and stop.

**Constraints**:
*   **Do not manufacture work.** An auto-continue is permission to advance known work, not a demand to find some. Step 5 is a correct outcome, not a failure.
*   **A one-line stop ends the series.** The hook reads your turn back: a wake after which you made no tool call is taken as "nothing to advance", and the hook backs off and resets its counter rather than asking again. So do not pad an empty wake with a busy-work tool call — that is what keeps the series going.
*   **Never hand-roll the ask.** A pending question goes to `/interrogate` or `/decide` per step 4, never to an inline `AskUserQuestion` round, in or out of a loom.
*   **Switching it off is the user's call.** The suffix names the off-switch (`autoContinue: false` in `.state.json`, or the loom `Auto-continue` disposition set to off). Do not flip it yourself to get out of a wake; take step 5 instead.

---

## PROOF FOR §CMD_CONTINUE_ON_STOP

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "continuedOnStop": {
      "type": "string",
      "description": "Which step the wake resolved to and what it did (e.g., 'step 1: ran the commit step /next had named', 'step 4: dispatched /decide on the schema fork', 'step 5: nothing to advance, stopped')"
    }
  },
  "required": ["continuedOnStop"],
  "additionalProperties": false
}
```
