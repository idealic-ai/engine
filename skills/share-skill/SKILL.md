---
name: share-skill
description: "Promotes a project-local skill to the shared engine on Google Drive. Triggers: \"share this skill\", \"promote skill to shared engine\", \"push skill to Google Drive\", \"share command globally\"."
version: 2.0
---

Promotes a project-local skill to the shared engine on Google Drive.
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

# Share Command Protocol (The Promotion Gate)

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. My focus is SHARE_SKILL (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all standards are loaded.
    > 4. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Release Gatekeeper**.
    >    **Goal**: To safely promote a project-local skill to the shared engine, ensuring nothing is overwritten without explicit consent.
    >    **Mindset**: Shared means permanent. Treat every promotion like a deploy to production.
    > 5. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:

3.  **Parse Arguments**: Extract the skill name from the user's input.
    *   **Input**: `/share-skill <skill-name>`
    *   **Normalize**: Convert to kebab-case if not already.
    *   **Derive**: `PROMPT_NAME` = uppercase + underscores (e.g., `my-skill` -> `MY_SKILL`).

4.  **Resolve Engine Path**:
    *   The shared engine lives on Google Drive. Resolve the path:
        ```
        ~/Library/CloudStorage/GoogleDrive-*/Shared drives/*/engine/
        ```
    *   **Algorithm**: Use `ls` with the glob pattern above to find the engine directory. There should be exactly one match.
    *   *If no match*: STOP. Report "Cannot find engine directory on Google Drive. Is Google Drive synced?"
    *   *If multiple matches*: STOP. Report the matches and ask user to specify which one.
    *   **Output**: Display the resolved path as a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant):
        > **Engine Path**: [link]

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Skill name: `________`
> - PROMPT_NAME: `________`
> - Engine path: `________`

---

## 2. Inventory Phase
*Identify all files that belong to this skill.*

1.  **Scan project-local files**: Check `.claude/skills/` for all files associated with the skill:
    *   `.claude/skills/<skill-name>/SKILL.md` -- The skill file (contains frontmatter and protocol)
    *   `.claude/skills/<skill-name>/assets/TEMPLATE_*.md` -- Templates (debrief, log, plan, etc.)

2.  **Build file manifest**: List which files exist locally.
    *   *If no local files found*: STOP. Report "No local skill found for `<skill-name>`. Nothing to share."

3.  **Scan engine counterparts**: For each local file found, check if an engine counterpart exists:
    *   `[engine]/skills/<skill-name>/SKILL.md`
    *   `[engine]/skills/<skill-name>/assets/TEMPLATE_*.md`

4.  **Display manifest**:
    ```
    File Manifest for `<skill-name>`:

    | File | Local | Engine | Action |
    |------|-------|--------|--------|
    | skills/<name>/SKILL.md | Y/N | Y/N | New / Overwrite |
    | skills/<name>/assets/TEMPLATE_<X>.md | Y/N | Y/N | New / Overwrite / Skip |
    ```

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Local skill scanned: `________`
> - Engine counterparts checked: `________`
> - Manifest displayed: `________`

---

## 3. Diff Phase
*For files that will OVERWRITE existing engine files, produce a structural comparison.*

**Constraint**: Only diff files where both local and engine versions exist (Action = "Overwrite"). Skip files where the action is "New".

For each file being overwritten:

1.  **Read** both the local version and the engine version.
2.  **Structural comparison**:
    *   **For SKILL.md**: Compare frontmatter (description, version). Compare phase structure (list phases in each version). Report added/removed/reordered phases. Report changed roles, mindsets, or §CMD_ references.
    *   **For templates**: Compare section headers (H2/H3). Report added/removed sections. Report changed placeholder text.
3.  **Output** a summary per file (file paths as clickable links per `¶INV_TERMINAL_FILE_LINKS`):
    ```
    ### Changes: skills/<name>/SKILL.md
    *   **Phases**: Added "Phase 4: Validation" (not in engine version)
    *   **Removed**: "Phase 3: Deep Dive" renamed to "Phase 3: Investigation"
    *   **Role**: Changed from "Research Analyst" to "Senior Investigator"
    *   **New CMD refs**: Added `§CMD_VALIDATE_DEBRIEF`
    ```

*If NO files are being overwritten (all "New")*: Skip this phase entirely and note "All files are new -- no overwrites."

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Overwrite diffs displayed: `________` or `all files are new`

---

## 4. Confirmation Gate
*The user MUST explicitly approve before any files are copied.*

**Display the full action summary**:
```
SHARE CONFIRMATION

Skill:  <skill-name>
Engine: [engine path]

Files to COPY (new):
  - skills/<name>/SKILL.md
  - skills/<name>/assets/TEMPLATE_<X>.md

Files to OVERWRITE:
  - skills/<name>/SKILL.md (see diff above)

Files UNCHANGED (no local version):
  - (none)
```

**Ask** (via `§CMD_ASK_ROUND_OF_QUESTIONS`):
> "Do you want to proceed with sharing `<skill-name>` to the engine?"
> Options: "Yes, share it" / "No, abort"

*If user aborts*: Report "Share cancelled. No files were modified." and END.

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Action summary displayed: `________`
> - User approved: `________`

---

## 5. Copy Phase
*Execute the file copy operations.*

1.  **Create directories** if needed:
    ```bash
    mkdir -p [engine]/skills/<skill-name>/assets
    ```

2.  **Copy each file** from `.claude/skills/` to the engine directory:
    ```bash
    cp .claude/skills/<name>/SKILL.md [engine]/skills/<name>/SKILL.md
    cp .claude/skills/<name>/assets/TEMPLATE_*.md [engine]/skills/<name>/assets/
    # ... (only files that exist locally)
    ```

3.  **Verify** each copy succeeded by checking the destination file exists and has the same size as the source.

4.  **Report** each copy using `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Files copied: `________`
> - Each copy verified: `________`

---

## 6. Post-Copy Verification
*Ensure the engine is consistent after the copy.*

1.  **Check engine README**: Read `[engine]/skills/README.md` (if it exists).
    *   If the skill is NOT in the skill reference table: Ask the user if they want to add it.
    *   If it IS already in the table: Check if the description matches the frontmatter. Update if different.

2.  **Verify symlinks**: Check that `~/.claude/skills/<skill-name>/SKILL.md` resolves correctly (it should, since symlinks point to GDrive and we just updated GDrive).

3.  **Report**:
    ```
    Share complete.

    - [N] files copied to engine
    - Symlinks verified: ~/.claude/skills/<name>/SKILL.md -> [engine]/skills/<name>/SKILL.md
    - Engine README: [Updated / Already current / User declined / Not found]
    ```

### §CMD_VERIFY_PHASE_EXIT — Phase 6
**Output this block in chat with every blank filled:**
> **Phase 6 proof:**
> - Engine README: `________`
> - Symlinks verified: `________`
> - Final report: `________`

---

## 7. Synthesis

Execute `§CMD_REPORT_RESULTING_ARTIFACTS` -- list all files created or modified (both in engine and README).
Execute `§CMD_REPORT_SESSION_SUMMARY`.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

**Note**: This is a utility skill -- no session directory, no log, no debrief. The output is the action itself.
