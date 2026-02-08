# Implementation Plan Template

## Overview
**Context**: Link to `BRAINSTORM.md` or `ANALYSIS.md`.
**Required Documents**:
*   `~/.claude/standards/INVARIANTS.md` (Shared) and `.claude/standards/INVARIANTS.md` (Project-specific, if exists)
*   `docs/architecture/[RELEVANT_DOC].md`
*   `docs/concepts/[RELEVANT_DOC].md`

**Goal**: Define the exact steps to implement the feature/fix while adhering to strict system standards.

**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/IMPLEMENTATION_PLAN.md`.

---

## 1. Standards & Invariants Check
*Mandatory verification against the "Laws of Physics".*

*   **Ref**: `~/.claude/standards/INVARIANTS.md` (shared) + `.claude/standards/INVARIANTS.md` (project)

### Relevant Invariants
*   **§INV_[NAME]**: How does this plan respect it?
    *   *Check*: (e.g. "We are adding state to `Clip`, which violates immutability? NO, we are creating a new `Clip` instance.")
*   **§INV_[NAME]**: ...

---

## 2. Interface & Data Design
*Define "The Truth" before logic. Show the Types/Interfaces first.*

### Changed/New Interfaces
```typescript
// Proposed interface changes
interface NewState {
  // ...
}
```

### Data Flow
*   **Input**: `...`
*   **Transformation**: `...`
*   **Output**: `...`

---

## 3. Potential Pitfalls & Breaking Changes
*Anticipate where things might go wrong. Be paranoid.*

*   **Breaking Changes**: Does this change public API? Will it break existing Compositions?
*   **Thread Safety**: (e.g. "Is this accessed by both Main Thread and Audio Worker? If so, how do we handle locking/messaging?")
*   **Performance**: (e.g. "Does this introduce allocations in the hot loop?")
*   **State Sync**: (e.g. "What happens if the UI updates while audio is processing?")
*   **Edge Cases**: (e.g. "Empty arrays, NaN values, Disconnected nodes")
*   **The Future Maintainer**: (e.g. "The `reduce` logic is dense. If I don't comment it heavily, the next person will delete it.")

---

## 4. Test Plan (TDD)
*Define the failing tests that will drive the implementation.*

*   **Test File**: `src/lib/audio/__tests__/[Topic].test.ts`
*   **Case 1**: "Should handle X..."
    *   *Setup*: ...
    *   *Assertion*: ...
*   **Case 2**: "Should throw on invalid Y..."

---

## 5. Guides & Hints
*Help your future self or the agent implementation.*

*   **Reference Implementation**: (e.g. "See `StreamController.ts` for similar logic regarding buffer handling.")
*   **Helper Functions**: (e.g. "Use `Time.beatsToSeconds()` instead of manual calculation.")
*   **Libraries**: (e.g. "Use `zod` for validation if needed.")

---

## 6. Step-by-Step Implementation Strategy
*Break down the work into atomic, verifiable steps. Max 50 lines of code per step.*
*Each step MUST declare `Depends` and `Files` for parallel execution analysis.*

### Phase 1: Skeleton & Types
*   [ ] **Step 1**: [Action]
    *   **Intent**: Why are we doing this?
    *   **Reasoning**: Why this way?
    *   **Depends**: None
    *   **Files**: `src/path/to/file.ts`
    *   **Verification**: How do we know it works?
*   [ ] **Step 2**: Create the Test file with a failing test (red).
    *   **Intent**: TDD setup.
    *   **Reasoning**: Ensure we have a baseline.
    *   **Depends**: Step 1
    *   **Files**: `src/path/to/file.test.ts`
    *   **Verification**: Test fails as expected.

### Phase 2: Core Logic
*   [ ] **Step 3**: Implement minimal logic to pass Test 1 (green).
    *   **Intent**:
    *   **Reasoning**:
    *   **Depends**: Step 2
    *   **Files**: `src/path/to/file.ts`
    *   **Verification**:
*   [ ] **Step 4**: Refactor to clean up (refactor).
    *   **Depends**: Step 3
    *   **Files**: `src/path/to/file.ts`
*   [ ] **Step 5**: Add Test 2 (edge case) and implement.
    *   **Depends**: Step 3
    *   **Files**: `src/path/to/file.ts`, `src/path/to/file.test.ts`

### Phase 3: Integration & Wiring
*   [ ] **Step 6**: Wire into `StreamController` / `Engine`.
    *   **Depends**: Step 4, Step 5
    *   **Files**: `src/path/to/engine.ts`
*   [ ] **Step 7**: Verify full flow.
    *   **Depends**: Step 6
    *   **Files**: (none — verification only)

---

## 8. Parallel Execution Analysis
*Auto-derived from step dependencies and file sets. Presented to user before handoff.*

### Chunk Derivation
*Compute from the dependency graph. Steps with no shared dependencies and disjoint file sets form parallel chunks.*

### Chunk [A]: [Description]
**Steps**: [1, 3, 5]
**Files**: `src/parser.ts`, `src/parser.test.ts`
**Dependencies**: None (root chunk)

### Chunk [B]: [Description]
**Steps**: [2, 4, 6]
**Files**: `src/renderer.ts`, `src/renderer.test.ts`
**Dependencies**: None (root chunk)

### Chunk [C]: [Description] — SEQUENTIAL
**Steps**: [7, 8]
**Files**: `src/index.ts`
**Dependencies**: Chunk A, Chunk B (runs after both complete)

### Non-Intersection Proof
> Chunk A files: `{src/parser.ts, src/parser.test.ts}`
> Chunk B files: `{src/renderer.ts, src/renderer.test.ts}`
> Intersection: `∅` (empty — no conflicts)
> Chunk C depends on A+B and runs sequentially after.

**Recommended agents**: [N] (for [N] independent chunks in parallel)

---

## 7. Rollback & Contingency
*   **Risk**: (e.g. "Performance regression in main loop")
*   **Mitigation**: (e.g. "Feature flag or separate worker")
*   **Rollback**: "Revert commit X."

---

## 9. Manual Verification
*How can a human verify this without running tests?*

*   **Action**: (e.g., "Load the app, drag a clip, and check the console.")
*   **Expected Result**: (e.g., "Console logs 'Clip Dropped', and audio plays.")

---

## 10. Final Verification Checklist
*   [ ] **Linter**: `npm run lint` pass?
*   [ ] **Tests**: `npm test` pass?
*   [ ] **Invariants**: Checked?
*   [ ] **JSDoc**: Added?
