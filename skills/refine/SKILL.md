---
name: refine
description: "Iterative prompt and schema refinement using TDD methodology for LLM workloads. Triggers: \"refine the prompt\", \"improve extraction\", \"iterate on schema\", \"prompt TDD\", \"tune the model\"."
version: 2.0
tier: protocol
---

Iterative prompt and schema refinement using TDD methodology for LLM workloads.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Refinement Protocol (The Iteration Engine)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 2 (Interrogation / Manifest Creation) and Phase 3 (Experiment Design). The engine's plan lives in the session directory as a reviewable artifact, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

ARGUMENTS: Accepts optional flags:
- `--auto`: Run N iterations automatically (default: suggestion mode)
- `--dry-run`: Show what would happen without executing
- `--iterations N`: Set max iterations for auto mode (default: 5)
- `--manifest <path>`: Use existing manifest instead of interrogation
- `--plan <path>`: Skip planning, use existing REFINE_PLAN.md
- `--case <path>`: Focus on a single case instead of running all cases
- `--continue`: Resume from last iteration in current session directory

### Phases (for §CMD_PARSE_PARAMETERS)
*Include this array in the `phases` field when calling `session.sh activate`:*
```json
[
  {"major": 1, "minor": 0, "name": "Setup"},
  {"major": 2, "minor": 0, "name": "Interrogation"},
  {"major": 3, "minor": 0, "name": "Planning"},
  {"major": 4, "minor": 0, "name": "Validation"},
  {"major": 5, "minor": 0, "name": "Baseline"},
  {"major": 6, "minor": 0, "name": "Iteration Loop"},
  {"major": 7, "minor": 0, "name": "Synthesis"}
]
```
*Phase enforcement (¶INV_PHASE_ENFORCEMENT): transitions must be sequential. Use `--user-approved` for skip/backward.*

## Mode Presets

Refinement modes configure the iteration focus — what to optimize for. Mode definitions live in `modes/*.md`.

| Mode | Focus | When to Use |
|------|-------|-------------|
| **Accuracy** | Precision and correctness | Quality-critical extractions |
| **Speed** | Latency and token efficiency | Real-time or high-volume |
| **Robustness** | Edge case handling | Diverse input formats |
| **Custom** | User-defined | Hybrid or novel objectives |

**Mode files**: `~/.claude/skills/refine/modes/{accuracy,speed,robustness,custom}.md`

