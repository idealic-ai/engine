---
name: analyze
description: "Thorough analysis of code, architecture, or topics — produces a structured research report. Supports goal-based modes: Explore (general research), Audit (risk-focused critique), Improve (actionable suggestions), Custom (user-defined lens). Triggers: \"analyze this code\", \"deep dive into\", \"research this topic\", \"investigate how X works\", \"audit this\", \"critique this\", \"suggest improvements\", \"find risks in\"."
version: 3.0
tier: protocol
---

Thorough analysis of code, architecture, or topics — produces a structured research report.

# Deep Research Protocol

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "ANALYSIS",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed"],
      "gate": false},
    {"label": "1", "name": "Research Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_TRACK_PROGRESS", "§CMD_ASK_USER_IF_STUCK"],
      "proof": ["logEntries", "keyFinding", "openGaps"]},
    {"label": "2", "name": "Calibration",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depthChosen", "roundsCompleted"]},
    {"label": "3", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "3.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "3.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "3.3", "name": "Finding Triage",
      "steps": ["§CMD_WALK_THROUGH_RESULTS"], "commands": [], "proof": ["findingsTriaged", "delegated", "deferred", "dismissed"]},
    {"label": "3.4", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "3.5", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/brainstorm", "/implement", "/document", "/fix", "/chores"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_ANALYSIS_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_ANALYSIS.md",
  "requestTemplate": "assets/TEMPLATE_ANALYSIS_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_ANALYSIS_RESPONSE.md",
  "modes": {
    "explore": {"label": "Explore", "description": "Broad, curiosity-driven investigation", "file": "modes/explore.md"},
    "audit": {"label": "Audit", "description": "Adversarial, risk-focused critique", "file": "modes/audit.md"},
    "improve": {"label": "Improve", "description": "Constructive, actionable suggestions", "file": "modes/improve.md"},
    "custom": {"label": "Custom", "description": "User provides framing, agent blends modes", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Analyzing ___. Trigger: ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the [Subject] and [Question] provided by the user.

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, Research Topics, Calibration Topics, and Walk-Through Config.

**On "Custom"**: Read ALL 3 named mode files first (`modes/explore.md`, `modes/audit.md`, `modes/improve.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 research topics (from mode file)
*   Phase 2 calibration topics (from mode file)
*   Phase 3.3 walk-through config (from mode file)



---

## 1. Research Loop (Autonomous Deep Dive)
*Do not wait for permission. Explore the context immediately.*

§CMD_REPORT_INTENT:
> 1: Researching ___. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### A. Exploration Strategy
Iterate through the loaded files/docs using the **Research Topics** from the selected mode preset. Do not just read — **Interrogate**.

### B. The Logging Stream (Your Primary Output)
For *every* significant thought, execute `§CMD_APPEND_LOG`. **Logging is the core activity of analysis** — without rich log entries, downstream synthesis and the final report will be shallow and uninformative.
*   **High Volume**: Aim for **10-30 log entries** per session. More is better.
*   A thin log leads to a thin report. The log IS the raw material for everything downstream — the debrief, the finding triage, the action items. Every unlogged thought is a lost insight.
*   **Cadence**: Log at least **8 items** before moving to Calibration.
*   **Variety**: Use ALL available log schemas (Discovery, Weakness, Connection, Spark, Gap, Pattern, Tradeoff, Assumption, Strength). Varied entry types produce richer analysis.

---

## 2. Calibration (Interactive)
*After you have logged a significant batch of findings (8+), STOP and turn to the user.*

§CMD_REPORT_INTENT:
> 2: Calibrating with ___ findings logged. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Findings Summary**: Before asking any calibration questions, present a condensed summary of what was found during the Research Loop. Format as a numbered list of key findings (one line each), grouped by log entry type. This gives the user context to calibrate effectively — they can't guide the analysis if they don't know what was found.

**Action**: Present the findings summary, then ask the user to choose calibration depth. Then execute rounds.

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
> - **"Return to Research Loop"** — Go back to Phase 1 for more autonomous exploration based on calibration insights, then re-enter Calibration
> - **"More calibration (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Return to Research first (if selected, ignore all others — jump to Phase 1) -> Standard rounds -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

---

## 3. Synthesis
*When the user is satisfied.*

§CMD_REPORT_INTENT:
> 3: Synthesizing. ___ findings logged, ___ calibration rounds completed.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

**Debrief notes** (for `ANALYSIS.md`):
*   **Synthesize**: Don't just summarize. Connect the dots between Log entries.
*   **Identify Themes**: Group isolated findings into "Strategic Themes".
*   **Highlight**: Top Risks and Sparks.
*   **Recommend**: Concrete next steps.

### 3.3. Finding Triage (Action Planning)
*Convert analysis into action. Walk through each finding with the user and decide its fate.*

§CMD_REPORT_INTENT:
> 3.3: Triaging ___ findings into action items.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.3.*)

Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** from the selected mode preset.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  (uses Walk-Through Config from the selected mode preset)
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_RESUME_AFTER_CLOSE`.
