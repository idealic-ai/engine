---
name: delegate-request
description: "Posts a structured request for another agent session to pick up and fulfill. Triggers: \"post a delegation request\", \"request help from another session\", \"create a delegation request\"."
version: 2.0
---

Posts a structured request for another agent session to pick up and fulfill.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/standards/COMMANDS.md`, `~/.claude/standards/INVARIANTS.md`, and `~/.claude/standards/TAGS.md`.
2. LOAD PROJECT STANDARDS: Read `.claude/standards/INVARIANTS.md`.
3. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
4. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`
> - Project INVARIANTS.md: `________ or N/A`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Delegation Request Protocol (Utility Command)
*Lightweight — no log, no plan. Creates a request file and exits.*

## 1. Setup
1.  **Template**: The `~/.claude/skills/delegate-request/assets/TEMPLATE_DELEGATION_REQUEST.md` template is your schema.
2.  **Session Dir**: You MUST already be in an active session (via `§CMD_MAINTAIN_SESSION_DIR`). If not, ask the user which session to attach this request to.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Template path: `________`
> - Active session dir: `________`

---

## 2. Interrogation (Brief)
*Gather enough to populate the template. Do not over-interrogate.*

**Action**: Use `AskQuestion` to collect:
1.  **Topic**: What is being requested? (Becomes the `[TOPIC]` in the filename.)
2.  **Expectations**: What should the responding agent deliver?
3.  **Acceptance Criteria**: How will we know it's done?
4.  **Context**: Any relevant files, docs, or constraints?

**Constraint**: If the agent already has this information from the current session context (e.g., it discovered a dependency mid-work), skip the interrogation and populate directly.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Topic: `________`
> - Expectations: `________`
> - Acceptance criteria: `________`
> - Context: `________`

---

## 3. Execution
1.  **Create**: Populate the `~/.claude/skills/delegate-request/assets/TEMPLATE_DELEGATION_REQUEST.md` template with the topic, expectations, acceptance criteria, and context.
2.  **Write**: Save as `DELEGATION_REQUEST_[TOPIC].md` in the current session directory. `[TOPIC]` is UPPER_SNAKE_CASE, concise.
3.  **Tag**: Add `#needs-delegation` to the file:
    ```bash
    ~/.claude/scripts/tag.sh add "$FILE" '#needs-delegation'
    ```
4.  **Report**: State "Delegation request posted: [link]" where [link] is a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant).
5.  **Await (Optional)**: If the agent has other work to do in this session, offer to start a background watcher:
    > "Want me to watch for the response while I continue working?"
    *   If yes: Execute `§CMD_AWAIT_TAG` (file mode) on the request file for `#done-delegation`.
    *   If no: Skip — the tag system provides cross-session durability via `/dispatch`.
6.  **Done**: End turn. No debrief, no log.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Template populated: `________`
> - File written: `________`
> - File tagged: `________`
> - Posting reported: `________`
