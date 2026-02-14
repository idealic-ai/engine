### §CMD_SUGGEST_EXTERNAL_MODEL
**Definition**: Present an external model selection via `AskUserQuestion`. Records the user's choice (model name or "claude") for downstream use by `§CMD_EXECUTE_EXTERNAL_MODEL`. Generic command — any skill can invoke it to offer external model delegation.
**Trigger**: Called during Phase 0 (Setup) of skills that support external model delegation, after `§CMD_SELECT_MODE`.

**Prerequisites**:
*   `engine gemini` is available and whitelisted (`Bash(engine *)`).
*   The skill's prose provides a `modelQuestion` — a skill-specific phrasing for the question (e.g., "Use Gemini for writing?" vs "Use Gemini for review synthesis?").

---

## Algorithm

1.  **Build Question**: Construct an `AskUserQuestion` (multiSelect: false) using the skill's `modelQuestion` phrasing:

    | Option | Label | Description |
    |--------|-------|-------------|
    | 1 | "Yes — Gemini 3 Pro (Recommended)" | Uses `gemini-3-pro-preview`. Best for quality-critical synthesis from many files. |
    | 2 | "Yes — Gemini 3 Flash" | Uses `gemini-3-flash-preview`. Faster and cheaper, good for straightforward tasks. |
    | 3 | "No — Claude (default)" | Stay in context. Claude writes inline. Better for interactive refinement. |

2.  **Present**: Execute `AskUserQuestion`.

3.  **Record**: Store the selected model as `externalModel`:
    *   "Yes — Gemini 3 Pro" → `externalModel = "gemini-3-pro-preview"`
    *   "Yes — Gemini 3 Flash" → `externalModel = "gemini-3-flash-preview"`
    *   "No — Claude" → `externalModel = "claude"`
    *   "Other" (free text) → Parse as a model name string if it looks like one, otherwise default to `"claude"`

4.  **Effect**: The recorded `externalModel` value is used by `§CMD_EXECUTE_EXTERNAL_MODEL` in the skill's execution phase. When `externalModel = "claude"`, the skill proceeds normally (Claude writes inline). When set to a Gemini model, the skill gathers context file paths instead of reading files into context, and delegates writing to `§CMD_EXECUTE_EXTERNAL_MODEL`.

**Constraints**:
*   This CMD only asks the question and records the answer. It does NOT execute any model calls.
*   The question is asked once per session. Re-asking requires `§CMD_REFUSE_OFF_COURSE`.
*   Skills that don't support external models simply don't invoke this CMD.

---

## PROOF FOR §CMD_SUGGEST_EXTERNAL_MODEL

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "external_model": {
      "type": "string",
      "description": "The model chosen by the user: 'gemini-3-pro-preview', 'gemini-3-flash-preview', 'claude', or a custom model name"
    }
  },
  "required": ["external_model"],
  "additionalProperties": false
}
```
