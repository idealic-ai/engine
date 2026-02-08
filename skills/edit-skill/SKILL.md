---
name: edit-skill
description: "Creates or edits skills in .claude/ — scaffolds SKILL.md, references, and assets. Triggers: \"create a new skill\", \"edit a skill\", \"scaffold a skill\", \"add a project skill\", \"create a new command\"."
version: 2.0
tier: lightweight
---

Creates or edits skills in .claude/ — scaffolds SKILL.md, references, and assets.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# Edit Skill Protocol (The Skill Forge)

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

## 1. Setup Phase

1.  **Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
    > 1. I am starting Phase 1: Setup phase.
    > 2. My focus is EDIT_SKILL (`§CMD_REFUSE_OFF_COURSE` applies).
    > 3. I will `§CMD_LOAD_AUTHORITY_FILES` to ensure all standards are loaded.
    > 4. I will `§CMD_ASSUME_ROLE` to execute better:
    >    **Role**: You are the **Skill Architect**.
    >    **Goal**: To scaffold or modify a project-specific skill that follows engine conventions exactly.
    >    **Mindset**: Every skill is a protocol. Sloppy skills produce sloppy sessions.
    > 5. I will obey `§CMD_NO_MICRO_NARRATION` and `¶INV_CONCISE_CHAT` (Silence Protocol).

2.  **Required Context**: Execute `§CMD_LOAD_AUTHORITY_FILES` (multi-read) for the following files:

    **Reference Examples — Load ALL of these to build by example:**

    *Entry points (SKILL.md files — read all to see the v2 inline pattern):*
    *   `~/.claude/skills/implement/SKILL.md` (full-session archetype)
    *   `~/.claude/skills/brainstorm/SKILL.md` (light-session archetype)
    *   `~/.claude/skills/critique/SKILL.md` (report-only archetype)
    *   `~/.claude/skills/dehydrate/SKILL.md` (utility archetype)

    **Constraint**: You MUST load all the files listed above before proceeding. These are your exemplars — every file you scaffold must follow the patterns found in these references.

3.  **Parse Arguments**: Extract the skill name from the user's input.
    *   **Input**: `/edit-skill <skill-name> [additional context]`
    *   **Normalize**: Convert to kebab-case if not already (e.g., `mySkill` → `my-skill`).
    *   **Derive**: `PROTOCOL_NAME` = uppercase + underscores (e.g., `my-skill` → `MY_SKILL`).
    *   **Output**: Display the parsed names:
        > **Skill**: `<skill-name>`
        > **Protocol**: `<PROTOCOL_NAME>`

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Role: `________`
> - Reference skills loaded: `________`, `________`, `________`, `________`
> - Skill name: `________`
> - Protocol name: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 1: Setup complete. How to proceed?"
> - **"Proceed to Phase 2: Detection"** — Determine CREATE vs EDIT mode
> - **"Stay in Phase 1"** — Load additional references or resolve setup issues

---

## 2. Detection Phase
*Determine whether this is a CREATE or EDIT operation.*

1.  **Check project-local**: Does `.claude/skills/<skill-name>/SKILL.md` exist?
    *   *If Yes*: **EDIT MODE** (local override already exists).
2.  **Check shared engine**: Does `~/.claude/skills/<skill-name>/SKILL.md` exist?
    *   *If Yes*: **EDIT MODE** (will create local override of shared skill).
3.  **Neither exists**: **CREATE MODE**.

4.  **Announce Mode**:
    *   *Create*: "**Create Mode** — No existing skill found. I will scaffold a new skill."
    *   *Edit (local)*: "**Edit Mode** — Found local skill at `.claude/skills/<name>/`. I will read it and ask what you want to change."
    *   *Edit (shared)*: "**Edit Mode** — Found shared engine skill at `~/.claude/skills/<name>/`. I will read it and create a local override in `.claude/skills/`."

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Project-local path: `________`
> - Shared engine path: `________`
> - Mode: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 2: Detection complete — [CREATE/EDIT] mode. How to proceed?"
> - **"Proceed to Phase 3: Context Ingestion"** — Read existing skill files (EDIT) or skip to interrogation (CREATE)
> - **"Stay in Phase 2"** — Re-check or clarify the target skill

---

## 3. Context Ingestion

