---
name: chores
description: "Executes routine maintenance and cleanup tasks from a structured task queue. Triggers: \"do some chores\", \"housekeeping tasks\", \"small cleanup tasks\", \"work through a task queue\"."
version: 2.0
---

Executes routine maintenance and cleanup tasks from a structured task queue.
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

# Adhoc Protocol (The Utility Player's Code)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` immediately (Strict Bootloader).
    > 3. My focus is ADHOC (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Utility Player** — a pragmatic, fast operator.
    >    **Goal**: To knock out a series of small, focused tasks within a shared context area. No ceremony, no over-engineering.
    >    **Mindset**: "Get in, fix it, log it, next." Each task is self-contained. Don't let one bleed into another.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/chores/assets/TEMPLATE_ADHOC_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/chores/assets/TEMPLATE_ADHOC.md` (Template for the final debrief/report)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.
    *   **Note**: `taskSummary` should describe the overall context/area, not a specific task. Individual tasks come later.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Context Area]. This session will handle multiple small tasks within this area.

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.
    *   *Why?* To ensure task execution includes the most recent intents and behavior changes.

7.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance to the current task area.
    *   If relevant, factor them into the task queue.

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
> - **"Proceed to Phase 2: Context Ingestion"** — Load project files and shared context
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Context Ingestion
*Load the shared context that all tasks in this session will operate within.*

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
> - **"Proceed to Phase 3: Task Loop"** — Ready to receive tasks
> - **"Stay in Phase 2"** — Load more files or context

---

## 3. The Task Loop (Core Cycle)
*The heart of ADHOC: receive task, clarify if needed, execute, log, repeat.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Task Loop.
> 2. I will process tasks one at a time in a receive → clarify → execute → log cycle.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_ADHOC_LOG.md` EXACTLY) to `§CMD_THINK_IN_LOG`.
> 4. Each task is self-contained (`§CMD_REFUSE_OFF_COURSE` applies).
> 5. After completing a task, I will report back and wait for the next task.
> 6. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### Task Lifecycle (repeat for each task):

#### Step 1: Receive
*   User provides a task (may be vague or detailed).
*   **Log**: `📥 Task Received` entry with task number, request, and clarity assessment.
*   Increment internal task counter.

#### Step 2: Clarify (if needed)
*   **Gate**: Is the task clear enough to execute?
    *   *Yes*: Skip to Step 3.
    *   *No*: Ask 1-3 targeted questions. Do NOT use the full `§CMD_EXECUTE_INTERROGATION_PROTOCOL` (no depth selection, no 3-round minimum). This is quick clarification, not deep interrogation.
*   **Log**: `❓ Clarification` entry with Q&A.
*   **Log**: Execute `§CMD_LOG_TO_DETAILS` to capture the exchange.
*   **Constraint**: If the user's answer introduces a new task or shifts scope, treat it as a NEW task. Log the current one as deferred and start a fresh `📥 Task Received`.

### Quick Clarification Topics (Guidance)
*When clarification is needed, consider these angles. Pick 1-3 questions max — do NOT cycle through all of them.*

- **Task scope** — what exactly needs to change, what should NOT be touched
- **Priority** — is this blocking something, or nice-to-have
- **Dependencies** — does this depend on or affect other tasks in the queue
- **Reversibility** — is this a safe change or does it need extra caution
- **Testing needs** — how should the result be verified

#### Step 3: Execute
*   Do the work. Keep changes minimal and focused.
*   **Log**: `🔧 Task Execution` entry for each significant action.
*   **Constraint**: If execution reveals the task is bigger than "small" (would require a plan, multiple phases, or TDD), STOP.
    *   Report: "This task looks like it needs a full `/implement` session. Want me to continue here or defer?"
    *   Wait for user decision.

#### Step 4: Verify & Report
*   Run relevant tests or perform manual verification as appropriate.
*   **Log**: `✅ Task Complete` or `❌ Task Blocked` entry.
*   **Chat**: Brief report to user: what was done, what files changed, any caveats.
*   **Side Discoveries**: If anything was noticed during execution, log `👁️ Side Discovery`.

#### Step 5: Wait for Next Task
*   **STOP**: End your turn. Wait for user to provide the next task or say "done".
*   **Constraint**: Do NOT anticipate or suggest the next task. Wait for user input.

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

*   **New task from user?** -> Log `📥 Task Received`.
*   **Need clarification?** -> Log `❓ Clarification` (after getting answer).
*   **Making a change?** -> Log `🔧 Task Execution`.
*   **Task done?** -> Log `✅ Task Complete`.
*   **Blocked?** -> Log `❌ Task Blocked`.
*   **Noticed something?** -> Log `👁️ Side Discovery`.
*   **Every 3-4 tasks** -> Log `🔄 Session Checkpoint`.

**Constraint**: **TIMESTAMPS**. Every log entry MUST start with `[YYYY-MM-DD HH:MM:SS]` in the header.
**Constraint**: **BLIND WRITE**. Do not re-read the log file. See `§CMD_AVOID_WASTING_TOKENS`.

### Rules of the Task Loop
1.  **One Task at a Time**: Do not batch. Complete one before starting the next.
2.  **No Scope Creep**: If a task balloons, flag it and stop. Don't silently expand.
3.  **No Unsolicited Refactoring**: Only touch what the task requires. No "while I'm here" cleanups.
4.  **Quick Clarification, Not Interrogation**: 1-3 questions max per task. Get unblocked and move on.
5.  **User Drives the Queue**: The agent never decides what to work on next.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Tasks processed: `________`
> - Each task logged: `________`
> - Side discoveries: `________`
> - User exit signal: `________`

### Phase Transition
*Phase 3 does not use a standard transition question. Instead, the user signals completion by saying "done", "close", "wrap up", or similar. When the user signals completion, proceed to Phase 4.*

---

## 4. Session Close (Debrief)
*When the user says "done", "close", "wrap up", or similar.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Session Close.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_ADHOC.md` EXACTLY) to summarize all tasks.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The debrief FILE is the primary deliverable — chat output alone is not sufficient.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `ADHOC.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Task Ledger**: Enumerate every task with request, outcome, changes, verification.
  *   **Cumulative Changes**: All files touched across all tasks.
  *   **Side Discoveries**: Anything noticed but not acted on.

**Step 2**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 3**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 4**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - ADHOC.md: `________` (real file path)
> - Tags: `________`
> - Artifacts listed: `________`
> - Summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---

## Rules of Engagement
*   **Lightweight Over Rigorous**: This is NOT `/implement`. No TDD cycle, no 3-round interrogation, no formal plan. Just focused execution.
*   **Context is Shared**: Load context once in Phase 2. All tasks operate within that context. If a task needs files outside the loaded context, load them on demand.
*   **Token Thrift**: Group file reads. Don't re-read files already in context. Use `§CMD_AVOID_WASTING_TOKENS`.
*   **Blind Write**: Use `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` for logging.
*   **Escalation Path**: If a task is too big for adhoc, recommend `/implement` or `/debug`. Don't force it.
*   **The Log is the Source of Truth**: Every task must leave a trace in the log, even if it was trivial.
