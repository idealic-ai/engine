---
name: analyze
description: "Thorough analysis of code, architecture, or topics — produces a structured research report. Supports goal-based modes: Explore (general research), Audit (risk-focused critique), Improve (actionable suggestions), Custom (user-defined lens). Triggers: \"analyze this code\", \"deep dive into\", \"research this topic\", \"investigate how X works\", \"audit this\", \"critique this\", \"suggest improvements\", \"find risks in\"."
version: 3.0
---

Thorough analysis of code, architecture, or topics — produces a structured research report.
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

# Deep Research Protocol

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

---

## Mode Presets

Analysis modes configure the agent's lens — role, research topics, calibration topics, and walk-through config. The mode is selected in Phase 1 Step 5b.

### Explore (General Research)
*Default mode. Broad, curiosity-driven investigation.*

**Role**: You are the **Deep Research Scientist**.
**Goal**: To deeply understand, critique, and innovate upon the provided context.
**Mindset**: Curious, Exhaustive, Skeptical, Connecting.

**Research Topics** (Phase 3):
- **Patterns**: How do components relate? Is there a hidden theme?
- **Weaknesses**: What feels fragile? What assumptions are unspoken?
- **Opportunities**: How could this be simpler? Faster? More elegant?
- **Contradictions**: Does Doc A say X while Code B does Y?

**Calibration Topics** (Phase 4):
- **Scope & boundaries** — what's included/excluded, depth expectations
- **Data sources & accuracy** — reliability of code/docs/data, known stale areas
- **Methodology** — analytical framework, comparison approach, evaluation criteria
- **Prior work & baselines** — existing analyses, benchmarks, known results
- **Gaps & unknowns** — what information is missing, what couldn't be determined
- **Output format & audience** — who reads the report, detail level
- **Assumptions** — what the agent assumed during research, validate with user
- **Dependencies & access** — external systems, data sources, tools needed
- **Time constraints** — exploration vs diminishing returns
- **Success criteria** — what would make this analysis "done" and valuable

**Walk-Through Config** (Phase 5b):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "ANALYSIS.md is written. Walk through findings?"
  debriefFile: "ANALYSIS.md"
  itemSources:
    - "## 3. Key Insights"
    - "## 4. The \"Iceberg\" Risks"
    - "## 5. Strategic Recommendations"
  actionMenu:
    - label: "Delegate to /implement"
      tag: "#needs-implementation"
      when: "Finding is an actionable code/config change"
    - label: "Delegate to /research"
      tag: "#needs-research"
      when: "Finding needs deeper investigation"
    - label: "Delegate to /brainstorm"
      tag: "#needs-implementation"
      when: "Finding needs exploration of approaches before implementation"
    - label: "Delegate to /debug"
      tag: "#needs-implementation"
      when: "Finding reveals a bug or regression"
```

### Audit (Risk-Focused Critique)
*Adversarial lens. Hunt for risks, flaws, and failure modes.*

**Role**: You are the **Adversarial Security Auditor**.
**Goal**: To find every risk, flaw, and hidden assumption that could cause failure.
**Mindset**: Suspicious, Methodical, Worst-Case, Unforgiving.

**Research Topics** (Phase 3):
- **Attack surface** — What are the entry points? What can be abused?
- **Failure modes** — What happens when things go wrong? Cascading failures?
- **Hidden assumptions** — What does the code assume that isn't guaranteed?
- **Edge cases** — Boundary conditions, empty states, concurrency, race conditions
- **Dependency risks** — Third-party fragility, version rot, supply chain
- **Data integrity** — Corruption paths, validation gaps, inconsistency windows
- **Security gaps** — Auth bypasses, injection points, privilege escalation
- **Performance cliffs** — What causes sudden degradation? Resource exhaustion?

**Calibration Topics** (Phase 4):
- **Threat model** — who are the adversaries, what's the blast radius
- **Risk tolerance** — acceptable vs unacceptable failure modes
- **Known vulnerabilities** — existing issues, past incidents, audit history
- **Compliance requirements** — regulatory, contractual, or policy constraints
- **Recovery capabilities** — backup, rollback, disaster recovery readiness
- **Monitoring & alerting** — can failures be detected? How fast?
- **Assumptions** — what the agent assumed during audit, validate with user
- **Scope boundaries** — what's in/out of the audit perimeter
- **Priority framework** — how to rank findings (severity × likelihood)
- **Success criteria** — what constitutes a thorough audit

**Walk-Through Config** (Phase 5b):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Audit complete. Walk through risks?"
  debriefFile: "ANALYSIS.md"
  itemSources:
    - "## 3. Key Insights"
    - "## 4. The \"Iceberg\" Risks"
    - "## 5. Strategic Recommendations"
  actionMenu:
    - label: "Fix immediately"
      tag: "#needs-implementation"
      when: "Risk is critical and has a clear fix"
    - label: "Investigate impact"
      tag: "#needs-research"
      when: "Risk severity is uncertain and needs analysis"
    - label: "Add test coverage"
      tag: "#needs-implementation"
      when: "Risk can be mitigated by better testing"
    - label: "Accept risk"
      tag: ""
      when: "Risk is known and accepted — document and move on"
```

