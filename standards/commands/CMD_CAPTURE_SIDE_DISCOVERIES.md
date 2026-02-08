### §CMD_CAPTURE_SIDE_DISCOVERIES
**Definition**: At synthesis, scans the session log for side-discovery entries and presents a multichoice menu — letting the user tag discoveries for future dispatch via `/dispatch`.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 10, after `§CMD_MANAGE_TOC` and before `§CMD_REPORT_LEFTOVER_WORK`.

**Algorithm**:
1.  **Locate Log File**: Find the session's `*_LOG.md` file (e.g., `IMPLEMENTATION_LOG.md`, `DOC_UPDATE_LOG.md`).
    *   If no log file exists, skip silently.
2.  **Scan for Side-Discovery Entries**: Search the log for entries with these emoji prefixes:
    *   👁️ **Observation** — things noticed while working (code smells, patterns, surprises)
    *   😟 **Concern** — worries about performance, security, architecture
    *   🗑️ **Parking Lot** — deferred items explicitly set aside during the session
    *   🩺 **Observation** (document skill variant) — same as 👁️, different emoji
    *   Extract the entry's header line (summary) and the first bullet point (detail/context).
3.  **If No Discoveries Found**: Skip silently. Return control to the caller. Do NOT prompt the user.
4.  **If Discoveries Found**: Present via `AskUserQuestion` (multiSelect: true):
    *   `question`: "These side discoveries were logged during the session. Tag any for future work?"
    *   `header`: "Discoveries"
    *   `options` (up to 4, batch if more):
        *   For each discovery: Label = `"[emoji] [summary]"`, Description = `"[first detail line]"`
    *   If more than 4 discoveries, present in batches. After the first batch, ask "More discoveries?" with the remaining items.
5.  **On Selection**: For each selected discovery, ask which tag to apply via `AskUserQuestion` (multiSelect: false):
    *   `question`: "What type of work does '[discovery summary]' need?"
    *   `header`: "Tag type"
    *   **Descriptive labels** (per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`): Option labels MUST include the `#needs-X` tag and describe the specific action for THIS discovery. Do NOT use generic labels — customize to the discovery content.
    *   `options` (example — adapt labels/descriptions to each discovery):
        *   label=`"#needs-implementation: [specific change]"`, description=`"[why this matters]"`
        *   label=`"#needs-research: [specific question]"`, description=`"[what we'd learn]"`
        *   label=`"#needs-decision: [specific choice]"`, description=`"[what's at stake]"`
        *   `"Skip"` — Don't tag this one after all
6.  **Apply Tags**: For each tagged discovery:
    *   Add the tag to the debrief file's `**Tags**:` line via `§CMD_TAG_FILE`:
        ```bash
        ~/.claude/scripts/tag.sh add "[sessionDir]/[DEBRIEF].md" '#needs-implementation'
        ```
    *   Also write the discovery as an inline tag in the debrief's "Side Discoveries" or "Btw, I also noticed..." section (if it exists), or append a new `## Tagged Discoveries` section:
        ```markdown
        ## Tagged Discoveries
        *   [emoji] [summary] #needs-implementation
        *   [emoji] [summary] #needs-research
        ```
7.  **Report**: Log the tagging to the session's `_LOG.md`:
    ```bash
    ~/.claude/scripts/log.sh [sessionDir]/[LOG_NAME].md <<'EOF'
    ## 🏷️ Side Discoveries Tagged
    *   **Discoveries found**: [N]
    *   **Tagged**: [N] ([list of tags applied])
    *   **Skipped**: [N]
    EOF
    ```

**Constraints**:
*   **Non-blocking on empty**: Skip silently if no discoveries. Only prompt when there are actionable items.
*   **Tag to debrief only**: Tags are written to the debrief file (the canonical session artifact), not to the log. The log gets an audit entry.
*   **Batching**: If more than 4 discoveries, present in batches of 4 per `AskUserQuestion`'s option limit. Offer "More items..." as the 4th option in each batch.
*   **No double-tagging**: Check if the debrief already has the proposed tag before adding (idempotent).
*   **Discovery → Dispatch pipeline**: Once tagged, discoveries become discoverable by `/dispatch` which routes them to the appropriate resolving skill (`/implement`, `/research`, `/decide`). This closes the loop: session work → log discovery → tag → dispatch → resolve.
