# Ticket Search Report: [Intent]
**Tags**: #needs-review
*Written by the navigator sub-agent at the end of its run. This is the authoritative account of what already exists in Linear near this body of work — for context, and (louder) as a possible DUPLICATE. It is read downstream by TWO consumers: the **orchestrator** (which spot-checks the dup callout and triages each ticket with the user), and the NEXT agent (via the durable facts → `LESSONS.md`). The heavy ticket bodies + comment threads that produced this stayed inside the sub-agent — this report carries only the distilled verdicts. Fill every section.*

**Slug**: `[slug]`
**Mode**: [Standalone (ran `engine ticket-search`) / Startup (navigated SRC_RELATED_TICKETS)]
**Status**: [Complete / Partial / No related tickets found / Blocked — no Linear MCP]

## 0. Headline
*Lead with the single most decision-relevant fact. Is this work a duplicate — and if so, of what and in what state?*

*   "[e.g. 'FIN-1180 (Done) already ships this — reuse, don't rebuild.' / 'FIN-1234 (Backlog) is an open dup someone filed — coordinate before building.' / 'No duplicates; two tickets give useful context.']"

## 1. Related for context
*Tickets that INFORM this work — prior decisions, adjacent systems, useful precedent — but are NOT the same deliverable. Ranked, most relevant first. If none, say "none".*

*   `[KEY]` · [title] · [state] · [why it's related — the decision/context it carries] · [url]
*   `[KEY]` · [title] · [state] · [why it's related] · [url]

## 2. ⚠️ Duplicate / overlapping work
*The loud callout — a ticket that IS, in whole or part, the same deliverable. This is what a new session most needs before building. Classify EVERY entry by `state.type` (from `§CMD_READ_RELATED_TICKET`), TOTALLY across Linear's six values — never let the open case fall through. If none, say "none — no duplicate or overlapping work found".*

### Already built (`completed`) → reuse / skip
*   `[KEY]` · [state] · [what overlaps + the ticket's own words that prove it — reuse this, don't rebuild]

### Deliberately dropped (`canceled`) → investigate WHY before rebuilding
*   `[KEY]` · [state] · [what overlaps + the reason it was canceled, from the ticket/comments — a canceled dup was ABANDONED, not built; do NOT "reuse" it]

### Open / not-yet-built (`triage` · `backlog` · `unstarted` · `started`) → coordinate, may be duplicating
*   `[KEY]` · [state] · [what overlaps + who owns it — a backlog/triage ticket someone already filed is the headline dup; coordinate before duplicating]

## 3. Suggested actions
*Per ticket, a SUGGESTION only — the orchestrator triages these with the user; nothing here is done. Never "subscribed"/"folded in" — only "suggest: …".*

*   `[KEY]` — suggest: [read / subscribe (`engine ticket subscribe [KEY]`) / fold into scope / coordinate / dismiss] — [one-line why]
*   `[KEY]` — suggest: [action] — [why]

## 4. Coverage
*What you read vs skipped, honestly. A silent skip reads as "covered".*

*   **Deep-read** (full body + comments via `§CMD_READ_RELATED_TICKET`): `[KEY, KEY, …]`
*   **Dismissed from summary** (title/snippet plainly unrelated, no deep read): `[KEY — reason, …]`
*   **Could not read**: "[KEYs skipped + why — e.g. no Linear MCP, get_issue error. Empty if none.]"

<!-- TRIAGE OUTCOMES — appended by the orchestrator after the walkthrough. Append, never rewrite. -->
## 5. Triage Outcomes
*Per-ticket fate, decided with the user.*

*   `[KEY]` — [Subscribe / Fold into scope / Read / Coordinate / Dismiss]: "[the user's reason, and where it went — subscription, /build fold-in, /communicate handoff, or dismissed]"
