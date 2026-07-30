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
> - **The page has NO JavaScript runtime — emit diagrams as inline `<svg>` or a pre-rendered PNG `data:` URI, NEVER as a diagram-language block.** A `/prove` page is published as a **plain static file on S3** (`¶INV_PROVE_S3_URL_IS_SHAREABLE`) and the artifact rules forbid loading anything from a CDN — so there is no renderer present and none can be fetched. **Mermaid is the trap**: `<pre class="mermaid">` renders natively inside the claude.ai *Artifact* host, so it is the natural reach and it silently degrades to literal source text here. The same applies to Chart.js, KaTeX, D3, and any other client-side renderer. Either hand-write the SVG (`currentColor` for strokes and text so it inherits both themes; `viewBox` + `width="100%"` to scale; wrapped in an `overflow-x:auto` container so it scrolls inside itself rather than pushing the body sideways), or render the diagram to PNG in the subagent and embed the bytes.
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
> - **Answer the reader's questions, not the author's (REQUIRED).** Directly under the thesis, before the evidence, put a **Questions & Answers** block: the **3-5 questions the READER named above will actually arrive with**, each answered in **ONE line — a direct yes / no / partly plus the number that settles it**. Derive them from that reader's stated job, not from what you found interesting. *The failure this prevents:* a page that brilliantly answers "what did we learn about X?" while the reader came to ask "does it work, can I ship it, what breaks?" — true, well-argued, and useless. Answers must not outrun the ledger; "we don't know" is a valid answer when paired with what would settle it.
> - **Say what to do about it (REQUIRED).** Close with **Next Steps** — concrete, each traced to a finding, each marked `follows` (the evidence points at it) or `idea` (a reasonable option the evidence permits but does not establish). Include what you deliberately do NOT suggest, with the reason. Never a generic backlog; never an idea laundered into a recommendation. `/prove` suggests — it does not act.
> - Honest `<title>` and favicon (emoji). Do NOT impersonate a real org or person; do NOT fabricate records, receipts, or reviews. If the subject matter would function as the real thing, note that in your return so the orchestrator publishes as a file for the user to judge.
>
> **6. Output Contract.** WRITE the dossier to `<dossierPath>` using the Proof Dossier template (this skill's `assets/TEMPLATE_PROVE.md` — the orchestrator gives you its base dir; do NOT hardcode `~/.claude`): thesis, per-claim table (claim · provenance · evidence · asset), assets rendered (+ any that failed), the chosen structural device, the scope block (what-the-evidence-shows / out-of-scope / trusted-from-upstream), the **Questions & Answers** block (each answer traced to a ledger claim), and **Next Steps** (each marked `follows` / `idea`). WRITE the proof HTML to `<proofPath>` (in `builds/`) — the single, self-contained deliverable; do not write a second copy anywhere. Think in the notebook: append your assemble/render stream via `<LOGGING>` every ~5 tool calls (a heartbeat hook BLOCKS after 10 tool calls without a log). Then RETURN a tight manifest — thesis, the provenance table (counts: N trusted-upstream / N checked-here), assets rendered + any that failed, the structural device, and `<proofPath>`. Do NOT dump the HTML or the base64 into your return — the orchestrator reads the dossier and publishes the file **as-is** from `<proofPath>`.

**Substituting paths (hand fully-substituted ABSOLUTE paths, never placeholders):** `<dossierPath>` = `<trailDir>/<slug>_PROVE.md` and `<proofPath>` = `<trailDir>/<slug>_PROOF.html` (both durable, in `builds/`); raw captured assets under `<assetDir>/` (scratchpad — throwaway, embedded into the HTML as `data:` URIs).

**Substituting `<LOGGING>`:** the concrete command — append via `engine log <the active session's log path>` using the notebook schemas in this skill's `assets/TEMPLATE_PROVE_LOG.md` (Trusted-Upstream / Checked-Here / Asset-Rendered / Asset-Failed / Overreach-Cut / Attributed-Text).

**Before dispatching — `§CMD_LOG_SKILL_INVOCATION`:** log this dispatch to the session log (why + the thesis + how to re-tread) as the last step before the `Task`/`Agent` handoff.

Dispatch to the background by default (`run_in_background: true`). Foreground only if you need the artifact before your very next step.

## 3. Presentation-Integrity Pass (the gate)

This is where `/prove` earns its name — NOT by re-proving the finding (you trust it), but by making sure the page shows it *straight*. Read the **dossier** (not the big HTML — it keeps you lean).

**Eyeball the load-bearing render.** Don't re-run the analysis — but don't ship a caption on faith either. For the asset the thesis rests on, open the rendered image / quoted output **yourself** and confirm it actually depicts what its caption claims: the page you label p86 *is* p86; the rows you tinted *are* the rows the finding named; the log line you quote *is* in the log. A proof whose render doesn't match its caption is worse than no proof. Flag any caption you couldn't confirm against its asset.

**Hunt for overstatement.** Every claim on the page must be either (a) shown by a real asset, or (b) carried as attributed text pointing at the trusted upstream finding. Nothing on the page may claim MORE than the evidence shows or more than upstream established. Confirm provenance is honest — `trusted-upstream` is labeled as such; `checked-here` means someone actually looked. Cut anything that oversells — a hedge honestly stated beats a confident overreach.

**Enforce the scope block.** Confirm the page shows *what the evidence shows / what's out of scope / what rests on the trusted upstream finding*, where the reader meets it — not buried. If the pass finds a problem, direct a targeted edit to the draft (small fix inline, or re-dispatch a focused correction), then re-check.

**Audit the answers (the ten-second job).** Read the **Questions & Answers** block as the named reader would. Two checks, both of which have failed real pages:
1.  **Are these the reader's questions?** If they are the author's — "what did we learn about the method?" where the reader asked "can I turn it on?" — the page fails its job no matter how well it argues. Rewrite the questions, not the evidence.
2.  **Does each answer outrun its evidence?** Trace every answer to a ledger claim. A confident "yes" resting on a partly-circular metric, or on a sample too small to carry it, must be softened to what the evidence actually supports. A hedge honestly stated beats a clean answer that isn't earned.

**Check Next Steps are grounded.** Each step traces to a finding and is honestly marked `follows` vs `idea`. Cut anything invented, generic, or dressed up as a recommendation when the evidence only permits it as an option.

**Degrade gracefully (`¶INV_PROVE_DEGRADE_GRACEFULLY`).** If no imagery could be rendered, confirm the draft is still a readable proof (code blocks, tables, CLI text, diagrams) and that it *says imagery was unavailable* — never let a missing render become a silent gap or a fake.

## 4. Publish & Report

**The shareable deliverable is a public S3 URL (`¶INV_PROVE_S3_URL_IS_SHAREABLE`).** The composed `<proofPath>` (`builds/<slug>_PROOF.html`) is self-contained, so it uploads to S3 as a single object served at a public HTTPS URL that **anyone with the link can open** — no auth wall, no private preview. The on-disk `builds/` file stays the durable local copy (and the Linear-attachment source); the **S3 URL** is what you hand to a teammate, a ticket, or a downstream skill.

**Config — prescribed once in the project `.env`, poke only if truly unset.** The bucket comes from `PROVE_S3_BUCKET` (+ `PROVE_S3_REGION`, default `us-east-2`; `PROVE_S3_PREFIX`, default `proofs`; optional `PROVE_S3_PROFILE`, `PROVE_S3_USER`). The helper resolves each **first wins**: a real environment variable, else the nearest **project `.env`** (walked up from `$PWD` — each project prescribes its own bucket beside its AWS creds, so the global skill stays uncoupled). **Only if none is found does it poke** — the proof is already composed in `builds/`, so report that file and tell the user to prescribe the bucket, then stop at publish:
> Add to the project `.env` (finch → repo-root `.env`): `PROVE_S3_BUCKET=staging-finch-proofs` · `PROVE_S3_REGION=us-east-2` · `PROVE_S3_PROFILE=finch-staging`.

**Single generation (`¶INV_PROVE_COMPOSE_ONCE`).** Upload the **already-composed** `<proofPath>` from `builds/` — the subagent composed it once in §2; you upload that same self-contained file, never re-render it. The upload is one command:
> `~/.claude/skills/prove/assets/publish-s3.sh <proofPath> <slug>`

It derives the per-user key segment from the AWS caller identity (`…:user/yarik` → `yarik`; override with `$PROVE_S3_USER`), mints an **unguessable** key (`<prefix>/<user>/<slug>-<rand>.html`), uploads with `--content-type text/html`, and prints the **public URL to stdout** (capture it — `aws s3 cp` chatter goes to stderr). The random suffix keeps the link unlisted: shareable, not discoverable.

**Auto-open for the author.** After capturing the URL, open it in the user's browser as a convenience — `open "<url>"` (macOS) or `xdg-open "<url>"` (Linux), best-effort (`|| true`; skip silently in headless/CI). This is an orchestrator step, NOT part of `publish-s3.sh` — the helper stays pure (URL-to-stdout only) so the forwarder skills (`/snapshot`, `/pr`, …) can call it programmatically without popping a browser.

**For a ticket / teammate** (chained from `/snapshot`, `/communicate`, `/inbox-post`, `/pr`, or the user says "attach / share / put it on the ticket"): hand over the **S3 URL** as the proof link. When the target wants a copy that travels with the ticket even if the bucket is later cleaned, ALSO attach the `builds/` file to Linear — `prepare_attachment_upload(issue, filename, "text/html", size)` → PUT the raw bytes to the signed `uploadRequest.url` with its headers verbatim (`curl --data-binary @<proofPath>`, 60s window) → `create_attachment_from_upload(issue, assetUrl, title, subtitle)`. Reference the S3 URL (or that attachment) in any comment.

**Never publish** a page that impersonates a real org/person or presents fabricated records as genuine — if the subject is that kind (the subagent flagged it, or you judge it so), keep it as a local file in `builds/` and let the user decide, rather than uploading it to a public URL.

**Report:** lead with the **S3 URL** (the shareable proof) and the durable `builds/` artifacts — the **proof HTML** (`<trailDir>/<slug>_PROOF.html`, self-contained; also attachable directly to a Linear ticket via the MCP upload flow above) and its dossier (`<trailDir>/<slug>_PROVE.md`) (`§CMD_LINK_FILE` each). Close with a one-line honesty summary: `Shown: N claims with real assets · trusted-from-upstream: N (labeled) · out-of-scope: …`

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
- **A diagram that needs a runtime** — a `<pre class="mermaid">` block (or Chart.js / KaTeX / D3) on a page published as a static S3 file with no JS and no CDN allowed. It renders as literal source text and the author usually never sees it, because mermaid *does* render in the claude.ai Artifact host. Inline `<svg>` or an embedded PNG, always.
- **Buried honesty** — the scope / provenance block (what's shown vs. what rests on the trusted upstream finding) hidden at the bottom. It sits where the reader meets the claim.
- **Answering the author's question instead of the reader's** — the page argues the thing the author found interesting ("the metric was blind, and here is why") while the reader arrived asking "does it work, can I turn it on, what breaks?". The argument can be true, elegant and well-evidenced and still fail its only job. The Questions & Answers block exists for exactly this; derive it from the §1.B reader, never from what the investigation enjoyed.
- **A proof with no exit** — the page establishes what is true and leaves the reader to re-derive what to do about it. Next Steps closes that, traced to findings and honestly marked `follows` vs `idea` — never a generic backlog, never an idea promoted to a recommendation.
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
- **Subagent for the heavy lift; the integrity gate + publish stay with the orchestrator.** The subagent assembles, renders, and composes the draft (base64 never returns to the orchestrator); the orchestrator owns the presentation-integrity pass and the S3 publish (the human-facing gate).
- **Artifact rules are hard.** Self-contained, CSP-safe, theme-aware, responsive, honest title/favicon. Never impersonate a real org/person; never present fabricated records as genuine — such content stays a file, published only at the user's choice.
- **`¶INV_PROVE_COMPOSE_ONCE` — single generation.** The proof HTML is composed exactly once, by the subagent, into `builds/<slug>_PROOF.html`; §4 uploads *that same file* to S3 and never re-renders it. One build → two uses (the public S3 URL + the on-disk file).
- **`¶INV_PROVE_S3_URL_IS_SHAREABLE` — the shareable deliverable is the public S3 URL.** `/prove` uploads the self-contained `builds/<slug>_PROOF.html` to `$PROVE_S3_BUCKET` under an unguessable `<prefix>/<user>/<slug>-<rand>.html` key (via `assets/publish-s3.sh`) and serves it at a public HTTPS URL anyone with the link can open. That URL — there is **no** claude.ai Artifact preview any more — is what leaves the author's machine: a ticket comment, an attachment reference, a handoff to a teammate or a downstream skill (`/inbox-post`, `/snapshot`, `/communicate`, `/pr`) all carry the S3 URL (and, when the target needs a ticket-durable copy, the `builds/` file attached via the Linear MCP `prepare_attachment_upload` → PUT bytes → `create_attachment_from_upload` flow). The bucket is prescribed once per project (`PROVE_S3_BUCKET` + friends, resolved env-var → project `.env` → poke); if none is found the skill reports the `builds/` file and pokes the user to prescribe it — it does **not** silently skip, and it never guesses a bucket. Applies to every skill that forwards a proof/report, not just `/prove`.
- **Durable in `builds/`, attachable.** The proof HTML (`<slug>_PROOF.html`) and its dossier (`<slug>_PROVE.md`) live in the session's `builds/` — durable session artifacts beside the `/build`//`/probe`//`/experiment` trail. Because the HTML is self-contained (assets embedded as `data:` URIs), it can be attached directly to a Linear ticket. Raw captured assets stay in scratchpad as throwaway intermediates. The dossier + HTML persist even on a partial run, so the evidence sits on disk, not just asserted.
- **Lightweight + sessionless.** Runs within the active session: scope → dispatch (assemble/render/compose) → integrity pass → publish → stop.
