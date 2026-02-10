# Research Response: Claude Code Hooks Uses to Improve Processes
**Tags**: #done-research

## 1. Metadata
*   **Gemini Interaction ID**: `v1_ChdtcDJKYVpIdEtiak1qdU1QejhidmlBZxIXbXAySmFaSHRLYmpNanVNUHo4YnZpQWc`
*   **Original Request**: `sessions/2026_02_09_CLAUDE_HOOKS/RESEARCH_REQUEST_CLAUDE_HOOKS.md`
*   **Requested By**: `sessions/2026_02_09_CLAUDE_HOOKS`
*   **Model**: `deep-research-pro-preview-12-2025`

## 2. Research Report
*Raw output from Gemini Deep Research. Unedited.*

# Comprehensive Catalog of Claude Code Hooks: Patterns and Architectures

## Executive Summary
Claude Code, Anthropic's CLI-based autonomous coding agent, introduces a deterministic "Hooks" system that allows developers to intercept, modify, or block the agent's actions at critical lifecycle events. Unlike the probabilistic nature of Large Language Models (LLMs), hooks provide a rigid execution layer for enforcing standards, security, and workflows.

The following report categorizes discovered hook patterns into a taxonomy of use cases, ranging from basic quality gates to complex multi-agent orchestration. It details specific implementation patterns using `settings.json` configurations and shell scripts, explores novel architectures involving prompt injection and external API integration, and analyzes lesser-known hook events like `PostToolUseFailure` and `TeammateIdle`.

## 1. Taxonomy of Use Cases
Research into developer repositories, documentation, and community discussions reveals a functional taxonomy of hook usage. Developers primarily utilize hooks to bridge the gap between AI autonomy and engineering rigor.

| Category | Primary Function | Typical Events Used |
| :--- | :--- | :--- |
| **Quality Gates** | Enforcing code style, linting, and test passing before or after edits. | `PostToolUse`, `PreToolUse` |
| **Security & Safety** | Blocking destructive commands, preventing secret exfiltration, and managing file permissions. | `PreToolUse` |
| **Context Management** | Injecting project rules, "memory" files, or prompt augmentations to keep the agent aligned. | `UserPromptSubmit`, `SessionStart` |
| **Observability** | Logging tool usage, tracking costs/tokens, and creating audit trails for compliance. | `PostToolUse`, `SessionEnd` |
| **Workflow Automation** | Auto-committing to Git, cleaning up temporary files, and handling notifications. | `PostToolUse`, `SessionEnd`, `Notification` |
| **Agent Coordination** | Managing sub-agent lifecycles and handling idle states in multi-agent teams. | `SubagentStart`, `TeammateIdle`, `TaskCompleted` |
| **Error Recovery** | intercepting tool failures to provide deterministic fixes or hints to the agent. | `PostToolUseFailure` |

---

## 2. Comprehensive Pattern Catalog

### 2.1 Quality Gates: The "Auto-Fixer"
**Goal:** Ensure code written by Claude adheres to project standards without manual intervention.
**Mechanism:** Triggers a formatter or linter immediately after a file is modified.

*   **Event:** `PostToolUse`
*   **Matcher:** `Edit|Write` (Matches file modification tools)
*   **Why use this:** LLMs often miss minor formatting nuances. This guarantees consistency.

**Configuration (`settings.json`):**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "scripts/format_and_check.sh"
          }
        ]
      }
    ]
  }
}
```

**Implementation (`scripts/format_and_check.sh`):**
```bash
#!/bin/bash
# Read JSON from stdin
INPUT=$(cat)

# Extract the file path using jq
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')

# 1. Run Prettier (Frontend)
if [[ "$FILE_PATH" == *.ts ]] || [[ "$FILE_PATH" == *.tsx ]]; then
    npx prettier --write "$FILE_PATH"
fi

# 2. Run Python Black (Backend)
if [[ "$FILE_PATH" == *.py ]]; then
    black "$FILE_PATH"
fi

