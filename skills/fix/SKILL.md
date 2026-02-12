---
name: fix
description: "Systematic diagnosis and repair of bugs, failures, and regressions — structured triage before action, with two walk-throughs (issues + fixes). Supports goal-based modes: General (standard investigate-fix-verify), TDD (test-first discipline), Hotfix (abbreviated emergency), Custom (user-defined lens). Triggers: \"fix this\", \"fix the tests\", \"investigate this failure\", \"why is this broken\", \"something isn't working right\", \"performance is degraded\"."
version: 1.0
tier: protocol
---

Systematic diagnosis and repair of bugs, failures, and regressions — structured triage before action, with two walk-throughs (issues + fixes).

# Fix Protocol (The Fixer's Code)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 2 (Investigation) and Phase 3 (Triage Walk-Through). The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "FIX",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "templates_loaded", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Context Ingestion", "proof": ["context_sources_presented", "files_loaded"]},
    {"major": 2, "minor": 0, "name": "Investigation", "proof": ["depth_chosen", "rounds_completed"]},
    {"major": 3, "minor": 0, "name": "Triage Walk-Through", "proof": ["plan_written", "issues_triaged", "user_approved"]},
    {"major": 4, "minor": 0, "name": "Fix Loop", "proof": ["fixes_applied", "tests_pass", "log_entries", "unresolved_blocks"]},
    {"major": 4, "minor": 1, "name": "Agent Handoff"},
    {"major": 5, "minor": 0, "name": "Results Walk-Through", "proof": ["results_presented", "user_approved"]},
    {"major": 6, "minor": 0, "name": "Synthesis"},
    {"major": 6, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 6, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 6, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 6, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/test", "/implement", "/analyze", "/document", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"],
  "modes": {
    "general": {"label": "General", "description": "Standard investigate-fix-verify", "file": "~/.claude/skills/fix/modes/general.md"},
    "tdd": {"label": "TDD", "description": "Test-first discipline", "file": "~/.claude/skills/fix/modes/tdd.md"},
    "hotfix": {"label": "Hotfix", "description": "Emergency abbreviated", "file": "~/.claude/skills/fix/modes/hotfix.md"},
    "custom": {"label": "Custom", "description": "User-defined lens", "file": "~/.claude/skills/fix/modes/custom.md"}
  }
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is FIXING (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_PARSE_PARAMETERS` to activate the session and discover context (alerts, delegations, RAG).
    > 5. I will select the **Fix Mode** (General / TDD / Hotfix / Custom).
    > 6. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 7. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — constructs the session parameters JSON and pipes it to `session.sh activate` via heredoc.
    *   activate creates the session directory, stores parameters in `.state.json`, and returns context:
        *   `## Active Alerts` — files with `#active-alert` (add relevant ones to `contextPaths` for Phase 1)
        *   `## RAG Suggestions` — semantic search results from session-search and doc-search (add relevant ones to `contextPaths`)
    *   **No JSON chat output** — parameters are stored by activate, not echoed to chat.

4.  **Scope**: Understand the [Problem] and [Symptoms].

5.  **Process Context**: Parse activate's output for alerts and RAG suggestions. Add relevant items to `contextPaths` for ingestion in Phase 1.

6.  **Fix Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What type of fix approach should I use?"
    > - **"General" (Recommended)** — Standard investigate → triage → fix → verify
    > - **"TDD"** — Test-first: write failing test that reproduces the bug, then fix until green
    > - **"Hotfix"** — Emergency: shortest path to stable, abbreviated triage
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file.
    **On "Custom"**: Read ALL 3 named mode files first (`modes/general.md`, `modes/tdd.md`, `modes/hotfix.md`) for context, then read `modes/custom.md`. The user types their framing. Parse it into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 role (from mode file)
    *   Phase 2 investigation topics (from mode file)
    *   Phase 3 & 5 walk-through configs (from mode file)

7.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

8.  **Initial Evidence**: Capture initial state relevant to the fix mode:
    *   **General**: Reproduce the issue, document symptoms.
    *   **TDD**: Run the failing tests, capture output.
    *   **Hotfix**: Capture current system state and impact.
    *   **Custom**: Gather context relevant to the user's defined focus.

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Context Ingestion
*Load the raw materials before processing.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Skip to 4: Fix Loop | Issues are obvious, go straight to fixing"

---

## 2. The Investigation (Interrogation)
*Classify issues before acting. Adapt investigation topics to the fix mode selected in Phase 0.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Investigation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to categorize issues into tiers.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` using `FIX_LOG.md` to record findings.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` with topics from the loaded mode file.

### Investigation Topics (Fix)
*Primary topic source: the **Triage Topics from the loaded mode file** (`modes/{mode}.md`). Use mode-specific topics as the primary investigation lens.*

*The standard topics below are available for ALL modes as supplementary investigation themes. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once, available in all modes):
- **Symptom characterization** — exact error messages, stack traces, failure frequency
- **Reproduction steps** — minimal repro, environment specifics, intermittent vs consistent
- **Environment & versions** — Node version, dependency changes, OS differences, CI vs local
- **Recent changes** — what changed recently, git blame suspects, deployment timeline
- **Blast radius** — how many tests/features are affected, is this isolated or systemic
- **Logs & observability** — relevant log output, monitoring data, debug traces available
- **Hypotheses** — initial theories about root cause, rank by likelihood
- **Isolation strategy** — how to narrow down the cause, bisection approach
- **Similar past bugs** — has this pattern been seen before, related incidents
- **Rollback options** — can we revert, what's the blast radius of rollback

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
3.  **Critique the Docs**: If documentation contradicts code or is too vague, log a `📖 Documentation Insight/Critique` entry immediately.
4.  **No "Hack-Fixes"**: Do not mask symptoms with workarounds without understanding *why* the issue occurred.
5.  **The "Dog vs. Tail" Rule**: If a fix requires changing 5+ files to resolve one symptom, stop and ask for confirmation.
6.  **Batch & Conquer**: Look for "Failure Clusters" (multiple symptoms sharing the same root cause). Investigate the cluster as a unit.
7.  **Follow the Data**: Let metrics and logs guide hypotheses — don't rely on code reading alone.

