---
name: delegate
description: "Manages task delegation to other agent sessions. Triggers: \"delegate this task\", \"hand off to another agent\", \"create a delegation\", \"assign work to an agent\"."
version: 2.0
---

Manages task delegation to other agent sessions.
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

# Delegation Protocol (Full Lifecycle — Request + Builder Handoff)

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. My focus is DELEGATION (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 4. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 5. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 6. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Delegation Strategist**.
    >    **Goal**: To craft a precise delegation request, get it fulfilled by a builder agent, and deliver the result.
    >    **Mindset**: A good delegation request is half the work. Define clear expectations and acceptance criteria before handing off.
    > 7. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/delegate-request/SKILL.md` (Request posting protocol — Phase 4 is reused below)
    *   `~/.claude/skills/delegate-respond/assets/TEMPLATE_DELEGATION_RESPONSE.md` (Template for the response document)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md` (Template for session logging)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Goal].

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
> - **"Proceed to Phase 2: Context Ingestion"** — Load project files and context
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Context Ingestion
*Load relevant materials before refining the delegation.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - RAG session-search: `________ results` or `unavailable`
> - RAG doc-search: `________ results` or `unavailable`
> - Files loaded: `________ files`
> - User confirmed: `yes / no`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Context loaded. How to proceed?"
> - **"Proceed to Phase 3: Interrogation"** — Refine the delegation through structured dialogue
> - **"Stay in Phase 2"** — Load more files or context

---

## 3. The Interrogation (Delegation Refinement)
*Refine the delegation request through structured dialogue.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to refine the delegation request.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.

**Action**: Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` (Iterative Loop).
**Constraint**: **MINIMUM 3 ROUNDS**. Focus on:
*   **Round 1 (Broad)**: What needs to be built/changed? What is the current state? What do you already know?
*   **Round 2 (Scope)**: What constraints apply? What should be included/excluded? What is the acceptance criteria?
*   **Round 3 (Output)**: What specific deliverables? Which files are affected? How will we verify success?

*   **Log**: After each answer, execute `§CMD_LOG_TO_DETAILS` and `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with a Task Refinement entry.

Execute `AskUserQuestion` (multiSelect: false):
> "Interrogation complete. Ready to proceed?"
> - **"Ready"** — Proceed to delegation execution
> - **"More discussion"** — Continue refining the task

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Rounds completed: `________` (minimum 3)
> - DETAILS.md entries: `________`
> - User confirmed readiness: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Interrogation complete. How to proceed?"
> - **"Proceed to Phase 4: Delegation Execution"** — Post request and launch builder agent
> - **"More interrogation"** — Continue refining the delegation
> - **"Stay in Phase 3"** — Revisit previous answers

---

## 4. Post Request & Execute via Builder Agent
*Create the request document, then hand off to the builder agent.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Delegation Execution.
> 2. I will post the request document for traceability.
> 3. I will hand off to the builder agent via the Task tool.

### Step 1: Post Request
Execute Phase 3 (Execution steps 1-4) of the delegate-request protocol to create the request document, tag it with `#needs-delegation`, and log the posting. Use the interrogation context already gathered in Phase 3 above — do not re-interrogate.

### Step 2: Compose Builder Task
1.  **Construct** the task description for the builder agent. Include:
    *   The full path to the delegation request file
    *   The session directory
    *   The log file path (for the builder to append to)
    *   The standards and templates to load
    *   The acceptance criteria (verbatim from the request)
    *   The instruction to write `DELEGATION_RESPONSE_[TOPIC].md` when done
    *   The instruction to swap the tag: `#needs-delegation` -> `#done-delegation` on the request file
    *   The instruction to append a breadcrumb to the request file

2.  **Handoff Preamble** (include in the task description):
    ```
    ## Operational Discipline
    1. Read `~/.claude/standards/COMMANDS.md` and `~/.claude/standards/INVARIANTS.md`.
    2. Read `.claude/standards/INVARIANTS.md` (project-level).
    3. Read the delegation request file at [path].
    4. Log all work to [log file path] using `~/.claude/scripts/log.sh`.
    5. When complete:
       a. Write DELEGATION_RESPONSE_[TOPIC].md in the session directory using the template.
       b. Swap tag on the request file: `~/.claude/scripts/tag.sh swap "$REQUEST_FILE" '#needs-delegation' '#done-delegation'`
       c. Append breadcrumb to request file via log.sh.
    ```

### Step 3: Launch Builder
1.  **Execute**: Use the `Task` tool to launch the builder agent with the composed task description.
2.  **Inform user**: "Delegation request posted and builder agent launched. The builder will execute the work and write the response."

### Step 4: Await Results
1.  **Background Watch**: Execute `§CMD_AWAIT_TAG` (file mode) on the request file for `#done-delegation`:
    ```bash
    Bash("~/.claude/scripts/await-tag.sh $REQUEST_FILE '#done-delegation'", run_in_background=true)
    ```
    The agent can continue other work while the builder agent executes in the background.
2.  **Receive**: When the background watcher completes (builder swapped `#done-delegation`), read the `DELEGATION_RESPONSE_[TOPIC].md` to verify the builder's output.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Request file created: `________`
> - Request tagged: `________`
> - Builder task composed: `________`
> - Builder launched: `________`
> - Watcher status: `________`

---

## 5. Present Results & Debrief
*Show the delegation results and close the session.*

1.  **Present**: Output the builder's response summary in chat so the user can review it immediately.
2.  **Verify**: Check the acceptance criteria status from the response.
3.  **Log**: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with a Delegation Complete entry.
4.  **Finalize**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` and `§CMD_REPORT_SESSION_SUMMARY`.
5.  **Next steps**: Suggest follow-up options:
    *   "Run `/review` to validate the builder's work"
    *   "The delegation response is at `[path]` — reference it from any other session"

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Builder response summary: `________`
> - Acceptance criteria: `________`
> - Log entry written: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
