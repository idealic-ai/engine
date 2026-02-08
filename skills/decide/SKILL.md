---
name: decide
description: "Structures and records architectural/design decisions with rationale and trade-offs. Triggers: \"make a decision\", \"resolve deferred decisions\", \"surface pending decisions\", \"record a decision\"."
version: 2.0
---

Structures and records architectural/design decisions with rationale and trade-offs.
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

# Decision Protocol (The Judge's Bench)

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. My focus is DECISION (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 4. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 5. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 6. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Decision Facilitator**.
    >    **Goal**: To surface deferred decisions, present context neutrally, and record the user's call faithfully.
    >    **Mindset**: "Present. Don't advocate. Record faithfully."
    > 7. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `.claude/skills/decide/assets/TEMPLATE_DECISION.md` (or `~/.claude/skills/decide/assets/TEMPLATE_DECISION.md`) (Template for the decisions record)
    *   `.claude/skills/decide/assets/TEMPLATE_DECISION_LOG.md` (or `~/.claude/skills/decide/assets/TEMPLATE_DECISION_LOG.md`) (Template for continuous session logging)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`
> - Parameters parsed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Discovery"** — Search for #needs-decision tags across sessions
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Discovery Phase
*Find all pending decisions across all sessions.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Discovery.
> 2. I will search for `#needs-decision` tags across all sessions.
> 3. I will collect context for each pending decision.

**Algorithm**:
1.  **Search**: Execute `§CMD_FIND_TAGGED_FILES` for `#needs-decision` across `sessions/`.
2.  **If Zero Results**: Report "No pending decisions found." Execute `§CMD_REPORT_SESSION_SUMMARY`. **STOP**.
3.  **For Each Tagged File**:
    *   Read the **Tags line** (line 2) to confirm `#needs-decision` is present.
    *   Read the **file content** to locate the decision point. Look for:
        *   Explicit `#needs-decision` markers in text.
        *   Questions marked as unresolved, deferred, or needing user input.
        *   `[UNRESOLVED]` markers in logs.
    *   **Extract**: The question/topic, the surrounding context (2-3 paragraphs), and any options already suggested.
    *   **Note**: The originating session directory and file path.
4.  **Log**: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` — record discovery results (how many files, which sessions).
5.  **Present Summary**: Output a numbered list of all pending decisions:
    ```
    ## Pending Decisions ([N] items)
    | # | Session | File | Topic |
    |---|---------|------|-------|
    | 1 | SESSION_NAME | FILE.md | Brief question summary |
    | 2 | ...     | ...  | ...   |
    ```

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Tag search executed: `________`
> - Tagged files reviewed: `________`
> - DECISION_LOG.md entries: `________`
> - Pending decisions presented: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Discovery complete. [N] pending decisions found. How to proceed?"
> - **"Proceed to Phase 3: Decision Loop"** — Present each decision interactively
> - **"Stay in Phase 2"** — Re-scan or refine discovery results

---

## 3. Decision Loop (Interactive)
*Present each decision with context. Allow the user to decide or dig deeper.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Decision Loop.
> 2. I will present each decision with context and options.
> 3. For "Analyze deeper" responses, I will read surrounding session files and re-present.
> 4. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` after each decision.

**For Each Pending Decision**:

1.  **Present** (via `§CMD_ASK_ROUND_OF_QUESTIONS`):
    *   **Header**: "Decision [N]/[Total]: [Topic]"
    *   **Context**: The extracted question and surrounding context from the originating file.
    *   **Source**: "From `[session_dir]/[file]`"
    *   **Options**: Include the options discovered in the file (if any), PLUS:
        *   **"Analyze deeper"** — Always include this option. Description: "Read more surrounding session files for richer context, then re-present this decision."

2.  **Handle Response**:
    *   **If "Analyze deeper"**:
        1.  Read additional files from the originating session: `DETAILS.md`, `*_LOG.md`, `*_PLAN.md`, other debriefs.
        2.  Extract relevant context related to the decision topic.
        3.  Re-present the decision with the enriched context and refined options.
        4.  **Loop**: Allow "Analyze deeper" again (max 3 iterations, then present what you have).
    *   **If User Decides**:
        1.  **Log**: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` — record the decision, reasoning, and source.
        2.  **Log to Details**: Execute `§CMD_LOG_TO_DETAILS` — capture the Q&A verbatim.
        3.  **Swap Tag**: Execute `§CMD_SWAP_TAG_IN_FILE` on the originating file:
            ```bash
            ~/.claude/scripts/tag.sh swap "$ORIGINATING_FILE" '#needs-decision' '#done-decision'
            ```
        4.  **Breadcrumb**: Append a decision record to the originating file:
            ```bash
            ~/.claude/scripts/log.sh "$ORIGINATING_FILE" <<'EOF'
            ## Decision Recorded
            *   **Decided By**: `/decide` session at `[DECIDE_SESSION_DIR]`
            *   **Date**: [YYYY-MM-DD HH:MM:SS]
            *   **Question**: [The question]
            *   **Decision**: [The user's choice]
            *   **Reasoning**: [Brief reasoning if provided]
            EOF
            ```
        5.  **Proceed** to the next decision.

3.  **Continue** until all decisions are resolved or the user says "Stop" / "Skip remaining".

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Decisions presented: `________`
> - User responses recorded: `________`
> - Tag swaps executed: `________`
> - Breadcrumbs appended: `________`
> - DECISION_LOG.md entries: `________`
> - DETAILS.md entries: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Decision loop complete. [N] resolved, [M] skipped. How to proceed?"
> - **"Proceed to Phase 4: Synthesis"** — Generate DECISIONS.md and close session
> - **"Stay in Phase 3"** — Revisit skipped decisions

---

## 4. Synthesis (Debrief)
*When all decisions are resolved (or user stops).*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Synthesis.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_DECISION.md` EXACTLY) to record all decisions.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The decisions FILE is the primary deliverable — chat output alone is not sufficient.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `DECISIONS.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   Record every decision made during this session.
  *   For each: the question, the context, the options considered, the final decision, and the reasoning.
  *   Note any decisions skipped or deferred further.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - DECISIONS.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

## Rules & Standards
*   **Scope**: Read-only + `DECISIONS.md` + tag swaps. No code changes. No plan modifications.
*   **Neutrality**: Present options without advocacy. The user decides; the agent records.
*   **Faithfulness**: Record the user's exact words and reasoning. Do not paraphrase decisions.
*   **Tag Lifecycle**: `#needs-decision` -> `#done-decision`. Always swap after recording.
*   **Breadcrumbs**: Always append a decision record to the originating file for traceability.
*   **Specifically**: `§CMD_REPORT_FILE_CREATION_SILENTLY`, `§CMD_INIT_OR_RESUME_LOG_SESSION`, `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`.
