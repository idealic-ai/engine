# [Project Name] — Orchestration Vision
**Tags**: [lifecycle tags]

## Provenance

| Field | Value |
|-------|-------|
| **Created by** | `sessions/[DIRECT_SESSION_PATH]` |
| **Mode** | [Greenfield / Evolution (v[N]) / Split ([parent-slug])] |
| **Date** | [YYYY-MM-DD] |
| **Version** | [v1 / v2 / ...] |
| **Previous version** | [None / path to previous version or git ref] |

---

## 1. Background & Motivation

### Problem Statement
[What problem does this project solve? Describe the current pain in concrete terms. What breaks, what's slow, what's missing, what's costing money or time?]

### Current State
[How things work today. Key systems involved, their limitations, technical debt, user complaints. Be specific — this grounds the vision in reality.]

### Opportunity
[What becomes possible after this project? Not just "fix the bug" — what new capabilities, efficiencies, or business outcomes does this unlock?]

### Cost of Inaction
[What happens if we do nothing? Quantify where possible: growing tech debt, missed deadlines, competitive risk, user churn, operational cost.]

### Stakeholders
| Stakeholder | Interest | Impact |
|-------------|----------|--------|
| [Who] | [What they care about] | [How this project affects them] |

---

## 2. Vision

### Goal
[What this project achieves. 2-3 sentences defining the north star. This is the sentence everyone can recite.]

### Success Criteria
[Measurable outcomes. When ALL of these are checked, the project is done.]
- [ ] [Measurable outcome 1 — quantified where possible]
- [ ] [Measurable outcome 2]
- [ ] [Measurable outcome 3]

### Non-Goals
[Explicitly out of scope. What this project does NOT do, even if related. Prevents scope creep.]
- [Non-goal 1 — why it's excluded]
- [Non-goal 2]

### Constraints
[Hard boundaries that cannot be violated.]
- [Constraint 1 — non-negotiable boundary, e.g., "Must not break existing API contracts"]
- [Constraint 2 — compliance, timeline, budget, resource limits]
- [Constraint 3 — technical constraints, e.g., "Must run on existing infrastructure"]

---

## 3. Architecture Sketch

### System Overview
[High-level view of what the system looks like AFTER this project completes. Draw the target state, not the current state. Use §CMD_FLOWGRAPH notation for all diagrams.]

```
[§CMD_FLOWGRAPH — Target Architecture]

[Example:
START → User Request ⟨HTTP⟩
  ↓
API GATEWAY (NestJS)
  │ • Validates request
  │ • Authenticates caller
  │
  ├► AUTH SERVICE
  │   │ • Token management
  │   │ • Session handling
  │
  ├► TEMPORAL ORCHESTRATOR
  │   │ • Workflow dispatch
  │   │ • Durable execution
  │   │
  │   ├► WORKER GROUP: API
  │   │   │ • Business logic activities
  │   │   ↓
  │   ╰► WORKER GROUP: DOMAIN
  │       │ • Domain-specific processing
  │
  ╰► DATABASE (Postgres)
      │ • Entity state (source of truth)
      │ • Process state via Temporal history
]
```

### Key Components
[What are the major pieces being built or modified?]

| Component | Location | Role | Changed By |
|-----------|----------|------|------------|
| [Component name] | [package/path] | [What it does] | [Which chapter(s)] |

### Data Flow
[How data moves through the system. Use §CMD_FLOWGRAPH for non-trivial flows.]

```
[§CMD_FLOWGRAPH — Critical Data Path]

START → [Data entry point]
  ↓
INPUT PROCESSING
  │ • [Validation step]
  │ • [Transformation step]
  ↓
  ◆ [Decision point?]
  ║
  ╠⇒ [Path A] → [Processing]
  ║         │ • [Detail]
  ║    ╭────╯
  ║    ↓
  ╚⇒ [Path B] → [Alternative processing]
            │ • [Detail]
  ╭─────────╯
  ↓
STORAGE
  │ • [Where data lands — both paths converge here]
  ↓
END → [Consumer / output]
```

### Key Technical Decisions
[Decisions already made that constrain the architecture. Reference brainstorm/analyze sessions.]

| Decision | Rationale | Alternatives Rejected |
|----------|-----------|----------------------|
| [Decision 1] | [Why] | [What else was considered] |
| [Decision 2] | [Why] | [What else was considered] |

---

## 4. Decision Principles

[Natural language guidance for the coordinator's judgment calls. These influence LLM reasoning — they are soft guidance, not mechanical rules. Hard rules belong in `coordinate.config.json`.]

### Development Approach
- [e.g., "Prefer speed over thoroughness for internal tools"]
- [e.g., "Always use TDD for API-facing changes"]
- [e.g., "Write integration tests before unit tests for workflow code"]

### Risk & Escalation
- [e.g., "Escalate anything touching payment processing"]
- [e.g., "Database migrations require human review before execution"]
- [e.g., "If unsure about a public API change, escalate — don't guess"]

### Quality & Standards
- [e.g., "Follow existing patterns in the codebase — consistency over novelty"]
- [e.g., "Every new endpoint needs OpenAPI documentation"]
- [e.g., "No new dependencies without justification"]

### Prioritization
- [e.g., "Core functionality before edge cases"]
- [e.g., "Unblock other chapters before optimizing current chapter"]
- [e.g., "Fix broken tests immediately — never leave the suite red"]

---

## 5. Context Sources

[Sessions and documents that informed this vision. This is the bibliography — every claim in this document should trace back to one of these sources.]

| Source | Type | Key Insight | Date |
|--------|------|-------------|------|
| `sessions/[PATH]` | /analyze | [What it contributed — specific findings] | [YYYY-MM-DD] |
| `sessions/[PATH]` | /brainstorm | [What it contributed — decisions made] | [YYYY-MM-DD] |
| `sessions/[PATH]` | /research | [What it contributed — external knowledge] | [YYYY-MM-DD] |
| `docs/[PATH]` | documentation | [What it provides — specs, architecture] | [YYYY-MM-DD] |

---

## 6. Dependency Graph

```
[§CMD_FLOWGRAPH — Chapter Dependencies]

[Example:
START → Project Kickoff
  ↓
PARALLEL GROUP 1 (no shared deps)
  │
  ├► @app/auth-system
  │   │ • Separate concerns, extract token service
  │
  ╰► @packages/sdk/types
      │ • Shared type definitions
  ╭───╯
  ↓
PARALLEL GROUP 2 (depends on Group 1)
  │
  ├► @app/rate-limiting
  │   │ • Depends on: @app/auth-system
  │   │ • Uses new token service hooks
  │
  ╰► @packages/sdk/client-update
      │ • Depends on: @packages/sdk/types
  ╭───╯
  ↓
@app/error-standardization
  │ • Depends on: @app/rate-limiting, @packages/sdk/client-update
  │ • Standardize all auth error responses
  ↓
END → All chapters complete
]
```

### Parallel Groups
[Chapters that can execute simultaneously — no shared dependencies.]

| Group | Chapters | Notes |
|-------|----------|-------|
| **Group 1** | `@[slug-a]`, `@[slug-b]` | No shared files or APIs |
| **Group 2** | `@[slug-c]` | Depends on Group 1 completion |
| **Group 3** | `@[slug-d]`, `@[slug-e]` | Depends on Group 2; internal independence |

### Critical Path
[The longest serial chain. This determines the minimum project duration.]
`@[slug-a]` → `@[slug-c]` → `@[slug-d]` → `@[slug-f]`

### Shared Resources
[Resources touched by multiple chapters. These create implicit dependencies even without explicit `Depends on` fields.]

| Resource | Chapters | Risk | Mitigation |
|----------|----------|------|------------|
| [file/API/table] | `@[slug-a]`, `@[slug-c]` | [Conflict type] | [How to avoid] |

---

## 7. Glossary

[Domain terms, acronyms, and project-specific vocabulary. Agents and humans reading this document should not have to guess what terms mean.]

| Term | Definition |
|------|-----------|
| [Term 1] | [What it means in this project's context] |
| [Term 2] | [What it means] |

---

## Chapters

<!--
  CHAPTER TEMPLATE — Copy this block for each chapter.

  Slug format: path/based-semantic-slug (e.g., app/auth-system, packages/sdk/types)
  Slugs are STABLE identifiers — used for diffing, delegation, and folder naming.
  Do NOT rename slugs of completed chapters unless intentional (triggers re-execution).
-->

### `@[slug/path]`: [Human-Readable Title]
**Tags**: #needs-coordinate

[Description of this chapter's work. 2-4 sentences explaining what gets built, why it matters, and what changes when it's done.]

#### Scope
- **In scope**: [What's included — be specific about files, APIs, components]
- **Out of scope**: [What's explicitly excluded — prevents scope creep during execution]
- **Key files/components**: [Primary files or modules that will be created or modified]
  - `[path/to/file.ts]` — [what changes]
  - `[path/to/module/]` — [what changes]

#### Dependencies
- **Depends on**: [Nothing / `@slug/of-dependency` — what must complete first]
- **Blocks**: [`@slug/of-dependent` — what chapters are waiting on this one]
- **Shared resources**: [Files, APIs, or tables shared with other chapters]

#### Acceptance Criteria
[When ALL of these are true, this chapter is done. Written as testable assertions.]
- [ ] [Criterion 1 — specific, verifiable]
- [ ] [Criterion 2]
- [ ] [Criterion 3]
- [ ] [Tests pass: describe what test coverage is expected]

#### Risks & Open Questions
[What could go wrong? What's still uncertain?]
- **Risk**: [Description] → **Mitigation**: [How to handle it]
- **Open question**: [What needs to be resolved during execution]

#### Complexity & Effort
- **Estimated effort**: [S / M / L]
- **Complexity drivers**: [What makes this hard — integration points, unknowns, legacy code]
- **Parallel opportunity**: [Can sub-tasks within this chapter be parallelized across workers?]

---

### `@[slug/path]`: [Human-Readable Title]
**Tags**: #needs-coordinate

[Description]

#### Scope
- **In scope**: [Specifics]
- **Out of scope**: [Exclusions]
- **Key files/components**:
  - `[path]` — [change]

#### Dependencies
- **Depends on**: [`@slug/of-dependency`]
- **Blocks**: [`@slug/of-dependent`]
- **Shared resources**: [Shared files/APIs]

#### Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

#### Risks & Open Questions
- **Risk**: [Description] → **Mitigation**: [Handling]

#### Complexity & Effort
- **Estimated effort**: [S / M / L]
- **Complexity drivers**: [What makes it hard]
- **Parallel opportunity**: [Sub-task parallelism]

---

<!-- Repeat chapter blocks as needed -->

---

## Appendix: Evolution History

<!--
  Populated automatically by /direct Evolution mode.
  Each evolution adds a row. This is the audit trail of how the vision changed over time.
-->

| Version | Date | Session | Summary of Changes |
|---------|------|---------|-------------------|
| v1 | [YYYY-MM-DD] | `sessions/[PATH]` | Initial vision |
