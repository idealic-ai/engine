---
name: debug
description: "Systematic diagnosis and repair of bugs, failures, and regressions — structured triage before action. Supports goal-based modes: Test Failures (systematic test diagnosis), Behavior (trace-driven runtime investigation), Performance (data-driven bottleneck analysis), Custom (user-defined lens). Triggers: \"debug this\", \"fix the tests\", \"investigate this failure\", \"why is this broken\", \"something isn't working right\", \"performance is degraded\"."
version: 3.0
---

Systematic diagnosis and repair of bugs, failures, and regressions — structured triage before action. Supports goal-based modes: Test Failures (systematic test diagnosis), Behavior (trace-driven runtime investigation), Performance (data-driven bottleneck analysis), Custom (user-defined lens).
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

# Debugging Protocol (The Detective's Code)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 3 (Triage) and Phase 4 (DEBUG_PLAN.md). The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Phases (for §CMD_PARSE_PARAMETERS)
*Include this array in the `phases` field when calling `session.sh activate`:*
```json
[
  {"major": 1, "minor": 0, "name": "Setup"},
  {"major": 2, "minor": 0, "name": "Context Ingestion"},
  {"major": 3, "minor": 0, "name": "Triage"},
  {"major": 4, "minor": 0, "name": "Planning"},
  {"major": 5, "minor": 0, "name": "Debug Loop"},
  {"major": 6, "minor": 0, "name": "Debrief"}
]
```
*Phase enforcement (¶INV_PHASE_ENFORCEMENT): transitions must be sequential. Use `--user-approved` for skip/backward.*

---

## Mode Presets

Debug modes configure the agent's lens — role, triage topics, and walk-through config. The mode is selected in Phase 1 Step 7.

### Test Failures (Default)
*Default mode. Systematic diagnosis of test suite failures.*

**Role**: You are the **Test Failure Analyst**.
**Goal**: To systematically diagnose why tests are failing, distinguish real regressions from test rot, and restore the suite to green.
**Mindset**: Methodical, Pattern-Matching, Root-Cause-Focused.

**Triage Topics** (Phase 3):
- **Error messages & stack traces** — exact failures, assertion mismatches, exception types
- **Mock/fixture setup** — missing mocks, stale fixtures, test doubles out of sync
- **Test environment & versions** — Node version, dependency changes, CI vs local differences
- **Assertion mismatches** — expected vs actual values, type coercion, floating point
- **Test isolation & ordering** — shared state, test ordering dependencies, cleanup failures
- **Import & dependency changes** — renamed modules, moved files, barrel export changes
- **CI vs local differences** — environment variables, OS differences, timing sensitivity
- **Flaky vs deterministic failures** — intermittent patterns, race conditions, timing

**Walk-Through Config** (Phase 6):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Debug complete. Walk through test failure findings?"
  debriefFile: "DEBUG.md"
  itemSources:
    - "## 4. Root Cause Analysis & Decisions"
    - "## 6. The \"Technical Debt\" Ledger"
    - "## 8. The \"Parking Lot\" (Unresolved)"
  actionMenu:
    - label: "Fix test"
      tag: "#needs-implementation"
      when: "Test expectations are wrong or outdated"
    - label: "Fix code"
      tag: "#needs-implementation"
      when: "Code has a real regression or bug"
    - label: "Add regression test"
      tag: "#needs-implementation"
      when: "Fix applied but lacks a regression test"
    - label: "Investigate deeper"
      tag: "#needs-research"
      when: "Root cause unclear, needs more investigation"
