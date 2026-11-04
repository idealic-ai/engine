---
name: envision
description: "Write and keep a vision document from inside a loom, with chapters a loom can turn straight into threads. It rides the host session (it owns none and never moves the host's phase), drafts the whole vision first with every open choice marked PROPOSED and a lean, puts all its open questions into ONE ask, and writes docs/<NAME>_VISION.md whose chapters carry a thread slug, ticket, status, owner seat, paths, size and wave. Four actions: draft (a new vision), revise (intent changes, gated on answered forks), reconcile (a fact moved under the document, ungated) and decompose (the ready chapters written as /groom-format topics for the loom's add-a-thread flow). It files no ticket and edits no fleet config; /direct stays the standalone vision designer. Triggers: \"envision this\", \"write a vision in the loom\", \"turn this into a vision and threads\", \"reconcile the vision\", \"decompose the vision\"."
version: 1.0
tier: lightweight
args: "draft <subject> [--name <NAME>] [-- <context paths>] | revise <vision path> [-- <what changes>] | reconcile <vision path> — <what moved> | decompose <vision path>"
---

Write a vision a loom can execute, ask its questions once, and keep it true as the threads land.

# /envision Protocol (The Vision a Loom Can Run)

[!!!] A **composed, sessionless** skill. It **rides the host session** and owns none (`§INV_RIDE_NEVER_ACTIVATES`): it never runs `engine session activate` or `engine session phase`, and writes nothing to `.state.json`. There is one `.state.json` per session directory with one `currentPhase`, and a pass that advanced it would overwrite the conductor's own position in the only file the host has. It has no phases, no log of its own and no debrief.

## What it is, and what it is not

