### §CMD_MANAGE_DIRECTIVES
**Definition**: After debrief creation, manages directive files discovered during the session. Three passes: AGENTS.md updates (auto-mention new directives, keep dir context current), invariant capture, and pitfall capture.
**Trigger**: Called by `§CMD_FOLLOW_DEBRIEF_PROTOCOL` Step 2 (Pipeline), after debrief is written.

**Directive Types Managed**:

| Type | File | Management |
|------|------|------------|
| **AGENTS** | `AGENTS.md` | **Managed** — Pass 1: Auto-update when new directive files added to a dir |
| **Invariant** | `INVARIANTS.md` | **Managed** — Pass 2: Capture new rules/constraints discovered during session |
| **Pitfall** | `PITFALLS.md` | **Managed** — Pass 3: Capture gotchas/traps discovered during session |
| **Checklist** | `CHECKLIST.md` | **Not managed** — Enforced by `§CMD_PROCESS_CHECKLISTS` at deactivation |
| **Testing** | `TESTING.md` | **Not managed** — Read-only during build (used for test guidance) |
| **Contributing** | `CONTRIBUTING.md` | **Not managed** — Manual maintenance only |
| **Architecture** | `ARCHITECTURE.md` | **Not managed** — Manual maintenance only |
| **Template** | `TEMPLATE.md` | **Not managed** — Manual maintenance only |

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
5.  **Apply**: Use Edit tool to update. Report: "AGENTS.md updated: [list]."
6.  **If AGENTS.md is Missing**: If a directory received new directive files but has NO AGENTS.md at all, offer to create one from `TEMPLATE_AGENTS.md` (in `~/.claude/engine/.directives/templates/`):
    *   `question`: "Directory [path] has directive files but no AGENTS.md. Create one?"
    *   `options`: `"Create from template"` / `"Skip"`

#### Pass 2: Invariant Capture

1.  **Review Conversation**: Using agent judgment, scan the session for insights that could become invariants:
    *   Repeated corrections or clarifications from the user
    *   "Always do X" / "Never do Y" patterns that emerged
    *   Friction points that led to learnings
    *   New constraints discovered during implementation
    *   Mistakes that should be prevented in future sessions
2.  **Check for Candidates**: Identify up to 5 potential invariants. For each, draft:
    *   A name following the `¶INV_NAME` convention (e.g., `¶INV_CACHE_BEFORE_LOOP`)
    *   A one-line rule summary
    *   A reason explaining why this matters
3.  **If No Candidates**: Skip silently.
4.  **If Candidates Found**: For each invariant (max 5), execute `AskUserQuestion` with:
    *   `question`: "Add this invariant? **¶INV_NAME**: [rule summary]"
    *   `header`: "Invariant"
    *   `options`:
        *   `"Add to shared (~/.directives/INVARIANTS.md)"` — Universal rules across all projects
        *   `"Add to project (.directives/INVARIANTS.md)"` — Project-specific rules
        *   `"Skip this one"` — Do not add
    *   `multiSelect`: false
5.  **On Selection**:
    *   **If "Skip"**: Continue to next invariant.
    *   **If "shared" or "project"**: Append using Edit tool:
        ```
        *   **¶INV_NAME**: [One-line rule]
            *   **Rule**: [Detailed rule description]
            *   **Reason**: [Why this matters]
        ```
    *   **If project file doesn't exist**: Create with standard header.
6.  **Report**: "Added invariants: `¶INV_X` (shared), `¶INV_Y` (project)." or skip silently if none.

#### Pass 3: Pitfall Capture

1.  **Review Session**: Using agent judgment, identify "gotchas" and traps encountered during the session:
    *   Surprising behavior that wasn't obvious from docs or code
    *   Debugging dead ends that wasted significant time
    *   Counterintuitive API behavior or framework quirks
    *   Configuration traps or environment-specific issues
    *   Common mistakes that future sessions should avoid
2.  **Check for Candidates**: Identify up to 5 potential pitfalls. For each, draft:
    *   A short title (e.g., "Gemini rejects schemas with .min() constraints")
    *   A description of the pitfall (what happens, why it's surprising)
    *   A mitigation or workaround
3.  **If No Candidates**: Skip silently.
4.  **If Candidates Found**: For each pitfall (max 5), execute `AskUserQuestion` with:
    *   `question`: "Capture this pitfall? **[Title]**: [description]"
    *   `header`: "Pitfall"
    *   `options`:
        *   `"Add to nearest PITFALLS.md"` — The PITFALLS.md closest to where the issue occurred (walk-up from the affected directory)
        *   `"Add to project (.directives/PITFALLS.md)"` — Project-level pitfalls file
        *   `"Create new PITFALLS.md here"` — Create in the most relevant directory
        *   `"Skip this one"` — Do not capture
    *   `multiSelect`: false
5.  **On Selection**:
    *   **If "Skip"**: Continue to next pitfall.
    *   **If a destination is chosen**: Append using Edit tool. Format:
        ```markdown
        ### [Title]
        **Context**: [When/where this pitfall occurs]
        **Trap**: [What goes wrong and why it's surprising]
        **Mitigation**: [How to avoid or work around it]
        ```
    *   **If file doesn't exist**: Create with standard header:
        ```markdown
        # Pitfalls

        Known gotchas and traps in this area. Read before working here.

        ```
6.  **Report**: "Added pitfalls: [titles and destinations]." or skip silently if none.

**Constraints**:
*   **Agent judgment only**: All three passes use agent judgment to identify candidates — no explicit markers or log scanning required.
*   **Max 5 per pass**: Focus on the most valuable captures. Avoid prompt fatigue.
*   **Non-blocking**: If user selects "Skip" for everything, the session continues normally.
*   **Idempotent**: Check existing entries before suggesting to avoid duplicates.
*   **Order matters**: AGENTS.md first (factual/structural), then invariants (rules), then pitfalls (warnings). Each pass is independent.
*   **Skip silently**: Each pass independently decides whether it has candidates. An empty pass produces no output and no prompt.
*   **Template location**: Scaffolding templates for all directive types live in `~/.claude/engine/.directives/templates/TEMPLATE_*.md`.