```

### Behavior
*Trace-driven investigation of incorrect runtime behavior.*

**Role**: You are the **Behavior Detective**.
**Goal**: To reproduce, isolate, and fix incorrect runtime behavior by tracing data flow from input to unexpected output.
**Mindset**: Curious, Trace-Driven, Hypothesis-Testing.

**Triage Topics** (Phase 3):
- **Expected vs observed behavior** — what should happen vs what actually happens
- **Reproduction steps & minimal repro** — smallest possible reproduction case
- **State flow & data transformations** — how data moves through the system, where it mutates
- **Input validation & edge cases** — boundary conditions, unexpected input types
- **Recent code changes & git blame** — what changed recently, who touched it
- **Environment-specific behavior** — works locally but fails in staging, OS differences
- **Silent failures & swallowed errors** — try/catch hiding real errors, empty catch blocks
- **Cross-module interactions** — boundary between modules, API contract violations

**Walk-Through Config** (Phase 6):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Debug complete. Walk through behavior findings?"
  debriefFile: "DEBUG.md"
  itemSources:
    - "## 4. Root Cause Analysis & Decisions"
    - "## 6. The \"Technical Debt\" Ledger"
    - "## 9. \"Btw, I also noticed...\" (Side Discoveries)"
  actionMenu:
    - label: "Implement fix"
      tag: "#needs-implementation"
      when: "Issue has a known fix that wasn't applied"
    - label: "Add regression test"
      tag: "#needs-implementation"
      when: "Fix applied but behavior change lacks test coverage"
    - label: "Research deeper"
      tag: "#needs-research"
      when: "Root cause is unclear or has broader implications"
    - label: "Document behavior"
      tag: "#needs-documentation"
      when: "Expected behavior was undocumented, causing confusion"
```

### Performance
*Data-driven diagnosis of performance bottlenecks.*

**Role**: You are the **Performance Engineer**.
**Goal**: To identify, measure, and eliminate performance bottlenecks using data-driven analysis.
**Mindset**: Quantitative, Profile-Driven, Skeptical of Assumptions.

**Triage Topics** (Phase 3):
- **Profiling data & metrics** — CPU profiles, flame graphs, timing data
- **Resource utilization (CPU/memory/IO)** — which resource is saturated
- **Bottleneck isolation & hotspots** — where time is actually spent
- **Algorithmic complexity** — O(n^2) loops, unnecessary iterations, inefficient data structures
- **Database query performance** — slow queries, missing indexes, N+1 problems
- **Network latency & payload sizes** — request waterfall, oversized payloads, chatty APIs
- **Caching effectiveness** — cache hit rates, stale cache, cache invalidation issues
- **Memory leaks & GC pressure** — heap growth, retained objects, GC pauses

**Walk-Through Config** (Phase 6):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Debug complete. Walk through performance findings?"
  debriefFile: "DEBUG.md"
  itemSources:
    - "## 4. Root Cause Analysis & Decisions"
    - "## 6. The \"Technical Debt\" Ledger"
    - "## 8. The \"Parking Lot\" (Unresolved)"
  actionMenu:
    - label: "Optimize now"
      tag: "#needs-implementation"
      when: "Bottleneck identified with clear optimization path"
    - label: "Add benchmark"
      tag: "#needs-implementation"
      when: "Performance regression risk — needs ongoing measurement"
    - label: "Profile deeper"
      tag: "#needs-research"
      when: "Bottleneck source unclear, needs more profiling data"
    - label: "Accept for now"
      tag: ""
      when: "Performance is acceptable, document as known limitation"
```

### Custom (User-Defined)
*User provides their own role/goal/mindset. Uses Test Failures' topic lists as defaults.*

**Role**: *Set from user's free-text input.*
**Goal**: *Set from user's free-text input.*
**Mindset**: *Set from user's free-text input.*

**Triage Topics**: Same as Test Failures mode.
**Walk-Through Config**: Same as Test Failures mode.

---

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is DEBUGGING (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Debug Mode** (Test Failures / Behavior / Performance / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/debug/assets/TEMPLATE_DEBUG_LOG.md` (Template for continuous debugging logging)
    *   `~/.claude/skills/debug/assets/TEMPLATE_DEBUG.md` (Template for final session debrief/report)
    *   `~/.claude/skills/debug/assets/TEMPLATE_DEBUG_PLAN.md` (Template for drafting the repair plan)
    *   `.claude/standards/TESTING.md` (Testing standards and diagnostics — project-level, load if exists)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.
    *   *Why?* To catch recent changes that might be the source of the bug.

6.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance.
    *   *Note*: Re-run discovery during Debrief to catch late arrivals.

