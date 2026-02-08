# Pitfalls

Known gotchas and traps when creating or modifying skills. Read before working here.

### Synthesis steps have a strict order — don't rearrange
**Context**: The synthesis phase (final phase of every protocol-tier skill) calls `§CMD_PROCESS_CHECKLISTS` before `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`, which calls `§CMD_MANAGE_DIRECTIVES`, then `§CMD_CAPTURE_SIDE_DISCOVERIES`, then `§CMD_REPORT_LEFTOVER_WORK`, then `§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`. Each step depends on the prior step's output.
**Trap**: Reordering synthesis steps (e.g., generating the debrief before processing checklists) breaks the `¶INV_CHECKLIST_BEFORE_CLOSE` gate — `session.sh deactivate` will reject because `checkPassed` is not set. Similarly, managing directives before the debrief means the debrief content isn't available for README/invariant extraction.
**Mitigation**: Copy the synthesis section from an existing protocol-tier skill (e.g., `/implement`, `/document`) verbatim and only customize the walk-through configuration.

### Mode files must be self-contained — don't reference other modes
**Context**: Each mode file (`modes/surgical.md`, `modes/refine.md`, etc.) defines Role, Goal, Mindset, and Approach for that mode. Custom mode reads ALL named mode files to synthesize a hybrid.
**Trap**: If a mode file says "same as Surgical but with X", the Custom mode synthesis breaks — the agent can't reliably cross-reference between files during Custom mode construction. Each mode file must stand alone with its full definition.
**Mitigation**: Write each mode file as if it's the only one the agent will read. Repeat shared context if needed.

### The frontmatter `tier` field controls session overhead — choose carefully
**Context**: Skills have two tiers: `protocol` (full session lifecycle with phases, logging, debrief) and `lightweight` (minimal overhead, no phase enforcement).
**Trap**: Setting `tier: protocol` on a simple skill (like `edit-skill` or `writeup`) forces the agent through interrogation rounds, planning phases, and full synthesis — massive overhead for a 5-minute task. Conversely, setting `tier: lightweight` on a complex skill loses phase enforcement, logging discipline, and debrief generation.
**Mitigation**: If the skill typically completes in under 15 minutes with minimal user interaction, use `lightweight`. If it involves multi-step planning, iterative work, or needs an audit trail, use `protocol`.

### Phase arrays must match the actual protocol phases exactly
**Context**: Protocol-tier skills declare a `phases` array in the Phases section. `session.sh phase` enforces sequential transitions based on this array.
**Trap**: If you add, remove, or reorder phases in the protocol text but forget to update the phases array (or vice versa), phase enforcement either blocks valid transitions or allows skips. The phase labels in the array must match the headings in the SKILL.md protocol.
**Mitigation**: After any phase change in SKILL.md, diff the phases array against the actual `## N. Phase Name` headings. They must be 1:1.

### New engine features must propagate to all applicable skills
**Context**: `¶INV_SKILL_FEATURE_PROPAGATION` requires that when a new feature is added to one skill, it must be added to all applicable skills or tagged `#needs-implementation`.
**Trap**: Adding a feature (walk-through config, mode presets, interrogation depth, parallel handoff) to one skill and forgetting the rest creates structural debt. The "gold standard" skills diverge from "stale" skills, making it harder to propagate later.
**Mitigation**: After adding a feature to any skill, immediately grep all SKILL.md files for the presence/absence of that feature pattern. Tag missing skills or propagate in the same session.

### Template placeholder names must match the populated content
**Context**: Templates use `[PLACEHOLDER]` patterns that agents populate via `§CMD_POPULATE_LOADED_TEMPLATE`. The debrief template's structure defines the debrief's structure.
**Trap**: Renaming a section heading in a template without updating the skill protocol (which references specific section names for walk-through configuration or content instructions) creates silent mismatches. The agent writes content that doesn't align with the template structure.
**Mitigation**: Template sections and skill protocol references must stay in sync. Search the SKILL.md for any quoted section names from the template after modifications.
