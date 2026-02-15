# Orchestration System — Vision
**Tags**:

## Provenance

| Field | Value |
|-------|-------|
| **Created by** | `sessions/2026_02_13_ORCHESTRATION_ROADMAP` |
| **Mode** | Greenfield |
| **Date** | 2026-02-13 |
| **Version** | v1 |
| **Previous version** | None |

---

## 1. Background & Motivation

### Problem Statement
The workflow engine has a fleet system for running multiple Claude Code agents in tmux panes, and a coordinator skill (`/coordinate`) that can monitor workers and answer their routine questions. But the coordinator is a reactive monitor — it watches and responds. It cannot plan work, assign tasks to specific workers, track chapter-level progress, or advance through project milestones autonomously. The human remains the bottleneck for project orchestration: decomposing work into chunks, deciding what each worker should do, and tracking which milestones are complete.

### Current State
- **`/coordinate` (v3.0)**: Event-driven loop with `coordinate-wait`, `capture-pane` TUI parser, `connect/disconnect` purple layer, 3 modes (autonomous/cautious/supervised), ESC interrupt, selective logging. ~60% built for single-session oversight, ~10% built for orchestration.
- **`/direct` (v1.0)**: Vision creation skill with `TEMPLATE_DIRECT_VISION.md`, dependency analysis, 4 modes (greenfield/evolution/split/custom). Fully built — produces vision documents.
- **Fleet infrastructure**: `coordinate-wait` v1 (sweep-first event loop with wake signals), `capture-pane` (TUI parser), `connect/disconnect` (purple layer), 22+ tests. Missing: v2 auto-lifecycle, `@pane_user_focused`, `FOCUSED` return state.
- **Specs**: `ORCHESTRATION.md` (multi-chapter lifecycle), `COORDINATE.md` (single-session mechanics) — comprehensive design docs from 3 brainstorm + 1 implementation session.

### Opportunity
Transform the coordinator from a question-answering assistant into a self-driving project orchestrator. The user produces a high-level vision document (via `/direct`), and the coordinator drives through chapters autonomously — planning work, assigning tasks to workers, tracking progress, and advancing through milestones. Hours of coordinated multi-agent work with minimal human intervention.

### Cost of Inaction
- Human remains the bottleneck for all project-level decisions
- Multi-agent fleet underutilized — workers idle between tasks waiting for human direction
- No persistent project memory across coordinator sessions (no chapter plans, no progress tracking)
- The `/direct` → `/coordinate` pipeline exists conceptually but has no working consumer

### Stakeholders
| Stakeholder | Interest | Impact |
|-------------|----------|--------|
| Human operator | Less micro-management, more strategic thinking | Freed from routine task assignment and question answering |
| Worker agents | Clear task assignments, fewer idle periods | Receive structured work items via `%worker` routing |
| Coordinator agent | Structured plan to follow, clear success criteria | Evolves from reactive monitor to strategic coordinator |

---

## 2. Vision

### Goal
Build an autonomous orchestration system where `/direct` produces structured vision documents with tagged chapters, and `/coordinate` consumes them — claiming chapters, creating detailed execution plans, assigning tasks to workers via `%worker` identity routing, tracking completion, and progressing through milestones. Human attention is the scarce resource: the system minimizes interruptions via priority-based escalation (P0/P1/P2) and learns from human overrides to improve decision principles over time.

### Success Criteria
- [ ] `/coordinate` loads a vision document, claims a chapter (`#needs-coordination` → `#claimed-coordinate`), creates a chapter plan with user approval, and executes it
- [ ] `/direct` produces vision documents with dependency analysis that `/coordinate` directly consumes
- [ ] Escalation uses P0/P1/P2 priority markers; the coordinator tracks human overrides and suggests decision principle updates at synthesis
- [ ] Work items are assigned to specific workers via `%worker` identity on REQUEST file Tags lines; workers discover work by scanning for their `%name`
- [ ] `/coordinate` SKILL.md is structurally aligned with gold-standard skills: formal phases, `§CMD_*` steps, proof schemas, walk-through configs

