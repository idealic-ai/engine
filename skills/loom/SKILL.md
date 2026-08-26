---
name: loom
description: "Run many tickets as PARALLEL THREADS through one pipeline — each ticket woven triangulate→interrogate→build→scrutinize→snapshot→pr→council — while a conductor brokers file conflicts, relays messages between build agents, detects deadlocks, and escalates to you. A persistent session that keeps a live status ledger and never rushes to close: add threads, adjust a thread, or wrap up. Composes existing skills (/inbox-triangulate, /interrogate, /build, /scrutinize, /snapshot, /pr, /council); writes to Linear/git only through them. Triggers: \"loom these tickets\", \"parallel-build this batch\", \"weave these threads\", \"run an ultrabuild\", \"churn through these issues in parallel\"."
version: 1.0
tier: protocol
---

Weave many tickets through the build pipeline at once. `/loom` takes a batch of tickets, runs each as its own **thread** — triangulate → interrogate → build → scrutinize → snapshot → pr → council — and fans the threads out in parallel while a **conductor** (the parent) keeps them from colliding: it brokers who touches which files, relays messages between the build agents, detects deadlocks, and escalates the decisions that are genuinely yours. A live ledger tracks where every thread is; the session loops — you add threads, adjust a thread, or wrap up — and never rushes to close.

# /loom Protocol (The Conductor)

Execute §CMD_EXECUTE_SKILL_PHASES.

### What /loom is (and is not)

*   **It is** a **parallel-thread orchestrator**. A *thread* is one ticket walking the full chain; many threads run at once. `/loom` composes the building-block skills — it dispatches `/inbox-triangulate`, `/ticket`, `/communicate`, `/interrogate`, `/probe`, `/experiment`, `/build`, `/scrutinize`, `/snapshot`, `/pr`, `/council`, `/prove`, `/inbox-post`, `/inbox-next`, `/ticket-search` — and its own work is the conducting: partitioning files, relaying agent messages, brokering conflicts, detecting deadlocks, escalating, and keeping the ledger.
*   **It is NOT** a builder or a writer. `/loom` never writes code, never posts to Linear, never touches git directly (`¶INV_LOOM_COMPOSED_WRITES`). Every mutation happens *inside* a composed skill under that skill's own confirm — `/snapshot` posts the status and commits, `/pr` opens the PR. The conductor orchestrates; the sections do the work.
*   **`/loom` vs `/coordinate`**: `/coordinate` is a persistent fleet monitor that answers standing worker questions. `/loom` is task-scoped — it weaves a specific batch of tickets through a specific pipeline and closes when the batch is done. It reuses coordinate-grade relay/escalation mechanics without being an immortal monitor.
*   **`/loom` vs `/do`**: `/do` is one free-form thread of work. `/loom` is *many* threads at once with a conductor between them.

### The thread (`¶INV_LOOM_THREAD_IS_A_TICKET`)

A **thread** = one ticket/task through the full chain:

> triangulate → interrogate → build → scrutinize → snapshot → pr → council

The **interactive** front (triangulate, interrogate) and the **decision** points (triage, snapshot/pr confirms, council findings) involve you or the conductor; the **autonomous** middle (build, scrutinize) runs as parallel background agents. Not every stage fires on every thread — `/inbox-triangulate`, `/snapshot`, `/pr`, and `/council` are **offered** per the Setup dispositions and the offer-don't-force rule (`§INV_OFFER_DONT_FORCE_SKILLS`) — while the **ticket-disposition ask, interrogation** (per its disposition), and **scrutinize** are **mandatory** (`¶INV_LOOM_MANDATORY_STEPS`), never turned off by the Autonomy disposition.

### Thread identity & agent naming (`¶INV_LOOM_AGENTS_NAMED_BY_THREAD`)

Every thread gets a **threadId**: the ticket key `FIN-XXXX` when there is one, else a short SCREAMING slug the conductor derives from the task — `FACTS`, `INTRODOC` (≤8 chars, `[A-Z0-9]`, digit-suffixed on collision: `FACTS`, `FACTS2`) — for a **winged** (un-ticketed) task. A meaningful slug beats a bare letter: `FACTS:build` tells you what the thread is; `A:build` doesn't. Every agent `/loom` spawns belongs to a thread at a stage — `FIN-3141:build`, `FIN-3141:scrutinize`, `FACTS:build`.

