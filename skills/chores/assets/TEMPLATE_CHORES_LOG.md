# Chores Session Log (The Workbench Ledger)
**Usage**: Track each micro-task through its lifecycle. One entry per event, not per task.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## 📥 Task Received
*   **Task #**: `[N]`
*   **Request**: "User asked to [verbatim or close paraphrase]."
*   **Clarity**: [Clear / Needs Clarification]
*   **Estimated Scope**: [Trivial / Small / Medium]

## ❓ Clarification
*   **Task #**: `[N]`
*   **Question**: "What did the user mean by [X]?"
*   **Answer**: "User said [verbatim]."
*   **Decision**: "Proceeding with [approach]."

## 🔧 Task Execution
*   **Task #**: `[N]`
*   **Action**: "Changed [X] in [file]."
*   **Files**: `path/to/file.ts`, `path/to/other.ts`
*   **Approach**: "Direct edit / Refactor / Config change / etc."

## ✅ Task Complete
*   **Task #**: `[N]`
*   **Summary**: "Added [X] to [Y]."
*   **Changes**: `file1.ts` (modified), `file2.ts` (new)
*   **Verification**: "Tests pass / Manual check / N/A"
*   **Notes**: "Also noticed [side observation]."

## ❌ Task Blocked
*   **Task #**: `[N]`
*   **Obstacle**: "Cannot do [X] because [Y]."
*   **Resolution**: [Deferred / Escalated / Workaround Applied]
*   **Notes**: "Recommended [alternative]."

## 👁️ Side Discovery
*   **During Task #**: `[N]`
*   **Finding**: "Noticed [X] while working on [Y]."
*   **Relevance**: [High / Low]
*   **Action**: "Logged for later / Mentioned to user."

## 🔄 Session Checkpoint
*   **Tasks Completed**: [N of M]
*   **Running Changes**: `file1.ts`, `file2.ts`, ...
*   **Open Items**: "Task [N] still pending user input."