---

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is REFINEMENT (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Refinement Mode** (Accuracy / Speed / Robustness / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/refine/assets/TEMPLATE_REFINE_PLAN.md` (Template for experiment planning)
    *   `~/.claude/skills/refine/assets/TEMPLATE_REFINE_LOG.md` (Template for experiment logging)
    *   `~/.claude/skills/refine/assets/TEMPLATE_REFINE.md` (Template for session debrief)
    *   `~/.claude/skills/refine/assets/MANIFEST_SCHEMA.json` (Schema for workload manifest)

3.  **Parse Arguments**: Check for flags in the user's command:
    *   `--manifest <path>`: Skip interrogation, use existing manifest
    *   `--plan <path>`: Skip planning, use existing REFINE_PLAN.md
    *   `--auto`: Run automated iteration loop (default: suggestion mode)
    *   `--dry-run`: Show what would happen without executing
    *   `--iterations N`: Set max iterations for auto mode (default: 5)
    *   `--case <path>`: Focus on a single case instead of running all cases
    *   `--continue`: Resume from last iteration in current session

4.  **Parse Parameters**: Execute `§CMD_PARSE_PARAMETERS`.
    *   **CRITICAL**: Output the JSON **BEFORE** proceeding.

5.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR`.

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion.

6.1. **Refinement Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What refinement objective should I optimize for?"
    > - **"Accuracy" (Recommended)** — Precision-focused: maximize extraction correctness
    > - **"Speed"** — Efficiency-focused: minimize latency and token usage
    > - **"Robustness"** — Resilience-focused: handle edge cases and diverse inputs
    > - **"Custom"** — Define your own optimization objective

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Configuration (iteration focus, hypothesis style, success metric).

    **On "Custom"**: Read ALL 3 named mode files first (`modes/accuracy.md`, `modes/speed.md`, `modes/robustness.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 1 Step 6.2 role (from mode file)
    *   Phase 6 iteration focus, hypothesis style, and success metric (from mode file)

6.2. **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

7.  **Resume Check**: Does `--continue` flag exist?
    *   **If Yes**:
        1.  Read `REFINE_LOG.md` from session directory.
        2.  Parse last `🏁 Iteration Complete` or `📈 Metrics` entry to find iteration number.
        3.  Read manifest path from log or ask user.
        4.  Skip to Phase 6 (Iteration Loop) starting at iteration N+1.
    *   **If No**: Continue to manifest check.

9.  **Manifest Check**: Does `--manifest <path>` exist?
    *   **If Yes**: Read the manifest, validate against schema, proceed to plan check.
    *   **If No**: Proceed to Phase 2 (Interrogation).

10. **Plan Check**: Does `--plan <path>` exist?
    *   **If Yes**: Read the plan, skip to Phase 4 (Validation).
    *   **If No**: Proceed to Phase 3 (Planning).

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Mode: `________` (accuracy / speed / robustness / custom)
> - Role: `________` (quote the role name from the mode preset)
> - Session dir: `________`
> - Templates loaded: `________`
> - Parameters parsed: `________`
> - Flags parsed: `________`
> - Routing: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Interrogation"** — Build workload manifest through structured questioning
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues
> - **"Skip to Phase 3: Planning"** — Manifest already loaded via --manifest flag

---

## 2. Interrogation Phase (Manifest Creation)
*Build the workload manifest through structured questioning.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Interrogation (Manifest Creation).
> 2. I will ask questions to understand the workload configuration.
> 3. I will build a `refine.manifest.json` from your answers.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should manifest interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Simple workload, clear paths, few cases |
| **Medium** | 6+ | Moderate complexity, custom validators, overlays |
| **Long** | 9+ | Complex multi-stage pipeline, many edge cases |
| **Absolute** | Until ALL questions resolved | Novel workload type, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Interrogation Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

### Interrogation Topics (Refinement)
*Examples of themes to explore. Adapt to the workload — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Iteration goals** — What specific improvements are you targeting? What's "good enough"?
- **Baseline metrics** — What's the current pass rate? Where are the worst failures?
- **Evaluation criteria** — How do you measure success? Automated diffs, visual review, both?
- **Failure modes** — What kinds of errors are most common? Structural, value, missing fields?
- **Resource constraints** — Cost per iteration? API rate limits? Time budget?
- **Stopping conditions** — When should we stop iterating? Pass rate? Plateau? Budget?
- **Prompt engineering specifics** — Which prompt sections are most suspicious? Any known weak spots?
- **Data characteristics** — How varied are the cases? Format consistency? Outliers?
- **Edge cases** — Known tricky inputs? Cases that always fail?
- **Comparison strategy** — Diff-based, overlay-based, or manual inspection?

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Structured Manifest Questions

Within the interrogation rounds, cover these manifest-specific fields:

**Core Configuration** (Round A):
1.  "What is this workload called?" → `workloadId`
2.  "Where are the prompt files that control extraction?" → `promptPaths`
3.  "Where are the schema files (if any)?" → `schemaPaths`
4.  "Where are the test input files (cases)?" → `casePaths` (accept glob patterns)
5.  "Do you have expected output files for comparison?" → `expectedPaths` (optional)

**Execution Configuration** (Round B):
1.  "What command runs extraction on a single case?" → `runCommand`
2.  "Where should extraction output be written?" → `outputPath`
3.  "Do you have a command to generate visual overlays?" → `overlayCommand` (optional)
4.  "Any custom validation scripts to run?" → `validationScripts` (optional)

**Advanced Configuration** (Round C — Optional):
1.  "Custom critique prompt for visual analysis?" → `critiquePrompt` (optional)
2.  "Custom critique script instead of Claude?" → `critiqueScript` (optional)
3.  "Max iterations for auto mode?" → `maxIterations` (default: 5)

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to assemble manifest"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

### Assemble Manifest

1.  **Construct**: Build the manifest JSON from collected answers.
2.  **Validate**: Check against `MANIFEST_SCHEMA.json`.
3.  **Present**: Show the manifest to the user. Execute `AskUserQuestion` (multiSelect: false):
    > "Manifest ready. Confirm?"
    > - **"Confirmed"** — Manifest is correct, proceed
    > - **"I have changes"** — Let me adjust before proceeding

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`
> - Manifest validated: `________`
> - User confirmed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Manifest ready. How to proceed?"
> - **"Proceed to Phase 3: Planning"** — Design experiments before iterating
> - **"Stay in Phase 2"** — Modify the manifest
> - **"Skip to Phase 4: Validation"** — Jump straight to single-fixture test

---

## 3. Planning Phase (Experiment Design)
*Before iterating, design the experiment. Measure twice, cut once.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Planning (Experiment Design).
> 2. I will analyze current failures and form ranked hypotheses.
> 3. I will `§CMD_POPULATE_LOADED_TEMPLATE` using `REFINE_PLAN.md` template.
> 4. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before proceeding.

### Step A: Gather Failure Context

1.  **If continuing from prior session**: Read prior `REFINE.md` or `REFINE_LOG.md` for context.
2.  **If fresh**: Run a quick baseline scan (dry-run) to understand current failure patterns.
3.  **Categorize**: Group failures by symptom type (bounding box, missing fields, wrong values, structural).

### Step B: Form Hypotheses

1.  **Analyze Patterns**: What do failing cases have in common?
2.  **Hypothesize**: For each failure pattern, propose a root cause.
3.  **Rank**: Order hypotheses by:
    *   **Likelihood**: How confident are we this is the cause?
    *   **Testability**: Can we isolate and test this cheaply?
    *   **Impact**: How many cases would this fix?

### Step C: Design Experiments

1.  **Map**: Assign each hypothesis to a specific experiment.
2.  **Sequence**: Order experiments by priority (high-impact, high-confidence first).
3.  **Define Changes**: For each experiment, specify:
    *   The exact file and line to modify
    *   The current text and proposed text
    *   Which cases will test this change

### Step D: Select Cases

1.  **Focus Cases**: Pick 3-5 cases that best test the hypotheses.
2.  **Regression Guards**: Identify 2-3 passing cases that must stay passing.
3.  **Exclusions**: Note any cases to ignore (and why).

### Step E: Define Success Criteria

1.  **Quantitative**: What pass rate are we targeting?
2.  **Qualitative**: What visual/structural improvements do we expect?
3.  **Exit Conditions**: When do we stop iterating?

### Step F: Create Plan

1.  **Generate**: Execute `§CMD_POPULATE_LOADED_TEMPLATE` (Schema: `REFINE_PLAN.md`).
2.  **Present**: Show the plan to the user. Execute `AskUserQuestion` (multiSelect: false):
    > "Refinement plan ready. Proceed?"
    > - **"Approved"** — Plan is good, begin execution
    > - **"Needs revision"** — Adjust the plan first

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Failure context: `________`
> - Hypotheses ranked: `________`
> - Experiments designed: `________`
> - Cases selected: `________`
> - Success criteria: `________`
> - REFINE_PLAN.md written: `________`
> - User approved: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Plan approved. How to proceed?"
> - **"Proceed to Phase 4: Validation"** — Run single-fixture test to verify manifest
> - **"Revise the plan"** — Go back and edit the plan
> - **"Skip to Phase 5: Baseline"** — Manifest already validated, go straight to baseline

---

## 4. Validation Phase (Single-Fixture Test)
*Prove the manifest works before committing to the full loop.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Validation (Single-Fixture Test).
> 2. I will run ONE case through the pipeline to verify the manifest.
> 3. If validation fails, I will help fix the manifest interactively.

### Step A: Select Test Fixture

1.  **Expand**: Resolve `casePaths` globs to get actual file list.
2.  **Select**: Pick the FIRST case for validation.
3.  **Announce**: "Running validation with case: `[path]`"

### Step B: Execute Pipeline (Single Fixture)

1.  **Run Extraction**: Execute `runCommand` with `{case}` substituted.
    *   **If Error**: Log `🛑 Validation Failure`, ask user to fix `runCommand`.
2.  **Check Output**: Verify `outputPath` file was created.
    *   **If Missing**: Log `🛑 Validation Failure`, ask user to fix `outputPath`.
3.  **Run Overlay** (if configured): Execute `overlayCommand`.
    *   **If Error**: Log `🛑 Validation Failure`, ask user to fix `overlayCommand`.
4.  **Run Validators** (if configured): Execute each `validationScripts` entry.
    *   **If Error**: Log `🛑 Validation Failure`, show which script failed.

### Step C: Validation Result

*   **If All Passed**:
    1.  Log `✅ Validation Success` to REFINE_LOG.md.
    2.  Ask: "Validation passed. Where should I save the manifest?"
    3.  Write manifest to specified path (default: alongside workload code).
    4.  Proceed to Phase 5.

*   **If Any Failed**:
    1.  Log `🛑 Validation Failure` with details.
    2.  Ask: "Validation failed. What would you like to fix?"
    3.  Update manifest based on user input.
    4.  **Loop**: Return to Step B and retry (max 3 attempts).
    5.  **If 3 failures**: Abort with "Please fix the manifest manually and re-run with `--manifest <path>`."

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Test fixture: `________`
> - Pipeline result: `________`
> - Manifest saved: `________`
> - Validation logged: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 4: Validation passed. How to proceed?"
> - **"Proceed to Phase 5: Baseline"** — Run all cases to establish starting metrics
> - **"Stay in Phase 4"** — Re-run validation or fix issues

---

## 5. Baseline Phase (Initial Metrics)
*Establish the starting point before any refinement.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Baseline (Initial Metrics).
> 2. I will run ALL cases to establish baseline metrics.
> 3. This is iteration 0 — no changes have been made yet.

**If `--dry-run`**: Skip actual execution, show what WOULD happen, then STOP.

### Step A: Run Cases

1.  **Expand**: Resolve `casePaths` globs to get full case list.
2.  **Filter** (if `--case <path>` specified): Reduce to just the specified case.
3.  **Execute**: For each case:
    *   Run `runCommand`
    *   Run `overlayCommand` (if configured)
    *   Run `validationScripts` (if configured)
    *   Compare output to `expectedPaths` (if configured)
3.  **Log**: Append `🎯 Iteration Start` entry with baseline metrics.

### Step B: Collect Baseline Metrics

*   **Quantitative** (if `expectedPaths` configured):
    *   Passing cases: count where output matches expected
    *   Failing cases: list with diff summary
*   **Qualitative** (always):
    *   Generate overlay images for visual inspection
    *   Note any obvious errors visible in overlays

### Step C: Present Baseline

1.  **Report**: "Baseline: `X/Y` cases passing (`Z%`)"
2.  **List Failures**: Show which cases failed and why (if known).
3.  Execute `AskUserQuestion` (multiSelect: false):
    > "Baseline: X/Y passing. Ready to begin refinement iteration?"
    > - **"Begin"** — Start iterating on refinements
    > - **"Let me review"** — I want to inspect the baseline first

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Cases executed: `________`
> - Baseline metrics: `________`
> - Baseline presented: `________`
> - User confirmed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 5: Baseline established. How to proceed?"
> - **"Proceed to Phase 6: Iteration Loop"** — Begin analyze-critique-suggest-apply-measure cycle
> - **"Stay in Phase 5"** — Re-run baseline or investigate specific failures

---

## 6. Iteration Loop (The Core Cycle)
*Analyze → Critique → Suggest → Apply → Measure → Repeat*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 6: Iteration Loop.
> 2. I will analyze failures, critique visually, suggest edits, and measure impact.
> 3. Mode: `[Suggestion / Auto]`, Max iterations: `N`

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### 🔄 For Each Iteration (1 to maxIterations):

#### Step A: Analyze Failures

1.  **JSON Diff** (if `expectedPaths` configured):
    *   For each failing case, compute diff between output and expected.
    *   Categorize errors: missing fields, wrong values, extra fields, structural mismatch.
2.  **Validation Errors** (if `validationScripts` configured):
    *   Collect error messages from failed validators.
3.  **Log**: Append findings to REFINE_LOG.md using appropriate thought triggers.

#### Step B: Visual Critique (Reviewer Agent)

1.  **Select Pages**: Choose pages for review:
    *   All failing pages (from Step A analysis)
    *   Random sample of N pages if many failures (default: 5)
    *   Or specific pages flagged by user

2.  **Prepare Images**: Download/copy overlay images to `tmp/`:
    *   Full-page overlays: `tmp/layout-overlay-page-{N}.png`
    *   Layout JSON: `tmp/layout.json`
    *   (Optional) Quadrant tiles if precision needed

3.  **Launch Reviewer Agent**:
    ```
    Task(subagent_type="reviewer", prompt=`
      Review extraction results for case ${caseId}.

      **Images to analyze** (use Read tool):
      ${overlayPaths.map(p => `- ${p}`).join('\n')}

      **Layout JSON**:
      - ${layoutJsonPath}

      **Pages**: ${selectedPages.join(', ')}

      Analyze each overlay image, cross-reference with layout JSON, and return a CritiqueReport JSON.
      Run ALL checks from your §CRITIQUE_CHECKLIST.
      Include actionable recommendations for each issue found.
    `)
    ```

4.  **Process Results**:
    *   Parse CritiqueReport JSON from task result
    *   Log `👁️ Critique` entry with:
        *   Overall score
        *   Issue count by type
        *   Top 3 recommendations
    *   Feed recommendations into Step C (Hypothesis)

5.  **Manual Override** (if `--manual-critique` flag):
    *   If `overallScore < 70`: Present images to user for confirmation
    *   User can add issues the agent missed
    *   User can reject false positives

#### Step C: Form Hypothesis

1.  **Synthesize**: Combine JSON diff + validation errors + visual critique.
2.  **Hypothesize**: "The prompt lacks guidance on [X], causing [Y] errors."
3.  **Log**: Append `🔬 Hypothesis` entry.

#### Step D: Suggest Edit

1.  **Read Prompts**: Load files from `promptPaths`.
2.  **Generate Suggestion**: Based on hypothesis, propose specific edit.
    *   Include: file, line range, current text, proposed text.
3.  **Log**: Append `🔧 Suggestion` entry.

#### Step E: Apply Edit

*   **If Suggestion Mode**:
    1.  Present the suggested edit to the user.
    2.  Ask: "Apply this edit? [Yes / Modify / Skip]"
    3.  If Yes: Apply via Edit tool, log `✏️ Edit Applied`.
    4.  If Modify: Get user's version, apply, log.
    5.  If Skip: Log `🅿️ Parking Lot`, continue to next iteration.

*   **If Auto Mode**:
    1.  Apply the edit directly via Edit tool.
    2.  Log `✏️ Edit Applied (Auto)`.

#### Step F: Measure Impact

1.  **Re-run**: Execute all cases with updated prompts.
2.  **Compare**: Calculate new metrics vs previous iteration.
3.  **Log**: Append `📊 Result` entry.

#### Step G: Regression Check

*   **If metrics improved or neutral**: Continue.
*   **If metrics degraded**:
    1.  Log `⚠️ Regression Detected` with details (which cases regressed, by how much).
    2.  **Important**: Do NOT revert the edit via git. The log is append-only — the failed experiment is valuable data.
    3.  **If Auto Mode**: Log the regression, formulate alternative hypothesis, continue to next iteration with a different approach.
    4.  **If Suggestion Mode**: Ask user: "This edit caused regression. Options: (A) Accept tradeoff and continue, (B) Try different hypothesis next iteration, (C) Stop and analyze."
    5.  The next iteration's hypothesis should account for why this one failed.

#### Step H: Convergence Check

*   **If all cases passing**: Log `🏁 Iteration Complete (Converged)`, exit loop.
*   **If max iterations reached**: Log `🏁 Iteration Complete (Max Reached)`, exit loop.
*   **If Auto Mode and no improvement for 2 iterations**: Log `🏁 Iteration Complete (Plateau)`, exit loop.
*   **Otherwise**: Continue to next iteration.

### §CMD_VERIFY_PHASE_EXIT — Phase 6
**Output this block in chat with every blank filled:**
> **Phase 6 proof:**
> - Iterations completed: `________`
> - Each iteration logged: `________`
> - Exit condition: `________`
> - REFINE_LOG.md entries: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 6: Iteration loop complete. How to proceed?"
> - **"Proceed to Phase 7: Synthesis"** — Generate debrief and close session
> - **"Stay in Phase 6"** — More iterations needed
> - **"Re-run baseline comparison"** — Compare current state to original baseline

---

## 7. Synthesis Phase (Debrief)
*Summarize the refinement session.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 7: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` (if any discovered checklists exist).
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` following `assets/TEMPLATE_REFINE.md` EXACTLY.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY`.

**STOP**: Output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The debrief FILE is the primary deliverable — chat output alone is not sufficient.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `REFINE.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   Populate iteration history table.
  *   List all edits made with impact.
  *   Document remaining failures.
  *   Capture insights and recommendations.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.
  *   `REFINE_PLAN.md` — Experiment design and hypotheses
  *   `REFINE_LOG.md` — Full experiment journal
  *   `REFINE.md` — Session debrief
  *   `refine.manifest.json` — Workload configuration (if created)
  *   Modified prompt/schema files

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 4**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Refinement complete. Walk through remaining issues and recommendations?"
  debriefFile: "REFINE.md"
  templateFile: "~/.claude/skills/refine/assets/TEMPLATE_REFINE.md"
  actionMenu:
    - label: "Needs more refinement"
      tag: "#needs-implementation"
      when: "A failing fixture needs targeted prompt work"
    - label: "Needs research"
      tag: "#needs-research"
      when: "A failure pattern needs deeper investigation"
    - label: "Accept tradeoff"
      tag: ""
      when: "A regression was accepted as an intentional tradeoff"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 7 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 7 proof:**
> - REFINE.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 5**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Refinement complete. What's next? (Type a /skill name to invoke it, or describe new work to scope it)"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/refine` (Recommended) | Continue refining — more iterations on same or different workload |
| 2 | `/test` | Write regression tests for the refined prompts/schemas |
| 3 | `/implement` | Implement code changes discovered during refinement |
| 4 | `/analyze` | Analyze the refinement results for deeper patterns |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---

## Appendix: SDK CLI (Required Tooling)

[!!!] **CRITICAL**: Use the `@finch/sdk` CLI for all extraction operations. Do NOT write custom scripts.

The SDK CLI reads configuration from environment variables and provides a complete interface for the refinement workflow.

### Setup

The CLI uses `dotenv` and reads from `.env`:
```bash
# Required env vars (typically in .env)
S3_ENDPOINT=http://localhost:9000
S3_BUCKET=finch-uploads
TEMPORAL_ADDRESS=localhost:7233
TEMPORAL_NAMESPACE=finch
```

### Pre-flight: Verify Services

**Before running any extraction**, verify the required services are running:

```bash
# 1. Check MinIO (S3)
curl -s http://localhost:9000/minio/health/live && echo "MinIO: OK" || echo "MinIO: NOT RUNNING"

# 2. Check Temporal server
curl -s http://localhost:8080/api/v1/namespaces | grep -q finch && echo "Temporal: OK" || echo "Temporal: NOT RUNNING"

# 3. Check Temporal worker (CRITICAL — workflows won't execute without it)
ps aux | grep -q "[t]s-node.*worker.ts" && echo "Worker: OK" || echo "Worker: NOT RUNNING"
```

**If worker is not running**, start it:
```bash
# Start worker in background (from project root)
yarn workspace @finch/temporal dev &

# Or in a separate terminal for logs
yarn workspace @finch/temporal dev
```

**If Docker services are down**, start them:
```bash
yarn dev:deps  # Starts PostgreSQL, Redis, MinIO, Temporal via Docker
```

### Timeout Handling

Large PDFs (50+ pages) may take 15-30 minutes for full extraction. If the CLI times out:

1. **Check if workflow is still running**:
   ```bash
   curl -s "http://localhost:8080/api/v1/namespaces/finch/workflows" | \
     jq '.executions[:3] | .[] | {workflowId: .execution.workflowId, status: .status}'
   ```

2. **Wait for existing workflow with longer timeout**:
   ```bash
   npx tsx packages/sdk/src/cli.ts estimate wait <workflowId> --timeout 1800000
   ```

3. **Download overlays after completion**:
   ```bash
   npx tsx packages/sdk/src/cli.ts estimate layout overlays <caseId> -o tmp/overlays/<caseId>
   ```

### Common Commands

```bash
# Run full refinement pipeline (upload → extract → wait → download)
npx tsx packages/sdk/src/cli.ts estimate run <caseId> --debug-overlay -o tmp/overlays/<caseId>

# Run layout extraction only
npx tsx packages/sdk/src/cli.ts estimate layout run <caseId> --debug-overlay --wait

# Download overlays for an existing case
npx tsx packages/sdk/src/cli.ts estimate layout overlays <caseId> -o tmp/overlays

# Get layout JSON
npx tsx packages/sdk/src/cli.ts estimate layout get <caseId> -o tmp/layout.json

# Check workflow status
npx tsx packages/sdk/src/cli.ts estimate status <workflowId>

# Run visual review (via Temporal workflow)
npx tsx packages/sdk/src/cli.ts estimate review run <caseId> --wait -o tmp/review.json
```

### Why CLI Over Scripts

| Aspect | CLI | Custom Script |
|--------|-----|---------------|
| Config | Env vars (`.env`) | Hardcoded values |
| Namespace | Auto-detected | Easy to get wrong |
| Error handling | Structured JSON | Ad-hoc |
| Maintenance | One place | N scripts to update |

---

## Appendix: Reviewer Agent

Visual critique is handled by the **reviewer** subagent (`~/.claude/agents/reviewer.md`).

**Inputs**:
*   Local paths to overlay images (prepared in `tmp/`)
*   Path to layout JSON file
*   List of page numbers to review

**Output**: Structured `CritiqueReport` JSON (schema: `~/.claude/skills/refine/assets/SCHEMA_CRITIQUE_REPORT.json`)

**Checklist**: The agent runs ALL checks from `§CRITIQUE_CHECKLIST`:
*   Table bounds (top edge, bottom edge, group headers, comments, totals)
*   Scope detection (headers, totals, overlaps, types, continuations)
*   Structural (diagrams, metrics, breadcrumbs)
*   JSON-visual consistency (box matches, counts, phantoms)

**Legacy**: If `critiqueScript` is specified in the manifest, that script is used instead of the reviewer agent.

---

## Appendix: Invariants

The protocol respects these invariants:

*   **§INV_MANIFEST_COLOCATED**: Manifests live with workload code, not in a central registry.
*   **§INV_SURGICAL_SUGGESTIONS**: The suggestion LLM sees actual prompt content.
*   **§INV_NO_SILENT_REGRESSION**: Auto-mode flags metric degradation.
*   **§INV_VALIDATE_BEFORE_ITERATE**: Single-case validation before the loop.
*   **§INV_VISUAL_ONLY_VALID**: Workloads without `expectedPaths` are valid.
*   **§INV_SDK_CLI_OVER_SCRIPTS**: Use `@finch/sdk` CLI for extraction operations. Do NOT write custom `tmp/` scripts for upload, extract, wait, or download — the CLI already does this with proper config handling.
