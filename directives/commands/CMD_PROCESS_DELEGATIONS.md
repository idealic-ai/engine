### §CMD_PROCESS_DELEGATIONS
**Definition**: Scans the current session's artifacts for unresolved bare `#needs-X` inline tags and invokes `/delegate` for each one. This is a synthesis step that runs between `§CMD_WALK_THROUGH_RESULTS` and `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`.
**Trigger**: Called during skill synthesis phases. Positioned after walkthrough (which places tags) and before debrief (which captures final state).

**Algorithm**:

1.  **Scan**: Search the current session directory for bare inline `#needs-X` tags:
    ```bash
    engine tag find '#needs-*' --context [SESSION_DIR]
    ```
    *   This finds tags in session artifacts (log, plan, details, debrief draft).
    *   Filter to inline tags only -- skip Tags-line entries on REQUEST files (those are already delegated).

2.  **Filter Already-Delegated**: Remove tags that:
    *   Appear on REQUEST files (already delegated earlier in the session)
    *   Were placed by `§CMD_WALK_THROUGH_RESULTS` AND the walkthrough's own triage already handled them (check DETAILS.md for walk-through triage decisions)
    *   Match `#done-X` tags also present (already resolved)

3.  **Present Summary**: If unresolved tags remain, show count:
    > "Found [N] unresolved delegation tags in session artifacts. Processing each one."

    If none remain, skip silently -- output nothing and return control.

4.  **Process Each**: For each unresolved tag:
    *   Extract the tag, source file, line number, and surrounding context (from `--context` output)
    *   Invoke `/delegate` via the Skill tool: `Skill(skill: "delegate", args: "[tag] [source context summary]")`
    *   `/delegate` handles mode selection and REQUEST filing

5.  **Report**: After all tags processed:
    > "Delegation processing complete: [N] REQUESTs filed."
    *   Log to session log:
        ```
        Delegation processing: N tags found, X delegated, Y dismissed, Z already handled.
        ```

**Constraints**:
*   **Order**: Process tags in document order (top to bottom across files). This ensures higher-priority items (closer to plan steps) are delegated first.
*   **One at a Time**: Process tags sequentially, not in batch. Each invocation of `/delegate` may require user interaction (mode selection, confirmation).
*   **Skip Silently**: If no unresolved tags are found, return immediately without any chat output. Do not announce "no delegations found."
*   **Filter Aggressively**: Avoid re-delegating items that were already handled by walkthrough triage or earlier `/delegate` invocations in the same session.
*   **Tags-line vs Inline**: Only process INLINE tags. Tags on the `**Tags**:` line of a file are structural metadata, not delegation candidates (they're already discoverable by `tag.sh find`).
