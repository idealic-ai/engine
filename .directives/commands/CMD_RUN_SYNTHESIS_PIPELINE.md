### §CMD_RUN_SYNTHESIS_PIPELINE
**Definition**: The centralized synthesis pipeline orchestrator. Replaces the copy-pasted synthesis blocks in individual SKILL.md files with a single standard mechanism. Skills reference this command in their synthesis phase instead of duplicating pipeline steps.
**Trigger**: Called by skill protocols during their synthesis phase (typically Phase 5 or Phase 6, depending on skill).
**Prerequisite**: The skill MUST declare synthesis sub-phases with `§CMD_`-named proof fields in its `phases` array (see Sub-phase Convention below).

[!!!] **WORK → PROVE pattern**: Each step below follows the same sequence: execute the command first, then transition the phase with proof. The phase transition is the LAST action of each step, not the first. After context overflow recovery, the agent resumes at the saved phase — it must do the next step's work before transitioning.

**Sub-phase Convention** (all protocol-tier skills follow this pattern):
```json
{"major": N, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
{"major": N, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
{"major": N, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
{"major": N, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
```
Where N is the skill's synthesis phase number (e.g., 5 for implement, 6 for analyze).

**Proof Key Naming**: Every proof field name is a `§CMD_` reference from COMMANDS.md. This creates a direct link: proof field → command → debrief output heading. The `engine session debrief` command reads these proof fields to determine which scans to run.

**Algorithm**:

**Step 0 — Checklists** (sub-phase N.1):
1.  Execute `§CMD_PROCESS_CHECKLISTS` — process discovered CHECKLIST.md files. Skips silently if none.
2.  Prove:
    ```bash
    engine session phase sessions/DIR "N.1: Checklists" <<'EOF'
    §CMD_PROCESS_CHECKLISTS: [processed N checklists | skipped: none discovered]
    EOF
    ```

**Step 1 — Debrief** (sub-phase N.2):
1.  Execute `§CMD_GENERATE_DEBRIEF` — creates the debrief file (steps 1-7 of that command).
2.  Prove:
    ```bash
    engine session phase sessions/DIR "N.2: Debrief" <<'EOF'
    §CMD_GENERATE_DEBRIEF_file: sessions/DIR/DEBRIEF_FILE.md
    §CMD_GENERATE_DEBRIEF_tags: #needs-review
    EOF
    ```

**Step 2 — Pipeline** (sub-phase N.3):
1.  Run `engine session debrief sessions/DIR` to get scan results. The output contains `## §CMD_NAME (count)` headings for SCAN sections, static reminders for STATIC sections, and conditional sections for DEPENDENT sections.
2.  Process each section in the debrief output, in this canonical order:
    *   `§CMD_MANAGE_DIRECTIVES` (STATIC) — always execute. Three passes: AGENTS.md updates, invariant capture, pitfall capture. Skips silently if none found.
    *   `§CMD_PROCESS_DELEGATIONS` (SCAN) — use the scan results from debrief output. Execute the command with the listed items. Skips silently if count is 0.
    *   `§CMD_DISPATCH_APPROVAL` (DEPENDENT) — only execute if `§CMD_PROCESS_DELEGATIONS` found items (count > 0). Present dispatch walkthrough for user triage.
    *   `§CMD_CAPTURE_SIDE_DISCOVERIES` (SCAN) — use the scan results. Present multichoice for tagging. Skips silently if count is 0.
    *   `§CMD_MANAGE_ALERTS` (STATIC) — always execute. Check for alert raise/resolve. Skips silently if none needed.
    *   `§CMD_REPORT_LEFTOVER_WORK` (SCAN) — use the scan results. Output report in chat. Skips silently if count is 0.
3.  Prove:
    ```bash
    engine session phase sessions/DIR "N.3: Pipeline" <<'EOF'
    §CMD_MANAGE_DIRECTIVES: [ran: N updates | skipped: no files touched]
    §CMD_PROCESS_DELEGATIONS: [ran: N bare tags processed | skipped: none found]
    §CMD_DISPATCH_APPROVAL: [ran: N items dispatched | skipped: none found]
    §CMD_CAPTURE_SIDE_DISCOVERIES: [ran: N captured | skipped: none found]
    §CMD_MANAGE_ALERTS: [ran: N alerts managed | skipped: none needed]
    §CMD_REPORT_LEFTOVER_WORK: [ran: N items reported | skipped: none found]
    EOF
    ```

**Step 3 — Close** (sub-phase N.4):
1.  Execute `§CMD_REPORT_ARTIFACTS` — list all created/modified files in chat.
2.  Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph session summary in chat.
3.  Execute `§CMD_WALK_THROUGH_RESULTS` — skill-specific walk-through (config defined in each SKILL.md).
4.  Prove:
    ```bash
    engine session phase sessions/DIR "N.4: Close" <<'EOF'
    §CMD_REPORT_ARTIFACTS: yes
    §CMD_REPORT_SUMMARY: yes
    EOF
    ```
5.  Execute `§CMD_CLOSE_SESSION` — deactivate session, present next-skill menu.

**What stays skill-specific** (NOT centralized):
*   **Debrief template**: Each skill uses its own `TEMPLATE_*.md` (e.g., `TEMPLATE_IMPLEMENTATION.md` vs `TEMPLATE_ANALYSIS.md`).
*   **Walk-through config**: Each skill defines its own `§CMD_WALK_THROUGH_RESULTS Configuration` block (mode, gateQuestion, debriefFile, planQuestions).
*   **Walk-through placement**: Some skills place the walk-through before the debrief (e.g., brainstorm), others after (e.g., implement). The skill's synthesis block controls when `§CMD_WALK_THROUGH_RESULTS` runs relative to the other steps.
*   **Synthesis phase number**: N varies by skill (5 for implement, 6 for analyze, etc.).

**Constraints**:
*   **No skipping**: Every sub-phase executes, even if it produces no output. `§CMD_REFUSE_OFF_COURSE` applies.
*   **Sequential**: Sub-phases execute in order (N.1 → N.2 → N.3 → N.4). Each must prove before proceeding.
*   **Scan-first**: `engine session debrief` runs once at the start of Step 2. Its output drives the agent's pipeline processing. The agent does NOT re-scan — it uses the debrief output as its task list.
