### ¶CMD_SWAP_TAG_IN_FILE
**Definition**: To atomically replace one tag with another (e.g., `#needs-review` → `#done-review`).
**Algorithm**:
1.  **Execute**:
    ```bash
    engine tag swap "$FILE" '#old-tag' '#new-tag'
    ```
    *   Supports comma-separated old tags for multi-swap: `'#tag-a,#tag-b'`
