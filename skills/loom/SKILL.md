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

*   **It is** a **parallel-thread orchestrator**. A *thread* is one ticket walking the full chain; many threads run at once. `/loom` composes the building-block skills — it dispatches `/inbox-triangulate`, `/ticket`, `/communicate`, `/interrogate`, `/build`, `/scrutinize`, `/snapshot`, `/pr`, `/council` — and its own work is the conducting: partitioning files, relaying agent messages, brokering conflicts, detecting deadlocks, escalating, and keeping the ledger.
*   **It is NOT** a builder or a writer. `/loom` never writes code, never posts to Linear, never touches git directly (`¶INV_LOOM_COMPOSED_WRITES`). Every mutation happens *inside* a composed skill under that skill's own confirm — `/snapshot` posts the status and commits, `/pr` opens the PR. The conductor orchestrates; the sections do the work.
*   **`/loom` vs `/coordinate`**: `/coordinate` is a persistent fleet monitor that answers standing worker questions. `/loom` is task-scoped — it weaves a specific batch of tickets through a specific pipeline and closes when the batch is done. It reuses coordinate-grade relay/escalation mechanics without being an immortal monitor.
*   **`/loom` vs `/do`**: `/do` is one free-form thread of work. `/loom` is *many* threads at once with a conductor between them.

### The thread (`¶INV_LOOM_THREAD_IS_A_TICKET`)

A **thread** = one ticket/task through the full chain:

> triangulate → interrogate → build → scrutinize → snapshot → pr → council

The **interactive** front (triangulate, interrogate) and the **decision** points (triage, snapshot/pr confirms, council findings) involve you or the conductor; the **autonomous** middle (build, scrutinize) runs as parallel background agents. Not every stage fires on every thread — `/inbox-triangulate`, `/snapshot`, `/pr`, and `/council` are offered per the Setup dispositions and the offer-don't-force rule (`§INV_OFFER_DONT_FORCE_SKILLS`).

### Thread identity & agent naming (`¶INV_LOOM_AGENTS_NAMED_BY_THREAD`)

Every thread gets a **threadId**: the ticket key `FIN-XXXX` when there is one, else a letter `A` / `B` / `C` for a **winged** (un-ticketed) task. Every agent `/loom` spawns is **named `<threadId>:<stage>`** — `FIN-3141:build`, `FIN-3141:scrutinize`, `A:build`. This is load-bearing: the ledger, the SendMessage relay, and FleetView all identify a thread and its current step by that name. Never spawn an unnamed loom agent. A winged thread's letter threadId **upgrades to the new `FIN-XXXX`** if a ticket is filed for it — the ticket create/update step runs *after* triangulate + interrogate, before the build, so the ticket carries the scoped understanding.

### The four Setup dispositions

Asked once at Setup (`AskUserQuestion`, one per disposition — not `§CMD_SELECT_MODE` mode files). They parameterize the whole session and the escalation/relay reference file:

*   **Autonomy** — how much the conductor decides vs. asks: **Automagic** (proceed autonomously; auto-resolve conflicts where safe; escalate only on the hard floor) · **Careful** (escalate liberally; gate more) · **Allow agents to decide** (agents use judgment on when to escalate; conductor relays).
*   **Council** — **selective before PR** · **auto after each PR** *(default)* · **none** *(not recommended)*. Council runs after the PR.
*   **Interrogation** — how much `/interrogate` runs per thread: **Reasonable** (a few rounds → `/interrogate --depth quick`) · **Thorough** (→ `--depth deep`) · **None** (skip the interrogate stage).
*   **Detail importance** — how much granular detail matters, i.e. how hard over-zealous `/scrutinize`/`/council` findings get filtered before they reach you: **Low / ship-it** (downgrade nitpicks; only genuinely-blocking MUST-FIX surfaces; lean on recommended defaults) · **Balanced** *(default)* · **High / every detail** (surface everything for explicit decision). Low does NOT mean auto-accept — a blocking finding always surfaces.

**Above-ceiling handling (`¶INV_LOOM_SIMPLIFY_DONT_SCARE`)**: when a technical fork would stall the operator, pose it as a **plain-language choice with a clear recommendation** and take the recommended default if they're unsure (noted in the ledger) — never raw technical internals. Escalate to a senior reviewer only for one-way doors.

### The conductor's job (`¶INV_LOOM_CONDUCTOR_RELAYS`)

