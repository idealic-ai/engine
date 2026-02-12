### §CMD_SELECT_MODE
**Definition**: Present skill mode selection via `AskUserQuestion`, load the selected mode file, handle Custom mode, and record the mode configuration. Generic command — each skill provides its own modes via the `modes` parameter object.
**Trigger**: Called during Phase 0 (Setup) of modal skills, after `§CMD_PARSE_PARAMETERS`.

**Prerequisites**:
*   The skill's `modes` object is stored in `.state.json` (from session parameters). Structure:
    ```json
    "modes": {
      "modeName": {"label": "Label", "description": "Short desc", "file": "~/.claude/skills/[skill]/modes/[mode].md"},
      ...
      "custom": {"label": "Custom", "description": "User-defined", "file": "~/.claude/skills/[skill]/modes/custom.md"}
    }
    ```
*   By convention: exactly 3 named modes + 1 Custom mode (`¶INV_MODE_STANDARDIZATION`).

**Algorithm**:
1.  **Build Question**: From the `modes` object, construct an `AskUserQuestion` (multiSelect: false):
    *   **Question text**: Use the skill-specific phrasing (e.g., "What implementation approach should I use?", "What analysis lens should I use?"). Derive from the skill context — the command doesn't prescribe wording.
    *   **Options**: One per mode entry. The first named mode is marked "(Recommended)". Custom is always last.
    *   **Option format**: label = `"[Label] (Recommended)"` for first, `"[Label]"` for others. description = mode's `description` field.

2.  **Present**: Execute `AskUserQuestion`.

3.  **On Named Mode Selection**: Read the corresponding mode file from the `file` path in the `modes` object. The mode file defines:
    *   **Role**: Persona for `§CMD_ASSUME_ROLE`
    *   **Goal**: What the agent optimizes for
    *   **Mindset**: Cognitive anchoring
    *   **Configuration**: Skill-specific settings (interrogation topics, walk-through config, build approach, etc.)

4.  **On "Custom" Selection**:
    1.  Read ALL named mode files first (all entries except `custom`) — this gives the agent the flavor space to blend from.
    2.  Read the `custom` mode file (contains instructions for user-defined framing).
    3.  Accept user's framing text. Parse into role/goal/mindset structure.

5.  **Record**: Store the selected mode name and its configuration. The mode configures downstream phases:
    *   Phase 0: Role for `§CMD_ASSUME_ROLE` (from mode file)
    *   Interrogation phase: Topics list (from mode file, if applicable)
    *   Build/execution phase: Approach and constraints (from mode file, if applicable)
    *   Walk-through phase: Config for `§CMD_WALK_THROUGH_RESULTS` (from mode file, if applicable)

6.  **Assume Role**: After recording, execute `§CMD_ASSUME_ROLE` using the selected mode's **Role**, **Goal**, and **Mindset**.

**Constraints**:
*   Mode files live in `~/.claude/skills/[skill]/modes/`. Each skill owns its mode definitions.
*   The `modes` parameter is optional. Skills without modes (e.g., `/do`, `/brainstorm` historically) skip this command entirely.
*   `¶INV_MODE_STANDARDIZATION` requires exactly 3 named modes + Custom. Custom is always the last option.
*   Mode selection happens once per session. Re-selection requires `§CMD_REFUSE_OFF_COURSE`.