# Exit 0 allows the session to continue seamlessly
exit 0
```
*Limitation:* If the formatter significantly changes the file structure, Claude might lose track of line numbers for subsequent `Edit` operations unless it re-reads the file.

### 2.2 Security: The "Destructive Command Blocker"
**Goal:** Prevent the agent from executing dangerous shell commands or accessing sensitive configuration files.
**Mechanism:** Intercepts `Bash` tool calls or file writes *before* execution and returns a blocking decision.

*   **Event:** `PreToolUse`
*   **Matcher:** `Bash` or `Write`
*   **Why use this:** To prevent accidental deletion of files or exfiltration of `.env` secrets.

**Configuration (`settings.json`):**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "scripts/block_danger.sh" }]
      },
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "scripts/protect_secrets.sh" }]
      }
    ]
  }
}
```

**Implementation (`scripts/block_danger.sh`):**
```bash
#!/bin/bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Block rm -rf or massive deletions
if [[ "$CMD" == *"rm -rf"* ]] || [[ "$CMD" == *"rm -r"* ]]; then
    # Output JSON decision to block
    echo "{\"decision\": \"block\", \"reason\": \"Destructive command 'rm -rf' is prohibited by policy.\"}"
    exit 0
fi

# Approve otherwise
echo "{\"decision\": \"allow\"}"
exit 0
```
*Note:* A simpler version can just `exit 2` and print the error to stderr, which Claude interprets as a block with the stderr message as the reason.

### 2.3 Context Management: The "Prompt Augmenter"
**Goal:** Inject specific project rules, architectural constraints, or "memory" into every user prompt to ensure the model stays aligned.
**Mechanism:** Intercepts the user's input and modifies it (by appending text) before it reaches the model.

*   **Event:** `UserPromptSubmit`
*   **Matcher:** (Not supported for this event; fires on all prompts)
*   **Why use this:** To enforce an "Actually Works" protocol or persist critical instructions that Claude tends to forget during context compaction.

**Configuration (`settings.json`):**
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "scripts/inject_context.sh"
          }
        ]
      }
    ]
  }
}
```

**Implementation (`scripts/inject_context.sh`):**
```bash
#!/bin/bash
# Read user input
INPUT=$(cat)
USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt')

# Print purely to stdout is added to the prompt context
echo " [SYSTEM NOTE: Remember to use the 'Actually Works' protocol: 1. Verify files exist. 2. Run tests after edits.]"

exit 0
```
*Key Distinction:* Unlike other hooks where stdout is hidden or used for JSON control, `UserPromptSubmit` stdout is directly appended to the context visible to Claude.

### 2.4 Workflow: The "Git Safety Net"
**Goal:** Automatically stage or commit changes after successful edits to create checkpoints.
**Mechanism:** Runs git commands after a `Write` or `Edit` tool completes.

*   **Event:** `PostToolUse`
*   **Matcher:** `Edit|Write`
*   **Why use this:** Allows for easy rollbacks if Claude's subsequent actions break the code.

**Implementation:**
```bash
#!/bin/bash
# scripts/auto_git.sh
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path')

# Add the specific file that was changed
git add "$FILE"
# Optional: Commit with a generic message (or use a separate agent to generate a message)
git commit -m "Auto-checkpoint: Claude modified $FILE"