*   **It is** the vision writer for a loom. A vision is a plan of record: a goal, its constraints, and chapters. Here each chapter carries the fields a loom needs to make it a thread, a ticket and an owner, so a vision written here turns into work without anybody re-deriving it.
*   **It is not `/direct`.** `/direct` stays the standalone vision designer for an interactive session of its own (the operator's ruling BESIDE, ask `meta:engine/envision-shape`, 2026-11-04). Inside a loom, use this skill. The two do not edit each other's documents: `/direct` writes `docs/<NAME>_DIRECT.md`, this skill writes `docs/<NAME>_VISION.md`.
*   **It is not a filer.** It files no ticket, creates no lane and edits no fleet config (`¶INV_ENVISION_FILES_NO_TICKET`, `¶INV_ENVISION_PROPOSES_OWNERS_ONLY`). It writes the vision, its record and the topic file; the loom does the rest through its own composed skills.

## Where it runs, and who it asks

Resolve these once, before any action does anything, and say them in one line.

*   **The host.** Take the host session from the caller first: a conductor dispatching a lane passes the host's session directory and log path in the brief, because a lane in its own worktree may get nothing back from `engine session find`. Otherwise read the active session with `engine session find`. A loom (`taskType: LOOM`) or any other live session → ride it: the record goes in `<host>/builds/`, and log entries go in the host's log prefixed `[<threadId>]`. **With no host at all**, the actions split:
    *   `reconcile` and `decompose` still run, because they ask nothing and move no phase. Their record goes beside the vision as `<vision dir>/<slug>_ENVISION.md`, and the topic file as `<vision dir>/<slug>_ENVISION_TOPICS.md`. Say in one line that no host was found.
    *   `draft` and `revise` stop and say so. They ask questions and need a host to row them; `/direct` is the standalone vision designer.
    *   This skill never activates a session to make room for itself.
*   **The threadId.** The loom gives the pass one like any other thread (`ENVISION`, or the vision's slug), so the ledger, the stall sweep and the proof rule see it.
*   **The asking surface.** This follows the loom's rule, stated in `skills/loom/SKILL.md` § The manager chain and cited rather than restated here:
    *   **A dispatched lane** (another agent started you with its Agent tool) writes no ask and calls no `AskUserQuestion`. It hands the questions back to its conductor, each logged as `## [<threadId>] ❓ Ask <id>: …` (`LOOM_AGENT_DIRECTIONS.md` § Progress reporting), and the conductor writes the ask.
    *   **A seat with a parent** (`bash ~/.claude/engine/skills/coordinate/scripts/hop.sh target` prints a seat) puts every open question into **one** ask with `Skill(ask, "<the question> --to <that seat> [--reserved-for operator]")`. Questions that change intent (the goal, a non-goal, a constraint, a chapter's scope or its existence) are marked `--reserved-for operator`, in an ask of their own linked with `--related`, because a manager may not rule on direction. Factual and ordering questions go to the manager unreserved.
    *   **No parent and the operator demonstrably at this terminal** → `AskUserQuestion`, batched four per call. This is the only branch that calls it.
    *   **No parent and nobody watching, or you cannot tell** → one ask `--to operator`.
*   **The owners map.** Where the project publishes one, read it, so each chapter can propose an owner from its paths. In kit it is the "Ownership is fixed" line of `docs/LIVE_MARKET_DIRECT.md`, read from origin (kit `CLAUDE.md` § Owners gives the command). A project that publishes none leaves every Owner as an open question.
*   **The target project's handbook.** Read its `## Ticketing Strategy` and `## Boundaries` through `§CMD_READ_PROJECT_HANDBOOK`, as `/ticket` does: the Size dial decides chunk versus finding, and the boundaries decide which project a chapter belongs to. A missing handbook degrades in one line.

## The documents it writes

*   **The vision**: always `docs/<NAME>_VISION.md` in the repository whose work it plans (the operator's ruling DOCS). `<NAME>` is SCREAMING_SNAKE, from `--name` or the subject. Its shape is `assets/TEMPLATE_ENVISION_VISION.md`. `draft` and `revise` write only `_VISION.md` files.
*   **Existing `_DIRECT.md` visions are never renamed or moved**: `scripts/broadcast.sh` reads kit's `docs/LIVE_MARKET_DIRECT.md` as the seat owners map, and other pointers name those files by path. They stay where they are, under their names. **`reconcile` writes to any vision file, a `_DIRECT.md` included**, because those are the visions looms run against today: it adds the dated reconciliation section and the `**State (…)**` lines, and updates Ticket and Status where the chapter has those fields. An intent change to a `_DIRECT.md` goes to standalone `/direct`, never through `revise` here.
*   **The record**: `<host>/builds/<slug>_ENVISION.md` (beside the vision when there is no host). One block per pass: the action, the context read, every question asked with its lean, counter and falsifier, the ask's `<seat>/<id>` and app URL, and once answered, what was decided and what it was decided against. This is where a successor finds why a chapter reads the way it does.
*   **The topics**: `<host>/builds/<slug>_ENVISION_TOPICS.md`, written by `decompose` (below).

`<slug>` is the vision's NAME in kebab-case. Reuse it across every pass on the same vision, so the record and the topics cluster.

## The actions

Each action states what it reads, what it writes, and what it may not touch. `draft` and `revise` end with `decompose` unless the caller passes `--no-decompose`.

### draft

A new vision, from a subject and whatever context the caller names.

1.  **Read the context, never re-derive it.** Session paths, ticket keys, a groom topic file, a `/probe` or `/analyze` report, the owners map, the handbook. Write what each told you into the record, by path.
2.  **Write the whole draft on your own leans.** Fill every section of the template. Wherever a choice is still open (a boundary, a dependency edge, a chapter in or out, a split, an owner the map does not settle), write your lean into the document and mark that line **PROPOSED** with the fork id it waits on: `PROPOSED (fork SCOPEAUTH): <your lean>`. A chapter whose existence or scope is open has `**Status**: proposed`. Do not leave a field blank to wait for an answer; a blank cannot be reviewed and a lean can.
3.  **Size every chapter** by the project's Size dial: `chunk` (one landing arc, days not hours) may become a ticket; `finding` goes out as an inbox drop; `too big` is split here, in the draft, into chapters that are chunks. A chapter that cannot fill **Wrong today** with a file, row, output or behaviour that is wrong now is a guard or a plan item, not a chunk: `/ticket`'s Subject Gate would refuse it, so mark it `finding` or drop it and say which in the record.
4.  **Order the chapters.** Fill **Depends on**, then the dependency graph with its parallel groups and critical path; **Wave** is the parallel group number.
5.  **Ask once.** Put every PROPOSED fork into one ask, per § Where it runs, written to `/ask` § Writing one.
    *   **The opening** is a few sentences on what the vision is for, then the chapter list (slug, title, status, one line each), so the answerer sees what they are approving. The list is context; it does not explain any fork.
    *   **Under every fork heading, before its `Lean:` line, a paragraph of at least two sentences**: what is being decided and why it matters to the person answering. Show the line as it reads now, PROPOSED, and as each option would write it, in backticks. `engine ask new` refuses a fork whose own paragraph is shorter than twelve words, and for any fork after the first the opening paragraph does not count.
    *   **A choice** becomes `Choose one`, with `Lean:` and `Counter:` lines, and under each option a line saying what picking it changes and a `Cost:` line. **An open fact** becomes `Text`, with its own paragraph.
    *   **Row the ask** in the record. In a loom, the conductor also rows it in the log's `🗳️ Asks` block and opens a `🔓 Open claims` row for each chapter that waits on it; a lane leaves its `❓ Ask` heading instead and lets the conductor write both.
6.  **Keep working while it is open.** A chapter whose fork does not change its scope stays `ripe` and may be decomposed now. Only chapters whose open fork changes their scope wait, as `proposed`.
7.  **When the answer arrives**, run `revise` with the draft as its baseline.

### revise

The direction itself changes: the operator answered a fork, or asked for something different. It works on `_VISION.md` files only; an intent change to a `_DIRECT.md` is standalone `/direct`'s. **Gated**: an intent change lands only with an answered fork's record behind it (`¶INV_ENVISION_INTENT_NEEDS_AN_ANSWER`).

1.  **Baseline.** Read the current document and the answered ask (`engine ask read <seat>/<id>`, which stamps the read).
2.  **Apply each answer.** A PROPOSED line whose fork was answered becomes decided, rewritten to the answer where it differs from the lean, with its PROPOSED mark removed. Add the answer to the **Decisions** list: the fork, the choice, the ask id, and what it was decided against.
3.  **Leave what nobody answered.** An unanswered fork stays PROPOSED. **No answer is not a yes.** A fork answered in chat and nowhere else stays PROPOSED and is rowed `open — decided in chat, not yet recorded`.
4.  **A split** of a chapter is a revise: the parent chapter becomes `dropped` with a line naming its children, and each child is a new chapter with its own fields.
5.  **Never revise a reconciliation.** The dated `## 🔄 STATUS RECONCILIATION` sections and the `**State (…)**` lines record what happened; they are not offered for a decision and not rewritten here.
6.  **New forks** a revise opens go out as a new ask, per draft step 5.

### reconcile

A fact moved under the document: a thread landed, a chapter was re-scoped mid-build, a dependency was re-cut, a measurement was superseded. It runs on any vision file, `_VISION.md` or `_DIRECT.md`, with or without a host. **Ungated by construction**: it asks nothing, because gating a record of what already happened is how the record goes unwritten. This is the action the loom's Vision reconcile trigger runs (`Skill(envision, "reconcile <vision path> — <what moved>")`).

*   **It writes**: a dated `## 🔄 STATUS RECONCILIATION (YYYY-MM-DD)` section (append, or extend today's), each moved chapter's `**State (<date>, after <what>)**` line directly under its header line, and the chapter's **Ticket** and **Status** (a ticket filed, a thread in flight, a landing). A statement of fact corrected in place keeps its superseded wording in the reconciliation section. Each item is labelled measured, inferred or proposed, with who measured it.
*   **It may not write intent**: the Goal, Success Criteria, Non-Goals, Constraints, Decision Principles, a chapter's Goal, Acceptance signals or Not in scope, or the dependency graph. A reconciliation that would need one of those stops, writes the section with the open point stated, and hands that subject to `revise` through a new fork.
*   **It drains the register.** The log's registers are append-only blocks, rewritten whole, so a row closes when a fresh copy of the latest `📚 Docs owed` block is appended with that row reading `revised — <vision path> § <the section>`, or stating what leaves it open. The conductor writes that block: a lane running this action reports each row's new state in its hand-back, and the conductor appends the block.

### decompose

Emit the ripe chapters as loom work.

1.  Write `<host>/builds/<slug>_ENVISION_TOPICS.md` (beside the vision when there is no host) in `/groom`'s topic format (`skills/groom/assets/TEMPLATE_GROOM_TOPICS.md`; follow it rather than restating it here). One topic block per chapter whose Status is `ripe`:
    *   the topic's `[SLUG]` is the chapter's **Thread**, and its subject line is the chapter's **Plain terms**;
    *   its one member is the chapter: `leftover — <vision path> § <@area/slug>`, or a `ticket` member when the chapter already has a **Ticket**;
    *   **Ripe?** reads `yes — envisioned, answered forks <ids>`; **Dials read** names the Size dial;
    *   the **Decision fork** leans `graduate` when the chapter has no ticket and `dispatch as-is` when it has one, and names the chapter's **Owner** in **Unblocks**;
    *   the **Disposition** and **Dispatch** sections are left as placeholders for the loom.
2.  Chapters sized `finding` go in the same file under a heading `## Findings (inbox drops, not threads)`, one line each, for the loom's harvest round to drop through `/inbox-post`.
3.  Chapters still `proposed`, and chapters whose Owner is another seat, are listed under `## Not dispatched here`, each with its reason: `waits on fork <id>`, or `owner <seat> — a 📨 Seat handovers row`.
4.  **Then stop.** The conductor feeds each topic into its add-a-thread flow (`skills/loom/SKILL.md` § Adding a thread), where the mandatory steps still run: interrogation per the disposition, and the ticket-disposition ask, which is where a chapter becomes a ticket through `/ticket`. A topic is one thread (`¶INV_GROOM_ONE_TOPIC_ONE_THREAD` holds for these as for any groom topic). A chapter owned by another seat goes out as a `📨 Seat handovers` row with the chapter as its member link, never as a thread in this loom.

## The chapter, and where each field goes

The template carries the block. Each field has one named consumer, so a field nobody reads is a field to remove, not to fill.

*   **Thread** → the loom `threadId` (≤12 chars, `[A-Z0-9-]`, starting with a letter, never ending in a hyphen). It upgrades to the ticket key when one is filed.
*   **Ticket**, **Status** (`proposed · ripe · in flight · landed · dropped`) → the link to execution; `reconcile` keeps them current.
*   **Type**, **Plain terms**, **Goal**, **Wrong today**, **Acceptance signals**, **First step**, **Not in scope**, **Paths** → the `/ticket` drafter, by this mapping: Type → `type` (bug · feature · chore · tech-debt · spike); Plain terms → `plain-terms`, the ticket's first line; Wrong today → `premise/problem`, the instance its Subject Gate requires; Goal → `intent/why now`; Acceptance signals → `acceptance signals`; First step → `first step`; Not in scope → `non-goals`; Paths → `evidence/grounding`; the vision's Constraints section → `constraints`.
*   **Size** → the project's Size dial: `chunk`, `finding` or `too big — split`.
*   **Depends on**, **Wave** → the loom's dispatch order. A chapter whose dependency is unlanded waits for a later wave, or the conductor cuts it from that lane's head and rows `based on <threadId> @ <sha>`.
*   **Owner** → who runs it: this loom's seat becomes a thread here; another seat becomes a seat handover. It is a proposal read from the owners map, with the line it was read from.
*   **Paths** → the loom's slot claims (`engine loom-slots --claim`) and, under one shared tree, the file partition.
*   **Open questions** → the ask fork ids the chapter waits on, or `none`.

## Constraints

*   **`§INV_RIDE_NEVER_ACTIVATES`**: it rides the host and owns no session; with no host, `reconcile` and `decompose` run sessionless and `draft` and `revise` stop. **A host that finds this skill moving its phase stops and reports.**
*   **`¶INV_ENVISION_FILES_NO_TICKET`**: it files no ticket, posts no comment and opens no inbox drop. Chapters become tickets one at a time through the loom's ticket-disposition ask and `/ticket` (the operator's ruling DECOMP). **Why**: `/ticket` caps an agent at one ticket per run, and a vision that filed a ticket per chapter is the many-item plan becoming many tickets. If the operator wants every chapter filed at once, saying so is the human split ask that lifts `/ticket`'s cap, and the conductor runs it.
*   **`¶INV_ENVISION_PROPOSES_OWNERS_ONLY`**: an Owner is a proposal read from the project's ownership line; it never creates a lane, edits fleet config, or rules an ownership question (the operator's ruling PROPOSE). A chapter with no owner in the map carries the owner as an open question. **Why**: who owns which path is the operator's.
*   **`¶INV_ENVISION_INTENT_NEEDS_AN_ANSWER`**: an intent change lands only with an answered fork's record path behind it, and a reconciliation never asks. **Why**: the first is how a vision drifts from the person who owns it, the second is how the record of what happened goes unwritten. The two write surfaces are disjoint, which is what lets a reader tell a decided change from a recorded one.
*   **One ask per pass.** Every open question of a pass goes into one ask (two when some are reserved for the operator), never a question round at a terminal nobody watches.
*   **One home, no renames.** New visions are `docs/<NAME>_VISION.md`; existing `_DIRECT.md` files are never renamed or moved. `reconcile` may write facts into them; `draft` and `revise` never touch them.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file.
