---
name: prove-visionary
description: "Compile an unsettled body of work into a self-contained, shareable visual DIRECTION page — where this is going, the options that get there with their costs, and the evidence that grounds them kept reachable rather than in the way. The forward-looking sibling of /prove: where /prove SHOWS a settled finding, /prove-visionary PROPOSES — it may reason forward, extrapolate, sketch a shape that does not exist yet, and recommend. Spine: it loosens what the page may SAY, never what it may claim as MEASURED — every claim carries a visible epistemic label (measured · inferred · proposed), every proposal names what would falsify it, every option is costed (fixes / leaves unfixed / risks / the cheap check that would size it) with the honest do-nothing option present, and every number keeps its denominator and its source. Direction leads; the current state is the runway, not the flight; the full workings sit behind disclosures a skeptic can reach and a persuaded reader never has to walk through. A subagent assembles + composes; the orchestrator owns the honesty gate and the S3 publish. A building block: it proposes and reports, never fixes, commits, files, or decides. Triggers: \"where should this go\", \"make the case for a direction\", \"lay out the options\", \"vision page\", \"proposal page\", \"what are our moves here\", \"write this up as a direction with costs\", \"pitch this properly\"."
version: 1.0
tier: lightweight
args: "[<the question this page must answer>] [-- <the reader / the decision the page is feeding>]"
---

Turn a body of work that is **still in flight** into a self-contained, shareable **direction page**. `/prove-visionary` takes an open question — where should this go, what are our moves, what is this worth building — and hands it to a background subagent that grounds it in what has actually been measured, reasons forward from there, costs the options, and composes a page that **flies**. You then run the honesty gate and publish it to an S3 URL.

This is the **forward-looking sibling of `/prove`**. Where `/prove` takes a settled finding and *shows* it, `/prove-visionary` takes an unsettled one and *proposes*. It may extrapolate, sketch a shape that does not exist yet, rank options and recommend one. As a **building block** it produces a page, not a change or a decision: it never edits code, never commits, never files a ticket, and never makes the call it is laying out.

**When to use this instead of its siblings — route by whether the answer is settled, and by what the reader must do with it:**

- The answer is **one claim** that is settled and needs *showing* → **`/prove`**. **A settled finding with renderable evidence is `/prove`'s job — do not route it here.** A page that merely re-presents established evidence gains nothing from this skill's machinery and loses `/prove`'s tighter discipline.
- The answer is **knowable or already known, and large**, and the reader must *understand* it → **`/prove-explore`**. That includes explaining a direction someone has already chosen.
- The reader needs **one mechanism** taught — the idea, how it works, a worked example, its edge cases → **`/prove-explanation`**.
- The route is **decided** and the page lays out its steps and their checks → **`/prove-plan`**.
- The calls are ready to be **collected** — framed items, the human's answer per item, a record of what was decided → **`/decide`**, which publishes a Decision Board and records the call. This skill proposes and never collects.
- The answer is **not settled** and someone must *choose* between directions → **`/prove-visionary`**.

*The spine — non-negotiable:* **`/prove-visionary` loosens what the page may SAY, never what it may claim as MEASURED.** It may reason forward, propose, extrapolate and recommend. It may not invent a number, attribute a measurement that was never taken, or present a projection in the typography of a finding. That single distinction is what buys the freedom to speculate without the freedom to mislead. Remove it and this skill produces exactly `/prove`'s named anti-pattern — a gorgeous page that proves nothing — with invented numbers on top, which is worse than no page at all.

*The second half of the spine — the architecture:* **the direction leads; the current state is the runway, not the flight.** `/prove` puts evidence in the primary position and the conclusion last. `/prove-visionary` inverts that order: where this is going comes first, the present state is stated once and briefly, and the full workings sit behind disclosures. A **skeptical reader must be able to get all the way down to the artefact; a persuaded reader must never have to walk through it to reach the point.**

*Crucial constraint:* `/prove-visionary` does NOT own a session. It reads the *active* session's context and writes its paper trail into that session — the **dossier and the composed HTML into `builds/`** (durable, attachable to a Linear ticket), the **raw captured assets into scratchpad** (throwaway intermediates, embedded into the HTML as `data:` URIs).

# /prove-visionary Protocol

## 1. Scope the Question

Pin what the page is trying to settle, before anything is composed.

