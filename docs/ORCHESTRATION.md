# Orchestration System Design

**Provenance**: `sessions/2026_02_13_COORDINATOR_SKILL_BRAINSTORM` (9 rounds, Focused mode)
**Related**: `COORDINATE.md` (single-session loop mechanics), `FLEET.md` (multi-agent workspace), `TAG_LIFECYCLE.md` (tag dispatch), `DAEMON.md` (daemon dispatch)

This document defines the orchestration system — the coordinator's evolution from an event-driven question answerer to a self-driving project orchestrator. It is the specification for future `/implement` sessions and the reference for agents executing `/coordinate`.

---

## 1. Architecture Overview

The orchestration system has three layers, each with a distinct lifecycle and ownership:

```
┌─────────────────────────────────────────────────┐
│  Vision Document (docs/)                        │
│  Evergreen project plan — chapters, goals,      │
│  worker groups, decision principles             │
│  Created by: /direct                            │
│  Template: TEMPLATE_DIRECT_VISION.md           │
│  Lifecycle: Survives across all chapters        │
├─────────────────────────────────────────────────┤
│  Chapter Plan (session artifact)                │
│  Per-chapter execution plan — checkboxes,       │
│  worker assignments, completion criteria        │
│  Created by: /coordinate on chapter start          │
│  Template: TEMPLATE_COORDINATION_PLAN.md         │
│  Lifecycle: One per /coordinate session            │
├─────────────────────────────────────────────────┤
│  Coordinator Loop (SKILL.md runtime)               │
│  Event-driven pane processing — await-next,   │
│  state model, focus detection, serial processing│
│  Defined in: coordinate/SKILL.md                   │
│  Lifecycle: Runs continuously within a session  │
└─────────────────────────────────────────────────┘
```

**Lifecycle**: User produces vision → vision gets chunked into serial chapters → each chapter is an `/coordinate` session → coordinator finishes one chapter, starts the next automatically.

### Why Three Layers?

The separation addresses three distinct concerns that change at different rates:

1. **Vision** changes slowly — it represents the user's high-level project intent. Created by `/direct`, which owns the vision template and handles dependency analysis (serial vs parallel chunks). Editing the vision mid-chapter is fine because the coordinator reads the latest version at each chapter boundary. Keeping this in `docs/` (not `sessions/`) makes it persistent and accessible to all skills.

2. **Chapter plans** change per-chapter — each chapter has different work items, assignments, and completion criteria. Making these session artifacts means they get the full session lifecycle (logging, debrief, tag tracking). A chapter plan is conceptually similar to an implementation plan in `/implement`.

3. **The loop** is runtime behavior — it processes events, makes decisions, and communicates with workers. It doesn't change between chapters; only its *context* changes (which chapter plan it's reading, which workers it's managing).

**Alternatives considered and rejected**:
- **Single-level (just a plan + loop)**: No mechanism for long-running multi-chapter projects. The user would need to manually restart `/coordinate` for each phase.
- **Two-level (vision + loop, no chapter plan)**: The loop would need to derive work items from the vision directly, making the vision overly detailed and mixing "what to achieve" with "how to execute."
- **Four-level (adding a "sprint" between vision and chapter)**: Over-engineering. Chapters already serve as the chunking mechanism. Adding another level creates planning overhead without value.

---

## 2. await-next v2

The core loop primitive. A single blocking call per iteration that handles pane engagement, transcript reading, and lifecycle management.

For full loop mechanics, state model, and decision engine details, see `COORDINATE.md`.

### Behavior

```
Call N:
  1. Auto-disconnect previous pane (from call N-1)
  2. Sweep for actionable panes:
     - Skip: @pane_user_focused = 1
     - Skip: @pane_coordinator_active = 1 (already managed, shouldn't happen)
     - Include: @pane_notify in {unchecked, error, done}
  3. Pick highest priority:
     - error > unchecked > done
  4. Auto-connect (set @pane_coordinator_active = 1, purple bg)
  5. Read worker transcript (JSONL) for last AskUserQuestion
  6. Return to caller
```

The key insight (from brainstorm Round 3): disconnect should be automatic on the *next* call, not explicit after processing. This means `await-next` call N auto-disconnects whatever call N-1 connected, then sweeps and connects a new pane. The loop body becomes truly single-command: just keep calling `await-next`.

### Output Format

**Normal return** (pane found):
```
pane_id|state|label|location
{capture JSON}
```

The first line provides routing metadata. The JSON blob contains the `AskUserQuestion` call extracted from the worker's conversation transcript — questions, options, descriptions, and headers as exact structured data.

**Timeout** (no actionable panes within timeout period):
```
TIMEOUT
STATUS total=N working=N done=N idle=N
```

**All user-focused** (panes exist but user has them all):
```
FOCUSED
STATUS total=N working=N done=N focused=N
```

The `FOCUSED` return is distinct from `TIMEOUT` — it tells the coordinator "there IS work, but the user is handling it." The coordinator can use this to avoid logging false-idle heartbeats.

### Lifecycle Management

The caller never calls `coordinator-connect` or `coordinator-disconnect` directly (`§INV_AWAIT_NEXT_LIFECYCLE`). `await-next` manages the full lifecycle:

