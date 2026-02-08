# LLM Command & Session Standards
[!!!] CRITICAL: If you are reading this file, you have ALREADY succeeded in loading the core standards.
[!!!] DO NOT READ THIS FILE AGAIN.
[!!!] DO NOT LOAD `INVARIANTS.md` AGAIN (if already loaded).

## Overview
This document defines the **Immutable "Laws of Physics"** for all Agent interactions.
**CRITICAL**: You must load and obey these rules. Ignorance is not an excuse.

---

## 1. File Operation Commands (The "Physics")

### §CMD_POPULATE_LOADED_TEMPLATE
**Definition**: To create a new artifact (Plan, Debrief), use the Template already loaded in your context.

**Algorithm**:
1.  **Read**: Locate the relevant template (`TEMPLATE_*.md`) block in your current context.
2.  **Populate**: In your memory, fill in the placeholders (e.g., `[TOPIC]`).
3.  **Write**: Execute the `write` tool to create the destination file with the populated content.

**Constraint**:
*   Do NOT use `cp`.
*   Do NOT read the template file from disk (it is already in your context).
*   **STRICT TEMPLATE FIDELITY**: Do not invent headers or change structure.

### §CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE
**Definition**: Logs are Append-Only streams.
**Constraint**: **BLIND WRITE**. You will not see the file content. Trust the append. See `§CMD_AVOID_WASTING_TOKENS`.
**Constraint**: **TIMESTAMPS**. `log.sh` auto-injects `[YYYY-MM-DD HH:MM:SS]` into the first `## ` heading. Do NOT include timestamps manually.

**Algorithm**:
1.  **Reference**: Look at the loaded `[SESSION_TYPE]_LOG.md` schema in your context.
2.  **Construct**: Prepare Markdown content matching that schema. Use `## ` headings (no timestamp — log.sh adds it).
3.  **Execute**:
    ```bash
    ~/.claude/scripts/log.sh sessions/[YYYY_MM_DD]_[TOPIC]/[LOG_NAME].md <<'EOF'
    ## [Header/Type]
    *   **Item**: ...
    *   **Details**: ...
    EOF
    ```
    *   The script auto-prepends a blank line, creates parent dirs, auto-injects timestamp into first `## ` heading, and appends content.
    *   In append mode, content MUST contain a `## ` heading or log.sh will error (exit 1).
    *   Whitelisted globally via `Bash(~/.claude/scripts/*)` — no permission prompts.

**Forbidden Patterns (DO NOT DO)**:
*   ❌ **The "Read-Modify-Write"**: Reading the file, adding text in Python/JS, and writing it back.
*   ❌ **The "Placeholder Hunt"**: Looking for `{{NEXT_ENTRY}}`.

### §CMD_REPORT_FILE_CREATION_SILENTLY
**Definition**: The Chat is for Meta-Discussion. The Filesystem is for Content.
**Algorithm**:
1.  **Action**: Create/Update the file.
2.  **Report**: Output a clickable link per `¶INV_TERMINAL_FILE_LINKS`. Use **Full** display variant (relative path as display text).
3.  **Constraint**: NEVER echo the file content in the chat.

### §CMD_AWAIT_TAG
**Description**: Start a background watcher that blocks until a specific tag appears on a file or directory. Uses `fswatch`.
**Trigger**: After launching async work (research, delegation), optionally await the completion tag.
**Reference**: `~/.claude/standards/commands/CMD_AWAIT_TAG.md`

---

## 2. Process Control Commands (The "Guards")

### §CMD_NO_MICRO_NARRATION
**Definition**: Do not narrate micro-steps or internal thoughts in the chat.
**Rule**: The Chat is for **User Communication Only** (Questions, Plans, Reports). It is NOT for debug logs or stream of consciousness.
**Constraint**: NEVER output text like "Wait, I need to check...", "Okay, reading file...", or "Executing...". Just call the tool.
**Bad**: "I will read the file now. [Tool Call]. Okay, I read it."
**Good**: [Tool Call]

### §CMD_ESCAPE_TAG_REFERENCES
**Definition**: Backtick-escape tag references in body text/chat. Bare `#tag` = actual tag; backticked `` `#tag` `` = reference only.
**Reference**: See `~/.claude/standards/TAGS.md` § Escaping Convention for the full behavioral rule, reading/writing conventions, and examples.

### §CMD_THINK_IN_LOG
**Definition**: The Log file is your Brain. The Chat is your Mouth.
**Rule**: Before writing code or answering complex questions, write your specific reasoning into the active `_LOG.md`.
**Constraint**: Do NOT output your thinking process in the chat. Write it to the log file or keep it internal.

### §CMD_ASSUME_ROLE
**Definition**: Cognitive anchoring to a specific persona.
**Rule**: Execute this during the Setup Phase to shift internal weighting towards specific values (e.g., TDD, Skepticism, Rigor).
**Algorithm**:
1.  **Read**: The "Role", "Goal", and "Mindset" provided in the prompt.
2.  **Internalize**: Explicitly acknowledge the role in chat.
3.  **Effect**: Maintain this persona for the duration of the session.

