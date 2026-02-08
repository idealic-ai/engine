---
name: dehydrate
description: "Captures and persists current session context for later restoration. Triggers: \"dehydrate this session\", \"serialize session state\", \"save session snapshot\", \"pause and resume later\"."
version: 2.0
tier: lightweight
args: "[restart]"
---

Captures and persists current session context for later restoration.

**Usage**:
- `/dehydrate` — Save context to file, stay in session
- `/dehydrate restart` — Save context to file, restart Claude with fresh context

[!!!] INVOCATION (READ THIS):
- This skill is invoked via the **Skill tool**, NOT via Bash.
- Correct: `Skill(skill: "dehydrate", args: "restart")`
- WRONG: `~/.claude/scripts/session.sh dehydrate` (this does not exist)
- WRONG: `Bash("/dehydrate restart")` (slash commands are not shell scripts)

[!!!] CRITICAL BOOT SEQUENCE:
1. SKIP LOADING STANDARDS — Context is likely at overflow. DO NOT read extra files.
2. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.
3. MINIMIZE I/O: The protocol specifies exactly what minimal commands are allowed.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

**Dehydrate-specific check** (LOW-I/O skill — context near overflow):
> - Active session dir: `________`
> - Extra files loaded: `none`

# Dehydration Protocol (Context Compressor)

**Role**: You are the **Context Archivist**.
**Goal**: To package the current session's entire state into a portable summary and a list of required files.
**Trigger**: When the user says "Dehydrate", "Serialize", "Pause", or asks to save context. Also triggered by PreToolUse hook at 90% context overflow.

## 1. Context Inventory (Pre-Flight)
**Action**: Before writing the summary, gather the inventory from CURRENT CONTEXT ONLY.

[!!!] CRITICAL: DO NOT READ EXTRA FILES. Context is already near overflow. Use ONLY what's already loaded in your context window:
*   Recall files you've already read this session
*   Recall the session directory from `§CMD_MAINTAIN_SESSION_DIR` output
*   Recall `contextPaths` from `§CMD_PARSE_PARAMETERS` output
*   DO NOT call Read tool to load files just to inventory them

**Minimal I/O Allowed**:
1.  **List Session Dir** (1 command): Execute `ls -F sessions/[CURRENT_SESSION]/` to see what artifacts exist.
2.  **Review from Memory**: Look back at the chat history for `§CMD_PARSE_PARAMETERS` output to recall `contextPaths` and `preludeFiles`.
3.  **Identify Criticals**: Any file mentioned in `preludeFiles` OR generated in the session folder (especially `DETAILS.md`, `_LOG.md`, `_PLAN.md`) is **MANDATORY** to list in Required Files section — but do NOT read them now.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Session directory: `________`
> - Session dir listed: `________`
> - Context paths recalled: `________`
> - Critical files identified: `________`

---

## 2. The Summary Phase (Markdown Output)
**Action**: Generate the summary in Markdown format.
**Content**:
1.  **Header**: "# DEHYDRATED CONTEXT (Session Handover)\nThis content contains the high-level summary, handover notes, and immediate next steps."
2.  **The "Big Picture" (High Level Task)**:
    *   **Ultimate Goal**: What is the single main objective of this entire session/feature? (e.g., "Implement seamless graph swapping without audio glitches").
    *   **Strategy**: What architectural or implementation path are we taking? (e.g., "Using double-buffering for nodes").
    *   **Status**: How far along is the overall mission? (e.g., "50% - Core logic done, integration tests pending").
3.  **User Interaction History**:
    *   **Sentiment**: Was the user satisfied with recent progress? (e.g., "Happy", "Frustrated", "Impatient").
    *   **Key Directives**: Did the user explicitly ask to *avoid* something or *focus* on something? (e.g., "User explicitly forbade using `any` types" or "User wants to focus on performance first").
    *   **Recent Feedback**: specific quotes or summaries of the last few user messages.
