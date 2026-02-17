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
  Description text (-> AskUserQuestion description)
- [CODE] Label text
  Description text
- Label text without code
  Description text
```

- **Heading** — `### ¶ASK_[NAME]` — UPPER_SNAKE, unique across all CMD/SKILL files
- **Trigger** — `Trigger: [description]` — prose line after heading, before `## Decision:`. Describes when this ask pattern is useful.
- **Extras** — `Extras: A: ... | B: ... | C: ...` — agent-generated smart extras shown in the preamble legend. Optional.
- **Identifier** — `[CODE]` — OPTIONAL. 3-4 uppercase letters from the Standard Label Vocabulary ONLY. Items that don't map to a standard code have no `[CODE]` prefix — just the label. Do NOT invent new codes.
- **Multi-select** — `- [CODE] [ ] Label` or `- [ ] Label` — `[ ]` turns the tree into multiSelect. Works with or without code prefix.
- **Flat peers** — ALL items are declared at the same indent level. No nesting hierarchy. The agent surfaces the top 4 by relevance; the rest are accessible via `/` in the Other field.
- **Width** — Declare any number of items (typically 5-10). Agent surfaces the top 4 for AskUserQuestion (`¶INV_ASK_SURFACE_FOUR`). No upper limit on declaration.
- **Description** — Indented line below label
- **Label text** — Max 3-4 words. Prefer verbs or adjectives over domain-specific nouns. Put detail in the description line, not the label.

**Path format**: Codes or labels tracing the selection path. Multi-select uses commas.

- `LGTM` — Direct selection of a coded option
- `Devil's advocate round` — Direct selection of a codeless option (uses label text)
- `custom:merge with step 3` — Other with typed text
- `LGTM,GRAB` — Multi-select: two coded items
- `NO/RWRK` — Nested: NO branch -> RWRK (for trees with branches, see Nesting below)

**Nesting** (optional): Items may have children (2-space indent). When a user selects a branch item, a follow-up `AskUserQuestion` shows its children. Hard limit: 3 levels. However, most trees should be flat peers — nesting is for genuinely hierarchical choices, not for overflow.

---

## Standard Label Vocabulary

34 reusable codes organized by semantic category. Tree authors MUST use codes from this vocabulary. Items that don't map to a standard code use their label only — no code prefix. This keeps codes meaningful and recognizable.

### Verdict — approval/rejection outcomes

*   LGTM — Approve / accept / looks good
*   RWRK — Reject / rework / redo
*   SKIP — Skip / pass / ignore
*   HOLD — Defer / wait / not now
*   INFO — Need more information

### Level — amount/detail spectrum

*   FULL — Maximum / all / complete
*   RICH — Detailed / thorough (but not max)
*   MEDM — Medium / moderate / balanced
*   LITE — Minimum / basic / bare
*   NONE — Nothing / zero
*   EACH — Per-item / individually
*   AUTO — Smart default / let system decide
*   SOME — Partial / selective / subset
*   DEEP — Drill into detail / go deeper

### Action — what to do

*   EDIT — Modify / change / update
*   DROP — Remove / delete / discard
*   KEEP — Retain / preserve / as-is
*   SWAP — Replace / switch / exchange
*   SPLT — Split / divide / break apart
*   MERG — Merge / combine / join
*   SEND — Delegate / route / dispatch / hand off
*   GRAB — Claim / take / pick up
*   COPY — Duplicate / clone / reuse
*   NEW — Create fresh / start over
*   MANY — Multiple / fan-out / parallel

### Navigation — flow control

*   NEXT — Proceed / continue / forward
*   BACK — Previous / return / go back
*   REDO — Try again / retry / repeat
*   DONE — Complete / finished / close out
*   VIEW — Inspect / review / examine first
*   MORE — Continue with more of the same
*   JUMP — Skip forward / leap ahead

### Scope — where it applies

*   HERE — Local / this file / this project
*   WIDE — Global / shared / everywhere

