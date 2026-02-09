---
name: fleet
description: "Interactive agent fleet designer - configure your multi-agent workspace. Triggers: \"configure fleet\", \"setup agents\", \"multi-agent workspace\", \"fleet layout\"."
version: 2.0
tier: lightweight
---

Interactive agent fleet designer - configure your multi-agent workspace.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 0 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 0 until every blank is filled.

# Fleet Protocol (The Workspace Architect)

Interactive agent fleet designer. Helps users configure their multi-agent workspace based on their workflow, not generic categories.

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This protocol has its own structured phases. Use THIS protocol's phases, not the IDE's.

## Core Concepts

### Workgroups
High-level themes that organize your work. Not everyone has all of these:

| Workgroup | Description | Examples |
|-----------|-------------|----------|
| **project** | Active codebase work | Viewer, Layout, API, Extraction |
| **company** | Company-specific agents | MCP tools, internal systems |
| **domain** | Domain research & expertise | Insurance, Financials, Legal |
| **meta** | Engine & session work | Sessions analysis, reports, engine |
| **personal** | Personal productivity | Notes, learning, experiments |

### Subprojects
Actual features/areas you work on — discovered through interview, not picked from a menu.
- Bad: "Frontend: Components" (generic)
- Good: "Viewer", "Layout", "Extraction UI" (your actual work)

### Placeholders
Slots for areas you don't know yet. Create "Future" agents to reserve space.

---

## Subcommands

| Command | Action |
|---------|--------|
| `/fleet` | Full interview (new or update) |
| `/fleet update` | Quick changes |
| `/fleet rearrange` | Reorder agents/tabs |
| `/fleet launch` | Start the fleet |
| `/fleet launch {workgroup}` | Start specific workgroup |
| `/fleet status` | Show current state |
| `/fleet add {workgroup}` | Add agents to workgroup |
| `/fleet placeholder {workgroup}` | Add future slot |

---

## 0. Setup Phase

1. **Auto-detect identity** (per `¶INV_INFER_USER_FROM_GDRIVE`):
   ```bash
   USERNAME=$(engine user-info username)
   EMAIL=$(engine user-info email)
   ```
   Announce: "Detected identity: **{USERNAME}** ({EMAIL})"

2. **Check for existing config**: Use `fleet.sh` to detect existing configs:
   ```bash
   engine fleet status
   ```
   This outputs the fleet directory path and any running sessions.

   Then check for yml files:
   ```bash
   engine fleet list
   ```

   - If configs found: "Found existing fleet config. Update it, or start fresh?"
   - If no configs: "No existing fleet configuration found — let's design one from scratch!"

3. **Detect pane context** (if running inside a fleet pane):
   ```bash
   # Check if we're in a fleet tmux session
   TMUX_SOCKET=$(echo "$TMUX" | cut -d, -f1 | xargs basename 2>/dev/null || echo "")
   if [ "$TMUX_SOCKET" = "fleet" ]; then
     CURRENT_PANE_ID="${TMUX_PANE_TITLE:-}"
     CURRENT_LABEL=$(tmux -L fleet display-message -p '#{@pane_label}' 2>/dev/null || echo "")
     CURRENT_WINDOW=$(tmux -L fleet display-message -p '#W' 2>/dev/null || echo "")
   fi
   ```

   If running in a fleet pane, offer: "You're in pane **{CURRENT_LABEL}** ({CURRENT_PANE_ID}). Update this pane, or configure the whole fleet?"

### §CMD_VERIFY_PHASE_EXIT — Phase 0
**Output this block in chat with every blank filled:**
> **Phase 0 proof:**
> - Identity detected: `________`
> - Existing config: `________`
> - Pane context: `________`
> - Mode: `________`

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Interview Phase (Discovery-Based)

The goal is to **discover** what the user actually works on, not force them into categories.

### Round 1: Workgroups
Execute `AskUserQuestion` (multiSelect: true):
> "What levels of work do you do?"
> - **"Project work"** — Building features in your codebase
> - **"Company work"** — Company-specific tools, MCPs, internal systems
> - **"Domain research"** — Industry expertise (insurance, finance, legal, etc.)
> - **"Meta work"** — Sessions, reports, engine improvements, documentation
>
> *(Personal/experiments/learning → user types in "Other")*

### Round 2: Subproject Discovery (per workgroup)

