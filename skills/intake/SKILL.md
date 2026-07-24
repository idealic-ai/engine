---
name: intake
description: "A living, never-ending feedback ingestion queue with periodic reorganization/promotion passes that sync a Linear Project to the agent's evolving cross-scope vision. You drop scattered ideas/findings/reports; /intake organizes them, marinates them until ripe, and — on your per-item confirm — promotes them into tickets under phase milestones, then projects its understanding back to Linear. A brief-writer/dispatcher + cross-scope organizer, NEVER an executor. Triggers: \"intake this\", \"organize the feedback\", \"run an intake pass\", \"drop this into the inbox\", \"reorganize the hairball\", \"pre-ticket triage\", \"marinate this idea\"."
version: 1.0
tier: protocol
---

A living feedback ingestion queue that organizes scattered input, marinates it until ripe, and promotes it into Linear tickets on your confirm — never rushing to closure.

# /intake Protocol (The Curator)

Execute §CMD_EXECUTE_SKILL_PHASES.

### What /intake is (and is not)

*   **It is** a persistent *pre-ticket* organizing layer: it ingests scattered feedback (yours, teammates', clients'), holds it cheaply, builds a cross-scope understanding, and — only when an item is *ripe* and you confirm — promotes it into a tracked Linear ticket. It dispatches **pick-up-able briefs** (`#needs-research`, `#needs-brainstorm`, …) for other skills to execute.
*   **It is NOT** an executor. It never does the research, writes the code, or fixes the bug. It organizes and hands off (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`).
*   **`/intake` vs `/direct`** (`¶INV_INTAKE_IS_BOTTOM_UP`): `/direct` designs a top-down vision — chapters and a plan — from a **known goal**. `/intake` accretes bottom-up from scattered feedback with **no goal yet**; the structure *emerges* from what marinates. Reach for `/direct` when you know the destination; `/intake` when you're still finding which thread to pull.

### State model — Linear is the source of truth (`¶INV_LINEAR_IS_TRUTH`)

*   **Linear tickets = the durable source of truth.** Feedback comes in and gets organized *for real* in Linear. Humans acting in Linear (dragging a milestone, closing an issue, replying) are always authoritative — the skill never overwrites human state.
*   **The engine session doc = internal working context only.** It holds the agent's intermediate decision-making, the historical log of input, and the evolving cross-scope understanding. It is **projected outward** to the Linear Project *description + updates*. It is a reasoning/vision surface, NOT a competing store. If the doc is lost, it is rebuildable from Linear (the "filed as FIN-XXX" reply-threads + tickets are the record).

### The Linear Project shape (one Project per initiative — with a real domain goal)

*   **The Project** has a **domain-specific goal** — a real initiative (e.g. "raise email-classification auto-approve rate without regressing safety"), **NOT "the inbox"** (`¶INV_PROJECT_HAS_A_DOMAIN_GOAL`). `/intake` figures this goal out via Setup interrogation and writes it as the Project's description/summary.
*   **Milestones** (five — lifecycle from raw lead to actionable):
    *   **`Inboxes`** *(frozen — lead collectors)* — holds **the Inbox ticket** (below) **plus** any existing tickets parked to gather input. Never active work; the skill **never files graduated tickets here** and only *reads* the threads here as feedback.
    *   **`Uncategorized`** — a promoted ticket whose work-type isn't obvious yet, awaiting triage. The anti-dumping-ground: visible, not lost.
    *   **`Needs decision`** — needs discussion/alignment → dispatch to `/brainstorm`.
    *   **`Needs research`** — needs investigation / root-cause / consolidation → `/analyze` `/research` `/experiment` `/probe`.
    *   **`Ready for action`** — clear problem + clear fix → `/ticket` `/implement`.
    *   *(Milestone names are the project's, teammate-facing — keep their descriptions human, no skill/engine jargon in Linear.)*
*   **The inbox tickets** — one or more **typed collection tickets under the `Inboxes` milestone**, chosen **per project** (`¶INV_INBOX_IS_TICKETS`). Each is a comment firehose for a *kind* of feedback; a dropper picks the one matching what they're reporting. Strong default set — a **what's-broken / why-broken / what-we-want / how-to-do-it** taxonomy: **Observed problems with data** (symptoms) · **Identified system shortcomings** (diagnosed gaps) · **Feature requirements** (desired new behaviors) · **Potential solutions** (proposed fixes/mechanisms). A single comment may span channels (e.g. a solution + a requirement) — the organize pass splits and cross-links. All are frozen, never closed, never worked. **The tickets ARE the inbox — the Project is not.**
*   **Research issue(s)** — living progress snapshots.
*   **Project Updates** — human-readable checkpoint reports.
*   **Item state lives as reply-threads on the origin Inbox comment**: `candidate` (ripeness nomination), `seems like FIN-…` / `seems like <cluster>` (dedup link), `filed as FIN-XXX` (graduation backlink).

### The lifecycle — a persistent loop that never rushes to closure (`¶INV_NO_RUSH_TO_CLOSURE`)

`/intake` sessions are **long-lived**. You drop ideas/findings/organizational prompts over time and the agent *reacts*. The natural state is Phase 1 (the Curation Loop) — the agent stays there, cycling its four actions on demand, and **does not nudge toward closing**. Ending the session is a deliberate, rare act; the agent must never treat "wrap up" as the default. Model: `/coordinate` (persistent), not `/do` (close-when-done).

### Session Parameters
```json
{
  "taskType": "INTAKE",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["intentReported", "sessionDir", "parametersParsed", "contextSourcesPresented", "filesLoaded"], "gate": false},
    {"label": "1", "name": "Curation Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_REFUSE_OFF_COURSE", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["logEntries"]},
    {"label": "2", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "2.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "2.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "2.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "2.4", "name": "Close",
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
*Resolve the initiative's Linear Project and load the working context.*

§CMD_REPORT_INTENT:
> 0: Opening an intake pass for ___ initiative. Trigger: ___.
> Focus: resolve the Linear Project, load the working vision doc, assume the Curator role.
> Not: organizing or promoting yet — setup only.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

**Assume the role** (`§CMD_ASSUME_ROLE`): You are **The Curator** — a patient organizer of scattered signal. Your job is to make sense of a hairball without forcing premature structure. You hold ideas cheaply, notice what's connected, and resist the urge to file a ticket before an item has earned it. You never rush.

**Resolve the initiative & its Linear Project** (`¶INV_LINEAR_IS_TRUTH`, `¶INV_PROJECT_HAS_A_DOMAIN_GOAL`):
1.  **Identify the initiative** from the user's prompt. One initiative = one Linear Project.
2.  **Interrogate the domain goal** (`§CMD_INTERROGATE`, first run only): the Project is a real initiative, so pin its **specific domain-specific goal** before creating it — what problem it solves, what "better" means, what's in / out of scope. Draw on provided context (prior tickets, a sibling project, a `/probe` of related work). **Do NOT assume the goal from the initiative's name.**
    *   **Also ask about a Notion knowledge base** (`¶INV_NOTION_KNOWLEDGE_BASE`): is there an existing Notion page for this domain to observe/read/maintain (plain-language, non-technical product docs helpful to the user), or should one be created? Link the page **and its subpages** into the Project description under a "Knowledge base" section.
3.  **Read the tracker config** from the project `CLAUDE.md` `## Tracker` section (team, issue prefix, URL) — never hardcode it. **Check for existing sibling projects first** and surface them — never silently spawn a duplicate.
4.  **First run** (no Project yet): with the user's confirm, bootstrap via the `linear-server` MCP —
    *   the **Project** — a *lean* description (the domain goal + what-this-is), **not** a re-description of the milestones (they're self-explanatory from their own descriptions) and **not** the vision prose.
    *   the five **milestones** (`Inboxes` (frozen), `Uncategorized`, `Needs decision`, `Needs research`, `Ready for action`) — each with a *prescribed, human-facing* description (`¶INV_TEAMMATE_FACING_LINEAR`): what blocks an item here, and where it exits to.
    *   a companion **"Vision & Process" document** on the Project (`¶INV_VISION_IN_COMPANION_DOC`) — teammate-facing: why the system exists, the lifecycle, the constantly-cleaned-state, how it's operated. This holds the vision; the skill holds the operations.
    *   **the project's inbox tickets** — one or more *typed* channels under the `Inboxes` milestone, chosen for the initiative (default: `Observed problems with data` / `Identified system shortcomings` / `Feature requirements` / `Potential solutions`).
    *   Record the Project ID + the inbox ticket IDs + the doc ID + the drain **watermark** (initially empty) in the working doc.
5.  **Subsequent run**: load the existing Project + Inbox ticket by ID from the working doc.

**Load the working context**:
*   **Read the structure catalog FIRST** (`¶INV_STRUCTURE_CATALOG_IS_LOCAL`): `~/.claude/engine/skills/intake/INTAKE_SYSTEM.md` — the canonical milestone catalog (names, prescribed descriptions, goals, entry/exit), the pre-created-tickets pattern, and the operating guide. Read it on every invocation before touching the Project.
*   **Working vision doc** — `INTAKE.md` in the session dir (the `debriefTemplate`), the SSOT-of-*understanding* projected to Linear. If it exists, read it; if not, it is created on first Organize.
*   Pin the doc location: **the active session dir** (`¶INV_DOC_IN_SESSION_DIR`). The session is long-lived, so the doc lives with it; Linear is the durable record if the session is ever lost.

*Phase 0 always proceeds to Phase 1 — no transition question.*

---

## 1. Curation Loop
*The persistent heart. You drop input; the Curator reacts. It never rushes to close.*

§CMD_REPORT_INTENT:
> 1: Curating the ___ inbox. Reacting to dropped input; cycling ingest / organize / promote / sync on demand.
> Focus: hold cheaply, organize, marinate until ripe, project understanding to Linear.
> Not: executing downstream work, and NOT rushing toward closure.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### How this phase works

There is no march to an end. The agent **stays in this loop**, reacting to whatever the user drops and to its own reorganization judgment. After each unit of work, it logs and **returns to a ready state** — the default is always "still curating; drop the next thing," never "shall we close?" (`¶INV_NO_RUSH_TO_CLOSURE`).

The loop performs four **actions**, invoked on demand (by the user's input, or the agent's own periodic reorganization pass). They are a vocabulary, not a sequence — run whichever the moment calls for, in any order, as often as needed.

#### Action A — Ingest (drain the queue)
*   Pull **new comments across the typed inbox tickets + any parked tickets under `Inboxes`, since the watermark** (the typed tickets are the firehoses; parked tickets also solicit input). Also accept input dropped **directly in chat**.
*   **Exclude the skill's own reply-threads** from ingestion (`¶INV_EXCLUDE_OWN_COMMENTS`) — filter by author + a self-authored marker so the loop never re-ingests its own annotations.
*   **Write each raw item to the working doc's input log BEFORE advancing the watermark** (`¶INV_WRITE_BEFORE_WATERMARK`). If a pass dies mid-drain, the un-advanced watermark means a re-run re-reads the same comments — nothing is silently lost.
*   Log the ingest (`§CMD_APPEND_LOG`): count + source.

#### Action B — Organize (dedup, cluster, classify, rank)
*   **Dedup / cluster** related items; when an item echoes an existing one, drop a `seems like <cluster/FIN-…>` reply on its origin comment.
*   **Classify** each cluster into a bucket: `conversational` (needs shaping) · `research` (needs investigation) · `action` (ready to build) — mapping to the phase milestone it would graduate to.
*   **Draft/refine a brief** per cluster: the problem, the intended next-action, and the brief *type* (`#needs-brainstorm` / `#needs-research` / `#needs-implementation`, or `/probe` / `/experiment` intents).
*   **Rank by impact** — *reserved seam, `¶INV_RANKING_WITH_PROOFS`*: v1 records a coarse impact/effort read per cluster; the **primary next build** is a "pull this first, and why — *with proofs*" ranked view (evidence-backed, tied to `/probe`/`/prove`). Design for it now; leave a clear seam in the doc's ranking section.
*   Update the **working vision doc** — the evolving cross-scope understanding.

#### Action C — Promote (the ripeness gate — human confirms each)
*   Apply the **recorded binary ripeness checklist** (`¶INV_RIPENESS_IS_A_RECORDED_CHECKLIST`) to each candidate cluster. An item is **ripe** only when ALL are checked:
    *   [ ] **Crisp problem** — a one-sentence problem statement a stranger could understand.
    *   [ ] **Defined next-action** — the concrete thing to do next is named.
    *   [ ] **Brief type assigned** — which milestone / which skill picks it up.
    *   [ ] **Enough corroboration** — ≥1 *non-self* comment supports it (the skill's own replies **do not count** — `¶INV_EXCLUDE_OWN_COMMENTS`).
    Record the checklist result on the item in the doc (a checked box each), so ripeness is auditable, not a vibe.
*   **Agent proposes, you confirm — per item** (`¶INV_TICKET_EARNED_BY_CONFIRM`). Present the ripe nominees (with their drafted brief) via `§CMD_DISPATCH_APPROVAL`-style per-item approval. **No Linear ticket is ever created without your explicit yes.**
*   On confirm: **create a new ticket** tagged with the brief — filed **straight into its work-type milestone when the type is obvious** (`Needs decision` / `Needs research` / `Ready for action`), else into **`Uncategorized`** to await triage. **Never `Inboxes`** (that milestone is frozen lead-collectors only). Make it **idempotent** (`¶INV_IDEMPOTENT_PROMOTION`): file-then-annotate is two calls; carry a pre-write key so a crash between them never double-files a twin.
*   Drop a `filed as FIN-XXX` reply on the origin comment (the graduation backlink), and record `FIN-XXX` on the item in the doc.

#### Action D — Sync & Report (project the vision to Linear)
*   **Sync Linear to the vision** (`¶INV_LINEAR_IS_TRUTH` — one-way, doc→Linear, and only for *skill-derived* framing; never overwrite human-owned state like milestone position or issue status):
    *   Refresh the **Project description** with the current cross-scope understanding + the ranked "where to start" read.
    *   Post a **Project Update** — a human-readable checkpoint: what's *marinating*, what's *ripe*, what was *filed this pass*, and the honest counts (including nomination-rejection and staleness, so rot is visible — not just flattering volume).
    *   Refresh the **Research snapshot issue** if research threads advanced.
*   Log the sync.

#### Action E — Consolidate (keep a constantly-cleaned state)
*Always on. Run on every pass and whenever new input lands (`¶INV_CONTINUOUS_CONSOLIDATION`). The point is that nothing rots — the ticket set stays a clean, navigable map of the real problems, never a dumping ground.*
*   **Dedup** — the same item twice → mark one `duplicateOf` the other; keep a single canonical.
*   **Merge** — several tickets are facets of one → fold into a canonical ticket (others `duplicateOf` it), carrying their context forward.
*   **Supersede** — a newer/better-framed ticket obsoletes older ones → mark the old superseded + closed, so the live framing wins.
*   **Connect** — the consolidation primitive: distinct symptoms that share a root cause → a **parent "root-cause / solution" ticket** with the symptoms as **children** (plus `relatedTo` / `blocks` where apt). This is how "tickets A–Y are all fixed by solution Z" becomes visible and trackable — fix the *path*, not each symptom.
*   Maintain a **root-cause map** in the working doc: symptom clusters → hypothesized root cause → candidate consolidating solution. This cross-scope view is what makes the consolidating solution *findable* — a single-ticket view can't surface it.
*   **Human confirms every destructive op** (merge / supersede / close) — `¶INV_TICKET_EARNED_BY_CONFIRM` + `¶INV_LINEAR_IS_TRUTH` (never overwrite human state). Non-destructive connects (related/parent-child) are proposed, then applied on confirm.
*   **Feeds the ranking**: a parent resolving N symptoms outranks a one-off — consolidation breadth is the core impact signal for "where to start" (`¶INV_RANKING_WITH_PROOFS`).

#### The problem map — dependency graph + research memory (the anti-relitigation core)
*The map is not a flat list. It is a **dependency graph** (`¶INV_PROBLEM_DEPENDENCY_GRAPH`) and a **research memory** (`¶INV_RESEARCH_MEMORY`) — together they are what let a human make the leap to a big solution cheaply, and only once.*
*   **Dependency graph** — nodes = problems / candidate solutions; edges = *stands-on*, *blocked-by*, *unlocks*, *needs-research-from*. Materialize edges as Linear issue relations (`blocks` / `blockedBy` / parent-child / `relatedTo`) **and** hold the readable graph in the working doc. This is what lets someone *see* that solution Z stands on X,Y and unlocks O — and find the 20%-effort / 80%-win node — instead of facing undifferentiated "clumps of legos."
*   **Research memory** — every problem node accumulates the investigation done against it (findings, dead-ends, *why/when* it happens) attached to the **ticket** (its description/comments), never to a person or a dead session. When anyone picks it up, the research is already there; nobody attacks from zero twice. The working doc holds the cross-cutting synthesis; the ticket holds the durable record.
*   **Enable the conjecture, don't manufacture it** — /intake assembles the decomposed, dependency-aware, non-lossy context so a human (or a downstream skill) can make the creative leap to a solution cheaply and once. It **never** claims to auto-generate the solution — it makes forming and criticising it cheap, and makes it stick.

### The loop gate (persistent — closing is the exception)

After any action, re-present the ready state via `AskUserQuestion` (multiSelect: false), **defaulting to continuation**:
> "Curating `<initiative>` — what next?"
> - **"Drop input / keep curating"** *(default)* — stay in the loop; ingest/organize whatever's next. This is the normal state.
> - **"Run a full reorganization pass"** — cycle Ingest → Organize → Promote → Sync in one sweep.
> - **"Review promotions"** — run the ripeness gate on current candidates.
> - **"Checkpoint (sync to Linear)"** — run Action D without closing.
> - **"Close the session"** — the rare, deliberate exit → Phase 2.

**Never** present closing as the recommended or default option. If the user goes quiet, the agent waits in the loop — it does not prompt "ready to wrap up?" (`¶INV_NO_RUSH_TO_CLOSURE`). Only an explicit close request (or the user selecting "Close the session") advances to Phase 2.

**Off-protocol input** (e.g., "just go fix this bug") → route via `§CMD_REFUSE_OFF_COURSE`: /intake dispatches briefs, it does not execute. Offer to promote-and-hand-off instead.

---

## 2. Synthesis
*Only on an explicit close. A checkpoint, not a finalization — the initiative continues in Linear.*

§CMD_REPORT_INTENT:
> 2: Checkpointing and closing the ___ intake session. ___ items curated this session.
> Focus: final Linear sync, debrief the working vision, clean handoff.
> Not: abandoning the initiative — Linear carries it forward; a future /intake resumes it.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

Before the pipeline, run a **final Action D (Sync & Report)** so Linear reflects the latest vision on exit.

**Debrief notes** (for `INTAKE.md`): fill every section — the working vision doc IS the debrief here (cross-scope understanding, item registry with ripeness/state, ranked priorities, Linear Project pointer, what's marinating vs ripe vs filed).

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Intake checkpoint complete. Walk through the current vision + open threads?"
  debriefFile: "INTAKE.md"
```

**Post-Synthesis**: If the user keeps dropping input after close, obey `§CMD_RESUME_AFTER_CLOSE` — reactivate and return to the Curation Loop. Closing was a checkpoint, not an end.

---

## Critical Invariants (this skill)

*   **¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES**: /intake organizes and hands off briefs; it never does the downstream research/build/fix.
*   **¶INV_NO_RUSH_TO_CLOSURE**: The session is long-lived. The agent stays in the Curation Loop and never nudges toward closing; ending is a deliberate, explicit, rare act.
*   **¶INV_LINEAR_IS_TRUTH**: Linear tickets are the source of truth; humans acting in Linear are authoritative. The doc is a working projection synced one-way to Linear, never overwriting human-owned state.
*   **¶INV_INTAKE_IS_BOTTOM_UP**: /intake accretes bottom-up with no goal yet (vs /direct's top-down vision from a known goal).
*   **¶INV_PROJECT_HAS_A_DOMAIN_GOAL**: The Linear Project is a real initiative with a specific domain goal, interrogated at Setup — never assumed from a name, and never "the inbox" itself.
*   **¶INV_INBOX_IS_TICKETS**: The feedback inbox is one or more *typed* tickets under the `Inboxes` milestone — each a comment firehose for a kind of feedback, chosen **contextually per project** (default taxonomy — what's-broken / why-broken / what-we-want / how: Observed problems with data / Identified system shortcomings / Feature requirements / Potential solutions). The Project is not the inbox.
*   **¶INV_CONTINUOUS_CONSOLIDATION**: The skill is always on the lookout to **merge / dedup / supersede / connect** tickets within a project, maintaining a constantly-cleaned state (never a dumping ground). Cross-cutting symptoms consolidate into a single higher-leverage parent ("solution Z") that references what it resolves — fix the path, not each symptom — and consolidation breadth feeds the impact ranking. Destructive ops (merge/supersede/close) require human confirm.
*   **¶INV_TEAMMATE_FACING_LINEAR**: Linear content teammates read (Project + milestone descriptions, ticket bodies) stays human/domain-facing — no engine/skill jargon (`§CMD_*`, `/skill` names). The engine vocabulary lives in the working doc, not on the board.
*   **¶INV_VISION_IN_COMPANION_DOC**: The vision / process / philosophy lives in a teammate-facing "Vision & Process" companion document on the Project — not in the Project description (which stays a lean goal; the milestones are self-explanatory) and not duplicated in the skill. The skill focuses on the operational process; the doc holds the why.
*   **¶INV_STRUCTURE_CATALOG_IS_LOCAL**: The canonical structure catalog + operating guide lives in `INTAKE_SYSTEM.md` next to the skill, read on every invocation. It holds the milestone catalog (names, prescribed descriptions, goals), the pre-created-tickets pattern, and the how/why of operating a Project — the general, project-agnostic source the agent bootstraps and operates from.
*   **¶INV_NOTION_KNOWLEDGE_BASE**: The skill links, writes, and maintains related **non-technical Notion pages** as a knowledge base for the user (plain-language "how it's supposed to work" docs — not engineering designs). At project creation, ask whether there's an existing Notion page to observe/manage/read or one should be created; link it (and its subpages) from the Project description, and keep it current as understanding evolves.
*   **¶INV_TICKET_EARNED_BY_CONFIRM**: No Linear ticket is created without an explicit per-item human confirm.
*   **¶INV_RIPENESS_IS_A_RECORDED_CHECKLIST**: Ripeness is a recorded binary checklist (crisp problem · defined next-action · brief type · enough non-self corroboration), not a vibe.
*   **¶INV_EXCLUDE_OWN_COMMENTS**: The skill's own reply-threads are excluded from ingestion AND from the ripeness corroboration count.
*   **¶INV_WRITE_BEFORE_WATERMARK**: Write drained items to the doc before advancing the drain watermark, so a mid-pass crash never silently loses feedback.
*   **¶INV_IDEMPOTENT_PROMOTION**: File-then-annotate carries a pre-write key so a crash never double-files a twin ticket.
*   **¶INV_RANKING_WITH_PROOFS**: Impact-ranking-with-proofs (a "pull this first, and why, with evidence" view) is the primary reserved seam — designed-for now, built next.
*   **¶INV_PROBLEM_DEPENDENCY_GRAPH**: The problem map is a dependency graph (nodes = problems/solutions; edges = stands-on / blocked-by / unlocks / needs-research-from), materialized as Linear issue relations + held readably in the working doc — so decomposition and the high-leverage sub-problem are visible, not buried in undifferentiated clumps.
*   **¶INV_RESEARCH_MEMORY**: Investigation done against a problem accumulates ON the problem (its ticket) — findings, dead-ends, why/when — never lost to a person or a dead session; no problem is attacked from zero twice. The system *enables* the conjecture (the big solution), it never claims to *generate* it.
