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

**Source**: Determine item sources using one of two methods:

1.  **Marker-based (preferred)**: If the configuration has a `templateFile`, read that template and find all `<!-- WALKTHROUGH {TYPE} -->` HTML comment markers (where `{TYPE}` matches the config's `mode` — e.g., `RESULTS` or `PLAN`). Each marker indicates that the **next heading** (the `##` heading immediately below the marker) is a walk-through source section. Extract items from those sections in the **debrief file** (not the template — the template only defines *which* sections to extract from).

2.  **Legacy (fallback)**: If the configuration has `itemSources` instead of `templateFile`, read the sections listed in `itemSources` directly from the debrief file. This is the original behavior, retained for backward compatibility.

**Marker format**: `<!-- WALKTHROUGH RESULTS -->` or `<!-- WALKTHROUGH PLAN -->` — an HTML comment on its own line, immediately above the target `##` heading in the template file. Multiple markers per template are supported (e.g., a template with both `<!-- WALKTHROUGH RESULTS -->` above 3 different sections).

**Extraction rules**:
*   Each item should have: a **title** (section heading or bullet label) and a **body** (the key sentences from the synthesis).
*   Group items by their source section to maintain context.
*   If an item is too granular (sub-bullets under a theme), group them into the parent item. The user triages themes, not micro-findings.
*   Aim for **5-15 items** total. If more, consolidate by theme. If fewer, include all.

### Step 3: Per-Item Walk-Through

**For each item**, present via `AskUserQuestion` (multiSelect: false):

1.  **Context Block (2 paragraphs — MANDATORY)**: Display 2 paragraphs that let the user triage the item **without reading the debrief file**:

    > **[Item N / Total]**: [Title]
    >
    > **What this is about**: [1 paragraph — Explain the topic/area this item covers: what part of the session's work does it relate to, what was the goal or context. The user should understand *what they're being asked about* from this paragraph alone.]
    >
    > **The finding**: [1 paragraph — The specific content from the debrief synthesis: what happened, what was discovered, what the state is. Concrete details, not vague summaries.]

    **Anti-pattern**: Do NOT present an item as just a title + 1 line of debrief text. The user is NOT reading the debrief file — these 2 paragraphs ARE their view of the content.

2.  **Present Options**: Build dynamically from the `§CMD_DISCOVER_DELEGATION_TARGETS` table (loaded at activate). Rules:
    *   Pick the **2 most relevant tags** from the delegation targets table for this specific item based on its content. Use `nextSkills` from `.state.json` to bias selection — prefer tags whose skills appear in `nextSkills`.
    *   Always include **Dismiss** as the last option.
    *   Maximum 3 options (2 dynamic tags + Dismiss) per `AskUserQuestion` (user can always type "Other").
    *   **Descriptive labels** (per `¶INV_QUESTION_GATE_OVER_TEXT_GATE`): Option labels MUST include the `#needs-X` tag and describe the specific action for THIS item. Do NOT use generic labels like "Delegate to /implement" — instead write `"#needs-implementation: [what specifically]"`. Descriptions explain the benefit/purpose.
        *   *Example*: label=`"#needs-implementation: add rate limiting to /api/extract"`, description=`"Prevents abuse of the LLM extraction endpoint"`

3.  **On Selection** (execute in order — do NOT skip sub-steps):
    *   **Tag option (delegate)**:
        1.  **Place inline tag**: Edit the debrief file to place the `#needs-X` tag inline next to the relevant item via `§CMD_HANDLE_INLINE_TAG`. This is the primary action — the Tags line is secondary.
        2.  **Output tag proof** (fill in ALL blanks):
            > **Tag proof [Item N]:** The tag `____` for item `____` was placed at `____` in `____`
        3.  **Log**: Record the decision to DETAILS.md via `§CMD_LOG_TO_DETAILS`.
    *   **Dismiss**:
        1.  No tag placed.
        2.  Output: **Tag proof [Item N]:** No tag — dismissed.
        3.  Log the dismissal reason to DETAILS.md.
    *   **Other (user typed)**: Execute the user's custom instruction. Output tag proof if a tag was placed. Log to DETAILS.md.

    [!!!] If ANY blank in the tag proof is empty, you skipped the inline tag placement. Go back and place the tag before continuing.

### Step 3b: Per-Group Walk-Through (Groups granularity)

**For each group** (one per source section from Step 2), present via `AskUserQuestion` (multiSelect: false):

1.  **Context Block (2 paragraphs — MANDATORY)**: Before the options, output 2 paragraphs in chat that let the user triage the group **without reading the debrief file**:

    > **Group [N / Total]**: [Section Title]
    >
    > **What this covers**: [1 paragraph — Explain what aspect of the session this group represents. What was the goal, what area of the codebase was involved, what kind of work was done. The user should understand the *topic* from this paragraph alone.]
    >
    > **Key findings**: [1 paragraph — Summarize the specific items in this group. For each item, give its title and a 1-sentence summary. If there are 3+ items, use an inline list (e.g., "(1) ..., (2) ..., (3) ..."). The user should be able to make a triage decision from this paragraph alone.]

    **Anti-pattern**: Do NOT present a group as just a title + 1 line of debrief text. The user is NOT reading the debrief file — these 2 paragraphs ARE their view of the content.

2.  **Present Options**: Same rules as Step 3 (pick 2 most relevant tags from delegation targets + Dismiss), applied to the group as a whole.

3.  **On Selection**: Same as Step 3 (including tag proof output), applied to all items in the group.

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
    | 3 | [Title] | Defer | #needs-brainstorm |
    ```

2.  **Inline Tag Verification**: Output a verification report listing every inline tag placed:
    ```
    **Inline Tag Verification:**
    Tagged: N items | Dismissed: N items
    1. `#needs-xxx`: [item title] ([location in debrief])
    2. `#needs-xxx`: [item title] ([location in debrief])
    ...
    ```
    [!!!] The count here MUST match the number of tag proofs output during Step 3. If it doesn't, go back and find the missing inline tags.

3.  **Update Debrief Tags Line**: If any inline tags were applied, also add them to the debrief file's `**Tags**:` line via `§CMD_TAG_FILE` so they're discoverable by `tag.sh find`.

4.  **Log**: Append a summary entry to the session log:
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

1.  **Context Block (2 paragraphs — MANDATORY)**: Display 2 paragraphs that let the user review the step **without reading the plan file**:

    > **[Step N / Total]**: [Step title]
    >
    > **What this step does**: [1 paragraph — Explain the goal, approach, and reasoning for this step. What area of the codebase does it target, and why is this step needed at this point in the sequence.]
    >
    > **Scope**: [1 paragraph — Specific files to be changed, dependencies on prior steps, verification method. Concrete details so the user can assess feasibility and risk.]

    **Anti-pattern**: Do NOT present a step as just a title + 1 line. The user is NOT reading the plan file — these 2 paragraphs ARE their view of the content.

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

Group plan steps by their phase/section. For each group, present via `AskUserQuestion` (multiSelect: true):

1.  **Context Block (2 paragraphs — MANDATORY)**: Before the options, output 2 paragraphs in chat:

    > **Group [N / Total]**: [Phase/Section Title]
    >
    > **What this covers**: [1 paragraph — Explain what this phase of the plan accomplishes, what area it targets, and why it's sequenced here. The user should understand the scope from this paragraph alone.]
    >
    > **Steps in this group**: [1 paragraph — List each step with its title and a 1-sentence summary of its intent. Include file and dependency info inline.]

    **Anti-pattern**: Do NOT present a group as just a title + 1 line. The user is NOT reading the plan file — these 2 paragraphs ARE their view of the content.

2.  **Options**: Same as per-item (Looks good / I have feedback / Flag for revision), applied to the group.

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
  templateFile: "[Path to template with <!-- WALKTHROUGH --> markers]"
  planQuestions:                    # For plan mode: per-item review questions
    - "[Question template 1]"
    - "[Question template 2]"
```

**Rules**:
*   `mode` defaults to `"results"` if omitted (backward-compatible). Use `"plan"` for pre-execution review.
*   `gateQuestion` should describe what's being offered: "Walk through [what]?" The three granularity options (Each item / Groups / None) are appended automatically.
*   `debriefFile` is the filename (not path) — the command resolves it relative to the session directory.
*   `templateFile` is the path to the template file containing `<!-- WALKTHROUGH RESULTS -->` or `<!-- WALKTHROUGH PLAN -->` markers. The command reads this template to discover which sections to extract from the debrief file. **Preferred over `itemSources`**.
*   `itemSources` *(legacy, deprecated)*: lists section headings directly. Retained for backward compatibility — if `templateFile` is present, `itemSources` is ignored. If only `itemSources` is present, the old heading-matching behavior applies.
*   **Triage actions (results mode)**: Dynamically derived from `§CMD_DISCOVER_DELEGATION_TARGETS` table. No `actionMenu` configuration needed — the agent picks the 2 most relevant tags per item, biased by `nextSkills`. Dismiss is always included.
*   `planQuestions` (plan mode): 2-3 question templates for per-item review. Use `[item]` placeholder for the item title. If omitted, defaults to generic plan review questions.

---

## Constraints

*   **Non-blocking**: If user selects "None" at the gate, the session continues normally. No walk-through performed.
*   **Item count**: Aim for 5-15 items. Consolidate if more; include all if fewer.
*   **Batch respect**: When the user gives a batch instruction, honor it immediately. Do not force per-item triage.
*   **Tag hygiene** (results mode): Inline tags follow `§CMD_HANDLE_INLINE_TAG` rules. File-level tags use `§CMD_TAG_FILE`.
*   **Logging**: Every triage decision (results) or feedback comment (plan) is logged to DETAILS.md. The summary is logged to the session log.
*   **AskUserQuestion limits**: Maximum 4 options per question. In results mode: pick 2 dynamic tags + Dismiss (3 options + Other). In plan mode: always include "Looks good", "I have feedback", "Flag for revision".
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
*   `/fix` — Results: Track remaining issues. Plan: Review hypotheses.

**Adoption is optional**: The "None" granularity option lets users skip instantly. Adding the call adds one `AskUserQuestion` overhead for sessions where the user doesn't want a walk-through.
