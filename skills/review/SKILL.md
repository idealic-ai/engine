---
name: review
description: "Reviews and validates work across sessions for consistency and correctness. Triggers: \"review session work\", \"validate debriefs\", \"approve session reports\", \"end-of-day review\"."
version: 4.0
tier: protocol
---

Reviews and validates work across sessions for consistency and correctness.

# Review Protocol (The Multiplexer)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "RESOLVE",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_SELECT_MODE", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": ["§CMD_FIND_TAGGED_FILES"],
      "proof": ["mode", "sessionDir", "parametersParsed", "debriefsDiscovered"], "gate": false},
    {"label": "1", "name": "Discovery",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["debriefsRead", "siblingLogsPlansRead", "debriefCardsLogged", "crossSessionChecks", "conflictsFound"]},
    {"label": "2", "name": "Dashboard & Interrogation",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["dashboardPresented", "depthChosen", "roundsCompleted", "debriefsReviewed", "verdictsTagged", "logEntries"]},
    {"label": "3", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "3.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "3.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "3.3", "name": "Finding Triage",
      "steps": ["§CMD_WALK_THROUGH_RESULTS"], "commands": [], "proof": ["findingsTriaged", "delegated", "deferred", "dismissed"], "gate": false},
    {"label": "3.4", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "3.5", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/implement", "/document", "/brainstorm", "/analyze", "/chores"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_REVIEW_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_REVIEW.md",
  "requestTemplate": "assets/TEMPLATE_REVIEW_REQUEST.md",
  "responseTemplate": "assets/TEMPLATE_REVIEW_RESPONSE.md",
  "modes": {
    "quality": {"label": "Quality", "description": "Thorough validation, evidence-driven", "file": "modes/quality.md"},
    "progress": {"label": "Progress", "description": "Cross-session status reporting", "file": "modes/progress.md"},
    "evangelize": {"label": "Evangelize", "description": "Stakeholder communication, narrative", "file": "modes/evangelize.md"},
    "custom": {"label": "Custom", "description": "User-defined", "file": "modes/custom.md"}
  }
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Reviewing ___ session debriefs. Scope: ___ tagged files discovered.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Identify unvalidated debriefs (`#needs-review` and `#needs-rework`) and review delegation requests.

**Debrief & Request Discovery** (`§CMD_FIND_TAGGED_FILES`):
*   Search `sessions/` directory for `#needs-review` and `#needs-rework` tags.
*   Glob for `sessions/**/REVIEW_REQUEST_*.md` to find review delegation requests.
*   Merge and deduplicate by path. Output all found files with their source (tag-discovered or REQUEST file).

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. It defines Role, Goal, Mindset, and Review Strategy.

**On "Custom"**: Read ALL 3 named mode files first (`modes/quality.md`, `modes/progress.md`, `modes/evangelize.md`), then accept user's framing. Parse into role/goal/mindset.

**Record**: Store the selected mode. It configures:
*   Phase 0 role (from mode file)
*   Phase 2 review criteria (from mode file)

**Model Selection** (after mode selection):

Execute `§CMD_SUGGEST_EXTERNAL_MODEL` with:
> modelQuestion: "Use an external model for writing the review report instead of Claude?"

Records `externalModel` (model name or `"claude"`).

### Phase Transition
*Phase 0 always proceeds to Phase 1 -- no transition question needed.*

---

## 1. Discovery & Cross-Session Analysis
*Read everything. Build the global picture.*

§CMD_REPORT_INTENT:
> 1: Reading ___ debriefs and their sibling logs. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

**Action**:
1.  **Read All Debriefs**: For each discovered file, read the full debrief.
2.  **Read All Logs**: For each debrief's session directory, also read:
    *   The `_LOG.md` file(s) (e.g., `IMPLEMENTATION_LOG.md`, `BRAINSTORM_LOG.md`)
    *   Any `_PLAN.md` files for additional context.
    *   **Goal**: Catch buried concerns, rejected alternatives, and internal reasoning not surfaced in the debrief.
3.  **Log Debrief Cards**: For each debrief, execute `§CMD_APPEND_LOG` with the `Debrief Card` schema.
4.  **Cross-Session Analysis**: Analyze ALL debriefs together against the 4 cross-session checks:
    *   **File Overlap**: Did multiple sessions touch the same files?
    *   **Schema/Interface Conflicts**: Did sessions make incompatible changes to shared types?
    *   **Contradictory Decisions**: Did session A decide X while session B decided not-X?
    *   **Dependency Order**: Did any session depend on another session's unvalidated output?
5.  **Log Findings**: For each finding, execute `§CMD_APPEND_LOG`. **Logging is the core activity of discovery** — without rich log entries, downstream triage and the final report will be shallow and uninformative.
    *   **High Volume**: Aim for **1-3 log entries per debrief** plus cross-session entries. More is better.
    *   **Variety**: Use varied entry types to produce richer analysis:
        *   **Debrief Card** — Per-debrief summary (goal, what was done, files touched, risk flags)
        *   **Cross-Session Conflict** — File overlaps, schema conflicts, contradictory decisions
        *   **Discovery** — Interesting patterns, noteworthy achievements, positive outcomes
        *   **Weakness** — Risk flags, buried concerns, gaps in coverage
        *   **Connection** — Links between sessions, shared themes, dependency chains
        *   **Spark** — Ideas triggered by the review, improvement opportunities
        *   **Gap** — Missing tests, undocumented changes, incomplete work
    *   A thin log leads to a thin report. The log IS the raw material for the debrief, finding triage, and action items. Every unlogged thought is a lost insight.

Do NOT present findings to the user yet. Complete the full analysis first.

---

## 2. Dashboard & Per-Debrief Interrogation

### Phase 2a: Findings Summary
*Present the global picture before per-debrief review begins.*

§CMD_REPORT_INTENT:
> 2: Presenting ___ findings from ___ debriefs and cross-session analysis. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Findings Summary**: Before the dashboard, present a condensed numbered list of key findings from Phase 1. Group by type (cross-session conflicts, discoveries, weaknesses, connections, gaps). This gives the user context to calibrate their per-debrief review — they can't evaluate individual sessions without understanding the cross-cutting picture.

**Format**: Numbered list, one line per finding, grouped by type:
```
**Cross-Session Findings** (N total):
1. [CONFLICT] Sessions A and B both modified schema X — incompatible field renames
2. [CONNECTION] Sessions C and D are building the same feature from different angles
3. [DISCOVERY] Session E introduced a pattern that could simplify Session F's approach

**Per-Debrief Highlights** (N debriefs):
4. [WEAKNESS] Session A: 3 tests skipped without explanation
5. [GAP] Session B: no documentation updates despite API change
6. [SPARK] Session C: novel approach to caching worth adopting elsewhere
```

### Phase 2b: The Dashboard
*Present the per-debrief summary cards.*

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
> - **"Proceed to per-debrief review"** -- Walk through each debrief individually
> - **"Discuss findings first"** -- I want to talk about the findings summary and cross-session analysis

### Phase 2c: Per-Debrief Interrogation
*Walk through each debrief and REQUEST file with the user.*

### Interrogation Depth Selection

**Before starting per-debrief review**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How thorough should the per-debrief review be?"

| Depth | Minimum Rounds Per Debrief | When to Use |
|-------|---------------------------|-------------|
| **Short** | 1 round | Quick validation, trusted agent, small scope |
| **Medium** | 2 rounds | Standard review, moderate complexity |
| **Long** | 3+ rounds | Deep audit, critical changes, untrusted work |
| **Absolute** | Until ALL concerns resolved | High-risk sessions, production changes, security-sensitive |

Record the user's choice. This sets the **minimum** per debrief -- the agent can always ask more, and the user can always say "approve" after the minimum is met.

### Topics (Review)
*Examples of themes to explore per debrief. Adapt to the session -- skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once per debrief):
- **Acceptance criteria** -- Did the session achieve what was asked?
- **Test coverage** -- Were tests written/updated? Are they passing? Any skipped?
- **Breaking changes** -- Did this session change interfaces, schemas, or APIs that other code depends on?
- **Documentation alignment** -- Were relevant docs updated, or is there now a doc-code drift?
- **Risk flags** -- Did the agent express concerns in the log that didn't make it to the debrief?
- **Buried alternatives** -- Did the agent reject an option that the user should know about?
- **TODO completeness** -- Anything explicitly deferred or marked as future work?
- **Cross-session consistency** -- Does this session's output conflict with other concurrent sessions?

