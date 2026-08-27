# Triage Report Template

The fixed shape for every `/triage` report (`builds/triage-<subject-id>[-<angle>].md`). The paired handoff prompt is a **separate** file (`builds/triage-handoff-<subject-id>[-<angle>].md`, from `TEMPLATE_HANDOFF_PROMPT.md`); both are bundled into the dossier the comment links, so the full chain (question → answer) is reproducible.

> 🔴 **This is the investigation record, not the thing you post.** Its reader is the next triage pass, the adjudicator, and the people who maintain this skill — which is why `**Angle**`, `Steering read`, basis tags, verbatim queries and method boundaries all belong here. **The comment is a different artifact for a different reader** and is written from `TEMPLATE_TICKET_COMMENT.md` (`¶INV_COMMENT_REPORTS_THE_SUBJECT_NOT_THE_METHOD`). Never paste this file into a ticket.

The **entity rows, the app base and the deep-link patterns come from the project's access directive** (`.directives/INBOX_TRIAGE_ACCESS.md`) — this template names the *shape*, the project names the nouns. Fill every section. Cut a section only if truly N/A, and say so.

---

```
# Triage Report — <subject-id> "<title>"

**Angle**: <db | ui | code | artifact | execution | history | spec | unrestricted> — the evidence base this report rests on.
*Your angle is **where you started and what you set out to establish** — not a limit on what you were allowed to look at. **Use every tool you need**: a code-led investigation that needs one database query to settle its own claim should run it. List the instruments you actually used alongside the lead you took. **"I could not establish X" is a finding only when X was genuinely unreachable — if X was one query away, it is a bad report.***

**Subject**: <one sentence — what is actually being claimed, and what kind of thing it is:
a product defect, a claim about the codebase, a failing test, a piece of tooling, a process.
Where this differs from how the caller framed it, say so — you investigated this, not the framing.>

**Project**: <the resolved `Product:`-prefixed Linear project, plus the evidence that picked it —
or `none — generic recipe` where no project owns the subject, which is a normal outcome.>

**Mode**: <`inbox — inferred: <what fired it>` | `inbox — --mode inbox` | `plain — --mode plain` |
`plain — ordinary work ticket` | `plain — no Linear subject`. Inbox mode is inferred rather than
passed, so it is stated here: an inference nobody can see is one nobody can correct.>

## Verdict
- **Finding**: <the answer in one line>
- **Disposition**: <graduate → milestone | enrich (already owned) | still-needs-triage | marinate — or, outside inbox mode, the caller's own vocabulary> · **Priority**: <Urgent/High/Med/Low>
- **Confidence**: <high | med | low> — <one clause why>
- **Repro**: <always | intermittent | couldn't | confirmed-in-data | n/a — <why>> — <the shortest path that shows it, or the step that failed>. `confirmed-in-data` means the stored state was checked instead of a live repro being attempted; the two are not interchangeable, so never write one having done the other.
- **Data**: <which source — the live primary, or a snapshot AND the snapshot's own date. "A replica" is not an answer: a snapshot does not track, so a count off one is as of when it was taken, not now> · queried <YYYY-MM-DD HH:MMZ>

## Entities (ids + reproduce links)
Raw ids kept ALONGSIDE links so a re-analysis agent can pick them up without parsing prose.
App base and link patterns: from the project's access directive. One row per entity the
finding touches, most-specific first, each as `<name/number> \`<id>\` — [deep link](…)`.

## Signal
- **Origin**: <issue key> (<channel / parent>) · reporter <name> · <created date> — or, where the subject came from a context pack rather than a thread, what the pack carried and who assembled it
- **Reported**: <verbatim or tight paraphrase>
- **Reporter hypothesis** (if any): <what they guessed — triage confirms or corrects it>

## Findings
Tag each by basis — `[confirmed]` a query/record proves it · `[inferred]` reasoned from the data · `[needs-source]` can't be settled read-only.
- **[confirmed]** <finding> — evidence: <ids / counts / the row that proves it>
- **[inferred]** <finding> — basis: <the reasoning>
- **[needs-source]** <finding> — needs: <the source artifact to settle it>

## Queries (verbatim, read-only)
The exact queries and commands, so the report is reproducible and extensible:
```sql
-- <what this answers>
<SELECT …>;
```
→ <key result rows / the number that matters>

## Scope
<systemic? blast radius with counts AND their denominator (e.g. "112,625/115,080 docs, 1,411 records"), or "single instance — not systemic". A count whose population is unstated is worse than no count.>

## Related
<sibling / duplicate / candidate root-cause-parent tickets — issue key + why related; call out what NOT to fold together>

## Recommendation & Boundary
- **Recommendation**: <disposition + milestone + priority + the concrete next step>
- **Boundary — what triage could NOT determine (→ research)**: <the correctness / root-cause questions that need more than read-only access, and what artifact/owner closes them>

## Steering read  (process-STEERING, not solutions — ¶INV_STEERING_NOT_SOLUTIONS)
Reactions that shift the process in a direction, oriented by the project's Directions — NOT a correct answer to produce now. Feeds the Decision Board's steering widgets (the orchestrator polishes the options).
- **Legitimacy / confidence**: <looks-legit | plausible-needs-more-info | weak-signal | not-a-problem | out-of-scope-per-Directions> — <one clause why; cite the Direction if it applies>
- **Still-open questions**: <what this triage could not settle — for a human / next pass to weigh>
- **What to measure/triage next**: <concrete next probes that would move it forward — each feeds a `measure:*` option>
- **Suggested board options** (3–5, each `{key, label}` — keys are stable machine ids): e.g. `{needs-research, "Needs more research"}` · `{seems-like-a-ticket, "Seems like a ticket"}` · `{fold-into:<KEY>, "Fold into <KEY>"}` · `{measure:<x>, "Measure <x> first"}` · `{not-a-problem, "Not a problem"}`

---
*Read-only throughout. Handoff prompt bundled alongside (`triage-handoff-<subject-id>[-<angle>].md`). **This file is never the comment body** — it rides the comment inside the dossier; the comment itself is written from `TEMPLATE_TICKET_COMMENT.md`.*
```
