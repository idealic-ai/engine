---
name: test
description: "Designs and writes test cases for code correctness and regression prevention. Supports goal-based modes: Coverage (gap-filling), Hardening (edge cases & stress), Integration (boundaries & contracts), Custom (user-defined lens). Triggers: \"write tests\", \"design test cases\", \"verify edge cases\", \"catch regressions\", \"test this feature\", \"harden this\", \"integration tests\"."
version: 2.0
tier: protocol
---

Designs and writes test cases for code correctness and regression prevention.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Testing Protocol (The QA Standard)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 3 (Strategy) and TESTING_PLAN.md. The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Phases (for §CMD_PARSE_PARAMETERS)
*Include this array in the `phases` field when calling `session.sh activate`:*
```json
[
  {"major": 1, "minor": 0, "name": "Setup"},
  {"major": 2, "minor": 0, "name": "Context Ingestion"},
  {"major": 3, "minor": 0, "name": "Strategy"},
  {"major": 3, "minor": 1, "name": "Agent Handoff"},
  {"major": 4, "minor": 0, "name": "Testing Loop"},
  {"major": 5, "minor": 0, "name": "Synthesis"}
]
```
*Phase enforcement (¶INV_PHASE_ENFORCEMENT): transitions must be sequential. Use `--user-approved` for skip/backward.*

---

## Mode Presets

Testing modes configure the agent's lens — role, interrogation topics, and walk-through config. The mode is selected in Phase 1 Step 5.1. Mode definitions live in `modes/*.md`.

| Mode | Focus | When to Use |
|------|-------|-------------|
| **Coverage** (Default) | Systematic gap-filling prioritized by risk | Expand test coverage, identify and fill gaps |
| **Hardening** | Adversarial edge cases and failure modes | Stress-test with boundary conditions and worst cases |
| **Integration** | Component boundaries, contracts, and E2E flows | Verify components work correctly together |
| **Custom** | User-defined lens | None of the above fit the situation |

