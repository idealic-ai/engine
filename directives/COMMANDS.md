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
    engine log sessions/[YYYY_MM_DD]_[TOPIC]/[LOG_NAME].md <<'EOF'
    ## [Header/Type]
    *   **Item**: ...
    *   **Details**: ...
    EOF
    ```
    *   The script auto-prepends a blank line, creates parent dirs, auto-injects timestamp into first `## ` heading, and appends content.
    *   In append mode, content MUST contain a `## ` heading or log.sh will error (exit 1).
    *   Whitelisted globally via `Bash(engine *)` — no permission prompts.

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
**Reference**: `~/.claude/directives/commands/CMD_AWAIT_TAG.md`

---

## 2. Process Control Commands (The "Guards")

### §CMD_LOG_BETWEEN_TOOL_USES
**Definition**: Log progress at a regular cadence between tool calls. Mechanically enforced by `pre-tool-use-heartbeat.sh`.
**Rule**: After N tool calls without a `log.sh` append, the heartbeat hook warns (at `toolUseWithoutLogsWarnAfter`, default 3) and blocks (at `toolUseWithoutLogsBlockAfter`, default 10). Thresholds are configurable in `.state.json`.
**When Blocked**: Read the log template for the active skill, then append a progress entry via `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`.
**Related**: `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (the logging mechanism), `§CMD_THINK_IN_LOG` (the logging rationale).

### §CMD_REQUIRE_ACTIVE_SESSION
**Definition**: All tool use requires an active session. Mechanically enforced by `pre-tool-use-session-gate.sh`.
**Rule**: The session gate blocks all non-whitelisted tools until `session.sh activate` succeeds. Whitelisted: `Read(~/.claude/*)`, `Bash(session.sh/log.sh/tag.sh)`, `AskUserQuestion`, `Skill`.
**When Blocked**: Use `AskUserQuestion` to ask the user which skill/session to activate, then invoke the skill via the Skill tool.
**Related**: `¶INV_SKILL_PROTOCOL_MANDATORY` (skills require formal session activation), `§CMD_MAINTAIN_SESSION_DIR` (session directory lifecycle).

### §CMD_DEBRIEF_BEFORE_CLOSE
**Definition**: A session cannot be deactivated without its debrief file. Mechanically enforced by `session.sh deactivate`.
**Rule**: Before deactivation, `session.sh` checks if the skill's debrief file exists (e.g., `IMPLEMENTATION.md` for `/implement`, `ANALYSIS.md` for `/analyze`). If missing, deactivation is blocked.
**When Blocked**: Write the debrief via `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`, then retry deactivation.
**Skip**: If the user explicitly approves skipping, use `--user-approved "Reason: [quote user's words]"` on the deactivate command. The agent MUST use `AskUserQuestion` to get user approval before skipping. The reason MUST quote the user's actual words — agent-authored justifications are not valid.
**Prohibited justifications** (these are never valid reasons to skip the debrief):
*   "Small focused change — no debrief needed."
*   "This task was too simple for a debrief."
*   "The changes are self-explanatory."
*   Any reason authored by the agent without user input.
**Valid reasons** (these require the user to have actually said it):
*   `"Reason: User said 'skip the debrief, just close it'"`
*   `"Reason: User said 'discard this session'"`
*   `"Reason: User abandoned session early — said 'never mind, move on'"`
**Related**: `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (creates the debrief), `¶INV_CHECKLIST_BEFORE_CLOSE` (similar gate pattern for checklists).

### §CMD_VERIFY_PHASE_EXIT
**Definition**: Self-report proof block that gates phase progression. The agent fills in every blank; if any blank is empty, the agent cannot proceed. Covers both the boot gate (standards loaded) and per-phase exit proofs (phase work verified).
**Rule**: Every skill phase ends with a `§CMD_VERIFY_PHASE_EXIT` block. The agent outputs it in chat with every blank filled. If any blank is empty, the agent goes back and completes the missing work before proceeding.
**Variants**:
*   **Boot gate** (Phase 0 entry): Verifies standards files are loaded (`COMMANDS.md`, `INVARIANTS.md`, `TAGS.md`). Uses the `⛔ GATE CHECK` heading. Placed before Phase 0 in the skill protocol.
*   **Phase exit** (Phase N completion): Verifies the phase's deliverables exist and are valid. Uses the `§CMD_VERIFY_PHASE_EXIT — Phase N` heading. Placed at the end of each phase.
**Algorithm**:
1.  **Output**: Print the proof block template (defined inline in each skill's SKILL.md) to chat.
2.  **Fill**: Replace every `________` placeholder with the actual value from the current session state.
3.  **Verify**: If any blank is still empty, GO BACK and complete the missing work. Do NOT proceed to the next phase.
4.  **Proceed**: Once all blanks are filled, the phase exit is verified. The agent may now execute the phase transition (via `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH` or the phase's specific transition pattern).
**Constraint**: The proof block is output to chat (not logged) — it's a user-visible verification step.
**Related**: `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH` (called after this command at phase boundaries), `¶INV_PHASE_ENFORCEMENT` (mechanical enforcement of phase ordering).

### §CMD_NO_MICRO_NARRATION
**Definition**: Do not narrate micro-steps or internal thoughts in the chat.
**Rule**: The Chat is for **User Communication Only** (Questions, Plans, Reports). It is NOT for debug logs or stream of consciousness.
**Constraint**: NEVER output text like "Wait, I need to check...", "Okay, reading file...", or "Executing...". Just call the tool.
**Bad**: "I will read the file now. [Tool Call]. Okay, I read it."
**Good**: [Tool Call]

### §CMD_ESCAPE_TAG_REFERENCES
**Definition**: Backtick-escape tag references in body text/chat. Bare `#tag` = actual tag; backticked `` `#tag` `` = reference only.
**Reference**: See `~/.claude/directives/TAGS.md` § Escaping Convention for the full behavioral rule, reading/writing conventions, and examples.

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

### §CMD_SESSION_CLI
**CRITICAL**: These are the exact command formats. Do NOT invent flags (e.g., `--description`). Description and parameters are always piped via stdin heredoc.

```bash
# Activate (with parameters — first activation)
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
```

---

### §CMD_PARSE_PARAMETERS
**Definition**: Parse and validate the session parameters before execution.
**Rule**: Execute this immediately after `§CMD_MAINTAIN_SESSION_DIR` (or as part of setup). This command outputs the "Flight Plan" for the session.

**Schema**:
```json
{
  "type": "object",
  "title": "Session Parameters",
  "required": ["sessionDir", "taskType", "taskSummary", "startedAt", "scope", "directoriesOfInterest", "preludeFiles", "contextPaths", "planTemplate", "logTemplate", "debriefTemplate", "requestTemplate", "responseTemplate", "requestFiles", "nextSkills", "extraInfo", "phases"],
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
      "description": "List of system files (directives/templates) to load immediately.",
      "items": { "type": "string" },
      "example": [
        ["docs/directives/INVARIANTS.md", "docs/TOC.md"],
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
    "directives": {
      "type": "array",
      "items": { "type": "string" },
      "title": "Skill Directives",
      "description": "Directive file types this skill cares about beyond the core set (README.md, INVARIANTS.md, CHECKLIST.md are always discovered). Derived from the skill's Required Context section: if SKILL.md loads `.claude/directives/X.md`, include `X.md` here. Convention: editing skills (implement, test, debug, refine, document) load PITFALLS.md; testing skills (implement, test, debug) load TESTING.md. See ¶INV_DIRECTORY_AWARENESS.",
      "example": [
        ["TESTING.md", "PITFALLS.md"],
        ["PITFALLS.md"],
        []
      ],
      "default": []
    },
    "planTemplate": {
      "type": "string",
      "title": "Plan Template Path",
      "description": "Path to the plan template (if applicable).",
      "example": [
        "skills/implement/assets/TEMPLATE_IMPLEMENTATION_PLAN.md",
        "skills/fix/assets/TEMPLATE_FIX_PLAN.md",
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
        "skills/fix/assets/TEMPLATE_FIX_LOG.md",
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
        "skills/fix/assets/TEMPLATE_FIX.md",
        "skills/brainstorm/assets/TEMPLATE_BRAINSTORM.md"
      ],
      "default": null
    },
    "requestTemplate": {
      "type": "string",
      "title": "Request Template Path",
      "description": "Path to the REQUEST template (if this skill supports delegation).",
      "example": [
        "skills/implement/assets/TEMPLATE_IMPLEMENTATION_REQUEST.md",
        "skills/brainstorm/assets/TEMPLATE_BRAINSTORM_REQUEST.md"
      ],
      "default": null
    },
    "responseTemplate": {
      "type": "string",
      "title": "Response Template Path",
      "description": "Path to the RESPONSE template (if this skill supports delegation).",
      "example": [
        "skills/implement/assets/TEMPLATE_IMPLEMENTATION_RESPONSE.md",
        "skills/brainstorm/assets/TEMPLATE_BRAINSTORM_RESPONSE.md"
      ],
      "default": null
    },
    "requestFiles": {
      "type": "array",
      "items": { "type": "string" },
      "title": "Request Files",
      "description": "Request files this session is fulfilling. Supports two types: formal REQUEST files (filename contains 'REQUEST') and inline-tag source files (any other file with #needs-* tags). Validated by session.sh check Validation 3 (¶INV_REQUEST_BEFORE_CLOSE).",
      "example": [
        ["sessions/2026_02_09_TOPIC/IMPLEMENTATION_REQUEST_FEATURE.md"],
        ["sessions/2026_02_09_TOPIC/BRAINSTORM.md"]
      ],
      "default": []
    },
    "nextSkills": {
      "type": "array",
      "items": { "type": "string" },
      "title": "Next Skill Options",
      "description": "Skills to suggest after session completion. Used by §CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL for the post-session menu. Each skill declares its own nextSkills in SKILL.md. Required field.",
      "example": [["/test", "/document", "/analyze", "/fix"]],
      "default": []
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
3.  **Activate Session**: Pipe the JSON to `session.sh activate` via heredoc (see `§CMD_SESSION_CLI` for exact syntax). The JSON is stored in `.state.json` (merged with runtime fields) and activate returns context (alerts, delegations, RAG suggestions). Do NOT output the JSON to chat — it is stored by activate.
    *   The agent reads activate's stdout for context sections (## §CMD_SURFACE_ACTIVE_ALERTS, ## §CMD_RECALL_PRIOR_SESSIONS, ## §CMD_RECALL_RELEVANT_DOCS, ## §CMD_DISCOVER_DELEGATION_TARGETS).
    *   activate uses `taskSummary` from the JSON to run thematic searches via session-search and doc-search automatically.
    *   **No-JSON calls** (e.g., re-activation without new params): use `< /dev/null` to avoid stdin hang.
4.  **Process Context Output**: Parse activate's Markdown output to identify the 3 context categories (Alerts, RAG:Sessions, RAG:Docs). These are consumed by `§CMD_INGEST_CONTEXT_BEFORE_WORK` to build the multichoice menu in Phase 2.

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
        *   `session-search.sh query --tag '#active-alert'` → `## §CMD_SURFACE_ACTIVE_ALERTS` section
        *   `session-search.sh query --tag '#needs-delegation'` → `## §CMD_SURFACE_OPEN_DELEGATIONS` section
        *   `session-search.sh query` → `## §CMD_RECALL_PRIOR_SESSIONS` section
        *   `doc-search.sh query` → `## §CMD_RECALL_RELEVANT_DOCS` section
        *   `§CMD_DISCOVER_DELEGATION_TARGETS` runs unconditionally (outside SHOULD_SCAN guard)
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
        *   For `/fix`: `FIX_LOG.md`, `FIX.md`
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
1.  **Execute** (sequential transition — next phase in order): Use the `engine session phase` command (see `§CMD_SESSION_CLI` for exact syntax).
    *   Phase labels MUST start with a number: `"N: Name"` or `"N.M: Name"` (e.g., `"4: Planning"`, `"4.1: Agent Handoff"`).
2.  **Execute** (non-sequential transition — skip forward or go backward): Use `engine session phase` with `--user-approved` flag (see `§CMD_SESSION_CLI`).
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

**Categories**: Activate outputs sections: `## §CMD_SURFACE_ACTIVE_ALERTS`, `## §CMD_SURFACE_OPEN_DELEGATIONS`, `## §CMD_RECALL_PRIOR_SESSIONS`, `## §CMD_RECALL_RELEVANT_DOCS`, `## §CMD_DISCOVER_DELEGATION_TARGETS`. Each contains file paths (one per line) or `(none)`, except delegation targets which outputs a table.

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
    *   *Example*:
        ```markdown
        # Implementation Debriefing: My Feature
        **Tags**: #needs-review
        ```
    *   **Note**: Do NOT auto-add `#needs-documentation`. Documentation tags are applied manually by the user when needed, not auto-applied to every debrief.
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
8.  **Directive Management**: Execute `§CMD_MANAGE_DIRECTIVES`.
    *   Three passes: README updates (doc files touched), invariant capture (new rules), pitfall capture (gotchas).
    *   Each pass uses agent judgment, prompts user per candidate, skips silently if none found.
9b. **Process Delegations**: Execute `§CMD_PROCESS_DELEGATIONS`.
    *   Scans session artifacts for unresolved bare `#needs-X` inline tags.
    *   Invokes `/delegate` for each one (user chooses async/blocking/silent per tag).
    *   Skips silently if no unresolved delegation tags found.
10.  **Capture Side Discoveries**: Execute `§CMD_CAPTURE_SIDE_DISCOVERIES`.
    *   Scans the session log for side-discovery entries (observations, concerns, parking lot items).
    *   Presents multichoice to tag them for future dispatch (`#needs-implementation`, `#needs-research`, `#needs-brainstorm`).
    *   Skips silently if no side-discovery entries found.
10b. **Manage Alerts**: Execute `§CMD_MANAGE_ALERTS`.
    *   Checks whether this session's work warrants raising or resolving alerts.
    *   Uses `tag.sh` operations for `#active-alert` / `#done-alert` lifecycle.
    *   Skips silently if no alert actions needed.
11.  **Report Leftover Work**: Execute `§CMD_REPORT_LEFTOVER_WORK`.
    *   Extracts unfinished items from session artifacts (tech debt, unresolved blocks, incomplete plan steps, doc impact).
    *   Outputs a concise report in chat + appends to session log.
    *   Gives the user context for their next-skill choice.
    *   Skips silently if no leftover items found.
11b. **Dispatch Approval**: Execute `§CMD_DISPATCH_APPROVAL`.
    *   Scans current session for `#needs-X` tags (excluding review/rework).
    *   Groups by tag type, presents walkthrough for user to approve → flip to `#delegated-X`.
    *   Approved items become visible to the daemon for autonomous dispatch.
    *   Skips silently if no `#needs-X` tags found.
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
3.  **Deactivate**: Execute using `engine session deactivate` (see `§CMD_SESSION_CLI` for exact syntax). This sets `lifecycle=completed`, stores description + keywords in `.state.json`, and runs a RAG search returning related sessions in stdout.
4.  **Process RAG Results**: If deactivate returned a `## Related Sessions` section in stdout, display it in chat. This gives the user awareness of related past work.
5.  **Contextualize & Present Menu**:
    *   **Preamble (REQUIRED)**: Before presenting the menu, output a short summary block in chat that explains what each skill option would concretely do *for this session's work*. Do NOT use generic descriptions — tailor each to the actual changes, files, and outcomes of the session. Format:
        > **What each option involves:**
        > - `/skill1` — [1-2 sentences: what this skill would do given the specific work just completed]
        > - `/skill2` — [1-2 sentences: what this skill would do given the specific work just completed]
        > - `/skill3` — [1-2 sentences]
        > - `/skill4` — [1-2 sentences]
    *   **Menu**: Then execute `AskUserQuestion` with options derived from the `nextSkills` array in `.state.json` (populated at session activation from the skill's `### Next Skills` declaration). Each skill defines up to **4 options** (the AskUserQuestion limit). The implicit 5th option ("Other") lets the user type a skill name or describe new work. The question text MUST explain this: include "(Type a /skill name to invoke it, or describe new work to scope it)" in the question.
    *   **Option format**: For each skill in `nextSkills`, use: label=`"/skill-name"`, description=contextualized to this session's work (from the preamble above). The first option should be marked "(Recommended)".
    *   **Fallback**: If `nextSkills` is empty or missing in `.state.json`, use the `§CMD_DISCOVER_DELEGATION_TARGETS` table to derive options (pick the 4 most commonly recommended skills).
6.  **On Selection**:
    *   **If a skill is chosen**: Invoke the Skill tool: `Skill(skill: "[chosen-skill]")`
    *   **If "Other" — skill name** (user typed `/implement`, `/test`, etc.): Invoke the Skill tool with the typed skill name.
    *   **If "Other" — new work details** (user typed notes, questions, or requirements): This is new input that needs scoping. Offer to route to interrogation: execute `AskUserQuestion` with "Start interrogation to scope this?" / "Just do it inline" options. If interrogation is chosen, reactivate the session and enter Phase 3.

**Constraints**:
*   **Session description is REQUIRED**: `session.sh deactivate` will ERROR if no description is piped. This powers RAG search for future sessions.
*   **Keywords are RECOMMENDED**: If omitted, deactivate still works but the session is less discoverable by future RAG queries.
*   **Max 4 options**: Each skill defines up to 4 skill options via its `nextSkills` array. The first should be marked "(Recommended)". The user can always type something else via "Other".
*   **Options come from `nextSkills`**: Each skill declares its own `nextSkills` in `### Next Skills (for §CMD_PARSE_PARAMETERS)`. The command reads them from `.state.json` at runtime — it doesn't read SKILL.md.
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
3.  **Update Phase Tracking**: Execute `§CMD_UPDATE_PHASE` to update `.state.json` (see `§CMD_SESSION_CLI` for exact syntax). This updates the status line display and enables restart recovery.
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
1.  **Construct**: Prepare the Markdown block following `~/.claude/directives/TEMPLATE_DETAILS.md`.
    *   **Agent**: Quote your question (keep nuance/options).
    *   **User**: VERBATIM quote of the user's answer.
    *   **Action**: Paraphrase your decision/action (e.g., "Updated Plan").
2.  **Execute**:
    ```bash
    engine log sessions/[YYYY_MM_DD]_[TOPIC]/DETAILS.md <<'EOF'
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
**Definition**: Structured interrogation with depth selection, topic-driven rounds, between-rounds context, and exit gating. The skill provides a **standard topics list** (under `### Interrogation Topics` in its SKILL.md); the command owns all mechanics.
**Trigger**: Called by skill protocols during their interrogation/pre-flight phase.

**Step 1 — Depth Selection**: Present via `AskUserQuestion` (multiSelect: false):
> "How deep should interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Task is well-understood, small scope, clear requirements |
| **Medium** | 6+ | Moderate complexity, some unknowns, multi-file changes |
| **Long** | 9+ | Complex system changes, many unknowns, architectural impact |
| **Absolute** | Until ALL questions resolved | Novel domain, high risk, critical system, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

**Step 2 — Round Loop**:

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth.

**Round counter**: Output on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the skill's standard topics or the universal repeatable topics below. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

**Universal repeatable topics** (available to all skills, can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1.  **Between-rounds context (2 paragraphs — MANDATORY, skip for Round 1)**:
    > **Round N-1 recap**: [1 paragraph — Summarize what was learned: key answers, decisions made, constraints established, assumptions confirmed or invalidated.]
    >
    > **Round N — [Topic]**: [1 paragraph — Explain what topic is next, why it's relevant given what was just learned, and what the questions aim to uncover.]

    **Anti-pattern**: Do NOT jump straight into questions without context. The user should always know what was just established and why they're being asked the next set.
2.  **Ask**: Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on the chosen topic).
3.  **Handle response**:
    *   **User provided answers**: Execute `§CMD_LOG_TO_DETAILS` immediately. Continue to next round.
    *   **User asked a counter-question**: PAUSE. Answer in chat. Ask "Does this clarify? Ready to resume?" Once confirmed, resume.

**Step 3 — Exit Gate**: After reaching minimum rounds, present via `AskUserQuestion` (multiSelect: true):
> "Round N complete (minimum met). What next?"
> - **"Proceed to next phase"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → re-present exit gate.

**On "Proceed to next phase"**: After the exit gate resolves, fire `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH` using the skill's Phase Transition config for the interrogation boundary. This gives the user the walkthrough option (review what was established during interrogation) before committing to the next phase. The skill's `### Phase Transition` block after interrogation provides the `completedPhase`/`nextPhase`/`prevPhase` values.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Output: "Round N complete. I still have questions about [X]. Continuing..."

**Constraints**:
*   Minimum rounds are mandatory. No self-authorized skips — fire `§CMD_REFUSE_OFF_COURSE` if tempted.
*   Between-rounds context is mandatory after Round 1. No bare question dumps.
*   Every round logged to DETAILS.md. No unlogged rounds.
*   Counter-questions don't count as rounds.

### §CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH
**Description**: Standardized phase boundary menu — presents 3 core options (proceed to next phase, walkthrough current phase output, go back to previous phase) plus an optional 4th skill-specific option. Replaces ad-hoc `AskUserQuestion` blocks at phase transitions.
**Trigger**: Called by skill protocols at phase boundaries, after `§CMD_VERIFY_PHASE_EXIT`. Not used for special boundaries (interrogation exit gate, parallel handoff, synthesis deactivation).
**Reference**: `~/.claude/directives/commands/CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH.md`

### §CMD_HAND_OFF_TO_AGENT
**Description**: Standardized handoff from a parent command to an autonomous agent (opt-in, foreground).
**Trigger**: After plan approval, skill protocols offer agent handoff as an alternative to inline execution.
**Reference**: `~/.claude/directives/commands/CMD_HAND_OFF_TO_AGENT.md`

### §CMD_PARALLEL_HANDOFF
**Description**: Parallel agent handoff — analyzes plan dependencies, derives independent chunks, presents non-intersection proof, and launches multiple agents in parallel.
**Trigger**: After plan approval in plan-based skills (implement, debug, test, document, refine-docs). Extends `§CMD_HAND_OFF_TO_AGENT` with multi-agent coordination.
**Reference**: `~/.claude/directives/commands/CMD_PARALLEL_HANDOFF.md`

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

### §CMD_CHECK
**Description**: Validates session artifacts before deactivation — 3 validations (tag scan, checklists, request files). All must pass for `checkPassed=true`.
**Trigger**: Called during synthesis, before debrief. Agents use `§CMD_PROCESS_TAG_PROMOTIONS` and `§CMD_PROCESS_CHECKLISTS` to address failures.
**Reference**: `~/.claude/directives/commands/CMD_CHECK.md`

### §CMD_PROCESS_CHECKLISTS
**Description**: Processes discovered CHECKLIST.md files during synthesis — reads each checklist, evaluates items against the session's work, then quotes results back to `session.sh check` for mechanical validation. Sets `checkPassed=true` in `.state.json`. Ensures the deactivation gate (`¶INV_CHECKLIST_BEFORE_CLOSE`) will pass.
**Trigger**: Called by skill protocols during synthesis phase, BEFORE `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`. Read the reference file before executing.
**Reference**: `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md`

### §CMD_PROCESS_TAG_PROMOTIONS
**Description**: Handles bare inline lifecycle tags reported by `session.sh check` during synthesis. For each bare `#needs-*` / `#claimed-*` / `#done-*` tag found in session artifacts, the agent presents a promote/acknowledge menu and processes the user's choices.
**Trigger**: Called when `session.sh check` exits 1 with `¶INV_ESCAPE_BY_DEFAULT` violations.

**Algorithm**:
1.  **Run check**: Execute `session.sh check [sessionDir] < /dev/null`. If exit 0, skip (no bare tags).
2.  **Parse output**: Extract bare tag entries from stderr (format: `file:line: #tag — context`).
3.  **Present menu**: For each bare tag, execute `AskUserQuestion` (multiSelect: false):
    > "Bare inline tag found: `#tag` in `file:line`"
    > - **"Promote"** — Create a REQUEST file from the skill's template + backtick-escape the inline tag in-place
    > - **"Acknowledge"** — Tag is intentional, leave it bare (agent logs the acknowledgment)
    > - **"Escape"** — Just backtick-escape it (no request file needed, it was a reference not a work item)
4.  **Execute choice**:
    *   **Promote**: (a) Read the skill's `TEMPLATE_*_REQUEST.md` from `~/.claude/skills/[tag-noun]/assets/`. (b) Populate the template with context from the inline tag's surrounding text. (c) Write the request file to the session directory. (d) Backtick-escape the inline tag in the source file.
    *   **Acknowledge**: Log the acknowledgment to `_LOG.md`. No file changes.
    *   **Escape**: Backtick-escape the tag in the source file. No request file.
5.  **Mark complete**: After all tags are processed, execute `session.sh update [sessionDir] tagCheckPassed true`.
6.  **Re-run check**: Execute `session.sh check [sessionDir]` again (with stdin for checklists if applicable). Should now pass.

**Constraints**:
*   This command runs BEFORE `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` — debrief cannot be written until tags are resolved.
*   The `tagCheckPassed` field in `.state.json` persists across re-runs — once set, the tag scan is skipped.
*   If no per-skill request template exists for the tag's noun, use a generic format: `# Request: [topic]\n**Tags**: #needs-[noun]\n## Context\n[surrounding text]`.

### §CMD_MANAGE_DIRECTIVES
**Description**: Unified end-of-session directive management. Three passes: README updates (doc files touched near discovered READMEs), invariant capture (new rules/constraints), pitfall capture (gotchas and traps). Replaces `§CMD_MANAGE_TOC` + `§CMD_PROMPT_INVARIANT_CAPTURE`.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 8, after debrief is written. Read the reference file before executing.
**Reference**: `~/.claude/directives/commands/CMD_MANAGE_DIRECTIVES.md`

### §CMD_CAPTURE_SIDE_DISCOVERIES
**Description**: Scans the session log for side-discovery entries (observations, concerns, parking lot items) and presents a multichoice menu to tag them for future dispatch.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 10, after TOC management. Read the reference file before executing.
**Reference**: `~/.claude/directives/commands/CMD_CAPTURE_SIDE_DISCOVERIES.md`

### §CMD_DELEGATE
**Description**: Write a delegation REQUEST file, apply the appropriate tag, and execute the chosen delegation mode (async, blocking, or silent). The low-level primitive behind `/delegate`.
**Trigger**: Called by the `/delegate` skill after mode selection. Not called directly by agents.
**Reference**: `~/.claude/directives/commands/CMD_DELEGATE.md`

### §CMD_PROCESS_DELEGATIONS
**Description**: Scans session artifacts for unresolved bare `#needs-X` inline tags and invokes `/delegate` for each one. Synthesis pipeline step between walkthrough and debrief.
**Trigger**: Called during skill synthesis phases, after `§CMD_WALK_THROUGH_RESULTS` and before `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`. Read the reference file before executing.
**Reference**: `~/.claude/directives/commands/CMD_PROCESS_DELEGATIONS.md`

### §CMD_REPORT_LEFTOVER_WORK
**Description**: Extracts unfinished items from session artifacts (tech debt, unresolved blocks, incomplete plan steps) and presents a concise report in chat before the next-skill menu.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 11, after side discoveries. Read the reference file before executing.
**Reference**: `~/.claude/directives/commands/CMD_REPORT_LEFTOVER_WORK.md`

### §CMD_DISPATCH_APPROVAL
**Description**: Reviews `#needs-X` tags in the current session and lets the user approve them for daemon dispatch (`#delegated-X`). The human gate between tag creation and autonomous processing.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 9b (after `§CMD_PROCESS_DELEGATIONS`, before `§CMD_CAPTURE_SIDE_DISCOVERIES`). Also callable standalone.

**Algorithm**:
1.  **Scan**: Find all `#needs-X` tags in the current session directory:
    *   `tag.sh find '#needs-*' [sessionDir] --tags-only` — Tags-line entries on REQUEST files and debriefs
    *   Exclude `#needs-review` (resolved by `/review`, not daemon dispatch)
    *   Exclude `#needs-rework` (resolved by `/review`)
2.  **Skip if empty**: If no `#needs-X` tags found (excluding review/rework), skip silently. No user prompt.
3.  **Group**: Organize results by tag type (e.g., all `#needs-implementation` together, all `#needs-chores` together).
4.  **Present**: For each group, execute `AskUserQuestion` (multiSelect: true):
    > "Dispatch approval — `#needs-[noun]` ([N] items):"
    > - **"Approve all [N] for daemon dispatch → `#delegated-[noun]`"** — Flip all items in this group
    > - **"Review individually"** — Walk through each item to approve/defer/dismiss
    > - **"Defer all"** — Leave as `#needs-[noun]` (will appear in next session's dispatch approval)
5.  **Execute**:
    *   **Approve all**: For each file in the group, `tag.sh swap [file] '#needs-[noun]' '#delegated-[noun]'`.
    *   **Review individually**: For each file, present: Approve (`#delegated-X`) / Defer (keep `#needs-X`) / Dismiss (remove tag entirely).
    *   **Defer all**: No action. Tags remain as `#needs-X`.
6.  **Report**: Output summary in chat: "Dispatched: [N] items. Deferred: [M] items. Dismissed: [K] items."

**Constraints**:
*   **Current session only**: Does NOT scan other sessions. Cross-session dispatch is out of scope.
*   **Human approval required** (`¶INV_DISPATCH_APPROVAL_REQUIRED`): Agents MUST NOT auto-flip `#needs-X` → `#delegated-X`.
*   **Daemon monitors `#delegated-*`** (`¶INV_NEEDS_IS_STAGING`): Only approved items become visible to the daemon.
*   **Debounce-friendly**: Multiple `tag.sh swap` calls in rapid succession are collected by the daemon's 3s debounce (`¶INV_DAEMON_DEBOUNCE`).

### §CMD_WALK_THROUGH_RESULTS
**Description**: Walks the user through skill outputs or plan items with configurable granularity (None / Groups / Each item). Two modes: **results** (post-execution triage — delegate/defer/dismiss) and **plan** (pre-execution review — comment/question/flag). Each skill provides a configuration block defining mode, gate question, item sources, and action menu or plan questions.
**Trigger**: Called by skill protocols either during synthesis (results mode) or after plan creation (plan mode). Read the reference file before executing.
**Reference**: `~/.claude/directives/commands/CMD_WALK_THROUGH_RESULTS.md`

