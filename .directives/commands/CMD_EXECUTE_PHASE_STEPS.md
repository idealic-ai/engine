### ¶CMD_EXECUTE_PHASE_STEPS
**Definition**: Per-phase step runner. Reads the current phase's `steps` array from `.state.json`, executes each step command sequentially, and collects proof outputs.
**Concept**: "Here are this phase's mechanical steps — execute them in order."
**Trigger**: Called within each phase section of SKILL.md, typically after `§CMD_REPORT_INTENT`.

---

## Algorithm

### Step 1: Read Phase Steps

The current phase's steps are available from `engine session phase` stdout (already displayed when transitioning into this phase):

```
Steps:
  1.1: §CMD_INTERROGATE
  1.2: §CMD_LOG_INTERACTION
```

If no `Steps:` section appeared in the transition stdout, or the steps list is empty, this phase has no mechanical steps. Skip to Step 3.

### Step 2: Execute Steps Sequentially

For each step `N.M:` `§CMD_X`:

1. **Roll Call (Announce)**: Prefix your chat output with the step number from the engine's listing: `N.M. §CMD_X — [brief result]`. This creates a numbered roll call matching the engine's step listing. Example: `4.3.1. §CMD_MANAGE_DIRECTIVES — scanned 2 dirs, no updates needed`.
2. **Locate the command**: The CMD file (`CMD_X.md`) was preloaded by the `post-tool-use-phase-commands.sh` hook during the phase transition. It should already be in your context for reference. **To edit a preloaded CMD file, Read it first** (`¶INV_PRELOAD_IS_REFERENCE_ONLY`).
3. **Execute**: Follow the command definition exactly as written in `CMD_X.md`.
4. **Collect proof**: After the command completes, note the proof fields specified in the `## PROOF FOR` `§CMD_X` section of the CMD file. These become part of the phase's proof when transitioning out.
5. **Proceed to next step**: Move to step `N.(M+1)`.

**Rules**:
- Execute steps in declared order. Do NOT skip or reorder.
- If a step fails or blocks, log it (`§CMD_APPEND_LOG`) and continue to the next step if possible. If the block is fatal, stop and `§CMD_ASK_USER_IF_STUCK`.
- After all steps complete, return control to the SKILL.md prose section. The prose may add additional work after the mechanical steps.

### Step 3: Return to Prose

After all steps execute (or if there are no steps), the phase continues with whatever prose follows in SKILL.md. The mechanical protocol is done — skill-specific content takes over.

### Step 4: Phase Gate

After SKILL.md prose completes, check whether gating is enabled for this phase. The `Gate:` line from `engine session phase` stdout (displayed when transitioning INTO this phase) indicates the gate setting:

*   **`Gate: true`** (or absent — default): Run the gate menu below.
*   **`Gate: false`**: Skip the gate. Return control to the skill orchestrator to transition immediately.

**Gate Algorithm**:

1.  **Derive Phases**: Read `currentPhase` from `.state.json`. Look up the `phases` array to determine:
    *   **Next phase**: First entry after current (by major.minor order).
    *   **Previous phase**: Last entry before current (by major.minor order).
    *   **Current phase proof fields**: The `proof` array on the current phase entry (if declared).

2.  **Present Menu**: Invoke §CMD_DECISION_TREE with the phase gate tree below. Use preamble context to fill in current/next/previous phase names and any custom option.

    **Option order**: Proceed (default forward path) > Walkthrough > Go back > Custom.

3.  **Execute Choice**:
    *   **`NEXT`**: Pipe proof fields via STDIN to `engine session phase` for the current phase (proving it was completed). If the current phase declares `proof` fields, you MUST provide them as JSON.
    *   **`VIEW`**: Invoke §CMD_WALK_THROUGH_RESULTS ad-hoc on the current phase's artifacts. After the walk-through completes, **re-present this same menu**.
    *   **`PREV`**: Fire `§CMD_UPDATE_PHASE` with `prevPhase` and `--user-approved "User chose 'Go back to [prevPhase]'"`. Return control to the skill protocol for the previous phase.
    *   **`MORE/REDO`**: Re-execute the current phase from scratch.
    *   **`MORE/JUMP`**: Jump past the next phase. Requires `--user-approved`.
    *   **`MORE/XTRA`**: Add more work items to the current phase before moving on. Agent asks for the new items, logs them, and re-enters the phase execution loop.
    *   **`MORE/custom:*`** (free text or skill-specific custom): If it matches a configured custom action, execute it. If it describes new requirements → route to interrogation phase (use `§CMD_UPDATE_PHASE` with `--user-approved`). If it's a clarification → answer in chat, re-present the menu.

