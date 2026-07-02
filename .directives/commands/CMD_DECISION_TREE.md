### ¶CMD_DECISION_TREE
**Definition**: General-purpose declarative decision collector. Navigates markdown-defined trees via `AskUserQuestion`. Supports single-item and batch (up to 4 items) invocation. Returns `chosen_items[]` — no side effects.
**Trigger**: Called by `§CMD_WALK_THROUGH_RESULTS`, `§CMD_DISPATCH_APPROVAL`, `§CMD_EXECUTE_PHASE_STEPS`, or any protocol step needing structured decisions.

---

## Markdown Tree Format

```
## ¶ASK_[NAME]: Choose one: [Title]
Trigger: [when this ask pattern is useful — prose description]
Extras: A: ... | B: ... | C: ...

- [ ] [CODE] Label text
  Description text (-> AskUserQuestion description)
- [ ] [CODE] Label text
  Description text
- [ ] Label text without code
  Description text
```

- **Heading** — `## ¶ASK_[NAME]: Choose one: [Title]` — single heading combining the tree identifier and title. UPPER_SNAKE name, unique across all CMD/SKILL files. Use `Choose one:` for single-select, `Choose:` for multi-select.
- **Trigger** — `Trigger: [description]` — metadata line after heading, before options. Describes when this ask pattern is useful.
- **Extras** — `Extras: A: ... | B: ... | C: ...` — agent-generated smart extras shown in the preamble legend. Optional.
- **Identifier** — `[CODE]` — OPTIONAL. 3-4 uppercase letters from the Standard Label Vocabulary ONLY. Items that don't map to a standard code have no `[CODE]` prefix — just the label. Do NOT invent new codes.
- **Hidden identifier** — `[_CODE]` — Machine-readable key NOT shown to the user. The underscore prefix means "internal." In the answer store, the underscore is stripped: `[_REASON]` → store key `REASON`. Use hidden codes when a question needs to be queryable by conditions but shouldn't display a code badge visually.
- **Checkbox prefix** — `- [ ]` — ALL options get a checkbox prefix. This is universal formatting, not a multi-select signal. Multi-select vs single-select is determined by the heading (`Choose:` vs `Choose one:`).
- **Flat peers** — ALL items are declared at the same indent level. No nesting hierarchy. The agent surfaces the top 4 by relevance; the rest are accessible via `/` in the Other field.
- **Width** — Declare any number of items (typically 5-10). Agent surfaces the top 4 for AskUserQuestion (`¶INV_ASK_SURFACE_FOUR`). No upper limit on declaration.
- **Description** — Indented line below label
- **Label text** — Max 3-4 words. Prefer verbs or adjectives over domain-specific nouns. Put detail in the description line, not the label.
- **Anonymous trees** — Trees without a `¶ASK_` name use just `## Choose one: [Title]` or `## Choose: [Title]`.

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
*   **multiSelect**: `true` if the heading uses `Choose:` (multi-select) instead of `Choose one:` (single-select).

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
## ¶ASK_[DERIVED_NAME]: Choose one: [Name]
Extends: §ASK_[BASE_NAME]
Trigger: [override — replaces base trigger]
Extras: [override — replaces base extras]

- [ ] [NEXT]
- [ ] Devil's advocate round
- [ ] [NEW] New option label
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

Derived: `¶ASK_SKILL_SPECIFIC_EXIT` — adds Return to Research Loop, drops Gaps round:

```
## ¶ASK_SKILL_SPECIFIC_EXIT: Choose: Skill-Specific Exit
Extends: §ASK_INTERROGATION_EXIT
Trigger: after minimum skill-specific rounds are met

- [ ] [NEXT]
- [ ] [MORE]
- [ ] [DEEP]
- [ ] Devil's advocate round
- [ ] What-if scenarios round
- [ ] Return to Research Loop
  Go back to Phase 1 for more autonomous exploration
```

Resolved: [NEXT]*(inherited)*, [MORE]*(inherited)*, [DEEP]*(inherited)*, Devil's advocate*(inherited)*, What-if scenarios*(inherited)*, Return to Research Loop*(new)*. Gaps round dropped (absent from overlay). Agent surfaces top 4 of these 6 based on context.

---

## Example Trees

### Static: Plan Review (7 items — agent surfaces top 4)
```
## Choose one: Plan Review

- [ ] [LGTM] Looks good
  No changes needed to this step
- [ ] [INFO] More info needed
  I have questions about this step's approach
- [ ] [RWRK] Rework this step
  Rewrite with a different approach
- [ ] [SWAP] Change approach
  Fundamental direction change needed
- [ ] [DROP] Remove from plan
  This step is not needed
- [ ] [SPLT] Split this step
  Break into smaller sub-steps
- [ ] [MERG] Merge with another step
  Combine this step with an adjacent one
```

