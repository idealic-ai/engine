### ¶CMD_RESUME_SESSION
**Definition**: Resumes a session after interruption — context overflow restart or manual continuation. Single unified algorithm regardless of whether dehydrated context is available.
**Trigger**: Invoked when a fresh Claude starts and needs to resume an existing session. The SessionStart hook auto-injects dehydrated context when available.
**Preloaded**: Always — this file is injected by SessionStart hook alongside dehydrated context (if present).

---

## Algorithm

### Step 1: Resume Session

Run `engine session continue`. This single command handles everything: auto-detects the session (fleet pane ID in tmux, PID fallback outside tmux), registers PID, sets lifecycle=active, clears loading, resets heartbeat, checks for completed sessions, and outputs rich context.

```bash
# With explicit path (when session dir is known):
engine session continue sessions/[SESSION_DIR]

# Without path (auto-detect):
engine session continue
```

**If exit 1 — no session found**: Inform the user: "No active session found. Use a `/skill` to start one." STOP.

**If exit 1 — session completed**: The output includes `## Next Skills`. Execute `§CMD_PRESENT_NEXT_STEPS` using those values. STOP.

**If exit 0**: Parse the output for session state:
*   **Skill**: The active skill name
*   **Phase**: The saved phase (source of truth)
*   **Log**: Path to the active log file
*   **`## Artifacts`**: List of session files (log, plan, debrief, etc.)
*   **`## Next Skills`**: Post-session skill suggestions

### Step 2: Assess Progress

Determine what was accomplished and what remains:

*   **If dehydrated context is present** (look for `## Session Recovery (Dehydrated Context)` in the initial system message): Use the injected summary, lastAction, and nextSteps. No file reads needed.
*   **If no dehydrated context**: Read the last section of the log file (from Step 1 output) to derive progress, last action, and remaining work.

**Sub-Phase Awareness**: If `currentPhase` is a sub-phase (e.g., `"5.2: Debrief"`), the resume point is AT that sub-phase. Debrief existence does NOT mean synthesis is complete — sub-phases N.3 (Pipeline) and N.4 (Close) may still be pending.

### Step 3: Log the Restart

```bash
engine log sessions/[SESSION_DIR]/[SKILL_UPPER]_LOG.md <<'EOF'
## ♻️ Session Resume
*   **Resumed At**: [PHASE]
*   **Last Action**: [from dehydrated context or log scan]
*   **Remaining**: [next steps from context or log scan]
EOF
```

### Step 4: Follow the Skill Protocol

The `post-tool-use-templates.sh` hook auto-preloads the resumed skill's SKILL.md after `engine session continue`. It will appear in your context as `[Preloaded: ~/.claude/skills/[SKILL]/SKILL.md]`.

**Follow the preloaded SKILL.md** — it defines the phases, commands, and proof requirements for the skill you're resuming. But resume at `[PHASE]`, not from Phase 0:

**DO NOT**:
- Repeat earlier phases (Setup, Interrogation, Planning if already done)
- Re-parse parameters
- Re-create the session directory
- Execute `§CMD_EXECUTE_SKILL_PHASES` from the top

**DO**:
- Pick up exactly where the session left off
- Follow the skill protocol from `[PHASE]` onward — read the SKILL.md's phase section for `[PHASE]` and execute its steps
- Continue logging per `§CMD_APPEND_LOG`

**Proof-Gated Awareness**: After `session continue`, you are AT the saved phase — not past it. If the phase's work is complete, you must:
1. DO the next phase's work first
2. THEN transition with proof via `engine session phase`

### Step 6: Check Phase Completion

After resuming, check if the current phase's work is already complete:
1. **Read the log** — are all planned work items done?
2. **If yes**: Fire §CMD_EXECUTE_PHASE_STEPS immediately — the gate at the end of step execution handles the transition. Do NOT informally announce readiness — the gate IS the announcement.
3. **If no**: Continue executing the phase's remaining work.

**Constraint**: "Ready to proceed when you give the word" is NEVER a valid substitute for §CMD_EXECUTE_PHASE_STEPS. If you're at a boundary, use the tool.

### Step 7: Announce Resume

> **Resuming `[SKILL]`** at `[PHASE]`
>
> - **Goal**: [from summary or log]
> - **Last Action**: [from context]
> - **Remaining**: [next steps]
>
> Continuing now...

---

## Constraints

- **Auto-resume always**: Never ask the user what to do. The user invoked `/session continue` — that IS the instruction. Auto-resume at the saved phase with a concise announcement.
- **Trust injected context**: If the SessionStart hook loaded dehydrated summary and required files, do NOT re-read them (`¶INV_TRUST_CACHED_CONTEXT`). To **edit** an injected file, Read it first (`¶INV_PRELOAD_IS_REFERENCE_ONLY`).
- **No re-interrogation**: The original agent already completed earlier phases. Use available context (dehydrated or log-derived).
- **No re-creation**: Do NOT re-create the session directory or re-parse parameters.
- **No sub-phase skipping**: When resuming at a phase with sub-phases (e.g., synthesis), resume at the exact sub-phase from `currentPhase` in `.state.json`. Debrief existence proves sub-phase N.2 completed — it does NOT prove N.3 (Pipeline) or N.4 (Close) completed.
- **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration of the resume steps.
- **`¶INV_PROTOCOL_IS_TASK`**: The resume protocol defines the task — do not skip steps.

---

## PROOF FOR §CMD_RESUME_SESSION

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "sessionReactivated": {
      "type": "string",
      "description": "Reactivation outcome (e.g., 'resumed at Phase 3')"
    },
    "phaseResumed": {
      "type": "string",
      "description": "The phase the agent resumed at"
    }
  },
  "required": ["sessionReactivated", "phaseResumed"],
  "additionalProperties": false
}
```