### §CMD_INIT_OR_RESUME_LOG_SESSION
**Definition**: Establates or reconnects to a session log.
**Algorithm**:
1.  **Check**: Does the destination log file already exist?
2.  **Action**: 
    *   *If No*: Create it using `§CMD_POPULATE_LOADED_TEMPLATE`.
    *   *If Yes*: Continue appending to it using `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.

### §CMD_WAIT_FOR_USER_CONFIRMATION
**Definition**: You are not allowed to switch Phases (e.g., Brainstorm -> Implement) or proceed past "Wait" steps on your own.
**Rule**: When a protocol says "Wait" or "Stop", you MUST end your turn immediately. Do NOT call any more tools. Do NOT provide more analysis.
**Algorithm**:
1.  **Stop**: Finish the current instruction.
2.  **Ask**: "Session complete. Debrief at [path]. Proceed to [Next Phase]?" or similar.
3.  **Wait**: End your turn. Do nothing until the user provides input.

### §CMD_REFUSE_OFF_COURSE
**Definition**: The deviation router. When you or the user wants to deviate from the active skill protocol — skip a step, do work that belongs to another skill, or abandon the current phase — you MUST surface the conflict instead of acting silently.

**Trigger** (bidirectional):
*   **Model-initiated**: You judge a protocol step as unnecessary, too simple, or mismatched to the user's intent.
*   **User-initiated**: The user asks you to do something that belongs to a different skill or would skip the current protocol phase.

**Rule**: You are NEVER allowed to silently skip a protocol step. If you feel the impulse to skip, that impulse is your trigger to fire this command. The skip-impulse becomes the ask-impulse.

**Algorithm**:
1.  **Detect**: You are about to skip a protocol step, or the user asked for off-protocol work.
2.  **State the Conflict**: In one sentence, explain what you were about to skip or what the user asked for, and why it conflicts with the active protocol.
3.  **Route**: Execute `AskUserQuestion` with these options:

    | Option | Label | Description |
    |--------|-------|-------------|
    | 1 | "Continue protocol" | Resume the current step as specified. No deviation. |
    | 2 | "Switch to /[skill]" | Explicitly change skill. The agent will propose the appropriate skill name. |
    | 3 | "Tag & defer" | Tag the item with `#needs-X` (e.g., `#needs-implementation`, `#needs-research`) and continue the current protocol. |
    | 4 | "One-time deviation" | Allow the deviation this once. The agent logs it and returns to the protocol after. |
    | 5 | "Inline quick action" | For trivial asks (e.g., "what's the file path?", "what time is it"). No logging, no session overhead. |

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

### §CMD_PARSE_PARAMETERS
**Definition**: Parse and validate the session parameters before execution.
**Rule**: Execute this immediately after `§CMD_MAINTAIN_SESSION_DIR` (or as part of setup). This command outputs the "Flight Plan" for the session.

**Schema**:
```json
{
  "type": "object",
  "title": "Session Parameters",
  "required": ["sessionDir", "taskType", "taskSummary", "startedAt", "scope", "directoriesOfInterest", "preludeFiles", "contextPaths", "planTemplate", "logTemplate", "debriefTemplate", "extraInfo", "phases"],
  "properties": {
    "sessionDir": {
      "type": "string",
      "title": "Session Directory",
      "description": "Absolute or relative path to the active session folder.",
      "example": [
        "sessions14_ANALYSIS_AUTH",
        "sessions10_DEBUG_AUDIO_GLITCH",
        "sessions15_IMPLEMENT_NEW_FEATURE"
      ],
      "default": "{CURRENT_SESSION_DIR}"
    },
    "taskType": {
      "type": "string",
      "title": "Task Type",
      "description": "The active mode of operation.",
      "enum": ["ADHOC", "ANALYSIS", "BRAINSTORM", "CHANGESET", "DEBUG", "DIVERGE", "DOC_IMPROVE", "DOCUMENT_UPDATE", "EVANGELISM", "IMPLEMENTATION", "RESOLVE", "TESTING"],
      "example": ["IMPLEMENTATION", "ANALYSIS", "DEBUG"]
    },
    "taskSummary": {
      "type": "string",
      "title": "Task Summary",
      "description": "Concise summary of the user's prompt/goal.",
      "example": [
        "Refactor the AudioGraph to use SharedArrayBuffer",
        "Investigate memory leak in Worker thread",
        "Draft a plan for the new Plugin API"
      ]
    },
    "startedAt": {
      "type": "string",
      "title": "Started At",
      "description": "Timestamp when the session started.",
      "example": "2026-01-28T10:00:00Z"
    },
    "scope": {
      "type": "string",
      "title": "Scope of Work",
      "description": "Operational boundaries and sanity check (e.g., 'Discussion Only', 'Code Changes Allowed'). Prevents phase leakage.",
      "example": [
        "Brainstorming - NO Code Changes",
        "Implementation - Code & Tests",
        "Analysis - Read Only"
      ],
      "default": "Full Codebase"
    },
    "directoriesOfInterest": {
      "type": "array",
      "title": "Working Directories / Directories of interest",
      "description": "Explicit directories targeted for this task (source code, docs, etc.).",
      "items": { "type": "string" },
      "example": [
        ["src/lib/audio"],
        ["docs/architecture", "src/types"],
        ["frontend/components"],
        ["/"]
      ],
      "default": []
    },
    "preludeFiles": {
      "type": "array",
      "title": "Prelude Files",
      "description": "List of system files (standards/templates) to load immediately.",
      "items": { "type": "string" },
      "example": [
        ["docs/standards/INVARIANTS.md", "docs/TOC.md"],
        ["skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md"]
      ],
      "default": []
    },
    "contextPaths": {
      "type": "array",
      "title": "Project Context Paths",
      "description": "User-specified files/directories to load in Phase 2.",
      "items": { "type": "string" },
      "example": [
        ["src/lib/audio", "src/types/*.ts"],
        ["src/components/Button.tsx"],
        []
      ],
      "default": []
    },
    "ragDiscoveredPaths": {
      "type": "array",
      "title": "RAG-Discovered Paths",
      "description": "Paths discovered via RAG search during setup. These are suggested by semantic search over session logs, docs, and codebase — not explicitly requested by the user. Merged with contextPaths during ingestion, but displayed separately so the user can review/prune.",
      "items": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "File or directory path" },
          "reason": { "type": "string", "description": "Why RAG suggested this (e.g., 'similar past session', 'mentions same component')" },
          "confidence": { "type": "string", "enum": ["high", "medium", "low"], "description": "RAG confidence level" }
        },
        "required": ["path", "reason"]
      },
      "example": [
        [
          { "path": "sessions/2026_01_15_AUTH_REFACTOR/IMPLEMENTATION.md", "reason": "Similar auth implementation session", "confidence": "high" },
          { "path": "packages/api/src/auth/clerk.ts", "reason": "Mentions ClerkAuthGuard referenced in prompt", "confidence": "medium" }
        ]
      ],
      "default": []
    },
    "planTemplate": {
      "type": "string",
      "title": "Plan Template Path",
      "description": "Path to the plan template (if applicable).",
      "example": [
        "skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md",
        "skills/debug/assets/TEMPLATE_DEBUG_PLAN.md",
        "skills/test/assets/TEMPLATE_TESTING_PLAN.md"
      ],
      "default": null
    },
    "logTemplate": {
      "type": "string",
      "title": "Log Template Path",
      "description": "Path to the log template (if applicable).",
      "example": [
        "skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md",
        "skills/debug/assets/TEMPLATE_DEBUG_LOG.md",
        "skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md"
      ],
      "default": null
    },
    "debriefTemplate": {
      "type": "string",
      "title": "Debrief Template Path",
      "description": "Path to the debrief template.",
      "example": [
        "skills/implement/assets/TEMPLATE_IMPLEMENTATION.md",
        "skills/debug/assets/TEMPLATE_DEBUG.md",
        "skills/brainstorm/assets/TEMPLATE_BRAINSTORM.md"
      ],
      "default": null
    },
    "extraInfo": {
      "type": "string",
      "title": "Extra Info",
      "description": "Any additional context or constraints.",
      "example": [
        "User emphasized performance over readability.",
        "Strictly adhere to the new style guide.",
        "Do not touch legacy code."
      ],
      "default": ""
    },
    "phases": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["major", "minor", "name"],
        "properties": {
          "major": {
            "type": "integer",
            "description": "Major phase number (1, 2, 3, ...). Main phases from the skill protocol."
          },
          "minor": {
            "type": "integer",
            "description": "Minor phase number (0 for main phases, 1+ for sub-phases). E.g., major=4 minor=0 is '4: Planning', major=4 minor=1 is '4.1: Agent Handoff'."
          },
          "name": {
            "type": "string",
            "description": "Short phase name (e.g., 'Setup', 'Context Ingestion'). Label is derived: minor=0 → 'N: Name', minor>0 → 'N.M: Name'."
          }
        }
      },
      "title": "Session Phases",
      "description": "Ordered list of phases for this skill session. These MUST correspond to the phases defined in the skill's SKILL.md protocol. Phase enforcement ensures sequential progression — non-sequential transitions (skip forward or go backward) require explicit user approval via --user-approved flag on session.sh phase. Sub-phases (minor > 0) can be auto-appended during the session without pre-declaration. Labels are derived from major/minor/name — not stored.",
      "example": [
        [
          {"major": 1, "minor": 0, "name": "Setup"},
          {"major": 2, "minor": 0, "name": "Context Ingestion"},
          {"major": 3, "minor": 0, "name": "Interrogation"},
          {"major": 4, "minor": 0, "name": "Planning"},
          {"major": 5, "minor": 0, "name": "Build Loop"},
          {"major": 6, "minor": 0, "name": "Synthesis"}
        ]
      ],
      "default": []
    }
  }
}
```

