### ¶CMD_OFFER_CLOSING_SNAPSHOT
**Definition**: Offers a closing `/snapshot` on the ticket a session just worked, immediately before the session goes idle. The one reusable command a ticket-bearing skill declares so the tracker learns the outcome — the status transition, the debrief attach, the closing comment. **It OFFERS, it never forces** (`¶INV_OFFER_DONT_FORCE_SKILLS`), and it never writes to the tracker itself: `/snapshot` owns every write under its own batch confirm.
**Concept**: "This session moved `<KEY>`; the tracker still reads `<state>`. Post the close before going idle?"
**Trigger**: Declared as a step in a caller's Close phase, positioned **before** `§CMD_CLOSE_SESSION`.

---

## Why it sits before the idle transition

`engine session idle` activates the idle gate, which restricts tools to `AskUserQuestion`, `Skill`, and engine commands. `/snapshot` commits and posts, so it must be offered while tools are still open. Declaring this step after `§CMD_CLOSE_SESSION` puts the offer behind a gate that blocks it.

---

## Algorithm

### Step 1: Resolve the ticket and its live state
Find the ticket key from, in order: the session's `extraInfo` / `taskSummary`, the current branch name (`<prefix>-NNNN-…`), the debrief's ticket links. The key prefix comes from the project's `## Tracker` config.

No key resolvable → record `decision: "skipped"`, reason `no-ticket`, and return. Do NOT guess a key from an adjacent ticket or from a related-work mention.

With a key, read the ticket's **current** state (`get_issue`) rather than trusting the session's memory of it — a parallel lane may have moved it.

### Step 2: Decide whether there is drift worth reporting
Compare what the session did against what the tracker says. Offer when either holds:
- The session landed commits for this ticket and the ticket sits in a **non-started** state (Backlog / Todo / Triage) or in an in-progress state the work has outrun.
- A `#needs-review` debrief exists and the ticket carries no comment covering it.

Neither holds (the tracker already reflects the work) → record `decision: "skipped"`, reason `no-drift`, and return.

### Step 3: Offer (interactive — a human is at the phase gate)
Present an `AskUserQuestion` naming the drift concretely — the key, the live state, and what landed:

> "`<KEY>` reads **`<live state>`**, and this session landed `<N>` commits + a debrief. Post the closing snapshot before going idle?"
> - **"Run /snapshot"** — commit the reviewed slice, post the comment, move the state, attach the debrief.
> - **"Comment only"** — pass `/snapshot` the intent to skip the state move.
> - **"Decline"** — close with the tracker left as-is.
> - **"Defer"** — note it in the session log and close.

**Decline** and **Defer** are complete, valid outcomes. Record the choice and return to the caller.

### Step 4: Route to `/snapshot`
On accept, invoke `Skill(snapshot, args: "<KEY> — closing snapshot")`, naming it a **closing** snapshot so `/snapshot` takes its closing path: the debrief rides as the ticket's permanent record and the status proposal targets a terminal state.

Hand `/snapshot` the live state read in Step 1 so its transition proposal starts from what the tracker actually says, not from an assumed `In Progress`.

Record `decision: "ran"`. Return to the caller when `/snapshot` reports.

---

## Constraints

- **Offer, never force**: no proof field gates the caller on a snapshot having run. `snapshotOffered` records that the offer was made; `decision` records the human's choice. A declined offer never blocks the close.
- **This command writes nothing to the tracker**: it reads state and routes. Every mutation — comment, status, description, attach — happens inside `/snapshot`, under `/snapshot`'s batch confirm. Do NOT call `save_issue` or `save_comment` here.
- **Read the live state, don't assume it**: propose the transition from what `get_issue` returns now.
- **Placed before `§CMD_CLOSE_SESSION`**: after the idle transition the gate blocks the commit and the post.
- **No tracker → skip cleanly**: a session with no resolvable ticket records `skipped` and closes; it does not file a new issue to have something to snapshot.
- **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: the offer is an `AskUserQuestion`, never bare text.

---

## Callers

Declared as a Close-phase step, before `§CMD_CLOSE_SESSION`:
- **`/implement`** — Phase 4.4, after the council offer.

---

## PROOF FOR §CMD_OFFER_CLOSING_SNAPSHOT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "snapshotOffered": {
      "type": "string",
      "description": "Whether the offer was presented and on what (e.g., 'yes — FIN-1234 reads Backlog, 2 commits landed', or 'skipped — no-ticket')"
    },
    "decision": {
      "type": "string",
      "enum": ["ran", "comment-only", "declined", "deferred", "skipped"],
      "description": "The user's choice: ran (/snapshot dispatched), comment-only, declined, deferred, or skipped (no ticket / no drift)"
    }
  },
  "required": ["snapshotOffered", "decision"],
  "additionalProperties": false
}
```