4.  **Last Action Report (Specifics)**:
    *   **Last Task**: What *exactly* was the agent doing when stopped? (e.g., "Debugging `AudioWorklet.ts` race condition").
    *   **Last Log Entry**: Which `_LOG.md` was updated? What timestamp/entry?
    *   **Outcome**: Did the last action Succeed, Fail, or Hang?
    *   **State**: Is the code currently compilable? Are tests passing?
5.  **Handover Instructions**: Specific instructions for the next agent.
6.  **Next Steps**: Bulleted list of immediate tasks.
7.  **Required Files (Context List)**:
    *   **Path Conventions** (CRITICAL — use correct prefix):
        | Prefix | Resolves To | Contains |
        |--------|-------------|----------|
        | `~/.claude/` | User home `~/.claude/` | Shared engine (skills, standards, agents, scripts) |
        | `.claude/` | Project root `.claude/` | Project-local config (settings, project standards) |
        | `sessions/` | Project root `sessions/` | Session directories (logs, plans, dehydrated context) |
        | `packages/`, `apps/`, `src/` | Project root | Source code |
    *   **Instruction**: "List all files that must be read to restore context."
    *   **MANDATORY**: You MUST list every `.md` file found in the session directory (Logs, Plans, especially DETAILS document).
    *   **MANDATORY**: You MUST list every file from the original `preludeFiles` list.
    *   **Source Code**: Comprehensive list of relevant code, tests, and config files touched during the session.
    *   **Guidance**: It is better to include too much context than too little. If in doubt, include it.
    *   **WARNING**: Do NOT confuse `~/.claude/` (shared engine) with `.claude/` (project-local). They are different directories.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Sections populated: `________` / 7
> - Session .md files listed: `________`
> - Original preludeFiles listed: `________`
> - Path conventions table: `________`
> - Extra files read: `________` (should be none)

---

## 3. Final Output (File + Optional Restart)
**Action**: Write the dehydrated context to file, then trigger restart if requested or overflow-triggered.

### Step 3a: Write to File (ALWAYS)
**Action**: Write the full dehydrated markdown to `DEHYDRATED_CONTEXT.md` in the session directory using log.sh.
```bash
~/.claude/scripts/log.sh --overwrite sessions/[CURRENT_SESSION]/DEHYDRATED_CONTEXT.md <<'EOF'
# DEHYDRATED CONTEXT (Session Handover)
[FULL CONTENT HERE]
EOF
```

### Step 3b: Display in Chat
**Action**: Output a summary in chat so the user can see what was captured.
*   Show the section headers and key points (not necessarily the full content).
*   State the file path as a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant): "Dehydrated context saved to [link]"

### Step 3c: Trigger Restart (Overflow OR User Request)
**Condition**: Execute this step if ANY of these are true:
1. Dehydration was triggered by context overflow (PreToolUse hook blocked you with "CONTEXT OVERFLOW" message)
2. User passed `restart` argument (e.g., `/dehydrate restart`)

**Action**:

1. **Save current phase** — Determine which phase of the skill protocol you were in and save it:
   ```bash
   ~/.claude/scripts/session.sh phase sessions/[CURRENT_SESSION] "Phase X: [Name]"
   ```
   *   Look at your recent work to determine the phase (e.g., "Phase 3: Execution", "Phase 5: Build Loop")
   *   This tells the restarted Claude where to resume

2. **Trigger restart** — Call `session.sh restart` to spawn fresh Claude:
   ```bash
   ~/.claude/scripts/session.sh restart sessions/[CURRENT_SESSION]
   ```

**WARNING**: This command will:
1. Set `.state.json` status to `ready-to-kill`
2. Kill the current Claude process
3. Spawn a fresh Claude with the skill invocation + rehydration instructions

### Step 3d: Confirm (No Restart)
**Condition**: ONLY if no restart was triggered (manual dehydration without `restart` argument).
**Action**: State "Dehydrated to `sessions/[CURRENT_SESSION]/DEHYDRATED_CONTEXT.md`"

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - DEHYDRATED_CONTEXT.md written: `________`
> - Summary displayed: `________`
> - Restart condition: `________` (met / not met)
> - Action taken: `________` (phase saved + restart triggered / confirmation output)
