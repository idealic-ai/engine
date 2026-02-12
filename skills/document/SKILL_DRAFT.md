---
name: document
description: "Keeps documentation in sync with code changes and project state. Triggers: \"update documentation\", \"patch the docs\", \"sync docs with code changes\", \"update architecture docs\"."
version: 3.0
tier: protocol
---

Keeps documentation in sync with code changes and project state.

# Document Update Protocol (The Surgical Standard)

### Session Parameters
```json
{
  "taskType": "DOCUMENT_UPDATE",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Interrogation", "proof": ["depth_chosen", "rounds_completed"]},
    {"major": 2, "minor": 0, "name": "Diagnosis & Planning", "proof": ["context_loaded", "drift_assessed", "plan_written", "user_approved"]},
    {"major": 3, "minor": 0, "name": "Inline Operation", "proof": ["plan_steps_completed", "log_entries"]},
    {"major": 3, "minor": 1, "name": "Agent Handoff"},
    {"major": 3, "minor": 2, "name": "Parallel Agent Handoff"},
    {"major": 4, "minor": 0, "name": "Synthesis"},
    {"major": 4, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 4, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 4, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 4, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/review", "/implement", "/analyze", "/brainstorm", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"],
  "planTemplate": "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_PLAN.md",
  "logTemplate": "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_LOG.md",
  "debriefTemplate": "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION.md",
  "requestTemplate": "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_REQUEST.md",
  "responseTemplate": "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_RESPONSE.md",
  "modes": {
    "surgical": {"label": "Surgical", "description": "Fix specific stale/incorrect docs", "file": "~/.claude/skills/document/modes/surgical.md"},
    "audit": {"label": "Audit", "description": "Read-only verification pass", "file": "~/.claude/skills/document/modes/audit.md"},
    "refine": {"label": "Refine", "description": "Improve clarity, examples, structure", "file": "~/.claude/skills/document/modes/refine.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "~/.claude/skills/document/modes/custom.md"}
  }
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT_TO_USER`:
> Updating ___ docs. Mode: ___. Trigger: ___.

1.  **Scope**: Understand the [Trigger] (e.g., "We refactored the Audio Graph").
    *   **Goal**: **Truth Convergence** — outdated docs are debt.
    *   **New Features**: If this is a new feature, define its "Home". Does it need a new `concepts/X.md`? or a section in `features/Y.md`? Do not leave it homeless.

2.  **Mode Selection**: `§CMD_SELECT_MODE`

---

## 1. Interrogation

`§CMD_REPORT_INTENT_TO_USER`:
> Interrogating ___ assumptions before planning ___ updates.

`§CMD_EXECUTE_INTERROGATION_PROTOCOL`

### Topics (Documentation)

**Standard topics** (typically covered once):
- **Scope & boundaries** — which docs are in/out, depth of changes, new vs update
- **Audience & tone** — who reads these docs, technical level, formality
- **Source of truth** — where does the "correct" information live (code, specs, conversations)
- **Freshness assessment** — how stale are the current docs, when were they last updated
- **Structure & format** — should we restructure, add diagrams, change headings
- **Dependencies** — do changes to one doc require cascading updates to others
- **New feature docs** — does this need a new file, a new section, or a new concept page
- **Risks & constraints** — what could go wrong with doc changes (broken links, stale references)

**Repeatable topics**:
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions about doc changes
- **Deep dive** — Drill into a specific doc area in detail

---

## 2. Diagnosis & Planning

`§CMD_REPORT_INTENT_TO_USER`:
> Diagnosed ___ docs with drift in ___. Planning ___ updates.

1.  **Context Ingestion**: `§CMD_INGEST_CONTEXT_BEFORE_WORK`
2.  **Survey**: Targeted reads to identify outdated sections.
3.  **Plan**: `§CMD_GENERATE_PLAN_FROM_TEMPLATE`
    *   Be specific. "Rewrite Section 3 of X.md" is better than "Update X.md".
4.  **Walk-through** (optional):
    ```
    §CMD_WALK_THROUGH_RESULTS Configuration:
      mode: "plan"
      gateQuestion: "Surgical plan ready. Walk through the operations before cutting?"
      debriefFile: "DOCUMENTATION_PLAN.md"
      templateFile: "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_PLAN.md"
      planQuestions:
        - "Is this the right scope for this operation?"
        - "Any docs I'm missing that should also be updated?"
        - "Concerns about this change breaking existing references?"
    ```
5.  **Execution Path**: `§CMD_SELECT_EXECUTION_PATH` → routes to 3.A, 3.B, or 3.C.

---

## 3.A. Inline Operation
*Execute the plan step by step in this conversation.*

`§CMD_REPORT_INTENT_TO_USER`:
> Executing ___-step surgical plan. Target: ___.

Follow the plan. Mark steps complete as you go.

---

## 3.B. Agent Handoff
*Hand off to a single autonomous agent.*

Handoff config:
*   `agentName`: `"writer"`
*   `startAtPhase`: `"3.A: Inline Operation"`
*   `planOrDirective`: `[sessionDir]/DOCUMENTATION_PLAN.md`
*   `logFile`: `DOCUMENTATION_LOG.md`
*   `taskSummary`: `"Execute the document update plan: [brief description]"`

---

## 3.C. Parallel Agent Handoff
*Hand off to multiple agents working in parallel on independent plan chunks.*

`§CMD_PARALLEL_HANDOFF` with:
*   `agentName`: `"writer"`
*   `planFile`: `[sessionDir]/DOCUMENTATION_PLAN.md`
*   `logFile`: `DOCUMENTATION_LOG.md`
*   `taskSummary`: `"Execute the document update plan: [brief description]"`

---

## 4. Synthesis
*When the surgery is complete.*

`§CMD_REPORT_INTENT_TO_USER`:
> Synthesizing. ___ files touched, ___ sections updated.

**Debrief notes** (for `DOCUMENTATION.md`):
*   **Summary**: What was changed?
*   **Prognosis**: Is the documentation healthy?
*   **Expert Opinion**: Your subjective take on the state of the docs.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Documentation complete. Walk through the updates?"
  debriefFile: "DOCUMENTATION.md"
  templateFile: "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION.md"
```