7.  **Debug Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What type of issue are we debugging?"
    > - **"Test Failures" (Default)** — Test suite is red, tests are failing or flaky
    > - **"Behavior"** — Code runs but produces wrong results or unexpected behavior
    > - **"Performance"** — Slow responses, memory leaks, resource exhaustion
    > - **"Custom"** — Define your own role, goal, and mindset

    **On "Custom"**: The user types their framing. Parse it into role/goal/mindset. Use Test Failures' topic lists as defaults.

    **Record**: Store the selected mode. It configures:
    *   Phase 1 Step 8 role (from mode preset)
    *   Phase 3 triage topics (from mode preset)
    *   Phase 6 walk-through config (from mode preset)

8.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the Mode Presets section above.

9.  **Initial Evidence**: Capture initial state relevant to the diagnostic mode:
    *   **Test Failures**: Run the failing tests, capture output.
    *   **Behavior**: Reproduce the issue, document steps.
    *   **Performance**: Capture baseline metrics if available.
    *   **Custom**: Gather context relevant to the user's defined focus.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Mode: `________` (test-failures / behavior / performance / custom)
> - Role: `________` (quote the role name from the mode preset)
> - Session dir: `________`
> - Templates loaded: `________`, `________`, `________`
> - Parameters parsed: `________`
> - Initial evidence: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Context Ingestion"** — Load project files and RAG context
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Context Ingestion
*Load the raw materials before processing.*

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
> - **"Proceed to Phase 3: Triage"** — Classify failures before acting
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Planning"** — Failures are obvious, go straight to repair plan

---

## 3. The Triage (Interrogation)
*Classify issues before acting. Adapt triage topics to the diagnostic mode selected in Phase 1.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Triage.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to categorize failures into tiers.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` using `DEBUG_LOG.md` to record findings.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: First, ask the user to choose triage depth. Then execute rounds.

### Triage Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should triage go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Few failures, clear error messages, obvious root cause |
| **Medium** | 6+ | Multiple failures, some mysterious, need investigation |
| **Long** | 9+ | Large test suite failure, systemic issues, architectural concerns |
| **Absolute** | Until ALL questions resolved | Critical production bug, zero tolerance for misdiagnosis |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Nuanced Triage Criteria

*   **Tier 1: High-Confidence Fixes (The "Obvious")**
    *   **Setup Noise**: Missing mocks, syntax errors, obvious import path mismatches after a refactor.
    *   **Simple API Aliases**: A method was renamed (e.g., `start()` -> `play()`) and the logic is identical.
    *   **Configuration Drift**: Environment variables, feature flags, or config values that are stale or mismatched.
    *   **Known Patterns**: Issues matching a well-documented pattern with a known fix.
*   **Tier 2: Investigations (The "Mysterious")**
    *   **API Erosion**: A method is missing, and it's unclear if it was moved, deleted, or subsumed.
    *   **Logic Drift**: Expected behavior `A`, but observed behavior `B`. Check if expectations are outdated or if this is a regression.
    *   **Intermittent Failures**: Issues that appear under specific conditions (load, timing, state, environment).
    *   **Silent Failures**: The system appears to work but logs internal errors or produces "almost" correct data.
    *   **Cross-Layer Issues**: The symptom appears in one layer but the root cause is in another (e.g., error in API caused by database, performance issue caused by middleware).

### Rules of Thumb (The Detective's Intuition)
1.  **Don't Guess**: If you can't find the root cause in 2 targeted searches, it's Tier 2. Park it.
2.  **Context First**: If the issue references documentation, specs, or config, you **MUST** read those sources before attempting a fix.
3.  **Critique the Docs**: If documentation contradicts code or is too vague, log a `📖 Documentation Insight/Critique` entry immediately.
4.  **No "Hack-Fixes"**: Do not mask symptoms with workarounds (timeouts, retries, empty mocks) without understanding *why* the issue occurred.
5.  **The "Dog vs. Tail" Rule**: If a fix requires changing 5+ files to resolve one symptom, stop and ask for confirmation.
6.  **Batch & Conquer**: When investigating Tier 2 issues, look for "Failure Clusters" (multiple symptoms sharing the same root cause). Investigate the cluster as a unit.
7.  **Follow the Data**: For performance mode especially, let metrics and logs guide hypotheses — don't rely on code reading alone.

### Triage Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

### Triage Topics (Debug)
*Primary topic source: the **Triage Topics from the selected mode preset** (see Mode Presets section above). Use mode-specific topics as the primary investigation lens.*

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

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and hypotheses made so far
- **What-if scenarios** — Explore edge cases and failure modes
- **Deep dive** — Drill into a specific failure or hypothesis in detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Triage Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 4: Planning"** — *(terminal: if selected, skip all others and move on)*
> - **"More triage (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging hypotheses, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring failure modes, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a specific failure, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Triage depth: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`
> - Tier 1 count: `________`
> - Tier 2 count: `________`

