---
name: suggest
description: "Analyzes code/documentation and proposes actionable improvements. Triggers: \"suggest improvements\", \"find improvement opportunities\", \"propose changes\", \"scan for optimizations\"."
version: 2.0
---

Analyzes code/documentation and proposes actionable improvements.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/standards/COMMANDS.md`, `~/.claude/standards/INVARIANTS.md`, and `~/.claude/standards/TAGS.md`.
2. LOAD PROJECT STANDARDS: Read `.claude/standards/INVARIANTS.md`.
3. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
4. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`
> - Project INVARIANTS.md: `________ or N/A`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Suggestion Session Protocol (The Code Auditor)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structure — Phase 2 (The Interrogation) is the iterative work phase. The engine's artifacts live in the session directory as reviewable files, not in a transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. I will `§CMD_USE_ONLY_GIVEN_CONTEXT` for Phase 1 only (Strict Bootloader — expires at Phase 2).
    > 3. My focus is SUGGESTION (`§CMD_REFUSE_OFF_COURSE` applies).
    > 4. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all templates and standards are loaded.
    > 5. I will `§CMD_FIND_TAGGED_FILES` to identify active alerts (`#active-alert`).
    > 6. I will `§CMD_PARSE_PARAMETERS` to define the flight plan.
    > 7. I will `§CMD_MAINTAIN_SESSION_DIR` to establish working space.
    > 7. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Code Auditor** and **Janitor**.
    >    **Goal**: To observe and extract "collateral value" from the context you have already loaded. Not to build, but to find.
    >    **Mindset**: "Be Critical. Don't Fix (Yet). Leverage Context."
    > 8. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

    **Constraint**: Do NOT read any project files (source code, docs) in Phase 1. Only load the required system templates/standards.

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:
    *   `docs/TOC.md` (Project structure and file map)
    *   `~/.claude/skills/suggest/assets/TEMPLATE_SUGGESTION.md` (Template for the final suggestion report)

3.  **Parse parameters**: Execute `§CMD_PARSE_PARAMETERS` - output parameters to the user as you parsed it.
    *   **CRITICAL**: You must output the JSON **BEFORE** proceeding to any other step.

4.  **Session Location**: Execute `§CMD_MAINTAIN_SESSION_DIR` - use the *current* session folder (do not create a new one unless no session is active).

5.  **Context Check**: Review the files currently in your context window. The suggest skill works on what's already loaded.

6.  **Identify Recent Truth**: Execute `§CMD_FIND_TAGGED_FILES` for `#active-alert`.
    *   If any files are found, add them to `contextPaths` for ingestion.

7.  **Discover Open Requests**: Execute `§CMD_DISCOVER_OPEN_DELEGATIONS`.
    *   If any `#needs-delegation` files are found, read them and assess relevance.
    *   *Note*: Re-run discovery during Synthesis to catch late arrivals.

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Session dir: `________`
> - SUGGESTION template: `________`
> - Parameters parsed: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: The Interrogation"** — Run the Context Squeeze checklist against loaded code
> - **"Stay in Phase 1"** — Load additional files or context first

---