For each selected workgroup, execute an `AskUserQuestion` to discover subprojects. Use hardcoded examples as options — the user names their actual subprojects via "Other".

**If Project selected:**
Execute `AskUserQuestion` (multiSelect: true):
> "What features or areas of your app do you actively work on?"
> - **"Viewer"** — Frontend viewing/display components
> - **"Layout"** — Page layout and structure analysis
> - **"API"** — Backend API and services
> - **"Extraction"** — Data extraction and parsing

Then execute `AskUserQuestion` (multiSelect: false):
> "Any areas you might work on soon but haven't started?"
> - **"Yes, I'll list them"** — Creates placeholder agents (type in "Other")
> - **"No placeholders needed"** — Skip placeholder creation

**If Company selected:**
Execute `AskUserQuestion` (multiSelect: true):
> "What company-specific tools or systems do you work with?"
> - **"MCP tools"** — Model Context Protocol integrations
> - **"Internal dashboards"** — Company-internal admin tools
> - **"Company docs"** — Internal documentation and knowledge bases

**If Domain selected:**
Execute `AskUserQuestion` (multiSelect: true):
> "What domains do you research or need expertise in?"
> - **"Insurance claims"** — Claims processing, Xactimate, adjusting
> - **"Financials"** — Financial analysis and reporting
> - **"Legal compliance"** — Regulatory and legal requirements

**If Meta selected:**
Execute `AskUserQuestion` (multiSelect: true):
> "What meta-level work do you do?"
> - **"Sessions analysis"** — Reviewing and analyzing agent sessions
> - **"Reports"** — Generating progress and status reports
> - **"Engine work"** — Workflow engine improvements and maintenance
> - **"Documentation"** — Docs, standards, and knowledge management

**Key principle**: Let the user name their subprojects via "Other". The hardcoded options are starting points, not an exhaustive list.

### Round 3: Hardware & Layout

Execute `AskUserQuestion` (multiSelect: false):
> "How many monitors?"
> - **"1"** — Single monitor setup
> - **"2"** — Dual monitor setup
> - **"3+"** — Three or more monitors

Execute `AskUserQuestion` (multiSelect: false):
> "Agents visible per screen?"
> - **"4 (2x2)"** — Compact grid, 4 agents per monitor
> - **"6 (2x3)"** — Medium grid, 6 agents per monitor
> - **"9 (3x3)"** — Large grid, 9 agents per monitor
> - **"12 (3x4)"** — Maximum density, 12 agents per monitor

### Round 4: Organization

Execute `AskUserQuestion` (multiSelect: false):
> "How should workgroups be organized?"
> - **"Separate tabs per workgroup"** — One tab per workgroup (Project tab, Domain tab, Meta tab)
> - **"Combined"** — All in fewer tabs, grouped by relatedness
> - **"Separate tmux sessions"** — Independent tmux sessions per workgroup (launch separately)

Execute `AskUserQuestion` (multiSelect: false):
> "Add a delegation pool for background tasks?"
> - **"Yes (4 workers)"** — Full pool with 4 background workers
> - **"Yes (2 workers)"** — Small pool with 2 background workers
> - **"No"** — No delegation pool

### §CMD_VERIFY_PHASE_EXIT — Phase 1
**Output this block in chat with every blank filled:**
> **Phase 1 proof:**
> - Workgroups selected: `________`
> - Subprojects per workgroup: `________`
> - Hardware/layout: `________`
> - Organization: `________`
> - Delegation pool: `________`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "1: Interview"
  nextPhase: "2: Generate Layout"
  prevPhase: "0: Setup"

---

## 2. Generate Layout Phase

### Workgroup → Tab Mapping

Based on organization preference:
- **Separate**: One tab per workgroup, subprojects as agents within
- **Combined**: Merge related workgroups (e.g., Project + Meta)
- **Separate sessions**: Generate multiple tmuxinator configs

### Agent Generation

For each subproject discovered, gather three things during the interview:

1. **Agent type** — the persona from `~/.claude/agents/`
2. **Description** — 1-3 sentence topic description (what this agent works on)
3. **Delegation tags** — which `#needs-*` tags this agent handles

Generate a yml pane block with all three:

```yaml
- {workgroup}-{subproject}:
    - export TMUX_PANE_TITLE="{workgroup}-{subproject}"
    - export AGENT_DESCRIPTION="{topic description}"
    - tmux set-option -p -t $TMUX_PANE @pane_label "{Subproject}"
    - clear && engine run --agent {agent_type} --description "$AGENT_DESCRIPTION"
```

