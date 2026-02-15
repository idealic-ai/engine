### ¶CMD_CLOSE_SESSION
**Definition**: After synthesis is complete, transitions the session to idle state. Handles debrief gate verification, session description, keyword inference, and the idle transition. The post-idle routing menu is handled separately by `§CMD_PRESENT_NEXT_STEPS`.
**Algorithm**:
0.  **Debrief Gate** (`¶INV_CHECKLIST_BEFORE_CLOSE` pattern): Verify the skill's debrief file exists (e.g., `IMPLEMENTATION.md` for `/implement`, `ANALYSIS.md` for `/analyze`). This is mechanically enforced — the debrief must exist before proceeding.
    *   **When Blocked**: Write the debrief via `§CMD_GENERATE_DEBRIEF`, then retry.
    *   **Skip**: If the user explicitly approves skipping, quote the user's actual words as the reason. The agent MUST use `AskUserQuestion` to get user approval before skipping. Agent-authored justifications are not valid.
    *   **Prohibited justifications** (these are never valid reasons to skip the debrief):
        *   "Small focused change — no debrief needed."
        *   "This task was too simple for a debrief."
        *   "The changes are self-explanatory."
        *   Any reason authored by the agent without user input.
    *   **Valid reasons** (these require the user to have actually said it):
        *   `"Reason: User said 'skip the debrief, just close it'"`
        *   `"Reason: User said 'discard this session'"`
        *   `"Reason: User abandoned session early — said 'never mind, move on'"`
1.  **Compose Description**: Write a 1-3 line summary of what was accomplished in this session. Focus on *what changed* and *why*, not process details.
2.  **Infer Keywords**: Based on the session's work, infer 3-5 search keywords that capture the key topics, files, and concepts. These power future RAG discoverability.
    *   *Example*: For a session that refactored auth middleware: `"auth, middleware, ClerkAuthGuard, session-management, NestJS"`
    *   Keywords should be comma-separated, concise, and specific to this session's work.
3.  **Transition to Idle**: Execute `engine session idle` (NOT `deactivate`). This sets `lifecycle=idle`, clears PID (null sentinel), stores description + keywords, and runs a RAG search returning related sessions in stdout.
    ```bash
    engine session idle <session-dir> --keywords 'kw1,kw2,kw3' <<'EOF'
    What was accomplished in this session (1-3 lines)
    EOF
    ```
4.  **Process RAG Results**: If the idle command returned a `## Related Sessions` section in stdout, display it in chat. This gives the user awareness of related past work.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **Session description is REQUIRED**: `engine session idle` will ERROR if no description is piped.
*   **Keywords are RECOMMENDED**: If omitted, idle still works but the session is less discoverable.
*   **No routing**: This command does NOT present skill menus or handle user routing. That is `§CMD_PRESENT_NEXT_STEPS`.
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration of the idle transition steps.

---

## PROOF FOR §CMD_CLOSE_SESSION

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "sessionIdled": {
      "type": "string",
      "description": "Idle outcome (e.g., 'idled with 5 keywords')"
    },
    "descriptionWritten": {
      "type": "string",
      "description": "Description summary (e.g., 'wrote 2-line summary')"
    }
  },
  "required": ["sessionIdled", "descriptionWritten"],
  "additionalProperties": false
}
```
