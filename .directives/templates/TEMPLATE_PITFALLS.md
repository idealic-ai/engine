# [PACKAGE_NAME] Pitfalls

<!-- Known gotchas and traps. Read before working here. -->
<!-- Each pitfall: ¶PTF_NAME bullet with Context → Trap → Mitigation sub-fields -->
<!-- Add new pitfalls as they're discovered (§CMD_MANAGE_DIRECTIVES captures these at end-of-session) -->
<!-- Naming: Derive PTF_NAME from the trap essence in UPPER_SNAKE_CASE. No scope prefix — file location provides scope. -->

*   **¶PTF_EXAMPLE_NAME**: [one-line trap summary]
    *   **Context**: When/where this pitfall occurs (e.g., "When adding new Zod schemas for Gemini extraction")
    *   **Trap**: What goes wrong and why it's surprising (e.g., "Gemini rejects schemas with .min()/.max() constraints")
    *   **Mitigation**: How to avoid or work around it (e.g., "Move constraints to .describe() text instead")

*   **¶PTF_ANOTHER_EXAMPLE**: [one-line trap summary]
    *   **Context**: Situation that triggers this trap
    *   **Trap**: The surprising behavior or failure mode
    *   **Mitigation**: The workaround or correct approach

## Writing Good Pitfalls

- Each entry uses the `*   **¶PTF_NAME**: [summary]` bullet format with Context/Trap/Mitigation sub-fields
- Names capture the trap essence in UPPER_SNAKE_CASE (e.g., `¶PTF_HOOK_EXIT_AFTER_ALLOW`, `¶PTF_BASH32_COMPATIBILITY`)
- `¶PTF_NAME` marks the definition; `§PTF_NAME` marks references from other files
- Ordered by severity or frequency of occurrence
- Cross-references relevant invariants (e.g., "See `§INV_GEMINI_SCHEMA_SIMPLICITY`")
- Concise — each pitfall is 4-6 lines, not a debugging guide
- Code examples indent under Mitigation sub-bullet
- Added incrementally as gotchas are discovered during sessions