**Algorithm**:
1.  **Analyze**: Review the user's prompt and current context to extract the parameters.
2.  **Construct**: Create the JSON object matching the schema.
3.  **Activate Session**: Pipe the JSON to `session.sh activate` via heredoc. The JSON is stored in `.state.json` (merged with runtime fields) and activate returns context (alerts, delegations, RAG suggestions). Do NOT output the JSON to chat — it is stored by activate.
    ```bash
    ~/.claude/scripts/session.sh activate sessions/[YYYY_MM_DD]_[TOPIC] [SKILL_NAME] <<'EOF'
    { "taskSummary": "...", "taskType": "...", ... }
    EOF
    ```
    *   The agent reads activate's stdout for context sections (## Active Alerts, ## Open Delegations, ## RAG: Sessions, ## RAG: Docs).
    *   activate uses `taskSummary` from the JSON to run thematic searches via session-search and doc-search automatically.
    *   **No-JSON calls** (e.g., re-activation without new params): use `< /dev/null` to avoid stdin hang.
4.  **Process Context Output**: Parse activate's Markdown output to identify the 4 context categories (Alerts, Delegations, RAG:Sessions, RAG:Docs). These are consumed by `§CMD_INGEST_CONTEXT_BEFORE_WORK` to build the multichoice menu in Phase 2.

### §CMD_MAINTAIN_SESSION_DIR
**Definition**: To ensure continuity, the Agent must anchor itself in a single Session Directory for the duration of the task.
**Rule**: Called automatically by `§CMD_PARSE_PARAMETERS` step 4. Do not call separately unless resuming a session without parameter parsing.

**Algorithm**:
1.  **Identify**: Look for an active session directory in the current context:
    *   Check the recent chat history for a "📂 **Session Directory**" entry.
    *   Check the `sessionDir` parameter from `§CMD_PARSE_PARAMETERS`.
    *   Check the most recently modified directory in `sessions/` for the current date.
2.  **Decision**:
    *   **Reuse**: If an existing session directory is found and matches the current topic (even if the `SESSION_TYPE` differs slightly, e.g., switching from IMPLEMENTATION to TESTING), **STAY** in that directory.
    *   **Create**: Only create a new directory if no relevant session exists or if the user explicitly asks for a "New Session".