**Repeatable topics** (can be selected any number of times):
- **Followup** -- Clarify or revisit answers from previous rounds
- **Devil's advocate** -- Challenge assumptions and decisions made so far
- **What-if scenarios** -- Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** -- Drill into a specific topic from a previous round in much more detail

### Standard Validation Checklist (LLM Internal Guidance)

This is YOUR internal rubric -- do NOT present it as a form. Use it to generate contextualized findings.

1.  **Goal Alignment** -- Did the session achieve what was asked?
2.  **Completeness** -- Are all template sections filled? Any placeholders or "TBD" left?
3.  **Test Status** -- Were tests written/updated? Are they passing? Any skipped?
4.  **Breaking Changes** -- Did this session change interfaces, schemas, or APIs that other code depends on?
5.  **Risk Flags** -- Did the agent express concerns/worries in the log that didn't make it to the debrief?
6.  **Buried Alternatives** -- Did the agent reject an option in the log that the user should know about?
7.  **TODOs & Leftovers** -- Anything explicitly deferred or marked as future work?
8.  **Doc Alignment** -- Were relevant docs updated, or is there now a doc-code drift?

### Per-Debrief Review Protocol

**For each debrief (sequentially)**:

**Round counter**: Output it on each debrief: "**Reviewing debrief N of M -- Round R / {depth_minimum}+**"

