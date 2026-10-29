---
name: prove-explanation
description: "Teach ONE mechanism to a newcomer as a self-contained, shareable EXPLANATION page — the main idea in everyday words, then how it works, then a worked example with real values taken from the source, then its edge cases and what it is not. The teaching sibling of /prove: where /prove SHOWS a settled claim and /prove-explore MAPS a whole territory, /prove-explanation teaches one mechanism, narrower and more didactic than a map. Boundary with /prove-explore: one mechanism, taught in order to someone who knows none of our words, is /prove-explanation; a whole with many parts, mapped so a reader sees how they connect and where the map ends, is /prove-explore. Spine: teaching loosens the ORDER and the WORDS, never the evidence — every claim still carries a real asset or an honest provenance label exactly as /prove demands, and every value in the worked example is read from the source, never made up to be tidy. The thin sibling on /prove's shared assets: the assembler brief, the provenance rules, the dossier and notebook templates and the S3 publish are /prove's, cited and never copied; the prose follows VOICE.md's rules for explaining. A subagent grounds + composes; the orchestrator owns the teaching gate and the publish. A building block: it teaches and reports, never fixes, commits, files, or decides. Triggers: \"explain how X works\", \"teach me this mechanism\", \"explain this to a newcomer\", \"explainer page\", \"walk me through one example of X\", \"what actually happens when Y\"."
version: 1.0
tier: lightweight
args: "[<the one mechanism to teach, by its code name>] [-- <the reader / what they must be able to do after reading>]"
---

Teach **one mechanism** to someone who has not met it, as a self-contained, shareable **explanation page**. `/prove-explanation` takes a mechanism — how a hold is placed, how a retry is scheduled, how a row id is minted — and hands it to a background subagent that grounds it in the real source, traces one real input through it, and composes a page that teaches in a fixed order. You then run the teaching gate and publish it to a public S3 URL.

This is the **teaching sibling of `/prove`**, and a thin one: everything that is not specific to an explanation is `/prove`'s, cited below and never restated. As a **building block** it produces a page, not a change: it never edits code, never commits, never files a ticket, and never rules on whether the mechanism is right.

**The boundary with `/prove-explore`, stated in both skills:** `/prove-explanation` teaches **one mechanism** to a newcomer, in order — the idea, how it works, one worked example with real values, its edges. `/prove-explore` maps **a whole** — many parts, how they connect, and where the map ends. If the question has more than one mechanism in it, or the reader needs to see how parts fit together rather than how one part works, it is `/prove-explore`'s. Both skills answer to "how does X work"; the deciding fact is whether X is one mechanism or a whole. A settled claim that needs showing is `/prove`'s; an open direction is `/prove-visionary`'s; a decided route is `/prove-plan`'s.

*The spine — non-negotiable:* **teaching loosens the order and the words, never the evidence.** The page may open with an everyday analogy, may repeat an idea in a second form, and may spend its length on one example. Every claim in it still carries a real asset (the code, a log line, a test, a captured value) or an honest provenance label, exactly as `/prove` demands (`¶INV_PROVE_REAL_ASSETS_ONLY`, `¶INV_PROVE_FAITHFUL_PRESENTATION`). The worked example uses values read from the source, pinned to the version they were read at; a value made up to be tidy is a fabricated asset.

*Crucial constraint:* `/prove-explanation` does NOT own a session. Like `/prove`, it reads the *active* session and writes its paper trail there — the dossier and the composed HTML into `builds/`, raw captures into scratchpad.

## What this skill takes from /prove (cited, not copied)

The canonical base is `/prove` at `~/.claude/engine/skills/prove/SKILL.md`, not `/prove-next`: `/prove` owns the publishing plumbing under `prove/assets/`, and `/prove-next` is the kit-composed variant that itself reaches back into those assets. Read each cited section at run time; do not carry a copy of it.

