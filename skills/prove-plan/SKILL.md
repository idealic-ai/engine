---
name: prove-plan
description: "Compile a DECIDED route into a self-contained, shareable PLAN page — the ordered steps with their dependencies drawn as a flowgraph, the acceptance for each step and how each will be checked, the risks, the owners, and what is out of scope. The route sibling of /prove: where /prove SHOWS a settled finding and /prove-visionary PROPOSES among options that are still open, /prove-plan LAYS OUT a route that has already been chosen and not yet travelled, so a reader can follow it, check it and own a piece of it. Its sources are a /build or /implement plan, a loom's thread map, or a ticket. Spine: it trusts the decisions and presents them straight, and its honesty gate is that every step names its check and nothing is presented as done — a plan page shows what will happen and how anyone will know it happened, never progress. The thin sibling on /prove's shared assets: the assembler brief, the provenance rules, the dossier and notebook templates and the S3 publish are /prove's, cited and never copied. A subagent extracts + composes; the orchestrator owns the route gate and the publish. A building block: it lays out and reports, never executes the plan, commits, files, or decides. Triggers: \"prove the plan\", \"make the plan shareable\", \"plan page\", \"show the route\", \"draw the dependency graph for this plan\", \"lay out the steps with their checks\", \"who owns which step\"."
version: 1.0
tier: lightweight
args: "[<the plan source — a plan file, a loom thread map, or a ticket key>] [-- <the reader / what they must be able to do with the route>]"
---

Turn a route that has **been decided and not yet travelled** into a self-contained, shareable **plan page**. `/prove-plan` takes a plan — a `/build` or `/implement` plan file, a loom's thread map, or a ticket — and hands it to a background subagent that extracts the steps, their order and their dependencies, draws the dependency flowgraph from those edges, and composes a page a reader can follow step by step. You then run the route gate and publish it to a public S3 URL.

This is the **route sibling of `/prove`**, and the thinnest of the family: everything that is not specific to a plan page is `/prove`'s, cited below and never restated. As a **building block** it produces a page, not progress: it never runs a step, never commits, never files a ticket, and never re-opens a decision the plan has made.

**When to use this instead of its siblings — route by what the reader must DO with the page:**

- A finding is settled and must be *shown* → **`/prove`**.
- The route is **not yet chosen** and someone must *decide* among options → **`/prove-visionary`**. A plan page for an undecided route presents a guess as a commitment.
- A large, knowable whole must be *understood* → **`/prove-explore`**; one mechanism must be *taught* → **`/prove-explanation`**.
- The route **is chosen and still ahead**, and people must *follow, check and own* it → **`/prove-plan`**.
- A route **already travelled** — what was done, in what order, and how it turned out — is a finding, so it is `/prove`'s, or `/prove-explore`'s when it has many parts. Calling it "a route" does not make it a plan.

*The spine — non-negotiable:* **`/prove-plan` presents what will happen and how anyone will know it happened — never that it has happened.** Every step names its check: the command, test or observation that will show the step is complete, who or what runs it, and what result counts as passing. Nothing on the page is presented as done. The plan's decisions are trusted from the source exactly as `/prove` trusts a finding (`¶INV_PROVE_TRUST_UPSTREAM`); what this skill adds is the discipline that a route without checks is a wish list, and a route that shows ticks is a status report wearing a plan's clothes.

*Crucial constraint:* `/prove-plan` does NOT own a session. Like `/prove`, it reads the *active* session and writes its paper trail there — the dossier and the composed HTML into `builds/`, raw captures into scratchpad.

## What this skill takes from /prove (cited, not copied)

The canonical base is `/prove` at `~/.claude/engine/skills/prove/SKILL.md`, not `/prove-next`: `/prove` owns the publishing plumbing under `prove/assets/`, and `/prove-next` is the kit-composed variant that itself reaches back into those assets. Read each cited section at run time; do not carry a copy of it.

