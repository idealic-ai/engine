---
name: implement
description: "Drives feature implementation following structured development protocols. Triggers: \"implement this feature\", \"build this\", \"write the code\", \"TDD implementation\", \"execute the plan\"."
version: 3.0
tier: protocol
---

Drives feature implementation following structured development protocols.

# Implementation Protocol (The Builder's Code)

### Session Parameters
```json
{
  "taskType": "IMPLEMENTATION",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK", "mode", "session_dir", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Interrogation", "proof": ["§CMD_INTERROGATE", "§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION", "depth_chosen", "rounds_completed"]},
    {"major": 2, "minor": 0, "name": "Planning", "proof": ["§CMD_GENERATE_PLAN", "§CMD_WALK_THROUGH_RESULTS", "§CMD_GATE_PHASE", "plan_written", "plan_presented", "user_approved"]},
    {"major": 3, "minor": 0, "name": "Build Loop", "proof": ["plan_steps_completed", "tests_pass", "log_entries", "unresolved_blocks"]},
    {"major": 3, "minor": 1, "name": "Agent Handoff", "proof": ["§CMD_HANDOFF_TO_AGENT"]},
    {"major": 3, "minor": 2, "name": "Parallel Agent Handoff", "proof": ["§CMD_PARALLEL_HANDOFF"]},
    {"major": 4, "minor": 0, "name": "Synthesis", "proof": ["§CMD_RUN_SYNTHESIS_PIPELINE"]},
    {"major": 4, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS", "§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS"]},
    {"major": 4, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 4, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 4, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION"]}
  ],
  "nextSkills": ["/test", "/document", "/analyze", "/fix", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"],
  "planTemplate": "assets/TEMPLATE_IMPLEMENTATION_PLAN.md",
  "logTemplate": "assets/TEMPLATE_IMPLEMENTATION_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_IMPLEMENTATION.md",
  "requestTemplate": "assets/TEMPLATE_IMPLEMENTATION_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_IMPLEMENTATION_RESPONSE.md",
  "modes": {
    "general": {"label": "General", "description": "Pragmatic balance", "file": "modes/general.md"},
    "tdd": {"label": "TDD", "description": "Test-driven rigor", "file": "modes/tdd.md"},
    "experimentation": {"label": "Experimentation", "description": "Fast prototyping", "file": "modes/experimentation.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT_TO_USER`:
> Implementing ___ feature.
> Mode: ___. Trigger: ___.
> Focus: session activation, mode selection, context loading.

1.  **Scope**: Understand the [Topic] and [Goal].
2.  **Mode Selection**: `§CMD_SELECT_MODE`

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Configuration.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/tdd.md`, `modes/experimentation.md`, `modes/general.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 role (from mode file)
    *   Phase 1 interrogation depth (from mode file)
    *   Phase 3.A build approach (from mode file)

3.  **Context Ingestion**: `§CMD_INGEST_CONTEXT_BEFORE_WORK`

---

## 1. Interrogation

`§CMD_REPORT_INTENT_TO_USER`:
> Interrogating ___ assumptions before planning implementation.
> Drawing from scope, data flow, testing, and risk topics.

`§CMD_INTERROGATE`

### Topics (Implementation)
*Standard topics for the command to draw from. Adapt to the task -- skip irrelevant ones, invent new ones as needed.*

- **Scope & constraints** -- boundaries, what's in/out, existing patterns to follow
- **Data flow** -- who owns the data, state transitions, schemas involved
- **Edge cases** -- error handling, empty states, concurrency, race conditions
- **Testing strategy** -- unit vs integration, mocking approach, fixtures, coverage goals
- **Risks & unknowns** -- reversibility, assumptions being made, what could go wrong
- **Performance & security** -- latency concerns, auth, input validation, resource limits
- **Dependencies** -- external services, package changes, deployment, migration
- **API surface & naming** -- public interfaces, backwards compatibility, naming conventions
- **Failure modes** -- rollback strategy, monitoring, alerting, degraded operation
- **Integration** -- how this fits existing systems, circular dependencies, shared state

---

## 2. Planning

`§CMD_REPORT_INTENT_TO_USER`:
> Planning ___ implementation. ___ steps identified.
> Producing IMPLEMENTATION_PLAN.md with dependencies and file mappings.

**Unless the user points to an existing plan, you MUST create one.**

1.  **Plan**: `§CMD_GENERATE_PLAN`
    *   Fill in every section -- invariants check, interface design, pitfalls, test plan, and the step-by-step strategy with `Depends`/`Files` fields for parallel execution analysis.
2.  **Present**: `§CMD_LINK_FILE`
3.  **Walk-through** (optional):
    ```
    §CMD_WALK_THROUGH_RESULTS Configuration:
      mode: "plan"
      gateQuestion: "Plan is ready. Walk through the steps before building?"
      debriefFile: "IMPLEMENTATION_PLAN.md"
      planQuestions:
        - "Any concerns about this step's approach or complexity?"
        - "Should the scope change -- expand, narrow, or split this step?"
        - "Dependencies or risks I'm missing?"
    ```
    If any items are flagged for revision, return to the plan for edits before proceeding.
4.  **Execution Path**: `§CMD_SELECT_EXECUTION_PATH` -> routes to 3.A, 3.B, or 3.C.

---

## 3.A. Build Loop (TDD Cycle)
*Execute the plan step by step in this conversation.*

`§CMD_REPORT_INTENT_TO_USER`:
> Executing ___-step build plan. Target: ___.
> Approach: Red-Green-Refactor per mode configuration.

**Build Cycle**:
1.  **Write Test (Red)**: Create the test case.
2.  **Code (Green)**: Implement the solution.
3.  **Log**: `§CMD_APPEND_LOG` to `IMPLEMENTATION_LOG.md`.
4.  **Tick**: Mark `[x]` in `IMPLEMENTATION_PLAN.md`.

**On "Other" (free-text) at phase transition**: The user is describing new requirements or additional work. Route to Phase 1 (Interrogation) to scope it before building -- do NOT stay in Phase 3.A or jump to synthesis.

---

## 3.B. Agent Handoff
*Hand off to a single autonomous agent.*

`§CMD_HANDOFF_TO_AGENT` with:
*   `agentName`: `"builder"`
*   `startAtPhase`: `"3.A: Build Loop"`
*   `planOrDirective`: `[sessionDir]/IMPLEMENTATION_PLAN.md`
*   `logFile`: `IMPLEMENTATION_LOG.md`
*   `taskSummary`: `"Execute the implementation plan: [brief description]"`

---

## 3.C. Parallel Agent Handoff
*Hand off to multiple agents working in parallel on independent plan chunks.*

`§CMD_PARALLEL_HANDOFF` with:
*   `agentName`: `"builder"`
*   `planFile`: `[sessionDir]/IMPLEMENTATION_PLAN.md`
*   `logFile`: `IMPLEMENTATION_LOG.md`
*   `taskSummary`: `"Execute the implementation plan: [brief description]"`

---

## 4. Synthesis
*When all tasks are complete.*

`§CMD_REPORT_INTENT_TO_USER`:
> Synthesizing. ___ plan steps completed, ___ tests passing.
> Producing IMPLEMENTATION.md debrief with deviation analysis.

**Debrief notes** (for `IMPLEMENTATION.md`):
*   **Deviation Analysis**: Compare Plan vs. Log. Where did we struggle?
*   **Tech Debt**: What did we hack to get it working?
*   **The Story**: Narrate the build journey.
*   **Next Steps**: Clear recommendations for the next session.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Implementation complete. Walk through the changes?"
  debriefFile: "IMPLEMENTATION.md"
```
