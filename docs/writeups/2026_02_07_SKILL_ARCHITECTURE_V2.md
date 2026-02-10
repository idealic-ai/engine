# Writeup: Skill Architecture v2 — Inline Protocols, Phase Gating, and Tiered Interrogation

*Created: 2026-02-07*

## Problem

The workflow engine's skill system has three architectural issues that compound into real cost:

**1. Two-file indirection wastes tokens and adds latency.**

Every skill invocation follows the same path: Claude reads `SKILL.md`, sees a 4-line boot sequence that says "go read `references/IMPLEMENT.md`", then makes a second read call to load the actual protocol. This costs ~500 tokens for the boot sequence read + one tool call round-trip, multiplied by every skill invocation across every agent in the fleet. For a 6-pane fleet running 10 skill invocations per day, that's 60 wasted read calls daily.

The boot sequence itself is also redundant. It tells the agent to load `COMMANDS.md` and `INVARIANTS.md`, but these are already standard practice in Phase 1 of every protocol. The boot sequence duplicates instructions that exist in the protocol it points to.

**2. Phases have no verifiable exit criteria.**

Protocols define phases (Setup, Context Ingestion, Interrogation, Planning, Execution, Synthesis) with narrative descriptions and `STOP` markers, but there's no machine-checkable verification that a phase was actually completed. An agent can skip from Phase 1 to Phase 5 without any structural guard catching it. The `STOP` markers are advisory — they work when the agent is disciplined, but degrade under context pressure or when the agent is eager to "get to the code."

This manifests as:
- Interrogation phases with zero questions asked
- Synthesis phases that output a chat message but never write the debrief file
- Planning phases that produce a plan but never get user confirmation

**3. Interrogation is underspecified and inconsistent.**

