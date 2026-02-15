### ¶CMD_CAPTURE_SIDE_DISCOVERIES
**Definition**: At synthesis, scans the session log for side-discovery entries and presents a multichoice menu — letting the user tag discoveries for future work.
**Classification**: SCAN

**Algorithm**:
1.  **Read Debrief Scan Output**: The `engine session debrief` output (run once at the start of N.3 per `§CMD_RUN_SYNTHESIS_PIPELINE`) contains a `## §CMD_CAPTURE_SIDE_DISCOVERIES (N)` section with pre-scanned results. Read the count and line references from this section. Do NOT re-scan the log yourself.
    *   The engine scans for these emoji prefixes: 👁️ (observation), 😟 (concern), 🗑️ (parking lot), 🅿️ (parking lot alt), 🩺 (doc observation).
    *   If count is 0: skip silently. Return control to the caller. Do NOT prompt the user.
2.  **If Discoveries Found (count > 0)**: Read the referenced log lines to extract context. Present via `AskUserQuestion` (multiSelect: true):
    *   `question`: "These side discoveries were logged during the session. Tag any for future work?"
    *   `header`: "Discoveries"
    *   `options` (up to 4, batch if more):
        *   For each discovery: Label = `"[emoji] [summary]"`, Description = `"[first detail line]"`
    *   If more than 4 discoveries, present in batches. After the first batch, ask "More discoveries?" with the remaining items.
5.  **On Selection**: Chunk the selected discoveries into fixed groups of **4** (matching `AskUserQuestion`'s max of 4 questions per call). Last group gets the remainder (1-3 discoveries). For each group:

    1.  **Context Blocks (per-discovery, single chat message)**: Output ALL discoveries' context in one message. Each discovery gets an ID per the Item IDs convention (SIGILS.md § Item IDs). Format: `{phase}/{discovery}` — e.g., if side discoveries are captured during synthesis sub-phase 5.3, the first discovery is `5.3/1`:

        > **{itemId}**: [emoji] [summary]
        >
        > **Context**: [1-2 sentences — what was observed, where, why it matters]

    2.  **Present Options (multi-question)**: One `AskUserQuestion` call with up to 4 questions (one per discovery). Each question is single-select (multiSelect: false):
        *   **Question text**: `"[discovery summary]?"` or `"{itemId}: [summary]?"`
        *   **Header per question**: The discovery's item ID — e.g., `"5.3/1"`, `"5.3/2"`.
        *   **Descriptive labels** (per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`): Option labels MUST include the `#needs-X` tag and describe the specific action for THIS discovery. Do NOT use generic labels — customize to the discovery content.
        *   **Options per question** (example — adapt labels/descriptions to each discovery):
            *   label=`"#needs-implementation: [specific change]"`, description=`"[why this matters]"`
            *   label=`"#needs-research: [specific question]"`, description=`"[what we'd learn]"`
            *   label=`"#needs-brainstorm: [specific choice]"`, description=`"[what's at stake]"`
            *   `"Skip"` — Don't tag this one after all

    3.  **On Selection**: Process each discovery's answer independently. Apply tags for non-skipped items (step 6). Move to next group after all answers processed.
6.  **Apply Tags**: For each tagged discovery:
    *   Add the tag to the debrief file's `**Tags**:` line via `§CMD_TAG_FILE`:
        ```bash
        engine tag add "[sessionDir]/[DEBRIEF].md" '#needs-implementation'
        ```
    *   Also write the discovery as an inline tag in the debrief's "Side Discoveries" or "Btw, I also noticed..." section (if it exists), or append a new `## Tagged Discoveries` section:
        ```markdown
        ## Tagged Discoveries
        *   [emoji] [summary] #needs-implementation
        *   [emoji] [summary] #needs-research
        ```
7.  **Report**: Log the tagging to the session's `_LOG.md`:
    ```bash
    engine log [sessionDir]/[LOG_NAME].md <<'EOF'
    ## 🏷️ Side Discoveries Tagged
    *   **Discoveries found**: [N]
    *   **Tagged**: [N] ([list of tags applied])
    *   **Skipped**: [N]
    EOF
    ```

**Constraints**:
*   **Non-blocking on empty**: Skip silently if no discoveries. Only prompt when there are actionable items.
*   **Tag to debrief only**: Tags are written to the debrief file (the canonical session artifact), not to the log. The log gets an audit entry.
*   **Batching (Step 4 — discovery selection)**: If more than 4 discoveries, present in batches of 4 per `AskUserQuestion`'s option limit. Offer "More items..." as the 4th option in each batch.
*   **Batching (Step 5 — tag selection)**: Chunk selected discoveries into fixed groups of 4 (matching `AskUserQuestion`'s max questions per call). One multi-question call per group, each question single-select. Last group gets remainder (1-3 items).
*   **Follow-up on demand**: If a tag selection requires additional context or sub-options, fire a follow-up `AskUserQuestion` for that specific discovery before moving to the next group.
*   **No double-tagging**: Check if the debrief already has the proposed tag before adding (idempotent).
*   **Discovery → Resolution pipeline**: Once tagged, discoveries become discoverable by `engine tag find` which routes them to the appropriate resolving skill per `§TAG_DISPATCH` (e.g., `#needs-implementation` → `/implement`, `#needs-research` → `/research`, `#needs-brainstorm` → `/brainstorm`). This closes the loop: session work → log discovery → tag → resolve.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and option labels; bare tags only on `**Tags**:` lines or intentional inline placement in the debrief.

---

## PROOF FOR §CMD_CAPTURE_SIDE_DISCOVERIES

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "discoveriesFound": {
      "type": "string",
      "description": "Count and types of discoveries found in log"
    },
    "discoveriesTagged": {
      "type": "string",
      "description": "Count and tags applied (e.g., '2 tagged: #needs-impl, #needs-research')"
    }
  },
  "required": ["executed"],
  "additionalProperties": false
}
```
