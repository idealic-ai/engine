# LLM Command & Session Standards
[!!!] CRITICAL: If you are reading this file, you have ALREADY succeeded in loading the core standards.
[!!!] DO NOT READ THIS FILE AGAIN.
[!!!] DO NOT LOAD `INVARIANTS.md` AGAIN (if already loaded).

## Overview
This document defines the **Immutable "Laws of Physics"** for all Agent interactions.
**CRITICAL**: You must load and obey these rules. Ignorance is not an excuse.

---

## 1. File Operation Commands (The "Physics")

### ¶CMD_WRITE_FROM_TEMPLATE
**Definition**: To create a new artifact (Plan, Debrief), use the Template already loaded in your context.

**Algorithm**:
1.  **Read**: Locate the relevant template (`TEMPLATE_*.md`) block in your current context.
2.  **Populate**: In your memory, fill in the placeholders (e.g., `[TOPIC]`).
3.  **Write**: Execute the `write` tool to create the destination file with the populated content.

**Constraint**:
*   Do NOT use `cp`.
*   Do NOT read the template file from disk (it is already in your context).
*   **STRICT TEMPLATE FIDELITY**: Do not invent headers or change structure.

### ¶CMD_APPEND_LOG
**Definition**: Logs are Append-Only streams.
**Constraint**: **BLIND WRITE**. You will not see the file content. Trust the append. See `¶INV_TRUST_CACHED_CONTEXT`.
**Constraint**: **TIMESTAMPS**. `engine log` auto-injects `[YYYY-MM-DD HH:MM:SS]` into the first `## ` heading. Do NOT include timestamps manually.

**Algorithm**:
1.  **Reference**: Look at the loaded `[SESSION_TYPE]_LOG.md` schema in your context.
2.  **Construct**: Prepare Markdown content matching that schema. Use `## ` headings (no timestamp — `engine log` adds it).
3.  **Execute**:
    ```bash
    engine log sessions/[YYYY_MM_DD]_[TOPIC]/[LOG_NAME].md <<'EOF'
    ## [Header/Type]
    *   **Item**: ...
    *   **Details**: ...
    EOF
    ```
    *   The script auto-prepends a blank line, creates parent dirs, auto-injects timestamp into first `## ` heading, and appends content.
    *   In append mode, content MUST contain a `## ` heading or `engine log` will error (exit 1).
    *   Whitelisted globally via `Bash(engine *)` — no permission prompts.

**Forbidden Patterns (DO NOT DO)**:
*   ❌ **The "Read-Modify-Write"**: Reading the file, adding text in Python/JS, and writing it back.
*   ❌ **The "Placeholder Hunt"**: Looking for `{{NEXT_ENTRY}}`.

### ¶CMD_LINK_FILE
**Definition**: The Chat is for Meta-Discussion. The Filesystem is for Content.
**Algorithm**:
1.  **Action**: Create/Update the file.
2.  **Report**: Output the full clickable URL per `¶INV_TERMINAL_FILE_LINKS`. Resolve `~` and relative paths to absolute. Prepend the terminal link protocol from your system prompt.
    *   **Example**: `cursor://file/Users/name/.claude/skills/implement/SKILL.md`
    *   **Bad**: `` `sessions/2026_02_14_TOPIC/IMPLEMENTATION.md` `` (not clickable)
3.  **Constraint**: NEVER echo the file content in the chat.

### [¶CMD_AWAIT_TAG](commands/CMD_AWAIT_TAG.md)
Start a background watcher that blocks until a specific tag appears on a file or directory.

---

## 2. Process Control Commands (The "Guards")

### ¶CMD_LOG_BETWEEN_TOOL_USES
**Definition**: Log progress at a regular cadence between tool calls. Mechanically enforced by `pre-tool-use-heartbeat.sh`.
**Rule**: After N tool calls without an `engine log` append, the heartbeat hook warns (at `toolUseWithoutLogsWarnAfter`, default 3) and blocks (at `toolUseWithoutLogsBlockAfter`, default 10). Thresholds are configurable in `.state.json`.
**When Blocked**: Append a progress entry via `§CMD_APPEND_LOG`. The log template is already in your context (preloaded by `template-preload` rule or SubagentStart hook).
**Related**: `§CMD_APPEND_LOG` (the logging mechanism), `§CMD_THINK_IN_LOG` (the logging rationale).