- **Call 1**: No previous pane. Sweep → connect → return.
- **Call N**: Disconnect call N-1's pane → sweep → connect → return.
- **On ESC interrupt**: Coordinator exits the wait. Asks user what they want. Then resumes waiting (next call handles lifecycle normally).
- **On focus override**: If the user focuses a managed pane mid-processing, the coordinator aborts, disconnects, sets notify back to `unchecked`, and returns to waiting.

### Blocking Mechanics

When no actionable panes exist, `await-next` blocks efficiently using `tmux wait-for coordinator-wake` rather than polling. Workers automatically fire the wake signal when `engine fleet notify` sets `unchecked`/`error`/`done` on any pane. After wake, `await-next` re-sweeps to get current state (the wake signal just says "something changed," not what changed).

### Inputs

- `--timeout <seconds>`: How long to block before returning TIMEOUT
- `--panes <pane_ids>`: Panes this coordinator manages. If omitted, auto-discovers from `@pane_manages` on the calling pane (set in fleet.yml).

---

## 3. Three-Dimensional State Model

Pane state is three orthogonal dimensions. This model emerged from brainstorm Round 2's analysis of the existing state system — the dimensions were already partially implemented but not formalized.

| Dimension | Variable | Values | Set By | Meaning |
|-----------|----------|--------|--------|---------|
| **Notify** | `@pane_notify` | working, unchecked, error, done, checked | `fleet.sh notify` | WHAT happened in the pane |
| **Coordinator** | `@pane_coordinator_active` | 0/1 | `await-next` (auto) | WHO:bot — coordinator is processing |
| **User Focus** | `@pane_user_focused` | 0/1 | tmux focus hook | WHO:human — user is looking at it |

### Why Three Dimensions?

The original system conflated "what happened" with "who is handling it." The notify dimension (`@pane_notify`) tells WHAT — the pane needs attention, has an error, is done, etc. But it said nothing about WHO is handling the situation. Adding `@pane_coordinator_active` (Round 1 design) distinguished bot-handled from unhandled. But user intervention was still invisible — when a user focused a managed pane, the coordinator couldn't detect the conflict.

The three-dimension model separates concerns cleanly:
- **Notify** answers: "What state is this pane in?"
- **Coordinator** answers: "Is the bot currently processing this pane?"
- **Focus** answers: "Is the human currently looking at this pane?"

### Dimension Interactions

- `await-next` filters: skip panes where `@pane_user_focused = 1` OR `@pane_coordinator_active = 1`
- When user focuses a managed pane (`coordinator_active=1`): coordinator detects, aborts, disconnects, sets notify back to `unchecked`
- When user focuses out: `@pane_user_focused` clears, pane re-enters coordinator eligibility
- `notify-check` (existing): transitions `unchecked → checked` on focus. This is orthogonal to `@pane_user_focused`.

### State Interaction Matrix

All valid combinations of the three dimensions:

| Notify | Coordinator | Focused | Meaning | Coordinator Action |
|--------|----------|---------|---------|-----------------|
| working | 0 | 0 | Worker busy, nobody watching | Skip (not actionable) |
| working | 0 | 1 | Worker busy, user watching | Skip (user present) |
| unchecked | 0 | 0 | Needs attention, nobody on it | **Pick up** (highest priority after error) |
| unchecked | 0 | 1 | Needs attention, user handling | Skip (user present) |
| unchecked | 1 | 0 | Coordinator processing | Should not appear in sweep (already managed) |
| unchecked | 1 | 1 | **Conflict** — user focused managed pane | Abort → disconnect → set unchecked → yield |
| error | 0 | 0 | Error, nobody on it | **Pick up** (highest priority) |
| error | 0 | 1 | Error, user handling | Skip (user present) |
| done | 0 | 0 | Worker finished, nobody checked | **Pick up** (lowest priority) |
| checked | 0 | 0 | User already saw it | Skip (acknowledged) |

### Focus Detection for Interrupt

The coordinator must detect mid-processing that the user focused its current pane. Implementation options (to be decided during `/implement`):

1. **Polling `@pane_user_focused`**: Check the flag between processing steps. Simple but coarse — if the coordinator is mid-LLM-call, it won't detect until the call returns.
2. **tmux hook notification**: The focus hook writes to a signal file or sends a tmux signal. More responsive.
3. **Combined**: Focus hook sets the flag + sends a wake signal to a named pipe the coordinator monitors.

The interrupt behavior: abort current processing → disconnect → set notify to `unchecked` → return to `await-next`.

For full details on the state model, focus mechanics, and interrupt handling, see `COORDINATE.md` §Three-Dimensional State Model and §Focus & Interrupt Mechanics.

---

## 4. Vision Document Spec

The top-level project plan. Lives in `docs/` as a persistent, evergreen document (`§INV_VISION_IS_EVERGREEN`).

### Template: `TEMPLATE_DIRECT_VISION.md`

Owned by `/direct` skill (`skills/direct/assets/TEMPLATE_DIRECT_VISION.md`). The full template is ~300 lines with rich per-chapter structure. Below is the abbreviated structure — see the actual template for all sections.

