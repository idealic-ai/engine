# Testing Plan Template

## Overview
**Context**: Link to the feature or module being tested.
**Goal**: To verify correctness, robustness, and performance without brittle coupling to implementation details.

**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/TESTING_PLAN.md`.

---

## 1. Testing Strategy
*Define the approach. Avoid "Testing for Testing's Sake".*

*   **Scope**: [Unit | Integration | E2E]
*   **The "Real" Boundary**: What will we use *real* instances of? (e.g., "Use real `Clip` and `Track` objects, mock only `AudioContext`.")
*   **The Mock Boundary**: What *must* be mocked? (e.g., "Hardware I/O, Network calls.")

---

## 2. Risk Areas & "Sad Paths"
*Where is the system most likely to break?*

*   **Risk 1**: (e.g., "Buffer underflow during high CPU.")
*   **Risk 2**: (e.g., "State desync if `stop()` is called immediately after `start()`.")

---

## 3. Test Case Matrix
*The specific scenarios to implement.*

### Category: [Logic / State / Error / Perf]
*   [ ] **Case 1**: "Should [Behavior] when [Condition]."
    *   *Input*: `...`
    *   *Assertion*: `...`
    *   *Rationale*: Why is this valuable?
*   [ ] **Case 2**: ...

---

## 4. Refactoring Opportunities
*Does the code need to change to be testable?*

*   **Action**: (e.g., "Extract `TimeCalculator` from `StreamController` to test pure math.")
*   **Reason**: "Allows testing math without mocking the entire engine."

---

## 5. Verification Checklist
*   [ ] **Fast**: Do tests run in < 100ms?
*   [ ] **Deterministic**: No flaky async waits?
*   [ ] **Readable**: Can a junior dev understand the failure message?
