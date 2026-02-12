# [PACKAGE_NAME] Pitfalls

<!-- Known gotchas and traps. Read before working here. -->
<!-- Each pitfall: Context → Trap → Mitigation -->
<!-- Add new pitfalls as they're discovered (§CMD_MANAGE_DIRECTIVES captures these at end-of-session) -->

## [Pitfall Title]

**Context**: When/where this pitfall occurs (e.g., "When adding new Zod schemas for Gemini extraction")
**Trap**: What goes wrong and why it's surprising (e.g., "Gemini rejects schemas with .min()/.max() constraints")
**Mitigation**: How to avoid or work around it (e.g., "Move constraints to .describe() text instead")

## [Another Pitfall Title]

**Context**: Situation that triggers this trap
**Trap**: The surprising behavior or failure mode
**Mitigation**: The workaround or correct approach

## Example: Engine PITFALLS.md

A good pitfalls file:
- Each entry has Context (when), Trap (what), Mitigation (how to avoid)
- Ordered by severity or frequency of occurrence
- Cross-references relevant invariants (e.g., "See ¶INV_GEMINI_SCHEMA_SIMPLICITY")
- Concise — each pitfall is 3-5 lines, not a debugging guide
- Added incrementally as gotchas are discovered during sessions
