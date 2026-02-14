### §CMD_GENERATE_DEBRIEF
**Definition**: Creates or regenerates a standardized debrief artifact.
**Algorithm**:
1.  **Check for Continuation**: Is this a continuation of an existing session (user chose "Continue existing" via `§CMD_MAINTAIN_SESSION_DIR`, or continued post-synthesis via `§CMD_RESUME_AFTER_CLOSE`)?
    *   **If continuation**: Read the **full log file** (original + continuation entries) to capture the complete session history. The debrief must reflect ALL work done, not just the latest round.
    *   **If fresh**: Proceed normally with current context.
2.  **Execute**: `§CMD_WRITE_FROM_TEMPLATE` using the `.md` schema found in context.
    *   **Continuation Note**: The debrief **replaces** any existing debrief file. Do NOT append — regenerate the entire document so it reads as one coherent summary of all work.
3.  **Tag**: Include a `**Tags**: #needs-review` line immediately after the H1 heading. This marks the debrief as unvalidated and discoverable by `/review`.
    *   *Example*:
        ```markdown
        # Implementation Debriefing: My Feature
        **Tags**: #needs-review
        ```
    *   **Note**: Do NOT auto-add `#needs-documentation`. Documentation tags are applied manually by the user when needed, not auto-applied to every debrief.
5.  **Related Sessions**: If `ragDiscoveredPaths` was populated during context ingestion (session-search found relevant past sessions), include a `## Related Sessions` section in the debrief:
    ```markdown
    ## Related Sessions
    *   `sessions/2026_01_15_AUTH_REFACTOR/IMPLEMENTATION.md` — Similar auth implementation
    *   `sessions/2026_01_10_CLERK_SETUP/ANALYSIS.md` — Initial Clerk research
    ```
    *   Only include sessions (not code files). Link to the debrief or most relevant artifact.
    *   This creates a knowledge graph — future sessions can trace lineage.
6.  **Report**: `§CMD_LINK_FILE`. If this was a regeneration, say "Updated `[path]`" not "Created".
7.  **Reindex Search DBs**: *Handled automatically by `engine session deactivate`.* No manual action needed.

**Note**: Steps 8-15 (pipeline orchestration, deactivation) have been extracted to `§CMD_RUN_SYNTHESIS_PIPELINE`. This command now only handles debrief file creation (steps 1-7).

---

## PROOF FOR §CMD_GENERATE_DEBRIEF

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "debrief_file": {
      "type": "string",
      "description": "Filename of the debrief written to the session directory"
    },
    "debrief_tags": {
      "type": "string",
      "description": "Tags applied to the debrief file"
    }
  },
  "required": ["debrief_file", "debrief_tags"],
  "additionalProperties": false
}
```
