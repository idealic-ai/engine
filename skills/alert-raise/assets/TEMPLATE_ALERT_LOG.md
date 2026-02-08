# Alert Log Schemas (The Context Capture)
**Usage**: Capture the raw observations, diff analysis, and intent discoveries during an alert session.

## 🔍 Discovery: Code Change
*   **File**: `src/path/to/file.ts`
*   **Change**: "Modified the `Engine.start()` method to include a new `mode` parameter."
*   **Intent**: "To support 'Solo' vs 'Sync' modes as requested in the session."
*   **Impact**: "Breaks existing calls in `App.tsx` (fixed in this session)."

## 🔍 Discovery: Test Change
*   **Test**: `src/lib/core/__tests__/Engine.test.ts`
*   **Observation**: "Added integration tests for 'Solo' mode."
*   **Status**: "Passed, but uncovered a race condition in the cleanup logic."

## 🔍 Discovery: Intent / Requirement
*   **Source**: `IMPLEMENTATION_LOG.md` (Line 145)
*   **Detail**: "Agent mentioned that `¶INV_LOCKED_PHASE` was difficult to maintain with the new latency buffer."
*   **Inference**: "We might need to revisit the phase locking algorithm in the next session."

## 🔍 Discovery: API / Interface
*   **Interface**: `IPlaybackState`
*   **Change**: "Added `latencyMs: number` property."
*   **Reason**: "Needed for UI synchronization (Video System)."

## 🔍 Discovery: Tech Debt / Risk
*   **Observation**: "The `StreamWorker` is still using the old memory management for AAC stems."
*   **Risk**: "Memory leak if more than 4 decks are loaded."
*   **Note**: "Noted for future cleanup."

## 📝 Raw Analysis Note
*   **Topic**: [Topic Name]
*   **Content**: "Analysis of the `current_diff.txt` shows heavy churn in the `ParameterScheduler`. It seems the agent was trying to unify the two paths but stopped halfway."

## 💡 Compilation Insight
*   **Note**: "The most critical change this session was the `AudioWorklet` bypass logic. Everything else was supporting that."
