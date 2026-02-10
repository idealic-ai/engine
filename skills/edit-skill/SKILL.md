---
name: edit-skill
description: "Creates, edits, or promotes skills — scaffolds SKILL.md and assets to project-local or shared engine. Triggers: \"create a new skill\", \"edit a skill\", \"scaffold a skill\", \"promote a skill\", \"add a project skill\", \"create a new command\"."
version: 2.0
tier: protocol
---

Creates, edits, or promotes skills — scaffolds SKILL.md and assets to project-local or shared engine.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# Edit Skill Protocol (The Skill Forge)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

## Subcommands

| Command | Action |
|---------|--------|
| `/edit-skill <name>` | Create or edit a skill (default flow) |
| `/edit-skill promote <name>` | Promote project-local skill to shared engine |

**Routing**: Parse the arguments to determine the flow:
- If first argument is `promote`: Jump to **Promote Flow** (after Phase 0 setup).
- Otherwise: Continue with **Create/Edit Flow** (Phases 0-5).

### Session Parameters (for §CMD_PARSE_PARAMETERS)
*Merge into the JSON passed to `session.sh activate`:*
```json
{
  "taskType": "EDIT_SKILL",
  "phases": [
    {"major": 0, "minor": 0, "name": "Setup", "proof": ["mode", "templates_loaded", "parameters_parsed"]},
    {"major": 1, "minor": 0, "name": "Detection", "proof": ["detection_mode", "target_location"]},
    {"major": 2, "minor": 0, "name": "Context Ingestion", "proof": ["context_sources_presented"]},
    {"major": 3, "minor": 0, "name": "Interrogation", "proof": ["depth_chosen", "rounds_completed"]},
    {"major": 4, "minor": 0, "name": "Scaffold", "proof": ["plan_presented", "log_entries"]},
    {"major": 5, "minor": 0, "name": "Synthesis"},
    {"major": 5, "minor": 1, "name": "Checklists", "proof": ["§CMD_PROCESS_CHECKLISTS"]},
    {"major": 5, "minor": 2, "name": "Debrief", "proof": ["§CMD_GENERATE_DEBRIEF_file", "§CMD_GENERATE_DEBRIEF_tags"]},
    {"major": 5, "minor": 3, "name": "Pipeline", "proof": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"]},
    {"major": 5, "minor": 4, "name": "Close", "proof": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY"]}
  ],
  "nextSkills": ["/edit-skill", "/implement", "/analyze", "/chores"],
  "directives": [],
  "logTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md",
  "debriefTemplate": "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md"
}
```

---

