### §CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH
**Definition**: Standardized phase boundary menu that replaces ad-hoc `AskUserQuestion` blocks at phase transitions. Presents 3 core options — proceed to next phase, walk through current phase's output, go back to previous phase — plus an optional 4th skill-specific option.
**Concept**: "What do you want to do at this phase boundary?"
**Trigger**: Called by skill protocols at phase boundaries (after `§CMD_VERIFY_PHASE_EXIT`). Replaces the manual `### Phase Transition` / `AskUserQuestion` pattern.

---

## Configuration

Each invocation is configured inline in the skill's SKILL.md:

```
Execute §CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH:
  completedPhase: "N: Name"
  nextPhase: "N+1: Name"
  prevPhase: "N-1: Name"
  custom: "Label | Description"    # Optional — 4th option
```

**Fields**:
*   `completedPhase` — The phase that just finished. Used in the question text.
*   `nextPhase` — Where "Proceed" goes. Fires `§CMD_UPDATE_PHASE` normally (sequential forward).
*   `prevPhase` — Where "Go back" goes. Fires `§CMD_UPDATE_PHASE` with `--user-approved "User chose 'Go back to [prevPhase]'"`.
*   `custom` — Optional 4th option. Format: `"Label | Description"`. If omitted, the menu has 3 options.

---

## Algorithm

### Step 1: Present Menu

Execute `AskUserQuestion` (multiSelect: false):

> "Phase [completedPhase] complete. How to proceed?"
> - **"Proceed to [nextPhase]"** — Continue to the next phase
> - **"Walkthrough"** — Review this phase's output before moving on
> - **"Go back to [prevPhase]"** — Return to the previous phase
> - **"[custom label]"** *(if configured)* — [custom description]

**Option order**: Proceed (default forward path) → Walkthrough → Go back → Custom.

### Step 2: Execute Choice

*   **"Proceed"**: Fire `§CMD_UPDATE_PHASE` with `nextPhase`. Return control to the skill protocol for the next phase.

*   **"Walkthrough"**: Invoke `§CMD_WALK_THROUGH_RESULTS` ad-hoc on the current phase's artifacts. After the walk-through completes, **re-present this same menu** (the user may now want to proceed, go back, or walk through again with different granularity).

*   **"Go back"**: Fire `§CMD_UPDATE_PHASE` with `prevPhase` and `--user-approved "User chose 'Go back to [prevPhase]'"`. Return control to the skill protocol for the previous phase.

*   **"[custom]"**: Execute the skill-specific action described in the custom option. The skill protocol defines what this does (e.g., skip forward, launch agent, run verification).

*   **"Other" (free-text)**: The user typed something outside the options. Treat as new input:
    *   If it describes new requirements → route to interrogation phase (use `§CMD_UPDATE_PHASE` with `--user-approved`).
    *   If it's a clarification → answer in chat, then re-present the menu.

---

## Constraints

*   **Max 4 options**: AskUserQuestion limit. 3 core + 1 custom. If no custom, 3 options (+ implicit "Other").
*   **Context before question** (`¶INV_QUESTION_GATE_OVER_TEXT_GATE`): The `§CMD_VERIFY_PHASE_EXIT` proof block that precedes this command provides the context. No additional narration needed.
*   **Walkthrough is always available**: `§CMD_WALK_THROUGH_RESULTS` works ad-hoc on whatever artifacts exist in the session directory. No explicit walkthrough config block required.
*   **Go back uses --user-approved**: Backward transitions are non-sequential per `§CMD_UPDATE_PHASE` enforcement. The user's menu choice is auto-quoted as the approval reason.
*   **Re-presentation after walkthrough**: After a walkthrough completes, the menu is shown again. This allows the user to walk through, then decide.
*   **Phase 1 edge case**: If `prevPhase` would be before Phase 1 (no previous phase exists), omit the "Go back" option entirely. Menu becomes 2 core + optional custom.

---

## Integration Guide

### Replacing Existing Phase Transition Blocks

**Before** (ad-hoc pattern in SKILL.md):
```markdown
### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Context loaded. How to proceed?"
> - **"Proceed to Phase 3: Interrogation"** — Validate assumptions before planning
> - **"Stay in Phase 2"** — Load more files or context
> - **"Skip to Phase 4: Planning"** — I already have a clear plan
```

**After** (standardized):
```markdown
### Phase Transition
Execute §CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH:
  completedPhase: "2: Context Ingestion"
  nextPhase: "3: Interrogation"
  prevPhase: "1: Setup"
  custom: "Skip to 4: Planning | Requirements are obvious, jump to planning"
```

### Special Cases

**Remove entirely (no replacement needed)**:
*   **Phase 0→1 (Setup→Context Ingestion)** → Setup always proceeds to Context Ingestion. No user question needed — just flow through. Remove the Phase Transition block entirely and replace with a comment: *"Phase 0 always proceeds to Phase 1 — no transition question needed."*

**Do NOT replace (keep existing patterns)**:
*   **`§CMD_EXECUTE_INTERROGATION_PROTOCOL` exit gate** → The interrogation protocol's Step 3 handles its own exit with depth-based gating. However, when the user selects "Proceed to next phase" in the exit gate, the protocol SHOULD fire this command for the actual transition (providing the walkthrough option at the interrogation→planning boundary).
*   **`§CMD_PARALLEL_HANDOFF` boundaries** → Plan→Build transitions in implement/test that offer agent handoff keep their specialized menu.
*   **Synthesis phase transitions** → Post-synthesis uses `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`, not this command.

### Skills That Should Adopt This

All skills with phase-based protocols:
*   `/implement` — 1→2 (via interrogation exit), 4→5. Phase 0→1 removed. (Phase 0 = Setup)
*   `/analyze` — All applicable phase boundaries. Phase 0→1 removed. (Phase 0 = Setup)
*   `/brainstorm` — All applicable phase boundaries. Phase 0→1 removed. (Phase 0 = Setup)
*   `/test` — All applicable phase boundaries. Phase 0→1 removed. (Phase 0 = Setup)
*   `/document` — All applicable phase boundaries. Phase 0→1 removed. (Phase 0 = Setup)
*   `/fix` — All applicable phase boundaries. Phase 0→1 removed. (Phase 0 = Setup)
*   `/refine-docs` — All applicable phase boundaries. Phase 0→1 removed. (Phase 0 = Setup)