```markdown
# [Project Name] — Orchestration Vision
**Tags**: [lifecycle tags as needed]

## Provenance
| Field | Value |
|-------|-------|
| **Created by** | `sessions/[DIRECT_SESSION_PATH]` |
| **Mode** | [Greenfield / Evolution (v[N]) / Split ([parent-slug])] |

## 1. Background & Motivation
[Problem statement, current state, opportunity, cost of inaction, stakeholders]

## 2. Vision
### Goal
[What this project achieves. 2-3 sentences.]
### Success Criteria
- [ ] [Measurable outcome 1]
### Non-Goals
### Constraints

## 3. Architecture Sketch
[§CMD_FLOWGRAPH diagrams — target architecture, data flow]

## 4. Decision Principles
[Natural language guidance for the coordinator's judgment calls.]
- Development Approach, Risk & Escalation, Quality & Standards, Prioritization

## 5. Context Sources
[Sessions and documents that informed this vision — bibliography]

## 6. Dependency Graph
[§CMD_FLOWGRAPH — chapter dependencies with parallel groups]

## 7. Glossary

## Chapters

### @[slug/path]: [Human-Readable Title]
**Tags**: #needs-coordinate
[Description]
#### Scope
#### Dependencies
- **Depends on**: [Nothing / @slug/of-dependency]
- **Blocks**: [@slug/of-dependent]
#### Acceptance Criteria
#### Risks & Open Questions
#### Complexity & Effort
```

**Note**: Worker groups are NOT part of the vision template. Worker assignment is handled by `/coordinate` at chapter execution time based on fleet configuration. The vision defines WHAT to build; `/coordinate` decides WHO builds it.

### Properties

- **Evergreen**: Created by `/direct`, updated at any time via `/direct` (Evolution mode), `/brainstorm`, or manual editing. The coordinator reads the latest version at each chapter boundary — mid-chapter changes are visible but not acted on until the next chapter starts.
- **Chapter tags**: Each chapter gets `#needs-coordinate`. The coordinator claims chapters by swapping `#needs-coordinate` → `#claimed-coordinate` → `#done-coordinate`. This reuses the standard tag lifecycle (see `TAG_LIFECYCLE.md`).
- **Parallel chapters**: Chapters with `**Depends on**: Nothing` (or the same dependency) can run in parallel via multiple coordinators. `/direct` performs the dependency analysis to determine which chunks are serial vs parallel.
- **Worker groups**: Managed by `/coordinate` at chapter execution time, NOT in the vision template. The coordinator assigns workers based on fleet configuration and chapter scope. No cross-domain assignment — "layout work goes to layout workers, API work goes to API workers" (brainstorm Round 4).
- **Decision principles**: LLM-native natural language (brainstorm Round 4). The coordinator interprets principles via reasoning rather than executing mechanical rules. Hard rules (always escalate deletions) stay in `coordinate.config.json`; soft guidance lives in the vision.

### Delegation Lifecycle Integration

The vision document's chapter tags connect to the existing delegation system, but with important differences from standard delegation:

**Standard delegation** (`TAG_LIFECYCLE.md`):
```
Agent creates #needs-X → Human approves → #delegated-X → Daemon spawns worker → #claimed-X → #done-X
```

**Coordinator chapter delegation**:
```
User creates vision with #needs-coordinate chapters → Coordinator claims #needs-coordinate → #claimed-coordinate → #done-coordinate
```

Key differences:
1. **No daemon involvement**: The coordinator claims chapters directly. There is no `#delegated-coordinate` state — the coordinator IS the dispatcher for its own chapters.
2. **No human approval gate between chapters**: Once the user creates the vision, the coordinator progresses autonomously. The human gate is at vision creation time, not at each chapter transition.
3. **Serial, not parallel**: Standard delegation can batch multiple `#delegated-X` items for parallel workers. Chapter progression is strictly serial (`§INV_STRICT_CHAPTER_GATES`).
4. **Same tag infrastructure**: Despite the semantic differences, the coordinator uses the same `tag.sh swap` mechanics. A stale `#needs-coordinate` tag is discoverable by `engine tag find` just like any other `#needs-X` tag.

### What Happens to Stale Chapters

If the coordinator dies mid-project (context overflow with no restart, user abandons):
- **Current chapter**: `#claimed-coordinate` tag remains. `/delegation-review` can surface it as stale work.
- **Future chapters**: `#needs-coordinate` tags remain. A new `/coordinate` session can pick them up.
- **Vision doc**: Unchanged. The user can resume the project by invoking `/coordinate` again with the same vision path.

---

## 5. Chapter Plan Spec

The per-chapter execution plan. Lives in the session directory as an `/coordinate` session artifact. Created during Phase 2 (Chapter Planning) after the coordinator interrogates the vision doc and other context sources.

### Template: `TEMPLATE_COORDINATION_PLAN.md`

A rich worker guidance document with 9 required sections. The chapter plan is the PRIMARY context for workers — rich enough that workers rarely need to escalate to the coordinator.

**Sections**:

