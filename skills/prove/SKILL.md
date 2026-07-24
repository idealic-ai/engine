---
name: prove
description: "Compile the detective evidence for a resolved body of work into a self-contained, shareable visual PROOF — the real artifacts (code blocks, PDF pages, screenshots, logs, CLI output, overlays, diagrams), a structure that makes the claim legible at a glance, and a short honest written summary. The visual capstone offered at the synthesis of /probe, /analyze, /fix, /experiment, /implement WHEN there is renderable evidence to show: it TRUSTS the upstream finding and re-presents it as an Artifact — it never re-investigates or re-litigates. Spine: it verifies only from the angle that serves the presentation — every rendered asset is REAL (from the actual source, never mocked) and FAITHFULLY shows what its caption claims, and provenance is honest (trusted-from-upstream vs. checked-here). Nothing fabricated, nothing oversold. A subagent assembles + renders the real assets + composes the draft; the orchestrator owns the presentation-integrity pass and the publish. A building block: it proves and reports, never fixes, commits, files, or re-investigates. Triggers: \"prove this\", \"make a proof artifact\", \"build the evidence page\", \"visualize this finding\", \"before/after proof\", \"dossier this\", \"exhibit this defect\", \"show me the proof of X\"."
version: 1.0
tier: lightweight
args: "[<the claim/thesis to prove>] [-- <the reader / what the page must make legible>]"
---

Turn a piece of finished problem-solving into a self-contained, shareable **proof**. `/prove` takes a **claim** you have already settled — a diagnosis, a fix, a before/after, a comparison — and hands it to a background subagent that re-establishes the ground truth, renders the *real* evidence (a PDF page, a screenshot, CLI output, an overlay, a diagram), and composes it into a legible Artifact. You then run the honesty pass and publish.

This is the **visual capstone** of the workflow family. Where `/probe` and `/analyze` *find* the answer, `/fix` *repairs*, and `/experiment` *tests*, `/prove` **shows** — it takes an already-resolved finding and compiles its evidence into an at-a-glance, defensible proof artifact. As a **building block** it produces a page, not a change: it never edits code, never commits, never files a ticket, and — the point of this skill — **never re-investigates or re-litigates the finding**. It trusts the upstream work, presents it honestly, publishes, and stops.

*The spine — non-negotiable (`¶INV_PROVE_FAITHFUL_PRESENTATION`):* `/prove` **trusts the finding and proves the *rendering*.** It does NOT re-run the analysis to re-confirm a claim's correctness — that was `/probe`/`/analyze`/`/experiment`'s job, and their verdict is taken as given (`¶INV_PROVE_TRUST_UPSTREAM`). The only verification `/prove` owns is the kind that serves the presentation: every asset on the page is **real** (rendered from the actual source, never mocked — `¶INV_PROVE_REAL_ASSETS_ONLY`), each asset **faithfully shows what its caption claims** (the render depicts the thing, and the claim doesn't outrun what the render shows), and **provenance is honest** — a claim is labeled *trusted-from-`<upstream>`* vs. *checked-here*. Nothing fabricated, nothing oversold. A beautiful page that manufactures false confidence is worse than none — but the confidence that matters here is *"this evidence is real and shown straight,"* not *"I re-proved the finding."*

*Crucial constraint:* `/prove` does NOT own a session. It reads the *active* session's context and established findings, and writes its paper trail into that session — the **dossier and the composed proof HTML into `builds/`** (durable, attachable to a Linear ticket), the **raw captured assets into scratchpad** (throwaway intermediates, since they're embedded into the HTML as `data:` URIs).

# /prove Protocol

## 1. Scope the Claim

Pin the exact thing the page must prove, before anything is rendered.

