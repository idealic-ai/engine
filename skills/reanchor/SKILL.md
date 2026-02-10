---
name: reanchor
description: Re-initializes session context after context overflow restart. Internal skill - invoked by session.sh restart.
version: 2.0
tier: lightweight
trigger: internal
---

Re-initializes session context after context overflow restart.

[!!!] THIS IS A RECOVERY SKILL -- Follow the protocol EXACTLY.

[!!!] CRITICAL BOOT SEQUENCE:
1. LOAD STANDARDS: IF NOT LOADED, Read `~/.claude/.directives/COMMANDS.md`, `~/.claude/.directives/INVARIANTS.md`, and `~/.claude/.directives/TAGS.md`.
2. GUARD: "Quick task"? NO SHORTCUTS. See `¶INV_SKILL_PROTOCOL_MANDATORY`.
3. EXECUTE: FOLLOW THE PROTOCOL BELOW EXACTLY.

### ⛔ GATE CHECK — Do NOT proceed to Phase 1 until ALL are filled in:
**Output this block in chat with every blank filled:**
> **Boot proof:**
> - COMMANDS.md — §CMD spotted: `________`
> - INVARIANTS.md — ¶INV spotted: `________`
> - TAGS.md — §FEED spotted: `________`

[!!!] If ANY blank above is empty: STOP. Go back to step 1 and load the missing file. Do NOT read Phase 1 until every blank is filled.

Arguments:
- `--session`: Session directory path
- `--skill`: Original skill to resume
- `--phase`: Phase to resume at
- `--continue`: Auto-continue execution after reanchoring (no pause for user)

# Reanchor Protocol (Context Overflow Recovery)

**Role**: You are the **Session Restorer**.
**Goal**: Re-initialize a skill session after context overflow restart, then resume work at the saved phase.
**Trigger**: Invoked automatically by `session.sh restart` when context overflows.

---

## FIRST: Report Intent to User

**Action**: Before doing anything, announce your recovery plan.

**Output this blockquote**:
> **Context Overflow Recovery**
>
> Reanchoring session after context overflow restart:
> - **Session**: `[SESSION_DIR]`
> - **Skill**: `[SKILL]`
> - **Resuming at**: `[PHASE]`
> - **Mode**: `[--continue present ? "Auto-continue" : "Manual"]`
>
> I will now:
> 1. Activate session and load standards
> 2. Read dehydrated context
> 3. Load required files and skill protocol
> 4. Log the restart entry and resume session tracking
> 5. Resume at `[PHASE]`

---

## Phase 1: Activate Session

**Action**: Re-register this Claude process with the session.

```bash
engine session activate [SESSION_DIR] [SKILL]
```

**Announce**: "Reanchoring session: `[SESSION_DIR]`"

---

## Phase 2: Load Standards

**Action**: Load the core standards into context. These are required for all skills.

**Files to Read** (in order):
1. `~/.claude/.directives/COMMANDS.md` -- Command definitions
2. `~/.claude/.directives/INVARIANTS.md` -- System invariants
3. `.claude/.directives/INVARIANTS.md` -- Project invariants (if exists)

---

## Phase 3: Read Dehydrated Context

**Action**: Load the dehydrated context to understand where we left off.

**File**: `[SESSION_DIR]/DEHYDRATED_CONTEXT.md`

**Extract from dehydrated context**:
- Ultimate goal and strategy
- Last action and outcome
- Required files list
- Next steps

---

## Phase 4: Load Required Files

**Action**: Load all files listed in the "Required Files" section of dehydrated context.

**Path Conventions** (resolve correctly):
| Prefix | Location | Example |
|--------|----------|---------|
| `~/.claude/` | User home | `~/.claude/skills/refine/SKILL.md` -> shared engine |
| `.claude/` | Project root | `.claude/.directives/INVARIANTS.md` -> project-local config |
| `sessions/` | Project root | `sessions/2026_02_05_FOO/REFINE_LOG.md` -> session artifacts |

**WARNING**: `~/.claude/` is not `.claude/`. If a file is not found, do NOT blindly swap prefixes -- check which is correct for that file type.