### Static: Approve/Reject (5 items — agent surfaces top 4)
```
## Choose one: Approval

- [ ] [LGTM] Approve
  Accept as-is
- [ ] [RWRK] Reject
  Send back for revision
- [ ] [HOLD] Defer
  Not ready to decide yet
- [ ] [EDIT] Conditional approve
  Approve with noted conditions
- [ ] [SEND] Escalate
  Needs someone else's input
```

### Conditional: Review with Follow-Up Questions

Shows `(if:)` for dependent questions, `(Recommended if:)` for conditional recommendations, `[_CODE]` for hidden codes, and multi-select `[ ]`.

```
## Choose one: Review
- [VERDICT] Overall verdict
  - [APR] Approve (Recommended)
    No changes needed
  - [REJ] Reject
    Send back for revision
  - [DEF] Defer
    Not ready to decide
- [_REASON] Why reject? (if: VERDICT == 'REJ')
  - [QUA] Quality issues (Recommended if: VERDICT == 'REJ')
    Code quality or correctness problems
  - [SCO] Out of scope
    This work doesn't belong here
  - [INC] Incomplete
    Missing required elements
- [NEXT] Next action (if: VERDICT == 'REJ')
  - [RWK] Rework (Recommended if: REASON == 'QUA')
    Author revises and resubmits
  - [ESC] Escalate (Recommended if: REASON == 'SCO')
    Route to appropriate owner
  - [BLK] Block
    Cannot proceed until resolved
- [TAGS] [ ] Tag this item (if: VERDICT != 'DEF')
  - [URG] Urgent
  - [BKR] Blocker
  - [FYI] Info only
- [PRI] Priority (if: VERDICT != 'DEF')
  - [HI] High
  - [MED] Medium (Recommended)
  - [LO] Low
```

**What happens**: User sees VERDICT first. If they pick REJ, REASON and NEXT appear. If they pick APR or REJ, TAGS (multi-select) and PRI appear. DEF hides everything else. `[_REASON]` is queryable by NEXT's recommendations but the code badge isn't shown to the user.

### Conditional: Cross-Item Batch Shortcut

Shows `$` queries for cross-item state — options that appear based on what happened in prior items.

```
## Choose one: Batch Review
- [VERDICT] Overall verdict
  - [APR] Approve (Recommended)
    No changes needed
  - [REJ] Reject
    Send back for revision
- [BULK] Apply to all remaining (if: $[?@.VERDICT == 'APR'].length > 3)
  - [YES] Yes, approve the rest
    Skip review for remaining items
  - [NO] No, keep reviewing
    Continue one by one
```

**What happens**: BULK only appears after 3+ items have been approved across the batch. The `$[?@.VERDICT == 'APR'].length > 3` query counts all prior items where VERDICT was APR.

### Checklist: Mutually Exclusive Branches

Shows the checklist interpretation mode — top-level branches are select-one, nested items are select-all. The LLM fills `[x]` marks.

```markdown
## Structure

- [ ] I DID create or modify SKILL.md
  - [ ] YAML frontmatter has `name`, `description`, `version`, `tier`
  - [ ] Boot sector present at top
  - [ ] JSON manifest block is valid
  - [ ] `assets/` directory exists with log and debrief templates
- [ ] I DID NOT create or modify SKILL.md
  - [ ] Confirmed changes don't affect skill structure

## Modes

- [ ] I DID create or modify mode files
  - [ ] `modes/` directory has 3 named modes + custom
  - [ ] Each mode file has Role, Goal, Mindset, and Approach sections
- [ ] I DID NOT create or modify mode files
  - [ ] Confirmed no mode changes needed
```

**LLM fills it as** (example — did modify SKILL.md, did not modify modes):
```markdown
## Structure

- [x] I DID create or modify SKILL.md
  - [x] YAML frontmatter has `name`, `description`, `version`, `tier`
  - [x] Boot sector present at top
  - [x] JSON manifest block is valid
  - [x] `assets/` directory exists with log and debrief templates
- [ ] I DID NOT create or modify SKILL.md
  - [ ] Confirmed changes don't affect skill structure

## Modes

- [ ] I DID create or modify mode files
  - [ ] `modes/` directory has 3 named modes + custom
  - [ ] Each mode file has Role, Goal, Mindset, and Approach sections
- [x] I DID NOT create or modify mode files
  - [x] Confirmed no mode changes needed
```

**Validation rules**: Exactly one top-level branch per `##` section. All nested items under the selected branch must be `[x]`. Evaluator rejects if both branches checked, or if any nested item under the selected branch is unchecked.

