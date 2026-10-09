# /loom-experiment — build notes

For the operator. Dated 2026-09-26. What was written, how it maps to the request, and which lessons the sources did not bear out.

## What was written

- `SKILL.md` — the lean protocol. It keeps /loom's frontmatter, boot sector, JSON Session Parameters (phases, steps, proof, logTemplate, debriefTemplate), lists-not-tables, and the loom machinery by reference (threadId naming, composed writes, no rush to close, a proof page per thread). The additions:
  - rigor tiers (Light / Registered / Landing), so a $0 question stays light;
  - Setup dispositions (budget, model tier, landing authority, proof publishing), each asked with a recommended option;
  - an inventory of data, runtime and instruments, and a `COMMON_BRIEF.md` every lane carries;
  - the thread flow: question → $0 look → (tooling) → design + register → paid arm → verdict → review → land or park → proof;
  - conductor duties: the spend ledger, verdict words, reviews, staged landing, resume by id, infra, rulings, morning questions, the stop-buying check;
  - a loop gate with a "Stop spending" option.
- `assets/EXPERIMENT_DIRECTIONS.md` — the lane rules, successor to LOOM_AGENT_DIRECTIONS for experiment lanes.
- `assets/EXPERIMENT_ORGANIZATION.md` — covers:
  - the folder layout (PREMISE with its Lever line, design, arms, instruments, runs, results, findings);
  - phrasing a question around a decision, and the ladder of checks;
  - recording findings, and the statistics to observe;
  - what an actionable finding looks like, and which findings become report-only checks.
- `assets/TOOLING.md` — the instruments, each with what it answers, its smallest version, its own controls, and how it went wrong here: scorer, census, replay, verdict, touch ledger/held-out, registration, spend ledger, checks, judges, preflight, proof pages. Also a short guide for walking the user through building a missing one.
- `assets/INVARIANTS.md` — every `¶INV_EXP_*` rule with its Rule, Redirection and "Reason, measured". SKILL.md lists only the rules that shape the loop.
- `assets/PITFALLS.md` — the `¶PTF_*` catalogue, grouped Measurement / Money / Execution / Agents / Review and records / Operator and publishing. Each entry gives what happens, the incident, and the guard.
- Templates:
  - `TEMPLATE_EXPERIMENT_DESIGN.md` — the pre-registration;
  - `TEMPLATE_LOOM_EXPERIMENT_LOG.md` — the log, with a spend ledger, registration, verdict and ruling entries;
  - `TEMPLATE_LOOM_EXPERIMENT.md` — the debrief;
  - `TEMPLATE_MORNING_QUESTIONS.md`.
- Symlink: `~/.claude/skills/loom-experiment` → `~/.claude/engine/skills/loom-experiment`. Nothing else in the engine was touched.

## Design choices worth knowing

- The full rule set lives in assets, not SKILL.md, per the "lean and easy going" ask. SKILL.md leads with the loop.
- `AskUserQuestion` allows at most four options, so the loop gate merges "add" and "adjust" to make room for "Stop spending".
- Rules carry no project names. Evidence lines are short and generic ("a document-parsing LLM pipeline"), with numbers kept where they carry the point.

## Lessons verified, and where

Each lesson below appears in the conductor log (`sessions/2026_08_30_POLICY_PARSE_LOOM/LOOM_LOG.md` plus the scratchpad mirror), the handoffs, MORNING_QUESTIONS, COMMON_BRIEF, TIGHTEN_REPORT or the experiment runbook. For example:
- the census of 0 in 456,902: log 09-26 15:44;
- the private worker polling shared queues: 09-25 01:08;
- the stale anchor cutter running for 69 runs: 09-25 04:25 and 04:43;
- the whole-tree formatter and the two builders in one worktree: 09-25 04:25;
- the env-variable ruling: 09-26 14:39;
- the placebo excusing a regression (M2): 09-24 16:12 and 16:15;
- document-level resampling flipping verdicts: 09-24 18:32;
- built inputs counted as reads: 09-26 02:24;
- seed copies counted as reads: 09-25 01:08 and 02:09;
- the hidden reconcile stage: 09-25 07:16;
- the vanished OCR mirror: 09-25 04:53 and 05:06;
- wording failing three times: 09-25 07:05;
- the enum limits: 09-24 16:53, 20:13 and 22:23;
- the safeguard kills, and smaller models refusing relayed briefs: 09-26 05:50–05:54;
- the inert fix round left unreviewed: 09-26 07:43 and 13:02;
- A/B/C pricing: 09-26 14:06;
- the Docker outages and who caused them: 09-26 05:30, 14:06 and 15:06.

## Lessons not fully verified

- **Cross-provider acceptance probes.** The sources show a $0 acceptance probe against the same provider, and cross-engine judge panels. They show no cross-provider acceptance probe. The skill states "acceptance probe on the real endpoint" and "judges on at least two engines" instead.
- **"A relayed fact from a peer is a check you didn't run."** The sentence itself was not found. The rule is supported by three incidents: the conductor's "my error" on a relaxed test it authorised, an auditor missing a ruling it had heard second-hand, and a lane declining to publish on relayed consent. The wording is mine.
- **"A negative must prove the instrument could see a hit."** It is stated in the experiment runbook and in the checks' canary rule. The log shows it only indirectly (vacuous merge-guard evidence; a format check that caught none of the tenfold amounts).
- **Spend recounted from receipts.** Receipts are verified. A full per-lane recount is not: the ledger itself says "rough; recount from lane reports", and only one lane's recount correction is in the log.

## Added beyond the requested list, found in the sources

- temperature-0 repeats are not replicates;
- the control must run in the same batch;
- designs underpowered by construction, and the minimum detectable effect;
- claim whole clusters, not document ids;
- register last, since a stale registration gets no verdict;
- unbalanced arms;
- an empty success body counts as a failure;
- cache keys that omit a field;
- an example that reaches past its target;
- a default flipped on smoke evidence;
- a test that passes on the parent commit;
- tools that write git need review;
- re-read every external write;
- the conductor assigns experiment numbers, and every folder carries a Lever line;
- stale numbers on published pages;
- ambiguous "pick the ones you disagree with" questions;
- a "private" channel that isn't;
- credential workarounds;
- disk-full and synced-folder outages;
- stop buying quality when the levers run dry (the data council and its stop list);
- "don't overbuild" for tooling.
