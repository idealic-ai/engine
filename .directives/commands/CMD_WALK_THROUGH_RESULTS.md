### ¶CMD_WALK_THROUGH_RESULTS
**Definition**: Walks the user through skill outputs or plan items with configurable granularity (None / Groups / Each item). Supports two modes: **results** (post-execution triage — delegate/defer/dismiss) and **plan** (pre-execution review — comment/question/flag).

---

## Mode Deltas

The algorithm below is parameterized. These mode-specific values fill the placeholders:

*   **results**
  *   **Context labels**: "What this is about" + "The finding"
  *   **Decision command**: §CMD_TAG_TRIAGE (dynamic tag options from `SRC_DELEGATION_TARGETS`)
  *   **On result**: tag → `§CMD_HANDLE_INLINE_TAG` + tag proof output; dismiss → no tag; custom → execute instruction
  *   **Summary fields**: Tagged: N, Dismissed: N — includes inline tag verification report
  *   **Plan Review tree**: Not used

*   **plan**
  *   **Context labels**: "What this step does" + "Scope"
  *   **Decision command**: §CMD_DECISION_TREE with `Plan Review` tree (OK/INF/RWK/CHG/REM)
  *   **On result**: OK → next; INF → detail + re-present; RWK → mark `[!]` + log; CHG → flag rework + log; REM → mark removal + log
  *   **Summary fields**: Approved: N, Feedback: N, Flagged: N
  *   **Plan Review tree**: (see below)

**Plan Review Tree** (plan mode only):
```
## Decision: Plan Review
- [OK] Looks good
  No changes needed to this step
- [INF] More info needed
  I have questions about this step's approach
- [OTH] Other
  - [RWK] Rework this step
    Rewrite with a different approach
  - [CHG] Change approach
    Fundamental direction change needed
  - [REM] Remove from plan
    This step is not needed
```

---

## Algorithm

### Step 1: Gate Question (Granularity Selection)

Invoke §CMD_DECISION_TREE with `§ASK_WALKTHROUGH_GRANULARITY`. Use the `gateQuestion` from config as preamble context.

**Behavior by granularity**:
*   **`EAC`** (Each item): Extract all items (Step 2), present one-by-one (Step 3).
*   **`GRP`** (Groups): Extract items (Step 2), chunk into fixed groups of 4. Present each item's context block in one message, then one `AskUserQuestion` with up to 4 questions. Last group may have 1-3 items.
*   **`SMT`** (Smart): Auto-determine: ≤4 items → Each, 5-12 → Groups, 13+ → Groups with batch shortcuts.
*   **`OTH/NON`** (None): Return control. No walk-through performed.
*   **`OTH/TOP`** (Top N only): Walk through the N most important items, skip the rest.

### Step 2: Extract Items

**Source** (two methods):
1.  **Marker-based (preferred)**: If config has `templateFile`, find `<!-- WALKTHROUGH {TYPE} -->` HTML comment markers (where `{TYPE}` matches config `mode`). Each marker indicates the next `##` heading is a walk-through source section. Extract items from those sections in the **debrief file** (not the template).
2.  **Legacy (fallback)**: If config has `itemSources` instead, read those sections from the debrief file directly.

**Extraction rules**: Each item needs a **title**, **body**, and **item ID**. Item IDs follow the convention in SIGILS.md § Item IDs. Format: `{phase}.{sub-phase}.{section}/{item}`. Example: Synthesis(4), Debrief(4.2), Section 3, Item 2 = `4.2.3/2`. IDs are assigned at creation time in the debrief artifact and carried through to walk-through presentation. Group sub-bullets into parent items. Aim for **5-15 items**. Consolidate if more; include all if fewer.

### Step 3: Per-Item Walk-Through

**For each item** (or group of up to 4). Use the item's ID (from Step 2) as the `header` field in `AskUserQuestion`:

1.  **Context Block** (`§FMT_CONTEXT_BLOCK` — MANDATORY): Use mode context labels (see Mode Deltas). Reference the item by its ID (e.g., `> **4.2.3/2**: [Title]`). For groups, output ALL items' context blocks in one chat message, then one `AskUserQuestion` with up to 4 questions.

