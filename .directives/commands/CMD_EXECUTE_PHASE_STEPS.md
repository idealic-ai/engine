### §CMD_EXECUTE_PHASE_STEPS
**Definition**: Per-phase step runner. Reads the current phase's `steps` array from `.state.json`, executes each step command sequentially, and collects proof outputs.
**Concept**: "Here are this phase's mechanical steps — execute them in order."
**Trigger**: Called within each phase section of SKILL.md, typically after `§CMD_REPORT_INTENT_TO_USER`.

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

For each step `N.M: §CMD_X`:

1. **Locate the command**: The CMD file (`CMD_X.md`) was preloaded by the `post-tool-use-phase-commands.sh` hook during the phase transition. It should already be in your context.
2. **Execute**: Follow the command definition exactly as written in `CMD_X.md`.
3. **Collect proof**: After the command completes, note the proof fields specified in the `## PROOF FOR §CMD_X` section of the CMD file. These become part of the phase's proof when transitioning out.
4. **Proceed to next step**: Move to step `N.(M+1)`.

**Rules**:
- Execute steps in declared order. Do NOT skip or reorder.
- If a step fails or blocks, log it (`§CMD_APPEND_LOG`) and continue to the next step if possible. If the block is fatal, stop and `§CMD_ASK_USER_IF_STUCK`.
- After all steps complete, return control to the SKILL.md prose section. The prose may add additional work after the mechanical steps.

### Step 3: Return to Prose

After all steps execute (or if there are no steps), the phase continues with whatever prose follows in SKILL.md. The mechanical protocol is done — skill-specific content takes over.

---

## Self-Affirmation of Invariants

If the phase stdout includes an `Invariants:` section, the agent MUST self-affirm each invariant before executing steps:

```markdown
> I will follow invariants:
> * ¶INV_CONCISE_CHAT, because ____
> * ¶INV_SKILL_PROTOCOL_MANDATORY, because ____
```

The agent fills in the blanks with its own understanding of WHY this invariant matters for the current phase. This is cognitive anchoring — the act of articulating the reason primes attention to the constraint throughout the phase.

**Rules**:
- Self-affirm BEFORE executing any steps (it's the first output after the intent block).
- Fill every blank — do NOT leave `____` unfilled.
- Keep reasons concise (one phrase or sentence).
- If an invariant is unfamiliar, state that: "because I need to read this invariant to understand it."

---

## Interaction with SKILL.md Prose

This command is called WITHIN prose, not instead of it. The pattern:

```markdown
## N. Phase Name

`§CMD_REPORT_INTENT_TO_USER`:
> [intent block]

Execute `§CMD_EXECUTE_PHASE_STEPS`.

### Skill-Specific Content
[Topics, question banks, configuration, etc.]
```

The prose WRAPS the protocol. Examples:
- "Execute `§CMD_EXECUTE_PHASE_STEPS`. After steps complete, review the topics below for additional context."
- "Before executing `§CMD_EXECUTE_PHASE_STEPS`, note that this skill uses a modified interrogation approach."

---

## Step Sub-Indexing

Steps are numbered with sub-indices derived from the phase label:
- Phase `1` → steps `1.1`, `1.2`, `1.3`
- Phase `2.1` → steps `2.1.1`, `2.1.2`
- Phase `3.A` → steps `3.A.1`, `3.A.2`

This creates a hierarchy (phase.step) readable in logs and audit trails.

---

## Empty Phases

Phases with `steps: []` (or no `steps` array) are prose-only. `§CMD_EXECUTE_PHASE_STEPS` has nothing to execute — it returns immediately. The phase runs entirely on SKILL.md prose.

This is valid and expected for iterative work phases (Build Loop, Research Loop, Testing Loop) where the work pattern is inherently non-sequential.

---

## Constraints

- **No step-level checkpointing**: If context overflows mid-phase, recovery restarts at the phase level. The LLM uses the log to determine which steps were completed.
- **Steps are commands**: Every entry in `steps` MUST be a `§CMD_*` reference (`¶INV_STEPS_ARE_COMMANDS`). Prose instructions are not steps.
- **Proof is cumulative**: Phase proof = union of all step proof schemas + any phase-level data fields (like `mode`, `session_dir`).
- **Preloading is automatic**: The hook preloads CMD files for all steps and commands when you transition into a phase. You don't need to manually load them.

---

## PROOF FOR §CMD_EXECUTE_PHASE_STEPS

This command does not produce its own proof. The proof comes from the individual steps it executes — each step's `## PROOF FOR §CMD_X` schema contributes to the phase proof.
