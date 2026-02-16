### ¶CMD_MANAGE_DIRECTIVES
**Definition**: After debrief creation, manages directive files discovered during the session. Three passes: AGENTS.md updates (auto-mention new directives, keep dir context current), invariant capture, and pitfall capture.
**Classification**: STATIC

**Directive Types Managed**:

- **AGENTS**
  File: `AGENTS.md`
  Management: **Managed** — Pass 1: Auto-update when new directive files added to a dir

- **Invariant**
  File: `INVARIANTS.md`
  Management: **Managed** — Pass 2: Capture new rules/constraints discovered during session

- **Pitfall**
  File: `PITFALLS.md`
  Management: **Managed** — Pass 3: Capture gotchas/traps discovered during session

- **Checklist**
  File: `CHECKLIST.md`
  Management: **Not managed** — Enforced by `§CMD_PROCESS_CHECKLISTS` at deactivation

- **Testing**
  File: `TESTING.md`
  Management: **Not managed** — Read-only during build (used for test guidance)

- **Contributing**
  File: `CONTRIBUTING.md`
  Management: **Not managed** — Manual maintenance only

- **Architecture**
  File: `ARCHITECTURE.md`
  Management: **Not managed** — Manual maintenance only

- **Template**
  File: `TEMPLATE.md`
  Management: **Not managed** — Manual maintenance only

**Algorithm**:

#### Pass 1: AGENTS.md Updates

AGENTS.md is a micro-README: it describes what a directory is for, what to think about when working there, and lists available directive files. It's force-fed to every agent touching that directory — keep it tight.

1.  **Collect Directive Changes**: Check if this session created or deleted any directive files (INVARIANTS.md, CHECKLIST.md, TESTING.md, PITFALLS.md, CONTRIBUTING.md, ARCHITECTURE.md, TEMPLATE.md) in any directory.
2.  **Check Each Discovered AGENTS.md**: For each AGENTS.md in `discoveredDirectives` (from `.state.json`), check if directive files were added or removed in its directory tree.
3.  **If No Changes**: Skip silently.
4.  **If Changes Found**: Present via `AskUserQuestion` (multiSelect: true):
    *   `question`: "New directive files were created near these AGENTS.md files. Update them to mention the new directives?"
    *   `header`: "AGENTS updates"
    *   `options` (up to 4, batch if more):
        *   `"Update: path/to/.directives/AGENTS.md"` — description: `"Add mention of [new directive files]. Will also refresh dir description if stale."`
    *   For each selected AGENTS.md: Read it, add references to new directive files in the "Available Directives" section (or equivalent). If the AGENTS.md has no such section, add one. Refresh the directory description if it's clearly stale.
5.  **Apply**: Use Edit tool to update. Report file paths per `¶INV_TERMINAL_FILE_LINKS`: "AGENTS.md updated: [clickable paths]."
6.  **If AGENTS.md is Missing**: If a directory received new directive files but has NO AGENTS.md at all, offer to create one from `TEMPLATE_AGENTS.md` (in `~/.claude/.directives/templates/`):
    *   `question`: "Directory [path] has directive files but no AGENTS.md. Create one?"
    *   `options`: `"Create from template"` / `"Skip"`

#### Pass 2: Invariant Capture

Invoke §CMD_CAPTURE_KNOWLEDGE with:
*   **Type**: Invariant
*   **Scan criteria**: Repeated corrections, "always/never" patterns, friction points, new constraints, preventable mistakes
*   **Draft fields**: `¶INV_NAME` convention name, one-line rule summary, reason
*   **Decision tree**: `§ASK_INVARIANT_CAPTURE`
*   **Format**: `*   **¶INV_NAME**: [rule]` with indented `**Rule**:` and `**Reason**:` sub-bullets
*   **Targets**: `SHR` → `~/.claude/.directives/INVARIANTS.md`, `PRJ` → `.directives/INVARIANTS.md`, `EDT` → edit+re-present, `MRG` → merge with existing