1.  **Analyze Against Checklist (Internal)**: Review the debrief against the Standard Validation Checklist. Filter and contextualize -- skip checks that aren't relevant. For each relevant check, prepare a specific, contextualized finding.
    *   **Bad**: "Test Status: PASS" (meaningless)
    *   **Good**: "Test Status: 164/164 estimate + 57/57 viewer tests pass. No skipped tests. The new `mutate()` context has 3 dedicated tests covering capture, backwards compat, and before snapshot."

2.  **Present to User**: Use `AskUserQuestion` with structured options:
    *   Present your findings as detailed descriptions per option.
    *   Ask targeted questions about anything ambiguous or concerning.
    *   Always include these options:
        *   **"Approve (clean)"** -- No issues found, validate the debrief
        *   **"Approve + note TODOs"** -- Validate, but capture follow-up work
        *   **"Flag for rework"** -- Reject, mark for rework with reason
        *   **"I have questions"** -- Discuss before deciding

3.  **Process User Response**:
    *   **Approve (clean)**: Validate the debrief -- swap tags and log:
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

4.  **Log**: Execute `§CMD_LOG_INTERACTION` after each user interaction. Execute `§CMD_APPEND_LOG` with the verdict schema.

5.  **Repeat** for next debrief.

### Per-REQUEST File Review

**For each discovered `REVIEW_REQUEST_*.md` file (after all debriefs are processed)**:

1.  **Read REQUEST**: Read the full REQUEST file. Extract structured fields: Topic, Context, Expectations, Requesting Session.
2.  **Read Linked Context**: If the REQUEST references a session or specific files, read them.
3.  **Present to User**: Show the REQUEST summary and ask:
    *   **"Fulfill request"** -- Review the linked work and write a RESPONSE file
    *   **"Defer"** -- Leave the REQUEST for a future review session
    *   **"Dismiss"** -- Remove the REQUEST (tag swap to `#done-review`)

4.  **On "Fulfill request"**: Review the linked artifacts (debrief, code, etc.) using the Standard Validation Checklist. Then apply the same verdict options (Approve clean / Approve + TODOs / Flag for rework / Questions).

5.  **Write RESPONSE**: After the verdict, write a `REVIEW_RESPONSE_[TOPIC].md` in the **review session directory** using `§CMD_WRITE_FROM_TEMPLATE` with the `TEMPLATE_REVIEW_RESPONSE.md` template. Also add a `## Response` breadcrumb section to the original REQUEST file:
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
> - **"Approve and move to next debrief"** -- *(terminal: if selected, skip all others and proceed)*
> - **"More review (1 more round)"** -- Standard review round, then this gate re-appears
> - **"Devil's advocate round"** -- 1 round challenging the session's decisions, then this gate re-appears
> - **"What-if scenarios round"** -- 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** -- 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard round first -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining concerns. Ask: "Round N complete. I still have concerns about [X]. Continuing..."

