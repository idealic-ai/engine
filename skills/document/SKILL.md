---
name: document
description: "Keeps documentation in sync with code changes and project state. Triggers: \"update documentation\", \"patch the docs\", \"sync docs with code changes\", \"update architecture docs\"."
version: 2.0
---

Keeps documentation in sync with code changes and project state.
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

# Document Update Protocol (The Surgical Standard)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 2 (Diagnosis & Planning) produces a DOC_UPDATE_PLAN.md. The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is DOCUMENT_UPDATE (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Documentation Surgeon**.
    >    **Goal**: To align documentation with reality using **surgical precision**.
    >    **Mindset**: "Scalpel, not Sledgehammer. Preserve the tissue, remove the disease."
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project structure and file map)
    *   `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_LOG.md` (Template for continuous surgery logging)
    *   `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE.md` (Template for final session debrief/report)
    *   `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_PLAN.md` (Template for technical execution planning)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Trigger] (e.g., "We refactored the Audio Graph").
    *   **Goal**: The mission is **Truth Convergence**. Make the map match the territory.
    *   **Value**: Outdated docs are debt. They mislead devs and waste hours. You are the cleaner.
    *   **New Features**: If this is a **New Feature**, you must define its "Home". Does it need a new `concepts/X.md`? or a section in `features/Y.md`? **Do not leave it homeless.**

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion.

7.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance.
    *   *Note*: Re-run discovery during Post-Op to catch late arrivals.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`, `________`
> - Parameters parsed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 1b: Interrogation"** — Validate assumptions about scope, audience, and approach before planning
> - **"Skip to Phase 2: Diagnosis & Planning"** — Requirements are clear, go straight to surveying docs and drafting the plan
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 1b. Interrogation (Optional Pre-Flight)
*Validate assumptions before cutting. Skip this phase when the documentation task is straightforward.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1b: Interrogation.
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
> - **"Proceed to Phase 2: Diagnosis & Planning"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

### §CMD_VERIFY_PHASE_EXIT — Phase 1b
**Output this block in chat with every blank filled:**
> **Phase 1b proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`

---

## 2. Diagnosis & Planning (Pre-Op)
*Before cutting, understand the anatomy and draft the procedure.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Diagnosis & Planning.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to load relevant docs and code.
> 3. I will survey the target documentation to assess the extent of the "drift".
> 4. I will `§CMD_GENERATE_PLAN_FROM_TEMPLATE` using `DOC_UPDATE_PLAN.md`.
> 5. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding to edits.

**Action**:
1.  **Context Ingestion**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.
2.  **Survey**: Use targeted reads to identify outdated sections.
3.  **Plan**: Execute `§CMD_GENERATE_PLAN_FROM_TEMPLATE`.
    *   **Constraint**: Be specific. "Rewrite Section 3 of X.md" is better than "Update X.md".
4.  **Verify**: **STOP**. Ask user to confirm the Surgical Plan.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Context ingested: `________`
> - Documentation drift assessed: `________`
> - DOC_UPDATE_PLAN.md written: `________`
> - Plan presented: `________`
> - User approved: `________`

### Optional: Plan Walk-Through
Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Surgical plan ready. Walk through the operations before cutting?"
  debriefFile: "DOC_UPDATE_PLAN.md"
  itemSources:
    - "## 6. Step-by-Step Implementation Strategy"
  planQuestions:
    - "Is this the right scope for this operation?"
    - "Any docs I'm missing that should also be updated?"
    - "Concerns about this change breaking existing references?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/standards/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 2: Surgical plan ready. How to proceed?"
> - **"Launch writer agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 2b. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 2 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"writer"`
*   `startAtPhase`: `"Phase 3: The Operation"`
*   `planOrDirective`: `[sessionDir]/DOC_UPDATE_PLAN.md`
*   `logFile`: `DOC_UPDATE_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE.md`
*   `logTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_LOG.md`
*   `taskSummary`: `"Execute the document update plan: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"writer"`
*   `planFile`: `[sessionDir]/DOC_UPDATE_PLAN.md`
*   `logFile`: `DOC_UPDATE_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE.md`
*   `logTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_LOG.md`
*   `taskSummary`: `"Execute the document update plan: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 3 as normal.
**If "Revise the plan"**: Return to Phase 2 for revision.

---

## 3. The Operation (Execution)
*Execute the plan. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Operation.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage edits.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_DOC_UPDATE_LOG.md` EXACTLY) to record changes as they happen.
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

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Plan steps completed: `________`
> - DOC_UPDATE_LOG.md entries: `________`
> - Unresolved blocks: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Operation complete. How to proceed?"
> - **"Proceed to Phase 4: Post-Op Synthesis"** — Generate debrief and close session
> - **"Stay in Phase 3"** — More edits needed, continue operating
> - **"Run verification first"** — Review changes before closing

---

## 4. Post-Op (Synthesis)
*When the surgery is complete.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Post-Op Synthesis.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_DOC_UPDATE.md` EXACTLY).
> 3. I will `§CMD_MANAGE_TOC` to update `docs/TOC.md` with documentation files touched this session.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list all outputs.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `DOC_UPDATE.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Summary**: What was changed?
  *   **Prognosis**: Is the documentation healthy?
  *   **Expert Opinion**: Your subjective take on the state of the docs.

**Step 2 (TOC MANAGEMENT)**: Execute `§CMD_MANAGE_TOC`.
  *   Collects all documentation files created, modified, or deleted during this session.
  *   Presents multichoice for TOC.md additions, description updates, and stale entry removals.
  *   Auto-applies selected changes to `docs/TOC.md`.
  *   Skips silently if no documentation files were touched.

**Step 3**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 4**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 5**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 6**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Documentation complete. Walk through the updates?"
  debriefFile: "DOC_UPDATE.md"
  itemSources:
    - "## 2. Operations Performed"
    - "## 4. Side Discoveries"
    - "## 5. Expert Opinion"
  actionMenu:
    - label: "Needs code changes"
      tag: "#needs-implementation"
      when: "Doc update revealed code that needs fixing"
    - label: "Research further"
      tag: "#needs-research"
      when: "Doc gap needs deeper investigation"
    - label: "Add more docs"
      tag: "#needs-documentation"
      when: "Related documentation also needs updating"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - DOC_UPDATE.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 7**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Documentation complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/evangelize` (Recommended) | Docs ready — share the knowledge |
| 2 | `/implement` | Docs revealed gaps — build the missing pieces |
| 3 | `/analyze` | Need deeper research for the docs |
| 4 | `/brainstorm` | Explore ideas for better documentation |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
