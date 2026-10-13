---
name: loom-experiment
description: "Run many EXPERIMENTS as parallel threads under one conductor that spends money on purpose: each question goes $0 census/replay first, then — only if money has to be spent — a pre-registered, placebo-controlled paid arm scored by a verdict tool, an adversarial review, and a landing that turns on in code once it is reviewed and measured, with no new flag. A persistent session with a budget ledger recounted from receipts, a fixed model tier, a live thread ledger, operator rulings kept verbatim, and a proof page per thread. Rigor scales with the stakes: a $0 question is just answered and written down; the full machinery runs only when money is spent or behaviour is about to change. Guides the user through building the measurement tooling (scorer, census, replay, verdict, held-out ledger, spend ledger, checks) when it is missing. The experimentation sibling of /loom. Triggers: \"loom experiments\", \"spend budget to improve X\", \"run experiments overnight\", \"measure and improve\", \"experiment loom\", \"try things and land what works\"."
version: 1.3
tier: protocol
---

Spend money on purpose to find out what works, and land only what the measurement earns. `/loom-experiment` runs many experiment **threads** at once — each one a question walked from a free look at stored data, through a paid arm only when it is needed, to a verdict, a review, and a landing or a parked negative result — while a **conductor** keeps the budget, the model tier, the held-out documents, the shared runtime and the operator's rulings straight. It never rushes to close.

# /loom-experiment Protocol (The Experiment Conductor)

Execute §CMD_EXECUTE_SKILL_PHASES.

### What it is, and what it is not

*   **It is** `/loom` turned into an experimentation conductor. It keeps loom's machinery — threads, agents named by threadId (`¶INV_LOOM_AGENTS_NAMED_BY_THREAD`), composed writes, the live ledger, no rush to close, a proof page per thread (`¶INV_LOOM_EVERY_THREAD_PROVES`) — and adds a budget, a verdict discipline, tooling, and a landing path.
*   **It is not** a ticket pipeline. Use `/loom` to ship a batch of known work. Use `/experiment` for one quick in-tree spike. Use this when the answer is unknown, costs money to find, and should change what ships.
*   **Who it is for**: an operator with a budget, a system whose outputs can be stored and re-scored (an LLM pipeline, a ranking, a parser, a prompt), and a willingness to hear "no effect".

### Rigor scales with the stakes (`¶INV_EXP_RIGOR_SCALES_WITH_STAKES`)

Decide the tier of every thread when it enters, write it on its ledger row, and do only what that tier asks.

*   **Light — a $0 question.** A census, a replay, a read of stored outputs, a probe. Answer it, write the answer to a file with denominators and a date, prove it, done. No pre-registration.
*   **Registered — money is spent to answer.** The design is sealed and the run registered before the first paid call; a placebo, derived held-out documents, document-level statistics and a verdict tool decide. See `assets/EXPERIMENT_ORGANIZATION.md`.
*   **Landing — behaviour is about to change.** A verdict (or an operator ruling that names its evidence class), an adversarial review until it approves, the knock-on cost priced, the change measured and then turned on in code — no new flag or environment switch.

When a default is available, take it, say so in one line, and flag it in the ledger. Ask only what changes money, scope or what ships — and ask with a recommendation (`¶INV_EXP_ASK_WITH_A_RECOMMENDATION`).

### The thread

> question → $0 look → (tooling) → design + register → paid arm → verdict → review → land or park → proof

A Light thread stops after the $0 look and its proof. Tooling appears only when the instrument the thread needs does not exist (`¶INV_EXP_TOOLING_IS_WORK`) — it then becomes a thread of its own.

