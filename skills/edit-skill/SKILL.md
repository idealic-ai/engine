---
name: edit-skill
description: "Creates, edits, or promotes skills — scaffolds SKILL.md and assets to project-local or shared engine. Triggers: \"create a new skill\", \"edit a skill\", \"scaffold a skill\", \"promote a skill\", \"add a project skill\", \"create a new command\"."
version: 3.0
tier: protocol
---

Creates, edits, or promotes skills — scaffolds SKILL.md and assets to project-local or shared engine.

# Edit Skill Protocol (The Skill Forge)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Subcommands

| Command | Action |
|---------|--------|
| `/edit-skill <name>` | Create or edit a skill (default flow) |
| `/edit-skill promote <name>` | Promote project-local skill to shared engine |

**Routing**: Parse the arguments to determine the flow:
- If first argument is `promote`: Jump to **Promote Flow** (after Phase 0 setup).
- Otherwise: Continue with **Create/Edit Flow** (Phases 0-4).

### Session Parameters (for `§CMD_PARSE_PARAMETERS`)
*Merge into the JSON passed to `engine session activate`:*
```json
{
  "taskType": "EDIT_SKILL",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed", "templatesLoaded"], "gate": false},
    {"label": "1", "name": "Detection",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": [],
      "proof": ["detectionMode", "targetLocation"]},
    {"label": "2", "name": "Interrogation",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_INTERROGATE"],
      "commands": ["§CMD_ASK_ROUND", "§CMD_LOG_INTERACTION"],
      "proof": ["depthChosen", "roundsCompleted"]},
    {"label": "3", "name": "Scaffold",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_LINK_FILE"],
      "proof": ["planPresented", "logEntries"]},
    {"label": "4", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "4.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "4.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "4.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "4.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/edit-skill", "/implement", "/analyze", "/chores"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_EDIT_SKILL_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_EDIT_SKILL.md"
}
```

---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Forging skill: ___. Operation: ___. Target: ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Understand the skill name, subcommand (create/edit/promote), and load reference exemplars.

**Reference Examples**: Load ALL of these to build by example:

*Entry points (SKILL.md files — read all to see the v2 inline pattern):*
*   `~/.claude/skills/implement/SKILL.md` (full-session archetype)
*   `~/.claude/skills/brainstorm/SKILL.md` (light-session archetype)
*   `~/.claude/skills/do/SKILL.md` (lightweight archetype)
*   `~/.claude/skills/session/SKILL.md` (utility archetype)

**Parse Arguments**: Extract the skill name and subcommand from the user's input.
*   **Input**: `/edit-skill [promote] <skill-name> [additional context]`
*   **Normalize**: Convert to kebab-case if not already (e.g., `mySkill` -> `my-skill`).
*   **Derive**: `PROTOCOL_NAME` = uppercase + underscores (e.g., `my-skill` -> `MY_SKILL`).
*   **Route**: If first argument is `promote`, jump to **Promote Flow** after displaying parsed names.
*   **Output**: Display the parsed names:
    > **Skill**: `<skill-name>`
    > **Protocol**: `<PROTOCOL_NAME>`
    > **Subcommand**: `create/edit` or `promote`

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Detection
*Determine whether this is a CREATE or EDIT operation, and where the skill should live.*

§CMD_REPORT_INTENT:
> 1: Detecting skill ___ in project-local and shared engine. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

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
    *   *Edit (shared -> local override)*: "**Edit Mode** — Creating local override of shared skill."
    *   *Edit (local override)*: "**Edit Mode** — Found local override at `.claude/skills/<name>/`."

---

## 2. Interrogation
*Gather requirements through structured questioning.*

§CMD_REPORT_INTENT:
> 2: Interrogating ___ skill design assumptions before scaffolding. ___.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

### Context Ingestion (Pre-Interrogation)

