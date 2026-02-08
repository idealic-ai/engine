### §CMD_WALK_THROUGH_RESULTS
**Definition**: Walks the user through skill outputs or plan items with configurable granularity (None / Groups / Each item). Supports two modes: **results** (post-execution triage — delegate/defer/dismiss) and **plan** (pre-execution review — comment/question/flag).
**Concept**: "What kind of walk-through are we doing here?"
**Trigger**: Called by skill protocols either (a) during synthesis before `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` (results mode), or (b) after plan creation before phase transition to build (plan mode). Each skill provides a **Configuration Block** that customizes the behavior.

---

## Algorithm

### Step 1: Gate Question (Granularity Selection)

Present the walk-through offer via `AskUserQuestion` (multiSelect: false):

> "[gateQuestion from config]"
> - **"Each item"** — Walk through every item individually (finest granularity). Proceed to Step 2.
> - **"Groups"** — Walk through items grouped by section/theme. Proceed to Step 2.
> - **"None"** — Skip the walk-through entirely.

**Behavior by granularity**:
*   **Each item**: Extract all individual items (Step 2), present one-by-one (Step 3).
*   **Groups**: Extract items (Step 2), but present them grouped by their source section. One `AskUserQuestion` per group instead of per item. The user triages or comments on the group as a whole.
*   **None**: Return control to the calling skill. No walk-through performed.

### Step 2: Extract Items

**Source**: Read the sections listed in the configuration's `itemSources` from the debrief file just written. Each discrete finding, change, recommendation, idea, risk, or action item becomes a triage item.

**Extraction rules**:
*   Each item should have: a **title** (section heading or bullet label) and a **body** (the key sentences from the synthesis).
*   Group items by their source section to maintain context.
*   If an item is too granular (sub-bullets under a theme), group them into the parent item. The user triages themes, not micro-findings.
*   Aim for **5-15 items** total. If more, consolidate by theme. If fewer, include all.

### Step 3: Per-Item Walk-Through

**For each item**, present via `AskUserQuestion` (multiSelect: false):

1.  **Quote**: Display the finding as a blockquote — include the title and the 1-2 most important sentences from the synthesis. Keep it concise enough to decide on, not the full section.

    > **[Item N / Total]**: [Title]
    >
    > > [Quoted synthesis — 2-4 sentences max]

