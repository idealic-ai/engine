---
name: writeup
description: "Creates semi-permanent situational documents in project docs folders. Lightweight skill — no session, no logs, just focused writing. Triggers: \"write up\", \"writeup\"."
version: 2.0
tier: lightweight
---

Creates semi-permanent situational documents for reference. Writeups describe a current situation, explain context, and suggest improvements. Stored in `apps/*/docs/writeups/` or `packages/*/docs/writeups/`.
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

# Writeup Protocol (Lightweight Situational Documentation)

[!!!] LIGHTWEIGHT SKILL: No session directory, no log file, no tags. Just focused writing.

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structure. Use THIS protocol's phases, not the IDE's.

## 1. Setup & Discovery

**Intent**: Parse the topic and discover available destinations.

1.  **Parse Topic**: Extract the writeup topic from the user's prompt.
    *   If unclear, ask: "What topic should this writeup cover?"

2.  **Discover Destinations**: Find all `apps/` and `packages/` directories that have a `docs/` folder.
    ```bash
    ls -d apps/*/docs 2>/dev/null | sed 's|/docs||'
    ls -d packages/*/docs 2>/dev/null | sed 's|/docs||'
    ```

3.  **Ask Destination**: Use `AskUserQuestion` to present discovered locations.
    *   Options: Each discovered app/package as a choice.
    *   The selected path becomes: `<choice>/docs/writeups/`

4.  **Ensure Directory**: Create the `writeups/` subdirectory if it doesn't exist.
    ```bash
    mkdir -p <destination>/docs/writeups
    ```

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Topic parsed: `________`
> - Destinations discovered: `________`
> - User selected destination: `________`
> - writeups/ directory exists: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: RAG Keywords"** — Search for related context before writing
> - **"Skip to Phase 3: Interrogation"** — Skip RAG, go straight to clarification

---

## 2. RAG Keywords (Optional Context Discovery)

**Intent**: Offer the user keywords to search for related context.

1.  **Generate Keywords**: Based on the topic, generate 4-6 relevant search keywords.
    *   Example: Topic "extraction accuracy" → keywords: "extraction", "accuracy", "parsing", "LLM output", "validation"

2.  **Present Keywords**: Use `AskUserQuestion` with `multiSelect: true`.
    *   Header: "RAG Keywords"
    *   Question: "Select keywords to search for related context (or skip):"
    *   Options: Each keyword + a "Skip RAG" option.

3.  **Execute Searches**: For each selected keyword (if any):
    ```bash
    ~/.claude/tools/session-search/session-search.sh query "<keyword>" --limit 5
    ~/.claude/tools/doc-search/doc-search.sh query "<keyword>" --limit 5
    ```
    *   Collect unique file paths and brief descriptions.
    *   These populate the "Related" section of the writeup.

4.  **If Skipped**: Proceed without the Related section (or mark it "None").

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Keywords generated (or skipped): `________`
> - RAG searches executed (or skipped): `________`
> - Related files collected (or "None"): `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: RAG complete. How to proceed?"
> - **"Proceed to Phase 3: Interrogation"** — Clarify writeup content
> - **"Stay in Phase 2"** — Search more keywords

---

## 3. Interrogation (Brief Clarification)

**Intent**: Gather structured input for each section of the writeup.

### Interrogation Depth Selection

**Before asking questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How detailed should the clarification be?"

| Depth | Rounds | When to Use |
|-------|--------|-------------|
| **Short** | 1 round | Simple writeup, you already have context |
| **Medium** | 2 rounds | Standard writeup, some unknowns |
| **Long** | 3+ rounds | Complex topic, multiple perspectives |

Record the user's choice.

### Interrogation Topics (Writeup)
*Themes to explore during clarification.*

**Standard topics** (typically covered once):
- **Audience** — Who will read this? Technical depth needed?
- **Tone & style** — Formal/informal, opinionated/neutral?
- **Key takeaways** — What should the reader walk away knowing?
- **Structure preference** — Problem/solution, comparison, narrative?
- **Sources & citations** — What evidence or references to include?
- **Length constraints** — Brief (1 page) or comprehensive?
- **Visual aids** — Diagrams, tables, code examples needed?
- **Draft vs final** — Is this a first draft or publication-ready?

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

### Round Execution

Use `AskUserQuestion` to clarify the writeup content.

**Questions to ask** (combine into one `AskUserQuestion` call with multiple questions):

1.  **Problem**: "What's the core problem or situation to document?"
    *   Options: Free-form (let user type via "Other")

2.  **Options**: "What options or approaches exist?"
    *   Options: Provide 2-3 common patterns if detectable, plus "Other"

3.  **Recommendation**: "Do you have a preferred recommendation, or should I analyze and suggest?"
    *   Options: "I have a recommendation" / "Analyze and suggest" / "No recommendation yet"

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Clarification complete (minimum met). What next?"
> - **"Proceed to Phase 4: Writing"** — *(terminal: if selected, skip all others and move on)*
> - **"More clarification (1 more round)"** — Additional questions, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging the framing
> - **"Deep dive round"** — 1 round drilling into a specific aspect

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Interrogation depth chosen: `________`
> - Minimum rounds completed: `________`
> - User selected proceed: `________`

---

## 4. Writing

**Intent**: Generate the writeup document.

1.  **Compute Filename**:
    ```
    YYYY_MM_DD_<TOPIC_SLUG>.md
    ```
    *   `TOPIC_SLUG`: Uppercase, underscores, derived from topic (e.g., "extraction gaps" → "EXTRACTION_GAPS")

2.  **Compute Full Path**:
    ```
    <destination>/docs/writeups/YYYY_MM_DD_<TOPIC_SLUG>.md
    ```

3.  **Populate Template**: Use `§CMD_POPULATE_LOADED_TEMPLATE` with `TEMPLATE_WRITEUP.md`.
    *   **Problem**: From interrogation answer + agent analysis.
    *   **Context**: Agent synthesizes from loaded context + RAG results.
    *   **Related**: List of RAG-discovered files (if any). Format as bullet list with brief descriptions.
    *   **Options**: From interrogation + agent analysis. Present 2-3 options with trade-offs.
    *   **Recommendation**: From user preference or agent's analysis.
    *   **Next Steps**: Concrete actionable items.

4.  **Write File**: Create the document at the computed path.

5.  **Report**: Output to chat the created file path as a clickable link per `¶INV_TERMINAL_FILE_LINKS`.

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Writeup file created: `________` (real file path)
> - All template sections populated: `________`
> - File path reported: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Constraint**: No debrief, no log, no session summary. Just report the created file.

---

## Quick Reference

| Aspect | Value |
|--------|-------|
| Session | None |
| Log | None |
| Tags | None |
| Output | `<app_or_pkg>/docs/writeups/YYYY_MM_DD_TOPIC.md` |
| Template | `assets/TEMPLATE_WRITEUP.md` |
| Phases | 4 (Setup → RAG → Interrogation → Writing) |