---

## 4. The Phased Plan
**Draft a plan that separates noise from mystery.**

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Planning.
> 2. I will `§CMD_GENERATE_PLAN_FROM_TEMPLATE` using `DEBUG_PLAN.md`.
> 3. I will group investigations to save tokens.
> 4. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before starting repairs.

1.  **Draft Plan**: Execute `§CMD_GENERATE_PLAN_FROM_TEMPLATE`.
    *   **Phase 1**: Easy Fixes (Tier 1).
    *   **Phase 2**: Bulk Investigations (Tier 2).
    *   **Phase 3**: User Confirmation of Options.
    *   **Phase 4**: Final Execution.
2.  **Present**: Report the plan file via `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - DEBUG_PLAN.md written: `________`
> - Tier separation: `________`
> - User approved plan: `________`

### Optional: Plan Walk-Through
Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Investigation plan ready. Walk through the hypotheses?"
  debriefFile: "DEBUG_PLAN.md"
  itemSources:
    - "## 6. Step-by-Step Implementation Strategy"
  planQuestions:
    - "Does this hypothesis seem likely given what you know?"
    - "Any other signals or logs I should check?"
    - "Should I prioritize this step or skip it?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

### Phase Transition
Execute `§CMD_PARALLEL_HANDOFF` (from `~/.claude/standards/commands/CMD_PARALLEL_HANDOFF.md`):
1.  **Analyze**: Parse the plan's `**Depends**:` and `**Files**:` fields to derive parallel chunks.
2.  **Visualize**: Present the chunk breakdown with non-intersection proof.
3.  **Menu**: Present the richer handoff menu via `AskUserQuestion`.

*If the plan has no `**Depends**:` fields, fall back to the simple menu:*
> "Phase 4: Plan ready. How to proceed?"
> - **"Launch debugger agent"** — Hand off to autonomous agent for execution
> - **"Continue inline"** — Execute step by step in this conversation
> - **"Revise the plan"** — Go back and edit the plan before proceeding

---

## 4b. Agent Handoff (Opt-In)
*Only if user selected an agent option in Phase 4 transition.*

**Single agent** (no parallel chunks or user chose "1 agent"):
Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"debugger"`
*   `startAtPhase`: `"Phase 5: Debug Loop"`
*   `planOrDirective`: `[sessionDir]/DEBUG_PLAN.md`
*   `logFile`: `DEBUG_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/debug/assets/TEMPLATE_DEBUG.md`
*   `logTemplate`: `~/.claude/skills/debug/assets/TEMPLATE_DEBUG_LOG.md`
*   `taskSummary`: `"Debug: [brief description from taskSummary]"`

**Multiple agents** (user chose "[N] agents" or "Custom agent count"):
Execute `§CMD_PARALLEL_HANDOFF` Steps 5-6 with:
*   `agentName`: `"debugger"`
*   `planFile`: `[sessionDir]/DEBUG_PLAN.md`
*   `logFile`: `DEBUG_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/debug/assets/TEMPLATE_DEBUG.md`
*   `logTemplate`: `~/.claude/skills/debug/assets/TEMPLATE_DEBUG_LOG.md`
*   `taskSummary`: `"Debug: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 5 as normal.
**If "Revise the plan"**: Return to Phase 4 for revision.

---

## 5. The Debug Loop
*Execute in batches. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Debug Loop.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage the debug cycle.
> 3. I will resolve Tier 1 issues first, then investigate Tier 2.
> 4. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_DEBUG_LOG.md` EXACTLY) to `§CMD_THINK_IN_LOG`.
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
**Constraint**: **TIMESTAMPS**. Every log entry MUST start with `[YYYY-MM-DD HH:MM:SS]` in the header.

