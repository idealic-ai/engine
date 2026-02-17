### ¶CMD_RESOLVE_BARE_TAGS
**Definition**: Handles bare inline lifecycle tags reported by `engine session check` during synthesis. For each bare `#needs-*` / `#claimed-*` / `#done-*` tag found in session artifacts, the agent presents a promote/acknowledge menu and processes the user's choices.
**Algorithm**:
1.  **Run check**: Execute `engine session check [sessionDir] < /dev/null`. If exit 0, skip (no bare tags).
2.  **Parse output**: Extract bare tag entries from stderr (format: `file:line: #tag — context`).
3.  **Present menu**: For each bare tag (or in batches of up to 4), invoke §CMD_DECISION_TREE with `§ASK_BARE_TAG_TRIAGE`. Use preamble context to show the tag, file path (per `¶INV_TERMINAL_FILE_LINKS`), and surrounding context.
4.  **Execute choice** (by tree path):
    *   **`PRO`** (Promote): (a) Read the skill's `TEMPLATE_*_REQUEST.md` from `~/.claude/skills/[tag-noun]/assets/`. (b) Populate the template with context from the inline tag's surrounding text. (c) Write the request file to the session directory. (d) Backtick-escape the inline tag in the source file.
    *   **`ACK`** (Acknowledge): Log the acknowledgment to `_LOG.md`. No file changes.
    *   **`ESC`** (Escape): Backtick-escape the tag in the source file. No request file.
    *   **`MORE/DROP`** (Delete): Remove the tag and surrounding context entirely.
    *   **`MORE/MOV`** (Move to Tags line): Remove inline tag, add to the file's `**Tags**:` line via `§CMD_TAG_FILE`.
5.  **Mark complete**: After all tags are processed, execute `engine session update [sessionDir] tagCheckPassed true`.
6.  **Re-run check**: Execute `engine session check [sessionDir]` again (with stdin for checklists if applicable). Should now pass.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   This command runs BEFORE `§CMD_GENERATE_DEBRIEF` — debrief cannot be written until tags are resolved.
*   The `tagCheckPassed` field in `.state.json` persists across re-runs — once set, the tag scan is skipped.
*   If no per-skill request template exists for the tag's noun, use a generic format: `# Request: [topic]\n**Tags**: #needs-[noun]\n## Context\n[surrounding text]`.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and menu labels; bare tags only on `**Tags**:` lines or in `engine tag` commands.

---

### ¶ASK_BARE_TAG_TRIAGE
Trigger: when bare inline lifecycle tags are found during synthesis check (except: when no bare tags found — check passes automatically)
Extras: A: View tag context with surrounding lines | B: Batch-process all tags with same action | C: Show which file each tag is in

## Decision: Bare Tag Triage
- [SEND] Promote
  Create a REQUEST file from the tag + backtick-escape inline
- [KEEP] Acknowledge
  Tag is intentional — leave it bare, log acknowledgment
- Escape
  Backtick-escape it — was a reference, not a work item
- [DROP] Delete tag entirely
  Remove the tag and surrounding context
- Move to Tags line
  Relocate from inline to the file's Tags line

---

## PROOF FOR §CMD_RESOLVE_BARE_TAGS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "bareTagsFound": {
      "type": "string",
      "description": "Count and types of bare tags found"
    },
    "tagsPromoted": {
      "type": "string",
      "description": "Count and targets of promoted tags (e.g., '2 promoted to REQUEST files')"
    },
    "tagsEscaped": {
      "type": "string",
      "description": "Count of tags backtick-escaped in place"
    }
  },
  "required": ["executed"],
  "additionalProperties": false
}
```
