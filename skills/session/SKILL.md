---
name: session
description: "Smart assistant for session management — dehydrate context, recover from overflow, search sessions, check status. Triggers: \"session status\", \"dehydrate this session\", \"search sessions\", \"session find\"."
version: 2.0
tier: lightweight
args: "[subcommand] [args]"
---

Smart assistant for session management — dehydrate, recover, search, and inspect sessions.

[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# Session Assistant Protocol (The Session Operator)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It boots, classifies the request, and handles it. Identical pattern to `/engine`.

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup for the Session Assistant.
    > 2. I will `§CMD_ASSUME_ROLE`:
    >    **Role**: You are the **Session Operator** — the authoritative guide to session lifecycle, context preservation, and session discovery.
    >    **Goal**: Handle session operations accurately. Dehydrate context, recover from overflow, search sessions, and report status.
    >    **Mindset**: "Know every session's state. Preserve context. Recover cleanly."
    > 3. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT`.

2.  **Parse User Intent**: Review the user's original request (the `/session` arguments). Classify it:

    | Pattern | Subcommand | Handler |
    |---------|-----------|---------|
    | *(bare — no args)* | `status` | Show current session status + offer menu |
    | `dehydrate` | `dehydrate` | Write DEHYDRATED_CONTEXT.md |
    | `dehydrate restart` | `dehydrate restart` | Write + kill + respawn |
    | `restart` | `restart` | Auto-detect session, bare restart (no dehydration) |
    | `continue --session X --skill Y --phase Z [--continue]` | `continue` | Load dehydrated state, resume skill |
    | `search <query>` | `search` | Semantic session search |
    | `status` | `status` | Show `.state.json` details |
    | `find <filter>` | `find` | Structured session find |
    | *(free text that doesn't match above)* | `search` | Classify as search query |

    **Subcommand detection**: Check args for known subcommand keywords first. If no match, treat the entire args string as a search query.

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Interactive Loop

**This phase loops until the user is done.** Each iteration handles one subcommand.

---

### Subcommand: `status` (default on bare `/session`)

**Action**: Display the current session state.

1.  **Check for active session**: Run `engine session status` (if it exists) or read `.state.json` from the most recent session directory.
    ```bash
    engine find-sessions --recent 1
    ```
2.  **Display**:
    *   Active session directory (or "No active session")
    *   Current skill and phase
    *   Context usage % (if available)
    *   Session lifecycle state (active, completed, loading)
3.  **Offer menu** (only on bare `/session`):
    Execute `AskUserQuestion` (multiSelect: false):
    > "What session operation do you need?"
    > - **"Dehydrate"** — Save current context to file
    > - **"Search sessions"** — Find past sessions by topic
    > - **"Done"** — Exit

    On selection, execute the corresponding subcommand handler below.

---

### Subcommand: `dehydrate`

**Action**: Capture and persist current session context for later restoration.

[!!!] CRITICAL: Context may be near overflow. DO NOT read extra files. Use ONLY what's already in your context window.

**Role**: You are the **Context Archivist**.
**Goal**: Package the current session's state into a portable summary and a list of required files.

#### Step 1: Context Inventory

Gather inventory from CURRENT CONTEXT ONLY.

**Minimal I/O Allowed**:
1.  **List Session Dir** (1 command): Execute `ls -F sessions/[CURRENT_SESSION]/` to see what artifacts exist.
2.  **Review from Memory**: Look back at chat history for `§CMD_PARSE_PARAMETERS` output to recall `contextPaths` and `preludeFiles`.
3.  **Identify Criticals**: Any file mentioned in `preludeFiles` OR generated in the session folder (especially `DETAILS.md`, `_LOG.md`, `_PLAN.md`) is **MANDATORY** to list in Required Files — but do NOT read them now.

#### Step 2: The Summary (Markdown Output)

Generate the summary in Markdown format:

1.  **Header**: `# DEHYDRATED CONTEXT (Session Handover)`
2.  **The "Big Picture"**:
    *   **Ultimate Goal**: Single main objective of the session/feature.
    *   **Strategy**: Architectural or implementation path.
    *   **Status**: How far along (e.g., "50% - Core logic done, integration tests pending").
3.  **User Interaction History**:
    *   **Sentiment**: Was the user satisfied?
    *   **Key Directives**: Explicit asks/avoids from the user.
    *   **Recent Feedback**: Quotes or summaries of recent user messages.
4.  **Last Action Report**:
    *   **Last Task**: What exactly was the agent doing when stopped?
    *   **Outcome**: Succeed, Fail, or Hang?
    *   **State**: Is code compilable? Tests passing?
5.  **Handover Instructions**: Specific instructions for the next agent.
6.  **Next Steps**: Bulleted list of immediate tasks. For proof-gated phases, include the proof fields needed for the next transition.
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
    *   **Injection Framework Note**: Engine standards (`COMMANDS.md`, `INVARIANTS.md`, `TAGS.md`), project directives, and skill templates are auto-injected by the framework. Focus dehydration on session-specific state (artifacts, source code, user interaction history).

#### Step 3: Final Output

**3a — Write Markdown File** (human-readable + `/session continue` fallback):
```bash
engine log --overwrite sessions/[CURRENT_SESSION]/DEHYDRATED_CONTEXT.md <<'EOF'
# DEHYDRATED CONTEXT (Session Handover)
[FULL CONTENT HERE]
EOF
```

**3b — Write JSON to .state.json** (hook-based restore):
Build a JSON object from the summary and pipe it to the engine command. The SessionStart hook will read this on the next Claude startup and inject it as `additionalContext`.
```bash
engine session dehydrate sessions/[CURRENT_SESSION] <<'EOF'
{
  "summary": "[Ultimate Goal + Strategy + Status — 2-3 sentences]",
  "lastAction": "[Last Task + Outcome — 1-2 sentences]",
  "nextSteps": ["Step 1", "Step 2", "..."],
  "handoverInstructions": "[Specific instructions for the next agent]",
  "requiredFiles": [
    "sessions/[CURRENT_SESSION]/IMPLEMENTATION_LOG.md",
    "sessions/[CURRENT_SESSION]/IMPLEMENTATION_PLAN.md",
    "~/.claude/skills/[SKILL]/SKILL.md"
  ],
  "userHistory": "[Sentiment + Key Directives + Recent Feedback — 2-3 sentences]"
}
EOF
```
**Field guidelines**:
*   `requiredFiles`: Same files as the Markdown "Required Files" section. Use the same path conventions (prefix-based).
*   `summary`, `lastAction`, `userHistory`: Concise — these become the hook's `additionalContext` header. The Markdown file has the verbose version.
*   `nextSteps`: Array of strings, one per step. Keep actionable.

**3c — Display in Chat**: Show section headers and key points. State file path as clickable link per `¶INV_TERMINAL_FILE_LINKS`.

**3d — Trigger Restart** (if args contain `restart` OR triggered by context overflow):
1.  Save current phase:
    ```bash
    engine session phase sessions/[CURRENT_SESSION] "Phase X: [Name]"
    ```
2.  Trigger restart:
    ```bash
    engine session restart sessions/[CURRENT_SESSION]
    ```
    **WARNING**: This will kill the current Claude process and spawn a fresh one. The new Claude's SessionStart hook will inject the dehydrated context automatically. `/session continue` remains as fallback if the hook doesn't fire.

**3e — Confirm** (no restart): State "Dehydrated to `sessions/[CURRENT_SESSION]/DEHYDRATED_CONTEXT.md`"

---

### Subcommand: `restart`

**Action**: Bare restart — kill the current Claude process and respawn at the saved phase. No dehydration.

[!!!] This does NOT dehydrate context. If you need context preservation, use `dehydrate restart` instead.

1.  **Find active session**:
    ```bash
    engine session find
    ```
    If no active session is found (exit 1), display: "No active session found. Nothing to restart."
2.  **Trigger restart**:
    ```bash
    engine session restart [SESSION_DIR]
    ```
    This sets `killRequested=true` in `.state.json`, writes the `restartPrompt` (a `/session continue` command), and signals the watchdog to kill Claude.
3.  **Output**: "Restarting session `[SESSION_DIR]`... Claude will respawn at the saved phase."

    **WARNING**: This will kill the current Claude process. The new Claude will receive a `/session continue` prompt and resume at the saved phase — but without dehydrated context, it relies on `.state.json` phase info only.

---

### Subcommand: `continue`

**Action**: Recover from context overflow by loading dehydrated state and resuming the original skill.

**Arguments**:
- `--session`: Session directory path (REQUIRED)
- `--skill`: Original skill to resume (REQUIRED)
- `--phase`: Phase to resume at (REQUIRED)
- `--continue`: Auto-continue execution after recovery (no pause for user)

**Protocol**: This subcommand uses a multi-phase recovery protocol. Load it on demand:

```
Read: ~/.claude/engine/skills/session/references/continue-protocol.md
```

After reading, execute the continue protocol exactly as written. Do NOT improvise or abbreviate — the protocol is battle-tested.

---

### Subcommand: `search`

**Action**: Semantic search across session artifacts.

1.  **Execute**:
    ```bash
    engine session-search query "[QUERY]"
    ```
2.  **Display results**: Show top matches with session directory, distance score, and excerpt.
3.  **Offer follow-up**: "Want me to read any of these sessions?"

---

### Subcommand: `find`

**Action**: Structured session discovery with filters.

1.  **Parse filters**: Extract from args:
    *   `--tag <tag>` — Find sessions with a specific tag
    *   `--recent <N>` — Show N most recent sessions
    *   `--skill <name>` — Filter by skill type
2.  **Execute**:
    ```bash
    # Tag-based
    engine tag find '<tag>'

    # Recent
    engine find-sessions --recent <N>

    # Skill-based
    engine find-sessions --skill <name>
    ```
3.  **Display results**: Show matching sessions with key metadata.

---

### Subcommand: `status` (explicit)

Same as the default handler above. Show session state details.

---

### Iteration

After handling each request, wait for the user's next message. Do NOT proactively ask "What else?" — just wait. The user will either:
*   Ask another question → handle it
*   Invoke another skill → let the skill system handle it
*   Say nothing → session ends naturally

---

## Key Reference: Session Command Categories

| Need | Command | Notes |
|------|---------|-------|
| Dehydrate context | `/session dehydrate` | Save context to file |
| Dehydrate + restart | `/session dehydrate restart` | Save + kill + respawn |
| Bare restart | `/session restart` | Kill + respawn (no dehydration) |
| Recover from overflow | `/session continue --session X ...` | Auto-invoked by restart |
| Search sessions | `/session search <query>` | Semantic search |
| Find sessions | `/session find --tag X` | Structured filters |
| Session status | `/session` or `/session status` | Current session state |
