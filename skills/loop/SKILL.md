---
name: loop
description: "Hypothesis-driven iteration engine for LLM workloads — runs cycles of hypothesize, execute, review, analyze, decide, edit. Triggers: \"iterate on this\", \"run a loop\", \"hypothesis-driven refinement\", \"improve the prompt\", \"tune the model\"."
version: 2.0
tier: protocol
---

Hypothesis-driven iteration engine for any LLM workload.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# Loop Protocol (The Iteration Engine)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 1 (Interrogation / Manifest Creation) and Phase 2 (Experiment Design). The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

ARGUMENTS: Accepts optional flags:
- `--manifest <path>`: Use existing manifest instead of interrogation
- `--plan <path>`: Skip planning, use existing LOOP_PLAN.md
- `--case <path>`: Focus on a single case instead of running all cases
- `--continue`: Resume from last iteration in current session directory

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "CHANGESET",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "templates_loaded", "parameters_parsed", "flags_parsed", "routing"]},
    {"major": 1, "minor": 0, "name": "Interrogation", "proof": ["depth_chosen", "rounds_completed", "manifest_validated"]},
    {"major": 2, "minor": 0, "name": "Planning", "proof": ["failure_context", "hypotheses_ranked", "experiments_designed", "cases_selected", "success_criteria", "plan_written", "user_approved"]},
    {"major": 3, "minor": 0, "name": "Calibration", "proof": ["test_fixture", "pipeline_result", "manifest_saved", "calibration_logged"]},
    {"major": 4, "minor": 0, "name": "Baseline", "proof": ["cases_executed", "baseline_metrics", "baseline_presented", "user_approved"]},
    {"major": 5, "minor": 0, "name": "Iteration Loop", "proof": ["iterations_completed", "log_entries", "exit_condition"]},
    {"major": 6, "minor": 0, "name": "Synthesis"},
    {"major": 6, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 6, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 6, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 6, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/loop", "/test", "/implement", "/analyze", "/chores"],
  "directives": ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md"],
  "planTemplate": "~/.claude/skills/loop/assets/TEMPLATE_LOOP_PLAN.md",
  "logTemplate": "~/.claude/skills/loop/assets/TEMPLATE_LOOP_LOG.md",
  "debriefTemplate": "~/.claude/skills/loop/assets/TEMPLATE_LOOP.md",
  "requestTemplate": "~/.claude/skills/loop/assets/TEMPLATE_LOOP_REQUEST.md",
  "responseTemplate": "~/.claude/skills/loop/assets/TEMPLATE_LOOP_RESPONSE.md",
  "modes": {
    "precision": {"label": "Precision", "description": "Surgical iteration, isolate variables", "file": "~/.claude/skills/loop/modes/precision.md"},
    "exploration": {"label": "Exploration", "description": "Bold changes, seek breakthroughs", "file": "~/.claude/skills/loop/modes/exploration.md"},
    "convergence": {"label": "Convergence", "description": "Tighten tolerances, harden edges", "file": "~/.claude/skills/loop/modes/convergence.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "~/.claude/skills/loop/modes/custom.md"}
  }
}
```

### Next Skills (for §CMD_PARSE_PARAMETERS)
```
/loop, /test, /implement, /analyze, /chores
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is ITERATION (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_PARSE_PARAMETERS` to activate the session and discover context.
    > 6. I will select the **Loop Mode** (Precision / Exploration / Convergence / Custom).
    > 7. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/loop/assets/MANIFEST_SCHEMA.json` (Schema for workload manifest)
    *   `~/.claude/skills/loop/assets/COMPOSER_PROMPT.md` (Composer subagent prompt template)
    *   `.claude/.directives/PITFALLS.md` (Known pitfalls and gotchas — project-level, load if exists)

3.  **Parse Arguments**: Check for flags in the user's command:
    *   `--manifest <path>`: Skip interrogation, use existing manifest
    *   `--plan <path>`: Skip planning, use existing LOOP_PLAN.md
    *   `--case <path>`: Focus on a single case instead of running all cases
    *   `--continue`: Resume from last iteration in current session

4.  **Parse Parameters**: Execute `§CMD_PARSE_PARAMETERS`.

5.  **Process Context**: Parse activate's output for alerts and RAG suggestions. Add relevant items to `contextPaths` for ingestion in Phase 1.

5.1. **Loop Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What iteration strategy should I use?"
    > - **"Precision" (Recommended)** — Surgical fixes: isolate one variable per iteration, minimize blast radius
    > - **"Exploration"** — Bold changes: tolerate regressions, seek breakthroughs and paradigm shifts
    > - **"Convergence"** — Tighten tolerances: harden edge cases, close remaining gaps
    > - **"Custom"** — Define your own iteration strategy

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Configuration.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/precision.md`, `modes/exploration.md`, `modes/convergence.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 role (from mode file)
    *   Phase 5 iteration focus, hypothesis style, and success metric (from mode file)

5.2. **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

6.  **Resume Check**: Does `--continue` flag exist?
    *   **If Yes**:
        1.  Read `LOOP_LOG.md` from session directory.
        2.  Parse last `🏁 Iteration Complete` or `📈 Metrics` entry to find iteration number.
        3.  Read manifest path from log or ask user.
        4.  Skip to Phase 5 (Iteration Loop) starting at iteration N+1.
    *   **If No**: Continue to manifest check.

7.  **Manifest Check**: Does `--manifest <path>` exist?
    *   **If Yes**: Read the manifest, validate against schema, proceed to plan check.
    *   **If No**: Proceed to Phase 1 (Interrogation).

8.  **Plan Check**: Does `--plan <path>` exist?
    *   **If Yes**: Read the plan, skip to Phase 3 (Calibration).
    *   **If No**: Proceed to Phase 2 (Planning).

### Phase Transition
*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Interrogation Phase (Manifest Creation)
*Build the workload manifest through guided questioning.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Interrogation (Manifest Creation).
> 2. I will guide you through building a workload manifest via structured questions.
> 3. I will build a `loop.manifest.json` from your answers.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.

### Interrogation Protocol

Execute `§CMD_EXECUTE_INTERROGATION_PROTOCOL` with the topics below.

### Interrogation Topics (Loop)
*Standard topics for the command to draw from. Adapt to the workload — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Workload identity** — What is this workload? What does it produce? What signals quality?
- **Iteration goals** — What specific improvements are you targeting? What's "good enough"?
- **Artifact paths** — Which files (prompts, schemas, configs) will be modified during iteration?
- **Evaluation strategy** — How do you measure quality? External reviewer? Automated diff? Visual inspection?
- **Failure patterns** — What kinds of errors are most common? Where does the LLM struggle?
- **Case selection** — What input cases best represent the problem space? Edge cases?
- **Domain context** — What background docs should the Composer agent receive for deep analysis?
- **Resource constraints** — Cost per iteration? API rate limits? Time budget?
- **Stopping conditions** — When should we stop iterating? Quality threshold? Plateau? Budget?
- **Agent configuration** — Do you have existing reviewer/Composer prompts, or should we generate them?

### Manifest Assembly

Within the interrogation rounds, build the manifest from these fields:

**Core Configuration**:
1.  "What is this workload called?" → `workloadId`
2.  "Which files will be modified during iteration?" → `artifactPaths`
3.  "Where are the test input files (cases)?" → `casePaths` (accept glob patterns)
4.  "Do you have expected output files for comparison?" → `expectedPaths` (optional)

**Execution Configuration**:
1.  "What command runs the workload on a single case?" → `runCommand`
2.  "Where should output be written?" → `outputPath`
3.  "What command evaluates quality?" → `evaluateCommand`
4.  "Alternative review command?" → `reviewCommand` (optional)

**Agent Configuration**:
1.  "Composer agent prompt file?" → `agents.composer.promptFile` (or auto-generate)
2.  "Reviewer agent prompt file?" → `agents.reviewer.promptFile` (or auto-generate)
3.  "Domain context documents for the Composer?" → `domainDocs` (optional)

**Advanced**:
1.  "Max iterations?" → `maxIterations` (default: 10)

### Auto-Generation (Bootstrap)

If the user doesn't have existing agent prompts:
1.  Read the artifact files from `artifactPaths` to understand the domain.
2.  Read any `domainDocs` for additional context.
3.  Draft a Composer prompt and reviewer prompt based on the domain.
4.  Present drafts to the user for review and adjustment.
5.  Save to `agents.composer.promptFile` and `agents.reviewer.promptFile`.

### Manifest Validation

1.  **Construct**: Build the manifest JSON from collected answers.
2.  **Validate**: Check against `MANIFEST_SCHEMA.json`.
3.  **Present**: Show the manifest to the user. Execute `AskUserQuestion` (multiSelect: false):
    > "Manifest ready. Confirm?"
    > - **"Confirmed"** — Manifest is correct, proceed
    > - **"I have changes"** — Let me adjust before proceeding

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Skip to Phase 3: Calibration | Jump straight to single-fixture test"

---

## 2. Planning Phase (Experiment Design)
*Before iterating, design the experiment. Measure twice, cut once.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Planning (Experiment Design).
> 2. I will analyze current failures and form ranked hypotheses.
> 3. I will `§CMD_POPULATE_LOADED_TEMPLATE` using `LOOP_PLAN.md` template.
> 4. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding.

### Step A: Gather Failure Context

1.  **If continuing from prior session**: Read prior `LOOP.md` or `LOOP_LOG.md` for context.
2.  **If fresh**: Form initial hypotheses from domain knowledge and manifest context.
3.  **Categorize**: Group expected failure patterns by type.

### Step B: Form Hypotheses

1.  **Analyze**: What do we expect to improve? Even a benign initial hypothesis like "we expect cases to process correctly" is valid.
2.  **Hypothesize**: For each improvement area, propose a root cause and a predicted outcome.
3.  **Rank**: Order hypotheses by:
    *   **Likelihood**: How confident are we this is the cause?
    *   **Testability**: Can we isolate and test this cheaply?
    *   **Impact**: How many cases would this fix?

### Step C: Design Experiments

1.  **Map**: Assign each hypothesis to a specific experiment.
2.  **Sequence**: Order experiments by priority (high-impact, high-confidence first).
3.  **Define Changes**: For each experiment, specify:
    *   The exact file and section to modify
    *   The current text and proposed change
    *   Which cases will test this change

### Step D: Select Cases

1.  **Focus Cases**: Pick 3-5 cases that best test the hypotheses.
2.  **Regression Guards**: Identify 2-3 passing cases that must stay passing.
3.  **Exclusions**: Note any cases to ignore (and why).

### Step E: Define Success Criteria

1.  **Quantitative**: What quality threshold are we targeting?
2.  **Qualitative**: What improvements do we expect to see?
3.  **Exit Conditions**: When do we stop iterating?

### Step F: Create Plan

1.  **Generate**: Execute `§CMD_POPULATE_LOADED_TEMPLATE` (Schema: `LOOP_PLAN.md`).
2.  **Present**: Show the plan to the user. Execute `AskUserQuestion` (multiSelect: false):
    > "Loop plan ready. Proceed?"
    > - **"Approved"** — Plan is good, begin execution
    > - **"Needs revision"** — Adjust the plan first

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Skip to Phase 4: Baseline | Manifest already validated, go straight to baseline"

---

## 3. Calibration Phase (Single-Fixture Test)
*Prove the manifest works before committing to the full loop.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Calibration (Single-Fixture Test).
> 2. I will run ONE case through the pipeline to verify the manifest.
> 3. If calibration fails, I will help fix the manifest interactively.

### Step A: Select Test Fixture

1.  **Expand**: Resolve `casePaths` globs to get actual file list.
2.  **Select**: Pick the FIRST case for calibration.
3.  **Announce**: "Running calibration with case: `[path]`"

### Step B: Execute Pipeline (Single Fixture)

1.  **Run Workload**: Execute `runCommand` with `{case}` substituted.
    *   **If Error**: Log `🛑 Calibration Failure`, ask user to fix `runCommand`.
2.  **Check Output**: Verify `outputPath` file was created.
    *   **If Missing**: Log `🛑 Calibration Failure`, ask user to fix `outputPath`.
3.  **Run Evaluation** (if configured): Execute `evaluateCommand`.
    *   **If Error**: Log `🛑 Calibration Failure`, ask user to fix `evaluateCommand`.

### Step C: Calibration Result

*   **If All Passed**:
    1.  Log `✅ Calibration Success` to LOOP_LOG.md.
    2.  Ask: "Calibration passed. Where should I save the manifest?"
    3.  Write manifest to specified path (default: alongside workload code).
    4.  Proceed to Phase 4.

*   **If Any Failed**:
    1.  Log `🛑 Calibration Failure` with details.
    2.  Ask: "Calibration failed. What would you like to fix?"
    3.  Update manifest based on user input.
    4.  **Loop**: Return to Step B and retry (max 3 attempts).
    5.  **If 3 failures**: Abort with "Please fix the manifest manually and re-run with `--manifest <path>`."

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 4. Baseline Phase (Initial Metrics)
*Establish the starting point before any iteration.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Baseline (Initial Metrics).
> 2. I will run ALL cases to establish baseline metrics.
> 3. This is iteration 0 — the initial hypothesis is tested here.

### Step A: Form Initial Hypothesis

1.  **State**: The initial hypothesis (even a benign one: "We expect cases to process correctly with current configuration").
2.  **Predict**: What do we expect the baseline to show?
3.  **Log**: Append `🔬 Hypothesis` entry to LOOP_LOG.md.

### Step B: Run Cases

1.  **Expand**: Resolve `casePaths` globs to get full case list.
2.  **Filter** (if `--case <path>` specified): Reduce to just the specified case.
3.  **Execute**: For each case:
    *   Run `runCommand`
    *   Run `evaluateCommand` (if configured)
    *   Compare output to `expectedPaths` (if configured)
4.  **Log**: Append `📊 Result` entry with baseline metrics.

### Step C: Present Baseline

1.  **Report**: "Baseline: `X/Y` cases passing (`Z%`)"
2.  **List Issues**: Show which cases had problems and why (if known).
3.  Execute `AskUserQuestion` (multiSelect: false):
    > "Baseline: X/Y passing. Ready to begin iteration?"
    > - **"Begin"** — Start the hypothesis-driven iteration cycle
    > - **"Let me review"** — I want to inspect the baseline first

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 5. Iteration Loop (The Core Cycle)
*HYPOTHESIZE → RUN → REVIEW → ANALYZE → DECIDE → EDIT*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Iteration Loop.
> 2. Each iteration follows the scientific method: hypothesize, execute, review, analyze, decide, edit.
> 3. The Composer subagent provides deep analytical reasoning for each iteration.

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### 🔄 For Each Iteration (1 to maxIterations):

#### Step A: HYPOTHESIZE

1.  **Review**: What did the previous iteration reveal? (Skip for iteration 1 — use baseline findings.)
2.  **Hypothesize**: "The artifact lacks [X], causing [Y] failures. Adding [Z] should improve [W]."
3.  **Predict**: State the expected outcome explicitly. "After this change, cases A, B, C should improve."
4.  **Log**: Append `🔬 Hypothesis` entry to LOOP_LOG.md with prediction.

#### Step B: RUN

1.  **Execute**: Run `runCommand` for all cases (or focused cases per plan).
2.  **Collect Output**: Store results at `outputPath`.
3.  **Log**: Append `🧪 Experiment` entry.

#### Step C: REVIEW

1.  **Evaluate**: Run `evaluateCommand` to get quality assessment.
    *   If `expectedPaths` configured: also compute diff-based metrics.
2.  **Log**: Append `👁️ Critique` entry with evaluation results.

#### Step D: ANALYZE (Composer Subagent)

1.  **Invoke Composer**: Launch the Composer subagent via Task tool with:
    *   Full prompt/schema text from `artifactPaths`
    *   All evaluation critiques from this iteration
    *   Complete iteration history (hypothesis records from LOOP_LOG.md)
    *   Domain docs from `domainDocs`
    *   The Composer prompt template from `agents.composer.promptFile`

2.  **Composer Output**: The Composer produces:
    *   **Root Cause Analysis**: Why the current artifacts produce these failures
    *   **Strategic Options**: 3 approaches to fix the root cause
    *   **Recommendation**: 1 recommended fix with 2 alternatives
    *   Each fix must be a **structural prompt engineering technique** — not a surface-level suggestion

3.  **Present All 3 Options**: Always show the recommended fix AND both alternatives to the user.
4.  **Log**: Append `🎯 Composer Analysis` entry.

#### Step E: DECIDE

1.  **Present**: Execute `AskUserQuestion` (multiSelect: false):
    > "Composer recommends Option 1. Choose an option:"
    > - **"Option 1: [Recommended fix summary]"** — Apply the recommended change
    > - **"Option 2: [Alternative A summary]"** — Apply alternative A
    > - **"Option 3: [Alternative B summary]"** — Apply alternative B
    > - **"Skip this iteration"** — Move to next iteration with a different hypothesis

2.  **On rejection handling**: If the user skips or wants something different:
    Execute `AskUserQuestion` (multiSelect: false):
    > "How should we proceed?"
    > - **"Next iteration with new hypothesis"** — Skip to next cycle with a fresh hypothesis
    > - **"Retry with feedback"** — Feed your reason back to the Composer for a refined suggestion

3.  **Log**: Append `💡 Decision` entry.

#### Step F: EDIT

1.  **Apply**: Make the chosen edit to the artifact files.
2.  **Log**: Append `✏️ Edit Applied` entry with exact changes.
3.  **Verify Prediction**: The NEXT iteration's RUN step will test the hypothesis. This is the scientific method — the edit IS the experiment; the next run IS the measurement.

#### Convergence Check (End of Each Iteration)

*   **If all cases passing**: Log `🏁 Iteration Complete (Converged)`, exit loop.
*   **If max iterations reached**: Log `🏁 Iteration Complete (Max Reached)`, exit loop.
*   **If no improvement for 2 iterations**: Present choice to user:
    > "Plateau detected. Continue or stop?"
    > - **"Continue with different approach"** — Try a fundamentally different hypothesis
    > - **"Stop — accept current state"** — Exit to synthesis
*   **If regression detected**:
    1.  Log `⚠️ Regression Detected`.
    2.  DO NOT auto-revert. The failed experiment is valuable data.
    3.  Present choice:
        > "Regression detected. How to proceed?"
        > - **"Accept tradeoff and continue"** — The improvement elsewhere outweighs the regression
        > - **"Try different hypothesis next"** — The approach was wrong, form new hypothesis
        > - **"Stop and analyze"** — Exit to synthesis with regression analysis

*   **Otherwise**: Continue to next iteration (loop back to Step A).

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Re-run baseline comparison | Compare current state to original baseline"

---

## 6. Synthesis Phase

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 6: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Debrief creation notes** (for Step 1 — `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `LOOP.md`
*   Populate iteration history table with hypothesis records.
*   List all edits made with impact and hypothesis outcomes.
*   Document remaining failures with root cause analysis.
*   Capture Composer insights and generalizable learnings.

**Walk-through config** (for Step 3 — `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Iteration complete. Walk through remaining issues and recommendations?"
  debriefFile: "LOOP.md"
  templateFile: "~/.claude/skills/loop/assets/TEMPLATE_LOOP.md"
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---

## Appendix: Invariants

The protocol respects these invariants:

*   **§INV_HYPOTHESIS_AUDIT_TRAIL**: Every iteration must produce a hypothesis record (prediction + outcome). The log is the audit trail of what was tried, predicted, and learned.
*   **§INV_REVIEW_BEFORE_COMPOSE**: The Composer subagent MUST receive evaluation results as input. It never operates on raw outputs alone — the reviewer/evaluator provides the structured quality signal.
*   **§INV_COMPOSER_STRUCTURAL_FIXES**: Composer suggestions must be structural prompt engineering fixes ("add anchoring rule for table boundaries"), not surface-level ("extract the table correctly"). If a suggestion lacks a concrete mechanism, it is rejected.
*   **§INV_RE_REVIEW_AFTER_EDIT**: After each edit, the next iteration's RUN+REVIEW step provides fresh evaluation. Do not compare old reviews to new outputs.
*   **§INV_EXPECTED_OPTIONAL**: `expectedPaths` in the manifest is optional. The loop must work from evaluation critiques alone.
*   **§INV_MANIFEST_COLOCATED**: Manifests live with workload code, not in a central registry.
*   **§INV_NO_SILENT_REGRESSION**: Regressions are detected and surfaced to the user with options. Never silently accepted.
*   **§INV_VALIDATE_BEFORE_ITERATE**: Single-case calibration before the full loop.
