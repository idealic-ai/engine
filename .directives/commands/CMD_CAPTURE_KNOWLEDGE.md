### ¶CMD_CAPTURE_KNOWLEDGE
**Definition**: Parameterized capture loop for extracting session learnings into directive files. Called by `§CMD_MANAGE_DIRECTIVES` for invariant and pitfall capture. Reusable for any directive type with a scan-draft-present-route pattern.

**Parameters** (provided inline by the caller):
*   `type` — Label (e.g., "Invariant", "Pitfall")
*   `scanCriteria` — What signals to look for in the session
*   `draftFields` — Fields each candidate needs
*   `decisionTree` — Which `¶ASK_*` tree to invoke
*   `formatTemplate` — Markdown format for the output entry
*   `targets` — Where to write (per decision tree path)

**Algorithm**:

1.  **Scan**: Using agent judgment, review the session for up to 5 candidates matching `scanCriteria`.
2.  **Draft**: For each candidate, prepare `draftFields`.
3.  **Gate**: If no candidates found, skip silently. Return `"0 captured"`.
4.  **Present**: For each candidate (batches of up to 4), invoke `§CMD_DECISION_TREE` with the specified `decisionTree`. Use preamble context to show drafted fields.
5.  **Route**: On selection, follow `targets`:
    *   **Skip path**: Continue to next candidate.
    *   **Add path**: Format using `formatTemplate`, append to target file via Edit tool.
    *   **Edit path**: Present text for user refinement, re-present decision tree.
    *   **Other paths**: Execute per caller's routing definition.
6.  **Report**: "[N] [type](s) captured: [names and destinations]." Skip silently if none.

**Constraints**:
*   **Max 5**: Focus on most valuable captures. Avoid prompt fatigue.
*   **Agent judgment only**: No explicit markers or log scanning required.
*   **Idempotent**: Check existing entries before suggesting to avoid duplicates.
*   **Non-blocking**: If user skips all, calling command continues normally.

---

## PROOF FOR §CMD_CAPTURE_KNOWLEDGE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "captured": {
      "type": "string",
      "description": "Count and summary of captured items (e.g., '2 invariants: INV_X, INV_Y')"
    }
  },
  "required": ["captured"],
  "additionalProperties": false
}
```