**The fleet/status view shows the sub-agent TYPE (`builder`, `writer`, …), not a label you set — so the threadId will NOT appear on its own. You MUST push it into what the agent emits, or the threads are indistinguishable** (the exact symptom this rule exists to prevent). Two things, both required:
*   **Lead the spawn `description` with the threadId in brackets** — `description: "[FIN-3141] build extract-totals"`, `"[FACTS] scrutinize parser"`. That bracketed prefix is what surfaces in the status row next to the `builder`/`writer` type.
*   **Instruct the agent to prefix EVERY line it emits** — its status/progress reports, its shared-log entries, and its `SendMessage`s to the conductor — with `[<threadId>]`. A build agent's log entry reads `## [FIN-3141] tests green`, not `## tests green`. This is stated in `assets/LOOM_AGENT_DIRECTIONS.md`, which every agent's context pack carries.

This prefix is load-bearing: the ledger, the SendMessage relay, and the fleet view all tell threads apart by it. **Never spawn a loom agent whose `description` and output are not threadId-prefixed.** A winged thread's slug threadId **upgrades to the new `FIN-XXXX`** if a ticket is filed for it — the ticket create/update step runs *after* triangulate + interrogate, before the build, so the ticket carries the scoped understanding.

### The four Setup dispositions

Asked once at Setup (`AskUserQuestion`, one per disposition — not `§CMD_SELECT_MODE` mode files). They parameterize the whole session and the escalation/relay reference file:

*   **Autonomy** — how much the conductor decides vs. asks: **Automagic** (proceed autonomously; auto-resolve conflicts where safe; escalate only on the hard floor) · **Careful** (escalate liberally; gate more) · **Allow agents to decide** (agents use judgment on when to escalate; conductor relays). **Autonomy tunes how much the conductor *resolves without asking* — it NEVER licenses skipping a mandatory step.** Automagic that skips the ticket-disposition ask, the interrogation, or the scrutinize agent is a bug, not autonomy (`¶INV_LOOM_MANDATORY_STEPS`).
*   **Council** — *when* `/council` runs, chosen once: **selective before PR** (a panel *before* the PR opens, only on threads you flag) · **auto after each PR** *(default — a panel on every thread once its PR is up)* · **none** *(not recommended)*. The timing is the whole distinction: *before PR* reviews the work before it's proposed; *after PR* reviews the proposed change.
*   **Interrogation** — how much `/interrogate` runs per thread: **Reasonable** (a few rounds → `/interrogate --depth quick`) · **Thorough** (→ `--depth deep`) · **None** (skip the interrogate stage).
*   **Detail importance** — how much granular detail matters, i.e. how hard over-zealous `/scrutinize`/`/council` findings get filtered before they reach you: **Low / ship-it** (downgrade nitpicks; only genuinely-blocking MUST-FIX surfaces; lean on recommended defaults) · **Balanced** *(default)* · **High / every detail** (surface everything for explicit decision). Low does NOT mean auto-accept — a blocking finding always surfaces.

**Above-ceiling handling (`¶INV_LOOM_SIMPLIFY_DONT_SCARE`)**: when a technical fork would stall the operator, pose it as a **plain-language choice with a clear recommendation** and take the recommended default if they're unsure (noted in the ledger) — never raw technical internals. Escalate to a senior reviewer only for one-way doors.

### The conductor's job (`¶INV_LOOM_CONDUCTOR_RELAYS`)

