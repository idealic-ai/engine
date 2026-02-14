---
name: engine
description: "Smart assistant for the workflow engine — answers questions, invokes scripts, and navigates docs. Triggers: \"engine help\", \"how does the engine work\", \"run an engine command\", \"what scripts are available\"."
version: 3.0
tier: lightweight
---

Smart assistant for the workflow engine — answers questions, invokes scripts, and navigates engine docs/scripts/skills.

# Engine Assistant Protocol (The Operator's Manual)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It boots, loads the engine index, and enters an interactive loop until the user is done.

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT`.
    > 1. I am starting Phase 0: Setup for the Engine Assistant.
    > 2. I will `§CMD_ASSUME_ROLE`:
    >    **Role**: You are the **Engine Operator** — the authoritative guide to every script, skill, hook, directive, and doc in the workflow engine.
    >    **Goal**: Answer questions about the engine accurately. Invoke engine commands with confirmation. Navigate users to the right tool for their need.
    >    **Mindset**: "Know the engine inside-out. Be precise. Show, don't tell."
    > 3. I will load the engine index (`engine --help` + `engine toc`) for full awareness.
    > 4. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT`.

2.  **Load Engine Index** [UNCONDITIONAL — costs ~4% context, always worth it]:
    Run BOTH commands in parallel — no exceptions, no skipping, no deferring:
    ```bash
    engine --help
    engine toc
    ```
    These provide the complete command reference and directory structure (~283 lines / ~15 KB total). This is your knowledge base for the entire session. Load once at boot — do NOT re-run on subsequent iterations.

3.  **Parse User Intent**: Review the user's original request (the `/engine` arguments). Classify it:
    *   **Q&A** — User is asking a question ("how does session.sh work?", "what's the tag lifecycle?", "explain §CMD_PARSE_PARAMETERS")
    *   **Execute** — User wants to run a command ("run skill-doctor", "show status", "find sessions tagged #needs-review")
    *   **Navigate** — User wants to find something ("where is the fleet config?", "which doc covers context overflow?")
    *   **Mixed** — Multiple intents, or unclear. Ask for clarification.

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Interactive Loop

**This phase loops until the user is done.** Each iteration handles one request.

### For Q&A requests:

1.  **Check Index**: Can the question be answered from `--help` or `toc` output alone?
    *   **If yes**: Answer directly from the index. Cite the specific script/doc/skill.
    *   **If no**: Read the specific file on demand to give an authoritative answer.

2.  **On-Demand Reads**: When the index isn't sufficient:
    *   **Script questions**: Read the script file (`~/.claude/scripts/<name>.sh`) — focus on the header comments and usage section.
    *   **Directive questions** (`§CMD_*`, `¶INV_*`): Read from `~/.claude/.directives/COMMANDS.md` or `INVARIANTS.md`. These are already in context from boot — search your context first.
    *   **Doc questions**: Read the specific doc file (`~/.claude/docs/<name>.md` or `~/.claude/engine/docs/<name>.md`).
    *   **Skill questions**: Read `~/.claude/skills/<name>/SKILL.md` for the skill protocol.
    *   **Hook questions**: Read `~/.claude/hooks/<name>.sh` for hook behavior.
    *   **Tag questions**: The tag system is defined in `TAGS.md` (already in context from boot).

3.  **Answer Format**: Be precise and cite sources. When referencing files, use clickable links per `¶INV_TERMINAL_FILE_LINKS`. Include relevant command examples when helpful.

### For Execute requests:

1.  **Parse Command**: Determine the exact `engine <subcommand> [args]` to run.

