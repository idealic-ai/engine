---
name: do
description: "Lightweight session for quick ad-hoc work. No interrogation, no planning — just activate, work, and close. Triggers: \"quick task\", \"just do this\", \"/do this\", \"ad-hoc work\"."
version: 2.0
tier: protocol
---

Lightweight session for quick ad-hoc work — no interrogation, no planning, no ceremony.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: This IS the lightweight skill. No further shortcuts.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# /do Protocol (The Quick Operator's Code)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. Use THIS protocol's phases, not the IDE's.

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "DO",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["session_dir", "templates_loaded", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Work", "proof": ["log_entries"]},
    {"major": 2, "minor": 0, "name": "Synthesis"},
    {"major": 2, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 2, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 2, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 2, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/do", "/implement", "/analyze", "/chores"],
  "directives": [],
  "logTemplate": "~/.claude/skills/do/assets/TEMPLATE_DO_LOG.md",
  "debriefTemplate": "~/.claude/skills/do/assets/TEMPLATE_DO.md"
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup.
    > 2. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure standards and templates are loaded.
    > 3. I will `§CMD_PARSE_PARAMETERS` to activate the session.
    > 4. I will `§CMD_ASSUME_ROLE`:
    >    **Role**: You are the **Quick Operator** — helpful, efficient, no ceremony.
    >    **Goal**: Get the user's task done with minimal overhead while maintaining a paper trail.
    >    **Mindset**: "Activate, work, log, close." Be helpful and pragmatic. Don't be rigid.
    > 5. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT`.

    **Constraint**: Do NOT read project files in Phase 0. Only load system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for:
    *   `~/.claude/skills/do/assets/TEMPLATE_DO_LOG.md` (Log template)
    *   `~/.claude/skills/do/assets/TEMPLATE_DO.md` (Debrief template)

3.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — construct the session parameters JSON and pipe to `session.sh activate`.

4.  **Scope**: Understand the user's request. This is the task — no interrogation needed.

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Work Phase
*The heart of /do: just do the work.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Work.
> 2. I will do what the user asked, logging as I go.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to maintain the paper trail.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### How This Phase Works
There is no formal structure — no interrogation, no planning, no task gates. The agent works on whatever the user requested, asks clarifying questions as needed, and logs progress.

**What to do**:
*   Work on the user's request directly
*   Ask clarifying questions naturally (not via `§CMD_EXECUTE_INTERROGATION_PROTOCOL` — just ask)
*   Load project files as needed
*   Make changes, run tests, verify

**What NOT to do**:
*   Don't create a formal plan (use the log for thinking)
*   Don't run interrogation rounds
*   Don't gate on AskUserQuestion between steps — just work

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### 🧠 Thought Triggers (When to Log)
*   **Starting work?** → Log `▶️ Started` (goal and approach).
*   **Made progress?** → Log `🔧 Progress` (what changed and why).
*   **Made a choice?** → Log `💡 Decision` (why A over B).
*   **Blocked?** → Log `🚧 Block` (what's wrong, what you're trying).
*   **Done with something?** → Log `✅ Done` (summary and verification).
*   **Noticed something?** → Log `👁️ Side Discovery`.

**Constraint**: **BLIND WRITE**. Do not re-read the log file. See `§CMD_AVOID_WASTING_TOKENS`.

### Completion Signal
When a unit of work is done, present the work-phase gate via `AskUserQuestion` (multiSelect: false):
> "What next?"
> - **"Keep working"** — Stay in Phase 1. The session remains active for more tasks. Log the completed unit and continue.
> - **"Close session"** — Proceed to Phase 2: Synthesis. Write the debrief and deactivate.
> - **"Walkthrough changes"** — Review what was done so far, then re-present this gate.

If the user explicitly says "done", "that's it", "close", or similar — skip the gate and proceed directly to Phase 2.

**On "Keep working"**: Log a `✅ Done` entry for the completed unit, then remain in Phase 1. The agent waits for the user's next request. Repeat this gate after each subsequent unit of work.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 2. Synthesis
*Wrap up and create the debrief.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Debrief creation notes** (for Step 1 -- `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `DO.md`
*   Fill in every section from the template based on the work done.

**Walk-through config** (for Step 3 -- `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Work complete. Walk through the changes?"
  debriefFile: "DO.md"
  templateFile: "~/.claude/skills/do/assets/TEMPLATE_DO.md"
```

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---

## Rules of Engagement
*   **Helpful Over Rigid**: This is the lightweight skill. Be pragmatic. Don't fight the user over ceremony.
*   **Log Is Non-Negotiable**: The one thing you MUST do is log. Everything else is flexible.
*   **No Interrogation**: Ask questions naturally as part of the work, not via formal rounds.
*   **No Planning Phase**: Use the log for thinking. Don't create a separate plan artifact.
*   **Escalation Path**: If the work turns out to be complex (multi-file, needs TDD, architectural decisions), suggest switching to `/implement` via `§CMD_REFUSE_OFF_COURSE`.

### Next Skills (for §CMD_PARSE_PARAMETERS)
```json
["/do", "/implement", "/analyze", "/chores"]
```
