### ¶CMD_DECISION_TREE
**Definition**: General-purpose declarative decision collector. Navigates markdown-defined trees via `AskUserQuestion`. Supports single-item and batch (up to 4 items) invocation. Returns `chosen_items[]` — no side effects.
**Trigger**: Called by `§CMD_WALK_THROUGH_RESULTS`, `§CMD_DISPATCH_APPROVAL`, `§CMD_EXECUTE_PHASE_STEPS`, or any protocol step needing structured decisions.

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
- [MORE] Other
  - [DEF] Default if blank
    Description
```

- **Heading** — `### ¶ASK_[NAME]` — UPPER_SNAKE, unique across all CMD/SKILL files
- **Trigger** — `Trigger: [description]` — prose line after heading, before `## Decision:`. Describes when this ask pattern is useful.
- **Identifier** — `[CODE]` — exactly 4 uppercase letters, unique within siblings
- **Multi-select** — `- [CODE] [ ] Label` — `[ ]` after code turns the level into multiSelect
- **Nesting** — 2-space indent per level. Hard limit: 3 levels
- **Width** — Exactly 3 named options + `[MORE]` per level = 4 total (`¶INV_ASK_ALWAYS_FOUR`)
- **Description** — Indented line below label
- **`[MORE]`** — Explicit Other subtree. Blank input → navigate children. Typed text → smart parse (see below). Always has ≥2 subchoices.
- **`...` indicator** — Auto-appended to labels with children. Not written by authors

**Path format**: Slash-separated codes tracing the selection path. Multi-select uses commas.

- **`LGTM`** — Direct leaf
- **`NO/RWRK`** — Nested: NO → RWRK
- **`MORE/custom:merge with step 3`** — Other with typed text
- **`MORE/RWRK`** — Other blank → auto-select or menu pick
- **`TAG,BRS`** — Multi-select: two leaves
- **`TAG,NO/RWRK`** — Multi-select: one leaf + one nested

---

## Algorithm

### Step 1: Parse Tree

Extract from the tree definition: nodes (`[CODE]`, label, description, children), multi-select flags, `[MORE]` subtree presence.

### Step 2: Preamble (Context + Legend)

Before calling `AskUserQuestion`, output a **preamble** in chat. The preamble has two parts: (1) context explaining WHAT and WHY, (2) extended options legend. Always shown — consistent UX. The user does NOT read log files or artifacts — the preamble IS their context window for making this decision.

