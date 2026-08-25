---
name: remix
description: "Remix — a config-driven engine for converging a visual/renderable design system by orchestrated iteration where the artifact IS the test, the gate is a human eye, and work is ADJUDICATED into rulings — not completed. The protocol is system-agnostic; a specific design system is a loadable config manifest (--config <name-or-path>, default warm-print — the /loop engine+workload pattern). Four modes: orchestrate (the dispatch → review → rule → re-dispatch loop across isolated page-builders), page (build or fix ONE artifact, verified by looking at it across the config's render matrix), tend (lint/reconcile kit↔docs↔corpus and regenerate the digest, leaving a number behind), critique (validate a page's RESOLVED styles + geometry and class each defect geometry/glyph/semantic). Every mode reads a durable DIGEST (rules preamble + FACTS ledger + vocabulary registry) at dispatch instead of re-deriving the corpus. Triggers: \"remix\", \"remix the design system\", \"converge the design vocabulary\", \"orchestrate the design\", \"build a proof page\", \"tend the kit\", \"critique this page's geometry\", \"reconcile the kit against its docs\"."
version: 1.0
tier: protocol
args: "[orchestrate|page|tend|critique] [<subject>] [--config <name-or-path>]"
---

Converge and maintain a visual design system where the artifact is the test, the gate is a human eye, and work is adjudicated into rulings.

**This skill is the engine; a design system is the workload.** The protocol (the four modes, the phase skeleton, the eye-gate, the digest mechanism, the honesty invariants) is system-agnostic and lives here. The *specific* design system — its kit, corpus, digest locations, render matrix, reserved channels, thresholds — lives in a **config manifest** the skill loads at Setup (`--config <name-or-path>`, default `warm-print`). Same protocol, any design system. (The `/loop` pattern: generic engine, workload as input.)

