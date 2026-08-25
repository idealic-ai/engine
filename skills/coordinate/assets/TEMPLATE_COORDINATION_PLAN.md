# Chapter [N]: [Chapter Name]
**Tags**:
**Vision**: [path to vision document]
**Previous Chapter**: [session path or "None"]
**Requesting Session**: [session that produced this chapter, e.g., `/direct` session path]

---

## 1. Provenance

*   **Chapter Number**: [N] of [Total]
*   **Vision Document**: [path — the evergreen project plan that defines this chapter]
*   **Previous Chapter Session**: [session path — for continuity and cross-reference]
*   **Created By**: `/coordinate` session at [session path]
*   **Source Material**: [List documents consumed during chapter planning — vision doc, brainstorms, analyses, prior debriefs]

---

## 2. Objective & Context

### What This Chapter Achieves
[1-2 paragraphs. Derived from the vision document's chapter description. State the concrete outcome — what will be true when this chapter is done that isn't true now.]

### How It Fits the Larger Vision
[1 paragraph. Connect this chapter to the overall project goal. What did previous chapters establish? What does this chapter unblock for future chapters? Reference the vision doc's dependency graph if applicable.]

### Scope Boundaries
*   **In Scope**: [Explicit list of what this chapter covers]
*   **Out of Scope**: [Explicit list of what is deferred to later chapters or other work]
*   **Dependencies**: [What must be true before this chapter can start — prior chapter completion, external systems, etc.]

---

## 3. Decision Principles

Referenceable rules that guide all work in this chapter. Workers load the vision doc alongside this plan — principles defined there can be referenced by name without re-explanation.

### Inherited from Vision
*   **`RUL_[NAME]`**: [Brief reminder of what it means — workers have the full definition in the vision doc]
*   **`RUL_[NAME]`**: [...]

### Chapter-Specific
*   **`RUL_[NAME]`**: [Full definition — this rule applies only to this chapter's work]
    *   *Rationale*: [Why this rule exists for this chapter]
*   **`RUL_[NAME]`**: [...]

### Anti-Patterns
*   **Do NOT**: [Specific thing workers should avoid in this chapter]
    *   *Why*: [Consequence of doing it]

---

## 4. Architecture & Design Notes

### Technical Decisions
[Key architectural choices made during chapter planning. These are decisions — not explorations. Each should have a clear rationale.]

*   **Decision**: [What was decided]
    *   *Rationale*: [Why]
    *   *Alternatives Rejected*: [What else was considered and why it was rejected]

### Patterns to Follow
[Existing codebase patterns that workers should replicate. Reference specific files as examples.]

*   **Pattern**: [Name/description]
    *   *Example*: [File path or code reference]
    *   *When to Use*: [Conditions]

### Constraints
[Hard constraints from the codebase, infrastructure, or project conventions that workers must respect.]

*   [Constraint 1 — e.g., "All new endpoints must follow the NestJS controller pattern in `apps/api/src/`"]
*   [Constraint 2]

---

## 5. Work Items

Work items are the core execution units. Two formats: **Big Task** for substantial work and **Small Task** for lightweight items. Prefer fewer bigger tasks with sub-checklists over many small tickets.

### Big Task Format

#### [WI-N]: [Task Title]
*   **Description**: [2-3 sentences. What needs to be done and why. Enough context for a worker to start without asking questions.]
*   **Acceptance Criteria**:
    *   [ ] [Specific, verifiable criterion 1]
    *   [ ] [Specific, verifiable criterion 2]
    *   [ ] [Specific, verifiable criterion 3]
*   **Dependencies**: [Other work items that must complete first, or "None"]
*   **Assigned To**: Group: [worker group name]
*   **Key Files**: [Primary files this task touches — helps workers scope their work]
*   **Sub-Checklist**:
    *   [ ] [Sub-step 1]
    *   [ ] [Sub-step 2]
    *   [ ] [Sub-step 3]
*   **Hints**: [Implementation guidance, reference files, gotchas. Optional but valuable.]

### Small Task Format

#### [WI-N]: [Task Title]
*   **Description**: [1 sentence]
*   **Assigned To**: Group: [worker group name]
*   **Key Files**: [Files touched]
*   **Criteria**: [Single line — what "done" looks like]

### Work Items

[Populate with actual tasks during chapter planning. Use Big Task format for complex work, Small Task for simple items.]

---

## 6. Worker Briefing

Per-group briefings provide dedicated context for each worker group. Workers receive their group's briefing alongside the full chapter plan.

### Group: [Group Name]
*   **Workers**: [Worker pane labels, e.g., `%api:Worker-1`, `%api:Worker-2`]
*   **Assigned Work Items**: [WI-1], [WI-3], [WI-5]
*   **Skills Expected**: [Which `/skill` commands workers will use — e.g., `/implement`, `/fix`, `/test`]
*   **Context to Load**: [Specific files, sessions, or docs this group needs beyond the chapter plan]
*   **Group-Specific Guidance**: [Anything unique to this group's work — coordination between workers within the group, shared state, ordering constraints]

### Group: [Group Name]
*   **Workers**: [...]
*   **Assigned Work Items**: [...]
*   **Skills Expected**: [...]
*   **Context to Load**: [...]
*   **Group-Specific Guidance**: [...]

---

## 7. Open Questions & Gaps

Items where the coordinator identified missing information during chapter planning. Tagged with `#needs-*` for deferred resolution.

*   **[Q-N]**: [Question or gap description]
    *   *Impact*: [Which work items are affected if this remains unresolved]
    *   *Suggested Resolution*: [How to find the answer — ask user, research, brainstorm]
    *   *Tag*: [e.g., `#needs-brainstorm`, `#needs-research`]

*   **[Q-N]**: [...]

[If no open questions remain after interrogation, state: "All questions resolved during chapter planning interrogation."]

---

## 8. Completion Criteria

ALL criteria must pass before this chapter is marked `#done-coordination` and the next chapter begins. These are the enforcement mechanism for chapter gates.

### Functional Criteria
*   [ ] [All work items checked — every WI-N is complete]
*   [ ] [Integration verification — components work together]
*   [ ] [No open `#needs-fix` tags in chapter artifacts]

### Quality Criteria
*   [ ] [Tests pass — specify which test suites]
*   [ ] [Lint passes — specify scope]
*   [ ] [No regressions in existing functionality]

### Process Criteria
*   [ ] [All worker sessions have debriefs]
*   [ ] [No unresolved escalations]
*   [ ] [Documentation updated if applicable]

---

## 9. References & Context Sources

### Vision Document
*   [Path to vision doc — the authoritative source for project-level goals]

### Prior Chapter Sessions
*   [Session paths for completed chapters — for cross-reference and continuity]

### Relevant Documentation
*   [Architecture docs, API specs, design docs referenced by work items]

### Relevant Code Paths
*   [Key directories and files that workers will interact with]

### Prior Analysis/Brainstorm Sessions
*   [Sessions that informed this chapter's planning — analysis reports, brainstorm outputs]
