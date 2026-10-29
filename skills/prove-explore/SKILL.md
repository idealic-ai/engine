---
name: prove-explore
description: "Answer a large question by compiling it into a self-contained, shareable MAP — the territory, its parts, how they connect, and where the blank regions are — rather than compressing it into a verdict. The expansive sibling of /prove: where /prove SHOWS one settled claim and /prove-visionary PROPOSES a direction, /prove-explore EXPLAINS a whole — for a question whose answer is knowable or already known but too large to fit in a thesis. Spine: it loosens the SHAPE AND SIZE of the answer, never the evidence — the question is decomposed into named sub-questions, the page's outline IS that decomposition, every section carries real assets or honest provenance exactly as /prove demands, every section owes the reader something that CARRIES its answer or declares why it cannot (and a decorative asset fails that gate where a declared-bare section passes), the map states its own boundary where the reader meets it, unknowns are first-class (a measured absence, an unsettled question and an unexamined region each render differently, and none of them may hide behind a disclosure), and a genuine disagreement is shown rather than smoothed. A subagent assembles + composes; the orchestrator owns the per-section honesty gate and the S3 publish. A building block: it explains and reports, never fixes, commits, files, or decides. For ONE mechanism taught to a newcomer — the idea in everyday words, how it works, a worked example with real values, its edge cases — use /prove-explanation instead; /prove-explore maps a whole. Triggers: \"how does X actually work\", \"map this subsystem\", \"explain the whole picture\", \"write up the state of this\", \"I need to understand this properly\", \"walk me through how this fits together\", \"what are all the moving parts here\"."
version: 1.0
tier: lightweight
args: "[<the question this page must answer>] [-- <the reader / what they must be able to understand>]"
---

Answer a question too large for a verdict by turning it into a self-contained, shareable **map**. `/prove-explore` takes a question whose answer is *knowable* — how a subsystem actually works, what the real state of a body of work is, what the moving parts are and how they connect — and hands it to a background subagent that decomposes it, grounds each part in real evidence, and composes a page a reader can walk. You then run the per-section honesty gate and publish it to a public S3 URL.

This is the **expansive sibling of `/prove`**. Where `/prove` compresses a settled finding into one thesis and a verdict, `/prove-explore` opens a knowable answer into a structured territory. As a **building block** it produces a page, not a change and not a conclusion: it never edits code, never commits, never files a ticket, and never rules on anything it maps.

**When to use this instead of its siblings — route by the SHAPE OF THE ANSWER, not the size of the subject:**

- The answer is **one claim** that is settled and needs *showing* → **`/prove`**. A thesis with renderable evidence does not belong here; this skill's machinery adds breadth it does not need and loses `/prove`'s tighter discipline.
- The answer is **not settled** and someone must *decide* → **`/prove-visionary`**. Options, costs, falsifiers, a recommendation. Routing an open question here produces a map of a thing that has no shape yet.
- The answer is **knowable or already known, and large** — it has parts, relations, and a boundary — and someone must *understand* it → **`/prove-explore`**.

*The spine — non-negotiable:* **`/prove-explore` loosens the SHAPE AND SIZE of the answer, and loosens nothing about the evidence.** The page may be long, many-sectioned, and structured as a territory instead of a claim. Every assertion in it still carries either a real rendered asset or an honest provenance label, exactly as `/prove` demands. **Breadth is bought by adding sections that answer sub-questions actually asked — never by adding sentences that assert more.** Remove that distinction and this skill produces a confident tour of a subject nobody checked, which is strictly worse than a short page that proved one thing.

*The second half of the spine — the architecture:* **the map comes before the parts, and the boundary comes with the map.** `/prove` leads with evidence and closes with a verdict; `/prove-visionary` leads with direction. This page leads with **the shape of the answer** — what the territory is, what its regions are, and where it ends — so a reader sees the whole before any one region and **learns what is NOT covered at the same moment they learn what is**. A reader who stops after the map should have an accurate, incomplete picture; never a confident, wrong one.

*Crucial constraint:* `/prove-explore` does NOT own a session. It reads the *active* session's context and writes its paper trail into that session — the **dossier and the composed HTML into `builds/`** (durable, attachable to a Linear ticket), the **raw captured assets into scratchpad** (throwaway intermediates, embedded into the HTML as `data:` URIs).

# /prove-explore Protocol

## 1. Scope the Question — and Decompose It

The decomposition IS the design of the page. Do it here, before anything is composed.

