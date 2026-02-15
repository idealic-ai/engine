### ¶CMD_RESUME_SESSION
**Definition**: Resumes a session after interruption. Handles two scenarios: (1) context overflow restart with dehydrated context (fast path), (2) bare continuation without dehydrated context (slow path). Replaces the former `§CMD_REHYDRATE`.
**Trigger**: Invoked when a fresh Claude starts and needs to resume an existing session. The SessionStart hook auto-injects dehydrated context when available.
**Preloaded**: Always — this file is injected by SessionStart hook alongside dehydrated context (if present).

---

## Algorithm

### Step 1: Detect Path

Check for dehydrated context in the initial system message:
*   **Fast path**: `## Session Recovery (Dehydrated Context)` is present. The SessionStart hook injected summary, lastAction, nextSteps, and required files. Proceed to **Step 2F**.
*   **Slow path**: No dehydrated context. The user invoked `/session continue` manually, or a restart happened without dehydration. Proceed to **Step 2S**.

---

## Fast Path (Dehydrated Context Present)

### Step 2F: Report Intent

**Output this blockquote**:
> **Context Overflow Recovery**
>
> Rehydrating session after context overflow restart:
> - **Session**: `[SESSION_DIR]`
> - **Skill**: `[SKILL]`
> - **Resuming at**: `[PHASE]`
>
> I will now:
> 1. Re-activate session
> 2. Resume session tracking
> 3. Log the restart
> 4. Continue at `[PHASE]`

### Step 2.5F: Check Lifecycle (Completed Session Guard)

Before attempting reactivation, check if the session was already deactivated (overflow can hit AFTER `§CMD_CLOSE_SESSION` completes):

```bash
lifecycle=$(jq -r '.lifecycle // "active"' sessions/[SESSION_DIR]/.state.json)
```

*   **If `lifecycle` = `completed`**: The session finished successfully before overflow. Nothing to resume.
    1. **Announce**: "Session already completed before overflow. Nothing to resume."
    2. **Present next steps**: Execute `§CMD_PRESENT_NEXT_STEPS` directly (read `nextSkills` from `.state.json`). The user can start a new skill from here.
    3. **STOP**: Do not proceed to Step 3F. Do not attempt reactivation.
*   **If `lifecycle` = `idle`**: The session is in post-synthesis idle state. Proceed to Step 3F — reactivation of idle sessions is supported.
*   **If `lifecycle` = `restarting`**: Expected after dehydration-triggered restart. Proceed to Step 3F.
*   **If `lifecycle` = `active`** (or absent): Normal case. Proceed to Step 3F.

### Step 3F: Re-Activate Session

```bash
engine session activate sessions/[SESSION_DIR] [SKILL] < /dev/null
```

This re-registers the Claude process with the session. Use `< /dev/null` — no new parameters needed (session already has them from the original activation).

### Step 4F: Resume Session Tracking

```bash
engine session continue sessions/[SESSION_DIR]
```

This clears the `loading` flag and resets heartbeat counters. The saved phase in `.state.json` is the source of truth — `continue` resumes the heartbeat at that phase.

### Step 5F: Log the Restart

```bash
engine log sessions/[SESSION_DIR]/[SKILL_UPPER]_LOG.md <<'EOF'
## ♻️ Context Overflow Restart
*   **Resumed At**: [PHASE]
*   **Last Action**: [from dehydrated context summary]
*   **Next Steps**: [from dehydrated context next steps]
EOF
```

### Step 6F: Load Skill Protocol

Read the original skill's SKILL.md so you know how to continue:
```
~/.claude/skills/[SKILL]/SKILL.md
```

### Step 7F: Resume at Saved Phase

**DO NOT**:
- Repeat earlier phases (Setup, Interrogation, Planning if already done)
- Re-parse parameters (use dehydrated context)
- Re-create the session directory

**DO**:
- Pick up exactly where the dehydrated context says you left off
- Follow the skill protocol from `[PHASE]` onward
- Continue logging per `§CMD_APPEND_LOG`

**Proof-Gated Awareness**: After `session continue`, you are AT the saved phase — not past it. If dehydrated context says the current phase's work is complete, you must:
1. DO the next phase's work first
2. THEN transition with proof via `engine session phase`

**Sub-Phase Awareness**: If the saved phase is a sub-phase (e.g., `"5.2: Debrief"`), you are AT that sub-phase. Check if its work is complete. If complete, transition to the next sub-phase (e.g., `"5.3: Pipeline"`). If not, finish it. Do NOT skip remaining sub-phases — debrief existence does NOT mean the full synthesis pipeline is complete.

### Step 8F: Check Phase Completion

After resuming, check if the current phase's work is already complete:
1. **Read the log** — are all planned work items done?
2. **If yes**: Fire §CMD_EXECUTE_PHASE_STEPS immediately -- the gate at the end of step execution handles the transition. Do NOT informally announce readiness -- the gate IS the announcement.
3. **If no**: Continue executing the phase's remaining work.

**Constraint**: "Ready to proceed when you give the word" is NEVER a valid substitute for §CMD_EXECUTE_PHASE_STEPS. If you're at a boundary, use the tool.

### Step 9F: Announce Resume

> **Resuming `[SKILL]`** at `[PHASE]`
>
> **Context restored from**: `.state.json` (auto-injected by SessionStart)
> - **Goal**: [from summary]
> - **Last Action**: [from lastAction]
> - **Next Steps**: [from nextSteps]
>
> Continuing now...

---

## Slow Path (No Dehydrated Context)

The slow path mirrors the fast path — auto-resume with a concise announcement. The user invoked `/session continue` specifically to resume; asking what to do adds unnecessary friction.

### Step 2S: Auto-Detect and Resume