| Mechanism | Where it lives | What changes here |
| --- | --- | --- |
| Trail layout, slug reuse | `prove/SKILL.md` § "1. Scope the Claim" (part D) | the two file names in §1 D below |
| The prover brief: its opening paragraph, items 2, 3, 5 and 6, and the two *Substituting* paragraphs | `prove/SKILL.md` § "2. Dispatch the Prover — Assemble → Render → Compose (subagent)" | items 1 and 4 are replaced, and item 5's reader-side bullet is overridden (§2) |
| Dossier | `~/.claude/engine/skills/prove/assets/TEMPLATE_PROVE.md` | filled per the section map in §2, plus the addendum |
| Notebook schemas for the subagent's log | `~/.claude/engine/skills/prove/assets/TEMPLATE_PROVE_LOG.md` | none |
| The integrity checks every page owes | `prove/SKILL.md` § "3. Presentation-Integrity Pass (the gate)" | the teaching gate below runs on top of them |
| Publish, config, port check, seat strip, attachment flow, report | `prove/SKILL.md` § "4. Publish & Report", via `~/.claude/engine/skills/prove/assets/publish-s3.sh` | the summary line below |
| Page mechanics measured in a driven browser | `prove-explore/SKILL.md` § "3. The Coverage Gate", check C9 | applied to the `builds/` file (E8) |
| Invariants | `¶INV_PROVE_TRUST_UPSTREAM`, `¶INV_PROVE_REAL_ASSETS_ONLY`, `¶INV_PROVE_FAITHFUL_PRESENTATION`, `¶INV_PROVE_DEGRADE_GRACEFULLY`, `¶INV_PROVE_COMPOSE_ONCE`, `¶INV_PROVE_S3_URL_IS_SHAREABLE` in `prove/SKILL.md` § "Constraints" | provenance gains a third class, `derived-here` (§2) |

The one asset of its own is `~/.claude/engine/skills/prove-explanation/assets/explain-page-scan.py`, the mechanical half of the teaching gate. It walks the HTML with `~/.claude/engine/skills/prove-plan/assets/_page_regions.py`, which it shares with `/prove-plan`'s scanner and imports by relative path.

**The prose rules are `~/.claude/engine/.directives/VOICE.md`**, and this page leans on it harder than any sibling:
- `VOICE.md` § "The reader": a newcomer knows programming but none of our words.
- `VOICE.md` § "Explaining": the main idea in everyday words first; a small example with real numbers; a term introduced once and kept; the code's spelling for things the code names.
- `VOICE.md` § "Talking about the work": our working words stay out.
- `VOICE.md` § "A calm tone": say what a thing is not only when a reader would otherwise believe it.
- `VOICE.md` § "Honesty and numbers".

Cite these sections in the brief; do not paraphrase them into it.

# /prove-explanation Protocol

## 1. Scope the Mechanism

**A. The one mechanism.** Name it by the code's own spelling and state, in one sentence, what it does. If that sentence needs an "and" joining two things that could each be explained alone, it is two mechanisms: pick one, or route the whole to `/prove-explore`. If you cannot name it, ask ONE `AskUserQuestion`.

**B. The reader and the job.** By default the reader is a newcomer in VOICE.md's sense. Name what they must be able to do after reading — predict what the mechanism does with a given input, or find where to change it. Write the two **job questions** that test it (for example, "what does `target` print for seat X in this tree?" and "which function would I change to add a new exit code?"); E9 asks them.

**C. The source.** The code paths, tests, docs or a sibling's report the explanation rests on. Record the version of each file you will quote: its commit sha, or its `sha256` when it is uncommitted. Code that changes while you work moves line ranges under the page; the pin is what makes a quote checkable later. Findings from upstream are trusted as `/prove` trusts them; values the page quotes are read here, from the source.

**D. The trail — the one place these paths are stated.** As `/prove` § "1. Scope the Claim" part D, with:

- `<pagePath> = <trailDir>/<slug>_EXPLAIN.html`
- `<dossierPath> = <trailDir>/<slug>_PROVE_EXPLANATION.md`

Everywhere else this file says `<pagePath>` and `<dossierPath>`. Wherever `/prove`'s text says `<proofPath>`, read `<pagePath>`.

**Acknowledge** in one line: `Explaining: <mechanism> — reader: <who>, who must be able to <job>; from: <source @ pin>; trail: <dossierPath>.`

## 2. Dispatch the Teacher — Ground → Sequence → Trace → Compose (subagent)

Dispatch exactly as `/prove` § "2. Dispatch the Prover — Assemble → Render → Compose (subagent)" says — backgrounded by default, a fully self-contained brief with absolute paths, `§CMD_LOG_SKILL_INVOCATION` before the handoff, base64 never returning to your context.