3.  **Path Strategy**: If creating a new directory, prefer a descriptive topic name: `sessions/[YYYY_MM_DD]_[TOPIC]`.
    *   **Prohibited**: Do NOT include `[SESSION_TYPE]` (e.g., BRAINSTORM, IMPLEMENT) in the folder name.
    *   **Reason**: Sessions are multi-modal. A `BRAINSTORM` session might evolve into `IMPLEMENT`. The folder name must remain stable (Topic-Centric).
    *   **Bad**: `sessions/2026_01_28_BRAINSTORM_LAYOUT_REFACTOR`
    *   **Good**: `sessions/2026_01_28_LAYOUT_REFACTOR`
4.  **Action**: Session activation is handled by `§CMD_PARSE_PARAMETERS` step 3, which pipes the parameters JSON to `session.sh activate` via heredoc. The script will:
    *   Create the directory if it doesn't exist.
    *   Write `.state.json` with PID, skill name, status tracking, AND the piped session parameters (merged).
    *   Auto-detect fleet pane ID if running in fleet tmux (no manual `--fleet-pane` needed).
    *   Enable context overflow protection (PreToolUse hook will block at 90%).
    *   Run context scans (on fresh activation or skill change) — all use `taskSummary` for thematic relevance:
        *   `session-search.sh query --tag '#active-alert'` → `## Active Alerts` section
        *   `session-search.sh query --tag '#needs-delegation'` → `## Open Delegations` section
        *   `session-search.sh query` → `## RAG: Sessions` section
        *   `doc-search.sh query` → `## RAG: Docs` section
    *   If the same Claude (same PID) and same skill: brief re-activation, no scans.
    *   If the same Claude but different skill: updates skill, runs scans.
    *   If a different Claude is already active in this session, it rejects with an error.
    *   If a stale `.state.json` exists (dead PID), it cleans up and proceeds.
    *   **Note**: For simple operations without skill tracking, use `session.sh init` instead (legacy).
    *   **Note**: For re-activation without new parameters: `session.sh activate path skill < /dev/null`.
5.  **Detect Existing Skill Artifacts** (CRITICAL):
    *   After identifying/creating the session directory, check if artifacts from the **current skill type** already exist:
        *   For `/implement`: `IMPLEMENTATION_LOG.md`, `IMPLEMENTATION.md`
        *   For `/test`: `TESTING_LOG.md`, `TESTING.md`
        *   For `/debug`: `DEBUG_LOG.md`, `DEBUG.md`
        *   For `/analyze`: `ANALYSIS_LOG.md`, `ANALYSIS.md`
        *   For `/brainstorm`: `BRAINSTORM_LOG.md`, `BRAINSTORM.md`
        *   (etc. — match the skill's log and debrief filenames)
    *   **If artifacts exist**, ask before proceeding:
        > "This session already has [skill] artifacts (`[LOG_FILE]`, `[DEBRIEF_FILE]`). Continue the existing [skill] phase, or start a new session?"
        > - **"Continue existing"** — Resume: use the existing log (append), and regenerate the debrief at the end.
        > - **"New session"** — Create a new session directory with a distinguishing suffix (e.g., `_v2`, `_round2`).
    *   **If no artifacts exist** for this skill type, proceed normally (even if other skill artifacts exist — sessions are multi-modal).
6.  **Echo (CRITICAL)**: Output "📂 **Session Directory**: [Path]" to the chat, where [Path] is a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant). If reusing, say "📂 **Reusing Session Directory**: [Path]". If continuing existing skill artifacts, say "📂 **Continuing existing [skill] in**: [Path]".

### §CMD_UPDATE_PHASE
**Definition**: Update the current skill phase in `.state.json` for status line display, context overflow recovery, and **phase enforcement**.
**Rule**: Call this when transitioning between phases of a skill protocol. Phase enforcement ensures sequential progression.

**Algorithm**:
1.  **Execute** (sequential transition — next phase in order):
    ```bash
    ~/.claude/scripts/session.sh phase sessions/[CURRENT_SESSION] "N: [Name]"
    ```
    *   Example: `session.sh phase sessions/2026_02_05_MY_TOPIC "3: Interrogation"`
    *   Phase labels MUST start with a number: `"N: Name"` or `"N.M: Name"` (e.g., `"4: Planning"`, `"4.1: Agent Handoff"`).
2.  **Execute** (non-sequential transition — skip forward or go backward):
    ```bash
    ~/.claude/scripts/session.sh phase sessions/[CURRENT_SESSION] "N: [Name]" --user-approved "Reason: [why you need this phase change, citing user's response]"
    ```
    *   **Required**: The `--user-approved` reason MUST quote the user's actual response from `AskUserQuestion`.
    *   Without `--user-approved`, non-sequential transitions are **rejected** (exit 1).
3.  **Effect**:
    *   Updates `currentPhase` in `.state.json`
    *   Appends to `phaseHistory` array (audit trail of all transitions)
    *   Clears `loading` flag and resets heartbeat counters
    *   Status line displays as `[skill:P3]`
    *   If context overflow triggers restart, new Claude resumes from this phase
4.  **Sub-phase auto-append**: If you call a phase like `"4.1: Agent Handoff"` and no such phase is declared, it is automatically inserted into the `phases` array — as long as its major number matches the current phase's major number and its minor number is higher. No explicit append command needed.

**Phase Enforcement** (when `.state.json` has a `phases` array):
*   **Sequential forward**: Transition to the next declared phase is always allowed.
*   **Skip forward**: Requires `--user-approved`. Error message shows expected next phase.
*   **Go backward**: Requires `--user-approved`. Error message shows expected next phase.
*   **Sub-phase**: Same major, higher minor → auto-appended and allowed.
*   **No `phases` array**: Enforcement is disabled (backward compat). Any transition allowed.

**When to Call**:
*   At the START of each major phase (after completing the previous one)
*   Phase labels must match the `phases` array declared at session activation

