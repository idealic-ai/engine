### ¶CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT
**Definition**: The canonical way to ask the user anything via `AskUserQuestion`. **The name is the rule**: every question carries its **complete context inside the question body itself** — never in a separate chat block rendered "before" the popup. The user decides from the question in place, not by scrolling between a context block above and terse options below. This kills the question↔context duality.

**Trigger**: Any `AskUserQuestion` that presents a decision, item, or topic-specific choice. The base primitive that `§CMD_DECISION_TREE`, `§CMD_TAG_TRIAGE`, `§CMD_INTERROGATE`, and `§CMD_WALK_THROUGH_RESULTS` route through. (Trivial gates with self-evident options may inline it without ceremony.)

**Why**: `AskUserQuestion` question bodies AND option labels have no practical length limit — long, self-complete bodies render fine. The old "render a `§FMT_CONTEXT_BLOCK` in chat, then ask a terse question" pattern existed only because long/labeled content wasn't reliable in-terminal; it forced the user to map options back to context above. Put the context in the body and the duality disappears.

**Algorithm**:
1.  **Body = complete context** (`§FMT_CONTEXT_BLOCK`). Compose the `question` field so it fully frames the decision on its own: what's being decided, why it matters, and everything needed to choose without reading anything else. Long is fine. For a rich judgment call, the body IS a decision card (`§FMT_DECISION_CARD` via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`).
2.  **Options carry gradation** (`§FMT_ANSWER_GRADATION`). Each option `label` leads with the closed gradation cluster — `△●Ⓢ★ ` (risk · confidence · effort · ★) — showing **only the 1–2 dimensions that differentiate this set**; the `description` states what the option means / its trade-off.
3.  **Call `AskUserQuestion`.** No separate preamble/context-block, no "output context in chat first." A one-line lead-in sentence is fine; keep ONE trailing blank line before the call so the last line stays visible above the UI overlay.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: all user-facing decisions still go through `AskUserQuestion`.
*   **Complete context in the body** — the point of the name. Never split the context from the question into a preceding chat block.
*   **Gradation is a closed set** (`§FMT_ANSWER_GRADATION`): use only the defined glyphs, never freehand; show only differentiating dimensions (no soup).
*   **`¶INV_LISTS_INSTEAD_OF_TABLES`**, **`¶INV_ESCAPE_BY_DEFAULT`** apply to the body content.

---

## PROOF FOR §CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "questionAsked": {
      "type": "string",
      "description": "What was asked with complete in-body context (e.g., 'apply-approach — full context in body, 4 gradation-tagged options')"
    }
  },
  "required": ["questionAsked"],
  "additionalProperties": false
}
```
