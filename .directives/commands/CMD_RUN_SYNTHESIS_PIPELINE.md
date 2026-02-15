### ¶CMD_RUN_SYNTHESIS_PIPELINE
**Definition**: Conceptual guide to the synthesis pipeline — the session's final act where raw work becomes a coherent record. This document explains *why* synthesis matters and *how* the sub-phase convention works. Individual `§CMD_*` commands define their own procedures; this document provides the philosophy and structure that binds them.
**Trigger**: Called by skill protocols during their synthesis phase (typically Phase 4, 5, or 6 depending on skill).

---

## Why Synthesis Matters

A session without synthesis is a session that never happened. Code changes persist, but reasoning — why this approach, what trade-offs, what remains — evaporates when the context window closes. The debrief is the primary deliverable: it transforms raw artifacts into a narrative future agents can act on. Without it, three failures compound: **orphaned work** (tags unresolved, delegations in limbo), **invisible debt** (shortcuts and assumptions die with the context), and **broken continuity** (sessions become isolated islands instead of a connected knowledge graph). A good debrief answers: goal, what happened (including plan deviations), decisions and why, what's undone, what the next agent needs. Tech debt callouts must be specific (file, line, what was hacked) not vague.

## Why the Pipeline Scans Matter

The pipeline (N.3) maintains system hygiene through scans that are cheap to run and expensive to skip. Directive management captures new invariants and pitfalls. Delegation processing advances the tag lifecycle (`#needs-X` → `#delegated-X` → `#claimed-X` → `#done-X`). Side-discovery capture harvests incidental findings. Cross-session tags and backlinks weave the session into the project's knowledge graph. Alert management surfaces ongoing situations. Leftover work reporting ensures nothing falls through.

---

## Sub-Phase Convention

All protocol-tier skills declare synthesis as four sub-phases. N is the skill's synthesis phase number (e.g., 4 for implement, 5 for analyze).

```json
{"major": N, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
{"major": N, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
{"major": N, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
{"major": N, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"]}
```

**Proof key naming**: Every proof field is a `§CMD_` reference. This creates a direct link: proof field → command → debrief scanner output heading. The `engine session debrief` command reads these proof fields to determine which scans to run.

[!!!] **WORK → PROVE pattern**: Each sub-phase follows the same sequence — execute the commands first, then transition the phase with proof. The phase transition is the LAST action of each sub-phase, not the first. After context overflow recovery, the agent resumes AT the saved sub-phase and must complete its work before transitioning.

### N.1: Checklists
Execute `§CMD_PROCESS_CHECKLISTS`. Process discovered CHECKLIST.md files (skips silently if none). Prove and transition.

### N.2: Debrief
Execute `§CMD_GENERATE_DEBRIEF`. Creates the debrief file using the skill's template. Prove with file path and tags.

### N.3: Pipeline
Run `engine session debrief sessions/DIR` once to get scan results. Process each command in canonical order:

**1. `§CMD_MANAGE_DIRECTIVES`**
  **Type**: STATIC
  **Behavior**: Always execute. Three passes: AGENTS.md, invariants, pitfalls.

**2. `§CMD_PROCESS_DELEGATIONS`**
  **Type**: SCAN
  **Behavior**: Use debrief scan results. Process bare inline tags.

**3. `§CMD_DISPATCH_APPROVAL`**
  **Type**: CONSUMER
  **Behavior**: Consumes step 2 output (REQUEST files) + agent's pre-existing knowledge of Tags-line `#needs-*` tags. No independent scan. User triage walkthrough.

**4. `§CMD_CAPTURE_SIDE_DISCOVERIES`**
  **Type**: SCAN
  **Behavior**: Use debrief scan results. Multichoice tagging menu.

**5. `§CMD_RESOLVE_CROSS_SESSION_TAGS`**
  **Type**: STATIC
  **Behavior**: Always execute. Find tags resolved by this session's work.

