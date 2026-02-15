### ¶CMD_SUGGEST_EXTERNAL_MODEL
**Definition**: Present an external model selection via `AskUserQuestion`. Records the user's choice (model name or "claude") for downstream use by §CMD_EXECUTE_EXTERNAL_MODEL. Generic command — any skill can invoke it to offer external model delegation.
**Trigger**: Called during Phase 0 (Setup) of skills that support external model delegation, after `§CMD_SELECT_MODE`. **Opt-in only** — skills that don't need external models simply don't invoke this CMD. Currently used by `/document` and `/rewrite`.

**Prerequisites**:
*   `engine gemini` is available and whitelisted (`Bash(engine *)`).
*   The skill's prose provides a `modelQuestion` — a skill-specific phrasing for the question (e.g., "Use Gemini for writing?" vs "Use Gemini for review synthesis?").

---

## Algorithm

1.  **Present**: Invoke §CMD_DECISION_TREE with `§ASK_MODEL_SELECTION`. Use the skill's `modelQuestion` phrasing as the preamble context.

2.  **Record**: Store the selected model as `externalModel` based on the tree path:
    *   `PRO` → `externalModel = "gemini-3-pro-preview"`
    *   `FLS` → `externalModel = "gemini-3-flash-preview"`
    *   `CLD` → `externalModel = "claude"`
    *   `OTH/CUS` → Parse as a model name string, otherwise default to `"claude"`
    *   `OTH/SKP` → `externalModel = "claude"`

3.  **Effect**: The recorded `externalModel` value is used by §CMD_EXECUTE_EXTERNAL_MODEL in the skill's execution phase. When `externalModel = "claude"`, the skill proceeds normally (Claude writes inline). When set to a Gemini model, the skill gathers context file paths instead of reading files into context, and delegates writing to §CMD_EXECUTE_EXTERNAL_MODEL.

**Constraints**:
*   This CMD only asks the question and records the answer. It does NOT execute any model calls.
*   The question is asked once per session. Re-asking requires `§CMD_REFUSE_OFF_COURSE`.
*   Skills that don't support external models simply don't invoke this CMD.

---

### ¶ASK_MODEL_SELECTION
Trigger: during setup of skills that support external model delegation (except: skills that don't invoke §CMD_SUGGEST_EXTERNAL_MODEL — opt-in only)
Extras: A: Compare model capabilities | B: View estimated costs | C: Use same model as last session

## Decision: External Model
- [PRO] Gemini 3 Pro
  Best for quality-critical synthesis from many files
- [FLS] Gemini 3 Flash
  Faster and cheaper, good for straightforward tasks
- [CLD] Claude (default)
  Stay in context. Better for interactive refinement
- [OTH] Other
  - [CUS] Custom model
    Specify a model name manually (e.g., a fine-tuned variant)
  - [SKP] Skip model selection
    Stay with Claude default — don't ask again this session

---

## PROOF FOR §CMD_SUGGEST_EXTERNAL_MODEL

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "externalModel": {
      "type": "string",
      "description": "The model chosen by the user: 'gemini-3-pro-preview', 'gemini-3-flash-preview', 'claude', or a custom model name"
    }
  },
  "required": ["externalModel"],
  "additionalProperties": false
}
```