Brief items included from /prove: opening, 2, 3, 5, 6, Substituting.
Brief items replaced here: 1, 4.

Build the brief in this order, reading each included part from `/prove`'s file:

1. `/prove`'s **opening paragraph** (the one beginning "You are an **evidence engineer**"), with "PROOF" read as "EXPLANATION page" and "finding" as "the mechanism as the source implements it". Then name `~/.claude/engine/.directives/VOICE.md` as the prose rules the subagent must read before writing.
2. Item **1** below, in place of `/prove`'s item 1.
3. `/prove`'s items **2** and **3** as written.
4. Item **4** below, in place of `/prove`'s item 4.
5. `/prove`'s item **5**, except its bullet **"Write from the reader's side"**, which item 4 below overrides entirely:
   - its thesis line becomes the one-line scope at the top;
   - its key-insight callout becomes part 1, the idea;
   - its scope block becomes that top scope line plus part 5's closing boundary;
   - its end-state is dropped, because the five parts end on what the mechanism is not.

   Item 5's other bullets — loading `Skill(artifact-design)`, self-contained and CSP-safe, no third-party renderer, theme-aware and responsive, an honest title — stand.
6. `/prove`'s item **6** (the output contract: the dossier from the template, the `<LOGGING>` heartbeat, the tight return manifest). The template's base dir is `~/.claude/engine/skills/prove/assets/`, not this skill's. The return manifest's provenance counts gain a third, `N derived-here`, beside `/prove`'s trusted-upstream and checked-here.
7. `/prove`'s two **Substituting** paragraphs, with the paths from §1 D: `<dossierPath>` and `<pagePath>` (in place of `<proofPath>`), and `<LOGGING>` resolved to the concrete `engine log` command.

