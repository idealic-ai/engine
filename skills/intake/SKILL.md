---
name: intake
description: "A wave-based grooming pass over a Linear Project's feedback inbox: one session drains new inbox comments, organizes + consolidates them, triages each signal toward an outcome (graduate to a ticket, dispatch light triage, or marinate), then closes with a debrief — the next wave resumes from Linear. Reads incoming feedback; the paired /inbox-post writes it. A brief-writer / triage-orchestrator / cross-scope organizer, NEVER an executor. Triggers: \"run an intake pass\", \"groom the inbox\", \"intake wave\", \"triage the incoming feedback\", \"reorganize the hairball\", \"pre-ticket triage\", \"marinate this idea\"."
version: 2.0
tier: protocol
---

A wave-based inbox grooming pass: drain new feedback, organize + consolidate, triage each signal to an outcome, close with a debrief. The next wave resumes from Linear.

# /intake Protocol (The Curator)

Execute §CMD_EXECUTE_SKILL_PHASES.

### What /intake is (and is not)

*   **It is** a **wave-based grooming pass** over one initiative's Linear inbox: it drains the new feedback since the last watermark, builds a cross-scope understanding, **triages** each signal toward an outcome, and — only when an item is *ripe* and you confirm — graduates it into a tracked ticket. It reads incoming feedback; the paired **`/inbox-post`** is how feedback is written in. A wave ends; the next resumes from Linear.
*   **It is NOT** an executor. It never does the research, writes the code, or fixes the bug. It organizes, **triages** (light detail-gathering / repro / related-tickets, via dispatched sub-agents), and **hands off** context-rich briefs for others to execute (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`). Deep research happens on a *ticket*, not in the inbox.
*   **`/intake` vs `/direct`** (`¶INV_INTAKE_IS_BOTTOM_UP`): `/direct` designs a top-down vision — chapters and a plan — from a **known goal**. `/intake` accretes bottom-up from scattered feedback with **no goal yet**; the structure *emerges* from what marinates. Reach for `/direct` when you know the destination; `/intake` when you're still finding which thread to pull.

### State model — Linear is the source of truth (`¶INV_LINEAR_IS_TRUTH`)

*   **Linear tickets = the durable source of truth.** Feedback comes in and gets organized *for real* in Linear. Humans acting in Linear (dragging a milestone, closing an issue, replying) are always authoritative — the skill never overwrites human state.
*   **Durability is in Linear, not the session** — which is *why* /intake can be a bounded wave. Tickets, inbox reply-threads, and the drain watermark persist across sessions; a wave can end cleanly and the next resumes with nothing lost.
*   **The engine session doc = internal working context only.** It holds the agent's intermediate decision-making, the historical log of input, and the evolving cross-scope understanding, projected outward to the Linear Project *description + updates*. If the doc is lost, it is rebuildable from Linear (the `filed as FIN-XXX` reply-threads + tickets are the record).

### The Linear Project shape (one Project per initiative — with a real domain goal)

*   **The Project** has a **domain-specific goal** — a real initiative (e.g. "raise email-classification auto-approve rate without regressing safety"), **NOT "the inbox"** (`¶INV_PROJECT_HAS_A_DOMAIN_GOAL`). `/intake` figures this goal out via Setup interrogation and writes it as the Project's description/summary.
*   **Milestones** (seven — the full lifecycle, raw lead → terminal):
    *   **`Inboxes`** *(frozen — lead collectors)* — holds the inbox tickets (below) **plus** any existing tickets parked to gather input. Never active work; the skill **never files graduated tickets here**, only *reads* the threads here as feedback. Sub-issues coworkers create under an inbox ticket get **parked to `Uncategorized`** (`¶INV_INBOX_NOT_TICKETS`).
    *   **`Uncategorized`** — awaiting triage: a promoted ticket whose work-type isn't obvious yet, a ticket pulled from another project to consolidate here, **or a sub-issue parked out of `Inboxes`**. The anti-dumping-ground: visible, not lost.
    *   **`Needs decision`** — needs discussion/alignment → dispatch to `/brainstorm`.
    *   **`Needs research`** — needs investigation / root-cause / consolidation → `/analyze` `/research` `/experiment` `/probe`.
    *   **`Ready for action`** — clear problem + clear fix → `/ticket` `/implement`.
    *   **`Archived`** *(terminal)* — done/shipped work moved out of the active queue, so `Ready for action` stays a live picture of what's left. A record of what's been fixed.
    *   **`Cancelled`** *(terminal)* — rejected/abandoned **with the reason recorded** (bad idea / bad diagnosis / superseded / no longer relevant). Kept, not deleted — a dead-end memory so it isn't re-litigated (`¶INV_RESEARCH_MEMORY`). Consolidation *supersede* and *close* ops land here.
    *   *(Milestone names are the project's, teammate-facing — keep their descriptions human, no skill/engine jargon in Linear.)*
*   **The inbox tickets** — one or more **typed collection tickets under the `Inboxes` milestone**, chosen **per project** (`¶INV_INBOX_IS_TICKETS`). Each is a comment firehose for a *kind* of feedback; a dropper (via `/inbox-post`) picks the one matching what they're reporting. Strong default set: **Observed problems** (symptoms) · **Identified shortcomings** (diagnosed gaps) · **Feature requirements** (desired new behaviors) · **Potential solutions** (proposed fixes/mechanisms) · **Feedback & Transcripts** (raw longform source, chunked into the others) · **Researches & Fixtures** (human-ratified golden fixtures) · **Priorities & Deadlines** (the escape hatch on computed priority — deadlines, urgency, strategic weight the ranking can't see) · **Documentation** (docs missing / needed / wrong / stale, ours and product-facing alike — graduates to `/document`). Each channel's description carries **only** its own one-line what-belongs-here plus its `## Directions` (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`); the shared machinery lives once in the project's **Inbox Handbook** document (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`). A single comment may span channels — the organize pass splits and cross-links. All frozen, never closed, never worked. **The tickets ARE the inbox — the Project is not.**
*   **Research issue(s)** — living progress snapshots.
*   **Project Updates** — human-readable checkpoint reports, posted at Close.
*   **Item state lives as reply-threads on the origin Inbox comment** (`¶INV_TRIAGE_BEFORE_TICKET`): `candidate` (ripeness nomination) · `seems like FIN-…` / `seems like <cluster>` (dedup link) · `🔎 needs-triage` (+ handoff/report) → `👀 claimed by <who>` → `✅ result` (the triage handoff protocol) · `filed as FIN-XXX` (graduation backlink). Whenever one of these replies cites a **specific comment** (a `→` provenance source, a `seems like` sibling, a corroboration), deep-link it via `§FMT_TICKET_COMMENT_LINK` (never a bare comment id); ticket keys via `§FMT_TICKET_LINK`.

### The lifecycle — bounded waves (not an endless loop) (`¶INV_NO_RUSH_ITEMS_TO_CLOSURE`)

`/intake` runs as a **wave**: one session grooms one project's inbox from the watermark forward, drives each signal to an outcome, then **closes with a debrief**. The next `/intake` picks up from Linear + the advanced watermark. This is deliberate — durability lives in Linear, so a wave ends cleanly and loses nothing. The no-rush guarantee is **item-level**: a wave may end with items still marinating (recorded in Linear), and an item is **never force-promoted just because the wave is closing**. What ends is the session, not the initiative. Model: a grooming *pass*, not `/coordinate`'s immortal monitor.

### Session Parameters
```json
{
  "taskType": "INTAKE",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["intentReported", "sessionDir", "parametersParsed", "contextSourcesPresented", "filesLoaded"], "gate": false},
    {"label": "1", "name": "Ingest",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_LOG_SKILL_INVOCATION"],
      "proof": ["logEntries"]},
    {"label": "2", "name": "Scope & Worklist",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["logEntries"]},
    {"label": "3", "name": "Triage",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_LOG_SKILL_INVOCATION"],
      "proof": ["logEntries"]},
    {"label": "4", "name": "Digest",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["logEntries"]},
    {"label": "5", "name": "Outcomes",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_DISPATCH_APPROVAL", "§CMD_REFUSE_OFF_COURSE"],
      "proof": ["logEntries"]},
    {"label": "6", "name": "Discussion",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_REFUSE_OFF_COURSE", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["logEntries"]},
    {"label": "7", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "7.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "7.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "7.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "7.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/intake", "/probe", "/research", "/brainstorm", "/ticket"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_INTAKE_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_INTAKE.md"
}
```

---

## 0. Setup
*Resolve the initiative's Linear Project and load the working context. One wave = one project.*

§CMD_REPORT_INTENT:
> 0: Opening an intake wave for ___ initiative. Trigger: ___.
> Focus: resolve the Linear Project, load the working vision doc + watermark, assume the Curator role.
> Not: draining or triaging yet — setup only.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

**Assume the role** (`§CMD_ASSUME_ROLE`): You are **The Curator** — a patient organizer of scattered signal. You make sense of a hairball without forcing premature structure: hold ideas cheaply, notice what's connected, triage before ticketing, and resist filing a ticket before an item has earned it. You drive each wave to real outcomes, but you never rush an *item* to closure.

**Resolve the initiative & its Linear Project** (`¶INV_LINEAR_IS_TRUTH`, `¶INV_PROJECT_HAS_A_DOMAIN_GOAL`):
1.  **Identify the initiative** from the user's prompt. One initiative = one Linear Project = one wave.
2.  **Interrogate the domain goal** (`§CMD_INTERROGATE`, first run only): pin its **specific domain goal** before creating it — what problem it solves, what "better" means, in/out of scope. Draw on provided context. **Do NOT assume the goal from the name.**
    *   **Also ask about a Notion knowledge base** (`¶INV_NOTION_KNOWLEDGE_BASE`): an existing Notion page to observe/read/maintain, or create one? Link the page **and its subpages** into the Project description under a "Knowledge base" section.
3.  **Read the tracker config** from the project `CLAUDE.md` `## Tracker` section (team, issue prefix, URL) — never hardcode it. **Check for existing sibling projects first** — never silently spawn a duplicate.
4.  **First run** (no Project yet): with the user's confirm, bootstrap via the `linear-server` MCP —
    *   the **Project** — its description follows the **section schema** in `INTAKE_SYSTEM.md` (§ *The Project description*), which is the only place the sections are enumerated. Write the domain-goal prose and the mandatory **`## Ticketing Strategy`** section (canonical default verbatim from the catalog, `¶INV_TICKETING_STRATEGY_IN_PROJECT`); tell the user the three bullets are theirs to edit. Not a milestone re-description, not the vision prose.
    *   the seven **milestones** (`Inboxes` (frozen), `Uncategorized`, `Needs decision`, `Needs research`, `Ready for action`, `Archived` (terminal), `Cancelled` (terminal)) — each with a *prescribed, human-facing* description (`¶INV_TEAMMATE_FACING_LINEAR`).
    *   a companion **"Vision & Process" document** on the Project (`¶INV_VISION_IN_COMPANION_DOC`) — teammate-facing: why the system exists, the wave lifecycle, the constantly-cleaned state, how it's operated.
    *   the project's **Inbox Handbook** document (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`) — the shared machinery written ONCE: the 📋 report template, what-happens-next (incl. *"the triage that comes back is a draft"*), the other-intake-inboxes list, the generic triage recipe. Create it **before** the channels, so each channel can link to it.
    *   **the project's inbox tickets** — one or more *typed* channels under `Inboxes` (default: `Observed problems` / `Identified shortcomings` / `Feature requirements` / `Potential solutions` / `Feedback & Transcripts` / `Researches & Fixtures` / `Priorities & Deadlines` / `Documentation`). Each description stays **thin — readable in ten seconds**: a one-line *what belongs here*, a link to the Inbox Handbook, and a **`## Directions`** section (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`) — ask the user what this project is trying to achieve right now and write it there; leave it out rather than inventing one. **Never paste the machinery inline** — that is what the handbook is for.
    *   Record the Project ID + inbox ticket IDs + doc ID + the drain **watermark** (initially empty) in the working doc.
5.  **Subsequent run**: load the existing Project + inbox ticket IDs + the current watermark from the working doc.

**Load the working context**:
*   **Read the structure catalog FIRST** (`¶INV_STRUCTURE_CATALOG_IS_LOCAL`): `~/.claude/engine/skills/intake/INTAKE_SYSTEM.md` — the milestone catalog, the inbox-channel pattern, the wave operating guide. Read it on every invocation before touching the Project.
*   **Load the project's Directions** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`) — the per-project steer that this wave must respect. Read the `## Directions` section of the **Project description** (project-wide) and of **each inbox channel ticket's description** (per-channel). Precedence: **channel > project > skill default**. Absent = the skill's defaults apply; never fail, never invent one.
    *   Directions say *what this project is trying to achieve right now*, *what counts as ripe here*, and *what triage should chase or skip* — not mechanics (the skill holds those).
    *   Copy the loaded Directions verbatim into `INTAKE.md` §1 so every later phase and every dispatched sub-agent reads the same steer. If a channel's Directions changed since the last wave, say so in the log — a changed steer re-opens judgments made under the old one.
*   **Load the project's Ticketing Strategy** (`¶INV_TICKETING_STRATEGY_IN_PROJECT`) — read the `## Ticketing Strategy` section of the **Project description**. Project-level only: there is no channel override and no precedence chain, because how many tickets a project wants is a property of the project, not of the firehose an item arrived through.
    *   It answers the question *after* ripeness — given an item IS ripe, should it be its own ticket, folded into a parent, or left marinating. Applied as a distinct gate at Outcomes (Phase 5), not as a fifth ripeness criterion.
    *   Copy it verbatim into `INTAKE.md` §1, so Digest's consolidation runs with it in view and every dispatched sub-agent receives it.
    *   **Absent → warn once, then proceed on the catalog's canonical default**, and record *"Ticketing Strategy: default applied (none set on the project)"* in `INTAKE.md` §1 and the log. Never a silent fallback — a defaulted project must be visible as defaulted. Offer to write the section into the Project description at Outcomes, when the description is being synced anyway.
    *   **If it changed since the last wave, say so in the log and re-examine recent graduations.** A changed Direction re-opens pending judgment; a changed Ticketing Strategy re-opens already-filed tickets.
*   **Load the project's Stakeholders** — read the `## Stakeholders` section of the **Project description** and copy it into `INTAKE.md` §1. Optional: absent is a normal state and is **not** warned about (unlike Ticketing Strategy). They are *facts about people*, never assignment rules — so each phase draws its own inference: Triage carries the relevant names into a handoff prompt so a sub-agent that hits a question it cannot close knows **who to ask**; Outcomes infers a sensible assignee/reviewer on a graduated ticket and decides who a Project Update should reach. Inference only — the skill proposes, the human confirms; a Stakeholders line is never authority.
*   **Load the project's Inbox Handbook** (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`) — one `get_document` fetch of the shared machinery (report template · what-happens-next · other-inboxes · the generic triage recipe). Hold it for the wave: Phase 3 pastes the relevant part into every handoff prompt, since a sub-agent still cannot read the project. **One fetch replaces N copies** — do not re-read it per channel, and do not reconstruct it from a channel description.
    *   **Absent** (a project predating the handbook, or one whose channels still carry inline machinery): say so in the log and fall back to reading it off a channel description this wave. Then **offer to create the handbook and thin the channels** at Outcomes, when descriptions are being synced anyway — that is the migration path, taken one project at a time.
*   **Working vision doc** — `INTAKE.md` in the session dir (the `debriefTemplate`). If it exists, read it; if not, it is created on first Organize.
*   Pin the doc location: **the active session dir**. Linear is the durable record if the session is ever lost.

*Phase 0 always proceeds to Phase 1 — no transition question.*

---

## 1. Ingest — drain new signal since the watermark
*Read what's new. A wave opens by pulling the incoming feedback, cheaply, into the raw input log.*

§CMD_REPORT_INTENT:
> 1: Draining new inbox comments for ___ since the watermark. Reading incoming signal.
> Focus: pull only what's new via the drain subagent, into INTAKE_DRAIN.md; advance the watermark.
> Not: organizing or triaging yet.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

Ingest runs as a **background drain subagent**, never an inline fetch. Comment payloads are large — a single `Feedback & Transcripts` drop can be 30–40KB, and the MCP has no count-only/projection mode — so pulling them into the main loop floods context and can bust the per-call token ceiling. The subagent absorbs the fat bodies and hands back only a compact digest (proven: MCP works from a detached subagent; ~30× context reduction).

*   **The watermark is a single per-project ISO timestamp**, in the `Watermark:` field on the Inbox-tickets line of `INTAKE.md` (empty on a fresh project = drain everything). All inbox tickets drain together. The Linear MCP has **no server-side `since` filter** — the watermark is applied **client-side, inside the subagent**.
*   **Dispatch a drain subagent** (write the `§CMD_LOG_SKILL_INVOCATION` breadcrumb first) with the inbox ticket IDs + the current watermark + this contract:
    1.  Load the tool: `ToolSearch select:mcp__linear-server__list_comments`.
    2.  Per inbox ticket (+ any parked tickets under `Inboxes`): `list_comments(issueId, orderBy: createdAt, limit: 1)`, paging **one comment per call** via `cursor`. Order is newest-first, so **early-stop** once a comment's `createdAt` **<** the watermark — keep every comment with `createdAt` **>=** watermark (the boundary second is re-fetched on purpose, see step 4). **Guard**: if a page is NOT strictly descending by `createdAt`, do not early-stop — page to the end (early-stop assumes newest-first). **Retry once** on a transient MCP error (502s occur).
    3.  Exclude by **marker prefix, NOT by author** — all skill posts land under the operator's human Linear identity, so author can't distinguish them. Drop replies leading with `candidate` / `seems like …` / `→` (chunk-destination) / `🔎 needs-triage` / `👀 claimed` / `✅ result` / `filed as FIN-…` (`¶INV_EXCLUDE_OWN_COMMENTS` — every skill-authored reply MUST lead with one of these markers so the exclusion is complete). Also skip inline/description-anchored comments (`quotedText` != null) — they annotate the ticket description, not the firehose.
    4.  **Never filter on resolved state** (`¶INV_RESOLVE_ON_DISPOSITION`). A resolved thread means *dispositioned*, not *closed to input* — so a **new reply on a resolved thread is live signal** and must drain like any other. It arrives with its own `createdAt`, so the watermark catches it for free; the only way to lose it is to add a `resolved == false` filter. Don't. Surface such replies prominently in the digest — a reply on a dispositioned thread is usually someone correcting a triage the system got wrong, which is the highest-value drop there is.
    5.  **Dedup by comment id** against `INTAKE_DRAIN.md` (the `>=` boundary re-fetches watermark-second comments — drop any id already logged), then append each new kept comment (author · createdAt · id · full body) to `INTAKE_DRAIN.md` in the session dir — the raw input log.
    5.  Return ONLY a compact digest: per-ticket new-count, a one-line summary per comment, and the newest `createdAt` seen. **No bodies in the return.**
*   **After the digest returns**, advance the watermark in `INTAKE.md` to the **newest ingested `createdAt`** (`¶INV_WRITE_BEFORE_WATERMARK` — the raw items are already in `INTAKE_DRAIN.md`, so the doc-write precedes the watermark advance; a crash before this leaves the watermark un-advanced → safe re-drain). The **`>=` boundary** re-fetches any comment sharing the watermark's exact second next wave; **dedup by comment id** (step 4) drops those duplicates — so nothing at the boundary second is ever silently lost.
*   Also accept input dropped **directly in chat** (no subagent needed).
*   **Also pull the backlog's triage candidates into the wave's scope**: existing thin tickets — `Uncategorized` items and parked sub-issues that lack account/claim/repro. They join the new drops on the Phase 2 worklist so the wave enriches the backlog too, not just fresh signal.
*   **Empty drain**: if nothing is new, no chat input, and no thin backlog, the wave has nothing to groom — say so and offer to close (→ Phase 7) or wait.
*   Log the ingest (`§CMD_APPEND_LOG`): per-ticket count + new watermark + `INTAKE_DRAIN.md` pointer + backlog-candidate count.

---

## 2. Scope & Worklist
*Cheap, orchestrator-only: collapse obvious twins and decide WHAT needs triage — so Phase 3 doesn't fan out on duplicates or already-clear items.*

§CMD_REPORT_INTENT:
> 2: Scoping ___'s drained signal + backlog candidates. Quick dedup; building the triage worklist.
> Focus: collapse obvious twins, cluster loosely, mark each item needs-triage vs already-clear.
> Not: deep consolidation (that's Digest, Phase 4, after triage) or dispatching subagents yet.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

A **light** pass — no subagents, no DB. Just enough to avoid triaging the same thing five times and to size Phase 3.
*   **Assemble the wave's items**: the newly-drained inbox comments (`INTAKE_DRAIN.md`) **plus** the existing **triage-candidate tickets** pulled in Phase 1 (thin `Uncategorized` / parked sub-issues lacking account/claim/repro).
*   **Cheap dedup / loose cluster**: collapse obvious twins (same reporter+subject, or the same claim/id visible in the text) into one canonical; drop a `seems like <…>` reply on the echoes. Coarse only — the deep merge/supersede/connect happens in Digest (Phase 4) with triage data in hand.
*   **Apply the channel's Directions** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`) before marking anything. The Directions decide *what this project cares about right now* — an item the Directions call out is worth triaging even when it looks thin; an item they put out of scope is **parked with the Directions line cited as the reason** — never marked `already-clear`. Those are different states and must not be conflated: `already-clear` means *the gathering is done*, parked means *we chose not to gather, and here is the steer that said so*. Collapsing the second into the first erases the reason and makes the item look investigated. Cite the Directions line in the worklist row either way, so the call is auditable rather than a vibe.
*   **Build the triage worklist** — mark each unique item:
    *   `needs-triage` — missing the facts that make it ticketable (which account/claim, a repro, related tickets): a screenshot-only report, a vague symptom, a thin backlog ticket.
    *   `already-clear` — **a binary test on the reporter's own text, not a judgement about the item**: it already contains everything triage would go get — the account/org, the claim or entity id, and a repro (or a definitive "here is the exact thing"). Miss any one of those and it is `needs-triage`. What `already-clear` means is *"the gathering is done"*, never *"gathering wouldn't help"*.
        *   **Not** "I already know what this says." Authorship of a signal is not evidence about it (`§INV_CONFIDENCE_FROM_THE_CHECK`) — when the person triaging is the person who wrote the report, that is a reason to check **harder**, not a licence to skip. This is the single most common way the marker gets misapplied, because self-authored input feels maximally reliable and is minimally checkable.
        *   **Not** "no DB lookup would help." That is a far weaker test and it waves through every structural, design, or process signal unexamined — triage is not only a DB lookup.
        *   `already-clear` skips the Phase-3 **fan-out only**. It does NOT skip the related-tickets search — see Phase 3.
    *   `chat-drop` — dropped in chat with full context → skip the fan-out (the related-tickets search still runs).
*   Record the worklist in the working doc (item → status → why). Log the counts (`§CMD_APPEND_LOG`): N items · M needs-triage · K already-clear.
*   **Empty worklist** (nothing new, nothing thin): skip Phase 3 → Digest, or offer to close.

---

## 3. Triage — parallel enrichment of the worklist
*Fan out read-only `/inbox-triage` subagents, one per `needs-triage` item, to make thin signals ticketable. Triage ≠ research: light detail-gathering / repro / related-tickets, not deep root-causing.*

§CMD_REPORT_INTENT:
> 3: Triaging ___'s worklist — M /inbox-triage subagents in parallel.
> Focus: enrich each needs-triage item (account/claim/URL, repro, related tickets); post results back on the origin comment.
> Not: deep research (runs on a graduated Needs-research ticket) or deciding dispositions (that's Outcomes, Phase 5).

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

*   **The related-tickets search runs on EVERY item in the wave** — `needs-triage`, `already-clear` and `chat-drop` alike (`¶INV_RELATED_SEARCH_IS_UNCONDITIONAL`). It is the one triage step that applies regardless of project, domain, or how complete the report looks, and it is also the cheapest: tracker search only — no DB, no tunnel, no subagent needed. The fan-out covers it for `needs-triage` items; **sweep it orchestrator-side for everything that skipped the fan-out**, and record what it found (or "nothing") per item in the worklist. What it turns up — a duplicate, a cancelled precedent, a shipped fix, the ticket that already tried this and failed — changes a disposition more often than any other enrichment does, and unlike the rest of triage it cannot be recovered afterwards: the item graduates without it and nobody ever learns what was missed.
*   **Open the read-only tunnel ONCE for the wave** — `./scripts/staging-db-tunnel.sh` (background → `localhost:15432`), connect as **`data_ro`** (read-only by grant; see `/inbox-triage`'s Data-access section). All triage subagents **share this one tunnel** — do NOT open one per subagent (they connect to `:15432`; a second opener would fail to bind the port). Skip if the worklist has no `needs-triage` items. **The orchestrator owns the tunnel's lifecycle**: before opening, check `:15432` isn't already held (reuse a live one; kill a stale one); if it dies mid-fan-out, reopen and re-dispatch the affected items; **close it when the phase ends** — don't leave an orphan SSM session.
*   **Fan out in parallel, bounded** (~4–6 concurrent — cap the fan-out, queue the rest). Per `needs-triage` item: write a `§CMD_LOG_SKILL_INVOCATION` breadcrumb, then the **orchestrator authors + saves the handoff prompt** (`builds/inbox-triage-handoff-<origin-id>.md`, scaffold `assets/TEMPLATE_HANDOFF_PROMPT.md`) and dispatches an **`/inbox-triage`** sub-agent (else `/probe`) with it + the origin signal (body + screenshots) + known context + **the origin channel's `## Directions` verbatim** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS` — the sub-agent can't read the project, so the steer must travel in the prompt or it is silently lost). The sub-agent identifies account/org/claim/page-URL (read-only DB via the shared tunnel), pulls PostHog if sourced, attempts repro, finds related/duplicate tickets → a **triage report** (`builds/inbox-triage-<origin-id>.md`, per `/inbox-triage`'s `TEMPLATE_TRIAGE_REPORT.md`). `<origin-id>` = origin comment id or FIN-key, so concurrent triages never collide on filenames.
*   **Collect + post each result** on its origin comment (`¶INV_TRIAGE_BEFORE_TICKET`), as a **new reply per pass** (dated timeline): lead with the one-line **verdict** + **reproduce links** (app URLs for every entity); **attach BOTH** the report and the handoff prompt (comment-level: `prepare_attachment_upload(issue)` → `curl` PUT bytes to the 60s signed URL, **one file at a time** → embed the returned `assetUrl` in the reply via `save_comment`; do NOT `create_attachment_from_upload` — that makes it a *ticket* attachment). A short 1–4 line finding may go inline instead of attached. Enrichment **accretes** across waves until an item is ripe.
*   **Reply-based claim/return** — a doer (human or agent) claims with a `👀 claimed by <who>` reply and returns a `✅ result` reply. Reactions aren't MCP-addressable; state lives in replies. A dedicated doer-claim skill is deferred.
*   Enriched items flow into **Digest**; items whose triage didn't land this wave stay `needs-triage`, re-picked next wave.

---

## 4. Digest — organize & consolidate (with triage data in hand)
*Now that thin signals are enriched, turn the wave's items into clustered, deduped, connected understanding + the problem map.*

§CMD_REPORT_INTENT:
> 4: Digesting ___'s (triaged) signal. Finalize clusters, dedup/merge/supersede/connect, build the problem map.
> Focus: enriched items → deep clusters, dependency graph, root-cause map; refresh the working doc.
> Not: promoting or dispatching yet (that's Outcomes, Phase 5).

§CMD_EXECUTE_PHASE_STEPS(4.0.*)

Phase 2 already did the *coarse* pass (collapse obvious twins, size the triage worklist). This is the **deep** pass — finalize the clusters now that triage has enriched the items, then consolidate across the whole project. Build on Phase 2's dedup; don't re-litigate it.

**Organize:**
*   **Chunk longform source first** — comments on the `Feedback & Transcripts` channel are whole emails / transcripts / threads. Split each into the discrete observations, shortcomings, requirements, and solutions it contains before clustering, so one transcript can feed several channels. Reply on the source comment with the chunks' destinations (provenance stays on the raw source).
*   **Dedup / cluster** related items; when an item echoes an existing one, drop a `seems like <cluster/FIN-…>` reply on its origin comment.
*   **Classify** each cluster into a bucket: `conversational` (needs shaping) · `research` (needs investigation) · `action` (ready to build) — mapping to the milestone it would graduate to.
*   Update the **working vision doc** — the evolving cross-scope understanding.

**Consolidate — keep a constantly-cleaned state** (`¶INV_CONTINUOUS_CONSOLIDATION`; run every wave, and whenever new input lands — nothing rots):
*   **Dedup** — the same item twice → mark one `duplicateOf` the other; keep a single canonical.
*   **Merge** — several tickets are facets of one → fold into a canonical (others `duplicateOf` it), carrying context forward.
*   **Supersede** — a newer/better-framed ticket obsoletes older ones → mark the old superseded + closed, so the live framing wins.
*   **Connect** — the consolidation primitive: distinct symptoms sharing a root cause → a **parent "root-cause / solution" ticket** with the symptoms as **children** (+ `relatedTo` / `blocks`). This is how "tickets A–Y are all fixed by solution Z" becomes visible — fix the *path*, not each symptom.
*   Maintain a **root-cause map** in the working doc: symptom clusters → hypothesized root cause → candidate consolidating solution.
*   **Human confirms every destructive op** (merge / supersede / close) — `¶INV_TICKET_EARNED_BY_CONFIRM` + `¶INV_LINEAR_IS_TRUTH`. Non-destructive connects (related / parent-child) are proposed, then applied on confirm.

**The problem map — dependency graph + research memory** (the anti-relitigation core):
*   **Dependency graph** (`¶INV_PROBLEM_DEPENDENCY_GRAPH`) — nodes = problems / candidate solutions; edges = *stands-on*, *blocked-by*, *unlocks*, *needs-research-from*. Materialize edges as Linear relations (`blocks` / `blockedBy` / parent-child / `relatedTo`) **and** hold the readable graph in the working doc. Turns "clumps of legos" into a map where Z stands on X,Y and unlocks O — and the 20%-effort / 80%-win node becomes findable.
*   **Research memory** (`¶INV_RESEARCH_MEMORY`) — investigation against a problem accumulates ON the **ticket** (findings, dead-ends, why/when), never on a person or a dead session. No problem is attacked from zero twice.
*   **Enable the conjecture, don't manufacture it** — /intake assembles the decomposed, dependency-aware, non-lossy context so a human makes the creative leap to a solution cheaply and once. It never claims to auto-generate the solution.

---

## 5. Outcomes — prioritize, dispose, sync
*The productive climax. Rank the digested items, drive each to a disposition, project to Linear, and offer the wave's Project Update.*

§CMD_REPORT_INTENT:
> 5: Deciding outcomes for ___. Prioritize, then dispose each; sync + offer the update.
> Focus: every item gets a disposition — graduate to a ticket, keep enriching, park, or marinate; then project to Linear.
> Not: doing the downstream work itself — dispatching it with context.

§CMD_EXECUTE_PHASE_STEPS(5.0.*)

### Prioritize first (`¶INV_TWO_LEVEL_PRIORITY`, `¶INV_RANKING_WITH_PROOFS`)
*   **Intake-internal** — rank so the highest-leverage items are disposed first. Impact = **consolidation breadth** (a parent resolving N symptoms) + **non-self corroboration** (distinct reporters) + **blast-radius** (orgs/claims/users hit — the triage reports quantify this); effort coarse (S/M/L). Cite **proof-pointers** (comments / tickets / triage-report findings behind each).
*   **Output** — the durable ranking that guides doers: set the Linear **priority field** on graduated tickets AND keep a ranked "pull this first, and why, with proofs" list in the working doc → the Project Update.

### Disposition each item (per-item; human confirms — `¶INV_TICKET_EARNED_BY_CONFIRM`)
Apply the **recorded binary ripeness checklist** (`¶INV_RIPENESS_IS_A_RECORDED_CHECKLIST`) — ripe only when ALL: [ ] crisp one-sentence problem · [ ] defined next-action · [ ] brief type assigned · [ ] ≥1 *non-self* corroboration (the skill's own replies don't count). Record the result.

**The checklist is project-configurable** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`): the four above are the *default*. A channel's or project's `## Directions` may add a criterion (e.g. "a fixture needs the corrected answer plus its evidence"), relax one (e.g. "a lone cross-cutting conjecture is ripe without corroboration — route it to Needs research"), or reprioritize what counts as a crisp problem here. Record the checklist **as actually applied**, naming which items came from Directions — a silently-swapped gate is unauditable. Directions may never remove the human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`).

**Then the chunkiness gate** (`¶INV_TICKETING_STRATEGY_IN_PROJECT`) — a **separate** call, run only on items that passed ripeness. Ripeness asked *"is this well-formed enough to be a ticket?"*; this asks *"should it be its OWN ticket?"* Apply the project's `## Ticketing Strategy` (loaded at Setup; the catalog default if the project has none, in which case say so) and answer:

*   **Its own ticket** — it clears Volume, Size and Substance as that project defines them. Graduate.
*   **Fold into a parent** — real, but a facet of something already tracked or of a root cause. Use Phase 4's existing machinery (`relatedTo` / parent-child / merge) rather than filing a sibling; carry its context onto the parent so nothing is lost. This is how chunkiness is actually achieved — the gate names the call, Digest performs it.
*   **Keep marinating** — real but not yet a chunk worth tracking on its own.

**Record the call as applied**, next to the ripeness checklist: which of the three bullets decided it, and — when the project had no section — that the default was used. A silently-applied volume policy is as unauditable as a silently-swapped ripeness gate. The strategy steers the judgment; it never removes the human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`), and it is never a reason to discard an item — "not its own ticket" always means folded or marinating, never dropped.

Then exactly one disposition:

1.  **Graduate → ticket** (ripe, type obvious): **file it via `/ticket` — never hand-write the body** (`¶INV_GRADUATION_VIA_TICKET`). Invoke `/ticket` with a **caller-pinned placement**: the project + the work-type **milestone** (`Needs decision` / `Needs research` / `Ready for action` / `Quick wins`), else `Uncategorized`, and **new issue, never a sub-issue** — the parent `/ticket` would otherwise detect is the frozen inbox collector the signal arrived on, and a sub-issue there gets parked straight back out (`§INV_INBOX_NOT_TICKETS`). **Never `Inboxes`.**
    *   **`/ticket` owns the body**, and that is the whole point of routing through it: the plain-terms opening line, premise-first sections, non-goals, acceptance signals, the **spike escape-hatch** for a research item with no honest acceptance criteria yet, and — the one that matters most to a wave — **conservative single-ticket-by-default decomposition that never inflates the count.** A wave that hand-writes bodies produces essays only their author can read, and more of them than the work justifies.
    *   **What /intake keeps** (graduation semantics `/ticket` knows nothing about): the **recorded ripeness checklist** as actually applied, the **priority from this wave's ranking**, **idempotency** (`¶INV_IDEMPOTENT_PROMOTION` — pre-write key so a crash never double-files), the **`filed as FIN-XXX` reply** on the origin comment, and recording `FIN-XXX` in the working doc.
    *   **Correcting a ticket a wave filed** — this wave or an earlier one — goes through **`/snapshot`**'s description-drift flow, **never a freehand overwrite**: an evergreen body carrying every prior `## Change history` entry verbatim plus one new dated line, with the description **re-read immediately before** the full-field replace. Two reasons it isn't optional: a wave that overwrites a description it filed earlier can silently clobber a human's edit, and a body that accumulates correction blocks forces every future reader to reconstruct what is currently true. Routine progress is a comment, not a rewrite.
2.  **Graduate → Needs-research ticket**: items needing deep work — same `/ticket` route as (1) with the milestone pinned to `Needs research`, and carry the accumulated triage/research memory onto the ticket. If the item has no honest acceptance criteria yet, let `/ticket`'s **spike** type do its job rather than inventing criteria to fill the form. (Deep research runs on the ticket, not the inbox.)
3.  **Keep enriching** (triage ran but the item's still thin, or its triage didn't land this wave): leave it `needs-triage` — Phase 3 re-picks it next wave; the accreted `✅ result` replies stay on the comment. **Bound it**: if triage has failed to make it ticketable across a few waves, stop churning — reply asking the reporter for the missing detail, or marinate it with the gap recorded. Don't loop `needs-triage` forever.
4.  **Marinate** (not ripe, nothing more to gather): leave it (`¶INV_NO_RUSH_ITEMS_TO_CLOSURE`); record *why* in the doc.
5.  **Park sub-issues** (`¶INV_INBOX_NOT_TICKETS`): issues parented under a frozen inbox channel ticket → propose **reparenting each to `Uncategorized`** (confirm each — someone else's ticket). Keeps `Inboxes` frozen-collectors-only.

### Resolve the origin thread when the signal LEAVES the inbox (`¶INV_RESOLVE_ON_DISPOSITION`)

An **unresolved** comment thread means *"this signal still needs something from the intake pass."* So resolve it exactly when that stops being true — after the pointer reply is posted, never before:

*   **Filed as a ticket** → resolve (the `filed as FIN-XXX` reply carries the pointer).
*   **Folded into a parent** → resolve (reply names the parent).
*   **Closed as outdated / incorrect / superseded / not-a-problem** → resolve, with the reason in the reply.

**Do NOT resolve** while it is still intake's problem: `needs-triage`, marinating, or parked against a Direction. Those are live signal awaiting a disposition, and burying them is exactly the loss this system exists to prevent.

**Never resolve on ticket-DONE.** The ticket owns the work's lifecycle; the comment owns the *signal's*. Mirroring done-ness back into the inbox creates two sources of truth for one fact (`¶INV_LINEAR_IS_TRUTH`), and threads would sit open for months — defeating the archiving entirely.

**A reply on a resolved thread un-resolves it** and re-enters the next drain. Resolution means *dispositioned*, never *closed to further input* — otherwise it silently revokes the promise every channel now makes: *"the triage that comes back is a draft… reply on your own comment."*

**Mechanism**: `engine ticket resolve-comment <commentId>` (the Linear **MCP exposes no comment-resolve mutation** — only `resolve_diff_thread`, which is for diff reviews; the CLI reaches the GraphQL API directly, mirroring `ticket-search.sh` / `project.sh`). If that command is not available yet, **say so and ask the human to resolve** — do not silently skip it, and do not claim it was done.

### Sync + offer the Project Update
*   **Sync the state** (`¶INV_LINEAR_IS_TRUTH`, one-way doc→Linear, skill-derived framing only; never overwrite human-owned state): refresh the **Project description** with the current cross-scope understanding + the ranked "where to start" read.
*   **Offer the Project Update** (`¶INV_TEAMMATE_FACING_LINEAR`) — the wave's team-facing checkpoint (what was *triaged / filed / handed off / parked* this wave, what's *marinating*, honest counts incl. nomination-rejections + staleness). **Offered / confirmed, never auto-posted.** If the user declines here, it's re-offered on-demand in Discussion (Phase 6) and backstopped at Close (Phase 7) — no wave closes without a checkpoint.
*   **Announce the completed wave in Slack** (`§PASS_HEARTBEAT` — makes a run *visible where the team already looks*): the moment the Project Update is actually posted, emit a **one-shot** alert via `engine slack-post` so a completed pass is loud and a *skipped* one shows up as a gap. Compose the message from the update just posted — its headline + the ranked "pull first" + the honest counts — plus the **latest watermark** and a **"previous pass ran `<date>` (`<N>`d ago)"** line (read the prior Project Update's timestamp via `get_status_updates`; that gap line is the silence-made-legible signal, no cron). **Fire exactly once per posted update** — if you announced at Outcomes, do NOT re-announce at the Close backstop. Best-effort: a missing token/channel or a Slack error is logged and **never blocks the wave's Close**. Setup + env vars: `§PASS_HEARTBEAT` in `INTAKE_SYSTEM.md`.

**Off-protocol input** (e.g., "just go fix this bug") → route via `§CMD_REFUSE_OFF_COURSE`: /intake dispatches context-rich briefs, it does not execute. Offer to graduate-and-hand-off instead.

---

## 6. Discussion (held — optional)
*Keep the context alive: dig into clusters, ranking, or dispositions before closing. Close is always on the table.*

§CMD_REPORT_INTENT:
> 6: Holding open for discussion on ___. Digging into clusters / ranking / dispositions on demand.
> Focus: let the user interrogate the wave's outcomes; adjust dispositions; keep context without forcing closure.
> Not: rushing to close — but Close is always offered, never hidden.

§CMD_EXECUTE_PHASE_STEPS(6.0.*)

A bounded held loop. The wave's productive pass (1→5) is done; now the user may dig in. The earlier **actions remain callable inline** here — drop more input (re-drain), re-scope, re-triage an item, re-cluster, re-rank, adjust a disposition — without a formal backward phase jump. This phase is **optional**: if there's nothing to discuss, offer Close immediately and move on.

After any action, re-present the ready state via `AskUserQuestion` (multiSelect: false):
> "Wave for `<initiative>` — what next?"
> - **"Discuss / adjust an outcome"** — dig into a cluster, ranking, or disposition.
> - **"Drop more input"** — re-ingest / re-scope / re-triage whatever's new (re-runs the relevant phases inline).
> - **"Re-rank priorities"** — refresh the ranked "pull first" view.
> - **"Post / refresh the Project Update"** — the on-demand team checkpoint, if you skipped it at Outcomes.
> - **"Close the wave"** — final sync + debrief → Phase 7.

Unlike the old endless loop, **Close is a first-class, always-visible option** — no rush to close an item, but no pretense of an immortal session either (`¶INV_NO_RUSH_ITEMS_TO_CLOSURE`). If the user goes quiet, wait; don't nag toward closing.

---

## 7. Synthesis — final sync, debrief, close the wave
*Project the wave's understanding to Linear, debrief it as durable record, hand off to the next wave.*

§CMD_REPORT_INTENT:
> 7: Closing the ___ wave. ___ triaged, ___ filed, ___ handed off, ___ marinating.
> Focus: final Linear sync + Project Update, debrief the working vision, confirm watermark advanced, clean handoff.
> Not: abandoning the initiative — the next /intake resumes from Linear.

**Final Sync & Report** — run this **FIRST**, before `§CMD_EXECUTE_PHASE_STEPS` below launches the synthesis pipeline (which ends in `§CMD_CLOSE_SESSION` — do it after and it never runs). One-way doc→Linear, skill-derived framing only; never overwrite human-owned state (`¶INV_LINEAR_IS_TRUTH`):
*   Refresh the **Project description** with the current cross-scope understanding + the ranked "where to start" read.
*   Post a **Project Update** — **the backstop**: if it wasn't already posted at Outcomes (Phase 5) or in Discussion, post it now so no wave closes without a team-facing checkpoint (what was *triaged / filed / handed off / parked* this wave, what's *marinating*, honest counts incl. nomination-rejections + staleness — rot visible, not just flattering volume). Offered/confirmed as always. **If this backstop is where the update finally posts, fire the `§PASS_HEARTBEAT` Slack announce here** (once — skip if already announced at Outcomes).
*   Refresh the **Research snapshot issue** if research threads advanced.
*   Confirm the **watermark** in `INTAKE.md` is advanced to this wave's newest ingested `createdAt`.

§CMD_EXECUTE_PHASE_STEPS(7.0.*)

**Debrief notes** (for `INTAKE.md`): fill every section — the working vision doc IS the debrief (cross-scope understanding, item registry with ripeness/triage state, ranked priorities, dependency graph + root-cause map, Linear pointer, what's marinating vs handed-off vs filed this wave).

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Wave complete. Walk through the current vision + open threads?"
  debriefFile: "INTAKE.md"
```

**Post-Close**: if the user keeps dropping input after close, obey `§CMD_RESUME_AFTER_CLOSE` — reactivate and start a fresh pass (or resume the wave). Closing was the end of a wave, not the initiative.

---

## Critical Invariants (this skill)

*   **¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES**: /intake organizes, triages, and hands off context-rich briefs; it never does the downstream research/build/fix. "Dispatch" means posting a self-contained handoff (prompt in `builds/`, attached), not a bare tag.
*   **¶INV_NO_RUSH_ITEMS_TO_CLOSURE**: The guarantee is item-level — an item is never force-promoted just because a wave is closing; unripe items marinate in Linear across waves. The **session** is a bounded wave that ends cleanly (durability is in Linear, not the session). Supersedes the former no-rush-to-closure (which conflated item-ripeness with session-immortality).
*   **¶INV_RELATED_SEARCH_IS_UNCONDITIONAL**: The related-tickets search runs on every item in the wave, whatever its worklist marker. `already-clear` and `chat-drop` exempt an item from the triage **fan-out**, never from this search. It is the only triage step that is project- and domain-independent, it is the cheapest (tracker search — no DB, no tunnel, no subagent), and it is the only one whose omission is unrecoverable: an item that graduates without it carries no record of what wasn't looked for. Record the result per item — including "nothing found" — so the search is auditable rather than assumed. Captured from a real wave that skipped it on 11 of 15 items and filed three tickets missing five relevant existing ones, including a cancelled precedent that was the strongest available argument for one of them.
*   **¶INV_GRADUATION_VIA_TICKET**: A wave never hand-writes a ticket body. Graduation goes through **`/ticket`** with a caller-pinned placement (project + work-type milestone + new-issue-never-sub-issue); corrections to an already-filed ticket go through **`/snapshot`**'s description-drift flow. /intake keeps only what those skills don't know about: the recorded ripeness checklist, the priority from the wave's ranking, the idempotent pre-write key, and the `filed as FIN-XXX` origin reply. **Reason**: `/ticket` already holds the drafting discipline a wave needs and would otherwise reinvent worse — premise-not-algorithm, plain-terms opener, non-goals, acceptance signals, a spike escape-hatch for research with no honest acceptance criteria, and conservative single-ticket-by-default decomposition. `/snapshot` already holds the correction discipline — evergreen body, append-only `## Change history`, re-read before a full-field replace. Captured from a wave that hand-filed six tickets: they read as essays comprehensible only to whoever sat through the source review, two of the six should never have been tickets at all, and four descriptions were freehand-overwritten with no history line and no re-read guard. Every one of those failures is something the two existing skills prevent by construction.
*   **¶INV_TRIAGE_BEFORE_TICKET**: Not-ready signals get light **triage** in-thread (orchestrator-dispatched sub-agents gather detail / repro / related-tickets) before they earn a ticket — not a premature ticket. Triage ≠ research: triage makes a signal ticketable; deep research runs on a graduated `Needs research` ticket.
*   **¶INV_INBOX_NOT_TICKETS**: Inbox items keep their own lightweight format (the channel reporter templates) — do not reimplement tickets inside comment threads. Sub-issues coworkers create under a frozen inbox channel ticket are parked to `Uncategorized` (confirm each), keeping `Inboxes` frozen-collectors-only.
*   **¶INV_TWO_LEVEL_PRIORITY**: Priority operates at two levels — intake-internal (which signals a wave triages first) and output (the durable ranking that guides doers: the Linear priority field on tickets + a ranked "pull first, why, with proofs" narrative in the Project Update). Same impact model (consolidation breadth + non-self corroboration + blast-radius).
*   **¶INV_LINEAR_IS_TRUTH**: Linear tickets are the source of truth; humans acting in Linear are authoritative. The doc is a working projection synced one-way to Linear, never overwriting human-owned state.
*   **¶INV_INTAKE_IS_BOTTOM_UP**: /intake accretes bottom-up with no goal yet (vs /direct's top-down vision from a known goal).
*   **¶INV_PROJECT_HAS_A_DOMAIN_GOAL**: The Linear Project is a real initiative with a specific domain goal, interrogated at Setup — never assumed from a name, and never "the inbox" itself.
*   **¶INV_INBOX_IS_TICKETS**: The feedback inbox is one or more *typed* tickets under the `Inboxes` milestone — each a comment firehose for a kind of feedback, chosen contextually per project (default: Observed problems / Identified shortcomings / Feature requirements / Potential solutions / Feedback & Transcripts / Researches & Fixtures / Priorities & Deadlines / Documentation). Each channel's description carries **only** that channel's `## Directions` + a one-line what-belongs-here + a link to the project's Inbox Handbook, where the shared machinery lives once (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`). The Project is not the inbox.
*   **¶INV_CONTINUOUS_CONSOLIDATION**: Always on the lookout to **merge / dedup / supersede / connect** tickets, maintaining a constantly-cleaned state (never a dumping ground). Cross-cutting symptoms consolidate into a single higher-leverage parent ("solution Z") — fix the path, not each symptom; consolidation breadth feeds the ranking. Destructive ops require human confirm.
*   **¶INV_TEAMMATE_FACING_LINEAR**: Linear content teammates read (Project + milestone descriptions, ticket bodies, inbox replies) stays human/domain-facing — no engine/skill jargon. The engine vocabulary lives in the working doc.
*   **¶INV_VISION_IN_COMPANION_DOC**: The vision / process / philosophy lives in a teammate-facing "Vision & Process" companion doc on the Project — not the lean Project description, not duplicated in the skill.
*   **¶INV_STRUCTURE_CATALOG_IS_LOCAL**: The canonical structure catalog + wave operating guide lives in `INTAKE_SYSTEM.md` next to the skill, read on every invocation.
*   **¶INV_NOTION_KNOWLEDGE_BASE**: The skill links, writes, and maintains related non-technical Notion pages as a user knowledge base. At project creation, ask whether one exists to observe/manage or should be created; link page + subpages from the Project description; keep it current.
*   **¶INV_TICKET_EARNED_BY_CONFIRM**: No Linear ticket is created (and no destructive consolidation op / sub-issue reparent) without an explicit per-item human confirm.
*   **¶INV_RIPENESS_IS_A_RECORDED_CHECKLIST**: Ripeness is a recorded binary checklist (crisp problem · defined next-action · brief type · enough non-self corroboration), not a vibe. The four are the *default* — a project's Directions may modify them (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`); record the checklist **as applied**, naming which items came from Directions.
*   **¶INV_DIRECTIONS_IN_DESCRIPTIONS**: A project's steer — what it's chasing now, what counts as ripe here, what triage should chase or skip — lives in a `## Directions` section of the **inbox channel ticket descriptions** (per-channel) and optionally the **Project description** (project-wide). Not in a separate doc: the steer belongs where the drop happens, a human edits it in place, and the skill already holds every mechanic so Directions need only say *what to achieve*. Precedence **channel > project > skill default**; absent = defaults, never fail, never invent one. They are loaded at Setup, applied to the Phase-2 triage call (citing the line), passed **verbatim into every triage handoff prompt** (a sub-agent can't read the project — an unpassed steer is a lost steer), and may modify the ripeness checklist. They steer judgment; they never grant authority — no Direction removes a human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`).
*   **¶INV_TICKETING_STRATEGY_IN_PROJECT**: Every intake project's **Project description** carries a `## Ticketing Strategy` section — how much ticketing that project wants, as three independently-dialable bullets (**Volume** how many we want at all · **Size** how big one should be · **Substance** what makes one worth existing). It is deliberately **not** a variant of `¶INV_DIRECTIONS_IN_DESCRIPTIONS`: it is **mandatory**, it is **Project-level only** with no channel override and no precedence chain (how many tickets a project wants is a property of the project, not of the firehose an item arrived through), and **absence is loud** — warn once per wave, proceed on the catalog's canonical default, and record *"default applied"*; never a silent fallback. It gates a different axis from ripeness: ripeness asks *is this well-formed enough to be a ticket*, this asks *should it be its OWN ticket* — so it is a **distinct gate at Outcomes** run after ripeness passes, never a fifth ripeness criterion. Its outcomes are own-ticket / fold-into-a-parent / keep-marinating — **never discard**. Loaded at Setup, held in view during Digest's consolidation, carried **verbatim into every triage handoff prompt in its own block** (the sub-agent's "ripe → which milestone" recommendation is a graduation-volume call made by an agent that cannot read the project), and **recorded as applied** naming which bullet decided it. A changed Direction re-opens pending judgment; a changed Ticketing Strategy re-opens **already-filed tickets** — say so and re-examine recent graduations. It steers judgment; it never removes the human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`). The canonical default text and the Project-description section schema both live in `INTAKE_SYSTEM.md`.
*   **¶INV_CHANNEL_MACHINERY_IN_ONE_DOC**: A channel description carries **only its own steer** — a one-line *what belongs here*, its `## Directions`, and a link. All **shared machinery** (📋 report template · what-happens-next incl. the draft/correction affordance · the other-intake-inboxes list · the generic triage recipe) lives **once per project, in the Inbox Handbook document** — a Linear *Document*, not an attachment, because a Document is human-editable in place, linkable, and agent-readable via `get_document`. Setup loads it once and holds it; Triage pastes the relevant part into each handoff (a sub-agent cannot read the project); `/inbox-post` and `/inbox-triage` read it when standalone. **Never paste machinery inline on a channel**, and never reconstruct the handbook from a channel description. Rationale is measured, not theoretical: propagating one sentence across the channel set cost **35 writes**, and the duplicated channel list had already drifted (`/inbox-post` documented "6 channels" while 7 existed) — duplication does not merely cost effort, it silently goes stale. Accepted tradeoff: a dropper sees a pointer where a template used to be — right for machinery, wrong for steer, which is where the split runs.
*   **¶INV_RESOLVE_ON_DISPOSITION**: Resolve an origin comment thread exactly when the signal **leaves the inbox** — filed as a ticket, folded into a parent, or closed as outdated/incorrect/superseded — always *after* the pointer reply is posted. **Never on ticket-done**: the ticket owns the work's lifecycle, the comment owns the signal's, and mirroring done-ness back would create two sources of truth for one fact (`¶INV_LINEAR_IS_TRUTH`) with threads open for months. **Never** while it is still intake's problem (`needs-triage`, marinating, parked). **A reply on a resolved thread un-resolves it** and re-enters the next drain — resolution means *dispositioned*, never *closed to further input*, or it silently revokes the promise every channel makes that triage is a draft you can correct. Mechanism is `engine ticket resolve-comment` against the GraphQL API: the **Linear MCP exposes no comment-resolve mutation** (`resolve_diff_thread` is diff-review only). Absent that command, ask the human — never skip silently, never claim it was done.
*   **¶INV_EXCLUDE_OWN_COMMENTS**: The skill's own reply-threads are excluded from ingestion AND from the ripeness corroboration count — identified by their **marker prefix**, not by author (all skill posts land under the operator's human Linear identity, so author can't distinguish them). Every skill-authored reply MUST lead with a recognized marker (`candidate` / `seems like …` / `→` / `🔎 needs-triage` / `👀 claimed` / `✅ result` / `filed as FIN-…`) so the exclusion is complete.
*   **¶INV_WRITE_BEFORE_WATERMARK**: Write drained items to `INTAKE_DRAIN.md` before advancing the watermark, so a mid-drain crash never silently loses feedback.
*   **¶INV_IDEMPOTENT_PROMOTION**: File-then-annotate carries a pre-write key so a crash never double-files a twin ticket.
*   **¶INV_RANKING_WITH_PROOFS**: The "pull this first, and why, with evidence" ranked view is a **required step in Outcomes (Phase 5)** — no longer a reserved seam. The agent ranks by the impact model (consolidation breadth + non-self corroboration + blast-radius) with proof-pointers; it is a prescribed action, not an automated/mechanical feature.
*   **¶INV_PROBLEM_DEPENDENCY_GRAPH**: The problem map is a dependency graph (nodes = problems/solutions; edges = stands-on / blocked-by / unlocks / needs-research-from), materialized as Linear relations + held readably in the working doc — so decomposition and the high-leverage sub-problem are visible.
*   **¶INV_RESEARCH_MEMORY**: Investigation done against a problem accumulates ON the problem (its ticket) — findings, dead-ends, why/when — never lost to a person or a dead session; no problem is attacked from zero twice. The system *enables* the conjecture, it never claims to *generate* it.
