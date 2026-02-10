### §CMD_DELEGATE
**Definition**: Write a delegation REQUEST file, apply the appropriate tag, and execute the chosen delegation mode (async, blocking, or silent).
**Trigger**: Called by the `/delegation-create` skill after mode selection. Not called directly by agents.

**Algorithm**:

1.  **Resolve Template**: Execute `session.sh request-template '#needs-X'` to get the REQUEST template for the target skill. If no template exists, use a generic format:
    ```markdown
    # Request: [topic]
    **Tags**: #needs-[noun]
    ## Context
    [surrounding text from tag source]
    ## Expectations
    [derived from context]
    ```

2.  **Pre-fill REQUEST**: Populate the template from current context:
    *   **Topic**: From the tagged item's surrounding text (nearest heading + paragraph).
    *   **Relevant Files**: From the session's `contextPaths` or recently-read files.
    *   **Expectations**: Derived from the tagged item and its context.
    *   **Requesting Session**: Current session directory path.
    *   **Requester**: Agent name or fleet pane ID (from `.state.json`).

3.  **Write REQUEST**: Write the populated template to the current session directory:
    *   **Filename**: `[SKILL_UPPER]_REQUEST_[TOPIC].md` (e.g., `IMPLEMENTATION_REQUEST_AUTH_VALIDATION.md`)
    *   **Location**: Always the current session directory (the requester's session).
    *   **Tool**: Use the Write tool (not log.sh -- this is a new file, not an append).

4.  **Tag REQUEST**: Apply the lifecycle tag to the REQUEST file:
    ```bash
    engine tag add "$REQUEST_FILE" '#needs-X'
    ```

5.  **Execute by Mode**:

    **Async Mode** ("Delegate -- worker will notify"):
    *   No further action. The REQUEST file + tag is sufficient.
    *   A pool worker (or manual user) discovers via `tag.sh find '#needs-X'` and processes it.
    *   Report to user: "REQUEST filed at `[path]`. Worker will process and notify via `#done-X`."

    **Blocking Mode** ("Await result from worker now"):
    *   Start background watcher:
        ```bash
        Bash("engine await-tag [REQUEST_FILE] '#done-X'", run_in_background=true)
        ```
    *   Report to user: "REQUEST filed at `[path]`. Awaiting `#done-X`..."
    *   Auto-degradation: If the current session dies before resolution, the REQUEST + tag persist. A pool worker can still pick it up (degrades to async).

    **Silent Mode** ("Spawn sub-agent to do it silently"):
    *   Determine `subagent_type` from tag noun:

        | Tag Noun | subagent_type |
        |----------|--------------|
        | implementation | builder |
        | research | researcher |
        | brainstorm | general-purpose |
        | chores | builder |
        | documentation | writer |
        | review | reviewer |

    *   Launch Task tool:
        ```
        Task(subagent_type="[type]", prompt="Execute this delegation request:\n[REQUEST content]\n\nWrite your response to: [RESPONSE_FILE_PATH]")
        ```
    *   On completion:
        -   Read the subagent's output
        -   Swap tag on REQUEST: `tag.sh swap "$REQUEST_FILE" '#needs-X' '#done-X'`
        -   Write RESPONSE breadcrumb if subagent didn't (link back to REQUEST)
    *   Report summary to user.

**Constraints**:
*   **Self-Contained** (`¶INV_REQUEST_IS_SELF_CONTAINED`): The REQUEST file must contain ALL context needed for execution. Do not reference "see the current session" -- include the relevant details inline.
*   **Single Location**: REQUEST files always go in the requester's session directory. RESPONSE files go in the worker's (new) session directory.
*   **Tag First**: Apply the tag AFTER writing the file. The file must exist before tagging.
*   **No Session Activation**: This command does not activate or create sessions. It operates within the caller's active session.
*   **Idempotent Tagging**: `tag.sh add` is idempotent -- safe to re-run.