## 0. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 0: Setup phase.
    > 2. My focus is EDIT_SKILL (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all standards are loaded.
    > 4. I will `§CMD_ASSUME_ROLE`:
    >    **Role**: You are the **Skill Architect**.
    >    **Goal**: To scaffold or modify skills that follow engine conventions exactly, in the right location.
    >    **Mindset**: Every skill is a protocol. Sloppy skills produce sloppy sessions. Location matters — shared means permanent.
    > 5. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:

    **Reference Examples — Load ALL of these to build by example:**

    *Entry points (SKILL.md files — read all to see the v2 inline pattern):*
    *   `~/.claude/skills/implement/SKILL.md` (full-session archetype)
    *   `~/.claude/skills/brainstorm/SKILL.md` (light-session archetype)
    *   `~/.claude/skills/suggest/SKILL.md` (report-only archetype)
    *   `~/.claude/skills/dehydrate/SKILL.md` (utility archetype)

    **Constraint**: You MUST load all the files listed above before proceeding. These are your exemplars — every file you scaffold must follow the patterns found in these references.

3.  **Parse Arguments**: Extract the skill name and subcommand from the user's input.
    *   **Input**: `/edit-skill [promote] <skill-name> [additional context]`
    *   **Normalize**: Convert to kebab-case if not already (e.g., `mySkill` → `my-skill`).
    *   **Derive**: `PROTOCOL_NAME` = uppercase + underscores (e.g., `my-skill` → `MY_SKILL`).
    *   **Route**: If first argument is `promote`, jump to **Promote Flow** after displaying parsed names.
    *   **Output**: Display the parsed names:
        > **Skill**: `<skill-name>`
        > **Protocol**: `<PROTOCOL_NAME>`
        > **Subcommand**: `create/edit` or `promote`

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Detection Phase
*Determine whether this is a CREATE or EDIT operation, and where the skill should live.*

1.  **Check project-local**: Does `.claude/skills/<skill-name>/SKILL.md` exist?
2.  **Check shared engine**: Does `~/.claude/engine/skills/<skill-name>/SKILL.md` exist?
    *   Also check if `~/.claude/skills/<skill-name>` is a symlink (indicates shared skill).
3.  **Route by result**:

    | Project-local | Shared engine | Mode | Description |
    |:---:|:---:|---|---|
    | No | No | **CREATE** | New skill — ask where to put it |
    | Yes | No | **EDIT (local)** | Edit existing project-local skill |
    | No | Yes | **EDIT (shared)** | Create local override for safety, offer promote later |
    | Yes | Yes | **EDIT (local override)** | Local override exists — edit the local version |

4.  **For CREATE mode — ask location**:

    Execute `AskUserQuestion` (multiSelect: false):
    > "Where should this skill live?"
    > - **"Project-local (.claude/skills/)" (Recommended)** — Skill specific to this project, can promote to shared later
    > - **"Shared engine (~/.claude/engine/skills/)"** — Available across all projects immediately

    Record the choice as `targetLocation`: `"project"` or `"shared"`.

5.  **For EDIT (shared) mode**: Announce that a local override will be created for safety:
    > "Found shared engine skill at `~/.claude/skills/<name>/`. I will create a local override in `.claude/skills/` for safe editing. Use `/edit-skill promote <name>` to push changes back to the engine."

    Set `targetLocation`: `"project"` (always local for edits of shared skills).

6.  **For EDIT (local) and EDIT (local override)**: Set `targetLocation`: `"project"`.

7.  **Announce Mode**:
    *   *Create (project)*: "**Create Mode** — Scaffolding new skill in `.claude/skills/<name>/`."
    *   *Create (shared)*: "**Create Mode** — Scaffolding new skill in `~/.claude/engine/skills/<name>/` (+ symlink)."
    *   *Edit (local)*: "**Edit Mode** — Found local skill at `.claude/skills/<name>/`."
    *   *Edit (shared → local override)*: "**Edit Mode** — Creating local override of shared skill."
    *   *Edit (local override)*: "**Edit Mode** — Found local override at `.claude/skills/<name>/`."

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 2. Context Ingestion

### If EDIT MODE:
1.  **Read** the existing SKILL.md entry point (from the source — project-local or shared engine).
2.  **Read** any associated asset files (check the skill's `assets/` directory for templates).
3.  **Summarize** to the user: Brief description of what the skill does, its phases, what templates it uses. Do NOT dump the full content.
4.  **Proceed** to Phase 3 (Interrogation).

### If CREATE MODE:
*   No files to read. Proceed directly to Phase 3 (Interrogation).

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`.

---

## 3. Interrogation
*Gather requirements through structured questioning.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 3: Interrogation.
> 2. I will `§CMD_EXECUTE_INTERROGATION_PROTOCOL` to gather skill requirements.
> 3. I will `§CMD_LOG_TO_DETAILS` to capture the Q&A.

**Action**: First, ask the user to choose interrogation depth. Then execute rounds.

### Interrogation Depth Selection

**Before asking any questions**, present this choice via `AskUserQuestion` (multiSelect: false):

> "How deep should the skill design interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Simple utility skill, clear requirements, small scope |
| **Medium** | 5+ | Multi-phase skill, some design decisions, moderate complexity |
| **Long** | 8+ | Complex protocol, many phases, integration-heavy, architectural skill |
| **Absolute** | Until ALL questions resolved | Novel pattern, critical workflow, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

**CREATE mode**: 3 rounds minimum regardless of depth choice.
**EDIT mode**: 2 rounds minimum regardless of depth choice.

### Interrogation Protocol (Rounds)

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth. Track your round count visibly.

**Round counter**: Output it on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the topic menu below each round. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

### Interrogation Topics (Skill Design)

**Standard topics** (typically covered once):
- **Skill purpose** — what the skill does, why it exists, what gap it fills
- **Phase structure** — what phases are needed, what order, what each does
- **Template needs** — what session artifacts to generate, what sections they need
- **Integration points** — what §CMD_ commands to reference, what other skills it interacts with
- **Testing approach** — how to verify the skill works, what a good run looks like
- **Archetype selection** — full-session, light-session, report-only, or utility

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1. Pick an uncovered topic (or a repeatable topic).
2. Execute `§CMD_ASK_ROUND_OF_QUESTIONS` via `AskUserQuestion` (3-5 targeted questions on that topic).
3. On response: Execute `§CMD_LOG_TO_DETAILS` immediately.
4. If the user asks a counter-question: ANSWER it, verify understanding, then resume.

### Interrogation Exit Gate

**After reaching minimum rounds**, present this choice via `AskUserQuestion` (multiSelect: true):

> "Round N complete (minimum met). What next?"
> - **"Proceed to Phase 4: Scaffold"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → Deep dive → re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions.

---

## 4. Scaffold / Rewrite
*Generate the v2 inline SKILL.md into the target location.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Scaffold.
> 2. I will generate skill files into the target location determined in Phase 1.
> 3. I will `§CMD_REPORT_FILE_CREATION_SILENTLY` for each file.

### Target Path Resolution

Based on `targetLocation` from Phase 1:

| Target | Skill files go to | Symlink action |
|--------|-------------------|----------------|
| `project` | `.claude/skills/<name>/` | None |
| `shared` | `~/.claude/engine/skills/<name>/` | Create symlink: `~/.claude/skills/<name>` → `~/.claude/engine/skills/<name>/` |

**For shared target**: After writing files to engine:

1.  **Remove local project copy** (if it exists) to prevent duplication:
    ```bash
    # Only if .claude/skills/<name>/ is a real directory (not already a symlink)
    [ -d .claude/skills/<name> ] && [ ! -L .claude/skills/<name> ] && rm -rf .claude/skills/<name>/
    ```
2.  **Create symlink**:
    ```bash
    ln -s ~/.claude/engine/skills/<name> ~/.claude/skills/<name>
    ```
3.  **Verify** symlink resolves: `ls -la ~/.claude/skills/<name>/SKILL.md`

### Step A: Skill File (SKILL.md) — v2 Inline Format

**Destination**: `[target_path]/<skill-name>/SKILL.md`

**CRITICAL**: The v2 format puts the entire protocol INLINE in SKILL.md. There is NO separate `references/` protocol file. The protocol goes directly into SKILL.md after the boot sequence.

**Template**:
```markdown
---
name: <skill-name>
description: "[One-line description]. Triggers: \"[trigger 1]\", \"[trigger 2]\", \"[trigger 3]\"."
version: 2.0
tier: protocol
---

[One-line description].
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

# [Protocol Title]

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases.

[Full inline protocol with phases, Phase Transition with AskUserQuestion after every phase except the last, --- between phases]
```

Generate the phased protocol following the engine pattern. Include these phases based on the archetype:

| Phase | Full-session | Light-session | Report-only | Utility |
|-------|-------------|---------------|-------------|---------|
| 0. Setup | yes | yes | yes | yes |
| 1. Context Ingestion | if needed | if needed | if needed | if needed |
| 2. Interrogation | if needed | if needed | no | no |
| 3. Planning | yes | no | no | no |
| 4. Work Loop | yes | yes | yes | yes |
| 5. Synthesis | yes | yes | yes | no |

Each phase MUST reference appropriate §CMD_ commands:
*   Setup → `§CMD_LOAD_AUTHORITY_FILES`, `§CMD_ASSUME_ROLE`, `§CMD_MAINTAIN_SESSION_DIR`, `§CMD_PARSE_PARAMETERS`
*   Context Ingestion → `§CMD_INGEST_CONTEXT_BEFORE_WORK`
*   Interrogation → `§CMD_EXECUTE_INTERROGATION_PROTOCOL`, `§CMD_LOG_TO_DETAILS`
*   Planning → `§CMD_POPULATE_LOADED_TEMPLATE` (using plan template)
*   Work Loop → `§CMD_THINK_IN_LOG`, `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`, `§CMD_REFUSE_OFF_COURSE`
*   Synthesis → `§CMD_FOLLOW_DEBRIEF_PROTOCOL`

**v2 Structural Requirements**:
*   `### Phase Transition` with `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH` after every phase except the last.
*   `---` between phases.
*   Final phase uses `§CMD_FOLLOW_DEBRIEF_PROTOCOL` for synthesis.
*   Skills with interrogation get: depth selection table, round counter, custom topics (standard + repeatable), exit gate.

**DETAILS.md integration (automatic for non-utility archetypes)**:
Any skill that has an Interrogation phase or interactive dialogue MUST include DETAILS.md logging.

**Question Bank (if requested during interrogation)**:
If the user requested an angles-of-view checklist, generate a `### The Question Bank` section in the protocol's work/strategy phase.

### Step B: Template Files (Conditional)
Generate templates based on archetype. Follow engine template conventions.

**If archetype has logging** (`full-session`, `light-session`):
*   **Destination**: `[target_path]/<skill-name>/assets/TEMPLATE_<NAME>_LOG.md`

**If archetype has planning** (`full-session` only):
*   **Destination**: `[target_path]/<skill-name>/assets/TEMPLATE_<NAME>_PLAN.md`

**If archetype has debrief/report** (`full-session`, `light-session`, `report-only`):
*   **Destination**: `[target_path]/<skill-name>/assets/TEMPLATE_<NAME>.md`

### Step C: Report
Execute `§CMD_REPORT_FILE_CREATION_SILENTLY` for each file created.

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  custom: "Revise the scaffold | Go back and edit generated files"

---

## 5. Synthesis

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Synthesis.
> 2. I will execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL` to process checklists, write the debrief, run the pipeline, and close.

**STOP**: Do not create artifacts yet. You must output the block above first.

**2. Execute `§CMD_FOLLOW_DEBRIEF_PROTOCOL`**

**Debrief creation notes** (for Step 1 -- `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`):
*   Dest: `EDIT_SKILL.md`
*   Include: skill name, mode (create/edit), target location, files generated, archetype used.

**Walk-through config** (for Step 3 -- `§CMD_WALK_THROUGH_RESULTS`):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Skill scaffolded. Walk through the generated files?"
  debriefFile: "EDIT_SKILL.md"
  templateFile: "~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION.md"
```

**Post-scaffold suggestion**:
- If project-local: "You can now use `/<skill-name>` in this project. To share it across projects, run `/edit-skill promote <skill-name>`."
- If shared: "You can now use `/<skill-name>` in any project."

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.

---
---

# Promote Flow

*Promotes a project-local skill to the shared engine.*

**Entry**: Invoked via `/edit-skill promote <name>`. Starts after Phase 0 setup.

## P1. Inventory
*Identify all files that belong to this skill.*

1.  **Scan project-local files**: Check `.claude/skills/<name>/` for:
    *   `SKILL.md` — The skill file
    *   `assets/TEMPLATE_*.md` — Templates
    *   `assets/*` — Other assets (configs, etc.)
    *   `modes/*.md` — Mode definitions

2.  **Build file manifest**: List which files exist locally.
    *   *If no local files found*: STOP. Report "No local skill found for `<name>`. Nothing to promote."

3.  **Scan engine counterparts**: For each local file, check if an engine counterpart exists at `~/.claude/engine/skills/<name>/`.

4.  **Display manifest**:
    ```
    File Manifest for `<name>`:

    | File | Local | Engine | Action |
    |------|-------|--------|--------|
    | SKILL.md | ✅ | ✅/❌ | New / Overwrite |
    | assets/TEMPLATE_*.md | ✅/❌ | ✅/❌ | New / Overwrite / Skip |
    ```

---

## P2. Diff (Conditional)
*For files that will OVERWRITE existing engine files, produce a structural comparison.*

**Constraint**: Only diff files where both local and engine versions exist (Action = "Overwrite"). Skip files where the action is "New".

For each file being overwritten:

1.  **Read** both the local version and the engine version.
2.  **Structural comparison**:
    *   **For SKILL.md**: Compare frontmatter (description, version). Compare phase structure. Report added/removed/reordered phases. Report changed roles, mindsets, or §CMD_ references.
    *   **For templates**: Compare section headers (H2/H3). Report added/removed sections.
3.  **Output** a summary per file.

*If NO files are being overwritten (all "New")*: Skip this phase entirely and note "All files are new — no overwrites."

---

## P3. Confirmation Gate
*The user MUST explicitly approve before any files are copied.*

**Display the full action summary**:
```
PROMOTE CONFIRMATION

Skill:  <name>
Source: .claude/skills/<name>/
Target: ~/.claude/engine/skills/<name>/

Files to COPY (new): [list]
Files to OVERWRITE: [list] (see diff above)

After promote:
  - Local .claude/skills/<name>/ will be DELETED
  - Symlink created: ~/.claude/skills/<name> → ~/.claude/engine/skills/<name>/
```

Execute `AskUserQuestion` (multiSelect: false):
> "Proceed with promoting `<name>` to the shared engine?"
> - **"Yes, promote it"** — Copy files, delete local, create symlink
> - **"No, abort"** — Cancel the promotion

*If user aborts*: Report "Promote cancelled. No files were modified." and END.

---

## P4. Execute Promotion
*Copy files, delete local, create symlink.*

1.  **Create engine directories** if needed:
    ```bash
    mkdir -p ~/.claude/engine/skills/<name>/assets
    mkdir -p ~/.claude/engine/skills/<name>/modes
    ```

2.  **Copy each file** from `.claude/skills/<name>/` to `~/.claude/engine/skills/<name>/`.

3.  **Verify** each copy succeeded.

4.  **Delete project-local directory**:
    ```bash
    rm -rf .claude/skills/<name>/
    ```

5.  **Create symlink**:
    ```bash
    ln -s ~/.claude/engine/skills/<name> ~/.claude/skills/<name>
    ```

6.  **Verify symlink** resolves correctly:
    ```bash
    ls -la ~/.claude/skills/<name>/SKILL.md
    ```

7.  **Report**: Execute `§CMD_REPORT_FILE_CREATION_SILENTLY` for each file.

Execute `§CMD_REPORT_RESULTING_ARTIFACTS`.
Execute `§CMD_REPORT_SESSION_SUMMARY`.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
