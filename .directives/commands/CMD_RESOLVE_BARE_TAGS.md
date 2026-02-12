### §CMD_RESOLVE_BARE_TAGS
**Description**: Handles bare inline lifecycle tags reported by `engine session check` during synthesis. For each bare `#needs-*` / `#claimed-*` / `#done-*` tag found in session artifacts, the agent presents a promote/acknowledge menu and processes the user's choices.
**Trigger**: Called when `engine session check` exits 1 with `¶INV_ESCAPE_BY_DEFAULT` violations.

**Algorithm**:
1.  **Run check**: Execute `engine session check [sessionDir] < /dev/null`. If exit 0, skip (no bare tags).
2.  **Parse output**: Extract bare tag entries from stderr (format: `file:line: #tag — context`).
3.  **Present menu**: For each bare tag, execute `AskUserQuestion` (multiSelect: false):
    > "Bare inline tag found: `#tag` in `file:line`"
    > - **"Promote"** — Create a REQUEST file from the skill's template + backtick-escape the inline tag in-place
    > - **"Acknowledge"** — Tag is intentional, leave it bare (agent logs the acknowledgment)
    > - **"Escape"** — Just backtick-escape it (no request file needed, it was a reference not a work item)
4.  **Execute choice**:
    *   **Promote**: (a) Read the skill's `TEMPLATE_*_REQUEST.md` from `~/.claude/skills/[tag-noun]/assets/`. (b) Populate the template with context from the inline tag's surrounding text. (c) Write the request file to the session directory. (d) Backtick-escape the inline tag in the source file.
    *   **Acknowledge**: Log the acknowledgment to `_LOG.md`. No file changes.
    *   **Escape**: Backtick-escape the tag in the source file. No request file.
5.  **Mark complete**: After all tags are processed, execute `engine session update [sessionDir] tagCheckPassed true`.
6.  **Re-run check**: Execute `engine session check [sessionDir]` again (with stdin for checklists if applicable). Should now pass.

**Constraints**:
*   This command runs BEFORE `§CMD_GENERATE_DEBRIEF` — debrief cannot be written until tags are resolved.
*   The `tagCheckPassed` field in `.state.json` persists across re-runs — once set, the tag scan is skipped.
*   If no per-skill request template exists for the tag's noun, use a generic format: `# Request: [topic]\n**Tags**: #needs-[noun]\n## Context\n[surrounding text]`.