1. **Provenance** — Vision doc path, previous chapter, chapter number, requesting session
2. **Objective & Context** — What this chapter achieves, how it fits the larger vision, scope boundaries
3. **Decision Principles** — Named `RUL_` rules inherited from vision doc (by reference) + chapter-specific additions. Workers load the vision doc too, so principles only need to be referenced, not duplicated.
4. **Architecture & Design Notes** — Technical decisions with rationale, patterns to follow, constraints
5. **Work Items** — Two formats: Big Task (description, acceptance criteria, dependencies, key files, sub-checklist, hints) and Small Task (description, assigned group, key files, criteria). Prefer fewer bigger tasks with sub-checklists over many small tickets.
6. **Worker Briefing** — Per-group briefings with dedicated context (assigned items, skills expected, files to load, group-specific guidance)
7. **Open Questions & Gaps** — Tagged with `#needs-*` for deferred resolution. Each includes impact assessment and suggested resolution path.
8. **Completion Criteria** — Functional, quality, and process criteria. ALL must pass before chapter is marked `#done-coordination`.
9. **References & Context Sources** — Vision doc, prior chapters, relevant docs, code paths, analysis sessions

### Properties

- **Rich guidance**: The plan is conceptually a "groomed ticket" — the coordinator enriches it with details, understanding, philosophy, and decisions during Chapter Planning. Workers should be able to work independently from the chapter plan alone.
- **`RUL_` convention**: Decision principles use named `RUL_UPPER_SNAKE` identifiers for cross-document referencing. Vision doc defines rules; chapter plan references them by name. Same pattern as `INV_` and `PTF_`.
- **Two task formats**: Big tasks have full acceptance criteria and sub-checklists. Small tasks are lightweight. The coordinator chooses the format during planning based on task complexity.
- **Checkboxes**: Progress tracking inline. Coordinator checks items as workers complete them. Checkbox state is the ground truth for chapter completion — not worker self-reports.
- **Group assignments**: Work items assigned to worker groups, not individual workers. The coordinator dispatches to groups; individual worker selection within a group is opportunistic (whoever is idle).
- **Completion criteria**: Must ALL pass before chapter is marked done and next chapter starts. This is the enforcement mechanism for `§INV_STRICT_CHAPTER_GATES`.
- **Session-scoped**: Each chapter = one `/coordinate` session in `sessions/`. The session gets its own log, debrief, and artifact trail. Cross-chapter continuity comes from the vision doc and `**Previous Chapter**` reference.
- **Vision link**: The `**Vision**` field creates a two-way reference — the vision doc lists chapters with tags, and each chapter plan links back to the vision.
- **Backward compat**: The coordinator can consume any structured document (brainstorm, analysis, etc.) as input — not limited to `/direct` vision docs. Works best with vision docs but adapts to varied document structures.

---

## 6. Chapter Lifecycle

```
Vision Doc (docs/)
  │
  ├── Chapter 1: #needs-coordinate
  │     │
  │     ├── Coordinator claims: #needs-coordinate → #claimed-coordinate
  │     ├── Creates session: sessions/YYYY_MM_DD_CHAPTER_1_NAME/
  │     ├── Loads chapter plan from template
  │     ├── Delegates work to worker groups
  │     ├── Tracks checkboxes
  │     ├── All criteria met → marks chapter #done-coordinate
  │     └── Starts next chapter automatically
  │
  ├── Chapter 2: #needs-coordinate
  │     └── (same lifecycle)
  │
  └── Chapter N: #needs-coordinate
        └── (same lifecycle)
```

### Autonomous Progression

When a chapter completes:
1. Coordinator marks current chapter `#done-coordinate` in the vision doc
2. Coordinator synthesizes the current chapter session (debrief, artifact report)
3. Coordinator scans the vision doc for next `#needs-coordinate` chapter
4. If found: claims it (`#needs-coordinate` → `#claimed-coordinate`), creates new session, begins execution
5. If not found: all chapters complete — coordinator reports to user and exits

This is the core "self-driving" behavior (brainstorm Round 8). The user produces the high-level vision, and the coordinator drives through chapters autonomously. The user can evolve the vision over time — the coordinator reads the latest version at chapter start.

### Worked Example: 3-Chapter Project

**Vision**: "Refactor the authentication module — separate concerns, add rate limiting, standardize errors."

**Chapter 1: Separate Concerns** (`#needs-coordinate`)
- Scope: Extract token management into its own service. Move session logic out of the auth controller.
- Worker Groups: API group (2 workers)
- Completion: All auth endpoints still pass. Token service has its own test suite.

**Chapter 2: Rate Limiting** (`#needs-coordinate`, depends on Chapter 1)
- Scope: Add per-endpoint rate limiting. Use the new token service's rate-limit hooks.
- Worker Groups: API group (2 workers)
- Completion: Rate limit tests pass. Load test shows correct throttling.

**Chapter 3: Error Standardization** (`#needs-coordinate`, depends on Chapter 2)
- Scope: Standardize all auth error responses to follow API convention. Update client SDK.
- Worker Groups: API group (1 worker), SDK group (1 worker)
- Completion: All error responses match convention. SDK integration tests pass.

**Execution flow**:
1. User invokes `/coordinate` with the vision doc path. Coordinator claims Chapter 1.
2. Coordinator creates `sessions/2026_02_15_CHAPTER_1_SEPARATE_CONCERNS/`, populates chapter plan.
3. Coordinator dispatches work items to API group workers via delegation tags.
4. Workers ask questions → coordinator answers autonomously or escalates.
5. All checkboxes checked, completion criteria met → coordinator marks `#done-coordinate` on Chapter 1.
6. Coordinator synthesizes Chapter 1 session, scans vision, claims Chapter 2.
7. Creates `sessions/2026_02_15_CHAPTER_2_RATE_LIMITING/`, dispatches to API group.
8. Repeat until Chapter 3 completes. Coordinator reports: "All chapters complete."

