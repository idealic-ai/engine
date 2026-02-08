---
name: dispatch
description: Scans all #needs-* tags across sessions, groups by type, and launches the resolving skill. Triggers: "dispatch", "what needs doing", "show pending tags", "triage deferred items".
version: 2.0
---

Scans all #needs-* tags across sessions, groups by type, and launches the resolving skill.
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

# Dispatch Protocol

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup.
    > 2. My focus is DISPATCH (tag triage) (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure standards and TAGS.md are loaded.
    > 4. I will scan all `#needs-*` tags across sessions.
    > 5. I will present grouped results and let you choose what to resolve.
    > 6. I will obey `§CMD_NO_MICRO_NARRATION`.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - COMMANDS.md: `________`
> - INVARIANTS.md: `________`
> - TAGS.md with §TAG_DISPATCH: `________`

---

## 2. Scan Phase

**Action**: Scan for ALL `#needs-*` tags across sessions using `tag.sh find`.

**Algorithm**:
1.  For each dispatchable tag in the registry (see §TAG_DISPATCH in TAGS.md), run:
    ```bash
    ~/.claude/scripts/tag.sh find '#needs-TAG' sessions/ --context
    ```
2.  Collect results into groups. Skip tags with zero hits.
3.  For tags that also appear inline (like `#needs-decision`), include the inline context.

**Registry** (from §TAG_DISPATCH in TAGS.md):

| Tag | Resolving Skill | Mode |
|-----|----------------|------|
| `#needs-decision` | `/decide` | interactive |
| `#needs-research` | `/research` | async (Gemini) |
| `#needs-documentation` | `/document` | interactive |
| `#needs-review` | `/review` | interactive |
| `#needs-delegation` | `/delegate-respond` | agent |
| `#needs-rework` | `/review` | interactive |
| `#needs-implementation` | `/implement` | interactive |

If the user passed a specific tag as an argument (e.g., `/dispatch #needs-decision`), scan ONLY that tag and skip to Phase 3.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Tags scanned: `________`
> - Groups with hits: `________`
> - Zero-hit tags excluded: `________`

---

## 3. Present Phase

**Action**: Present the scan results to the user as a numbered menu.

**Format**:
```
Pending items across sessions:

1. #needs-decision    (3 items) → /decide
   - sessions/2026_02_04_SKILLS_MIGRATION/BRAINSTORM_LOG.md:42 — Architecture choice
   - sessions/2026_02_04_STABLE_IDS/BRAINSTORM_LOG.md:77 — Document types
   - sessions/2026_02_03_AUTH_FLOW/IMPLEMENTATION_LOG.md:15 — Token strategy

2. #needs-research    (1 item) → /research
   - sessions/2026_02_04_STABLE_IDS/BRAINSTORM_LOG.md:77 — Document types

3. #needs-review      (5 items) → /review
   [list files]

Pick a number to resolve, or "all" to triage everything.
```

**Rules**:
*   Show the tag, count, resolving skill, and a brief context line for each hit.
*   The context line should extract the heading or first meaningful text near the tag.
*   Use `AskUserQuestion` to let the user pick.
*   Options: Each numbered group, plus "all" (resolve sequentially), plus "skip" (done).

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Menu presented: `________`
> - Groups shown: `________`
> - User selection: `________`

---

## 4. Dispatch Phase

**Action**: Launch the selected skill with the tagged files as context.

**Algorithm**:
1.  **Single group selected**: Invoke the resolving skill using the `Skill` tool.
    *   Pass the list of tagged file paths as arguments so the skill knows what to process.
    *   Format: `/skill-name file1.md:line1 file2.md:line2 ...`
2.  **"All" selected**: Process groups sequentially in priority order:
    1.  `#needs-decision` (decisions unblock other work)
    2.  `#needs-research` (async — queue early)
    3.  `#needs-delegation` (delegate to other agents)
    4.  `#needs-implementation` (the work itself)
    5.  `#needs-documentation` (post-work docs)
    6.  `#needs-review` / `#needs-rework` (validation)
    *   After each skill completes, return to Phase 2 (re-scan) to see updated state.
    *   Offer "Continue to next?" between each.
3.  **"Skip" selected**: End dispatch.

**Async handling**: For `/research` (async via Gemini), dispatch offers:
*   "Queue research request now" — invokes `/research-request` (non-blocking)
*   "Skip (handle later)" — moves to next group

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Skills invoked: `________`
> - Priority order followed: `________`
> - Completions confirmed: `________`

---

## 5. Summary Phase

After all selected dispatches complete:

1.  **Report**: Show what was resolved:
    ```
    Dispatch complete:
    - #needs-decision: 3 items → resolved via /decide
    - #needs-research: 1 item → queued via /research-request

    Remaining:
    - #needs-review: 5 items (skipped)
    ```
2.  **Offer re-scan**: "Re-scan for remaining tags?"
3.  **Done**: If no remaining tags or user declines, end.

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Resolution report: `________`
> - Remaining items: `________`
> - Re-scan offered: `________`
