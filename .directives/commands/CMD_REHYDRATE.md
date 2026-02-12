### §CMD_REHYDRATE
**Definition**: Re-initializes session context after context overflow restart. The SessionStart hook auto-injects dehydrated content and required files from `.state.json`. This command tells the agent how to resume.

**Trigger**: Invoked automatically when a fresh Claude starts and the SessionStart hook injects dehydrated context (visible as `## Session Recovery (Dehydrated Context)` in the initial system message).

**Preloaded**: Always — this file is injected by SessionStart hook alongside the dehydrated context.

---

## Algorithm

### Step 1: Verify Recovery Context

Check that the SessionStart hook injected dehydrated context. You should see:
- `## Session Recovery (Dehydrated Context)` in your initial context
- Session name, skill, and phase
- Summary, last action, next steps
- Required files auto-loaded (as `#### File: ...` blocks)

If this is NOT present, you are not in a recovery scenario. Ignore this command.

### Step 2: Report Intent

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

### Step 3: Re-Activate Session

```bash
engine session activate sessions/[SESSION_DIR] [SKILL] < /dev/null
```

This re-registers the Claude process with the session. Use `< /dev/null` — no new parameters needed (session already has them from the original activation).

### Step 4: Resume Session Tracking

```bash
engine session continue sessions/[SESSION_DIR]
```

This clears the `loading` flag and resets heartbeat counters. The saved phase in `.state.json` is the source of truth — `continue` resumes the heartbeat at that phase.

### Step 5: Log the Restart

```bash
engine log sessions/[SESSION_DIR]/[SKILL_UPPER]_LOG.md <<'EOF'
## ♻️ Context Overflow Restart
*   **Resumed At**: [PHASE]
*   **Last Action**: [from dehydrated context summary]
*   **Next Steps**: [from dehydrated context next steps]
EOF
```

### Step 6: Load Skill Protocol

Read the original skill's SKILL.md so you know how to continue:
```
~/.claude/skills/[SKILL]/SKILL.md
```

### Step 7: Resume at Saved Phase

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

### Step 8: Announce Resume

> **Resuming `[SKILL]`** at `[PHASE]`
>
> **Context restored from**: `.state.json` (auto-injected by SessionStart)
> - **Goal**: [from summary]
> - **Last Action**: [from lastAction]
> - **Next Steps**: [from nextSteps]
>
> Continuing now...

---

## Constraints

- **Trust injected context**: The SessionStart hook already loaded the dehydrated summary and required files. Do NOT re-read files that are already in your context (`¶INV_TRUST_CACHED_CONTEXT`).
- **Fresh context**: You have ~0% context usage. Do NOT trigger another dehydration.
- **Minimal I/O**: Only read the skill SKILL.md (Step 6) and any files NOT already auto-loaded.
- **No re-interrogation**: The original agent already completed interrogation. Use the dehydrated summary.

---

## PROOF FOR §CMD_REHYDRATE

```json
{
  "session_reactivated": {
    "type": "boolean",
    "description": "Whether engine session activate succeeded",
    "examples": [true]
  },
  "phase_resumed": {
    "type": "string",
    "description": "The phase the agent resumed at",
    "examples": ["3: Build Loop", "4: Synthesis"]
  }
}
```
