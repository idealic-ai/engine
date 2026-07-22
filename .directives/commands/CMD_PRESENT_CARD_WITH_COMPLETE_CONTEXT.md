### ¶CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT
**Definition**: The specialization of `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` for **decision-card** items (findings, ideas, observations, plan steps). It renders a full `§FMT_DECISION_CARD` **as the `AskUserQuestion` question body** — so the user reads the complete card and picks a disposition in one place, with no scroll between a card in chat and a terse question below.

**Trigger**: Any per-item walk-through or disclosure where the item warrants a card, not just a one-line prompt: `§CMD_WALK_THROUGH_RESULTS` (results mode), `§CMD_ELICIT`, `§CMD_TAG_TRIAGE`, plan review. One item = one question; batch up to 4 cards as 4 questions in one `AskUserQuestion`.

**Why**: the card WAS rendered as chat text (cards-then-summary), then a separate terse `AskUserQuestion` collected the choice — the duality. With no body-length limit, the card belongs IN the body; the dispositions become the options.

**Algorithm**:
1.  **Build the card** (`§FMT_DECISION_CARD`) — depth scales with the triage bucket (`FYI` one-liner · `I've-got-this` one-line what+why · `Your-call` full card). Anti-anchor: options-first-neutral, then the defeasible lean.
2.  **Card → question body (plain text, aligned columns).** Put the card's *analysis* in the `question` field — heading (`itemId · Title`), a subtitle (`scope · △●Ⓜ`), What's-at-stake, How-to-verify, My-lean, Confidence. **No markdown** — AskUserQuestion bodies render `**bold**`/`` `code` ``/`####` literally; use whitespace-aligned key/value columns (field left-padded, value right). **Do NOT list the Options in the body** — the answers ARE the options (Step 3), so re-listing is redundant. `header` = the item ID (SIGILS.md § Item IDs).
3.  **Options → the AskUserQuestion answers.** Each option's `label` leads with `§FMT_ANSWER_GRADATION` (`△●Ⓢ★ `, only differentiating dims) + a short action; its `description` carries **that option's trade-off**. **My lean** → the `★` on the recommended answer. Include the honest do-nothing / defer when real.
4.  **Batch**: up to 4 cards per `AskUserQuestion` (one per question). Larger sets chunk into groups of 4.
5.  **Collect + hand off.** `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT` is disclosure+ask; the caller's decision command still owns the *meaning* of the choice (tag placement in `§CMD_TAG_TRIAGE`, fix/skip/defer, LGTM/RWRK) — this command just renders it as one self-complete unit.

**Constraints**:
*   Built on `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` — inherits complete-context-in-body + closed-set gradation.
*   **Card depth scales** — don't spend a full card on an `FYI`, don't shortchange a `Your-call`.
*   **`¶INV_DISCLOSE_AND_TRIAGE`**: have a POV (the `★`/lean), front-load stakes/trade-off/verify, triage by severity×complexity, escalate by exception.
*   **`¶INV_LISTS_INSTEAD_OF_TABLES`**, **`¶INV_ESCAPE_BY_DEFAULT`** apply to the card body.

---

## PROOF FOR §CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "cardsPresented": {
      "type": "string",
      "description": "Count of items rendered as cards-in-body + disposition options (e.g., '3 Your-call cards as question bodies, gradation-tagged options')"
    }
  },
  "required": ["cardsPresented"],
  "additionalProperties": false
}
```
