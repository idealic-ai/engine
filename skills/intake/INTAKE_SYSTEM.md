# The Intake System — Structure Catalog & Operating Guide

**Read this on every `/intake` invocation.** It is the canonical reference for how an intake Project is structured and how the agent operates it. The `SKILL.md` defines the *protocol* (phases); this defines the *structure and the why*. Per-project specifics (the Project's goal, its IDs, its current understanding) live in the session working doc (`INTAKE.md`) and in Linear — this file is the general, project-agnostic spec.

---

## What the intake system is

A **pre-ticket layer** where scattered feedback is gathered, organized, consolidated, and — only when ripe and a human confirms — promoted into tracked tickets. It exists because the queue is past the point a human can hold in their head: raw feedback gets lost if not acted on immediately, and cross-cutting root causes ("tickets A…Y are all one problem") never surface. One **Linear Project per initiative** is the durable home; **Linear is the source of truth**, the session doc is the agent's working understanding projected onto it.

---

## Structure catalog

### Milestones (the lifecycle — stages of understanding, named for what blocks an item)

Create these five on every intake Project, with these **prescribed, teammate-facing descriptions** (no engine/skill jargon on the board — `¶INV_TEAMMATE_FACING_LINEAR`):

1. **Inboxes** *(frozen — lead collectors)*
   - **Goal**: collect signal, never track work.
   - **Description**: "Frozen lead-collectors — never worked. The Inbox ticket (where raw feedback arrives as comments) and any ticket parked here to gather input live here. Work is never tracked in this milestone; it exists purely to collect signal that becomes tickets elsewhere. Tickets here do not 'progress' — they spawn new tickets in the other milestones."
   - **Entry**: the Inbox ticket; existing tickets a human parks here for input. **Exit**: none — feedback here *spawns* new tickets elsewhere.

2. **Uncategorized**
   - **Goal**: hold a real-but-unsorted ticket visibly, never lost — the anti-dumping-ground.
   - **Description**: "Captured, awaiting triage. A piece of feedback that has become a real ticket but whose type isn't decided yet. It waits here — visible, never lost — until it's sorted into Needs decision, Needs research, or Ready for action. A ticket should not linger here: every pass tries to classify it out."
   - **Entry**: a promotion whose work-type wasn't obvious. **Exit**: → Needs decision / Needs research / Ready for action.

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
   - **Description**: "Nothing blocks it but the doing. Clear problem, clear fix, no open questions or unknowns left — ready to be built or handed to implementation as-is. Exits to done, or gets reassigned to the project that owns the work."
   - **Exit**: → done, or reassigned to the owning work project.

### Pre-created tickets — the inbox channels (contextual per project)

The `Inboxes` milestone holds **one or more typed inbox tickets**, each a comment firehose for a *kind* of feedback. The set is **contextual per project** (`¶INV_INBOX_IS_TICKETS`) — pick channels that fit the initiative. A strong default set is a **what's-broken / why-broken / what-we-want / how-to-do-it** taxonomy:

- **🔴 Observed problems with data** — *symptoms*; things seen going wrong (with case / claim / org refs where available).
- **🟠 Identified system shortcomings** — *diagnosed gaps* / structural weaknesses; the "why it's broken", one level deeper than a symptom.
- **🔵 Feature requirements** — *desired new behaviors / capabilities* from the product side; the "what", which can stand on its own without a specific bug behind it.
- **🟢 Potential solutions** — *conjectured fixes*, ideas, design concepts; the "how", where the creative leaps land so they're not lost.

All are frozen (never worked, never closed). A dropper picks the ticket matching what they're reporting; ingest drains comments across all of them. A single comment may **span channels** (e.g. a solution that also implies a requirement) — the organize pass splits and cross-links it. Each ticket's body invites half-formed input and points at the project's Vision & Process doc.

### Companion artifacts

- **Linear "Vision & Process" document** (on the Project) — teammate-facing projection of the vision/why/lifecycle. Human audience. Kept in sync from the working understanding.
- **Session working doc** (`INTAKE.md`) — the agent's cross-scope understanding, item registry, root-cause/consolidation map, ranked priorities. Projected outward to the Project description + updates. Not a competing store.
- **Notion knowledge base** (`¶INV_NOTION_KNOWLEDGE_BASE`) — related **non-technical** Notion pages: plain-language "how it's supposed to work" product docs for the user, distinct from engineering designs. Linked from the Project description (page + subpages). At project creation, **ask** whether there's an existing Notion page to observe/manage/read or one should be created; link/write/maintain it as understanding evolves.

---

## How the agent works with it (and why)

- **Reactive, persistent loop, no rush to closure** (`¶INV_NO_RUSH_TO_CLOSURE`). The default state is "curating; drop the next thing." The user drops input; the agent reacts. Ending is a rare, deliberate act.
- **Ingest cheaply** — feedback lands as comments on the Inbox ticket (and Inboxes-milestone threads). Write drained items to the working doc *before* advancing the watermark (`¶INV_WRITE_BEFORE_WATERMARK`), and exclude the agent's own reply-threads (`¶INV_EXCLUDE_OWN_COMMENTS`). *Why*: never silently lose or re-ingest feedback.
- **Organize** — dedup, cluster, classify into a milestone's work-type, draft a brief. Annotate state as reply-threads on the origin comment (`candidate` / `seems like …` / `filed as FIN-XXX`).
- **Consolidate continuously** (`¶INV_CONTINUOUS_CONSOLIDATION`) — always on the lookout to **merge / dedup / supersede / connect**. Distinct symptoms sharing a root cause become a **parent "solution Z" ticket** with the symptoms as children. Maintain a root-cause map in the working doc. *Why*: keep a constantly-cleaned state and fix the *path*, not each symptom.
- **Promote only when ripe, human confirms each** (`¶INV_RIPENESS_IS_A_RECORDED_CHECKLIST`, `¶INV_TICKET_EARNED_BY_CONFIRM`). Ripe = crisp problem + defined next-action + brief type + ≥1 *non-self* corroboration, recorded as a checklist. File straight into the work-type milestone when obvious, else `Uncategorized` — **never** `Inboxes`.
- **Every destructive op needs a human's yes** — creating a ticket, merging, superseding, closing. Linear is the source of truth; never overwrite human-owned state (`¶INV_LINEAR_IS_TRUTH`).
- **Sync to Linear** — refresh the Project description (lean — goal only, not a milestone re-description) and post Project Updates. Keep the Vision & Process doc current.
- **Rank with proofs** (`¶INV_RANKING_WITH_PROOFS`, reserved seam) — "pull this first, and why, with evidence." Consolidation breadth (a parent resolving N symptoms) is a core impact signal.
- **Dispatch, never execute** (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`) — /intake writes briefs and hands off; it never does the research/build/fix.

---

## The problem map — dependency graph + research memory

This is the heart of *why* the system earns its keep. The big solution ("tickets A…Y are all fixed by Z") is a **creative conjecture** — it comes from a human forming a concept, not from mechanically summing tickets. The system does **not** claim to generate it. What it does is make that conjecture *cheap to form* and *impossible to re-research*:

- **Dependency graph** (`¶INV_PROBLEM_DEPENDENCY_GRAPH`) — hold the problem space as a graph, not a flat list. Nodes = problems / candidate solutions; edges = *stands-on*, *blocked-by*, *unlocks*, *needs-research-from*. Materialize the edges as Linear relations (`blocks` / `blockedBy` / parent-child / `relatedTo`) and keep a readable version in the working doc. This is what turns "clumps of legos, no way to decompose and realign" into a map where you can *see* that Z stands on X,Y and unlocks O — and where the 20%-effort / 80%-win sub-problem becomes findable.
- **Research memory** (`¶INV_RESEARCH_MEMORY`) — every problem node accumulates the investigation done against it (findings, dead-ends, why/when it happens) attached to the **ticket**, never to a person or a dead session. The single most defensible value: *no problem is attacked from zero twice.* The working doc holds the cross-cutting synthesis; the ticket holds the durable record.

**What it does NOT solve** (be honest about the boundary): it does not manufacture the insight, and it does not solve "months roll by" — allocation/execution is a staffing decision, not a knowledge one. It makes the highest-leverage thing *obvious* so someone can choose to spend the time; it can't make them.
