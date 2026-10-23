### ¶CMD_HANDLE_INLINE_TAG
**Definition**: When a user types `#needs-xxx` (e.g., `#needs-brainstorm`, `#needs-research`, `#needs-documentation`) in response to a question or during discussion, the agent must capture it as an inline tag in the active artifact.

**Rule**: The user typing `#needs-xxx` means: "I can't answer this now. Tag it so it can be addressed later by the appropriate skill (e.g., `/brainstorm`, `/research`, `/document`)."

**Algorithm**:
1.  **Detect**: The user's response contains a `#needs-xxx` tag.
2.  **Tag the Source**: Add the tag **inline** in the relevant location of the **active work artifact** (the log entry, plan section, or debrief section currently being discussed). Place it naturally — next to the heading, in the paragraph, or as a bold marker:
    *   *In a log entry*: `### [timestamp] 🚧 Block — [Topic] #needs-brainstorm`
    *   *In a plan step*: `*   [ ] **Step 3**: [Action] #needs-brainstorm`
    *   *In a debrief section*: Add to the relevant paragraph or as a bullet.
3.  **Log to DIALOGUE.md**: Execute `§CMD_LOG_INTERACTION` recording the user's deferral (the question asked, the `#needs-xxx` response, and the context).
4.  **Do NOT Duplicate**: The tag should appear in **exactly one** work artifact (the log OR the debrief section — whichever is active when the user defers). Do NOT propagate the tag from DIALOGUE.md into the debrief automatically. If the debrief has a "Pending Decisions" or "Open Questions" section, list it there as a **reference** (one-liner with source path), not a full copy.
5.  **Tag the File**: If the work artifact is a debrief (final output), also add the `#needs-xxx` tag to the file's `**Tags**:` line via `§CMD_TAG_FILE`.
6.  **Tag Reactivity** (`¶INV_WALKTHROUGH_TAGS_ARE_PASSIVE`): Determine the current context and react accordingly:
    *   **During `§CMD_WALK_THROUGH_RESULTS`**: Tags are **passive**. The walkthrough protocol handles triage. Do NOT offer `/delegation-create` — the tag is protocol-placed, not a user-initiated deferral. Record and move on.
    *   **All other contexts** (interrogation, QnA, ad-hoc chat, side discovery): Tags are **reactive**. After recording the tag, invoke `/delegation-create` via the Skill tool: `Skill(skill: "delegation-create", args: "[tag] [context summary]")`. The `/delegation-create` skill handles mode selection (async/blocking/silent) and REQUEST filing. The user can always decline via "Other" in the delegate prompt.
7.  **Continue**: Resume the session. Do not halt or change phases — the deferral is recorded (and optionally delegated), move on.

**Constraint**: **Once Only**. Each deferred item appears as an inline tag in ONE place. The DIALOGUE.md captures the verbatim exchange. The debrief may list it in a "Pending" section as a pointer. Never three copies.
