---
name: test
description: "Designs and writes test cases for code correctness and regression prevention. Supports goal-based modes: Coverage (gap-filling), Hardening (edge cases & stress), Integration (boundaries & contracts), Custom (user-defined lens). Triggers: \"write tests\", \"design test cases\", \"verify edge cases\", \"catch regressions\", \"test this feature\", \"harden this\", \"integration tests\"."
version: 3.0
tier: protocol
---

Designs and writes test cases for code correctness and regression prevention.

# Testing Protocol (The QA Standard)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "TESTING",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": ["§CMD_FIND_TAGGED_FILES"],
      "proof": ["mode", "session_dir", "parameters_parsed"]},
    {"label": "1.A", "name": "Strategy",
      "steps": ["§CMD_INTERROGATE", "§CMD_GENERATE_PLAN", "§CMD_SELECT_EXECUTION_PATH"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION", "§CMD_LINK_FILE"],
      "proof": ["depth_chosen", "rounds_completed", "plan_written", "user_approved"]},
    {"label": "1.B", "name": "Agent Handoff",
      "steps": ["§CMD_HANDOFF_TO_AGENT"], "commands": [], "proof": []},
    {"label": "2", "name": "Testing Loop",
      "steps": [],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["plan_steps_completed", "tests_pass", "log_entries", "unresolved_blocks"]},
    {"label": "3", "name": "Synthesis",
      "steps": ["§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": []},
    {"label": "3.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": []},
    {"label": "3.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debrief_file", "debrief_tags"]},
    {"label": "3.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": []},
    {"label": "3.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION"], "commands": [], "proof": []}
  ],
  "nextSkills": ["/document", "/implement", "/fix", "/analyze", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md", "CHECKLIST.md"],
  "planTemplate": "assets/TEMPLATE_TESTING_PLAN.md",
  "logTemplate": "assets/TEMPLATE_TESTING_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_TESTING.md",
  "modes": {
    "coverage": {"label": "Coverage", "description": "Systematic gap-filling prioritized by risk", "file": "modes/coverage.md"},
    "hardening": {"label": "Hardening", "description": "Adversarial edge cases and failure modes", "file": "modes/hardening.md"},
    "integration": {"label": "Integration", "description": "Component boundaries, contracts, and E2E flows", "file": "modes/integration.md"},
    "custom": {"label": "Custom", "description": "User-defined lens", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT_TO_USER`:
> Testing ___ with ___ mode.
> Trigger: ___. Focus: session activation, mode selection, context loading.
> Loading context via `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

`§CMD_EXECUTE_PHASE_STEPS(0.0.*)`

*   **Scope**: Understand the [Topic] and [Goal].

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file (e.g., `modes/coverage.md`, `modes/hardening.md`, `modes/integration.md`).
**On "Custom"**: Read ALL 3 named mode files first (`modes/coverage.md`, `modes/hardening.md`, `modes/integration.md`) for context, then read `modes/custom.md`. The user types their framing. Parse it into role/goal/mindset. Use Coverage's topic lists as defaults.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 interrogation topics (from mode file)
*   Phase 3 walk-through config (from mode file)

---

## 1. Strategy (Planning + Interrogation)
*Before writing code, use the Anti-Fragile Checklist to generate high-value scenarios.*

`§CMD_REPORT_INTENT_TO_USER`:
> Interrogating ___ testing assumptions, then building the plan.
> Drawing from mode-specific topics and the Question Bank.
> Minimum rounds: ___ (based on depth selection).

`§CMD_EXECUTE_PHASE_STEPS(1.0.*)`

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should the testing strategy interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Well-understood code, small scope, clear test targets |
| **Medium** | 6+ | Moderate complexity, some unknowns, multi-module testing |
| **Long** | 9+ | Complex system testing, many edge cases, architectural impact |
| **Absolute** | Until ALL questions resolved | Critical system, zero tolerance for gaps, comprehensive coverage required |

Record the user's choice. This sets the **minimum** -- the agent can always ask more, and the user can always say "proceed" after the minimum is met.

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

### Interrogation Protocol (Rounds)

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Use the **Interrogation Topics from the loaded mode file** (`modes/{mode}.md`) as the primary source for each round. The standard/repeatable topics below are available for all modes as supplementary material. Do NOT follow a fixed sequence -- choose the most relevant uncovered topic based on what you've learned so far. Use the Question Bank above as inspiration for specific questions within each topic.

### Interrogation Topics (Testing)
*The mode file topics (from `modes/{mode}.md`) are your primary source. These standard topics are available for all modes as supplementary material. Adapt to the task -- skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Testing strategy** -- unit vs integration vs e2e, test runner, framework conventions
- **Coverage goals** -- what percentage, which modules, critical paths vs nice-to-have
- **Edge cases & boundaries** -- null/empty states, max values, type mismatches, error paths
- **Mocking approach** -- what to mock vs use real, mock libraries, fixture patterns
- **Data integrity** -- state corruption, invariant violations, concurrent mutations
- **Async & concurrency** -- promises, race conditions, timeouts, re-entrancy
- **Regression prevention** -- known bugs to cover, flaky test history, CI stability
- **Performance testing** -- benchmarks, load testing, memory leaks, timeout sensitivity
- **Integration boundaries** -- external service contracts, API shape validation, DB queries
- **Test maintenance** -- naming conventions, shared fixtures, test organization, cleanup

**Repeatable topics** (can be selected any number of times):
- **Followup** -- Clarify or revisit answers from previous rounds
- **Devil's advocate** -- Challenge assumptions and decisions made so far
- **What-if scenarios** -- Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** -- Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_INTERACTION` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to create TESTING_PLAN.md"** -- *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** -- Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** -- 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** -- 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** -- 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### Plan Creation

After interrogation completes:

1.  **Draft**: Use the Question Bank + interrogation answers to **brainstorm multiple perspectives** (Data, Async, Domain), then execute `§CMD_WRITE_FROM_TEMPLATE` (Schema: `TESTING_PLAN.md`).
2.  **Expand**: Immediately propose **5 additional testing avenues** inspired by these different perspectives.
    *   **Format**: `[Scenario] (Complexity: Low/High, Value: Low/High) - [Reasoning]`
3.  **Refine**: Ask the user which to include, then update `TESTING_PLAN.md`.

**Walk-through** (optional):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Testing plan is ready. Walk through the scenarios before executing?"
  debriefFile: "TESTING_PLAN.md"
  planQuestions:
    - "Any concerns about this test scenario's approach or complexity?"
    - "Should the scope change -- expand, narrow, or split this scenario?"
    - "Dependencies or risks I'm missing?"
```

---

## 1.B. Agent Handoff
*Hand off to a single autonomous agent.*

`§CMD_EXECUTE_PHASE_STEPS(1.1.*)`

`§CMD_HANDOFF_TO_AGENT` with:
*   `agentName`: `"builder"`
*   `startAtPhase`: `"2: Testing Loop"`
*   `planOrDirective`: `[sessionDir]/TESTING_PLAN.md`
*   `logFile`: `TESTING_LOG.md`
*   `taskSummary`: `"Execute the testing plan: [brief description from taskSummary]"`

---

## 2. Testing Loop (Execution)
*Iterate through the Plan.*

`§CMD_REPORT_INTENT_TO_USER`:
> Executing ___-step testing plan. Target: ___.
> Approach: Write test, run, log, tick.

`§CMD_EXECUTE_PHASE_STEPS(2.0.*)`

**Build Cycle**:
1.  **Write Test**: Create the test case (assert first).
2.  **Run**: Verify it fails as expected (red) or passes (green).
3.  **Log**: Update `TESTING_LOG.md` with your status.
4.  **Tick**: Mark `[x]` in `TESTING_PLAN.md`.

---

## 3. Synthesis
*When all tasks are complete.*

`§CMD_REPORT_INTENT_TO_USER`:
> Synthesizing. ___ test scenarios completed, ___ tests passing.
> Producing TESTING.md debrief with coverage analysis.

`§CMD_EXECUTE_PHASE_STEPS(3.0.*)`

**Debrief notes** (for `TESTING.md`):
*   **Summary**: Pass/Fail rates.
*   **Regressions**: What broke?
*   **Coverage**: What new areas are covered?

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  (uses Walk-Through Config from the loaded mode file: modes/{mode}.md)
```

---

**Testing Tip:**
To verify log output, use `logger.getHistory()`. This returns the structured log entries (including placeholders) which allows for robust assertion of error conditions without relying on fragile string matching.