**A. The Question** (one question, large answer)
State the question the page answers, and what would count as having answered it.
*(Illustrative — adapt, don't copy: "How does an email actually get from the Graph API to a claim, and what decides where it lands? Answering it means naming every stage, what each one can refuse, and where a message can be lost." / "What is the real state of the explainer set — what is published, what is stale, what was never harvested?")*
*Constraint:* the answer must be **knowable**, not *desirable*. If answering it requires deciding something, it is `/prove-visionary`'s. If it collapses into one claim, it is `/prove`'s.

**B. The Sub-Questions** (required — this is the skill's load-bearing step, and `/prove` has no equivalent)
**Decompose the question into named sub-questions.** Each becomes a section of the page; the page's outline IS this list. Write them down in the dossier before dispatch.

Two rules, both enforced at the gate:
- **Every section answers a named sub-question.** A section that answers none is cut, however interesting.
- **Every sub-question gets a section, or appears on the page as unanswered** — named, with why. A sub-question that quietly vanishes is how a map comes to look complete.

Aim for the smallest set that spans the question. If a sub-question needs sub-sub-questions, that is a sign the question is really two questions and should be two pages.

**C. The Boundary** (required — what the map does NOT cover)
Name explicitly what is **outside** this map. For a single-claim proof the scope note is hygiene; **for a map it is load-bearing**, because an incomplete map read as complete is the defect this skill most easily produces. A page headed with a broad name that is really about one narrow slice misleads a human reader and an agent equally — that is a measured failure, not a hypothetical.

**D. The Epistemic Inventory** (required — the blank regions are part of the answer)
Before composing, sort what you have into these kinds, and keep them distinct through to the page:
- **Known** — established, with its evidence.
- **Measured absent** — somebody looked and it is **not there**. A *finding*, carrying its reading and the positive control behind it; never filed as an unknown.
- **Not established** — somebody looked and could not settle it. Carries *what would settle it*.
- **Not looked at** — nobody has examined it. Carries *that nobody has*.

**Measured absent, not established and not looked at are different findings and never share a treatment.** Blending them is how a map's blank regions get read as empty ground — and demoting a measured absence to "unknown" throws away the one reading somebody paid for.

**E. The Reader & the Job**
Name the reader — **teammate** / **newcomer** / **operator** / **future self** — and the single job: what must this reader be able to *understand* after ten seconds of the map, and after a full read? The reader drives the density and how much vocabulary may be assumed.

**F. The Ground** (what the page stands on)
Name the work the page draws on and where its verdicts live: a `/probe` `_PROBE.md`, `/analyze` findings, an `/experiment` VERDICT, a `/council` report, a `/scrutinize` critique, measurements on disk, the active session's log and builds. These are **trusted exactly as `/prove` trusts them** — the page presents established work and does not re-litigate it. A finding you genuinely doubt goes back to `/probe` or `/analyze`, never through here. A region the map needs and nobody has measured is **"not looked at"**, named as such, never filled in by inference.

**G. The Trail** (durable in `builds/`, throwaway in scratchpad)
Set:
- `<trailDir> = <sessionDir>/builds/` — the durable home.
- `<pagePath> = <trailDir>/<slug>_EXPLORE.html` — the composed map, a **durable** self-contained session artifact (directly attachable to a Linear ticket).
- `<dossierPath> = <trailDir>/<slug>_PROVE_EXPLORE.md` — the record behind it.
- `<assetDir> = <scratchpad>/prove-explore-<slug>/` — raw captured assets: throwaway, since they get embedded as `data:` URIs.

Mint a short kebab-case `<slug>` from the question (e.g. `classification-pipeline-map`, `explainer-set-state`). *Before minting:* run `ls <trailDir>` — if an existing `<slug>_*` cluster matches this work, REUSE that slug so the page clusters with the `/build`, `/probe`, `/council` artifacts.

**Acknowledge:** echo your setup in exactly one line:
`Mapping: <question> — <N> sub-questions; reader: <who>; ground: <source work>; trail: <trailDir>/<slug>_PROVE_EXPLORE.md.`

**State the spine** back to yourself: the page may be long and many-sectioned; every section answers a named sub-question and gives the reader something that carries that answer, or says why it cannot; every assertion carries a real asset or an honest label; the boundary sits with the map; unknowns stay distinct.

**Load the voice before any words are written.** The page's structure comes from the design kit; its words follow `~/.claude/engine/.directives/VOICE.md`, which the session start loads. Hold it for the run. Three points matter most on a map, and §3 checks them:

- **Say near the top what the map covers and who it is for.** The boundary sits with the map, so the reader knows the territory before entering it.
- **Introduce a thing before discussing it.** A map is read by someone who does not know the territory, which is why they opened it.
- **Name the members of a list rather than stating its count.** A map is full of lists, and a count in prose goes stale when a member is added.

Twenty sections of unbroken prose are still a wall, however well each is written; the carry obligation (§2 step 6, gated at C10) is what prevents that. If `VOICE.md` is missing, say so in the acknowledgement line and compose from the points above.

## 2. Dispatch the Cartographer — Decompose → Ground → Structure → Compose (subagent)

**Backgroundable & parallelizable.** This dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working, and when the sub-questions are genuinely independent it can be fanned out one lane per region and reconciled.

The subagent does the heavy, context-bloating work — grounding each sub-question, rendering the real assets, and composing the draft HTML (so the base64 blobs **never return to your context**). It writes two artifacts: the **dossier** (every section → its sub-question → its evidence + provenance) and the **draft page**. It does NOT publish, and it does NOT re-open an investigation.

**Use the wait — don't idle.** When you background it, get a step ahead: re-read the sub-question list so you know which sections carry the load, and decide which rendered asset you will eyeball in §3.

Build the subagent's prompt entirely self-contained — it cannot see your memory:

> You are a **cartographer** compiling a MAP that answers a large question from work that has already been done. Your job: decompose, ground each region in REAL evidence, and compose an honest page a reader can walk. You do NOT investigate, you do NOT re-verify the findings you are given, and you do NOT fix anything — the established work is your INPUT. You also do NOT rule, recommend, or decide: a verdict belongs to `/prove` and a recommendation to `/prove-visionary`.
>
> **1. The Question and its decomposition:**
> - **Question:** `<question>` — answering it means `<what counts as answered>`.
> - **Sub-questions (the page's outline — each becomes a section):** `<the named list>`
> - **Boundary — explicitly OUT of scope:** `<what the map does not cover>`
> - **Reader & job:** `<reader>` — must be able to `<the 10-second job>` and `<the full-read job>`.
> - **Ground (trusted, not re-derived):** `<pointers>`. Read these to learn what was concluded and TRUST it. If something looks wrong, say so in your return, but do NOT re-run an analysis to settle it.
> - **Rule on the decomposition itself — it was fixed before anyone saw the territory.** Return `decomposition: holds` | `really-two` | `sub-question <N> wrong`, with the measurement behind it. A region set that turns out to share no measurable relation is **really-two**: say so rather than composing one map over a territory with no spine, and do NOT silently re-cut the outline yourself.
>
> **2. Ground every section — trust the findings; verify only the RENDERING.** For each sub-question, find the real evidence that shows its answer and confirm the depiction is faithful: the render actually shows the thing, and the caption does not outrun what the render shows. Record each claim's **provenance**: `trusted-upstream <source>` (the finding's own verdict — the default) or `checked-here <YYYY-MM-DD>` (something YOU confirmed purely for the presentation — **always with the date you read it**, since the page outlives the reading). A claim with no showable evidence is either cut or carried as attributed text ("per the `/analyze` findings: …").
>
> **3. Sort every region into Known / Measured absent / Not established / Not looked at**, and keep them visually distinct on the page through one convention stated in the legend. **A measured absence is a finding and never shares a treatment with an unknown.** A `measured absent` region carries the reading and the control that fired for it; `not established` carries what would settle it; `not looked at` carries that nobody has looked. **The blank regions are part of the answer — render them, do not omit them, and render every one of these labels OUTSIDE any collapsed element** (the gate tests that mechanically).
>
> **4. Show disagreement; never smooth it.** Where two sources conflict, or the parts genuinely do not fit together, **put both on the page with their evidence and say they disagree.** Resolving a contradiction by picking the nicer side is the behaviour this instruction forbids. If one side is better evidenced, say which and why — that is a finding, not a tidy-up.
>
> **5. Capture Real Assets — from the ACTUAL source, never a mockup.** Render the evidence itself and embed as `data:` URIs:
> - **Code / config** → the real file, the real lines, quoted with its path.
> - **Rendered UI / a live page** → a headless screenshot (`playwright`/`puppeteer`/`chrome --headless --screenshot`) of the actual thing.
> - **CLI / test / query output** → captured VERBATIM, not paraphrased.
> - **PDF pages** → `mutool draw -o page-%d.png -r 150 <file.pdf> <N>`.
> - **Maps / diagrams / charts** → generated from real data; every node a real component with a real name. No lorem, no illustrative fakes, no "representative" stand-ins.
> - If an asset genuinely cannot be captured, RECORD it in the dossier (`asset-failed` + why) and degrade — never fabricate a stand-in.
>
> **6. Make every section CARRY its answer — or say in the dossier why it cannot.** Each section owes the reader something to look at that delivers its one-line answer: a render, a diagram, a verbatim capture, a side-by-side, a table of the real rows. **The test is subtraction, not presence** — cover the paragraphs and ask whether the asset still answers the sub-question. If it does not it is decoration, and decoration here is worse than nothing. The honest out is to mark the section `bare: <why>` in the dossier ("the answer is a policy, and a policy has nothing to photograph") — **a declared-bare section passes the gate and a weakly-illustrated one fails it**, so a filler visual costs you rather than clearing anything.
>
> Two composition rules, both drawn from the material rather than from styling:
> - **Open each region with what would surprise a reader who thought they knew the territory** — the one thing that is not what they would guess. It is the most engaging opener available, and it is a claim like any other: it carries its evidence and its provenance label, or it is not written.
> - **Vary the shape of a section.** Sections cast in one mould read as a wall however tersely each is written — the sameness is the texture, and word-count discipline does not touch it. Let the evidence pick the shape: a walk, a comparison, one large render, a table, a short verbatim.
>
> **7. Choose a Structural Device that CARRIES the territory** (not decoration). Pick the one that makes the shape self-evident:
> - **A map or layered diagram** whose nodes are the real components and whose edges are real relations.
> - **A walk along the actual path** a thing takes through the system — follow one real subject end to end.
> - **Parts-and-connections** — each part, what it does, what it refuses, what it hands on.
> - **A known/unknown overlay** where the encoding marks epistemic state rather than category.
> Same rule as the parent: the device must carry the truth, never decorate, and any colour has a legend and a real referent. **Before drawing any chart, diagram or encoded figure, load `Skill(dataviz)` and follow it** — `artifact-design` calibrates the page, `dataviz` governs the figure: which form the data actually wants, colour that encodes a fact, the legend and axis that make it readable.
>
> **8. Compose the Page.** FIRST load `Skill(artifact-design)` to calibrate the design investment — and `Skill(dataviz)` too if any section carries a chart or an encoded figure; follow them. Then WRITE a single self-contained HTML file to `<pagePath>`:
> - Self-contained & CSP-safe: inline all CSS/JS, embed every asset as a `data:` URI. No external hosts.
> - **No third-party renderer — emit diagrams as inline `<svg>` or a pre-rendered PNG `data:` URI, never as a diagram-language block.** The page is published as a plain static file and loads no script; **mermaid is the trap** (an artifact host renders it natively, so it is the natural reach, and here it silently degrades to literal source text — same for Chart.js, KaTeX, D3).
> - Theme-aware (light AND dark), responsive (wide images scroll inside their own container; the body never scrolls sideways at 400px).
> - **A verbatim capture is exempt from the scroll-inside-its-container licence** — it must be legible in full where it sits, never clipped and never scroll-to-finish, because output a reader has to scroll to finish is half an asset. Re-lay out the **block** (give it full width) rather than reformatting the capture: a reformatted capture is a paraphrase.
> - **Lead with the map and its boundary together** — the shape of the answer, its regions, and what is out of scope, all before the first region opens. Then the sections, in the decomposition's order. Progressive disclosure via native `<details>` (the only mechanism a scriptless page has) for the workings, never for the boundary or the unknowns.
> - Honest `<title>` and emoji favicon. Do NOT impersonate a real org or person; do NOT fabricate records. If the subject would function as the real thing, note it in your return.
>
> **9. Output Contract.** WRITE the dossier to `<dossierPath>` using this skill's `assets/TEMPLATE_PROVE_EXPLORE.md` (at `<skillAssets>`; do NOT hardcode `~/.claude`): the question, the sub-question → section → evidence → provenance → **carries-or-bare** ledger, the epistemic inventory, any disagreements shown, assets rendered (+ any that failed), the structural device, and the boundary. **Write its SKELETON FIRST — every section header present, each marked `IN PROGRESS` — before you ground anything**, and fill each as you establish it: a lane that dies mid-run must leave a dossier the next one resumes from rather than nothing. WRITE the page to `<pagePath>`. Think in the notebook: append your stream via `<LOGGING>` every ~5 tool calls (a heartbeat hook BLOCKS after 10 tool calls without a log). Then RETURN a tight manifest — the question, the `decomposition:` verdict, the sub-question list with each section's provenance counts, the epistemic inventory totals, disagreements shown, assets rendered + failed, the device, **`sections: <N> · carrying: <N> · bare: <the names, each with its reason>`**, and `<pagePath>`. Do NOT dump the HTML or the base64 into your return.

**Substituting paths (hand fully-substituted ABSOLUTE paths, never placeholders):** `<dossierPath>` = `<trailDir>/<slug>_PROVE_EXPLORE.md` and `<pagePath>` = `<trailDir>/<slug>_EXPLORE.html` (both durable, in `builds/`); raw assets under `<assetDir>/`; `<skillAssets>` = this skill's own `assets/` dir, resolved from where you read this file.

**Substituting `<LOGGING>`:** the concrete command — append via `engine log <the active session's log path>` using the notebook schemas in this skill's `assets/TEMPLATE_PROVE_EXPLORE_LOG.md`.

**Before dispatching — `§CMD_LOG_SKILL_INVOCATION`:** log this dispatch to the session log (why + the question + the sub-question list + how to re-tread) as the last step before the handoff.

Dispatch to the background by default (`run_in_background: true`). Foreground only if you need the artifact before your very next step.

## 3. The Coverage Gate

`/prove`'s gate asks *"does this asset show what its caption claims?"* once. **This gate asks it per section**, and adds the checks a map needs and a single-claim proof does not. Read the **dossier** (not the big HTML — it keeps you lean), and open the rendered page for the checks that need eyes.

Run them all. Each is pass/fail, and a failure is a targeted edit (small fix inline, or a re-dispatched focused correction) followed by a re-check — not a note in the report. **The cartographer's own self-check is an input to this gate, never a pass** — every check below is yours to run.

**C1 — Decomposition coverage, both directions.** Every section answers a named sub-question, **and** every sub-question has a section or appears on the page as unanswered with its reason. A section answering no sub-question is cut. A sub-question that vanished is restored or named. **Check both directions** — a one-way check passes a map that grew sections nobody asked for. **Then read the return's `decomposition:` verdict**: `really-two` or `sub-question <N> wrong` is a scoping finding you act on — re-cut deliberately or split the page — not something to publish over.

**C2 — The boundary test (the one that decides whether the map is honest).** Read ONLY the top of the page, with every disclosure closed. **Can you state what this map does NOT cover?** If not, send it back. Record the position as a number rather than an impression — the boundary text's character offset lands in the first quarter of the document — so the check reproduces on the next run. A reader who cannot find the edge will assume there is none, and an incomplete map read as complete is this skill's signature defect.

**C3 — Per-section provenance (this is where the gate scales with size).** For **every** section, confirm its load-bearing claim carries a real asset or an honest `trusted-upstream` label — **and that every `checked-here` claim carries the date it was read**, because a map is opened months later and a reading with no date is indistinguishable from a reading that has expired. **Do not sample one claim for the page** — a map has more sentences than a proof, so proportionally more opportunity to overreach, and the long middle is exactly where an unlabelled assertion hides. The honesty pass is per-section, not per-page.

**C4 — Eyeball the load-bearing render in each region.** Don't re-run the analysis — but don't ship a caption on faith either. For each section's principal asset, open the rendered image or quoted output **yourself** and confirm it depicts what its caption claims. Flag any caption you could not confirm against its asset. **A verbatim capture must also be legible in full where it sits** — one that clips or needs scrolling to finish is half an asset: re-lay out the block, never reformat the capture.

**C5 — Unknowns render as unknowns, and render where the reader is.** Open the page and confirm Known / Measured absent / Not established / Not looked at are distinct by one convention stated in the legend, and that **a measured absence cannot be read as an unknown**. Confirm each `not established` region carries what would settle it. **Then test visibility mechanically rather than by eye** — "visually distinct" does not test "visible": strip every `<details>…</details>` from the HTML and confirm each of `measured absent`, `not established`, `not looked at` and `out of scope` that the dossier carries still occurs in what is left, **zero of them inside-only**. An unknown behind a disclosure reads as empty ground, which is a failure and not a gap.

**C6 — No false coherence.** For each disagreement the dossier records, confirm the page **shows both sides with their evidence** and says they disagree. A contradiction resolved by picking the nicer side is the failure; a contradiction resolved by *evidence*, with the reasoning shown, is a finding and passes.

**C7 — The padding audit.** Read the page as someone paying by the sentence. Every paragraph must change what the reader knows or does next. **Length is earned by coverage, never by elaboration** — cut anything that restates a neighbouring section, re-explains a thing already introduced, or narrates the investigation instead of its result. This is the check that fights the skill's natural failure.

**C8 — The orientation test, and scannability as a property.** Read ONLY the map, the section headings and the assets — **no paragraphs**, which is how the page will actually be read. **Can you say what the thing is, how its parts relate, and what each region answers?** If the headings are labels rather than claims, if the map organises nothing real, or if the answer is unreachable without prose, the page has no spine. This is also the backstop against C10's escape: a page where most sections declare themselves bare fails HERE, because nothing is legible without reading.

**C9 — Page mechanics (the page rules are hard; this is where they get tested).** Open the composed page in a driven browser with the network blocked, in BOTH themes at a wide width and again at 390px, and confirm: zero foreign requests, zero console errors, and `documentElement.scrollWidth === clientWidth` at every width — **reconciled as that number, not as an escaping-element pass**, which reports clean on an overflow whose ancestor chain contains a clipping box. Then audit the source: zero `<script>`, no mermaid/Chart.js/KaTeX/D3 block, and every external URL inside a code block rather than in a `src`/`href`. Read both themes' colours back off `body` so neither is inheriting the host's background.

**C10 — The carry audit (mechanical, in C5's idiom).** Count the page's sections and, for each, name what carries its answer. Then run the subtraction on every section the reader is most likely to stop at: hide the prose and confirm the asset still delivers that section's one-line answer from the dossier. **NAME every bare section** and confirm each is declared `bare: <why>` in the dossier — bare on the page and silent in the dossier is a fail. **A decorative asset fails this check; it does not pass it** — a chart of two numbers, a diagram that redraws the headings, an icon row, anything that organises nothing real. Remove it and declare the section bare instead. Reconcile as the number, not as an impression: `sections: <N> · carrying: <N> · declared bare: <names> · decorative, removed: <names>`.

**Degrade gracefully.** If whole regions could not be grounded, confirm the page *says so* and renders them as `not looked at` rather than omitting them. A map with declared blank regions is usable; a map silently missing a third of its territory is not.

## 4. Publish & Report

**The shareable deliverable is a public S3 URL.** The composed `<pagePath>` is one file — every asset embedded as a `data:` URI — so it uploads as a single object served at a public HTTPS URL anyone with the link can open. The on-disk `builds/` file stays the durable local copy and the Linear-attachment source.

**Single generation.** Upload the **already-composed** `<pagePath>` — the subagent composed it once in §2; you upload that same file and never re-render it. One command, via the **shared** helper at its absolute path (referenced, never copied):
> `~/.claude/skills/prove/assets/publish-s3.sh <pagePath> <slug>`

It mints an unguessable key (`<prefix>/<user>/<slug>-<rand>.html`), uploads with `--content-type text/html`, and prints the **public URL to stdout** (capture it — `aws s3 cp` chatter goes to stderr). The random suffix keeps the link unlisted: shareable, not discoverable.

**Config** resolves first-wins: a real environment variable, else the nearest project `.env.local`/`.env`, else the manifest defaults (`PROVE_S3_BUCKET=proofs`, endpoint `http://127.0.0.1:9440`, region `us-east-1`, prefix `proofs`). **It never guesses a bucket** — if none resolves, the page is already composed in `builds/`, so report that file, tell the user to prescribe the bucket, and **stop at publish**. Do not silently skip and do not fall back to another host. A loopback URL opens only on the author's machine: say so when handing it over, and attach the `builds/` file wherever someone else must read it.

**Auto-open for the author.** After capturing the URL, `open "<url>"` (macOS) or `xdg-open "<url>"` (Linux), best-effort (`|| true`; skip silently in headless/CI). An orchestrator step, NOT part of the helper, which stays pure so forwarder skills can call it without popping a browser.

**For a ticket / teammate:** hand over the **S3 URL**. When the target needs a copy that survives the bucket being cleaned, ALSO attach the `builds/` file to Linear — `prepare_attachment_upload(issue, filename, "text/html", size)` → PUT the raw bytes to the signed `uploadRequest.url` with its headers verbatim → `create_attachment_from_upload(issue, assetUrl, title, subtitle)`.

**Never publish** a page that impersonates a real org/person or presents fabricated records as genuine — keep it local in `builds/` and let the user decide.

**Report:** lead with the **S3 URL**, then the durable artifacts — the page (`<trailDir>/<slug>_EXPLORE.html`) and its dossier (`<trailDir>/<slug>_PROVE_EXPLORE.md`) (`§CMD_LINK_FILE` each). Close with a one-line coverage summary: `Mapped: <N> sub-questions answered · unanswered: … · known / measured-absent / not-established / not-looked-at: … · disagreements shown: … · sections carrying / declared bare: … · out of scope: …`

Then **stop**. Offer the natural chains (`/snapshot` to checkpoint, `/ticket` to capture a gap worth closing, `/prove-visionary` if the map exposed a decision) but never auto-run them.

## Worked Example (compressed)

*Question:* "What is the real state of the explainer set — what is published, what is stale, and what was never harvested?"

- **§1 decomposition:** four named sub-questions — what is live and under which keys · which published copies differ from local and how · what the retirement covered · what remains unharvested. **Boundary:** the page standard and the marketing beats are OUT; this is the explainer set only. **Epistemic inventory:** the live keys and their diffs are *known*; the demoted reference page returning 404 against 200 siblings in the same loop is *measured absent*; whether the long editions were ever published is *not established* (the bucket is not enumerable); the unharvested evergreen claims are *not looked at*.
- **§2 ground & compose:** each section grounded in real evidence — verbatim fetch output with statuses read, the actual byte-diff of a published copy against local, the real retirement banner. One disagreement surfaced and **shown rather than smoothed**: the publication census said six pairs, a critique measured seven, and the page carries both with the filename pattern that explains the gap.
- **Structural device:** **parts-and-connections** — each chapter, its published key, its staleness, its harvest state — with a **known/unknown overlay** so the unexamined regions are visible as regions rather than absent.
- **§3 gate:** C1 found a section on the page standard that answered no sub-question — cut, as out of boundary. C3 caught an unlabelled claim in the long middle about what the long editions contain. C5 caught *"never published"* rendered identically to *"could not be enumerated"* — split into two treatments — and its strip-the-disclosures pass caught three unknowns drafted inside a `<details>`, re-rendered as open panels. C4 caught a verbatim readout clipping mid-token in a half-width column; the block was widened, the capture untouched. C9 caught an 8px sideways scroll from one `nowrap` chip that the escaping-element pass had reported clean. C10 counted eleven sections and nine carrying: the retirement section had grown a donut chart of two numbers, **removed and declared bare** (`bare: the answer is "the banner says so", and the banner is already quoted`), and the harvest-state section's answer turned out to live only in prose — the real harvest table was pulled onto the page and the paragraph deleted.
- Published. The page rules on nothing and recommends nothing; the decision it exposes was handed to `/prove-visionary` separately.

## Anti-Patterns (name them, avoid them)

- **The padded tour** — the most likely failure, and the one a *careful* author drifts into. Every sentence is true, every asset is real, the page is long, and the reader finishes knowing the subject no better than the map alone would have told them. Length is earned by coverage, never by elaboration. C7 and C8 exist to catch this.
- **The complete-looking partial map** — a page headed with a broad name that is really about one narrow slice. The most damaging failure here, because the reader cannot detect it from inside the page, and an agent reading it will route off it. The boundary belongs with the map, not at the bottom.
- **Blended unknowns** — *"not established"* and *"measured absent"* sharing a treatment, so a region nobody examined reads as a region known to be empty, or a reading somebody paid for gets filed as a blank. Different findings; different renderings. **The disclosed unknown is the same anti-pattern in disguise**: an honest label inside a `<details>` nobody opens.
- **Smoothed contradiction** — two sources disagree and the page picks the tidier one, usually silently. A map that reads as coherent because its author resolved a conflict by preference has hidden its most interesting finding.
- **The verdict in disguise** — compressing the territory into a conclusion because a conclusion feels like an answer. That is `/prove`'s job and `/prove` does it better; a map that ends in a ruling has stopped being a map.
- **The proposal in disguise** — the map notices what should change and starts recommending. That is `/prove-visionary`'s job; hand the decision over rather than annexing it.
- **Decorative structure** — a diagram that organises nothing real, a layering that does not correspond to any boundary in the system, colour that encodes no fact. In a map the structure is a *claim about the territory*; it needs a referent like any other claim. **The filler visual is its gameable form** — a chart of two numbers, a diagram redrawing the headings, an icon row — reached for to discharge the carry obligation. Declaring the section bare with its reason is cheaper, and it is the route the gate rewards.
- **The uniform stack** — every section cast in the same mould: heading, paragraph, one captioned asset, repeat. Each one individually terse, the whole one wall. This is the texture the complaint is about, and economy of words does not touch it; the fix is letting each section's evidence choose its shape.
- **Telling instead of showing** — "the config confirms X" without quoting the real lines, or paraphrasing output you could capture verbatim. Trusting an upstream *verdict* is right; substituting prose for *evidence* is not.
- **Sections that grew rather than answered** — a section nobody asked for, added because the material was there. If it answers no named sub-question, either the decomposition was wrong (fix it deliberately) or the section goes.
- **Templated AI-artifact look** — the generic gradient-card page. `Skill(artifact-design)` exists to calibrate real design and `Skill(dataviz)` to govern anything that encodes numbers; follow them.

## Constraints

- **`¶INV_EXPLORE_SHAPE_LOOSENS_EVIDENCE_DOES_NOT`** — the page may be long, many-sectioned, and structured as a territory rather than a claim. Every assertion in it still carries a real rendered asset or an honest provenance label, exactly as `/prove` requires. **Breadth is bought with sections that answer named sub-questions, never with sentences that assert more.**
- **`¶INV_EXPLORE_OUTLINE_IS_THE_DECOMPOSITION`** — the question is decomposed into named sub-questions before composition, and the page's outline IS that decomposition. A section answering no named sub-question is cut; a sub-question with no section appears on the page as unanswered, with its reason. Checked in **both** directions.
- **`¶INV_EXPLORE_BOUNDARY_RIDES_WITH_THE_MAP`** — what the map does NOT cover is stated where the reader meets the map, not at the bottom. For a single-claim proof the scope note is hygiene; for a map it is load-bearing, because an incomplete map read as complete is the defect. A reader who stops after the map holds an accurate incomplete picture, never a confident wrong one.
- **`¶INV_EXPLORE_UNKNOWNS_ARE_FIRST_CLASS`** — every region is Known, Measured absent, Not established, or Not looked at, kept distinct by one convention stated in the legend. **A measured absence, an unsettled question and an unexamined region are different findings and never share a treatment.** A `measured absent` region carries its reading and the control behind it; `not established` carries what would settle it; `not looked at` carries that nobody has looked. Blank regions are rendered, never omitted — **and rendered outside every collapsed element, tested mechanically at the gate**, since a hidden unknown reads as empty ground exactly as an omitted one does.
- **`¶INV_EXPLORE_SHOW_THE_DISAGREEMENT`** — where sources conflict or the parts do not fit, the page shows both sides with their evidence and says they disagree. Resolving a contradiction by preference is prohibited; resolving it by evidence, with the reasoning shown, is a finding and is required to appear as one.
- **`¶INV_EXPLORE_GATE_IS_PER_SECTION`** — the honesty pass runs per section, not per page. A map has proportionally more opportunity to overreach than a proof, and the long middle is where an unlabelled claim hides. Sampling one claim for the whole page does not satisfy this.
- **`¶INV_EXPLORE_EVERY_SECTION_CARRIES`** — every section owes the reader something that carries its answer — a render, a diagram, a verbatim capture, a comparison, a table of the real rows — or declares in the dossier why it cannot. **The test is subtraction**: hide the prose and the asset still delivers the section's one-line answer. A declared-bare section passes the gate; a decoratively-illustrated one fails it, so the obligation can never be discharged with filler. The property it buys is **scannability** — the answer legible from the map, the headings and the assets alone — and a page where most sections declare bare fails the orientation test rather than this one. **It adds no licence to assert**: a carried answer is an answer that was already evidenced, now shown instead of described.
- **`¶INV_EXPLORE_LENGTH_IS_EARNED`** — every paragraph changes what the reader knows or does next. Restating a neighbouring section, re-explaining an introduced thing, or narrating the investigation instead of its result is cut. The page's natural failure is padding, and this is the rule against it.
- **Explains, never rules or recommends.** It maps the territory. A verdict belongs to `/prove`; a recommendation and a decision belong to `/prove-visionary`. It never fixes (`/fix`), commits (`/snapshot`), ships (`/pr`), or files (`/ticket`). Chains are offered, never auto-run.
- **Not for a settled claim and not for an open decision.** A resolved finding with renderable evidence goes to `/prove`; an unsettled question needing a call goes to `/prove-visionary`. Route by the shape of the answer, not the size of the subject.
- **Ground is trusted, never re-litigated.** The upstream verdicts the page stands on are the input. A region nobody measured is `not looked at`, named as such — never filled in by inference.
- **`¶INV_PROVE_REAL_ASSETS_ONLY` applies unchanged** — every asset is rendered from the ACTUAL source. No mockups, no lorem, no illustrative fakes, no prose standing in for a result that could be shown. A failed render is recorded and degraded around, never fabricated.
- **Subagent for the heavy lift; the coverage gate + publish stay with the orchestrator.** The subagent grounds and composes (base64 never returns to the orchestrator); the orchestrator owns the coverage gate and the S3 publish — the human-facing gate. The cartographer's self-check is an input to it, never a substitute for it.
- **`¶INV_PROVE_COMPOSE_ONCE`** — the page is composed exactly once, by the subagent, into `builds/<slug>_EXPLORE.html`; §4 uploads that same file and never re-renders it. One build → two uses (the public S3 URL + the on-disk file).
- **Page rules are hard.** Self-contained, CSP-safe, theme-aware (light AND dark), responsive with no sideways body scroll at 400px, honest title and emoji favicon, no client-side renderer to fetch (a static object — inline `<svg>` or an embedded PNG, never a mermaid/Chart.js/KaTeX/D3 block, which degrade to literal source text). Progressive disclosure uses native `<details>`, and never hides the boundary or the unknowns — C5 tests that by stripping the disclosures, not by eye. A verbatim capture is legible in full where it sits rather than clipped or scroll-to-finish. Never impersonate a real org/person; never present fabricated records as genuine — such content stays a local file, published only at the user's choice.
- **Durable in `builds/`, attachable.** The page (`<slug>_EXPLORE.html`) and its dossier (`<slug>_PROVE_EXPLORE.md`) live in the session's `builds/`, beside the `/build` / `/probe` / `/council` trail. Because the HTML is self-contained, it attaches directly to a Linear ticket. Raw captured assets stay in scratchpad as throwaway intermediates. Both persist on a partial run, because the dossier skeleton is written **before** the grounding starts — a killed lane leaves a record the next one resumes from.
- **Lightweight + sessionless.** Runs within the active session: scope and decompose → dispatch (ground/structure/compose) → coverage gate → publish → stop.
