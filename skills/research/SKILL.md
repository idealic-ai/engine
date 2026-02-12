---
name: research
description: "Full research cycle — refines query, calls Gemini Deep Research, polls, delivers report. Triggers: \"research this topic\", \"run a research cycle\", \"call Gemini Deep Research\"."
version: 3.0
tier: protocol
---

Full research cycle — refines query, calls Gemini Deep Research, polls, delivers report.

# Research Protocol (Full Lifecycle — Request + Fulfill)

Execute `§CMD_EXECUTE_SKILL_PHASES`.

### Session Parameters
```json
{
  "taskType": "RESEARCH",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["session_dir", "parameters_parsed", "context_sources_presented"]},
    {"label": "1", "name": "Interrogation",
      "steps": ["§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depth_chosen", "rounds_completed"]},
    {"label": "2", "name": "Research Execution",
      "steps": [],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["research_submitted", "research_fulfilled", "log_entries"]},
    {"label": "3", "name": "Synthesis",
      "steps": ["§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": []},
    {"label": "3.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": []},
    {"label": "3.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debrief_file", "debrief_tags"]},
    {"label": "3.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": []},
    {"label": "3.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION"], "commands": [], "proof": []}
  ],
  "nextSkills": ["/research", "/implement", "/analyze", "/brainstorm"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_RESEARCH_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_RESEARCH_RESPONSE.md",
  "requestTemplate": "assets/TEMPLATE_RESEARCH_REQUEST.md"
}
```

---

## 0. Setup

`§CMD_REPORT_INTENT_TO_USER`:
> Researching ___. Goal: ___.
> Role: Research Strategist — craft a precise question, get it answered, deliver the result.
> A good research question is half the answer. Spend time refining before firing.

`§CMD_EXECUTE_PHASE_STEPS(0.0.*)`

*   **Scope**: Understand the [Topic] and [Goal].

---

## 1. Interrogation (Query Refinement)

`§CMD_REPORT_INTENT_TO_USER`:
> Interrogating ___ assumptions before composing the research query.
> Drawing from scope, source quality, prior knowledge, and success criteria topics.

`§CMD_EXECUTE_PHASE_STEPS(1.0.*)`

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

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

### Topics (Research)
*Adapt to the task — skip irrelevant ones, invent new ones as needed.*

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
2. Execute `§CMD_ASK_ROUND` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_INTERACTION` immediately.
4. Also log a Query Refinement entry to the session log via `§CMD_APPEND_LOG`.
5. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

**If this is a follow-up**: Also ask which previous response to continue from. Read it to extract the Interaction ID.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 2: Execute Research"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

---

## 2. Research Execution
*Create the request document, call Gemini, and fulfill the research.*

`§CMD_REPORT_INTENT_TO_USER`:
> Executing research on ___. Posting request, calling Gemini Deep Research, awaiting results.
> Interaction will be tracked via request file tags for recoverability.

`§CMD_EXECUTE_PHASE_STEPS(2.0.*)`

### Step 1: Post Request
Create the request document using `assets/TEMPLATE_RESEARCH_REQUEST.md`:
1.  **Populate**: Fill in Query, Context, Constraints, Expected Output, and Requesting Session sections from interrogation context.
2.  **Save**: Write to `[session-dir]/RESEARCH_REQUEST_[TOPIC].md`.
3.  **Tag**: Apply `#needs-research` tag:
    ```bash
    engine tag add "$REQUEST_FILE" '#needs-research'
    ```
4.  **Log**: Log request posted entry via `§CMD_APPEND_LOG`.

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
3.  **Swap tag**: `#needs-research` -> `#claimed-research` on the request file:
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
2.  **Create**: Populate `assets/TEMPLATE_RESEARCH_RESPONSE.md` with the interaction ID, original request path, and full report. Save as `RESEARCH_RESPONSE_[TOPIC].md`.
3.  **Breadcrumb**: Append `## Response` section to the request file via `engine log`.
4.  **Swap Tag**: `#claimed-research` -> `#done-research` on the request file:
    ```bash
    engine tag swap "$REQUEST_FILE" '#claimed-research' '#done-research'
    ```
5.  **Cleanup**: Delete `research_raw_output.txt`.

---

## 3. Synthesis
*Present results and close the session.*

`§CMD_REPORT_INTENT_TO_USER`:
> Synthesizing. Research on ___ fulfilled.
> Presenting report and closing session.

`§CMD_EXECUTE_PHASE_STEPS(3.0.*)`

**Pre-debrief**: Present the research report in chat so the user can read it immediately.

**Debrief notes** (for `RESEARCH_RESPONSE_[TOPIC].md`):
*   Dest: `RESEARCH_RESPONSE_[TOPIC].md` (already created in Phase 2 Step 5 — update if needed)
*   Include: Interaction ID, original request path, full report content.

**Archive to Docs (Optional)** — After the debrief, ask the user if they want to copy the research to a project docs directory for permanent reference:
*   Use `AskUserQuestion` with options:
    *   "Yes — copy to docs" (provide a suggested path like `packages/[pkg]/docs/research/` or `docs/research/`)
    *   "No — keep in session only"
*   If yes: ensure target directory exists, copy the response file, report the copied path.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Research complete. Walk through the findings?"
  debriefFile: "RESEARCH_RESPONSE_[TOPIC].md"
  templateFile: "assets/TEMPLATE_RESEARCH_RESPONSE.md"
```

**Follow-up suggestion**: After close, suggest:
*   "Run `/research` again to ask a follow-up question (will chain via Interaction ID)"
*   "The research report is at `[path]` — reference it from any other session"

**Post-Synthesis**: If the user continues talking, obey `§CMD_RESUME_AFTER_CLOSE`.
