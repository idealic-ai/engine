### ¶CMD_REPORT_ARTIFACTS
**Definition**: Final summary step to list all files created or modified.
**Rule**: Must be executed at the very end of a session/task.
**Algorithm**:
1.  **Identify**: List all files created or modified during this session (Logs, Plans, Debriefs, Code).
2.  **Format**: Create a Markdown list where each path is a clickable link per `¶INV_TERMINAL_FILE_LINKS`. Use **Full** display variant (relative path as display text).
3.  **Output**: Print this list to the chat under the header "## Generated Artifacts".

**Constraints**:
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in the artifact list MUST be clickable URLs.

---

## PROOF FOR §CMD_REPORT_ARTIFACTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "artifactsListed": {
      "type": "string",
      "description": "Count and types of artifacts listed (e.g., '5 files: log, plan, debrief, 2 source')"
    }
  },
  "required": ["executed", "artifactsListed"],
  "additionalProperties": false
}
```
