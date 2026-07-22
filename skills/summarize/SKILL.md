---
name: summarize
description: "Catch yourself up on a body of work and review it. This is an inward, read-only report over a dynamically-scoped chunk OR the whole session. A reader subagent digests the trail (log / plan / DIALOGUE / builds / git) into a distilled, intent-oriented report: a header line, a top stat strip (files · LOC · commits · tests · plan-steps · leftovers), goal-vs-actual, the moves, leftovers, and a confidence read — TRUSTING the recorded numbers, never re-running gates. Then, a two-way review: the agent surfaces its genuine uncertainties for you to confirm, and hands you a 4×4 inverse-ask palette (16 curated questions YOU can fire back at it about its own work), answers them, and offers to save the report. A building block: it reports and reviews, never commits, posts, hunts bugs, or fixes. Triggers: \"summarize this\", \"summarize the chunk\", \"summarize the session\", \"catch me up\", \"recap what happened\", \"review this chunk\", \"what did we just do\", \"give me the numbers on this work\"."
version: 1.0
tier: lightweight
args: "[<scope: a plan step / builds slug / git range / 'session' / 'chunk'>] [-- <framing / what you most want to understand>]"
---

Catch yourself up on a body of work and review it. `/summarize` is the **inward, read-only** sibling of the workflow family. Where `/snapshot` reports *outward* (verify → commit → post) and `/scrutinize` *hunts and fixes* bugs, `/summarize` produces **understanding and a guided review**—and nothing else.

A reader subagent digests the paper trail into a tight, intent-oriented report. Then, you review the work in two ways: the agent asks you to clarify its genuine uncertainties, and it hands you a curated palette of questions so you can interrogate it. This skill is sessionless and lightweight. It runs *within* the active session: resolve scope → read → report → review → offer to save → stop.

**Hard Boundaries & Hand-offs:** This is **not `/snapshot`** (it never commits, posts to a ticket, or re-runs a gate to verify). This is **not `/scrutinize`** (it does not hunt for bugs or fix code). It reads what happened, explains it clearly, and helps you interrogate it. If it happens to notice a bug or risk, that becomes a line item in the report, not a trigger for a repair. As a report engine, its output can optionally be consumed by `/snapshot` to draft ticket updates. It consumes the artifacts produced by its siblings (`_BUILD`, `_CRITIQUE`, `_EXPERIMENT`, `_FIX`) and `LESSONS.md`.

# /summarize Protocol

## 1. Resolve scope & target

Establish **what to summarize** (a specific chunk or the entire session) and determine where the final report will be saved.

- **Auto-detect then confirm (One Question):** Do not force the user to specify the scope upfront. Auto-detect the most likely scope, then use a single `AskUserQuestion` to confirm when detection is ambiguous or the scope is large.
  - **Chunk (Default if detectable):** Look for the most recently worked plan section, the newest `builds/<slug>_*.md` cluster, the commit range since the last checkpoint, or "work since my last `/summarize`".
  - **Session:** The entire log / plan / `DIALOGUE.md` arc.
  - **Argument Overrides:** If the user provides an argument (e.g., a named plan step, a `builds/<slug>`, a git range like `HEAD~5..`, a time window, or literally types `session` / `chunk`), this overrides auto-detection.
- **Confirmation Rule:** Ask: *"Summarize **chunk: `<detected>`** (detected), or the **whole session**?"* **Skip this question ONLY** if the user provided an unambiguous argument that pinned the scope.
**Resolve the Artifact Location (`<trailDir>`) & report path.** Also bind `<reportPath>` — the report's save target — once, and hand the subagent (§2) the fully-substituted absolute path (never the placeholder): `<trailDir>/<slug>_SUMMARY.md` for a chunk scope, else `<sessionDir>/SESSION_SUMMARY.md` for a session scope. `<trailDir> = <sessionDir>/builds/` — determine it once and use it everywhere below.

**Mint the `<slug>`.** For a chunk scope, the orchestrator owns the slug.
1. Run `ls <trailDir>`.
2. If an existing `<slug>_*.md` cluster clearly matches this work (same chunk / ticket / topic), REUSE that slug so the trail clusters under one name.
3. Only mint a new short, kebab-case slug for genuinely new work.
*(For a session scope, no slug is needed; the save target is the session root — see §6).*

- **Resolve Git Range:** Deterministically find the commit range for the stat strip. For a chunk, use `<base>..HEAD` or the provided arg range. For a session, use the session's full commit span. Record this range so the reader subagent can use it for `git diff --numstat` and `git log`.

**Echo back one line:** `Summarizing <chunk: "<slug>" | the session> (<git-range>) from <trailDir>; report → chat<, savable as <name>>.`

## 2. Read — spawn the reader subagent (read-only digest)

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

> **Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + context-pack pointer + one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

Spawn **one** subagent (using a `general-purpose` or `analyzer` profile) to digest the scope and return a **distilled report**.