**Format**:
> [1-2 paragraphs: WHAT decision is being made, WHY it matters, and enough context for the user to choose without reading any files. In batch mode, include per-item context blocks before the legend.]
>
> **Also:** A: [smart extra 1] | B: [smart extra 2] | C: [smart extra 3]
> **Try:** /: more | Q: ask a question | ?: explain | !: skip
>
>
> *(two trailing blank lines — UI overlay workaround, required per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`)*

**Context requirement** (`¶INV_QUESTION_GATE_OVER_TEXT_GATE`): The context paragraphs are NOT optional. A bare A/B/C legend without explanation is a violation. The user must understand what they're deciding and why from the preamble alone.

**Trailing blank lines**: The last TWO lines of chat text before the `AskUserQuestion` call MUST be empty lines (`\n\n`). The question UI element overlaps the bottom of preceding text — a single blank line is insufficient padding. Two blank lines ensure the Try: line and final context sentence remain visible above the UI overlay. This applies to ALL preambles before `AskUserQuestion`, not just decision tree preambles.

**A/B/C smart extras**: Agent-generated options based on current context — not from the tree definition. These are creative alternatives the agent thinks are relevant. Examples:
*   During tag triage: `A: #needs-brainstorm + #needs-implementation | B: Defer to next session | C: Split into 2 items`
*   During phase gate: `A: Run tests first | B: Quick sanity check | C: Commit and move on`
*   For enum-style trees (depth, model): A/B/C may be omitted if no useful smart extras exist.

### Step 3: Present

**Single item** (1 item): One `AskUserQuestion` with the tree's root nodes as options (3 named + implicit Other).

**Batch** (2-4 items): One `AskUserQuestion` with N questions (one per item). Each question offers the same root nodes as options.

**Header convention**: `ID. Label` format — the item's full hierarchical ID (per SIGILS.md § Item IDs) + dot + space + short descriptive label (up to 20 chars for the label portion). The header stays the same across follow-ups for the same item (stable identifier). Examples: `1. Auth Design`, `2.3. Caching Layer`, `2.3.1. Error Handling`.

**Question text convention**: At root level, the question text is a plain contextual question. At deeper levels (follow-ups after branch/MORE selection), prefix the question with a breadcrumb path in brackets: `[CODE]: Question text` or `[CODE/SUB]: Question text`. This shows the user where they are in the tree without cluttering the header chip.

*   Root: `"How does Auth Design fit the system?"`
*   Depth 1: `"[MORE]: What should change about Auth Design?"`
*   Depth 2: `"[MORE/CHG]: How should Auth Design change?"`

For each option:
*   **Label**: `[CODE] ` prefix + Node's label text. The code prefix makes tree codes visible to the user, enabling Priority 3 smart parse (typed code matching). Auto-append `...` if node has children. Example: `[LGTM] Looks good`, `[RWRK] Rework this step...`.
*   **Description**: Node's description text.
*   **multiSelect**: `true` if any node at this level has the `[ ]` flag.

### Step 4: Resolve — Smart Parse

For each item's selection:

**Named option selected** (not Other):
*   **Leaf** (no children): Path = `CODE`.
*   **Branch** (has children): Follow-up `AskUserQuestion` with children. Path = `CODE/CHILD_CODE`. In batch mode, fire follow-ups per item as needed.
*   **Multi-select**: Comma-join all resolved paths (`TAG,BRS`).

**Other selected — Smart Parse Resolution Chain**:

- **Priority 1: Prefix trigger** (`/`, `Q:`, `?`, `???`, `!`, `#`, `@`, `+`)
  Action: Execute prefix behavior (see Universal Prefixes). Re-present after.
  Path: *(no path — re-present)*

- **Priority 2: A/B/C letter**
  Action: Execute the preamble smart extra. Agent announces: `> Matched: [extra description]`
  Path: `MORE/smart:[description]`

- **Priority 3: Local subchoice code** (e.g., `ABS`)
  Action: Auto-select that subchoice. Announce: `> Matched: [label]`
  Path: `MORE/CODE`

- **Priority 4: Local subchoice label** (e.g., `absolute`)
  Action: Case-insensitive match. Auto-select + announce.
  Path: `MORE/CODE`

- **Priority 5: Cross-tree keyword** (e.g., `model`, `depth`)
  Action: Agent contextually decides if a `¶ASK_*` tree is relevant. If yes, present that tree inline, then return.
  Path: *(cross-tree — handled separately)*

- **Priority 6: `/` (more)**
  Action: Navigate `[MORE]` subchoice menu (1 child → auto-select, N children → follow-up menu).
  Path: `MORE/PICKED`

- **Priority 7: Unmatched text**
  Action: Fallback to free text.
  Path: `MORE/custom:[text]`

**Announce on match**: When smart parse matches (priorities 2-4), the agent outputs a one-liner `> Matched: [label]` and proceeds — no blocking confirmation.

### Batch Follow-Up Rules (`¶INV_ASK_BATCH_PRESERVING_FOLLOWUP`)

When a follow-up is triggered for ONE item in a batch (branch selection, prefix trigger, Q: question, or any "Re-present" action):

1.  **Preserve resolved items**: Other items in the batch that already have answers are PRESERVED. Do NOT re-ask them.
2.  **Re-present only the triggering item**: Fire a NEW `AskUserQuestion` with a SINGLE question for the unresolved item. Header: same `ID. Label` as the original batch (stable — never changes). Question text: prefixed with breadcrumb path (e.g., `[MORE]: ...`).
3.  **Include follow-up context**: In the preamble before re-presenting, explain what triggered the follow-up (the user's question, the agent's answer, or the subtree navigation). The user needs context for why they're seeing this item again.
4.  **Continue the batch**: After the follow-up resolves, merge the result into `chosen_items[]` alongside the preserved answers. Proceed to the next batch (or Step 5 if this was the last batch).

**"Re-present" in batch context**: When the Universal Prefixes table says "Re-present tree" — in batch mode this means re-present ONLY the triggering item (not the entire batch). Other items' answers are final.

**Follow-up header convention**: The header for follow-up questions MUST be identical to the original batch header (`ID. Label`). Navigation context goes in the question text as a breadcrumb prefix (`[CODE]: ...`), not in the header. This keeps the header stable so the user always knows which item they're deciding on.

### Step 5: Return

Return `chosen_items[]` — array of `{item, path}` objects. Single-item has 1 entry; batch has up to 4. No side effects — caller handles all downstream actions.

---

## Universal Prefixes

These work in every `[MORE]` text field across all `¶ASK_*` patterns. Resolved at priority 1 (before code/label matching).

- **`/` — More**
  Behavior: Navigate the `[MORE]` subtree — show subchoice menu (1 child → auto-select, N children → follow-up menu)
  After: Present subtree

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

**Re-present**: After prefix execution, the same tree is shown again. The user can then pick a named option, type another prefix, or type `/` for MORE subchoices.

---

## Configuration

The caller provides:
*   **Tree definition**: Markdown tree block (inline or by reference).
*   **Items**: 1-4 items, each with `title` (used in question text and result), `itemId` (hierarchical ID per SIGILS.md § Item IDs — tracked internally in `chosen_items[]` output, NOT used as headers), `label` (short descriptive label for the `AskUserQuestion` header — up to 20 chars, e.g., `"Auth Design"`), and `context` (displayed in chat before the question — caller generates context blocks, not this command).

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

**Follow-ups don't count**: If an item selects `[MORE]` and needs a subtree follow-up, that's a separate `AskUserQuestion` call — it doesn't reduce the batch size. Batch on root questions only.

**Caller responsibility**: The caller (e.g., `§CMD_WALK_THROUGH_RESULTS`) chunks items by batch size and calls this command once per chunk.

---

## Constraints

*   **`¶INV_ASK_ALWAYS_FOUR`**: Every level has exactly 4 options: 3 named + `[MORE]`. No exceptions. Pad with useful alternatives rather than leaving 3 bare options. `[MORE]` always has subchoices — it provides extra options for free (only navigated when selected or left blank).
*   **`¶INV_ASK_WIDTH_LIMIT`**: Max 3 named options per level. The 4th is always `[MORE]`.
*   **`¶INV_ASK_DEPTH_LIMIT`**: Max 3 nesting levels.
*   **`¶INV_ASK_RETURNS_PATH`**: Pure decision collector — no side effects. Returns `chosen_items[]` only.
*   **`¶INV_ASK_OTH_SUBTREE`**: Empty Other → subtree; typed text → override.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All interactions via `AskUserQuestion`.
*   **`¶INV_ASK_IN_BATCHES_OF_4`**: AskUserQuestion supports max 4 questions per call. Batch size depends on tree roots per item: 1 root question/item → batch 4 items. 2 root questions/item → batch 2 items. Complex multi-root trees → batch 1 item. Always maximize batching to save round trips.
*   **`¶INV_ASK_BATCH_PRESERVING_FOLLOWUP`**: Follow-ups in batch mode preserve other items' answers and re-present ONLY the triggering item with the same `ID. Label` header (stable). Breadcrumb path goes in question text. Never re-ask resolved items or break out of batch mode. See "Batch Follow-Up Rules" in Step 4.

---

## Tree Overlay (Extends)

A derived tree can extend a base tree and only specify the delta. The overlay uses normal tree structure — items are auto-merged by matching `[CODE]`.

### Overlay Syntax

```
### ¶ASK_[DERIVED_NAME]
Extends: §ASK_[BASE_NAME]
Trigger: [override — replaces base trigger]
Extras: [override — replaces base extras]

## Decision: [Name]
- [BASE_CODE]
- [BASE_CODE]
- [NEWC] [ ] New option label
  New option description
- [OTH]
  - [MVCD] Moved option with new label
    Moved option description
  - [BASE_CODE]
```

### How Merging Works

Options are matched by `[CODE]` between base and overlay:

- **Bare `[CODE]`** (no label/description) — inherit everything from the base tree at that position
- **`[CODE] Label` + description** — override: use the overlay's label and description (new item or redefined existing)
- **Base item absent from overlay** — dropped from the resolved tree
- **Overlay item not in base** — new addition (position = where it appears in the overlay)

### Metadata Overrides

- `Trigger:` — replaces base trigger. Omit to inherit.
- `Extras:` — replaces base extras. Omit to inherit.

### Resolution Algorithm

1. Load base tree (resolve `Extends:` reference)
2. Apply metadata overrides (Trigger, Extras)
3. Walk the overlay tree level by level:
   a. For each `[CODE]` in the overlay — if bare, copy label+description from base; if defined, use overlay's definition
   b. Base items not present in the overlay at that level are dropped
   c. Order follows the overlay (not the base)
4. Present the resolved tree via normal Step 2-4 flow

### Overlay Constraints

- **Base must exist**: `Extends:` must resolve to a defined `¶ASK_*` tree
- **Codes are stable**: Bare `[CODE]` references must exist in the base. Base code renames break the overlay (intentional — forces review)
- **Width preserved**: Each level in the resolved tree must have exactly 4 options (`¶INV_ASK_ALWAYS_FOUR`)
- **Single inheritance**: No chaining (A extends B extends C). Depth limit = 1

### Overlay Example

Base: `§ASK_INTERROGATION_EXIT` has [NEXT], [MORE], [DEVL], [OTHR]→[WHIF],[DEEP],[GAPS]

Derived: `¶ASK_CALIBRATION_EXIT` — replaces top-level [DEVL] with [RTRN], moves [DEVL] under [OTHR], drops [GAPS]:

```
### ¶ASK_CALIBRATION_EXIT
Extends: §ASK_INTERROGATION_EXIT
Trigger: after minimum calibration rounds are met

## Decision: Calibration Exit
- [NEXT]
- [MORE]
- [RTRN] [ ] Return to Research Loop
  Go back to Phase 1 for more autonomous exploration
- [OTHR]
  - [DEVL] Devil's advocate round
    1 round challenging assumptions and decisions made so far
  - [WHIF]
  - [DEEP]
```

Resolved: [NEXT]*(inherited)*, [MORE]*(inherited)*, [RTRN]*(new)*, [OTHR]→[DEVL]*(moved+redefined)*, [WHIF]*(inherited)*, [DEEP]*(inherited)*. [GAPS] dropped (absent from overlay).

---

## Example Trees

**Plan Review:**
```
## Decision: Plan Review
- [LGTM] Looks good
  No changes needed to this step
- [INFO] More info needed
  I have questions about this step's approach
- [RWRK] Rework this step
  Rewrite with a different approach
- [MORE] Other
  - [SWAP] Change approach
    Fundamental direction change needed
  - [DROP] Remove from plan
    This step is not needed
  - [SPLT] Split this step
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
- [MORE] Other
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