Run `engine session continue` with no arguments. It auto-detects the session (fleet pane ID in tmux, PID fallback outside tmux), clears loading, resets heartbeat, and outputs everything:

```bash
engine session continue
```

If no active session is found, it exits 1 — inform the user: "No active session found. Use a `/skill` to start one."

Parse the output to get session dir, then re-activate:

```bash
engine session activate [SESSION_DIR from output] [SKILL from output] < /dev/null
```

The `continue` output provides structured context:
*   **Skill**: The active skill name
*   **Phase**: The saved phase (source of truth)
*   **Log**: Path to the active log file
*   **`## Artifacts`**: List of session files (log, plan, debrief, etc.)
*   **`## Next Skills`**: Post-session skill suggestions

Parse this output to derive the session state — no manual artifact scanning needed.

### Step 5S: Assess Progress

Using the `engine session continue` output and the log file:
1. **Read the last few log entries** to understand what was accomplished and what remains.
2. **Derive sub-phase state**: If `currentPhase` is a sub-phase (e.g., `"5.2: Debrief"`), the resume point is AT that sub-phase. Debrief existence does NOT mean synthesis is complete — sub-phases N.3 (Pipeline) and N.4 (Close) may still be pending.
3. **Derive actual state**: Compare `.state.json` phase with artifact evidence. Artifacts are ground truth.

### Step 6S: Log the Restart

```bash
engine log sessions/[SESSION_DIR]/[SKILL_UPPER]_LOG.md <<'EOF'
## ♻️ Manual Session Resume
*   **Resumed At**: [PHASE]
*   **Artifacts Found**: [from engine session continue output]
*   **Progress**: [derived from log scan]
EOF
```

### Step 7S: Load Skill Protocol

Read the original skill's SKILL.md so you know how to continue:
```
~/.claude/skills/[SKILL]/SKILL.md
```

### Step 8S: Resume at Saved Phase

Same rules as fast path Step 7F:

**DO NOT**:
- Repeat earlier phases (Setup, Interrogation, Planning if already done)
- Re-parse parameters
- Re-create the session directory

**DO**:
- Pick up exactly where the session left off
- Follow the skill protocol from `[PHASE]` onward
- Continue logging per `§CMD_APPEND_LOG`

**Proof-Gated Awareness**: After `session continue`, you are AT the saved phase — not past it. If the log shows the current phase's work is complete, you must:
1. DO the next phase's work first
2. THEN transition with proof via `engine session phase`

**Sub-Phase Awareness**: If the saved phase is a sub-phase (e.g., `"5.2: Debrief"`), you are AT that sub-phase. Check if its work is complete. If complete, transition to the next sub-phase. If not, finish it.

### Step 9S: Check Phase Completion

After resuming, check if the current phase's work is already complete:
1. **Read the log** — are all planned work items done?
2. **If yes**: Fire §CMD_EXECUTE_PHASE_STEPS immediately -- the gate at the end of step execution handles the transition. Do NOT informally announce readiness -- the gate IS the announcement.
3. **If no**: Continue executing the phase's remaining work.

**Constraint**: "Ready to proceed when you give the word" is NEVER a valid substitute for §CMD_EXECUTE_PHASE_STEPS. If you're at a boundary, use the tool.

### Step 10S: Announce Resume

> **Resuming `[SKILL]`** at `[PHASE]`
>
> - **Goal**: [from log/context]
> - **Last Action**: [from log scan]
> - **Remaining**: [derived from log]
>
> Continuing now...

---

## Constraints

- **Both paths auto-resume**: Neither path asks the user what to do. The user invoked `/session continue` — that IS the instruction. Auto-resume at the saved phase with a concise announcement.
- **Fast path: Trust injected context**: The SessionStart hook already loaded the dehydrated summary and required files. Do NOT re-read files just to check details (`¶INV_TRUST_CACHED_CONTEXT`). However, if you need to **edit** any injected file, you MUST Read it first (`¶INV_PRELOAD_IS_REFERENCE_ONLY`).
- **Fast path: Fresh context**: You have ~0% context usage. Do NOT trigger another dehydration.
- **Fast path: Minimal I/O**: Only read the skill SKILL.md (Step 6F) and any files NOT already auto-loaded.
- **Fast path: No re-interrogation**: The original agent already completed interrogation. Use the dehydrated summary.
- **Slow path: Use engine output**: `engine session continue` outputs artifacts and next skills. Read the last few log entries for progress — don't load entire files.
- **Slow path: Phase trust but verify**: `.state.json` phase may be stale. Artifacts are ground truth.
- **Both paths: No re-creation**: Do NOT re-create the session directory or re-parse parameters.
- **Both paths: No sub-phase skipping**: When resuming at a phase with sub-phases (e.g., synthesis), resume at the exact sub-phase from `currentPhase` in `.state.json`. Do NOT skip to the end of the major phase. Debrief existence proves sub-phase N.2 completed — it does NOT prove N.3 (Pipeline) or N.4 (Close) completed. Every sub-phase must execute per `§CMD_RUN_SYNTHESIS_PIPELINE`.
- **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration of the resume steps.
- **`¶INV_PROTOCOL_IS_TASK`**: The resume protocol defines the task — do not skip steps or phases.

---

## PROOF FOR §CMD_RESUME_SESSION

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "sessionReactivated": {
      "type": "string",
      "description": "Reactivation outcome (e.g., 'reactivated at Phase 3')"
    },
    "resumePath": {
      "type": "string",
      "description": "Which path was taken: fast (dehydrated) or slow (bare)"
    },
    "phaseResumed": {
      "type": "string",
      "description": "The phase the agent resumed at"
    }
  },
  "required": ["sessionReactivated", "resumePath", "phaseResumed"],
  "additionalProperties": false
}
```
