### §CMD_PRESENT_NEXT_STEPS
**Definition**: Post-synthesis routing menu. Presents the user with options to continue working, switch to another skill, or leave the session idle. Called after `§CMD_CLOSE_SESSION` transitions the session to idle state.
**Trigger**: Called as the final step of `§CMD_RUN_SYNTHESIS_PIPELINE` Close sub-phase, after `§CMD_CLOSE_SESSION`.
**Prerequisite**: Session must be in `lifecycle=idle` state (set by `§CMD_CLOSE_SESSION` via `engine session idle`).

---

## Algorithm

### Step 1: Read Next Skills

Read `nextSkills` from `.state.json`. This array is declared by each skill in its SKILL.md and stored at session activation.

**Fallback**: If `nextSkills` is empty or missing, use the `§CMD_DISCOVER_DELEGATION_TARGETS` table to derive options (pick the 3 most commonly recommended skills + "Done for now").

### Step 2: Contextualize Options

**Preamble (REQUIRED)**: Before presenting the menu, output a short summary block in chat that explains what each skill option would concretely do *for this session's work*. Do NOT use generic descriptions — tailor each to the actual changes, files, and outcomes of the session. Format:

> **What each option involves:**
> - `/skill1` — [1-2 sentences: what this skill would do given the specific work just completed]
> - `/skill2` — [1-2 sentences: what this skill would do given the specific work just completed]
> - `/skill3` — [1-2 sentences]

### Step 3: Present Menu

Execute `AskUserQuestion` (multiSelect: false):

```
AskUserQuestion:
  question: "Session idle. What next? (Type a /skill name to invoke it, or describe new work to scope it)"
  header: "Next steps"
  options:
    - label: "/skill1 (Recommended)"
      description: "[contextualized to this session's work]"
    - label: "/skill2"
      description: "[contextualized to this session's work]"
    - label: "/skill3"
      description: "[contextualized to this session's work]"
    - label: "Done for now"
      description: "Leave session idle. Come back later."
```

*   **Option format**: For each skill in `nextSkills`, use: label=`"/skill-name"`, description=contextualized to this session's work. The first option should be marked "(Recommended)". The last option is always "Done for now".
*   **Options MUST list specific skills**: List one option per `nextSkills` entry + "Done for now". Do NOT create generic bucket options like "Start a new skill" or "Continue in this session" — list the actual skills. If `nextSkills` has 4+ entries, include the top 3 most relevant + "Done for now" (the user can type a skill name via "Other").

### Step 4: Handle Selection

*   **If a skill is chosen**: Invoke `Skill(skill: "[chosen-skill]")`. The next skill's `§CMD_PARSE_PARAMETERS` will run `§CMD_MAINTAIN_SESSION_DIR`, which detects the idle session with existing artifacts and presents the delivery mode choice (fast-track / full ceremony / new session). The fast-track choice is handled there — NOT here — to avoid double-asking.
*   **If "Done for now"**: Session stays idle. Output: "Session is idle. Invoke any `/skill` when you're ready to continue."
*   **If "Other" — skill name** (user typed `/implement`, `/test`, etc.): Treat as skill selection — invoke `Skill(skill: "[typed-skill]")`.
*   **If "Other" — new work details** (user typed notes, questions, or requirements): This is new input that needs scoping. Route via `AskUserQuestion` (multiSelect: false):
    ```
    AskUserQuestion:
      question: "This sounds like new work. Should I scope it?"
      header: "Route"
      options:
        - label: "Yes — start /implement"
          description: "[contextualized: what implementing would mean for this input]"
        - label: "Yes — start /brainstorm"
          description: "Explore the idea before committing to implementation"
        - label: "No — just note it"
          description: "Log to DETAILS.md and stay idle"
    ```

---

## Constraints

*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: ALL user-facing interactions in this command — the main menu (Step 3) AND all follow-up routing (Step 4) — MUST use `AskUserQuestion`. Never drop to bare text for any question or routing decision.
*   **Idle gate active**: After `engine session idle`, the idle-gate injection restricts tools to AskUserQuestion, Skill, and engine commands only. This command operates within those constraints — it only uses AskUserQuestion and Skill.
*   **Options come from `nextSkills`**: Each skill declares its own `nextSkills` in its SKILL.md. The command reads them from `.state.json` at runtime.
*   **Same session directory**: Fast-track reuses the same session directory. New session creates a fresh one. This is handled by `§CMD_MAINTAIN_SESSION_DIR` in the next skill, not here.
*   **No deactivation**: This command does NOT call `engine session deactivate`. The session stays idle. Deactivation happens when the next skill activates (which completes the previous session) or when the user explicitly closes it.
*   **Menu is the terminal step**: This is the last thing that happens in a skill session. The proof records that the menu was presented and what the user chose.

---

## PROOF FOR §CMD_PRESENT_NEXT_STEPS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "menu_presented": {
      "type": "boolean",
      "description": "Whether the next-steps menu was presented via AskUserQuestion"
    },
    "user_choice": {
      "type": "string",
      "description": "What the user selected: a skill name, 'Done for now', or free-text"
    }
  },
  "required": ["menu_presented", "user_choice"],
  "additionalProperties": false
}
```
