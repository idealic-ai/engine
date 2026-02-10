---
name: review
description: "Reviews and validates work across sessions for consistency and correctness. Triggers: \"review session work\", \"validate debriefs\", \"approve session reports\", \"end-of-day review\"."
version: 2.0
tier: protocol
---

Reviews and validates work across sessions for consistency and correctness.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# Review Protocol (The Multiplexer)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structure — Phase 2 (Dashboard & Per-Debrief Interrogation) is the iterative work phase. The engine's artifacts live in the session directory as reviewable files, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "RESOLVE",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "session_dir", "templates_loaded", "parameters_parsed", "debriefs_discovered"]},
    {"major": 1, "minor": 0, "name": "Discovery", "proof": ["debriefs_read", "sibling_logs_plans_read", "debrief_cards_logged", "cross_session_checks", "conflicts_found"]},
    {"major": 2, "minor": 0, "name": "Dashboard & Interrogation", "proof": ["dashboard_presented", "depth_chosen", "rounds_completed", "debriefs_reviewed", "verdicts_tagged", "log_entries"]},
    {"major": 3, "minor": 0, "name": "Synthesis"},
    {"major": 3, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 3, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 3, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 3, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/implement", "/document", "/brainstorm", "/analyze", "/chores"],
  "directives": [],
  "logTemplate": "~/.claude/skills/review/assets/TEMPLATE_REVIEW_LOG.md",
  "debriefTemplate": "~/.claude/skills/review/assets/TEMPLATE_REVIEW.md",
  "requestTemplate": "~/.claude/skills/review/assets/TEMPLATE_REVIEW_REQUEST.md",
  "responseTemplate": "~/.claude/skills/review/assets/TEMPLATE_REVIEW_RESPONSE.md",
  "modes": {
    "quality": {"label": "Quality", "description": "Thorough validation, evidence-driven", "file": "~/.claude/skills/review/modes/quality.md"},
    "progress": {"label": "Progress", "description": "Cross-session status reporting", "file": "~/.claude/skills/review/modes/progress.md"},
    "evangelize": {"label": "Evangelize", "description": "Stakeholder communication, narrative", "file": "~/.claude/skills/review/modes/evangelize.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "~/.claude/skills/review/modes/custom.md"}
  }
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 0 only (Strict Bootloader — expires at Phase 1).
    > 3. My focus is REVIEW (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify unvalidated debriefs (`#needs-review` and `#needs-rework`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 8. I will select the **Review Mode** (Quality / Progress / Evangelize / Custom).
    > 9. I will `§CMD_ASSUME_ROLE` using the selected mode's preset.
    > 10. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project source code in Phase 0. Only load system templates/standards and discover tagged files.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `~/.claude/skills/review/assets/TEMPLATE_REVIEW_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/review/assets/TEMPLATE_REVIEW.md` (Template for the final review report)
    *   `~/.claude/skills/_shared/TEMPLATE_DETAILS.md` (Template for Q&A capture)

3.  **Discover Debriefs & Requests**: Execute `§CMD_FIND_TAGGED_FILES` for:
    *   `#needs-review` — never-validated debriefs.
    *   `#needs-rework` — previously rejected debriefs.
    *   Search scope: `sessions/` directory.
    *   **Also discover REQUEST files**: Glob for `sessions/**/REVIEW_REQUEST_*.md` to find review delegation requests that may not carry tags yet.
    *   **Merge & deduplicate**: Combine tag-discovered files with glob-discovered REQUEST files. Deduplicate by path.
    *   **Output**: List all found files to the user with their source (tag-discovered or REQUEST file). Each path should be a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant).

4.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.
    *   The `contextPaths` MUST include all discovered debrief files.

5.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.
    *   **Naming**: Use `sessions/[YYYY_MM_DD]_REVIEW_[N]` where N increments if multiple review sessions exist for the same date.

5.1. **Review Mode Selection**: Execute `AskUserQuestion` (multiSelect: false):
    > "What review lens should I use?"
    > - **"Quality" (Recommended)** — Correctness-focused: verify work quality, consistency, and completeness
    > - **"Progress"** — Status-focused: track completion, identify blockers, measure velocity
    > - **"Evangelize"** — Communication-focused: frame results for stakeholders, highlight wins
    > - **"Custom"** — Define your own role, goal, and mindset

    **On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Review Strategy.

    **On "Custom"**: Read ALL 3 named mode files first (`modes/quality.md`, `modes/progress.md`, `modes/evangelize.md`), then accept user's framing. Parse into role/goal/mindset.

    **Record**: Store the selected mode. It configures:
    *   Phase 0 role (from mode file)
    *   Phase 2 review criteria (from mode file)

6.  **Assume Role**: Execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset** from the loaded mode file.

7.  **Initialize Log**: Execute `§CMD_INIT_OR_RESUME_LOG_SESSION` (Template: `REVIEW_LOG.md`).

### Phase Transition
*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Discovery & Cross-Session Analysis
*Read everything. Build the global picture.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 1: Discovery & Cross-Session Analysis.
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

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Skip to Phase 3: Synthesis | I already know the verdicts, just write the report"

---

## 2. Dashboard & Per-Debrief Interrogation

### Phase 2a: The Dashboard
*Present the global picture first.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2a: Dashboard.
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

### Phase 2b: Per-Debrief Interrogation
*Walk through each debrief and REQUEST file with the user.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2b: Per-Debrief Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` for each debrief.
> 3. I will review each discovered REVIEW_REQUEST file with its structured fields.
> 4. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.
> 5. I will use the Standard Validation Checklist as internal guidance.
> 6. After each debrief, I will tag the outcome (validate or mark for rework) using the tag swap procedures below.
> 7. After each REQUEST file, I will write a REVIEW_RESPONSE file (`¶INV_REQUEST_BEFORE_CLOSE`).

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
        engine tag swap "$FILE" '#needs-review,#needs-rework' '#done-review'
        ```
        Record the verdict in `REVIEW_LOG.md`. Log `Verdict: Validated`. No leftovers.
    *   **Approve + note TODOs**: Validate (same tag swap as clean approve). Then immediately ask: "What follow-up work should I note down?" Capture the user's response and log it as `Leftover Spawned`. These become micro-dehydrated prompts in the Leftovers section of the final REVIEW.md report.
    *   **Flag for Rework**: Mark the debrief as needing rework:
        ```bash
        engine tag swap "$FILE" '#needs-review' '#needs-rework'
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

### Per-REQUEST File Review

**For each discovered `REVIEW_REQUEST_*.md` file (after all debriefs are processed)**:

1.  **Read REQUEST**: Read the full REQUEST file. Extract structured fields: Topic, Context, Expectations, Requesting Session.
2.  **Read Linked Context**: If the REQUEST references a session or specific files, read them.
3.  **Present to User**: Show the REQUEST summary and ask:
    *   **"Fulfill request"** — Review the linked work and write a RESPONSE file
    *   **"Defer"** — Leave the REQUEST for a future review session
    *   **"Dismiss"** — Remove the REQUEST (tag swap to `#done-review`)

4.  **On "Fulfill request"**: Review the linked artifacts (debrief, code, etc.) using the Standard Validation Checklist. Then apply the same verdict options (Approve clean / Approve + TODOs / Flag for rework / Questions).

5.  **Write RESPONSE** (`¶INV_REQUEST_BEFORE_CLOSE`): After the verdict, write a `REVIEW_RESPONSE_[TOPIC].md` in the **review session directory** using `§CMD_POPULATE_LOADED_TEMPLATE` with the `TEMPLATE_REVIEW_RESPONSE.md` template. Also add a `## Response` breadcrumb section to the original REQUEST file:
    ```markdown
    ## Response
    **Reviewed by**: `[review session dir]`
    **Verdict**: [Validated / Needs Rework]
    **Response file**: `[path to REVIEW_RESPONSE_*.md]`
    ```

6.  **Tag the REQUEST**: Swap the REQUEST file's tag:
    *   Validated: `engine tag swap [REQUEST_FILE] '#needs-review' '#done-review'`
    *   Needs rework: `engine tag swap [REQUEST_FILE] '#needs-review' '#needs-rework'`

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

---

## 3. Synthesis
*When all tasks are complete.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Debrief creation notes** (for Step 1 -- `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `REVIEW.md`
*   Write the file using the Write tool. This MUST produce a real file in the session directory.
*   Populate ALL sections from the template (`assets/TEMPLATE_REVIEW.md`).
*   Cross-Session Analysis: Transcribe findings from Phase 1.
*   Per-Debrief Verdicts: Condensed card for each debrief with verdict.
*   Leftovers: For each rework item or discovered TODO, generate a micro-dehydrated prompt:
    *   **Simple tasks** (delete a file, rename, small config change): Just a plain instruction. No command protocol needed.
    *   **Complex tasks** (feature rework, bug investigation, test gaps): Recommend a command (`/implement`, `/fix`, `/test`, `/analyze`) with a self-contained prompt referencing the review report and original session.
    *   Enough context for the user to copy-paste and immediately act.

**Walk-through config** (for Step 3 -- `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  Summary format: "Validated: N, Needs Rework: M, Leftovers Spawned: K."
```

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