| Mechanism | Where it lives | What changes here |
| --- | --- | --- |
| Trail layout, slug reuse | `prove/SKILL.md` § "1. Scope the Claim" (part D) | the two file names in §1 D below |
| The prover brief: its opening paragraph, items 2, 3, 5 and 6, and the two *Substituting* paragraphs | `prove/SKILL.md` § "2. Dispatch the Prover — Assemble → Render → Compose (subagent)" | items 1 and 4 are replaced, and item 5's reader-side bullet is overridden (§2) |
| Dossier | `~/.claude/engine/skills/prove/assets/TEMPLATE_PROVE.md` | filled per the section map in §2, plus the addendum |
| Notebook schemas for the subagent's log | `~/.claude/engine/skills/prove/assets/TEMPLATE_PROVE_LOG.md` | none |
| The integrity checks every page owes | `prove/SKILL.md` § "3. Presentation-Integrity Pass (the gate)" | the route gate below runs on top of them |
| Publish, config, port check, seat strip, attachment flow, report | `prove/SKILL.md` § "4. Publish & Report", via `~/.claude/engine/skills/prove/assets/publish-s3.sh` | the summary line below |
| Page mechanics measured in a driven browser | `prove-explore/SKILL.md` § "3. The Coverage Gate", check C9 | applied to the `builds/` file (P8) |
| Invariants | `¶INV_PROVE_TRUST_UPSTREAM`, `¶INV_PROVE_REAL_ASSETS_ONLY`, `¶INV_PROVE_FAITHFUL_PRESENTATION`, `¶INV_PROVE_DEGRADE_GRACEFULLY`, `¶INV_PROVE_COMPOSE_ONCE`, `¶INV_PROVE_S3_URL_IS_SHAREABLE` in `prove/SKILL.md` § "Constraints" | provenance gains a third class, `derived-here` (§2) |

The skill's own assets are `~/.claude/engine/skills/prove-plan/assets/plan-page-scan.py`, the mechanical half of the route gate, and `~/.claude/engine/skills/prove-plan/assets/_page_regions.py`, the HTML walking it shares with `/prove-explanation`'s scanner. They scan for marks `/prove` has no reason to know about. The prose on the page follows `~/.claude/engine/.directives/VOICE.md`, loaded as `/prove` § "1. Scope the Claim" says.

# /prove-plan Protocol

## 1. Scope the Route

**A. The source.** Resolve it from the arguments, else from the active session: a `/build` or `/implement` plan file (its steps and checkboxes), a loom's thread map (its threads, their order and what each waits on), or a ticket (its acceptance criteria and any sub-issues). Name it by path or key; it is the trusted input. Record the version you read: the commit sha, or the file's `sha256` when it is uncommitted, or the ticket's `updatedAt`. A live source (a loom ledger) changes while you work, so the page carries that stamp.

**B. The route in one sentence.** State where the route starts, where it ends, and what is true at the end. If the source holds options that are still open, this is not a plan yet: say so and point at `/prove-visionary`, rather than choosing on the plan's behalf. If you cannot state the route in one sentence, ask ONE `AskUserQuestion` to pin it.

**C. The reader and the job.** Name the reader (an owner of a step / a reviewer / a stakeholder) and what they must be able to do in a minute: find their step, see what it waits on, and know how its completion will be checked. Write the two **job questions** this reader would ask of the page (for example, "what does step S3 wait on?" and "how will we know S5 is finished?"); P9 asks them.

**D. The trail — the one place these paths are stated.** As `/prove` § "1. Scope the Claim" part D, with:

- `<pagePath> = <trailDir>/<slug>_PLAN.html`
- `<dossierPath> = <trailDir>/<slug>_PROVE_PLAN.md`

Everywhere else this file says `<pagePath>` and `<dossierPath>`. Wherever `/prove`'s text says `<proofPath>`, read `<pagePath>`.

**Acknowledge** in one line: `Planning: <route sentence> — reader: <who>; from: <source @ version>; trail: <dossierPath>.`

## 2. Dispatch the Planner — Extract → Order → Draw → Compose (subagent)

Dispatch exactly as `/prove` § "2. Dispatch the Prover — Assemble → Render → Compose (subagent)" says — backgrounded by default, a fully self-contained brief with absolute paths, `§CMD_LOG_SKILL_INVOCATION` before the handoff, base64 never returning to your context.

Brief items included from /prove: opening, 2, 3, 5, 6, Substituting.
Brief items replaced here: 1, 4.

Build the brief in this order, reading each included part from `/prove`'s file:

1. `/prove`'s **opening paragraph** (the one beginning "You are an **evidence engineer**"), with "PROOF" read as "PLAN page" and "finding" as "the decided plan".
2. Item **1** below, in place of `/prove`'s item 1.
3. `/prove`'s items **2** and **3** as written.
4. Item **4** below, in place of `/prove`'s item 4.
5. `/prove`'s item **5**, except its bullet **"Write from the reader's side"** (thesis line, key-insight callout, scope block, end-state), which item 4 below overrides entirely. A plan page has **no end-state**: "what is now true" is exactly what P2 forbids. Item 5's other bullets — loading `Skill(artifact-design)`, self-contained and CSP-safe, no third-party renderer, every code block tagged with its language (`language-text` when none fits; `publish-s3.sh` refuses an untagged block), theme-aware and responsive, an honest title — stand.
6. `/prove`'s item **6** (the output contract: the dossier from the template, the `<LOGGING>` heartbeat, the tight return manifest). The template's base dir is `~/.claude/engine/skills/prove/assets/`, not this skill's. The return manifest's provenance counts gain a third, `N derived-here`, beside `/prove`'s trusted-upstream and checked-here.
7. `/prove`'s two **Substituting** paragraphs, with the paths from §1 D: `<dossierPath>` and `<pagePath>` (in place of `<proofPath>`), and `<LOGGING>` resolved to the concrete `engine log` command.