### Conditional: Hidden Code with Static Recommendation

Shows `[_CODE]` for a question that doesn't need a visible badge but is referenced by later conditions.

```
## Choose one: Deployment
- [_ENV] Target environment
  - [STG] Staging (Recommended)
    Deploy to staging first
  - [PRD] Production
    Direct production deploy
- [_CONFIRM] Confirm production? (if: ENV == 'PRD')
  - [YES] Yes, deploy to prod
    I understand the risks
  - [NO] No, switch to staging
    Changed my mind
- [NOTIFY] Notify team? (if: ENV == 'PRD')
  - [YES] Yes, send alert
    Post in #deploys channel
  - [NO] No, silent deploy
    Skip notification
```

**What happens**: ENV and CONFIRM are hidden codes — no badge shown to the user, but the questions still appear and their answers are queryable. Selecting PRD triggers both CONFIRM and NOTIFY follow-ups.

---

## Conditional Syntax

Trees support conditional visibility and conditional recommendations via inline attributes. Conditions use expressions evaluated against the current scope (merged data object in data-driven trees, answer store in static trees).

### Condition Attributes

```
(if: EXPR)                    — Show this question/option only when EXPR is true
(Recommended)                 — Static recommendation (always shown as first option)
(Recommended if: EXPR)        — Conditional recommendation (shown as first when EXPR is true)
```

Attributes are parenthetical, placed after the label on the same line. Multiple attributes can coexist: `- [RWK] Rework (if: VERDICT == 'REJ') (Recommended if: REASON == 'QUA')`.

### Expression Patterns

Conditions use two namespaces:

- **Bare name** — Current scope (current item inside `each`, root outside). Use for intra-tree conditions.
- **`$`** — Data root. Use for cross-item conditions and root-level data access.

*   `CODE == 'VAL'` — Current scope's answer equals value. Example: `VERDICT == 'REJ'`
*   `CODE != 'VAL'` — Current scope's answer not equal. Example: `VERDICT != 'DEF'`
*   `CODE[?@ == 'VAL']` — Multi-select membership (truthy if non-empty). Example: `TAGS[?@ == 'urgent']`
*   `CODE.length > N` — Multi-select count. Example: `TAGS.length > 2`
*   `$[*].CODE` — All items' answers for CODE. Example: `$[*].VERDICT`
*   `$[?@.CODE == 'VAL']` — Filter items by answer (JSONPath filter). Example: `$[?@.VERDICT == 'REJ']`
*   `$[?@.CODE == 'VAL'].length > N` — Count items matching. Example: `$[?@.VERDICT == 'APR'].length > 3`

**`@` in filters**: Inside JSONPath filter expressions `[?...]`, `@` is the standard JSONPath filter variable (the element being tested). This is distinct from the top-level bare name syntax. Top-level conditions use bare names (`VERDICT == 'REJ'`); filter expressions use `@` per JSONPath spec (`$[?@.VERDICT == 'APR']`).

**Backward compatibility**: The evaluator accepts both bare `CODE` and legacy `@.CODE` at the top level. `@.CODE` is treated as equivalent to bare `CODE` (the `@.` prefix is stripped). New trees should use bare names exclusively.

### Conditional Example

```
## Choose one: Review
- [VERDICT] Overall verdict
  - [APR] Approve (Recommended)
    No changes needed
  - [REJ] Reject
    Send back for revision
  - [DEF] Defer
    Not ready to decide
- [_REASON] Why reject? (if: VERDICT == 'REJ')
  - [QUA] Quality issues (Recommended if: VERDICT == 'REJ')
    Code quality or correctness problems
  - [SCO] Out of scope
    This work doesn't belong here
  - [INC] Incomplete
    Missing required elements
- [NEXT] Next action (if: VERDICT == 'REJ')
  - [RWK] Rework (Recommended if: REASON == 'QUA')
    Author revises and resubmits
  - [ESC] Escalate (Recommended if: REASON == 'SCO')
    Route to appropriate owner
  - [BLK] Block
    Cannot proceed until resolved
- [TAGS] [ ] Tag this item (if: VERDICT != 'DEF')
  - [URG] Urgent
  - [BKR] Blocker
  - [FYI] Info only
- [PRI] Priority (if: VERDICT != 'DEF')
  - [HI] High
  - [MED] Medium (Recommended)
  - [LO] Low
- [BULK] Apply to all remaining (if: $[?@.VERDICT == 'APR'].length > 3)
  - [YES] Yes, approve rest
  - [NO] No, continue one by one
```

---

## Data-Driven Trees (`each` Directive)

Trees support data-driven batching via the `each` directive. Questions bound to a data array repeat per item; unbound questions appear once. Answers merge into data items — the data object IS the state.

