# Refine Debriefing (The Iteration Report)
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/REFINE.md`

## 1. Executive Summary
*Status: [Improved / Converged / Inconclusive / Reverted]*

*   **Plan**: Link to `REFINE_PLAN.md`
*   **Workload**: `[workloadId from manifest]`
*   **Iterations**: `N` iterations over `[duration]`
*   **Baseline**: `X/Y` fixtures passing (`Z%`)
*   **Final**: `A/B` fixtures passing (`W%`)
*   **Net Change**: `+N` fixtures improved, `M` regressions

## 2. Manifest Configuration
*The workload configuration used for this refinement session.*

```json
{
  "workloadId": "...",
  "promptPaths": ["..."],
  "fixturePaths": ["..."],
  ...
}
```

*   **Manifest Location**: `path/to/refine.manifest.json`

## 3. Iteration History
*Condensed view of each iteration's outcome.*

| Iter | Passing | Change | Key Edit | Verdict |
|------|---------|--------|----------|---------|
| 0 (baseline) | 12/15 | — | — | — |
| 1 | 14/15 | +2 | Multi-line header guidance | Improved |
| 2 | 14/15 | 0 | Coordinate bounds | Neutral |
| 3 | 15/15 | +1 | OCR fallback hint | Converged |

## 4. Key Edits Made
*The prompt/schema changes that drove improvement.*

### Edit 1: [Title]
*   **File**: `packages/estimate/src/schemas/prompts.ts`
*   **Lines**: 47-52
*   **Change**: Added multi-line header detection guidance
*   **Impact**: Fixed fixtures 3, 7, 12 (scope header failures)
*   **Iteration**: 1

### Edit 2: [Title]
*   **File**: ...
*   **Lines**: ...
*   **Change**: ...
*   **Impact**: ...
*   **Iteration**: ...

## 5. Failing Fixtures (Remaining)
*What still doesn't work, and why.*

*   **Fixture**: `edge-case/scanned-poor-quality`
    *   **Symptom**: OCR produces garbled text
    *   **Root Cause**: Input quality, not prompt issue
    *   **Recommendation**: Preprocessing or exclusion from test set

## 6. Insights & Discoveries
*Generalizable learnings from this refinement session.*

*   **Insight 1**: "Explicit coordinate bounds improve spatial accuracy"
    *   *Evidence*: 2 drift issues fixed by adding range constraints
    *   *Generalize?*: Yes — add to extraction prompt template

*   **Insight 2**: ...

## 7. Regressions & Tradeoffs
*Did we break anything? What tradeoffs were accepted?*

*   **Regression**: None
*   **Tradeoff**: "Looser scope header matching increases false positives on dense layouts"
    *   *Accepted Because*: "Dense layouts are rare in our corpus"

## 8. Recommendations
*What to do next.*

*   [ ] **Update Invariants**: Add `§INV_COORDINATE_BOUNDS` to shared invariants
*   [ ] **Expand Fixtures**: Add 3 more edge cases (continuation pages, work orders)
*   [ ] **Schedule Re-run**: After next schema change, re-run `/refine` to verify no regression

## 9. Agent's Expert Opinion (Subjective)

### 1. The Session Review
*   **Effectiveness**: "3 iterations to convergence — efficient"
*   **Difficulty**: "The multi-line header issue was subtle"
*   **Confidence**: "High — metrics are clear and reproducible"

### 2. The Result Audit
*   **Quality**: "15/15 passing is excellent, but the test set may be too easy"
*   **Robustness**: "Would like to see stress tests with 50+ fixtures"
*   **Completeness**: "Schema changes were not needed — prompt-only refinement"

### 3. Personal Commentary
*   **The Worry**: "The 'converged' state might be local maximum — need adversarial fixtures"
*   **The Surprise**: "Coordinate bounds had outsized impact for a small change"
*   **The Advice**: "Run this monthly as a regression check, not just when things break"

---
*Agent Claude Opus 4.5 | Session: sessions/[YYYY_MM_DD]_[TOPIC]*
