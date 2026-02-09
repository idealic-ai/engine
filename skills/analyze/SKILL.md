---
name: analyze
description: "Thorough analysis of code, architecture, or topics — produces a structured research report. Supports goal-based modes: Explore (general research), Audit (risk-focused critique), Improve (actionable suggestions), Custom (user-defined lens). Triggers: \"analyze this code\", \"deep dive into\", \"research this topic\", \"investigate how X works\", \"audit this\", \"critique this\", \"suggest improvements\", \"find risks in\"."
version: 3.0
tier: protocol
---

Thorough analysis of code, architecture, or topics — produces a structured research report.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 0 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 0 until every blank is filled.

# Deep Research Protocol

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

---

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "ANALYSIS",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup"},
    {"major": 1, "minor": 0, "name": "Context Ingestion"},
    {"major": 2, "minor": 0, "name": "Research Loop"},
    {"major": 3, "minor": 0, "name": "Calibration"},
    {"major": 3, "minor": 1, "name": "Agent Handoff"},
    {"major": 4, "minor": 0, "name": "Synthesis"},
    {"major": 4, "minor": 1, "name": "Finding Triage"}
  ],
  "nextSkills": ["/brainstorm", "/implement", "/document", "/fix", "/chores"],
  "provableDebriefItems": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK", "/delegation-review"],
  "directives": [],
  "logTemplate": "~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md",
  "debriefTemplate": "~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS.md",
  "modes": {
    "explore": {"label": "Explore", "description": "Broad, curiosity-driven investigation", "file": "~/.claude/skills/analyze/modes/explore.md"},
    "audit": {"label": "Audit", "description": "Adversarial, risk-focused critique", "file": "~/.claude/skills/analyze/modes/audit.md"},
    "improve": {"label": "Improve", "description": "Constructive, actionable suggestions", "file": "~/.claude/skills/analyze/modes/improve.md"},
    "custom": {"label": "Custom", "description": "User provides framing, agent blends modes", "file": "~/.claude/skills/analyze/modes/custom.md"}
  }
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is ANALYSIS (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Analysis Mode** (Explore / Audit / Improve / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md` (Template for continuous research logging)
    *   `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS.md` (Template for final research synthesis/report)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Subject] and [Question] provided by the user.

5.1. **Analysis Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What analysis lens should I use?"
    > - **"Explore" (Recommended)** — General research: understand, critique, and innovate
    > - **"Audit"** — Risk-focused: hunt for flaws, failure modes, and hidden assumptions
    > - **"Improve"** — Suggestion-focused: find actionable improvements with clear ROI
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, Research Topics, Calibration Topics, and Walk-Through Config.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/explore.md`, `modes/audit.md`, `modes/improve.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 Step 6 role (from mode file)
    *   Phase 2 research topics (from mode file)
    *   Phase 3 calibration topics (from mode file)
    *   Phase 4.1 walk-through config (from mode file)

6.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

7.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 1.
    *   *Why?* To ensure analysis includes the most recent intents and behavior changes.

### §CMD_VERIFY_PHASE_EXIT — Phase 0
**Output this block in chat with every blank filled:**
> **Phase 0 proof:**
> - Mode: `________` (explore / audit / improve / custom)
> - Role: `________` (quote the role name from the mode preset)
> - Session dir: `________`
> - taskType: `________`
> - Templates loaded: `________`, `________`
> - Active alerts: `________ found` or `none`

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Context Ingestion
*Load the raw materials before processing.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - RAG session-search: `________ results` or `unavailable`
> - RAG doc-search: `________ results` or `unavailable`
> - Files loaded: `________ files`
> - User confirmed: `yes / no`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "1: Context Ingestion"
  nextPhase: "2: Research Loop"
  prevPhase: "0: Setup"
  custom: "Skip to Phase 3: Calibration | I want to guide the analysis direction before research begins"

---

## 2. The Research Loop (Autonomous Deep Dive)
*Do not wait for permission. Explore the context immediately.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Research Loop.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to organize my investigation.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_ANALYSIS_LOG.md` EXACTLY) to `§CMD_THINK_IN_LOG` continuously.
> 4. I will maintain strict analytical focus (`§CMD_REFUSE_OFF_COURSE` applies).
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### A. Exploration Strategy
Iterate through the loaded files/docs using the **Research Topics** from the selected mode preset. Do not just read — **Interrogate**.

### B. The Logging Stream (Your Scratchpad)
For *every* significant thought, execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.
**Constraint**: **BLIND WRITE**. Do not re-read the file. See `§CMD_AVOID_WASTING_TOKENS`.
**Constraint**: **TIMESTAMPS**. Every log entry MUST start with `[YYYY-MM-DD HH:MM:SS]` in the header.
**Constraint**: **High Volume**. Aim for **5-20 log entries** per session. Do not be lazy.
**Rule**: A thin log leads to a shallow report. You need raw material.
**Cadence**: Log at least **5 items** before moving to Calibration.

### 🧠 Thought Triggers (When to Log)
*Review this list before every tool call. If your state matches, log it.*

*   **Found a Fact?** -> Log `🔍 Discovery` (The Fact, The Evidence).
*   **Found a Flaw?** -> Log `⚠️ Weakness` (The Risk, The Impact).
*   **Saw a Pattern?** -> Log `🔗 Connection` (Link A <-> B).
*   **Had an Idea?** -> Log `💡 Spark` (The Innovation, The Benefit).
*   **Missing Info?** -> Log `❓ Gap` (What is unknown?).

**Rule**: Dump your thoughts continuously. Do not filter for "high polish" yet—capture the raw insight.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Log entries written: `________` (minimum 5)
> - Key finding: `________` (one-liner of strongest insight)
> - Open gaps: `________` (count of unresolved questions)

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "2: Research Loop"
  nextPhase: "3: Calibration"
  prevPhase: "1: Context Ingestion"
  custom: "Skip to Phase 4: Synthesis | Findings are clear, ready to write the report"

---

## 3. The Calibration Phase (Interactive)
*After you have logged a significant batch of findings (5+), STOP and turn to the user.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Calibration.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to align direction with the user.
> 3. I will `§CMD_LOG_TO_DETAILS` to record the feedback.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

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

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the **Calibration Topics** defined in the selected mode preset. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

**Repeatable topics** (available in all modes, can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Calibration Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 4: Synthesis"** — *(terminal: if selected, skip all others and move on)*
> - **"More calibration (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Calibration complete. How to proceed with synthesis?"
> - **"Launch analyzer agent"** — Hand off to autonomous agent for synthesis (you'll get the report when done)
> - **"Continue inline"** — Write synthesis in this conversation
> - **"Return to Phase 2: Research Loop"** — More exploration needed before synthesis

---

## 3.1. Agent Handoff (Opt-In)
*Only if user selected "Launch analyzer agent" in Phase 3 transition.*

Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"analyzer"`
*   `startAtPhase`: `"Phase 4: The Synthesis Phase"`
*   `planOrDirective`: `"Synthesize research findings into ANALYSIS.md following the template. Focus on: [calibration-agreed themes and questions]"`
*   `logFile`: `ANALYSIS_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS.md`
*   `logTemplate`: `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md`
*   `taskSummary`: `"Synthesize analysis: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 4 as normal.

---

## 4. The Synthesis Phase (Final)
*When the user is satisfied.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` to process any discovered CHECKLIST.md files.
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_ANALYSIS.md` EXACTLY) to structure the research.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to deliver the final report.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The analysis FILE is the primary deliverable — chat output alone is not sufficient.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `ANALYSIS.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Synthesize**: Don't just summarize. Connect the dots between Log entries.
  *   **Identify Themes**: Group isolated findings into "Strategic Themes".
  *   **Highlight**: Top Risks and Sparks.
  *   **Recommend**: Concrete next steps.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - ANALYSIS.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "4: Synthesis"
  nextPhase: "4.1: Finding Triage"
  prevPhase: "3: Calibration"
  custom: "Skip to close | The report is enough, close the session"

---

## 4.1. Finding Triage (Action Planning)
*Convert analysis into action. Walk through each finding with the user and decide its fate.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4.1: Finding Triage.
> 2. I will execute `§CMD_WALK_THROUGH_RESULTS` to walk through each finding.
> 3. Decisions will be logged to DETAILS.md.

Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** from the selected mode preset.

### §CMD_VERIFY_PHASE_EXIT — Phase 4.1
**Output this block in chat with every blank filled:**
> **Phase 4.1 proof:**
> - Findings triaged: `________` / `________`
> - Delegated: `________`
> - Deferred: `________`
> - Dismissed: `________`

---

**Step 4**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