### ¶CMD_REQUIRE_ACTIVE_SESSION
**Definition**: All tool use requires an active session. Mechanically enforced by `pre-tool-use-session-gate.sh`.
**Rule**: The session gate blocks all non-whitelisted tools until `engine session activate` succeeds. Whitelisted: `Read(~/.claude/*)`, `Bash(engine session)`, `AskUserQuestion`, `Skill`.
**When Blocked**: Use `AskUserQuestion` to ask the user which skill to activate. Suggest `/do` for quick ad-hoc tasks, or a structured skill (`/implement`, `/analyze`, `/fix`, etc.) for larger work. Then invoke the skill via the Skill tool.
**Related**: `¶INV_SKILL_PROTOCOL_MANDATORY` (skills require formal session activation), `§CMD_MAINTAIN_SESSION_DIR` (session directory lifecycle).

### ¶CMD_NO_MICRO_NARRATION
**Definition**: Do not narrate micro-steps or internal thoughts in the chat.
**Rule**: The Chat is for **User Communication Only** (Questions, Plans, Reports). It is NOT for debug logs or stream of consciousness.
**Constraint**: NEVER output text like "Wait, I need to check...", "Okay, reading file...", or "Executing...". Just call the tool.
**Bad**: "I will read the file now. [Tool Call]. Okay, I read it."
**Good**: [Tool Call]

### ¶CMD_ESCAPE_TAG_REFERENCES
**Definition**: Backtick-escape tag references in body text/chat. Bare `#tag` = actual tag; backticked `` `#tag` `` = reference only.
**Reference**: See `~/.claude/.directives/SIGILS.md` § Escaping Convention for the full behavioral rule, reading/writing conventions, and examples.

### ¶CMD_DEBUG_HOOKS_IF_PROMPTED
**Definition**: When the user asks to debug hooks or asks about hook/guard behavior, switch to verbose hook reporting mode.
**Trigger**: User says "debug hooks", "what hooks are firing", "show me guards", "why is this being injected", or similar.
**Algorithm**:
1.  **Announce**: "Hook debug mode active. I'll report all hook activity I observe."
2.  **For each hook response you receive** (system-reminder tags with hook context), report in chat:
    *   **Hook name**: Which hook fired (e.g., `pre-tool-use-heartbeat.sh`, `post-tool-use-discovery.sh`)
    *   **Trigger**: What tool call triggered it
    *   **Injected content**: What was injected (preloaded files, directives, warnings, blocks)
    *   **Effect**: What it changed (added to pendingDirectives, blocked a tool call, warned about logging)
3.  **Continue reporting** until the user says "stop debugging" or the session ends.
**Constraint**: This is observational — do NOT modify hook behavior. Just report what you see.
**Constraint**: Only activate when explicitly prompted. Do NOT auto-activate on hook errors or warnings.

### ¶CMD_THINK_IN_LOG
**Definition**: The Log file is your Brain. The Chat is your Mouth.
**Rule**: Before writing code or answering complex questions, write your specific reasoning into the active `_LOG.md`.
**Constraint**: Do NOT output your thinking process in the chat. Write it to the log file or keep it internal.

### ¶CMD_ASSUME_ROLE
**Definition**: Cognitive anchoring to a specific persona.
**Rule**: Execute this during the Setup Phase to shift internal weighting towards specific values (e.g., TDD, Skepticism, Rigor).
**Algorithm**:
1.  **Read**: The "Role", "Goal", and "Mindset" provided in the prompt.
2.  **Internalize**: Explicitly acknowledge the role in chat.
3.  **Effect**: Maintain this persona for the duration of the session.

### ¶CMD_INIT_LOG
**Definition**: Establates or reconnects to a session log.
**Algorithm**:
1.  **Check**: Does the destination log file already exist?
2.  **Action**: 
    *   *If No*: Create it using `§CMD_WRITE_FROM_TEMPLATE`.
    *   *If Yes*: Continue appending to it using `§CMD_APPEND_LOG`.

### ¶CMD_WAIT_FOR_USER_CONFIRMATION
**Definition**: You are not allowed to switch Phases (e.g., Brainstorm -> Implement) or proceed past "Wait" steps on your own.
**Rule**: When a protocol says "Wait" or "Stop", you MUST end your turn immediately. Do NOT call any more tools. Do NOT provide more analysis.
**Algorithm**:
1.  **Stop**: Finish the current instruction.
2.  **Ask**: "Session complete. Debrief at [path]. Proceed to [Next Phase]?" or similar.
3.  **Wait**: End your turn. Do nothing until the user provides input.

### ¶CMD_REFUSE_OFF_COURSE
**Definition**: The deviation router. When you or the user wants to deviate from the active skill protocol — skip a step, do work that belongs to another skill, or abandon the current phase — you MUST surface the conflict instead of acting silently.

**Trigger** (bidirectional):
*   **Model-initiated**: You judge a protocol step as unnecessary, too simple, or mismatched to the user's intent.
*   **User-initiated**: The user asks you to do something that belongs to a different skill or would skip the current protocol phase.

