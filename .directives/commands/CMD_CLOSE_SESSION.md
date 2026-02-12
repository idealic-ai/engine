### §CMD_CLOSE_SESSION
**Definition**: After synthesis is complete, transitions the session to idle state and presents the 3-option transition menu. The session stays alive (lifecycle=idle) until the user picks a next action.
**Trigger**: Called as the final step of `§CMD_RUN_SYNTHESIS_PIPELINE` (Step 3.5).

**Algorithm**:
0.  **Debrief Gate** (`¶INV_CHECKLIST_BEFORE_CLOSE` pattern): Verify the skill's debrief file exists (e.g., `IMPLEMENTATION.md` for `/implement`, `ANALYSIS.md` for `/analyze`). This is mechanically enforced — the debrief must exist before proceeding.
    *   **When Blocked**: Write the debrief via `§CMD_GENERATE_DEBRIEF`, then retry.
    *   **Skip**: If the user explicitly approves skipping, quote the user's actual words as the reason. The agent MUST use `AskUserQuestion` to get user approval before skipping. Agent-authored justifications are not valid.
    *   **Prohibited justifications** (these are never valid reasons to skip the debrief):
        *   "Small focused change — no debrief needed."
        *   "This task was too simple for a debrief."
        *   "The changes are self-explanatory."
        *   Any reason authored by the agent without user input.
    *   **Valid reasons** (these require the user to have actually said it):
        *   `"Reason: User said 'skip the debrief, just close it'"`
        *   `"Reason: User said 'discard this session'"`
        *   `"Reason: User abandoned session early — said 'never mind, move on'"`
1.  **Compose Description**: Write a 1-3 line summary of what was accomplished in this session. Focus on *what changed* and *why*, not process details.
2.  **Infer Keywords**: Based on the session's work, infer 3-5 search keywords that capture the key topics, files, and concepts. These power future RAG discoverability.
    *   *Example*: For a session that refactored auth middleware: `"auth, middleware, ClerkAuthGuard, session-management, NestJS"`
    *   Keywords should be comma-separated, concise, and specific to this session's work.
3.  **Transition to Idle**: Execute `engine session idle` (NOT `deactivate`). This sets `lifecycle=idle`, clears PID (null sentinel), stores description + keywords, and runs a RAG search returning related sessions in stdout.
    ```bash
    engine session idle <session-dir> --keywords 'kw1,kw2,kw3' <<'EOF'
    What was accomplished in this session (1-3 lines)
    EOF
    ```
4.  **Process RAG Results**: If the idle command returned a `## Related Sessions` section in stdout, display it in chat. This gives the user awareness of related past work.
5.  **Contextualize & Present Skill Picker**:
    *   **Preamble (REQUIRED)**: Before presenting the menu, output a short summary block in chat that explains what each skill option would concretely do *for this session's work*. Do NOT use generic descriptions — tailor each to the actual changes, files, and outcomes of the session. Format:
        > **What each option involves:**
        > - `/skill1` — [1-2 sentences: what this skill would do given the specific work just completed]
        > - `/skill2` — [1-2 sentences: what this skill would do given the specific work just completed]
        > - `/skill3` — [1-2 sentences]
    *   **Menu**: Execute `AskUserQuestion` with skill options from `nextSkills` in `.state.json`, plus "Done for now":

    ```
    AskUserQuestion:
      question: "Session complete. What next? (Type a /skill name to invoke it, or describe new work to scope it)"
      header: "Next skill"
      options:
        - label: "/skill1 (Recommended)"
          description: "[contextualized to this session's work]"
        - label: "/skill2"
          description: "[contextualized to this session's work]"
        - label: "/skill3"
          description: "[contextualized to this session's work]"
        - label: "Done for now"
          description: "Leave session idle. Come back later."
    ```
    *   **Option format**: For each skill in `nextSkills`, use: label=`"/skill-name"`, description=contextualized to this session's work. The first option should be marked "(Recommended)". The last option is always "Done for now".
    *   **Fallback**: If `nextSkills` is empty or missing in `.state.json`, use the `§CMD_DISCOVER_DELEGATION_TARGETS` table to derive options (pick the 3 most commonly recommended skills + "Done for now").

6.  **On Skill Selection**:
    *   **If a skill is chosen**: Invoke `Skill(skill: "[chosen-skill]")`. The next skill's `§CMD_PARSE_PARAMETERS` will run `§CMD_MAINTAIN_SESSION_DIR`, which detects the idle session with existing artifacts and presents the delivery mode choice (fast-track / full ceremony / new session). The fast-track choice is handled there — NOT here — to avoid double-asking.
    *   **If "Done for now"**: Session stays idle. Output: "Session is idle. Invoke any `/skill` when you're ready to continue."
    *   **If "Other" — skill name** (user typed `/implement`, `/test`, etc.): Treat as skill selection — invoke `Skill(skill: "[typed-skill]")`.
    *   **If "Other" — new work details** (user typed notes, questions, or requirements): This is new input that needs scoping. Offer to route to interrogation via `AskUserQuestion`.

**Constraints**:
*   **Session description is REQUIRED**: `engine session idle` will ERROR if no description is piped.
*   **Keywords are RECOMMENDED**: If omitted, idle still works but the session is less discoverable.
*   **Idle gate active**: After `engine session idle`, the idle-gate injection restricts tools to AskUserQuestion, Skill, and engine commands only. This is expected — it forces skill selection before new work.
*   **Options come from `nextSkills`**: Each skill declares its own `nextSkills` in `### Next Skills (for §CMD_PARSE_PARAMETERS)`. The command reads them from `.state.json` at runtime.
*   **Same session directory**: Fast-track reuses the same session directory. New session creates a fresh one.

---

## PROOF FOR §CMD_CLOSE_SESSION

This command is a synthesis pipeline step. It produces no standalone proof fields — its execution is tracked by the pipeline orchestrator (`§CMD_RUN_SYNTHESIS_PIPELINE`).
