---
name: brainstorm
description: "Structured ideation and trade-off analysis for design and architecture decisions. Triggers: \"brainstorm ideas\", \"explore this problem\", \"think through trade-offs\", \"challenge assumptions\", \"discuss architecture\"."
version: 2.0
tier: protocol
---

Structured ideation and trade-off analysis for design and architecture decisions.
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

# Brainstorming Protocol (The Socratic Engine)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

### Phases (for §CMD_PARSE_PARAMETERS)
*Include this array in the `phases` field when calling `session.sh activate`:*
```json
[
  {"major": 1, "minor": 0, "name": "Setup"},
  {"major": 2, "minor": 0, "name": "Context Ingestion"},
  {"major": 3, "minor": 0, "name": "Dialogue Loop"},
  {"major": 3, "minor": 1, "name": "Agent Handoff"},
  {"major": 4, "minor": 0, "name": "Synthesis"}
]
```
*Phase enforcement (¶INV_PHASE_ENFORCEMENT): transitions must be sequential. Use `--user-approved` for skip/backward.*

## Mode Presets

Brainstorm modes configure the agent's ideation style — role, dialogue topics, and convergence approach. The mode is selected in Phase 1 via `AskUserQuestion`. Full mode definitions are in `modes/*.md` files.

| Mode | Description | When to Use |
|------|-------------|-------------|
| **Explore** | Wide ideation, divergent, creative | Default — open-ended exploration |
| **Focused** | Decision-oriented, trade-off analysis | Specific choice point, need recommendation |
| **Adversarial** | Stress-test assumptions, devil's advocate | Challenge existing ideas, find risks |
| **Custom** | Reads all 3 modes, synthesizes a hybrid | User provides framing, agent blends modes |

**Mode files**: `~/.claude/skills/brainstorm/modes/{explore,focused,adversarial,custom}.md`

---

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is BRAINSTORM (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Brainstorm Mode** (Explore / Focused / Adversarial / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project structure and file map)
    *   `~/.claude/skills/brainstorm/assets/TEMPLATE_BRAINSTORM_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/brainstorm/assets/TEMPLATE_BRAINSTORM.md` (Template for final session debrief/report)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Goal].

5.1. **Brainstorm Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What brainstorm approach should I use?"
    > - **"Explore" (Recommended)** — Open-ended ideation: generate options, challenge assumptions, map trade-offs
    > - **"Focused"** — Decision-oriented: narrow down choices, evaluate trade-offs, reach a recommendation
    > - **"Adversarial"** — Stress-test mode: poke holes, find weaknesses, challenge every assumption
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Dialogue Topics.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/explore.md`, `modes/focused.md`, `modes/adversarial.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 1 role (from mode file)
    *   Phase 3 dialogue topics (from mode file)

6.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

7.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Mode: `________` (explore / focused / adversarial / custom)
> - Role: `________` (quote the role name from the mode preset)
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
> - **"Proceed to Phase 3: Dialogue Loop"** — Begin Socratic exploration of the problem space
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Synthesis"** — I already know what I want, just synthesize

---

## 3. The Dialogue Loop (Socratic Exploration)
*Engage in Socratic inquiry to uncover constraints and opportunities.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Dialogue Loop.
> 2. I will `§CMD_USE_TODOS_TO_TRACK_PROGRESS` to manage the discussion flow.
> 3. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to explore the problem space.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture Q&A and `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to track internal thoughts.
> 5. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

**Action**: First, ask the user to choose dialogue depth. Then execute rounds.

### Dialogue Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should the brainstorming dialogue go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Narrow topic, clear constraints, quick exploration |
| **Medium** | 6+ | Moderate complexity, several trade-offs to explore |
| **Long** | 9+ | Complex architecture, many stakeholders, deep design space |
| **Absolute** | Until ALL questions resolved | Novel domain, critical decision, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "converge" after the minimum is met.

### Dialogue Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

**Each round follows the Socratic pattern**:

#### Step A: Listen & Analyze
*   **Input**: Read the user's latest message.
*   **Check**: Did they answer a question? Did they pose a new constraint?
*   **Action**: Execute `§CMD_LOG_TO_DETAILS` immediately to capture this interaction.

#### Step B: The Logging Stream (Capture Reality)
*   **Action**: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` - log your *internal* thoughts.
*   **Scope**: Use `BRAINSTORM_LOG.md` for *internal* decisions, alternatives, and risks.
*   **Constraint**: **BLIND WRITE**. Do not re-read the file.
*   **Constraint**: **Separation of Concerns**.
    *   User Interaction -> `DETAILS.md`
    *   Internal Monologue -> `BRAINSTORM_LOG.md`

#### Step C: The Socratic Response
*   **Action**: Reply to the user with questions on the next topic.
*   **Style**:
    1.  **Validate**: "I see why you want X..."
    2.  **Challenge**: "...but have you considered the latency cost?"
    3.  **Propose**: "What if we did Z instead?"
    4.  **Explore**: "How would that handle edge case Q?"