2.  **Collect Decision**: Call the mode's **decision command** (see Mode Deltas). Results mode: §CMD_TAG_TRIAGE. Plan mode: §CMD_DECISION_TREE with Plan Review tree.

3.  **On Result**: Execute mode-specific result handling (see Mode Deltas). For results mode, output tag proof per item:
    > **Tag proof [{itemId}]:** The tag `____` for item `____` was placed at `____` in `____`

    [!!!] If ANY blank in the tag proof is empty, you skipped the inline tag placement. Go back and place the tag.

### Step 4: Batch Shortcuts

If the user gives a batch instruction ("dismiss the rest", "delegate all remaining to /implement"), obey immediately. Apply batch action to all remaining items. Log to DETAILS.md. Proceed to Step 5.

### Step 5: Summary

After all items triaged/reviewed:

1.  **Summary**: Output mode-specific summary in chat (tagged/dismissed counts for results; approved/feedback/flagged counts for plan).
2.  **Inline Tag Verification** (results mode only): List every inline tag placed with file paths per `¶INV_TERMINAL_FILE_LINKS`. Count MUST match tag proofs from Step 3.
3.  **Update Tags Line** (results mode): Add inline tags to debrief's `**Tags**:` line via `§CMD_TAG_FILE`.
4.  **If flagged** (plan mode): Warn calling skill that revision is needed.
5.  **Log**: Append summary entry to session log.

### Step 6: Return Control

Return control to the calling skill protocol.

---

## Configuration Block

Each skill provides inline configuration in its SKILL.md:

```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"                  # "results" or "plan" (default: "results")
  gateQuestion: "[Question offering the walk-through]"
  debriefFile: "[Filename to extract items from]"
  templateFile: "[Path to template with <!-- WALKTHROUGH --> markers]"
  planQuestions:                    # Plan mode only: per-item review questions
    - "[Question template 1]"
```

**Rules**:
*   `gateQuestion` describes what's being offered. Granularity options appended automatically.
*   `debriefFile` is filename-only — resolved relative to session directory.
*   `templateFile` preferred over `itemSources` (legacy, deprecated).
*   Results mode triage actions derived dynamically from `SRC_DELEGATION_TARGETS` — no config needed.

---

## Constraints

*   **Tags are passive**: Tags placed during walk-through do NOT trigger `/delegation-create` offers. They are protocol-placed.
*   **Non-blocking**: "None" at gate → no walk-through, session continues.
*   **Batch respect**: Honor batch instructions immediately.
*   **Group size**: Fixed at 4 (matching `AskUserQuestion` max). Last group gets remainder.
*   **Decision commands**: Results → §CMD_TAG_TRIAGE. Plan → §CMD_DECISION_TREE.
*   **Idempotent**: If called multiple times, present unprocessed items only.
*   **Logging**: Every decision logged to DETAILS.md. Summary to session log.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and context blocks; bare tags only on `**Tags**:` lines or intentional inline placement.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in the inline tag verification and summary MUST be clickable URLs.

---

### ¶ASK_WALKTHROUGH_GRANULARITY
Trigger: before any walk-through of results or plan items (except: when collapsible-pass logic auto-skips the walk-through)
Extras: A: Preview item count before deciding | B: Walk through only flagged items | C: Export items to clipboard

## Decision: Walk-Through Granularity
- [EAC] Each item
  Walk through every item individually — finest control
- [GRP] Groups
  Walk through items grouped in batches of 4 — balanced
- [SMT] Smart
  Auto-determine: ≤4 items → Each, 5-12 → Groups, 13+ → Groups with batch shortcuts
- [OTH] Other
  - [NON] None
    Skip the walk-through entirely
  - [TOP] Top N only
    Walk through the N most important items, skip the rest

---

## PROOF FOR §CMD_WALK_THROUGH_RESULTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "resultsPresented": {
      "type": "string",
      "description": "Summary of items walked through with the user"
    },
    "userApproved": {
      "type": "string",
      "description": "User disposition after walk-through"
    }
  },
  "required": ["resultsPresented", "userApproved"],
  "additionalProperties": false
}
```
