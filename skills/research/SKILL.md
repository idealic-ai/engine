---
name: research
description: "Full research cycle — refines query, calls Gemini Deep Research, polls, delivers report. Combines /research-request + /research-respond. Triggers: \"research this topic\", \"run a research cycle\", \"call Gemini Deep Research\"."
version: 2.0
---

Full research cycle — refines query, calls Gemini Deep Research, polls, delivers report.
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

# Research Protocol (Full Lifecycle — Request + Fulfill)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own planning system — Phase 3 (Interrogation / Query Refinement). The engine's artifacts live in the session directory as reviewable files, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
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

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/research-request/SKILL.md` (Request posting protocol — Phase 4 reuses steps)
    *   `~/.claude/skills/research-respond/assets/TEMPLATE_RESEARCH_RESPONSE.md` (Template for the response document)
    *   `~/.claude/skills/research-request/assets/TEMPLATE_RESEARCH_LOG.md` (Template for session logging)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.

5.  **Scope**: Understand the [Topic] and [Goal].

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion in Phase 2.

7.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance.
    *   *Note*: Re-run discovery during Synthesis to catch late arrivals.

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
*Load relevant materials before refining the query.*

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
> - **"Proceed to Phase 3: Query Refinement"** — Refine the research question through interrogation
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Execute Research"** — Question is already well-defined, skip refinement

---

## 3. The Interrogation (Query Refinement)
*Refine the research question through structured dialogue.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Query Refinement.
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
4. Also log a 🎯 Query Refinement entry to the session log via `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.
5. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

**If this is a follow-up**: Also ask which previous response to continue from. Read it to extract the Interaction ID.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 4: Execute Research"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
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
> - Research question defined: `________`

---

## 4. Post Request & Execute Research
*Create the request document, then immediately fulfill it.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Research Execution.
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
Execute Phase 4 (steps 1-3) of `~/.claude/skills/research-request/SKILL.md` to create the request document, tag it with `#needs-research`, and log the posting. Use the interrogation context already gathered in Phase 3 above — do not re-interrogate.

### Step 2: Call Gemini
1.  **Compose**: Synthesize the Query, Context, Constraints, and Expected Output from the request document into a coherent research prompt.
2.  **Output path**: `[session-dir]/research_raw_output.txt` — temporary file for the script's raw output.
3.  **Execute** (background):
    *   **If initial request** (no previous Interaction ID):
        ```bash
        ~/.claude/scripts/research.sh <output-path> <<'EOF'
        [composed research prompt]
        EOF
        ```
    *   **If follow-up** (Interaction ID present):
        ```bash
        ~/.claude/scripts/research.sh --continue <interaction-id> <output-path> <<'EOF'
        [composed follow-up prompt]
        EOF
        ```
    *   Run with `run_in_background: true`. Note the **task ID** from the background task.

### Step 3: Capture Interaction ID
The script writes `INTERACTION_ID=<id>` to the output file immediately (before polling starts). After a short wait (~5 seconds), read the output file to extract the ID.

1.  **Read**: Read the output file. First line should be `INTERACTION_ID=<id>`.
2.  **Write to request**: Append the interaction ID to the **request file** so it's recoverable:
    ```bash
    ~/.claude/scripts/log.sh "$REQUEST_FILE" <<'EOF'
    ## Active Research
    *   **Interaction ID**: `[interaction-id]`
    *   **Started**: [YYYY-MM-DD HH:MM:SS]
    EOF
    ```
3.  **Swap tag**: `#needs-research` → `#active-research` on the request file:
    ```bash
    ~/.claude/scripts/tag.sh swap "$REQUEST_FILE" '#needs-research' '#active-research'
    ```
    This marks the request as in-flight. If this session dies, another agent can find `#active-research` requests, read the Interaction ID, and resume polling.

### Step 4: Await Results
1.  **Inform user**: "Research submitted to Gemini. Interaction ID: `[id]`. Watching for results via `§CMD_AWAIT_TAG`."
2.  **Watch**: Execute `§CMD_AWAIT_TAG` (file mode) on the request file for `#done-research`:
    ```bash
    Bash("~/.claude/scripts/await-tag.sh $REQUEST_FILE '#done-research'", run_in_background=true)
    ```
    The `research.sh` script (launched in Step 2) handles polling Gemini, writing the response, and swapping the tag. `await-tag.sh` detects the tag swap and signals the agent.
3.  **Continue or Wait**: The agent can either:
    *   Continue other work while the research runs (the background watcher will notify on completion).
    *   Wait for the watcher to complete if no other work is pending.
4.  **Timeout**: If the session ends before results arrive, the `#active-research` tag + Interaction ID on the request file means `/research-respond` can pick it up in a future session.

### Step 5: Post Response
1.  **Read** the output file. Line 1 is `INTERACTION_ID=<id>`. Remaining lines are the report.
2.  **Create**: Populate `~/.claude/skills/research-respond/assets/TEMPLATE_RESEARCH_RESPONSE.md` with the interaction ID, original request path, and full report. Save as `RESEARCH_RESPONSE_[TOPIC].md`.
3.  **Breadcrumb**: Append `## Response` section to the request file via `log.sh`.
4.  **Swap Tag**: `#active-research` → `#done-research` on the request file:
    ```bash
    ~/.claude/scripts/tag.sh swap "$REQUEST_FILE" '#active-research' '#done-research'
    ```
5.  **Cleanup**: Delete `research_raw_output.txt`.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Request created and tagged: `________`
> - Gemini called: `________`
> - Interaction ID captured: `________`
> - Response saved: `________`
> - Tag lifecycle complete: `________`
> - Raw output cleaned: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 4: Research complete. How to proceed?"
> - **"Proceed to Phase 5: Present Results"** — Show the research and close session
> - **"Stay in Phase 4"** — Research is still in progress or needs re-execution

---

## 5. Present Results & Debrief
*Show the research results and close the session.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Present Results.
> 2. I will present the research report.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create artifacts yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 4 or 5 without completing step 1.

**Step 1 (THE DELIVERABLE)**: Present the research report in chat so the user can read it immediately.

**Step 2**: Log a ✅ Research Complete entry via `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.

**Step 3**: Archive to Docs (Optional) — Ask the user if they want to copy the research to a project docs directory for permanent reference.
  *   Use `AskUserQuestion` with options:
      *   "Yes — copy to docs" (provide a suggested path like `packages/[pkg]/docs/research/` or `docs/research/`)
      *   "No — keep in session only"
  *   If yes:
      1.  Ensure the target directory exists (`mkdir -p`).
      2.  Copy the response file with a descriptive name.
      3.  Report the copied path.

**Step 4**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 5**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 6**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 7**: Suggest follow-up options:
  *   "Run `/research` again to ask a follow-up question (will chain via Interaction ID)"
  *   "The research report is at `[path]` — reference it from any other session"

### §CMD_VERIFY_PHASE_EXIT — Phase 5 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Research report presented: `________`
> - Log entry written: `________`
> - Archive decision: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