**Agent type** is chosen based on the subproject's primary function:
- **operator** — General-purpose work (API, schema, engine, etc.)
- **refiner** — Extraction, parsing, prompt iteration
- **reviewer** — Visual QA, review workflows
- **researcher** — Domain research, deep dives
- **analyzer** — Code/doc analysis, pattern identification
- **writer** — Documentation, reports
- **tester** — Test fixtures, coverage
- **builder** — TDD implementation
- **debugger** — Bug investigation
- **critiquer** — Design critique, code review

**Description** is a concise topic summary that gets injected into Claude's system prompt via `--description`. It tells the agent what area of the codebase/domain it specializes in. Write it as if briefing a new team member.

**Delegation tags** map subprojects to `#needs-*` tags for dispatch routing. Each active agent should have 1-2 tags:
- Viewer → `#needs-viewer`, `#needs-frontend`
- Layout → `#needs-layout`, `#needs-frontend`
- Parsing → `#needs-parsing`, `#needs-extraction`
- Insurance → `#needs-insurance`, `#needs-domain`
- Sessions → `#needs-sessions`, `#needs-meta`

Delegation tags are used by the dispatch daemon to route work to the right agent. They are NOT passed to `run.sh` — they are stored in the worker registration files created at startup by persistent agents (future feature) or in pool worker `--accepts` flags.

### Placeholder Agents

For areas mentioned as "might work on soon" — no agent, no description, just `fleet.sh wait`:
```yaml
- {workgroup}-future-1:
    - export TMUX_PANE_TITLE="{workgroup}-future-1"
    - tmux set-option -p -t $TMUX_PANE @pane_label "Future"
    - engine fleet wait
```

### Pool Workers

Pool workers use `run.sh --monitor-tags` (daemon mode). They receive `--agent`, `--description`, and `--monitor-tags` (delegation tags):

```yaml
- pool-worker-1:
    - export TMUX_PANE_TITLE="pool-worker-1"
    - export AGENT_DESCRIPTION="{worker description}"
    - tmux set-option -p -t $TMUX_PANE @pane_label "Worker 1"
    - clear && engine run --monitor-tags "#needs-delegation,#needs-implementation" --agent operator --description "$AGENT_DESCRIPTION"
```

`--monitor-tags` takes comma-separated `#needs-*` tags that this worker will watch for and auto-dispatch.

### Activating or Updating a Pane

This flow handles both:
- **Placeholder activation**: Converting a "Future" slot to a real agent
- **Self-update**: Modifying an existing pane's configuration

When `/fleet activate` is invoked (or user presses 'a' in a placeholder):

#### Step 1: Gather Context
```bash
CURRENT_PANE_ID="${TMUX_PANE_TITLE:-unknown}"
CURRENT_LABEL=$(tmux -L fleet display-message -p '#{@pane_label}' 2>/dev/null || echo "Future")
CURRENT_WINDOW=$(tmux -L fleet display-message -p '#W' 2>/dev/null || echo "unknown")
```

#### Step 2: Ask Configuration Questions
Use `AskUserQuestion` to gather:

1. **Name/Label**: "What should this agent be called?"
   - Suggest based on workgroup (e.g., domain → research-related names)

2. **Agent Type**: "What type of agent?"
   - Options: `researcher`, `builder`, `operator`, `analyzer`, `reviewer`, `writer`, `tester`, `prompter`

3. **Description**: "Describe what this agent does (1-2 sentences)"
   - Example: "Deep research agent for web, docs, and codebase exploration"

4. **Focus Areas**: "What topics does this agent specialize in? (comma-separated)"
   - Example: "Insurance claims, Xactimate codes, PDF extraction"

#### Step 3: Apply Immediately
```bash
# Update pane label (visible immediately)
tmux -L fleet set-option -p @pane_label "{NEW_LABEL}"
```

#### Step 4: Prompt for Permanent Update
**ALWAYS** ask after setting the label:

Execute `AskUserQuestion` (multiSelect: false):
> "Make this permanent in fleet.yml?"
> - **"Yes — persist across fleet restarts"** — Update yml config so this survives `fleet.sh start`
> - **"No — temporary until restart"** — Keep as runtime-only change (reverts on next fleet launch)

