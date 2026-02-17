### ¶CMD_SELECT_EXECUTION_PATH
**Definition**: Presents a choice between mutually exclusive execution paths. This is the sole step of a **gateway phase** — a flat numbered phase (e.g., `3: Execution`) that always runs, followed by letter-labeled branch phases (`3.A`, `3.B`, `3.C`) of which exactly one is entered.
**Rule**: Exactly one path is chosen. The unchosen paths are skipped entirely.

---

## Algorithm

### Step 1: Discover Paths

Read `.state.json` to get the `phases` array and `currentPhase`. Identify **candidate paths** — the branch phases (letter-labeled) that share the same major number as the current gateway phase.

**Discovery logic**:
1. Get the current phase's major number `N` (e.g., if current is `3: Execution`, N=3).
2. Collect all phases with labels matching `N.A`, `N.B`, `N.C`, etc. — these are the mutually exclusive branch paths.
3. If no branch candidates exist, skip this command -- proceed directly to the next phase via `§CMD_EXECUTE_PHASE_STEPS` (which handles the gate automatically).

**Path types** (by convention):
*   **`N.A`**: Inline execution — the agent does the work in this conversation (Build Loop, Fix Loop, Testing Loop, Operation, etc.)
*   **`N.B`**: Single agent handoff — `§CMD_HANDOFF_TO_AGENT`
*   **`N.C`**: Parallel agent handoff — `§CMD_PARALLEL_HANDOFF`

Letter suffixes are convention, not enforced. The paths are whatever the skill declares.

### Step 2: Present Choice

Invoke §CMD_DECISION_TREE with `§ASK_EXECUTION_PATH`. Use preamble context to describe the discovered paths (from Step 1) with their phase names from the manifest.

**Option order**: Inline first (recommended default), then single agent, then parallel.

### Step 3: Transition to Chosen Path

Transition to the chosen path's phase label:
```bash
engine session phase sessions/DIR "N.X: Path Name" <<'EOF'
{"pathChosen": "N.X", "pathsAvailable": "inline,agent,parallel"}
EOF
```

The gateway → branch transition (`N → N.A`) is allowed by the enforcement engine (see gateway parent pattern in `skills/.directives/AGENTS.md`).

### Step 4: Handle "Other" (Free-Text)

Per `¶INV_QUESTION_GATE_OVER_TEXT_GATE` empty-response rule:
- Empty/whitespace → auto-proceed with "Continue inline" (the N.A path — safest default)
- Non-empty text → treat as user input (may indicate a preference or constraint)

---

## Constraints

*   **Gateway phase only**: This command is the sole step of a gateway phase. It MUST NOT be placed as the last step of a planning or strategy phase — the gateway pattern gives it its own phase with its own proof.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **Exactly one path**: The user picks one. The others are never entered.
*   **Sub-phase skippability**: Unchosen paths are skipped — `¶INV_PHASE_ENFORCEMENT` allows `N.X → (N+1).0` without `--user-approved`.
*   **No default**: Always ask. Even if there's only inline + agent, the user decides.

---

### ¶ASK_EXECUTION_PATH
Trigger: at the gateway phase when selecting how to execute the plan (except: skills without a plan phase, e.g. /do, /chores)
Extras: A: View plan summary before choosing | B: Estimate complexity per path | C: View agent availability

## Decision: Execution Path
- [HERE] Inline execution
  Execute step by step in this conversation
- [SEND] Agent handoff
  Hand off to a single autonomous agent
- [MANY] Parallel agents
  Split into independent chunks for parallel agents
- [VIEW] Peek at plan first
  Re-read the plan before choosing an execution path
- [EACH] Sequential approval
  Inline but with step-by-step user approval before each action

---

## PROOF FOR §CMD_SELECT_EXECUTION_PATH

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "pathChosen": {
      "type": "string",
      "description": "The phase label of the chosen execution path (e.g., '3.A', '3.B')"
    },
    "pathsAvailable": {
      "type": "string",
      "description": "Comma-separated list of paths offered (e.g., 'inline,agent,parallel')"
    }
  },
  "required": ["pathChosen", "pathsAvailable"],
  "additionalProperties": false
}
```