### Session Parameters
```json
{
  "taskType": "LOOM_EXPERIMENT",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["sessionDir", "parametersParsed", "contextSourcesPresented", "filesLoaded", "intentReported", "dispositions", "inventory", "commonBrief"], "gate": false},
    {"label": "1", "name": "Loom",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["intentReported", "threadsWoven", "threadDispositions", "spendLedger", "verdictsRecorded", "ledgerMaintained", "proofPages", "logEntries"]},
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
  "nextSkills": ["/loom-experiment", "/loom", "/council", "/prove"],
  "directives": ["PITFALLS.md", "INVARIANTS.md", "CONTRIBUTING.md"],
  "logTemplate": "assets/TEMPLATE_LOOM_EXPERIMENT_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_LOOM_EXPERIMENT.md"
}
```

### Assets — load on demand

*   `assets/EXPERIMENT_DIRECTIONS.md` — every lane brief carries it by reference. The lane's rules.
*   `assets/EXPERIMENT_ORGANIZATION.md` — folder layout, phrasing a question, the ladder of checks, statistics, what an actionable finding looks like. Read before designing a Registered thread.
*   `assets/TOOLING.md` — the measurement instruments, their smallest useful version, and how each one went wrong. Read at Setup and whenever a thread needs an instrument.
*   `assets/INVARIANTS.md` — every `¶INV_EXP_*` rule with its Rule, Redirection and measured reason.
*   `assets/PITFALLS.md` — the `¶PTF_*` catalogue. Consult it when something looks odd, and before sealing a design.
*   Templates: `TEMPLATE_EXPERIMENT_DESIGN.md` (the pre-registration), `TEMPLATE_LOOM_EXPERIMENT_LOG.md`, `TEMPLATE_LOOM_EXPERIMENT.md` (debrief), `TEMPLATE_MORNING_QUESTIONS.md`.

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Setting up an experiment loom over ___. Goal: ___.
> Focus: budget, model tier, dispositions, the inventory of data and tooling, the common brief.
> Not: spending — nothing paid runs in Setup.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

1.  **Scope and goal.** What should get better, measured how, and what is out of scope. Load context via `§CMD_INGEST_CONTEXT_BEFORE_WORK`, including any project experiment docs, settled findings, negative results and closed avenues — a large share of promising ideas are already settled.
2.  **Dispositions** — one `AskUserQuestion`, recommended option first on each:
    *   **Budget** — a session ceiling and a default per-lane cap. Recommended: the ceiling the operator names, a cap per lane, and a reserve held back.
    *   **Model tier** — which models paid calls may use. Recommended: the cheapest tier that does the job; a stronger model only as a capped tie-break judge by standing permission (`¶INV_EXP_MODEL_TIER_IS_THE_OPERATORS`).
    *   **Money or turnaround** — recommended: money. If the operator rules turnaround (now or later), lanes prefer the standard service tier where a discounted one stalls, run more in parallel, and choose pools that already have gold; registration and verdicts do not relax (`¶INV_EXP_TURNAROUND_IS_THE_OPERATORS_CALL`).
    *   **Landing authority** — recommended: a lane's change is ready to fold when the verdict is LAND and an adversarial review approves; the integrator folds it; switch-on still waits for measurement and the operator's go; anything contested waits for the operator with the numbers.
    *   **Proof publishing** — where proof pages may go given the data they show. Ask; never assume a channel is private (`¶PTF_PRIVATE_CHANNEL_THAT_ISNT`).
3.  **Inventory** — write one `## 📦 Inventory` log entry naming what exists and what is missing:
    *   the stored data: which outputs are kept, their bodies, how many documents, how many are still unread by any lever (the standing never-read pool), and which are held out per lever (`¶INV_EXP_REUSE_BY_LEVER_AND_CONTACT`);
    *   the runtime: shared workers, queues, stores, and how a private worker is started;
    *   the instruments, checked against `assets/TOOLING.md`: scorer, census, replay, verdict, held-out ledger, registration, spend ledger, checks, judges, proof pages;
    *   spend so far, from receipts.
    Each missing instrument a Registered thread will need becomes a proposed tooling thread, offered with a recommendation and a size. Build the smallest version the next experiment needs (`¶INV_EXP_TOOLING_IS_WORK`).
