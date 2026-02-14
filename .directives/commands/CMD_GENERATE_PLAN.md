### §CMD_GENERATE_PLAN
**Definition**: Creates a standardized plan artifact.
**Algorithm**:
1.  **Execute**: `§CMD_WRITE_FROM_TEMPLATE` using the `_PLAN.md` schema found in context.
2.  **Report**: `§CMD_LINK_FILE`.

---

## PROOF FOR §CMD_GENERATE_PLAN

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "plan_written": {
      "type": "string",
      "description": "Filename of the plan written to the session directory"
    },
    "plan_presented": {
      "type": "string",
      "description": "How the plan was presented to the user"
    }
  },
  "required": ["plan_written", "plan_presented"],
  "additionalProperties": false
}
```