---

## Algorithm

### Step 1: Parse Tree

Extract all items from the tree definition: codes (`[CODE]`), labels, descriptions, multi-select flags, and any nested children.

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

### Step 3: Surface and Present

**Intelligent surfacing** (`¶INV_ASK_SURFACE_FOUR`): The tree declares N items. The agent selects the **top 4** most relevant to the current task context for the AskUserQuestion `options` array. The remaining items become the **overflow pool**, accessible via `/` in the Other field.

**Surfacing heuristics** (agent judgment — no mechanical rule):
*   Items that directly address the user's current situation surface first
*   Items selected in previous rounds or frequently used get priority
*   The default/most-common action (e.g., NEXT, LGTM) should almost always surface
*   Items that feel redundant with already-surfaced items drop to overflow

**Single item** (1 item): One `AskUserQuestion` with 4 surfaced options (+ implicit Other for `/`, smart parse, free text).

**Batch** (2-4 items): One `AskUserQuestion` with N questions (one per item). Each question offers the same 4 surfaced options.

**Header convention**: `ID. Label` format — the item's full hierarchical ID (per SIGILS.md § Item IDs) + dot + space + short descriptive label (up to 20 chars for the label portion). The header stays the same across follow-ups for the same item (stable identifier). Examples: `1. Auth Design`, `2.3. Caching Layer`, `2.3.1. Error Handling`.

**Question text convention**: At root level, the question text is a plain contextual question. At deeper levels (follow-ups after `/` or branch selection), prefix the question with a breadcrumb path in brackets: `[/]: More options` or `[//]: Even more options`. This shows the user where they are in the pagination.

For each surfaced option:
*   **Label**: `[CODE] ` prefix + Node's label text. The code prefix makes tree codes visible to the user, enabling smart parse (typed code matching). Auto-append `...` if node has children. Example: `[LGTM] Looks good`, `[RWRK] Rework this step...`.
*   **Description**: Node's description text.
*   **multiSelect**: `true` if the tree has the `[ ]` flag.

### Step 4: Resolve — Smart Parse

For each item's selection:

**Named option selected** (not Other):
*   **Leaf** (no children): Path = `CODE` (if coded) or label text (if codeless).
*   **Branch** (has children): Follow-up `AskUserQuestion` with children. Path = `CODE/CHILD_CODE`. In batch mode, fire follow-ups per item as needed.
*   **Multi-select**: Comma-join all resolved paths (`LGTM,GRAB`).

**Other selected — Smart Parse Resolution Chain**:

- **Priority 1: Prefix trigger** (`/`, `Q:`, `?`, `???`, `!`, `#`, `@`, `+`)
  Action: Execute prefix behavior (see Universal Prefixes). Re-present after.
  Path: *(no path — re-present)*

- **Priority 2: A/B/C letter**
  Action: Execute the preamble smart extra. Agent announces: `> Matched: [extra description]`
  Path: `smart:[description]`

- **Priority 3: Overflow item code** (e.g., `GRAB`)
  Action: Match against ALL coded tree items (not just the 4 surfaced). Auto-select if match found. Announce: `> Matched: [label]`
  Path: `CODE`

- **Priority 4: Overflow item label** (e.g., `devil's advocate`)
  Action: Case-insensitive match against ALL tree items (coded and codeless). Auto-select + announce.
  Path: `CODE` or label text

- **Priority 5: Cross-tree keyword** (e.g., `model`, `depth`)
  Action: Agent contextually decides if a `¶ASK_*` tree is relevant. If yes, present that tree inline, then return.
  Path: *(cross-tree — handled separately)*

- **Priority 6: Unmatched text**
  Action: Fallback to free text.
  Path: `custom:[text]`

**Announce on match**: When smart parse matches (priorities 2-4), the agent outputs a one-liner `> Matched: [label]` and proceeds — no blocking confirmation.

### `/` Pagination (Overflow Navigation)

