### ¶CMD_TAG_TRIAGE
**Definition**: Domain-specific tag-based triage. Presents dynamically-selected delegation targets per item, collects `#needs-[tag]` selections. Supports single-item and batch (up to 4 items) invocation. Returns `chosen_items[]` — no side effects. Separated from `§CMD_DECISION_TREE` because tags have domain-specific semantics (delegation targets, `nextSkills` bias, tag placement).
**Trigger**: Called by `§CMD_WALK_THROUGH_RESULTS` in results mode, or any protocol step routing work items to skills via tags.

---

## Algorithm

### Step 1: Discover Delegation Targets

Read the delegation targets table from session context (loaded at activation). Also read `nextSkills` from `.state.json` to bias selection.

### Step 2: Select Tags Per Item

For each item, pick the **2 most relevant tags**:
1.  **Content match**: Which tags describe the work? Bug → `#needs-fix`. Missing docs → `#needs-documentation`. Design question → `#needs-brainstorm`.
2.  **`nextSkills` bias**: Prefer tags whose skills appear in `nextSkills`.
3.  **No duplicates**: If the item already carries a `#needs-X` tag, skip that tag.

### Step 3: Present

**Single item** (1 item): One `AskUserQuestion` (multiSelect: false) with 3 options:
*   2 dynamic tags + Dismiss.

**Batch** (2-4 items): One `AskUserQuestion` with N questions (one per item, single-select each):
*   Per question: 2 dynamic tags (selected independently for THAT item) + Dismiss.
*   Header: the item's ID per the Item IDs convention (SIGILS.md § Item IDs). Inherited from the caller (e.g., `§CMD_WALK_THROUGH_RESULTS` provides the debrief item ID).

**Label format** (per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`): Labels MUST include the `#needs-X` tag and describe the specific action. Example: `"#needs-implementation: add rate limiting to /api/extract"`.

### Step 4: Process Selections

For each item's answer:
*   **Tag selected**: Record `decision: "tag"`, `tagNoun`, `explanation` (from label).
*   **Dismiss**: Record `decision: "dismiss"`.
*   **Other (typed text)**: If contains `#needs-[tag]`, extract tag noun. Otherwise record `decision: "custom"`, `customText`.

### Step 5: Return

Return `chosen_items[]` — array of `{item, decision, tagNoun, explanation}` objects. No side effects — caller handles tag placement (`§CMD_HANDLE_INLINE_TAG`), Tags-line updates (`§CMD_TAG_FILE`), and DIALOGUE.md logging.

---

## Constraints

*   **`¶INV_ASK_RETURNS_PATH`**: Pure decision collector — no side effects.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All interactions via `AskUserQuestion`. Descriptive labels required.
*   **`¶INV_1_TO_1_TAG_SKILL`**: Only offer tags with corresponding skills.
*   **2 tags + Dismiss**: 3 options per question (within `AskUserQuestion`'s 4-option limit with Other).
*   **Batch limit**: Max 4 items per invocation. Caller chunks larger sets.
*   **Tags are passive during walk-through**: Tags placed by the caller after tag triage do NOT trigger `/delegation-create` offers.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and labels; bare tags only on `**Tags**:` lines or intentional inline placement.

---

## PROOF FOR §CMD_TAG_TRIAGE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "chosenItems": {
      "type": "array",
      "description": "One entry per item. Each has decision (tag/dismiss/custom) and optional tag noun.",
      "items": {
        "type": "object",
        "properties": {
          "item": { "type": "string", "description": "Item title/identifier" },
          "decision": { "type": "string", "description": "'tag', 'dismiss', or 'custom'" },
          "tagNoun": { "type": "string", "description": "Tag noun if decision=tag, null otherwise" }
        },
        "required": ["item", "decision"]
      }
    }
  },
  "required": ["chosenItems"],
  "additionalProperties": false
}
```