2.  **Present Options**: Build from the skill's `actionMenu` configuration. Rules:
    *   Always include **Defer** and **Dismiss** as the last two options.
    *   Pick the 1-2 most relevant **action options** from the config for this specific item.
    *   Maximum 4 options per `AskUserQuestion` (user can always type "Other").
    *   If the config has more than 2 action options, choose the 2 most relevant for this item based on its content.
    *   **Descriptive labels** (per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`): Option labels MUST include the `#needs-X` tag and describe the specific action for THIS item. Do NOT use generic labels like "Delegate to /implement" — instead write `"#needs-implementation: [what specifically]"`. Descriptions explain the benefit/purpose.
        *   *Example*: label=`"#needs-implementation: add rate limiting to /api/extract"`, description=`"Prevents abuse of the LLM extraction endpoint"`

3.  **On Selection**:
    *   **Action option (delegate)**: Apply the inline tag specified in the config to the relevant section in the debrief file via `§CMD_HANDLE_INLINE_TAG`. Log the decision to DETAILS.md via `§CMD_LOG_TO_DETAILS`.
    *   **Defer**: Apply `#needs-decision` inline. Log to DETAILS.md.
    *   **Dismiss**: No tag. Log the dismissal reason to DETAILS.md.
    *   **Other (user typed)**: Execute the user's custom instruction. Log to DETAILS.md.

### Step 4: Batch Shortcuts

**If the user says** "dismiss the rest", "delegate all remaining to /implement", "defer everything else", or any batch instruction:
*   Obey the batch instruction — do NOT force per-item triage for every remaining finding.
*   Apply the batch action to all remaining items.
*   Log the batch decision to DETAILS.md.
*   Proceed to Step 5.

### Step 5: Triage Summary

After all items are triaged (or user batched the rest):

1.  **Summary Table**: Output a triage summary in chat:
    ```
    | # | Item | Decision | Tag |
    |---|------|----------|-----|
    | 1 | [Title] | Delegate → /implement | #needs-implementation |
    | 2 | [Title] | Dismiss | — |
    | 3 | [Title] | Defer | #needs-decision |
    ```

2.  **Update Debrief Tags Line**: If any inline tags were applied, also add them to the debrief file's `**Tags**:` line via `§CMD_TAG_FILE` so they're discoverable by `/dispatch`.

3.  **Log**: Append a summary entry to the session log:
    ```
    Walk-through complete: N items triaged — X delegated, Y deferred, Z dismissed.
    ```

### Step 6: Return Control

Return control to the calling skill protocol. The skill continues with its next step (typically `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`).

---

## Plan Mode

**When**: Before execution begins — after a plan is written but before the phase transition to the build loop. The user reviews each plan item and provides feedback via Q&A.

**Difference from Results Mode**: Results mode triages completed work (delegate/defer/dismiss). Plan mode reviews upcoming work (comment/question/approve/flag). The output is recorded feedback, not triage decisions.

### Plan Mode Algorithm

**Step 1**: Same gate question as results mode (granularity selection: Each item / Groups / None).

**Step 2: Extract Plan Items**:
*   Read the plan file (specified in `debriefFile`).
*   Each plan step/phase from `itemSources` sections becomes a review item.
*   Preserve the step numbering and dependency information.

**Step 3: Per-Item Review (Each item granularity)**:

For each plan item, present via `AskUserQuestion` (multiSelect: true):

1.  **Quote**: Display the plan step as a blockquote:

    > **[Step N / Total]**: [Step title]
    >
    > > [Step intent + reasoning — 2-4 sentences]
    > > **Files**: [files listed] | **Depends**: [dependencies]

2.  **Present Questions**: Use the skill's `planQuestions` config (or defaults below):
    *   Default Q1: "Any concerns about this step's approach?"
    *   Default Q2: "Should the scope change (expand/narrow)?"
    *   Default Q3: "Dependencies or risks I'm missing?"

3.  **Options**:
    > - **"Looks good"** — No comments, move to next item
    > - **"I have feedback"** — User types comments; record to DETAILS.md via `§CMD_LOG_TO_DETAILS`
    > - **"Flag for revision"** — Mark step in plan with `[!]` prefix; record concern to DETAILS.md

4.  **On Selection**:
    *   **Looks good**: Move to next item. No logging needed.
    *   **I have feedback**: Record the user's response to DETAILS.md. The feedback is available to the builder during execution.
    *   **Flag for revision**: Mark the step in the plan file and log the concern. The skill should address flagged items before proceeding to build.

**Step 3 (Groups granularity)**:
*   Group plan steps by their phase/section.
*   Present one `AskUserQuestion` per phase with all steps quoted.
*   Same options as per-item but applied to the group.

**Step 4: Review Summary**:

After all items reviewed:
1.  **Summary**: Output in chat:
    ```
    Plan review: N items — X approved, Y with feedback, Z flagged for revision.
    ```
2.  **If any flagged**: Warn the calling skill that revision is needed before proceeding.
3.  **Log**: Append summary to session log.

**Step 5**: Return control to calling skill.

---

## Configuration Block

Each skill provides a configuration block that customizes the walk-through. The block is defined inline in the skill's SKILL.md where it calls `§CMD_WALK_THROUGH_RESULTS`.

**Schema**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"                  # "results" (post-execution triage) or "plan" (pre-execution review)
  gateQuestion: "[Question offering the walk-through]"
  debriefFile: "[Filename to extract items from]"
  itemSources:
    - "[Section heading 1 to extract items from]"
    - "[Section heading 2]"
  actionMenu:                      # For results mode: triage actions
    - label: "[Action label]"
      tag: "[#needs-xxx tag to apply]"
      when: "[When this option is relevant]"
  planQuestions:                    # For plan mode: per-item review questions
    - "[Question template 1]"
    - "[Question template 2]"
```

**Rules**:
*   `mode` defaults to `"results"` if omitted (backward-compatible). Use `"plan"` for pre-execution review.
*   `gateQuestion` should describe what's being offered: "Walk through [what]?" The three granularity options (Each item / Groups / None) are appended automatically.
*   `debriefFile` is the filename (not path) — the command resolves it relative to the session directory.
*   `itemSources` lists the section headings (H2 or H3) where items live.
*   `actionMenu` (results mode): defines 2-4 action options (excluding Defer and Dismiss, which are always auto-included).
*   `planQuestions` (plan mode): 2-3 question templates for per-item review. Use `[item]` placeholder for the item title. If omitted, defaults to generic plan review questions.
*   Each action has a `when` hint that helps the command select the most relevant options per item.

---

## Skill Configurations

### /analyze (Results Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "ANALYSIS.md is written. Walk through findings?"
  debriefFile: "ANALYSIS.md"
  itemSources:
    - "## 3. Key Insights"
    - "## 4. The \"Iceberg\" Risks"
    - "## 5. Strategic Recommendations"
  actionMenu:
    - label: "Delegate to /implement"
      tag: "#needs-implementation"
      when: "Finding is an actionable code/config change"
    - label: "Delegate to /research"
      tag: "#needs-research"
      when: "Finding needs deeper investigation"
    - label: "Delegate to /brainstorm"
      tag: "#needs-implementation"
      when: "Finding needs exploration of approaches before implementation"
    - label: "Delegate to /debug"
      tag: "#needs-implementation"
      when: "Finding reveals a bug or regression"
```

### /implement (Results Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Implementation complete. Walk through the changes?"
  debriefFile: "IMPLEMENTATION.md"
  itemSources:
    - "## 3. Plan vs. Reality (Deviation Analysis)"
    - "## 5. The \"Technical Debt\" Ledger"
    - "## 9. \"Btw, I also noticed...\" (Side Discoveries)"
  actionMenu:
    - label: "Add test coverage"
      tag: "#needs-implementation"
      when: "Change lacks adequate test coverage"
    - label: "Needs documentation"
      tag: "#needs-documentation"
      when: "Change affects user-facing behavior or API surface"
    - label: "Investigate further"
      tag: "#needs-research"
      when: "Change introduced uncertainty or has unknown side effects"
```

### /brainstorm (Results Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Brainstorm complete. Walk through ideas?"
  debriefFile: "BRAINSTORM.md"
  itemSources:
    - "## Convergence"
    - "## Sparks & Ideas"
    - "## Recommendations"
  actionMenu:
    - label: "Implement this idea"
      tag: "#needs-implementation"
      when: "Idea is ready to build"
    - label: "Research feasibility"
      tag: "#needs-research"
      when: "Idea needs validation or deeper investigation before committing"
    - label: "Prototype first"
      tag: "#needs-implementation"
      when: "Idea is promising but needs a quick proof of concept"
```

### /debug (Results Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Debug complete. Walk through findings?"
  debriefFile: "DEBUG.md"
  itemSources:
    - "## 4. Root Cause Analysis & Decisions"
    - "## 6. The \"Technical Debt\" Ledger"
    - "## 8. The \"Parking Lot\" (Unresolved)"
    - "## 9. \"Btw, I also noticed...\" (Side Discoveries)"
  actionMenu:
    - label: "Implement fix"
      tag: "#needs-implementation"
      when: "Issue has a known fix that wasn't applied in this session"
    - label: "Add regression test"
      tag: "#needs-implementation"
      when: "Fix was applied but lacks a regression test"
    - label: "Research deeper"
      tag: "#needs-research"
      when: "Root cause is unclear or issue may have broader implications"
```

### /implement (Plan Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Plan is ready. Walk through the steps before building?"
  debriefFile: "IMPLEMENTATION_PLAN.md"
  itemSources:
    - "## 6. Step-by-Step Implementation Strategy"
  planQuestions:
    - "Any concerns about this step's approach or complexity?"
    - "Should the scope change — expand, narrow, or split this step?"
    - "Dependencies or risks I'm missing?"
```

### /document (Plan Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Surgical plan ready. Walk through the operations before cutting?"
  debriefFile: "DOC_UPDATE_PLAN.md"
  itemSources:
    - "## 6. Step-by-Step Implementation Strategy"
  planQuestions:
    - "Is this the right scope for this operation?"
    - "Any docs I'm missing that should also be updated?"
    - "Concerns about this change breaking existing references?"
```

### /debug (Plan Mode)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Investigation plan ready. Walk through the hypotheses?"
  debriefFile: "DEBUG_PLAN.md"
  itemSources:
    - "## 6. Step-by-Step Implementation Strategy"
  planQuestions:
    - "Does this hypothesis seem likely given what you know?"
    - "Any other signals or logs I should check?"
    - "Should I prioritize this step or skip it?"
```

---

## Constraints

*   **Non-blocking**: If user selects "None" at the gate, the session continues normally. No walk-through performed.
*   **Item count**: Aim for 5-15 items. Consolidate if more; include all if fewer.
*   **Batch respect**: When the user gives a batch instruction, honor it immediately. Do not force per-item triage.
*   **Tag hygiene** (results mode): Inline tags follow `§CMD_HANDLE_INLINE_TAG` rules. File-level tags use `§CMD_TAG_FILE`.
*   **Logging**: Every triage decision (results) or feedback comment (plan) is logged to DETAILS.md. The summary is logged to the session log.
*   **AskUserQuestion limits**: Maximum 4 options per question. In results mode: always include Defer and Dismiss, pick 1-2 action options. In plan mode: always include "Looks good", "I have feedback", "Flag for revision".
*   **Idempotent**: If called multiple times (e.g., after continuation), re-read the source file and present unprocessed items only.
*   **Groups collapse**: If "Groups" granularity is selected but a section has only 1 item, present it as-is (don't force grouping of a singleton).
*   **Mode default**: If `mode` is omitted from config, default to `"results"` (backward-compatible).

---

## Integration Guide

### Results Mode Integration
Any skill that produces a debrief with actionable items can integrate results mode. Add it to the skill's synthesis phase after the debrief is written and before `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`.

**Where to add**: In the synthesis phase, after session summary and before deactivate.

**How to call**:
```markdown
## Xb. [Triage Phase Name]
*Convert [skill output] into action.*

Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
[paste skill-specific results mode configuration block]
```

### Plan Mode Integration
Any skill with a planning phase can integrate plan mode. Add it after the plan is written and approved, before the phase transition to execution.

**Where to add**: In the planning phase transition, as an optional step between plan approval and build/execution.

**How to call**:
```markdown
### Optional: Plan Walk-Through
Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
[paste skill-specific plan mode configuration block]

If any items are flagged for revision, return to the plan for edits before proceeding.
```

### Skills that should adopt this
*   `/analyze` — Results: Triage findings (ALREADY INTEGRATED as Phase 5b)
*   `/implement` — Results: Review changes. Plan: Review implementation steps.
*   `/document` — Results: Review doc updates. Plan: Review surgical plan.
*   `/brainstorm` — Results: Convert ideas into actionable work
*   `/debug` — Results: Track remaining issues. Plan: Review hypotheses.

**Adoption is optional**: The "None" granularity option lets users skip instantly. Adding the call adds one `AskUserQuestion` overhead for sessions where the user doesn't want a walk-through.