#### Step 5: Update Yml (if user said Yes)

1. **Get yml path** (use `fleet.sh config-path` for dynamic resolution):
   ```bash
   # Default fleet config:
   YML_PATH=$(engine fleet config-path)
   # Workgroup-specific config:
   YML_PATH=$(engine fleet config-path project)
   ```

2. **Read the yml** and find the pane entry by `TMUX_PANE_TITLE`:
   - Search for line containing `export TMUX_PANE_TITLE="{CURRENT_PANE_ID}"`
   - This identifies the pane block to update

3. **Update the pane block**:
   - Change the pane key (e.g., `domain-future-2` → `domain-research`)
   - Update `@pane_label` value
   - Replace `fleet.sh wait` with `run.sh --agent {TYPE} --description "{DESC}" --focus "{FOCUS}"`
   - Add env var exports for description/focus

   **Before (placeholder)**:
   ```yaml
   - domain-future-2:
       - export TMUX_PANE_TITLE="domain-future-2"
       - tmux set-option -p -t $TMUX_PANE @pane_label "Future"
       - engine fleet wait
   ```

   **After (activated)**:
   ```yaml
   - domain-research:
       - export TMUX_PANE_TITLE="domain-research"
       - export AGENT_DESCRIPTION="Deep research agent for web, docs, and codebase exploration"
       - export AGENT_FOCUS="Insurance claims, Xactimate codes, PDF extraction"
       - tmux set-option -p -t $TMUX_PANE @pane_label "Research"
       - clear && engine run --agent researcher --description "$AGENT_DESCRIPTION" --focus "$AGENT_FOCUS"
   ```

4. **Write the updated yml** using the Edit tool.

5. **Confirm**: "Updated `{YML_PATH}`. Changes will persist on fleet restart."

### §CMD_VERIFY_PHASE_EXIT — Phase 2
**Output this block in chat with every blank filled:**
> **Phase 2 proof:**
> - Layout generated: `________`
> - Agent types assigned: `________`
> - Descriptions written: `________`
> - Placeholders created: `________`
> - Pool workers configured: `________`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "2: Generate Layout"
  nextPhase: "3: Present & Confirm"
  prevPhase: "1: Interview"

---

## 3. Present & Confirm Phase

Show the proposed layout with workgroup organization:

```
## Your Fleet Layout

**Person**: yarik (yarik@finchclaims.com)
**Setup**: 2 monitors, 6 agents per view

### Workgroup: Project
**Tab: Project** (2x3 grid)
┌─────────────┬─────────────┬─────────────┐
│ Viewer      │ Layout      │ Extraction  │
├─────────────┼─────────────┼─────────────┤
│ API         │ Schema      │ Future      │
└─────────────┴─────────────┴─────────────┘

### Workgroup: Domain
**Tab: Domain** (2x2 grid)
┌─────────────┬─────────────┐
│ Insurance   │ Financials  │
├─────────────┼─────────────┤
│ Future      │ Future      │
└─────────────┴─────────────┘

### Workgroup: Meta
**Tab: Meta** (2x2 grid)
┌─────────────┬─────────────┐
│ Sessions    │ Reports     │
├─────────────┼─────────────┤
│ Engine      │ Future      │
└─────────────┴─────────────┘

### Delegation Pool
**Tab: Pool** (2x2 grid)
┌─────────────┬─────────────┐
│ Worker 1    │ Worker 2    │
├─────────────┼─────────────┤
│ Worker 3    │ Worker 4    │
└─────────────┴─────────────┘

Adjust anything? (Add/remove/rename/reorder)
```

### §CMD_VERIFY_PHASE_EXIT — Phase 3
**Output this block in chat with every blank filled:**
> **Phase 3 proof:**
> - Layout presented: `________`
> - User reviewed: `________`
> - User confirmed or adjusted: `________`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "3: Present & Confirm"
  nextPhase: "4: Save & Generate"
  prevPhase: "2: Generate Layout"
  custom: "Go back to Phase 1 | Re-interview for different setup"

---

## 4. Save & Generate Phase

1. **Create directories**:
   ```bash
   mkdir -p ~/.claude/fleet/workers
   ```