# Remix Protocol (The Adjudicated Loop)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "REMIX",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed"], "gate": false},
    {"label": "1", "name": "Orient",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_THINK_IN_LOG", "§CMD_APPEND_LOG"],
      "proof": ["intentReported", "logEntries"], "gate": false},
    {"label": "2", "name": "Work",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["intentReported", "logEntries"], "gate": true},
    {"label": "3", "name": "Adjudicate",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["intentReported", "logEntries"], "gate": true},
    {"label": "4", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "4.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "4.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "4.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "4.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_OFFER_COUNCIL_REVIEW", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/prove", "/implement", "/scrutinize", "/chores"],
  "directives": ["PITFALLS.md", "CONTRIBUTING.md", "CHECKLIST.md"],
  "logTemplate": "assets/TEMPLATE_REMIX_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_REMIX.md",
  "modes": {
    "orchestrate": {"label": "Orchestrate", "description": "Iterative dispatch → review → rule → re-dispatch loop across isolated builders", "file": "modes/orchestrate.md"},
    "page": {"label": "Page", "description": "Build or fix ONE artifact, verified by looking at it across the config's render matrix", "file": "modes/page.md"},
    "tend": {"label": "Tend", "description": "Lint/reconcile kit↔docs↔corpus + regenerate the digest, leaving a number behind", "file": "modes/tend.md"},
    "critique": {"label": "Critique", "description": "Validate resolved styles + geometry; class each defect geometry/glyph/semantic", "file": "modes/critique.md"},
    "custom": {"label": "Custom", "description": "User provides the framing; agent blends the four modes for genuine cross-mode work", "file": "modes/custom.md"}
  }
}
```

---

## Why a skill rather than `/implement`

`/implement` assumes a plan whose steps are code changes verified by tests. Design work inverts three of those assumptions — which is why it needs its own protocol, its own proof, and its own memory:

1. **The artifact is the test.** A page that renders the pattern proves the pattern renders. There is no separate "assert" step; the specimen *is* the assertion.
2. **The gate is a human eye.** Twenty-plus defects in one day passed every automated check and were obvious in a screenshot. No `/implement` phase has a "look at it" step; here it is a mandatory, gated invariant (`¶INV_DS_LOOK_AT_IT`).
3. **Work is adjudicated, not completed.** The output of a build cycle is a **ruling** — what was decided *and why* — and rulings accumulate into the system's memory. `/implement` produces a diff and has nowhere to put a ruling.

**Do not relitigate this**, the four modes, or the shared invariants — they are settled. This skill's job is to run them.

---

## The four modes (pick one at Setup)

`§CMD_SELECT_MODE` picks the mode from `args` or asks. The mode file (`modes/<mode>.md`) is the operative specialization: it names phases **1 Orient · 2 Work · 3 Adjudicate** for that mode, defines their steps and hard rules, and lists the mode's **report proof** (the numbers its debrief must carry). The four named modes are the settled vocabulary; **`custom`** exists only for genuine cross-mode work (build-then-critique, sweep-then-re-dispatch) — it blends the four, never replaces a pure mode.

- **`orchestrate`** — the iterative loop. Frame → the Dispatch Loop (dispatch · relay · verify · adjudicate) → re-dispatch. You hold the vocabulary and the rulings; specialists build pages in isolation; the human adjudicates by eye. Integration is the bottleneck, so a wave gates on `landed / deferred / ticketed`.
- **`page`** — build or fix exactly ONE artifact, end to end, verified by looking at it. The **Verify** phase is the spine; its four parts are mandatory.
- **`tend`** — the gardener. Reconcile the kit with its documentation and its corpus, delete what nothing uses, **and regenerate the digest**. Leave a number behind for each thing closed.
- **`critique`** — the reviewer who sees cause beside effect. Load a page's **resolved** styles and geometry, overlay the computed values, and class every finding: geometry · glyph · semantic.

---

## Shared: the invariants every mode enforces

Stated once; each mode cites rather than restates. The first seven are the honesty rules; the last three govern the dispatch digest (see **The Digest** below). The rules are **universal defaults that stay in the skill** — their tunable *specifics* (the render matrix, the contrast floor, which channels are reserved) come from the loaded config, never from a literal here.

- **`¶INV_DS_ENCODE_OR_OMIT`** — colour encodes a fact or it does not appear, and every encoding carries a legend. `legend` is the one block with no fallback: no key ⇒ remove the colour.
- **`¶INV_DS_NON_COLOUR_CHANNEL`** — wherever colour carries meaning, a second non-colour channel must carry it too (shape · fill density · texture pitch · areal coverage · position). Hue dies in greyscale and in every form of CVD; the others do not.
- **`¶INV_DS_MISSING_NOT_EMPTY`** — an absent fact renders visibly distinct from a false one and from a zero.
- **`¶INV_DS_DEPTH_IS_SCARCE`** — at most one depth treatment per composed unit.
- **`¶INV_DS_CUTS_ARE_ANNOUNCED`** — a stylesheet may only make cuts that need no announcement. Only an author may announce a cut; only a checker can notice one. (A stylesheet silently clipping 234 px of prose is a *governance violation*, not a bug.)
- **`¶INV_DS_LOOK_AT_IT`** — no build or fix closes without the author opening the renders, across the config's full render matrix (every theme × every viewport). This is the `CHECKLIST.md` hard gate.
- **`¶INV_DS_ASSERT_THE_LOSS`** — a check asserts the thing the reader loses, never a condition that usually accompanies it. (Body-overflow measured 0 while ancestors clipped 234 px: the metric certified the pages it existed to catch.)
- **`¶INV_DS_DURABLE_OVER_WARM`** — the shared context a dispatched agent reads MUST be a durable, regenerable FILE (the digest), never a kept-warm live agent context. A warm context is mortal (transcripts age out) and, here, un-forkable (the `fork` subagent type is not provisioned in this environment — and even where it is, a forked child is a mortal live agent whose transcript ages out too: fork buys cheap spawn, not durability). A file survives death and forks for free. Warmth is never the fix for a durability failure.
- **`¶INV_DS_FACTS_ARE_CITED_NOT_COPIED`** — measured numbers cross a dispatch boundary as `FACTS` ledger id-citations, never as hand-copied values in a brief. (An orchestrator who re-types numbers introduces errors in transit.)
- **`¶INV_DS_REGISTER_BEFORE_DISPATCH`** — a channel vocabulary MUST be registered (`channel · values · meaning · reserved-for`) in the digest's registry before it is dispatched on. Seven agents asked to converge without a registry produced four partly-agreeing vocabularies.

Every mode reads `~/.claude/engine/skills/intake/.directives/PITFALLS.md` at Setup — several of its traps caught agents mid-page on the day these rules were written.

---

## The Config — engine + workload (`LOAD-CONFIG`)

At Setup the skill resolves `--config <name-or-path>` (default `warm-print`): a bare name → `configs/<name>.config.md` in this skill dir; an absolute path → that file. **`LOAD-CONFIG`** reads the manifest and binds its fields — `kit-dir` · `kit-readme` · `corpus-root` · `digest-dir` (+ `preamble`/`facts`/`registry` filenames) · `render-matrix` (themes × viewports + the assert/controls rules) · reserved channels · thresholds · pitfalls ref. Every later reference below to a path, a viewport, or a threshold reads from the config, never a literal in this file. A second design system is a second config, no protocol change. (Today there is one: `warm-print`.)

## The Digest — the durable dispatch context

The corpus a cold agent would re-read is large and mostly presentation (for `warm-print`: ~632k tokens, ~71% presentation). A dispatched builder does not need the galleries; it needs the **contracts, the measured facts, and the settled vocabulary**. So instead of keeping an agent *warm* (mortal, un-forkable — `¶INV_DS_DURABLE_OVER_WARM`), the design system keeps a durable **digest** current under the config's `digest-dir`, and every dispatch reads it fresh. This is the resolved form of "warm the cache": a file family, not a live context.

*These are remix-local protocol operations, NOT engine `§CMD_` commands (that sigil is reserved for the engine command registry — promoting them there is the generalization the scope guard defers). A future ticket promotes them to engine command primitives once a second consumer needs them.*

**The digest is a family of three files** (home: the config's `digest-dir`):

1. **preamble** (`PREAMBLE.md`) — the standing brief: the shared invariants, the pitfalls pointer, the render/verify discipline, the return contract. Assembled ONCE and prepended to every brief (≈80% of every hand-written brief was this boilerplate). **Refresh model: regenerate-whole**, idempotent.
2. **facts** (`FACTS.md`) — the measured-facts ledger: one entry per line, `id · claim · number · how measured · by whom`. Briefs **cite entry ids**; agents READ the number. **Refresh model: append-only**, immutable — each fact is written once and never rewritten (this is a feature: it fixes hand-copied-number errors and lets a reconciliation be *run* against stable ids).
3. **registry** (`REGISTRY.md`) — the vocabulary registry: one row per channel, `channel · values · meaning · reserved-for`, seeded from the config's reserved channels. Registered BEFORE dispatch so parallel builders adopt one vocabulary instead of inventing four. **Refresh model: append-only** (a new channel is a new row; a reservation is never silently overwritten — a conflict is a finding).

**The three operations** (referenced by the modes; all paths from the config):

- **`LOAD-DIGEST`** *(read; used by every mode at Orient, and by `orchestrate` in each brief)* — read the preamble + the relevant facts rows (by id) + the registry into the working context / the dispatch brief. This is what replaces "re-derive the corpus." Read fresh each dispatch — never streamed as an accumulating delta feed into a live context (that would re-introduce the append-only-context trap the digest exists to avoid).
- **`APPEND-FACT`** *(write; used whenever a mode MEASURES something)* — append one immutable fact (`id · claim · number · how · by whom`) and return its id, so downstream briefs cite rather than quote. Also the write side for a new registry channel row.
- **`REGENERATE-DIGEST`** *(rebuild; owned by `tend`)* — rebuild the preamble whole from the current invariants + contracts, and **stamp it** with a `last-regenerated` marker + the corpus delta since, so staleness is visible rather than silent. `tend` runs this as part of its sweep and leaves the number behind.

**Scope guard**: the digest operations serve `/remix` only. They are NOT a standalone `/digest` skill and are NOT wired into `/implement`, `/build`, or any other consumer. And the config layer stays N=1 — one real config, no multi-system machinery (registries of systems, inheritance) until a genuine second design system exists. Both are latent affordances, not activated surface.

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Remix, mode ___. Subject: ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the mode and the subject (the axis being designed / the page / the sweep target / the page to critique).

**Load the config** (`LOAD-CONFIG`): resolve `--config <name-or-path>` (default `warm-print`) → the manifest, and bind its fields (kit refs, digest-dir, render matrix, reserved channels, thresholds, pitfalls ref). Everything downstream reads from it. If the named config does not resolve, stop and say so — a design system without a config is a protocol with no workload.

**Mode Selection** (`§CMD_SELECT_MODE`): parse the mode from `args`; if absent or ambiguous, ask via `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`. **Read the selected `modes/<mode>.md`** — it defines the Role/Goal/Mindset, the names + steps + hard rules for phases 1–3, and the mode's report proof. Do NOT read the other mode files. **On `custom`**: read ALL FOUR named mode files first, then parse the user's framing into which mode owns each phase.

**Load the digest + pitfalls** (`LOAD-DIGEST`): read the digest family (from the config's `digest-dir`) and the config's pitfalls ref before any work. A brief or a build that re-derives a fact the ledger already holds is the failure this step exists to prevent (`¶INV_DS_FACTS_ARE_CITED_NOT_COPIED`).

---

## 1. Orient

§CMD_REPORT_INTENT:
> 1: Orienting — ___ (mode's phase-1 name: Frame / Ground / Sweep / Resolve).
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

*The mode file names and specializes this phase.* In every mode it means the same thing: **establish ground truth before acting — and never re-derive a measured fact** (read it from `FACTS.md`). Think in the log (`§CMD_THINK_IN_LOG`); record what the digest already settles vs. what this session must establish.

---

## 2. Work

§CMD_REPORT_INTENT:
> 2: Working — ___ (mode's phase-2 name: Dispatch Loop / Build / Triage / Overlay).
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

*The mode file is the operative protocol for this phase* — `orchestrate`'s Dispatch Loop, `page`'s Build, `tend`'s Triage, `critique`'s Overlay. Log continuously (`§CMD_APPEND_LOG`); track progress (`§CMD_TRACK_PROGRESS`); stop and ask when stuck (`§CMD_ASK_USER_IF_STUCK`). **Gate**: this phase is human-steered — the user directs cycles / reactions / triage before Adjudicate.

---

## 3. Adjudicate

§CMD_REPORT_INTENT:
> 3: Adjudicating — ___ (mode's phase-3 name: Adjudicate / Verify / Repair / Judge).
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

*The mode file specializes this phase.* It is where the **human eye** rules (`¶INV_DS_LOOK_AT_IT`) and where the session's output becomes a **ruling**, a **verified page**, a **repair with a number**, or a **classed finding**. **Gate**: nothing leaves this phase un-looked-at. Anything measured here is appended to `FACTS.md` (`APPEND-FACT`) so the next session cites it.

---

## 4. Synthesis

§CMD_REPORT_INTENT:
> 4: Synthesizing. Mode ___ — ___ (rulings / page / repairs / findings).
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(4.0.*)

**Debrief notes** (for `REMIX.md`): carry the mode's **report proof** (`orchestrate`: cyclesRun · agentsDispatched · rulingsRecorded · claimsVerifiedAtSource · vocabularyConflictsRelayed · **landed/deferred/ticketed** · `page`: artifact · rendersOpened · measurementsWithControls · defectsFoundByRender · defectsFoundByCheck · couldNotEstablish · `tend`: sweepsRun · defectsVerified · defectsRepaired · claimsCheckedAndFoundCorrect · deferredWithReason · digestRegenerated · `critique`: pagesResolved · findingsByClass · overlayRendered · controlsPrinted · blindSpotsStated). The debrief template has a slot per mode.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Remix cycle complete. Walk through the rulings / findings?"
  debriefFile: "REMIX.md"
```

Before closing, offer a `/council` panel review on the debrief via `§CMD_OFFER_COUNCIL_REVIEW` (offer, not force). The natural chain: `/prove` to publish the evidence, `/implement` to land a deferred integration, `/scrutinize` to adversarially review a page.

---

## Cross-mode: what accumulates

The design system is not a stylesheet; it is the memory that keeps a rendered page honest. Four things accumulate across sessions and modes:

- **Rulings** → the design system's memory. `orchestrate` writes them (decided *and why*, because the next agent inherits the rule without the conversation); every mode reads them via the digest.
- **Facts** → `FACTS.md`. Any mode that measures appends; every brief cites. Immutable and id-addressed.
- **Vocabulary** → `REGISTRY.md`. Registered before dispatch; a collision is a finding, never a silent overwrite.
- **Pitfalls** → `~/.claude/engine/skills/intake/.directives/PITFALLS.md`. Any mode may add; the bar is *it shipped, or nearly shipped, with every check green*.
- **Gates** → `critique` findings that recur become checks. **This is the loop's terminus**: a finding that stays a finding will recur, because instruction is not the lever — the slot is.