### Sigil Model

*   **`$`** — Data root. `$.bugs` accesses the root array. `$.bugs[0].title` for deep access.
*   **Bare name** — Current scope. Inside `each`: item field or answer code. Outside `each`: root field.
*   **`@`** — DEPRECATED at top level. Backward compatible (treated as bare name). Only valid inside JSONPath `[?...]` filters.

### `each` Directive Syntax

```
## Choose one: Bug Triage
(each: $.bugs, label: title, if: status == 'critical')

- [VERDICT] What's the verdict?
  - [APR] Approve
  - [REJ] Reject
- [_REASON] Why reject? (if: VERDICT == 'REJ')
  - [QUA] Quality
  - [SCO] Scope
```

**Directive parameters** (parenthetical, on the tree heading or question line):
*   `(each: $.bugs)` — Iterate over data array, bind answers to items
*   `(each: $.bugs, label: title)` — Iterate with auto-header from data field
*   `(each: $.bugs, if: status == 'critical')` — Iterate with filter on item fields
*   All three combine: `(each: $.bugs, label: title, if: status == 'critical')`

### Data Flow

1.  **Agent sends data**: `{ bugs: [{title: "Login crash", status: "critical"}, ...] }`
2.  **Expansion**: `each` multiplies bound questions × data items. Unbound questions appear once.
3.  **Answer merge**: User answers write back to data items: `$.bugs[0].VERDICT = 'APR'`
4.  **Response**: Merged data object returned — `{ bugs: [{title: "Login crash", status: "critical", VERDICT: "APR"}, ...], CONFIRM: "YES" }`

### Visual Grouping

Questions bound via `each` render with group headers (bold label from `label:` parameter) and dividers between item groups. Example with `(each: $.bugs, label: title)`:

```
──────────────────────
LOGIN CRASH
──────────────────────
What's the verdict? [APR] [REJ]
──────────────────────
CSS GLITCH
──────────────────────
What's the verdict? [APR] [REJ]
```

### Interpolation

Template interpolation in labels and descriptions via `{{field}}`:
*   `{{title}}` — Current scope field (item field inside `each`, root field outside)
*   `{{$.totalCount}}` — Root data field (explicit `$` prefix)

### Unbound Questions

Questions outside any `each` block are unbound. Their answers live at the data root: `$.CONFIRM = 'YES'`.

### Staggered Guards

Inside an `each` block, guards reference the current item's merged state. After answering VERDICT for bug 0, `(if: VERDICT == 'REJ')` checks bug 0's VERDICT — enabling staggered reveal per item.

### Schema

The agent provides a JSON Schema for the initial data shape. Use `additionalProperties: true` to allow answer fields to be merged in. The schema MAY optionally constrain answer values.

### Constraints

*   **Single level**: Nested `each` is not supported (v1). One level of iteration only.
*   **Empty arrays**: `(each: $.bugs)` with `$.bugs = []` produces zero questions (no error).
*   **Convention**: Answer codes are UPPER (`[VERDICT]`), data fields are camelCase (`title`, `status`). No runtime ambiguity — same object namespace.

---

## Checklist Mode

Checklists ARE decision trees. The same markdown format is used, with specific interpretation rules for LLM-driven filling:

- **Top-level items** (separated by `##` section headers) are **select-one** — mutually exclusive branches. The LLM selects exactly one branch per section by marking it `[x]`.
- **Nested items** under the selected branch are **select-all** — the LLM must check ALL nested items with `[x]`.
- **Validation**: Evaluator enforces exactly one top-level branch checked per section, all nested items under that branch checked.

**LLM interaction protocol**:
1. Agent sends the tree markdown (with `[ ]` checkboxes) to the LLM or processes it itself.
2. LLM returns the same markdown with `[ ]` → `[x]` for selected options.
3. Evaluator validates: one branch per section, all children checked.

This is the pattern used by `§CMD_PROCESS_CHECKLISTS`.

---

## Conditional Constraints

- **`¶INV_TREE_JSONPATH`**: Condition expressions use bare names for current scope and `$` for root/cross-item access. JSONPath `@` only inside `[?...]` filters.
- **`¶INV_TREE_BACKWARD_COMPAT`**: Static trees (no `(if:)` or `(Recommended if:)`) produce identical behavior to the current system. Conditional syntax is purely additive.

See `docs/DECISION_TREE_PIPELINE.md` for implementation details (answer store shape, TypeScript types, interpreter pipeline stages).

---

## PROOF FOR §CMD_DECISION_TREE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "treeName": {
      "type": "string",
      "description": "Name of the decision tree (from the heading title)"
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
