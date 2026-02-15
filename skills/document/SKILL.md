---
name: document
description: "Keeps documentation in sync with code changes and project state. Triggers: \"update documentation\", \"patch the docs\", \"sync docs with code changes\", \"update architecture docs\"."
version: 3.0
tier: protocol
---

Keeps documentation in sync with code changes and project state.

# Document Update Protocol (The Surgical Standard)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "DOCUMENT_UPDATE",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INTERROGATE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["mode", "sessionDir", "parametersParsed"]},
    {"label": "1", "name": "Diagnosis & Planning",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_GENERATE_PLAN"],
      "commands": ["§CMD_LINK_FILE"],
      "proof": ["contextSourcesPresented", "documentationDriftAssessed", "planWritten", "planPresented", "userApproved"]},
    {"label": "2", "name": "Execution",
      "steps": ["§CMD_SELECT_EXECUTION_PATH"],
      "commands": [],
      "proof": ["pathChosen", "pathsAvailable"]},
    {"label": "2.A", "name": "Operation",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS"],
      "proof": ["planStepsCompleted", "logEntries", "unresolvedBlocks"]},
    {"label": "2.B", "name": "Agent Handoff",
      "steps": ["§CMD_HANDOFF_TO_AGENT"], "commands": [], "proof": []},
    {"label": "2.C", "name": "Parallel Agent Handoff",
      "steps": ["§CMD_PARALLEL_HANDOFF"], "commands": [], "proof": []},
    {"label": "3", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": []},
    {"label": "3.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": []},
    {"label": "3.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"]},
    {"label": "3.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": []},
    {"label": "3.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": []}
  ],
  "nextSkills": ["/review", "/implement", "/analyze", "/brainstorm", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"],
  "planTemplate": "assets/TEMPLATE_DOCUMENTATION_PLAN.md",
  "logTemplate": "assets/TEMPLATE_DOCUMENTATION_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_DOCUMENTATION.md",
  "requestTemplate": "assets/TEMPLATE_DOCUMENTATION_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_DOCUMENTATION_RESPONSE.md",
  "modes": {
    "surgical": {"label": "Surgical", "description": "Fix specific stale/incorrect docs", "file": "modes/surgical.md"},
    "audit": {"label": "Audit", "description": "Read-only verification pass", "file": "modes/audit.md"},
    "refine": {"label": "Refine", "description": "Improve clarity, examples, structure", "file": "modes/refine.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT`:
> 0: Updating documentation for ___. Trigger: ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(0.0.*)`

*   **Scope**: Understand the [Trigger] (e.g., "We refactored the Audio Graph").
    *   **Goal**: The mission is **Truth Convergence**. Make the map match the territory.
    *   **Value**: Outdated docs are debt. They mislead devs and waste hours. You are the cleaner.
    *   **New Features**: If this is a **New Feature**, you must define its "Home". Does it need a new `concepts/X.md`? or a section in `features/Y.md`? **Do not leave it homeless.**

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Operation Strategy.

**On "Custom"**: Read ALL 3 named mode files first (`modes/surgical.md`, `modes/refine.md`, `modes/audit.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 diagnosis strategy (from mode file)
*   Phase 2 operation approach (from mode file)

### Interrogation Topics (Documentation)
*Brief pre-flight interrogation before context loading. Adapt to the task -- skip irrelevant topics, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Scope & boundaries** -- which docs are in/out, depth of changes, new vs update
- **Audience & tone** -- who reads these docs, technical level, formality
- **Source of truth** -- where does the "correct" information live (code, specs, conversations)
- **Freshness assessment** -- how stale are the current docs, when were they last updated
- **Structure & format** -- should we restructure, add diagrams, change headings
- **Dependencies** -- do changes to one doc require cascading updates to others
- **New feature docs** -- does this need a new file, a new section, or a new concept page
- **Risks & constraints** -- what could go wrong with doc changes (broken links, stale references)

**Repeatable topics** (can be selected any number of times):
- **Followup** -- Clarify or revisit answers from previous rounds
- **Devil's advocate** -- Challenge assumptions about doc changes
- **Deep dive** -- Drill into a specific doc area in detail

---

## 1. Diagnosis & Planning
*Before cutting, understand the anatomy and draft the procedure.*

`§CMD_REPORT_INTENT`:
> 1: Diagnosing documentation drift for ___. ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(1.0.*)`

*   **Survey**: Use targeted reads to identify outdated sections.
*   **Plan**: Be specific. "Rewrite Section 3 of X.md" is better than "Update X.md".

**Walk-through** (optional):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Surgical plan ready. Walk through the operations before cutting?"
  debriefFile: "DOCUMENTATION_PLAN.md"
  templateFile: "assets/TEMPLATE_DOCUMENTATION_PLAN.md"
  planQuestions:
    - "Is this the right scope for this operation?"
    - "Any docs I'm missing that should also be updated?"
    - "Concerns about this change breaking existing references?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

---

## 2. Execution
*Gateway -- select the execution path.*

`§CMD_REPORT_INTENT`:
> 2: Selecting execution path for documentation updates. ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(2.0.*)`

---

## 2.A. Operation
*Execute the plan. Surgical updates only.*

`§CMD_REPORT_INTENT`:
> 2.A: Executing ___-step documentation plan. Target: ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(2.A.*)`

**Operation Cycle**:
1.  **Cut**: Make the targeted edit.
2.  **Log**: `§CMD_APPEND_LOG` to `DOCUMENTATION_LOG.md`.
3.  **Tick**: Mark `[x]` in `DOCUMENTATION_PLAN.md`.

**On "Other" (free-text) at phase transition**: The user is describing new requirements. Route to Phase 0 (Setup) to scope it before operating -- do NOT stay in Phase 2.A or jump to synthesis.

---

## 2.B. Agent Handoff
*Hand off to a single autonomous agent.*

`§CMD_EXECUTE_PHASE_STEPS(2.B.*)`

`§CMD_HANDOFF_TO_AGENT` with:
```json
{
  "agentName": "writer",
  "startAtPhase": "2.A: Operation",
  "planOrDirective": "[sessionDir]/DOCUMENTATION_PLAN.md",
  "logFile": "DOCUMENTATION_LOG.md",
  "taskSummary": "Execute the document update plan: [brief description from taskSummary]"
}
```

---

## 2.C. Parallel Agent Handoff
*Hand off to multiple autonomous agents in parallel.*

`§CMD_EXECUTE_PHASE_STEPS(2.C.*)`

`§CMD_PARALLEL_HANDOFF` with the plan from `DOCUMENTATION_PLAN.md`.

---

## 3. Synthesis
*When the surgery is complete.*

`§CMD_REPORT_INTENT`:
> 3: Synthesizing. ___ documentation updates completed.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(3.0.*)`

**Debrief notes** (for `DOCUMENTATION.md`):
*   **Summary**: What was changed?
*   **Prognosis**: Is the documentation healthy?
*   **Expert Opinion**: Your subjective take on the state of the docs.

**Skill-specific step** (after debrief, before pipeline):
**TOC MANAGEMENT**: Reconcile documentation index.
  *   Collects all documentation files created, modified, or deleted during this session.
  *   Presents multichoice for TOC.md additions, description updates, and stale entry removals.
  *   Auto-applies selected changes to `docs/TOC.md`.
  *   Skips silently if no documentation files were touched.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Documentation complete. Walk through the updates?"
  debriefFile: "DOCUMENTATION.md"
  templateFile: "assets/TEMPLATE_DOCUMENTATION.md"
```