---

## 3. Synthesis
*When all debriefs are reviewed.*

§CMD_REPORT_INTENT:
> 3: Synthesizing. ___ debriefs validated, ___ flagged for rework, ___ leftovers spawned.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

**Debrief generation**:

**If `externalModel` is not "claude"** (external model path):
1.  **Gather context file paths**: Collect paths to all reviewed debriefs, their logs, REVIEW_LOG.md, DIALOGUE.md, and TEMPLATE_REVIEW.md. Do NOT read them into context.
2.  **Compose prompt**: Describe the review template structure, all verdicts, cross-session findings, and leftover work items.
3.  **Execute `§CMD_EXECUTE_EXTERNAL_MODEL`** with:
    *   `prompt`: The composed review synthesis instructions
    *   `template`: `TEMPLATE_REVIEW.md` path
    *   `system`: `"You are a senior technical reviewer producing a structured review report. Output ONLY the document content in Markdown. Follow the template structure exactly."`
    *   `contextFiles`: All debrief, log, and details file paths
4.  **Write the output** as REVIEW.md and proceed with tagging.

**If `externalModel` is "claude"** (default path):
*   **Cross-Session Analysis**: Transcribe findings from Phase 1.
*   **Per-Debrief Verdicts**: Condensed card for each debrief with verdict.
*   **Leftovers**: For each rework item or discovered TODO, generate a micro-dehydrated prompt:
    *   **Simple tasks** (delete a file, rename, small config change): Just a plain instruction. No command protocol needed.
    *   **Complex tasks** (feature rework, bug investigation, test gaps): Recommend a command (`/implement`, `/fix`, `/test`, `/analyze`) with a self-contained prompt referencing the review report and original session.
    *   Enough context for the user to copy-paste and immediately act.

### 3.3. Finding Triage (Action Planning)
*Convert review findings into action. Walk through each finding with the user and decide its fate.*

§CMD_REPORT_INTENT:
> 3.3: Triaging ___ findings into action items.
> Focus: cross-session conflicts, risk flags, discoveries, gaps, and sparks from Phase 1 discovery.
> Not: re-reviewing individual debriefs — verdicts are final from Phase 2.

§CMD_EXECUTE_PHASE_STEPS(3.3.*)

Execute `§CMD_WALK_THROUGH_RESULTS` with the **Walk-Through Config** below.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "findings"
  gateQuestion: "Review findings ready for triage. Walk through them?"
  debriefFile: "REVIEW.md"
  sourceArtifact: "REVIEW_LOG.md"
  itemSource: "Log entries from Phase 1 Discovery (Debrief Cards, Cross-Session Conflicts, Discoveries, Weaknesses, Connections, Sparks, Gaps)"
  triageOptions:
    - "Act now — create follow-up task"
    - "Defer — tag for future session"
    - "Dismiss — not actionable"
    - "Discuss — need more context"
```

**What gets triaged**: All findings logged during Phase 1 Discovery — cross-session conflicts, risk flags, buried alternatives, noteworthy patterns, gaps, and sparks. Per-debrief verdicts (approve/rework) are NOT retriaged — those are final from Phase 2.

**Triage outcomes**:
*   **Act now**: The finding becomes a concrete follow-up task. The agent generates a micro-dehydrated prompt recommending a skill (`/implement`, `/fix`, `/test`, `/analyze`, `/brainstorm`) with enough context to immediately act.
*   **Defer**: Tag with appropriate `#needs-X` for future dispatch. The finding is recorded in REVIEW.md's Leftovers section.
*   **Dismiss**: Acknowledged but no action needed. Recorded as "Dismissed" in the triage log.
*   **Discuss**: User wants more context before deciding. Agent provides additional analysis, then re-presents the triage options.

**Post-triage summary**: After all findings are triaged, output a condensed summary:
*   N findings triaged: X acted on, Y deferred, Z dismissed