### §CMD_REANCHOR_AFTER_RESTART
**Definition**: Re-initialize skill context after a context overflow restart.
**Implementation**: Handled by the `/reanchor` skill.
**Trigger**: Automatically invoked by `session.sh restart` — you don't call this manually.

**What it does**:
1. Activates the session
2. Loads standards (COMMANDS.md, INVARIANTS.md)
3. Reads dehydrated context
4. Loads required files and skill templates
5. Loads original skill protocol
6. Skips to saved phase and resumes work

**See**: `~/.claude/skills/reanchor/SKILL.md` for full protocol.

### §CMD_LOAD_AUTHORITY_FILES
**Definition**: Load system-critical files (Templates, Standards) into context.
**Rule**: Use this ONLY for files required by the Protocol (Phase 1).
**Constraint**: **Check First**. Do NOT re-read if already present.
**Algorithm**:
1.  **Identify**: The list of "Required Context" files from the Prompt.
2.  **Scan**: Review your context window (chat history) for these files.
3.  **Execute**:
    *   For each file:
        *   If present (content visible): **SKIP** and log "Skipped [File] (Already Loaded)".
        *   If missing: Call `read_file`.

### §CMD_USE_ONLY_GIVEN_CONTEXT
**Definition**: Work strictly within the current Context Window boundaries. Do NOT explore the filesystem.
**Scope**: This is a **phase-specific** constraint, typically applied during Setup (Phase 1) to prevent premature exploration. It does NOT apply to later phases like Context Ingestion (Phase 2), which explicitly require running searches.
**Rules**:
1.  **Forbidden** (during this constraint): `read_file`, `grep`, `ls`, `codebase_search`.
2.  **Allowed**: Only information currently in your context (User Prompt, System Prompt, Loaded Authority).
3.  **Exception**: If a file is CRITICAL and missing, you must **ASK** the user to load it. Do not load it yourself.
4.  **Expiration**: This constraint expires when the protocol moves to a phase that requires exploration (e.g., Context Ingestion). Do not carry this constraint forward into later phases.

### §CMD_AVOID_WASTING_TOKENS
**Definition**: Do not burn tokens on redundant operations.
**Rules**:
1.  **Rehydration Check**: If you have loaded `DEHYDRATED_CONTEXT.md` or `DEHYDRATED_DOCS.md` during session rehydration, you MUST NOT read the individual files contained within them (e.g., `_LOG.md`, specs) unless you have a specific reason to believe they have changed externally.
2.  **Memory over IO**: Rely on your context window. Do not `read_file` something just to check a detail if you recently read it in a dehydrated block.
3.  **Batch Operations**: Prefer single, larger tool calls over many small ones.
4.  **Blind Trust**: When you know a file exists and you have its content in a summary/dehydrated file, trust it.


### §CMD_USE_TODOS_TO_TRACK_PROGRESS
**Definition**: Use an internal `TODO` list to manage work items and track progress throughout the session.

**Rules**:
1.  **Create TODOs**: When interpreting a new command, request, or requirement, create a new TODO item describing it.
2.  **Track Status**: Each TODO should be marked as `Open`, `In Progress`, or `Done`.
3.  **Update Transparently**: Update TODO statuses as progress is made, and make these updates visible in logs or status reports.
4.  **Do Not Omit**: Do not skip or silently remove TODOs; all planned actions must have a TODO entry.
5.  **Review Frequently**: Regularly review the TODO list, especially before major execution steps, to ensure all items are addressed.

---

## 3. Interaction Protocols (The "Conversation")

### §CMD_ASK_USER_IF_STUCK
**Definition**: Proactive halting when progress is stalled or ambiguity is high.
**Rule**: Do not spin in loops. If 2+ attempts fail or you are unsure of the path, stop.
**Algorithm**:
1.  **Detect**: Are you repeating errors? Is the path unclear?
2.  **Stop**: Do not execute further tools.
3.  **Ask**: "I am stuck on [Problem]. Options are A/B. Guidance?"

### §CMD_ASK_ROUND_OF_QUESTIONS
**Definition**: The standard protocol for information gathering (Brainstorming, Debugging, Deep Dives).
**Algorithm**:
1.  **Formulate**: Generate 3-5 targeted questions based on the Session Goal.
2.  **Execute**: Call the `AskUserQuestion` tool.
    *   **Constraint**: Provide distinct options for each question (e.g., Yes/No, Multiple Choice).
    *   **Goal**: Gather structured data to inform the next steps.
3.  **Wait**: The tool will pause execution until the user responds.
4.  **Resume**: Once the tool returns, proceed immediately to logging.

---

## 4. Composite Workflow Commands (The "Shortcuts")

### §CMD_INGEST_CONTEXT_BEFORE_WORK
**Definition**: Present discovered context as a multichoice menu before work begins.
**Rule**: STOP after init. Enter this phase. Do NOT load files until user responds.

**Categories**: Activate outputs 4 sections: `## RAG: Sessions`, `## RAG: Docs`, `## Active Alerts`, `## Open Delegations`. Each contains file paths (one per line) or `(none)`.

**Algorithm**:
1.  Auto-load `contextPaths` from session parameters (explicitly requested — no menu needed).
2.  Parse activate's 4 sections. Drop empty categories and already-loaded paths.
3.  Build a single `AskUserQuestion` (multiSelect: true, max 4 options):
    *   **≤4 items** in a category → each item is a separate option (label=path, description=category).
    *   **>4 items** → single bulk option: `"[Category] ([N] found)"`.
    *   If total options > 4, promote largest categories to bulk until ≤ 4.
    *   **All empty** → skip menu, prompt for free-text paths via "Other".
4.  Load selected items + any "Other" free-text paths.