**Priority Order**:
1. **Session artifacts first**: `_LOG.md`, `_PLAN.md`, `DETAILS.md`
2. **Skill templates**: Load templates for the original skill
3. **Source code**: Files listed in dehydrated context

**Skill Templates by Type**:
- `implement`: `~/.claude/skills/implement/assets/TEMPLATE_IMPLEMENTATION_LOG.md`, `TEMPLATE_IMPLEMENTATION.md`, `TEMPLATE_IMPLEMENTATION_PLAN.md`
- `analyze`: `~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS_LOG.md`, `TEMPLATE_ANALYSIS.md`
- `fix`: `~/.claude/skills/fix/assets/TEMPLATE_FIX_LOG.md`, `TEMPLATE_FIX.md`
- `brainstorm`: `~/.claude/skills/brainstorm/assets/TEMPLATE_BRAINSTORM_LOG.md`, `TEMPLATE_BRAINSTORM.md`
- `test`: `~/.claude/skills/test/assets/TEMPLATE_TESTING_LOG.md`, `TEMPLATE_TESTING.md`

---

## Phase 5: Load Original Skill Protocol

**Action**: Load the original skill's protocol so you know how to continue.

**File**: `~/.claude/skills/[SKILL]/SKILL.md`

Examples:
- implement -> `~/.claude/skills/implement/SKILL.md`
- analyze -> `~/.claude/skills/analyze/SKILL.md`
- fix -> `~/.claude/skills/fix/SKILL.md`

**Note**: In v2, the protocol is inline in SKILL.md. There is no separate `references/` file.

---

## Phase 6: Resume at Saved Phase

**Action**: Skip to the phase specified in arguments.

**DO NOT**:
- Repeat earlier phases (Setup, Interrogation, Planning if already done)
- Re-parse parameters (use dehydrated context)
- Re-create the session directory (already exists)

**DO**:
- Log the continuation to `_LOG.md`:
  ```bash
  engine log [SESSION_DIR]/[SKILL_UPPER]_LOG.md <<'EOF'
  ## Context Overflow Restart
  *   **Resumed At**: [PHASE]
  *   **Last Action**: [from dehydrated context]
  *   **Next Steps**: [from dehydrated context]
  EOF
  ```
- Resume session tracking with `engine session continue`:
  `engine session continue [SESSION_DIR]`
  This clears the `loading` flag and resets heartbeat counters without touching phase state. The saved phase in `.state.json` is the single source of truth — `continue` simply resumes the heartbeat at that phase.

**Proof-Gated Awareness**: After `session continue`, you are AT the saved phase — not past it. If dehydrated context says the current phase's work is complete, you must:
1. DO the next phase's work first (while still at the current phase in `.state.json`)
2. THEN transition with the next phase's required proof via `engine session phase`
Do NOT call `engine session phase` before doing the work — the proof fields are evidence of completed work, provided at the moment of transition.

**Announce**: "Reanchored: `[SESSION_DIR]` -- resuming `[SKILL]` at `[PHASE]`"

---

## Phase 7: Report Resumed Intent

**Action**: After rehydration is complete, report intent for the RESUMED skill.

**Output this blockquote**:
> **Resuming `[SKILL]`** at `[PHASE]`
>
> **Context restored from**: `DEHYDRATED_CONTEXT.md`
> - **Ultimate Goal**: [from dehydrated context]
> - **Last Action**: [from dehydrated context]
> - **Next Steps**: [from dehydrated context]
>
> Continuing now...

**Auto-Continue** (if `--continue` flag is present):
- Do NOT wait for user confirmation
- Immediately begin executing the original skill protocol from [PHASE]
- Pick up exactly where dehydrated context says you left off
- This enables unbroken restart -- user sees seamless continuation

**Manual Mode** (if `--continue` flag is NOT present):
- Wait for user confirmation before proceeding
- Ask: "Ready to continue?"

---

## Constraints

- **Fresh context**: You have 0% context usage. Do NOT run `/dehydrate restart` again.
- **Trust dehydrated context**: It was written by the previous Claude with full knowledge.
- **Follow original protocol**: Once reanchored, follow the skill protocol exactly as if you were in that phase.
- **Logging**: The previous Claude logged. Continue logging per `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` and `§CMD_THINK_IN_LOG`. The `engine session continue` output tells you the log file path.