While threads run, the parent: computes an up-front file partition; runs a live message relay (agents `SendMessage` the parent to claim out-of-partition files and report progress); brokers file conflicts **first-claim-wins** (`¶INV_LOOM_FIRST_CLAIM_WINS`, the later thread's conflicting step defers to the next wave); maintains a *waiting-on* graph (a cycle = deadlock) and polls agent status (silence past a timeout → probe → escalate); and escalates per the hard floor. The rules live in `assets/LOOM_AGENT_DIRECTIONS.md`, fed **by reference** into every build agent's context pack.

**Hard escalation floor (`¶INV_LOOM_HARD_ESCALATION_FLOOR`)** — these ALWAYS reach you, even under Automagic: the **per-thread ticket-disposition question** (always asked before a thread builds — Automagic never suppresses it) · a **cyclic deadlock** the conductor can't break by deferral · a thread's **build failing after retries** · a **scrutinize MUST-FIX** needing a fix/skip/defer call · a **thread loopback** (council/scrutinize → interrogate or build).

### No rush to close (`¶INV_LOOM_NO_RUSH_TO_CLOSE`)

The loop gate defaults to **keep going**, never "shall we close?". A session ends only when you say so. Durability rides in Linear + git (via the composed `/snapshot` + `/pr`), so a `/loom` session can end cleanly with threads still mid-flight — the ledger records where each stands.

### Phase shape

`/loom` is `Setup → Loom → Synthesis` — three phases, like `/do`. Intake and per-thread interrogation are **not** upfront phases: they happen **inside the Loom body every time you add a thread**, because you add threads throughout the session, not all at once. Synthesis is reached only by an **explicit** "wrap up" choice at the loop gate (`¶INV_LOOM_NO_RUSH_TO_CLOSE`).

### Session Parameters
```json
{
  "taskType": "LOOM",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["sessionDir", "parametersParsed", "contextSourcesPresented", "filesLoaded", "intentReported", "dispositions"], "gate": false},
    {"label": "1", "name": "Loom",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["intentReported", "threadsWoven", "threadDispositions", "ledgerMaintained", "logEntries"]},
    {"label": "2", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "2.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "2.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "2.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "2.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_OFFER_COUNCIL_REVIEW", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/loom", "/pr", "/snapshot", "/council"],
  "directives": ["PITFALLS.md", "CONTRIBUTING.md"],
  "logTemplate": "assets/TEMPLATE_LOOM_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_LOOM.md"
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Setting up a loom over ___. Trigger: ___.
> Focus: session activation, loading the in-scope tickets, choosing the four dispositions.
> Not: building or spawning agents — setup only.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the batch of tickets/tasks in play. Load them via `§CMD_INGEST_CONTEXT_BEFORE_WORK` (the `SRC_RELATED_TICKETS` + any `contextPaths` name the candidates).
*   **Ask the four dispositions** (`AskUserQuestion`, one question per disposition — Autonomy · Council · Interrogation · Detail importance). Record the choices as the `dispositions` proof and echo them into the ledger header. These parameterize every downstream stage and the escalation/relay reference file.

*Phase 0 proceeds to Phase 1 — no transition gate.*

---

## 1. Loom
*The main body — the persistent parallel weave. Adding a thread, interrogating it, building, conducting, and closing a thread all happen here.*

§CMD_REPORT_INTENT:
> 1: Weaving threads in parallel. Autonomy: ___. Council: ___. Interrogation: ___.
> Focus: add threads (ticket/triangulate/interrogate/partition), fan out named builds, relay + broker conflicts, scrutinize, triage, offer snapshot/pr, council per policy, keep the ledger live.
> Not: writing Linear/git directly, and never closing on its own — mutations go through composed skills; Synthesis is an explicit choice.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

This phase is the whole working body. It runs a persistent loop: you **add threads** (each scoped interactively as it enters, while other threads' builds run in the background), the conductor **weaves** them, and the loop ends only when you explicitly choose to wrap up (`¶INV_LOOM_NO_RUSH_TO_CLOSE`).

### Adding a thread (whenever you add one — not a batch upfront)
A background build agent cannot ask you questions, so a new thread is scoped here on the main thread, while other threads keep building. **Each step is marked `[MANDATORY]` (always happens — no Autonomy disposition turns it off) or `[OFFERED]` (you or the conductor may skip).** Autonomy tunes how much the conductor *resolves without asking*; it never decides *which steps run* (`¶INV_LOOM_MANDATORY_STEPS`).

**Adding several at once** — before scoping them, assess adjacency:
*   **Very adjacent / near-duplicative** → **`[OFFERED]` group them into ONE thread** (`§INV_OFFER_DONT_FORCE_SKILLS`) instead of parallel threads — one build, one PR. Grouping collapses them; you decide.
*   **Distinct but simultaneous** → keep separate threads, but **batch their interrogation**: run the interrogation forks in shared rounds (≤4 questions spanning threads) rather than one `/interrogate` per thread, so each thread's answers inform the others (fewer round-trips).

1.  **[MANDATORY] Assign a threadId** — `FIN-XXXX`, or a conductor-derived SCREAMING slug for a winged task (≤8 chars `[A-Z0-9]`, digit-suffixed on collision: `FACTS`, `FACTS2`). Open/append its ledger row (`TEMPLATE_LOOM_LOG.md`).
2.  **[OFFERED] `/inbox-triangulate`** (`§INV_OFFER_DONT_FORCE_SKILLS`) — `Skill(inbox-triangulate, "<ticket>")` to validate real/ripe before investing a build. A not-ripe result parks the thread. Skip for an already-triaged ticket.
3.  **[MANDATORY per the Interrogation disposition] Interrogate** — `Reasonable` → `Skill(interrogate, "<ticket> --depth quick")`; `Thorough` → `--depth deep`; `None` → skip. The **disposition** decides whether it runs — the conductor may NOT skip it when the disposition is Reasonable/Thorough, and may NOT substitute an inline chat exchange for the dispatched `/interrogate`. The digest (`builds/<slug>_INTERROGATE.md`) is the scope half of the thread's build context pack.
4.  **[OFFERED] De-risk the scope** (`§INV_OFFER_DONT_FORCE_SKILLS`) — when interrogation surfaced an **open question** or an **unproven approach**, de-risk before investing a build. Most threads skip this; it's for the ones with a real unknown. Distinct from triangulate (which validates the *problem*): these de-risk the *solution*.
    *   **`/probe`** — a directed, read-only investigation for an open question. `Skill(probe, "<the question>")` sweeps code / DB / tickets and returns an answer-first report. Always safe — it writes nothing, so it needs no partition.
    *   **`/experiment`** — a feasibility spike to prove an approach works. `Skill(experiment, "<hypothesis>")` writes + runs code in-tree and returns a proved / disproved / inconclusive verdict. **It touches files while other threads build in parallel, so it MUST respect the partition** — claim its files first (or run in an isolated worktree), never write another thread's territory (`§INV_NO_DESTRUCTIVE_GIT`, first-claim-wins). Run it here, *before* this thread's partition is finalized (step 6), so its kept files fold into the thread's own set.
    The probe report / experiment verdict joins the thread's build context pack alongside the interrogation digest, and can reshape the ticket disposition (next) and the scope.
5.  **[MANDATORY — always ASK] Ticket disposition** (`AskUserQuestion`, composed-writes only) — asked **here, after triangulate + interrogate**, so the ticket reflects the scoped understanding before the build. **The question ALWAYS reaches you** (its answer may be "keep as-is"); it is never skipped by proximity to the offered steps, and Automagic never suppresses it. Three ways:
    *   **Create a new ticket** — `Skill(ticket, "<task>")` for a winged task, framed from the findings; on creation, upgrade the slug threadId to the new `FIN-XXXX`.
    *   **Update the existing ticket** — post the scoped understanding via `/snapshot` or `/communicate`, so it's current before the build.
    *   **Keep it here as-is** — no ticket action; runs against its current ticket, or un-ticketed with its slug.
    Every write happens inside the composed skill under its own confirm (`¶INV_LOOM_COMPOSED_WRITES`).
6.  **[MANDATORY] Merge into the file partition** — assign a disjoint file set (the `§CMD_PARALLEL_HANDOFF` non-intersection proof) against the currently-running threads; on overlap the thread queues until the conflicting files free (first-claim-wins).
7.  **[MANDATORY] Fan out its build — a concurrent /build-grade AGENT** — spawn a background builder **agent** (Agent/Task tool) with its `description` **leading with the bracketed threadId** (`description: "[FIN-3141] build extract-totals"`) and a full `/build`-grade context pack (goal + interrogation digest + file partition + hard gates + scope guard + `assets/LOOM_AGENT_DIRECTIONS.md` by reference, which tells it to prefix every line with `[<threadId>]`). **Never `Skill(build)`: the Skill tool is sequential, so a `Skill(build)` call blocks the loop and serializes the very parallelism loom exists for. Loom is carved OUT of `§INV_PREFER_BUILD_SCRUTINIZE`'s "prefer /build" wording — its fan-out is /build-*grade agents* run concurrently, not the /build *skill* in-line.**

### Conducting (continuous, while builds run)
*   **Relay** agent `SendMessage`s: grant out-of-partition file claims when unclaimed; broker conflicts **first-claim-wins** (loser's step defers); maintain the *waiting-on* graph (a cycle = deadlock); poll agent status (silence past a timeout → probe). Escalate per the **hard floor**.
*   **[MANDATORY] Scrutinize on land** — as each thread's build finishes, spawn a concurrent **scrutinize AGENT** (`description: "[<threadId>] scrutinize …"`, threadId-prefixed like the build) — a `/scrutinize`-grade critique of its Build Report — **never `Skill(scrutinize)` (it serializes the critiques)**. Scrutinize ALWAYS runs; the **Detail-importance** disposition filters which findings reach you, never *whether* the critique happens (`¶INV_LOOM_MANDATORY_STEPS`). Run a combined triage across threads (fix / skip / defer), then dispatch fixers.
*   **Offer `/snapshot` then `/pr`** per landed thread (`§INV_OFFER_DONT_FORCE_SKILLS`, composed-writes) — `/snapshot` posts status + commits the reviewed files; `/pr` opens the PR. Advance the ledger.
*   **Council per policy** — run `/council` per the **Council disposition**: *auto after each PR* runs a panel once a thread's PR is up; *selective before PR* runs one **before** the PR opens, only on threads you flag; *none* skips it. A council MUST-FIX is a **thread loopback** — escalate, and on confirm loop that thread back to interrogate or build (for a before-PR panel, that loopback happens before the PR ever opens).
*   **Closing snapshot before the proof** — after council settles (and after any PR-review / CI-gate fix cycle it triggered), **run a final `/snapshot`** on the thread. The earlier snapshot committed the reviewed *build* and opened the PR; this one **commits everything that landed since** — the council MUST-FIX fixes, the PR-review and gate fixes — and **advances the ticket to `In Review`** (the PR is up and reviewed; loom does not merge, so In Review is the state a thread lands on). It's the thread's closing checkpoint: `/snapshot` commits the thread's files scoped + gated on green, posts a closing comment, and flips the status (non-regressing) — all under its own batch confirm (`¶INV_LOOM_COMPOSED_WRITES`). Run it **before** the auto-proof, so the proof reflects the fully-committed, review-settled state and links the final commit.
*   **Auto-prove a completed thread** — once a thread reaches its **done** state (its PR is up, council has settled, and the closing snapshot has committed the fixes + moved the ticket to In Review — loom opens PRs but does not merge them, so this is the terminal state a thread reaches inside the session), **automatically run `/prove`** to compile the thread's work into a shareable visual proof at a public URL. It runs **without a gate**: `/prove` is read-only and silent — it changes no code, commits nothing, files nothing, and self-skips when there is no renderable evidence — so there is nothing to confirm. Hand it the **whole thread context**: its `builds/<slug>_*` trail (the interrogation digest, any probe/experiment output, the Build Report, the `/scrutinize` critique, the council report) plus the ticket + PR links and the ledger row. **Frame it as a before/after** — the proof's job here is to make two things legible at a glance: **the problem that existed** (from the ticket + interrogation digest — what was broken or missing) and **the evidence it's now solved** (the change, its verification, the PR). Invoke as `Skill(prove, "<slug> — problem: <what was broken/needed>; solved: <what shipped + how it's verified>")`. `/prove` trusts the trail (it re-presents the work, never re-investigates). Record the returned proof URL on the thread's ledger row.
*   **Harvest good findings at thread end** (`§INV_OFFER_DONT_FORCE_SKILLS`, composed-write) — when a thread finishes its chain, read its Build Report's `## Out-of-scope noticed (not touched)` section plus any `/scrutinize` deferrals, and **offer `/inbox-post` for the genuinely notable ones only** — real bugs, concrete follow-up work worth tracking — not every incidental note. Post each via `Skill(inbox-post, "<finding>")`, which routes it to the right inbox channel. Be selective: a thread that surfaced nothing worth filing posts nothing.
*   **Find the next thread at thread end** (`§INV_OFFER_DONT_FORCE_SKILLS`) — when a thread lands and the loom has capacity, offer to pull more work: `Skill(inbox-next)` when the batch came from a curated Linear project (ranked, in-project) or `Skill(ticket-search, "<keywords>")` to find related tickets by keyword. A chosen result becomes a new thread (the add-a-thread flow). This is how the no-rush loop refills itself.
*   **Keep the ledger live** — rewrite it as threads advance; surface it at each loop gate. Per thread, record its **mandatory-step completion**: the ticket-disposition answer, whether interrogation ran (or was skipped because the Interrogation disposition is None), and the scrutinize agent's id. This record IS the `threadDispositions` proof that gates Loom→Synthesis (`¶INV_LOOM_MANDATORY_STEPS`) — you cannot close a loom whose threads skipped their mandatory steps.

### The loop gate (`AskUserQuestion`, defaults to keep-going per `¶INV_LOOM_NO_RUSH_TO_CLOSE`)
Present after each unit of progress (a thread landing, a batch of builds finishing):
> "The loom is running. What next?"
> - **"Add a thread"** — scope + fan out a new thread (the add-a-thread flow above). The session stays open.
> - **"Adjust a thread"** — loop a thread back (council/scrutinize → interrogate or build), or re-triage.
> - **"Keep weaving"** — nothing to add; let running threads continue, re-present when the next lands.
> - **"Wrap up"** — proceed to Synthesis. **Only** when you explicitly choose it.

If the user explicitly says "done"/"close", skip the gate and proceed to Synthesis.

---

## 2. Synthesis
*Reached only by an explicit "wrap up". The batch is woven; close it out.*

§CMD_REPORT_INTENT:
> 2: Synthesizing. ___ threads landed.
> Focus: final ledger, debrief, pipeline, close.
> Not: starting new threads — wrapping up.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Debrief notes** (for `LOOM.md`):
*   **Final ledger** — every thread, its terminal stage, ticket + PR links, status.
*   **The weave** — which threads ran in parallel, what serialized and why, conflicts brokered, deadlocks/escalations.
*   **Dispositions** — the four choices and how they played out (what got filtered, what escalated).
*   **Leftovers** — threads parked (not ripe) or mid-flight, with where each stands.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Loom complete. Walk through the threads?"
  debriefFile: "LOOM.md"
```

**Post-Synthesis**: If the user keeps talking, obey `§CMD_RESUME_AFTER_CLOSE`.

---

## Constraints

*   **`¶INV_LOOM_COMPOSED_WRITES`**: `/loom` never writes code, Linear, or git directly. Every mutation goes through a composed skill (`/build`, `/snapshot`, `/pr`) under that skill's own confirm.
*   **`¶INV_LOOM_AGENTS_NAMED_BY_THREAD`**: every spawned agent leads its Agent `description` with `[<threadId>]` AND prefixes every line it emits (status, shared-log entry, `SendMessage`) with `[<threadId>]`. The fleet view shows the sub-agent type, not a label, so the prefix is the only thing that tells threads apart — no unprefixed loom agents.
*   **`¶INV_LOOM_MANDATORY_STEPS`**: per thread, the ticket-disposition ask, interrogation (per the Interrogation disposition), and the scrutinize agent are MANDATORY — the Autonomy disposition tunes how much the conductor resolves without asking, never *which steps run*. Build and scrutinize fan out as concurrent AGENTS, never `Skill(build)`/`Skill(scrutinize)` (which serialize the loop). The `threadDispositions` proof gates Loom→Synthesis on their completion.
*   **`¶INV_LOOM_NO_RUSH_TO_CLOSE`**: the loop gate defaults to keep-going. The session closes only on the user's explicit choice.
*   **`¶INV_LOOM_HARD_ESCALATION_FLOOR`**: cyclic deadlock · build-fails-after-retries · scrutinize MUST-FIX · thread loopback always reach the user, even under Automagic.
*   **`§INV_NO_DESTRUCTIVE_GIT`**: parallel builders never run tree/index-destructive git. Committing is `/snapshot`'s job.
*   **`§INV_OFFER_DONT_FORCE_SKILLS`**: triangulate, snapshot, pr, council are offered, never forced.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file (the ledger's table lives in the emitted `TEMPLATE_LOOM_LOG.md`, where tables are allowed).
