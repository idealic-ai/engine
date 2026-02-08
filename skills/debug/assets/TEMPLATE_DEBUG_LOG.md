# Debug Log Schemas (The Detective's Journal)
**Usage**: Choose the best schema for your finding. Combine them freely. The goal is to capture the *investigation*, not just the *solution*.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## 🐞 Symptom (Observed Behavior)
*   **Test/Repro**: `[Test Name] or [Repro Steps]`
*   **Expected**: "Audio should silence on pause."
*   **Observed**: "Audio continues for 200ms after pause."
*   **Context**: "Happens only on Firefox, not Chrome."

## 🧪 Hypothesis (The Why)
*   **Suspect**: `[Component/Function]`
*   **Theory**: "I think the `AudioWorklet` message port is async, causing a race condition during state updates."
*   **Confidence**: [Low/Medium/High]

## 🛠️ Fix Attempt (The Action)
*   **Strategy**: "Adding a synchronization flag to the `pause` method."
*   **Files**: `src/lib/audio/Stream.ts`
*   **Diff**: "Changed `is_playing` to be atomic."

## ✅ Verification (Success)
*   **Test Run**: `npm test src/lib/audio/__tests__/Stream.test.ts`
*   **Outcome**: [Passed]
*   **Side Effects**: "Latency seems unchanged."

## ❌ Failure (Pivot)
*   **Test Run**: `[Test Command]`
*   **Error**: "Assertion failed: expected 0, got 1."
*   **Refutation**: "The hypothesis was wrong. The race condition is NOT in the Worklet."
*   **New Direction**: "Checking the Main Thread event loop now."

## 🔍 Discovery (Root Cause)
*   **Component**: `[Module]`
*   **Findings**: "The buffer size was hardcoded to 1024, but the sample rate required 2048."
*   **Reference**: "See `.claude/directives/INVARIANTS.md` Section 2."

## 🚧 Blocker (Stuck)
*   **Obstacle**: "Cannot reproduce the crash locally."
*   **Needs**: "Access to the crash dump from CI."
*   **Status**: [Parked]

## 🅿️ Parked (Investigation Needed)
*   **Test/Repro**: `[Test Name]`
*   **Status**: "Unknown cause / Missing Context / Complex Logic"
*   **Notes**: "Method `X` exists but behaves unexpectedly under load."
*   **Context Links**: `[Relevant Docs/Files for Phase 5.2]`
*   **Reason for deferring**: "Unclear path / Complicated setup / Hanging test"

## 📖 Documentation Insight/Critique
*   **Doc Path**: `[Path to MD file]`
*   **Insight**: "According to the spec, the `gain` should be normalized to [0, 1]."
*   **Complaint**: "The documentation for `PluginX` is outdated/missing/conflicting with the implementation."
*   **Action**: "Will update doc in Phase 6 or parked for separate session."

## ⚖️ Options (Decision Point)
*   **Problem**: `[Issue Description]`
*   **Options**:
    1.  **Fix Code**: Update implementation to match test.
    2.  **Fix Test**: Update test to match new API/behavior.
    3.  **Remove Test**: Test is redundant or legacy rot.
    4.  **Investigate Further**: Need more logs/context.
*   **Recommendation**: [Option #]
*   **User Choice**: [Choice]

## 💡 Decision (The Why)
*   **Topic**: `[What was decided]`
*   **Choice**: "Option A over Option B."
*   **Reasoning**: "Option A addresses the root cause. Option B is a workaround that masks the issue."
*   **Trade-off**: "Option A requires more work now but prevents recurrence."
*   **Reversibility**: [Easy / Hard / One-way]

## 💸 Tech Debt (The Shortcut)
*   **Item**: "Hardcoded timeout to 5 seconds."
*   **Why**: "Getting the dynamic timeout requires refactoring the middleware chain."
*   **Risk**: "Will mask connection pool leaks under different load patterns."
*   **Payoff Plan**: "Ticket #123: Refactor middleware connection handling."
*   **Commitment**: "Added `// TODO: TECH DEBT` comment in code."

## 🧹 Cleanup (Refactor)
*   **Target**: `[Old Test/Code]`
*   **Action**: "Deleted `legacy_test_01.ts` as it covered the old architecture."
*   **Justification**: "Superseded by `suite_v2.ts`."
