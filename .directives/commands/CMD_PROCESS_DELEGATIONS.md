### ¶CMD_PROCESS_DELEGATIONS
**Definition**: Scans the current session's artifacts for unresolved bare `#needs-X` inline tags and invokes `/delegation-create` for each one. This is a synthesis step that runs between `§CMD_WALK_THROUGH_RESULTS` and `§CMD_GENERATE_DEBRIEF`.
**Classification**: SCAN

**Algorithm**:

1.  **Scan**: Search the current session directory for bare inline `#needs-X` tags:
    ```bash
    engine tag find '#needs-*' --context [SESSION_DIR]
    ```
    *   This finds tags in session artifacts (log, plan, details, debrief draft).
    *   Filter to inline tags only -- skip Tags-line entries on REQUEST files (those are already delegated).

2.  **Filter Already-Delegated**: Remove tags that:
    *   Appear on REQUEST files (already delegated earlier in the session)
    *   Were placed by `§CMD_WALK_THROUGH_RESULTS` AND the walkthrough's own triage already handled them (check DETAILS.md for walk-through triage decisions)
    *   Match `#done-X` tags also present (already resolved)

3.  **Present Summary**: If unresolved tags remain, show count:
    > "Found [N] unresolved delegation tags in session artifacts. Processing each one."

    If none remain, skip silently -- output nothing and return control.

4.  **Process Each**: For each unresolved tag (file paths per `¶INV_TERMINAL_FILE_LINKS`):
    *   Extract the tag, source file, line number, and surrounding context (from `--context` output)
    *   Invoke `/delegation-create` via the Skill tool: `Skill(skill: "delegation-create", args: "[tag] [source context summary]")`
    *   `/delegation-create` handles mode selection and REQUEST filing

5.  **Report**: After all tags processed:
    > "Delegation processing complete: [N] REQUESTs filed."
    *   Log to session log:
        ```
        Delegation processing: N tags found, X delegated, Y dismissed, Z already handled.
        ```

**Constraints**:
*   **Order**: Process tags in document order (top to bottom across files). This ensures higher-priority items (closer to plan steps) are delegated first.
*   **One at a Time**: Process tags sequentially, not in batch. Each invocation of `/delegation-create` may require user interaction (mode selection, confirmation).
*   **Skip Silently**: If no unresolved tags are found, return immediately without any chat output. Do not announce "no delegations found."
*   **Filter Aggressively**: Avoid re-delegating items that were already handled by walkthrough triage or earlier `/delegation-create` invocations in the same session.
*   **Tags-line vs Inline**: Only process INLINE tags. Tags on the `**Tags**:` line of a file are structural metadata, not delegation candidates (they're already discoverable by `engine tag find`).
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and log entries; bare tags only on `**Tags**:` lines or intentional inline.

---

## PROOF FOR §CMD_PROCESS_DELEGATIONS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "tagsFound": {
      "type": "string",
      "description": "Count and types of tags found (e.g., '3 tags: 2 #needs-impl, 1 #needs-research')"
    },
    "requestsFiled": {
      "type": "string",
      "description": "Count of REQUEST files created (e.g., '2 REQUESTs filed')"
    }
  },
  "required": ["executed", "tagsFound"],
  "additionalProperties": false
}
```
