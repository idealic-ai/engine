---
name: implement
description: "Drives feature implementation following structured development protocols. Triggers: \"implement this feature\", \"build this\", \"write the code\", \"TDD implementation\", \"execute the plan\"."
version: 3.0
tier: protocol
---

Drives feature implementation following structured development protocols.

# Implementation Protocol (The Builder's Code)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "IMPLEMENTATION",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "session_dir", "parameters_parsed"]},
    {"label": "1", "name": "Interrogation",
      "steps": ["§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depth_chosen", "rounds_completed"]},
    {"label": "2", "name": "Planning",
      "steps": ["§CMD_GENERATE_PLAN", "§CMD_WALK_THROUGH_RESULTS"],
      "commands": ["§CMD_LINK_FILE"],
      "proof": ["plan_written", "plan_presented", "user_approved"]},
    {"label": "3", "name": "Execution",
      "steps": ["§CMD_SELECT_EXECUTION_PATH"],
      "commands": [],
      "proof": ["path_chosen", "paths_available"]},
    {"label": "3.A", "name": "Build Loop",
      "steps": [],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["plan_steps_completed", "tests_pass", "log_entries", "unresolved_blocks"]},
    {"label": "3.B", "name": "Agent Handoff",
      "steps": ["§CMD_HANDOFF_TO_AGENT"], "commands": [], "proof": []},
    {"label": "3.C", "name": "Parallel Agent Handoff",
      "steps": ["§CMD_PARALLEL_HANDOFF"], "commands": [], "proof": []},
    {"label": "4", "name": "Synthesis",
      "steps": ["§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": []},
    {"label": "4.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": []},
    {"label": "4.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debrief_file", "debrief_tags"]},
    {"label": "4.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": []},
    {"label": "4.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": []}
  ],
  "nextSkills": ["/test", "/document", "/analyze", "/fix", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md", "CHECKLIST.md"],
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

`§CMD_REPORT_INTENT`:
> Implementing ___ feature.
> Mode: ___. Trigger: ___.
> Focus: session activation, mode selection, context loading.

`§CMD_EXECUTE_PHASE_STEPS(0.0.*)`

*   **Scope**: Understand the [Topic] and [Goal].

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Configuration.

**On "Custom"**: Read ALL 3 named mode files first (`modes/tdd.md`, `modes/experimentation.md`, `modes/general.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 interrogation depth (from mode file)
*   Phase 3.A build approach (from mode file)

---

## 1. Interrogation

`§CMD_REPORT_INTENT`:
> Interrogating ___ assumptions before planning implementation.
> Drawing from scope, data flow, testing, and risk topics.

`§CMD_EXECUTE_PHASE_STEPS(1.0.*)`

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

`§CMD_REPORT_INTENT`:
> Planning ___ implementation. ___ steps identified.
> Producing IMPLEMENTATION_PLAN.md with dependencies and file mappings.

`§CMD_EXECUTE_PHASE_STEPS(2.0.*)`

**Unless the user points to an existing plan, you MUST create one.**

*   **Plan**: Fill in every section -- invariants check, interface design, pitfalls, test plan, and the step-by-step strategy with `Depends`/`Files` fields for parallel execution analysis.

**Walk-through** (optional):
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

---

## 3. Execution

`§CMD_REPORT_INTENT`:
> Selecting execution path for implementation.

`§CMD_EXECUTE_PHASE_STEPS(3.0.*)`

*Gateway phase — presents inline/agent/parallel choice, then enters the selected branch.*

---

## 3.A. Build Loop (TDD Cycle)
*Execute the plan step by step in this conversation.*

`§CMD_REPORT_INTENT`:
> Executing ___-step build plan. Target: ___.
> Approach: Red-Green-Refactor per mode configuration.

`§CMD_EXECUTE_PHASE_STEPS(3.A.*)`

**Build Cycle**:
1.  **Write Test (Red)**: Create the test case.
2.  **Code (Green)**: Implement the solution.
3.  **Log**: `§CMD_APPEND_LOG` to `IMPLEMENTATION_LOG.md`.
4.  **Tick**: Mark `[x]` in `IMPLEMENTATION_PLAN.md`.

**On "Other" (free-text) at phase transition**: The user is describing new requirements or additional work. Route to Phase 1 (Interrogation) to scope it before building -- do NOT stay in Phase 3.A or jump to synthesis.

---

## 3.B. Agent Handoff
*Hand off to a single autonomous agent.*

`§CMD_EXECUTE_PHASE_STEPS(3.B.*)`

`§CMD_HANDOFF_TO_AGENT` with:
```json
{
  "agentName": "builder",
  "startAtPhase": "3.A: Build Loop",
  "planOrDirective": "[sessionDir]/IMPLEMENTATION_PLAN.md",
  "logFile": "IMPLEMENTATION_LOG.md",
  "taskSummary": "Execute the implementation plan: [brief description]"
}
```

---

## 3.C. Parallel Agent Handoff
*Hand off to multiple agents working in parallel on independent plan chunks.*

`§CMD_EXECUTE_PHASE_STEPS(3.C.*)`

`§CMD_PARALLEL_HANDOFF` with:
```json
{
  "agentName": "builder",
  "planFile": "[sessionDir]/IMPLEMENTATION_PLAN.md",
  "logFile": "IMPLEMENTATION_LOG.md",
  "taskSummary": "Execute the implementation plan: [brief description]"
}
```

---

## 4. Synthesis
*When all tasks are complete.*

`§CMD_REPORT_INTENT`:
> Synthesizing. ___ plan steps completed, ___ tests passing.
> Producing IMPLEMENTATION.md debrief with deviation analysis.

`§CMD_EXECUTE_PHASE_STEPS(4.0.*)`

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
