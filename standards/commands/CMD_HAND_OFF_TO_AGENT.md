### §CMD_HAND_OFF_TO_AGENT
**Definition**: Standardized handoff from a parent command to an autonomous agent.
**Rule**: Opt-in, foreground, user-initiated. The parent command asks; the user decides.

**Parameters**:
*   `agentName`: `"builder"` | `"writer"` | `"debugger"` | `"analyzer"`
*   `sessionDir`: Absolute path to the session directory
*   `parentPromptFile`: Path to the parent skill protocol (e.g., `~/.claude/skills/implement/SKILL.md`)
*   `startAtPhase`: Which phase the agent begins at (e.g., `"Phase 5: Build Loop"`)
*   `planOrDirective`: Path to plan file (plan-driven agents) or inline directive text (prompt-driven agents)
*   `logFile`: Relative path to log file within session (e.g., `IMPLEMENTATION_LOG.md`)
*   `debriefTemplate`: Path to debrief template (e.g., `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md`)
*   `logTemplate`: Path to log entry template (e.g., `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md`)
*   `contextFiles`: List of files loaded during Phase 2 (the agent must read these)
*   `detailsFile`: Path to `DETAILS.md` (interrogation record, for agent reference)
*   `taskSummary`: One-line description of what the agent should do

**Algorithm**:
1.  **Ask** (via `§CMD_ASK_ROUND_OF_QUESTIONS`):
    > "Plan approved. How do you want to proceed?"
    > - **"Launch [agentName] agent"** — Hand off to the agent for autonomous execution. You'll get the debrief when it's done.
    > - **"Continue inline"** — Execute step by step in this conversation.
2.  **If "Continue inline"**: Return control to the parent command's next phase. Done.
3.  **If "Launch agent"**:
    a.  **Log**: Append to the session log: "Handing off to `[agentName]` agent."
    b.  **Read Agent Definition**: Load `~/.claude/agents/[agentName].md`.
    c.  **Construct Task Prompt**: Build the agent's task description with these sections:

        ```
        You are executing an approved plan/directive as an autonomous agent.

        ## 1. Standards (Read These First)
        Read these files before doing anything:
        - ~/.claude/standards/COMMANDS.md
        - ~/.claude/standards/INVARIANTS.md
        - .claude/standards/INVARIANTS.md (if exists)

        ## 2. Your Operational Protocol
        Read: [parentPromptFile]
        You are starting at: [startAtPhase]
        Phases before [startAtPhase] have already been completed by the parent command.
        Execute from [startAtPhase] through to the Synthesis/Debrief phase.

        ## 3. Your Agent Definition
        Read: ~/.claude/agents/[agentName].md

        ## 4. Session Context
        Session directory: [sessionDir]
        Plan/Directive: [planOrDirective]
        Log file: [sessionDir]/[logFile]
        Details file: [sessionDir]/[detailsFile] (read for interrogation context)
        Debrief template: [debriefTemplate]
        Log entry template: [logTemplate]
        Task: [taskSummary]

        Context files to read:
        [list each contextFile]
        ```

    d.  **Invoke**: Call the `Task` tool with `subagent_type: [agentName]` (foreground).
    e.  **Post-Agent Review** (when agent completes):
        1.  Read the agent's debrief file — verify it exists and follows the template.
        2.  Tail the log file (last ~30 lines) — check for unresolved blocks or `😨 Stuck` entries.
        3.  *(Plan-driven agents only)*: Read the plan file — check for unchecked `[ ]` steps. Flag any incomplete work.
        4.  Present a concise summary to the user: what was done, any issues found, next steps.
    f.  **Report**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` and `§CMD_REPORT_SESSION_SUMMARY`.
    g.  **Skip**: The parent command skips its remaining execution and debrief phases — the agent handled both.

**Constraints**:
*   **Opt-In Only**: Never launch an agent without asking. The user always chooses.
*   **Foreground Only**: Agents run in the foreground. The parent waits for completion.
*   **No Chaining**: An agent cannot launch another agent. Only the parent command (user-facing) can invoke `§CMD_HAND_OFF_TO_AGENT`.
*   **Audit Trail**: The agent's log file IS the audit trail. The parent verifies it during post-agent review.
