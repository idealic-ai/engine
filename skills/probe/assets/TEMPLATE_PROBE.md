# Probe Report: [Intent]
**Tags**: #needs-review
*Written by the investigator sub-agent at the end of its run. This is the authoritative account of what was asked, what was found, and what the evidence actually shows. It is read downstream by THREE consumers: the **orchestrator** (which spot-checks the load-bearing evidence and triages the findings with the user), whatever skill a finding is handed to (`/ticket`, `/analyze`, `/experiment`), and the NEXT agent (via `reusableFacts` → `LESSONS.md`). Fill every field for all three readers.*

**Slug**: `[slug]`
**Status**: [Answered / Partial / Inconclusive / Blocked]

## 1. The Answer
*Lead with it. You were asked a question — answer it before anything else. Process comes later.*

*   **Intent (the question)**: "[The question, verbatim as it was handed to you.]"
*   **Answer**: "[The direct answer in 2-4 sentences. If the evidence doesn't settle it, say exactly that — an honest unknown is a successful probe. If the question turned out to be the wrong one, say so, then answer the right one.]"
*   **Confidence**: [High / Medium / Low] — "[What would raise it: the query you couldn't run, the file you couldn't reach, the person who'd know.]"

## 2. Sources Probed
*What you actually looked at, and how. Name what you skipped — a silent skip reads as 'covered'.*

*   **Code / files**: "[Areas swept + how — e.g. 'grepped packages/estimate/src/** for detectFlat, read the 3 call sites + the flat fixture']"
*   **Database**: "[What you queried + which connection — or 'not probed']"
*   **Tickets**: "[What you searched in Linear + the IDs you read — or 'not probed']"
*   **Not probed**: "[In-scope sources you skipped, and why the answer didn't need them.]"

## 3. Findings (Ranked)
*Most significant first. Every finding stands on evidence the reader can re-derive — a finding with no evidence is an opinion; label it as one or cut it.*

### Finding 1: [Short title]
*   **Where**: `path/to/file.ts:42` / `schema.table.column` / `FIN-1234`
*   **Evidence**: "[The EXACT thing you saw — the quoted line, the query AND the actual rows it returned, the ticket's own words. Never paraphrase a result you could quote.]"
*   **Significance**: "[Why this matters to the intent. If it doesn't bear on the question, it doesn't belong here.]"
*   **Confidence**: [High / Medium / Low]
*   **Suggested next step**: "[capture / dig deeper via reading / dig deeper via running / nothing]"

### Finding 2: [Short title]
*   **Where**: ...
*   **Evidence**: ...
*   **Significance**: ...
*   **Confidence**: ...
*   **Suggested next step**: ...

## 4. Blind Spots
*What you could NOT verify. A report with unstated blind spots is dishonest.*

*   "[The source, state, or integration outside your reach — and what it might be hiding.]"

## 5. Reusable Facts
*Durable truths discovered along the way — the compounding memory the next agent inherits. Facts and rulings, not narrative.*

*   "[e.g. 'claim_policy_snapshot.coverages is empty for every pre-cutover row — 412 of them, none after 2026-01.']"

## 6. Open Threads
*Neutral pointers: questions this probe surfaced but did not chase. Not recommendations — the orchestrator and user decide.*

*   "[The question] — would need [reading / running / asking someone]."

<!-- TRIAGE OUTCOMES — appended by the orchestrator after the walkthrough. Append, never rewrite. -->
## 7. Triage Outcomes
*Per-finding fate, decided with the user.*

*   **Finding 1** — [Capture / Dig deeper / Defer / Dismiss]: "[The user's reason, and where it went — ticket key, follow-up skill, or tag.]"