**Crucial Subagent Constraint:** It *only* reads. It never mutates, never commits, and **never re-runs a gate**. Delegating this to a subagent keeps your main orchestrator context lean, transforming a massive session trail into a tight, high-signal report.

Construct the subagent's prompt to be entirely self-contained. Use the following prompt structure:

> **ROLE:** You are an **investigative journalist** producing an INWARD REVIEW REPORT of a body of work for the developer who wrote it. Do not just list what changed—explain the **narrative arc**. Why did the approach pivot? What technical debt fought back? What features were traded away for speed? Distill the chaos of the session into clarity. You READ and DISTILL. You do NOT commit, post, fix, hunt for bugs, or re-run any test/gate. Report the numbers AS RECORDED; **never verify them**.
>
> **SCOPE:** `<chunk "<slug>" | the whole session>` — git range `<range>`.
>
> **SOURCES:** Read the trail SCOPED to this work, not just the diff. In `<trailDir>`, read this work's `<slug>_*.md` files (`_BUILD`, `_CONTEXT_PACK`, `_CRITIQUE`, `_FIX`, `_EXPERIMENT`, `_TICKETS`), PLUS the session `*_LOG.md`, the plan, `DIALOGUE.md`, and `LESSONS.md`. For a full session scope, read the entire arc.
> - *Note:* In a long session, `builds/` holds many unrelated slugs. Only skim artifacts from other slugs if they are directly relevant to this specific work.
>
> **TRUST, DON'T VERIFY (HARD FENCE):** Read test results, pass counts, and "green" claims from the LOG / git exactly as recorded. **Do NOT run** `tsc`, `test`, `build`, `lint`, `db:*`, or anything else. Label the numbers with their source and recorded time (e.g., *"tests 53→53 as recorded 14:33"*). If a claim is unclear or unverifiable from the artifacts, state that plainly. **Never assert a green you can't source.**
>
> **STAT STRIP:** Compute this deterministically (no LLM guessing).
> - Files touched + `+LOC/−LOC` (from `git diff --numstat <range>`)
> - Commit count (from `git log --oneline <range>`)
> - Test results (parsed from the log)
> - Plan-step completion (from the plan's `[x]`/`[ ]` within scope)
> - Leftover count (unfinished/deferred items).
> Format as one glanceable row.
>
> **REPORT FORMAT:** Use the template at `assets/TEMPLATE_SUMMARY.md` (the orchestrator gives you its base dir; **do not hardcode `~/.claude`**). Include:
> - **Header line:** What this work was (one line).
> - **Stat strip.**
> - **Goal vs. actual:** Intent alignment (what it was meant to do vs. what happened).
> - **The 'why' behind the moves:** 3–4 major architectural/logical shifts and WHY they happened. (Narrative, not a file list).
> - **Unresolved tensions:** Tech debt accepted, invariants left unasserted, disagreements settled by fiat.
> - **Leftovers / open items.**
> - **Confidence:** Your honest read + why.
> *Keep it tight and scannable. Large reports are fine if the work warrants it; padding is not.*
>
> **AGENT-ASKS-YOU (The Gut-Check):** Propose up to 4 GENUINE uncertainties you have about whether the work matches the user's intent. These must be real questions whose answers you don't know from the trail, each citing a concrete artifact or decision. No trivia or quiz questions. If you genuinely have none, return fewer (or zero).
>
> **INVERSE-ASK PALETTE (Two Steps):**
> 1. **Theme Map (~32 topics):** Derive a wide map of ~32 short topics (~8 per lens: **Correctness, Decisions, Risk, Scope-&-Next**). This represents the full space of *what is askable* about this work. **Generate every theme CONTEXTUALLY from THIS specific work.** Do not pattern-match the template's illustrative examples. Name real files, functions, decisions, and leftovers.
> 2. **The 16 Questions:** From those ~32 themes, SELECT the 16 best-fit, well-formed questions. These are the questions most worth asking about THIS work. Drop weak or overlapping themes. Every question MUST reference a concrete artifact/decision (`¶INV_INVERSE_ASK_IS_SPECIFIC`). Include a 1-2 sentence answer sketch for each.
> *Write BOTH the full ~32 theme map and the selected 16 questions to the report.*
>
> **RETURN CONTRACT:** WRITE the report + the two proposed question sets to `<reportPath>` using the template. Then, return a 6–10 line summary to the orchestrator containing: the header line, the stat strip, the confidence read, the count of agent-uncertainties, and confirmation that the 4×4 palette is ready.

Background is available (`run_in_background: true`) and relaying the report summary when it lands still applies — but this step **commonly runs foreground**, since the §4–§5 review needs the reader's report and question sets in hand right after. Run foreground when you need the result inline for the next step.

## 3. Render the report

Render the reader's report in the chat. Put the header line and stat strip at the top, followed by the body.

If the report is exceptionally long, render a tight digest and provide a link to the `<reportPath>`. This is the "catch me up" deliverable—a skimmer should be able to grasp the exact state of the work from the first three lines.

## 4. Agent-asks-you (the gut-check)

Present the reader subagent's genuine uncertainties to the user as **one** `AskUserQuestion` batch (maximum of 4 questions).

These are the specific areas where the agent isn't sure it aligned with the user's implicit intent—each must be tied to a concrete part of the work. If the reader returned zero real uncertainties, state that plainly and skip straight to §5. Do not invent filler questions just to populate the UI.

Log the user's answers as decisions (`engine log` under a session, else a plain trail-file append). These answers become the durable record of what "correct" means for this specific chunk of work.

## 5. Inverse-ask (themes → one 4×4 question grid)

The inverse-ask palette is built in two steps (both proposed by the reader subagent in §2):

1. **Theme map (Wide coverage scaffold):** This is mostly internal. It consists of **~32 short topics (about 8 per lens)** spanning *what is askable at all* about this work, grouped by the 4 lenses (Correctness, Decisions, Risk, Scope-&-Next). It is generated CONTEXTUALLY from the actual trail, never copied from template examples. It is intentionally ~2× the size of the final grid so the final questions are a genuine *curation*, not a forced fill. *Optional: Surface a one-line "you could ask about…" preface so the user sees the breadth of the map.*
2. **The 16 well-formed questions (User-facing):** The subagent SELECTED the 16 best-fit questions from the theme map. Present these to the user as **4 lens groups × 4 contextual questions** in a single `AskUserQuestion` (multiSelect).
   - Each lens is a question-column.
   - Its 4 questions are the options.
   - **The user always picks a well-formed, specific question — never a raw theme.**

The user may pick any subset of questions. The orchestrator agent then **answers each picked question** using the trail (relying on the reader's answer sketches and the artifacts).

**Single pass — no loop.** Once answered, proceed immediately to §6.

**Crucial Constraint:** Every question must be specific to this work (`¶INV_INVERSE_ASK_IS_SPECIFIC`). If a particular lens cannot yield 4 highly specific questions, present fewer options for that lens rather than padding it with generic boilerplate.

## 6. Offer to save

Offer to persist the report (via `AskUserQuestion` or a one-line confirm):
- **Chunk scope:** Save as `<trailDir>/<slug>_SUMMARY.md`. (This uses the same `<slug>_*` convention as `_BUILD.md` or `_SNAPSHOT.md`, ensuring it clusters cleanly with the chunk's other artifacts).
- **Session scope:** Save as `<sessionDir>/SESSION_SUMMARY.md` at the session root.

The report subagent already wrote a draft file to `<reportPath>` during §2.
- If the user **declines** the save, note the ephemeral path in the chat (it lives in the trail either way) or leave it as the working draft.
- If the user **accepts**, confirm the final path.

Then **stop**. A saved summary can later feed `/snapshot`'s comment body or a PR body, but wiring that up is the user's responsibility, not this skill's.

## Constraints
- **`¶INV_SUMMARIZE_READ_ONLY`** — `/summarize` never mutates. No commits, no ticket posts, no code fixes, no gate/test re-runs. It reads, reports, and asks. A bug or risk it notices is a report line, not a repair.
- **`¶INV_SUMMARIZE_TRUST_NOT_VERIFY`** — Numbers are trusted from the log/git exactly as recorded, labeled with their source and time. Verifying "greens" is `/snapshot`'s job. Unclear or unsourceable claims are stated as such; never assert a green you can't source.
- **`¶INV_INVERSE_ASK_IS_SPECIFIC`** — Every inverse-ask candidate (and agent-asks-you question) must reference a concrete artifact, decision, or leftover from the summarized work. The user-facing menu must be well-formed contextual questions, never raw themes. The theme map ensures broad coverage. Present fewer questions rather than padding with generics.
- **Dynamic scope, auto-detect + confirm once.** Detect the most likely scope (chunk vs. session). Let arguments override. Confirm with one question when detection is ambiguous or the scope is large. Never force the user to specify scope up front.
- **Always a read-only reader subagent.** The digest runs in a subagent (full trail in → tight report out) to keep the orchestrator's context lean. The interactive review (§4–§5) stays with the orchestrator because it requires user interaction.
- **Two-way review, in order.** Report → agent-asks-you (agent's uncertainties) → inverse-ask 4×4 palette (user's questions) → offer to save. One pass, no loop.
- **Chat first, save on offer.** Render in chat by default; offer to persist. No auto-save.
- **Building block.** It reports + reviews and then stops — it never commits, posts, files followups, or fixes. Its report engine is factored so downstream skills (like `/snapshot`) can call it to generate bodies.
- **Lightweight + sessionless.** Runs within the active session — resolve scope → read → report → review → offer to save, then stop.