### §CMD_GENERATE_DEBRIEF_USING_TEMPLATE
**Definition**: Creates or regenerates a standardized debrief artifact.
**Algorithm**:
1.  **Check for Continuation**: Is this a continuation of an existing session (user chose "Continue existing" via `§CMD_MAINTAIN_SESSION_DIR`, or continued post-synthesis via `§CMD_CONTINUE_OR_CLOSE_SESSION`)?
    *   **If continuation**: Read the **full log file** (original + continuation entries) to capture the complete session history. The debrief must reflect ALL work done, not just the latest round.
    *   **If fresh**: Proceed normally with current context.
2.  **Execute**: `§CMD_POPULATE_LOADED_TEMPLATE` using the `.md` schema found in context.
    *   **Continuation Note**: The debrief **replaces** any existing debrief file. Do NOT append — regenerate the entire document so it reads as one coherent summary of all work.
3.  **Tag**: Include a `**Tags**: #needs-review` line immediately after the H1 heading. This marks the debrief as unvalidated and discoverable by `/review`.
4.  **Doc Update Tag**: If the session involved code changes (task types: `IMPLEMENTATION`, `DEBUG`, `ADHOC`, `TESTING`), also add `#needs-documentation` to the Tags line. This marks the session as needing a documentation pass and is discoverable by scanning for the tag.
    *   *Example (code-changing session)*:
        ```markdown
        # Implementation Debriefing: My Feature
        **Tags**: #needs-review #needs-documentation
        ```
    *   *Example (read-only session)*:
        ```markdown
        # Analysis: My Research Topic
        **Tags**: #needs-review
        ```
    *   **Skip**: If the agent is confident there is zero documentation impact (e.g., a trivial config change with no user-facing effect), it may omit `#needs-documentation` but must log the reasoning.
5.  **Related Sessions**: If `ragDiscoveredPaths` was populated during context ingestion (session-search found relevant past sessions), include a `## Related Sessions` section in the debrief:
    ```markdown
    ## Related Sessions
    *   `sessions/2026_01_15_AUTH_REFACTOR/IMPLEMENTATION.md` — Similar auth implementation
    *   `sessions/2026_01_10_CLERK_SETUP/ANALYSIS.md` — Initial Clerk research
    ```
    *   Only include sessions (not code files). Link to the debrief or most relevant artifact.
    *   This creates a knowledge graph — future sessions can trace lineage.
6.  **Report**: `§CMD_REPORT_FILE_CREATION_SILENTLY`. If this was a regeneration, say "Updated `[path]`" not "Created".
7.  **Reindex Search DBs**: *Handled automatically by `session.sh deactivate` (step 12).* No manual action needed — deactivate spawns background `session-search.sh index` and `doc-search.sh index` processes.
8.  **Invariant Capture**: Execute `§CMD_PROMPT_INVARIANT_CAPTURE`.
    *   Reviews the conversation for insights worth preserving as permanent invariants.
    *   Prompts user to add each candidate to shared or project INVARIANTS.md.
    *   Skips silently if no candidates found.
9.  **TOC Management**: Execute `§CMD_MANAGE_TOC`.
    *   Proposes additions, description updates, and stale entry removals for `docs/TOC.md` based on documentation files touched this session.
    *   Skips silently if no documentation files were touched.
10.  **Capture Side Discoveries**: Execute `§CMD_CAPTURE_SIDE_DISCOVERIES`.
    *   Scans the session log for side-discovery entries (observations, concerns, parking lot items).
    *   Presents multichoice to tag them for future dispatch (`#needs-implementation`, `#needs-research`, `#needs-decision`).
    *   Skips silently if no side-discovery entries found.
11.  **Report Leftover Work**: Execute `§CMD_REPORT_LEFTOVER_WORK`.
    *   Extracts unfinished items from session artifacts (tech debt, unresolved blocks, incomplete plan steps, doc impact).
    *   Outputs a concise report in chat + appends to session log.
    *   Gives the user context for their next-skill choice.
    *   Skips silently if no leftover items found.
12.  **Deactivate & Prompt Next Skill**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`.
    *   Deactivates the session with description and keywords, then presents the skill progression menu.

### §CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL
**Definition**: After synthesis is complete, deactivates the session (re-engaging the gate) and presents skill-specific next-step options to guide the user.
**Trigger**: Called as the final step of `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (step 12).

**Algorithm**:
1.  **Compose Description**: Write a 1-3 line summary of what was accomplished in this session. Focus on *what changed* and *why*, not process details.
2.  **Infer Keywords**: Based on the session's work, infer 3-5 search keywords that capture the key topics, files, and concepts. These power future RAG discoverability.
    *   *Example*: For a session that refactored auth middleware: `"auth, middleware, ClerkAuthGuard, session-management, NestJS"`
    *   Keywords should be comma-separated, concise, and specific to this session's work.
3.  **Deactivate**: Execute:
    ```bash
    ~/.claude/scripts/session.sh deactivate [sessionDir] --keywords "kw1,kw2,kw3" <<'EOF'
    [1-3 line description]
    EOF
    ```
    This sets `lifecycle=completed`, stores description + keywords in `.state.json`, and runs a RAG search returning related sessions in stdout.
4.  **Process RAG Results**: If deactivate returned a `## Related Sessions` section in stdout, display it in chat. This gives the user awareness of related past work.
5.  **Present Menu**: Execute `AskUserQuestion` with the options defined in the **current skill's SKILL.md** under `### Next Skill Options`. Each skill defines up to **4 options** (the AskUserQuestion limit). The implicit 5th option ("Other") lets the user type a skill name or describe new work. The question text MUST explain this: include "(Type a /skill name to invoke it, or describe new work to scope it)" in the question.
6.  **On Selection**:
    *   **If a skill is chosen**: Invoke the Skill tool: `Skill(skill: "[chosen-skill]")`
    *   **If "Other" — skill name** (user typed `/implement`, `/test`, etc.): Invoke the Skill tool with the typed skill name.
    *   **If "Other" — new work details** (user typed notes, questions, or requirements): This is new input that needs scoping. Offer to route to interrogation: execute `AskUserQuestion` with "Start interrogation to scope this?" / "Just do it inline" options. If interrogation is chosen, reactivate the session and enter Phase 3.

