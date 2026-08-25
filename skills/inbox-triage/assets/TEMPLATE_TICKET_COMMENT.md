# Ticket Comment Template

The fixed shape for **what gets posted to a ticket** by `/inbox-triage` (`--post`) and by `/inbox-triangulate`.

> ### 🔴 This is NOT the triage report. Read this before writing a comment.
>
> These skills produce **two artifacts with two different audiences**, and posting the wrong one at the wrong reader is the failure this template exists to prevent:
>
> | | **Investigation record** | **Ticket comment** |
> | --- | --- | --- |
> | file | `builds/inbox-triage-<origin-id>[-<angle>].md` | posted to the origin thread |
> | template | `TEMPLATE_TRIAGE_REPORT.md` | **this file** |
> | audience | the next triage pass, the adjudicator, the skill's maintainers | **the person who owns the bug** |
> | may discuss | angles, steering reads, method boundaries, basis tags, verbatim SQL, confidence *in the investigation* | the defect, and nothing else |
>
> **The report is attached to the comment. It is never pasted as the comment.**
>
> **Measured, not theoretical.** A triangulated run on [FIN-3940](https://linear.app/finchclaims/issue/FIN-3940) published a comment in which roughly half the body was about the triangulation itself — which angle checked which commit SHA, whether the convergence between them was genuine, a critique of the orchestrator's own framing, and the orchestrator's briefing document attached for audit. The findings underneath were correct and well-evidenced. The reader was a product owner who wanted to know whether a money column on the estimate-comparison screen was still wrong. **The skill had told the agent to do this** — its Report section required the comment to carry *"the verdict, the angles used, where they disagreed"* — so this is a protocol fix, not a discipline fix.

## The rule

**Length is not the problem; subject is.** A long, dense, detailed comment is welcome and often correct — the operator explicitly asked for detail. Every paragraph of it must be about **the thing the ticket is about**. Method-talk gets exactly one line, at the bottom, in `<sub>`.

Concretely: above the footer, these words should not appear at all —

`angle` · `adjudicator` / `adjudication` · `triangulation` / `triangulate` · `the context pack` · `convergence` · `the premise` · `sub-agent` · `this triage` as a subject that does things · `Steering read` · `[DB-confirmed]` / `[inferred]` / `[needs-source]` basis tags

Not because they are forbidden vocabulary, but because each one signals a sentence whose subject is the investigation rather than the defect. If you need one to make a point, the point is probably method — move it to the report.

**Fill every section. Cut a section only if genuinely N/A, and say so in one clause.** Do not pad a section to fill the shape.

---

## The shape

```
## <one-line finding — what is wrong, in the product's own vocabulary>

### What's wrong
<The defect, stated as the product behaves. Two to five sentences. Name the screen,
the field, the value. A reader who has never opened this ticket before should
understand the failure from this section alone.>

### What the report got right, and wrong
<ONLY when the origin claim was mis-stated. Correct the record so the next
person doesn't re-derive it — a table works well when several claims are wrong
for different reasons. State WHAT is wrong with each claim, never HOW it was
discovered. Cut this section entirely when the reporter was simply right.>

### Where
<Every entity as a raw id AND a deep link, most-specific first. Org · claim ·
document / comparison / estimate · the exact tab. If the subject was found on
a non-production environment, give both bases and say which one you looked at.
Correct any id that was wrong upstream — plainly, without narrating the search.>

### The evidence
<The 2–5 facts that establish the finding, each with the source that carries it:
a stored row and its value, a file:line and the expression at it, a frame and
what it shows. Fenced code or a small table beats prose. This is where detail
belongs — be generous here. No basis tags; the source IS the basis.>

### How widespread
<Counts WITH their denominator, and what the denominator means. A number whose
population is unstated is worse than no number: say whether it measures
incidence, or only what survives today. If breadth was not measured, say that
in one clause rather than implying rarity.>

### Is it still happening
<fixed | live | partially fixed — with the artifact that says so: the commit and
where it landed, the row that still holds the bad value, the date it was checked.
When part is fixed and part is not, split them explicitly; that combination is
the most actionable thing a comment can carry and the easiest to blur.>

### What to do
<The recommended disposition and the concrete next steps, numbered. Explicitly a
recommendation, never an enacted decision (¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES).
Name the ticket each step belongs to. Include corrections to OTHER tickets'
records when this work found them stale.>

### Not established
<Open questions ABOUT THE DEFECT — never about the investigation — each with the
cheapest single thing that would close it. "Nobody confirmed X; this one query
settles it" is honest and useful. "Triage could not reach X" is method-talk;
rewrite it as a property of the defect. Rank by value if there are more than three.>

<sub><one line: method, code/data provenance + date, and the dossier link></sub>

[📄 <name>-dossier.md](<assetUrl>)
```

**Evidence rides the comment** (`¶INV_CHANNEL_EVIDENCE_RIDES_THE_COMMENT`): the dossier link must be **alone in its own block with nothing after it on that line**, or Linear renders it as plain text instead of a preview card. **One link, not several** — bundle the workings into a single dossier rather than competing for the reader's attention with four cards.

Ticket keys render via `§FMT_TICKET_LINK`; specific comments via `§FMT_TICKET_COMMENT_LINK`.

---

## A filled worked example

**The example lives with the project, not here.** A worked comment is only instructive when it is *real* — real ids, a real denominator, a real correction of a reporter who was half right — and those are customer identifiers that should not leave the product's own repository.

So look for it in the project's access directive: `.directives/INBOX_TRIAGE_ACCESS.md`, section **Worked example** (locate it with `engine discover-directives <dir> --walk-up`). Finch's is the reference fill.

If the project publishes none, the shape above is enough to write from — but say in your report that you had no filled example to calibrate against, and consider leaving one behind. Two things a good example is always doing, worth checking your draft against either way:

*   **"What the report got right, and wrong" earns a table** when several claims are wrong for *different reasons*. It states what is wrong with each claim, never how that was discovered.
*   **"How widespread" names its denominator and what the denominator means.** `8 of 178 sides` is a number a reader can act on; `8 instances` is not. And where the count measures only what survives today rather than what happened, it says so — otherwise a survivorship figure reads as an incidence figure.