While threads run, the parent: computes an up-front file partition; runs a live message relay (agents `SendMessage` the parent to claim out-of-partition files and report progress); brokers file conflicts **first-claim-wins** (`¶INV_LOOM_FIRST_CLAIM_WINS`, the later thread's conflicting step defers to the next wave); maintains a *waiting-on* graph (a cycle = deadlock) and polls agent status (silence past a timeout → probe → escalate); and escalates per the hard floor. The rules live in `assets/LOOM_ESCALATION_RELAY.md`, fed **by reference** into every build agent's context pack.

**Hard escalation floor (`¶INV_LOOM_HARD_ESCALATION_FLOOR`)** — these ALWAYS reach you, even under Automagic: a **cyclic deadlock** the conductor can't break by deferral · a thread's **build failing after retries** · a **scrutinize MUST-FIX** needing a fix/skip/defer call · a **thread loopback** (council/scrutinize → interrogate or build).

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
      "proof": ["intentReported", "threadsWoven", "ledgerMaintained", "logEntries"]},
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
A background build agent cannot ask you questions, so a new thread is scoped here on the main thread, while other threads keep building:
1.  **Assign a threadId** — `FIN-XXXX`, or a letter for a winged task. Open/append its ledger row (`TEMPLATE_LOOM_LOG.md`).
2.  **Offer `/inbox-triangulate`** (`§INV_OFFER_DONT_FORCE_SKILLS`) — `Skill(inbox-triangulate, "<ticket>")` to validate real/ripe before investing a build. A not-ripe result parks the thread. Skip for an already-triaged ticket.
3.  **Interrogate per the Interrogation disposition** — `Reasonable` → `Skill(interrogate, "<ticket> --depth quick")`; `Thorough` → `--depth deep`; `None` → skip. The digest (`builds/<slug>_INTERROGATE.md`) is the scope half of the thread's build context pack.
4.  **Ask the thread's ticket disposition** (`AskUserQuestion`, `§INV_OFFER_DONT_FORCE_SKILLS`, composed-writes only) — asked **here, after triangulate + interrogate**, so the ticket reflects the scoped understanding before the build (a fresh ticket is framed from real findings; an existing one is updated with them). Three ways:
    *   **Create a new ticket** — `Skill(ticket, "<task>")` for a winged task, framed from the triangulation + interrogation findings; on creation, upgrade the letter threadId to the new `FIN-XXXX`.
    *   **Update the existing ticket** — post the scoped understanding to the thread's ticket via `/snapshot` or `/communicate`, so it's current before the build.
    *   **Keep it here as-is** — no ticket action; the thread runs against its current ticket, or un-ticketed with its letter.
    Every write happens inside the composed skill under its own confirm (`¶INV_LOOM_COMPOSED_WRITES`).
5.  **Merge into the file partition** — assign a disjoint file set (the `§CMD_PARALLEL_HANDOFF` non-intersection proof) against the currently-running threads; on overlap the thread queues until the conflicting files free (first-claim-wins).
6.  **Fan out its build — named, background, /build-grade** — spawn `<threadId>:build` with a full `/build` context pack (goal + interrogation digest + file partition + hard gates + scope guard + `assets/LOOM_ESCALATION_RELAY.md` by reference). Prefer `/build` (`§INV_PREFER_BUILD_SCRUTINIZE`).

### Conducting (continuous, while builds run)
*   **Relay** agent `SendMessage`s: grant out-of-partition file claims when unclaimed; broker conflicts **first-claim-wins** (loser's step defers); maintain the *waiting-on* graph (a cycle = deadlock); poll agent status (silence past a timeout → probe). Escalate per the **hard floor**.
*   **Scrutinize on land** — as each `<threadId>:build` finishes, spawn `<threadId>:scrutinize` (a `/scrutinize`-grade critique of its Build Report). Filter findings by the **Detail-importance** disposition before they reach you. Run a combined triage across threads (fix / skip / defer), then dispatch fixers.
*   **Offer `/snapshot` then `/pr`** per landed thread (`§INV_OFFER_DONT_FORCE_SKILLS`, composed-writes) — `/snapshot` posts status + commits the reviewed files; `/pr` opens the PR. Advance the ledger.
*   **Council per policy** — after a thread's PR, run `/council` per the **Council disposition**. A council MUST-FIX is a **thread loopback** — escalate, and on confirm loop that thread back to interrogate or build.
*   **Keep the ledger live** — rewrite it as threads advance; surface it at each loop gate.

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
*   **`¶INV_LOOM_AGENTS_NAMED_BY_THREAD`**: every spawned agent is named `<threadId>:<stage>`. No unnamed loom agents.
*   **`¶INV_LOOM_NO_RUSH_TO_CLOSE`**: the loop gate defaults to keep-going. The session closes only on the user's explicit choice.
*   **`¶INV_LOOM_HARD_ESCALATION_FLOOR`**: cyclic deadlock · build-fails-after-retries · scrutinize MUST-FIX · thread loopback always reach the user, even under Automagic.
*   **`§INV_NO_DESTRUCTIVE_GIT`**: parallel builders never run tree/index-destructive git. Committing is `/snapshot`'s job.
*   **`§INV_OFFER_DONT_FORCE_SKILLS`**: triangulate, snapshot, pr, council are offered, never forced.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file (the ledger's table lives in the emitted `TEMPLATE_LOOM_LOG.md`, where tables are allowed).
