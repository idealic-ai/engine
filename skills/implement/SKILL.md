---
name: implement
description: "Drives feature implementation following structured development protocols. Triggers: \"implement this feature\", \"build this\", \"write the code\", \"TDD implementation\", \"execute the plan\"."
version: 2.0
---

Drives feature implementation following structured development protocols.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/standards/COMMANDS.md`, `~/.claude/standards/INVARIANTS.md`, and `~/.claude/standards/TAGS.md`.
2. LOAD PROJECT STANDARDS: Read `.claude/standards/INVARIANTS.md`.
3. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
4. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`
> - Project INVARIANTS.md: `________ or N/A`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Implementation Protocol (The Builder's Code)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 3 (Interrogation) and Phase 4 (IMPLEMENTATION_PLAN.md). The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Phases (for §CMD_PARSE_PARAMETERS)
*Include this array in the `phases` field when calling `session.sh activate`:*
```json
[
  {"major": 1, "minor": 0, "name": "Setup"},
  {"major": 2, "minor": 0, "name": "Context Ingestion"},
  {"major": 3, "minor": 0, "name": "Interrogation"},
  {"major": 4, "minor": 0, "name": "Planning"},
  {"major": 5, "minor": 0, "name": "Build Loop"},
  {"major": 6, "minor": 0, "name": "Synthesis"}
]
```
*Phase enforcement (¶INV_PHASE_ENFORCEMENT): transitions must be sequential. Use `--user-approved` for skip/backward.*

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is IMPLEMENTATION (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_PARSE_PARAMETERS` to activate the session and discover context (alerts, delegations, RAG).
    > 6. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Senior Tech Lead** and **Quality Assurance**.
    >    **Goal**: To execute a flawless implementation by forcing strict planning, rigorous logging, and TDD.
    >    **Mindset**: "Measure Twice, Cut Once." But when you cut, record *every* move.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md` (Template for the final debrief/report)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md` (Template for technical execution planning)
    *   `.claude/standards/TESTING.md` (Testing standards and TDD rules — project-level, load if exists)

3.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — constructs the session parameters JSON and pipes it to `session.sh activate` via heredoc.
    *   activate creates the session directory, stores parameters in `.state.json`, and returns context:
        *   `## Active Alerts` — files with `#active-alert` (add relevant ones to `contextPaths` for Phase 2)
        *   `## Open Delegations` — files with `#needs-delegation` (assess relevance, factor into plan)
        *   `## RAG Suggestions` — semantic search results from session-search and doc-search (add relevant ones to `contextPaths`)
    *   **No JSON chat output** — parameters are stored by activate, not echoed to chat.

4.  **Scope**: Understand the [Topic] and [Goal].

5.  **Process Context**: Parse activate's output for alerts, delegations, and RAG suggestions. Add relevant items to `contextPaths` for ingestion in Phase 2.
    *   *Note*: Open delegation requests may also appear mid-session. Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS` during Synthesis to catch late arrivals.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`, `________`
> - Activate context: alerts=`___`, delegations=`___`, RAG=`___`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Context Ingestion"** — Load project files and RAG context
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Context Ingestion
*Load the raw materials before processing.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Context sources presented: `________`
> - Files loaded: `________ files`
> - User confirmed: `yes / no`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Context loaded. How to proceed?"
> - **"Proceed to Phase 3: Interrogation"** — Validate assumptions before planning
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Planning"** — I already have a clear plan or requirements are obvious

---

## 3. The Interrogation (Pre-Flight Check)
*Before writing a plan, ensure you know the terrain.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to validate assumptions.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: First, ask the user to choose interrogation depth. Then execute rounds.

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Task is well-understood, small scope, clear requirements |
| **Medium** | 6+ | Moderate complexity, some unknowns, multi-file changes |
| **Long** | 9+ | Complex system changes, many unknowns, architectural impact |
| **Absolute** | Until ALL questions resolved | Novel domain, high risk, critical system, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Interrogation Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

### Interrogation Topics (Implementation)
*Examples of themes to explore. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Scope & constraints** — boundaries, what's in/out, existing patterns to follow
- **Data flow** — who owns the data, state transitions, schemas involved
- **Edge cases** — error handling, empty states, concurrency, race conditions
- **Testing strategy** — unit vs integration, mocking approach, fixtures, coverage goals
- **Risks & unknowns** — reversibility, assumptions being made, what could go wrong
- **Performance & security** — latency concerns, auth, input validation, resource limits
- **Dependencies** — external services, package changes, deployment, migration
- **API surface & naming** — public interfaces, backwards compatibility, naming conventions
- **Failure modes** — rollback strategy, monitoring, alerting, degraded operation
- **Integration** — how this fits existing systems, circular dependencies, shared state

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 4: Planning"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`

---

## 4. The Planning Phase
**Unless the user points to an existing plan, you MUST create one.**

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Planning.
> 2. I will `§CMD_POPULATE_LOADED_TEMPLATE` using `IMPLEMENTATION_PLAN.md` template to draft the IMPLEMENTATION_PLAN.md.
> 3. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding to build.

1.  **Create Plan**: Execute `§CMD_POPULATE_LOADED_TEMPLATE` (Schema: `IMPLEMENTATION_PLAN.md`).
2.  **Present**: Report the plan file via `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - IMPLEMENTATION_PLAN.md written: `________`
> - Plan presented: `________`
> - User approved: `________`

### Optional: Plan Walk-Through
Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Plan is ready. Walk through the steps before building?"
  debriefFile: "IMPLEMENTATION_PLAN.md"
  itemSources:
    - "## 6. Step-by-Step Implementation Strategy"
  planQuestions:
    - "Any concerns about this step's approach or complexity?"
    - "Should the scope change — expand, narrow, or split this step?"
    - "Dependencies or risks I'm missing?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/standards/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 4: Plan ready. How to proceed?"
> - **"Launch builder agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 4b. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 4 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"builder"`
*   `startAtPhase`: `"Phase 5: Build Loop"`
*   `planOrDirective`: `[sessionDir]/IMPLEMENTATION_PLAN.md`
*   `logFile`: `IMPLEMENTATION_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md`
*   `logTemplate`: `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md`
*   `taskSummary`: `"Execute the implementation plan: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"builder"`
*   `planFile`: `[sessionDir]/IMPLEMENTATION_PLAN.md`
*   `logFile`: `IMPLEMENTATION_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md`
*   `logTemplate`: `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md`
*   `taskSummary`: `"Execute the implementation plan: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 5 as normal.
**If "Revise the plan"**: Return to Phase 4 for revision.

---

## 5. The Build Loop (TDD Cycle)
*Iterate through the Plan. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Build Loop.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage the TDD cycle.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_IMPLEMENTATION_LOG.md` EXACTLY) to `§CMD_THINK_IN_LOG` continuously.
> 4. I will execute Red-Green-Refactor (`§CMD_REFUSE_OFF_COURSE` applies).
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### 🧠 Thought Triggers (When to Log)
*Review this list before every tool call. If your state matches, log it.*

*   **Starting a Step?** -> Log `▶️ Task Start` (Goal, Strategy, Dependencies).
*   **Hit an Error?** -> Log `🚧 Block` (The Error, The Context).
*   **Confused?** -> Log `😨 Stuck` (The Symptom, The Trace).
*   **Made a Choice?** -> Log `💡 Decision` (Why A over B?).
*   **Found Debt?** -> Log `💸 Tech Debt` (The Shortcut, The Risk).
*   **Success?** -> Log `✅ Success` (Changes, Verification).

**Constraint**: **Stream-of-Consciousness Logging**. Use `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` constantly. Do not wait for a task to be "finished" to log. Log as you think, especially when implementation gets complex.
**Constraint**: **TIMESTAMPS**. Every log entry MUST start with `[YYYY-MM-DD HH:MM:SS]` in the header.
**Constraint**: **BLIND WRITE**. Do not re-read the file. See `§CMD_AVOID_WASTING_TOKENS`.
**Guidance**: The Log is your *Brain*. If you didn't write it down, it didn't happen.

**Build Cycle**:
1.  **Write Test (Red)**: Create the test case.
2.  **Code (Green)**: Implement the solution.
3.  **Log**: Update `IMPLEMENTATION_LOG.md` with your status.
4.  **Tick**: Mark `[x]` in `IMPLEMENTATION_PLAN.md`.

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Plan steps completed: `________`
> - Tests pass: `________`
> - IMPLEMENTATION_LOG.md entries: `________`
> - Unresolved blocks: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 5: Build loop complete. How to proceed? (Type 'Other' to describe new requirements — will route to interrogation.)"
> - **"Proceed to Phase 6: Synthesis"** — Generate debrief and close session
> - **"Stay in Phase 5"** — More work needed, continue building
> - **"Run verification first"** — Run tests/lint before closing

**On "Other" (free-text)**: The user is describing new requirements or additional work. Route to Phase 3 (Interrogation) to scope it before building — do NOT stay in Phase 5 or jump to synthesis. Use `session.sh phase` with `--user-approved` to go backward.

---

## 6. The Synthesis (Debrief)
*When all tasks are complete.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 6: Synthesis.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_IMPLEMENTATION.md` EXACTLY) to summarize the build.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The debrief FILE is the primary deliverable — chat output alone is not sufficient.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `IMPLEMENTATION.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Deviation Analysis**: Compare Plan vs. Log. Where did we struggle?
  *   **Tech Debt**: What did we hack to get it working?
  *   **The Story**: Narrate the build journey.
  *   **Next Steps**: Clear recommendations for the next session.

**Step 2**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 3**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 4**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 5**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Implementation complete. Walk through the changes?"
  debriefFile: "IMPLEMENTATION.md"
  itemSources:
    - "## 3. Plan vs. Reality (Deviation Analysis)"
    - "## 5. The \"Technical Debt\" Ledger"
    - "## 9. \"Btw, I also noticed...\" (Side Discoveries)"
  actionMenu:
    - label: "Add test coverage"
      tag: "#needs-implementation"
      when: "Change lacks adequate test coverage"
    - label: "Needs documentation"
      tag: "#needs-documentation"
      when: "Change affects user-facing behavior or API surface"
    - label: "Investigate further"
      tag: "#needs-research"
      when: "Change introduced uncertainty or has unknown side effects"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 6 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 6 proof:**
> - IMPLEMENTATION.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 6**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Implementation complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/test` (Recommended) | Code was written — verify it with tests |
| 2 | `/document` | Update documentation to reflect the changes |
| 3 | `/analyze` | Review the implementation for issues or improvements |
| 4 | `/debug` | Something isn't working — investigate and fix |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