---

## 3. Triage Walk-Through
*User reviews and approves what to fix before any code changes.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Triage Walk-Through.
> 2. I will present all investigated issues for user approval.
> 3. The user decides what to fix, what to defer, what to investigate further.

**Action**: Draft the repair plan, then walk through the issues.

1.  **Draft Plan**: Execute `§CMD_GENERATE_PLAN_FROM_TEMPLATE` using `FIX_PLAN.md`.
    *   **Phase 1**: Easy Fixes (Tier 1).
    *   **Phase 2**: Bulk Investigations (Tier 2).
    *   **Phase 3**: User Confirmation of Options.
    *   **Phase 4**: Final Execution.
2.  **Present**: Report the plan file via `§CMD_REPORT_FILE_CREATION_SILENTLY`.
3.  **Walk Through Issues**: Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config (Phase 3 — Triage)** from the loaded mode file.

If any items are flagged for revision, update the plan before proceeding.

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/.directives/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 3: Plan approved. How to proceed?"
> - **"Launch fixer agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 4. The Fix Loop
*Execute repairs. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Fix Loop.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage the fix cycle.
> 3. I will resolve Tier 1 issues first, then investigate Tier 2.
> 5. I will log decisions (`💡`) and tech debt (`💸`) as I encounter them.
> 6. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

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

*   **Observed a Bug?** -> Log `🐞 Symptom` (Test/Repro, Expected vs Observed).
*   **Have a Theory?** -> Log `🧪 Hypothesis` (Suspect, Theory, Confidence).
*   **Trying a Fix?** -> Log `🛠️ Fix Attempt` (Strategy, Files, Diff).
*   **Fix Worked?** -> Log `✅ Verification` (Test Run, Outcome).
*   **Fix Failed?** -> Log `❌ Failure` (Error, Refutation, New Direction).
*   **Found Root Cause?** -> Log `🔍 Discovery` (Component, Findings, Reference).
*   **Stuck?** -> Log `🚧 Blocker` (Obstacle, Needs).
*   **Made a Choice?** -> Log `💡 Decision` (Topic, Choice, Reasoning, Trade-off).
*   **Found Debt?** -> Log `💸 Tech Debt` (Item, Why, Risk, Payoff Plan).
*   **Docs Wrong?** -> Log `📖 Documentation Insight/Critique` (Doc Path, Insight, Complaint).

