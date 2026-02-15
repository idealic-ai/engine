### ¶CMD_GATE_PHASE
**Definition**: Standardized phase boundary menu. Presents options to proceed (with proof), walk through current output, go back, or take a skill-specific action. Derives current/next/previous phases from the `phases` array in `.state.json`.
**Concept**: "What do you want to do at this phase boundary?"
**Trigger**: Called by skill protocols at phase boundaries.

---

## Configuration

Each invocation is configured inline in the skill's SKILL.md. Since the phases array declares the sequence, only the optional `custom` field is needed:

```
Execute `§CMD_GATE_PHASE`.
```

Or with a custom 4th option:

```
Execute `§CMD_GATE_PHASE`:
  custom: "Label | Description"
```

**Fields**:
*   `custom` — Optional 4th option. Format: `"Label | Description"`. If omitted, the menu has 3 options.

**Derived from `.state.json`**:
*   `currentPhase` — Read from `.state.json`. Used as the completed phase in the question text.
*   `nextPhase` — The next sequential phase in the `phases` array (sort by major, minor; find first after current).
*   `prevPhase` — The previous phase in the `phases` array (sort by major, minor; find last before current).

---

## Algorithm

### Step 1: Derive Phases

Read `currentPhase` from `.state.json`. Look up the `phases` array to determine:
*   **Next phase**: First entry after current (by major.minor order).
*   **Previous phase**: Last entry before current (by major.minor order).
*   **Current phase proof fields**: The `proof` array on the current phase entry (if declared). Proof validates what was just completed (FROM validation).

### Step 2: Present Menu

Invoke `§CMD_DECISION_TREE` with `§ASK_PHASE_GATE`. Use preamble context to fill in current/next/previous phase names and the custom option (if configured).

**Option order**: Proceed (default forward path) > Walkthrough > Go back > Custom.

### Step 3: Execute Choice

*   **`PRC`** (Proceed): Pipe proof fields via STDIN to `engine session phase` for the current phase (proving it was completed). If the current phase declares `proof` fields, you MUST provide them as JSON. See **Proof-Gated Transitions** below.

*   **`WLK`** (Walk through): Invoke `§CMD_WALK_THROUGH_RESULTS` ad-hoc on the current phase's artifacts. After the walk-through completes, **re-present this same menu**.

*   **`BAK`** (Go back): Fire `§CMD_UPDATE_PHASE` with `prevPhase` and `--user-approved "User chose 'Go back to [prevPhase]'"`. Return control to the skill protocol for the previous phase.

*   **`OTH/RST`** (Restart this phase): Re-execute the current phase from scratch (re-read inputs, redo the phase's work).

*   **`OTH/SKP`** (Skip ahead): Jump past the next phase. Requires `--user-approved`.

*   **`OTH/custom:*`** (free text or skill-specific custom): If it matches a configured custom action, execute it. If it describes new requirements → route to interrogation phase (use `§CMD_UPDATE_PHASE` with `--user-approved`). If it's a clarification → answer in chat, re-present the menu.

---

## Proof-Gated Transitions

When the current phase declares `proof` fields, pipe proof as JSON via STDIN to `engine session phase` (FROM validation — proving what was just completed). Missing or unfilled fields reject the transition (exit 1). No `proof` array → transition proceeds without STDIN.

---

## Constraints

*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **Max 4 options**: AskUserQuestion limit. 3 core + 1 custom. If no custom, 3 options (+ implicit "Other").
*   **Walkthrough is always available**: `§CMD_WALK_THROUGH_RESULTS` works ad-hoc on whatever artifacts exist in the session directory.
*   **Go back uses --user-approved**: Backward transitions are non-sequential per `§CMD_UPDATE_PHASE` enforcement. The user's menu choice is auto-quoted as the approval reason.
*   **Re-presentation after walkthrough**: After a walkthrough completes, the menu is shown again.
*   **First phase edge case**: If there is no previous phase, omit the "Go back" option. Menu becomes 2 core + optional custom.

---

### ¶ASK_PHASE_GATE
Trigger: at every phase boundary (except: Setup→Phase 1 auto-flow, interrogation exit gate, parallel handoff completion, synthesis sub-phase transitions)
Extras: A: View current phase output summary | B: View remaining phases | C: Check time spent in this phase

## Decision: Phase Gate
- [PRC] Proceed to next phase
  Continue to the next phase
- [WLK] Walk through output
  Review this phase's output before moving on
- [BAK] Go back
  Return to the previous phase
- [OTH] Other
  - [RST] Restart this phase
    Redo the current phase from scratch
  - [SKP] Skip ahead
    Jump forward past the next phase (requires approval)

---

## PROOF FOR §CMD_GATE_PHASE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "userChoice": {
      "type": "string",
      "enum": ["proceed", "walkthrough", "back", "custom", "other"],
      "description": "The user's choice at the phase gate"
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
  "required": ["executed", "userChoice", "phaseGated"],
  "additionalProperties": false
}
```
