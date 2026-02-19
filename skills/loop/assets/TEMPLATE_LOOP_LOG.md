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

## 👁️ Critique (REVIEW + CLASSIFY)
*   **Iteration**: `N`
*   **Evaluation Method**: [evaluateCommand / Composer / Visual / Manual]
*   **Classification**:
    *   Real errors: N — [brief list]
    *   Evaluator false positives: N — [brief list]
    *   Evaluator miscalibration: N — [brief list]
    *   Infrastructure bugs: N — [brief list]
*   **Qualitative Observations**:
    *   "Scope 'Kitchen' bounding box is too tall — includes the next scope header" (real error)
    *   "Line item 4 is missing entirely — OCR shows text is present" (real error)
    *   "Total value extracted as '$1,234' but overlay shows '$1,234.56'" (evaluator miscalibration — rounding)
*   **Aggregate Context**: Passing: 14/15, Failing: 1/15
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
*   **Problem Targeted**: "The model doesn't separate recap totals from table content"
*   **Hypothesis Outcome**: [Confirmed / Rejected / Partially Confirmed]
*   **Classification Summary**: X real errors (was Y), Z evaluator issues (was W)
*   **Evaluator Changes**: [None / "Fixed N false positives by updating reviewer checklist"]
*   **Cases Run**: 15
*   **Aggregate Context**: Passing: 14/15 (+2), Failing: 1/15 (-2)
*   **Verdict**: [Problem solved / Partially solved / Not solved / Wrong hypothesis]

## 📈 Metrics Snapshot
*   **Iteration**: `N`
*   **Classification Breakdown**:
    *   Real errors: N (was M) — [trend direction]
    *   Evaluator false positives: N (was M) — [evaluator quality trend]
    *   Evaluator miscalibrations fixed this iteration: N
*   **Error Categories** (real errors only):
    *   Bounding box drift: 0 (was 2)
    *   Missing fields: 1 (unchanged)
    *   Wrong values: 0 (was 1)
*   **Aggregate Context**: Pass rate: `93.3%` (14/15), Delta: `+13.3%` from baseline
*   **Artifact Changes**: +3 lines in `prompts.ts`
*   **Evaluator Changes**: [None / "Updated N checks in reviewer checklist"]

## 🏁 Iteration Complete
*   **Iteration**: `N`
*   **Duration**: "~8 minutes"
*   **Net Change**: "+2 passing, 0 regressions"
*   **Artifact Edits**: 1 file, +3 lines
*   **Hypothesis**: [Confirmed / Rejected / Partially Confirmed]
*   **Continue?**: [Yes — more to improve / No — converged / No — max iterations / No — plateau]

## ⚠️ Score Change Detected
*   **Iteration**: `N`
*   **Observation**: "Aggregate score changed: 14 → 12 passing"
*   **Classification** (MANDATORY before action):
    *   Real regressions: N — [which cases and why]
    *   Evaluator miscalibration: N — [evaluator flagging correct behavior]
    *   Expected tradeoffs: N — [known side-effects of the change]
    *   Infrastructure noise: N — [stale cache, empty output, etc.]
*   **Verdict**: [Real regression / Evaluator needs fixing / Acceptable tradeoff / Noise]
*   **Action**: [Fix evaluator / Accept tradeoff / Different hypothesis / Investigate further]

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
