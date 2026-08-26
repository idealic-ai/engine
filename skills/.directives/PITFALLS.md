# Pitfalls

Known gotchas and traps when creating or modifying skills. Read before working here.

### Synthesis steps have a strict order — don't rearrange
**Context**: The synthesis phase (final phase of every protocol-tier skill) calls `§CMD_PROCESS_CHECKLISTS` before `§CMD_GENERATE_DEBRIEF`, which calls `§CMD_MANAGE_DIRECTIVES`, then `§CMD_CAPTURE_SIDE_DISCOVERIES`, then `§CMD_REPORT_LEFTOVER_WORK`, then `§CMD_CLOSE_SESSION`. Each step depends on the prior step's output.
**Trap**: Reordering synthesis steps (e.g., generating the debrief before processing checklists) breaks the `¶INV_CHECKLIST_BEFORE_CLOSE` gate — `engine session deactivate` will reject because `checkPassed` is not set. Similarly, managing directives before the debrief means the debrief content isn't available for README/invariant extraction.
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
**Context**: Protocol-tier skills declare a `phases` array in the Phases section. `engine session phase` enforces sequential transitions based on this array.
**Trap**: If you add, remove, or reorder phases in the protocol text but forget to update the phases array (or vice versa), phase enforcement either blocks valid transitions or allows skips. The phase labels in the array must match the headings in the SKILL.md protocol.
**Mitigation**: After any phase change in SKILL.md, diff the phases array against the actual `## N. Phase Name` headings. They must be 1:1.

### New engine features must propagate to all applicable skills
**Context**: `¶INV_SKILL_FEATURE_PROPAGATION` requires that when a new feature is added to one skill, it must be added to all applicable skills or tagged `#needs-implementation`.
**Trap**: Adding a feature (walk-through config, mode presets, interrogation depth, parallel handoff) to one skill and forgetting the rest creates structural debt. The "gold standard" skills diverge from "stale" skills, making it harder to propagate later.
**Mitigation**: After adding a feature to any skill, immediately grep all SKILL.md files for the presence/absence of that feature pattern. Tag missing skills or propagate in the same session.

### Template placeholder names must match the populated content
**Context**: Templates use `[PLACEHOLDER]` patterns that agents populate via `§CMD_WRITE_FROM_TEMPLATE`. The debrief template's structure defines the debrief's structure.
**Trap**: Renaming a section heading in a template without updating the skill protocol (which references specific section names for walk-through configuration or content instructions) creates silent mismatches. The agent writes content that doesn't align with the template structure.
**Mitigation**: Template sections and skill protocol references must stay in sync. Search the SKILL.md for any quoted section names from the template after modifications.

### Asset shell scripts: macOS bash 3.2 crashes on `"${empty_array[@]}"` under `set -u`
**Context**: Skill asset scripts (`assets/*.sh`) often use `set -euo pipefail` and build optional CLI args as arrays (e.g. `cond=()`, `profile_arg=()`). macOS ships **bash 3.2** as `/usr/bin/env bash`; the engine runs there.
**Trap**: In bash 3.2, expanding an *empty* array with `"${arr[@]}"` while `nounset` (`set -u`) is on throws `unbound variable` and aborts the script — silently masking the real work (a conditional PUT never ran, an object "was never created"). Bash 4.4+ does not have this bug, so it passes on Linux/CI and fails only on a Mac.
**Mitigation**: Guard every array expansion with `${arr[@]+"${arr[@]}"}` — expands to nothing when empty instead of crashing. Applies to any optional-args array. Verify with `bash --version` + `bash -c 'set -u; a=(); printf "%s" "${a[@]}"'` (crashes on 3.2).

### ¶PTF_SELF_JUSTIFYING_DUPLICATION
**Context**: Content is sometimes duplicated across two artifacts for a real reason — most often because one consumer cannot reach the other copy (a dispatched sub-agent cannot read a Linear project, so a rule kept only on the project description reaches nobody). The duplication gets written down *with its rationale*, which feels like good practice.
**Trap**: **A duplicate that explains itself stops reading as debt and starts reading as a decision.** Nobody re-examines it, because the note answers the obvious objection in advance — so the copy outlives the condition that justified it and the two halves drift apart unnoticed. A real instance: a handbook section opened *"It lives in both places on purpose: the description is where a human edits it, and this document is what a handoff pastes forward."* Sound when written. It survived the project description going lean, at which point the stated reason no longer existed and the note was actively misleading.
**Mitigation**: When you write a deliberate duplication, record **the condition that would END it**, not just the reason for it — *"drop this copy once X can read Y directly."* A rationale with no exit condition is a permanent copy. Sharper still: prefer moving content to the copy the *machine* reads (agents cannot follow a pointer a human would), and leave the human a link.

### ¶PTF_TIMESTAMP_PROVES_THE_WRITE_NOT_THE_TRUTH
**Context**: Multi-write sessions against a live system (Linear documents, project descriptions, tickets) verify each write by checking that `updatedAt` advanced. It is a good check: it catches silent no-ops, which are real.
**Trap**: `updatedAt` proves **the write landed**. It proves nothing about what the write landed *next to*, and nothing about whether the surrounding document is still **true** after it. A session that edits many related artifacts changes the world those artifacts describe — so a paragraph that was accurate before your change can be false after it, in a document you never opened. Real instance: after retiring five companion docs, all five handbooks still said *"each project also carries its own Vision & Process document"* — a false statement **created** by the session's own correct writes, invisible to every timestamp check that passed.
**Mitigation**: Before closing, **read back at least one artifact you did not author in full** — ideally one you never read before patching. Choose it for blast radius, not convenience. Then ask specifically: *what did my other changes make untrue here?* Prefer `patch`/anchored edits over full-content replaces, so a drifted anchor aborts loudly instead of silently clobbering a section you never saw.

### ¶PTF_INVARIANT_ASSERTS_UNCHECKED_TOOL_CAPABILITY
**Context**: A skill's invariant or step often names a concrete tool capability — a parameter, a field, a naming knob — that it assumes the tool exposes (e.g. "name the agent `<threadId>:<stage>`", "set the agent's label", "pass `--flag`"). It reads as precise and enforceable, so it ships unquestioned.
**Trap**: **The capability may not exist.** The invariant sounds implementable but the tool's actual schema has no such lever — so the rule is dead on arrival, silently unmet, and the first operator to hit it either can't comply or invents a workaround that isn't what the rule said. Real instance: `¶INV_LOOM_AGENTS_NAMED_BY_THREAD` mandated naming spawned agents `<threadId>:<stage>`, but the Agent/Task tool has **no `name` parameter** — only `description`. The rule was unimplementable as written; the fix was to push identity into `description` + prefixed output instead. The invariant *asserted a tool capability that was never checked against the tool*.
**Mitigation**: Before an invariant or step asserts that a tool can do X, **check X against that tool's actual schema** (its parameter list / definition), not against how you imagine the tool works. If the lever doesn't exist, write the rule against a lever that does. When a dogfood run reveals an unimplementable rule, treat it as this class of bug, not a one-off — the same "asserted-not-verified" shape recurs across skills.
