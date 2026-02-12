---
name: research
description: "Full research cycle — refines query, calls Gemini Deep Research, polls, delivers report. Triggers: \"research this topic\", \"run a research cycle\", \"call Gemini Deep Research\"."
version: 2.0
tier: protocol
---

Full research cycle — refines query, calls Gemini Deep Research, polls, delivers report.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# Research Protocol (Full Lifecycle — Request + Fulfill)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 2 (Interrogation / Query Refinement). The engine's artifacts live in the session directory as reviewable files, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "RESEARCH",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "templates_loaded", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Context Ingestion", "proof": ["context_sources_presented", "files_loaded"]},
    {"major": 2, "minor": 0, "name": "Interrogation", "proof": ["depth_chosen", "rounds_completed"]},
    {"major": 3, "minor": 0, "name": "Research Execution", "proof": ["research_submitted", "research_fulfilled", "log_entries"]},
    {"major": 4, "minor": 0, "name": "Synthesis"},
    {"major": 4, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 4, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 4, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 4, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/research", "/implement", "/analyze", "/brainstorm"],
  "directives": [],
  "logTemplate": "~/.claude/skills/research/assets/TEMPLATE_RESEARCH_LOG.md",
  "debriefTemplate": "~/.claude/skills/research/assets/TEMPLATE_RESEARCH_RESPONSE.md",
  "requestTemplate": "~/.claude/skills/research/assets/TEMPLATE_RESEARCH_REQUEST.md"
}
```

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is RESEARCH (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Research Strategist**.
    >    **Goal**: To craft a precise research question, get it answered by Gemini Deep Research, and deliver the result.
    >    **Mindset**: A good research question is half the answer. Spend time refining before firing.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 0. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/research/assets/TEMPLATE_RESEARCH_RESPONSE.md` (Template for the response document)
    *   `~/.claude/skills/research/assets/TEMPLATE_RESEARCH_REQUEST.md` (Template for the request document)

3.  **Parse & Activate**: Execute `§CMD_PARSE_PARAMETERS` — constructs the session parameters JSON and pipes it to `session.sh activate` via heredoc.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Goal].

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 1.

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Context Ingestion
*Load relevant materials before refining the query.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Context Ingestion.
> 2. I will `§CMD_INGEST_CONTEXT_BEFORE_WORK` to ask for and load `contextPaths`.

**Action**: Execute `§CMD_INGEST_CONTEXT_BEFORE_WORK`.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Skip to 3: Execute Research | Question is already well-defined, skip refinement"

---

## 2. The Interrogation (Query Refinement)
*Refine the research question through structured dialogue.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Query Refinement.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to refine the research question.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should query refinement go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Question is mostly clear, just needs minor sharpening |
| **Medium** | 6+ | Moderate ambiguity, multiple angles to consider |
| **Long** | 9+ | Complex multi-faceted topic, many constraints |
| **Absolute** | Until ALL questions resolved | Novel domain, high-stakes research, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

### Interrogation Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

### Interrogation Topics (Research)
*Examples of themes to explore. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Core question** — What exactly do you want to know? What prompted this?
- **Scope & depth** — How broad or narrow? Survey vs deep dive? Time range?
- **Source quality** — Academic papers, official docs, blog posts, code examples? Preference?
- **Prior knowledge** — What do you already know? What have you already tried?
- **Output format** — Report, summary, comparison table, decision matrix, annotated bibliography?
- **Audience** — Who will read this? Technical depth appropriate?
- **Timeline** — How current must sources be? Historical context needed?
- **Known unknowns** — What specific gaps are you trying to fill?
- **Related topics** — Adjacent areas that might be relevant?
- **Success criteria** — How will you know the research answered your question?

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. Also log a Query Refinement entry to the session log via `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.
5. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

**If this is a follow-up**: Also ask which previous response to continue from. Read it to extract the Interaction ID.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 3: Execute Research"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

---

## 3. Research Execution
*Create the request document, call Gemini, and fulfill the research.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Research Execution.
> 2. I will post the request document for traceability.
> 3. I will call Gemini Deep Research and poll for results.

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

### Step 1: Post Request
Create the request document using `~/.claude/skills/research/assets/TEMPLATE_RESEARCH_REQUEST.md`:
1.  **Populate**: Fill in Query, Context, Constraints, Expected Output, and Requesting Session sections from interrogation context.
2.  **Save**: Write to `[session-dir]/RESEARCH_REQUEST_[TOPIC].md`.
3.  **Tag**: Apply `#needs-research` tag:
    ```bash
    engine tag add "$REQUEST_FILE" '#needs-research'
    ```
