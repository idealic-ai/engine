# Loop Debriefing (The Iteration Report)
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/LOOP.md`

## 1. Executive Summary
*Status: [Improved / Converged / Inconclusive / Reverted]*

*   **Plan**: Link to `LOOP_PLAN.md`
*   **Workload**: `[workloadId from manifest]`
*   **Mode**: [Precision / Exploration / Convergence / Custom]
*   **Iterations**: `N` iterations over `[duration]`
*   **Baseline**: `X/Y` cases passing (`Z%`)
*   **Final**: `A/B` cases passing (`W%`)
*   **Net Change**: `+N` cases improved, `M` regressions

## 2. Manifest Configuration
*The workload configuration used for this iteration session.*

```json
{
  "workloadId": "...",
  "artifactPaths": ["..."],
  "casePaths": ["..."],
  ...
}
```

*   **Manifest Location**: `path/to/loop.manifest.json`

## 3. Hypothesis Audit Trail
*Every hypothesis tested, its prediction, and outcome. The scientific record.*

| Iter | Hypothesis | Prediction | Outcome | Mechanism |
|------|-----------|------------|---------|-----------|
| 1 | "Prompt lacks multi-line header guidance" | "Cases 3, 7, 12 improve" | Confirmed (+3) | Anchoring rule |
| 2 | "Coordinate system is implicit" | "Drift issues on page 2+ fix" | Partially confirmed (+1) | Explicit bounds |
| 3 | "OCR fallback hint missing" | "Case 15 improves" | Confirmed (+1) | Negative example |

## 4. Iteration History
*Condensed view of each iteration's quantitative outcome.*

| Iter | Passing | Change | Key Edit | Verdict |
|------|---------|--------|----------|---------|
| 0 (baseline) | 12/15 | — | — | — |
| 1 | 14/15 | +2 | Multi-line header guidance | Improved |
| 2 | 14/15 | 0 | Coordinate bounds | Neutral |
| 3 | 15/15 | +1 | OCR fallback hint | Converged |

## 5. Key Edits Made
*The artifact changes that drove improvement.*

### Edit 1: [Title]
*   **File**: `packages/estimate/src/schemas/prompts.ts`
*   **Lines**: 47-52
*   **Change**: Added multi-line header detection guidance
*   **Mechanism**: Anchoring rule — explicit example of multi-line pattern
*   **Impact**: Fixed cases 3, 7, 12 (scope header failures)
*   **Iteration**: 1
*   **Hypothesis**: Confirmed

### Edit 2: [Title]
*   **File**: ...
*   **Lines**: ...
*   **Change**: ...
*   **Mechanism**: ...
*   **Impact**: ...
*   **Iteration**: ...
*   **Hypothesis**: ...

## 6. Composer Analysis Summary
*Key insights from the Composer subagent across iterations.*

*   **Iteration 1**: "Root cause: lack of anchoring for table boundaries. Recommended explicit boundary rules."
*   **Iteration 2**: "Root cause: implicit coordinate system. Recommended explicit bounds declaration."
*   **Iteration 3**: "Root cause: no fallback guidance for degraded input. Recommended negative examples."

<!-- WALKTHROUGH RESULTS -->
## 7. Failing Cases (Remaining)
*What still doesn't work, and why.*

*   **Case**: `edge-case/scanned-poor-quality`
    *   **Symptom**: OCR produces garbled text
    *   **Root Cause**: Input quality, not artifact issue
    *   **Recommendation**: Preprocessing or exclusion from case set

## 8. Insights & Discoveries
*Generalizable learnings from this iteration session.*

*   **Insight 1**: "Explicit coordinate bounds improve spatial accuracy"
    *   *Evidence*: 2 drift issues fixed by adding range constraints
    *   *Generalize?*: Yes — add to extraction prompt template

*   **Insight 2**: ...

<!-- WALKTHROUGH RESULTS -->
## 9. Regressions & Tradeoffs
*Did we break anything? What tradeoffs were accepted?*

*   **Regression**: None
*   **Tradeoff**: "Looser scope header matching increases false positives on dense layouts"
    *   *Accepted Because*: "Dense layouts are rare in our corpus"

<!-- WALKTHROUGH RESULTS -->
## 10. Recommendations
*What to do next.*

*   [ ] **Update Invariants**: Add relevant rules to shared invariants
*   [ ] **Expand Cases**: Add more edge cases to the case set
*   [ ] **Schedule Re-run**: After next artifact change, re-run `/loop` to verify no regression

## 11. Agent's Expert Opinion (Subjective)

### 1. The Session Review
*   **Effectiveness**: "3 iterations to convergence — efficient"
*   **Difficulty**: "The multi-line header issue was subtle"
*   **Confidence**: "High — metrics are clear and reproducible"

### 2. The Result Audit
*   **Quality**: "15/15 passing is excellent, but the case set may be too easy"
*   **Robustness**: "Would like to see stress tests with 50+ cases"
*   **Completeness**: "Schema changes were not needed — prompt-only refinement"

### 3. Personal Commentary
*   **The Worry**: "The 'converged' state might be a local maximum — need adversarial cases"
*   **The Surprise**: "Coordinate bounds had outsized impact for a small change"
*   **The Advice**: "Run this periodically as a regression check, not just when things break"

---
*Agent Claude Opus 4.6 | Session: sessions/[YYYY_MM_DD]_[TOPIC]*
