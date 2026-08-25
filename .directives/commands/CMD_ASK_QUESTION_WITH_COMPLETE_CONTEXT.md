### ¶CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT
**Definition**: The canonical way to ask the user anything via `AskUserQuestion`. **The name is the rule**: every question carries its **complete context inside the question body itself** — never in a separate chat block rendered "before" the popup. The user decides from the question in place, not by scrolling between a context block above and terse options below. This kills the question↔context duality.

**Trigger**: Any `AskUserQuestion` that presents a decision, item, or topic-specific choice. The base primitive that `§CMD_DECISION_TREE`, `§CMD_TAG_TRIAGE`, `§CMD_INTERROGATE`, and `§CMD_WALK_THROUGH_RESULTS` route through. (Trivial gates with self-evident options may inline it without ceremony.)

**Why**: `AskUserQuestion` question bodies AND option labels have no practical length limit — long, self-complete bodies render fine. The old "render a `§FMT_CONTEXT_BLOCK` in chat, then ask a terse question" pattern existed only because long/labeled content wasn't reliable in-terminal; it forced the user to map options back to context above. Put the context in the body and the duality disappears.

**Algorithm**:
1.  **Body = complete context** (`§FMT_CONTEXT_BLOCK`). Compose the `question` field so it fully frames the decision on its own: what's being decided, why it matters, and everything needed to choose without reading anything else. Long is fine. For a rich judgment call, the body IS a decision card (`§FMT_DECISION_CARD` via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`).
2.  **Options carry gradation** (`§FMT_ANSWER_GRADATION`). Each option `label` leads with the closed gradation cluster — `△●Ⓢ★ ` (risk · confidence · effort · ★) — showing **only the 1–2 dimensions that differentiate this set**; the `description` states what the option means / its trade-off.
3.  **Call `AskUserQuestion`.** No separate preamble/context-block, no "output context in chat first." A one-line lead-in sentence is fine; keep ONE trailing blank line before the call so the last line stays visible above the UI overlay.

**"Complete context" means everything needed to DECIDE — not an explanation of the machinery.**

This is the most common way this command is misread, and the misreading looks like diligence. **Write the question about the user's decision, not about the system's situation.** Lead with what changes for them and what it costs; then the options.

*   **Keep out of the body unless the decision genuinely turns on it**: protocol step numbers · skill and command names · `¶INV_*` / `§CMD_*` sigils · your own internal conflicts (a harness rule you are unsure about, a tension between two instructions) · table and column names · token counts · anything phrased as *"X says I must Y"*.
*   **Put in instead**: what the user gets either way · what actually differs between the options · time and money in plain units · what they lose by choosing wrong · one line on why they are being asked at all, if that is not obvious.
*   **Options are outcomes, not mechanisms.** *"Check it properly — two angles, cross-checked"* beats *"Dispatch it — run the protocol"*. A label naming an internal procedure asks the user to understand the system before they can answer.
*   **Say what you are unsure about in one clause, not a paragraph.** *"I need your nod before spinning up helpers"* carries the whole constraint; three sentences reconstructing the rule and its history do not carry more.

**Measured**: a question about whether to run a background investigation opened with *"Step 5 of /inbox-post says triangulate what I just posted"*, spent a paragraph on a conflict between the skill and a harness rule, quoted a token multiplier, and named three database columns — to a reader who had asked a one-sentence question about a Linear project. The operator's verdict: **"this sounds too nerdy, the message. can we make it less nerdy or scary"**. Every fact in it was true and load-bearing *to the agent*; almost none of it was load-bearing to the decision. **Verbosity was not the defect — subject was.** The rewrite was the same length.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: all user-facing decisions still go through `AskUserQuestion`.
*   **Complete context in the body** — the point of the name. Never split the context from the question into a preceding chat block.
*   **Complete ≠ exhaustive.** Long is fine; long *about the machinery* is the failure above. Before sending, check the body answers *"what am I choosing between, and what does each cost me"* — and that a reader who does not know how the system works could still answer it.
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
