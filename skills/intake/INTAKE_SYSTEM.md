# The Intake System — Structure Catalog & Operating Guide

**Read this on every `/intake` invocation.** It is the canonical reference for how an intake Project is structured and how the agent operates it. The `SKILL.md` defines the *protocol* (phases); this defines the *structure and the why*. Per-project specifics (the Project's goal, its IDs, its current understanding) live in the session working doc (`INTAKE.md`) and in Linear — this file is the general, project-agnostic spec.

---

## What the intake system is

A **pre-ticket layer** where scattered feedback is gathered, organized, consolidated, and — only when ripe and a human confirms — promoted into tracked tickets. It exists because the queue is past the point a human can hold in their head: raw feedback gets lost if not acted on immediately, and cross-cutting root causes ("tickets A…Y are all one problem") never surface. One **Linear Project per initiative** is the durable home; **Linear is the source of truth**, the session doc is the agent's working understanding projected onto it.

---

## Structure catalog

### Milestones (the lifecycle — stages of understanding, named for what blocks an item)

Create these seven on every intake Project, with these **prescribed, teammate-facing descriptions** (no engine/skill jargon on the board — `¶INV_TEAMMATE_FACING_LINEAR`):

1. **Inboxes** *(frozen — lead collectors)*
   - **Goal**: collect signal, never track work.
   - **Description**: "Frozen lead-collectors — never worked. The Inbox ticket (where raw feedback arrives as comments) and any ticket parked here to gather input live here. Work is never tracked in this milestone; it exists purely to collect signal that becomes tickets elsewhere. Tickets here do not 'progress' — they spawn new tickets in the other milestones."
   - **Entry**: the Inbox ticket; existing tickets a human parks here for input. **Exit**: none — feedback here *spawns* new tickets elsewhere.

2. **Uncategorized**
   - **Goal**: hold a real-but-unsorted ticket visibly, never lost — the anti-dumping-ground.
   - **Description**: "Captured, awaiting triage — visible, never lost. A ticket whose work-type isn't decided yet: either freshly promoted from the inbox, or brought in from another project to consolidate here. It waits until it's sorted into Needs decision, Needs research, or Ready for action — nothing should linger."
   - **Entry**: a promotion whose work-type wasn't obvious, **or a ticket pulled in from another project for consolidation**. **Exit**: → Needs decision / Needs research / Ready for action.

3. **Needs decision**
   - **Goal**: surface items blocked on a human call, not on facts.
   - **Description**: "Blocked on a decision, not on information. The path forward needs a human call — an open question, a trade-off, an alignment between people — rather than more digging. Once the decision is made it moves to Needs research (if it surfaced unknowns) or Ready for action (if it unblocked a clear fix)."
   - **Exit**: → Needs research or Ready for action, or closed.

4. **Needs research**
   - **Goal**: items blocked on understanding — including consolidation (one solution behind many symptoms).
   - **Description**: "Blocked on understanding, not on a decision. Needs investigation, reproduction, or root-causing — including finding the one solution that resolves several related symptoms (consolidation). Moves to Ready for action once the cause and the right fix are known, or to Needs decision if the research surfaced a choice."
   - **Exit**: → Ready for action or Needs decision, or closed.

5. **Ready for action**
   - **Goal**: nothing blocks it but the doing.
   - **Description**: "Nothing blocks it but the doing. Clear problem, clear fix, no open questions or unknowns left — ready to be built or handed to implementation as-is."
   - **Exit**: → `Archived` once built (or reassigned to the project that owns the work).

6. **Archived** *(terminal)*
   - **Goal**: keep `Ready for action` a live queue, not a graveyard.
   - **Description**: "Done and archived — shipped or resolved work, moved out of the active queue so Ready for action stays a live picture of what's still left. A record of what's been fixed."
   - **Entry**: a `Ready for action` ticket whose work shipped. **Exit**: none (terminal).

7. **Cancelled** *(terminal)*
   - **Goal**: preserve rejected ideas *with their reason* — a dead-end memory, not a deletion.
   - **Description**: "Rejected or abandoned — with the reason recorded (bad idea, bad diagnosis, superseded, no longer relevant). Kept, not deleted, so the same dead-end isn't re-litigated: the 'why not' is part of the memory."
   - **Entry**: a human-confirmed rejection, or a consolidation *supersede/close*. Always record the *why* (ties to `¶INV_RESEARCH_MEMORY`). **Exit**: none (terminal).

### Pre-created tickets — the inbox channels (contextual per project)

The `Inboxes` milestone holds **one or more typed inbox tickets**, each a comment firehose for a *kind* of feedback. The set is **contextual per project** (`¶INV_INBOX_IS_TICKETS`) — pick channels that fit the initiative. A strong default set is a **what's-broken / why-broken / what-we-want / how-to-do-it** taxonomy:

- **🔴 Observed problems** — *symptoms*; things seen going wrong (with case / claim / org refs where available).
- **🟠 Identified shortcomings** — *diagnosed gaps* / structural weaknesses; the "why it's broken", one level deeper than a symptom.
- **🔵 Feature requirements** — *desired new behaviors / capabilities* from the product side; the "what", which can stand on its own without a specific bug behind it.
- **🟢 Potential solutions** — *conjectured fixes*, ideas, design concepts; the "how", where the creative leaps land so they're not lost.
- **🟣 Feedback & Transcripts** — *raw longform source*: emails, call/meeting transcripts, message threads, attachments from team + clients, dropped whole. Not a distilled observation — this is where entire conversations and documents land to be **chunked and organized** into the other channels.
- **🟤 Priorities & Deadlines** — the *escape hatch on computed priority*: deadlines, urgency, strategic or relationship weight the ranking can't see from the signal alone. An **input** to prioritization weighed by the owner, not a command — droppers say *why*, so it's weighed honestly rather than loudest-wins.
- **🟡 Researches & Fixtures** — *human-ratified golden fixtures* for AI workloads: someone reviewed the AI's output (extraction / classification / comparison), corrected it to the right answer (the oracle), and captured the evidence that proves it. Each is banked into the golden corpus **and routed to a fix ticket** so the gap is fixed once and regressions are tracked (the check → correct → prove → post flow). Distinct from Observed problems (a symptom) and Feedback & Transcripts (raw source): a *corrected ground-truth artifact + its routing*.
- **🟦 Documentation** — *docs missing, needed, wrong, or stale*. Covers **both** kinds: our own engineering and process docs (runbooks, architecture, `CLAUDE.md`, engine directives) and product-facing docs (the Notion knowledge base, anything an adjuster or PA reads). The dropper is not asked to classify — triage sorts it. This is its own channel because a doc problem has no honest home elsewhere: nothing in the product broke (not 🔴), the system works and only its description doesn't (not 🟠), and nobody wants a new capability (not 🔵). Its graduated tickets route to `/document` rather than `/implement` — **a different consumer is what makes a channel real rather than a convenience.**

All are frozen (never worked, never closed). A dropper picks the ticket matching what they're reporting; ingest drains comments across all of them. A single comment may **span channels** (e.g. a solution that also implies a requirement) — the organize pass splits and cross-links it. Each ticket's body invites half-formed input and points at the project's Vision & Process doc.

### The Project description — the section schema

The Project description is not free prose. It is a small set of named sections, each with a different author and a different consumer, and **this list is the only place they are enumerated** — Phase 0 bootstrap writes from it and Phase 0 load reads from it, so a new section is added here first and nowhere else. A convention that lives in Linear but not in this catalog drifts: 🟤 Priorities & Deadlines existed as a real channel for a full pass while the skill's own default list still had six.

- **Domain-goal prose** *(mandatory)* — what this initiative is chasing and what "better" means. Written at bootstrap, interrogated from the user, never invented from the project name.
- **`## Ticketing Strategy`** *(mandatory — `¶INV_TICKETING_STRATEGY_IN_PROJECT`)* — how much ticketing this project wants. Project-level only; see below.
- **`## Directions`** *(optional — `¶INV_DIRECTIONS_IN_DESCRIPTIONS`)* — the current steer for triage and ripeness. Also appears per-channel, where it takes precedence.
- **`## Stakeholders`** *(recommended)* — facts about the people around this initiative, so each consumer draws its own inference rather than following an assignment rule that goes stale silently. See below.
- **Ownership + cadence** *(recommended)* — a named operator and backup, plus the committed public cadence (default "Weekly (by Friday) + on-demand for hot topics").

Mandatory means the section must be present on every intake project. It does not mean the text is identical everywhere — the shipped defaults are a starting point a human edits in place.

### Directions — the per-project steer (`¶INV_DIRECTIONS_IN_DESCRIPTIONS`)

Every intake project is chasing something different, and what counts as "worth triaging" or "ripe" differs with it. That steer lives **in Linear descriptions, not in a doc** — a `## Directions` section at the end of the **Project description** (project-wide) and of **each inbox channel ticket's description** (per-channel). Precedence: **channel > project > skill default**. Absent means the skill's defaults apply — never fail, never invent one.

Descriptions rather than documents, for three reasons: a dropper reads the channel ticket anyway (the steer is where the drop happens, not one click away), a human edits it in place without any tooling, and the skill already holds every mechanic — so Directions only need to say *what to achieve*, never *how*.

What belongs there:
- **What this project is trying to achieve right now** — the current push, in a sentence or two.
- **What counts as ripe here** — additions to, or relaxations of, the default ripeness checklist.
- **What triage should chase or skip** — the evidence that matters for this channel, and what's out of scope.

What does not: protocol mechanics, phase descriptions, anything the skill already knows. Keep it short and current; a stale Direction silently misdirects every wave until someone edits it.

**How it flows through a wave**: Setup loads them and copies them verbatim into the working doc → Scope & Worklist applies them to the needs-triage call (citing the line) → Triage passes the origin channel's Directions **verbatim into each handoff prompt** (a sub-agent cannot read the project, so an unpassed steer is a lost steer) → Outcomes applies the possibly-modified ripeness checklist and records it **as applied**. Directions may never remove a human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`) — they steer judgment, they don't grant authority.

### Ticketing Strategy — how much ticketing this project wants (`¶INV_TICKETING_STRATEGY_IN_PROJECT`)

Ripeness asks *"is this item well-formed enough to be a ticket?"*. Ticketing Strategy asks the question after it: *"given that it IS ripe, should it be its own ticket, or folded into a parent, or left marinating?"* That is volume and chunkiness, not readiness — a different axis, which is why it is a separate gate at Outcomes rather than a fifth ripeness criterion.

**Project-level only.** Unlike Directions there is no channel override and no precedence chain: how many tickets a project wants is a property of the project, not of the firehose an item happened to arrive through. A channel that could raise or lower ticket volume would make the same item graduate or not depending on where it was dropped.

**Mandatory, and absence is loud.** Every intake project carries the section. When a project has none, the wave **warns once** and proceeds on the default below, recording *"default applied"* in the working doc — never a silent fallback, which is the thing that keeps Directions optional.

**The canonical default** (written verbatim into every new project at bootstrap; operators then edit the bullets in place to dial their project — the knob is the edit, not the authoring):

```markdown
## Ticketing Strategy

How much ticketing this project wants. Edit these three lines to dial it — they steer what gets its own ticket, what gets folded into a parent, and what keeps marinating.

*   **Volume — fewer, better.** We are not trying to capture every observation as a ticket. A signal earns a ticket; it is not owed one. When in doubt, fold it into an existing ticket or leave it marinating.
*   **Size — a ticket should be a measurable chunk.** Big enough that finishing it visibly moves something, small enough that "done" is unambiguous. If you cannot say what would be true when it closes, it is not sized yet.
*   **Substance — a ticket should be a meaningful thing.** It stands on its own: a real problem or a real change, not a fragment, a restatement, or a bookkeeping note. If it only makes sense as a step inside another ticket, it belongs inside that ticket.
```

The three bullets are deliberately independent axes — *how many* we want at all, *how big* one should be, *what makes one worth existing* — so each dials on its own. A project wanting finer-grained tracking loosens Volume; one drowning in fragments tightens Substance.

**How it flows through a wave**: Setup loads it verbatim into the working doc (warning if absent) → Digest's consolidation runs with it in view, since folding symptoms under a root-cause parent is how chunkiness is achieved → Outcomes applies it as a distinct gate after ripeness passes, recording the call **as applied** → Triage carries it **verbatim into every handoff prompt** in its own block, because the sub-agent's "ripe to graduate → which milestone" recommendation is a graduation-volume call made by an agent that cannot read the project. It steers judgment; it never removes the human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`).

**When it changes, say so.** A changed Direction re-opens pending judgment. A changed Ticketing Strategy re-opens **already-filed tickets** — graduations made under the old policy are now decisions nobody would make today. Note the change in the working doc and re-examine recent graduations rather than proceeding silently.

### Stakeholders — facts about people, not assignment rules

Who is around this initiative, stated as **facts** rather than as a routing policy. The distinction is the whole design: a fact ("Dana owns the classifier prompts") stays true and lets each consumer draw its own inference — assignee, reviewer, who to ask, who to notify. A rule ("assign classifier tickets to Dana") goes stale the week Dana changes teams, and nothing announces that it has.

What belongs:
- **Who owns what** — areas of the system, decisions, or budgets, named by person.
- **Who to ask about what** — the person who can answer a question triage cannot close on its own.
- **Who cares about outcomes here** — who wants to hear that something shipped, and who must be consulted before it does.
- **Anything with an expiry** — an interim owner, someone on leave, a handover in progress. Say the expiry out loud.

What does not: assignment rules, approval workflows, org-chart reproduction, or anything the skill already knows. Never treat an entry as authority — a Stakeholders line never substitutes for a human confirm.

**How it flows through a wave**: Setup loads it into the working doc → Triage carries the relevant names into a handoff prompt, so a sub-agent that hits a question it cannot answer knows **who to ask** instead of guessing or silently degrading → Outcomes uses it to *infer* a sensible assignee or reviewer on a graduated ticket, and to decide who a Project Update should reach. Inference, always — the skill proposes, the human confirms.

Optional, unlike `## Ticketing Strategy`: a project with no named stakeholders is a normal state, and its absence is not warned about.

### The inbox handbook — shared machinery lives in ONE document (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`)

A channel description carries two very different things, and they have opposite maintenance costs:

- **Machinery** — the report template, "what happens next", the correction affordance, the other-inboxes list, the generic triage recipe. **Identical on every channel of every project.** Changing one sentence means editing it once per channel per project.
- **Steer** — that channel's `## Directions` and its one-line *what belongs here*. **Genuinely different per channel**, and read at the moment someone drops.

So they are stored differently. The machinery lives in **one Linear Document per project — the "Inbox Handbook"** — and every channel description links to it. Only the steer stays inline.

**Why a Document, not an attachment**: an attachment is an opaque file; a Document is editable in place by a human, linkable, versioned, and readable by an agent via `get_document`. Each project already has a *Vision & Process* document, so the pattern exists.

**What goes in the handbook**: the 📋 report template · what happens next (including *"the triage that comes back is a draft"*) · the other-intake-inboxes list · the generic triage recipe · how a comment becomes a ticket.

**What stays on the channel**: a one-line *what belongs here*, that channel's `## Directions`, and a link to the handbook. A channel should be readable in ten seconds.

**How agents get it**: Setup loads the handbook once and holds it; Triage pastes the relevant part into each handoff prompt (a sub-agent still cannot read the project); `/inbox-post` and `/inbox-triage` read it when running standalone. One fetch replaces N copies.

**The cost this pays for is measured, not theoretical**: propagating a single sentence across the channel set took **35 writes** — and the channel list had already drifted, with `/inbox-post` documenting "6 channels" while 7 existed. Duplication does not just cost effort; it silently goes stale.

**The tradeoff, stated plainly**: a dropper reading a channel ticket sees less than before — a pointer where a template used to be. That is the right trade for machinery and the wrong one for steer, which is exactly why the split runs where it does.

### Companion artifacts

- **Linear "Vision & Process" document** (on the Project) — teammate-facing projection of the vision/why/lifecycle. Human audience. Kept in sync from the working understanding.
- **Session working doc** (`INTAKE.md`) — the agent's cross-scope understanding, item registry, root-cause/consolidation map, ranked priorities. Projected outward to the Project description + updates. Not a competing store.
- **Notion knowledge base** (`¶INV_NOTION_KNOWLEDGE_BASE`) — related **non-technical** Notion pages: plain-language "how it's supposed to work" product docs for the user, distinct from engineering designs. Linked from the Project description (page + subpages). At project creation, **ask** whether there's an existing Notion page to observe/manage/read or one should be created; link/write/maintain it as understanding evolves.

---

## How the agent works with it (and why)

- **Bounded waves, item-level no-rush** (`¶INV_NO_RUSH_ITEMS_TO_CLOSURE`). A wave = one session that grooms **one project** from the watermark forward: **ingest** (drain) → **scope & worklist** (cheap dedup; mark what needs triage) → **triage** (parallel `/inbox-triage` subagents enrich the thin ones) → **digest** (deep organize/consolidate + problem map) → **outcomes** (prioritize, dispose, sync, offer the Project Update) → **(discuss)** → **close** with a debrief. The next wave resumes from Linear + the advanced watermark (durability is in Linear, not the session). The no-rush guarantee is item-level — a wave may close with items still marinating, and an item is never force-promoted just because the wave is ending.
- **Ingest via a background drain subagent** — feedback lands as comments on the inbox tickets (and Inboxes-milestone threads), but comment payloads are large (a single drop can be 30–40KB) and the Linear MCP has no server-side `since` filter and no projection mode. So the drain runs in a **subagent**, not the main loop: it pages `list_comments(issueId, orderBy: createdAt, limit: 1)` newest-first per ticket, **early-stops** just under the single per-project watermark (in `INTAKE.md`) — keeping `createdAt >= watermark` and **deduping by comment id** so the boundary second is never lost — retries once on a transient 502, appends each new kept comment to `INTAKE_DRAIN.md`, and returns only a **compact digest** (~30× smaller). The main loop advances the watermark to the newest ingested `createdAt` *after* the digest returns (`¶INV_WRITE_BEFORE_WATERMARK`), and the subagent excludes its own reply-threads by **marker prefix, not author** (`¶INV_EXCLUDE_OWN_COMMENTS`). *Why*: never silently lose or re-ingest feedback, and keep the fat bodies out of the orchestrator's context.
- **Organize** (in a wave this runs *after* triage, on the enriched items) — dedup, cluster, classify into a milestone's work-type, draft a brief. Annotate state as reply-threads on the origin comment: `candidate` · `seems like …` · the triage markers `🔎 needs-triage` → `👀 claimed by <who>` → `✅ result` · `filed as FIN-XXX`.
- **Consolidate continuously** (`¶INV_CONTINUOUS_CONSOLIDATION`) — always on the lookout to **merge / dedup / supersede / connect**. Distinct symptoms sharing a root cause become a **parent "solution Z" ticket** with the symptoms as children. Maintain a root-cause map in the working doc. *Why*: keep a constantly-cleaned state and fix the *path*, not each symptom.
- **Triage before ticket** (`¶INV_TRIAGE_BEFORE_TICKET`) — most signals aren't ticketable yet. Triage is *light*: dispatch a sub-agent (`/inbox-triage`, else `/probe`) to gather detail — identify account/org/claim/page-URL via the read-only DB, pull PostHog if sourced, attempt a repro, find related tickets. Post the result back on the origin comment as a **new reply per pass** (short finding inline; long report written to `builds/` and attached to the comment via upload→embed-`assetUrl`, skipping `create_attachment_from_upload` so it stays a *comment* attachment). Enrichment accretes until ripe. Triage ≠ research (deep work runs on a graduated `Needs research` ticket).
- **Park inbox sub-issues** (`¶INV_INBOX_NOT_TICKETS`) — coworkers sometimes create sub-issues under a frozen inbox channel ticket. Detect them and propose reparenting each to `Uncategorized` (confirm each), keeping `Inboxes` frozen-collectors-only. Inbox items keep their own lightweight format — don't reimplement tickets in comments.
- **Promote only when ripe, human confirms each** (`¶INV_RIPENESS_IS_A_RECORDED_CHECKLIST`, `¶INV_TICKET_EARNED_BY_CONFIRM`). Ripe = crisp problem + defined next-action + brief type + ≥1 *non-self* corroboration, recorded as a checklist. File straight into the work-type milestone when obvious, else `Uncategorized` — **never** `Inboxes`. Set the Linear priority field on the graduated ticket.
- **Every destructive op needs a human's yes** — creating a ticket, merging, superseding, closing. Linear is the source of truth; never overwrite human-owned state (`¶INV_LINEAR_IS_TRUTH`).
- **Sync to Linear** — refresh the Project description (lean — goal only, not a milestone re-description) and post Project Updates. Keep the Vision & Process doc current.
- **Rank with proofs, two levels** (`¶INV_RANKING_WITH_PROOFS`, `¶INV_TWO_LEVEL_PRIORITY`) — a built Triage step, not a seam. *Intake-internal*: which signals a wave triages first. *Output*: the durable "pull this first, and why, with evidence" ranking that guides doers — the Linear priority field on tickets + a ranked narrative in the Project Update. Impact = consolidation breadth (a parent resolving N symptoms) + non-self corroboration + blast-radius.
- **Dispatch, never execute** (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`) — /intake writes briefs and hands off; it never does the research/build/fix. "Dispatch" is a context-rich handoff (a self-contained prompt stored in `builds/`, often attached to the comment), not a bare tag — the orchestrator holds the context, so it seeds the doer onto the right path. Doers claim/return via replies (`👀`/`✅`); reactions aren't MCP-addressable.

---

## ¶PASS_HEARTBEAT — make a completed pass visible (and a skipped one legible)

The whole system is driven by someone choosing to run a pass. Nothing forces it, and the failure mode is **silence** — a pass quietly stops running and the inbox rots with all its content intact. The fix is deliberately **not** automation (running the pass is a human judgement call, HITL by design): it's making each *completed* pass **announce itself where the team already looks**, so its absence becomes noticeable.

- **What fires**: when a wave's **Project Update is posted** (Outcomes Phase 5, or the Close backstop Phase 7), the agent also emits a **one-shot Slack announce** via `engine slack-post` — the update headline, the ranked "pull first", the honest counts, the **latest watermark**, and a **"previous pass ran `<date>` (`<N>`d ago)"** gap line (the prior Project Update's timestamp, read via `get_status_updates`). The gap line is silence-made-legible: a long gap shows in the channel history without anyone asking, and there is **no cron** — a pass that never runs simply never announces, and the growing gap since the last announce is the tell.
- **Fire once per posted update** — announced at Outcomes ⇒ do not re-announce at Close.
- **Ownership + cadence** live in each project's **description** (a neighbour of `¶INV_DIRECTIONS_IN_DESCRIPTIONS`): a named operator + backup and the committed public cadence (default **"Weekly (by Friday) + on-demand for hot topics"**). The announce points at that project so the named operator sees it.
- **Setup** (one-time): the poster authenticates with a Slack **bot token** (`chat:write` scope, bot invited to the target channel). Provide it out-of-band, never in chat/committed source:
  - `SLACK_INTAKE_TOKEN` — the `xoxb-…` bot token (or `SLACK_BOT_TOKEN`). Keep it in a gitignored env file (e.g. the repo's `.env.local`) — `engine slack-post --env-file <path>` key-extracts it (never sources the file).
  - `SLACK_INTAKE_CHANNEL` — the destination channel id/name.
- **Best-effort**: a missing token/channel or a Slack `error` (e.g. `not_in_channel` → `/invite` the bot) is logged and **never blocks the wave's Close**. `engine slack-post --dry-run` prints the exact payload (token redacted) for a safe check.

---

## The problem map — dependency graph + research memory

This is the heart of *why* the system earns its keep. The big solution ("tickets A…Y are all fixed by Z") is a **creative conjecture** — it comes from a human forming a concept, not from mechanically summing tickets. The system does **not** claim to generate it. What it does is make that conjecture *cheap to form* and *impossible to re-research*:

- **Dependency graph** (`¶INV_PROBLEM_DEPENDENCY_GRAPH`) — hold the problem space as a graph, not a flat list. Nodes = problems / candidate solutions; edges = *stands-on*, *blocked-by*, *unlocks*, *needs-research-from*. Materialize the edges as Linear relations (`blocks` / `blockedBy` / parent-child / `relatedTo`) and keep a readable version in the working doc. This is what turns "clumps of legos, no way to decompose and realign" into a map where you can *see* that Z stands on X,Y and unlocks O — and where the 20%-effort / 80%-win sub-problem becomes findable.
- **Research memory** (`¶INV_RESEARCH_MEMORY`) — every problem node accumulates the investigation done against it (findings, dead-ends, why/when it happens) attached to the **ticket**, never to a person or a dead session. The single most defensible value: *no problem is attacked from zero twice.* The working doc holds the cross-cutting synthesis; the ticket holds the durable record.

**What it does NOT solve** (be honest about the boundary): it does not manufacture the insight, and it does not solve "months roll by" — allocation/execution is a staffing decision, not a knowledge one. It makes the highest-leverage thing *obvious* so someone can choose to spend the time; it can't make them.
