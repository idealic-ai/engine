---
name: summarize-progress
description: "Generates a progress report summarizing work across sessions. Triggers: \"summarize progress\", \"generate progress report\", \"what was done today\", \"status update across sessions\"."
version: 2.0
tier: lightweight
---

Generates a progress report summarizing work across sessions.
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

# Progress Summarization Protocol
*Lightweight -- no session directory, no log, no plan, no debrief. Scans sessions, calibrates with the user, writes a report to `reports/`.*

## Voice & Audience

**This report is for the team** -- engineers, designers, stakeholders. Write like you're sharing exciting momentum at an all-hands, not filing a technical log. The reader should finish thinking "wow, a lot happened" and feel the forward motion.

**Tone**: Bold, product-oriented, progressive. This is a highlight reel of what moved, not an engineering changelog. Lead with outcomes and user-facing impact. Save implementation details for the "Lessons" section -- and even there, tell stories, not specs.

**Rules**:
*   Narrative over enumeration. Tell the story of what happened and why it matters.
*   **Product-first language**: "Users can now toggle between..." not "Added a React component that...". "The comparison flow works end-to-end" not "Fixed a regex route handler bug."
*   No file paths, no git commits, no session-by-session breakdowns, no code snippets.
*   No listing sessions at the end -- the report speaks for itself.
*   No implementation-level bug descriptions (regex bugs, type cast errors, schema validation failures). Translate these into product impact: "Connecting two documents for the first time revealed integration gaps that were invisible in single-document mode."
*   Use the "why / what changed / the surprise" pattern for major objectives. Minor items get one-line table entries.
*   Analogies are good. Jargon is bad (unless the audience is all engineers).
*   **Target length**: ~80-120 lines. Dense paragraphs, not sprawling bullet lists.
*   Top 4-6 objectives get the full narrative pattern. The rest are brief entries in the objectives table.
*   **Energy**: The executive summary should feel like momentum. What phase did we enter? What capability unlocked? What shifted from "designed" to "real"?

---

## 1. Discovery

**Execute immediately** to get the file manifest for sessions active in the time window:

```bash
engine find-sessions active --files
```

Use `since` or `window` if the user specifies a custom time range:
```bash
engine find-sessions since '2026-02-03 06:00' --files
engine find-sessions window '2026-02-03 06:00' '2026-02-04 02:00' --files
```

**Then**: Load `~/.claude/skills/summarize-progress/assets/TEMPLATE_PROGRESS_SUMMARY.md` if not already in context.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - find-sessions.sh executed: `________`
> - Session manifest obtained: `________`
> - Template loaded: `________`

---

## 2. Scope

*   **Input**: Check if the user provided a specific time range.
*   **Defaults**: If not provided:
    *   **Start Time**: 6:00 AM today. (If currently 00:00-06:00, use 6:00 AM yesterday.)
    *   **End Time**: Now.
*   **Present**: Show the file manifest filtered to the time window as a table of sessions (name + artifact count + time range). NOT a raw file list.
*   **Confirm**: Present times, ask the user to confirm or adjust. Wait for approval.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Time range: `________`
> - Manifest presented: `________`
> - User confirmed: `________`

---

## 3. Ingest

Read all session artifacts (debriefs, logs, plans) modified within the confirmed time window.

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Artifacts read: `________`
> - Debriefs/logs/plans loaded: `________`

---

## 4. Calibrate
*Before writing, validate framing with the user.*

1.  **Synthesize**: Identify major themes, 4-6 narrative objectives, war stories, gaps.
2.  **Present a Proposed Structure** (NOT a draft):
    *   "Themes: [A, B, C]"
    *   "Full narrative: [1, 2, 3, 4]"
    *   "Brief table entries: [5, 6, 7]"
    *   "War stories: [X, Y]"
    *   "Anything I'm missing?"
3.  **Wait**: Stop. Let the user steer before writing.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Themes identified: `________`
> - Structure presented: `________`
> - User feedback: `________`

---

## 5. Write Report

1.  **Compose**: Fill out `TEMPLATE_PROGRESS_SUMMARY.md` using the user's calibration feedback + loaded context. Follow Voice & Audience rules.
2.  **Save**: Write to `reports/PROGRESS_SUMMARY_[YYYY_MM_DD].md`.
3.  **Report**: State the output path as a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant). Done.

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Report written (template fidelity): `________`
> - Voice rules followed: `________`
> - File saved: `________` (real file path)
> - Path reported: `________`

**Note**: This is a lightweight utility. The report IS the output. No debrief file.
