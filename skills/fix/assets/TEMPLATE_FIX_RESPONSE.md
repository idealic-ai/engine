# Fix Response: [TOPIC]
**Filename Convention**: `sessions/[YYYY_MM_DD]_[SESSION_TOPIC]/FIX_RESPONSE_[TOPIC].md`

## 1. Metadata
*   **Original Request**: `sessions/[YYYY_MM_DD]_[REQUESTING_SESSION]/FIX_REQUEST_[TOPIC].md`
*   **Requested By**: `[Requesting session name]`
*   **Responding Session**: `sessions/[YYYY_MM_DD]_[RESPONDING_SESSION]/`

## 2. Outcome
*   **Status**: [Fixed / Partial / Cannot Reproduce / Won't Fix]
*   **Summary**: [1-2 sentences: what was wrong and how it was fixed]

## 3. Root Cause
*   **Diagnosis**: [What caused the bug — the actual root cause, not symptoms]
*   **Evidence**: [File paths, code analysis, test results that confirmed the cause]

## 4. Changes Made
*   **[File 1]**: [What was changed and why]
*   **[File 2]**: [What was changed and why]

## 5. Verification
*   **Tests Added**: [List of new/modified test files]
*   **Tests Passing**: [All / N of M — details if not all]
*   **Manual Verification**: [Steps taken to verify the fix works]

## 6. Unresolved Items
*   [Item 1: related issue discovered but not fixed, tagged for follow-up]
*   *(None if fully resolved)*

## 7. Acceptance Criteria Status
*   [x] [Criterion from request — met]
*   [ ] [Criterion from request — not met, reason]
