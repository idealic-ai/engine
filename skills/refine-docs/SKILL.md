---
name: refine-docs
description: "Refines existing documentation for clarity, accuracy, and structure. Triggers: \"restructure the docs\", \"consolidate documentation\", \"improve doc readability\", \"fix stale documentation\", \"clean up docs\"."
version: 2.0
---

Refines existing documentation for clarity, accuracy, and structure.
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

# Document Improvement Session Protocol

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Analysis & Initialization (Setup)

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Analysis & Initialization.
    > 2. My focus is REFINE_DOCS (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 4. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 5. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 6. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Documentation Editor-in-Chief**.
    >    **Goal**: To refine, consolidate, and verify documentation, ensuring it is "Evergreen" and unambiguous.
    >    **Mindset**: Precision over speed. Every edit must be justified. Every deletion must be accounted for.
    > 7. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT edit any documentation files in Phase 1. Only load templates and standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project structure and file map)
    *   `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_LOG.md` (Template for continuous surgery logging)
    *   `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE.md` (Template for final session debrief/report)
    *   `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_PLAN.md` (Template for technical execution planning)

3.  **Context**: What is the improvement goal? (e.g., "Merge duplicate Playback concepts," "Verify Code vs Docs").

4.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` — output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

5.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` — create `sessions/[YYYY_MM_DD]_DOC_IMPROVEMENT_[TOPIC]/`.

6.  **Load Targets**: Read the specific documentation files (and optionally code files) provided by the user.

7.  **Initialize Log**: Execute `§CMD_INIT_OR_RESUME_LOG_SESSION` (Template: `DOC_UPDATE_LOG.md`, Dest: `DOC_IMPROVEMENT_LOG.md`).

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`, `________`
> - docs/TOC.md: `________`
> - Parameters parsed: `________`
> - Target files loaded: `________`
> - DOC_IMPROVEMENT_LOG.md: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Interrogation"** — Stress-test the documentation through structured rounds
> - **"Stay in Phase 1"** — Load additional files or resolve setup issues

---

## 2. The Interrogation (3+ Rounds)
*Before writing the Plan, stress-test the documentation with the user.*

**STOP. Do not write the Plan yet.** You must interact with the user to stress-test the documentation.

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to stress-test the docs in structured rounds.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to track internal findings in `DOC_IMPROVEMENT_LOG.md`.
> 5. Obey `§CMD_THINK_IN_LOG`. Record doubts and findings as I go.

### Interrogation Rounds

[!!!] CRITICAL: You MUST complete at least 3 rounds (Ambiguity, Truth, Preservation). Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / 3+**"

**Round 1: Ambiguity & Duplication**
Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` (5 questions).
*   *Agent Ask*: "File A says X, File B says Y. Which is true?"
*   *Agent Ask*: "Is `docs/X.md` redundant with `docs/Y.md`?"
*   *Agent Ask*: "This term is used differently in two places. Which definition is canonical?"
*   *Agent Ask*: "Section A repeats content from Section B almost verbatim. Which survives?"
*   *Agent Ask*: "This paragraph is ambiguous — it could mean X or Y. Which is intended?"

On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to `DOC_IMPROVEMENT_LOG.md`.

**Round 2: Truth Verification (Code vs Docs)**
Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` (5 questions).
*   *Agent Ask*: "The doc mentions `ComponentA`, but I only see `ComponentB` in code. Should we rename?"
*   *Agent Ask*: "This invariant seems violated by `src/lib/X.ts`. Is the code wrong or the doc?"
*   *Agent Ask*: "The doc describes behavior Y, but the implementation does Z. Which is the source of truth?"
*   *Agent Ask*: "This API endpoint documentation is missing parameter W. Is the doc incomplete or the parameter deprecated?"
*   *Agent Ask*: "The architecture diagram shows flow A->B->C, but code shows A->C directly. Which is current?"

On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to `DOC_IMPROVEMENT_LOG.md`.

**Round 3: Preservation Check (CRITICAL)**
Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` (5 questions).
*   *Agent Ask*: "If we delete Section X, where will the concept of 'Y' live?"
*   *Agent Ask*: "This snippet is the only place explaining Z. Do you confirm deletion?"
*   *Agent Ask*: "I want to remove this legacy example. Please justify why we still need it, or confirm deletion."
*   *Agent Ask*: "Merging these two files will lose the narrative structure of File A. Is that acceptable?"
*   *Agent Ask*: "This deprecated section still has unique context not captured elsewhere. Keep, move, or delete?"

On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to `DOC_IMPROVEMENT_LOG.md`.

