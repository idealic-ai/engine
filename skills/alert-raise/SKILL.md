---
name: alert-raise
description: "Raises an alert to notify agents about active changes causing temporary breakage. Triggers: \"post an alert\", \"warn about breaking changes\", \"announce in-flight work\", \"flag intentional breakage\"."
version: 2.0
---

Raises an alert to notify agents about active changes causing temporary breakage.
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

# Alert Raise Protocol (The Context Synchronizer)

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. My focus is ALERT_RAISE (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 4. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` in this phase.
    > 5. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 6. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Senior Architect** and **Context Aggregator**.
    >    **Goal**: To analyze recent code/test changes and generate a high-quality alert document for the global feed.
    >    **Mindset**: "Clarity is Power." Your notes are the bridge between agents.
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project map and file index)
    *   `~/.claude/skills/alert-raise/assets/TEMPLATE_ALERT_LOG.md` (Template for continuous session logging)
    *   `~/.claude/skills/alert-raise/assets/TEMPLATE_ALERT_RAISE.md` (Template for the alert)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - ensure the directory is created.
5.  **Initialize Log**: Execute `§CMD_INIT_OR_RESUME_LOG_SESSION` (Template: `ALERT_LOG.md`).
6.  **Scope**: Understand the [Topic] and [Goal].

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - Templates loaded: `________`, `________`
> - Parameters parsed: `________`
> - Log initialized: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Analysis & Context Capture"** — Review changes, diffs, logs, and plans
> - **"Stay in Phase 1"** — Load additional standards or resolve setup issues

---

## 2. Analysis & Context Capture
*Review what has changed and why. Obey §CMD_THINK_IN_LOG.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: Analysis & Context Capture.
> 2. I will `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (following `assets/TEMPLATE_ALERT_LOG.md` EXACTLY) to `§CMD_THINK_IN_LOG` as I analyze the changes.
> 3. I will analyze recent diffs, logs, and plans in the session folder.
> 4. I will identify key changes in code, tests, and API.

**Action**:
1.  Read the active `_LOG.md` and `_PLAN.md` files in the session directory.
2.  If possible, use `git diff` or compare with `current_diff.txt` to see actual code changes.
3.  Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` (Schema: `ALERT_LOG.md`) for every discovery (Code, Test, Intent, Tech Debt). Capture the variety of observations here.
4.  Synthesize the "Why" and "How" of the changes.

### 🧠 Thought Triggers (When to Log)
*Review this list before every tool call. If your state matches, log it.*

*   **Found a Fact?** -> Log `🔍 Discovery` (The Fact, The Evidence).
*   **Found a Flaw?** -> Log `⚠️ Weakness` (The Risk, The Impact).
*   **Saw a Pattern?** -> Log `🔗 Connection` (Link A <-> B).
*   **Had an Idea?** -> Log `💡 Spark` (The Innovation, The Benefit).
*   **Missing Info?** -> Log `❓ Gap` (What is unknown?).

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Session files reviewed: `________`
> - Diffs analyzed: `________`
> - ALERT_LOG.md entries: `________`
> - Synthesis: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Analysis complete. How to proceed?"
> - **"Proceed to Phase 3: Alert Generation"** — Compile discoveries into the alert document
> - **"Stay in Phase 2"** — Continue analyzing, more changes to review

---

## 3. Alert Generation
*Create a high-density, token-saving alert document.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Alert Generation.
> 2. I will compile only the **CRITICAL** discoveries from the `ALERT_LOG.md` into the `ALERT_RAISE.md`.
> 3. I will focus on **Troubleshooting** and **Test Impacts** rather than an exhaustive overview.
> 4. I will `§CMD_TAG_FILE` with `#active-alert`.
> 5. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_ALERT_RAISE.md` EXACTLY).

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution**
1.  **Generate**: Execute `§CMD_POPULATE_LOADED_TEMPLATE` (Schema: `ALERT_RAISE.md`).
    *   *Constraint*: Be concise. Use bullet points. Focus on what a future agent needs to know to avoid getting stuck or breaking things.
    *   *Reference Docs*: Ensure the "Session Docs" section at the top links to the actual files present in the directory (e.g., `IMPLEMENTATION.md`, `TESTING.md`, `BRAINSTORM.md`). If a file doesn't exist, remove its link.
2.  **Tag**: Execute `§CMD_TAG_FILE` on the newly created file with `#active-alert`.
3.  **Log**: Execute `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` to record the compilation logic.
4.  **Report**: `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - ALERT_RAISE.md written: `________`
> - Tagged #active-alert: `________`
> - Session Docs links verified: `________`
> - Compilation logged: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Alert generated. How to proceed?"
> - **"Proceed to Phase 4: Finalize"** — Wrap up the session
> - **"Revise the alert"** — Go back and edit the alert before finalizing

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
> - ALERT_RAISE.md: `________` (real file path)
> - Tagged #active-alert: `________`
> - ALERT_LOG.md entries: `________`
> - Artifacts listed: `________`
> - Summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
