# Refine Log Schemas (The Experiment Journal)
**Usage**: Capture the iterative refinement process. Record hypotheses, experiments, critiques, and results.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## 🎯 Iteration Start
*   **Iteration**: `N`
*   **Baseline Metrics**: (e.g., "12/15 fixtures passing, 3 bounding box errors")
*   **Focus**: "Targeting the scope header detection failures"
*   **Hypothesis**: "The prompt lacks guidance on multi-line headers"

## 🧪 Experiment
*   **Change**: "Added example of multi-line scope header to DATA_MASTER_PROMPT"
*   **File**: `packages/estimate/src/schemas/prompts.ts:47`
*   **Rationale**: "The LLM has no examples of headers spanning two lines"
*   **Expected Impact**: "Fixtures 3, 7, 12 should now detect headers correctly"

## 🔬 Hypothesis
*   **Observation**: "Bounding boxes consistently drift right by ~10px on page 2+"
*   **Theory**: "The coordinate system resets per page but the LLM treats it as continuous"
*   **Test**: "Check if adding 'coordinates are relative to page' improves accuracy"
*   **Status**: [Untested / Confirmed / Rejected]

## 👁️ Critique (Visual Analysis)
*   **Fixture**: `multi-room-v2/page-3`
*   **Overlay**: `tmp/refine-output/multi-room-v2-page-3.overlay.png`
*   **Observations**:
    *   "Scope 'Kitchen' bounding box is too tall — includes the next scope header"
    *   "Line item 4 is missing entirely — OCR shows text is present"
    *   "Total value extracted as '$1,234' but overlay shows '$1,234.56'"
*   **Severity**: [Blocking / Degraded / Minor]

## 📊 Result (Iteration Outcome)
*   **Iteration**: `N`
*   **Cases Run**: 15
*   **Passing**: 14 (+2 from baseline)
*   **Failing**: 1 (-2 from baseline)
*   **New Failures**: 0
*   **Regressions**: 0
*   **Verdict**: [Improved / Degraded / Neutral]

## 📈 Metrics (Quantitative Snapshot)
*   **Iteration**: `N`
*   **Pass Rate**: `93.3%` (14/15 cases)
*   **Delta from Baseline**: `+13.3%` (was 80%)
*   **Delta from Previous**: `+6.7%` (was 86.7%)
*   **Error Categories**:
    *   Bounding box drift: 0 (was 2)
    *   Missing fields: 1 (unchanged)
    *   Wrong values: 0 (was 1)
*   **Prompt Changes**: +3 lines in `prompts.ts`
*   **Schema Changes**: 0

## 🔧 Suggestion (Proposed Edit)
*   **Target**: `packages/estimate/src/schemas/prompts.ts`
*   **Line**: 47-52
*   **Current**:
    ```
    The scope header contains the room name.
    ```
*   **Proposed**:
    ```
    The scope header contains the room name. Headers may span multiple lines
    if the room name is long. Treat consecutive lines with the same indentation
    as a single header.
    ```
*   **Confidence**: [High / Medium / Low]
*   **Basis**: "Visual critique showed 3 fixtures with multi-line headers failing"

## ✏️ Edit Applied
*   **File**: `packages/estimate/src/schemas/prompts.ts`
*   **Lines**: 47-52
*   **Diff Summary**: "Added multi-line header guidance (+3 lines)"
*   **Mode**: [Auto / Suggested-and-Approved]

## ⚠️ Regression Detected
*   **Iteration**: `N`
*   **Metric**: "Passing fixtures dropped from 14 to 12"
*   **Likely Cause**: "The new guidance is too broad — now over-detecting headers"
*   **Action**: [Revert / Refine Further / Accept Tradeoff]

## 🛑 Validation Failure
*   **Phase**: Manifest Validation
*   **Error**: "runCommand failed: 'npx tsx scripts/run-extraction.ts' — module not found"
*   **Fix Attempted**: "Updated path to 'npx tsx apps/temporal/scripts/run-extraction.ts'"
*   **Status**: [Fixed / Needs User Input]

## 🏁 Iteration Complete
*   **Iteration**: `N`
*   **Duration**: "~8 minutes"
*   **Net Change**: "+2 passing fixtures, 0 regressions"
*   **Prompt Edits**: 1 file, +3 lines
*   **Schema Edits**: 0
*   **Continue?**: [Yes — more to improve / No — converged / No — max iterations]

## 💡 Insight
*   **Discovery**: "The LLM performs better when given explicit coordinate bounds"
*   **Evidence**: "Adding 'x in range [0, 612], y in range [0, 792]' fixed 2 drift issues"
*   **Generalization**: "Always specify coordinate system bounds in extraction prompts"
*   **Add to Invariants?**: [Yes / No]

## 🅿️ Parking Lot
*   **Item**: "The OCR quality on scanned PDFs is poor"
*   **Relevance**: "Out of scope for prompt refinement — needs preprocessing"
*   **Disposition**: [Defer / Separate Session / Ignore]
