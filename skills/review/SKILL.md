---
name: review
description: "Reviews and validates work across sessions for consistency and correctness. Triggers: \"review session work\", \"validate debriefs\", \"approve session reports\", \"end-of-day review\"."
version: 2.0
---

Reviews and validates work across sessions for consistency and correctness.
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

# Review Protocol (The Multiplexer)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structure — Phase 3 (Dashboard & Per-Debrief Interrogation) is the iterative work phase. The engine's artifacts live in the session directory as reviewable files, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is REVIEW (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify unvalidated debriefs (`#needs-review` and `#needs-rework`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Senior Reviewer** and **Quality Gate**.
    >    **Goal**: To review all agent session work, detect issues and conflicts, and present structured findings to the user for approval or rework.
    >    **Mindset**: "Trust but Verify." You are the user's eyes across all parallel agent sessions. Read everything. Surface what matters. Skip what doesn't.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project source code in Phase 1. Only load system templates/standards and discover tagged files.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/review/assets/TEMPLATE_REVIEW_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/review/assets/TEMPLATE_REVIEW.md` (Template for the final review report)
    *   `~/.claude/standards/TEMPLATE_DETAILS.md` (Template for Q&A capture)

3.  **Discover Debriefs**: Execute `§CMD_FIND_TAGGED_FILES` for BOTH:
    *   `#needs-review` — never-validated debriefs.
    *   `#needs-rework` — previously rejected debriefs.
    *   Search scope: `sessions/` directory.
    *   **Output**: List all found files to the user with their tag status. Each path should be a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant).

4.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.
    *   The `contextPaths` MUST include all discovered debrief files.

5.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.
    *   **Naming**: Use `sessions/[YYYY_MM_DD]_REVIEW_[N]` where N increments if multiple review sessions exist for the same date.

6.  **Initialize Log**: Execute `§CMD_INIT_OR_RESUME_LOG_SESSION` (Template: `REVIEW_LOG.md`).

7.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance.
    *   *Note*: Re-run discovery during Convergence to catch late arrivals.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`, `________`
> - Debriefs discovered: `________`
> - Parameters parsed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Discovery & Cross-Session Analysis"** — Read all debriefs and perform cross-session analysis
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Discovery & Cross-Session Analysis
*Read everything. Build the global picture.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Discovery & Cross-Session Analysis.
> 2. I will read ALL discovered debrief files AND their sibling `_LOG.md` files.
> 3. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to log a `Debrief Card` for each debrief.
> 4. I will perform the Cross-Session Analysis and log any `Cross-Session Conflict` findings.
> 5. I will `§CMD_THINK_IN_LOG` throughout.

### ⏱️ Logging Heartbeat (CHECK BEFORE EVERY TOOL CALL)
```
Before calling any tool, ask yourself:
  Have I made 2+ tool calls since my last log entry?
  → YES: Log NOW before doing anything else. This is not optional.
  → NO: Proceed with the tool call.
```

[!!!] If you make 3 tool calls without logging, you are FAILING the protocol. The log is your brain — unlogged work is invisible work.

**Action**:
1.  **Read All Debriefs**: For each discovered file, read the full debrief.
2.  **Read All Logs**: For each debrief's session directory, also read:
    *   The `_LOG.md` file(s) (e.g., `IMPLEMENTATION_LOG.md`, `BRAINSTORM_LOG.md`)
    *   Any `_PLAN.md` files for additional context.
    *   **Goal**: Catch buried concerns, rejected alternatives, and internal reasoning not surfaced in the debrief.
3.  **Log Debrief Cards**: For each debrief, execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with the `Debrief Card` schema.
4.  **Cross-Session Analysis**: Analyze ALL debriefs together against the 4 cross-session checks:
    *   **File Overlap**: Did multiple sessions touch the same files?
    *   **Schema/Interface Conflicts**: Did sessions make incompatible changes to shared types?
    *   **Contradictory Decisions**: Did session A decide X while session B decided not-X?
    *   **Dependency Order**: Did any session depend on another session's unvalidated output?
5.  **Log Conflicts**: For each finding, execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with the `Cross-Session Conflict` schema.

**Constraint**: Do NOT present findings to the user yet. Complete the full analysis first.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Debriefs read: `________`
> - Sibling logs/plans read: `________`
> - Debrief Cards logged: `________`
> - Cross-session checks: `________` / 4
> - Conflicts found: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Discovery & analysis complete. How to proceed?"
> - **"Proceed to Phase 3: Dashboard & Per-Debrief Interrogation"** — Present findings and walk through each debrief
> - **"Stay in Phase 2"** — Read more files or continue analysis
> - **"Skip to Phase 4: Convergence"** — I already know the verdicts, just write the report

---

## 3. Dashboard & Per-Debrief Interrogation

### Phase 3a: The Dashboard
*Present the global picture first.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3a: Dashboard.
> 2. I will present ALL debrief summary cards and cross-session analysis findings.
> 3. I will `§CMD_WAIT_FOR_USER_CONFIRMATION` before drilling into individual debriefs.

**Action**:
1.  **Present Cross-Session Findings**: Output the cross-session analysis (file overlaps, conflicts, contradictions, dependencies). If none found, say "No cross-session conflicts detected."
2.  **Present All Summary Cards**: For each debrief, output a summary card:
    *   **Session**: `[Session Dir]`
    *   **File**: `[Debrief Filename]` (`#needs-review` | `#needs-rework`)
    *   **Goal**: 1-line session goal.
    *   **What Was Done**: 2-3 bullet points.
    *   **Files Touched**: Key files.
    *   **Risk Flags**: Any concerns from log inspection. "None" if clean.
    *   **Agent Confidence**: High/Medium/Low (inferred from debrief tone and log).
