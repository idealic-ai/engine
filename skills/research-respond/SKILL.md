---
name: research-respond
description: "Checks and retrieves completed research results from Gemini Deep Research. Triggers: \"fulfill a research request\", \"check research results\", \"poll Gemini for research results\"."
version: 2.0
tier: lightweight
---

Checks and retrieves completed research results from Gemini Deep Research.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Research Respond Protocol (Utility Command)
*Lightweight — no log, no plan. Finds an open research request, calls Gemini, posts the result.*

## 1. Setup
1.  **Template**: The `~/.claude/skills/research-respond/assets/TEMPLATE_RESEARCH_RESPONSE.md` template is your schema.
2.  **Session Dir**: You MUST already be in an active session (via `§CMD_MAINTAIN_SESSION_DIR`). If not, ask the user which session to use.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Template loaded: `________`
> - Active session dir: `________`

---

## 2. Discovery
*Find open or abandoned research requests.*

1.  **Execute**: `§CMD_FIND_TAGGED_FILES` for both `#needs-research` and `#active-research` across `sessions/`.
    *   `#needs-research` — never started. Will need full query composition + API call.
    *   `#active-research` — started but abandoned (previous session died). The request file contains an `## Active Research` section with the Interaction ID. Can resume by polling the existing interaction.
2.  **If none found**: Report "No open research requests." and stop.
3.  **If one found**: Present it to the user for confirmation.
4.  **If multiple found**: Present the list with status (new vs abandoned). User picks one.
5.  **Read**: Read the selected request document fully.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Tag search executed: `________`
> - Request selected: `________`
> - Request document read: `________`

---

## 3. Compose Query
*Build the research prompt from the structured request.*

1.  **Extract** from the request document:
    *   The **Query** (Section 1)
    *   The **Context** (Section 2)
    *   The **Constraints** (Section 3)
    *   The **Expected Output** (Section 4)
    *   The **Previous Research Interaction ID** (Section 6 — may be "None")
2.  **Compose**: Synthesize these fields into a coherent research prompt. Include all constraints and context to guide Gemini's research. The prompt should read as a complete research brief.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Sections extracted: `________`
> - Research prompt composed: `________`
> - Previous Interaction ID: `________`

---

## 4. Execute Research
*Call the Gemini Deep Research API.*

1.  **Determine output path**: `[session-dir]/RESEARCH_RESPONSE_[TOPIC].md.tmp` (temporary — will be replaced by the final document).
2.  **Execute** (background):
    *   **If initial request** (Interaction ID = None):
        ```bash
        engine research <output-path> <<'EOF'
        [composed research prompt]
        EOF
        ```
    *   **If follow-up** (Interaction ID present):
        ```bash
        engine research --continue <interaction-id> <output-path> <<'EOF'
        [composed follow-up prompt]
        EOF
        ```
    *   Run with `run_in_background: true`.
3.  **Poll**: Check the output file periodically (Read tool). When content appears, proceed.
4.  **Parse**: Read the output file. Line 1 is `INTERACTION_ID=<id>`. Remaining lines are the report.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - research.sh executed: `________`
> - Output received: `________`
> - INTERACTION_ID parsed: `________`
> - Report content extracted: `________`

---

## 5. Post Response
*Write the response document and update the original request.*

1.  **Create**: Populate `~/.claude/skills/research-respond/assets/TEMPLATE_RESEARCH_RESPONSE.md`:
    *   Set **Gemini Interaction ID** from parsed output.
    *   Set **Original Request** path.
    *   Paste the full report into Section 2.
2.  **Write**: Save as `RESEARCH_RESPONSE_[TOPIC].md` in the current session directory.
3.  **Tag**: The template already includes `#done-research` in the Tags line.
4.  **Breadcrumb**: Append to the **original request** file:
    ```bash
    engine log "$REQUEST_FILE" <<'EOF'
    ## Response
    *   **Responded By**: `[RESPONSE_FILE_PATH]`
    *   **Date**: [YYYY-MM-DD HH:MM:SS]
    *   **Gemini Interaction ID**: `[interaction-id]`
    *   **Status**: Complete
    EOF
    ```
5.  **Swap Tag**: On the original request:
    ```bash
    engine tag swap "$REQUEST_FILE" '#needs-research' '#done-research'
    ```
6.  **Cleanup**: Delete the `.tmp` output file if it exists.
7.  **Report**: State "Research complete: [link]. Interaction ID: `[id]`." where [link] is a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant).
8.  **Done**: End turn. No debrief, no log. The response document IS the output.

### §CMD_VERIFY_PHASE_EXIT — Phase 5 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Response written: `________`
> - Breadcrumb appended: `________`
> - Tag swapped: `________`
> - .tmp cleaned: `________`
> - Completion reported: `________`
