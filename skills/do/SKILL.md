---
name: do
description: "Lightweight session for quick ad-hoc work. No interrogation, no planning — just activate, work, and close. Triggers: \"quick task\", \"just do this\", \"/do this\", \"ad-hoc work\"."
version: 3.0
tier: protocol
---

Lightweight session for quick ad-hoc work -- no interrogation, no planning, no ceremony.

# /do Protocol (The Quick Operator's Code)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "DO",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS"],
      "commands": [],
      "proof": ["sessionDir", "parametersParsed"], "gate": false},
    {"label": "1", "name": "Work",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_ASK_USER_IF_STUCK"],
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
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/do", "/implement", "/analyze", "/chores"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_DO_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_DO.md"
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Quick task: ___. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the user's request. This is the task -- no interrogation needed.

*Phase 0 always proceeds to Phase 1 -- no transition question needed.*

---

## 1. Work
*The heart of /do: just do the work.*

§CMD_REPORT_INTENT:
> 1: Working on ___. Logging as I go.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### How This Phase Works
There is no formal structure -- no interrogation, no planning, no task gates. The agent works on whatever the user requested, asks clarifying questions as needed, and logs progress.

**What to do**:
*   Work on the user's request directly
*   Ask clarifying questions naturally (not via `§CMD_INTERROGATE` -- just ask)
*   Load project files as needed
*   Make changes, run tests, verify

**What NOT to do**:
*   Don't create a formal plan (use the log for thinking)
*   Don't run interrogation rounds
*   Don't gate on AskUserQuestion between steps -- just work

### Completion Signal
When a unit of work is done, present the work-phase gate via `AskUserQuestion` (multiSelect: false):
> "What next?"
> - **"Keep working"** -- Stay in Phase 1. The session remains active for more tasks. Log the completed unit and continue.
> - **"Close session"** -- Proceed to Phase 2: Synthesis. Write the debrief and deactivate.
> - **"Walkthrough changes"** -- Review what was done so far, then re-present this gate.

If the user explicitly says "done", "that's it", "close", or similar -- skip the gate and proceed directly to Phase 2.

**On "Keep working"**: Log a done entry for the completed unit, then remain in Phase 1. The agent waits for the user's next request. Repeat this gate after each subsequent unit of work.

---

## 2. Synthesis
*Wrap up and create the debrief.*

§CMD_REPORT_INTENT:
> 2: Synthesizing. ___ units of work completed.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Debrief notes** (for `DO.md`):
*   Fill in every section from the template based on the work done.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Work complete. Walk through the changes?"
  debriefFile: "DO.md"
```

**Post-Synthesis**: If the user continues talking, obey `§CMD_RESUME_AFTER_CLOSE`.

---

## Rules of Engagement
*   **Helpful Over Rigid**: This is the lightweight skill. Be pragmatic. Don't fight the user over ceremony.
*   **Log Is Non-Negotiable**: The one thing you MUST do is log. Everything else is flexible.
*   **No Interrogation**: Ask questions naturally as part of the work, not via formal rounds.
*   **No Planning Phase**: Use the log for thinking. Don't create a separate plan artifact.
*   **Escalation Path**: If the work turns out to be complex (multi-file, needs TDD, architectural decisions), suggest switching to `/implement` via `§CMD_REFUSE_OFF_COURSE`.