3.  **If `#needs-rework`**: Include the previous `## Rework Notes` content and ask: "This was previously rejected. Has the underlying work been redone?"

Execute `AskUserQuestion` (multiSelect: false):
> "Dashboard presented. How to proceed?"
> - **"Proceed to per-debrief review"** — Walk through each debrief individually
> - **"Discuss dashboard first"** — I want to talk about the cross-session findings

### Phase 3b: Per-Debrief Interrogation
*Walk through each debrief with the user.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3b: Per-Debrief Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` for each debrief.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 4. I will use the Standard Validation Checklist as internal guidance.
> 5. After each debrief, I will tag the outcome (validate or mark for rework) using the tag swap procedures below.

### Interrogation Depth Selection

**Before starting per-debrief review**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How thorough should the per-debrief review be?"

| Depth | Minimum Rounds Per Debrief | When to Use |
|-------|---------------------------|-------------|
| **Short** | 1 round | Quick validation, trusted agent, small scope |
| **Medium** | 2 rounds | Standard review, moderate complexity |
| **Long** | 3+ rounds | Deep audit, critical changes, untrusted work |
| **Absolute** | Until ALL concerns resolved | High-risk sessions, production changes, security-sensitive |

Record the user's choice. This sets the **minimum** per debrief — the agent can always ask more, and the user can always say "approve" after the minimum is met.

### Interrogation Topics (Review)
*Examples of themes to explore per debrief. Adapt to the session — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once per debrief):
- **Acceptance criteria** — Did the session achieve what was asked?
- **Test coverage** — Were tests written/updated? Are they passing? Any skipped?
- **Breaking changes** — Did this session change interfaces, schemas, or APIs that other code depends on?
- **Documentation alignment** — Were relevant docs updated, or is there now a doc-code drift?
- **Risk flags** — Did the agent express concerns in the log that didn't make it to the debrief?
- **Buried alternatives** — Did the agent reject an option that the user should know about?
- **TODO completeness** — Anything explicitly deferred or marked as future work?
- **Cross-session consistency** — Does this session's output conflict with other concurrent sessions?

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

### Standard Validation Checklist (LLM Internal Guidance)

[!!!] This is YOUR internal rubric — do NOT present it as a form. Use it to generate contextualized findings.

1.  **Goal Alignment** — Did the session achieve what was asked?
2.  **Completeness** — Are all template sections filled? Any placeholders or "TBD" left?
3.  **Test Status** — Were tests written/updated? Are they passing? Any skipped?
4.  **Breaking Changes** — Did this session change interfaces, schemas, or APIs that other code depends on?
5.  **Risk Flags** — Did the agent express concerns/worries in the log that didn't make it to the debrief?
6.  **Buried Alternatives** — Did the agent reject an option in the log that the user should know about?
7.  **TODOs & Leftovers** — Anything explicitly deferred or marked as future work?
8.  **Doc Alignment** — Were relevant docs updated, or is there now a doc-code drift?

### Per-Debrief Review Protocol

**For each debrief (sequentially)**:

[!!!] CRITICAL: You MUST complete at least the minimum rounds per debrief for the chosen depth. Track your round count visibly.

**Round counter**: Output it on each debrief: "**Reviewing debrief N of M — Round R / {depth_minimum}+**"

1.  **Analyze Against Checklist (Internal)**: Review the debrief against the Standard Validation Checklist. Filter & contextualize — skip checks that aren't relevant. For each relevant check, prepare a specific, contextualized finding.
    *   **Bad**: "Test Status: PASS" (meaningless)
    *   **Good**: "Test Status: 164/164 estimate + 57/57 viewer tests pass. No skipped tests. The new `mutate()` context has 3 dedicated tests covering capture, backwards compat, and before snapshot."

2.  **Present to User**: Use `AskUserQuestion` with structured options:
    *   Present your findings as detailed descriptions per option.
    *   Ask targeted questions about anything ambiguous or concerning.
    *   Always include these options:
        *   **"Approve (clean)"** — No issues found, validate the debrief
        *   **"Approve + note TODOs"** — Validate, but capture follow-up work
        *   **"Flag for rework"** — Reject, mark for rework with reason
        *   **"I have questions"** — Discuss before deciding

3.  **Process User Response**:
    *   **Approve (clean)**: Validate the debrief — swap tags and log:
        ```bash
        ~/.claude/scripts/tag.sh swap "$FILE" '#needs-review,#needs-rework' '#done-review'
        ```
        Record the verdict in `REVIEW_LOG.md`. Log `Verdict: Validated`. No leftovers.
    *   **Approve + note TODOs**: Validate (same tag swap as clean approve). Then immediately ask: "What follow-up work should I note down?" Capture the user's response and log it as `Leftover Spawned`. These become micro-dehydrated prompts in the Leftovers section of the final REVIEW.md report.
    *   **Flag for Rework**: Mark the debrief as needing rework:
        ```bash
        ~/.claude/scripts/tag.sh swap "$FILE" '#needs-review' '#needs-rework'
        ```
        Then append a `## Rework Notes` section at the end with: the date of rejection, the user's stated reason, and specific items to address. If `## Rework Notes` already exists, append a new dated entry under it.
        Record the verdict in `REVIEW_LOG.md`. Ask user for the rework reason. Log `Verdict: Needs Rework`. The leftover prompt generated for this rework MUST include the instruction:
        1.  Execute `§CMD_SWAP_TAG_IN_FILE` to replace `#needs-rework` with `#done-review`.
        2.  Append a short resolution entry to the debrief's `## Rework Notes` section:
            ```
            ### [YYYY-MM-DD] Resolved
            [1-2 lines describing what was done]
            See: [REVIEW.md](../YYYY_MM_DD_REVIEW_N/REVIEW.md)
            ```
    *   **Questions/Discussion**: Answer the user's question fully, then re-present the approval question.