### Improve (Actionable Suggestions)
*Constructive lens. Find concrete ways to make things better.*

**Role**: You are the **Senior Engineering Consultant**.
**Goal**: To produce actionable, prioritized improvement suggestions with clear ROI.
**Mindset**: Pragmatic, Constructive, Impact-Focused, Empathetic.

**Research Topics** (Phase 3):
- **Code quality** — Readability, maintainability, consistency, naming
- **Architecture** — Coupling, cohesion, separation of concerns, abstraction levels
- **Performance** — Bottlenecks, unnecessary work, caching opportunities
- **Developer experience** — Build times, test speed, onboarding friction, tooling gaps
- **Error handling** — Resilience, graceful degradation, error messages, recovery
- **Testing** — Coverage gaps, test quality, missing edge cases, flaky tests
- **Documentation** — Accuracy, completeness, discoverability, staleness
- **Security** — Input validation, auth patterns, data protection, secrets management
- **Scalability** — Growth bottlenecks, resource limits, data volume concerns
- **Tech debt** — Accumulated shortcuts, deprecated patterns, migration needs

**Calibration Topics** (Phase 4):
- **Improvement priorities** — what matters most to the team right now
- **Constraints** — time budget, team capacity, risk appetite for changes
- **Past attempts** — what's been tried before, what worked or didn't
- **Team context** — skill levels, ownership boundaries, velocity concerns
- **Success metrics** — how to measure if improvements worked
- **Quick wins vs deep work** — appetite for small fixes vs structural changes
- **Assumptions** — what the agent assumed, validate with user
- **Dependencies** — what blocks improvements, external factors
- **Adoption** — how changes will be rolled out, migration strategy
- **Success criteria** — what would make this improvement review valuable

**Walk-Through Config** (Phase 5b):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Suggestions ready. Walk through improvements?"
  debriefFile: "ANALYSIS.md"
  itemSources:
    - "## 3. Key Insights"
    - "## 4. The \"Iceberg\" Risks"
    - "## 5. Strategic Recommendations"
  actionMenu:
    - label: "Implement now"
      tag: "#needs-implementation"
      when: "Suggestion is actionable and high-value"
    - label: "Research first"
      tag: "#needs-research"
      when: "Suggestion needs validation or deeper understanding"
    - label: "Prototype first"
      tag: "#needs-implementation"
      when: "Suggestion is promising but needs a proof of concept"
    - label: "Brainstorm approaches"
      tag: "#needs-implementation"
      when: "Suggestion needs exploration of approaches before committing"
```

### Custom (User-Defined Lens)
*User provides their own role/goal/mindset. Uses Explore's topic lists as defaults.*

**Role**: *Set from user's free-text input.*
**Goal**: *Set from user's free-text input.*
**Mindset**: *Set from user's free-text input.*

**Research Topics**: Same as Explore mode.
**Calibration Topics**: Same as Explore mode.
**Walk-Through Config**: Same as Explore mode.

---

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is ANALYSIS (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Analysis Mode** (Explore / Audit / Improve / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md` (Template for continuous research logging)
    *   `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS.md` (Template for final research synthesis/report)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Subject] and [Question] provided by the user.

5b. **Analysis Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What analysis lens should I use?"
    > - **"Explore" (Recommended)** — General research: understand, critique, and innovate
    > - **"Audit"** — Risk-focused: hunt for flaws, failure modes, and hidden assumptions
    > - **"Improve"** — Suggestion-focused: find actionable improvements with clear ROI
    > - **"Custom"** — Define your own role, goal, and mindset

    **On "Custom"**: The user types their framing. Parse it into role/goal/mindset. Use Explore's topic lists as defaults.

    **Record**: Store the selected mode. It configures:
    *   Phase 1 Step 6 role (from mode preset)
    *   Phase 3 research topics (from mode preset)
    *   Phase 4 calibration topics (from mode preset)
    *   Phase 5b walk-through config (from mode preset)

