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
- WRONG: `engine session dehydrate` (this does not exist)
- WRONG: `Bash("/dehydrate restart")` (slash commands are not shell scripts)

[!!!] CRITICAL: Context is likely near overflow. DO NOT read extra files. Use ONLY what's already in your context window.

# Dehydration Protocol (Context Compressor)

**Role**: You are the **Context Archivist**.
**Goal**: Package the current session's state into a portable summary and a list of required files.

## 1. Context Inventory
**Action**: Gather inventory from CURRENT CONTEXT ONLY.

[!!!] DO NOT call Read tool to load files just to inventory them. Use what's already loaded.

**Minimal I/O Allowed**:
1.  **List Session Dir** (1 command): Execute `ls -F sessions/[CURRENT_SESSION]/` to see what artifacts exist.
2.  **Review from Memory**: Look back at chat history for `§CMD_PARSE_PARAMETERS` output to recall `contextPaths` and `preludeFiles`.
3.  **Identify Criticals**: Any file mentioned in `preludeFiles` OR generated in the session folder (especially `DETAILS.md`, `_LOG.md`, `_PLAN.md`) is **MANDATORY** to list in Required Files — but do NOT read them now.

---

## 2. The Summary (Markdown Output)
**Action**: Generate the summary in Markdown format.
**Content**:
1.  **Header**: "# DEHYDRATED CONTEXT (Session Handover)"
2.  **The "Big Picture"**:
    *   **Ultimate Goal**: Single main objective of the session/feature.
    *   **Strategy**: Architectural or implementation path.
    *   **Status**: How far along (e.g., "50% - Core logic done, integration tests pending").
3.  **User Interaction History**:
    *   **Sentiment**: Was the user satisfied? (e.g., "Happy", "Frustrated")
    *   **Key Directives**: Explicit asks/avoids from the user.
    *   **Recent Feedback**: Quotes or summaries of recent user messages.
4.  **Last Action Report**:
    *   **Last Task**: What exactly was the agent doing when stopped?
    *   **Outcome**: Succeed, Fail, or Hang?
    *   **State**: Is code compilable? Tests passing?
5.  **Handover Instructions**: Specific instructions for the next agent.
6.  **Next Steps**: Bulleted list of immediate tasks.
7.  **Required Files (Context List)**:
    *   **Path Conventions**:
        | Prefix | Resolves To | Contains |
        |--------|-------------|----------|
        | `~/.claude/` | User home `~/.claude/` | Shared engine (skills, standards, scripts) |
        | `.claude/` | Project root `.claude/` | Project-local config |
        | `sessions/` | Project root `sessions/` | Session directories |
        | `packages/`, `apps/`, `src/` | Project root | Source code |
    *   **MANDATORY**: List every `.md` file in the session directory.
    *   **MANDATORY**: List every file from the original `preludeFiles` list.
    *   **Source Code**: All relevant code, tests, and config files touched during the session.
    *   **Guidance**: Better to include too much than too little.
    *   **WARNING**: Do NOT confuse `~/.claude/` (shared engine) with `.claude/` (project-local).

---

## 3. Final Output

### Step 3a: Write to File
```bash
engine log --overwrite sessions/[CURRENT_SESSION]/DEHYDRATED_CONTEXT.md <<'EOF'
# DEHYDRATED CONTEXT (Session Handover)
[FULL CONTENT HERE]
EOF
```

### Step 3b: Display in Chat
Show section headers and key points. State file path as clickable link per `¶INV_TERMINAL_FILE_LINKS`.

### Step 3c: Trigger Restart (if applicable)
**Condition**: Execute if ANY of these are true:
1. Dehydration was triggered by context overflow (PreToolUse hook blocked with "CONTEXT OVERFLOW")
2. User passed `restart` argument (e.g., `/dehydrate restart`)

**Action**:
1. **Save current phase**:
   ```bash
   engine session phase sessions/[CURRENT_SESSION] "Phase X: [Name]"
   ```
2. **Trigger restart**:
   ```bash
   engine session restart sessions/[CURRENT_SESSION]
   ```

**WARNING**: This will kill the current Claude process and spawn a fresh one.

### Step 3d: Confirm (No Restart)
**Condition**: Only if no restart was triggered.
**Action**: State "Dehydrated to `sessions/[CURRENT_SESSION]/DEHYDRATED_CONTEXT.md`"