**Constraint**: **BLIND WRITE**. Do not re-read the log file. See `§CMD_AVOID_WASTING_TOKENS`.

### Sub-Phase 4.1: Quick Wins (Tier 1)
1.  **Action**: Apply Tier 1 fixes.
2.  **Verify**: Run relevant verification (tests, reproduction steps, metrics).
3.  **Log**: Update `FIX_LOG.md`.
4.  **Park**: If a fix isn't straightforward, move it to Phase 4.2.

### Sub-Phase 4.2: Bulk Investigation (Tier 2)
1.  **Strategy**: Group related issues (Failure Clusters — multiple symptoms sharing root cause).
2.  **Doc Check**: Read any documents referenced in the issue.
3.  **Action**: Identify root causes for parked issues.
4.  **Log**: Use `🧪 Hypothesis` and `🔍 Discovery` entries.

### Sub-Phase 4.3: User Confirmation (The Decision Point)
1.  **Action**: Present a report with **Options** for each investigated item.
2.  **Log**: Use `⚖️ Options` schema in `FIX_LOG.md`.
3.  **Choose**: Execute `AskUserQuestion` (multiSelect: false) for each item:
    > "Choose path for [item]:"
    > - **"Fix Code"** — The implementation has a bug, fix it
    > - **"Fix Test"** — The test expectations are wrong, update them
    > - **"Workaround"** — Apply a temporary mitigation with documented tech debt
    > - **"Further Investigation"** — Not enough info, dig deeper

### Sub-Phase 4.4: Final Execution
1.  **Action**: Apply the chosen options.
2.  **Verify**: Confirm resolution per the fix mode's success criteria.
3.  **Loop**: If new issues arise or results are unclear, return to Sub-Phase 4.3.

### Rules of Engagement
*   **Don't Wage War**: Do not fix issues "at all costs". If it looks like "the tail wagging the dog", stop and ask.
*   **Token Thrift**: Group file reads and explorations. Don't investigate issue-by-issue if they share context.
*   **Stop the Bleeding**: If you spend >15 mins on one issue without a discovery, park it.
*   **Document Everything**: Every hypothesis, every dead end, every decision. The log is more valuable than the fix.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 4.1. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 3 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"debugger"`
*   `startAtPhase`: `"Phase 4: Fix Loop"`
*   `planOrDirective`: `[sessionDir]/FIX_PLAN.md`
*   `logFile`: `FIX_LOG.md`
*   `taskSummary`: `"Fix: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"debugger"`
*   `planFile`: `[sessionDir]/FIX_PLAN.md`
*   `logFile`: `FIX_LOG.md`
*   `taskSummary`: `"Fix: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 4 as normal.
**If "Revise the plan"**: Return to Phase 3 for revision.

---

## 5. Results Walk-Through
*User reviews all applied fixes before debrief.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Results Walk-Through.
> 2. I will present all changes for user review.
> 3. The user can accept, revise, or tag fixes for follow-up.

**Action**: Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config (Phase 5 — Results)** from the loaded mode file.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 6. The Synthesis (Debrief)
*When all fixes are applied and verified.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 6: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Debrief creation notes** (for Step 1 — `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `FIX.md`
*   Write the file using the Write tool. This MUST produce a real file in the session directory.
*   **The Story**: Narrate the diagnostic journey (§2 in template).
*   **Deviation Analysis**: Compare Plan vs. Reality — where did we pivot? (§3 in template).
*   **Root Cause Analysis**: Document the actual root causes found (§4 in template).
*   **War Story**: The hardest moment of the investigation (§5 in template).
*   **Tech Debt**: What shortcuts did we take or discover? (§6 in template).
*   **System Health**: What did we learn about the system's overall health? (§7 in template).
*   **Parking Lot**: What was parked or deferred (§8 in template).
*   **Expert Opinion**: Your unfiltered assessment (§10 in template).

**Walk-through config** (for Step 3 — `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Fixes complete. Walk through the changes?"
  debriefFile: "FIX.md"
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