2. **Generate tmuxinator config**:
   - Location: Resolve via `fleet.sh config-path [workgroup]`
   - Default fleet: `tmux_command: tmux -L fleet -f ~/.claude/engine/skills/fleet/assets/tmux.conf`
   - Workgroup fleet: `tmux_command: tmux -L fleet-{workgroup} -f ~/.claude/engine/skills/fleet/assets/tmux.conf`
   - Each active pane exports `AGENT_DESCRIPTION` and calls `run.sh --agent {type} --description "$AGENT_DESCRIPTION"`
   - Placeholder panes call `fleet.sh wait` (no agent, no description)
   - Pool workers use `run.sh --monitor-tags` with delegation tags, `--agent`, and `--description`

3. **Report**:
   ```
   Fleet configured!

   To start default:  fleet.sh start
   To start workgroup: fleet.sh start {workgroup}
   To update: /fleet update
   To rearrange: /fleet rearrange
   ```

### §CMD_VERIFY_PHASE_EXIT — Phase 4
**Output this block in chat with every blank filled:**
> **Phase 4 proof:**
> - Fleet directory created: `________`
> - Tmuxinator config written: `________`
> - Config validated (unique pane IDs): `________`
> - Launch instructions displayed: `________`

### Phase Transition
Execute `§CMD_TRANSITION_PHASE_WITH_OPTIONAL_WALKTHROUGH`:
  completedPhase: "4: Save & Generate"
  nextPhase: "5: Update Mode"
  prevPhase: "3: Present & Confirm"
  custom: "Done | Exit the fleet designer"

---

## 5. Update Mode

Quick operations without full interview.

Execute `AskUserQuestion` (multiSelect: false):
> "What do you want to change?"
> - **"Add agents to a workgroup"** — Create new agent panes in an existing workgroup
> - **"Remove agents"** — Delete agent panes from the fleet config
> - **"Rename agents/tabs"** — Change labels or tab names
> - **"Rearrange layout"** — Reorder tabs, move agents between tabs
>
> *(Add/remove workgroups, convert placeholder → type in "Other")*

### §CMD_VERIFY_PHASE_EXIT — Phase 5
**Output this block in chat with every blank filled:**
> **Phase 5 proof:**
> - Changes applied: `________`
> - Config file updated: `________`
> - User confirmed: `________`

---

## 6. Rearrange Mode

For easy reordering:

1. Show current layout as numbered list:
   ```
   1. [Project] Viewer
   2. [Project] Layout
   3. [Project] Extraction
   4. [Domain] Insurance
   5. [Meta] Sessions
   ```

2. Ask: "Enter new order (e.g., '3,1,2,5,4') or move commands ('move 5 to Project')"

3. Apply changes, regenerate config

### §CMD_VERIFY_PHASE_EXIT — Phase 6 (PROOF OF WORK)
**Output this block in chat with every blank filled:**
> **Phase 6 proof:**
> - New order applied: `________`
> - Config regenerated: `________`
> - User confirmed: `________`

If ANY blank above is empty: GO BACK and complete it before proceeding.

---

## Integration with Daemon Mode

Pool workers run in daemon mode (`run.sh --monitor-tags`), which handles work distribution:

```bash
# Workers scan sessions/ for tagged files
engine run --monitor-tags "#needs-implementation,#needs-chores"

# Files with matching tags are auto-dispatched
sessions/*/REQUEST.md  # with #needs-implementation tag
```

Tag-based routing:
- Pool workers specify `--monitor-tags "#needs-implementation"` in yml
- Each worker scans `sessions/` for files with matching tags
- On match: claim tag (`#needs-*` → `#active-*`), spawn Claude with the resolving skill per `§TAG_DISPATCH`
- Clean Ctrl+C exit (no more zombie processes)

---

## Invariants

- **¶INV_YML_IS_SOURCE_OF_TRUTH**: The fleet yml config is the single source of truth. No separate metadata files.
- **¶INV_POOL_TAB_LAST**: Pool worker tab is always last.
- **¶INV_UNIQUE_AGENT_IDS**: Agent IDs must be unique across all tabs.
- **¶INV_DISCOVER_DONT_PRESCRIBE**: Interview discovers subprojects; don't force generic categories.
- **¶INV_PLACEHOLDERS_ARE_CHEAP**: Encourage "Future" slots — easy to convert later.
- **¶INV_WORKERS_SELF_MONITOR**: Pool workers use daemon mode (`run.sh --monitor-tags`) to self-schedule work.
