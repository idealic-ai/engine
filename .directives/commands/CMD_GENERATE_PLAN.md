### §CMD_GENERATE_PLAN
**Definition**: Creates a standardized plan artifact.
**Algorithm**:
1.  **Execute**: `§CMD_WRITE_FROM_TEMPLATE` using the `_PLAN.md` schema found in context.
2.  **Report**: `§CMD_LINK_FILE`.

---

## PROOF FOR §CMD_GENERATE_PLAN

```json
{
  "plan_written": {
    "type": "string",
    "description": "Filename of the plan written to the session directory",
    "examples": ["IMPLEMENTATION_PLAN.md", "FIX_PLAN.md", "TESTING_PLAN.md"]
  },
  "plan_presented": {
    "type": "string",
    "description": "How the plan was presented to the user",
    "examples": ["cursor://file link shared", "plan echoed to chat"]
  }
}
```