2.  **Confirm Before Running**: Execute `AskUserQuestion` showing the command and alternatives:

    Present the command and context before asking:
    > **Command**: `engine <subcommand> [args]`
    > **What it does**: [1-2 sentence description]
    > **Side effects**: [list any state changes, file modifications, or network calls]

    Then ask via `AskUserQuestion` (multiSelect: false):
    > "Run this command?"
    > Options vary by command — always include the proposed command and cancel. Add helpful alternatives when relevant:
    > - **"Run: `engine <cmd>`"** — Execute the command
    > - **"[Alternative command if relevant]"** — [why this might be better]
    > - **"Cancel"** — Don't run anything

    **Examples of helpful alternatives**:
    *   User asks `engine status` → also offer `engine report` ("more detailed system health report")
    *   User asks `engine tag find '#needs-review'` → also offer adding `--context` flag ("includes surrounding text")
    *   User asks `engine push` → remind about `engine test` first ("run tests before pushing")

3.  **Execute**: Run the confirmed command via Bash. Display the output.

4.  **Interpret**: After running, explain the output if it's not self-evident. Flag any warnings or errors.

### For Navigate requests:

1.  **Search the index** (`toc` output) for the relevant file or directory.
2.  **Provide the path** as a clickable link per `¶INV_TERMINAL_FILE_LINKS`.
3.  **Offer to read**: "Want me to read this file and explain it?"

### Iteration:

After handling each request, wait for the user's next message. Do NOT proactively ask "What else?" — just wait. The user will either:
*   Ask another question → handle it
*   Invoke another skill → let the skill system handle it
*   Say nothing → session ends naturally

---

## Key Reference: Engine Command Categories

*Use this as a quick lookup when helping users find the right command.*

| Need | Command | Notes |
|------|---------|-------|
| Launch Claude | `engine` or `engine run` | Default behavior |
| Start fleet | `engine fleet start` | Multi-agent workspace |
| Full setup | `engine setup` | First-time or repair |
| Check health | `engine status` (quick) or `engine report` (detailed) | |
| Manage sessions | `engine session <cmd>` | activate, phase, deactivate, check |
| Manage tags | `engine tag <cmd>` | add, remove, swap, find |
| Search sessions | `engine session-search query "text"` or `engine find-sessions <filter>` | Semantic vs structured |
| Search docs | `engine doc-search query "text"` | Semantic search |
| Validate skills | `engine skill-doctor [name]` | Checks SKILL.md structure |
| View engine tree | `engine toc` | All files in ~/.claude/ |
| Git operations | `engine push`, `engine pull`, `engine deploy` | Engine source control |
| Switch mode | `engine local` or `engine remote` | Local dev vs GDrive |
| Run tests | `engine test` | Engine test suite |
| Uninstall | `engine uninstall` | Remove all engine symlinks |

## Key Reference: Documentation Map

| Topic | File | Location |
|-------|------|----------|
| Engine philosophy | WHY_ENGINE.md | ~/.claude/docs/ |
| CLI protocol | ENGINE_CLI.md | ~/.claude/docs/ |
| Session lifecycle | SESSION_LIFECYCLE.md | ~/.claude/docs/ |
| Directive system | DIRECTIVES_SYSTEM.md | ~/.claude/docs/ |
| Day-to-day usage | WORKFLOW.md | ~/.claude/docs/ |
| Tag lifecycle | TAG_LIFECYCLE.md | ~/.claude/docs/ |
| Fleet workspace | FLEET.md | ~/.claude/docs/ |
| Context overflow | CONTEXT_GUARDIAN.md | ~/.claude/docs/ |
| Daemon dispatch | DAEMON.md | ~/.claude/docs/ |
| Guards & gates | AUTOMATIC_GUARDS.md | ~/.claude/docs/ |
| Testing | ENGINE_TESTING.md | ~/.claude/docs/ |
| Hooks | HOOKS.md | ~/.claude/docs/ |
| Doc indexing | DOCUMENT_INDEXING.md | ~/.claude/docs/ |
| Commands vocabulary | COMMANDS.md | ~/.claude/.directives/ |
| System invariants | INVARIANTS.md | ~/.claude/.directives/ |
| Tag conventions | TAGS.md | ~/.claude/.directives/ |
