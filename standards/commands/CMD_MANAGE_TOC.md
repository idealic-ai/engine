### §CMD_MANAGE_TOC
**Definition**: After documentation work is complete, manages `docs/TOC.md` by proposing additions, description updates, and stale entry removals based on the session's file changes.
**Trigger**: Called during synthesis/post-op phases of any skill that creates, modifies, or deletes documentation files. Currently integrated into `/document` Phase 4; other skills can add it to their synthesis phases.

**Algorithm**:
1.  **Collect File Manifest**: Gather the list of documentation files touched during this session:
    *   **Created**: New files added to the project (candidates for TOC addition)
    *   **Modified**: Existing files that were updated (candidates for description refresh)
    *   **Deleted**: Files removed from the project (candidates for TOC removal)
    *   **Scope**: Only files under `docs/` or other documentation directories. Exclude session artifacts (`sessions/`), templates, and standards.
2.  **Read Current TOC**: Read `docs/TOC.md` to get the current state. If the file is empty or doesn't exist, treat all created files as new additions.
3.  **Derive Changes**: Compare the manifest against TOC.md:
    *   **Additions**: Files in manifest (created) that have no entry in TOC.md.
    *   **Updates**: Files in manifest (modified) that already have an entry in TOC.md — the description may be stale.
    *   **Removals**: Files listed in TOC.md that were deleted in this session, OR files in TOC.md that no longer exist on disk.
4.  **If No Changes**: Skip silently. Return control to the caller. Do NOT prompt the user.
5.  **If Changes Found**: Present via `AskUserQuestion` (multiSelect: true):
    *   `question`: "These documentation files were touched this session. Which TOC.md changes should I apply?"
    *   `header`: "TOC updates"
    *   `options` (up to 4, batch if more):
        *   For each addition: `"Add: path/to/file.md"` — description: `"New file. Will generate 3-line description from content."`
        *   For each update: `"Update: path/to/file.md"` — description: `"File was modified. Current TOC description may be stale."`
        *   For each removal: `"Remove: path/to/file.md"` — description: `"File no longer exists on disk."`
    *   If more than 4 items, present in batches of 4 with "More items..." option.
6.  **On Selection**: For each selected item:
    *   **Addition**:
        1.  Read the file's H1 heading and first paragraph.
        2.  Generate a 3-line description summarizing the file's purpose.
        3.  Determine the directory group (e.g., `## docs/architecture/`).
        4.  If the group header doesn't exist in TOC.md, auto-create it.
        5.  Append the entry under the correct group header:
            ```markdown
            - `path/to/file.md`
              [Line 1 of description]
              [Line 2 of description]
              [Line 3 of description]
            ```
    *   **Update**:
        1.  Read the modified file's content.
        2.  Generate a new 3-line description.
        3.  Replace the existing entry's description lines in TOC.md.
    *   **Removal**:
        1.  Remove the entry (path line + description lines) from TOC.md.
        2.  If the group header has no remaining entries, remove the header too.
7.  **Apply Changes**: Use the Edit tool to modify `docs/TOC.md`. If the file is empty, use Write to create the initial structure:
    ```markdown
    # Table of Contents

    ## [directory/]
    - `path/to/file.md`
      [Description line 1]
      [Description line 2]
      [Description line 3]
    ```
8.  **Report**: Log the changes to the active session log:
    ```
    TOC.md updated: +N added, ~N updated, -N removed.
    ```
    If no changes were selected, log: "TOC.md: no changes selected."

**TOC.md Format Convention**:
*   **Structure**: Grouped by directory, with `## directory/` headers.
*   **Entry format**: Backtick-quoted path on first line, followed by exactly 3 indented description lines.
*   **Ordering**: Groups alphabetical. Entries within groups alphabetical.
*   **Example**:
    ```markdown
    # Table of Contents

    ## docs/architecture/
    - `docs/architecture/AUTH.md`
      Authentication architecture, Clerk integration, and guard patterns.
      Covers session management, token refresh, and role-based access control.
      Last major update: auth system v2 migration.

    ## docs/concepts/
    - `docs/concepts/CLAIMS.md`
      Core domain model for insurance claims lifecycle.
      States, transitions, and business rules.
      Integration with Temporal workflows.
    ```

**Constraints**:
*   **Non-blocking**: If user selects nothing, the session continues normally.
*   **Scoped to docs/**: Only documentation files are candidates. Code files, config files, and session artifacts are excluded.
*   **Idempotent**: Check existing entries before suggesting additions to avoid duplicates.
*   **3-line descriptions**: Always exactly 3 lines. Generate from file content (H1 + first paragraph). Keep each line under 80 characters.
*   **Auto-create group headers**: New directories get headers automatically without asking.

---

## Integration Guide (For Other Skills)

Any skill that creates, modifies, or deletes documentation files can integrate TOC management by adding this call to its synthesis/post-op phase:

**Where to add**: In the synthesis phase, after the debrief is written (Step 1) and before artifact listing (Step 3). Typically as "Step 1.5" or "Step 2".

**How to call**: Add this line to the skill's synthesis phase:
```
**Step 1.5**: Execute `§CMD_MANAGE_TOC` — manage Table of Contents for documentation files touched this session.
```

**Skills that should adopt this** (when they touch docs/):
*   `/document` — Primary user (integrated in Phase 4)
*   `/implement` — When implementation includes doc file changes
*   `/debug` — When debugging reveals doc corrections needed
*   `/test` — When test sessions update testing docs
*   `/brainstorm` — When brainstorming produces new concept docs

**Adoption is optional**: The command skips silently if no documentation files were touched. Adding the call to a skill's protocol has zero overhead for sessions that don't touch docs.