**Constraints**:
*   **Session description is REQUIRED**: `session.sh deactivate` will ERROR if no description is piped. This powers RAG search for future sessions.
*   **Keywords are RECOMMENDED**: If omitted, deactivate still works but the session is less discoverable by future RAG queries.
*   **Max 4 options**: Each skill defines exactly 4 skill options in its `### Next Skill Options` section. The first should be marked "(Recommended)". The user can always type something else via "Other".
*   **Options come from SKILL.md**: Each skill defines its own options. The command just presents them — it doesn't decide.
*   **Same session directory**: The next skill reuses the same session directory (sessions are multi-modal per `§CMD_MAINTAIN_SESSION_DIR`).

### §CMD_GENERATE_PLAN_FROM_TEMPLATE
**Definition**: Creates a standardized plan artifact.
**Algorithm**:
1.  **Execute**: `§CMD_POPULATE_LOADED_TEMPLATE` using the `_PLAN.md` schema found in context.
2.  **Report**: `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_REPORT_INTENT_TO_USER
**Definition**: Explicitly state your current phase and intent to the user before transitioning.
**Rule**: Execute this before starting a new major block of work or changing phases (e.g., Setup -> Plan, Plan -> Execution).
**Constraint**: **Once Per Phase**. Do NOT repeat this intent block for every step within the phase (e.g., do not repeat it for every file edit or test run). Only report when *changing* phases or if the user interrupts and you resume.

**Algorithm**:
1.  **Reflect**: Identify the current phase and the specific task at hand.
2.  **Check**: Have I already reported this phase intent recently without interruption?
    *   *Yes*: Skip reporting.
    *   *No*: Proceed to report.
3.  **Update Phase Tracking**: Execute `§CMD_UPDATE_PHASE` to update `.state.json`:
    ```bash
    ~/.claude/scripts/session.sh phase sessions/[CURRENT_SESSION] "Phase X: [Name]"
    ```
    *   This updates the status line display and enables restart recovery.
4.  **Output**: Display a blockquote summary of your intent. When referencing files, use clickable links per `¶INV_TERMINAL_FILE_LINKS` (Compact `§` for inline, Location for code points).
    *   *Example*:
        > 1. I am moving to Phase 3: Test Implementation and will `§CMD_USE_TODOS_TO_TRACK_PROGRESS`.
        > 2. I'll `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to `§CMD_THINK_IN_LOG`.
        > 3. I will not write the debrief until the step is done (`§CMD_REFUSE_OFF_COURSE` applies).
        > 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### §CMD_LOG_TO_DETAILS
**Definition**: Records a Q&A interaction or User Assertion into the session's high-fidelity `DETAILS.md`.
**Usage**: Execute this immediately after receiving a User response to an Interrogation or an important Assertion.

**Algorithm**:
1.  **Construct**: Prepare the Markdown block following `~/.claude/standards/TEMPLATE_DETAILS.md`.
    *   **Agent**: Quote your question (keep nuance/options).
    *   **User**: VERBATIM quote of the user's answer.
    *   **Action**: Paraphrase your decision/action (e.g., "Updated Plan").
2.  **Execute**:
    ```bash
    ~/.claude/scripts/log.sh sessions/[YYYY_MM_DD]_[TOPIC]/DETAILS.md <<'EOF'
    ## [Topic Summary]
    **Type**: [Q&A / Assertion / Discussion]

    **Agent**:
    > [My Prompt/Question]

    **User**:
    > [User Response Verbatim]

    **Agent Action/Decision**:
    > [My Reaction]

    **Context/Nuance** (Optional):
    > [Thoughts]

    ---
    EOF
    ```

### §CMD_EXECUTE_INTERROGATION_PROTOCOL
**Definition**: The standard "Ask -> Log" loop using structured input.
**Algorithm**:
1.  **Execute**: Use `§CMD_ASK_ROUND_OF_QUESTIONS` via the `AskUserQuestion` tool.
2.  **Analyze User Response**:
    *   **Case A**: User asked a question / wants discussion.
        *   **Action**: PAUSE interrogation. Answer the user's question in Chat.
        *   **Verify**: Ask "Does this clarify? Ready to resume?"
        *   **Resume**: Once confirmed, return to Step 1.
    *   **Case B**: User provided answers.
        *   **Log**: Execute `§CMD_LOG_TO_DETAILS` to capture the Q&A.
        *   **Iterate**: Continue to the next round.
3.  **Iteration Constraint**: You MUST complete **AT LEAST 3 ROUNDS** of questioning.
4.  **Completion**:
    *   **Action**: Ask "Interrogation Phase Complete. Do you have any final questions or adjustments before I create the Plan?" via `AskUserQuestion`.
    *   **Wait**: Only proceed to the next phase when the user explicitly selects "Proceed".

### §CMD_HAND_OFF_TO_AGENT
**Description**: Standardized handoff from a parent command to an autonomous agent (opt-in, foreground).
**Trigger**: After plan approval, skill protocols offer agent handoff as an alternative to inline execution.
**Reference**: `~/.claude/standards/commands/CMD_HAND_OFF_TO_AGENT.md`

### §CMD_PARALLEL_HANDOFF
**Description**: Parallel agent handoff — analyzes plan dependencies, derives independent chunks, presents non-intersection proof, and launches multiple agents in parallel.
**Trigger**: After plan approval in plan-based skills (implement, debug, test, document, refine-docs). Extends `§CMD_HAND_OFF_TO_AGENT` with multi-agent coordination.
**Reference**: `~/.claude/standards/commands/CMD_PARALLEL_HANDOFF.md`

