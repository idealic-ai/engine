# Refinement Plan (The Experiment Design)

## Overview
**Context**: Link to `ANALYSIS.md` or prior `REFINE.md` if this is a follow-up refinement.
**Required Documents**:
*   `~/.claude/.directives/INVARIANTS.md` (Shared) and `.claude/.directives/INVARIANTS.md` (Project-specific, if exists)
*   Relevant prompt files from `promptPaths`
*   Relevant schema files from `schemaPaths`

**Goal**: Design a systematic approach to improve LLM extraction accuracy through controlled experiments.

**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/REFINE_PLAN.md`.

---

## 1. Problem Statement
*What are we trying to fix? What's the current state?*

*   **Current Accuracy**: `X/Y` cases passing (`Z%`)
*   **Primary Symptom**: (e.g., "Scope headers on multi-line entries are missed")
*   **Secondary Symptoms**: (e.g., "Bounding boxes drift right on continuation pages")
*   **Impact**: (e.g., "Affects 30% of estimates in production")

---

## 2. Workload Configuration
*The manifest-level settings for this refinement session.*

*   **Workload ID**: `[name]`
*   **Prompt Files**: `[list paths]`
*   **Schema Files**: `[list paths if any]`
*   **Case Files**: `[glob pattern or list]`
*   **Expected Outputs**: `[path pattern or "none — qualitative only"]`

---

## 3. Hypotheses (Ranked)
*What do we believe is causing the failures? Rank by likelihood and testability.*

### Hypothesis A: [Title] — Priority: HIGH
*   **Observation**: "3 fixtures fail on scope headers that span two lines"
*   **Theory**: "The prompt lacks examples of multi-line headers"
*   **Testable?**: Yes — add example, re-run affected cases
*   **Expected Impact**: "Fixes fixtures 3, 7, 12"
*   **Confidence**: [High / Medium / Low]

### Hypothesis B: [Title] — Priority: MEDIUM
*   **Observation**: "..."
*   **Theory**: "..."
*   **Testable?**: ...
*   **Expected Impact**: "..."
*   **Confidence**: ...

### Hypothesis C: [Title] — Priority: LOW
*   **Observation**: "..."
*   **Theory**: "..."
*   **Testable?**: ...
*   **Expected Impact**: "..."
*   **Confidence**: ...

---

## 4. Experimental Setup
*Define the controlled environment for testing.*

### 4.1 Control Group (Baseline)
*   **Cases**: `[list or "all cases in casePaths"]`
*   **Prompt Version**: `[commit hash or "current HEAD"]`
*   **Baseline Metrics**: `[from prior run or "TBD in Baseline Phase"]`

### 4.2 Test Variables
*What we're changing in each experiment.*

| Variable | Current Value | Proposed Change |
|----------|---------------|-----------------|
| Multi-line header guidance | None | Add explicit example |
| Coordinate system bounds | Implicit | Add explicit "x in [0,612], y in [0,792]" |
| ... | ... | ... |

### 4.3 Constants (Do Not Change)
*What stays fixed to isolate variables.*

*   Schema structure (no field additions/removals)
*   LLM model and temperature
*   Input preprocessing pipeline
*   ...

---

## 5. Case Selection Strategy
*Which cases to focus on and why.*

### 5.1 Focus Cases (High Signal)
*Cases that best test our hypotheses.*

| Case | Symptom | Tests Hypothesis |
|------|---------|------------------|
| `multi-room-v2/page-3` | Multi-line header missed | A |
| `continuation/page-5` | Bounding box drift | B |
| `edge-case/dense-layout` | Over-detection | A, C |

### 5.2 Regression Guards
*Cases that are currently passing and must stay passing.*

*   `standard/basic-estimate` — canonical happy path
*   `standard/single-room` — minimal case
*   `...`

### 5.3 Excluded Cases (And Why)
*Cases we're intentionally ignoring this session.*

*   `edge-case/scanned-poor-quality` — Input quality issue, not prompt issue
*   `...`

---

## 6. Success Criteria
*How do we know when we're done?*

### 6.1 Quantitative Goals
*   **Minimum**: Improve by `+N` passing cases with zero regressions
*   **Target**: Reach `X%` pass rate (currently `Y%`)
*   **Stretch**: 100% pass rate on focus cases

### 6.2 Qualitative Goals
*   Visual overlays show correct bounding boxes on all focus cases
*   No new categories of errors introduced
*   Insights documented for future sessions

### 6.3 Exit Conditions
*When to stop iterating.*

*   **Success**: Target pass rate achieved
*   **Plateau**: No improvement for 2 consecutive iterations
*   **Regression**: Net negative change after 3 iterations
*   **Max Iterations**: `N` iterations reached (default: 5)

---

## 7. Experiment Sequence
*Ordered list of experiments to run. Each tests one hypothesis.*

### Experiment 1: [Title] — Tests Hypothesis A
*   [ ] **Setup**: Identify the specific prompt section to modify
*   [ ] **Change**: Add multi-line header example to `prompts.ts:47`
*   [ ] **Run**: Execute on focus cases: `multi-room-v2/page-3`, `edge-case/dense-layout`
*   [ ] **Measure**: Compare pass rate, check for regressions
*   [ ] **Verdict**: [Proceed / Revert / Refine]

### Experiment 2: [Title] — Tests Hypothesis B
*   [ ] **Setup**: ...
*   [ ] **Change**: ...
*   [ ] **Run**: ...
*   [ ] **Measure**: ...
*   [ ] **Verdict**: ...

### Experiment 3: [Title] — Contingency
*If Experiments 1-2 don't achieve target, try this.*

*   [ ] **Setup**: ...
*   [ ] **Change**: ...
*   [ ] **Run**: ...
*   [ ] **Measure**: ...
*   [ ] **Verdict**: ...

---

## 8. Rollback & Contingency
*What if things go wrong?*

*   **Rollback Point**: `[commit hash]` — last known good state
*   **If Regression**: Do NOT revert mid-session. Log the failure, form new hypothesis, continue.
*   **If Stuck**: Escalate to user with findings. Consider expanding case set or re-examining hypotheses.

---

## 9. Pre-Flight Checklist
*Verify before starting iteration loop.*

*   [ ] Manifest validated against schema
*   [ ] All case files accessible
*   [ ] Baseline metrics recorded (or scheduled for Phase 4)
*   [ ] Focus cases identified and prioritized
*   [ ] Regression guard cases identified
*   [ ] Success criteria agreed with user

---

## 10. Notes & Constraints
*Any additional context or limitations.*

*   **Time Box**: "Max 2 hours for this session"
*   **Scope Limit**: "Prompt changes only — no schema modifications"
*   **Dependencies**: "Requires overlay generation to be working"
*   **...**: ...
