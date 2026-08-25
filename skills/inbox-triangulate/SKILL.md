---
name: inbox-triangulate
description: "Triangulated triage of an intake inbox signal: dispatches TWO /inbox-triage runs in parallel from deliberately DIFFERENT leading questions and starting points (DB · UI · code · artifact · history) — an angle is a LEAD, never a fence, so every run may use every tool — independent by construction since neither posts and both start from the same state, then — only when they need reconciling — a third adjudicator that actively RECONCILES them, running the cheap targeted checks that discriminate between their claims while never opening a line of inquiry neither angle asked. Publishes ONE comment that reports the SUBJECT — the defect, its evidence, its breadth, whether it is still live, and what to do — with the full workings (both angle reports, the adjudication, the context pack) bundled into a single linked dossier rather than narrated at the reader. Use before a signal becomes a ticket, a disposition, or a claim in a Project Update. Triggers: \"triangulate this\", \"two angles on this signal\", \"verify this before we file it\", \"inbox-triangulate\", \"is this finding real\"."
version: 1.1
tier: lightweight
args: "[origin comment URL/id or the handoff prompt] [--angles <a>,<b>]"
---

Two independent triage runs from different vantage points, then adjudication on the record. It corroborates and reports; it never files, never decides a disposition, and never edits app data.

# /inbox-triangulate Protocol (Dual Independent Assessment with Adjudication)

## Why this exists

**Two runs of the same method share the same blind spots**, so their agreement is replication, not corroboration. The failure class this is built for is the one that survives replication: a property of the **data** rather than of the query. One project spent weeks quoting numbers distorted by two organisations that were the same tenant imported twice — invisible to every database query ever run against it, because every query inherited it identically.

Triangulation is the established name for the fix: check a finding from **different vantage points**. Not "check it twice."

**Disagreement is the product, not the failure.** A defect was found in one pass precisely because a screen said one thing and a query said another — the gap *was* the bug. A process that resolves disagreements away destroys its most valuable output.

## What it is, and is not