**A. The Question** (not a thesis)
`/prove` asks for one provable claim. This skill asks for **the question the page is trying to answer, and what would count as answering it.** State both.
*(Illustrative — adapt, don't copy: "How wide should the percentage re-carve be — one member, the family, or the whole grid-taxonomy? Answering it means naming the scope, its cost, and the check that would size it." / "Is document splitting worth building before the resync, or after? Answering it means a cost on each order and the observation that would settle which.")*
*Constraint:* the question may be a **direction**, an **open question**, or a **body of work still in flight** — it does not have to be settled. It does have to be *one* question. If you cannot state it in a sentence plus a sentence of what answering it looks like, ask ONE `AskUserQuestion` to pin it. A vague question produces a page that proposes nothing.

**B. The Ask** (what the page wants from the reader — required, and `/prove` has no equivalent)
A proof asks for nothing; a direction page always asks for something, and confusing *what* it asks is how "a vision that is really an unreviewed plan" happens. Declare the page's **status** as one of:
- **Proposal** — a recommendation seeking a decision. Name the decision and who makes it.
- **Exploration** — options laid out seeking reactions, with no recommendation yet.

The status goes on the page, in the masthead, in those words. There is no "decided" status: a direction already chosen is not this skill's subject. If the route is chosen and the page lays out its steps, use `/prove-plan`; if a chosen direction is being explained, use `/prove-explore`. A page that reads as decided when it is really a Proposal is claiming authority it does not have.

**C. The Reader & the Job**
Name the reader — **operator** / **teammate** / **stakeholder** / **future self** — and the single job of the page: what must this reader be able to *decide or react to* in ten seconds? The reader drives the structure, the density, and the tone.

**D. The Ground** (what is actually known)
Name the work the page stands on and where its verdicts live: a `/probe` `_PROBE.md`, `/analyze` findings, an `/experiment` VERDICT, a `/council` report, measurements on disk, the active session's log and builds. These are the **grounding**, not the subject. Their conclusions are trusted the way `/prove` trusts them — the page does not re-run an analysis to manufacture support for a direction it already favours. If a measurement the direction needs does not exist, the page says so and names it as a cheap check, rather than inventing it.

**E. The Trail** (durable in `builds/`, throwaway in scratchpad)
Set:
- `<trailDir> = <sessionDir>/builds/` — the durable home.
- `<pagePath> = <trailDir>/<slug>_VISION.html` — the composed page, a **durable** self-contained session artifact (directly attachable to a Linear ticket).
- `<dossierPath> = <trailDir>/<slug>_PROVE_VISIONARY.md` — the record behind it.
- `<assetDir> = <scratchpad>/prove-visionary-<slug>/` — raw captured assets (PNGs, screenshots): throwaway, since they get embedded as `data:` URIs.

Mint a short kebab-case `<slug>` from the question (e.g. `percentage-recarve-scope`, `splitting-before-resync`). *Before minting:* run `ls <trailDir>` — if an existing `<slug>_*` cluster matches this work, REUSE that slug so the page clusters with the `/build`, `/probe`, `/council` artifacts.

**Acknowledge:** echo your setup in exactly one line:
`Direction: <question> — status: <proposal|exploration>; reader: <who>; ground: <source work>; trail: <trailDir>/<slug>_PROVE_VISIONARY.md.`

**State the spine** back to yourself: the page may propose, extrapolate and recommend — it may not invent a number or dress a projection as a measurement. Direction leads; the present state is the runway; the workings stay reachable.

**Load the voice before any words are written.** The page's structure comes from the design kit; its words follow `~/.claude/engine/.directives/VOICE.md`, which the session start loads. Hold it for the run. Two points are this skill's own, and §3 checks them:

- **The direction comes in the first paragraph,** in plain words, together with what it asks of the reader.
- **Every number carries its denominator and its date.** This does not relax here. A direction page that fudges a number loses the reader it was written for.

## 2. Dispatch the Visionary — Ground → Reason → Cost → Compose (subagent)

**Backgroundable & parallelizable.** This dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working, and when the options split into independent strands it can be fanned out and reconciled.

The subagent does the heavy, context-bloating work — gathering the grounding, capturing the real assets, costing the options, and composing the page (so base64 blobs **never return to your context**). It writes two artifacts: the **direction dossier** (the labelled claim ledger + the costed-options block) and the **page HTML**. It does NOT publish, and it does NOT make the decision.

**Use the wait — don't idle.** Pre-read the grounding work so you know which numbers are load-bearing, and line up which one you will check yourself in §3.

Build the subagent's prompt entirely self-contained — it cannot see your memory:

> You are a **direction architect** composing a page about work that is NOT settled. Your job: ground the direction in what has actually been measured, reason forward from it, cost the options honestly, and compose a page that flies. You may propose, extrapolate, sketch a shape that does not exist yet, and recommend. You may NOT invent a number, attribute a measurement that was never taken, or present a projection in the typography of a finding. You do NOT fix anything and you do NOT make the decision.
>
> **1. The Question** — what the page must answer:
> - **Question:** `<question>` — answering it means `<what counts as an answer>`.
> - **Status:** `<proposal | exploration>` — `<the decision + who makes it>`.
> - **Reader & job:** `<reader>` — the page must let them `<the 10-second job>`.
> - **Ground (trusted):** `<pointers: _PROBE.md / findings / VERDICT / council report / measurements on disk / log+plan+builds>`. Read these to learn what is actually KNOWN and trust those conclusions. Do NOT re-run an analysis to manufacture support for a direction. If a measurement the direction needs does not exist, say so and carry it as a cheap check — never invent it.
>
> **2. Label EVERY claim — the three labels.** Every assertion the page makes carries exactly one of these, **visibly on the page**, not only in the dossier:
> - **`measured`** — someone actually observed this. It carries its **number, its denominator, its date, and where it was taken**. The underlying artefact is reachable from the page.
> - **`inferred`** — reasoned from measured things, not itself observed. It carries **the step**: *from X, because Y*. It can be wrong in a checkable way.
> - **`proposed`** — does not exist yet: a shape, an option, a sequence, a design. It cannot be true or false, only good or bad, so it carries a **falsifier or a cheap check** instead of evidence.
>
> A claim that fits none of these is not a claim — cut it. A `measured` claim whose source you cannot name is downgraded to `inferred` or cut; it is never left as an unsourced number.
>
> **3. Every proposal names what would falsify it — or what would make it obviously right.** For each `proposed` and each `inferred` claim, state the observation that would show it wrong, or the one that would settle it in its favour. Prefer a falsifier that is **cheap and nameable** — a query someone could run, a sample someone could label, a week of watching a metric. If nothing could falsify a claim, the page says so and downgrades it: it is a **preference**, stated as a preference, not dressed as a finding. A vision with no falsifier is a wish.
>
> **4. Cost every option; never list them.** For EACH option — including the honest **do-nothing** option — give all four:
> - **What it fixes** — the part of the problem it actually removes.
> - **What it leaves unfixed** — the part it does not touch. An option with nothing in this field is under-examined, not perfect.
> - **What it risks** — what goes wrong if it is the wrong call, and how you would notice.
> - **The cheap check that would size it** — the small piece of work that would turn a guess about this option into a number.
>
> Keep the costs in the **same units across options** where you can; where you cannot, say why they are not comparable rather than implying they are. **The do-nothing option is present unless it is genuinely unavailable** — physically impossible, or already ruled out by someone with the authority — in which case the page names *who* ruled it out and on what grounds. Its absence with no explanation is the usual tell that a page is selling. Do-nothing carries the same four fields, its risks included (drift, compounding cost, the decision getting made by default); a do-nothing with an empty risk field is a strawman.
>
> **5. Capture real assets — from the ACTUAL source — and mark the proposed ones AS proposed.**
> - **Grounding assets** (a measurement, a code block, a log line, a PDF page, a query result) are captured exactly as `/prove` would: from the real source, verbatim, never a paraphrase and never a mockup. `mutool draw -o page-%d.png -r 150 <file.pdf> <N>` for PDF pages; a headless screenshot for a live page; verbatim terminal text for CLI output.
> - **Proposed assets** — a diagram of a shape that does not exist yet, a sketched flow, a before/after whose "after" is a design — are **allowed and encouraged**, and must be **visually distinguishable from a measured one at a glance**. Use one consistent convention across the page (for example: dashed borders, a `proposed` chip in the corner, a distinct ground tint) and state the convention in the legend. A before/after must never render both halves in the same treatment when the "after" does not exist. A principle in prose does not survive composition; a visual convention does.
> - If a grounding asset cannot be captured, RECORD that in the dossier (`asset-failed` + why) and degrade — never fabricate a stand-in.
>
> **6. Structure the page so it FLIES.** The order below is the spine. The current state is stated **once, briefly, early**, and then the page moves.
> 1. **Masthead** — what this is · who it is for · **what it asks of them** · its status (proposal / exploration). Where the reader meets it, never buried.
> 2. **The direction** — where this is going, point first, in a paragraph. The single most valuable thing, for a reader who stops here.
> 3. **The runway** — what is true today that makes this the direction. Measured, labelled, numbers with denominators. **This is the ONLY place the status quo lives, and it is budgeted: it may not be the longest section on the page.**
> 4. **The moves** — the costed options, each with its four fields and its falsifier, do-nothing included. The heart of the page.
> 5. **Load-bearing assumptions** — the premises taken on faith, each with what would break it. An unexamined premise is the most common way a direction page misleads.
> 6. **What would change our mind** — the falsifiers, collected, so a skeptic can see the whole set at once.
> 7. **The ask** — restated concretely: the decision, who makes it, by when if that is real.
> 8. **The workings** — full exhibits, queries, verbatim output, the long tables. In an appendix or behind disclosures.
>
> **7. Evidence is available on demand, not front-loaded.** The claim carries its label and its number **inline**; the full exhibit sits behind a `<details>`/`<summary>` disclosure, in a footnote, or in the workings appendix. Native `<details>` is the mechanism — the page loads no script, so it is the only progressive disclosure available, and it is enough. **Test as you compose: could a reader who opened no disclosure still state the direction, the options and their costs?** If not, evidence is load-bearing where it should be supporting — move it.
>
> **8. Compose the page.** FIRST load `Skill(artifact-design)` to calibrate the design investment; follow it. Then WRITE a single self-contained HTML file to `<pagePath>` (in the session's `builds/` — this is the durable, attachable artifact, composed ONCE here; the orchestrator publishes this very file, it is never re-generated):
> - Self-contained & CSP-safe: inline all CSS/JS, embed every asset as a `data:` URI. No external hosts.
> - **No third-party renderer — emit diagrams as inline `<svg>` or a pre-rendered PNG `data:` URI, never as a diagram-language block.** The page is published as a plain static file on S3 and loads no script from anywhere; **mermaid is the trap** (an artifact host renders `<pre class="mermaid">` natively, so it is the natural reach, and here it silently degrades to literal source text — same for Chart.js, KaTeX, D3).
> - Theme-aware (light AND dark), responsive (wide tables/images scroll inside their own container; the page body never scrolls sideways at 400px).
> - Honest `<title>` and favicon (emoji). Do NOT impersonate a real org or person; do NOT fabricate records, receipts, or reviews. If the subject matter would function as the real thing, note that in your return so the orchestrator publishes as a file for the user to judge.
>
> **9. Output Contract.** WRITE the dossier to `<dossierPath>` using the Direction Dossier template (`assets/TEMPLATE_PROVE_VISIONARY.md` at `<skillAssets>`; do NOT hardcode `~/.claude`): the question + what answers it, the three-label claim ledger, the costed-options block, load-bearing assumptions, the falsifier register, assets (+ any that failed), and the scope block. **Write its SKELETON FIRST — every section header present, each marked `IN PROGRESS` — before you ground anything**, and fill each as you establish it: a lane that dies mid-run must leave a dossier the next one resumes from rather than nothing. WRITE the page HTML to `<pagePath>` (in `builds/`) — the single, self-contained deliverable; do not write a second copy anywhere. Think in the notebook: append your stream via `<LOGGING>` every ~5 tool calls (a heartbeat hook BLOCKS after 10 tool calls without a log). Then RETURN a tight manifest — the question, the label tally (N measured / N inferred / N proposed), the options with a one-line cost each, any claim downgraded to a preference for want of a falsifier, assets rendered + any that failed, and `<pagePath>`. Do NOT dump the HTML or the base64 into your return.

**Substituting paths (hand fully-substituted ABSOLUTE paths, never placeholders):** `<dossierPath>` = `<trailDir>/<slug>_PROVE_VISIONARY.md` and `<pagePath>` = `<trailDir>/<slug>_VISION.html` (both durable, in `builds/`); raw captured assets under `<assetDir>/` (scratchpad — throwaway, embedded as `data:` URIs); `<skillAssets>` = this skill's own `assets/` dir, resolved from where you read this file.

**Substituting `<LOGGING>`:** the concrete command — append via `engine log <the active session's log path>` using the notebook schemas in this skill's `assets/TEMPLATE_PROVE_VISIONARY_LOG.md` (Measured / Inferred / Proposed / Falsifier / Option-Costed / Do-Nothing / Assumption / Asset-Rendered / Asset-Failed / Downgraded-To-Preference / Moved-To-Workings).

**Before dispatching — `§CMD_LOG_SKILL_INVOCATION`:** log this dispatch to the session log (why + the question + how to re-tread) as the last step before the `Task`/`Agent` handoff.

Dispatch to the background by default (`run_in_background: true`). Foreground only if you need the artifact before your very next step.

## 3. The Honesty Gate

This is where `/prove-visionary` earns its name. `/prove`'s gate asks *"does this asset show what its caption claims?"*. This gate asks a different question: **is every claim labelled, is every proposal falsifiable, is every number sourced, is the do-nothing option present — and would a skeptical reader feel sold to?** Read the **dossier** (not the big HTML — it keeps you lean), and open the rendered page for the checks that need eyes.

Run all nine. Each is pass/fail, and a failure is a targeted edit (small fix inline, or a re-dispatched focused correction) followed by a re-check — not a note in the report.

**G1 — Label coverage.** Every claim carries `measured`, `inferred` or `proposed`, **visibly on the page**, not only in the dossier. Take the load-bearing claim in each of the three classes and confirm the page shows its label where the reader meets the claim. An unlabelled claim is a claim the reader will read at whatever confidence the typography suggests.

**G2 — The skip test (the one that decides whether the page flies).** Read ONLY the masthead, the direction, the runway headline and the option cards, with every disclosure closed. **Can you state the direction, the options and their costs?** If not, evidence is load-bearing where it should be supporting — send it back to move bulk into the workings. This is the check that catches the page's most likely failure, and it cannot be done from the dossier alone: open the page.

**G3 — Falsifier coverage.** Every `proposed` and every `inferred` claim names what would falsify it or what would make it obviously right. Any that cannot must appear on the page as a **preference**, in that word. A proposal with no falsifier and no preference label is the failure this skill exists to prevent.

**G4 — Number provenance.** Every number on the page carries its denominator and where it came from. Pick the single number the direction rests on and **check it yourself** against its source — the file, the query output, the report line. A number you cannot source is cut, not hedged. This does not relax from `/prove`.

**G5 — Costed options.** Every option has all four fields — fixes / leaves unfixed / risks / the cheap check. An empty "leaves unfixed" means the option is under-examined. **The do-nothing option is present**, or the page names who ruled it out and on what grounds, and it carries its own risks rather than standing as a strawman.

**G6 — Proposed looks proposed.** Open the rendered page and confirm a `proposed` asset cannot be mistaken for a `measured` one at a glance: no projection rendered in the same treatment as a measurement, no before/after where a designed "after" matches the styling of a captured "before". Confirm the legend states the convention.

**G7 — The runway budget.** The current-state section is not the longest section on the page. If it is, the page is a status report wearing a future tense — send it back.

**G8 — The sold-to test.** Read it once as a skeptic who does not want this to happen. Where does the page ask for trust it has not earned? Every place you feel sold to, there is a missing label, a missing denominator, a missing cost, or a missing falsifier. Name each one and fix it. A hedge honestly stated beats a confident overreach.

**G9 — Page mechanics.** Run `/prove-explore`'s C9 (in `prove-explore/SKILL.md` § "3. The Coverage Gate") as written there, on the `builds/` file and not on the published copy, because `publish-s3.sh` adds its own scripts to the copy it uploads. It tests the page rules in §2 step 8 and Constraints in a driven browser instead of by eye: no foreign request, no script, both themes, no sideways scroll at 390px.

**Degrade gracefully.** If the grounding turned out thinner than expected, confirm the page *says so* — a direction that rests on one measurement says it rests on one measurement. A thin ground honestly declared is a usable page; a thin ground dressed up is not.

## 4. Publish & Report

**The shareable deliverable is an S3 URL.** The composed `<pagePath>` (`builds/<slug>_VISION.html`) is one file — every asset embedded as a `data:` URI, nothing referenced — so it uploads to S3 as a single object, served at an HTTPS URL that anyone with the link can open when the project prescribes a public bucket (the defaults below publish to a local store). The on-disk `builds/` file stays the durable local copy (and the Linear-attachment source); the **S3 URL** is what you hand to a teammate, a ticket, or a downstream skill.

**Read the PORT, never the bucket, to know which store got the bytes.** Several local proof stores run here and every one is named `proofs` at the same prefix, so a publish to the wrong one succeeds and returns a URL serving another store — a bucket-name check passes and is then read as evidence. `publish-s3.sh` states the resolved endpoint with its port before writing, refuses a resolved port that disagrees with the project `.env`, and reads the object back to compare it against the bytes it sent. Expect those bytes to differ from your `builds/` source: the publisher rewrites the page before uploading, so a source-sha comparison reports a meaningless mismatch.

**Config** resolves first-wins: a real environment variable, else the nearest project `.env.local`/`.env`, else the manifest defaults (`PROVE_S3_BUCKET=proofs`, endpoint `http://127.0.0.1:9440`, region `us-east-1`, prefix `proofs`). **It never guesses a bucket** — if none resolves, the page is already composed in `builds/`, so report that file, tell the user to prescribe the bucket, and **stop at publish**. Do not silently skip and do not fall back to another host. A loopback URL opens only on the author's machine: say so when handing it over, and attach the `builds/` file wherever someone else must read it.

**Single generation.** Upload the **already-composed** `<pagePath>` from `builds/` — the subagent composed it once in §2; you upload that same file and never re-render it. The upload is one command, using `/prove`'s **shared** helper at its absolute path (referenced, never copied — the sibling owns it):
> `~/.claude/skills/prove/assets/publish-s3.sh <pagePath> <slug>`

It derives the per-user key segment from the AWS caller identity, mints an **unguessable** key (`<prefix>/<user>/<slug>-<rand>.html`), uploads with `--content-type text/html`, and prints the **public URL to stdout** (capture it — `aws s3 cp` chatter goes to stderr). The random suffix keeps the link unlisted: shareable, not discoverable.

If the page mentions ticket keys, the helper warns on stderr that it is publishing without ticket data. That warning is **non-fatal and expected here** — this skill does not bake ticket metadata, so its ticket references stay plain text/links. Publishing proceeds; do not treat it as a failure.

**Auto-open for the author.** After capturing the URL, open it — `open "<url>"` (macOS) or `xdg-open "<url>"` (Linux), best-effort (`|| true`; skip silently in headless/CI). An orchestrator step, NOT part of the helper, which stays pure so forwarder skills can call it programmatically.

**For a ticket / teammate** (chained from `/snapshot`, `/communicate`, `/inbox-post`, `/pr`, or the user says "attach / share / put it on the ticket"): hand over the **S3 URL**. When the target wants a copy that travels with the ticket, ALSO attach the `builds/` file to Linear — it is self-contained and identical to what was uploaded. `prepare_attachment_upload(issue, filename, "text/html", size)` → PUT the raw bytes to the signed `uploadRequest.url` with its headers verbatim (`curl --data-binary @<pagePath>`, 60s window) → `create_attachment_from_upload(issue, assetUrl, title, subtitle)`.

**Never publish** a page that impersonates a real org/person or presents fabricated records as genuine — keep it as a local file in `builds/` and let the user decide.

**Report:** lead with the **S3 URL**, then the durable `builds/` artifacts — the page (`<trailDir>/<slug>_VISION.html`) and its dossier (`<trailDir>/<slug>_PROVE_VISIONARY.md`) (`§CMD_LINK_FILE` each). Close with a one-line honesty summary:
`Labelled: N measured · N inferred · N proposed · options costed: N (do-nothing: present/ruled-out-by <who>) · downgraded to preference for want of a falsifier: N · the ask: <the decision + who makes it>.`

Then **stop**. `/prove-visionary` proposes, publishes, and reports — it does not fix, commit, file, or decide. Offer the natural chains (`/ticket` to capture an option as work, `/experiment` to run the cheap check the page named, `/snapshot` to checkpoint, `/brainstorm` if the options turn out to be the wrong set) but never auto-run them.

## Worked Example (compressed)

*Question:* "How wide should the percentage re-carve be — one member, the family, or the whole declarations-grid taxonomy? Answering it means naming the scope, its cost, and the check that would size it." *Status:* **Proposal** — the operator decides scope.

- **The ground (trusted):** a `/council` domain finding that every percentage-taking predicate was earned from a declarations-grid column; a FLAKE scatter measurement; a selector-loss measurement relayed mid-task. Conclusions are the INPUT.
- **The direction (leads the page):** *"Define the shape in the vocabulary, at the level of the whole family. That level is wide enough to remove the sink and still within what has been measured."* One paragraph, point first, before any exhibit.
- **The runway (once, briefly):** three `measured` claims with denominators — 2,034 of 91,405 facts carry a percentage value; 154 land on `limit.percentage` across 3 documents; 2 of 7 declared percentage members receive zero facts anywhere on disk. Each number's full query sits behind a disclosure. The runway is four paragraphs; the moves are twelve.
- **The moves (costed, not listed):**
  - *Narrow — one member.* Fixes: the sink's worst case. Leaves unfixed: the six other members, all still grid-shaped. Risks: a second re-carve in a month. Cheap check: count distinct printed column headings in a 50-page sample.
  - *Family — the seven percentage members.* Fixes: the taxonomy shape for this value kind. Leaves unfixed: the same defect in the money family. Risks: the carve lands on a corpus slice of 2 documents. Cheap check: re-run the scatter on a wider selector sample.
  - *Whole grid taxonomy.* Fixes: the class of defect. Leaves unfixed: nothing known. Risks: a rewrite priced from a 20-page slice; the measured 69.3% moving-subject share bounds how much any predicate-only ruling can reach. Cheap check: same wider sample, plus one labelled multi-doc set.
  - *Do nothing.* Fixes: nothing. Leaves unfixed: everything above. Risks: `other` keeps absorbing constructions silently, and a scatter-only metric cannot see a complete hole — so the cost compounds invisibly. Not a strawman; on the smallest option it is genuinely competitive.
- **Labels in action:** the fact counts are `measured` (with denominators, dates, and the query behind a disclosure). *"The family is the natural carve boundary"* is `inferred` — from the `earnedFrom` pattern, because every member names a column. The proposed `members-plus-selector` shape is `proposed`, rendered as a dashed inline SVG with a `proposed` chip, and falsified by: *"a 50-page sample turning up printed constructions the shape cannot express."*
- **The gate:** G2 passed on the second pass — the first draft opened with the seven-member ledger and the direction arrived on screen three; the ledger moved into the workings and the direction moved to the top. G4: the orchestrator re-ran the 154-of-2,034 count itself. G7: the runway had been the longest section and was cut by half.

## Anti-Patterns (name them, avoid them)

- **The status-quo report in a vision's clothing** — the most likely failure, and the one a *careful* author drifts into. Every measurement is true, every exhibit is real, and the reader finishes knowing the present better and the direction no better at all. The runway is not the flight: state the current state once, early, briefly, and then move. G7 and G2 exist to catch this.
- **The pitch deck** — energy, momentum, and nothing a reader could check. No labels, no denominators, no do-nothing, and every number's provenance vanished into confidence. A pitch deck that smuggles invented numbers is worse than no page.
- **The roadmap with no falsifier** — a sequence of phases nobody could ever show to be wrong. A vision with no falsifier is a wish; say which observation would break it, or call it a preference.
- **The option list with no costs** — a menu that pushes the decision back to the reader while pretending to help. Every option carries what it leaves unfixed and what it risks, or it has not been examined.
- **The missing do-nothing** — the absence is usually the tell that a page is selling. Present it, cost it honestly, or name who ruled it out.
- **Confident extrapolation in the typography of a measurement** — a projection set in the same weight, the same chip, the same table as an observation. The label and the visual convention are what keep these apart; a reader scanning at speed reads typography, not disclaimers.
- **A "vision" that is really an unreviewed plan** — a page that reads as decided when nobody decided, borrowing authority from its own confidence. The masthead status is not decoration; declare Proposal and name who decides.
- **Re-running an analysis to manufacture support** — quietly re-measuring until a number favours the direction you already like. The grounding is what upstream found; a measurement the direction needs and does not have is a *cheap check*, named as such.
- **Buried honesty** — the scope block, the assumptions or the labels hidden at the bottom. They sit where the reader meets the claim.
- **Templated AI-artifact look** — the generic gradient-card page. `Skill(artifact-design)` exists to calibrate real design; follow it.

## Constraints

- **`¶INV_VISIONARY_SAYS_MORE_CLAIMS_NO_MORE`** — the page may reason forward, propose, extrapolate and recommend. It may NOT invent a number, attribute a measurement that was never taken, or present a projection in the typography of a finding. It loosens what the page may SAY, never what it may claim as MEASURED.
- **`¶INV_VISIONARY_LABELLED_CLAIMS`** — every claim carries exactly one of `measured` · `inferred` · `proposed`, **visible on the page**, not only in the dossier. `measured` = observed, with its number, denominator, date and source. `inferred` = reasoned from measured things, carrying its step (*from X, because Y*). `proposed` = does not exist yet, carrying a falsifier or a cheap check in place of evidence. A claim fitting none of these is cut.
- **`¶INV_VISIONARY_FALSIFIER_OR_PREFERENCE`** — every `proposed` and every `inferred` claim names what would falsify it or what would make it obviously right, preferring a cheap, nameable check. A claim nothing could falsify appears on the page as a **preference**, in that word. A vision with no falsifier is a wish.
- **`¶INV_VISIONARY_OPTIONS_ARE_COSTED`** — options are costed, never listed: what it fixes · what it leaves unfixed · what it risks · the cheap check that would size it, in the same units across options or with a stated reason they are not comparable. The honest **do-nothing** option is present with all four fields including its own risks, or the page names who ruled it out and on what grounds.
- **`¶INV_VISIONARY_NUMBERS_KEEP_PROVENANCE`** — no relaxation from `/prove`. Every number carries its denominator, its date and its source. A number that cannot be sourced is cut, not hedged.
- **`¶INV_VISIONARY_DIRECTION_LEADS`** — the direction leads the page; the current state is stated once, early, briefly, and is never the longest section; the full workings sit behind disclosures (`<details>`, footnotes, an appendix). A skeptical reader can reach the artefact; a persuaded reader never walks through it to reach the point.
- **`¶INV_VISIONARY_PROPOSED_LOOKS_PROPOSED`** — an asset depicting something that does not exist yet is visually distinguishable from a captured one at a glance, by one consistent convention stated in the legend. Mockups are allowed; a mockup presented as real is not.
- **Proposes, never decides.** It lays out the question, the options and their costs. It never makes the call, never fixes (`/fix`), never commits (`/snapshot`), never ships (`/pr`), never files (`/ticket`). Chains are offered, never auto-run.
- **Not for a settled finding.** A resolved claim with renderable evidence goes to `/prove`. Routing one here trades `/prove`'s tighter discipline for machinery it does not need, and produces a direction page about a thing that is not a direction.
- **Grounding is trusted, never re-litigated.** The upstream verdicts the page stands on are the input. A missing measurement is named as a cheap check, not manufactured.
- **Subagent for the heavy lift; the honesty gate + publish stay with the orchestrator.** The subagent grounds, costs and composes (base64 never returns to the orchestrator); the orchestrator owns the nine-check gate and the S3 publish — the human-facing gate.
- **Page rules are hard.** Self-contained, CSP-safe, theme-aware (light AND dark), responsive with no sideways body scroll at 400px, honest title and emoji favicon, no client-side renderer to fetch (the page is a static S3 object — inline `<svg>` or an embedded PNG, never a mermaid/Chart.js/KaTeX/D3 block, which degrade to literal source text). Progressive disclosure uses native `<details>`, the only mechanism a scriptless page has. Never impersonate a real org/person; never present fabricated records as genuine — such content stays a local file, published only at the user's choice.
- **Durable in `builds/`, attachable.** The page (`<slug>_VISION.html`) and its dossier (`<slug>_PROVE_VISIONARY.md`) live in the session's `builds/`, beside the `/build` / `/probe` / `/council` trail. Because the HTML is self-contained, it attaches directly to a Linear ticket. Raw captured assets stay in scratchpad as throwaway intermediates. Both persist on a partial run, because the dossier skeleton is written **before** the grounding starts — a killed lane leaves a record the next one resumes from.
- **Lightweight + sessionless.** Runs within the active session: scope the question → dispatch (ground/cost/compose) → honesty gate → publish → stop.
