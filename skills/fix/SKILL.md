---
name: fix
description: "Systematic diagnosis and repair of bugs, failures, and regressions — structured triage before action, with two walk-throughs (issues + fixes). Supports goal-based modes: General (standard investigate-fix-verify), TDD (test-first discipline), Hotfix (abbreviated emergency), Custom (user-defined lens). Triggers: \"fix this\", \"fix the tests\", \"investigate this failure\", \"why is this broken\", \"something isn't working right\", \"performance is degraded\"."
version: 3.0
tier: protocol
---

Systematic diagnosis and repair of bugs, failures, and regressions — structured triage before action, with two walk-throughs (issues + fixes).

# Fix Protocol (The Fixer's Code)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "FIX",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed"], "gate": false},
    {"label": "1", "name": "Investigation",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION", "§CMD_APPEND_LOG"],
      "proof": ["depthChosen", "roundsCompleted"]},
    {"label": "2", "name": "Triage Walk-Through",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_GENERATE_PLAN", "§CMD_WALK_THROUGH_RESULTS"],
      "commands": ["§CMD_LINK_FILE"],
      "proof": ["planWritten", "issuesTriaged", "userApproved"]},
    {"label": "3", "name": "Execution",
      "steps": ["§CMD_SELECT_EXECUTION_PATH"],
      "commands": [],
      "proof": ["pathChosen", "pathsAvailable"], "gate": false},
    {"label": "3.A", "name": "Fix Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["fixesApplied", "testsPass", "logEntries", "unresolvedBlocks"]},
    {"label": "3.B", "name": "Agent Handoff",
      "steps": ["§CMD_HANDOFF_TO_AGENT"], "commands": [], "proof": []},
    {"label": "3.C", "name": "Parallel Agent Handoff",
      "steps": ["§CMD_PARALLEL_HANDOFF"], "commands": [], "proof": []},
    {"label": "4", "name": "Results Walk-Through",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_WALK_THROUGH_RESULTS"], "commands": [], "proof": ["resultsPresented", "userApproved"]},
    {"label": "5", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "5.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "5.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "5.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "5.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/test", "/implement", "/analyze", "/document", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md", "CHECKLIST.md"],
  "planTemplate": "assets/TEMPLATE_FIX_PLAN.md",
  "logTemplate": "assets/TEMPLATE_FIX_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_FIX.md",
  "requestTemplate": "assets/TEMPLATE_FIX_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_FIX_RESPONSE.md",
  "modes": {
    "general": {"label": "General", "description": "Standard investigate-fix-verify", "file": "modes/general.md"},
    "tdd": {"label": "TDD", "description": "Test-first discipline", "file": "modes/tdd.md"},
    "hotfix": {"label": "Hotfix", "description": "Emergency abbreviated", "file": "modes/hotfix.md"},
    "custom": {"label": "Custom", "description": "User-defined lens", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Fixing ___. Symptoms: ___. Trigger: ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the [Problem] and [Symptoms].

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Configuration.

**On "Custom"**: Read ALL 3 named mode files first (`modes/general.md`, `modes/tdd.md`, `modes/hotfix.md`) for context, then read `modes/custom.md`. The user types their framing. Parse it into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 investigation topics (from mode file)
*   Phase 2 & 4 walk-through configs (from mode file)

**Initial Evidence**: Capture initial state relevant to the fix mode:
*   **General**: Reproduce the issue, document symptoms.
*   **TDD**: Run the failing tests, capture output.
*   **Hotfix**: Capture current system state and impact.
*   **Custom**: Gather context relevant to the user's defined focus.

---

## 1. Investigation

§CMD_REPORT_INTENT:
> 1: Interrogating ___ assumptions before triaging fixes. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### Investigation Topics (Fix)
*Primary topic source: the **Triage Topics from the loaded mode file** (`modes/{mode}.md`). Use mode-specific topics as the primary investigation lens.*

*The standard topics below are available for ALL modes as supplementary investigation themes. Adapt to the task -- skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once, available in all modes):
- **Symptom characterization** -- exact error messages, stack traces, failure frequency
- **Reproduction steps** -- minimal repro, environment specifics, intermittent vs consistent
- **Environment & versions** -- Node version, dependency changes, OS differences, CI vs local
- **Recent changes** -- what changed recently, git blame suspects, deployment timeline
- **Blast radius** -- how many tests/features are affected, is this isolated or systemic
- **Logs & observability** -- relevant log output, monitoring data, debug traces available
- **Hypotheses** -- initial theories about root cause, rank by likelihood
- **Isolation strategy** -- how to narrow down the cause, bisection approach
- **Similar past bugs** -- has this pattern been seen before, related incidents
- **Rollback options** -- can we revert, what's the blast radius of rollback

### Nuanced Triage Criteria

*   **Tier 1: High-Confidence Fixes (The "Obvious")**
    *   **Setup Noise**: Missing mocks, syntax errors, obvious import path mismatches after a refactor.
    *   **Simple API Aliases**: A method was renamed and the logic is identical.
    *   **Configuration Drift**: Environment variables, feature flags, or config values that are stale or mismatched.
    *   **Known Patterns**: Issues matching a well-documented pattern with a known fix.
*   **Tier 2: Investigations (The "Mysterious")**
    *   **API Erosion**: A method is missing, and it's unclear if it was moved, deleted, or subsumed.
    *   **Logic Drift**: Expected behavior `A`, but observed behavior `B`. Check if expectations are outdated or if this is a regression.
    *   **Intermittent Failures**: Issues that appear under specific conditions.
    *   **Silent Failures**: The system appears to work but logs internal errors.
    *   **Cross-Layer Issues**: The symptom appears in one layer but the root cause is in another.

### Rules of Thumb (The Fixer's Intuition)
1.  **Don't Guess**: If you can't find the root cause in 2 targeted searches, it's Tier 2. Park it.
2.  **Context First**: If the issue references documentation, specs, or config, you **MUST** read those sources before attempting a fix.
3.  **Critique the Docs**: If documentation contradicts code or is too vague, log a Documentation Insight/Critique entry immediately.
4.  **No "Hack-Fixes"**: Do not mask symptoms with workarounds without understanding *why* the issue occurred.
5.  **The "Dog vs. Tail" Rule**: If a fix requires changing 5+ files to resolve one symptom, stop and ask for confirmation.
6.  **Batch & Conquer**: Look for "Failure Clusters" (multiple symptoms sharing the same root cause). Investigate the cluster as a unit.
7.  **Follow the Data**: Let metrics and logs guide hypotheses -- don't rely on code reading alone.

---

## 2. Triage Walk-Through
*User reviews and approves what to fix before any code changes.*

§CMD_REPORT_INTENT:
> 2: Presenting ___ investigated issues for triage. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Plan structure** (for `FIX_PLAN.md`):
*   **Phase 1**: Easy Fixes (Tier 1).
*   **Phase 2**: Bulk Investigations (Tier 2).
*   **Phase 3**: User Confirmation of Options.
*   **Phase 4**: Final Execution.

**Walk-through** (from loaded mode file):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Triage complete. Walk through the issues before fixing?"
  debriefFile: "FIX_PLAN.md"
  planQuestions:
    - "Is this the right tier (Tier 1 vs Tier 2) for this issue?"
    - "Should we fix this now, defer it, or investigate further?"
    - "Any dependencies or risks I'm missing?"
```

If any items are flagged for revision, update the plan before proceeding.

---

## 3. Execution
*Gateway: select execution path before entering a branch.*

§CMD_REPORT_INTENT:
> 3: Selecting execution path for ___ fixes. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

---

## 3.A. Fix Loop
*Execute repairs. Resolve Tier 1 first, then investigate Tier 2.*

§CMD_REPORT_INTENT:
> 3.A: Executing ___-issue fix plan. Target: ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.A.*)

### Sub-Phase: Quick Wins (Tier 1)
1.  **Action**: Apply Tier 1 fixes.
2.  **Verify**: Run relevant verification (tests, reproduction steps, metrics).
3.  **Log**: Update `FIX_LOG.md`.
4.  **Park**: If a fix isn't straightforward, move it to Tier 2.

### Sub-Phase: Bulk Investigation (Tier 2)
1.  **Strategy**: Group related issues (Failure Clusters -- multiple symptoms sharing root cause).
2.  **Doc Check**: Read any documents referenced in the issue.
3.  **Action**: Identify root causes for parked issues.

### Sub-Phase: User Confirmation (The Decision Point)
1.  **Action**: Present a report with **Options** for each investigated item.
2.  **Choose**: Execute `AskUserQuestion` (multiSelect: false) for each item:
    > "Choose path for [item]:"
    > - **"Fix Code"** -- The implementation has a bug, fix it
    > - **"Fix Test"** -- The test expectations are wrong, update them
    > - **"Workaround"** -- Apply a temporary mitigation with documented tech debt
    > - **"Further Investigation"** -- Not enough info, dig deeper

### Sub-Phase: Final Execution
1.  **Action**: Apply the chosen options.
2.  **Verify**: Confirm resolution per the fix mode's success criteria.
3.  **Loop**: If new issues arise or results are unclear, return to User Confirmation.

### Rules of Engagement
*   **Don't Wage War**: Do not fix issues "at all costs". If it looks like "the tail wagging the dog", stop and ask.
*   **Token Thrift**: Group file reads and explorations. Don't investigate issue-by-issue if they share context.
*   **Stop the Bleeding**: If you spend >15 mins on one issue without a discovery, park it.
*   **Document Everything**: Every hypothesis, every dead end, every decision. The log is more valuable than the fix.

---

## 3.B. Agent Handoff
*Hand off to a single autonomous agent.*

§CMD_EXECUTE_PHASE_STEPS(3.B.*)

§CMD_HANDOFF_TO_AGENT with:
```json
{
  "agentName": "debugger",
  "startAtPhase": "3.A: Fix Loop",
  "planOrDirective": "[sessionDir]/FIX_PLAN.md",
  "logFile": "FIX_LOG.md",
  "taskSummary": "Fix: [brief description from taskSummary]"
}
```

---

## 3.C. Parallel Agent Handoff
*Hand off to multiple agents working in parallel on independent plan chunks.*

§CMD_EXECUTE_PHASE_STEPS(3.C.*)

§CMD_PARALLEL_HANDOFF with:
```json
{
  "agentName": "debugger",
  "planFile": "[sessionDir]/FIX_PLAN.md",
  "logFile": "FIX_LOG.md",
  "taskSummary": "Fix: [brief description from taskSummary]"
}
```

---

## 4. Results Walk-Through
*User reviews all applied fixes before synthesis.*

§CMD_REPORT_INTENT:
> 4: Presenting ___ applied fixes for review. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(4.0.*)

**Walk-through** (from loaded mode file):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Fixes applied. Walk through the changes?"
  debriefFile: "FIX_LOG.md"
```

---

## 5. Synthesis
*When all fixes are applied and verified.*

§CMD_REPORT_INTENT:
> 5: Synthesizing. ___ fixes applied, ___ tests passing.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(5.0.*)

**Debrief notes** (for `FIX.md`):
*   **The Story**: Narrate the diagnostic journey.
*   **Deviation Analysis**: Compare Plan vs. Reality -- where did we pivot?
*   **Root Cause Analysis**: Document the actual root causes found.
*   **War Story**: The hardest moment of the investigation.
*   **Tech Debt**: What shortcuts did we take or discover?
*   **System Health**: What did we learn about the system's overall health?
*   **Parking Lot**: What was parked or deferred.
*   **Expert Opinion**: Your unfiltered assessment.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Fixes complete. Walk through the changes?"
  debriefFile: "FIX.md"
```
