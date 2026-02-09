---
name: research-request
description: "Posts a research request for async fulfillment by Gemini Deep Research. Triggers: \"post a research request\", \"create a research question\", \"queue a research task for Gemini\"."
version: 2.0
tier: lightweight
---

Posts a research request for async fulfillment by Gemini Deep Research.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 0 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 0 until every blank is filled.

# Research Request Protocol (The Query Refiner)

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. My focus is RESEARCH_REQUEST (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 4. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 5. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 6. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Research Strategist**.
    >    **Goal**: To craft a precise, well-scoped research question that will produce a useful, actionable report.
    >    **Mindset**: A good research question is half the answer. Spend time refining before posting.
    > 7. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/research-request/assets/TEMPLATE_RESEARCH_REQUEST.md` (Template for the request document)
    *   `~/.claude/skills/research-request/assets/TEMPLATE_RESEARCH_LOG.md` (Template for session logging)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Goal].

### §CMD_VERIFY_PHASE_EXIT — Phase 0
**Output this block in chat with every blank filled:**
> **Phase 0 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`
> - Parameters parsed: `________`

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Context Ingestion
*Load relevant materials before refining the query.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - RAG session-search: `________ results` or `unavailable`
> - RAG doc-search: `________ results` or `unavailable`
> - Files loaded: `________ files`
> - User confirmed: `yes / no`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "1: Context Ingestion"
  nextPhase: "2: Interrogation"
  prevPhase: "0: Setup"
  custom: "Skip to 3: Post Request | Question is already clear, just post it"

---

## 2. The Interrogation (Query Refinement)
*Refine the research question through structured dialogue.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to refine the research question.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` (Iterative Loop).
**Constraint**: **MINIMUM 3 ROUNDS**. Focus on:
*   **Round 1 (Broad)**: What is the core question? What prompted this? What do you already know?
*   **Round 2 (Scope)**: What constraints apply? What should be included/excluded? What depth?
*   **Round 3 (Output)**: What format is most useful? What specific deliverables? How will you use the results?

*   **Log**: After each answer, execute `§CMD_LOG_TO_DETAILS` and `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with a Query Refinement entry if the question evolved.

**If this is a follow-up request**: Also ask:
*   Which previous research response are we continuing from?
*   What was missing or insufficient in the previous report?
*   Read the previous response to extract the Interaction ID.

Execute `AskUserQuestion` (multiSelect: false):
> "Research request refined. Ready to submit?"
> - **"Ready"** — Submit the research request
> - **"More discussion"** — Continue refining the question

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Rounds completed: `________` (minimum 3)
> - Core question refined: `________`
> - Constraints identified: `________`
> - Output format agreed: `________`
> - DETAILS.md entries: `________`
> - User confirmed: `________`

### Phase Transition
*Fired by §CMD_EXECUTE_INTERROGATION_PROTOCOL exit gate's "Proceed to next phase" option.*

Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "2: Interrogation"
  nextPhase: "3: Post Request"
  prevPhase: "1: Context Ingestion"
  custom: "Start over | The question has changed fundamentally, re-interrogate"

---

## 3. Post Request
*Create the research request document.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Post Request.
> 2. I will `§CMD_POST_RESEARCH_REQUEST` to create and tag the request document.
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` to close the session.

1.  **Create**: Populate the `~/.claude/skills/research-request/assets/TEMPLATE_RESEARCH_REQUEST.md` template with the refined query, context, constraints, expected output, and previous research (if follow-up). Save as `RESEARCH_REQUEST_[TOPIC].md` in the session directory (`[TOPIC]` is UPPER_SNAKE_CASE; for follow-ups append `_2.md`, `_3.md`). Tag with `#needs-research`:
    ```bash
    engine tag add "$FILE" '#needs-research'
    ```
2.  **Log**: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with a Request Posted entry.
3.  **Await (Optional)**: If the agent has other work to do in this session, offer to start a background watcher:
    > "Want me to watch for the research response while I continue working?"
    *   If yes: Execute `§CMD_AWAIT_TAG` (file mode) on the request file for `#done-research`.
    *   If no: Skip — the tag system provides cross-session durability via `/dispatch` or `/research-respond`.
4.  **Debrief**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` using a lightweight summary (no full debrief template — just a brief "Research Request Debrief" capturing the refined query, constraints, and why this research is needed).
5.  **Finalize**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` and `§CMD_REPORT_SESSION_SUMMARY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 3 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Request written: `________` (real file path)
> - Tagged: `________`
> - Log entry: `________`
> - Debrief written: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