> **1. The mechanism** — `<mechanism>`: `<one-sentence what it does>`, for `<reader>`, who must be able to `<job>`. Source: `<paths @ pins / report>`. Teach this one mechanism; where it hands off to a neighbouring one, name the neighbour in a sentence and stop.
>
> **4. Compose in this fixed order** — the order is the point of the page (this replaces item 5's reader-side bullet). Mark each part with `data-part`, and put a one-line scope marked `data-scope` at the very top: the mechanism, the reader, and what is not covered, so the boundary is met before the first part.
> 1. **`data-part="idea"` — the main idea in everyday words.** Say what the mechanism does and why it exists, in words a newcomer already has. An analogy is welcome if it is labelled as one and the page says where it stops holding. Wrap any term of ours or any code name used here in `<dfn>` with its definition beside it — or leave it out of this part.
> 2. **`data-part="how"` — how it works.** Give the steps the mechanism takes, in the order they happen. Ground each in the real code: a `<pre>` carrying `data-source="<path>:<lines>"` and `data-pin="<commit sha>"`, or `data-pin="sha256:<hex>"` for an uncommitted file — the pin of *that* file, since the gate checks it against the file. A line reference written in prose or in `<code>` (`hold.ts:12-18`) sits inside an element that carries the pin too. A diagram, if used, is inline `<svg>` whose boxes are the real functions or records.
> 3. **`data-part="example"` — a worked example with real values.** Trace one real input through those steps, showing the value at each step as read from the source — a fixture, a test case, a log line, a database row. Each capture is pinned the same way, a table of captured values included. Do not round, rename or tidy a value.
>    - An input that exists in the source is marked `data-fixture="source"`, with its own `data-source` and `data-pin`.
>    - An input you wrote — allowed only when no real one fits — is marked `data-fixture="teacher-written"` with `data-adapted-from="<the source fixture or test it was adapted from>"`, and is labelled "written for this page" inside its own element. The **values the mechanism produces** from it count as real only when they were captured by running the real code; the input itself is never presented as found.
>    - If no input can be run at all, say so on the page and in the dossier rather than inventing values.
> 4. **`data-part="edges"` — edge cases.** Each points at what in the source handles it (a branch, a guard or a test, pinned) and says what the mechanism does there.
> 5. **`data-part="not"` — what it is not.** Include only beliefs a newcomer would plausibly hold, each saying why it matters (`VOICE.md` § "A calm tone"). Close with the boundary: what this page does not cover, and that `/prove-explore` maps the whole if the reader needs it.
>
> Both "how" and "example" hold at least one pinned block, and every marked element is closed by its own end tag.
> **Marks the gate scans for:** `data-scope`, `data-part`, `<dfn>` (written `dfn`), `data-source`, `data-pin`, `data-fixture`, `data-adapted-from`.

**Dossier section map.** `/prove`'s template is filled as follows:
- *1. The Thesis* takes the mechanism sentence and the source pins.
- *2. Claim Ledger* holds one entry per part, giving that part's load-bearing claim and provenance.
- *3. Assets Rendered* lists every quote and capture with its pin.
- *4. Structural Device* reads "the five-part teaching order".
- *5. Scope Block* takes the top scope line verbatim.
- *6. Publish Record* is unchanged.

**Provenance has three classes here.** `trusted-upstream` covers what a sibling's report established. `checked-here` covers what was read or run here, with its pin and the time it was read. `derived-here` covers what the teacher wrote: an analogy, a teacher-written fixture, an edge case reasoned out. A `derived-here` item is labelled on the page as written for the page.

**Addendum**, appended after section 6:
- *Terms introduced*: each term and where it is first defined.
- *Worked-example trace*: step · value · source · pin · read at.
- *Edge cases*: each case and the code or test that handles it.
- *Not-beliefs*: each belief and why a reader would hold it.
- *Analogy*: if there is one, and where it breaks.
- *Job questions*: with where the page answers each one.

## 3. The Teaching Gate

Run `/prove` § "3. Presentation-Integrity Pass (the gate)" first. In that pass the opening must state its scope; the load-bearing render, here the worked example's captured values, is eyeballed against its source; overstatement is hunted; and the scope block must be where the reader meets it. Then run each check below. Each is pass/fail; a failure is a targeted edit and a re-check, never a note in the report. The teacher's self-check is an input, never a pass.

Read the dossier for the judgement checks, as `/prove` says. The checks that need the HTML (E2, E3, E5) run the scanner over it — `python3 -I ~/.claude/engine/skills/prove-explanation/assets/explain-page-scan.py all <pagePath> --root <the repo the data-source paths are relative to>` — which reports findings without the page entering your context. E8 is C9's own browser check. The scanner does **not** detect invented values; E4 is by eye only.

**E1 — One mechanism.** The page answers one "how does this work". A section that explains a second mechanism is cut to a one-sentence pointer.

**E2 — The order holds.** The scanner's `order` mode confirms the scope line comes first, followed by the five parts once each in order: idea, how it works, worked example, edge cases, what it is not. By eye: a reader who stops after the first part has a correct, simple picture.

**E3 — The first part is in everyday words.** The scanner's `jargon` mode finds the terms itself, from the page, rather than from the teacher's *Terms introduced*. A term the teacher did not list is still caught. It looks for every `<code>` span; every code-shaped token (snake_case and ENV_NAMES, camelCase, `--flags` and `-v`, file names); any hyphenated word that also appears in the page's own code, such as `may-rule`; and VOICE's working words that are never everyday English (gates, ledgers, lanes, patch-ids). Each one found in part 1 must be defined there in a `<dfn>`, which may carry its definition after a comma, colon or dash. VOICE's everyday working words — checks, guards, claims — are left to the reviewer, because "a quick check" reads correctly to a newcomer. Then, by eye, look for our project words the pattern cannot recognise (for example "seat" or "pane"), and confirm that any analogy is labelled and says where it breaks.

**E4 — Every value in the worked example is real.** This check is by eye only; no scanner looks for invented values. For each value, the dossier's trace names where it was read, its pin, and when it was read. Open the load-bearing capture yourself and compare it with the page. A value with no source, or one that differs from its capture, fails. A value produced from a teacher-written fixture passes only if it was captured from the real code.

**E5 — Every claim carries evidence or honest provenance, pinned.** Hunt overstatement per section, as `/prove` § "3. Presentation-Integrity Pass (the gate)" does per page: each part's load-bearing claim has a real asset, a `trusted-upstream` label, or a visible `derived-here` label. The scanner's `pins` mode confirms:
- every `<pre>`, every captured table and every `data-fixture="source"` carries `data-source` and a `data-pin` that is a commit sha or `sha256:<hex>`; a date fails, with or without its dashes;
- every pin belongs to the file it cites: a commit pin must contain that path (`git cat-file -e`), and a `sha256:` pin must be that file's hash, both under `--root`;
- every line reference (`path.ext:N`) in prose or `<code>` sits inside an element carrying a pin;
- "how" and "example" each hold at least one pinned block;
- every teacher-written fixture names what it was adapted from and is labelled where the reader sees it.

**E6 — Edge cases are grounded.** Each edge case points at the pinned branch, guard or test that handles it. An edge case reasoned out with nothing in the source behind it is cut or labelled `derived-here`.

**E7 — "What it is not" earns its place.** Each item names the belief it corrects and why that belief is plausible. A list of things the mechanism obviously is not is padding and is cut.

**E8 — Page mechanics.** Run `/prove-explore`'s C9 (in `prove-explore/SKILL.md` § "3. The Coverage Gate") as written there, on the `builds/` file and not on the published copy, because `publish-s3.sh` adds its own scripts to the copy it uploads.

**E9 — The page alone answers the job.** Take the two job questions from §1 B. Answer each from the page alone, without the dossier or the source, and record in the dossier where on the page each answer sits. A question the page cannot answer is a gap to fill, not a note.

**Degrade gracefully** (`¶INV_PROVE_DEGRADE_GRACEFULLY`): if no real input could be run, the worked-example part says so plainly and shows the code path with the values it would read named but not invented.

## 4. Publish & Report

Publish exactly as `/prove` § "4. Publish & Report" says, with `<pagePath>` in place of `<proofPath>`:

> `~/.claude/engine/skills/prove/assets/publish-s3.sh <pagePath> <slug>`

Report the S3 URL first, then `<pagePath>` and `<dossierPath>`, then one summary line:
`Taught: <mechanism> @ <pin> · terms defined in part 1: <N> · example values: <N> captured (invented: checked by eye, E4) · trusted-upstream / checked-here / derived-here: <N> / <N> / <N> · teacher-written inputs: <N> · edge cases: <N> grounded · not-beliefs: <N> · out of scope: …`

Then **stop**. Offer `/prove-explore` if the reader now needs the whole, `/snapshot` to checkpoint — never auto-run them.

## Worked Example (compressed)

*Mechanism:* `placeHold` — money is set aside when a job is posted. *Reader:* a developer new to the market. *Source:* `ledger/hold.ts` at sha `9e2b7c1`.

- **Idea:** "When you post work, its money is set aside at once, much as a hotel holds an amount on your card." This is labelled as an analogy, which stops holding because a hold here never expires on its own.
- **Worked example:** a fixture job of 120.00 (`data-fixture="source"`, from `hold.test.ts`) traced through `placeHold`. The balance row was read before (500.00 available) and after (380.00 available, 120.00 held), each value pinned to the fixture's sha.
- **Gate:**
  - E3's scanner caught `placeHold` and "ledger" in the first part without a `<dfn>`; the first was moved to part 2 and the second defined.
  - E4 matched both balance values against the captured rows.
  - E5's scanner caught one `<pre>` with no pin.

## Anti-Patterns

- **The map in miniature** — three mechanisms on one page because they sit near each other. That is `/prove-explore`'s page.
- **The tidy example** — round numbers made up because the real ones were awkward. The awkward real ones teach; the tidy ones are fabricated.
- **Jargon first** — opening with our own working words and defining them later, or never.
- **The unpinned quote** — a code block with a path and line range but no sha, which goes wrong the next time the file changes.
- **The straw "what it is not"** — denying things nobody believed.
- **The analogy that becomes the explanation** — an analogy carried past the point where it stops matching the code.

## Constraints

- **One mechanism, taught in order, to a newcomer.** A whole goes to `/prove-explore`; that boundary is stated in both skills.
- **Evidence is not loosened.** Every claim carries a real asset or honest provenance, as `/prove` demands; every worked-example value is captured from the source and pinned.
- **Thin.** The brief's shared parts, the templates, the provenance rules and the publish are `/prove`'s, and the prose rules are VOICE.md's, cited by path and section; restating them here would be a second copy that drifts.
- **Building block.** It teaches and reports; it never fixes, commits, files or decides.