**Rule**: You are NEVER allowed to silently skip a protocol step. If you feel the impulse to skip, that impulse is your trigger to fire this command. The skip-impulse becomes the ask-impulse.

**Algorithm**:
1.  **Detect**: You are about to skip a protocol step, or the user asked for off-protocol work.
2.  **State the Conflict**: In one sentence, explain what you were about to skip or what the user asked for, and why it conflicts with the active protocol.
3.  **Route**: Execute `AskUserQuestion` with these options:

    *   **Option 1 — "Continue protocol"**
        *   **Description**: Resume the current step as specified. No deviation.

    *   **Option 2 — "Switch to /[skill]"**
        *   **Description**: Explicitly change skill. The agent will propose the appropriate skill name.

    *   **Option 3 — "Tag & defer"**
        *   **Description**: Tag the item with `#needs-X` (e.g., `#needs-implementation`, `#needs-research`) and continue the current protocol.

    *   **Option 4 — "One-time deviation"**
        *   **Description**: Allow the deviation this once. The agent logs it and returns to the protocol after.

    *   **Option 5 — "Inline quick action"**
        *   **Description**: For trivial asks (e.g., "what's the file path?", "what time is it"). No logging, no session overhead.

4.  **Execute**: Follow the user's choice. If "One-time deviation", log it to the active `_LOG.md` before executing.
5.  **Return**: After any deviation (options 4 or 5), explicitly state which protocol step you're resuming.

**Constraints**:
*   **No Silent Skips**: If you skip a step without firing this command, you have violated the protocol. There is no "too simple" exception.
*   **No Self-Authorization**: You cannot choose an option yourself. The user always decides.
*   **Scope**: A "deviation" means skipping a protocol STEP or performing work that belongs to a different SKILL. Individual tool calls within a step (e.g., reading an extra file for context) are not deviations.
*   **User Priority**: The user's explicit requests always take priority over the session type. If the user directly asks for analysis during an implementation session, that is not a deviation — do it, then return to the protocol. Only fire this command when the agent itself wants to go off-course, or when the user's request would skip a protocol step. "This is an implementation task, not an analysis task" is NEVER a valid refusal when the user directly asked for analysis.

**Examples**:

*   **Example 1 — Model wants to skip RAG during `/implement`**:
    > "Phase 2 requires RAG search (`§CMD_INGEST_CONTEXT_BEFORE_WORK`), but I think the context is already sufficient from the brainstorm session. This conflicts with the protocol."
    > → [AskUserQuestion with 5 options]

*   **Example 2 — User asks to make a code change during `/analyze`**:
    > "You asked me to fix the bug I found, but we're in an `/analyze` session (read-only). Making changes belongs to `/implement`."
    > → [AskUserQuestion with 5 options]

*   **Example 3 — User asks to brainstorm alternatives during `/implement`**:
    > "You want to explore alternative approaches, but we're in Phase 5 (Build Loop) of `/implement`. Exploration belongs to `/brainstorm`."
    > → [AskUserQuestion with 5 options]

*   **Example 4 — Model judges interrogation as overkill**:
    > "Phase 3 requires a minimum of 3 interrogation rounds, but the task feels straightforward. I'm tempted to skip to planning. This conflicts with the protocol."
    > → [AskUserQuestion with 5 options]

### ¶CMD_SESSION_CLI
**CRITICAL**: 
    * These are the exact command formats. Do NOT invent flags (e.g., `--description`). Description and parameters are always piped via stdin heredoc.
    * Use `engine` command directly, dont attempt to resolve the symlink or add `.sh`, per §INV_ENGINE_COMMAND_DISPATCH


```bash
# Activate (with parameters — first activation)
# Remember to pass COMPLETE §CMD_PARSE_PARAMETERS json schema with all required fields
engine session activate sessions/YYYY_MM_DD_TOPIC skill-name <<'EOF'
{ "taskSummary": "...", "taskType": "...", ... }
EOF

# Activate (re-activation — no new parameters)
engine session activate sessions/YYYY_MM_DD_TOPIC skill-name < /dev/null

# Deactivate (description via stdin, keywords via flag)
engine session deactivate sessions/YYYY_MM_DD_TOPIC --keywords "kw1,kw2" <<'EOF'
What was done in this session (1-3 lines)
EOF

# Phase transition (sequential)
engine session phase sessions/YYYY_MM_DD_TOPIC "N: Phase Name"

# Phase transition (non-sequential — requires user approval)
engine session phase sessions/YYYY_MM_DD_TOPIC "N: Phase Name" --user-approved "Reason"

# Continue session after context overflow restart (used by /session continue)
engine session continue sessions/YYYY_MM_DD_TOPIC

# Find sessions (subcommands: today, yesterday, recent, date, range, topic, tag, active, since, window, all)
engine find-sessions recent
engine find-sessions today
engine find-sessions topic <NAME>
engine find-sessions tag '#needs-review'
engine find-sessions active
```