Total human interaction: vision creation + occasional escalations. Potentially hours of unattended work.

### Failure Modes

| Failure | What Happens | Recovery |
|---------|-------------|----------|
| **Context overflow mid-chapter** | Dehydrate → restart → resume at saved phase. Chapter plan checkboxes preserved. | Automatic via `§CMD_DEHYDRATE` / `§CMD_RESUME_SESSION`. The coordinator resumes its event loop with the same chapter plan. |
| **Worker crashes** | Worker's pane shows error state. Coordinator detects via `await-next` (`error` priority). | Coordinator escalates to human. `§INV_COORDINATOR_NEVER_RESTARTS_WORKERS` — the coordinator never kills or restarts workers. |
| **Vision changes mid-chapter** | Coordinator doesn't see changes until next chapter boundary. | By design. Mid-chapter stability prevents half-completed chapters from drifting. User can force a chapter restart by manually swapping `#claimed-coordinate` → `#needs-coordinate`. |
| **Chapter fails (criteria never met)** | Coordinator keeps waiting. After consecutive timeouts, escalates to human. | Human can: (a) fix the blocking issue, (b) relax completion criteria in the chapter plan, (c) skip the chapter via manual tag swap. |
| **All workers stuck** | All managed panes show `unchecked` or `error`. Coordinator escalates each one. | Human intervention required. The coordinator surfaces the situation but cannot resolve stuck workers. |
| **Coordinator killed (no dehydration)** | `#claimed-coordinate` remains on current chapter. Future chapters stay `#needs-coordinate`. | Re-invoke `/coordinate` with the same vision. Coordinator detects `#claimed-coordinate`, resumes that chapter (or starts fresh if session is gone). |
| **Chapter dependencies broken** | Chapter N depends on Chapter N-1, but N-1's completion criteria were relaxed. | Chapter plans should encode dependencies in completion criteria. The coordinator doesn't validate cross-chapter dependencies — the vision author must ensure coherence. |

---

## 7. Skill Pipeline Integration

### Plan Creation Workflow

The recommended workflow for producing a vision document:

1. `/analyze` — Research the project scope, identify components and dependencies
2. `/brainstorm` — Explore trade-offs, design approaches, make key decisions
3. `/direct` — Produce the vision document: chapters (serial/parallel), worker groups, decision principles
4. `/coordinate` — Execute the vision

**Concrete example**: Building a new payment processing system.

```
/analyze — "Analyze the current payment flow, identify all touchpoints,
            map external API dependencies"
  → Produces: ANALYSIS.md with component map, dependency graph, risk areas
  → Session: sessions/2026_02_15_PAYMENT_ANALYSIS/

/brainstorm — "Design the payment system rebuild. Use the analysis from
               sessions/2026_02_15_PAYMENT_ANALYSIS/ANALYSIS.md"
  → Produces: BRAINSTORM.md with architecture decisions, trade-offs
  → Session: sessions/2026_02_15_PAYMENT_BRAINSTORM/

/direct — "Create the orchestration direct for the payment rebuild.
            Source: sessions/2026_02_15_PAYMENT_BRAINSTORM/BRAINSTORM.md"
  → Produces: docs/PAYMENT_REBUILD_VISION.md
  → Performs dependency analysis: Chapters 1-2 serial, Chapter 3 parallel with 2
  → Tags: Each chapter has #needs-coordinate
  → Session: sessions/2026_02_15_PAYMENT_DIRECT/

/coordinate — "Execute docs/PAYMENT_REBUILD_VISION.md"
  → Claims Chapter 1, creates session, begins autonomous execution
```

### Per-Chapter Workflow

Each chapter optionally benefits from preparation:

1. `/analyze` — Research the chapter's scope in detail (optional, for complex chapters)
2. `/brainstorm` — Design the chapter's approach (optional, for chapters with ambiguous scope)
3. `/coordinate` — Execute the chapter (required)

For simple chapters, the coordinator can skip directly to execution. For complex chapters, the full pipeline produces better plans. The coordinator has visibility into the broader project context (vision doc, previous chapters) when creating chapter plans, so lightweight chapters often don't need separate analysis.

### Template Ownership

- `TEMPLATE_DIRECT_VISION.md` — owned by `/direct` skill, in `skills/direct/assets/`. The vision template lives upstream of `/coordinate` because `/direct` creates the vision.
- `TEMPLATE_COORDINATION_PLAN.md` — owned by `/coordinate` skill, in `skills/coordinate/assets/`. Chapter plans are execution artifacts created by the coordinator at chapter start.
- Behavior config (`coordinate.config.json`) — separate, unchanged. HOW the coordinator operates, not WHAT.

---

## 8. Delegation System Integration

The orchestration system intersects with the existing delegation system at multiple points. Understanding these intersections is critical for implementation.

### How the Coordinator Uses Tags

The coordinator operates within the tag lifecycle but with a specialized flow:

```
Standard delegation (TAG_LIFECYCLE.md):
  #needs-X → #delegated-X → #claimed-X → #done-X
  (staging)   (approved)     (worker)     (resolved)

Coordinator chapter flow:
  #needs-coordinate → #claimed-coordinate → #done-coordinate
  (in vision)      (coordinator took it)  (chapter done)
```

The `#delegated-coordinate` state is skipped because the coordinator IS the dispatcher — it claims its own work. There's no need for daemon involvement or human approval between chapters; the human approved the entire project when they created the vision.

### Coordinator-Created Tags

During chapter execution, the coordinator may create standard delegation tags:

1. **Worker questions that can't be answered**: If the coordinator encounters a question it can't handle (category escalation or low confidence) and the human is unavailable, it can tag the item `#needs-brainstorm` or `#needs-research` for later resolution.

2. **Cross-chapter work items**: If the coordinator discovers during Chapter N that Chapter N+2 needs additional scope, it can add `#needs-coordinate` items to future chapters in the vision doc — or tag inline items with `#needs-implementation` for the standard delegation path.

3. **Side discoveries**: Like any agent, the coordinator may discover issues outside its current scope. These get tagged via `§CMD_HANDLE_INLINE_TAG` and flow through the normal dispatch pipeline (`§CMD_DISPATCH_APPROVAL` during synthesis).

### How Standard Delegation Complements Orchestration

The coordinator and the daemon operate in parallel, not in conflict:

- **Coordinator** handles *project-level* work — chapters, milestones, coordinated multi-worker tasks.
- **Daemon** handles *ad-hoc* delegation — individual `#needs-X` items from any session.
- **No overlap**: The coordinator uses `#needs-coordinate` tags (chapter dispatch). The daemon monitors other `#delegated-X` tags. They share tag infrastructure but different tag nouns.

### Connection to TAG_LIFECYCLE.md

The `#needs-coordinate` tag follows `§FEED_GENERIC` conventions from `SIGILS.md`:
- Created on the vision doc's chapter headings
- Discoverable via `engine tag find '#needs-coordinate'`
- Swapped via `engine tag swap`
- Governance: bare inline tags in session artifacts are caught by `§CMD_RESOLVE_BARE_TAGS`

The coordinator's tag noun (`coordinate`) maps to the `/coordinate` skill per `¶INV_1_TO_1_TAG_SKILL`. This means `#needs-coordinate` items can theoretically flow through the standard daemon path (`#delegated-coordinate` → daemon spawns `/coordinate`), though the primary flow is direct claiming from the vision doc.

---

## 9. SKILL.md Phase Structure

The coordinator SKILL.md (`~/.claude/skills/coordinate/SKILL.md`) has 6 main phases plus synthesis sub-phases:

```
0: Setup → 1: Chapter Interrogation → 2: Chapter Planning → 3: Dispatch → 4: Oversight Loop → 5: Synthesis (5.1-5.4)
```

### Phase 3: Dispatch (Task-to-Worker Mapping)

Between planning and the oversight loop, the Dispatch phase maps work items to workers:
1. Read the chapter plan's work items (checkboxes in `COORDINATION_PLAN.md`)
2. Match work items to available worker groups (by skill/group from fleet status)
3. Present the suggested mapping to the user
4. On approval: apply `#delegated-coordination` + `%worker` tags to plan items
5. Gate: proceed to loop / adjust / back to plan / exit

The coordinator prepares the mapping PROACTIVELY — the user sees a suggested assignment, not a blank form. This phase uses the `¶ASK_COORDINATE_DISPATCH_EXIT` decision tree.

### Phase Navigation (Decision Trees)

Each post-planning phase has a structured gate with back-navigation:

*   **`¶ASK_COORDINATE_PLAN_EXIT`** (Phase 2 gate): Proceed to dispatch / refine plan / close session / return to interrogation / skip to loop
*   **`¶ASK_COORDINATE_DISPATCH_EXIT`** (Phase 3 gate): Enter loop / adjust mapping / return to planning / close session / add more items
*   **`¶ASK_COORDINATE_LOOP_EXIT`** (Phase 4 ESC menu): Resume / fleet status / synthesis / return to dispatch / return to planning / relay message

Back-navigation uses `--user-approved` per `§INV_PHASE_ENFORCEMENT`. Early exit (close session after planning or dispatch) deactivates cleanly — the plan artifact persists.

### Chapter Initialization (Phase 0)

During setup, the coordinator:
1. Loads vision document (from `contextPaths` or parameter)
2. Finds current chapter (scan for `#claimed-coordinate` or next `#needs-coordinate`)
3. Validates fleet is running
4. Discovers target panes

### Chapter Completion Check (Phase 4)

On TIMEOUT (all panes idle) within the oversight loop:
1. Read chapter plan checkboxes
2. If all items checked AND all completion criteria met:
   - Synthesize current chapter session (debrief, artifacts)
   - Mark chapter `#done-coordinate` in vision doc
   - Scan for next `#needs-coordinate` chapter
   - If found: claim it, initialize new chapter (new session)
   - If not: report completion, exit
3. If not all met: log status, assign filler work to idle workers if applicable

### Filler Work Assignment

When workers are idle (all chapter items assigned, waiting for other groups to finish per `§INV_STRICT_CHAPTER_GATES`), the coordinator can assign filler work:
- Chores (`#needs-chores` items from the backlog)
- Documentation updates
- Test improvements
- Code cleanup in the chapter's scope