### 🧠 Thought Triggers (When to Log)
*Review this list before every tool call. If your state matches, log it.*

*   **Made a Decision?** -> Log `🏛️ Decision` (Topic, Verdict, Reasoning).
*   **Rejected an Option?** -> Log `🔄 Alternative` (Option, Why Rejected).
*   **Found a Constraint?** -> Log `🛑 Constraint` (Rule, Source).
*   **Identified Risk?** -> Log `⚠️ Risk` (Fear, Scenario).
*   **Have a Concern?** -> Log `😟 Concern` (Topic, Detail).
*   **Open Question?** -> Log `❓ Question` (Asking, Context).
*   **Diverging?** -> Log `🔀 Divergence` (Trigger, Action).
*   **Converging?** -> Log `🤝 Convergence` (Theme, Principle).
*   **Parking Item?** -> Log `🅿️ Parking Lot` (Item, Reason).

### Dialogue Topics (Brainstorm)
*Examples of themes to explore. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Problem framing** — is the problem well-defined, are we solving the right thing
- **Constraints & non-negotiables** — hard requirements, budget, timeline, compliance
- **Stakeholders & perspectives** — who is affected, whose input matters, conflicting needs
- **Prior attempts** — what has been tried, what worked/failed, lessons learned
- **Wild ideas & provocations** — 10x solutions, unreasonable approaches, creative leaps
- **Feasibility** — technical viability, resource requirements, complexity assessment
- **Priorities & trade-offs** — what to optimize for, what to sacrifice, ranking criteria
- **Adjacent domains** — inspiration from other fields, analogous problems, transferable patterns
- **Risks of inaction** — what happens if we do nothing, cost of delay
- **Evaluation criteria** — how to judge solutions, metrics for success

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

### Dialogue Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 4: Synthesis"** — *(terminal: if selected, skip all others and move on)*
> - **"More dialogue (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Dialogue depth: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`
> - BRAINSTORM_LOG.md entries: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Dialogue complete. How to proceed with convergence?"
> - **"Launch analyzer agent"** — Hand off to autonomous agent for convergence synthesis (you'll get the report when done)
> - **"Continue inline"** — Write convergence in this conversation
> - **"Stay in Phase 3"** — More exploration needed

---

## 3.1. Agent Handoff (Opt-In)
*Only if user selected "Launch analyzer agent" in Phase 3 transition.*

Execute `§CMD_HAND_OFF_TO_AGENT` with:
*   `agentName`: `"analyzer"`
*   `startAtPhase`: `"Phase 4: Synthesis"`
*   `planOrDirective`: `"Synthesize brainstorming findings into BRAINSTORM.md following the template. Focus on: [key themes and decisions from dialogue]"`
*   `logFile`: `BRAINSTORM_LOG.md`
*   `debriefTemplate`: `~/.claude/skills/brainstorm/assets/TEMPLATE_BRAINSTORM.md`
*   `logTemplate`: `~/.claude/skills/brainstorm/assets/TEMPLATE_BRAINSTORM_LOG.md`
*   `taskSummary`: `"Synthesize brainstorm: [brief description from taskSummary]"`

**If "Continue inline"**: Proceed to Phase 4 as normal.

---

## 4. Synthesis
*When the dialogue has explored the space sufficiently.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` to process any discovered CHECKLIST.md files.
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_BRAINSTORM.md` EXACTLY) to summarize findings into a permanent record.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to formally close the session and list outputs.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 or 4 without completing step 1. The brainstorm FILE is the primary deliverable — chat output alone is not sufficient.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `BRAINSTORM.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Reflect**: Look back at the full session — identify key takeaways.
  *   **Synthesize**: Don't just summarize. Connect the dots between dialogue rounds.
  *   **Next Steps**: Propose the move to `IMPLEMENTATION` or `ANALYSIS` — guide the user.

**Step 2**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 3**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 4**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Brainstorm complete. Walk through ideas?"
  debriefFile: "BRAINSTORM.md"
  templateFile: "~/.claude/skills/brainstorm/assets/TEMPLATE_BRAINSTORM.md"
  actionMenu:
    - label: "Implement this idea"
      tag: "#needs-implementation"
      when: "Idea is ready to build"
    - label: "Research feasibility"
      tag: "#needs-research"
      when: "Idea needs validation or deeper investigation before committing"
    - label: "Prototype first"
      tag: "#needs-implementation"
      when: "Idea is promising but needs a quick proof of concept"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - BRAINSTORM.md: `________` (real file path)
> - Tags: `________`
> - Artifacts listed: `________`
> - Summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 5**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Brainstorm complete. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/implement` (Recommended) | Ideas formed — start building |
| 2 | `/analyze` | Need deeper research before committing to an approach |
| 3 | `/document` | Capture the brainstorm as a design document |
| 4 | `/debug` | Brainstorm revealed an issue — investigate it |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
