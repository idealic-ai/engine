### §CMD_PROMPT_INVARIANT_CAPTURE
**Definition**: After debrief creation, reviews the conversation for insights worth capturing as permanent invariants and prompts the user to add them.
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 8, after debrief is written.

**Algorithm**:
1.  **Review Conversation**: Scan the session for insights that could become invariants:
    *   Repeated corrections or clarifications from the user
    *   "Always do X" / "Never do Y" patterns that emerged
    *   Friction points that led to learnings
    *   New constraints discovered during implementation
    *   Mistakes that should be prevented in future sessions
2.  **Check for Candidates**: Identify up to 5 potential invariants. For each, draft:
    *   A name following the `¶INV_NAME` convention (e.g., `¶INV_CACHE_BEFORE_LOOP`)
    *   A one-line rule summary
    *   A reason explaining why this matters
3.  **If No Candidates**: Skip silently. Return control to the caller. Do NOT prompt the user.
4.  **If Candidates Found**: For each invariant (max 5), execute `AskUserQuestion` with:
    *   `question`: "Add this invariant? **¶INV_NAME**: [rule summary]"
    *   `header`: "Invariant"
    *   `options`:
        *   `"Add to shared (~/.claude/standards/INVARIANTS.md)"` — Universal rules across all projects
        *   `"Add to project (.claude/standards/INVARIANTS.md)"` — Project-specific rules
        *   `"Skip this one"` — Do not add
    *   `multiSelect`: false
5.  **On Selection**:
    *   **If "Skip"**: Continue to next invariant.
    *   **If "shared" or "project"**: Append to the target file using the Edit tool (NOT log.sh — INVARIANTS.md is a structured document, not a log):
        ```
        Edit tool: append to end of [TARGET_FILE]:
        *   **¶INV_NAME**: [One-line rule]
            *   **Rule**: [Detailed rule description]
            *   **Reason**: [Why this matters]
        ```
    *   **If project file doesn't exist**: Create it with header:
        ```markdown
        # Project Invariants

        Project-specific rules that extend the shared standards.

        ```
6.  **Report**: If any invariants were added, list them: "Added invariants: `¶INV_X` (shared), `¶INV_Y` (project)."

**Constraints**:
*   **Max 5 invariants**: Focus on the most valuable learnings. Avoid prompt fatigue.
*   **Judgment-based**: The agent uses judgment to identify insights — no explicit markers required from the user.
*   **Non-blocking**: If user selects "Skip" for all, the session continues normally.
*   **Idempotent**: Check existing invariants before suggesting to avoid duplicates.
