### §CMD_GENERATE_PLAN
**Definition**: Creates a standardized plan artifact.
**Algorithm**:
1.  **Execute**: `§CMD_WRITE_FROM_TEMPLATE` using the `_PLAN.md` schema found in context.
2.  **Report**: `§CMD_LINK_FILE`.
