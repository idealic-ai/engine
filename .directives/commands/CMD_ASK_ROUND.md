### ¶CMD_ASK_ROUND
**Definition**: The standard protocol for information gathering (Brainstorming, Debugging, Deep Dives).
**Algorithm**:
1.  **Formulate**: Generate up to 4 targeted questions based on the Session Goal (the `AskUserQuestion` tool maximum).
2.  **Execute**: Call the `AskUserQuestion` tool.
    *   **Constraint**: Provide distinct options for each question (e.g., Yes/No, Multiple Choice).
    *   **Goal**: Gather structured data to inform the next steps.
3.  **Wait**: The tool will pause execution until the user responds.
4.  **Resume**: Once the tool returns, proceed immediately to logging.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.

---

## PROOF FOR §CMD_ASK_ROUND

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "questionsAsked": {
      "type": "string",
      "description": "Count and topic of questions asked (e.g., '4 questions on auth flow')"
    },
    "roundNumber": {
      "type": "string",
      "description": "Round number and topic (e.g., 'round 3: edge cases')"
    }
  },
  "required": ["executed", "questionsAsked"],
  "additionalProperties": false
}
```