### Sub-Phase 5.1: Quick Wins (Tier 1)
1.  **Action**: Apply Tier 1 fixes.
2.  **Verify**: Run relevant verification (tests, reproduction steps, metrics).
3.  **Log**: Update `DEBUG_LOG.md`.
4.  **Park**: If a fix isn't straightforward, move it to Phase 5.2.

### Sub-Phase 5.2: Bulk Investigation (Tier 2)
1.  **Strategy**: Group related issues (Failure Clusters — multiple symptoms sharing root cause).
2.  **Doc Check**: Read any documents referenced in the issue, relevant spec files, or config.
3.  **Action**: Identify root causes for parked issues.
4.  **Log**:
    *   Use `🧪 Hypothesis` and `🔍 Discovery` entries.
    *   Use `💡 Decision` when choosing between investigation paths.
    *   Use `💸 Tech Debt` when discovering shortcuts or workarounds.
    *   Log `📖 Documentation Insight/Critique` if docs are confusing or missing.
    *   Do NOT apply complex fixes yet.

### Sub-Phase 5.3: User Confirmation (The Decision Point)
1.  **Action**: Present a report with **Options** for each investigated item.
2.  **Log**: Use `⚖️ Options` schema in `DEBUG_LOG.md`.
3.  **Choose**: Execute `AskUserQuestion` (multiSelect: false) for each item:
    > "Choose path for [item]:"
    > - **"Fix Code"** — The implementation has a bug, fix it
    > - **"Fix Test"** — The test expectations are wrong, update them
    > - **"Workaround"** — Apply a temporary mitigation with documented tech debt
    > - **"Further Investigation"** — Not enough info, dig deeper

### Sub-Phase 5.4: Final Execution
1.  **Action**: Apply the chosen options.
2.  **Verify**: Confirm resolution per the diagnostic mode's success criteria.
3.  **Loop**: If new issues arise or results are unclear, return to Sub-Phase 5.3.

### Rules of Engagement
*   **Don't Wage War**: Do not fix issues "at all costs". If it looks like "the tail wagging the dog", stop and ask.
*   **Token Thrift**: Group file reads and explorations. Don't investigate issue-by-issue if they share context.
*   **Stop the Bleeding**: If you spend >15 mins on one issue without a discovery, park it.
*   **Document Everything**: Every hypothesis, every dead end, every decision. The log is more valuable than the fix.

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Tier 1 fixes applied: `________`
> - Tier 2 investigations: `________`
> - User confirmed paths: `________`
> - Final fixes verified: `________`
> - DEBUG_LOG.md entries: `________`
> - Unresolved blockers: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 5: Debug loop complete. How to proceed?"
> - **"Proceed to Phase 6: Debrief"** — Generate debrief and close session
> - **"Stay in Phase 5"** — More fixes needed, continue debugging
> - **"Run full test suite"** — Verify everything before closing

---

## 6. The Debrief

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 6: Debrief.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_DEBUG.md` EXACTLY) to summarize the debug session.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The debrief FILE is the primary deliverable — chat output alone is not sufficient.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `DEBUG.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **The Story**: Narrate the diagnostic journey (§2 in template).
  *   **Deviation Analysis**: Compare Plan vs. Reality — where did we pivot? (§3 in template).
  *   **Root Cause Analysis**: Document the actual root causes found (§4 in template).
  *   **War Story**: The hardest moment of the investigation (§5 in template).
  *   **Tech Debt**: What shortcuts did we take or discover? (§6 in template).
  *   **System Health**: What did we learn about the system's overall health? (§7 in template).
  *   **Parking Lot**: What was parked or deferred (§8 in template).
  *   **Expert Opinion**: Your unfiltered assessment (§10 in template).

**Step 2**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 3**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 4**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 5**: Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** from the selected mode preset (see Mode Presets section above).

### §CMD_VERIFY_PHASE_EXIT — Phase 6 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 6 proof:**
> - DEBUG.md: `________` (real file path)
> - Tags: `________`
> - Artifacts listed: `________`
> - Summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 6**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Debug complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/test` (Recommended) | Bug fixed — add a regression test |
| 2 | `/implement` | Fix requires broader changes — implement them |
| 3 | `/analyze` | Root cause unclear — deeper analysis needed |
| 4 | `/document` | Document the fix and the root cause |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
