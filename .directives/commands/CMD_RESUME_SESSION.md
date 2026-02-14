### §CMD_RESUME_SESSION
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

### Step 8F: Check Phase Completion

After resuming, check if the current phase's work is already complete:
1. **Read the log** — are all planned work items done?
2. **If yes**: Fire `§CMD_GATE_PHASE` immediately. Do NOT informally announce readiness — the gate IS the announcement.
3. **If no**: Continue executing the phase's remaining work.

**Constraint**: "Ready to proceed when you give the word" is NEVER a valid substitute for `§CMD_GATE_PHASE`. If you're at a boundary, use the tool.

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

### Step 2S: Detect Active Session

Read `.state.json` from the most recent session directory (or the session specified by the user):
*   **Session dir**: From user args or auto-detected by `/session continue`
*   **Phase**: `currentPhase` from `.state.json`
*   **Skill**: `skill` from `.state.json`
*   **Lifecycle**: `lifecycle` from `.state.json`

If no `.state.json` exists or `lifecycle` is `completed`, inform the user: "No active session found. Use a `/skill` to start one."

### Step 3S: Scan Artifacts

Assess what was actually accomplished in the session:
1. **List session files**: `ls -F sessions/[SESSION_DIR]/`
2. **Check log**: Does `[SKILL_UPPER]_LOG.md` exist? Read the last few entries to understand progress.
3. **Check plan**: Does `[SKILL_UPPER]_PLAN.md` exist? Check which steps are marked `[x]`.
4. **Check debrief**: Does the debrief file exist? If so, synthesis may have already run.
5. **Derive actual state**: Compare `.state.json` phase with artifact evidence. The artifacts are ground truth — the phase claim may be stale if the agent died mid-phase.
6. **Derive sub-phase state**: Read `phaseHistory` from `.state.json` to identify the exact last sub-phase completed. `currentPhase` may store a sub-phase label (e.g., `"5.2: Debrief"`). If it does, the resume point is AT that sub-phase — not at the major phase. Debrief existence does NOT mean synthesis is complete — it only proves sub-phase N.2 ran. Sub-phases N.3 (Pipeline) and N.4 (Close) may still be pending.

### Step 4S: Report Intent

> **Session Resume (Manual)**
>
> Found active session:
> - **Session**: `[SESSION_DIR]`
> - **Skill**: `[SKILL]`
> - **Saved phase**: `[PHASE]`
> - **Artifacts found**: [list: log, plan, debrief, etc.]
> - **Actual progress**: [derived from artifact scan]

### Step 5S: Present Options

Execute `AskUserQuestion` (multiSelect: false):

> "How should I continue this session?"
> - **"Resume at [PHASE]"** — Pick up where the session left off. [1-line description of what remains based on artifact scan.]
> - **"Restart [PHASE]"** — Redo the current phase cleanly. Useful if the previous attempt was incomplete or went wrong.
> - **"Switch skill"** — Start a different skill on this session directory. Will invoke skill selection.

### Step 6S: Execute Choice

*   **"Resume"**: Re-activate session, call `engine session continue`, load skill protocol, resume at saved phase. Same as fast path steps 3F-9F but without dehydrated context — use artifact scan results instead.
*   **"Restart"**: Re-activate session, call `engine session continue`, load skill protocol, re-execute the current phase from scratch (re-read inputs, redo the phase's work).
*   **"Switch skill"**: Present skill picker via `AskUserQuestion`. On selection, invoke `Skill(skill: "[chosen-skill]")`. The new skill handles session directory detection via `§CMD_MAINTAIN_SESSION_DIR`.
*   **"Other" (free-text)**: Treat as new input. Route to the active skill's interrogation phase if it makes sense, or offer skill selection.

### Step 7S: Log the Resume

```bash
engine log sessions/[SESSION_DIR]/[SKILL_UPPER]_LOG.md <<'EOF'
## ♻️ Manual Session Resume
*   **Resumed At**: [PHASE]
*   **Method**: [Resume / Restart / Switch]
*   **Artifacts Found**: [list]
*   **Actual Progress**: [derived state]
EOF
```

---

## Constraints

- **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
- **Fast path: Trust injected context**: The SessionStart hook already loaded the dehydrated summary and required files. Do NOT re-read files that are already in your context (`¶INV_TRUST_CACHED_CONTEXT`).
- **Fast path: Fresh context**: You have ~0% context usage. Do NOT trigger another dehydration.
- **Fast path: Minimal I/O**: Only read the skill SKILL.md (Step 6F) and any files NOT already auto-loaded.
- **Fast path: No re-interrogation**: The original agent already completed interrogation. Use the dehydrated summary.
- **Slow path: Artifact scan is cheap**: Only `ls` and read last log entries. Don't load entire files.
- **Slow path: Phase trust but verify**: `.state.json` phase may be stale. Artifacts are ground truth.
- **Both paths: No re-creation**: Do NOT re-create the session directory or re-parse parameters.

---

## PROOF FOR §CMD_RESUME_SESSION

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "session_reactivated": {
      "type": "boolean",
      "description": "Whether engine session activate succeeded"
    },
    "resume_path": {
      "type": "string",
      "description": "Which path was taken: fast (dehydrated) or slow (bare)"
    },
    "phase_resumed": {
      "type": "string",
      "description": "The phase the agent resumed at"
    }
  },
  "required": ["session_reactivated", "resume_path", "phase_resumed"],
  "additionalProperties": false
}
```
