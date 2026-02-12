# Loop Log Schemas (The Experiment Journal)
**Usage**: Capture the hypothesis-driven iteration process. Record hypotheses, experiments, critiques, decisions, and edits.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `engine log`.

## 🔬 Hypothesis
*   **Iteration**: `N`
*   **Observation**: "Bounding boxes consistently drift right by ~10px on page 2+"
*   **Theory**: "The coordinate system resets per page but the LLM treats it as continuous"
*   **Prediction**: "Adding 'coordinates are relative to page' should fix cases A, B, C"
*   **Mechanism**: "Anchoring rule — explicit coordinate system declaration"
*   **Status**: [Untested / Confirmed / Rejected / Partially Confirmed]

## 🧪 Experiment (RUN)
*   **Iteration**: `N`
*   **Cases Run**: 15
*   **Command**: "`runCommand` with {case} substituted"
*   **Output**: "Results at `outputPath`"
*   **Duration**: "~2 minutes"
*   **Errors**: [None / "3 cases failed to execute: ..."]

## 👁️ Critique (REVIEW)
*   **Iteration**: `N`
*   **Evaluation Method**: [evaluateCommand / Composer / Visual / Manual]
*   **Passing**: 14/15
*   **Failing**: 1/15
*   **Observations**:
    *   "Scope 'Kitchen' bounding box is too tall — includes the next scope header"
    *   "Line item 4 is missing entirely — OCR shows text is present"
    *   "Total value extracted as '$1,234' but overlay shows '$1,234.56'"
*   **Severity**: [Blocking / Degraded / Minor]

## 🎯 Composer Analysis (ANALYZE)
*   **Iteration**: `N`
*   **Root Cause**: "The prompt lacks explicit boundary anchoring for table regions"
*   **Option 1 (Recommended)**: "[Name] — [1-sentence summary]"
*   **Option 2**: "[Name] — [1-sentence summary]"
*   **Option 3**: "[Name] — [1-sentence summary]"
*   **Confidence**: [High / Medium / Low]

## 💡 Decision (DECIDE)
*   **Iteration**: `N`
*   **Chosen**: "Option 1: [Name]"
*   **Reason**: "Best balance of expected impact and regression risk"
*   **User Override?**: [No / "Yes — user chose Option 2 instead"]
*   **Skipped?**: [No / "Yes — user wants different hypothesis"]

## ✏️ Edit Applied (EDIT)
*   **Iteration**: `N`
*   **File**: `packages/estimate/src/schemas/prompts.ts`
*   **Lines**: 47-52
*   **Diff Summary**: "Added multi-line header guidance (+3 lines)"
*   **Mechanism**: "Anchoring rule for table boundary detection"

## 📊 Iteration Result
*   **Iteration**: `N`
*   **Cases Run**: 15
*   **Passing**: 14 (+2 from baseline)
*   **Failing**: 1 (-2 from baseline)
*   **New Failures**: 0
*   **Regressions**: 0
*   **Hypothesis Outcome**: [Confirmed / Rejected / Partially Confirmed]
*   **Verdict**: [Improved / Degraded / Neutral]

## 📈 Metrics Snapshot
*   **Iteration**: `N`
*   **Pass Rate**: `93.3%` (14/15 cases)
*   **Delta from Baseline**: `+13.3%` (was 80%)
*   **Delta from Previous**: `+6.7%` (was 86.7%)
*   **Error Categories**:
    *   Bounding box drift: 0 (was 2)
    *   Missing fields: 1 (unchanged)
    *   Wrong values: 0 (was 1)
*   **Artifact Changes**: +3 lines in `prompts.ts`

## 🏁 Iteration Complete
*   **Iteration**: `N`
*   **Duration**: "~8 minutes"
*   **Net Change**: "+2 passing, 0 regressions"
*   **Artifact Edits**: 1 file, +3 lines
*   **Hypothesis**: [Confirmed / Rejected / Partially Confirmed]
*   **Continue?**: [Yes — more to improve / No — converged / No — max iterations / No — plateau]

## ⚠️ Regression Detected
*   **Iteration**: `N`
*   **Metric**: "Passing cases dropped from 14 to 12"
*   **Likely Cause**: "The new guidance is too broad — now over-detecting headers"
*   **Action**: [Accept Tradeoff / Different Hypothesis Next / Stop and Analyze]

## 🛑 Calibration Failure
*   **Phase**: Calibration
*   **Error**: "runCommand failed: 'npx tsx scripts/run-extraction.ts' — module not found"
*   **Fix Attempted**: "Updated path to 'npx tsx apps/temporal/scripts/run-extraction.ts'"
*   **Status**: [Fixed / Needs User Input]

## 💡 Insight
*   **Discovery**: "The LLM performs better when given explicit coordinate bounds"
*   **Evidence**: "Adding 'x in range [0, 612], y in range [0, 792]' fixed 2 drift issues"
*   **Generalization**: "Always specify coordinate system bounds in extraction prompts"
*   **Add to Invariants?**: [Yes / No]

## 🅿️ Parking Lot
*   **Item**: "The OCR quality on scanned PDFs is poor"
*   **Relevance**: "Out of scope for iteration — needs preprocessing"
*   **Disposition**: [Defer / Separate Session / Ignore]

## 🚧 Block / Friction
*   **Obstacle**: "evaluateCommand returns exit code 1 on partial failures"
*   **Context**: "The evaluation script treats any non-100% result as failure"
*   **Attempt**: "Adjusting exit code handling to parse structured JSON output"
*   **Severity**: [Blocking / Annoyance]

## 😨 Stuck / Confusion
*   **Symptom**: "Cases pass locally but fail in the iteration loop"
*   **Mental State**: "Suspect environment difference or stale cache"
*   **Trace**: "runCommand → output → evaluateCommand → [mismatch]"
*   **Next Move**: "Compare local and loop outputs byte-for-byte"
