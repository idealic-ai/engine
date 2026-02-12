### §CMD_EXECUTE_SKILL_PHASES
**Definition**: Skill-level phase orchestrator. Lives at the TOP of each SKILL.md. Drives the agent through all phases sequentially, calling `§CMD_EXECUTE_PHASE_STEPS` within each phase's prose section.
**Concept**: "Run through all my phases from start to finish."
**Trigger**: Invoked at the beginning of every protocol-tier skill execution. It's the first instruction the LLM reads.

---

## Placement

This command is invoked at the very top of SKILL.md, before any phase section (`¶INV_BOOT_SECTOR_AT_TOP`):

```markdown
# [Skill Name] Protocol

Execute `§CMD_EXECUTE_SKILL_PHASES` to run through all phases below.

---

## 0. Setup
[...]

## 1. Interrogation
[...]
```

---

## Algorithm

### Step 1: Identify Current Phase

Read `currentPhase` from `.state.json`. This tells you where the skill execution currently is:
- **Fresh session**: Start at Phase 0 (Setup).
- **Resumed session** (after context overflow): Start at the saved phase.

### Step 2: Execute Current Phase

Find the matching phase section in SKILL.md (e.g., `## 0. Setup`, `## 1. Interrogation`). Follow the prose instructions, which will include a call to `§CMD_EXECUTE_PHASE_STEPS` for mechanical steps.

### Step 3: Transition to Next Phase

When the current phase's work is complete, transition via `engine session phase` (either directly or through `§CMD_GATE_PHASE`). This:
1. Records proof for the phase being left (FROM validation)
2. Updates `currentPhase` in `.state.json`
3. Outputs the new phase's steps/commands/proof in stdout
4. Triggers the hook to preload CMD files for the new phase

### Step 4: Repeat

Return to Step 2 for the next phase. Continue until all phases are complete (synthesis pipeline closes the session).

---

## Phase Sequence

The phases array in `.state.json` defines the sequence. Phases are ordered by `major.minor`:

```
0.0: Setup → 1.0: Interrogation → 2.0: Planning → 3.0: Build Loop → ...
```

Sub-phases (minor > 0) are alternative paths or post-processing steps within a major phase:
- `3.0: Build Loop` — inline execution
- `3.1: Agent Handoff` — single agent delegation
- `3.2: Parallel Agent Handoff` — multi-agent delegation

The agent follows whichever path the user chose. Not all sub-phases execute — routing decisions determine which one is active.

---

## Interaction with Phase Prose

This command does NOT replace the phase sections in SKILL.md. It orchestrates WHEN each phase runs. The actual phase content (intent blocks, `§CMD_EXECUTE_PHASE_STEPS` calls, skill-specific topics, transition gates) lives in the prose.

Think of this command as the outer loop, and each phase section as the loop body.

---

## Context Overflow Recovery

If context overflows mid-skill:
1. The session's `currentPhase` in `.state.json` records where you stopped.
2. On recovery (`/session continue`), this command picks up at the saved phase — it does NOT restart from Phase 0.
3. The dehydrated context provides what was accomplished so far.

---

## Constraints

- **Boot sector position**: This must be the first instruction in SKILL.md (`¶INV_BOOT_SECTOR_AT_TOP`).
- **No phase skipping**: Execute phases in order. The only exception is user-approved skips via `§CMD_GATE_PHASE` custom options.
- **No backward jumps without approval**: Moving to an earlier phase requires `--user-approved` flag on `engine session phase`.
- **Utility-tier skills don't use this**: Only protocol-tier skills (with phases arrays) use the boot sector. Sessionless utilities (do, session, engine, fleet, etc.) have no phases.

---

## PROOF FOR §CMD_EXECUTE_SKILL_PHASES

This command does not produce its own proof. It orchestrates the phase sequence — proof is collected at the phase level by `§CMD_EXECUTE_PHASE_STEPS` and phase transitions.
