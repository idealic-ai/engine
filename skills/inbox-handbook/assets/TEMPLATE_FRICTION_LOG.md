# Recipe friction log — [PROJECT] · [SESSION SLUG]

Blunt account of following [PROJECT]'s Inbox Handbook `## What triage will chase`, **for the purpose of editing that handbook**. Not about the product, not about the findings the run produced.

*Every line must trace to something that actually happened in this run — a call made, a query run, a wrong turn taken. No speculative recipe advice: an unearned line costs the next reader exactly as much as a missing one.*

*The seven buckets below are not a suggestion. They come from a real triage run, and they are ordered so that what the recipe got RIGHT is recorded before what it got wrong — because the most expensive edit is one that cuts a working instruction to make room.*

---

## What was accurate and load-bearing

*What the recipe told you that turned out to be true AND to matter. Where you can prove it, prove it — "X was correct, and here is the evidence the alternative would have failed" is the line that protects an instruction from a future editor's pruning.*

*   [Instruction] — [why it held; what it saved you; the evidence]

## What was missing (and I had to work out myself)

*Facts you needed and had to derive. The test for this bucket: would stating this up front have saved a call, a detour, or a wrong conclusion? Name the fact precisely — a table name, an id identity, an auth model, a retention window, an endpoint shape.*

*   [The fact] — [how you derived it; what it cost; where in the recipe it belongs]

## What was harder than described

*Instructions that are technically correct but compressed — one line in the recipe that turned out to be three or six steps in practice. These usually want a snippet, not a rewrite.*

*   [Instruction as written] — [what it actually took]

## What was unnecessary for this signal

*Steps you performed because the recipe said so, which contributed nothing to THIS report shape. Be careful: "unnecessary for this signal" is not "unnecessary" — say which report shape it was useless for, and whether it would have earned its place on a different one.*

*   [Step] — [why it added nothing here; when it would still be right]

## Where the ordering was wrong

*Not "I would have preferred a different order" — cases where following the stated order led, or nearly led, to a wrong answer. State the report shape that breaks the ordering, because the fix is almost always a branch, not a reversal.*

*   [Ordering as written] — [the report shape it fails on] — [what the right order is for that shape]

## Dead ends (so nobody repeats them)

*Places you looked that held nothing, and traps that cost time. This is the highest-value-per-line bucket: each entry is time the next investigator does not spend. Include the tooling traps, not just the data ones.*

*   [What you tried] → [what you got] — [what to do instead]

## If I had to cut the handbook to its load-bearing core

*The payload. Everything above is evidence for this. State it as three explicit lists — a proposal a human could apply without re-reading the run.*

*   **Keep**: [the instructions that earned their place, from bucket 1]
*   **Add**: [the smallest set of lines that closes bucket 2 and the traps from bucket 6]
*   **Cut**: [what buckets 4 and 5 showed to be dead weight or wrong]

*   **Net effect on length**: [shorter / same / longer — and by roughly how much]

---

*Read-only account. This log proposes; it does not edit the handbook.*
