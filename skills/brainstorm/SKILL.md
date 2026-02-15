---
name: brainstorm
description: "Structured ideation and trade-off analysis for design and architecture decisions. Triggers: \"brainstorm ideas\", \"explore this problem\", \"think through trade-offs\", \"challenge assumptions\", \"discuss architecture\"."
version: 3.0
tier: protocol
---

Structured ideation and trade-off analysis for design and architecture decisions.

# Brainstorming Protocol (The Socratic Engine)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "BRAINSTORM",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed"]},
    {"label": "1", "name": "Dialogue Loop",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION", "§CMD_APPEND_LOG"],
      "proof": ["depthChosen", "roundsCompleted", "logEntries"]},
    {"label": "2", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": []},
    {"label": "2.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": []},
    {"label": "2.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"]},
    {"label": "2.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": []},
    {"label": "2.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": []}
  ],
  "nextSkills": ["/implement", "/analyze", "/document", "/fix", "/chores"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_BRAINSTORM_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_BRAINSTORM.md",
  "requestTemplate": "assets/TEMPLATE_BRAINSTORM_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_BRAINSTORM_RESPONSE.md",
  "modes": {
    "explore": {"label": "Explore", "description": "Wide ideation, divergent, creative", "file": "modes/explore.md"},
    "focused": {"label": "Focused", "description": "Decision-oriented, trade-off analysis", "file": "modes/focused.md"},
    "adversarial": {"label": "Adversarial", "description": "Stress-test assumptions, devil's advocate", "file": "modes/adversarial.md"},
    "custom": {"label": "Custom", "description": "User provides framing, agent blends modes", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT`:
> 0: Brainstorming ___ topic. Trigger: ___.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(0.*)`

*   **Scope**: Understand the [Topic] and [Goal].

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Dialogue Topics.

**On "Custom"**: Read ALL 3 named mode files first (`modes/explore.md`, `modes/focused.md`, `modes/adversarial.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 1 dialogue topics (from mode file)

---

## 1. Dialogue Loop (Socratic Exploration)
*Engage in Socratic inquiry to uncover constraints and opportunities.*

`§CMD_REPORT_INTENT`:
> 1: Exploring ___ problem space through Socratic dialogue.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(1.*)`

### Dialogue Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should the brainstorming dialogue go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Narrow topic, clear constraints, quick exploration |
| **Medium** | 6+ | Moderate complexity, several trade-offs to explore |
| **Long** | 9+ | Complex architecture, many stakeholders, deep design space |
| **Absolute** | Until ALL questions resolved | Novel domain, critical decision, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** -- the agent can always ask more, and the user can always say "converge" after the minimum is met.

### Dialogue Protocol (Rounds)

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence -- choose the most relevant uncovered topic based on what you've learned so far.

**Each round follows the Socratic pattern**:

#### Step A: Listen & Analyze
*   **Input**: Read the user's latest message.
*   **Check**: Did they answer a question? Did they pose a new constraint?
*   **Action**: Execute `§CMD_LOG_INTERACTION` immediately to capture this interaction.

#### Step B: Log Internal Thoughts
*   **Action**: Execute `§CMD_APPEND_LOG` to `BRAINSTORM_LOG.md`.
*   **Scope**: Log *internal* decisions, alternatives, and risks.

#### Step C: The Socratic Response
*   **Action**: Reply to the user with questions on the next topic.
*   **Style**:
    1.  **Validate**: "I see why you want X..."
    2.  **Challenge**: "...but have you considered the latency cost?"
    3.  **Propose**: "What if we did Z instead?"
    4.  **Explore**: "How would that handle edge case Q?"

### Dialogue Topics (Brainstorm)
*Examples of themes to explore. Adapt to the task -- skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Problem framing** -- is the problem well-defined, are we solving the right thing
- **Constraints & non-negotiables** -- hard requirements, budget, timeline, compliance
- **Stakeholders & perspectives** -- who is affected, whose input matters, conflicting needs
- **Prior attempts** -- what has been tried, what worked/failed, lessons learned
- **Wild ideas & provocations** -- 10x solutions, unreasonable approaches, creative leaps
- **Feasibility** -- technical viability, resource requirements, complexity assessment
- **Priorities & trade-offs** -- what to optimize for, what to sacrifice, ranking criteria
- **Adjacent domains** -- inspiration from other fields, analogous problems, transferable patterns
- **Risks of inaction** -- what happens if we do nothing, cost of delay
- **Evaluation criteria** -- how to judge solutions, metrics for success

**Repeatable topics** (can be selected any number of times):
- **Followup** -- Clarify or revisit answers from previous rounds
- **Devil's advocate** -- Challenge assumptions and decisions made so far
- **What-if scenarios** -- Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** -- Drill into a specific topic from a previous round in much more detail

### Dialogue Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Synthesis"** -- *(terminal: if selected, skip all others and move on)*
> - **"More dialogue (3 more rounds)"** -- Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** -- 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** -- 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** -- 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### Phase Transition
Execute `§CMD_GATE_PHASE`.

---

## 2. Synthesis
*When the dialogue has explored the space sufficiently.*

`§CMD_REPORT_INTENT`:
> 2: Synthesizing. ___ rounds of dialogue completed.
> Focus: ___.
> Not: ___.

`§CMD_EXECUTE_PHASE_STEPS(2.0.*)`

**Debrief notes** (for `BRAINSTORM.md`):
*   **Reflect**: Look back at the full session -- identify key takeaways.
*   **Synthesize**: Don't just summarize. Connect the dots between dialogue rounds.
*   **Next Steps**: Propose the move to `IMPLEMENTATION` or `ANALYSIS` -- guide the user.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Brainstorm complete. Walk through ideas?"
  debriefFile: "BRAINSTORM.md"
```
