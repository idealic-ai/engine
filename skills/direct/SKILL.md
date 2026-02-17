---
name: direct
description: "High-level project vision designer — splits work into sequential or parallel chapters, defines decision principles, produces structured plans consumable by /coordinate. Triggers: \"create a direct\", \"design a project vision\", \"plan the project\", \"split this into chapters\", \"evolve the vision\"."
version: 1.0
tier: protocol
---

High-level project vision designer — produces structured, diffable vision documents with tagged chapters for `/coordinate` execution.

# Direct Protocol (The Architect's Blueprint)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "DIRECT",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed"], "gate": false},
    {"label": "1", "name": "Interrogation",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depthChosen", "roundsCompleted"]},
    {"label": "2", "name": "Planning",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_GENERATE_PLAN"],
      "commands": ["§CMD_LINK_FILE", "§CMD_APPEND_LOG"],
      "proof": ["planWritten", "planPresented"]},
    {"label": "3", "name": "Dependency Analysis",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["graphProduced", "parallelGroupsIdentified"]},
    {"label": "4", "name": "Execution",
      "steps": ["§CMD_SELECT_EXECUTION_PATH"],
      "commands": [],
      "proof": ["pathChosen", "pathsAvailable"], "gate": false},
    {"label": "4.A", "name": "Vision Writing",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_LINK_FILE"],
      "proof": ["visionWritten", "chaptersTagged"]},
    {"label": "4.B", "name": "Agent Handoff",
      "steps": ["§CMD_HANDOFF_TO_AGENT"], "commands": [], "proof": []},
    {"label": "5", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "5.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "5.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "5.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "5.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/loop", "/implement", "/analyze", "/brainstorm"],
  "directives": [],
  "planTemplate": "assets/TEMPLATE_DIRECT_PLAN.md",
  "logTemplate": "assets/TEMPLATE_DIRECT_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_DIRECT.md",
  "requestTemplate": "assets/TEMPLATE_DIRECT_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_DIRECT_RESPONSE.md",
  "modes": {
    "greenfield": {"label": "Greenfield", "description": "New project vision from scratch", "file": "modes/greenfield.md"},
    "evolution": {"label": "Evolution", "description": "Extend or modify an existing vision", "file": "modes/evolution.md"},
    "split": {"label": "Split", "description": "Decompose a large chapter into sub-chapters", "file": "modes/split.md"},
    "custom": {"label": "Custom", "description": "User-defined blend", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Designing project vision for ___. Output: `docs/[name]_DIRECT.md`.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the project goal and select the operating mode.

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and mode-specific behavior.

**On "Custom"**: Read ALL 3 named mode files first (`modes/greenfield.md`, `modes/evolution.md`, `modes/split.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 interrogation topics (from mode file)
*   Phase 4 writing behavior (from mode file)

**Mode-Specific Setup**:
*   **Greenfield**: No existing vision to load. Proceed to interrogation.
*   **Evolution**: Load the existing vision document (from `contextPaths` or user-specified path). Display a summary: chapter count, completion status of each (`#done-coordinate`, `#claimed-coordinate`, `#needs-coordinate`, untagged). Store the loaded vision as the "v1 baseline" for later diffing.
*   **Split**: Load the existing vision document AND identify the target chapter slug. Ask the user which chapter to decompose if not specified in the prompt.

---

## 1. Interrogation

§CMD_REPORT_INTENT:
> 1: Interrogating ___ project vision assumptions. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### Topics (Direct Design)
*Standard topics for the command to draw from. Adapt to the task -- skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Project goal** -- what the project achieves, why it exists, success criteria
- **Constraints & non-negotiables** -- hard requirements, timeline, budget, compliance
- **Scope boundaries** -- what's in, what's out, where the project ends
- **Chapter decomposition** -- natural work boundaries, what can be parallelized
- **Decision principles** -- soft guidance for coordinator judgment calls
- **Context sources** -- which /analyze, /brainstorm, /research sessions feed this vision
- **Dependency mapping** -- cross-chapter dependencies, shared resources, ordering constraints
- **Risk assessment** -- what could go wrong, contingency plans, reversibility

**Repeatable topics** (can be selected any number of times):
- **Followup** -- Clarify or revisit answers from previous rounds
- **Devil's advocate** -- Challenge assumptions and decisions made so far
- **What-if scenarios** -- Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** -- Drill into a specific topic from a previous round in much more detail

**Mode-specific additional topics**:
- **Evolution**: Current vision analysis, what changed since v1, migration impact
- **Split**: Target chapter complexity analysis, natural sub-boundaries, sub-chapter dependency mapping

---

## 2. Planning

§CMD_REPORT_INTENT:
> 2: Planning ___ vision structure. ___ chapters identified.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Unless the user points to an existing plan, you MUST create one.**

*   **Plan**: Fill in every section -- chapter outline with semantic slugs, preliminary dependency sketch, decision principles draft, success criteria.

**The plan is a structured outline, NOT the final vision document.** It captures:
1.  **Chapter List**: Each chapter with its semantic slug (`@app/auth-system`), one-line description, and preliminary scope.
2.  **Preliminary Dependencies**: Which chapters depend on which (to be validated in Phase 3).
3.  **Decision Principles Draft**: Natural language guidance extracted from interrogation.
4.  **Success Criteria Draft**: Measurable outcomes for the overall project.

**Walk-through** (optional):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Chapter outline ready. Walk through before dependency analysis?"
  debriefFile: "DIRECT_PLAN.md"
  planQuestions:
    - "Is this chapter scoped correctly — too broad, too narrow?"
    - "Any missing chapters or unnecessary ones?"
    - "Dependencies I'm missing between these chapters?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

---

## 3. Dependency Analysis

§CMD_REPORT_INTENT:
> 3: Analyzing dependencies across ___ chapters. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

**This phase is the unique value-add of /direct.**

### Step 1: Build Dependency Graph

Analyze each chapter's scope for:
- **Shared resources**: Files, APIs, database tables, packages touched by multiple chapters
- **Output dependencies**: Does Chapter B need Chapter A's output as input?
- **Ordering constraints**: Must Chapter A complete before Chapter B can start?

### Step 2: Produce Visual Graph

Produce a dependency graph using `§CMD_FLOWGRAPH` notation showing chapter relationships, parallel groups, and serial chains. Use branch glyphs (`├►`, `╰►`) for parallel groups and sequential flow (`↓`) for serial dependencies.

See the Dependency Graph section of `TEMPLATE_DIRECT_VISION.md` for the canonical example format.

### Step 3: Identify Parallel Groups

Group chapters that share no dependencies:
- Chapters with no `**Depends on**` pointing to each other can run in parallel (multiple coordinators)
- Chapters with dependencies enforce serial ordering within their chain
- Present the grouping to the user for approval

### Step 4: User Approval

Present the dependency analysis via `AskUserQuestion`:
> "Dependency analysis complete. [N] chapters in [M] parallel groups."
> - **"Approve dependencies"** -- Accept the graph and proceed to Vision Writing
> - **"Adjust dependencies"** -- Modify the graph (add/remove dependencies)
> - **"Re-analyze"** -- Something was missed, re-run the analysis

---

## 4. Execution

§CMD_REPORT_INTENT:
> 4: Selecting execution path for vision document. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(4.*)

*Gateway phase — presents inline/agent/parallel choice, then enters the selected branch.*

---

## 4.A. Vision Writing
*Produce the final vision document.*

§CMD_REPORT_INTENT:
> 4.A: Writing vision document: `docs/[name]_DIRECT.md`. ___ chapters across ___ parallel groups.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(4.A.*)

### Output Path

The vision document is written directly to `docs/`:
- **Path**: `docs/[NAME]_DIRECT.md` (user-specified or derived from project goal)
- **Provenance**: References the current direct session

### Writing the Vision

Use `TEMPLATE_DIRECT_VISION.md` to produce the vision document. Populate all sections from the interrogation and planning phases:

1.  **Goal**: From interrogation (project goal topic)
2.  **Success Criteria**: From planning phase draft
3.  **Constraints**: From interrogation (constraints topic)
4.  **Decision Principles**: From interrogation and planning
5.  **Context Sources**: Sessions that fed into this vision (/analyze, /brainstorm refs)
6.  **Dependency Graph**: ASCII graph from Phase 3
7.  **Chapters**: Each chapter from the plan, with:
    - Semantic slug as heading identifier
    - Scope description
    - `**Depends on**:` field (from dependency analysis)
    - `**Tags**: #needs-coordinate` (for coordinator execution)

### Mode-Specific Writing Behavior

**Greenfield**: Write the full document from scratch.

**Evolution**:
1.  Write the updated v2 document (full rewrite incorporating all changes)
2.  **Diff Phase**: Compare v1 baseline (loaded in Setup) against the new v2
3.  Present diff hunks interactively via `§CMD_WALK_THROUGH_RESULTS`:
    - **New chapters**: Marked for `#needs-coordinate` tagging
    - **Modified chapters**: User decides: re-execute (`#needs-coordinate` reset), skip (keep current tag), or manual review
    - **Removed chapters**: User decides: cleanup (`#needs-chores`), or dismiss
4.  Apply tag changes based on user decisions

**Split**:
1.  Replace the target chapter with sub-chapters in the existing vision
2.  Sub-chapters inherit the parent's slug as prefix: `@app/auth-system/token-service`
3.  Original chapter heading becomes a group header (no `#needs-coordinate` tag)
4.  Sub-chapters get their own `#needs-coordinate` tags
5.  Run dependency analysis within the sub-chapter group
6.  Write the modified vision document

### Report

Execute `§CMD_LINK_FILE` for the produced vision document.

---

## 4.B. Agent Handoff
*Hand off to an autonomous agent for vision writing.*

§CMD_EXECUTE_PHASE_STEPS(4.B.*)

§CMD_HANDOFF_TO_AGENT with:
```json
{
  "agentName": "writer",
  "startAtPhase": "4.A: Vision Writing",
  "planOrDirective": "[sessionDir]/DIRECT_PLAN.md",
  "logFile": "DIRECT_LOG.md",
  "taskSummary": "Write the vision document: [brief description]"
}
```

---

## 5. Synthesis
*When the vision document is complete.*

§CMD_REPORT_INTENT:
> 5: Synthesizing. Vision document written with ___ chapters.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(5.0.*)

**Debrief notes** (for `DIRECT.md`):
*   **Vision Summary**: What the project achieves, chapter count, parallel group count
*   **Dependency Analysis**: Summary of the dependency graph and parallel opportunities
*   **Mode Used**: Greenfield/Evolution/Split and what it entailed
*   **Evolution Diff** (if applicable): Summary of changes from v1 to v2
*   **Next Steps**: Clear recommendation — invoke `/coordinate` with the vision path

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Vision document complete. Walk through the chapters?"
  debriefFile: "DIRECT.md"
```

**Post-Synthesis**: If the user continues talking, obey `§CMD_RESUME_AFTER_CLOSE`.