This is optional and configurable. The coordinator should not assign filler work that could conflict with in-progress chapter items.

---

## 10. Design Decisions & Reasoning

Key design choices from the brainstorm, with the reasoning captured for future maintainers.

### Why Strict Chapter Gates?

**Decision**: Chapter boundaries are sync points. All worker groups must complete their chapter work before any group starts the next chapter (`§INV_STRICT_CHAPTER_GATES`).

**Reasoning** (brainstorm Round 6): Conservative and simple. The alternative — letting fast groups start the next chapter early — introduces cross-chapter dependency management, which requires tracking which work items from Chapter N+1 depend on Chapter N's outputs. This complexity isn't worth the time savings, especially since idle workers can do filler work.

**Trade-off**: Some worker idle time between chapters. Accepted for simplicity.

### Why Serial Chapters?

**Decision**: Chapters execute one at a time, in order.

**Reasoning**: Parallel chapter execution would require the coordinator to track multiple chapter plans simultaneously, manage cross-chapter resource conflicts, and handle partial completion states. The coordinator's serial processing constraint (`§INV_SERIAL_PROCESSING`) already limits it to one pane at a time — adding parallel chapters would fight this constraint at the architectural level.

**Future consideration**: Multi-coordinator (multiple `/coordinate` sessions running different chapters in parallel) is architecturally possible but not in scope. Each coordinator would manage its own fleet, preventing git conflicts.

### Why Vision Is Evergreen?

**Decision**: The vision document can be edited at any time (`§INV_VISION_IS_EVERGREEN`). The coordinator reads the latest version at chapter start.

**Reasoning** (brainstorm Round 8): Projects evolve. Insights from Chapter 1 may change the scope of Chapter 3. Forcing the user to re-create the entire vision would be wasteful. Instead, the vision is a living document — the user updates it, and the coordinator picks up changes at the next chapter boundary.

**Constraint**: Mid-chapter changes are NOT acted on until the current chapter completes. This prevents scope drift within a chapter.

### Why Worker Groups Instead of Individual Assignments?

**Decision**: Work items are assigned to groups, not individual workers (brainstorm Round 4).

**Reasoning**: Workers within a group are interchangeable for the group's domain. Assigning to groups means the coordinator can dispatch to whoever is idle, rather than waiting for a specific worker. It also aligns with fleet workgroups — the fleet already organizes workers by proficiency domain.

**No cross-domain assignment**: "Layout work goes to layout workers, API work goes to API workers." This prevents git conflicts (workers in the same domain coordinate via the chapter plan) and context confusion (a worker that understands the domain produces better work).

### Why Decision Principles Are Natural Language?

**Decision**: Escalation heuristics in the plan are natural language, not structured rules (brainstorm Round 4).

**Reasoning**: The coordinator is an LLM — it interprets natural language natively. Structured rules (JSON config) work for hard categories ("always escalate deletions") but are too rigid for judgment calls. "Prefer speed over thoroughness" is meaningful to an LLM but hard to encode as a rule. The config retains hard rules; the plan provides soft guidance.

---

## 11. Edge Cases & Failure Modes

Comprehensive catalog of edge cases and their expected behavior.

### Vision Document Issues

| Edge Case | Behavior |
|-----------|----------|
| **Vision doc missing** | Coordinator fails at chapter initialization. Reports error: "Vision document not found at [path]." User must provide a valid path. |
| **Vision doc has no chapters** | Coordinator reports: "No chapters found in vision." Exits gracefully. |
| **Vision doc has no `#needs-coordinate` chapters** | All chapters are `#claimed-coordinate` or `#done-coordinate`. Coordinator reports: "All chapters complete." |
| **Vision doc has chapters with unmet dependencies** | Coordinator respects `**Depends on**` field. If Chapter 3 depends on Chapter 2 but Chapter 2 isn't `#done-coordinate`, the coordinator skips Chapter 3 and reports the dependency. |
| **Multiple `#needs-coordinate` chapters, non-sequential** | Coordinator picks the lowest-numbered unclaimed chapter. If Chapter 1 is `#done-coordinate` and Chapters 2 and 4 are `#needs-coordinate`, the coordinator claims Chapter 2. |

### Chapter Execution Issues

