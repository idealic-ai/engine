### §CMD_MANAGE_DIRECTIVES
**Definition**: After debrief creation, manages directive files discovered during the session. Handles three concerns in one pass: README.md updates (replaces `§CMD_MANAGE_TOC`), invariant capture (replaces `§CMD_PROMPT_INVARIANT_CAPTURE`), and pitfall capture (new).
**Trigger**: Called by `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE` step 8, after debrief is written.

**Directive Types Managed**:

| Type | File | Action |
|------|------|--------|
| **README** | `README.md` | Update descriptions of documentation files touched this session |
| **Invariant** | `INVARIANTS.md` | Capture new rules/constraints discovered during the session |
| **Pitfall** | `PITFALLS.md` | Capture "gotchas" and traps discovered during the session |
| **Testing** | `TESTING.md` | No end-of-session action (read-only during build — used for test guidance) |
| **Checklist** | `CHECKLIST.md` | No end-of-session action (enforced by `§CMD_PROCESS_CHECKLISTS`) |
| **Contributing** | `CONTRIBUTING.md` | Pass 4: Capture file patterns and conventions |

**Algorithm**:

#### Pass 1: README Updates

1.  **Collect File Manifest**: Gather documentation files touched this session:
    *   **Created**: New files (candidates for README mention)
    *   **Modified**: Updated files (descriptions may be stale)
    *   **Deleted**: Removed files (remove stale references)
    *   **Scope**: Only files under `docs/` or other documentation directories. Exclude session artifacts (`sessions/`), templates, and standards.
2.  **Check Each Discovered README.md**: For each README.md in `discoveredDirectives` (from `.state.json`), check if any touched doc files are in its directory tree.
3.  **If No Changes**: Skip silently.
4.  **If Changes Found**: Present via `AskUserQuestion` (multiSelect: true):
    *   `question`: "Documentation files were touched near these READMEs. Which updates should I apply?"
    *   `header`: "README updates"
    *   `options` (up to 4, batch if more):
        *   `"Update: path/to/README.md"` — description: `"[N] doc files changed in this tree. Will refresh descriptions."`
    *   For each selected README: Read it, identify entries referencing touched files, regenerate descriptions from current file content.
5.  **Apply**: Use Edit tool to update. Report: "READMEs updated: [list]."

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
        *   `"Add to shared (~/.claude/directives/INVARIANTS.md)"` — Universal rules across all projects
        *   `"Add to project (.claude/directives/INVARIANTS.md)"` — Project-specific rules
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
        *   `"Add to project (.claude/directives/PITFALLS.md)"` — Project-level pitfalls file
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

#### Pass 4: Contributing-Pattern Capture

1.  **Review Session**: Using agent judgment, identify file patterns and conventions established or followed during the session:
    *   New files created that establish a pattern (e.g., "every workflow gets a `__tests__/` directory")
    *   Barrel files (index.ts) that were updated or should be updated
    *   Naming conventions followed (e.g., `*.workflow.ts`, `*.activity.ts`)
    *   Example files that serve as templates for future similar files
    *   Import/export patterns specific to the directory
2.  **Check for Candidates**: Identify up to 5 potential contributing patterns. For each, draft:
    *   A short title (e.g., "Workflow file naming convention")
    *   A description of the pattern and when to follow it
    *   An example file reference if applicable
3.  **If No Candidates**: Skip silently.
4.  **If Candidates Found**: For each pattern (max 5), execute `AskUserQuestion` with:
    *   `question`: "Capture this contributing pattern? **[Title]**: [description]"
    *   `header`: "Contributing"
    *   `options`:
        *   `"Add to nearest CONTRIBUTING.md"` — The CONTRIBUTING.md closest to where the pattern applies (walk-up from the affected directory)
        *   `"Create new CONTRIBUTING.md here"` — Create in the most relevant directory
        *   `"Skip this one"` — Do not capture
    *   `multiSelect`: false
5.  **On Selection**:
    *   **If "Skip"**: Continue to next pattern.
    *   **If a destination is chosen**: Append or create using Edit tool. Use the TEMPLATE_CONTRIBUTING.md structure:
        ```markdown
        ### [Title]
        **Pattern**: [What the convention is]
        **When**: [When to follow it]
        **Example**: [Reference file or inline example]
        ```
    *   **If file doesn't exist**: Create from `TEMPLATE_CONTRIBUTING.md`.
6.  **Report**: "Added contributing patterns: [titles and destinations]." or skip silently if none.

**Constraints**:
*   **Agent judgment only**: All four passes use agent judgment to identify candidates — no explicit markers or log scanning required.
*   **Max 5 per pass**: Focus on the most valuable captures. Avoid prompt fatigue.
*   **Non-blocking**: If user selects "Skip" for everything, the session continues normally.
*   **Idempotent**: Check existing entries before suggesting to avoid duplicates.
*   **Order matters**: README first (factual), then invariants (rules), then pitfalls (warnings), then contributing patterns (conventions). Each pass is independent.
*   **Skip silently**: Each pass independently decides whether it has candidates. An empty pass produces no output and no prompt.
