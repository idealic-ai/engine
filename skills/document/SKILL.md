---
name: document
description: "Keeps documentation in sync with code changes and project state. Triggers: \"update documentation\", \"patch the docs\", \"sync docs with code changes\", \"update architecture docs\"."
version: 2.0
tier: protocol
---

Keeps documentation in sync with code changes and project state.
# Document Update Protocol (The Surgical Standard)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 1 (Diagnosis & Planning) produces a DOCUMENTATION_PLAN.md. The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "DOCUMENT_UPDATE",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "templates_loaded", "parameters_parsed"]},
    {"major": 0, "minor": 1, "name": "Interrogation", "proof": ["§CMD_EXECUTE_INTERROGATION_PROTOCOL", "§CMD_LOG_TO_DETAILS"]},
    {"major": 1, "minor": 0, "name": "Diagnosis & Planning", "proof": ["context_sources_presented", "documentation_drift_assessed", "plan_written", "plan_presented", "user_approved"]},
    {"major": 1, "minor": 1, "name": "Agent Handoff"},
    {"major": 2, "minor": 0, "name": "Operation", "proof": ["plan_steps_completed", "log_entries", "unresolved_blocks"]},
    {"major": 3, "minor": 0, "name": "Synthesis"},
    {"major": 3, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 3, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 3, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 3, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
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

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is DOCUMENT_UPDATE (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 5. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 6. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will select the **Documentation Mode** (Surgical / Refine / Audit / Custom).
    > 8. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 9. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — constructs the session parameters JSON and pipes it to `session.sh activate` via heredoc.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Trigger] (e.g., "We refactored the Audio Graph").
    *   **Goal**: The mission is **Truth Convergence**. Make the map match the territory.
    *   **Value**: Outdated docs are debt. They mislead devs and waste hours. You are the cleaner.
    *   **New Features**: If this is a **New Feature**, you must define its "Home". Does it need a new `concepts/X.md`? or a section in `features/Y.md`? **Do not leave it homeless.**

5.1. **Documentation Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What documentation approach should I use?"
    > - **"Surgical" (Recommended)** — Targeted updates: fix specific docs affected by code changes
    > - **"Refine"** — Improve existing docs: restructure, clarify, consolidate
    > - **"Audit"** — Comprehensive review: find gaps, stale content, and inconsistencies
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Operation Strategy.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/surgical.md`, `modes/refine.md`, `modes/audit.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 role (from mode file)
    *   Phase 1 diagnosis strategy (from mode file)
    *   Phase 2 operation approach (from mode file)

6.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

7.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion.

*Phase 0 always proceeds to Phase 0.1 — no transition question needed.*

---

## 0.1. Interrogation (Optional Pre-Flight)
*Validate assumptions before cutting. Skip this phase when the documentation task is straightforward.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 0.1: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to validate assumptions.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: First, ask the user to choose interrogation depth. Then execute rounds.

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Task is well-understood, just confirming scope |
| **Medium** | 6+ | Moderate complexity, new feature docs, audience unclear |
| **Long** | 9+ | Architecture docs, multi-audience, significant restructuring |
| **Absolute** | Until ALL questions resolved | Critical documentation, zero ambiguity tolerance |

### Interrogation Topics (Documentation)
*Examples of themes to explore. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Scope & boundaries** — which docs are in/out, depth of changes, new vs update
- **Audience & tone** — who reads these docs, technical level, formality
- **Source of truth** — where does the "correct" information live (code, specs, conversations)
- **Freshness assessment** — how stale are the current docs, when were they last updated
- **Structure & format** — should we restructure, add diagrams, change headings
- **Dependencies** — do changes to one doc require cascading updates to others
- **New feature docs** — does this need a new file, a new section, or a new concept page
- **Risks & constraints** — what could go wrong with doc changes (broken links, stale references)

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions about doc changes
- **Deep dive** — Drill into a specific doc area in detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 1: Diagnosis & Planning"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

---

## 1. Diagnosis & Planning (Pre-Op)
*Before cutting, understand the anatomy and draft the procedure.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Diagnosis & Planning.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to load relevant docs and code.
> 3. I will survey the target documentation to assess the extent of the "drift".
> 4. I will `§CMD_GENERATE_PLAN_FROM_TEMPLATE` using `DOCUMENTATION_PLAN.md`.
> 5. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding to edits.

**Action**:
1.  **Context Ingestion**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.
2.  **Survey**: Use targeted reads to identify outdated sections.
3.  **Plan**: Execute `§CMD_GENERATE_PLAN_FROM_TEMPLATE`.
    *   **Constraint**: Be specific. "Rewrite Section 3 of X.md" is better than "Update X.md".
4.  **Verify**: **STOP**. Ask user to confirm the Surgical Plan.

### Optional: Plan Walk-Through
Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
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

If any items are flagged for revision, return to the plan for edits before proceeding.

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/.directives/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 1: Surgical plan ready. How to proceed?"
> - **"Launch writer agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 1.1. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 1 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"writer"`
*   `startAtPhase`: `"Phase 2: The Operation"`
*   `planOrDirective`: `[sessionDir]/DOCUMENTATION_PLAN.md`
*   `logFile`: `DOCUMENTATION_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION.md`
*   `logTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_LOG.md`
*   `taskSummary`: `"Execute the document update plan: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"writer"`
*   `planFile`: `[sessionDir]/DOCUMENTATION_PLAN.md`
*   `logFile`: `DOCUMENTATION_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION.md`
*   `logTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION_LOG.md`
*   `taskSummary`: `"Execute the document update plan: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 2 as normal.
**If "Revise the plan"**: Return to Phase 1 for revision.

---

## 2. The Operation (Execution)
*Execute the plan. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Operation.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage edits.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_DOCUMENTATION_LOG.md` EXACTLY) to record changes as they happen.
> 4. I will execute surgical updates (`§CMD_REFUSE_OFF_COURSE` applies).
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

*   **Making a Cut?** -> Log `✂️ Incision` (Section, Action).
*   **Finding Rot?** -> Log `💀 Necrosis` (Dead Link, Outdated Info).
*   **Inconsistency?** -> Log `🩸 Bleeding` (Contradiction, Source).
*   **Fixing?** -> Log `🩹 Suture` (Fix, Rationale).
*   **Observing?** -> Log `🩺 Observation` (Tone, Structure, Insight).

**Constraint**: **High-Fidelity Logging**. Use `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.
**Constraint**: **BLIND WRITE**. Do not re-read the log file.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 3. Synthesis
*When the surgery is complete.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.
> 3. I will also execute `§CMD_MANAGE_TOC` to update `docs/TOC.md` with documentation files touched this session.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Debrief creation notes** (for Step 1 -- `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `DOCUMENTATION.md`
*   **Summary**: What was changed?
*   **Prognosis**: Is the documentation healthy?
*   **Expert Opinion**: Your subjective take on the state of the docs.

**Skill-specific step** (after Step 1, before Step 2):
**TOC MANAGEMENT**: Execute `§CMD_MANAGE_TOC`.
  *   Collects all documentation files created, modified, or deleted during this session.
  *   Presents multichoice for TOC.md additions, description updates, and stale entry removals.
  *   Auto-applies selected changes to `docs/TOC.md`.
  *   Skips silently if no documentation files were touched.

**Walk-through config** (for Step 3 -- `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Documentation complete. Walk through the updates?"
  debriefFile: "DOCUMENTATION.md"
  templateFile: "~/.claude/skills/document/assets/TEMPLATE_DOCUMENTATION.md"
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
