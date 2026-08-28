# Ticket Comment Template

The fixed shape for **what gets posted to a ticket** by `/triage` (`--post`) and by `/triangulate`.

> ### 🔴 This is NOT the triage report. Read this before writing a comment.
>
> These skills produce **two artifacts with two different audiences**, and posting the wrong one at the wrong reader is the failure this template exists to prevent:
>
> | | **Investigation record** | **Ticket comment** |
> | --- | --- | --- |
> | file | `builds/triage-<subject-id>[-<angle>].md` | posted to the origin thread |
> | template | `TEMPLATE_TRIAGE_REPORT.md` | **this file** |
> | audience | the next triage pass, the adjudicator, the skill's maintainers | **the person who owns the subject** |
> | may discuss | angles, steering reads, method boundaries, basis tags, verbatim SQL, confidence *in the investigation* | the subject, and nothing else |
>
> **The report is attached to the comment. It is never pasted as the comment.**
>
> **Measured, not theoretical.** A triangulated run on [FIN-3940](https://linear.app/finchclaims/issue/FIN-3940) published a comment in which roughly half the body was about the triangulation itself — which angle checked which commit SHA, whether the convergence between them was genuine, a critique of the orchestrator's own framing, and the orchestrator's briefing document attached for audit. The findings underneath were correct and well-evidenced. The reader was a product owner who wanted to know whether a money column on the estimate-comparison screen was still wrong. **The skill had told the agent to do this** — its Report section required the comment to carry *"the verdict, the angles used, where they disagreed"* — so this is a protocol fix, not a discipline fix.

## The rule

**Length is not the problem; subject is.** A long, dense, detailed comment is welcome and often correct — the operator explicitly asked for detail. Every paragraph of it must be about **the thing the ticket is about**. Method-talk gets exactly one line, at the bottom, in `<sub>`.

Concretely: above the footer, these words should not appear at all —

`angle` · `adjudicator` / `adjudication` · `triangulation` / `triangulate` · `the context pack` · `convergence` · `the premise` · `sub-agent` · `this triage` as a subject that does things · `Steering read` · `[DB-confirmed]` / `[inferred]` / `[needs-source]` basis tags

Not because they are forbidden vocabulary, but because each one signals a sentence whose subject is the investigation rather than the thing being triaged. If you need one to make a point, the point is probably method — move it to the report.

**Fill every section. Cut a section only if genuinely N/A, and say so in one clause.** Do not pad a section to fill the shape.

---

## The shape

```
## <one-line finding — what is wrong, in the subject's own vocabulary>

### What's wrong
<The failure, stated as the thing behaves. Two to five sentences. Name the screen,
the field and the value — or the file, the command and the expression. A reader who
has never opened this ticket before should understand the failure from this section
alone.>

### What the report got right, and wrong
<ONLY when the origin claim was mis-stated. Correct the record so the next
person doesn't re-derive it — a table works well when several claims are wrong
for different reasons. State WHAT is wrong with each claim, never HOW it was
discovered. Cut this section entirely when the reporter was simply right.>

### Where
<Every entity as a raw id AND a deep link, most-specific first. Org · claim ·
document / comparison / estimate · the exact tab — or, where the subject is not a
record, the `path:line`, the command or the commit. If the subject was found on
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
<Open questions ABOUT THE SUBJECT — never about the investigation — each with the
cheapest single thing that would close it. "Nobody confirmed X; this one query
settles it" is honest and useful. "Triage could not reach X" is method-talk;
rewrite it as a property of the subject. Rank by value if there are more than three.>

<sub><one line: method, code/data provenance + date. NO file paths — a repo path here is
prose naming a file, which a reader without repo access cannot open; the workings travel
as the uploaded card below.></sub>

[📄 <name>-dossier.md](<assetUrl>)
```

**Evidence rides the comment** (`¶INV_CHANNEL_EVIDENCE_RIDES_THE_COMMENT`): every attachment link must be **alone in its own block with nothing after it on that line**, or Linear renders it as plain text instead of a preview card.

**ONE CARD PER KIND OF READER — not one card total.** The old wording said *"one link, not several"*, and it was already false in practice: triangulated runs have been shipping a readable report beside the dossier for a while, and nobody flagged it because the extra card reads better than the rule. A count nothing obeys is worse than no rule. What actually matters is that each card answers a different person's question:

| card | who opens it | what they want |
| --- | --- | --- |
| **the synthesis** — `triage-<subject-id>.md` | the person who owns the subject, after reading the comment | the findings in full, without the method |
| **the dossier** — `…-dossier.md` | whoever audits or maintains the method | everything: adjudication, both angle reports, the context pack |
| **the repro** — `…-repro.ts`, one per angle that wrote one | whoever takes the fix | something they can run |

**Do not bundle across rows of that table, and do not duplicate within one.** Two reports for the same reader is the failure the old rule was reaching for; a script fenced inside a 130 KB dossier is a different failure, because the person who needs it has to extract it before it runs. If you are about to add a card, name the reader it is for — if that reader already has one, it belongs *inside* theirs.

The canonical invariant is permissive about count on purpose: it governs the *mechanism* — comment-level via `prepare_attachment_upload`, never a ticket-level attachment — and says outright that **every** file attaches that way. The count was only ever presentation guidance, and the table above is what that guidance was trying to say.

Ticket keys render via `§FMT_TICKET_LINK`; specific comments via `§FMT_TICKET_COMMENT_LINK`.

## The pointer — one per ticket the comment names

**Every ticket named above the `<sub>` footer gets one of these on it, unconditionally** (`¶INV_EVERY_NAMED_TICKET_GETS_A_POINTER`). Build the roster from the comment body before the first post, minus the thread the comment itself landed on. **Do not filter it down to the tickets the finding "changes"** — that test asks someone to judge whether a mention matters, and the ticket that most needed telling was flagged only as a hazard, which such a test scores as borderline.

**The cross-post is on by default; `--no-cross-post` is the caller's opt-out and the only thing that turns it off.** It exists for a caller whose phase forbids writes onto other people's tickets — the default writes onto work someone else owns. **It is not the filter refused above**, which asks the run to judge per ticket at the end; this is one decision, taken once by the caller, over the whole roster, before anything runs. **There is no middle**: with the flag absent every named ticket gets a pointer, with it present none does, and either way the roster is built and returned — under the flag with every URL empty and the suppression named, so the caller inherits a countable list of what it now owns.

```
<One or two sentences: what routed here, from where, and what this finding
corrects, or newly relies on, about THIS ticket — in this ticket's own vocabulary.>
Full workings: [<origin ticket> — <short finding phrase>](<comment URL>)
```

**It is a pointer, not a second copy of the finding.** No evidence dump, no dossier card, no re-run of the sections above — those live on the origin thread and reach a reader through the link. A pointer that grows past a few lines has become a duplicate report, and the duplicate is the copy nobody updates.

**And it must say something, or say what changed.** *"You were mentioned"* is noise the tracker already renders, and a stub on a busy ticket teaches people to skip its comments — which costs more than the pointer buys. Where the finding corrects nothing on the target, the pointer says what the target is now being relied on for; that is the fact its owner needs.

Three fills, so the shape is unambiguous:

*   **Corrects the target** — *"The record count in this ticket's description counts coverage-scope facts rather than limit rows; for the scope this ticket works in the figure is 1,702, not 1,937."*
*   **Warns the target** — *"This ticket's acceptance signal is 'the column reads non-null', which a finding on the origin thread shows is satisfied by the clobbered value as well as the correct one — the signal cannot tell a pass from the defect."*
*   **Depends on the target** — *"A finding on the origin thread routes its fix here: the wrong value is written by the apply path this ticket owns, so nothing upstream can close it."*

**A run publishing several comments at once posts one pointer per TICKET, never one per comment.** The roster is the union across everything it published, and the pointer links whichever comment named that ticket — on a batch run, the class comment (`/triangulate` § *Batch publishing*). Two pointers on one ticket out of one investigation is the duplicate this rule is not asking for.

## Batch runs — one FULL comment per class, a short one per member

Only for a run that investigated several subjects at once (`/triangulate` § *1b*). **A single-subject run uses the shape above unchanged and can stop reading here.**

**BATCH IS NOT SPECIAL.** Per class, a batch publishes exactly what a single-subject run publishes for its subject: the shape above, filled completely, standing on its own. **Nothing is stripped on the grounds that a batch produced it** — a class comment carries its own routing, its own duplicate and related tickets, its own recommendation, its own *Not established*. The saving is in the investigation and the dossier; there is none in the output.

**The class comment** — one per grouping, on the class's own ticket where one exists, otherwise on the representative member's thread. Fill every section above. Where it lands on a member's thread, fold that member's own specifics into it and post no separate member comment for them.

**Richest representative wins, and two class comments on one thread is correct rather than a collision to avoid.** Where two classes resolve to the same member, that member is the richest representative of both and both comments land there — the representative's own material *is* each class's primary evidence, which is what makes the comment read as a finding about that thread instead of someone else's report parked on it. Do not spread classes for balance and do not hold to one home per thread. **A class with no owning ticket homes on its definitional member** — the subject whose own material is the class's primary evidence — and its *What to do* says `no single owner`, plus one line that the class is a graduation candidate in its own right. Do not attach an unowned class to the nearest plausible ticket to give it a home; that is how a finding about what the record does not yet track stops being visible.

**The member comment** — one per subject the class explains, on that subject's own thread. **Short**, and only these:

*   **What's wrong** — one or two sentences in this subject's own terms.
*   **Where** — this subject's ids and deep links. **Only theirs**; a sibling's record does not belong on this thread.
*   **The evidence** — this subject's own rows: its counts, its dates, its sender, the value it actually showed. **This is the whole point of a member comment**, so be concrete here and nowhere else.
*   **One line naming the class and linking its comment** — where the mechanism, the breadth, the routing and the recommendation live.
*   **The dossier card.**

**No second copy of the ticket routing on a member.** It lives on the class comment; two copies drift, and the member's is the one nobody updates. **Unrelated classes never share a comment**, and **a subject whose evidence spans several classes attaches to each by facet** — never one comment averaging two causes together. Two substantial facets get two member comments, each pointing at its own class comment.

**A thin single facet rides as a sentence inside that subject's primary-class member comment** rather than earning a standalone one, naming its class and linking that class comment in the same sentence. **Thin means the facet's whole content is a line or two with no evidence of its own** — nothing this subject specifically showed for that class beyond what the class comment already carries. *Measured at N=2*: two genuinely different facets each needed their own comment, because each reporter needed their specific one; a lone thin facet got a standalone comment heavier than the one-line footnote in it. **This is about where a facet is rendered, never about whether it is found** — the grouping keeps every facet, and a subject spanning three classes would flatten to one label without that.

**Write a member comment from that subject's own material, never by swapping a name into the class finding.** *Measured*: on the run that produced this rule, the adjudicated finding was entirely class-level and carried **zero** per-subject specifics, so the specifics had to be re-read from each original signal body. They are not in the class finding to reuse. **Test your draft**: if it contains nothing that is *false of the sibling members*, it was not written for this one.

**The forbidden-words list above grows here** — `batch` · `cohort of` · `the other reports` · `these eight` · `the sibling threads`. Someone who owns one subject is owed a finding about theirs, not an account of the others investigated beside it. **Translate, don't delete**: what a sibling's evidence proves about *this* subject is content and stays, stated as breadth; a member comment naming its class comment is content too, because that is where the rest of their answer is.

**Breadth is content; the roster is method.** How widespread the defect is is a fact about the subject and belongs in the comment; which threads the run spanned is a fact about the investigation and belongs in the dossier. So a sibling named **as a place the same defect is live** stays — *"the same hold sits behind the Belton and Brandon Steven reports"* tells this reader how far their own problem reaches. Siblings named **as what else was looked at** go, which is what every phrase on the forbidden list marks. *Measured*: a run wrote that breadth sentence, weighed it against the list with nothing here to weigh it against, read it as content, and was right.

**One dossier for the whole batch** — `triage-<batch-id>-dossier.md` — linked from every comment, class and member alike. Attachments are comment-level, so the same file uploads once per comment; that is correct and is not a duplicated card. **Every one of those comments carries it the way a single-subject comment carries its dossier**: uploaded through `prepare_attachment_upload` and embedded as `[📄 filename](assetUrl)` alone in its own block. *Measured*: a batch run named the workings by `builds/…` repo path in the `<sub>` footer instead, which a teammate without repo access cannot open — a repo path is prose naming a file, and the rule against that binds the batch path exactly as it binds a single one.

---

---

## A filled worked example

**The example lives with the project, not here.** A worked comment is only instructive when it is *real* — real ids, a real denominator, a real correction of a reporter who was half right — and those are customer identifiers that should not leave the product's own repository.

So look for it in the project's access directive: `.directives/INBOX_TRIAGE_ACCESS.md`, section **Worked example** (locate it with `engine discover-directives <dir> --walk-up`). Finch's is the reference fill.

If the project publishes none, the shape above is enough to write from — but say in your report that you had no filled example to calibrate against, and consider leaving one behind. Two things a good example is always doing, worth checking your draft against either way:

*   **"What the report got right, and wrong" earns a table** when several claims are wrong for *different reasons*. It states what is wrong with each claim, never how that was discovered.
*   **"How widespread" names its denominator and what the denominator means.** `8 of 178 sides` is a number a reader can act on; `8 instances` is not. And where the count measures only what survives today rather than what happened, it says so — otherwise a survivorship figure reads as an incidence figure.
