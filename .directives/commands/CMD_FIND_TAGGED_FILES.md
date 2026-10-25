### ¶CMD_FIND_TAGGED_FILES
**Definition**: To locate files carrying specific semantic tags (on the Tags line or as intentional inline tags), filtering out backtick-escaped references.
**Algorithm**:
1.  **Identify**: Determine the target tag (e.g., `#needs-review`).
2.  **Execute**:
    ```bash
    engine tag find '#tag-name'
    ```
    *   Searches `sessions/` by default. Pass a path argument to override.
    *   Two-pass search: Tags line (high precision) + inline body (backtick-filtered).
    *   Add `--context` for line numbers and surrounding text (useful before `remove --inline` or `swap --inline`).
3.  **Output**: A list of file paths (one per line) that carry the tag. Each path should be a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant).
4.  **Goal**: Identify active alerts, pending reviews, or other tagged artifacts.
