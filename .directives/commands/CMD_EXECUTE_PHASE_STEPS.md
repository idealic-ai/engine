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

---

## Constraints

- **Self-affirmation**: If phase stdout includes `Invariants:`, self-affirm each before executing steps: `> I will follow ¶INV_X, because [your reasoning]`. Cognitive anchoring — articulating the reason primes attention.
- **Sub-indexing**: Steps are numbered from the phase label — Phase `1` → `1.1`, `1.2`; Phase `3.A` → `3.A.1`, `3.A.2`. Use these numbers in roll call output.
- **Empty phases**: Phases with `steps: []` are prose-only. This command returns immediately. Valid for iterative work phases (Build Loop, Research Loop).
- **No step-level checkpointing**: If context overflows mid-phase, recovery restarts at the phase level. The LLM uses the log to determine which steps were completed.
- **Steps are commands**: Every entry in `steps` MUST be a `§CMD_*` reference (`¶INV_STEPS_ARE_COMMANDS`). Prose instructions are not steps.
- **Proof is cumulative**: Phase proof = union of all step proof schemas + any phase-level data fields (like `mode`, `session_dir`).
- **Preloading is automatic**: The hook preloads CMD files for all steps and commands when you transition into a phase. To **edit** a preloaded file, call Read first (`¶INV_PRELOAD_IS_REFERENCE_ONLY`).
- **`¶INV_PROTOCOL_IS_TASK`**: The protocol defines the task — do not skip steps or reorder them.

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
    }
  },
  "required": ["executed"],
  "additionalProperties": false
}
```