| Edge Case | Behavior |
|-----------|----------|
| **No workers available for a group** | Coordinator cannot dispatch work items for that group. Escalates to human: "No workers available for [group]. Fleet may need reconfiguration." |
| **Worker accepts work item but never completes** | Coordinator's timeout cycle detects no progress. After configurable consecutive timeouts, escalates: "Worker [pane] appears stuck on [item]." |
| **Completion criteria can never be met** | Coordinator keeps waiting and escalating. Human must intervene — either fix the issue, relax criteria, or skip the chapter. |
| **Chapter plan has zero work items** | Degenerate case. Coordinator immediately checks completion criteria (which should all be met since there's nothing to do) and advances. |

### Context Overflow Issues

| Edge Case | Behavior |
|-----------|----------|
| **Overflow mid-chapter** | Standard dehydration. Chapter plan checkboxes are preserved (they're in the session directory). New Claude resumes the event loop with the same chapter context. |
| **Overflow between chapters** | Chapter boundary is a natural restart point. The dehydrated context includes the vision path and current chapter. New Claude re-reads the vision, finds the next `#needs-coordinate` chapter, and continues. |
| **Overflow during chapter initialization** | Dehydration captures "mid-initialization" state. New Claude re-runs initialization (idempotent — the chapter plan is written to disk). |
| **Repeated overflows on same chapter** | Each restart resumes from the same checkpoint. If the chapter's work is too large for a single context window, the coordinator makes incremental progress across restarts (checkbox state persists). |

### Multi-Agent Coordination Issues

| Edge Case | Behavior |
|-----------|----------|
| **Two coordinators claim the same chapter** | `engine tag swap` is not race-safe across processes (unlike `tag.sh swap` for daemon claims). This is a known gap — serial chapter execution and single-coordinator design make it unlikely. Future multi-coordinator work must address this. |
| **Worker makes a git conflict** | The coordinator doesn't manage git. Workers commit independently. Git conflicts are resolved by the workers or escalated to the human. |
| **Fleet restarts during chapter** | Workers lose their Claude sessions. The coordinator detects changed pane states on the next `await-next` sweep. Workers' `#unchecked` notifications trigger re-engagement. |

---

## 12. Implementation Scope

Recommended split (from brainstorm Round 9):

### Phase 1: Infrastructure (`fleet.sh`)
- `await-next` v2 (auto-connect, auto-disconnect, capture inline, priority selection)
- `@pane_user_focused` flag + tmux focus hook wiring
- Focus-based interrupt mechanism
- Tests for all new behavior

### Phase 2: Plan System
- `TEMPLATE_DIRECT_VISION.md` (owned by `/direct` skill)
- `TEMPLATE_COORDINATION_PLAN.md` (owned by `/coordinate` skill)
- `/direct` skill — vision creation with dependency analysis (serial/parallel chunks)
- Plan loading and parsing logic in `/coordinate` (read vision, find chapters, create session)
- Chapter progress tracking (checkbox management via file edits)

### Phase 3: SKILL.md + Chapter Lifecycle
- Chapter initialization sub-phase in SKILL.md
- Modified main loop with plan context and decision principles
- Autonomous chapter progression (claim → execute → complete → next)
- Vision doc tag management (`#needs-coordinate` → `#claimed-coordinate` → `#done-coordinate`)
- Strict chapter gates (wait for all groups)
- Filler work assignment (optional)

---

## 13. Invariants

| Invariant | Definition | Source |
|-----------|-----------|--------|
| `¶INV_SERIAL_PROCESSING` (existing) | One pane at a time. No background signals. | coordinate/SKILL.md |
| `¶INV_STRICT_CHAPTER_GATES` (new) | Chapter boundaries are sync points. All groups complete before any start next. | Brainstorm Round 6 |
| `¶INV_VISION_IS_EVERGREEN` (new) | Vision doc is a living document. Coordinator reads latest at chapter start. | Brainstorm Round 8 |
| `¶INV_AWAIT_NEXT_LIFECYCLE` (new) | `await-next` manages connect/disconnect. Caller never calls them directly. | Brainstorm Round 3 |
| `¶INV_AUTO_DISCONNECT_ON_STATE_CHANGE` (existing) | Clears coordinator_active on non-unchecked transition. | fleet.sh |
| `¶INV_TRANSCRIPT_IS_API` (new) | Worker questions read from transcripts; answers via send-keys. | coordinate/SKILL.md |
| `¶INV_COORDINATOR_NEVER_RESTARTS_WORKERS` (existing) | Coordinator sends keystrokes only. Stuck workers escalated to human. | coordinate/SKILL.md |

---

## 14. Open Questions (For Implementation)

1. **Focus interrupt detection**: Polling vs. hook notification vs. named pipe? Trade-off is responsiveness vs. complexity. Polling is simplest (check `@pane_user_focused` between assess/decide steps). Hook notification via named pipe is more responsive but adds infrastructure. **Recommended**: Start with polling, upgrade to hook notification if latency is unacceptable.

2. **Filler work assignment**: How does the coordinator decide what filler work to assign idle workers? Options: (a) maintain a backlog section in the chapter plan, (b) scan `#needs-chores` tags globally, (c) generate filler from the project's tech debt. **Recommended**: Scan `#needs-chores` and `#needs-documentation` tags — this reuses existing infrastructure.

3. **Chapter plan creation**: Does the coordinator create the chapter plan itself (from the vision doc), or does it expect the plan to already exist? **Recommended**: Coordinator creates it from the template, using the vision's chapter description as input. For complex chapters, a preparatory `/brainstorm` session can produce a richer plan.

4. **Multi-coordinator**: Can two coordinators run different chapters in parallel? Current design says no (serial chapters). **Recommended**: Defer. The tag system supports it (different tag instances), but multi-coordinator coordination (shared vision doc, resource conflicts) is complex. Revisit when serial execution becomes a bottleneck.

5. **Vision doc format validation**: Should the coordinator validate the vision doc against the template, or trust the author? **Recommended**: Light validation — check for `## Chapters` section and at least one `#needs-coordinate` tag. Don't enforce template compliance strictly; the coordinator can work with minimal structure.
