---
name: implement
description: "Drives feature implementation following structured development protocols. Triggers: \"implement this feature\", \"build this\", \"write the code\", \"TDD implementation\", \"execute the plan\"."
version: 2.0
tier: protocol
---

Drives feature implementation following structured development protocols.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 0 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 0 until every blank is filled.

# Implementation Protocol (The Builder's Code)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 2 (Interrogation) and Phase 3 (IMPLEMENTATION_PLAN.md). The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "IMPLEMENTATION",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup"},
    {"major": 1, "minor": 0, "name": "Context Ingestion"},
    {"major": 2, "minor": 0, "name": "Interrogation"},
    {"major": 3, "minor": 0, "name": "Planning"},
    {"major": 3, "minor": 1, "name": "Agent Handoff"},
    {"major": 4, "minor": 0, "name": "Build Loop"},
    {"major": 5, "minor": 0, "name": "Synthesis"}
  ],
  "nextSkills": ["/test", "/document", "/analyze", "/fix", "/chores"],
  "provableDebriefItems": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK", "/delegation-review"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"],
  "planTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md",
  "logTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md",
  "debriefTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md",
  "requestTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_REQUEST.md",
  "responseTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_RESPONSE.md",
  "modes": {
    "general": {"label": "General", "description": "Pragmatic balance", "file": "~/.claude/skills/implement/modes/general.md"},
    "tdd": {"label": "TDD", "description": "Test-driven rigor", "file": "~/.claude/skills/implement/modes/tdd.md"},
    "experimentation": {"label": "Experimentation", "description": "Fast prototyping", "file": "~/.claude/skills/implement/modes/experimentation.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "~/.claude/skills/implement/modes/custom.md"}
  }
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is IMPLEMENTATION (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_PARSE_PARAMETERS` to activate the session and discover context (alerts, delegations, RAG).
    > 6. I will `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md` (Template for the final debrief/report)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md` (Template for technical execution planning)
    *   `.claude/directives/TESTING.md` (Testing standards and TDD rules — project-level, load if exists)
    *   `.claude/directives/PITFALLS.md` (Known pitfalls and gotchas — project-level, load if exists)

3.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — constructs the session parameters JSON and pipes it to `session.sh activate` via heredoc.
    *   activate creates the session directory, stores parameters in `.state.json`, and returns context:
        *   `## Active Alerts` — files with `#active-alert` (add relevant ones to `contextPaths` for Phase 1)
        *   `## RAG Suggestions` — semantic search results from session-search and doc-search (add relevant ones to `contextPaths`)
    *   **No JSON chat output** — parameters are stored by activate, not echoed to chat.

4.  **Scope**: Understand the [Topic] and [Goal].

5.  **Process Context**: Parse activate's output for alerts and RAG suggestions. Add relevant items to `contextPaths` for ingestion in Phase 1.

5.1. **Implementation Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What implementation approach should I use?"
    > - **"General" (Recommended)** — Pragmatic balance: solid code with appropriate testing
    > - **"TDD"** — Test-driven: strict Red-Green-Refactor cycle, tests before code
    > - **"Experimentation"** — Rapid prototype: code first, validate feasibility fast
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Configuration.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/tdd.md`, `modes/experimentation.md`, `modes/general.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 role (from mode file)
    *   Phase 2 interrogation depth (from mode file)
    *   Phase 4 build approach (from mode file)

### §CMD_VERIFY_PHASE_EXIT — Phase 0
**Output this block in chat with every blank filled:**
> **Phase 0 proof:**
> - Mode: `________` (tdd / experimentation / general / custom)
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`, `________`
> - Activate context: alerts=`___`, delegations=`___`, RAG=`___`

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Context Ingestion
*Load the raw materials before processing.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`, which presents a multichoice menu of discovered context — RAG-suggested sessions, docs, and active alerts from the activate output — so the user can pick which ones to load. Any files in `contextPaths` are auto-loaded; the menu covers everything else that semantic search found relevant.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Context sources presented: `________`
> - Files loaded: `________ files`
> - User confirmed: `yes / no`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "1: Context Ingestion"
  nextPhase: "2: Interrogation"
  prevPhase: "0: Setup"
  custom: "Skip to 3: Planning | Requirements are obvious, jump to planning"

---

## 2. The Interrogation (Pre-Flight Check)
*Before writing a plan, ensure you know the terrain.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to validate assumptions.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### Interrogation Topics (Implementation)
*Standard topics for the command to draw from. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

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

**Action**: Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` with the topics above, which first asks how deep the interrogation should go (Short 3+ / Medium 6+ / Long 9+ / Absolute). Then runs rounds — each round opens with a 2-paragraph context block summarizing what was learned and previewing the next topic, followed by 3-5 targeted questions. After the minimum is met, an exit gate lets the user proceed to planning or request more rounds.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`

### Phase Transition
*Fired by `§CMD_EXECUTE_INTERROGATION_PROTOCOL` exit gate's "Proceed to next phase" option.*

Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "2: Interrogation"
  nextPhase: "3: Planning"
  prevPhase: "1: Context Ingestion"

---

## 3. The Planning Phase
**Unless the user points to an existing plan, you MUST create one.**

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Planning.
> 2. I will `§CMD_POPULATE_LOADED_TEMPLATE` using `IMPLEMENTATION_PLAN.md` template to draft the IMPLEMENTATION_PLAN.md.
> 3. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding to build.

1.  **Create Plan**: Execute `§CMD_POPULATE_LOADED_TEMPLATE` (Schema: `IMPLEMENTATION_PLAN.md`), which takes the template already in context and fills in every section — invariants check, interface design, pitfalls, test plan, and the step-by-step strategy with `Depends`/`Files` fields for parallel execution analysis. The result is written as `IMPLEMENTATION_PLAN.md` in the session directory.
2.  **Present**: Execute `§CMD_REPORT_FILE_CREATION_SILENTLY`, which outputs a clickable link to the plan file — the content stays in the file, not echoed to chat.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
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
  templateFile: "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md"
  planQuestions:
    - "Any concerns about this step's approach or complexity?"
    - "Should the scope change — expand, narrow, or split this step?"
    - "Dependencies or risks I'm missing?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/directives/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 3: Plan ready. How to proceed?"
> - **"Launch builder agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 3.1. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 3 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"builder"`
*   `startAtPhase`: `"Phase 4: Build Loop"`
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

**If "Continue inline"**: Proceed to Phase 4 as normal.
**If "Revise the plan"**: Return to Phase 3 for revision.

---

## 4. The Build Loop (TDD Cycle)
*Iterate through the Plan. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Build Loop.
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

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Plan steps completed: `________`
> - Tests pass: `________`
> - IMPLEMENTATION_LOG.md entries: `________`
> - Unresolved blocks: `________`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "4: Build Loop"
  nextPhase: "5: Synthesis"
  prevPhase: "3: Planning"
  custom: "Run verification first | Run tests/lint before closing"

**On "Other" (free-text)**: The user is describing new requirements or additional work. Route to Phase 2 (Interrogation) to scope it before building — do NOT stay in Phase 4 or jump to synthesis. Use `session.sh phase` with `--user-approved` to go backward.

---

## 5. The Synthesis (Debrief)
*When all tasks are complete.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` (if any discovered checklists exist).
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_IMPLEMENTATION.md` EXACTLY) to summarize the build.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The debrief FILE is the primary deliverable — chat output alone is not sufficient.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `IMPLEMENTATION.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Deviation Analysis**: Compare Plan vs. Log. Where did we struggle?
  *   **Tech Debt**: What did we hack to get it working?
  *   **The Story**: Narrate the build journey.
  *   **Next Steps**: Clear recommendations for the next session.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 4**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Implementation complete. Walk through the changes?"
  debriefFile: "IMPLEMENTATION.md"
  templateFile: "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 5 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - IMPLEMENTATION.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 5**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