#### Pass 3: Pitfall Capture

Invoke §CMD_CAPTURE_KNOWLEDGE with:
*   **Type**: Pitfall
*   **Scan criteria**: Surprising behavior, debugging dead ends, counterintuitive APIs, configuration traps, common mistakes
*   **Draft fields**: `¶PTF_NAME` convention name, one-line trap summary, context, trap description, mitigation
*   **Decision tree**: `§ASK_PITFALL_CAPTURE`
*   **Format**: `*   **¶PTF_NAME**: [one-line trap summary]` with indented `**Context**:`, `**Trap**:`, `**Mitigation**:` sub-bullets
*   **Targets**: `NRS` → nearest PITFALLS.md (walk-up), `PRJ` → `.directives/PITFALLS.md`, `NEW` → create new PITFALLS.md from template, `EDT` → edit+re-present

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **Agent judgment only**: All three passes use agent judgment to identify candidates — no explicit markers or log scanning required.
*   **Max 5 per pass**: Focus on the most valuable captures. Avoid prompt fatigue.
*   **Non-blocking**: If user selects "Skip" for everything, the session continues normally.
*   **Idempotent**: Check existing entries before suggesting to avoid duplicates.
*   **Order matters**: AGENTS.md first (factual/structural), then invariants (rules), then pitfalls (warnings). Each pass is independent.
*   **Skip silently**: Each pass independently decides whether it has candidates. An empty pass produces no output and no prompt.
*   **Template location**: Scaffolding templates for all directive types live in `~/.claude/.directives/templates/TEMPLATE_*.md`.
*   **`¶INV_TERMINAL_FILE_LINKS`**: File paths in AGENTS.md update reports and directive references MUST be clickable URLs.

---

### ¶ASK_INVARIANT_CAPTURE
Trigger: during directive management when invariant candidates are identified (except: when no candidates found — collapsible pass, echo via roll call)
Extras: A: View existing invariants in target file | B: Search for similar invariants | C: Defer to review session

## Decision: Invariant Capture
- [SHR] Add to shared
  Universal rule — add to ~/.directives/INVARIANTS.md
- [PRJ] Add to project
  Project-specific — add to .directives/INVARIANTS.md
- [SKP] Skip this one
  Do not add this invariant
- [MORE] Other
  - [EDT] Edit first
    Refine the invariant wording before adding
  - [MRG] Merge with existing
    Combine with an existing invariant instead of creating new

### ¶ASK_PITFALL_CAPTURE
Trigger: during directive management when pitfall candidates are identified (except: when no candidates found — collapsible pass, echo via roll call)
Extras: A: View existing pitfalls in target file | B: Preview the formatted entry | C: Defer to review session

## Decision: Pitfall Capture
- [NRS] Add to nearest PITFALLS.md
  Walk-up from affected directory to closest PITFALLS.md
- [PRJ] Add to project PITFALLS.md
  Project-level pitfalls file
- [SKP] Skip this one
  Do not capture this pitfall
- [MORE] Other
  - [NEW] Create new PITFALLS.md
    Create in the most relevant directory
  - [EDT] Edit first
    Refine the pitfall description before adding

---

## PROOF FOR §CMD_MANAGE_DIRECTIVES

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "agentsUpdated": {
      "type": "string",
      "description": "Count and targets of AGENTS.md updates (e.g., '1 updated: src/.directives')"
    },
    "invariantsCaptured": {
      "type": "string",
      "description": "Count and names of invariants added (e.g., '1 added: INV_CACHE_BEFORE_LOOP')"
    },
    "pitfallsCaptured": {
      "type": "string",
      "description": "Count and titles of pitfalls added"
    }
  },
  "required": ["executed", "agentsUpdated", "invariantsCaptured", "pitfallsCaptured"],
  "additionalProperties": false
}
```