When the user types `/` in the Other field, the agent presents the **overflow pool** — all tree items not shown in the current page.

**Algorithm**:
1.  Calculate overflow: all tree items minus the items shown on the current page.
2.  Select the top 4 overflow items by relevance (same surfacing heuristics as Step 3).
3.  Present via a NEW `AskUserQuestion` with these 4 items.
4.  Question text: `[/]: More options for [decision name]` (breadcrumb prefix).
5.  If overflow still has items beyond these 4, the user can type `/` again to see the next page.
6.  When all items have been shown, `/` loops back to the first page (the original 4 surfaced items).

**Page memory**: The agent tracks which items have been shown across pages. Each `/` shows NEW items not yet seen in this pagination session.

### Batch Follow-Up Rules (`¶INV_ASK_BATCH_PRESERVING_FOLLOWUP`)

When a follow-up is triggered for ONE item in a batch (branch selection, prefix trigger, Q: question, or any "Re-present" action):

1.  **Preserve resolved items**: Other items in the batch that already have answers are PRESERVED. Do NOT re-ask them.
2.  **Re-present only the triggering item**: Fire a NEW `AskUserQuestion` with a SINGLE question for the unresolved item. Header: same `ID. Label` as the original batch (stable — never changes). Question text: prefixed with breadcrumb path.
3.  **Include follow-up context**: In the preamble before re-presenting, explain what triggered the follow-up.
4.  **Continue the batch**: After the follow-up resolves, merge the result into `chosen_items[]` alongside the preserved answers.

**Follow-up header convention**: The header for follow-up questions MUST be identical to the original batch header (`ID. Label`). Navigation context goes in the question text as a breadcrumb prefix, not in the header.

### Step 5: Return

Return `chosen_items[]` — array of `{item, path}` objects. Single-item has 1 entry; batch has up to 4. No side effects — caller handles all downstream actions.

---

## Universal Prefixes

These work in the Other text field across all `¶ASK_*` patterns. Resolved at priority 1 (before code/label matching).

- **`/` — More items**
  Behavior: Show the next page of overflow items (up to 4 items not yet shown in this pagination session)
  After: Present overflow page

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

**Re-present**: After prefix execution, the current page is shown again. The user can then pick a named option, type another prefix, or type `/` for more items.

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

**Follow-ups don't count**: If an item triggers `/` pagination or a branch follow-up, that's a separate `AskUserQuestion` call — it doesn't reduce the batch size. Batch on root questions only.

**Caller responsibility**: The caller (e.g., `§CMD_WALK_THROUGH_RESULTS`) chunks items by batch size and calls this command once per chunk.

---

## Constraints

*   **`¶INV_ASK_SURFACE_FOUR`**: AskUserQuestion always shows exactly 4 named options (+ the built-in Other for `/`, smart parse, and free text). Trees declare N items as flat peers; the agent surfaces the top 4 by relevance. Replaces the former `¶INV_ASK_ALWAYS_FOUR` and `¶INV_ASK_WIDTH_LIMIT`.
*   **`¶INV_ASK_DEPTH_LIMIT`**: Max 3 nesting levels (for branch items with children). Most trees should be flat peers.
*   **`¶INV_ASK_RETURNS_PATH`**: Pure decision collector — no side effects. Returns `chosen_items[]` only.
*   **`¶INV_ASK_SLASH_FOR_MORE`**: The `/` prefix in Other navigates to overflow items. Each page shows up to 4 new items. Replaces the former `¶INV_ASK_OTH_SUBTREE`.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All interactions via `AskUserQuestion`.
*   **`¶INV_ASK_IN_BATCHES_OF_4`**: AskUserQuestion supports max 4 questions per call. Batch size depends on tree roots per item. Always maximize batching to save round trips.
*   **`¶INV_ASK_BATCH_PRESERVING_FOLLOWUP`**: Follow-ups in batch mode preserve other items' answers and re-present ONLY the triggering item with the same `ID. Label` header (stable). Breadcrumb path goes in question text. Never re-ask resolved items or break out of batch mode.