> **1. The route** — `<route sentence>`, for `<reader>`, who must be able to `<job>`. Source: `<plan path / thread map path / ticket key>` at `<version>`. The decisions in the source are your INPUT. Do not re-plan, re-order for preference, or add a step the source does not state. A step you believe is missing goes under *Open questions*, not into the graph. If the source is contradictory, say so in your return.
>
> **4. Extract the Step Ledger, then draw from it.**
> For every step, record in the dossier: `id` · `title` · `depends on` (step or external ids) · `owner` (a name from the source, or `unowned` — never invented) · `acceptance` (the observable end state, not an activity) · `check` (the command, test or observation that will show the step is complete, who or what runs it, and the result that counts as passing) · `provenance` per field.
> **Provenance has three classes here.** `trusted-upstream` means the source says it, and you quote where. `checked-here` means you confirmed it for the presentation. `derived-here` means you proposed it — a check the source lacked, an owner or an edge you inferred — and the page renders it as "proposed by the planner". A step with no check gets a `derived-here` check, never a blank and never "verify it works".
> **Source shapes.** *A ticket's* acceptance criteria are acceptance, not steps. Every step you cut from a ticket is `derived-here`, and its acceptance cell quotes the criterion it serves. *A step the source records as complete* is not a route step: list it once under *Starting point*, with its provenance, and leave it out of the graph. *A step in flight* — dispatched, not finished — is a route step like any other, with no progress mark on it; the dossier notes it as in flight, and the as-of stamp says when. *A dependency owned outside this route* (another lane's commit, another team's release) is an **external precondition**: one node of its own kind, drawn dashed, naming its owner, with no card of its own and not counted as a step.
> **Marks the gate scans for** — emit them exactly, and close every marked element with its own end tag:
> - the route sentence: `data-route` (at most one);
> - the scope line: `data-scope` (exactly one);
> - the colour legend, if colour is used: `data-legend` (at most one);
> - the *Starting point* list: `data-starting-point` (at most one, holding no cards);
> - each step card: `data-card="<id>"`;
> - each acceptance cell, inside its card: `data-acceptance`, with text starting `Passes when:`;
> - each check cell, inside its card: `data-check`, with text starting `Checked by:`;
> - each step node in the SVG: `data-step="<id>"`;
> - each external node: `data-external="<id>"`;
> - each edge: `data-edge="<from>-><to>"`, where `<to>` waits on `<from>`.
> The route sentence, scope line, legend, *Starting point* list and the acceptance and check cells hold wording this skill requires, so P2 does not search their words, only their ticks. Put nothing else in them, and do not nest one inside another. Status may not hide in an `aria-label`, a `title` attribute, an SVG `<title>`, a `<progress>` or a `<meter>` either: the scanner reads all of those.
> Then draw the **dependency flowgraph** as inline `<svg>` generated from the ledger's `depends on` edges, laid out so the order reads top-to-bottom or left-to-right. If the edges form a cycle, stop and report it; do not draw around it. No node may show a status, a tick or a progress colour; colour, if used, encodes the owner and carries a legend.
> **Page shape, in this order** (this replaces item 5's reader-side bullet):
> 1. The route sentence (`data-route`) and who the page is for.
> 2. The **scope line**, above the flowgraph. It states what this plan covers; what is out of scope; that every step is planned and none is finished; and `as of <source> @ <version>, <time>`.
> 3. The flowgraph.
> 4. *Starting point*, if there is one.
> 5. One card per step, in a topological order: title, waits on, owner, acceptance, check.
> 6. Risks, each naming the step it threatens and its mitigation, or `accepted`.
> 7. Owners, each with their steps.
> 8. Out of scope, quoted from the source where it says so.
> 9. Open questions the source leaves.

**Dossier section map.** `/prove`'s template is filled as follows:
- *1. The Thesis* takes the route sentence and the source version.
- *2. Claim Ledger* becomes the Step Ledger, with the three provenance classes.
- *3. Assets Rendered* takes the flowgraph and any captured source excerpt.
- *4. Structural Device* reads "flowgraph + step cards".
- *5. Scope Block* takes the scope line verbatim.
- *6. Publish Record* is unchanged.

**Addendum**, appended after section 6:
- *Graph reconciliation*: `steps · externals · nodes · edges · ledger edges · cycles`.
- *Risks*.
- *Owners*.
- *Out of scope*.
- *Starting point*.
- *In flight*.
- *Job questions*, with where the page answers each one.

## 3. The Route Gate

Run `/prove` § "3. Presentation-Integrity Pass (the gate)" first. In that pass the opening must state its scope; the load-bearing render, here the flowgraph, is eyeballed against what it claims; overstatement is hunted; and the scope block must be where the reader meets it. Then run each check below. Each is pass/fail; a failure is a targeted edit and a re-check, never a note in the report. The planner's self-check is an input, never a pass.

Read the dossier for the judgement checks, as `/prove` says. The checks that need the HTML (P2, P3, P6, P8) run the scanner over it — `python3 -I ~/.claude/engine/skills/prove-plan/assets/plan-page-scan.py all <pagePath>` — which reports counts and findings without the page entering your context.

**P1 — Every step names its check.** For every card, the check names a concrete command, test or observation, who or what runs it, and the passing result. "Test it", "verify", "confirm it works", "check that it's right" and a blank all fail; the scanner's `done` mode flags a check cell that says only one of those, and the rest is read by eye. Reconcile as a number: `checks named: <N>/<steps>`. Anything short of all is sent back.

**P2 — Nothing is presented as done.** The scanner's `done` mode searches the page's words outside the six regions whose wording this skill requires — the route sentence, the scope line, the legend, the *Starting point* list, and the acceptance and check cells — and outside `<pre>`, `<code>` and `<blockquote>`, where quoted source may say what it says. It reads `aria-label` and `title` attributes and an SVG `<title>` as page text; only a `<title>` inside `<head>` is skipped.
- **Inside the six regions** it still flags tick marks and enforces the fixed openings `Passes when:` and `Checked by:`.
- **The regions are bounded**, so they cannot be used to hide status: exactly one scope line; at most one route sentence, one legend and one *Starting point* list; acceptance and check cells only inside a card; no card inside a region; no region inside another; and every region closed by its own end tag. A region left unclosed is an error, never a region stretching over the rest of the page.
- **Anywhere** a strike-through, a checked checkbox, a `<progress>` or a `<meter>` is a finding.
- **A done-word counts only as its own word.** Part of a hyphenated compound ("built-in") is not a hit, and neither is a possibility or a future ("the PR may be closed", "will be merged").
Done-words: done, complete, completed, finished, shipped, passed, merged, landed, committed, fixed, built, published, resolved, closed, green, released, succeeded, deployed, verified, ✓, ✔, ✅, ☑, [x].
Ticks are matched in any case (`[x]` and `[X]`). Every hit is removed, or the sentence moves into the region it belongs to; there is no override. Reconcile: `shown as done: 0`.

**P3 — The graph is the ledger.** The scanner's `graph` mode reads `data-step`, `data-external`, `data-edge` and `data-card`. It confirms that every edge joins known nodes and appears once; that no edge points into an external and every external feeds a step; that the cards are exactly the steps; that `tsort` finds no cycle; and that the card order is topological. Compare its line `steps · externals · nodes · edges · cards · cycles` against the dossier's ledger counts. They must be equal as numbers, not as an impression.

**P4 — Acceptance is an end state.** Each step's acceptance describes something a reader could observe afterwards ("Passes when: the endpoint returns 404 for a deleted row"), not the activity ("implement deletion").

**P5 — Owners are real.** Each step shows an owner taken from the source or says `unowned`. No owner is invented; an inferred owner is `derived-here` and shows "proposed by the planner".

**P6 — Scope, risks and out-of-scope are where the reader meets them.** The scanner's `scope` mode confirms the scope line sits above the flowgraph and carries `as of <source> @ <version>` and says what is out of scope ("out of scope" or "out-of-scope"). By eye, confirm that each risk names the step it threatens.

**P7 — Provenance is visible.** Every `derived-here` field carries "proposed by the planner" on the page, so a reader can tell the plan's words from the planner's.

**P8 — Page mechanics.** Run `/prove-explore`'s C9 (in `prove-explore/SKILL.md` § "3. The Coverage Gate") as written there, on the `builds/` file and not on the published copy, because `publish-s3.sh` adds its own scripts to the copy it uploads.

**P9 — The page alone answers the job.** Take the two job questions from §1 C. Answer each from the page alone, without the dossier or the source, and record in the dossier where on the page each answer sits. A question the page cannot answer is a gap to fill, not a note.

**Degrade gracefully** (`¶INV_PROVE_DEGRADE_GRACEFULLY`): if the graph cannot be drawn, the page says so and shows the ledger as an ordered table with each step's `waits on` column, still carrying the `data-card` marks. A plan page without a drawing is usable; one without checks is not.

## 4. Publish & Report

Publish exactly as `/prove` § "4. Publish & Report" says, with `<pagePath>` in place of `<proofPath>`:

> `~/.claude/engine/skills/prove/assets/publish-s3.sh <pagePath> <slug>`

Report the S3 URL first, then `<pagePath>` and `<dossierPath>`, then one summary line:
`Route: <N> steps · externals: <N> · checks named: <N>/<N> · trusted-upstream: <N> · checked-here: <N> · derived-here: <N> · unowned: <N> · risks: <N> · out of scope: <N> · shown as done: 0 · as of <source @ version>`

Then **stop**. Offer `/build` or `/implement` to execute the route, `/loom` to run it as threads, `/snapshot` to checkpoint — never auto-run them. Live progress on the page is out of scope for this skill.

## Worked Example (compressed)

*Source:* a `/build` plan with five steps for a retry fix, at sha `4f1c2a9`. *Route:* "From today's single retry to a configurable three-retry upload path, ending with the staging upload test passing three injected failures."

- **Ledger:** step 3 ("wire the config") had no check in the plan; the planner proposed `npm test -- upload-retry.config` exiting 0, marked "proposed by the planner". Step 1 was already ticked in the plan, so it moved to *Starting point* with its provenance and left the graph. Step 4 waits on another team's SDK release, drawn as a dashed external node.
- **Graph:** four steps, one external, four edges; the scanner's counts matched the ledger and `tsort` found no cycle.
- **Gate:** P2 caught a "✓ schema" badge copied from the plan's checkbox and the word "landed" in a card's subtitle; both were removed. P1 read `checks named: 4/4`.

## Anti-Patterns

- **The status report in disguise** — ticks, progress bars, or "done" and "landed" badges on a plan page. Progress is a different page.
- **The wish list** — steps with no check, or a check that names no command, observation or passing result.
- **The decorative graph** — a flowgraph drawn by hand instead of from the ledger's edges, or one whose nodes carry no `data-step` marks to count.
- **Re-planning** — re-ordering or adding steps because the planner prefers them. The plan is the input; a disagreement goes in the return, a missing step in *Open questions*.
- **Invented owners** — a plausible name in an owner slot the source left empty.
- **The undated live plan** — a page cut from a ledger that moves every few minutes, with no as-of stamp.

## Constraints

- **Decided routes still ahead.** An undecided route goes to `/prove-visionary`; a travelled one to `/prove` or `/prove-explore`.
- **Every step names its check; nothing is presented as done.** These are this skill's honesty gate, checked as P1 and P2.
- **Thin.** The brief's shared parts, the templates, the provenance rules and the publish are `/prove`'s, cited by path and section; restating them here would be a second copy that drifts.
- **Building block.** It lays out a route and reports; it never executes, commits, files or decides.
