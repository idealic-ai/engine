### ¶CMD_GENERATE_PLAN
**Definition**: Creates a standardized plan artifact.
**Algorithm**:
1.  **Execute**: `§CMD_WRITE_FROM_TEMPLATE` using the `_PLAN.md` schema found in context.
2.  **Report**: `§CMD_LINK_FILE`.

**Constraints**:
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in the plan report MUST be clickable URLs.

---

## PROOF FOR §CMD_GENERATE_PLAN

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "planWritten": {
      "type": "string",
      "description": "Filename of the plan written to the session directory"
    },
    "planPresented": {
      "type": "string",
      "description": "How the plan was presented to the user"
    }
  },
  "required": ["planWritten", "planPresented"],
  "additionalProperties": false
}
```
