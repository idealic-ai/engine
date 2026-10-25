### ¶CMD_TAG_FILE
**Definition**: To add a semantic tag to a Markdown file.
**Constraint**: Tags live on a dedicated `**Tags**:` line immediately after the H1 heading (line 2). Never on the H1 itself.
**Format**: `**Tags**: #tag1 #tag2`
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag add "$FILE" '#tag-name'
    ```
    *   Ensures `**Tags**:` line exists after H1, then appends tag idempotently.
    *   Safe to run multiple times.