4.  **Log**: Execute `§CMD_LOG_TO_DETAILS` after each user interaction. Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` with the verdict schema.

5.  **Repeat** for next debrief.

### Interrogation Exit Gate

**After reaching minimum rounds for a debrief**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Debrief review round complete (minimum met). What next?"
> - **"Approve and move to next debrief"** — *(terminal: if selected, skip all others and proceed)*
> - **"More review (1 more round)"** — Standard review round, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging the session's decisions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard round first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining concerns. Ask: "Round N complete. I still have concerns about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Dashboard presented: `________`
> - User confirmed: `________`
> - Depth chosen: `________`
> - Debriefs reviewed: `________`
> - Verdicts tagged: `________`
> - REVIEW_LOG.md entries: `________`
> - DETAILS.md entries: `________`

---

## 4. Convergence (Wrap-Up)
*Produce the review report and spawn leftovers.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Convergence.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_REVIEW.md` EXACTLY) to create the review report.
> 3. I will spawn leftover sessions with micro-dehydrated prompts.
> 4. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to formally close the session.
> 5. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER. Do NOT skip to step 3 without completing step 1. The review report FILE is the primary deliverable — chat output alone is not sufficient.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Dest: `REVIEW.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   Populate ALL sections from the template.
  *   Cross-Session Analysis: Transcribe findings from Phase 2.
  *   Per-Debrief Verdicts: Condensed card for each debrief with verdict.
  *   Leftovers: For each rework item or discovered TODO, generate a micro-dehydrated prompt:
      *   **Simple tasks** (delete a file, rename, small config change): Just a plain instruction. No command protocol needed.
      *   **Complex tasks** (feature rework, bug investigation, test gaps): Recommend a command (`/implement`, `/debug`, `/test`, `/analyze`) with a self-contained prompt referencing the review report and original session.
      *   Enough context for the user to copy-paste and immediately act.

**Step 2**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 3**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created/modified files in chat.

**Step 4**: Execute `§CMD_REPORT_SESSION_SUMMARY` — output a final count: "Validated: N, Needs Rework: M, Leftovers Spawned: K."

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - REVIEW.md written: `________` (real file path)
> - Tags line: `________`
> - Per-debrief verdicts: `________`
> - Leftovers: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Convergence**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
