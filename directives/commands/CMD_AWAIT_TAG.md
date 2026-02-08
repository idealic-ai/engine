### §CMD_AWAIT_TAG
**Definition**: Start a background watcher that blocks until a specific tag appears on a file or in a directory. Uses `fswatch` for event-driven detection (no polling). Fires an OS notification when resolved.
**Dependency**: Requires `fswatch` (`brew install fswatch`).

**Algorithm (File Mode — watch a specific request file)**:
1.  **Launch**: Start the watcher in the background:
    ```bash
    Bash("~/.claude/scripts/await-tag.sh <file> '<tag>'", run_in_background=true)
    ```
    *   Example: `await-tag.sh sessions/.../RESEARCH_REQUEST_AUTH.md '#done-research'`
2.  **Continue**: The agent keeps working on other tasks. The watcher runs silently.
3.  **Receive**: When the tag appears (e.g., research completes with `#done-research`), the background task completes. The agent receives the result on its next turn.

**Algorithm (Directory Mode — watch for any tag appearance)**:
1.  **Launch**:
    ```bash
    Bash("~/.claude/scripts/await-tag.sh --dir <path> '<tag>'", run_in_background=true)
    ```
    *   Example: `await-tag.sh --dir sessions/ '#done-research'`
2.  **Continue/Receive**: Same as file mode.

**Use Cases**:
*   After launching research (`research.sh`), await `#done-research` on the request file.
*   Monitor for newly completed work: `--dir sessions/ '#done-implementation'`.

**Constraints**:
*   The watcher dies when the session ends. Cross-session durability is handled by the tag system itself (`§TAG_DISPATCH` routing or `SessionStart` hook).
*   The agent is NOT required to start a watcher. It is opt-in — useful when the agent has other work to do while waiting.
