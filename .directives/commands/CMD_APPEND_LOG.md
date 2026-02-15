### ¶CMD_APPEND_LOG
**Definition**: Logs are Append-Only streams.
**Constraint**: **BLIND WRITE**. You will not see the file content. Trust the append. See `¶INV_TRUST_CACHED_CONTEXT`.
**Constraint**: **TIMESTAMPS**. `engine log` auto-injects `[YYYY-MM-DD HH:MM:SS]` into the first `## ` heading. Do NOT include timestamps manually.

**Algorithm**:
1.  **Reference**: Look at the loaded `[SESSION_TYPE]_LOG.md` schema in your context.
2.  **Construct**: Prepare Markdown content matching that schema. Use `## ` headings (no timestamp — `engine log` adds it).
3.  **Execute**:
    ```bash
    $ engine log sessions/[YYYY_MM_DD]_[TOPIC]/[LOG_NAME].md <<'EOF'
    ## [Header/Type]
    *   **Item**: ...
    *   **Details**: ...
    EOF
    ```
    *   The script auto-prepends a blank line, creates parent dirs, auto-injects timestamp into first `## ` heading, and appends content.
    *   In append mode, content MUST contain a `## ` heading or `engine log` will error (exit 1).
    *   Whitelisted globally via `Bash(engine *)` — no permission prompts.

**Forbidden Patterns (DO NOT DO)**:
*   **The "Read-Modify-Write"**: Reading the file, adding text in Python/JS, and writing it back.
*   **The "Placeholder Hunt"**: Looking for `{{NEXT_ENTRY}}`.

---

## PROOF FOR §CMD_APPEND_LOG

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "logEntries": {
      "type": "string",
      "description": "Count and topics of log entries appended"
    }
  },
  "required": ["logEntries"],
  "additionalProperties": false
}
```
