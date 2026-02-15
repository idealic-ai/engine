---
name: improve-protocol
description: "Analyzes transcripts, session artifacts, or feedback to identify and apply protocol improvements across commands, directives, phases, and skills. Triggers: \"improve the protocol\", \"analyze this session for improvements\", \"protocol audit\", \"fix the wording in\", \"improve this command\"."
version: 2.0
tier: protocol
---

Analyzes transcripts, session artifacts, or feedback to identify and apply protocol improvements across commands, directives, phases, and skills.

# Protocol Improvement (The Protocol Doctor)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "PROTOCOL_IMPROVEMENT",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed"]},
    {"label": "1", "name": "Analysis Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["logEntries", "findingsCount", "filesAnalyzed"]},
    {"label": "2", "name": "Calibration",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depthChosen", "roundsCompleted"]},
    {"label": "3", "name": "Apply",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS"],
      "proof": ["findingsPresented", "editsApplied", "editsSkipped"]},
    {"label": "4", "name": "Test Loop",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_DESIGN_E2E_TEST"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["testsDesigned", "testsPassed", "testsFailed", "testsSkipped"]},
    {"label": "5", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": []},
    {"label": "5.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": []},
    {"label": "5.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"]},
    {"label": "5.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": []},
    {"label": "5.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": []}
  ],
  "nextSkills": ["/implement", "/analyze", "/edit-skill", "/chores"],
  "directives": ["PITFALLS.md", "CONTRIBUTING.md"],
  "logTemplate": "assets/TEMPLATE_PROTOCOL_IMPROVEMENT_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_PROTOCOL_IMPROVEMENT.md",
  "modes": {
    "audit": {"label": "Audit", "description": "Find violations, skipped steps, broken patterns", "file": "modes/audit.md"},
    "improve": {"label": "Improve", "description": "Enhance clarity, reduce ambiguity, better wording", "file": "modes/improve.md"},
    "refactor": {"label": "Refactor", "description": "Restructure commands, merge/split phases, reorganize", "file": "modes/refactor.md"},
    "custom": {"label": "Custom", "description": "User-defined blend of modes", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT`:
> 0: Improving protocol based on ___. Input type: ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(0.0.*)`

*   **Scope**: Understand the input (session ID, transcript, or feedback) and goal.

### Input Detection

Parse the user's arguments to determine input type:

| Pattern | Input Type | Action |
|---------|-----------|--------|
| `sessions/YYYY_MM_DD_*` or session path | **Session ID** | Load session artifacts (LOG, DETAILS, DEBRIEF, PLAN) |
| Large text block or "transcript:" prefix | **Transcript** | Parse for behavioral patterns |
| Short description or feedback text | **Feedback** | Capture as improvement directive |
| Mixed (session ID + feedback) | **Session + Feedback** | Load artifacts AND apply feedback lens |

**For Session ID input**:
1.  Verify the session directory exists.
2.  List available artifacts: `ls sessions/[DIR]/`
3.  Queue artifacts for Phase 1 ingestion.

**For Transcript input**:
1.  Accept the pasted text.
2.  Queue for Phase 1 parsing.

**For Feedback input**:
1.  Capture the feedback text.
2.  Identify mentioned files/commands if any.
3.  Queue for targeted analysis in Phase 1.

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, Analysis Focus, and Calibration Topics.

**On "Custom"**: Read ALL 3 named mode files first (`modes/audit.md`, `modes/improve.md`, `modes/refactor.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 analysis focus (from mode file)
*   Phase 2 calibration topics (from mode file)

### Phase Transition
Execute `§CMD_GATE_PHASE`

---

## 1. Analysis Loop (Autonomous Deep Dive)
*Do not wait for permission. Analyze the input immediately.*

`§CMD_REPORT_INTENT`:
> 1: Analyzing ___ for protocol improvements. Mode: ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(1.0.*)`

### A. Input Processing

**Session ID**: Read the session's artifacts in order:
1.  `*_LOG.md` -- The raw work stream. Look for friction, repeated blocks, skipped steps.
2.  `DETAILS.md` -- Q&A interactions. Look for misunderstandings, unclear questions.
3.  `*_PLAN.md` -- If present. Check plan quality, step clarity.
4.  Debrief (`*.md` matching debrief template) -- Check completeness, quality.

**Transcript**: Parse the conversation for:
1.  Behavioral anti-patterns (narration, skipped phases, tool misuse).
2.  Protocol violations (missing logs, no between-rounds context, bare tags).
3.  Communication issues (unclear questions, missed user intent).

**Feedback**: Map feedback to affected protocol files:
1.  Identify mentioned commands (`§CMD_*`), invariants (`¶INV_*`), skills.
2.  Read the referenced files.
3.  Analyze the feedback in context.

### B. Pattern Library (Known Anti-Patterns)

Apply these checks based on the mode's focus:

**Behavioral Patterns**:
- Agent narrated micro-steps in chat (violated `§CMD_NO_MICRO_NARRATION`)
- Agent skipped protocol phases without `§CMD_REFUSE_OFF_COURSE`
- Missing between-rounds context in interrogation
- No `§CMD_APPEND_LOG` between tool uses (heartbeat violations)
- Agent self-authorized phase skips (violated `¶INV_USER_APPROVED_REQUIRES_TOOL`)
- Agent output plain text file paths instead of clickable URLs (violated `¶INV_TERMINAL_FILE_LINKS`)
- Bare tags in body text (violated `¶INV_ESCAPE_BY_DEFAULT`)

**Clarity Patterns**:
- Ambiguous command wording (could be interpreted multiple ways)
- Missing examples in command definitions
- Unclear proof field descriptions
- Inconsistent terminology across commands
- Overly long command definitions (could be split)

**Structural Patterns**:
- Redundant logic across commands
- Missing `§CMD_*` extraction (inline prose that should be a command)
- Phase ordering issues
- Proof field drift (proof doesn't match what command actually produces)
- Dead references (commands/invariants referenced but not defined)

### C. Open Exploration

Beyond the pattern library, freely explore:
- Read the actual protocol files referenced in findings.
- Cross-reference related commands for consistency.
- Check if similar patterns exist in other skills.
- Look for missing error handling or edge cases.

### D. Logging (The Analysis Notebook)

For *every* finding, execute `§CMD_APPEND_LOG` to `PROTOCOL_IMPROVEMENT_LOG.md`.

**Cadence**: Log at least **5 findings** before moving to Calibration.

### Phase Transition
Execute `§CMD_GATE_PHASE`:
  custom: "Skip to Phase 3: Apply | Findings are clear, ready to propose changes"

---

## 2. Calibration (Interactive)
*Present findings to the user and align on priorities.*

`§CMD_REPORT_INTENT`:
> 2: Calibrating with ___ findings logged. ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(2.0.*)`

### Findings Summary

Before interrogation, present a summary:
> **Findings so far**: N total
> - **Violations**: N (clear protocol violations)
> - **Clarity issues**: N (ambiguous wording, missing examples)
> - **Structural issues**: N (redundancy, missing extractions)
> - **Suggestions**: N (improvement ideas)
>
> **Files affected**: [list of protocol files]

### Interrogation Topics

**Standard topics** (consumed by `§CMD_INTERROGATE`):
- **Priority triage** -- Which findings matter most? What to fix first?
- **Scope confirmation** -- Are all findings in scope, or should some be deferred?
- **Wording review** -- For clarity fixes, does the proposed wording sound right?
- **Structural decisions** -- For refactoring proposals, confirm the restructuring approach
- **Risk assessment** -- Could any proposed change break existing behavior?

### Phase Transition
Execute `§CMD_GATE_PHASE`

---

## 3. Apply (Grouped-by-File Edit Proposals)
*Present findings grouped by file and offer edits with user approval.*

`§CMD_REPORT_INTENT`:
> 3: Applying ___ approved findings across ___ files. ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(3.0.*)`

### Apply Protocol

For each affected protocol file (grouped):

1.  **Present the file group** (file paths per `¶INV_TERMINAL_FILE_LINKS`):
    > **File**: cursor://file/ABSOLUTE_PATH — N changes proposed
    >
    > | # | Type | Finding | Granularity |
    > |---|------|---------|-------------|
    > | 1 | Clarity | [summary] | Surgical |
    > | 2 | Structural | [summary] | Directional |

2.  **For each finding in the group**:
    *   **Surgical** (clear-cut): Show exact old text -> new text diff.
    *   **Directional** (investigative): Show the section, describe the problem, propose approach.

3.  **Ask per group** via `AskUserQuestion` (multiSelect: true):
    > "Changes for `[file]` -- which to apply?"
    > - Finding 1: [summary]
    > - Finding 2: [summary]
    > - "Skip all for this file"

4.  **Apply approved edits**: Use the Edit tool for surgical changes. For directional changes, write the improvement inline.

5.  **Log**: `§CMD_APPEND_LOG` after each file group is processed.

### Phase Transition
Execute `§CMD_GATE_PHASE`

---

## 4. Test Loop (Autonomous Verification)
*Verify applied changes by designing and running e2e reproduction tests in a sandbox.*

`§CMD_REPORT_INTENT`:
> 4: Testing ___ applied findings. Designing reproduction cases in sandbox.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(4.0.*)`

### Test Execution

Execute `§CMD_DESIGN_E2E_TEST` (which handles its own testability assessment and user confirmation gate — no separate entry gate needed here).

**On test failure**: Offer to loop back to Phase 3: Apply to address the issue, or continue to synthesis with the failure noted.

**On test failure**: Offer to loop back to Phase 3: Apply to address the issue, or continue to synthesis with the failure noted.

### Phase Transition
Execute `§CMD_GATE_PHASE`

---

## 5. Synthesis
*When all findings are processed and verified.*

`§CMD_REPORT_INTENT`:
> 5: Synthesizing. ___ findings processed, ___ applied, ___ tested.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(5.0.*)`

**Debrief notes** (for `PROTOCOL_IMPROVEMENT.md`):
*   **Input Summary**: What was analyzed (session, transcript, or feedback).
*   **Findings Overview**: Total findings by category.
*   **Changes Applied**: What was changed and why.
*   **Changes Skipped**: What was skipped and why.
*   **Impact Assessment**: How the changes improve protocol clarity/correctness.
*   **Remaining Work**: Directional findings that need follow-up.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Protocol improvement complete. Walk through the changes?"
  debriefFile: "PROTOCOL_IMPROVEMENT.md"
```
