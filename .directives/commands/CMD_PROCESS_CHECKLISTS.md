### ¶CMD_PROCESS_CHECKLISTS
**Definition**: During synthesis, processes all discovered CHECKLIST.md files — reads each checklist, fills checkboxes based on session work, then submits full content as JSON to `engine session check` for strict validation. The engine reads the original files from disk and compares via text diff after normalizing checkboxes. Ensures the deactivation gate (`¶INV_CHECKLIST_BEFORE_CLOSE`) will pass.
**Algorithm**:
1.  **Check for Discovered Checklists**: Read `.state.json` field `discoveredChecklists` (array of absolute paths).
    *   If the array is empty or missing, skip silently. Return control to the caller.
2.  **Check for Already-Passed**: Read `.state.json` field `checkPassed`.
    *   If `checkPassed` is `true`, skip silently (already validated).
3.  **For Each Discovered Checklist**:
    a.  **Read**: Load the CHECKLIST.md file content.
    b.  **Evaluate**: Review each item in the checklist against the session's work:
        *   If the item was addressed by this session → mark `[x]`.
        *   If the item was NOT addressed → leave `[ ]`.
        *   For branching checklists (items with 2-space indented children): check exactly ONE parent branch and ALL its children.
    c.  **CRITICAL — Reproduce Faithfully**: The agent MUST reproduce the EXACT text of every checklist item. The ONLY change allowed is toggling `[ ]` to `[x]`. Do NOT:
        *   Modify item text (even slightly — "unit tests" → "tests" will fail)
        *   Omit items
        *   Add items
        *   Reorder items
        *   Add annotations, comments, or evidence text after items
    d.  **Present Summary**: Output a brief summary in chat. File path per `¶INV_TERMINAL_FILE_LINKS`:
        > **Checklist processed**: cursor://file/ABSOLUTE_PATH
        > - Checked: [N] items
        > - Unchecked: [N] items
    e.  **Log**: Append to the session's `_LOG.md`:
        ```bash
        engine log [sessionDir]/[LOG_NAME].md <<'EOF'
        ## 📋 Checklist Processed
        *   **File**: [absolute path]
        *   **Items**: [total] total — [checked] checked, [unchecked] unchecked
        EOF
        ```
4.  **Submit as JSON to engine session check**: Build a JSON object keyed by absolute file path, with values being the full checklist markdown content (with `[x]` filled). Pipe to `engine session check`:
    ```bash
    engine session check [sessionDir] <<'EOF'
    {
      "/absolute/path/to/CHECKLIST.md": "- [x] Item one\n- [x] Item two\n- [ ] Item three",
      "/absolute/path/to/OTHER_CHECKLIST.md": "- [x] All items verified"
    }
    EOF
    ```
    *   On success: `engine session check` sets `checkPassed=true` in `.state.json`. The deactivation gate will pass.
    *   On failure: `engine session check` exits 1 with a descriptive error. Fix the content and retry.
5.  **Report Pending Items**: If any checklist items are marked `[ ]` (unchecked), flag them:
    *   Add a brief mention in the debrief's "Next Steps" section.
    *   If significant, tag with `#needs-implementation` via `§CMD_TAG_FILE`.

**JSON Schema** (stdin to `engine session check`):
```json
{
  "/absolute/path/to/CHECKLIST.md": "full markdown content with [x] filled"
}
```
*   **Keys**: Absolute paths matching entries in `discoveredChecklists[]` from `.state.json`.
*   **Values**: The complete checklist markdown content. Must be a faithful reproduction of the original with only checkbox state changed.
*   **All discovered paths must be present**: Missing keys cause validation failure.

**Validation Pipeline** (what `engine session check` does):
1.  Parse JSON — must be a valid JSON object
2.  For each discovered checklist path:
    a.  Verify the path exists as a key in the JSON
    b.  Extract the agent's content from the JSON value
    c.  Read the original CHECKLIST.md from disk
    d.  Run branching validation on agent's content (if nested checkboxes detected)
    e.  Normalize both versions: `[x]`/`[X]`/`[ ]` → `[ ]`, trim trailing whitespace, CRLF→LF
    f.  Compare normalized versions — any difference = failure

**Constraints**:
*   **Non-blocking on empty**: Skip silently if no discovered checklists. Only process when checklists exist.
*   **Strict text diff**: The engine compares the normalized original against the normalized agent content. Any non-checkbox text difference causes failure. This prevents agents from omitting items, changing text, or fabricating content.
*   **Branching validation**: For checklists with nested items (2-space indented children), exactly one parent branch must be checked, and all children of the checked parent must also be checked.
*   **Belt-and-suspenders**: This command is the "belt" (protocol-level). The `engine session deactivate` gate is the "suspenders" (infrastructure-level). Both exist because agents skip protocol steps — the gate catches failures.
*   **Session state**: `checkPassed` (boolean) in `.state.json` is the source of truth. The deactivate gate checks `checkPassed == true` when `discoveredChecklists` is non-empty.
*   **Idempotent**: Safe to run multiple times. If `checkPassed` is already true, skips (step 2).
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — brief checklist summary, no micro-narration of the validation steps.

---

## PROOF FOR §CMD_PROCESS_CHECKLISTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "checklistsProcessed": {
      "type": "string",
      "description": "Count and names of checklists processed"
    },
    "itemsChecked": {
      "type": "string",
      "description": "Count of items marked [x] (e.g., '8 of 10 checked')"
    },
    "itemsUnchecked": {
      "type": "string",
      "description": "Count and scope of unchecked items (e.g., '2 unchecked: docs, e2e tests')"
    }
  },
  "required": ["executed", "checklistsProcessed"],
  "additionalProperties": false
}
```