### Non-Goals
- Multi-coordinator: running multiple `/coordinate` sessions on different chapters in parallel. Serial chapter execution only.
- Escalation batching or quiet hours. Escalations are immediate with priority markers.
- Self-calibration: the coordinator does not auto-adjust thresholds mid-session. It recommends changes at synthesis.
- Worker-to-worker communication via the coordinator. Workers use the existing delegation system (REQUEST/RESPONSE files) for inter-worker coordination.
- Daemon routing of `%worker` tags. The `%worker` sigil is coordinator-local, not daemon-discoverable.

### Constraints
- ORCHESTRATION.md is the authoritative specification. Deviations require explicit justification.
- TDD-first for all fleet.sh infrastructure changes.
- The coordinator is a servant-leader (not a director). Workers can push back. Disagreements escalate to human.
- `tmux send-keys` is ONLY for answering AskUserQuestion prompts. Task assignment uses the delegation/tag system.
- Backward compatibility: single-session coordinator (no chapter system) must still work after all changes.

---

## 3. Architecture Sketch

### System Overview

```
USER
  │
  ├► /direct (Vision Architect)
  │   │ • Interrogates project goals
  │   │ • Decomposes into chapters with @slugs
  │   │ • Analyzes dependencies (serial vs parallel)
  │   │ • Produces docs/VISION.md with #needs-coordination tags
  │   ↓
  │  VISION DOCUMENT (docs/)
  │   │ • Evergreen project plan
  │   │ • Chapters tagged #needs-coordination
  │   │ • Decision principles (natural language)
  │   │ • Dependency graph
  │
  ╰► /coordinate (Fleet Coordinator)
      │ • Loads vision document
      │ • Claims chapter: #needs-coordination → #claimed-coordinate
      │ • Creates chapter plan (TEMPLATE_COORDINATOR_PLAN.md)
      │ • Enters event loop
      │
      ├► CHAPTER PLAN (session artifact)
      │   │ • Work items with checkboxes
      │   │ • %worker assignments
      │   │ • Completion criteria
      │
      ├► coordinate-wait v2 (fleet.sh)
      │   │ • Auto-disconnect previous pane
      │   │ • Sweep for actionable panes
      │   │ • Skip @pane_user_focused
      │   │ • Pick highest priority (error > unchecked > done)
      │   │ • Auto-connect + capture inline
      │
      ├► ASSESS → DECIDE/ESCALATE
      │   │ • P0: blocking (worker stopped)
      │   │ • P1: decision needed (ambiguity)
      │   │ • P2: informational (FYI)
      │   │ • Override tracking → learning
      │
      ╰► CHAPTER COMPLETE
          │ • All checkboxes checked
          │ • Completion criteria met
          │ • #claimed-coordinate → #done-coordinate
          │ • Advance to next chapter (or exit)
```

### Key Components

| Component | Location | Role | Changed By |
|-----------|----------|------|------------|
| coordinate-wait v2 | `~/.claude/engine/scripts/fleet.sh` | Event loop primitive — sweep, connect, capture, return | `@engine/orchestration/foundation` |
| `@pane_user_focused` | tmux focus hooks + fleet.sh | 3rd state dimension — user focus detection | `@engine/orchestration/foundation` |
| `TEMPLATE_COORDINATOR_PLAN.md` | `~/.claude/skills/coordinate/assets/` | Chapter plan template with checkboxes and assignments | `@engine/orchestration/chapter-system` |
| `/coordinate` SKILL.md | `~/.claude/skills/coordinate/SKILL.md` | Main skill protocol — phases, loop, synthesis | All chapters |
| `coordinate.config.json` | Session directory | Runtime config — thresholds, escalation rules, priorities | `@engine/orchestration/foundation`, `@engine/orchestration/attention-model` |
| SIGILS.md | `~/.claude/.directives/SIGILS.md` | `%worker` sigil convention | `@engine/orchestration/task-assignment` |