*   **It is** a wrapper that runs `/inbox-triage` twice on different angles and adjudicates the results. Everything `/inbox-triage` needs, this needs — it is passing that input through, twice.
*   **It is NOT** a deeper triage. Each run is an ordinary triage. The value is in the *diversity of the pair*, not in the depth of either.
*   **It does NOT decide dispositions.** It returns a corroborated finding; graduating, folding or parking stays with the caller (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`).

## When to invoke it

**Per item, by judgement — never universally.** Measured at **~2× a single triage** (106k + 132k tokens on the first real run, plus the adjudicator when needed), and running it on items nobody will act on manufactures agreement theatre.

Invoke when the item is heading for **a ticket, a decision, or a claim in a Project Update** — the three places a wrong finding becomes expensive and durable. A signal that will marinate does not need it.

---

## 1. Inputs — everything `/inbox-triage` takes, plus the angles

Assemble once; both runs receive the same pack:

*   **The origin signal in full — INCLUDING THE THREAD'S REPLIES**, not just the comment body. Screenshots and attachments too. **An origin comment's replies are part of the signal, not commentary on it**: prior triage results, corrections and the reporter's own follow-ups live there, and passing in the body alone silently withholds the most-processed evidence available. *Learned expensively — a ticket was filed asserting something had never been investigated, four days after a reply on that exact thread said it had, and gave the answer.*
*   **The origin comment id** and its channel ticket, so each run can post its own result.
*   **The channel's `## Directions` verbatim** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`) — a sub-agent cannot read the project; an unpassed steer is a lost steer.
*   **The handbook's `## What triage will chase` and `## Boundaries`** — the per-project recipe and the neighbour tests.
*   **The `## Ticketing Strategy`**, since each run recommends a milestone.
*   **Relevant stakeholders** — who to ask when a run hits a question it cannot close.
*   **The Slack channel-context slice**, if the wave loaded one.
*   **Data access**: the project's shared read-only connection, already open — the access directive (`.directives/INBOX_TRIAGE_ACCESS.md`) says how it is reached. Both runs share it; neither opens its own.
*   **The angle assignment** — one primary, one corroborating.

## 2. An angle is a STARTING POINT AND A QUESTION — never a fence

> ### 🔴 Every run may use every tool. Read this before writing a brief.
>
> An angle says **what you lead with and what you are trying to establish**. It does **not** limit what evidence you may touch. If a code-led run needs one database query to settle its own claim, **it runs the query**. If a record-led run needs to open a screenshot, it opens it.
>
> **Independence comes from different questions asked in parallel with no sight of each other's conclusions** — which `--no-post` already guarantees. It never came from starving each run of evidence, and pretending otherwise buys nothing while costing a great deal.
>
> **Why this is written as a warning.** An earlier version of this skill fenced each run to one evidence base — *"do not read tickets", "do not query the database"*. The result was exactly the complaint the method exists to avoid: **not enough evidence.** Both runs reported that the thing they could not settle was one query inside the other's fence, the wrapper recorded low confidence on precisely that question, and one "disagreement" between the runs turned out to be an artifact of each seeing half a picture rather than a real epistemic gap. **A restriction that manufactures the uncertainty it was meant to detect is worse than no restriction.**
>
> So: **lead with your angle, and follow the question wherever it goes.** A run that ends "I could not establish X" when X was one query away has written a bad report, not a disciplined one.

## 2b. Choose leads that FIND DIFFERENTLY

The evidence bases:

*   **DB** — rows, rates, distributions.
*   **UI** — drive the app; see what a user sees. **Where the project provisions a read-only agent account this angle is literally available**: the run signs in and looks at the reporter's screen rather than inferring it from rows. The mechanics — credentials, the sign-in traps, the waits, how to point a session at an account — belong to the project's access directive, which `/inbox-triage`'s Reproduce step sends you to. Without such an account a UI-led angle can only reason *about* the interface, which makes it the weakest of the five; with one, treat it as first-class.
*   **code** — read the deployed branch; trace the path.
*   **artifact** — open the actual document, export, screenshot or payload the customer complained about.
    > **How to actually open a Linear-hosted attachment**: pass the markdown containing the image reference to **`mcp__linear-server__extract_images`**. **Do NOT `curl` the `assetUrl` — it returns 401 and always will.** `uploads.linear.app` serves nothing unauthenticated; the bare URL is a *reference*, and access needs a session or a signed URL that Linear mints per-viewer with a ~300-second expiry. A pasted signed link is therefore **not** a durable citation — it works when written and 401s when read. Cite the attachment on its ticket and fetch it through the MCP.
    > *This is written down because a wrapper once concluded the artifact angle was unavailable to sub-agents, on the strength of a single unauthenticated `curl`. It was available the whole time, and the wrong conclusion was one call from being disproved.*
*   **history** — what shipped, what was cancelled, what already failed. (Cheapest of all, and the one whose omission is unrecoverable.)

**Rules:**

1.  **The two angles MUST come from different bases.** Two DB runs are replication.
2.  **Match the angle to the claim's shape.** A rendering claim wants UI + code. An extraction claim wants artifact + DB. A "we already tried this" claim wants history + code.
3.  **Both angles must be able to SEE the claim.** Before dispatching, state in one line what each angle could find that would settle the question. **If you cannot say that for an angle, it is the wrong angle** — a pair blind to the same thing produces two "cannot answer" reports and a vacuous AGREE that looks like corroboration and is worth nothing.
4.  **The caller may pin angles** via `--angles`; otherwise choose and *state the choice with its reason* in the report.

**Cost, measured rather than assumed.** The first real run cost **106k and 132k tokens** — the two angles came out roughly equal, so **budget ~2×**, not the "cheap second angle" this section originally claimed. That claim was reasoning presented as a figure and the first run refuted it. The cheapness argument still holds *within* an angle (a `git grep` beats designing a query), but it does not make the pair cheap. Invoke accordingly.

## 3. Dispatch both — parallel, THROUGH `/inbox-triage`, and neither posts

> ### 🔴 DISPATCH THE SKILL. NEVER HAND-AUTHOR A BRIEF IN ITS PLACE.
>
> Each angle is **a sub-agent whose job is to invoke `/inbox-triage`** — write the handoff to `builds/inbox-triage-handoff-<origin-id>-<angle>.md`, then dispatch an agent whose prompt says, in these words: *"Invoke the `/inbox-triage` skill via the Skill tool with `<handoff path> --no-post --angle <base>`. Follow that protocol exactly; do not improvise a method."*
>
> **A hand-written `general-purpose` brief is NOT a substitute, however good the brief is.** `/inbox-triage` carries discipline this wrapper does not restate and must not re-derive: the report template, the read-all-three-surfaces rule, the open-the-attachments rule (and the `curl` 401 trap), the Directions-outrank-the-recipe precedence, the Ticketing-Strategy-bounds-your-recommendation rule, and the branch-by-report-shape recipe. A bespoke brief inherits **none** of it, and the loss is invisible — the reports come back long, confident and well-structured, just in the wrong shape and without the checks.
>
> **Measured, not theoretical.** A wrapper run hand-authored two `general-purpose` briefs instead of dispatching the skill. Both angles produced genuinely good work, and the deviation still cost three things at once: reports in bespoke shapes rather than `TEMPLATE_TRIAGE_REPORT`, so nothing downstream could parse them; neither run inherited the triage skill's own guardrails; and because the wrapper was choosing agent types freely, it chose an unconstrained one for the adjudicator too. **The operator caught it, not the wrapper** — which is why this is a hard rule with a mechanical check rather than a preference.
>
> **Verify it happened**: the dispatched agent's transcript must show a `Skill` call for `inbox-triage`. If a run returns without one, it did not run the protocol — treat its output as an unstructured opinion, say so, and re-dispatch.

Dispatch both **simultaneously**, each with `--no-post` and its assigned `--angle`. Each does an ordinary triage and returns its report.

**Independence is structural here, not a rule either agent has to remember** (`¶INV_INDEPENDENCE_BY_CONSTRUCTION`). They start from identical state, write to different files, and **neither posts** — so there is no output of one that the other could see. Nothing needs prohibiting because nothing is reachable.

*Symmetric shared context is fine and should not be stripped.* Both angles seeing the same prior-wave `✅ result` replies does not compromise independence; seeing each other's **conclusions** would. Do not impoverish either run's context in the name of a blindness it already has.

**`--no-post` is the whole reason this is safe**, and it exists for a second reason too: two angle-reports landing on the thread before adjudication show the reporter two possibly-contradictory answers followed by a third comment resolving them — intermediates presented as conclusions. **The wrapper publishes once, at the end.**

> ### 🔴 License at least one angle to REJECT the question
>
> The two runs are independent of each other and **both depend on the wrapper's framing** — they receive the same statement of the claim, written by the same author. That is a shared contamination channel the angle split does nothing about: **triangulation protects against method blind spots, not against a badly-framed question.** Two angles answering the wrong question in agreement is the failure mode, and it is *more* convincing than a single wrong answer, not less.
>
> So at least one brief must say, in these terms: **"If the premise of this question is wrong, say so and explain why — that is a more useful answer than answering it."** Give it the claim as a *claim to be tested*, never as background it should assume.
>
> The first real run survived this hole by luck: the premise happened to be checkable from one angle's evidence base. Had both bases been silent on the framing, both would have answered obediently and agreed.
>
> **A later run showed the licence is necessary but not sufficient** — both angles used it, both partly rejected the premise, and the framing still steered them somewhere neither noticed. Three words did it. *"More data"* set both to counting **volume, never value**: neither de-duplicated to distinct meaning per claim, nor sampled a single claim to ask what an adjuster actually misses. *"Loses"* hid a **correctness** hazard sitting in plain sight — users may be shown a *wrong* value today under last-writer-wins, needing no migration at all, and neither angle sized it because "loses" points at absence. *"…tables"* named the terminus, so both audited tables and **neither opened the UI** — while one angle's binding conclusion rested on that unopened layer. **So the adjudicator carries a required section for it** (§5, *"what the framing made both miss"*): both runs inherit one author's vocabulary, and that section is the only place in the method where its blind spots can surface.

## 4. Compare — cheaply, before spending a third agent

The wrapper reads both reports and asks one question: **do the verdicts and their load-bearing numbers agree?**

*   **They agree, and at least one reports medium-or-better confidence** → post a short concluding reply naming both angles and the agreed finding. **No adjudicator.** Done.
*   **They agree and BOTH report low confidence** → **that is not corroboration and may not stand as a verdict.** Two shallow runs matching is two guesses matching. Report it as *"agreed but unestablished"*, name what neither could reach, and treat the item as still un-triaged. Agreement between weak evidence is the most seductive false positive this process can produce, because it wears the shape of a confirmed finding.
*   **They differ in any way that matters** → adjudicate.

Be generous about what "differ" means. Different confidence, different scope, a number one found and the other did not — all qualify. The adjudicator is cheap relative to filing a wrong ticket.

## 5. Adjudicate — through the same skill, and it RECONCILES rather than shrugs

**The adjudicator is dispatched exactly like the two angles: a sub-agent that invokes `/inbox-triage`**, with `--adjudicate --no-post` and the two report paths as its subject. Same skill, same discipline, same report shape — what differs is its **subject** (the two reports, not the signal) and the **shape of its evidence budget**.

Hand-authoring its brief instead of invoking the skill is the same mistake as doing it for an angle. **The mistake is the substituted brief, not the agent type** — every dispatch names some registered agent type (`debugger` fits triage; `analyzer` and `general-purpose` also work), because `Agent(subagent_type: "inbox-triage")` does not exist and fails at the tool boundary. Name a real type, then make `Skill(skill: "inbox-triage")` its first instruction.

> ### 🔴 It MAY gather evidence — but ONLY evidence that discriminates between the two reports
>
> **The adjudicator is not a blind judge.** Its job is to *actually settle* apparent disagreements, and most of them are settled by one cheap, targeted check: re-run the query one angle ran and see which scope it used; count the map both cited and disagreed about; open the one file whose contents decide whose reading is right. **An adjudicator that returns "they disagreed, someone should measure X" when X was one command away has failed at its job**, exactly as an angle would have.
>
> **The line is PURPOSE, not tools.** It is drawn between two things that look similar and are not:
>
> *   ✅ **Reconciling evidence** — a check whose only function is to discriminate between claims **already on the record**. *"A says 1,937 and B says 1,702; I ran both predicates and A counted all coverage-scope facts while B counted `coverage.limit` only."* That is arbitration, and it is what this role is for.
> *   ❌ **New evidence** — a check that answers a question **neither angle asked**. The moment it opens its own line of inquiry it becomes a third investigator with a stake in its own answer, and its ruling becomes advocacy dressed as arbitration. If it finds such a question, it **names it in "what neither could reach"** and leaves it for the caller — that is a finding, not a failure.
>
> **Every gathered fact is declared and attributed.** The report carries a **`## Checks I ran`** section: one row per check, naming *the exact discrepancy it was settling*, the command, and the result. A check that cannot name the A-vs-B discrepancy it discriminates is by definition new evidence and should not have been run.
>
> **Prefer reading first.** Most apparent disagreements are not contradictions at all — they are a different denominator, a different scope, or a different question — and careful reading resolves them at zero cost. Reach for a command only when reading genuinely cannot decide.
>
> **This constraint is INSTRUCTION, not structure**, unlike `¶INV_INDEPENDENCE_BY_CONSTRUCTION`, which no agent has to remember. So it is **audited, not trusted** — and the audit is the `## Checks I ran` table, not a tool count. **A raw tool count no longer distinguishes a good adjudication from a bad one**, because a reconciling adjudicator legitimately runs commands; what distinguishes them is whether every command traces to a named discrepancy. Check that table, and say in the published comment how many reconciling checks were run.
>
> **A GENUINE CONFLICT now means much more than it used to.** It is no longer "the reports differ and I could not read my way out of it" — it is *"I tried to settle this and the evidence needed does not exist yet."* That is a strong, expensive claim, and it should be rare. Name the single measurement that would settle it.

**Three outcomes, exactly one of which is a gap:**

*   **AGREE** — the angles land in the same place; the wrapper simply missed it. State the finding, **and carry both angles' confidence with it** — an AGREE where neither run got above low confidence is reported as *agreed but unestablished*, never as a settled result.
*   **RECONCILED** — they appeared to differ and do not. **Name the reason**, which is nearly always one of: a **different denominator** (1.43% *of documents* against 72.16% *of segments* — same funnel, incomparable quantities), a **different scope** (9,408 claims unfiltered against 2,662 filtered to one source), or **a different question** (one measured what the other assumed). *This is the highest-value outcome and the reason the adjudicator exists.*
*   **GENUINE CONFLICT** — they contradict on the same question at the same scope, and settling it needs evidence neither run has. **Name the single measurement that would settle it.**

**A genuine conflict is a successful run, not a failed one.** Its output is not "they disagreed" but *"here is the one thing to measure next"* — which makes the gap the next investigation rather than a shrug. Report it to the caller as a finding in its own right; the caller decides whether to spend that measurement now or file the item with the conflict recorded.

**The adjudication report carries these sections, all required:**

0.  **Checks I ran** — one row per reconciling check: the exact A-vs-B discrepancy it was settling, the command, the result. **Empty is a valid and common answer** (careful reading settles most disagreements at zero cost) — but a check that cannot name its discrepancy is new evidence and should not have been run. This table is the audit for `¶INV_ADJUDICATOR_RECONCILES_WITH_BOUNDED_EVIDENCE`.
1.  **Outcome per sub-question** — AGREE / RECONCILED / GENUINE_CONFLICT for the headline framing and for *each* number or claim the two treat differently. One verdict for the whole pair hides the interesting half.
2.  **The corroborated finding** — what a reader should actually believe, in plain language, **carrying the confidence it genuinely has.** Where it rests on one angle's medium-confidence reading, say exactly that rather than rounding up.
3.  **Where the angles disagreed** — never omitted. If they agreed on everything, say so explicitly; that is a reason to look again, not a gold star.
4.  **What neither could reach** — the questions still open after both runs, and the cheapest measurement that would close each.
5.  **On disposition** — the two recommendations side by side with the tradeoff, explicitly **not** a ruling (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`).
6.  **What the framing made both miss** — the shared-channel check (`¶INV_FRAMING_IS_A_SHARED_CHANNEL`). Both runs inherited one author's vocabulary; this is the only place in the method where its blind spots can surface, so an empty answer here is a claim that needs justifying, not a pass.

## 6. Report

**Publish ONE comment** on the origin thread — whether the outcome came from the cheap comparison or the adjudicator. The reporter sees one answer, not a debate.

> ### 🔴 The comment reports the SUBJECT. The dossier reports the METHOD.
>
> **Write the comment from `../inbox-triage/assets/TEMPLATE_TICKET_COMMENT.md`** (`¶INV_COMMENT_REPORTS_THE_SUBJECT_NOT_THE_METHOD`). It is addressed to **the person who owns the bug**, and every sentence above its one-line `<sub>` footer is about the defect: what's wrong · what the reporter got right and wrong · where (ids + deep links) · the evidence · how widespread · is it still happening · what to do · not established.
>
> **Detail is welcome — length was never the problem.** A long, dense, evidence-heavy comment is usually the right one. What must not appear is the *investigation as a subject*: the angles and what each led with, which run checked which object, whether the convergence was genuine, the adjudicator's per-question outcomes, the critique of this wrapper's own framing. **All of that is real and all of it belongs in the dossier.**
>
> **Measured, not theoretical.** This section used to require the comment to carry *"the verdict, the angles used, where they disagreed"*, plus the context pack attached for audit. On [FIN-3940](https://linear.app/finchclaims/issue/FIN-3940) that produced a comment roughly half of which taught the reader about triangulation — a product owner who wanted to know whether a money column was still wrong. **The wording above did that, not the agent following it.**
>
> **Translate, don't delete.** Each thing you are cutting has a content-shaped sibling that must survive:
>
> | Method sentence (→ dossier) | Its content sibling (→ comment) |
> | --- | --- |
> | "Angle A checked `bf6d3b5de`, angle B checked `06570f5c4`" | "the same change exists under two SHAs, so checking either alone is misleading" |
> | "medium-high confidence — the predicate was never run" | "nobody has confirmed X on this document; this one query settles it" |
> | "the framing steered both angles away from the screen" | "is today's $157,514.60 correct? Nobody has checked" |
> | "no GENUINE_CONFLICT; every contradiction reconciled" | *(nothing — the reader needs the reconciled facts, not the reconciliation)* |
>
> The left column is not worthless; it is worthless **here**. It is how the method improves, so it ships in the dossier where the people who maintain the method read it.

**Build ONE dossier and link it once.** Concatenate — in this order, with a table of contents — the adjudication (or, where no adjudicator ran, a short note saying the two angles agreed), angle A's report, angle B's report, and the context pack, into `builds/inbox-triage-<origin-id>-dossier.md`. Upload that single file and embed it as a clickable `[📄 filename](assetUrl)` link **alone in its own block with nothing after it** so Linear renders a preview card (`§INV_CHANNEL_EVIDENCE_RIDES_THE_COMMENT` — naming a file in prose is not linking it). **One card, not four**: four attachments compete for a reader's attention and none of them wins, and the reader who wants the workings wants all of them anyway.

**The context pack goes INTO the dossier — it is not dropped.** The adjudication carries a required *"what the framing made both miss"* section, and that is a criticism of the wrapper's **own wording**; a criticism nobody can check is worth little, so the thing being criticised must travel with it. It also makes the run reproducible in the way that matters: a reader can see what both angles were given, and therefore what they were never in a position to find. **Reason**: on the run that introduced this, the adjudication's sharpest finding was that three words of the wrapper's framing had steered both angles away from the screen and away from a live correctness hazard. That finding is unverifiable if the framing stays on the orchestrator's disk. **What changed is only the destination** — the pack is published inside the dossier rather than as a fourth card on a product ticket. Do not read this as the safeguard being removed and restore the old behaviour.

**Return the posted comment URL to the caller.** That URL is what the caller's `triageAccounting` requires; a run that investigated well and published nowhere has not finished (`¶INV_TERMINAL_PRODUCER_POSTS`).

Return to the caller:

```
{ item, angles: [primary, corroborating], reports: [url, url],
  outcome: AGREE | RECONCILED | GENUINE_CONFLICT,
  finding,                    // the corroborated result, or null on GENUINE_CONFLICT
  disagreements: [ ... ],     // ALWAYS present; an empty array is a claim, not an omission
  settledBy }                 // on GENUINE_CONFLICT: the one measurement that would settle it
```

**`disagreements` is never omitted.** If two genuinely independent angles agreed on everything, say so explicitly — that is worth a second look, not a gold star.

---

## Critical Invariants

*   **¶INV_ANGLE_IS_A_LEAD_NOT_A_FENCE**: An angle names **where a run starts and what it is trying to establish**. It never limits what evidence that run may reach — **every run may use every tool**, and one that needs the other's usual instrument to settle its own claim simply uses it. Diversity comes from **different leading questions**, which change what gets *found*; independence comes from **parallel dispatch with no sight of each other's conclusions**, which `--no-post` already provides. **Reason, measured**: an earlier version fenced each run to a single evidence base, and both runs then reported that the one thing they could not settle sat inside the other's fence — so the wrapper recorded low confidence on exactly the question an unfenced run would have answered, and one apparent disagreement turned out to be an artifact of each seeing half the picture. **A restriction that manufactures the uncertainty it exists to detect is worse than none.** Single-lead output remains a **hypothesis** until corroborated, and may not be cited as fact in a ticket, a disposition or a board.
*   **¶INV_INDEPENDENCE_BY_CONSTRUCTION**: The two runs are independent because **nothing they produce is visible to each other** — dispatched simultaneously from identical state, writing to different files, neither posting. Independence is a property of the arrangement, not a rule either agent has to remember. **Symmetric shared context does not compromise it**: both seeing the same prior-wave results is fine; seeing each other's *conclusions* is not. Prefer structure over instruction wherever the choice exists — a prohibition an agent must recall is weaker than a mechanism that makes the failure impossible, and this one dissolved the moment posting moved to the caller.
*   **¶INV_DISPATCH_THROUGH_THE_SKILL**: Every run this wrapper spawns — both angles **and** the adjudicator — is a sub-agent that **invokes `/inbox-triage`**. The wrapper writes the handoff and names the flags; it never hand-authors a brief in the skill's place. **It does name an agent type — it must**, because `subagent_type` accepts only registered agent types and `"inbox-triage"` is not one of them (`Agent type 'inbox-triage' not found`). Pick a registered type whose posture fits (`debugger` for triage) and make `Skill(skill: "inbox-triage")` the first instruction; what is forbidden is substituting your own brief for the skill's, not the act of choosing a carrier. **Reason, measured**: a wrapper run substituted two hand-written `general-purpose` briefs. The angles did good work and the substitution still cost three things simultaneously — reports in bespoke shapes instead of `TEMPLATE_TRIAGE_REPORT` so nothing downstream could parse them; no inheritance of the triage skill's own guardrails (read all three surfaces · open the attachments and never `curl` an `assetUrl` · Directions outrank the recipe · Ticketing Strategy bounds the recommendation · branch by report shape); and, because the wrapper had taken over agent selection, an **unconstrained agent type for the adjudicator**, whose whole contract is that it may not investigate. **The operator caught it; the wrapper did not.** The loss is invisible precisely because a bespoke brief returns long, confident, well-structured work — it just is not the protocol. Mechanical check: the dispatched agent's transcript must contain a `Skill` call for `inbox-triage`; absent that, the output is an unstructured opinion, not a triage.
*   **¶INV_ADJUDICATOR_RECONCILES_WITH_BOUNDED_EVIDENCE**: The adjudicator **may gather evidence, but only evidence that discriminates between claims already on the record.** Re-running a query one angle ran to find which scope it used, counting a map both cited and disagreed about, opening the one file that decides whose reading is right — all arbitration, all encouraged. Opening a line of inquiry **neither angle asked** is not: that makes it a third investigator with a stake in its own answer, and turns its ruling into advocacy dressed as arbitration. Such a question goes into *"what neither could reach"* as a finding. **The line is purpose, not tools.** **Reason**: the blind version produced excellent reconciliations and then hit a wall it could not pass — it reported that neither angle had run an in-tree parity command that would have settled what a config change actually surfaces, and could not run it either. *"They disagreed, someone should measure X"* when X is one command away is a shrug, not a ruling. **Audited, not trusted**: every gathered fact is declared in a **`## Checks I ran`** table naming the exact discrepancy it settles, and a check that cannot name its discrepancy is by definition new evidence. **A raw tool count no longer distinguishes a good adjudication from a bad one** — a reconciling adjudicator legitimately runs commands — so the audit is that table. Consequence worth stating: **GENUINE_CONFLICT becomes a much stronger claim**, meaning *"I tried to settle this and the evidence does not exist yet"*, and should be rare.
*   **¶INV_ADJUDICATOR_GATHERS_NOTHING**: **Superseded by `¶INV_ADJUDICATOR_RECONCILES_WITH_BOUNDED_EVIDENCE`.** Its prohibition on *all* gathering was too strong: it prevented advocacy at the cost of preventing reconciliation, which is the role's actual purpose. Retained as an alias for existing cross-references; the "no new lines of inquiry" half survives intact in the successor.
*   **¶INV_FRAMING_IS_A_SHARED_CHANNEL**: The two runs are independent of each other and **both inherit the wrapper's framing of the question** — the one dependency the angle split does nothing about. **Triangulation protects against method blind spots, not against a badly-framed question**, and two angles agreeing on the wrong question is *more* persuasive than one wrong answer, not less. Therefore at least one brief must license rejecting the premise: *"if the premise is wrong, say so and explain why — that is a more useful answer than answering it."* Hand each run the claim as a **claim to be tested**, never as background to assume. **Reason**: the first real run survived this hole by luck — the premise happened to be checkable from one angle's evidence base. Had both bases been silent on the framing, both would have answered obediently and agreed, and the agreement would have been believed harder for being unanimous.
*   **¶INV_WEAK_AGREEMENT_IS_NOT_CORROBORATION**: An AGREE where **both** runs report low confidence may not stand as a verdict — two shallow runs matching is two guesses matching. Report it as *"agreed but unestablished"*, name what neither could reach, and leave the item un-triaged. Every verdict carries both angles' confidence, so a reader can tell corroboration from coincidence. This is the most seductive false positive the process can produce, because it arrives wearing the shape of a confirmed finding.
*   **¶INV_DISAGREEMENT_IS_THE_PRODUCT**: A gap between angles is a finding, not a failure to resolve. Never average two answers, never silently prefer the more confident one, and never drop the quieter angle's result. The pass that found a defect by noticing a screen and a query disagreeing would have found nothing under a process that harmonises. **This survives `¶INV_COMMENT_REPORTS_THE_SUBJECT_NOT_THE_METHOD` intact, and the two are easy to collide by accident** — "no method-talk in the comment" must never become "the disagreement disappeared". The line is what the disagreement is *about*: a gap that changes **what is true of the subject** is content and belongs in the comment; the *account of who found what* is method and belongs in the dossier. Worked example, from the run that earned both rules: *"the same change exists under two SHAs, so checking either one alone is misleading"* is a fact about the codebase that a reader needs — it goes in. *"Angle A checked `bf6d3b5de` while angle B checked `06570f5c4`"* is a fact about the investigation — it goes in the dossier. **If cutting the method sentence also deletes a fact, you cut too much: translate it, don't drop it.**
*   **¶INV_COMMENT_REPORTS_THE_SUBJECT_NOT_THE_METHOD**: The single published comment is addressed to **the person who owns the subject**, and reports the subject. The workings are a *different artifact for a different reader* — bundled into one dossier and linked once, never pasted into the body. Method-talk gets one `<sub>` line naming the method, the provenance and the date. **Detail is not the enemy**: a long, dense, evidence-heavy comment is usually the right one; a comment that spends its length on how the answer was reached is not. Shared with `/inbox-triage` via `TEMPLATE_TICKET_COMMENT.md`, deliberately — a rule that binds only the wrapper is undone by running the other entry point. **Reason, measured**: §6 of this skill used to *require* the comment to carry "the angles used, where they disagreed" and to attach the wrapper's own briefing pack for audit. On [FIN-3940](https://linear.app/finchclaims/issue/FIN-3940) that produced a comment roughly half of which taught a product owner about triangulation while they were trying to find out whether a money column was still wrong. The findings underneath were correct and well-evidenced, which is what makes the failure worth an invariant: **good work posted at the wrong reader still fails.**
*   **¶INV_TERMINAL_PRODUCER_POSTS**: Whoever produces the *finding a reader should act on* publishes it, once. A single triage run standalone posts its own finding; under triangulation the two runs pass `--no-post` and **the wrapper posts one comment** — reporting the subject, with the workings bundled into one linked dossier (`¶INV_COMMENT_REPORTS_THE_SUBJECT_NOT_THE_METHOD`). Intermediates never appear on the thread as if they were conclusions. **And the guard against an unposted report is the GATE, not the poster**: whoever posts returns the resolvable comment URL, and the caller's accounting cannot complete without it. One wave lost three complete investigations to a posting step that was a trailing bullet with nothing checking it — moving the write around would not have helped; making it verifiable does.
