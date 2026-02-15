### ¶CMD_EXECUTE_EXTERNAL_MODEL
**Definition**: Executes a writing/synthesis task via an external model (Gemini). Accepts a prompt, optional template with variables, and context file paths. Calls `engine gemini` and returns the result on stdout. The calling skill decides where to write the output.
**Trigger**: Called during execution/writing phases of skills that support external model delegation, when `§CMD_SUGGEST_EXTERNAL_MODEL` recorded a non-claude model choice.

**Prerequisites**:
*   `§CMD_SUGGEST_EXTERNAL_MODEL` has been called and recorded `externalModel` (a Gemini model name).
*   The skill has gathered all relevant context file paths (not contents — paths only).
*   The skill has composed its prompt text describing what to produce.

---

## Algorithm

1.  **Check Model**: Read the `externalModel` value recorded by `§CMD_SUGGEST_EXTERNAL_MODEL`.
    *   If `"claude"` → Do NOT execute this CMD. The skill should handle writing inline (Claude default path). This CMD should never be called when model is claude.
    *   If a Gemini model name → Proceed.

2.  **Gather Inputs** (from skill prose — the skill provides these, not the CMD):
    *   **Prompt** (`prompt`): The main instruction text. Describes what to produce, tone, audience, structure.
    *   **Template** (`template`, optional): A file path to a Markdown template. Contains `{{VARIABLE}}` placeholders.
    *   **Variables** (`vars`, optional): Key-value pairs to substitute into the template. Format: `--var KEY=VALUE` repeated.
    *   **Context files** (`contextFiles`): Positional file paths. These are attached as context for Gemini to reference.
    *   **System instruction** (`system`, optional): A system prompt for Gemini (e.g., "You are a technical writer...").

3.  **Render Template** (if template provided):
    1.  Read the template file.
    2.  For each variable in `vars`, replace `{{KEY}}` with `VALUE` using `sed`.
    3.  Prepend the rendered template to the prompt, separated by a blank line.

4.  **Compose and Execute**:
    ```bash
    # Without template:
    echo "<prompt>" | engine gemini \
      --model "<externalModel>" \
      --system "<system instruction>" \
      <context-file-1> <context-file-2> ...

    # With template (rendered):
    cat <<'PROMPT'
    <prompt>

    USE THIS TEMPLATE STRUCTURE:
    <rendered template content>
    PROMPT
    | engine gemini \
      --model "<externalModel>" \
      --system "<system instruction>" \
      <context-file-1> <context-file-2> ...
    ```

5.  **Handle Output**:
    *   **Success**: The Gemini response is on stdout. The calling skill captures it and writes to the appropriate file (debrief, writeup, review doc, etc.).
    *   **Failure**: If `engine gemini` exits non-zero (API error, missing key), report the error in chat and fall back to Claude inline writing. Log the failure via `§CMD_APPEND_LOG`.

6.  **Log**: Append to the active log:
    ```bash
    engine log sessions/[SESSION]/[LOG].md <<'EOF'
    ## 🤖 External Model Execution
    *   **Model**: [externalModel]
    *   **Context files**: [count] files
    *   **Template**: [template path or "none"]
    *   **Result**: [success/failure]
    EOF
    ```

**Constraints**:
*   This CMD handles execution only. The decision to use an external model is made by `§CMD_SUGGEST_EXTERNAL_MODEL`.
*   The skill composes the prompt. This CMD is plumbing — it renders templates and calls `engine gemini`.
*   Output is stdout only. The skill decides where to write the result.
*   On failure, graceful degradation to Claude inline is mandatory. Never leave the skill stuck.
*   Template rendering is simple `sed` substitution. No nested templates, no conditionals, no loops.
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration of the external model call steps.

---

## Skill Integration Pattern

Skills that use this CMD follow a dual-path pattern in their execution phase:

```markdown
**If `externalModel` is not "claude"** (external model path):
1.  Gather context file paths (don't read into context — save tokens).
2.  Compose prompt with skill-specific instructions.
3.  Execute `§CMD_EXECUTE_EXTERNAL_MODEL` with prompt, template, vars, and file paths.
4.  Write the output to the target file.

**If `externalModel` is "claude"** (default path):
1.  Read files into context as normal.
2.  Write inline using Claude.
```

---

## PROOF FOR §CMD_EXECUTE_EXTERNAL_MODEL

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "modelUsed": {
      "type": "string",
      "description": "The external model that was called (e.g., 'gemini-3-pro-preview')"
    },
    "contextFilesCount": {
      "type": "string",
      "description": "Count and scope of context files (e.g., '4 files: SKILL.md, 3 source')"
    },
    "executionResult": {
      "type": "string",
      "description": "Outcome: 'success' or 'fallback_to_claude'"
    }
  },
  "required": ["modelUsed", "contextFilesCount", "executionResult"],
  "additionalProperties": false
}
```