**If EDIT MODE**:
1.  **Read** the existing SKILL.md entry point (from the source — project-local or shared engine).
2.  **Read** any associated asset files (check the skill's `assets/` directory for templates).
3.  **Summarize** to the user: Brief description of what the skill does, its phases, what templates it uses. Do NOT dump the full content.

**If CREATE MODE**:
*   No files to read. Proceed directly to interrogation rounds.

### Topics (Skill Design)
*Standard topics for the command to draw from. Adapt to the task -- skip irrelevant ones, invent new ones as needed.*

**Standard topics** (typically covered once):
- **Skill purpose** — what the skill does, why it exists, what gap it fills
- **Phase structure** — what phases are needed, what order, what each does
- **Template needs** — what session artifacts to generate, what sections they need
- **Integration points** — what `§CMD_` commands to reference, what other skills it interacts with
- **Testing approach** — how to verify the skill works, what a good run looks like
- **Archetype selection** — full-session, light-session, report-only, or utility

**Repeatable topics** (can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail


---

## 3. Scaffold / Rewrite
*Generate the v2 inline SKILL.md into the target location.*

§CMD_REPORT_INTENT:
> 3: Scaffolding skill ___ into ___. Generating SKILL.md and templates for ___ archetype.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

### Target Path Resolution

Based on `targetLocation` from Phase 1:

| Target | Skill files go to | Symlink action |
|--------|-------------------|----------------|
| `project` | `.claude/skills/<name>/` | None |
| `shared` | `~/.claude/engine/skills/<name>/` | Create symlink: `~/.claude/skills/<name>` -> `~/.claude/engine/skills/<name>/` |

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

The v2 format puts the entire protocol INLINE in SKILL.md. There is NO separate `references/` protocol file. The protocol goes directly into SKILL.md after the boot sequence.

**Template**:
```markdown
---
name: <skill-name>
description: "[One-line description]. Triggers: \"[trigger 1]\", \"[trigger 2]\", \"[trigger 3]\"."
version: 2.0
tier: protocol
---

[One-line description].
# [Protocol Title]

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

Each phase MUST reference appropriate `§CMD_` commands:
*   Setup -> `§CMD_ASSUME_ROLE`, `§CMD_MAINTAIN_SESSION_DIR`, `§CMD_PARSE_PARAMETERS`
*   Context Ingestion -> `§CMD_INGEST_CONTEXT_BEFORE_WORK`
*   Interrogation -> `§CMD_INTERROGATE`, `§CMD_LOG_INTERACTION`
*   Planning -> `§CMD_WRITE_FROM_TEMPLATE` (using plan template)
*   Work Loop -> `§CMD_THINK_IN_LOG`, `§CMD_APPEND_LOG`, `§CMD_REFUSE_OFF_COURSE`
*   Synthesis -> `§CMD_RUN_SYNTHESIS_PIPELINE`

**v2 Structural Requirements**:
*   Phase transitions managed by §CMD_EXECUTE_PHASE_STEPS (automatic gating).
*   `---` between phases.
*   Final phase uses `§CMD_RUN_SYNTHESIS_PIPELINE` for synthesis.
*   Skills with interrogation get: custom topics (standard + repeatable). Depth selection and exit gates are handled by `§CMD_INTERROGATE`.

**DIALOGUE.md integration (automatic for non-utility archetypes)**:
Any skill that has an Interrogation phase or interactive dialogue MUST include DIALOGUE.md logging.

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
Execute `§CMD_LINK_FILE` for each file created.

---

## 4. Synthesis
*When scaffolding is complete.*

§CMD_REPORT_INTENT:
> 4: Synthesizing. Skill ___ scaffolded with ___ files.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(4.0.*)

**Debrief notes** (for `EDIT_SKILL.md`):
*   Include: skill name, mode (create/edit), target location, files generated, archetype used.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Skill scaffolded. Walk through the generated files?"
  debriefFile: "EDIT_SKILL.md"
  templateFile: "assets/TEMPLATE_IMPLEMENTATION.md"
```

**Post-scaffold suggestion**:
- If project-local: "You can now use `/<skill-name>` in this project. To share it across projects, run `/edit-skill promote <skill-name>`."
- If shared: "You can now use `/<skill-name>` in any project."

---
---

# Promote Flow

*Promotes a project-local skill to the shared engine.*

**Entry**: Invoked via `/edit-skill promote <name>`. Starts after Phase 0 setup.

Promoting is not a file copy. The skill is moving from a place where one project's habits are correct into a place where every project inherits them, so **P2.5 is a gate that stops the promote**, not a note on the way past. The phases: P1 inventory → P2 diff → **P2.5 project-assumption check** → P3 confirmation → P4 execute.

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
    | SKILL.md | yes | yes/no | New / Overwrite |
    | assets/TEMPLATE_*.md | yes/no | yes/no | New / Overwrite / Skip |
    ```

---

## P2. Diff (Conditional)
*For files that will OVERWRITE existing engine files, produce a structural comparison.*

Only diff files where both local and engine versions exist (Action = "Overwrite"). Skip files where the action is "New".

For each file being overwritten:

1.  **Read** both the local version and the engine version.
2.  **Structural comparison**:
    *   **For SKILL.md**: Compare frontmatter (description, version). Compare phase structure. Report added/removed/reordered phases. Report changed roles, mindsets, or `§CMD_` references.
    *   **For templates**: Compare section headers (H2/H3). Report added/removed sections.
3.  **Output** a summary per file.

*If NO files are being overwritten (all "New")*: Skip this phase entirely and note "All files are new — no overwrites."

---

## P2.5 Project-Assumption Check
*A skill that worked in one project is about to become shared, where every other project inherits it. This phase finds the assumptions it is carrying and does not let them travel unexamined.*

**This phase can FAIL.** An unadjudicated hit does not proceed to P3 — the promote stops and the user chooses what to do. It is not an advisory read.

### Derive the source vocabulary (do this first)

Do not grep for a hardcoded project name. Derive the vocabulary from the project you are promoting *out of*, so the check works for any project:

*   **Issue-key prefix** and **team** and **tracker host** — from the project `CLAUDE.md`'s `## Tracker` block, when it has one.
*   **Repo / org name** — the basename of the repo root, and any org name in the tracker URL.
*   **Workspace paths** — the top-level app/package directory names (`ls` the repo root; e.g. `apps/<x>`, `packages/<y>`) and the npm scope from the root `package.json` `name`.

Call this set `<SRCVOCAB>`. Every arm below uses it.

### Arm 1 — the source project's own names, in a file about to be shared

```bash
grep -rnE "<SRCVOCAB alternation>" .claude/skills/<name>/
```

Each hit is a project assumption until the user says otherwise. The distinction that matters: a name inside an **illustrative example** that the reader will obviously substitute is legal; a name inside a **live rule, a path the skill will act on, or a command it will run** is not.

### Arm 2 — a skill that handles ticket keys with no tracker-config resolve

Trigger and verdict, both cheap:

```bash
# does the skill derive or construct an issue key?
grep -coiE -- '\-NNNN|<PREFIX>|from the branch|branch.s ticket key|ticket key from' .claude/skills/<name>/SKILL.md
# does it resolve the config that tells it the key's shape?
grep -c 'Tracker' .claude/skills/<name>/SKILL.md
```

**Derives a key AND zero `Tracker` → this arm fires.** The skill is about to take one project's key shape into shared space.

### Arm 3 — one project's measurement stated as a general truth

The hardest of the three, because it can name no project, no key and no path. The mechanism is a **frequency or magnitude claim about how the world is**, whose evidence came from the single project the skill grew up in. In shared space it reads as a fact about every project.

```bash
grep -rniE '\b(usually|typically|generally|almost always|richly|tend(s)? to|often|most)\b[^.]{0,60}\b(ticket|tickets|cluster|issue|issues|PR|PRs|repo|claim|claims|comment|comments)\b' .claude/skills/<name>/
```

**Adjudicate each hit against one discriminator**: does the sentence carry a condition the next project can evaluate for itself? *"Where tickets are richly wired via `relatedTo`, a cluster is usually one decision — where the rows carry few relations, the clusters will be thin"* is legal: it names both branches and tells the reader which they are in. *"Tickets are richly wired via `relatedTo`"* is not: it is a measurement of one tracker, in the indicative, with nothing to evaluate.

**Severity, stated honestly**: Arms 1 and 2 produce a mechanical verdict. Arm 3 produces a flag that a reader must rule on — and its known benign class is the correctly conditionalised generalisation above. Arm 3 blocks on an **unruled** hit, not on a hit.

### The prescribed remedy — resolve the config, don't delete the behaviour

For an Arm-1 or Arm-2 hit about the tracker, the fix is the convention the engine already uses. **Read how `ticket`, `pr`, `snapshot`, `release-notes` and `intake` do it and follow that**, rather than inventing a variant:

*   Write keys as **`<PREFIX>-NNNN`** (uppercase for keys, lowercase for branches: `<prefix>-NNNN-…`). Never a literal key.
*   **Resolve `<PREFIX>`, team and base branch in the skill's own first phase**, by reading the project `CLAUDE.md`'s `## Tracker` block.
*   An orchestrator that dispatches a subagent **resolves and injects** the config — the subagent does not see `CLAUDE.md`.
*   **Fall back to detection** when there is no `## Tracker` block: an uppercase-alpha prefix + `-NNNN` from the branch / slug / conversation, at lower confidence.
*   **Never error on absence.** The config is an input, not a requirement.

For an Arm-3 hit, the fix is to **name the condition and both of its sides**, so a project in the other branch is told which one it is in — not to delete the insight.

### Outcome

| Result | Action |
|---|---|
| All arms clean (or every hit adjudicated legal, with the reason recorded) | Proceed to P3. Carry the verdict into P3's summary. |
| Any hit the user has not ruled on | **STOP.** Do not copy a file. Report each hit as `path:line` with its arm, and offer: fix it here (then re-run this phase) · promote as-is with the hit recorded in the summary · abort. |

**Report the zeros with a control.** A clean arm is a claim about the instrument as much as about the file. Run each arm over `~/.claude/engine/skills/` and name a skill it fires on, so a zero means absence rather than a broken pattern — then **never draw the control from text you just wrote**, which confirms your edit and not your instrument (`~/.claude/.directives/INVARIANTS.md` `§INV_A_CONTROL_DRAWN_FROM_WHAT_YOU_JUST_FIXED_IS_NOT_A_CONTROL`). Exclude the skill being promoted from the control sweep.

Arm 2 is the one that controls itself: the same loop prints a FIRES side (derives a key, zero `Tracker`) and a silent side (derives **and** resolves), so its silence is a reading rather than a dead pattern. For Arms 1 and 3, pick the firing example out of that sweep rather than from a list written here — a named example goes stale the moment someone fixes it, and a stale control is read as a pass.

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

Project-assumption check (P2.5): [clean | N hits adjudicated legal | N hits fixed]
  [one path:line + arm per hit the user ruled legal, with the reason]

After promote:
  - Local .claude/skills/<name>/ will be DELETED — a tracked change in this
    project's repo, which you will owe a commit (see P4 step 4)
  - Symlink created: ~/.claude/skills/<name> -> ~/.claude/engine/skills/<name>/
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

    **This is a tracked change in the project's repo, and it owes a commit.** `.claude/skills/` is checked in, so the deletion shows up in `git status` as removed files that nobody was told about — a later reader finds an unexplained deletion, or `git checkout` quietly restores the local copy and shadows the engine one. Do not leave it unreported:
    *   **State the owed commit** in the P4 report, by path, with a subject that says where the skill went — e.g. `chore: <name> moves out of this project and into the shared engine`.
    *   **Do not run the commit from this skill**, and do not stage with `-A`/`-u`/`.` — the working tree may hold other work. Hand the user the message and the explicit paths.
    *   The engine side of the promote is a change in **`~/.claude/engine`**, which is its own repository. Report that commit as owed too; it is not the same commit.

5.  **Create symlink**:
    ```bash
    ln -s ~/.claude/engine/skills/<name> ~/.claude/skills/<name>
    ```

6.  **Verify symlink** resolves correctly:
    ```bash
    ls -la ~/.claude/skills/<name>/SKILL.md
    ```

7.  **Report**: Execute `§CMD_LINK_FILE` for each file. Close with the **two owed commits** — the project repo's deletion (step 4) and the engine repo's addition — each with its paths and a suggested subject, and say plainly that this skill ran neither.

Execute `§CMD_REPORT_ARTIFACTS`.
Execute `§CMD_REPORT_SUMMARY`.
