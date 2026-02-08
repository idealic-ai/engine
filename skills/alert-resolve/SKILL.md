---
name: alert-resolve
description: "Resolves a previously raised alert once associated work is complete and stable. Triggers: \"resolve an alert\", \"mark alert as done\", \"close a changeset warning\", \"clear an active alert\"."
version: 2.0
---

Resolves a previously raised alert once associated work is complete and stable.
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

# Resolve Protocol (The Alignment Enforcer)

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. My focus is ALERT_RESOLVE (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 4. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 5. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 6. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Quality Control** and **Release Manager**.
    >    **Goal**: To validate all active alerts, ensure alignment, and finalize the session work.
    >    **Mindset**: "Zero Ambiguity." Nothing leaves this phase without being verified and documented.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md` (For the final debrief)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS`.
4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR`.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - TEMPLATE_IMPLEMENTATION.md loaded: `________`
> - Parameters parsed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Discovery & Validation"** — Find and review all active alerts
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Discovery & Validation
*Find and review all active alerts.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Discovery & Validation.
> 2. I will `§CMD_FIND_TAGGED_FILES` to find the `#active-alert` tag.
> 3. I will review each alert for completeness and test status.

**Action**:
1.  Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert` across `sessions/`.
2.  Read all found alert files.
3.  Verify that the changes described are indeed implemented and tested.
4.  **STOP**: If any alert seems incomplete or contradictory, ask the user for clarification using `§CMD_ASK_ROUND_OF_QUESTIONS`.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Alerts found: `________`
> - Alert files reviewed: `________`
> - Implementation verified: `________`
> - Contradictions resolved: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Discovery complete. How to proceed?"
> - **"Proceed to Phase 3: Resolution & Archiving"** — Untag alerts and generate Master Debrief
> - **"Stay in Phase 2"** — More validation needed, continue reviewing

---

## 3. Resolution & Archiving
*Finalize the changes and clear the active tags.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Resolution & Archiving.
> 2. I will `§CMD_UNTAG_FILE` to remove `#active-alert` from all resolved documents.
> 3. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_IMPLEMENTATION.md` EXACTLY) to create a "Master Debrief".

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution**
1.  **Untag**: For each alert file: Execute `§CMD_UNTAG_FILE` for `#active-alert`.
2.  **Debrief**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Schema: `IMPLEMENTATION.md`) to create a "Master Debrief" for the session.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Alerts untagged: `________`
> - Master Debrief written: `________`
> - Debrief references alerts: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Resolution complete. How to proceed?"
> - **"Proceed to Phase 4: Finalize"** — Wrap up the session
> - **"Stay in Phase 3"** — Revise debrief or re-check tags

---

## 4. Finalize
*Wrap up the session.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Finalize.
> 2. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 3. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**Action**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS`.
**Summarize**: Execute `§CMD_REPORT_SESSION_SUMMARY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 4 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Master Debrief: `________` (real file path)
> - Alerts untagged: `________`
> - Artifacts listed: `________`
> - Summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
