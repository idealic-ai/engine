### ¶CMD_REPORT_INTENT
**Definition**: Display-only announcement of the current phase's intent. Renders a structured 3-line blockquote (What / How / Not-what) at phase entry, before any steps execute. Serves dual purpose: user progress signal + agent cognitive anchoring (self-affirmation before starting work).
**Trigger**: Called as the first step of each applicable phase. The SKILL.md provides per-phase content as a blockquote template immediately after the `§CMD_REPORT_INTENT` reference.

---

## Algorithm

### Step 1: Read Phase Content

The SKILL.md phase section contains a blockquote template immediately after `§CMD_REPORT_INTENT`:

```markdown
`§CMD_REPORT_INTENT`:
> [Line 1: What + Trigger]
> [Line 2: How / Focus]
> [Line 3: Not-what / Exclusions]
```

The agent reads this template and fills in any `___` placeholders with values from the current context (session parameters, prior phase outputs, user selections).

### Step 2: Fill Placeholders

Replace `___` blanks with actual values. Only reference values that are **already available** at phase entry — values from prior phases or session parameters.

**Temporal Rule** (`¶INV_INTENT_TEMPORAL_RULE`): Intent MUST NOT reference values produced by steps within the same phase. Intent renders at phase entry, before any steps execute. If a value isn't available yet, leave the blank or use a generic descriptor.

**Examples**:
*   Phase 0 cannot mention mode (mode is selected in Phase 0's steps)
*   Phase 1 can mention mode (selected in Phase 0)
*   Phase 3.A can mention plan step count (plan was created in Phase 2)

### Step 3: Render

Output the filled blockquote in chat. This is the agent's announcement of what it's about to do.

**Format** (strict 3-line):
```
> [What]: [Action verb + topic]. [Trigger or context].
> [How]: [Focus areas, tools, commands, or artifacts in play].
> [Not-what]: [What this phase explicitly does NOT do].
```

**Line semantics**:
*   **Line 1 (What)**: Identity of the phase. Starts with a gerund matching the skill verb. Includes trigger/context. User-facing — answers "what's happening?"
*   **Line 2 (How)**: Focus areas. What tools, commands, or artifacts are in play. Agent-facing — anchors the agent on scope.
*   **Line 3 (Not-what)**: Exclusions. What this phase does NOT do. Prevents scope creep. Required for all phases — even when exclusions seem obvious, stating them reinforces boundaries.

### Step 4: Record

No further action. The intent is display-only. Proof (`intent_reported: true`) is collected at phase transition.

---

## Scope

**Required for**:
*   Major phases (Phase 0, 1, 2, 3, 4, etc.)
*   Work branches (Phase 3.A, 3.B, 3.C, etc.)

**NOT required for**:
*   Synthesis sub-phases (N.1 Checklists, N.2 Debrief, N.3 Pipeline, N.4 Close)
*   Gateway phases (Phase N: Execution — these just present a choice)
*   Utility-tier skills (engine, session, delegation-* — no phases)

---

## Content Ownership

**Shape + Content split**: This command defines the 3-line structure (shape). Each SKILL.md phase provides the specific words (content). The command enforces format; the skill provides substance.

**Per-phase templates**: Each SKILL.md phase section contains its own blockquote with `___` placeholders. These are the per-phase content templates — they vary by skill and phase.

**Override model**: There is no "default template" to fall back on. Every phase that requires intent MUST have a blockquote in its SKILL.md section. If a phase lacks a blockquote, the agent writes one following the 3-line format using its understanding of the phase's purpose.

---

## Constraints

*   **Once per phase**: Do NOT repeat the intent block for every step within a phase. Only render when entering a new phase or resuming after interruption.
*   **No `AskUserQuestion`**: This is display-only. No user interaction.
*   **No logging**: Intent is rendered in chat, not logged. The log captures work outputs, not announcements.
*   **Temporal rule is absolute**: `¶INV_INTENT_TEMPORAL_RULE` — no exceptions. If you're tempted to reference a value from a step in the same phase, that's your signal that the reference is invalid.
*   **3 lines required**: All three lines must be present. The "Not-what" line is mandatory even when exclusions seem obvious — stating boundaries reinforces them.
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration beyond the 3-line intent block.

---

## Examples

### Good — Phase 0 (Setup)
```
> Implementing auth middleware. Trigger: user story #42.
> Focus: session activation, mode selection, context loading.
> Not: writing code or tests — setup only.
```

### Good — Phase 1 (Interrogation, mode already selected)
```
> Interrogating auth middleware assumptions. Mode: TDD.
> Drawing from scope, data flow, testing, and risk topics.
> Not: planning or writing code — information gathering only.
```

### Bad — Phase 0 referencing mode (not yet selected)
```
> Implementing auth middleware. Mode: TDD.        ← VIOLATION: mode selected in Phase 0 steps
> Focus: session activation, mode selection.
> Not: writing code.
```

### Good — Phase 3.A (Build Loop)
```
> Executing 5-step build plan. Target: ClerkAuthGuard.
> Approach: Red-Green-Refactor per TDD mode configuration.
> Not: planning or interrogation — executing the approved plan.
```

---

## PROOF FOR §CMD_REPORT_INTENT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "intentReported": {
      "type": "string",
      "description": "Intent summary (e.g., 'reported: Build Loop phase')"
    }
  },
  "required": ["intentReported"],
  "additionalProperties": false
}
```