exit 0
```

---

## 3. Creative and Novel Uses

### 3.1 Multi-Agent "Thinking" Simulation
Developers have simulated "reasoning" phases by utilizing the `UserPromptSubmit` hook to force Claude to output a plan before executing tools.
*   **Pattern:** The hook intercepts the prompt and appends: *"Before answering, list 3 potential risks of this request."*
*   **Result:** Claude processes the modified prompt, generates the risk assessment, and then proceeds with the user's original request, effectively creating a safety thinking step.

### 3.2 External LLM Routing (The "Second Opinion")
A novel pattern involves using hooks to query *other* models (like Gemini or a local Ollama instance) to validate Claude's actions or provide specialized help.
*   **Event:** `UserPromptSubmit` or `PreToolUse`
*   **Pattern:** A script receives the prompt, sends it to the Gemini CLI or API, and injects Gemini's response into the context for Claude to see.
*   **Use Case:** If the user asks for help with a library Claude is unfamiliar with, the hook can fetch the documentation summary from a web-connected model and feed it to Claude.

### 3.3 Dynamic Status Lines
While Claude Code has a native status line, developers use hooks to update terminal status indicators dynamically based on the current context.
*   **Event:** `SessionStart` / `PostToolUse`
*   **Pattern:** Scripts that calculate token usage or current git branch and output it to a dedicated status file or terminal overlay, providing a "heads-up display" for the developer.

---

## 4. Deep Dive: Lesser-Known Hook Types

### 4.1 `PostToolUseFailure`: Deterministic Error Recovery
This is one of the most powerful but underutilized hooks. When a tool fails (e.g., a build error or missing dependency), this hook fires.
*   **Use Case:** Auto-remediation.
*   **Pattern:** If a `Bash` command fails with "module not found," the hook can analyze the stderr, detect the missing package, and inject a prompt telling Claude: *"The previous command failed because 'pandas' is missing. Please run 'pip install pandas'."*
*   **Value:** It prevents Claude from hallucinating the cause of the error by providing ground-truth debugging data.

**Configuration:**
```json
{
  "hooks": {
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "scripts/analyze_failure.py" }]
      }
    ]
  }
}
```

### 4.2 `SubagentTurnStart` and `SubagentStop`
These hooks fire when the main Claude agent spawns a "Task" (a sub-agent) to handle a complex objective.
*   **Use Case:** Monitoring and Budgeting.
*   **Pattern:** A `SubagentTurnStart` hook can track how many turns a sub-agent has taken. If it exceeds a limit, the hook can return `{"decision": "block"}` to kill the sub-agent process, preventing infinite loops or excessive token costs.
*   **Data Available:** The hook receives the `subagent_type` (e.g., "Explore", "Plan") and the prompt assigned to it.

### 4.3 `TeammateIdle` and `TaskCompleted`
Introduced for multi-agent "Team" workflows (experimental), these hooks allow for orchestration between agents.
*   **Use Case:** Handoff protocols.
*   **Pattern:** When `TeammateIdle` fires, a hook can check a shared "todo.md" file. If tasks remain, it can inject a prompt to the idle agent to pick up the next task. This enables a crude form of autonomous project management.

---

## 5. Anti-Patterns and Pitfalls

### 5.1 The Infinite Loop Trap
**Scenario:** A hook is configured on `PostToolUse` with the matcher `Write`.
**The Pattern:** The hook script modifies the file (e.g., formatting) and saves it.
**The Pitfall:** Saving the file triggers the `Write` event again, which triggers the hook again, causing an infinite loop.
**Solution:**
1.  Use specific matchers (e.g., exclude the file being written by the hook).
2.  Implement a lock file mechanism or check if the file actually requires changes before writing.
3.  Use `PreToolUse` to modify the content *in-flight* rather than writing to disk after the fact.

### 5.2 Performance Blocking
**Scenario:** Running a full test suite (e.g., `npm test` taking 30s) on every `PostToolUse`.
**Impact:** This destroys the developer experience, making the agent feel sluggish.
**Best Practice:**
*   Run heavy tasks asynchronously using the `&` operator in shell scripts (fire and forget), unless the result is strictly required to proceed.
*   Only run tests on the specific file changed, not the whole suite.

### 5.3 `Exit 2` vs. `Exit 0` Confusion
A common mistake is misusing exit codes.
*   **Mistake:** Exiting with 1 or a random error code when a check fails.
*   **Consequence:** Claude ignores the output or treats it as a generic system error.
*   **Correct Usage:**
    *   **Exit 0:** The hook ran successfully. Claude parses the JSON on stdout (e.g., `{"decision": "block"}`).
    *   **Exit 2:** Hard block/Error. Claude ignores stdout and presents stderr to the model/user as a failure. This is often used for "panic" buttons.

### 5.4 Environment Variable Blindness
Hooks run in a child process. They do not automatically inherit the full shell environment of the user (aliases, unexported variables).
*   **Pitfall:** A hook trying to run `npm` might fail if `node` is not in the `PATH` seen by Claude Code.
*   **Solution:** Always use absolute paths or source the user's profile (`source ~/.bashrc`) at the start of complex hook scripts.

## 6. References
*   Official Hooks Documentation (Event types, matchers).
*   Steve Kinney's Course (Control flow, exit codes).
*   "Automated Quality Checks" (Linting patterns).
*   Claude Code Hooks Blog (Logging, Event Logger).
*   Security Hooks (Blocking rm -rf).
*   `claude-code-kit` (TypeScript types for hooks).
