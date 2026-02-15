### ¶CMD_DECISION_TREE
**Definition**: General-purpose declarative decision collector. Navigates markdown-defined trees via `AskUserQuestion`. Supports single-item and batch (up to 4 items) invocation. Returns `chosen_items[]` — no side effects.
**Trigger**: Called by `§CMD_WALK_THROUGH_RESULTS`, `§CMD_DISPATCH_APPROVAL`, `§CMD_GATE_PHASE`, or any protocol step needing structured decisions.

---

## Markdown Tree Format

```
### ¶ASK_[NAME]
Trigger: [when this ask pattern is useful — prose description]

## Decision: [Name]
- [CODE] Label text
  Description text (→ AskUserQuestion description)
  - [SUB1] Sub-option label
    Sub-option description
- [OTH] Other
  - [DEF] Default if blank
    Description
```

- **Heading** — `### ¶ASK_[NAME]` — UPPER_SNAKE, unique across all CMD/SKILL files
- **Trigger** — `Trigger: [description]` — prose line after heading, before `## Decision:`. Describes when this ask pattern is useful.
- **Identifier** — `[CODE]` — 1-4 uppercase letters, unique within siblings
- **Multi-select** — `- [CODE] [ ] Label` — `[ ]` after code turns the level into multiSelect
- **Nesting** — 2-space indent per level. Hard limit: 3 levels
- **Width** — Exactly 3 named options + `[OTH]` per level = 4 total (`¶INV_ASK_ALWAYS_FOUR`)
- **Description** — Indented line below label
- **`[OTH]`** — Explicit Other subtree. Blank input → navigate children. Typed text → smart parse (see below). Always has ≥2 subchoices.
- **`...` indicator** — Auto-appended to labels with children. Not written by authors

**Path format**: Slash-separated codes tracing the selection path. Multi-select uses commas.

- **`OK`** — Direct leaf
- **`NO/RWK`** — Nested: NO → RWK
- **`OTH/custom:merge with step 3`** — Other with typed text
- **`OTH/RWK`** — Other blank → auto-select or menu pick
- **`TAG,BRS`** — Multi-select: two leaves
- **`TAG,NO/RWK`** — Multi-select: one leaf + one nested

---

## Algorithm

### Step 1: Parse Tree

Extract from the tree definition: nodes (`[CODE]`, label, description, children), multi-select flags, `[OTH]` subtree presence.

### Step 2: Preamble (Context + Legend)

Before calling `AskUserQuestion`, output a **preamble** in chat. The preamble has two parts: (1) context explaining WHAT and WHY, (2) extended options legend. Always shown — consistent UX. The user does NOT read log files or artifacts — the preamble IS their context window for making this decision.

