---
name: session
description: "Smart assistant for session management — search sessions, check status, restart, continue after overflow. Triggers: \"session status\", \"search sessions\", \"session find\"."
version: 4.0
tier: lightweight
args: "[subcommand] [args]"
---

Smart assistant for session management — search, inspect, restart, and continue sessions.

# Session Assistant Protocol (The Session Operator)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It boots, classifies the request, and handles it. Identical pattern to `/engine`.

[!!!] **Dehydration is NOT a subcommand anymore**. Dehydration is handled by `§CMD_DEHYDRATE` (always preloaded). The overflow hook triggers it directly. If a user says "dehydrate", explain that `§CMD_DEHYDRATE` handles it automatically at context overflow, or they can invoke it manually by following the protocol in their context.

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup for the Session Assistant.
    > 2. I will `§CMD_ASSUME_ROLE`:
    >    **Role**: You are the **Session Operator** — the authoritative guide to session lifecycle, context preservation, and session discovery.
    >    **Goal**: Handle session operations accurately. Search sessions, restart, recover from overflow, and report status.
    >    **Mindset**: "Know every session's state. Preserve context. Recover cleanly."
    > 3. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT`.

2.  **Parse User Intent**: Review the user's original request (the `/session` arguments). Classify it:

    | Pattern | Subcommand | Handler |
    |---------|-----------|---------|
    | *(bare — no args)* | `status` | Show current session status + offer menu |
    | `restart` | `restart` | Auto-detect session, bare restart (no dehydration) |
    | `continue --session X --skill Y --phase Z [--continue]` | `continue` | Resume after overflow via `§CMD_REHYDRATE` |
    | `search <query>` | `search` | Semantic session search |
    | `status` | `status` | Show `.state.json` details |
    | `find <filter>` | `find` | Structured session find |
    | `dehydrate` | *(redirect)* | Explain: use `§CMD_DEHYDRATE` protocol (preloaded) |
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
    > - **"Search sessions"** — Find past sessions by topic
    > - **"Restart"** — Kill + respawn current session
    > - **"Done"** — Exit

    On selection, execute the corresponding subcommand handler below.

---

### Subcommand: `dehydrate` (redirect)

**Action**: Explain that dehydration is now handled by `§CMD_DEHYDRATE`.

> Dehydration is no longer a `/session` subcommand. It's handled by `§CMD_DEHYDRATE`, which is always preloaded in your context.
>
> - **Automatic**: The overflow hook triggers `§CMD_DEHYDRATE NOW` when context exceeds the threshold
> - **Manual**: Follow the `§CMD_DEHYDRATE` protocol in your context — produce JSON, pipe to `engine session dehydrate`
>
> The `engine session dehydrate` command stores context in `.state.json` and triggers restart automatically.

---

### Subcommand: `restart`

**Action**: Bare restart — kill the current Claude process and respawn at the saved phase. No dehydration.

[!!!] This does NOT dehydrate context. If you need context preservation, follow `§CMD_DEHYDRATE` first.

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

**Action**: Recover from context overflow by resuming the original skill at the saved phase.

**Arguments**:
- `--session`: Session directory path (REQUIRED)
- `--skill`: Original skill to resume (REQUIRED)
- `--phase`: Phase to resume at (REQUIRED)
- `--continue`: Auto-continue execution after recovery (no pause for user)

**Protocol**: Execute `§CMD_REHYDRATE` (preloaded in context). The SessionStart hook has already injected dehydrated context and required files from `.state.json`. Follow the `§CMD_REHYDRATE` algorithm to re-activate the session, resume tracking, log the restart, and continue at the saved phase.

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
| Dehydrate context | `§CMD_DEHYDRATE` protocol | Preloaded; produces JSON → `engine session dehydrate` |
| Bare restart | `/session restart` | Kill + respawn (no dehydration) |
| Recover from overflow | `/session continue --session X ...` | Follows `§CMD_REHYDRATE` |
| Search sessions | `/session search <query>` | Semantic search |
| Find sessions | `/session find --tag X` | Structured filters |
| Session status | `/session` or `/session status` | Current session state |
