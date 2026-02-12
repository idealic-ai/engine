---
name: analyze
description: "Thorough analysis of code, architecture, or topics — produces a structured research report. Supports goal-based modes: Explore (general research), Audit (risk-focused critique), Improve (actionable suggestions), Custom (user-defined lens). Triggers: \"analyze this code\", \"deep dive into\", \"research this topic\", \"investigate how X works\", \"audit this\", \"critique this\", \"suggest improvements\", \"find risks in\"."
version: 3.0
tier: protocol
---

Thorough analysis of code, architecture, or topics — produces a structured research report.
# Deep Research Protocol

---

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "ANALYSIS",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "templates_loaded", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Research Loop", "proof": ["log_entries", "key_finding", "open_gaps"]},
    {"major": 2, "minor": 0, "name": "Calibration", "proof": ["depth_chosen", "rounds_completed"]},
    {"major": 2, "minor": 1, "name": "Agent Handoff"},
    {"major": 3, "minor": 0, "name": "Synthesis"},
    {"major": 3, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 3, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 3, "minor": 3, "name": "Finding Triage", "proof": ["findings_triaged", "delegated", "deferred", "dismissed"]},
    {"major": 3, "minor": 4, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 3, "minor": 5, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/brainstorm", "/implement", "/document", "/fix", "/chores"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_ANALYSIS_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_ANALYSIS.md",
  "modes": {
    "explore": {"label": "Explore", "description": "Broad, curiosity-driven investigation", "file": "modes/explore.md"},
    "audit": {"label": "Audit", "description": "Adversarial, risk-focused critique", "file": "modes/audit.md"},
    "improve": {"label": "Improve", "description": "Constructive, actionable suggestions", "file": "modes/improve.md"},
    "custom": {"label": "Custom", "description": "User provides framing, agent blends modes", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > I am starting **Phase 0: Setup** for analysis of ___.
    > I will select the analysis mode, load context, and prepare the research workspace.
    > Focus is ANALYSIS — `§CMD_REFUSE_OFF_COURSE` applies.

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — constructs the session parameters JSON and pipes it to `session.sh activate` via heredoc.

3.  **Scope**: Understand the [Subject] and [Question] provided by the user.

4.  **Analysis Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What analysis lens should I use?"
    > - **"Explore" (Recommended)** — General research: understand, critique, and innovate
    > - **"Audit"** — Risk-focused: hunt for flaws, failure modes, and hidden assumptions
    > - **"Improve"** — Suggestion-focused: find actionable improvements with clear ROI
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, Research Topics, Calibration Topics, and Walk-Through Config.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/explore.md`, `modes/audit.md`, `modes/improve.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 Step 5 role (from mode file)
    *   Phase 1 research topics (from mode file)
    *   Phase 2 calibration topics (from mode file)
    *   Phase 3.3 walk-through config (from mode file)

5.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion.

7.  **Context Ingestion**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### Phase Transition
Execute `§CMD_GATE_PHASE`:
  custom: "Skip to Phase 2: Calibration | I want to guide the analysis direction before research begins"

---

## 1. The Research Loop (Autonomous Deep Dive)
*Do not wait for permission. Explore the context immediately.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> I am entering **Phase 1: Research Loop** to investigate ___.
> I will explore autonomously using `§CMD_TRACK_PROGRESS` and `§CMD_APPEND_LOG` continuously.
> Analytical focus applies — `§CMD_REFUSE_OFF_COURSE` if I drift.

### A. Exploration Strategy
Iterate through the loaded files/docs using the **Research Topics** from the selected mode preset. Do not just read — **Interrogate**.

### B. The Logging Stream (Your Scratchpad)
For *every* significant thought, execute `§CMD_APPEND_LOG`.
**Constraint**: **BLIND WRITE**. Do not re-read the file. See `§CMD_TRUST_CACHED_CONTEXT`.
**Constraint**: **High Volume**. Aim for **5-20 log entries** per session.
**Rule**: A thin log leads to a shallow report. You need raw material.
**Cadence**: Log at least **5 items** before moving to Calibration.

### Phase Transition
Execute `§CMD_GATE_PHASE`:
  custom: "Skip to Phase 3: Synthesis | Findings are clear, ready to write the report"

---

## 2. The Calibration Phase (Interactive)
*After you have logged a significant batch of findings (5+), STOP and turn to the user.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> I am entering **Phase 2: Calibration** with ___ findings logged.
> I will `§CMD_INTERROGATE` to align analysis direction with the user.
> Feedback will be recorded via `§CMD_LOG_INTERACTION`.

**Action**: First, ask the user to choose calibration depth. Then execute rounds.

### Calibration Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should calibration go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Findings are clear, user just needs to confirm direction |
| **Medium** | 6+ | Moderate complexity, some findings need user input |
| **Long** | 9+ | Complex analysis, many open questions, need deep alignment |
| **Absolute** | Until ALL questions resolved | Critical research, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Calibration Protocol (Rounds)

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the **Calibration Topics** defined in the selected mode preset. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

**Repeatable topics** (available in all modes, can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_INTERACTION` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Calibration Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 3: Synthesis"** — *(terminal: if selected, skip all others and move on)*
> - **"More calibration (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Calibration complete. How to proceed with synthesis?"
> - **"Launch analyzer agent"** — Hand off to autonomous agent for synthesis (you'll get the report when done)
> - **"Continue inline"** — Write synthesis in this conversation
> - **"Return to Phase 1: Research Loop"** — More exploration needed before synthesis

---

## 2.1. Agent Handoff (Opt-In)
*Only if user selected "Launch analyzer agent" in Phase 2 transition.*

Execute `§CMD_HANDOFF_TO_AGENT` with:
```yaml
agentName: "analyzer"
startAtPhase: "Phase 3: Synthesis"
planOrDirective: "Synthesize research findings into ANALYSIS.md following the template. Focus on: [calibration-agreed themes and questions]"
logFile: ANALYSIS_LOG.md
debriefTemplate: assets/TEMPLATE_ANALYSIS.md
logTemplate: assets/TEMPLATE_ANALYSIS_LOG.md
taskSummary: "Synthesize analysis: [brief description from taskSummary]"
```

**If "Continue inline"**: Proceed to Phase 3 as normal.

---

## 3. The Synthesis (Debrief)
*When the user is satisfied.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> I am entering **Phase 3: Synthesis** to write the analysis report.
> I will execute `§CMD_RUN_SYNTHESIS_PIPELINE` to process checklists, write the debrief, triage findings, run the pipeline, and close.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execute `§CMD_RUN_SYNTHESIS_PIPELINE`**

**Debrief creation notes** (for Step 1 -- `§CMD_GENERATE_DEBRIEF`):
*   Dest: `ANALYSIS.md`
*   **Synthesize**: Don't just summarize. Connect the dots between Log entries.
*   **Identify Themes**: Group isolated findings into "Strategic Themes".
*   **Highlight**: Top Risks and Sparks.
*   **Recommend**: Concrete next steps.

**Skill-specific step** (between Steps 1 and 2 of `§CMD_RUN_SYNTHESIS_PIPELINE`):

### 3.3. Finding Triage (Action Planning)
*Convert analysis into action. Walk through each finding with the user and decide its fate.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> I am entering **Phase 3.3: Finding Triage** to convert findings into action items.
> I will execute `§CMD_WALK_THROUGH_RESULTS` with the mode's walk-through config.
> Decisions will be logged to DETAILS.md.

Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** from the selected mode preset.

**Walk-through config** (for Step 3 -- `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  (uses Walk-Through Config from the selected mode preset)
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_RESUME_AFTER_DEBRIEF`.