**Proof-Gated Transitions**: When the current phase declares `proof` fields, pipe proof as JSON via STDIN to `engine session phase` (FROM validation). Missing or unfilled fields reject the transition (exit 1). No `proof` array → transition proceeds without STDIN.

### ¶ASK_PHASE_GATE
Trigger: at every phase boundary where `Gate: true` (default)
Extras: A: View current phase output summary | B: View remaining phases | C: Check time spent in this phase

## Decision: Phase Gate
- [NEXT] Next phase
  Continue to the next phase
- [VIEW] See output
  Review this phase's output before moving on
- [PREV] Previous
  Return to the previous phase
- [MORE] Other
  - [REDO] Again
    Redo the current phase from scratch
  - [JUMP] Jump ahead
    Jump forward past the next phase (requires approval)
  - [XTRA] Extend phase
    Add more work items to current phase before moving on

---

## Constraints

### Step Execution
- **Self-affirmation**: If phase stdout includes `Invariants:`, self-affirm each before executing steps: `> I will follow ¶INV_X, because [your reasoning]`. Cognitive anchoring — articulating the reason primes attention.
- **Sub-indexing**: Steps are numbered from the phase label — Phase `1` → `1.1`, `1.2`; Phase `3.A` → `3.A.1`, `3.A.2`. Use these numbers in roll call output.
- **Empty phases**: Phases with `steps: []` are prose-only. This command returns immediately (skipping to Step 4). Valid for iterative work phases (Build Loop, Research Loop).
- **No step-level checkpointing**: If context overflows mid-phase, recovery restarts at the phase level. The LLM uses the log to determine which steps were completed.
- **Steps are commands**: Every entry in `steps` MUST be a `§CMD_*` reference (`¶INV_STEPS_ARE_COMMANDS`). Prose instructions are not steps.
- **Proof is cumulative**: Phase proof = union of all step proof schemas + any phase-level data fields (like `mode`, `session_dir`).
- **Preloading is automatic**: The hook preloads CMD files for all steps and commands when you transition into a phase. To **edit** a preloaded file, call Read first (`¶INV_PRELOAD_IS_REFERENCE_ONLY`).
- **`¶INV_PROTOCOL_IS_TASK`**: The protocol defines the task — do not skip steps or reorder them.

### Phase Gate
- **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in the gate MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
- **Max 4 options**: AskUserQuestion limit. 3 core + 1 custom. If no custom, 3 options (+ implicit "Other").
- **Walkthrough is always available**: §CMD_WALK_THROUGH_RESULTS works ad-hoc on whatever artifacts exist in the session directory.
- **Go back uses --user-approved**: Backward transitions are non-sequential per `§CMD_UPDATE_PHASE` enforcement. The user's menu choice is auto-quoted as the approval reason.
- **Re-presentation after walkthrough**: After a walkthrough completes, the menu is shown again.
- **First phase edge case**: If there is no previous phase, omit the "Go back" option. Menu becomes 2 core + optional custom.
- **Gate: false phases**: Setup→Phase 1 auto-flow, synthesis sub-phase transitions, and similar seamless transitions should use `gate: false` in their phase entry.

---

## PROOF FOR §CMD_EXECUTE_PHASE_STEPS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "stepsCompleted": {
      "type": "string",
      "description": "Count and names of steps completed (e.g., '3 steps: interrogate, log, gate')"
    },
    "userChoice": {
      "type": "string",
      "enum": ["proceed", "walkthrough", "back", "custom", "other", "gate_skipped"],
      "description": "The user's choice at the phase gate, or 'gate_skipped' if gate: false"
    },
    "phaseGated": {
      "type": "string",
      "description": "The phase being gated (completed phase)"
    },
    "nextPhase": {
      "type": "string",
      "description": "The next phase if user chose proceed"
    },
    "proofProvided": {
      "type": "string",
      "description": "Proof status (e.g., 'yes, 3 fields piped' or 'no proof required')"
    }
  },
  "required": ["executed"],
  "additionalProperties": false
}
```