### §CMD_REPORT_RESULTING_ARTIFACTS
**Definition**: Final summary step to list all files created or modified.
**Rule**: Must be executed at the very end of a session/task.
**Algorithm**:
1.  **Identify**: List all files created or modified during this session (Logs, Plans, Debriefs, Code).
2.  **Format**: Create a Markdown list where each path is a clickable link per `¶INV_TERMINAL_FILE_LINKS`. Use **Full** display variant (relative path as display text).
3.  **Output**: Print this list to the chat under the header "## Generated Artifacts".

### §CMD_REPORT_SESSION_SUMMARY
**Definition**: Produces a dense 2-paragraph narrative summary of the session's work.
**Rule**: Must be executed immediately after `§CMD_REPORT_RESULTING_ARTIFACTS`.
**Algorithm**:
1.  **Reflect**: Review all work performed during this session — decisions made, problems solved, artifacts created, and key outcomes.
2.  **Compose**: Write exactly 2 dense paragraphs:
    *   **Paragraph 1 (What & Why)**: What was the goal, what approach was taken, and what was accomplished. Include specific technical details — files changed, patterns applied, problems solved. When referencing files inline, use **Compact** (`§`) or **Location** (`file:line`) links per `¶INV_TERMINAL_FILE_LINKS`.
    *   **Paragraph 2 (Outcomes & Next)**: What the current state is, what works, what doesn't yet, and what the logical next steps are. Flag any risks, open questions, or tech debt introduced.
3.  **Output**: Print under the header "## Session Summary".

### §CMD_CONTINUE_OR_CLOSE_SESSION
**Definition**: When the user sends a message after a skill has completed its synthesis phase, re-anchor to the session and continue logging. No question — assume continuation by default.
**Why**: Without this, post-skill conversation loses session context — no logging, no debrief updates, no artifact trail. Work happens but leaves no record.
**Trigger**: The user sends a message AND all of these are true:
*   A debrief file exists in the session directory (e.g., `IMPLEMENTATION.md`, `ANALYSIS.md`, `BRAINSTORM.md`). The debrief's existence is the marker that synthesis completed.
*   The conversation is still active (same Claude Code session).
*   The user's message implies further work (not just "thanks" or "bye").

**Algorithm**:
1.  **Detect**: You just finished a skill's synthesis phase and the user is now asking for more work or discussing the topic further.
2.  **Reactivate Session (CRITICAL)**:
    *   Execute `~/.claude/scripts/session.sh activate [sessionDir] [skill]` to re-register this Claude process with the session.
    *   *Why*: After context overflow restart or new conversation, the status line reads from `.state.json`. Without reactivation, it shows stale session info.
3.  **Same Topic — Assume Continuation**:
    *   **Announce** (not a question): "📂 Continuing in `[sessionDir]` — logging resumed."
    *   **Log Continuation Header**: Append to the existing `_LOG.md`:
        ```bash
        ~/.claude/scripts/log.sh [sessionDir]/[LOG_NAME].md <<'EOF'
        ## ♻️ Session Continuation
        *   **Trigger**: User requested further work after synthesis.
        *   **Goal**: [brief description of what user asked for]
        EOF
        ```
    *   **Work**: Execute the user's request. Continue logging as normal (same `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` cadence as the original skill).
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
    *   **Regenerate**: Re-run `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` using the **full session context** (original work + continuation). This **replaces** the existing debrief file.
    *   **Why Regenerate**: A debrief is a summary of the entire session. Appending creates a patchwork; regenerating keeps it coherent and properly structured.
7.  **Trivial Messages**: If the user's message is clearly conversational (e.g., "thanks", "got it", "bye"), respond naturally without triggering this protocol — but still offer to update the debrief if continuation work was done:
    > "Got it. Want me to update the debrief before we wrap up?"

### §CMD_PROMPT_INVARIANT_CAPTURE
**Description**: Reviews the session for insights worth capturing as permanent invariants and prompts the user to add them.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 8, after debrief is written. Read the reference file before executing.
**Reference**: `~/.claude/standards/commands/CMD_PROMPT_INVARIANT_CAPTURE.md`

### §CMD_MANAGE_TOC
**Description**: Manages `docs/TOC.md` by proposing additions, description updates, and stale entry removals based on the session's documentation file changes.
**Trigger**: Called during synthesis/post-op phases of any skill that creates, modifies, or deletes documentation files. Read the reference file before executing.
**Reference**: `~/.claude/standards/commands/CMD_MANAGE_TOC.md`

### §CMD_CAPTURE_SIDE_DISCOVERIES
**Description**: Scans the session log for side-discovery entries (observations, concerns, parking lot items) and presents a multichoice menu to tag them for future dispatch.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 10, after TOC management. Read the reference file before executing.
**Reference**: `~/.claude/standards/commands/CMD_CAPTURE_SIDE_DISCOVERIES.md`

### §CMD_REPORT_LEFTOVER_WORK
**Description**: Extracts unfinished items from session artifacts (tech debt, unresolved blocks, incomplete plan steps) and presents a concise report in chat before the next-skill menu.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 11, after side discoveries. Read the reference file before executing.
**Reference**: `~/.claude/standards/commands/CMD_REPORT_LEFTOVER_WORK.md`

### §CMD_WALK_THROUGH_RESULTS
**Description**: Walks the user through skill outputs or plan items with configurable granularity (None / Groups / Each item). Two modes: **results** (post-execution triage — delegate/defer/dismiss) and **plan** (pre-execution review — comment/question/flag). Each skill provides a configuration block defining mode, gate question, item sources, and action menu or plan questions.
**Trigger**: Called by skill protocols either during synthesis (results mode) or after plan creation (plan mode). Read the reference file before executing.
**Reference**: `~/.claude/standards/commands/CMD_WALK_THROUGH_RESULTS.md`