**Round X: Followups (until satisfied)**
Continue with interrogation rounds as needed. The user may raise new concerns, request deeper investigation, or confirm readiness to proceed.

On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to `DOC_IMPROVEMENT_LOG.md`.

### Interrogation Exit Gate

**After completing Round 3**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum 3 met). What next?"
> - **"Proceed to Phase 3: Drafting"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Additional stress-testing, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions about proposed changes, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a specific doc area in more detail, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first -> Devil's advocate -> Deep dive -> re-present exit gate.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Round 1 (Ambiguity): `________`
> - Round 2 (Truth): `________`
> - Round 3 (Preservation): `________`
> - DETAILS.md entries: `________`
> - DOC_IMPROVEMENT_LOG.md entries: `________`

---

## 3. The Drafting (Planning)
*Create the documentation improvement plan.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Drafting.
> 2. I will `§CMD_GENERATE_PLAN_FROM_TEMPLATE` (Template: `DOC_UPDATE.md`, Dest: `DOC_UPDATE_PLAN.md`) to create the improvement plan.
> 3. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding.

1.  **Clone Template (IMPERATIVE)**: Execute `§CMD_GENERATE_PLAN_FROM_TEMPLATE` (Template: `DOC_UPDATE.md`, Dest: `DOC_UPDATE_PLAN.md`).
2.  **Fill Template**: Use `search_replace` to populate the *existing* headers.
    *   **CRITICAL**: Do NOT overwrite the whole file. Fill in the blanks.
3.  **Refine**:
    *   **Style**: The plan must be **rich, nuanced, and reasoning-heavy**.
    *   **Avoid**: Do not write "Update Section X".
    *   **Do**: Write "Refactor Section X because Y. Current state implies Z, but we are moving to W. The key change is..."
4.  **Strict Rules**:
    *   **Consolidation**: If merging files, explicitly map where every paragraph goes.
    *   **Deprecation**: If deleting > 3 lines or a code snippet, you MUST add a specific "Deprecation Justification" in the Plan.
    *   **Truth**: Every change must be backed by a Code Reference or User Confirmation.
    *   **Reasoning**: Every major bullet point must have a "Why" or "Before/After" explanation.
5.  **Present**: Report the plan file via `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - DOC_UPDATE_PLAN.md written: `________`
> - Rich reasoning used: `________`
> - Deprecation justifications: `________`
> - Changes backed by evidence: `________`
> - Plan presented: `________`
> - User approved: `________`

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/standards/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 3: Plan ready. How to proceed?"
> - **"Launch writer agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute the plan step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 3b. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 3 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"writer"`
*   `parentPromptFile`: `~/.claude/skills/refine-docs/SKILL.md`
*   `startAtPhase`: `"Phase 4: Output"`
*   `planOrDirective`: `[sessionDir]/DOC_UPDATE_PLAN.md`
*   `logFile`: `DOC_IMPROVEMENT_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE.md`
*   `logTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_LOG.md`
*   `taskSummary`: `"Execute the documentation improvement plan: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"writer"`
*   `planFile`: `[sessionDir]/DOC_UPDATE_PLAN.md`
*   `logFile`: `DOC_IMPROVEMENT_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE.md`
*   `logTemplate`: `~/.claude/skills/document/assets/TEMPLATE_DOC_UPDATE_LOG.md`
*   `taskSummary`: `"Execute the documentation improvement plan: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 4 as normal.
**If "Revise the plan"**: Return to Phase 3 for revision.

---

## 4. Output (Synthesis)
*Finalize and deliver the documentation improvement plan.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Output.
> 2. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 3. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not proceed until you output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER.

**Step 1 (THE DELIVERABLE)**: Confirm `DOC_UPDATE_PLAN.md` exists in the session directory and is complete.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat:
*   `sessions/[...]/DOC_UPDATE_PLAN.md`
*   `sessions/[...]/DOC_IMPROVEMENT_LOG.md`
*   `sessions/[...]/DETAILS.md`

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - DOC_UPDATE_PLAN.md exists: `________` (real file path)
> - DOC_IMPROVEMENT_LOG.md entries: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---

## Rules of Engagement
*   **Chesterton's Fence**: Do not remove a rule, section, or code snippet until you understand why it was put there.
*   **Default to Keep**: When in doubt, keep the content. Noise is better than data loss.
*   **No Data Loss**: If you delete a file, its knowledge must be moved, not destroyed.
*   **Code is King**: If Doc conflicts with Code, the Doc is wrong (unless it is a spec for future work).
