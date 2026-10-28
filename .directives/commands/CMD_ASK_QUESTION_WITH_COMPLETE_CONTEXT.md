### ¶CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT
**Definition**: The canonical way to ask the user anything via `AskUserQuestion`. **The name is the rule**: every question carries its **complete context inside the question body itself** — never in a separate chat block rendered "before" the popup. The user decides from the question in place, not by scrolling between a context block above and terse options below. This kills the question↔context duality.

**Trigger**: Any `AskUserQuestion` that presents a decision, item, or topic-specific choice. The base primitive that `§CMD_DECISION_TREE`, `§CMD_TAG_TRIAGE`, `§CMD_INTERROGATE`, and `§CMD_WALK_THROUGH_RESULTS` route through. (Trivial gates with self-evident options may inline it without ceremony. ⛔ **An agent does not get to call its own gate trivial where the answer WRITES something** — filing, posting, committing, dispatching, transitioning. Those feel routine from inside and are the ones where the reader is being asked to approve an artifact they must be able to see first.)

**Why**: `AskUserQuestion` question bodies AND option labels have no practical length limit — long, self-complete bodies render fine. The old "render a `§FMT_CONTEXT_BLOCK` in chat, then ask a terse question" pattern existed only because long/labeled content wasn't reliable in-terminal; it forced the user to map options back to context above. Put the context in the body and the duality disappears.

**Algorithm**:
1.  **Body = complete context** (`§FMT_CONTEXT_BLOCK`). Compose the `question` field so it fully frames the decision on its own: what's being decided, why it matters, and everything needed to choose without reading anything else. Long is fine. For a rich judgment call, the body IS a decision card (`§FMT_DECISION_CARD` via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`).
2.  **Options carry gradation** (`§FMT_ANSWER_GRADATION`). Each option `label` leads with the closed gradation cluster — `△●Ⓢ★ ` (risk · confidence · effort · ★) — showing **only the 1–2 dimensions that differentiate this set**; the `description` states **what that option COSTS**, not only what it is. Labels are short by necessity; descriptions are not, and they take real sentences — the trade-off belongs there. ⛔ **A description that says what the option IS without saying what it costs does not satisfy this step**, however accurate it is: *"File it as drafted: new top-level, Backlog, High priority"* tells the reader what will happen and nothing about what they give up by picking it.
3.  **List the tickets the question names, first** (`§INV_TICKETS_PRESENTED_BEFORE_ASKED`, defined in `skills/loom/SKILL.md` §Constraints). If the body or any option mentions a tracker ticket, print one line per ticket in chat before the call: `[KEY](url) — Title [Status since HH:MM D Mon] — two-line summary`, or the key with `status unread` when the tracker can't be read. It is the one chat block allowed ahead of a question, and it does not replace the body's context.
4.  **Call `AskUserQuestion`.** No other preamble/context-block, no "output context in chat first." A one-line lead-in sentence is fine; keep ONE trailing blank line before the call so the last line stays visible above the UI overlay.

**"Complete context" means everything needed to DECIDE — not an explanation of the machinery.**

This is the most common way this command is misread, and the misreading looks like diligence. **Write the question about the user's decision, not about the system's situation.** Lead with what changes for them and what it costs; then the options.

*   **Keep out of the body unless the decision genuinely turns on it**: protocol step numbers · skill and command names · `¶INV_*` / `§CMD_*` sigils · your own internal conflicts (a harness rule you are unsure about, a tension between two instructions) · table and column names · token counts · anything phrased as *"X says I must Y"*.
*   **Put in instead**: what the user gets either way · what actually differs between the options · time and money in plain units · what they lose by choosing wrong · one line on why they are being asked at all, if that is not obvious.
*   **Options are outcomes, not mechanisms.** *"Check it properly — two angles, cross-checked"* beats *"Dispatch it — run the protocol"*. A label naming an internal procedure asks the user to understand the system before they can answer.
*   **Say what you are unsure about in one clause, not a paragraph.** *"I need your nod before spinning up helpers"* carries the whole constraint; three sentences reconstructing the rule and its history do not carry more.

**Measured**: a question about whether to run a background investigation opened with *"Step 5 of /inbox-post says triangulate what I just posted"*, spent a paragraph on a conflict between the skill and a harness rule, quoted a token multiplier, and named three database columns — to a reader who had asked a one-sentence question about a Linear project. The operator's verdict: **"this sounds too nerdy, the message. can we make it less nerdy or scary"**. Every fact in it was true and load-bearing *to the agent*; almost none of it was load-bearing to the decision. **Verbosity was not the defect — subject was.** The rewrite was the same length.

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: all user-facing decisions still go through `AskUserQuestion`.
*   **Complete context in the body** — the point of the name. Never split the context from the question into a preceding chat block. The ticket list of step 3 is the exception, and it sits beside the body rather than standing in for it.
*   **Complete ≠ exhaustive.** Long is fine; long *about the machinery* is the failure above. Before sending, check the body answers *"what am I choosing between, and what does each cost me"* — and that a reader who does not know how the system works could still answer it.
*   **Gradation is a closed set** (`§FMT_ANSWER_GRADATION`): use only the defined glyphs, never freehand; show only differentiating dimensions (no soup).
*   **`¶INV_LISTS_INSTEAD_OF_TABLES`**, **`¶INV_ESCAPE_BY_DEFAULT`** apply to the body content.
*   ⚠️ **Stated, not enforced** (`§INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL`). Nothing reddens for a thin question. This command's proof field is a free-text `questionAsked` string filled by assertion, and its own example — *"apply-approach — full context in body, 4 gradation-tagged options"* — is satisfied by a one-line body with four four-word descriptions. **A check would have to read the question payload rather than a claim about it**: whether the body carries the subject matter it names (the draft under approval, the item a reference points at), and per option whether a `description` exists at all and states a cost rather than restating its label. Until something reads the payload, the only enforcement is a reader noticing — which is how the measured instance above shipped.

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
