---
name: delegate-respond
description: "Picks up and completes work from an existing delegation request. Triggers: \"respond to a delegation\", \"fulfill a delegation request\", \"answer an open delegation\"."
version: 2.0
---

Picks up and completes work from an existing delegation request.
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

# Delegation Respond Protocol (Utility Command)
*Lightweight — no log, no plan. Discovers open delegation requests, posts responses, and exits.*

## 1. Setup
1.  **Template**: The `~/.claude/skills/delegate-respond/assets/TEMPLATE_DELEGATION_RESPONSE.md` template is your schema.
2.  **Session Dir**: You MUST already be in an active session (via `§CMD_MAINTAIN_SESSION_DIR`). If not, ask the user which session to attach responses to.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Template path: `________`
> - Active session dir: `________`

---

## 2. Discovery
**Action**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
*   Search `sessions/` for all `#needs-delegation` files.
*   If none found: Report "No open delegation requests found." and end turn.
*   If found: Read each request file to understand what is being asked.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Search for #needs-delegation: `________`
> - Results: `________`

---

## 3. Relevance Assessment
*For each discovered request, determine if the current session's work addresses it.*

**Action**: Present the list to the agent (or user if invoked standalone):
*   **Request**: `[File path]` — [1-line summary of what's requested]
*   **Relevance**: [Relevant / Not Relevant / Partially Relevant]

**Constraint**: If invoked standalone (not mid-session), ask the user which requests to respond to.
**Constraint**: If invoked mid-session by another command, the agent decides relevance based on its current work scope.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Requests assessed: `________`
> - Relevant requests: `________`

---

## 4. Response (For Each Relevant Request)
1.  **Populate**: Fill the `~/.claude/skills/delegate-respond/assets/TEMPLATE_DELEGATION_RESPONSE.md` template with:
    *   What was done to address the request.
    *   Acceptance criteria status (mirror the request's criteria).
    *   Verification details.
2.  **Execute**: `§CMD_POST_DELEGATION_RESPONSE` — write the response file, append breadcrumb to request, swap tag.
3.  **Report**: State "Delegation response posted: [response link] -> addresses [request link]" where links are clickable per `¶INV_TERMINAL_FILE_LINKS` (Full variant).

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Templates populated: `________`
> - Response files written: `________`
> - Tags swapped: `________`
> - Breadcrumbs appended: `________`
> - Posting reported: `________`

---

## 5. Done
End turn. No debrief, no log.
