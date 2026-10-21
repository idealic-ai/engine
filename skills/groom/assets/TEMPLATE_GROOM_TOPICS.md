# Topic List — `<project>`
**Usage**: Phase 1 writes this; Phase 2 reads it; `/decide --items <this path>` reads the **Decision fork** blocks and writes its outcomes back into them.
**Rule**: one block per TOPIC, never one per member. A single-member topic is a legitimate topic.
**Rule**: a member is one item from any source — an inbox signal, an open ticket, or an un-ticketed leftover. A topic mixing sources is the intended shape, not an edge case.
**Rule**: `/decide` reads the **Decision fork** block and the evidence above it, and fills **Disposition**. It leaves the fork framing and **Dispatch** alone — a section still carrying its placeholder is one nobody has filled yet, not an empty answer.
**Marker values**: one per outcome, per `§INV_GROOM_MARKS_WHAT_IT_WRITES` — recorded here so the write half is auditable from this ledger and not only from the protocol. A blank on a disposed topic means the exclusion leaks next pass.

**Drained**: inbox [N] new · [M] still-owed (unresolved root threads) · tickets [T] open ([X] excluded as In-Progress) · leftovers [L] *(or the one-line degradation)* · **Taken this pass**: [K] — *[the ruling that set the bound, and who gave it]*
**Next move**: [KEY — title] — *[why it ranks first, from the row; the runner-up it beat]*

---

## [SLUG] — [the subject, one sentence]

*   **Why these are one subject**: [one clause — the shared cause, the shared surface, or the shared ask]
*   **Sources**: [which of inbox · tickets · leftovers this topic draws on — name the mix]
*   **Channels**: [which inbox channels its signals arrived on, or `none — no inbox member`]
*   **Members**:
    *   `inbox` — [🔗 comment abcd1234](<deep link>) — [reporter] — [what it reported, one clause]
    *   `ticket` — [KEY](<issue link>) — [state] · [milestone] · ~[estimate]pt · [blocked?] — [the relation that joined it: relatedTo/parent/blocks/blockedBy/duplicateOf KEY]
    *   `leftover` — [source pointer: the debrief, snapshot comment, or LESSONS line] — [the followup, one clause]
*   **Ripe?**: [yes — what makes it so | no — the gap, and whether /triangulate was offered | already filed — nothing to establish]
*   **Related**: [ticket keys this may fold into or duplicate, READ from the rows' relation keys — or `none found`]
*   **Dials read**: [which Ticketing Strategy bullet bears on this topic]

### Decision fork *(Phase 1 frames — this is what `/decide --items` reads)*
*   **The fork**: Which outcome does `[SLUG]` take?
*   **Unblocks**: [the Phase 3 dispatch this topic is waiting on — name the thread it becomes, or what stays unfiled until it is settled]
*   **Options, with this topic's trade-off for each** *(omit any outcome this topic's members cannot take, or the dials rule out, and say which — an already-filed member cannot graduate)*:
    *   **graduate** *(unfiled members only)* — [what a ticket here buys, and what it costs — Volume/Size as they read for THIS topic]
    *   **fold** — [the parent it would join, and what is lost by making it a facet; for ticket members, the survivor and why]
    *   **route 🛠️** — [why the subject may be machinery rather than product]
    *   **marinate** *(unfiled members)* — [what is still missing, and what would make it ripe]
    *   **dispatch as-is** *(already-filed)* — [why it is ready to ride a thread untouched]
    *   **re-scope** *(already-filed)* — [how the topic shows the ticket's shape is wrong, and what the thread would carry]
    *   **defer** *(already-filed)* — [why not this pass; the rank it keeps meanwhile]
*   **Lean**: [the reading Phase 1 arrived at, and the strongest case against it]

### Disposition *(Phase 2 fills — or `/decide` writes back here)*
*   **Outcome**: [graduate | fold | route 🛠️ | marinate | dispatch as-is | re-scope | defer] — exactly one, for the whole topic
*   **Decided against**: [the outcomes not taken, each with its one-clause reason — the half that stops the next pass re-ruling this topic]
*   **Where it went**: [ticket key(s) · the parent it folded into · the channel comment · `marinating` · `rides its own ticket` · `re-scope carried to the thread` · `deferred at rank N`]
*   **Per member**: [what became of each member under the one outcome — the half a mixed topic needs]
*   **Why**: [the dial or the evidence that decided it]
*   **Marker**: [the marker prefix the pointer reply led with, or `none posted — no channel thread (ticket/leftover member)`, or `none posted — <other reason>`]
*   **Threads resolved**: [comment ids resolved after the pointer reply, or `left open — <reason>`]
*   **Decided by**: [`Phase 2 confirm` · `/decide — <record path>`]

### Dispatch *(Phase 3 fills)*
*   **Thread**: [threadId — the slug, or the ticket key it upgraded to] | `not dispatched — <reason>`

---

## [NEXT-SLUG] — [...]

---

## Deferred (not taken this pass)
*Each keeps the state it already had — an inbox signal stays unresolved, a ticket stays open at its rank, a leftover stays in the debrief it was found in. The next pass re-offers all three.*

*   `inbox` — [🔗 comment ijkl9012](<deep link>) — [one clause]
*   `ticket` — [KEY](<issue link>) — [one clause] — rank [N]
*   `leftover` — [source pointer] — [one clause] — *reason also written to the debrief `## Leftovers`, which the next gather reads*