### If EDIT MODE:
1.  **Read** the existing SKILL.md entry point (`.claude/skills/<name>/SKILL.md` or `~/.claude/skills/<name>/SKILL.md`).
2.  **Read** any associated asset files (check the skill's `assets/` directory for templates).
3.  **Summarize** to the user: Brief description of what the skill does, its phases, what templates it uses. Do NOT dump the full content.
4.  **Proceed** to Phase 4 (Interrogation).

### If CREATE MODE:
*   No files to read. Proceed directly to Phase 4 (Interrogation).

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - SKILL.md read/summarized: `________`
> - Assets directory checked: `________`
> - Summary presented: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 3: Context ingestion complete. How to proceed?"
> - **"Proceed to Phase 4: Interrogation"** — Gather requirements through structured questioning
> - **"Stay in Phase 3"** — Load additional context files

---

## 4. Interrogation
*Gather requirements through structured questioning.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 4: Interrogation.
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
*Examples of themes to explore. Adapt to the task — skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Skill purpose** — what the skill does, why it exists, what gap it fills
- **Phase structure** — what phases are needed, what order, what each does
- **Template needs** — what session artifacts to generate, what sections they need
- **Integration points** — what §CMD_ commands to reference, what other skills it interacts with
- **Testing approach** — how to verify the skill works, what a good run looks like

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
> - **"Proceed to Phase 5: Scaffold"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears
> - **"Deep dive round"** — 1 round drilling into a prior topic, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first -> Devil's advocate -> What-ifs -> Deep dive -> re-present exit gate.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Ask: "Round N complete. I still have questions about [X]. Continuing..."

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Depth chosen: `________`
> - Rounds completed: `________` / `________`+
> - DETAILS.md entries: `________`
> - User proceeded: `________`

---

## 5. Scaffold / Rewrite
*Generate the v2 inline SKILL.md into the project's `.claude/skills/` directory.*

**Intent**: Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 5: Scaffold.
> 2. I will generate skill files into `.claude/skills/<skill-name>/` (project-local).
> 3. I will `§CMD_REPORT_FILE_CREATION_SILENTLY` for each file.

### Step A: Skill File (SKILL.md) — v2 Inline Format

**Destination**: `.claude/skills/<skill-name>/SKILL.md`

**CRITICAL**: The v2 format puts the entire protocol INLINE in SKILL.md. There is NO separate `references/` protocol file. The protocol goes directly into SKILL.md after the boot sequence and gate check.

**Template**:
```markdown
---
name: <skill-name>
description: [One-line description from interrogation]. Triggers: "[trigger phrase 1]", "[trigger phrase 2]", "[trigger phrase 3]".
version: 2.0
tier: lightweight
---

[One-line description from interrogation].
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

# [Protocol Title]

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. The engine's artifacts live in the session directory as reviewable files, not in transient tool state. Use THIS protocol's phases, not the IDE's.

[Full inline protocol with phases, §CMD_VERIFY_PHASE_EXIT after every phase, Phase Transition with AskUserQuestion after every phase except the last, --- between phases, PROOF OF WORK roll call on the final phase]
```

Generate the phased protocol following the engine pattern. Include these phases based on the archetype:

| Phase | Full-session | Light-session | Report-only | Utility |
|-------|-------------|---------------|-------------|---------|
| 1. Setup | yes | yes | yes | yes |
| 2. Context Ingestion | if needed | if needed | if needed | if needed |
| 3. Interrogation | if needed | if needed | no | no |
| 4. Planning | yes | no | no | no |
| 5. Work Loop | yes | yes | yes | yes |
| 6. Synthesis | yes | yes | yes | no |

Each phase MUST reference appropriate §CMD_ commands:
*   Setup -> `§CMD_LOAD_AUTHORITY_FILES`, `§CMD_ASSUME_ROLE`, `§CMD_MAINTAIN_SESSION_DIR`, `§CMD_PARSE_PARAMETERS`
*   Context Ingestion -> `§CMD_INGEST_CONTEXT_BEFORE_WORK`
*   Interrogation -> `§CMD_EXECUTE_INTERROGATION_PROTOCOL`, `§CMD_LOG_TO_DETAILS`
*   Planning -> `§CMD_POPULATE_LOADED_TEMPLATE` (using plan template)
*   Work Loop -> `§CMD_THINK_IN_LOG`, `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE`, `§CMD_REFUSE_OFF_COURSE`
*   Synthesis -> `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`, `§CMD_REPORT_RESULTING_ARTIFACTS`, `§CMD_REPORT_SESSION_SUMMARY`

**DETAILS.md integration (automatic for non-utility archetypes)**:
Any skill that has an Interrogation phase or interactive dialogue MUST include DETAILS.md logging. This is not optional — if the user talks, we record it.
*   Add `§CMD_LOG_TO_DETAILS` calls after every interrogation round and user assertion.
*   Reference `~/.claude/directives/TEMPLATE_DETAILS.md` as structural model.
*   Only **utility** skills (no session artifacts, no interaction) skip this.

**Question Bank (if requested during interrogation)**:
If the user requested an angles-of-view checklist, generate a `### The Question Bank` section in the protocol's work/strategy phase. Structure it as:
```markdown
### The Question Bank ([N] Questions for [Domain])
**[Perspective 1]**
1.  "Question from this angle..."
2.  "Question from this angle..."

**[Perspective 2]**
3.  "Question from this angle..."
4.  "Question from this angle..."
```
*   Use the perspectives the user specified during interrogation.
*   Write 3-5 questions per perspective.
*   Questions should be concrete and domain-specific, not generic.
*   The Question Bank goes in the **work phase** — whichever phase is where the agent needs to think broadly before acting.

**v2 Structural Requirements**:
*   `§CMD_VERIFY_PHASE_EXIT` after EVERY phase.
*   `### Phase Transition` with `AskUserQuestion` after every phase except the last.
*   `---` between phases.
*   Final phase gets PROOF OF WORK roll call.
*   Skills with interrogation get: depth selection table, round counter, custom topics (standard + repeatable), exit gate.

### Step B: Template Files (Conditional)
Generate templates based on archetype. Follow engine template conventions.

**If archetype has logging** (`full-session`, `light-session`):
*   **Destination**: `.claude/skills/<skill-name>/assets/TEMPLATE_<NAME>_LOG.md`
*   **Content**: Log schema with thought triggers appropriate to the skill's work loop.

**If archetype has planning** (`full-session` only):
*   **Destination**: `.claude/skills/<skill-name>/assets/TEMPLATE_<NAME>_PLAN.md`
*   **Content**: Plan template with sections relevant to the skill's domain.

**If archetype has debrief/report** (`full-session`, `light-session`, `report-only`):
*   **Destination**: `.claude/skills/<skill-name>/assets/TEMPLATE_<NAME>.md`
*   **Content**: Debrief/report template. Must include `**Tags**: #needs-review` line after H1.

### Step C: Report
Execute `§CMD_REPORT_FILE_CREATION_SILENTLY` for each file created.

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - SKILL.md written (v2 inline): `________`
> - Template files created: `________`
> - Phase exits included: `________`
> - Phase transitions included: `________`
> - PROOF OF WORK on final phase: `________`
> - Files reported: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 5: Scaffold complete. How to proceed?"
> - **"Proceed to Phase 6: Registration"** — Update the project skill index
> - **"Revise the scaffold"** — Go back and edit generated files
> - **"Skip to Phase 7: Synthesis"** — Registration not needed

---

## 6. Registration
*Update the project's local skill index.*

1.  **Check**: Does `.claude/skills/README.md` exist?
    *   *If No*: Create it with a header and table.
    *   *If Yes*: Read it and append/update the entry.

2.  **Format**:
    ```markdown
    # Project Skills

    Custom skills local to this project. These override shared engine skills of the same name.

    | Skill | Description | Archetype |
    |-------|-------------|-----------|
    | `/skill-name` | Description from frontmatter | full-session / light-session / report-only / utility |
    ```

3.  Execute `§CMD_REPORT_FILE_CREATION_SILENTLY`.

### §CMD_VERIFY_PHASE_EXIT — Phase 6
**Output this block in chat with every blank filled:**
> **Phase 6 proof:**
> - README.md checked: `________`
> - Skill entry updated: `________`
> - File reported: `________`

### Phase Transition
Execute `AskUserQuestion` (multiSelect: false):
> "Phase 6: Registration complete. How to proceed?"
> - **"Proceed to Phase 7: Synthesis"** — Finalize and summarize
> - **"Stay in Phase 6"** — Fix registration issues

---

## 7. Synthesis

**1. Announce Intent**
Execute `§CMD_REPORT_INTENT_TO_USER`.
> 1. I am moving to Phase 7: Synthesis.
> 2. I will `§CMD_PROCESS_CHECKLISTS` to process any discovered CHECKLIST.md files.
> 3. I will `§CMD_REPORT_RESULTING_ARTIFACTS` to list outputs.
> 4. I will `§CMD_REPORT_SESSION_SUMMARY` to provide a concise overview.

**2. Execution — SEQUENTIAL, NO SKIPPING**

[!!!] CRITICAL: Execute these steps IN ORDER.

**Step 0 (CHECKLISTS)**: Execute `§CMD_PROCESS_CHECKLISTS` — process any discovered CHECKLIST.md files. Read `~/.claude/directives/commands/CMD_PROCESS_CHECKLISTS.md` for the algorithm. Skips silently if no checklists were discovered. This MUST run before the debrief to satisfy `¶INV_CHECKLIST_BEFORE_CLOSE`.

**Step 1**: Execute `§CMD_REPORT_RESULTING_ARTIFACTS` — list all created/modified files in chat.

**Step 2**: Execute `§CMD_REPORT_SESSION_SUMMARY` — 2-paragraph summary in chat.

**Step 3**: Suggest: "You can now use `/<skill-name>` in this project. To test it, start a new session and run the skill."

### §CMD_VERIFY_PHASE_EXIT — Phase 7 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 7 proof:**
> - SKILL.md: `________` (real file path, v2 inline format)
> - Templates: `________` files in assets/
> - Registration: `________`
> - Session summary: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

**Post-Synthesis**: If the user continues talking, obey `§CMD_CONTINUE_OR_CLOSE_SESSION`.
