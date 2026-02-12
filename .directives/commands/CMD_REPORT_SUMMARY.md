### §CMD_REPORT_SUMMARY
**Definition**: Produces a dense 2-paragraph narrative summary of the session's work.
**Rule**: Must be executed immediately after `§CMD_REPORT_ARTIFACTS`.
**Algorithm**:
1.  **Reflect**: Review all work performed during this session — decisions made, problems solved, artifacts created, and key outcomes.
2.  **Compose**: Write exactly 2 dense paragraphs:
    *   **Paragraph 1 (What & Why)**: What was the goal, what approach was taken, and what was accomplished. Include specific technical details — files changed, patterns applied, problems solved. When referencing files inline, use **Compact** (`§`) or **Location** (`file:line`) links per `¶INV_TERMINAL_FILE_LINKS`.
    *   **Paragraph 2 (Outcomes & Next)**: What the current state is, what works, what doesn't yet, and what the logical next steps are. Flag any risks, open questions, or tech debt introduced.
3.  **Output**: Print under the header "## Session Summary".

---

## PROOF FOR §CMD_REPORT_SUMMARY

This command is a synthesis pipeline step. It produces no standalone proof fields — its execution is tracked by the pipeline orchestrator (`§CMD_RUN_SYNTHESIS_PIPELINE`).
