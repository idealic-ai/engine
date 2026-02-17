### ¶CMD_MAINTAIN_SESSION_DIR
**Definition**: To ensure continuity, the Agent must anchor itself in a single Session Directory for the duration of the task.
**Rule**: Called automatically by `§CMD_PARSE_PARAMETERS` step 4. Do not call separately unless resuming a session without parameter parsing.

**Algorithm**:
1.  **Identify**: Look for an active session directory in the current context:
    *   Check the recent chat history for a "📂 **Session Directory**" entry.
    *   Check the `sessionDir` parameter from `§CMD_PARSE_PARAMETERS`.
    *   Check the most recently modified directory in `sessions/` for the current date.
2.  **Decision**:
    *   **Reuse**: If an existing session directory is found and matches the current topic (even if the `SESSION_TYPE` differs slightly, e.g., switching from IMPLEMENTATION to TESTING), **STAY** in that directory.
    *   **Create**: Only create a new directory if no relevant session exists or if the user explicitly asks for a "New Session".
3.  **Path Strategy**: If creating a new directory, prefer a descriptive topic name: `sessions/[YYYY_MM_DD]_[TOPIC]`.
    *   **Prohibited**: Do NOT include `[SESSION_TYPE]` (e.g., BRAINSTORM, IMPLEMENT) in the folder name.
    *   **Reason**: Sessions are multi-modal. A `BRAINSTORM` session might evolve into `IMPLEMENT`. The folder name must remain stable (Topic-Centric).
    *   **Bad**: `sessions/2026_01_28_BRAINSTORM_LAYOUT_REFACTOR`
    *   **Good**: `sessions/2026_01_28_LAYOUT_REFACTOR`
4.  **Action**: Session activation is handled by `§CMD_PARSE_PARAMETERS` step 3, which pipes the parameters JSON to `engine session activate` via heredoc. The script will:
    *   Create the directory if it doesn't exist.
    *   Write `.state.json` with PID, skill name, status tracking, AND the piped session parameters (merged).
    *   Auto-detect fleet pane ID if running in fleet tmux (no manual `--fleet-pane` needed).
    *   Enable context overflow protection (PreToolUse hook will block at 90%).
    *   Run context scans (on fresh activation or skill change) — all use `taskSummary` for thematic relevance:
        *   `SRC_ACTIVE_ALERTS` — alerts are surfaced automatically (no agent action needed)
        *   `engine tag find '#next-*' [sessionDir]` → `## SRC_OPEN_DELEGATIONS` section (scans current session for `#next-*` items claimed for immediate next-skill execution)
        *   `engine session-search query` → `## SRC_PRIOR_SESSIONS` section
        *   `engine doc-search query` → `## SRC_RELEVANT_DOCS` section
        *   `SRC_DELEGATION_TARGETS` runs unconditionally (outside SHOULD_SCAN guard)
    *   If the same Claude (same PID) and same skill: brief re-activation, no scans.
    *   If the same Claude but different skill: updates skill, runs scans.
    *   If a different Claude is already active in this session (different PID), it rejects with an error. **When this happens, the agent MUST**:
        1.  **Explain the lock to the user**: "Session `[DIR]` has an active agent (PID [N]). Another Claude is working there."
        2.  **Suggest alternatives**: (a) Wait for the other agent to finish, (b) Use a different session directory, (c) Check if PID [N] is actually alive (`ps -p [N]`).
        3.  **Do NOT invent flags**: There is no `--force`, `--clear-pid`, `--override`, or similar. The only activate flags are: `--fleet-pane`, `--target-file`, `--user-approved`, `--fast-track`. If the PID is dead but activate still rejects, the user should manually delete `.state.json` from the session directory.
    *   If a stale `.state.json` exists (dead PID), it cleans up automatically and proceeds.
    *   **Note**: For simple operations without skill tracking, use `engine session init` instead (legacy).
    *   **Note**: For re-activation without new parameters: `engine session activate path skill < /dev/null`.
5.  **Detect Existing Skill Artifacts** (CRITICAL):
    *   After identifying/creating the session directory, check if artifacts from the **current skill type** already exist:
        *   For `/implement`: `IMPLEMENTATION_LOG.md`, `IMPLEMENTATION.md`
        *   For `/test`: `TESTING_LOG.md`, `TESTING.md`
        *   For `/fix`: `FIX_LOG.md`, `FIX.md`
        *   For `/analyze`: `ANALYSIS_LOG.md`, `ANALYSIS.md`
        *   For `/brainstorm`: `BRAINSTORM_LOG.md`, `BRAINSTORM.md`
        *   (etc. — match the skill's log and debrief filenames)
    *   **If artifacts exist**, ask before proceeding:
        > "This session already has [skill] artifacts (`[LOG_FILE]`, `[DEBRIEF_FILE]`). How should I proceed?"
        > - **"Continue (fast-track)"** — Resume with `--fast-track`: skip RAG/directive scans. Use existing log (append), regenerate debrief at end. Pass `--fast-track` flag to `engine session activate`.
        > - **"Continue (full ceremony)"** — Resume with full context: run RAG search, directive discovery, alert surfacing. Use existing log (append), regenerate debrief at end. Do NOT pass `--fast-track`.
        > - **"New session"** — Create a new session directory with a distinguishing suffix (e.g., `_v2`, `_round2`).
    *   **If no artifacts exist** for this skill type, proceed normally (even if other skill artifacts exist — sessions are multi-modal).
6.  **Echo (CRITICAL)**: Output "📂 **Session Directory**: [Path]" to the chat, where [Path] is a clickable link per `¶INV_TERMINAL_FILE_LINKS` (Full variant). If reusing, say "📂 **Reusing Session Directory**: [Path]". If continuing existing skill artifacts, say "📂 **Continuing existing [skill] in**: [Path]".

---

### ¶ASK_SESSION_REUSE
Trigger: when existing skill artifacts are found in the session directory (except: first activation of any skill on a fresh session)
Extras: A: View existing artifacts before deciding | B: Diff with previous session | C: Archive existing and start fresh

## Decision: Session Reuse
- [LITE] Continue (fast-track)
  Resume with existing log, skip RAG/directive scans
- [FULL] Continue (full ceremony)
  Resume with full context: RAG search, directive discovery, alert surfacing
- [NEW] New session
  Create a new session directory with distinguishing suffix
- [SKIP] Skip artifacts check
  Proceed as if no artifacts exist — start fresh in same directory
- [MERG] Merge sessions
  Load artifacts from another session into this one

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in the session directory echo MUST be clickable URLs.

---

## PROOF FOR §CMD_MAINTAIN_SESSION_DIR

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "sessionDirectory": {
      "type": "string",
      "description": "Absolute path to the session directory"
    },
    "action": {
      "type": "string",
      "enum": ["created", "reused", "continued"],
      "description": "Whether the directory was created, reused, or continued with existing skill artifacts"
    },
    "existingArtifacts": {
      "type": "string",
      "description": "Artifact status (e.g., 'found LOG + DEBRIEF' or 'none')"
    }
  },
  "required": ["executed", "sessionDirectory", "action"],
  "additionalProperties": false
}
```