**Format**:
> [1-2 paragraphs: WHAT decision is being made, WHY it matters, and enough context for the user to choose without reading any files. In batch mode, include per-item context blocks before the legend.]
>
> **Also:** A: [smart extra 1] | B: [smart extra 2] | C: [smart extra 3]
> **Try:** Blank for more | Q: ask a question | ?: explain | !: skip
>
> *(trailing blank line — required per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`)*

**Context requirement** (`¶INV_QUESTION_GATE_OVER_TEXT_GATE`): The context paragraphs are NOT optional. A bare A/B/C legend without explanation is a violation. The user must understand what they're deciding and why from the preamble alone.

**Trailing blank line**: The last line of chat text before the `AskUserQuestion` call MUST be an empty line (`\n`). The question UI element overlaps the bottom of preceding text — without the blank line, the user cannot read the agent's final sentence.

**A/B/C smart extras**: Agent-generated options based on current context — not from the tree definition. These are creative alternatives the agent thinks are relevant. Examples:
*   During tag triage: `A: #needs-brainstorm + #needs-implementation | B: Defer to next session | C: Split into 2 items`
*   During phase gate: `A: Run tests first | B: Quick sanity check | C: Commit and move on`
*   For enum-style trees (depth, model): A/B/C may be omitted if no useful smart extras exist.

### Step 3: Present

**Single item** (1 item): One `AskUserQuestion` with the tree's root nodes as options (3 named + implicit Other).

**Batch** (2-4 items): One `AskUserQuestion` with N questions (one per item). Each question offers the same root nodes as options. Header per question: the item's ID per the Item IDs convention (SIGILS.md § Item IDs). The caller provides item IDs — this command uses them as-is in `AskUserQuestion` headers.

For each option:
*   **Label**: Node's label text. Auto-append `...` if node has children.
*   **Description**: Node's description text.
*   **multiSelect**: `true` if any node at this level has the `[ ]` flag.

### Step 4: Resolve — Smart Parse

For each item's selection:

**Named option selected** (not Other):
*   **Leaf** (no children): Path = `CODE`.
*   **Branch** (has children): Follow-up `AskUserQuestion` with children. Path = `CODE/CHILD_CODE`. In batch mode, fire follow-ups per item as needed.
*   **Multi-select**: Comma-join all resolved paths (`TAG,BRS`).

**Other selected — Smart Parse Resolution Chain**:

- **Priority 1: Prefix trigger** (`Q:`, `?`, `???`, `!`, `#`, `@`, `+`)
  Action: Execute prefix behavior (see Universal Prefixes). Re-present after.
  Path: *(no path — re-present)*

- **Priority 2: A/B/C letter**
  Action: Execute the preamble smart extra. Agent announces: `> Matched: [extra description]`
  Path: `OTH/smart:[description]`

- **Priority 3: Local subchoice code** (e.g., `ABS`)
  Action: Auto-select that subchoice. Announce: `> Matched: [label]`
  Path: `OTH/CODE`

- **Priority 4: Local subchoice label** (e.g., `absolute`)
  Action: Case-insensitive match. Auto-select + announce.
  Path: `OTH/CODE`

- **Priority 5: Cross-tree keyword** (e.g., `model`, `depth`)
  Action: Agent contextually decides if a `¶ASK_*` tree is relevant. If yes, present that tree inline, then return.
  Path: *(cross-tree — handled separately)*

- **Priority 6: Blank/empty**
  Action: Navigate `[OTH]` subchoice menu (1 child → auto-select, N children → follow-up menu).
  Path: `OTH/PICKED`

- **Priority 7: Unmatched text**
  Action: Fallback to free text.
  Path: `OTH/custom:[text]`

**Announce on match**: When smart parse matches (priorities 2-4), the agent outputs a one-liner `> Matched: [label]` and proceeds — no blocking confirmation.

### Batch Follow-Up Rules (`¶INV_ASK_BATCH_PRESERVING_FOLLOWUP`)

When a follow-up is triggered for ONE item in a batch (branch selection, prefix trigger, Q: question, or any "Re-present" action):

1.  **Preserve resolved items**: Other items in the batch that already have answers are PRESERVED. Do NOT re-ask them.
2.  **Re-present only the triggering item**: Fire a NEW `AskUserQuestion` with a SINGLE question for the unresolved item. Header: `"Item N: Follow-up"` (using the item's original batch identifier).
3.  **Include follow-up context**: In the preamble before re-presenting, explain what triggered the follow-up (the user's question, the agent's answer, or the subtree navigation). The user needs context for why they're seeing this item again.
4.  **Continue the batch**: After the follow-up resolves, merge the result into `chosen_items[]` alongside the preserved answers. Proceed to the next batch (or Step 5 if this was the last batch).

**"Re-present" in batch context**: When the Universal Prefixes table says "Re-present tree" — in batch mode this means re-present ONLY the triggering item (not the entire batch). Other items' answers are final.

**Follow-up header convention**: The header for follow-up questions MUST include the item ID from the original batch. Format: `"{itemId}: Follow-up"` or `"{itemId}: [reason]"` (e.g., `"4.2.3/2: Subtree"`, `"4.2.3/2: Q&A"`).

### Step 5: Return

Return `chosen_items[]` — array of `{item, path}` objects. Single-item has 1 entry; batch has up to 4. No side effects — caller handles all downstream actions.

---

## Universal Prefixes

These work in every `[OTH]` text field across all `¶ASK_*` patterns. Resolved at priority 1 (before code/label matching).

- **`Q:` — Question**
  Behavior: Agent answers in chat with context, then generates new `AskUserQuestion` with derived options
  After: Re-present tree

- **`?` — Explain**
  Behavior: Agent rephrases the current question and options with more context
  After: Re-present tree

- **`???` — Deep explain**
  Behavior: Agent gives comprehensive background and rationale for each option
  After: Re-present tree

- **`!` — Force**
  Behavior: `!skip` / `!dismiss` / `![code]` — force-select without confirmation
  After: Resolve immediately

- **`#` — Tag**
  Behavior: `#needs-brainstorm` — triggers `§CMD_HANDLE_INLINE_TAG` on the active artifact
  After: Re-present tree

- **`@` — Reference**
  Behavior: `@path/to/file` — agent loads that file for context, summarizes relevance
  After: Re-present tree

- **`+` — Add**
  Behavior: `+[code]` — in multiSelect trees, add to current selection without replacing
  After: Accumulate selection

**Re-present**: After prefix execution, the same tree is shown again. The user can then pick a named option, type another prefix, or leave blank for OTH subchoices.

---

## Configuration

The caller provides:
*   **Tree definition**: Markdown tree block (inline or by reference).
*   **Items**: 1-4 items, each with `title` (used in question text and result), `itemId` (hierarchical ID per SIGILS.md § Item IDs — used in `AskUserQuestion` headers and `chosen_items[]` output), and `context` (displayed in chat before the question — caller generates context blocks, not this command).

---

## Batching Strategy (`¶INV_ASK_IN_BATCHES_OF_4`)

AskUserQuestion supports max 4 questions per call. Batch size = `floor(4 / roots_per_item)`:

- **1 root question**
  Batch Size: 4 items per call
  Example: Phase gate, granularity selection, model selection

- **2 root questions**
  Batch Size: 2 items per call
  Example: Tag triage (tag noun + action)

- **3-4 root questions**
  Batch Size: 1 item per call
  Example: Complex multi-dimension decisions

**Follow-ups don't count**: If an item selects `[OTH]` and needs a subtree follow-up, that's a separate `AskUserQuestion` call — it doesn't reduce the batch size. Batch on root questions only.

**Caller responsibility**: The caller (e.g., `§CMD_WALK_THROUGH_RESULTS`) chunks items by batch size and calls this command once per chunk.

---

## Constraints

*   **`¶INV_ASK_ALWAYS_FOUR`**: Every level has exactly 4 options: 3 named + `[OTH]`. No exceptions. Pad with useful alternatives rather than leaving 3 bare options. `[OTH]` always has subchoices — it provides extra options for free (only navigated when selected or left blank).
*   **`¶INV_ASK_WIDTH_LIMIT`**: Max 3 named options per level. The 4th is always `[OTH]`.
*   **`¶INV_ASK_DEPTH_LIMIT`**: Max 3 nesting levels.
*   **`¶INV_ASK_RETURNS_PATH`**: Pure decision collector — no side effects. Returns `chosen_items[]` only.
*   **`¶INV_ASK_OTH_SUBTREE`**: Empty Other → subtree; typed text → override.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All interactions via `AskUserQuestion`.
*   **`¶INV_ASK_IN_BATCHES_OF_4`**: AskUserQuestion supports max 4 questions per call. Batch size depends on tree roots per item: 1 root question/item → batch 4 items. 2 root questions/item → batch 2 items. Complex multi-root trees → batch 1 item. Always maximize batching to save round trips.
*   **`¶INV_ASK_BATCH_PRESERVING_FOLLOWUP`**: Follow-ups in batch mode preserve other items' answers and re-present ONLY the triggering item with `"Item N: Follow-up"` header. Never re-ask resolved items or break out of batch mode. See "Batch Follow-Up Rules" in Step 4.

---

## Example Trees

**Plan Review:**
```
## Decision: Plan Review
- [OK] Looks good
  No changes needed to this step
- [INF] More info needed
  I have questions about this step's approach
- [RWK] Rework this step
  Rewrite with a different approach
- [OTH] Other
  - [CHG] Change approach
    Fundamental direction change needed
  - [REM] Remove from plan
    This step is not needed
  - [SPL] Split this step
    Break into smaller sub-steps
```

**Approve/Reject:**
```
## Decision: Approval
- [APR] Approve
  Accept as-is
- [REJ] Reject
  Send back for revision
- [DEF] Defer
  Not ready to decide yet
- [OTH] Other
  - [CND] Conditional approve
    Approve with noted conditions
  - [ESC] Escalate
    Needs someone else's input
```

---

## PROOF FOR §CMD_DECISION_TREE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "treeName": {
      "type": "string",
      "description": "Name of the decision tree (from ## Decision: [Name])"
    },
    "chosenItems": {
      "type": "array",
      "description": "One entry per item. Single-item has 1; batch has up to 4.",
      "items": {
        "type": "object",
        "properties": {
          "item": { "type": "string", "description": "Item title/identifier" },
          "path": { "type": "string", "description": "Resolved path. Single-select: 'OK'. Multi-select: 'TAG,BRS'." }
        },
        "required": ["item", "path"]
      }
    }
  },
  "required": ["treeName", "chosenItems"],
  "additionalProperties": false
}
```