The original interrogation design says "minimum 3 rounds" with vague topic guidance. In practice:
- Agents interpret "3 rounds" as "ask 3 quick questions and move on"
- Topic selection is ad-hoc — agents ask whatever comes to mind
- There's no user control over interrogation depth
- Skills use different interrogation structures (some have topic lists, some don't)
- A 2-file change and a full architecture redesign get the same interrogation treatment

The result is a mismatch between task complexity and preparation depth.

## Context

The engine has grown to 29 skills with a consistent but limited architecture:

```
~/.claude/skills/<name>/
├── SKILL.md              # Frontmatter + boot sequence (4 lines)
├── references/<NAME>.md  # Actual protocol (50-300 lines)
└── assets/               # Templates (TEMPLATE_*.md)
```

Skills fall into four archetypes:
- **Full-session** (implement, debug, test, analyze): 5-7 phases, planning, build loops, debriefs
- **Light-session** (brainstorm, critique, refine, review): 3-5 phases, dialogue-driven
- **Report-only** (suggest, writeup, document): 2-4 phases, single output artifact
- **Utility** (delegate, dispatch, dehydrate, alerts): 1-3 phases, no session directory

The `IMPLEMENT_DRAFT.md` (created during a fleet session analysis) prototyped three solutions: phase exit verification checkboxes, interrogation depth tiers, and structured topic menus. These changes were validated against the implement skill and are ready to port across the system.

### What worked before

The original architecture was appropriate for a smaller system. When there were 5 skills, the boot sequence provided a clear separation of concerns: `SKILL.md` was the "what" (discovery metadata) and `references/*.md` was the "how" (execution protocol). The two-file split also made it easy to edit protocols without accidentally breaking the frontmatter that Claude Code uses for skill discovery.

### What changed

The system scaled to 29 skills. The boot sequence became pure overhead — every skill has the same 4 lines. The `references/` directory added filesystem complexity without meaningful organizational benefit. And the lack of verification became visible when agents started running in parallel fleets, where skipped phases in one agent could cascade into incorrect assumptions in another.

## Related

- Plan: `/Users/invizko/.claude/plans/fancy-herding-quokka.md` — The approved implementation plan for this migration
- Draft: `IMPLEMENT_DRAFT.md` (fleet session) — Prototype of gating + interrogation changes for the implement skill
- COMMANDS.md `§CMD_HAND_OFF_TO_AGENT` — References `parentPromptFile` paths that will change
- INVARIANTS.md `¶INV_SKILL_PROTOCOL_MANDATORY` — References `references/*.md` pattern
- `edit-skill` protocol — Scaffolds new skills using the old two-file pattern
- `reanchor` protocol — Loads skill protocols by constructing `references/` paths
- `share-skill` protocol — Copies skill files including `references/` directory

## Options

### Option A: Inline Protocols (Merge references/ into SKILL.md)

Eliminate the `references/` directory entirely. The protocol becomes the body of `SKILL.md`, directly after the frontmatter.

**New structure:**
```
~/.claude/skills/<name>/
├── SKILL.md       # Frontmatter + full inline protocol
└── assets/        # Templates (unchanged)
```

**Pros:**
- One read call per skill invocation (saves ~500 tokens + 1 round-trip per invocation)
- Simpler mental model: SKILL.md IS the skill
- No indirection — what you see is what executes
- Easier to diff, review, and version

**Cons:**
- SKILL.md files become longer (50-300 lines instead of 4)
- Frontmatter and protocol are now co-located — accidental frontmatter edits during protocol changes
- `edit-skill`, `share-skill`, and `reanchor` all need path updates

**Risk:** Low. The frontmatter block (`---` delimited) is structurally distinct from the protocol body. Accidental corruption is unlikely.

### Option B: Keep Two-File, Add Gating Only

Keep `references/*.md` as-is but add phase exit verification and interrogation improvements to the protocol files.

**Pros:**
- Smaller change surface — only protocol content changes, not file structure
- No downstream path updates needed

**Cons:**
- Perpetuates the token waste
- Two files to maintain per skill (60 files total instead of 30)
- Boot sequence remains redundant

### Option C: Compile-Time Merge (Build Step)

Keep source files separate but add a build step that concatenates `SKILL.md` + `references/*.md` into a single output file.

**Pros:**
- Clean source separation during editing
- Single file at runtime

**Cons:**
- Adds build tooling to a system that currently has none
- Another thing that can break
- Overkill for markdown concatenation

## Recommendation

**Option A: Inline Protocols** — with the following philosophy:

### The Philosophical Shift

The v1 skill architecture was designed around **separation of concerns** — metadata in one file, behavior in another. This mirrors software patterns like interface/implementation splits or header/source files.

The v2 architecture shifts to **single source of truth per skill**. A skill is one document. Reading it gives you everything: what it is (frontmatter), what it does (protocol), and how to verify it worked (phase exit checklists). This mirrors the shift in software from scattered config files to colocated, self-describing modules.

Three principles drive the v2 changes:

**1. Protocols should be self-verifying.**

Phase exit checkboxes (`§CMD_VERIFY_PHASE_EXIT`) turn advisory `STOP` markers into structural checklists. Each phase ends with a verification block:

```
### §CMD_VERIFY_PHASE_EXIT — Phase 3
□ Interrogation depth chosen by user
□ Minimum rounds for chosen depth completed
□ Each round logged to DETAILS.md
□ User explicitly said to proceed
```

The agent checks these boxes before transitioning. If a box is unchecked, the phase isn't complete. This is not enforcement (the agent can still skip), but it's **visible accountability** — the checklist makes skipping a conscious choice rather than an oversight.

The Phase 6 "Roll Call" takes this further by requiring the agent to output verification in chat:

```
> Phase 6 Roll Call:
> - Debrief: sessions/2026_02_07_TOPIC/IMPLEMENTATION.md (real file path)
> - Artifacts: 5 files listed
> - Summary: done
```

This creates a **proof of work** — the user can verify completion without reading the session directory.

**2. Interrogation depth should match task complexity.**

The tiered depth system replaces "minimum 3 rounds" with user-controlled rigor:

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| Short | 3+ | Well-understood, small scope |
| Medium | 6+ | Moderate complexity, some unknowns |
| Long | 9+ | Complex system changes, many unknowns |
| Absolute | Until zero questions remain | Novel domain, critical system |

The user picks the tier. The agent tracks rounds visibly ("Round 4 / 6+"). This gives the user a knob: turn it down for routine work, crank it up for risky changes.

Each skill gets custom interrogation topics tailored to its domain. Implementation asks about data flow and testing strategy. Debug asks about reproduction steps and rollback options. Research asks about source quality and output format. This prevents the "generic questions about nothing" failure mode.

**3. Every token spent on infrastructure should earn its keep.**

The boot sequence costs tokens and adds nothing. The `references/` indirection costs a tool call and adds nothing. The inline architecture eliminates both. A skill invocation goes from:

```
Read SKILL.md (boot sequence) → Read references/X.md (protocol) → Execute
```

to:

```
Read SKILL.md (protocol) → Execute
```

This is not about saving money — it's about **cognitive overhead**. Every indirection is a place where the agent can lose context, misinterpret instructions, or waste attention. Fewer hops = fewer failure modes.

## Next Steps

- [ ] Port IMPLEMENT_DRAFT.md into `implement/SKILL.md` (merge frontmatter + inline protocol)
- [ ] Add phase exit verification to all 29 skills
- [ ] Add interrogation depth selection + custom topics to all 13 skills with interrogation phases
- [ ] Merge all `references/*.md` into their parent `SKILL.md` files
- [ ] Update downstream references: COMMANDS.md, INVARIANTS.md, README.md, reanchor, edit-skill, share-skill
- [ ] Set up symlinks from `~/.claude/skills/` to Google Drive
- [ ] Delete empty `references/` directories
