# Fix Plan

## Overview
**Context**: Link to `FIX_LOG.md` or prior session.
**Fix Mode**: [General / TDD / Hotfix / Custom]
**Required Documents**:
*   `~/.claude/.directives/INVARIANTS.md` (Shared) and `.claude/.directives/INVARIANTS.md` (Project-specific, if exists)
*   `docs/architecture/[RELEVANT_DOC].md`

**Goal**: To systematically diagnose and resolve the issue by prioritizing high-confidence fixes, grouping related failures, and confirming options with the user before complex changes.

**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/FIX_PLAN.md`.

---

## 1. Problem Statement
*   **Symptom**: [What is observed — error messages, unexpected behavior, performance degradation, production incidents]
*   **Impact**: [Who/what is affected — users, tests, CI, production]
*   **Urgency**: [Critical / High / Medium / Low]
*   **Reproduction**: [How to reproduce — test command, user flow, load conditions]

---

## 2. Triage Summary
*   **Total Issues**: [N]
*   **Tier 1 (High-Confidence)**: [Count] — Clear root cause, straightforward fix
*   **Tier 2 (Investigation Needed)**: [Count] — Unclear root cause, requires deeper analysis
*   **Blockers**: [List critical paths that must be resolved first]

---

## 3. Standards & Invariants Check
*Mandatory verification — are any invariants relevant to the diagnosis?*

*   **Ref**: `~/.claude/.directives/INVARIANTS.md` (shared) + `.claude/.directives/INVARIANTS.md` (project)

### Relevant Invariants
*   **§INV_[NAME]**: How does this invariant relate to the issue?
    *   *Check*: (e.g., "The test assumes immutability but the implementation mutates state — possible violation of §INV_ISOLATED_STATE.")

---

## 4. Hypotheses (Ranked)
*List candidate root causes ordered by likelihood.*

*   **Hypothesis 1**: [Most likely cause]
    *   *Evidence For*: ...
    *   *Evidence Against*: ...
    *   *Confidence*: [High / Medium / Low]
    *   *Validation Strategy*: How to confirm or refute this.
*   **Hypothesis 2**: [Second most likely]
    *   *Evidence For*: ...
    *   *Evidence Against*: ...
    *   *Confidence*: ...
    *   *Validation Strategy*: ...

---

<!-- WALKTHROUGH PLAN -->
## 5. Attack Plan (Prioritized Steps)
*Break down the investigation and repair into atomic, verifiable steps.*
*Each step MUST declare `Depends` and `Files` for parallel execution analysis.*

### Phase 1: Quick Wins (Tier 1)
*Clear high-confidence issues first to reduce noise.*

*   [ ] **Step 1**: [Action — e.g., "Fix missing mock for AuthService"]
    *   **Intent**: Why are we doing this?
    *   **Hypothesis**: Which hypothesis does this address?
    *   **Depends**: None
    *   **Files**: `src/path/to/file.ts`, `src/path/to/test.ts`
    *   **Verification**: How do we know it worked?
*   [ ] **Step 2**: [Action]
    *   **Intent**: ...
    *   **Hypothesis**: ...
    *   **Depends**: None
    *   **Files**: ...
    *   **Verification**: ...

### Phase 2: Investigation (Tier 2)
*Deeper analysis for unclear root causes.*

*   [ ] **Step 3**: [Investigation action — e.g., "Profile request lifecycle to find bottleneck"]
    *   **Intent**: ...
    *   **Hypothesis**: ...
    *   **Depends**: Step 1
    *   **Files**: ...
    *   **Verification**: ...
*   [ ] **Step 4**: [Investigation action]
    *   **Depends**: Step 1
    *   **Files**: ...

### Phase 3: User Confirmation
*Present findings and options for each investigated issue.*

*   [ ] **Draft Options Report**: List choices (Fix Code / Fix Test / Remove Test / Workaround) for each investigation result.
*   [ ] **Wait for User Choice**: HARD STOP.
    *   **Depends**: Steps 3, 4

### Phase 4: Final Execution
*Apply the chosen fixes and verify.*

*   [ ] **Step 5**: Apply fixes per user choices.
    *   **Depends**: Phase 3
    *   **Files**: [Determined by user choices]
*   [ ] **Step 6**: Final verification — run full test suite or reproduction steps.
    *   **Depends**: Step 5

---

## 6. Parallel Execution Analysis
*Auto-derived from step dependencies and file sets.*

### Chunk Derivation
*Compute from the dependency graph. Steps with no shared dependencies and disjoint file sets form parallel chunks.*

### Chunk [A]: [Description]
**Steps**: [1, 2]
**Files**: `src/path/to/mock.ts`
**Dependencies**: None (root chunk)

### Chunk [B]: [Description]
**Steps**: [3, 4]
**Files**: `src/path/to/middleware.ts`
**Dependencies**: Chunk A

### Non-Intersection Proof
> Chunk A files: `{...}`
> Chunk B files: `{...}`
> Intersection: `∅` (empty — no conflicts)

**Recommended agents**: [N]

---

## 7. Rollback & Contingency
*   **Risk**: [e.g., "Fix might introduce a regression in the auth flow"]
*   **Mitigation**: [e.g., "Run auth integration tests before and after"]
*   **Rollback**: "Revert commit X."

---

## 8. Verification
*   **Command**: [Test command or reproduction steps]
*   **Success Criteria**: [e.g., "All failing tests pass. No new failures. Production symptom no longer reproducible."]

---

## 9. Final Verification Checklist
*   [ ] **Root cause confirmed**: Evidence supports the diagnosis
*   [ ] **Fix applied**: Code changes are minimal and targeted
*   [ ] **Tests pass**: All relevant tests green
*   [ ] **No regressions**: Full suite or affected area verified
*   [ ] **Invariants checked**: No violations introduced