---

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is TESTING (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Testing Mode** (Coverage / Hardening / Integration / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/test/assets/TEMPLATE_TESTING_LOG.md` (Template for continuous testing logging)
    *   `~/.claude/skills/test/assets/TEMPLATE_TESTING.md` (Template for final session debrief/report)
    *   `~/.claude/skills/test/assets/TEMPLATE_TESTING_PLAN.md` (Template for drafting the test strategy)
    *   `.claude/directives/TESTING.md` (Testing standards and quality requirements — project-level, load if exists)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Goal].

5.1. **Testing Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What testing lens should I use?"
    > - **"Coverage" (Recommended)** — Expand test coverage, identify and fill gaps
    > - **"Hardening"** — Stress-test with edge cases, boundary conditions, failure modes
    > - **"Integration"** — Verify component boundaries, contracts, and E2E flows
    > - **"Custom"** — Define your own testing focus and approach

    **On selection**: Read the corresponding `modes/{mode}.md` file (e.g., `modes/coverage.md`, `modes/hardening.md`, `modes/integration.md`).
    **On "Custom"**: Read ALL 3 named mode files first (`modes/coverage.md`, `modes/hardening.md`, `modes/integration.md`) for context, then read `modes/custom.md`. The user types their framing. Parse it into role/goal/mindset. Use Coverage's topic lists as defaults.

    **Record**: Store the selected mode. It configures:
    *   Phase 1 Step 6 role (from mode file)
    *   Phase 3 interrogation topics (from mode file)
    *   Phase 5 walk-through config (from mode file)

6.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file (`modes/{mode}.md`).

7.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - COMMANDS.md loaded: `________`
> - INVARIANTS.md loaded (shared + project): `________`
> - TAGS.md loaded: `________`
> - All 3 templates loaded (LOG, DEBRIEF, PLAN): `________`
> - Parameters parsed and output: `________`
> - Session directory: `________`
> - Mode: `________` (coverage / hardening / integration / custom)
> - Mode file loaded: `________` (path to the loaded mode file)
> - Role assumed: `________` (quote the role name from the mode file)

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
> - RAG searches executed: `________`
> - Context paths presented: `________`
> - User confirmed files: `________`
> - Files loaded: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Context loaded. How to proceed?"
> - **"Proceed to Phase 3: Strategy"** — Plan test scenarios and coverage strategy
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Testing Loop"** — Requirements are obvious, jump straight to writing tests

---

## 3. The Strategy Phase (Planning + Interrogation)
*Before writing code, use the **Anti-Fragile Checklist** to generate high-value scenarios.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Strategy.
> 2. I will use the Question Bank to brainstorm test scenarios.
> 3. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to validate testing assumptions.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 5. I will `§CMD_POPULATE_LOADED_TEMPLATE` using `TESTING_PLAN.md` template to draft the plan.
> 6. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding to test execution.

### The Question Bank (20 Questions for Coverage)

**Data Integrity**
1.  "What happens if we pass `null`, `undefined`, or `NaN` to strict methods?"
2.  "Can we corrupt the state by calling public methods in the wrong order?"
3.  "Does this data structure maintain its invariants after 1000 mutations?"
4.  "What is the 'Zero State' (empty lists) behavior?"
5.  "What is the 'Max State' (arrays with 10k items) behavior?"

**Async & Concurrency**
6.  "What if the Promise rejects immediately?"
7.  "What if the Promise hangs forever?"
8.  "What if `stop()` is called while `start()` is pending?"
9.  "Are there race conditions between UI events and background events?"
10. "Is this function re-entrant?"

**Refactoring & Isolation**
11. "Can we extract the logic to test it without mocking complex dependencies?"
12. "Are we testing implementation details (private state) or behavior (public API)?"
13. "Is this test brittle? Will it break if we rename a variable?"
14. "Can we use a Factory to simplify test setup?"
15. "Are we over-mocking? Can we use real data objects?"

**Domain Specific**
16. "What happens during a gap or missing data in the pipeline?"
17. "Does backwards traversal / undo handle state reset correctly?"
18. "Do we handle format or version mismatches?"
19. "What if the input payload is shorter/smaller than expected?"
20. "Does the system recover gracefully from transient failures?"

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should the testing strategy interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Well-understood code, small scope, clear test targets |
| **Medium** | 6+ | Moderate complexity, some unknowns, multi-module testing |
| **Long** | 9+ | Complex system testing, many edge cases, architectural impact |
| **Absolute** | Until ALL questions resolved | Critical system, zero tolerance for gaps, comprehensive coverage required |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Interrogation Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Use the **Interrogation Topics from the loaded mode file** (`modes/{mode}.md`) as the primary source for each round. The standard/repeatable topics below are available for all modes as supplementary material. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far. Use the Question Bank above as inspiration for specific questions within each topic.

### Interrogation Topics (Testing)
*The mode file topics (from `modes/{mode}.md`) are your primary source. These standard topics are available for all modes as supplementary material. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Testing strategy** — unit vs integration vs e2e, test runner, framework conventions
- **Coverage goals** — what percentage, which modules, critical paths vs nice-to-have
- **Edge cases & boundaries** — null/empty states, max values, type mismatches, error paths
- **Mocking approach** — what to mock vs use real, mock libraries, fixture patterns
- **Data integrity** — state corruption, invariant violations, concurrent mutations
- **Async & concurrency** — promises, race conditions, timeouts, re-entrancy
- **Regression prevention** — known bugs to cover, flaky test history, CI stability
- **Performance testing** — benchmarks, load testing, memory leaks, timeout sensitivity
- **Integration boundaries** — external service contracts, API shape validation, DB queries
- **Test maintenance** — naming conventions, shared fixtures, test organization, cleanup

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
> - **"Proceed to create TESTING_PLAN.md"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### Plan Creation

After interrogation completes:

1.  **Draft**: Use the Question Bank + interrogation answers to **brainstorm multiple perspectives** (Data, Async, Domain), then execute `§CMD_POPULATE_LOADED_TEMPLATE` (Schema: `TESTING_PLAN.md`).
2.  **Expand**: Immediately propose **5 additional testing avenues** inspired by these different perspectives.
    *   **Format**: `[Scenario] (Complexity: Low/High, Value: Low/High) - [Reasoning]`
3.  **Refine**: Ask the user which to include, then update `TESTING_PLAN.md`.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Interrogation depth chosen: `________`
> - Minimum rounds completed: `________`
> - Each round logged to DETAILS.md: `________`
> - User selected proceed in exit gate: `________`
> - TESTING_PLAN.md written: `________`
> - User approved plan: `________`

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/directives/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 3: Strategy complete, plan approved. How to proceed?"
> - **"Launch builder agent"** — Hand off to autonomous agent for test execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 3.1. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 3 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"builder"`
*   `startAtPhase`: `"Phase 4: Testing Loop"`
*   `planOrDirective`: `[sessionDir]/TESTING_PLAN.md`
*   `logFile`: `TESTING_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/test/assets/TEMPLATE_TESTING.md`
*   `logTemplate`: `~/.claude/skills/test/assets/TEMPLATE_TESTING_LOG.md`
*   `taskSummary`: `"Execute the testing plan: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"builder"`
*   `planFile`: `[sessionDir]/TESTING_PLAN.md`
*   `logFile`: `TESTING_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/test/assets/TEMPLATE_TESTING.md`
*   `logTemplate`: `~/.claude/skills/test/assets/TEMPLATE_TESTING_LOG.md`
*   `taskSummary`: `"Execute the testing plan: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 4 as normal.
**If "Revise the plan"**: Return to Phase 3 for revision.

---

## 4. The Testing Loop (Execution)
*Iterate through the Plan. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Testing Loop.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage the test execution cycle.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_TESTING_LOG.md` EXACTLY) to `§CMD_THINK_IN_LOG` continuously.
> 4. I will not write the debrief until the step is done (`§CMD_REFUSE_OFF_COURSE` applies).
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

*   **Starting Subtask?** -> Log `🎭 New Scenario` (Context, Goal).
*   **Investigating?** -> Log `🐞 Debugging` (Symptom, Hypothesis, Action).
*   **Success?** -> Log `✅ Success` (Test, Status, Verification).
*   **Stuck?** -> Log `🚧 Stuck` (Barrier, Effort, Plan).
*   **Found Edge Case?** -> Log `🧪 New Edge Case` (Discovery, Impact).
*   **Had Idea?** -> Log `💡 Idea for Test` (Trigger, Idea, Value).
*   **Found Friction?** -> Log `🐢 Reported Inconvenient Testing` (Pain Point, Suggestion).
*   **Found Legacy?** -> Log `🏚️ Found Outdated Tests` (File, Issue, Action).
*   **Found Duplicate?** -> Log `👯 Duplicate Tests` (Target, Observation, Action).

**Constraint**: **Stream-of-Consciousness Logging**. Use `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` constantly. Do not wait for a task to be "finished" to log. Log as you think, especially when implementation gets complex.
**Constraint**: **TIMESTAMPS**. Every log entry MUST start with `[YYYY-MM-DD HH:MM:SS]` in the header.
**Constraint**: **BLIND WRITE**. Do not re-read the file. See `§CMD_AVOID_WASTING_TOKENS`.
**Guidance**: The Log is your *Brain*. If you didn't write it down, it didn't happen.

**Rule**: If you spend more than 2 tool calls on a single subtask without logging, you are failing the protocol. Log early, log often.

**Build Cycle**:
1.  **Write Test**: Create the test case (assert first).
2.  **Run**: Verify it fails as expected (red) or passes (green).
3.  **Log**: Update `TESTING_LOG.md` with your status.
4.  **Tick**: Mark `[x]` in `TESTING_PLAN.md`.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - All plan steps marked [x] (or deferred with reasoning): `________`
> - Tests pass: `________`
> - TESTING_LOG.md has entries for each step: `________`
> - No unresolved stuck entries: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 4: Testing loop complete. How to proceed?"
> - **"Proceed to Phase 5: Synthesis"** — Generate debrief and close session
> - **"Stay in Phase 4"** — More tests needed, continue testing
> - **"Run full test suite first"** — Run all tests before closing to verify no regressions

---

## 5. The Synthesis (Debrief)
*When the session is done.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` to process any discovered CHECKLIST.md files.
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_TESTING.md` EXACTLY) to summarize findings.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The debrief FILE is the primary deliverable — chat output alone is not sufficient.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `TESTING.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Summary**: Pass/Fail rates.
  *   **Regressions**: What broke?
  *   **Coverage**: What new areas are covered?

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 4**: Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** from the loaded mode file (`modes/{mode}.md`).

### §CMD_VERIFY_PHASE_EXIT — Phase 5 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - TESTING.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`
> - Walk-through completed: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 6**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Tests complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/document` (Recommended) | Tests pass — document the changes |
| 2 | `/implement` | Tests revealed missing features — build them |
| 3 | `/debug` | Tests found bugs — investigate |
| 4 | `/analyze` | Test results need deeper analysis |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---

**Testing Tip:**
To verify log output, use `logger.getHistory()`. This returns the structured log entries (including placeholders) which allows for robust assertion of error conditions without relying on fragile string matching.