**6. `§CMD_MANAGE_BACKLINKS`**
  **Type**: STATIC
  **Behavior**: Always execute. Create cross-session links.

**7. `§CMD_MANAGE_ALERTS`**
  **Type**: STATIC
  **Behavior**: Always execute. Check for alert raise/resolve.

**8. `§CMD_REPORT_LEFTOVER_WORK`**
  **Type**: SCAN
  **Behavior**: Use debrief scan results. Report incomplete items.

**Type semantics**: STATIC commands always run (reminder + action). SCAN commands use `engine session debrief` output as their task list. CONSUMER commands receive their input from a prior step's output rather than scanning independently. DEPENDENT commands only run when their prerequisite produced results.

**Roll call format**: Every pipeline step echoes a single terse line in chat. This is the audit trail — no verbose narration, no emojis in the echo, no multi-paragraph explanations.

**Format**: `N.3.K: §CMD_X — [outcome].`

**Examples**:
*   `5.3.1: §CMD_MANAGE_DIRECTIVES — no updates needed.`
*   `5.3.2: §CMD_PROCESS_DELEGATIONS — 2 bare tags found, processing.`
*   `5.3.4: §CMD_CAPTURE_SIDE_DISCOVERIES — scanned log, none found.`
*   `5.3.8: §CMD_REPORT_LEFTOVER_WORK — 3 items reported.`

When a step has actionable items, the roll call line precedes the interaction (e.g., `AskUserQuestion`). When a step finds nothing, the roll call line IS the full output — no follow-up.

**Collapsibility classification**: Pipeline steps fall into two categories based on whether they can be silently skipped when they produce no actionable items:

**COLLAPSIBLE**
  **Steps**: `§CMD_MANAGE_DIRECTIVES` (invariant + pitfall passes), `§CMD_CAPTURE_SIDE_DISCOVERIES`, `§CMD_REPORT_LEFTOVER_WORK`
  **Behavior when empty**: Roll call line only. No `AskUserQuestion`.

**NOT COLLAPSIBLE**
  **Steps**: `§CMD_RESOLVE_BARE_TAGS`, `§CMD_DISPATCH_APPROVAL`, `§CMD_PRESENT_NEXT_STEPS`
  **Behavior when empty**: Require per-item user decisions. Always present even with few items.

STATIC steps (`§CMD_MANAGE_DIRECTIVES` AGENTS.md pass, `§CMD_RESOLVE_CROSS_SESSION_TAGS`, `§CMD_MANAGE_BACKLINKS`, `§CMD_MANAGE_ALERTS`) always execute regardless — they perform actions, not triage. The collapsibility classification applies only to steps that would otherwise present an empty or trivial `AskUserQuestion`.

### N.4: Close
Execute in order: `§CMD_REPORT_ARTIFACTS` (list files), `§CMD_REPORT_SUMMARY` (2-paragraph narrative), `§CMD_WALK_THROUGH_RESULTS` (skill-specific), `§CMD_CLOSE_SESSION` (debrief gate + deactivate), `§CMD_PRESENT_NEXT_STEPS` (routing menu).

---

## What Stays Skill-Specific

*   **Debrief template**: Each skill uses its own `TEMPLATE_*.md`.
*   **Walk-through config**: Each skill defines mode, gateQuestion, debriefFile, planQuestions.
*   **Walk-through placement**: Some skills walk through before debrief (brainstorm), others after (implement).
*   **Synthesis phase number**: N varies by skill.

## Constraints

*   **No skipping**: Every sub-phase executes, even if it produces no output. `§CMD_REFUSE_OFF_COURSE` applies.
*   **Sequential**: Sub-phases execute in order (N.1 → N.2 → N.3 → N.4). Each must prove before proceeding.
*   **Scan-first**: `engine session debrief` runs once at the start of N.3. Its output drives pipeline processing. The agent does NOT re-scan.
*   **`¶INV_PROTOCOL_IS_TASK`**: The synthesis pipeline defines the task — do not skip sub-phases or reorder them.