4.  **Log**: Log `📝 Request Posted` entry via `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.

### Step 2: Call Gemini
1.  **Compose**: Synthesize the Query, Context, Constraints, and Expected Output from the request document into a coherent research prompt.
2.  **Output path**: `[session-dir]/research_raw_output.txt` — temporary file for the script's raw output.
3.  **Execute** (background):
    *   **If initial request** (no previous Interaction ID):
        ```bash
        engine research <output-path> <<'EOF'
        [composed research prompt]
        EOF
        ```
    *   **If follow-up** (Interaction ID present):
        ```bash
        engine research --continue <interaction-id> <output-path> <<'EOF'
        [composed follow-up prompt]
        EOF
        ```
    *   Run with `run_in_background: true`. Note the **task ID** from the background task.

### Step 3: Capture Interaction ID
The script writes `INTERACTION_ID=<id>` to the output file immediately (before polling starts). After a short wait (~5 seconds), read the output file to extract the ID.

1.  **Read**: Read the output file. First line should be `INTERACTION_ID=<id>`.
2.  **Write to request**: Append the interaction ID to the **request file** so it's recoverable:
    ```bash
    engine log "$REQUEST_FILE" <<'EOF'
    ## Active Research
    *   **Interaction ID**: `[interaction-id]`
    *   **Started**: [YYYY-MM-DD HH:MM:SS]
    EOF
    ```
3.  **Swap tag**: `#needs-research` → `#claimed-research` on the request file:
    ```bash
    engine tag swap "$REQUEST_FILE" '#needs-research' '#claimed-research'
    ```
    This marks the request as in-flight. If this session dies, another agent can find `#claimed-research` requests, read the Interaction ID, and resume polling.

### Step 4: Await Results
1.  **Inform user**: "Research submitted to Gemini. Interaction ID: `[id]`. Watching for results via `§CMD_AWAIT_TAG`."
2.  **Watch**: Execute `§CMD_AWAIT_TAG` (file mode) on the request file for `#done-research`:
    ```bash
    Bash("engine await-tag $REQUEST_FILE '#done-research'", run_in_background=true)
    ```
    The `research.sh` script (launched in Step 2) handles polling Gemini, writing the response, and swapping the tag. `await-tag.sh` detects the tag swap and signals the agent.
3.  **Continue or Wait**: The agent can either:
    *   Continue other work while the research runs (the background watcher will notify on completion).
    *   Wait for the watcher to complete if no other work is pending.
4.  **Timeout**: If the session ends before results arrive, the `#claimed-research` tag + Interaction ID on the request file means `/research` can pick it up in a future session.

### Step 5: Post Response
1.  **Read** the output file. Line 1 is `INTERACTION_ID=<id>`. Remaining lines are the report.
2.  **Create**: Populate `~/.claude/skills/research/assets/TEMPLATE_RESEARCH_RESPONSE.md` with the interaction ID, original request path, and full report. Save as `RESEARCH_RESPONSE_[TOPIC].md`.
3.  **Breadcrumb**: Append `## Response` section to the request file via `engine log`.
4.  **Swap Tag**: `#claimed-research` → `#done-research` on the request file:
    ```bash
    engine tag swap "$REQUEST_FILE" '#claimed-research' '#done-research'
    ```
5.  **Cleanup**: Delete `research_raw_output.txt`.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 4. Synthesis
*Present results and close the session.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.

**STOP**: Do not create artifacts yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Pre-debrief**: Present the research report in chat so the user can read it immediately.

**Debrief creation notes** (for Step 1 -- `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `RESEARCH_RESPONSE_[TOPIC].md` (already created in Phase 3 Step 5 — update if needed)
*   Include: Interaction ID, original request path, full report content.

**Archive to Docs (Optional)** — After the debrief, ask the user if they want to copy the research to a project docs directory for permanent reference:
*   Use `AskUserQuestion` with options:
    *   "Yes — copy to docs" (provide a suggested path like `packages/[pkg]/docs/research/` or `docs/research/`)
    *   "No — keep in session only"
*   If yes: ensure target directory exists, copy the response file, report the copied path.

**Walk-through config** (for Step 3 -- `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Research complete. Walk through the findings?"
  debriefFile: "RESEARCH_RESPONSE_[TOPIC].md"
  templateFile: "~/.claude/skills/research/assets/TEMPLATE_RESEARCH_RESPONSE.md"
```

**Follow-up suggestion**: After close, suggest:
*   "Run `/research` again to ask a follow-up question (will chain via Interaction ID)"
*   "The research report is at `[path]` — reference it from any other session"

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
