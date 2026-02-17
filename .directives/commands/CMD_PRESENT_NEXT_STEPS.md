### ¶CMD_PRESENT_NEXT_STEPS
**Definition**: Post-synthesis routing menu. Presents the user with options to continue working, switch to another skill, or leave the session idle. Called after `§CMD_CLOSE_SESSION` transitions the session to idle state.
**Prerequisite**: Session must be in `lifecycle=idle` state (set by `§CMD_CLOSE_SESSION` via `engine session idle`).

---

## Algorithm

### Step 1: Read Next Skills

Read `nextSkills` from the `## Next Skills` section of `engine session idle` output. (`engine session deactivate` also outputs this, but standard skill close uses `idle` — see `§CMD_SESSION_CLI`.) These commands output nextSkills directly in their stdout after transitioning the session lifecycle.

**Fallback**: If the engine output doesn't include `## Next Skills` (older engine version), read `nextSkills` from `.state.json` via `jq -r '.nextSkills // [] | .[]'`. If still empty, use the `SRC_DELEGATION_TARGETS` table to derive options (pick the 3 most commonly recommended skills + "Done and clear").

### Step 2: Contextualize Options

**Preamble (REQUIRED)**: Before the menu, output a blockquote explaining what each skill would concretely do *for this session's work*. Tailor to actual changes — no generic descriptions.

**Incorporate Opportunities**: If `§CMD_SURFACE_OPPORTUNITIES` ran earlier in N.4 Close and produced opportunity bullets, use them to drive the preamble and option descriptions. Each opportunity maps to a skill — use those mappings to make the menu options concrete. Example: instead of `/implement — Continue building features`, write `/implement — Add rate limiting to auth guard (opportunity 5.4.3/1)`. If no opportunities were surfaced, fall back to general session-aware contextualization.

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
    - label: "Done and clear"
      description: "Clear context and get a fresh Claude. Session stays idle."
```

*   **Option format**: For each skill in `nextSkills`, use: label=`"/skill-name"`, description=contextualized to this session's work. The first option should be marked "(Recommended)". The last option is always "Done and clear".
*   **Options MUST list specific skills**: List one option per `nextSkills` entry + "Done and clear". Do NOT create generic bucket options like "Start a new skill" or "Continue in this session" — list the actual skills. If `nextSkills` has 4+ entries, include the top 3 most relevant + "Done and clear" (the user can type a skill name via "Other").

### Step 4: Handle Selection

*   **If a skill is chosen**: Invoke `Skill(skill: "[chosen-skill]")`. The next skill's `§CMD_PARSE_PARAMETERS` will run `§CMD_MAINTAIN_SESSION_DIR`, which detects the idle session with existing artifacts and presents the delivery mode choice (fast-track / full ceremony / new session). The fast-track choice is handled there — NOT here — to avoid double-asking.
*   **If "Done and clear"**: Output "Clearing context. Fresh Claude incoming." then execute `engine session clear <session-dir>`. This is terminal — do NOT call any further tools after it.
*   **If "Other" — skill name** (user typed `/implement`, `/test`, etc.): Treat as skill selection — invoke `Skill(skill: "[typed-skill]")`.
*   **If "Other" — new work details** (user typed notes, questions, or requirements): This is new input that needs scoping. Invoke §CMD_DECISION_TREE with `§ASK_NEW_WORK_ROUTING`. Use preamble context to summarize the user's input and how each option would handle it.

---

## Constraints

*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All interactions — main menu AND follow-up routing — MUST use `AskUserQuestion`.
*   **Idle gate active**: After `engine session idle`, tools are restricted to AskUserQuestion, Skill, and engine commands.
*   **Options from engine output**: Read from the `## Next Skills` section of `engine session idle`/`deactivate` stdout. This avoids the session gate blocking `.state.json` reads after deactivation. Fallback to `.state.json` only if engine output lacks the section.
*   **No deactivation**: Session stays idle. Deactivation happens when the next skill activates or the user explicitly closes it.

---

### ¶ASK_NEW_WORK_ROUTING
Trigger: when user describes new work via Other in the next-steps menu (except: when user's text clearly matches a skill name — route directly)
Extras: A: Describe the work in more detail | B: Check existing sessions for overlap | C: Tag for later instead

## Decision: New Work Routing
- Start /implement
  Scope and implement the described work
- Start /brainstorm
  Explore the idea before committing to implementation
- [KEEP] Just note it
  Log to DIALOGUE.md and stay idle
- Start /research
  Research the topic before any action
- Start /fix
  This sounds like a bug — investigate and fix

---

## PROOF FOR §CMD_PRESENT_NEXT_STEPS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "menuPresented": {
      "type": "string",
      "description": "Menu outcome (e.g., 'presented 3 skills + done')"
    },
    "userChoice": {
      "type": "string",
      "description": "What the user selected: a skill name, 'Done and clear', or free-text"
    }
  },
  "required": ["menuPresented", "userChoice"],
  "additionalProperties": false
}
```