**Activate flags** (the ONLY valid flags — do NOT invent others): `--fleet-pane`, `--target-file`, `--user-approved`, `--fast-track`.

**Workspace-aware path resolution**: Session paths accept 3 forms:
1. **Bare name**: `2026_02_14_X` → resolved via `$WORKSPACE/sessions/` or `sessions/`
2. **With prefix**: `sessions/2026_02_14_X` → prefix stripped, then resolved same as bare
3. **Full path**: `epic/sessions/2026_02_14_X` → used as-is (must contain `sessions/`)

When `WORKSPACE` env var is set (e.g., `WORKSPACE=apps/estimate-viewer/extraction`), sessions live at `$WORKSPACE/sessions/`. All session subcommands are workspace-aware via `resolve_session_path()` in lib.sh.

---

### [¶CMD_PARSE_PARAMETERS](commands/CMD_PARSE_PARAMETERS.md)
Parse and validate session parameters, construct the JSON schema, pipe to `engine session activate`, and process context output.

### [¶CMD_MAINTAIN_SESSION_DIR](commands/CMD_MAINTAIN_SESSION_DIR.md)
Anchor the agent in a single session directory — identify/reuse/create, detect existing skill artifacts, echo the session path.

### ¶CMD_UPDATE_PHASE
**Definition**: Update the current skill phase in `.state.json` for status line display, context overflow recovery, and **phase enforcement**.
**Rule**: Call this when transitioning between phases of a skill protocol. Phase enforcement ensures sequential progression.

**Algorithm**:
1.  **Execute** (sequential transition — next phase in order): Use the `engine session phase` command (see `§CMD_SESSION_CLI` for exact syntax).
    *   Phase labels MUST start with a number: `"N: Name"` or `"N.M: Name"` (e.g., `"4: Planning"`, `"4.1: Agent Handoff"`).
