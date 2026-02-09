---
name: delegate
description: "Routes tagged work items to workers via async, blocking, or silent delegation. Triggers: \"delegate this\", \"route this work\", \"hand off this task\"."
version: 2.0
tier: lightweight
---

Routes tagged work items to workers via async, blocking, or silent delegation.
[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/directives/COMMANDS.md`, `~/.claude/directives/INVARIANTS.md`, and `~/.claude/directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

**Note**: This is a utility skill — no session activation. Operates within the caller's session.

### GATE CHECK — Do NOT proceed until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT proceed until every blank is filled.

# Delegate Protocol (The Router)

Lightweight utility for routing tagged work items to other agents or workers. Can be invoked standalone or mid-skill. No session activation, no log file, no debrief.

[!!!] DO NOT USE THE BUILT-IN PLAN MODE (EnterPlanMode tool). This is a utility skill with a single-phase protocol. Follow the steps below exactly.

---

## 1. Detect Context

Determine how this skill was invoked:

- **Standalone**: User typed `/delegate` directly. Look for a `#needs-X` tag and summary in the user's message or arguments.
- **Mid-skill**: Called from within another skill's protocol (e.g., during `§CMD_WALK_THROUGH_RESULTS` triage or `§CMD_CAPTURE_SIDE_DISCOVERIES`). The calling skill passes the `#needs-X` tag and surrounding context as arguments.

Extract:
- **Tag**: The `#needs-X` tag (e.g., `#needs-implementation`, `#needs-research`, `#needs-brainstorm`)
- **Summary context**: What the work item is about (from the tag's surrounding context, the user's message, or the calling skill's triage output)

If no tag is provided, ask:
Execute `AskUserQuestion` (multiSelect: false):
> "What type of work should be delegated?"
> - **"Implementation"** — Code changes, feature building (`#needs-implementation`)
> - **"Research"** — Deep investigation, domain exploration (`#needs-research`)
> - **"Brainstorm"** — Ideation, trade-off analysis (`#needs-brainstorm`)
> - **"Documentation"** — Docs updates, README writing (`#needs-documentation`)
> - **"Review"** — Code/output review and validation (`#needs-review`)
> - **"Chores"** — Routine maintenance, cleanup (`#needs-chores`)

---

## 2. Resolve Template

Use `session.sh request-template` to find the REQUEST template for the detected tag:

```bash
~/.claude/scripts/session.sh request-template '#needs-X'
```

This scans `~/.claude/skills/*/assets/TEMPLATE_*_REQUEST.md` for a template matching the tag. If no template is found, report the error and list available templates.

---

## 3. Pre-fill REQUEST

Populate the REQUEST template from current context:

- **Topic**: Derived from the tag's surrounding context or user description
- **Relevant files**: From the session's `contextPaths`, recently-read files, or the calling skill's loaded files
- **Expectations**: Derived from the tagged item — what the worker should deliver
- **Requesting session**: Current session directory (if operating within a session)

The REQUEST file must be self-contained (`¶INV_REQUEST_IS_SELF_CONTAINED`). A worker picking up this file should be able to start work without additional context from the delegating agent.

---

## 4. Show Summary + Confirm

Present a 2-3 line summary of what will be delegated. Do NOT show the full template.

Format:
> **Delegation summary:**
> - **Tag**: `#needs-X`
> - **Target skill**: `/skill-name`
> - **Topic**: [1-line description of what will be delegated]
> - **Key expectations**: [What the worker should deliver]

---

## 5. Mode Selection

Execute `AskUserQuestion` (multiSelect: false):
> "[Tag] detected: [Summary]. How should I handle it?"
> - **"Delegate — worker will notify" (Recommended)** — Write REQUEST, tag `#needs-X`, pool worker picks it up. You continue working.
> - **"Await result from worker now"** — Write REQUEST, start `await-tag.sh` for `#done-X`. Blocks until worker completes.
> - **"Spawn sub-agent to do it silently"** — Pass REQUEST content to Task tool with appropriate subagent_type. Synchronous, in-process.

---

## 6. Execute by Mode

### Mode A: Async (Delegate — worker will notify)

1. **Write REQUEST file** to current session directory via `§CMD_DELEGATE`.
   - File naming: `[SKILL_UPPER]_REQUEST_[TOPIC].md` (e.g., `IMPLEMENTATION_REQUEST_AUTH_VALIDATION.md`)
   - Topic portion is derived from the summary, uppercased, spaces replaced with underscores.

2. **Apply tag** to REQUEST file:
   ```bash
   ~/.claude/scripts/tag.sh add '[session_dir]/[REQUEST_FILE]' '#needs-X'
   ```

3. **Report**:
   > "REQUEST filed: `[REQUEST_FILE]`. Worker will notify via `#done-X` tag."

4. **Return control** to the calling skill. If invoked standalone, the skill is done.

### Mode B: Blocking (Await result from worker now)

1. **Write REQUEST file** to current session directory via `§CMD_DELEGATE`.
   - Same naming convention as Mode A.

2. **Apply tag** to REQUEST file:
   ```bash
   ~/.claude/scripts/tag.sh add '[session_dir]/[REQUEST_FILE]' '#needs-X'
   ```

3. **Start background watcher** for completion:
   ```bash
   ~/.claude/scripts/await-tag.sh '[session_dir]/[REQUEST_FILE]' '#done-X'
   ```
   Run with `run_in_background=true`. The watcher polls until the tag transitions from `#needs-X` to `#done-X`.

4. **Report**:
   > "REQUEST filed: `[REQUEST_FILE]`. Awaiting `#done-X`..."

5. **Return control**. The background watcher will notify when the worker completes.

### Mode C: Silent (Spawn sub-agent)

1. **Write REQUEST file** to current session directory via `§CMD_DELEGATE` (audit trail — even silent work gets a REQUEST breadcrumb).
   - Same naming convention as Mode A.

2. **Determine subagent_type** from tag:

   | Tag | subagent_type |
   |-----|---------------|
   | `#needs-implementation` | `builder` |
   | `#needs-research` | `researcher` |
   | `#needs-brainstorm` | `general-purpose` |
   | `#needs-documentation` | `writer` |
   | `#needs-review` | `reviewer` |
   | `#needs-chores` | `general-purpose` |

3. **Launch Task tool** with `subagent_type` and a directive containing the REQUEST expectations. The directive should include:
   - The full REQUEST content
   - The session directory path (for writing outputs)
   - Clear success criteria from the Expectations section

4. **On completion**:
   - Write a RESPONSE breadcrumb file: `[SKILL_UPPER]_RESPONSE_[TOPIC].md` in the session directory
   - Swap tag: `#needs-X` to `#done-X` on the REQUEST file:
     ```bash
     ~/.claude/scripts/tag.sh remove '[session_dir]/[REQUEST_FILE]' '#needs-X'
     ~/.claude/scripts/tag.sh add '[session_dir]/[REQUEST_FILE]' '#done-X'
     ```

5. **Report** result summary to user (2-3 lines from the sub-agent's output).

---

## 7. Return

Control returns to the calling skill protocol. If invoked standalone (not mid-skill), the skill is done.

No debrief. No session deactivation. No next-skill menu. This is a utility — it does its job and gets out of the way.

---

## Constraints

- **No session activation** (`¶INV_DELEGATE_IS_NESTABLE`): This skill does not call `session.sh activate`. It operates within the caller's session or standalone without a session.
- **REQUEST files are self-contained** (`¶INV_REQUEST_IS_SELF_CONTAINED`): A worker must be able to start work from the REQUEST file alone, without context from the delegating agent.
- **Graceful degradation** (`¶INV_GRACEFUL_DEGRADATION`):
  - Async without fleet: REQUEST file still gets written and tagged. User can run the resolving skill manually later.
  - Blocking without fleet: Falls back to async (REQUEST filed, no watcher — user checks manually).
- **Silent mode is for fully-specified work only**: If the work is ambiguous, complex, or requires interrogation, route to async or blocking instead. Silent mode skips interrogation — the REQUEST must be complete.
- **REQUEST file naming**: `[SKILL_UPPER]_REQUEST_[TOPIC].md` (e.g., `IMPLEMENTATION_REQUEST_AUTH_VALIDATION.md`, `RESEARCH_REQUEST_XACTIMATE_CODES.md`)

## Auto-Degradation

- **Blocking mode to async**: If the session dies or the watcher fails, the tag persists on disk. A pool worker (or manual user) can still pick up the REQUEST via the `#needs-X` tag.
- **Async mode to manual**: If no fleet is running (no pool workers monitoring tags), the REQUEST file is still written and tagged. The user can invoke the resolving skill manually later by reading the REQUEST file.
