---
name: chores
description: "Executes routine maintenance and cleanup tasks from a structured task queue. Triggers: \"do some chores\", \"housekeeping tasks\", \"small cleanup tasks\", \"work through a task queue\"."
version: 3.0
tier: protocol
---

Executes routine maintenance and cleanup tasks from a structured task queue.

# Chores Protocol (The Utility Player's Code)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "CHORES",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed", "contextSourcesPresented"], "gate": false},
    {"label": "1", "name": "Task Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["logEntries"]},
    {"label": "2", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "2.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "2.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "2.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "2.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/chores", "/implement", "/review", "/document"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_CHORES_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_CHORES.md",
  "requestTemplate": "assets/TEMPLATE_CHORES_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_CHORES_RESPONSE.md"
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Processing chores for ___ context area. Trigger: ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the [Topic] and [Context Area]. This session will handle multiple small tasks within this area.
*   **`taskSummary`**: Describe the overall context/area, not a specific task. Individual tasks come later.

*Phase 0 always proceeds to Phase 1 -- no transition question needed.*

---

## 1. Task Loop
*The heart of chores: receive task, clarify if needed, execute, log, repeat.*

§CMD_REPORT_INTENT:
> 1: Entering task loop for ___ area.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### Task Lifecycle (repeat for each task):

#### Step 1: Receive
*   User provides a task (may be vague or detailed).
*   **Log**: `Task Received` entry with task number, request, and clarity assessment.
*   Increment internal task counter.

#### Step 2: Clarify (if needed)
*   **Gate**: Is the task clear enough to execute?
    *   *Yes*: Skip to Step 3.
    *   *No*: Ask up to 4 targeted questions via `AskUserQuestion`. Do NOT use the full `§CMD_INTERROGATE`. This is quick clarification, not deep interrogation.
*   **Log**: `Clarification` entry with Q&A.
*   **Log**: Execute `§CMD_LOG_INTERACTION` to capture the exchange.
*   If the user's answer introduces a new task or shifts scope, treat it as a NEW task. Log the current one as deferred and start a fresh `Task Received`.

### Quick Clarification Topics
*When clarification is needed, consider these angles. Pick 1-3 questions max -- do NOT cycle through all of them.*

- **Task scope** -- what exactly needs to change, what should NOT be touched
- **Priority** -- is this blocking something, or nice-to-have
- **Dependencies** -- does this depend on or affect other tasks in the queue
- **Reversibility** -- is this a safe change or does it need extra caution
- **Testing needs** -- how should the result be verified

#### Step 3: Execute
*   Do the work. Keep changes minimal and focused.
*   **Log**: `Task Execution` entry for each significant action.
*   If execution reveals the task is bigger than "small" (would require a plan, multiple phases, or TDD), STOP and present a gate:
    > "This task looks like it needs a full /implement session."
    > - **"Continue here"** -- Keep working in chores mode despite complexity
    > - **"Defer to /implement"** -- Log task as deferred, move to next
    > - **"Abort task"** -- Drop this task entirely and wait for next

#### Step 4: Verify & Report
*   Run relevant tests or perform manual verification as appropriate.
*   **Log**: `Task Complete` or `Task Blocked` entry.
*   **Chat**: Brief report to user: what was done, what files changed, any caveats.
*   **Side Discoveries**: If anything was noticed during execution, log `Side Discovery`.

#### Step 5: Next Task Gate
> "Task complete. What's next?"
> - **"Provide next task"** -- Ready for the next chore (type task in "Other")
> - **"Close session"** -- Wrap up and generate debrief
> - **"Review progress"** -- Show summary of tasks completed so far

### Rules of the Task Loop
1.  **One Task at a Time**: Do not batch. Complete one before starting the next.
2.  **No Scope Creep**: If a task balloons, flag it and stop. Don't silently expand.
3.  **No Unsolicited Refactoring**: Only touch what the task requires. No "while I'm here" cleanups.
4.  **Quick Clarification, Not Interrogation**: 1-3 questions max per task. Get unblocked and move on.
5.  **User Drives the Queue**: The agent never decides what to work on next.

### Phase Transition
*Phase 1 does not use a standard transition question. The user signals completion by saying "done", "close", "wrap up", or similar. When the user signals completion, proceed to Phase 2.*

---

## 2. Synthesis
*When the user says "done", "close", "wrap up", or similar.*

§CMD_REPORT_INTENT:
> 2: Synthesizing. ___ tasks completed in ___ area.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Debrief notes** (for `CHORES.md`):
*   **Task Ledger**: Enumerate every task with request, outcome, changes, verification.
*   **Cumulative Changes**: All files touched across all tasks.
*   **Side Discoveries**: Anything noticed but not acted on.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Chores complete. Walk through completed tasks and side discoveries?"
  debriefFile: "CHORES.md"
  templateFile: "assets/TEMPLATE_CHORES.md"
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_RESUME_AFTER_CLOSE`.

---

## Rules of Engagement
*   **Lightweight Over Rigorous**: This is NOT `/implement`. No TDD cycle, no 3-round interrogation, no formal plan. Just focused execution.
*   **Context is Shared**: Load context once in Phase 0. All tasks operate within that context. If a task needs files outside the loaded context, load them on demand.
*   **Escalation Path**: If a task is too big for chores, recommend `/implement` or `/fix`. Don't force it.
*   **The Log is the Source of Truth**: Every task must leave a trace in the log, even if it was trivial.
