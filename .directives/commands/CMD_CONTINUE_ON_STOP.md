### ¶CMD_CONTINUE_ON_STOP
**Definition**: The action to take when the Stop hook (`hooks/stop-auto-continue.sh`) refuses to let your turn end and hands it back with a short `decision: block` reason that cites `§CMD_CONTINUE_ON_STOP`. Do the next thing you already know about; when you do not know one, ask `/next` for it; when the next thing is an answer only the operator can give, write it down as an ask addressed up your chain instead of asking it at this terminal; and when there is genuinely nothing, say so in one line and stop. One place, cited by the Stop hook's two-line reason.

**Trigger**: Your turn tried to end and came back with a reason naming this command and, on its second line, a counter saying how many of the allowed auto-continues this is and how to switch them off. The hook fires only in an active session whose `.state.json` does not carry `autoContinue: false`, at most `autoContinueMax` (default 3) times in a row.

**Algorithm** (on an auto-continue):
1.  **Finish the sequence you are in.** If you invoked `/next` recently and are part-way through the sequence it named, carry on with its next step.
2.  **In a live weave, look at the open rows.** If you are conducting a `/loom` that is in its live phase (Phase 1), the next thing is usually an open row — `🔓 Open claims`, `📚 Docs owed` or `🗳️ Boards` in the log.
3.  **Otherwise invoke `/next`.** It reads what state the work is actually in and runs the sequence that advances it, blocking-first.
4.  **Put a question only the operator can answer in an ask.** If what you would wait on is an answer only the operator can give, do NOT hand-roll an `AskUserQuestion`, and do not stop with "waiting on your answers" either: nobody is at this terminal to answer. Write an ask (`skills/ask/SKILL.md`, whose § Writing one says how to write one the operator can decide from):
    1.  **Find where it goes.** Run `bash ~/.claude/engine/skills/coordinate/scripts/hop.sh target`. It prints `<seat> <pane>`, or `operator`. The ask goes to the **first word** of what it prints, never the whole line.
        *   **Exit 0:** that seat.
        *   **Exit 3:** still that seat (a dead rung was skipped, or the top was dead and it printed `operator`).
        *   **Exit 5** (this seat's live edge cannot be used): if stderr says this seat is not in the live tree and names `FLEET_PARENT='<seat>'`, address that `<seat>`. Otherwise address `operator`. That covers `FLEET_PARENT='unset'`, a `FLEET_PARENT` that is this seat itself or `operator`, a live parent that is the seat itself, and a live parent named `operator`. Do not take a seat from hop's `is stale; using the live @pane_parent` note. This exit-5 split is the director's interim rule; `/coordinate` Step 5 still sends every exit 5 to the operator.
        *   **Exit 2 or 4** (a config or identity error, or a live tree it cannot read): address `operator`.

        On any exit other than 0, start the ask's body with `broken hop: <hop's stderr>`, so its reader sees which edge is broken, and repeat that reason in the pointer of step 3.
    2.  **Write it.** `engine ask new --to <that target>` (the first word alone), with the forks written per that section, prints the ask's path. Then keep working on whatever does not depend on the answer.
    3.  **Leave a pointer** where the next reader looks for an open question, naming the ask's path and what waits on it, so they find the question without reopening your turn. A conductor writes a one-line row under `🔓 Open claims` in its loom log. A lane logs a `## [TAG] ❓ Ask <id>: …` heading in the log it reports into, which is what `engine open-asks` reads; a lane's `🔓 Open claims` row is not seen by that sweep.

    **The exception is an operator who is present at this terminal.** `/interrogate` (a question that gathers information) and `/decide` (a fork that unblocks work) both ask through `AskUserQuestion` here, so they are the route only when the operator is demonstrably at this terminal and driving it. A seat with a parent never uses them on a wake: its question goes up as an ask, even when the answer is the operator's to give. Either route beats stopping, and both beat an inline round, which is the substitution a loom forbids.

5.  **Or stop, in one line.** If there is genuinely nothing to advance and nothing to ask, say so in one line and stop.

**Constraints**:
*   **Never quote the hook's counter text in this file.** The hook recognises its own earlier wakes by a fragment of that counter line. This atom is preloaded at SessionStart, and in a session that was not seeded the Stop hook's fallback delivers it into the transcript after your first tool call on a wake. Either way it sits in the transcript the hook reads, so a copy of the fragment here would be read as a newer wake, and a wake that did real work would be taken for an idle one.
*   **Do not manufacture work.** An auto-continue is permission to advance known work, not a demand to find some. Step 5 is a correct outcome, not a failure.
*   **A one-line stop ends the series.** The hook reads your turn back: a wake after which you made no tool call is taken as "nothing to advance", and the hook backs off and resets its counter rather than asking again. So do not pad an empty wake with a busy-work tool call — that is what keeps the series going.
*   **Never hand-roll the ask.** A question only the operator can answer goes up as an ask per step 4 (`engine ask new --to` the first word `hop.sh target` prints, chosen by its exit code per step 4.1), never to an inline `AskUserQuestion` round, in or out of a loom. `/interrogate` and `/decide` are the route only for an operator present at this terminal, and never for a seat with a parent.
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
      "description": "Which step the wake resolved to and what it did (e.g., 'step 1: ran the commit step /next had named', 'step 4: wrote ask schema-fork to the parent seat and left its pointer', 'step 5: nothing to advance, stopped')"
    }
  },
  "required": ["continuedOnStop"],
  "additionalProperties": false
}
```