---

## Tree Overlay (Extends)

A derived tree can extend a base tree and only specify the delta. Items are matched by `[CODE]` (for coded items) or by label text (for codeless items).

### Overlay Syntax

```
### ¶ASK_[DERIVED_NAME]
Extends: §ASK_[BASE_NAME]
Trigger: [override — replaces base trigger]
Extras: [override — replaces base extras]

## Decision: [Name]
- [NEXT]
- Devil's advocate round
- [NEW] New option label
  New option description
```

### How Merging Works

Options are matched by `[CODE]` (coded items) or exact label text (codeless items):

- **Bare `[CODE]`** (no label/description) — inherit everything from the base tree
- **Bare label text** (no code, no description) — inherit description from the base item with matching label
- **`[CODE] Label` + description** or **`Label` + description** — override: use the overlay's definition
- **Base item absent from overlay** — dropped from the resolved tree
- **Overlay item not in base** — new addition

### Metadata Overrides

- `Trigger:` — replaces base trigger. Omit to inherit.
- `Extras:` — replaces base extras. Omit to inherit.

### Resolution Algorithm

1. Load base tree (resolve `Extends:` reference)
2. Apply metadata overrides (Trigger, Extras)
3. Walk the overlay's item list:
   a. For each item — match to base by `[CODE]` (coded) or label text (codeless). If bare (no description), inherit from base; if defined, use overlay's definition
   b. Base items not present in the overlay are dropped
   c. Order follows the overlay (not the base)
4. Present the resolved tree via normal Step 2-4 flow (agent surfaces top 4 from the resolved list)

### Overlay Constraints

- **Base must exist**: `Extends:` must resolve to a defined `¶ASK_*` tree
- **Codes are stable**: Bare `[CODE]` references must exist in the base. Base code renames break the overlay (intentional — forces review)
- **Single inheritance**: No chaining (A extends B extends C). Depth limit = 1

### Overlay Example

Base: `§ASK_INTERROGATION_EXIT` has [NEXT], [MORE], [DEEP] (coded) + Devil's advocate round, What-if scenarios round, Gaps round (codeless)

Derived: `¶ASK_CALIBRATION_EXIT` — adds Return to Research Loop, drops Gaps round:

```
### ¶ASK_CALIBRATION_EXIT
Extends: §ASK_INTERROGATION_EXIT
Trigger: after minimum calibration rounds are met

## Decision: Calibration Exit
- [NEXT]
- [MORE]
- [DEEP]
- Devil's advocate round
- What-if scenarios round
- Return to Research Loop
  Go back to Phase 1 for more autonomous exploration
```

Resolved: [NEXT]*(inherited)*, [MORE]*(inherited)*, [DEEP]*(inherited)*, Devil's advocate*(inherited)*, What-if scenarios*(inherited)*, Return to Research Loop*(new)*. Gaps round dropped (absent from overlay). Agent surfaces top 4 of these 6 based on context.

---

## Example Trees

**Plan Review (7 items — agent surfaces top 4):**
```
## Decision: Plan Review
- [LGTM] Looks good
  No changes needed to this step
- [INFO] More info needed
  I have questions about this step's approach
- [RWRK] Rework this step
  Rewrite with a different approach
- [SWAP] Change approach
  Fundamental direction change needed
- [DROP] Remove from plan
  This step is not needed
- [SPLT] Split this step
  Break into smaller sub-steps
- [MERG] Merge with another step
  Combine this step with an adjacent one
```

**Approve/Reject (5 items — agent surfaces top 4):**
```
## Decision: Approval
- [LGTM] Approve
  Accept as-is
- [RWRK] Reject
  Send back for revision
- [HOLD] Defer
  Not ready to decide yet
- [EDIT] Conditional approve
  Approve with noted conditions
- [SEND] Escalate
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