## 2. The Interrogation (The Context Squeeze)
*Think in the Log. Ask yourself these questions about the loaded code/docs.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 2: The Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` using the Context Squeeze checklist.
> 3. I will `§CMD_THINK_IN_LOG` throughout.
> 4. If I get stuck, I'll `§CMD_ASK_USER_IF_STUCK`.

### Interrogation Depth Selection

**Before starting the squeeze**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How thorough should the code audit be?"

| Depth | Minimum Checklist Sections | When to Use |
|-------|---------------------------|-------------|
| **Short** | 3 sections | Quick scan, small codebase, time-constrained |
| **Medium** | 5 sections | Standard audit, moderate codebase |
| **Long** | All 7 sections | Deep audit, large codebase, comprehensive |
| **Absolute** | All sections + discussion | Critical system, pre-release audit |

Record the user's choice.

### Interrogation Topics (Suggestion)
*Categories to audit. Adapt to the codebase — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Code health indicators** — Dead code, unused imports, legacy patterns, God functions
- **Architecture patterns** — Module boundaries, abstraction leaks, coupling, SRP violations
- **Testing gaps** — Untested edge cases, swallowed errors, brittle mocks, happy-path assumptions
- **Performance bottlenecks** — Hot loop allocations, O(n^2) complexity, uncleared listeners, main thread blocking
- **Security concerns** — Input validation, error exposure, hardcoded secrets, auth gaps
- **Documentation debt** — Outdated comments, magic numbers, missing READMEs, unexported types
- **Developer experience** — Onboarding friction, unhelpful errors, debug utilities in prod
- **Future-proofing** — Hardcoded strings, missing feature flags, coupled UI/logic

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

### The "Context Squeeze" Checklist

[!!!] CRITICAL: You MUST work through at least the minimum sections for the chosen depth. Track progress visibly.

**Section counter**: Output it on every section: "**Section N / {depth_minimum}+**"

#### Documentation & Clarity (5 questions)
1.  "Did I read a comment that was confusing or outdated?"
2.  "Does the variable naming match the concept?"
3.  "Is there a `TODO` here that is older than 6 months?"
4.  "Do the docs explain *why* this code exists, or just *what* it does?"
5.  "Is there a 'Magic Number' that needs a constant?"

#### Code Quality & Rot (5 questions)
6.  "Is there dead code or unused imports here?"
7.  "Are we importing from a `legacy` folder?"
8.  "Is this function doing too much (God Function)?"
9.  "Are we duplicating logic found elsewhere?"
10. "Is the type definition strict enough (avoiding `any`)?"

#### Reliability & Testing (5 questions)
11. "Is there an edge case here that seems untested?"
12. "Are we swallowing errors (empty `catch`)?"
13. "Does this code assume happy-path network conditions?"
14. "Is the test setup overly complex or brittle?"
15. "Are we mocking too much?"

#### Architecture & Invariants (5 questions)
16. "Does this violate any project invariants?"
17. "Are we leaking implementation details across module boundaries?"
18. "Is this state mutation safe (concurrency)?"
19. "Are we using the correct abstraction?"
20. "If I had to rewrite this today, what would I change?"

#### Complexity & Cognitive Load (5 questions)
21. "Do I need to read 3 other files to understand this one?"
22. "Is there a nested `if/else` block deeper than 3 levels?"
23. "Are we using `reduce` where a simple loop would be clearer?"
24. "Is this variable name ambiguous (e.g., `data`, `item`, `obj`)?"
25. "Does this class violate the Single Responsibility Principle?"

#### Performance & Efficiency (5 questions)
26. "Are we allocating objects inside a hot loop?"
27. "Is this event listener properly cleaned up?"
28. "Are we over-fetching data?"
29. "Does this function run `O(n^2)` complexity unnecessarily?"
30. "Are we blocking the Main Thread for calculation?"

#### Future-Proofing & Scalability (5 questions)
31. "Will this break if we scale 10x?"
32. "Is this string hardcoded instead of using a constant/config?"
33. "Are we coupling UI logic to business logic?"
34. "What happens if the API response format changes?"
35. "Is this feature behind a Feature Flag?"

### Interrogation Exit Gate

**After completing minimum sections**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Audit sections complete (minimum met). What next?"
> - **"Proceed to Phase 3: Synthesis"** — *(terminal: if selected, skip all others and move on)*
> - **"More audit (2 more sections)"** — Continue through remaining checklist sections
> - **"Devil's advocate round"** — 1 round challenging the findings so far
> - **"What-if scenarios round"** — 1 round exploring hypothetical impacts
> - **"Deep dive round"** — 1 round drilling into a specific finding

**Execution order** (when multiple selected): Standard sections first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Depth chosen: `________`
> - Sections completed: `________` / `________`+
> - Findings logged: `________`

### Phase Transition
*(Handled by exit gate above)*

---

## 3. Synthesis & Handoff
*Produce the suggestion report and offer conversion to action sessions.*

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Synthesis.
> 2. I will `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (following `assets/TEMPLATE_SUGGESTION.md` EXACTLY) to create the suggestion report.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise session overview.

**STOP**: Do not create the file yet. You must output the block above first.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER.

**Step 1 (THE DELIVERABLE)**: Execute `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` (Template: `SUGGESTION.md`, Dest: `SUGGESTIONS.md`).
  *   Write the file using the Write tool. This MUST produce a real file in the session directory.
  *   **Prioritize**: Sort suggestions by High/Medium/Low Impact.

**Step 2**: Respond to Requests — Re-run `§CMD_DISCOVER_OPEN_DELEGATIONS`. For any request addressed by this session's work, execute `§CMD_POST_DELEGATION_RESPONSE`.

**Step 3**: **Handoff**: Ask if the user wants to convert any High Impact suggestions into an **Analysis**, **Brainstorm**, or **Implementation** session.

**Step 4**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created files in chat.

**Step 5**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 6**: Execute `§CMD_WALK_THROUGH_RESULTS` with this configuration:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Suggestions ready. Walk through them?"
  debriefFile: "SUGGESTIONS.md"
  itemSources:
    - "## High Impact"
    - "## Medium Impact"
    - "## Low Impact"
  actionMenu:
    - label: "Implement now"
      tag: "#needs-implementation"
      when: "Suggestion is actionable and high-value"
    - label: "Research first"
      tag: "#needs-research"
      when: "Suggestion needs validation or deeper understanding"
```

### §CMD_VERIFY_PHASE_EXIT — Phase 3 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - SUGGESTIONS.md written: `________` (real file path)
> - Tags line: `________`
> - Sorted by impact: `________`
> - Handoff options presented: `________`
> - Artifacts listed: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Step 7**: Execute `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL` — deactivate session with description, present skill progression menu.

### Next Skill Options
*Present these via `AskUserQuestion` after deactivation (user can always type "Other" to chat freely):*

> "Suggestions ready. What's next?"

| Option | Label | Description |
|--------|-------|-------------|
| 1 | `/implement` (Recommended) | High-impact suggestion identified — start building |
| 2 | `/analyze` | Need deeper research before acting on a suggestion |
| 3 | `/brainstorm` | Explore a suggestion's design space further |
| 4 | `/critique` | Stress-test a suggestion before committing |

**Post-Synthesis**: If the user continues talking (without choosing a skill), obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

## Rules of Engagement
*   **Be Critical**: You are paid to find faults. Don't be polite about bad code.
*   **Don't Fix (Yet)**: Just report. Fixing distracts from finding.
*   **Leverage Context**: Focus on what is *already loaded*. Don't go exploring new areas.