4.  **Common brief** — write `COMMON_BRIEF.md` in the session: the operator's intent verbatim, standing rulings, the budget and tier, money or turnaround, the switch-number registry (prompt revision numbers and bundle component names, each with its owner, and the next free number — `¶INV_EXP_SWITCH_NUMBERS_FROM_ONE_REGISTRY`), how to run a paid arm here (private worker and queues, store, credentials by reference only), the landing rule, the report and proof rules, and `assets/EXPERIMENT_DIRECTIONS.md` by reference. Every lane gets it. Append each new ruling to it and broadcast to running lanes.

*Phase 0 proceeds to Phase 1 — no transition gate.*

---

## 1. Loom
*The persistent body. Threads enter, run, land or park, and prove. The session closes only on the operator's word.*

§CMD_REPORT_INTENT:
> 1: Running experiment threads. Budget ___ of ___ spent (receipts). Model tier: ___.
> Focus: $0 first, register before paying, verdicts from the tool, reviews before landing, the spend ledger live.
> Not: spending past a cap, landing on prose, or closing on its own.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### Adding a thread

1.  **Name it** — threadId and ledger row as in `/loom`. The conductor assigns the experiment number and claims it in the ledger, and assigns revision and switch numbers from the registry in `COMMON_BRIEF.md`; lanes never self-number.
2.  **Phrase the question so the answer changes a decision** — "if yes we do X, if no we do Y" — and write its tier. Check settled findings and closed avenues first; a thread that reopens a closed avenue needs a reason.
3.  **$0 look first** (`¶INV_EXP_FREE_BEFORE_PAID`) — a census, replay or prototype over stored data. It sizes the prize before anything is built; a rare defect may earn a report-only check instead of a build. Many threads end here as Light.
4.  **Choose the lever** — follow the project's lever ladder in the order the operator ruled: prompt or schema before code that rewrites model output, which comes last and needs the operator's OK; within a class, cheapest first; after two or three arms of one class fail on the same failure, move to the next class (`¶INV_EXP_LEVERS_IN_THE_OPERATORS_ORDER`). Any change that touches what is sent to a provider checks the provider's limits first (`¶INV_EXP_SCHEMA_LIMITS_ARE_GATED`). Prefer bundles: when several prompt or schema changes touch the same stage, test them as one registered bundle with a switch per component; run a single lever only when it is risky, conflicts with another, or adds schema shape (`¶INV_EXP_BUNDLE_SAME_STAGE_CHANGES`; *Designing a bundle* in `assets/EXPERIMENT_ORGANIZATION.md`).
5.  **Price the knock-on before building** (`¶INV_EXP_PRICE_THE_KNOCK_ON`) — what landing it re-reads or re-asks, priced three ways: lazy (on each item's next natural run), re-derive all now, only the changed ones.
6.  **If paying: dry-run, design and register** — dry-run the base arm at $0 through every downstream stage the metric reads and size the movers from that (`¶INV_EXP_DRY_RUN_DOWNSTREAM`). Fill `assets/TEMPLATE_EXPERIMENT_DESIGN.md` with a sealed null even when the arms are deterministic (`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`) the gold version (`¶INV_EXP_GOLD_IS_VERSIONED`), each placebo's role (`¶INV_EXP_PLACEBO_ALWAYS`), and guards that carry a null check, a planted-harm positive control and the repeat count they were calibrated at (`¶INV_EXP_GUARDS_HAVE_TWO_CONTROLS`, `¶INV_EXP_GUARD_CALIBRATION_PINS_THE_REPEATS`), seal it, pass preflight, run the verdict dry-run (`finch-sdk study preseal --design <file> --stages <every stage the run writes>`) against a freshly regenerated ledger — the stages are the ones the run's entry point actually writes, receipt paths included, and each must be a declared lever (`¶PTF_STAGE_LEVER_MISMATCH`) — and continue only on PRESEAL OK, and register and launch in one command right before the first call (`¶INV_EXP_REGISTER_BEFORE_THE_FIRST_CALL`). Choose documents per lever: reuse what the rule allows, exclude what the lane looked at while designing the change, and screen the standing never-read pool at $0 before any new draw (`¶INV_EXP_REUSE_BY_LEVER_AND_CONTACT`). Claim the documents by cluster in the shared claims file.
7.  **Dispatch the lane** — a background agent, `[threadId]`-prefixed, with a brief carrying: the question, tier, cap, model tier, the design path, the partition, `COMMON_BRIEF.md` and `assets/EXPERIMENT_DIRECTIONS.md` by reference, and an absolute report path of the form `builds/<slug>/<SLUG>_REPORT.md` (round N: `<SLUG>_REPORT_rN.md`) — Claude Code's Write tool refuses a subagent's `.md` file whose basename starts with REPORT, SUMMARY, FINDINGS or ANALYSIS, so the lane prefix goes first. The lane returns the full report in its hand-back; the conductor saves any report that is not on disk to that path (`¶INV_EXP_ANSWERS_GO_TO_DISK`). Paid arms run on a private worker and private queues against pinned code (`¶INV_EXP_PAID_ARMS_RUN_PRIVATE`).

### Conducting (continuous)

*   **Spend ledger** — recount from lane receipts at every report; keep committed caps beside spent; refuse a new paid thread that would breach the ceiling. Log each change as a `## 💰 Spend` entry.
*   **Relay and broker** as in `/loom`: file partition, first-claim-wins, the waiting-on graph. Shared derived state that verdicts depend on (a touch ledger, cluster files) regenerates one lane at a time under the conductor's turn.
*   **Verdicts** — record each verdict word verbatim from the tool with its evidence class (`¶INV_EXP_VERDICT_WORDS`). A NO VERDICT names what was missing; a procedural one is a tooling lesson, not a technicality.
*   **Review every landing** (`¶INV_EXP_EVERY_LANDING_IS_REVIEWED`) — a fresh critiquer agent per change; fix rounds until APPROVE; split MUSTs into "before merge" and "before switch-on"; re-review any fix round that changed code. Code changed after the verdict is replayed at $0 against the measured experiment before the landing cites it (`¶INV_EXP_REPLAY_AFTER_THE_VERDICT`).
*   **Integrator lane** (`¶INV_EXP_ONE_INTEGRATOR_FOLDS`) — lanes push reviewed branches and stop; one integrator at a time folds the ready ones into the integration branch, gets each conflict resolution reviewed, re-runs type checks and a $0 replay at every new head, and keeps the PR body current. Dispatch the next integrator once the previous one has exited and two or more branches are ready, or one ready branch has waited past the next integration restart, or the operator asks.
*   **Production-safety review** (`¶INV_EXP_PRODUCTION_SAFETY_BEFORE_SHIPPING`) — before the integrated work ships to production, a read-only review of the whole release as it will deploy: migrations and one-way doors, what an automatic rollback restores, ungated changes, old and new code side by side. Its findings go to the operator as questions with a recommendation.
*   **Land on in code** (`¶INV_EXP_SHIP_OFF_THEN_DEFAULT_IN_CODE`) — measure through the harness's per-run override, then turn it on in code once the review approves and the measurement holds; "off" is a short staging step, not a resting state. Add no new flag or environment switch; where a gate is unavoidable, reuse an existing one. Before loosening any protection, check the land-held record (`¶INV_EXP_LANDS_HAVE_A_COUNTER_METRIC`). Batch reviewed changes into one integration restart with a clean cutover (`¶INV_EXP_ONE_INTEGRATION_RESTART`).
*   **Park honestly** — a negative result is committed with its folder, what would overturn it, and a line in the project's negative-results list.
*   **Reliability** — a lane killed by a limit or a safeguard is resumed by id: "resume; check disk, store and git; don't repeat paid calls" (`¶INV_EXP_RESUME_BY_ID`). After a harness restart old ids no longer resume: write a recovery preamble in the session once (read the common brief and the log from the restart, recover worktree, build files, receipts and run outputs, count what an in-flight paid run bought, log "recovered", then continue) and spawn each lane fresh with its brief plus the preamble. A hand-back from a lane whose name is lost is recovered from disk before anyone acts on it. Never start a second agent on a lane whose first may be alive.
*   **Infra** — when the store or runtime stops, restart it from a written recipe with the operator's OK, and ask who stopped it.
*   **Operator loop** — rulings go into the ledger and `COMMON_BRIEF.md` verbatim (`¶INV_EXP_RULINGS_ARE_VERBATIM`). While the operator is away, questions go to `MORNING_QUESTIONS.md` (template in assets) with a lean and the default taken, blockers first. On request, write a dated `HANDOFF_<date>.md` for the next conductor; do not dehydrate unless asked.
*   **Know when to stop buying** (`¶INV_EXP_STOP_WHEN_THE_LEVERS_RUN_DRY`) — when paid levers keep returning NO-EFFECT, offer a `/council` over the measured results and write a stop list. Systems before quality: $0 hardening of the pipeline and the instruments usually beats another paid arm.
*   **Prove every thread** at its end, while hot, per `¶INV_LOOM_EVERY_THREAD_PROVES` and the Setup publishing disposition.
*   **Ledger** — rewrite it in place as threads advance, keeping a dated copy of the previous one. Per thread: tier, experiment number, cap and spend, verdict word and evidence class, review state, switch state, whether a LAND has held (held · reversed · untested), proof URL.

### The loop gate (`AskUserQuestion`, defaults to keep going)
> "The experiment loom is running. Budget ___ of ___. What next?"
> - **"Keep weaving"** (recommended) — let running threads continue; re-present when the next one lands.
> - **"Add or adjust a thread"** — a new question enters, or a thread widens, narrows, loops back to design, or parks.
> - **"Stop spending"** — hold the budget; only $0 work continues.
> - **"Wrap up"** — Synthesis. Only on an explicit choice.

If the operator says "done" or "close" outright, skip the gate and go to Synthesis.

---

## 2. Synthesis
*Reached only by an explicit "wrap up".*

§CMD_REPORT_INTENT:
> 2: Synthesizing. ___ threads; ___ landed; $___ spent of $___.
> Focus: the spend ledger, the verdict table, what landed and is live, negative results, the stop list, lessons carried upward.
> Not: new paid work.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Debrief notes** (for `LOOM_EXPERIMENT.md`):
*   **Spend** — per lane cap vs receipts, and what share ended in procedural NO VERDICT, split by reason and by whether the protection against that reason had landed yet (`¶PTF_HEADLINE_MIXES_ERAS`).
*   **Verdicts** — every thread's word, evidence class, what it changed, and whether each LAND has held, been reversed or is untested.
*   **Live state** — what landed, whether it is on, and what the knock-on cost was.
*   **Negative results and the stop list** — so nobody pays for them again.
*   **Lessons carried upward** — each into the project's experiment runbook, lever ladder, findings or pitfalls, in the same turn.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Experiment loom complete. Walk through the threads?"
  debriefFile: "LOOM_EXPERIMENT.md"
```

**Post-Synthesis**: If the user keeps talking, obey `§CMD_RESUME_AFTER_CLOSE`.

---

## Constraints

The loop-shaping rules. The full set, each with its measured reason, is `assets/INVARIANTS.md`.

*   **`¶INV_EXP_RIGOR_SCALES_WITH_STAKES`**: Light, Registered, Landing — each thread does what its tier asks and no more.
*   **`¶INV_EXP_FREE_BEFORE_PAID`**: a $0 look at stored data runs before any paid arm, and a small pilot before a confirmation.
*   **`¶INV_EXP_BUDGET_IS_A_LEDGER`**: a ceiling, lane caps, and spend recounted from receipts.
*   **`¶INV_EXP_REGISTER_BEFORE_THE_FIRST_CALL`**: a paid arm's design is sealed and its run registered before the first call; nothing designed afterwards can land.
*   **`¶INV_EXP_HELD_OUT_IS_DERIVED`**: tooling decides which documents are held out and which are design contact; an author's list only adds exclusions.
*   **`¶INV_EXP_REUSE_BY_LEVER_AND_CONTACT`**: held-out is per lever and per design contact; reuse what the rule allows and screen the standing never-read pool before drawing.
*   **`¶INV_EXP_BUNDLE_SAME_STAGE_CHANGES`**: same-stage prompt or schema changes are tested as one registered bundle; single levers only when risky, conflicting or shape-adding.
*   **`¶INV_EXP_SWITCH_NUMBERS_FROM_ONE_REGISTRY`**: revision and switch numbers come only from the registry in `COMMON_BRIEF.md`.
*   **`¶INV_EXP_TURNAROUND_IS_THE_OPERATORS_CALL`**: money or wall-clock is the operator's ruling; a turnaround ruling never relaxes registration or verdicts.
*   **`¶INV_EXP_VERDICT_WORDS`**: LAND · NO-EFFECT · FAIL-GUARD · NO VERDICT · DESCRIPTIVE ONLY, printed by the tool, never paraphrased upward.
*   **`¶INV_EXP_EVERY_LANDING_IS_REVIEWED`**: no change counts as landed without an approving adversarial review.
*   **`¶INV_EXP_SHIP_OFF_THEN_DEFAULT_IN_CODE`**: new behaviour turns on in code once reviewed and measured; off is a brief staging step; no new flags or environment switches.
*   **`¶INV_EXP_LANDS_HAVE_A_COUNTER_METRIC`**: each LAND is tracked as held, reversed or untested, and every loosening of a protection is gated on it.
*   **`¶INV_EXP_SEALED_MEANING_NEVER_CHANGES`**: the verdict tool never changes what a sealed rule value means; new behaviour is a new sealed value or a method version.
*   **`¶INV_EXP_GUARDS_HAVE_TWO_CONTROLS`** and **`¶INV_EXP_GUARD_CALIBRATION_PINS_THE_REPEATS`**: a guard has a null check and a planted-harm positive control, a false-trip budget per family, and runs only at the repeat count it was calibrated at.
*   **`¶INV_EXP_LEVERS_IN_THE_OPERATORS_ORDER`**: prompt or schema before code that rewrites model output; output fixes last, with the operator's OK.
*   **`¶INV_EXP_DRY_RUN_DOWNSTREAM`**: the base arm runs at $0 through every downstream stage before a paid arm; in-sample gains are ceilings.
*   **`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`**: deterministic arms still seal a null.
*   **`¶INV_EXP_GOLD_IS_VERSIONED`**: every verdict names its gold version; a gold revision re-scores at $0, descriptively.
*   **`¶INV_EXP_REPLAY_AFTER_THE_VERDICT`**: code changed after a verdict is replayed at $0 before the landing cites it.
*   **`¶INV_EXP_ONE_INTEGRATOR_FOLDS`** and **`¶INV_EXP_PRODUCTION_SAFETY_BEFORE_SHIPPING`**: one integrator folds; a release-level safety review precedes production.
*   **`¶INV_EXP_RESUME_BY_ID`**: a killed lane resumes by id, or after a harness restart is replaced from disk with a recovery preamble, and never repeats a paid call.
*   **`¶INV_EXP_ANSWERS_GO_TO_DISK`**: the full report comes back in the hand-back and the conductor saves it.
*   **`¶INV_LOOM_COMPOSED_WRITES`**, **`¶INV_LOOM_AGENTS_NAMED_BY_THREAD`**, **`¶INV_LOOM_NO_RUSH_TO_CLOSE`**, **`¶INV_LOOM_EVERY_THREAD_PROVES`**: inherited from `/loom` unchanged.
*   **`§INV_NO_DESTRUCTIVE_GIT`**, **`§INV_A_PROBE_WRITES_ITS_ANSWER_DOWN`**, **`§INV_OFFER_DONT_FORCE_SKILLS`**, **`§INV_LISTS_INSTEAD_OF_TABLES`**: engine-wide, apply here as everywhere.