6.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the Mode Presets section above.

7.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.
    *   *Why?* To ensure analysis includes the most recent intents and behavior changes.

8.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance to the current task.
    *   If relevant, factor them into research direction.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Mode: `________` (explore / audit / improve / custom)
> - Role: `________` (quote the role name from the mode preset)
> - Session dir: `________`
> - taskType: `________`
> - Templates loaded: `________`, `________`
> - Active alerts: `________ found` or `none`

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
> - **"Proceed to Phase 3: Research Loop"** — Begin autonomous deep dive into loaded context
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Calibration"** — I want to guide the analysis direction before research begins

---

## 3. The Research Loop (Autonomous Deep Dive)
*Do not wait for permission. Explore the context immediately.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Research Loop.
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

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Log entries written: `________` (minimum 5)
> - Key finding: `________` (one-liner of strongest insight)
> - Open gaps: `________` (count of unresolved questions)

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Research loop complete. How to proceed?"
> - **"Proceed to Phase 4: Calibration"** — Align research direction with user feedback
> - **"Stay in Phase 3"** — Continue exploring, more to discover
> - **"Skip to Phase 5: Synthesis"** — Findings are clear, ready to write the report

---

## 4. The Calibration Phase (Interactive)
*After you have logged a significant batch of findings (5+), STOP and turn to the user.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Calibration.
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
> - **"Proceed to Phase 5: Synthesis"** — *(terminal: if selected, skip all others and move on)*
> - **"More calibration (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 4: Calibration complete. How to proceed with synthesis?"
> - **"Launch analyzer agent"** — Hand off to autonomous agent for synthesis (you'll get the report when done)
> - **"Continue inline"** — Write synthesis in this conversation
> - **"Return to Phase 3: Research Loop"** — More exploration needed before synthesis

---

## 4b. Agent Handoff (Opt-In)
*Only if user selected "Launch analyzer agent" in Phase 4 transition.*

Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"analyzer"`
*   `startAtPhase`: `"Phase 5: The Synthesis Phase"`
*   `planOrDirective`: `"Synthesize research findings into ANALYSIS.md following the template. Focus on: [calibration-agreed themes and questions]"`
*   `logFile`: `ANALYSIS_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS.md`
*   `logTemplate`: `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md`
*   `taskSummary`: `"Synthesize analysis: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 5 as normal.

---

## 5. The Synthesis Phase (Final)
*When the user is satisfied.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Synthesis.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_ANALYSIS.md` EXACTLY) to structure the research.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to deliver the final report.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The analysis FILE is the primary deliverable — chat output alone is not sufficient.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `ANALYSIS.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Synthesize**: Don't just summarize. Connect the dots between Log entries.
  *   **Identify Themes**: Group isolated findings into "Strategic Themes".
  *   **Highlight**: Top Risks and Sparks.
  *   **Recommend**: Concrete next steps.

**Step 2**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 3**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 4**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

### §CMD_VERIFY_PHASE_EXIT — Phase 5 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - ANALYSIS.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "ANALYSIS.md is written. Want to triage findings into actions?"
> - **"Proceed to Phase 5b: Finding Triage"** — Walk through each finding and decide what to do with it
> - **"Skip to close"** — The report is enough, close the session

---

## 5b. Finding Triage (Action Planning)
*Convert analysis into action. Walk through each finding with the user and decide its fate.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5b: Finding Triage.
> 2. I will execute `§CMD_WALK_THROUGH_RESULTS` to walk through each finding.
> 3. Decisions will be logged to DETAILS.md.

Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** from the selected mode preset.

### §CMD_VERIFY_PHASE_EXIT — Phase 5b
**Output this block in chat with every blank filled:**
> **Phase 5b proof:**
> - Findings triaged: `________` / `________`
> - Delegated: `________`
> - Deferred: `________`
> - Dismissed: `________`

---

**Step 5**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Analysis complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/brainstorm` (Recommended) | Research done — explore solutions and approaches |
| 2 | `/implement` | Findings are clear — start building |
| 3 | `/document` | Capture the analysis as permanent documentation |
| 4 | `/debug` | Analysis revealed a bug — investigate and fix |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