2.  **Execute** (non-sequential transition — skip forward or go backward): Use `engine session phase` with `--user-approved` flag (see `§CMD_SESSION_CLI`).
    *   **Required** (`¶INV_USER_APPROVED_REQUIRES_TOOL`): `AskUserQuestion` is the ONLY valid mechanism to obtain a `--user-approved` reason. The reason string MUST quote the user's answer from the `AskUserQuestion` tool response. Self-authored reasons are invalid. See the invariant for valid/invalid examples.
    *   **Prohibited justifications** (these are never valid `--user-approved` reasons):
        *   `"Reason: This phase doesn't apply"` — agent-authored, not user words
        *   `"Reason: Task is too simple"` — agent judgment, not user authorization
        *   `"Reason: Already covered in previous session"` — agent inference
    *   **Valid justifications** (must quote the user's actual response):
        *   `"Reason: User said 'Skip to synthesis' in response to 'Ready to proceed?'"`
        *   `"Reason: User said 'Go back to planning' in response to 'How to proceed?'"`
    *   Without `--user-approved`, non-sequential transitions are **rejected** (exit 1).
3.  **Proof-gated transitions (FROM validation)**: If the current phase (being left) declares `proof` fields in its phases array entry, the agent MUST pipe proof as a JSON object via STDIN when transitioning away from it. Proof validates what the agent accomplished IN that phase before leaving. Semantically: proof on a phase = "what you must accomplish in this phase before leaving it."
    *   **Format**: JSON object piped via heredoc. Example: `{"depth_chosen": "Short", "rounds_completed": 3}`. Backward compat: `key: value` lines are still accepted with a deprecation warning.
    *   **Validation**: Two levels — (1) field presence: all declared proof fields must be present and non-blank, (2) schema validation: proof is validated against the combined JSON Schema from the phase's CMD step files (exit 1 on failure). CMD proof schemas use standard JSON Schema format (see `## PROOF FOR` sections in CMD files).
    *   **No proof declared on current phase**: Transition proceeds normally. If sibling phases have proof fields, a stderr warning is emitted (nudge to add proof).
    *   **Empty proof array** (`proof: []`): Passes trivially — intentionally no requirements.
    *   **First transition** (no current phase set): FROM validation is skipped — there is no phase to leave.
    *   **Re-entering same phase**: FROM validation is skipped — you are not leaving.
    *   **FROM proof applies even on skip**: When skipping Phase 1→3 with `--user-approved`, FROM validation checks Phase 1's proof (the phase being LEFT), not Phase 2's. `--user-approved` bypasses sequential enforcement but NOT proof validation — these are independent checks.
    *   **Proof storage**: When proof is provided (regardless of whether the current phase declares proof fields), the `phaseHistory` entry stores it as an object: `{"phase": "N: Name", "ts": "...", "proof": {"field": "value"}}`. Proof is always parsed and stored when piped via STDIN.
    *   **Example** (leaving Phase 2: Interrogation which declares `proof: ["depth_chosen", "rounds_completed"]`, transitioning to Phase 3):
        ```bash
        engine session phase sessions/DIR "3: Planning" <<'EOF'
        {"depth_chosen": "Short", "rounds_completed": 3}
        EOF
        ```
4.  **Letter suffix** (optional branch labels): Sub-phase labels may include a single uppercase letter suffix: `"3.1A: Agent Handoff"`.
    *   **Enforcement**: The letter is stripped for enforcement purposes (enforces as `3.1`). The full label with letter is preserved in `phaseHistory`.
    *   **Constraints**: Single uppercase letter only, only on sub-phases (`N.M` format). Lowercase or double letters are rejected.
    *   **Use case**: Distinguishing alternative branches in the audit trail (e.g., `3.1A: Single Agent` vs `3.1B: Parallel Agents`).
5.  **Effect**:
    *   Updates `currentPhase` in `.state.json`
    *   Appends to `phaseHistory` array (audit trail of all transitions, with proof if provided)
    *   Clears `loading` flag and resets heartbeat counters
    *   Status line displays as `[skill:P3]`
    *   If context overflow triggers restart, new Claude resumes from this phase
6.  **Sub-phase auto-append**: If you call a phase like `"4.1: Agent Handoff"` and no such phase is declared, it is automatically inserted into the `phases` array — as long as its major number matches the current phase's major number and its minor number is higher. No explicit append command needed.

**Phase Enforcement** (when `.state.json` has a `phases` array):
*   **Sequential forward**: Transition to the next declared phase is always allowed.
*   **Skip forward**: Requires `--user-approved`. Error message shows expected next phase.
*   **Go backward**: Requires `--user-approved`. Error message shows expected next phase.
*   **Sub-phase**: Same major, higher minor → auto-appended and allowed.
*   **Proof-gated (FROM)**: If the current phase (being left) has `proof` fields, STDIN proof is required and validated.
*   **No `phases` array**: Enforcement is disabled (backward compat). Any transition allowed.
*   **Context overflow recovery**: Use `engine session continue` (not `phase`) to resume after restart. `continue` clears loading and resets heartbeat counters without touching phase state.

**When to Call**:
*   At the START of each major phase (after completing the previous one)
*   Phase labels must match the `phases` array declared at session activation

### [¶CMD_DEHYDRATE](commands/CMD_DEHYDRATE.md)
Captures current session context as JSON and triggers context overflow restart. Always preloaded by SessionStart hook.

### [¶CMD_RESUME_SESSION](commands/CMD_RESUME_SESSION.md)
Resumes a session after interruption — fast path (dehydrated context) or slow path (bare continuation). Replaces the former `§CMD_REHYDRATE`. Always preloaded by SessionStart hook.

### [¶CMD_PRESENT_NEXT_STEPS](commands/CMD_PRESENT_NEXT_STEPS.md)
Post-synthesis routing menu — presents continue/switch skill/done options while session is idle.

### ¶CMD_FREEZE_CONTEXT
**Definition**: Work strictly within the current Context Window boundaries. Do NOT explore the filesystem.
**Scope**: This is a **phase-specific** constraint, typically applied during Setup (Phase 1) to prevent premature exploration. It does NOT apply to later phases like Context Ingestion (Phase 2), which explicitly require running searches.
**Rules**:
1.  **Forbidden** (during this constraint): `read_file`, `grep`, `ls`, `codebase_search`.
2.  **Allowed**: Only information currently in your context (User Prompt, System Prompt, Loaded Authority).
3.  **Exception**: If a file is CRITICAL and missing, you must **ASK** the user to load it. Do not load it yourself.
4.  **Expiration**: This constraint expires when the protocol moves to a phase that requires exploration (e.g., Context Ingestion). Do not carry this constraint forward into later phases.

### ¶CMD_TRACK_PROGRESS
**Definition**: Use an internal `TODO` list to manage work items and track progress throughout the session.

**Rules**:
1.  **Create TODOs**: When interpreting a new command, request, or requirement, create a new TODO item describing it.
2.  **Track Status**: Each TODO should be marked as `Open`, `In Progress`, or `Done`.
3.  **Update Transparently**: Update TODO statuses as progress is made, and make these updates visible in logs or status reports.
4.  **Do Not Omit**: Do not skip or silently remove TODOs; all planned actions must have a TODO entry.
5.  **Review Frequently**: Regularly review the TODO list, especially before major execution steps, to ensure all items are addressed.

---

## 3. Interaction Protocols (The "Conversation")

### ¶CMD_ASK_USER_IF_STUCK
**Definition**: Proactive halting when progress is stalled or ambiguity is high.
**Rule**: Do not spin in loops. If 2+ attempts fail or you are unsure of the path, stop.
**Algorithm**:
1.  **Detect**: Are you repeating errors? Is the path unclear?
2.  **Stop**: Do not execute further tools.
3.  **Ask**: "I am stuck on [Problem]. Options are A/B. Guidance?"

### [¶CMD_ASK_ROUND](commands/CMD_ASK_ROUND.md)
Standard protocol for information gathering — formulate 3-5 targeted questions via `AskUserQuestion`.

---

## 4. Composite Workflow Commands (The "Shortcuts")

### [¶CMD_INGEST_CONTEXT_BEFORE_WORK](commands/CMD_INGEST_CONTEXT_BEFORE_WORK.md)
Present discovered context (alerts, RAG sessions/docs, delegations) as a multichoice menu before work begins.

### [¶CMD_GENERATE_DEBRIEF](commands/CMD_GENERATE_DEBRIEF.md)
Creates or regenerates a standardized debrief artifact with continuation detection, template population, and `#needs-review` tagging.

### [¶CMD_RUN_SYNTHESIS_PIPELINE](commands/CMD_RUN_SYNTHESIS_PIPELINE.md)
Centralized synthesis pipeline orchestrator — 4 sub-phases: Checklists, Debrief, Pipeline (directives, delegations, dispatch, discoveries, alerts, leftover), Close.

### [¶CMD_CLOSE_SESSION](commands/CMD_CLOSE_SESSION.md)
Verify debrief gate, deactivate the session, display RAG results, and present next-skill menu from `nextSkills` array.

### [¶CMD_SELECT_MODE](commands/CMD_SELECT_MODE.md)
Present skill mode selection (3 named + Custom), load mode file, handle Custom blending, record config, execute `§CMD_ASSUME_ROLE`.

### [¶CMD_SUGGEST_EXTERNAL_MODEL](commands/CMD_SUGGEST_EXTERNAL_MODEL.md)
Present external model selection via `AskUserQuestion` (Gemini Pro, Flash, or Claude default) for downstream use by `§CMD_EXECUTE_EXTERNAL_MODEL`.

### [¶CMD_EXECUTE_EXTERNAL_MODEL](commands/CMD_EXECUTE_EXTERNAL_MODEL.md)
Executes a writing/synthesis task via an external model (Gemini) with graceful fallback to Claude on failure.

### [¶CMD_GENERATE_PLAN](commands/CMD_GENERATE_PLAN.md)
Creates a standardized plan artifact using the `_PLAN.md` template from context.

### [¶CMD_REPORT_INTENT](commands/CMD_REPORT_INTENT.md)
Display-only 3-line blockquote (What / How / Not-what) at phase entry. Serves as user progress signal + agent cognitive anchoring. Called as first step of each applicable phase; SKILL.md provides per-phase content templates with `___` placeholders. Boolean proof: `intent_reported`.

### ¶CMD_LOG_INTERACTION
**Definition**: Records a User Assertion or Discussion into the session's high-fidelity `DETAILS.md`.
**Usage**: Execute this immediately after receiving an important User Assertion or Discussion that was NOT triggered by `AskUserQuestion`.

**Auto-Logging**: Q&A entries from `AskUserQuestion` are **automatically logged** by the `post-tool-use-details-log.sh` PostToolUse hook. The hook captures the agent's preamble (from transcript), questions, options, and user answers. **Do NOT manually log AskUserQuestion interactions** — the hook handles it. Manual `§CMD_LOG_INTERACTION` is only needed for:
*   **Assertions**: The user makes an unprompted statement that shapes the work (e.g., "always use bun", "no Python").
*   **Discussions**: Non-AskUserQuestion back-and-forth that establishes important context.

**Algorithm**:
1.  **Construct**: Prepare the Markdown block following `~/.claude/skills/_shared/TEMPLATE_DETAILS.md`.
    *   **Agent**: Quote your question or the context (keep nuance/options).
    *   **User**: VERBATIM quote of the user's answer.
    *   **Action**: Paraphrase your decision/action (e.g., "Updated Plan").
2.  **Execute**:
    ```bash
    engine log sessions/[YYYY_MM_DD]_[TOPIC]/DETAILS.md <<'EOF'
    ## [Topic Summary]
    **Type**: [Assertion / Discussion]

    **Agent**:
    > [My Prompt/Question or Context]

    **User**:
    > [User Response Verbatim]

    **Agent Action/Decision**:
    > [My Reaction]

    **Context/Nuance** (Optional):
    > [Thoughts]

    ---
    EOF
    ```

### [¶CMD_INTERROGATE](commands/CMD_INTERROGATE.md)
Structured interrogation — depth selection, topic-driven round loop with between-rounds context, exit gating with proceed/extend options.

### [¶CMD_EXECUTE_SKILL_PHASES](commands/CMD_EXECUTE_SKILL_PHASES.md)
Skill-level phase orchestrator — drives the agent through all phases sequentially at the TOP of each protocol-tier SKILL.md.

### [¶CMD_EXECUTE_PHASE_STEPS](commands/CMD_EXECUTE_PHASE_STEPS.md)
Per-phase step runner — reads the current phase's `steps` array, executes each `§CMD_*` step sequentially, collects proof outputs, and runs the phase gate menu (configurable per-phase via `gate: true/false`).

### [¶CMD_SELECT_EXECUTION_PATH](commands/CMD_SELECT_EXECUTION_PATH.md)
Presents a choice between mutually exclusive execution paths (inline, agent, parallel) at gateway phases.

### [¶CMD_HANDOFF_TO_AGENT](commands/CMD_HANDOFF_TO_AGENT.md)
Standardized handoff from a parent command to an autonomous agent (opt-in, foreground).

### [¶CMD_PARALLEL_HANDOFF](commands/CMD_PARALLEL_HANDOFF.md)
Parallel agent handoff — analyzes plan dependencies, derives independent chunks, and launches multiple agents in parallel.

### [¶CMD_DESIGN_E2E_TEST](commands/CMD_DESIGN_E2E_TEST.md)
Designs and runs e2e reproduction tests — creates a sandbox, reproduces "before" behavior, applies fix, demonstrates "after" behavior.

### [¶CMD_RECOVER_SESSION](commands/CMD_RECOVER_SESSION.md)
Re-initialize skill context after a context overflow restart.

### [¶CMD_REPORT_ARTIFACTS](commands/CMD_REPORT_ARTIFACTS.md)
Final summary step — lists all files created or modified during the session as clickable links.

### [¶CMD_REPORT_SUMMARY](commands/CMD_REPORT_SUMMARY.md)
Produces a dense 2-paragraph narrative summary of the session's work.

### ¶CMD_RESUME_AFTER_CLOSE
**Definition**: When the user sends a message after a skill has completed its synthesis phase, re-anchor to the session and continue logging. No question — assume continuation by default.
**Why**: Without this, post-skill conversation loses session context — no logging, no debrief updates, no artifact trail. Work happens but leaves no record.
**Trigger**: The user sends a message AND all of these are true:
*   A debrief file exists in the session directory (e.g., `IMPLEMENTATION.md`, `ANALYSIS.md`, `BRAINSTORM.md`). The debrief's existence is the marker that synthesis completed.
*   The conversation is still active (same Claude Code session).
*   The user's message implies further work (not just "thanks" or "bye").

**Algorithm**:
1.  **Detect**: You just finished a skill's synthesis phase and the user is now asking for more work or discussing the topic further.
2.  **Reactivate Session (CRITICAL)**:
    *   Execute `engine session activate [sessionDir] [skill]` to re-register this Claude process with the session.
    *   *Why*: After context overflow restart or new conversation, the status line reads from `.state.json`. Without reactivation, it shows stale session info.
3.  **Same Topic — Assume Continuation**:
    *   **Announce** (not a question): "📂 Continuing in `[sessionDir]` — logging resumed."
    *   **Log Continuation Header**: Append to the existing `_LOG.md`:
        ```bash
        engine log [sessionDir]/[LOG_NAME].md <<'EOF'
        ## ♻️ Session Continuation
        *   **Trigger**: User requested further work after synthesis.
        *   **Goal**: [brief description of what user asked for]
        EOF
        ```
    *   **Work**: Execute the user's request. Continue logging as normal (same `§CMD_APPEND_LOG` cadence as the original skill).
4.  **Different Topic — Ask First**:
    *   If the user's message is clearly about a **different topic**:
        > "This looks like a new topic. Start fresh session, or continue in `[sessionDir]`?"
    *   Let the user decide. If they choose fresh, the next skill invocation will create a new session via `§CMD_MAINTAIN_SESSION_DIR`.
5.  **Different Skill Invoked** (e.g., finished `/implement`, now running `/test`):
    *   The new skill handles session selection via `§CMD_MAINTAIN_SESSION_DIR` (which will detect existing artifacts and ask appropriately).
    *   **Log File Switching**: The new skill uses its own log file (e.g., `/test` uses `TESTING_LOG.md`, not `IMPLEMENTATION_LOG.md`). Each skill owns its log format.
    *   The session directory stays the same (sessions are multi-modal), but logs are skill-specific.
6.  **Debrief Regeneration (CRITICAL)**:
    *   **Do NOT append** to the debrief. The debrief must remain a single coherent artifact.
    *   **Detect Break Point**: When the continuation work is complete — user says "thanks", "that's it", asks about something unrelated, or there's a natural lull — the agent must nudge:
        > "Before we move on, let me update the debrief to reflect the continuation work."
    *   **Regenerate**: Re-run `§CMD_GENERATE_DEBRIEF` using the **full session context** (original work + continuation). This **replaces** the existing debrief file.
    *   **Why Regenerate**: A debrief is a summary of the entire session. Appending creates a patchwork; regenerating keeps it coherent and properly structured.
7.  **Trivial Messages**: If the user's message is clearly conversational (e.g., "thanks", "got it", "bye"), respond naturally without triggering this protocol — but still offer to update the debrief if continuation work was done:
    > "Got it. Want me to update the debrief before we wrap up?"

### [¶CMD_VALIDATE_ARTIFACTS](commands/CMD_VALIDATE_ARTIFACTS.md)
Validates session artifacts before deactivation — 3 validations (tag scan, checklists, request files).

### [¶CMD_PROCESS_CHECKLISTS](commands/CMD_PROCESS_CHECKLISTS.md)
Processes discovered CHECKLIST.md files during synthesis — evaluates items and quotes results back to `engine session check`.

### [¶CMD_RESOLVE_BARE_TAGS](commands/CMD_RESOLVE_BARE_TAGS.md)
Handle bare inline lifecycle tags from `engine session check` — present promote/acknowledge/escape menu for each.

### [¶CMD_MANAGE_DIRECTIVES](commands/CMD_MANAGE_DIRECTIVES.md)
Unified end-of-session directive management — AGENTS.md updates, invariant capture, pitfall capture.

### [¶CMD_CAPTURE_KNOWLEDGE](commands/CMD_CAPTURE_KNOWLEDGE.md)
Parameterized capture loop for extracting session learnings (invariants, pitfalls) into directive files.

### [¶CMD_CAPTURE_SIDE_DISCOVERIES](commands/CMD_CAPTURE_SIDE_DISCOVERIES.md)
Scans the session log for side-discovery entries and presents a multichoice menu to tag them for future dispatch.

### [¶CMD_DELEGATE](commands/CMD_DELEGATE.md)
Write a delegation REQUEST file, apply the appropriate tag, and execute the chosen delegation mode (async, blocking, or silent).

### [¶CMD_DISPATCH_APPROVAL](commands/CMD_DISPATCH_APPROVAL.md)
Scan `#needs-X` tags in session, group by type, present approve/claim/review/defer menu, execute tag swaps.

### [¶CMD_PROCESS_DELEGATIONS](commands/CMD_PROCESS_DELEGATIONS.md)
Scans session artifacts for unresolved bare `#needs-X` inline tags and invokes `/delegation-create` for each one.

### [¶CMD_RESOLVE_CROSS_SESSION_TAGS](commands/CMD_RESOLVE_CROSS_SESSION_TAGS.md)
Traces fulfilled REQUEST files back to requesting sessions and resolves the original inline source tags.

### [¶CMD_MANAGE_BACKLINKS](commands/CMD_MANAGE_BACKLINKS.md)
Creates and maintains cross-document links between related sessions (continuations, derived work, delegations).

### [¶CMD_REPORT_LEFTOVER_WORK](commands/CMD_REPORT_LEFTOVER_WORK.md)
Extracts unfinished items from session artifacts and presents a concise report in chat before the next-skill menu.

### [¶CMD_DECISION_TREE](commands/CMD_DECISION_TREE.md)
General-purpose declarative decision collector. Navigates markdown-defined trees via `AskUserQuestion`. Supports single-item and batch (up to 4 items) invocation.

### [¶CMD_TAG_TRIAGE](commands/CMD_TAG_TRIAGE.md)
Domain-specific tag-based triage. Presents dynamically-selected delegation targets per item, collects `#needs-[tag]` selections. Separated from `§CMD_DECISION_TREE` because tags have domain-specific semantics.

### [¶CMD_WALK_THROUGH_RESULTS](commands/CMD_WALK_THROUGH_RESULTS.md)
Walks the user through skill outputs or plan items with configurable granularity (None / Groups / Each item).


