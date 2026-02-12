### §CMD_CLOSE_SESSION
**Definition**: After synthesis is complete, deactivates the session (re-engaging the gate) and presents skill-specific next-step options to guide the user.
**Trigger**: Called as the final step of `§CMD_FOLLOW_DEBRIEF_PROTOCOL` (Step 3.5).

**Algorithm**:
1.  **Compose Description**: Write a 1-3 line summary of what was accomplished in this session. Focus on *what changed* and *why*, not process details.
2.  **Infer Keywords**: Based on the session's work, infer 3-5 search keywords that capture the key topics, files, and concepts. These power future RAG discoverability.
    *   *Example*: For a session that refactored auth middleware: `"auth, middleware, ClerkAuthGuard, session-management, NestJS"`
    *   Keywords should be comma-separated, concise, and specific to this session's work.
3.  **Deactivate**: Execute using `engine session deactivate` (see `§CMD_SESSION_CLI` for exact syntax). This sets `lifecycle=completed`, stores description + keywords in `.state.json`, and runs a RAG search returning related sessions in stdout.
4.  **Process RAG Results**: If deactivate returned a `## Related Sessions` section in stdout, display it in chat. This gives the user awareness of related past work.
5.  **Contextualize & Present Menu**:
    *   **Preamble (REQUIRED)**: Before presenting the menu, output a short summary block in chat that explains what each skill option would concretely do *for this session's work*. Do NOT use generic descriptions — tailor each to the actual changes, files, and outcomes of the session. Format:
        > **What each option involves:**
        > - `/skill1` — [1-2 sentences: what this skill would do given the specific work just completed]
        > - `/skill2` — [1-2 sentences: what this skill would do given the specific work just completed]
        > - `/skill3` — [1-2 sentences]
        > - `/skill4` — [1-2 sentences]
    *   **Menu**: Then execute `AskUserQuestion` with options derived from the `nextSkills` array in `.state.json` (populated at session activation from the skill's `### Next Skills` declaration). Each skill defines up to **4 options** (the AskUserQuestion limit). The implicit 5th option ("Other") lets the user type a skill name or describe new work. The question text MUST explain this: include "(Type a /skill name to invoke it, or describe new work to scope it)" in the question.
    *   **Option format**: For each skill in `nextSkills`, use: label=`"/skill-name"`, description=contextualized to this session's work (from the preamble above). The first option should be marked "(Recommended)".
    *   **Fallback**: If `nextSkills` is empty or missing in `.state.json`, use the `§CMD_DISCOVER_DELEGATION_TARGETS` table to derive options (pick the 4 most commonly recommended skills).
6.  **On Selection**:
    *   **If a skill is chosen**: Invoke the Skill tool: `Skill(skill: "[chosen-skill]")`
    *   **If "Other" — skill name** (user typed `/implement`, `/test`, etc.): Invoke the Skill tool with the typed skill name.
    *   **If "Other" — new work details** (user typed notes, questions, or requirements): This is new input that needs scoping. Offer to route to interrogation: execute `AskUserQuestion` with "Start interrogation to scope this?" / "Just do it inline" options. If interrogation is chosen, reactivate the session and enter Phase 3.

**Constraints**:
*   **Session description is REQUIRED**: `engine session deactivate` will ERROR if no description is piped. This powers RAG search for future sessions.
*   **Keywords are RECOMMENDED**: If omitted, deactivate still works but the session is less discoverable by future RAG queries.
*   **Max 4 options**: Each skill defines up to 4 skill options via its `nextSkills` array. The first should be marked "(Recommended)". The user can always type something else via "Other".
*   **Options come from `nextSkills`**: Each skill declares its own `nextSkills` in `### Next Skills (for §CMD_PARSE_PARAMETERS)`. The command reads them from `.state.json` at runtime — it doesn't read SKILL.md.
*   **Same session directory**: The next skill reuses the same session directory (sessions are multi-modal per `§CMD_MAINTAIN_SESSION_DIR`).