### Key Technical Decisions

| Decision | Rationale | Alternatives Rejected |
|----------|-----------|----------------------|
| Serial chapter execution | Avoids cross-chapter dependency management. Idle workers get filler work. | Parallel chapters (too complex for v1) |
| `%worker` sigil for identity | Consistent with engine's sigil-driven design. Greppable. Maps to fleet_id. | `**Assigned To**` field (not greppable), directory-based routing (too much infrastructure) |
| P0/P1/P2 priority (not batching) | Real-time awareness with triage. User can defer low-priority. | Batching (delays critical escalations), no priority (all look the same) |
| Learning at synthesis only | Recommend config/principle changes, don't auto-adjust mid-session. | Mid-session auto-adjustment (unpredictable), no learning (never improves) |
| Coordinator as servant-leader | Workers can push back. Reduces error cascades. | Director model (top-down, workers can't object) |

---

## 4. Decision Principles

### Development Approach
- ORCHESTRATION.md and COORDINATE.md are the authoritative specifications. Implementation follows these specs; deviations require explicit justification in the session log.
- TDD-first for fleet.sh infrastructure. Write tests before implementation. Maintain the 22+ test standard from the Feb 12 session.
- Prefer additive changes over rewrites until Chapter 5 (Polish). Chapters 1-4 add capabilities; Chapter 5 restructures.

### Risk & Escalation
- The coordinator never makes irreversible decisions autonomously. Deletions, architecture changes, and PR creation always escalate regardless of confidence.
- When uncertain, probe the worker first (pre-escalation interrogation). Only escalate to human if still unsure after the worker explains.
- Flag Chapter 4's SIGILS.md change as high-scrutiny — it's cross-cutting and affects all skills.

### Quality & Standards
- Follow existing patterns in the codebase — consistency over novelty.
- `/coordinate` SKILL.md must match the structural quality of `/implement` and `/analyze` after Chapter 5.
- Config changes must be backward-compatible: new fields with defaults, never remove existing fields.

### Prioritization
- Core functionality before edge cases. Get the chapter lifecycle working before optimizing the attention model.
- Unblock the parallel group (Chapters 2+3) by completing Foundation (Chapter 1) first.
- If stuck on a chapter, escalate to human rather than blocking the critical path.

---

## 5. Context Sources

| Source | Type | Key Insight | Date |
|--------|------|-------------|------|
| `sessions/2026_02_13_COORDINATOR_SKILL_BRAINSTORM/BRAINSTORM.md` | /brainstorm | 9-round design: self-driving orchestrator, chapters, worker groups, strict gates, decision principles | 2026-02-13 |
| `sessions/2026_02_11_OVERSEE_SKILL_DESIGN/BRAINSTORM.md` | /brainstorm | Original design: TUI emulation, manifest, hybrid escalation, serial processing, 6 invariants | 2026-02-11 |
| `sessions/2026_02_12_OVERSEE_SKILL_IMPROVEMENTS/IMPLEMENTATION.md` | /implement | Event-driven rework: coordinate-wait v1, pane labels, wake signals, 22 tests, timer bug fix | 2026-02-12 |
| `sessions/2026_02_13_OVERSEER_ANALYSIS/ANALYSIS.md` | /analyze | Gap analysis: 60% single-session, 10% orchestration, 20-item roadmap, 4 themes, worker identity problem | 2026-02-13 |
| `sessions/2026_02_13_RENAME_SKILLS/DOCUMENTATION.md` | /document | Skill renames: /oversee→/coordinate, /roadmap→/direct, 14 ops across ~35 files | 2026-02-13 |
| `~/.claude/engine/docs/ORCHESTRATION.md` | documentation | Multi-chapter lifecycle: 3-layer architecture, coordinate-wait v2 spec, 3D state model, vision doc spec, chapter lifecycle, failure modes | 2026-02-13 |
| `~/.claude/engine/docs/COORDINATE.md` | documentation | Single-session mechanics: event loop internals, decision engine, worker comms, focus/interrupt, config system, edge cases | 2026-02-13 |

---

## 6. Dependency Graph

```
START → Orchestration System Build
  ↓
PARALLEL GROUP 1 (foundation — no deps)
  │
  ╰► @engine/orchestration/foundation
      │ • coordinate-wait v2, @pane_user_focused, config reconcile
      │ • Effort: L | Files: fleet.sh, tmux hooks, coordinate.config
  ╭───╯
  ↓
PARALLEL GROUP 2 (depends on Group 1)
  │
  ├► @engine/orchestration/chapter-system
  │   │ • Depends on: @engine/orchestration/foundation
  │   │ • Chapter template, planning phase, vision loading
  │   │ • Effort: L | Files: SKILL.md (phase structure), new template
  │
  ╰► @engine/orchestration/attention-model
      │ • Depends on: @engine/orchestration/foundation
      │ • P0/P1/P2 priority, override tracking, learning
      │ • Effort: M | Files: SKILL.md (escalation UI), mode files, templates
  ╭───╯
  ↓
PARALLEL GROUP 3 (depends on Group 2: chapter-system)
  │
  ╰► @engine/orchestration/task-assignment
      │ • Depends on: @engine/orchestration/chapter-system
      │ • %worker sigil, REQUEST routing, completion tracking
      │ • Effort: L | Files: SIGILS.md, REQUEST templates, SKILL.md (loop)
  ╭───╯
  ↓
PARALLEL GROUP 4 (depends on all)
  │
  ╰► @engine/orchestration/polish
      │ • Depends on: all prior chapters
      │ • Full SKILL.md restructure, hardening, multi-chapter, e2e tests
      │ • Effort: L | Files: everything (final integration)
  ↓
END → Autonomous orchestration operational
```

### Parallel Groups
| Group | Chapters | Notes |
|-------|----------|-------|
| **Group 1** | `@engine/orchestration/foundation` | Foundation — must complete first |
| **Group 2** | `@engine/orchestration/chapter-system`, `@engine/orchestration/attention-model` | Parallel — different SKILL.md sections |
| **Group 3** | `@engine/orchestration/task-assignment` | Depends on chapter-system |
| **Group 4** | `@engine/orchestration/polish` | Final integration — depends on all |

### Critical Path
`@engine/orchestration/foundation` → `@engine/orchestration/chapter-system` → `@engine/orchestration/task-assignment` → `@engine/orchestration/polish`

### Shared Resources
| Resource | Chapters | Risk | Mitigation |
|----------|----------|------|------------|
| `SKILL.md` | 2, 3, 4, 5 | Merge conflicts if parallel | Section ownership: Ch 2 = phases, Ch 3 = escalation UI, Ch 4 = loop routing. Ch 5 = final restructure. |
| `fleet.sh` | 1, 5 | Ch 5 hardening over Ch 1 additions | Sequential — Ch 1 completes before Ch 5 starts |
| `SIGILS.md` | 4 | Cross-cutting `%worker` sigil | Additive change — new sigil, no modification to existing tags |
| `coordinate.config` | 1, 3 | Schema changes in both | Sequential — Ch 1 reconciles first, Ch 3 adds attention fields |

---

## 7. Glossary

| Term | Definition |
|------|-----------|
| **Coordinator** | The `/coordinate` skill — a persistent Claude Code agent that monitors fleet workers, answers questions, and orchestrates chapter execution |
| **Vision document** | Evergreen project plan in `docs/` created by `/direct`. Contains chapters, dependency graph, decision principles. |
| **Chapter** | A discrete unit of work within a vision. Each chapter becomes one `/coordinate` session. Tagged `#needs-coordination`. |
| **Chapter plan** | Per-chapter execution plan created by the coordinator. Session artifact with checkboxes, `%worker` assignments, completion criteria. |
| **`%worker`** | Sigil for ephemeral worker identity. Maps to `@pane_fleet_id` from fleet.yml. Used on Tags lines for work routing. |
| **`@slug`** | Sigil for stable epic/chapter identifiers. Filesystem-backed. `@engine/orchestration/foundation` = a chapter in this vision. |
| **P0/P1/P2** | Escalation priority levels. P0 = blocking (worker stopped). P1 = decision needed. P2 = informational. |
| **Strict chapter gates** | Chapter boundaries are sync points. All workers complete before any start next chapter. |
| **Filler work** | Low-priority tasks (`#needs-chores`, `#needs-documentation`) assigned to idle workers between chapter items. |

---

## Chapters

### `@engine/orchestration/foundation`: Infrastructure Hardening
**Tags**: #needs-coordination

Upgrade the fleet infrastructure to support robust long-running coordinator sessions. The current coordinate-wait v1 works for basic monitoring but lacks the lifecycle management, focus detection, and inline capture needed for autonomous chapter execution.

#### Scope
- **In scope**: coordinate-wait v2 (auto-disconnect on next call, FOCUSED return state, inline capture), `@pane_user_focused` dimension with tmux focus hooks, config schema reconciliation (example JSON vs COORDINATE.md), delegation templates for `/coordinate` (`TEMPLATE_COORDINATE_REQUEST.md`, `TEMPLATE_COORDINATE_RESPONSE.md`)
- **Out of scope**: SKILL.md protocol changes, chapter system logic, attention model, task assignment
- **Key files/components**:
  - `~/.claude/engine/scripts/fleet.sh` — coordinate-wait v2, connect/disconnect lifecycle
  - tmux hook configuration — `@pane_user_focused` wiring
  - `~/.claude/skills/coordinate/assets/coordinate.config.example.json` — schema reconciliation
  - `~/.claude/skills/coordinate/assets/TEMPLATE_COORDINATE_REQUEST.md` — new delegation template
  - `~/.claude/skills/coordinate/assets/TEMPLATE_COORDINATE_RESPONSE.md` — new delegation template

#### Dependencies
- **Depends on**: Nothing (foundational)
- **Blocks**: `@engine/orchestration/chapter-system`, `@engine/orchestration/attention-model`
- **Shared resources**: `fleet.sh` (shared with Chapter 5 — sequential, no conflict)

#### Acceptance Criteria
- [ ] `coordinate-wait` v2 auto-disconnects the previous pane on each call
- [ ] `coordinate-wait` returns `FOCUSED` when all panes are user-focused
- [ ] `@pane_user_focused` flag is set/cleared by tmux focus hooks
- [ ] `coordinate.config.example.json` schema matches COORDINATE.md section 7
- [ ] Delegation templates exist and follow the engine's REQUEST/RESPONSE conventions
- [ ] All existing coordinate-wait tests pass (22+) plus new tests for v2 behavior
- [ ] Tests: TDD — write failing tests for v2 behavior before implementation

#### Risks & Open Questions
- **Risk**: tmux focus hooks may fire unreliably across different terminal emulators → **Mitigation**: Test with the primary terminal (iTerm2/Cursor). Degrade gracefully if hooks don't fire (skip `@pane_user_focused` filtering).
- **Open question**: Should auto-disconnect happen on timeout too, or only on successful return? (ORCHESTRATION.md §14 Q1)
- **Open question**: Focus detection implementation — polling vs hook notification vs named pipe? (ORCHESTRATION.md §14 Q1. Recommended: start with polling.)

#### Complexity & Effort
- **Estimated effort**: L
- **Complexity drivers**: tmux event system integration for focus hooks, coordinate-wait lifecycle redesign, backward compatibility with v1 callers
- **Parallel opportunity**: coordinate-wait v2 and `@pane_user_focused` can be developed in parallel (different fleet.sh sections)

---

### `@engine/orchestration/chapter-system`: Chapter System (Strategic Brain)
**Tags**: #needs-coordination

Give the coordinator the ability to consume vision documents, claim chapters, and create detailed execution plans. This is the transition from "reactive monitor" to "strategic coordinator" — the coordinator gains a planning phase and project-level awareness.

#### Scope
- **In scope**: `TEMPLATE_COORDINATOR_PLAN.md` (rich chapter plan), new Chapter Planning phase in SKILL.md (between Setup and Loop), chapter initialization (vision loading, chapter claiming via tags, plan creation with user approval), `§CMD_INGEST_CONTEXT_BEFORE_WORK` added to Setup steps
- **Out of scope**: Multi-chapter autonomous progression (Chapter 5 scope), worker routing/assignment (Chapter 4), attention model changes
- **Key files/components**:
  - `~/.claude/skills/coordinate/assets/TEMPLATE_COORDINATOR_PLAN.md` — new template
  - `~/.claude/skills/coordinate/SKILL.md` — new Phase 1: Chapter Planning, modified Setup phase
  - Vision document loading logic — read `docs/*.md`, find `#needs-coordination` chapters

#### Dependencies
- **Depends on**: `@engine/orchestration/foundation` (reliable monitoring for chapter execution)
- **Blocks**: `@engine/orchestration/task-assignment` (needs chapter plans to assign from)
- **Shared resources**: `SKILL.md` (owns phase structure — Chapter 3 owns escalation UI, no conflict)

#### Acceptance Criteria
- [ ] `TEMPLATE_COORDINATOR_PLAN.md` exists with: chapter summary, success criteria, work item checkboxes, `%worker` assignment slots, completion gates
- [ ] `/coordinate` SKILL.md has Phase 1: Chapter Planning (load vision → claim chapter → create plan → user approval)
- [ ] The coordinator can load a vision document from a path parameter and identify `#needs-coordination` chapters
- [ ] Chapter claiming works: `#needs-coordination` → `#claimed-coordinate` via `engine tag swap`
- [ ] `§CMD_INGEST_CONTEXT_BEFORE_WORK` runs during Setup (loads alerts, RAG, delegations)
- [ ] The chapter plan is presented to the user for approval before entering the loop

#### Risks & Open Questions
- **Risk**: Vision documents may have varied structure (hand-written vs `/direct`-produced) → **Mitigation**: Light validation only — check for `## Chapters` section and `#needs-coordination` tags. Don't enforce full template compliance.
- **Open question**: Should the chapter plan support sub-task parallelism within a chapter (multiple workers on different items simultaneously)?
- **Risk**: Chapter planning phase may consume significant context → **Mitigation**: Keep plan creation concise. Dehydrate aggressively if context grows.

#### Complexity & Effort
- **Estimated effort**: L
- **Complexity drivers**: SKILL.md phase restructure, vision document parsing, tag system integration, user approval gate design
- **Parallel opportunity**: Template design and SKILL.md phase addition can be developed in parallel

---

### `@engine/orchestration/attention-model`: User Attention Model
**Tags**: #needs-coordination

Make the coordinator respect human attention as a scarce resource. Add priority-based escalation so the user can triage interruptions, track when the user overrides coordinator decisions, and surface learning recommendations at synthesis.

#### Scope
- **In scope**: P0/P1/P2 escalation priority markers in the escalation UI, override tracking in log schema (original decision + override + reason), "Override Pattern Analysis" section in debrief template, decision principle suggestions at synthesis
- **Out of scope**: Quiet hours, escalation batching, self-calibration, mid-session auto-adjustment
- **Key files/components**:
  - `~/.claude/skills/coordinate/SKILL.md` — escalation UI modifications (Step 5: Escalate)
  - `~/.claude/skills/coordinate/modes/*.md` — priority behavior per mode (autonomous auto-resolves P2, cautious escalates P1+)
  - `~/.claude/skills/coordinate/assets/TEMPLATE_COORDINATE_LOG.md` — override tracking schema
  - `~/.claude/skills/coordinate/assets/TEMPLATE_COORDINATE.md` — "Override Pattern Analysis" debrief section

#### Dependencies
- **Depends on**: `@engine/orchestration/foundation` (stable loop for attention tracking)
- **Blocks**: Nothing directly (Chapter 5 incorporates it but doesn't strictly depend)
- **Shared resources**: `SKILL.md` (owns escalation UI — Chapter 2 owns phase structure, no conflict)

#### Acceptance Criteria
- [ ] Escalation UI shows P0/P1/P2 priority markers: P0 = blocking, P1 = decision needed, P2 = informational
- [ ] Mode files define priority behavior: autonomous auto-resolves P2, cautious escalates P1+, supervised escalates all
- [ ] When human overrides a coordinator decision, the override is logged with: original decision, override choice, reason (if given)
- [ ] Debrief template has "Override Pattern Analysis" section with: override count, categories, suggested principle updates
- [ ] At synthesis, the coordinator surfaces patterns: "You overrode [category] decisions [N] times — consider updating decision principles"

#### Risks & Open Questions
- **Risk**: Priority classification may be subjective — what makes something P0 vs P1? → **Mitigation**: Clear definitions. P0 = worker is blocked and cannot proceed. P1 = worker asked a question with uncertain answer. P2 = FYI (worker completed a task, status update).
- **Risk**: Override tracking requires the coordinator to detect when its decision was overridden by the human → **Mitigation**: Compare coordinator's logged decision with the actual selection that occurred. If different, log as override.

#### Complexity & Effort
- **Estimated effort**: M
- **Complexity drivers**: Priority classification logic, override detection mechanism, pattern analysis at synthesis
- **Parallel opportunity**: Priority UI and override tracking are independent — can be developed in parallel

---

### `@engine/orchestration/task-assignment`: Worker Identity & Task Routing
**Tags**: #needs-coordination

Solve the "who does what" problem. Give the coordinator a mechanism to assign specific work items to specific workers, using the `%worker` sigil as an ephemeral identity that maps to fleet_id. Connect chapter plan checkboxes to worker completion for progress tracking.

#### Scope
- **In scope**: `%worker` sigil design and documentation in SIGILS.md, REQUEST file template with `%worker` on Tags line, worker self-discovery (workers grep for their `%name`), chapter plan checkbox → worker completion wiring, coordinator loop modifications for work dispatch
- **Out of scope**: Daemon routing of `%worker` (coordinator-local only), workgroup-level assignment (individual workers only in v1), worker process management
- **Key files/components**:
  - `~/.claude/.directives/SIGILS.md` — `%worker` sigil convention added to sigil inventory
  - `~/.claude/skills/coordinate/assets/TEMPLATE_COORDINATE_REQUEST.md` — `%worker` on Tags line
  - `~/.claude/skills/coordinate/SKILL.md` — work dispatch logic in loop, completion tracking
  - Chapter plan template — `%worker` in assignment slots

#### Dependencies
- **Depends on**: `@engine/orchestration/chapter-system` (chapter plans needed to assign from)
- **Blocks**: `@engine/orchestration/polish` (e2e testing needs routing to work)
- **Shared resources**: SIGILS.md (additive — new sigil, doesn't modify existing tags)

#### Acceptance Criteria
- [ ] SIGILS.md documents `%worker` sigil: definition, format (`%fleet-id`), discovery (`engine tag find` or grep), scope (coordinator-local, not daemon-routed)
- [ ] REQUEST files use `**Tags**: #claimed-implementation %prog-1` format for worker-specific assignment
- [ ] Workers can discover work assigned to them by scanning for their `%name`
- [ ] Chapter plan checkboxes update when corresponding work items reach `#done-*` state
- [ ] The coordinator can dispatch work items from the chapter plan to specific `%worker` targets

#### Risks & Open Questions
- **Risk**: SIGILS.md `%worker` change is cross-cutting — all skills that parse tags need to handle the new sigil → **Mitigation**: `%worker` is additive. Existing `engine tag find` ignores unknown sigils. Only the coordinator and workers need to understand `%worker`.
- **Open question**: How does `%worker` interact with fleet.yml workgroup definitions? Is `%worker` always a fleet_id, or can it be a workgroup name for load-balanced assignment?
- **Open question**: What if a worker crashes mid-task? How does the coordinator detect and reassign?

#### Complexity & Effort
- **Estimated effort**: L
- **Complexity drivers**: Cross-cutting SIGILS.md change, worker self-discovery mechanism, completion tracking wiring, coordinator dispatch logic
- **Parallel opportunity**: SIGILS.md convention work and SKILL.md dispatch logic can be developed in parallel

---

### `@engine/orchestration/polish`: Structural Alignment & Hardening
**Tags**: #needs-coordination

Final integration chapter. Restructure `/coordinate` SKILL.md to match gold-standard skills, convert prose event loop to `§CMD_*` steps, add multi-chapter autonomous progression, harden the event loop for long-running sessions, and validate the full system end-to-end.

#### Scope
- **In scope**: Full SKILL.md restructure (Phase 0 Setup → Phase 1 Chapter Planning → Phase 2 Oversight Loop → Phase 3 Synthesis), convert prose event loop to `§CMD_*` steps with proof schemas, walk-through config for synthesis, ESC interrupt hardening (documented recovery), consecutive timeout handling, config self-validation at startup, multi-chapter autonomous progression (chapter complete → claim next → new session), end-to-end testing
- **Out of scope**: Multi-coordinator (parallel chapter execution), worker process management, daemon changes
- **Key files/components**:
  - `~/.claude/skills/coordinate/SKILL.md` — full rewrite incorporating all prior chapters
  - `~/.claude/engine/scripts/fleet.sh` — event loop hardening
  - `coordinate.config.json` — validation schema
  - Test files — end-to-end coordinator tests

#### Dependencies
- **Depends on**: `@engine/orchestration/foundation`, `@engine/orchestration/chapter-system`, `@engine/orchestration/attention-model`, `@engine/orchestration/task-assignment`
- **Blocks**: Nothing (final chapter)
- **Shared resources**: Everything — this is the integration chapter

#### Acceptance Criteria
- [ ] SKILL.md has 4 formal phases: Setup, Chapter Planning, Oversight Loop, Synthesis
- [ ] Event loop steps are `§CMD_*` references with proof schemas (not prose)
- [ ] Walk-through config exists for synthesis phase
- [ ] Multi-chapter progression: on chapter complete, coordinator claims next `#needs-coordination` chapter automatically (or exits if none remain)
- [ ] ESC interrupt has documented recovery path
- [ ] Consecutive timeout handling: after N timeouts, surface status to human
- [ ] Config self-validation at session start catches malformed configs
- [ ] End-to-end test validates: setup → chapter plan → loop (simulated workers) → escalation → synthesis

#### Risks & Open Questions
- **Risk**: Full SKILL.md rewrite is context-intensive (340+ lines) — may trigger context overflow → **Mitigation**: Dehydrate aggressively. Split the rewrite into sub-phases if needed.
- **Risk**: Multi-chapter progression adds complexity that may destabilize single-chapter use → **Mitigation**: Feature-flag multi-chapter behind a config option. Default to single-chapter.
- **Open question**: Multi-chapter progression: should the coordinator auto-advance or present a gate between chapters?

#### Complexity & Effort
- **Estimated effort**: L
- **Complexity drivers**: Full protocol rewrite, multi-chapter state management, end-to-end testing with simulated fleet
- **Parallel opportunity**: SKILL.md restructure and fleet.sh hardening can be developed in parallel

---

## Appendix: Evolution History

| Version | Date | Session | Summary of Changes |
|---------|------|---------|-------------------|
| v1 | 2026-02-13 | `sessions/2026_02_13_ORCHESTRATION_ROADMAP` | Initial vision — 5 chapters, 4 parallel groups |
