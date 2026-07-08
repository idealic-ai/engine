### ¶CMD_HANDOFF_TO_AGENT
**Definition**: Standardized handoff from a parent command to an autonomous agent.
**Rule**: Opt-in, foreground, user-initiated. The parent command asks; the user decides.

**Parameters**:
```json
{
  "agentName": "builder | writer | debugger | analyzer",
  "sessionDir": "[absolute path to session directory]",
  "parentPromptFile": "[path to parent skill protocol, e.g. ~/.claude/skills/implement/SKILL.md]",
  "startAtPhase": "[phase label, e.g. 'Phase 5: Build Loop']",
  "planOrDirective": "[path to plan file or inline directive text]",
  "logFile": "[relative path within session, e.g. IMPLEMENTATION_LOG.md]",
  "debriefTemplate": "[path to debrief template, e.g. ~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md]",
  "logTemplate": "[path to log entry template, e.g. ~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md]",
  "contextFiles": ["[files loaded during Phase 2]"],
  "detailsFile": "[path to DIALOGUE.md]",
  "taskSummary": "[one-line description]"
}
```

**Algorithm**:
0.  **Prefer `/build` + `/scrutinize` when available** (`§INV_PREFER_BUILD_SCRUTINIZE`): before offering a raw agent handoff, check the available-skills list. If **both `/build` and `/scrutinize`** are present, offer that combo as the **recommended** path instead of a bare handoff — `/build` assembles a complete self-contained context pack (goal + verbatim asks + prior-chunk history + hard gates + scope guard), dispatches the builder, and returns a structured Build Report; `/scrutinize` then adversarially reviews that report. It's a strictly richer handoff than launching the agent directly. Present it as the first option (label it "(Recommended)"), keep the raw handoff + inline as fallbacks, and honor the user's choice. If either skill is absent, skip this and offer the plain handoff below.
    *   **Chunk-check FIRST (do not merge independent chunks)**: this single-agent path is for **one cohesive chunk**. Before offering it, scan the plan for ≥2 **independent** chunks (disjoint `Files:`, no cross-`Depends:`). If found, do NOT run one merged `/build` over them — hand off to `§CMD_PARALLEL_HANDOFF` instead, which runs **one `/build` per chunk in parallel + one `/scrutinize` per Build Report** (per `§INV_PREFER_BUILD_SCRUTINIZE`). Only run a single `/build` here when the work is genuinely one chunk (shared files / an unsplittable `Depends` chain).
1.  **Ask** (via `§CMD_ASK_ROUND`):
    > "Plan approved. How do you want to proceed?"
    > - **"Build with `/build` (Recommended)"** — *(only when `/build` + `/scrutinize` are available)* Hand off via `/build` (context-maxed pack → Build Report), then optionally `/scrutinize` the result.
    > - **"Launch [agentName] agent"** — Hand off to the agent directly for autonomous execution. You'll get the debrief when it's done.
    > - **"Continue inline"** — Execute step by step in this conversation.
2.  **If "Build with `/build`"**: invoke `Skill(build, "<task summary> -- <goal>")`; when it returns, offer `/scrutinize` on its Build Report (the `/build` protocol already chains this). Done — skip the raw-handoff path below.
3.  **If "Continue inline"**: Return control to the parent command's next phase. Done.
4.  **If "Launch agent"**:
    a.  **Log**: Append to the session log: "Handing off to `[agentName]` agent."
    b.  **Read Agent Definition**: Load `~/.claude/agents/[agentName].md`.
    c.  **Construct Task Prompt**: Build the agent's task description with these sections:

        ```
        You are executing an approved plan/directive as an autonomous agent.

        ## 1. Standards (Read These First)
        Read these files before doing anything:
        - ~/.claude/.directives/COMMANDS.md
        - ~/.claude/.directives/INVARIANTS.md
        - .claude/.directives/INVARIANTS.md (if exists)

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

        ## 5. Logging Discipline
        You MUST log progress to the session log every ~5 tool calls.
        A heartbeat hook will BLOCK you if you exceed 10 tool calls without logging.

        Log file: [sessionDir]/[logFile]
        Command:
        ```bash
        engine log [sessionDir]/[logFile] <<'EOF'
        ## Progress Update
        *   **Task**: [what you were doing]
        *   **Status**: [done/in-progress/blocked]
        *   **Next**: [what's next]
        EOF
        ```

        If blocked by the heartbeat hook, use the command above immediately to unblock.
        ```

    d.  **Invoke**: Call the `Task` tool with `subagent_type: [agentName]` (foreground).
    e.  **Post-Agent Review** (when agent completes):
        1.  Read the agent's debrief file — verify it exists and follows the template.
        2.  Tail the log file (last ~30 lines) — check for unresolved blocks or `😨 Stuck` entries.
        3.  *(Plan-driven agents only)*: Read the plan file — check for unchecked `[ ]` steps. Flag any incomplete work.
        4.  Present a concise summary to the user: what was done, any issues found, next steps.
    f.  **Report**: Execute `§CMD_REPORT_ARTIFACTS` and `§CMD_REPORT_SUMMARY`.
    g.  **Skip**: The parent command skips its remaining execution and debrief phases — the agent handled both.

**Constraints**:
*   **Opt-In Only**: Never launch an agent without asking. The user always chooses.
*   **Foreground Only**: Agents run in the foreground. The parent waits for completion.
*   **No Chaining**: An agent cannot launch another agent. Only the parent command (user-facing) can invoke `§CMD_HANDOFF_TO_AGENT`.
*   **Audit Trail**: The agent's log file IS the audit trail. The parent verifies it during post-agent review.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in the post-agent review and report MUST be clickable URLs.

---

## PROOF FOR §CMD_HANDOFF_TO_AGENT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "agentLaunched": {
      "type": "string",
      "description": "Agent type and task summary for the launched agent"
    }
  },
  "required": ["agentLaunched"],
  "additionalProperties": false
}
```
