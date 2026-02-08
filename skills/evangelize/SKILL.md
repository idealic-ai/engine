---
name: evangelize
description: "Crafts compelling narratives around completed work for stakeholder communication. Triggers: \"sell this work\", \"frame for stakeholders\", \"write an announcement\", \"generate enthusiasm\"."
version: 2.0
tier: protocol
---

Crafts compelling narratives around completed work for stakeholder communication.
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

# Evangelism Protocol (Strategic Impact & Vision)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

### Phases (for §CMD_PARSE_PARAMETERS)
*Include this array in the `phases` field when calling `session.sh activate`:*
```json
[
  {"major": 1, "minor": 0, "name": "Setup"},
  {"major": 2, "minor": 0, "name": "Context Ingestion"},
  {"major": 3, "minor": 0, "name": "Autonomous Analysis"},
  {"major": 4, "minor": 0, "name": "Interrogation"},
  {"major": 4, "minor": 1, "name": "Agent Handoff"},
  {"major": 5, "minor": 0, "name": "Synthesis"}
]
```
*Phase enforcement (¶INV_PHASE_ENFORCEMENT): transitions must be sequential. Use `--user-approved` for skip/backward.*

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is EVANGELISM (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Product Strategist** and **Tech Visionary**.
    >    **Goal**: To translate code into **Value**. We are not just documenting *what* we built, but *why it matters* and *what it unlocks*.
    >    **Mindset**: Connect the dots. How does a low-level refactor enable a high-level competitive advantage? Find the coolness, the angles, the paths forward.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/evangelize/assets/TEMPLATE_EVANGELISM_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/evangelize/assets/TEMPLATE_EVANGELISM.md` (Template for final session debrief/report — check `.claude/skills/evangelize/assets/TEMPLATE_EVANGELISM.md` first for project-local override)

    *Note: The `assets/` template files are critical — they define the exact structure for your logs and reports.*

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the recent [IMPLEMENTATION] or [BUGFIX] and its implications.

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.
    *   *Why?* To ensure evangelism includes the most recent intents and behavior changes.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`
> - Parameters parsed: `________`

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
> - **"Proceed to Phase 3: Horizon Mapping"** — Begin autonomous analysis of strategic value
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Interrogation"** — I want to guide the narrative direction before analysis begins

---

## 3. Autonomous Analysis (Horizon Mapping)
*Scan the code and identify the strategic ripples.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Autonomous Analysis.
> 2. I will `§CMD_THINK_IN_LOG` to identify candidates for the Three Horizons.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` using `EVANGELISM_LOG.md` to record initial findings.
> 4. I will maintain strict evangelism focus (`§CMD_REFUSE_OFF_COURSE` applies).
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### Horizon Search
1.  **Horizon 1 (User Value)**: Immediate pain solved or delight added.
2.  **Horizon 2 (Dev Velocity)**: Why is the *next* feature 2x faster to build?
3.  **Horizon 3 (The Moat)**: What "impossible" feature is now possible?

### Initial Angles
Before entering interrogation, identify at least 3 distinct "coolness angles" — different framings of why this work matters. Log them to `EVANGELISM_LOG.md`.

### The Logging Stream (Your Scratchpad)
For *every* significant thought, execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.
**Constraint**: **BLIND WRITE**. Do not re-read the file. See `§CMD_AVOID_WASTING_TOKENS`.
**Constraint**: **TIMESTAMPS**. Every log entry MUST start with `[YYYY-MM-DD HH:MM:SS]` in the header.
**Constraint**: **High Volume**. Aim for **5-20 log entries** per session. Do not be lazy.
**Rule**: A thin log leads to a shallow report. You need raw material.
**Cadence**: Log at least **5 items** before moving to Interrogation.

### 🧠 Thought Triggers (When to Log)
*Review this list before every tool call. If your state matches, log it.*

*   **Discovered a new angle?** -> Log `🔓 Angle` (Framing, Why It Matters).
*   **User revealed something surprising?** -> Log `💡 Spark` (Insight, Implication).
*   **Found a weakness in the narrative?** -> Log `🔍 Gap` (What's Missing, How to Address).
*   **Identified a stakeholder perspective?** -> Log `👤 Audience` (Who, What They Care About).
*   **Devil's advocate found a real concern?** -> Log `⚠️ Challenge` (Objection, Strength of Concern).
*   **Convergence on a strong narrative?** -> Log `🎯 Narrative` (Theme, Supporting Evidence).

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Context files explored: `________`
> - EVANGELISM_LOG.md entries: `________` (minimum 5)
> - Coolness angles identified: `________` (minimum 3)
> - Three Horizons assessed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Horizon mapping complete. How to proceed?"
> - **"Proceed to Phase 4: Interrogation"** — Explore value surface through deep-dive dialogue
> - **"Stay in Phase 3"** — Continue exploring, more angles to discover
> - **"Skip to Phase 5: Synthesis"** — Findings are clear, ready to write the report

---

## 4. The Interrogation (Deep-Dive Dialogue)
*Explore the value of the work through adaptive, multi-round questioning.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: The Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to explore the full value surface of these changes.
> 3. I will `§CMD_LOG_TO_DETAILS` after each round to capture Q&A verbatim.
> 4. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to capture internal thoughts and evolving angles.
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: First, ask the user to choose interrogation depth. Then execute rounds.

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should the interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Narrative is clear, user just needs to confirm angles |
| **Medium** | 6+ | Moderate complexity, some angles need user input |
| **Long** | 9+ | Complex work, many stakeholder perspectives, need deep alignment |
| **Absolute** | Until ALL questions resolved | Critical announcement, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Interrogation Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

### Interrogation Topics (Evangelism)
*Examples of themes to explore. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Target audience** — who is the primary audience for this narrative, what do they care about
- **Key message** — what is the single most important takeaway, the "headline"
- **Evidence quality** — what concrete data/metrics/examples support the narrative
- **Objection handling** — what are the likely pushbacks, how to preemptively address them
- **Call to action** — what should the audience DO after hearing this, what's the next step
- **Comparison points** — how does this compare to alternatives, competitors, or the previous state
- **Success metrics** — how will we know the narrative landed, what response indicates success

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
   *   Questions should be provocative and specific, not generic.
   *   Reference concrete code/architecture from the context — "Now that `extractScopeData` runs per-page instead of per-document, what if..."
   *   Adapt based on what the user revealed in previous rounds.
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. Reflect: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` — log new angles discovered, revised assessments, surprises.
5. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 5: Synthesis"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
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
> - Key angles refined: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 4: Interrogation complete. How to proceed with synthesis?"
> - **"Launch evangelism agent"** — Hand off to autonomous agent for synthesis (you'll get the report when done)
> - **"Continue inline"** — Write synthesis in this conversation
> - **"Return to Phase 3: Horizon Mapping"** — More exploration needed before synthesis

---

## 4.1. Agent Handoff (Opt-In)
*Only if user selected "Launch evangelism agent" in Phase 4 transition.*

Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"evangelist"`
*   `startAtPhase`: `"Phase 5: The Synthesis"`
*   `planOrDirective`: `"Synthesize evangelism findings into EVANGELISM.md following the template. Focus on: [interrogation-agreed angles and narratives]"`
*   `logFile`: `EVANGELISM_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/evangelize/assets/TEMPLATE_EVANGELISM.md`
*   `logTemplate`: `~/.claude/skills/evangelize/assets/TEMPLATE_EVANGELISM_LOG.md`
*   `taskSummary`: `"Synthesize evangelism: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 5 as normal.

---

## 5. The Synthesis (The Strategic Impact Report)
*When the user is satisfied.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` to process any discovered CHECKLIST.md files.
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_EVANGELISM.md` EXACTLY) to structure the report.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to deliver the final report.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The evangelism FILE is the primary deliverable — chat output alone is not sufficient.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `EVANGELISM.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Reflect**: Look back at your memory of the session — identify key angles, strongest narratives, devil's advocate challenges that were overcome.
  *   **Synthesize**: Don't just summarize. Connect the dots between Log entries. Weave the Three Horizons into a coherent story.
  *   **Next Steps**: Propose how to capitalize on the win — guide the user.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 4**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Evangelism complete. Walk through the key narrative elements?"
  debriefFile: "EVANGELISM.md"
  templateFile: "~/.claude/skills/evangelize/assets/TEMPLATE_EVANGELISM.md"
  actionMenu:
    - label: "Needs implementation"
      tag: "#needs-implementation"
      when: "An unlock path or next step requires code changes"
    - label: "Needs research"
      tag: "#needs-research"
      when: "A claim or angle needs data validation"
    - label: "Needs documentation"
      tag: "#needs-documentation"
      when: "Narrative insights should be captured in project docs"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 5 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - EVANGELISM.md written: `________` (real file path)
> - Tags line: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 5**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Evangelism complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/analyze` (Recommended) | Feedback received — analyze it |
| 2 | `/brainstorm` | New ideas from sharing — explore them |
| 3 | `/implement` | Action items from evangelism — build them |
| 4 | `/document` | Update docs based on feedback |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