**A. The Thesis** (the one claim)
Resolve it from the arguments, else from the active session's resolved work / a sibling's report. State it as **one claim with a truth value** — not a topic, not a summary. The whole artifact exists to make *this one thing* legible.
*(Illustrative — adapt, don't copy: "Three separate PDF pages (73, 86, 93) collapsed into one estimate entity because they shared a key." / "The fix cut recap duplication from 18 rows to 0 without moving any real line item." / "Estimate A and B agree on scope but diverge $4,210, all in one room.")*
*Constraint:* If you cannot state the thesis as a single provable claim in one sentence, ask ONE `AskUserQuestion` to pin it. A vague thesis produces a page that proves nothing.

**B. The Reader & the Job** (who it's for)
Name the reader — **reviewer** / **future self** / **stakeholder** — and the single job of the page: what must this reader be able to see and trust in ten seconds? The reader drives the structure, the density, and the tone.

**C. The Source Work** (the trusted finding)
Name the resolved body of work the page draws on and where its verdict lives: a `/probe` `_PROBE.md`, `/analyze` findings, a `/fix` before/after + verification, an `/experiment` VERDICT, or the active session's settled log/plan/builds. `/prove` **trusts** these — their conclusion is the input, not something to re-derive. It does not re-open the investigation, re-run the analysis, or second-guess the verdict. (It compiles and presents the evidence; it does not re-discover or re-litigate it.) If the finding itself is in doubt, that's a signal to go back to `/probe`/`/analyze`/`/experiment` — not a job for `/prove`.

**D. The Trail** (durable in `builds/`, throwaway in scratchpad)
Set:
- `<trailDir> = <sessionDir>/builds/` — the durable home.
- `<proofPath> = <trailDir>/<slug>_PROOF.html` — the composed proof, a **durable** self-contained session artifact (directly attachable to a Linear ticket).
- `<dossierPath> = <trailDir>/<slug>_PROVE.md` — the record behind it.
- `<assetDir> = <scratchpad>/prove-<slug>/` (from your system prompt's scratchpad dir) — the **raw captured assets** (PNGs, screenshots): throwaway intermediates, since they get embedded into the HTML as `data:` URIs.

Mint a short kebab-case `<slug>` from the thesis (e.g. `page-key-collision`, `recap-dup-before-after`). *Before minting:* run `ls <trailDir>` — if an existing `<slug>_*` cluster matches this work (same chunk / ticket / topic), REUSE that slug so the proof clusters with the `/build`, `/probe`, `/experiment` artifacts.

**Acknowledge:** echo your setup in exactly one line:
`Proving: <thesis> — reader: <who>; from: <source work>; trail: <trailDir>/<slug>_PROVE.md.`

**State the spine** back to yourself: the page will show *only* real evidence, rendered faithfully, for a finding you *trust* from upstream — provenance labeled honestly, nothing oversold.

## 2. Dispatch the Prover — Assemble → Render → Compose (subagent)

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working, and when the evidence splits into independent strands it can be fanned out and reconciled.

The subagent does the heavy, context-bloating work — assembling the evidence, rendering the real assets, and composing the draft HTML (so the base64 blobs **never return to your context**). It writes two artifacts: the **proof dossier** (the record of every claim → its evidence + provenance) and the **draft artifact HTML**. It does NOT publish, and it does NOT re-open the investigation.

**Use the wait — don't idle.** When you background it, get a step ahead: pre-read the source finding so you know the load-bearing claims, and line up which rendered asset you'll eyeball in §3.

Build the subagent's prompt entirely self-contained — it cannot see your memory:

> You are an **evidence engineer** compiling a PROOF from a TRUSTED finding. Your job: take a conclusion that has already been established, render the REAL evidence that shows it, and compose an honest visual artifact. You do NOT investigate, you do NOT re-verify the finding, and you do NOT fix anything — the verdict is your INPUT. Your job is to *show it straight*.
>
> **1. The Thesis** — the one claim the page presents:
> - **Thesis:** `<thesis>`
> - **Reader & job:** `<reader>` — the page must let them `<the 10-second job>`.
> - **Source work (the trusted finding):** `<pointers: _PROBE.md / findings / before-after / VERDICT / log+plan+builds>`. Read it to learn WHAT was concluded and TRUST that conclusion — you are presenting this finding, not checking whether it is correct. If it looks wrong, say so in your return, but do NOT re-run the analysis to settle it.
>
> **2. Assemble the Evidence (trust the finding; verify only the RENDERING).** For EACH claim the page will make, find the real evidence that DEPICTS it and confirm the depiction is faithful: the render actually shows the thing, and the caption does not outrun what the render shows. **Do NOT re-run the analysis to re-confirm the claim's correctness** — that is upstream's verdict, taken as given. Record each claim's **provenance**: `trusted-upstream` (the finding's own verdict — the default) or `checked-here` (something YOU confirmed purely for the presentation, e.g. "the rendered page shows rows 12–14", "the log line quoted matches the file"). A claim with no showable evidence is either cut or carried as attributed text ("per the /experiment VERDICT: …"). Write all of this to the dossier.
>
> **3. Capture Real Assets — from the ACTUAL source, never a mockup.** Render the evidence itself and embed as `data:` URIs:
> - **PDF pages** → `mutool draw -o page-%d.png -r 150 <file.pdf> <N>` (or `pdftoppm -png -r 150 -f <N> -l <N> <file.pdf> out`). Render the real page, not a retyped table.
> - **Rendered UI / a live page** → a headless screenshot (`playwright`/`puppeteer`/`chrome --headless --screenshot`) of the actual thing.
> - **CLI / test / query output** → capture it VERBATIM (the real terminal text, the actual row counts), not a paraphrase.
> - **Overlays / diagrams / charts** → generate from real data (bounding-box overlays on the real render; a diagram whose nodes are the real entities). No lorem, no illustrative fakes, no "representative" stand-ins.
> - If an asset genuinely cannot be captured, RECORD that in the dossier (`asset-failed` + why) and degrade — never fabricate a stand-in.
>
> **4. Choose a Structural Device that CARRIES the truth** (not decoration). Pick the one that makes the thesis self-evident:
> - **before / after** — for a fix or a change (two columns, the delta highlighted).
> - **claim → proof → verdict** — for a diagnosis (assertion, the rendered evidence, the ruling).
> - **color-coding where the color encodes a REAL fact** — e.g. each row colored by its *true* owner, each cell by its *actual* verdict. The legend states what the color MEANS. Never color for prettiness.
>
> **5. Compose the Artifact.** FIRST load `Skill(artifact-design)` to calibrate the design investment; follow it. Then WRITE a single self-contained HTML file to `<proofPath>` (in the session's `builds/` — this is the durable, attachable proof, composed ONCE here; the orchestrator publishes this very file, it is never re-generated):
> - Self-contained & CSP-safe: inline all CSS/JS, embed every asset as a `data:` URI. No external hosts.
> - Theme-aware (light AND dark), responsive (wide tables/images scroll inside their own container; the page body never scrolls sideways).
> - **Write from the reader's side:** a **thesis line** at the top; a **key-insight callout** (the one thing to take away); an explicit **scope block** — *what the evidence shows · what's out of scope · what rests on the upstream finding (trusted, not re-checked here)* (this is where honesty lives — it is NOT buried at the bottom, it sits where the reader meets it); and an **end-state** (what is now true / resolved).
> - Honest `<title>` and favicon (emoji). Do NOT impersonate a real org or person; do NOT fabricate records, receipts, or reviews. If the subject matter would function as the real thing, note that in your return so the orchestrator publishes as a file for the user to judge.
>
> **6. Output Contract.** WRITE the dossier to `<dossierPath>` using the Proof Dossier template (this skill's `assets/TEMPLATE_PROVE.md` — the orchestrator gives you its base dir; do NOT hardcode `~/.claude`): thesis, per-claim table (claim · provenance · evidence · asset), assets rendered (+ any that failed), the chosen structural device, and the scope block (what-the-evidence-shows / out-of-scope / trusted-from-upstream). WRITE the proof HTML to `<proofPath>` (in `builds/`) — the single, self-contained deliverable; do not write a second copy anywhere. Think in the notebook: append your assemble/render stream via `<LOGGING>` every ~5 tool calls (a heartbeat hook BLOCKS after 10 tool calls without a log). Then RETURN a tight manifest — thesis, the provenance table (counts: N trusted-upstream / N checked-here), assets rendered + any that failed, the structural device, and `<proofPath>`. Do NOT dump the HTML or the base64 into your return — the orchestrator reads the dossier and publishes the file **as-is** from `<proofPath>`.

**Substituting paths (hand fully-substituted ABSOLUTE paths, never placeholders):** `<dossierPath>` = `<trailDir>/<slug>_PROVE.md` and `<proofPath>` = `<trailDir>/<slug>_PROOF.html` (both durable, in `builds/`); raw captured assets under `<assetDir>/` (scratchpad — throwaway, embedded into the HTML as `data:` URIs).

**Substituting `<LOGGING>`:** the concrete command — append via `engine log <the active session's log path>` using the notebook schemas in this skill's `assets/TEMPLATE_PROVE_LOG.md` (Trusted-Upstream / Checked-Here / Asset-Rendered / Asset-Failed / Overreach-Cut / Attributed-Text).

**Before dispatching — `§CMD_LOG_SKILL_INVOCATION`:** log this dispatch to the session log (why + the thesis + how to re-tread) as the last step before the `Task`/`Agent` handoff.

Dispatch to the background by default (`run_in_background: true`). Foreground only if you need the artifact before your very next step.

## 3. Presentation-Integrity Pass (the gate)

This is where `/prove` earns its name — NOT by re-proving the finding (you trust it), but by making sure the page shows it *straight*. Read the **dossier** (not the big HTML — it keeps you lean).

**Eyeball the load-bearing render.** Don't re-run the analysis — but don't ship a caption on faith either. For the asset the thesis rests on, open the rendered image / quoted output **yourself** and confirm it actually depicts what its caption claims: the page you label p86 *is* p86; the rows you tinted *are* the rows the finding named; the log line you quote *is* in the log. A proof whose render doesn't match its caption is worse than no proof. Flag any caption you couldn't confirm against its asset.

**Hunt for overstatement.** Every claim on the page must be either (a) shown by a real asset, or (b) carried as attributed text pointing at the trusted upstream finding. Nothing on the page may claim MORE than the evidence shows or more than upstream established. Confirm provenance is honest — `trusted-upstream` is labeled as such; `checked-here` means someone actually looked. Cut anything that oversells — a hedge honestly stated beats a confident overreach.

**Enforce the scope block.** Confirm the page shows *what the evidence shows / what's out of scope / what rests on the trusted upstream finding*, where the reader meets it — not buried. If the pass finds a problem, direct a targeted edit to the draft (small fix inline, or re-dispatch a focused correction), then re-check.

**Degrade gracefully (`¶INV_PROVE_DEGRADE_GRACEFULLY`).** If no imagery could be rendered, confirm the draft is still a readable proof (code blocks, tables, CLI text, diagrams) and that it *says imagery was unavailable* — never let a missing render become a silent gap or a fake.

## 4. Publish & Report

**Single generation (`¶INV_PROVE_COMPOSE_ONCE`).** Publish the **already-composed** `<proofPath>` from `builds/` — pass its file path to the **Artifact** tool, which reads the file from disk. The page is **published, never re-generated**: the subagent composed it once in §2, and that same self-contained file is both the Artifact source and the on-disk deliverable. Do NOT re-render or re-emit the HTML for the publish step. Publish private by default (the user later chooses whether to share). `Skill(artifact-design)` was already loaded by the subagent. Give it an honest `<title>`, a one-sentence `description` that states what the page proves, and an honest favicon.

**Never publish** a page that impersonates a real org/person or presents fabricated records as genuine — if the subject is that kind (the subagent flagged it, or you judge it so), keep it as a file and let the user decide, rather than auto-publishing.

**Report:** the Artifact URL, plus the durable artifacts in `builds/` — the **proof HTML** (`<trailDir>/<slug>_PROOF.html`, a self-contained file you can **attach directly to a Linear ticket** — via the Linear MCP `create_attachment`, or surfaced by `/snapshot`//`/communicate` — with nothing else needed) and its dossier (`<trailDir>/<slug>_PROVE.md`) (`§CMD_LINK_FILE` each). Close with a one-line honesty summary: `Shown: N claims with real assets · trusted-from-upstream: N (labeled) · out-of-scope: …`

Then **stop**. `/prove` proves, publishes, and reports — it does not fix, commit, file, or investigate. Offer the natural chains (`/snapshot` to checkpoint, `/pr` to ship, `/ticket` to capture a follow-up) but never auto-run them.

## Worked Example (compressed)

*Thesis:* "Estimate pages 73, 86, and 93 are three distinct rooms, but the extractor collapsed them into ONE entity because all three share the same layout key."

- **The finding (trusted):** `/analyze` already concluded the three-into-one collapse and determined each row's **true owner** (page 73 / 86 / 93). That verdict is the INPUT — `/prove` does not re-run the extractor to re-confirm it.
- **§2 assemble & render:** the subagent rendered the evidence FOR that finding — `mutool draw -r 150` → real p73/p86/p93 PNGs from the actual PDF, rows tinted by the owner the analysis named. Provenance: the collapse + the owners = `trusted-upstream`; "each tinted row is the row the finding named" = `checked-here`.
- **Structural device:** **color-coding where color encodes the true owner** — every row tinted by the page it belongs to per the finding; the legend states the mapping. Per-page **"stays / moves / drops"** verdicts sit beside each render.
- **Reader-side framing:** thesis line up top; a **key-insight callout** — *"the collision is the shared key, not the content"*; a **scope block**: *shown* = the three real pages + the owner tint; *out of scope* = the fix itself; *rests on upstream* = the collapse diagnosis (established by `/analyze`, not re-derived here).
- **§3 integrity pass:** the orchestrator opened the p86 render itself and confirmed the tinted rows are the rows the finding named — caption matches asset. Published. It did NOT re-run the extractor; that verdict is `/analyze`'s.

## Anti-Patterns (name them, avoid them)

- **Rendering theatre** — a gorgeous page that proves nothing, or that asserts more than the evidence shows / more than upstream established. If it's not shown and not established, the page doesn't claim it.
- **Fake / mocked assets** — a retyped "screenshot", a lorem table, an illustrative stand-in for a render you couldn't capture. Real source only; a failed capture is recorded and degraded, never faked.
- **Decorative color** — color that encodes nothing. In a proof, color is a *claim* (owner, verdict, delta); it always has a legend and a real referent.
- **Buried honesty** — the scope / provenance block (what's shown vs. what rests on the trusted upstream finding) hidden at the bottom. It sits where the reader meets the claim.
- **Templated AI-artifact look** — the generic gradient-card page. `Skill(artifact-design)` exists to calibrate real design; follow it.
- **Telling instead of showing** — writing "the log confirms X" without rendering the actual log line, or paraphrasing a result you could quote. Trusting the upstream *verdict* is right; substituting prose for the *evidence* is not — show the real artifact.
- **Re-litigating the finding** — re-running the analysis to "make sure" before rendering. That's not `/prove`'s job; the verdict is the input. If you genuinely doubt it, hand back to `/probe`/`/analyze`/`/experiment` — don't quietly re-investigate inside a proof.

## Constraints

- **`¶INV_PROVE_TRUST_UPSTREAM`** — `/prove` trusts the finding it presents. It does NOT re-run the analysis or re-litigate the verdict — that was `/probe` / `/analyze` / `/experiment` / `/fix`'s job, and their conclusion is the input. A finding you genuinely doubt goes back upstream, never through `/prove`.
- **`¶INV_PROVE_REAL_ASSETS_ONLY`** — Every asset is rendered from the ACTUAL source (code block from the real file, PDF render, real screenshot, verbatim log/CLI output, data-driven overlay/diagram). No mockups, no lorem, no illustrative fakes, no prose standing in for a result you could show. A render that fails is recorded and degraded around, never fabricated.
- **`¶INV_PROVE_FAITHFUL_PRESENTATION`** — The only verification `/prove` owns serves the presentation: each asset faithfully shows what its caption claims, nothing on the page claims MORE than the evidence shows or more than upstream established, and provenance is honest (`trusted-upstream` vs. `checked-here`). The page carries an explicit, unburied scope block: what the evidence shows / out of scope / what rests on the trusted upstream finding. Overreach is cut.
- **`¶INV_PROVE_DEGRADE_GRACEFULLY`** — No imagery renderable → still produce a readable proof (code blocks / tables / CLI text / diagrams) and say imagery was unavailable. A partial or blocked run still leaves the dossier.
- **Presents, never investigates.** `/prove` takes an already-resolved finding and compiles + shows it. It never opens a fresh investigation and never re-runs one — that's `/probe` / `/analyze` / `/experiment`. It presents; it does not re-derive.
- **Offered only when there's something to show.** As a next-step it is offered (never forced, `¶INV_OFFER_DONT_FORCE_SKILLS`) at the synthesis of the investigative skills **only when the finding carries renderable evidence** — a rendered artifact, a before/after, code, a log, real output. An abstract conclusion with nothing to show is not a `/prove` candidate.
- **Building block — proves, then stops.** It publishes a proof and reports. It never fixes (`/fix`), commits (`/snapshot`), ships (`/pr`), or files (`/ticket`). Chains are offered, never auto-run.
- **Subagent for the heavy lift; the integrity gate + publish stay with the orchestrator.** The subagent assembles, renders, and composes the draft (base64 never returns to the orchestrator); the orchestrator owns the presentation-integrity pass and the Artifact publish (the human-facing gate).
- **Artifact rules are hard.** Self-contained, CSP-safe, theme-aware, responsive, honest title/favicon. Never impersonate a real org/person; never present fabricated records as genuine — such content stays a file, published only at the user's choice.
- **`¶INV_PROVE_COMPOSE_ONCE` — single generation.** The proof HTML is composed exactly once, by the subagent, into `builds/<slug>_PROOF.html`; §4 publishes *that same file* to Artifacts (the Artifact tool reads it from disk) and never re-renders it. One build → two uses (the Artifact URL + the on-disk file).
- **Durable in `builds/`, attachable.** The proof HTML (`<slug>_PROOF.html`) and its dossier (`<slug>_PROVE.md`) live in the session's `builds/` — durable session artifacts beside the `/build`//`/probe`//`/experiment` trail. Because the HTML is self-contained (assets embedded as `data:` URIs), it can be attached directly to a Linear ticket. Raw captured assets stay in scratchpad as throwaway intermediates. The dossier + HTML persist even on a partial run, so the evidence sits on disk, not just asserted.
- **Lightweight + sessionless.** Runs within the active session: scope → dispatch (assemble/render/compose) → integrity pass → publish → stop.
