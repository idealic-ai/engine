# Review Log Schemas (The Review Stream)
**Usage**: Capture the reviewer's analysis and findings as it reviews debriefs. Combine freely.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## Debrief Card
*   **Session**: `[Session Dir]`
*   **File**: `[Debrief Filename]`
*   **Goal**: "What the session was supposed to achieve."
*   **Outcome**: "What actually happened (from the debrief)."
*   **Files Touched**: `file1.ts`, `file2.ts`
*   **Risk Flags**: [None / List]
*   **Confidence**: [High / Medium / Low]

## Checklist Finding
*   **Debrief**: `[Session/File]`
*   **Check**: `[Which of the 8 standard checks]`
*   **Status**: [Pass / Fail / Not Applicable]
*   **Detail**: "What specifically was found or confirmed."
*   **Severity**: [Info / Warning / Critical]

## Cross-Session Conflict
*   **Type**: [File Overlap / Schema Conflict / Contradictory Decision / Dependency Order]
*   **Sessions**: `[Session A]` vs `[Session B]`
*   **Detail**: "Session A changed X while Session B also changed X with incompatible intent."
*   **Severity**: [Warning / Critical]
*   **Recommendation**: "Which session's change should take precedence, or how to reconcile."

## Verdict: Validated
*   **Debrief**: `[Session/File]`
*   **Summary**: "User confirmed all findings. No rework needed."
*   **Tag Transition**: `#needs-review` -> `#done-review`

## Verdict: Needs Rework
*   **Debrief**: `[Session/File]`
*   **Reason**: "User identified issues with X. The implementation of Y needs revisiting."
*   **Rework Notes**: "Appended to debrief file."
*   **Tag Transition**: `#needs-review` -> `#needs-rework`

## Leftover Spawned
*   **Title**: `[Leftover Description]`
*   **Command**: `/implement` or `/fix` or `/test`
*   **Source Debrief**: `[Session/File]`
*   **Prompt**: "The micro-dehydrated prompt for the leftover session."

## Decision
*   **Topic**: `[Concept/Finding]`
*   **Verdict**: "What was decided."
*   **Reasoning**: "Why."

## Concern
*   **Topic**: `[Area of Worry]`
*   **Detail**: "What specifically worries the reviewer."
*   **Status**: [Tracking / Escalated to User]

## Parking Lot
*   **Item**: `[Deferred Topic]`
*   **Disposition**: [Defer / Separate Session / Not Relevant]
*   **Reason**: "Why this is being parked."
