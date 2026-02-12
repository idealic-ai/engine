# Continue Protocol (Context Overflow Recovery)

**Role**: You are the **Session Restorer**.
**Goal**: Re-initialize a skill session after context overflow restart, then resume work at the saved phase.
**Trigger**: Invoked automatically by `session.sh restart` when context overflows. Arrives as `/session continue --session X --skill Y --phase Z --continue`.

---

## FIRST: Report Intent to User

**Action**: Before doing anything, announce your recovery plan.

**Output this blockquote**:
> **Context Overflow Recovery**
>
> Recovering session after context overflow:
> - **Session**: `[SESSION_DIR]`
> - **Skill**: `[SKILL]`
> - **Resuming at**: `[PHASE]`
> - **Mode**: `[--continue present ? "Auto-continue" : "Manual"]`
>
> I will now:
> 1. Activate session
> 2. Read dehydrated context
> 3. Load required files and skill protocol
> 4. Log the restart entry and resume session tracking
> 5. Resume at `[PHASE]`

---

## Phase 1: Activate Session

**Action**: Re-register this Claude process with the session.

```bash
engine session activate [SESSION_DIR] [SKILL] < /dev/null
```

**Announce**: "Recovering session: `[SESSION_DIR]`"

---

## Phase 2: Read Dehydrated Context

**Action**: Load the dehydrated context to understand where we left off.

**File**: `[SESSION_DIR]/DEHYDRATED_CONTEXT.md`

**Extract from dehydrated context**:
- Ultimate goal and strategy
- Last action and outcome
- Required files list
- Next steps

---

## Phase 3: Load Required Files

**Action**: Load all files listed in the "Required Files" section of dehydrated context.

**Path Conventions** (resolve correctly):

| Prefix | Location | Example |
|--------|----------|---------|
| `~/.claude/` | User home | `~/.claude/skills/loop/SKILL.md` → shared engine |
| `.claude/` | Project root | `.claude/.directives/INVARIANTS.md` → project-local config |
| `sessions/` | Project root | `sessions/2026_02_05_FOO/LOOP_LOG.md` → session artifacts |

**WARNING**: `~/.claude/` is not `.claude/`. If a file is not found, do NOT blindly swap prefixes — check which is correct for that file type.

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

## Phase 4: Load Original Skill Protocol

**Action**: Load the original skill's protocol so you know how to continue.

**File**: `~/.claude/skills/[SKILL]/SKILL.md`

Examples:
- implement → `~/.claude/skills/implement/SKILL.md`
- analyze → `~/.claude/skills/analyze/SKILL.md`
- fix → `~/.claude/skills/fix/SKILL.md`

**Note**: In v2, the protocol is inline in SKILL.md. There is no separate `references/` file.

---

## Phase 5: Resume at Saved Phase

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
  ```bash
  engine session continue [SESSION_DIR]
  ```
  This clears the `loading` flag and resets heartbeat counters without touching phase state. The saved phase in `.state.json` is the single source of truth — `continue` simply resumes the heartbeat at that phase.

**Proof-Gated Awareness**: After `session continue`, you are AT the saved phase — not past it. If dehydrated context says the current phase's work is complete, you must:
1. DO the next phase's work first (while still at the current phase in `.state.json`)
2. THEN transition with the next phase's required proof via `engine session phase`

Do NOT call `engine session phase` before doing the work — the proof fields are evidence of completed work, provided at the moment of transition.

**Announce**: "Recovered: `[SESSION_DIR]` — resuming `[SKILL]` at `[PHASE]`"

---

## Phase 6: Report Resumed Intent

**Action**: After recovery is complete, report intent for the RESUMED skill.

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
- This enables unbroken restart — user sees seamless continuation

**Manual Mode** (if `--continue` flag is NOT present):
- Wait for user confirmation before proceeding
- Ask: "Ready to continue?"

---

## Injection Framework Dependency

The Context Injection Framework (`~/.claude/engine/injections.json`) may automatically inject content via PreToolUse hooks during recovery. This is expected behavior:

- **Directive auto-injection**: The `directive-autoload` rule may inject discovered directives as you read files and touch directories.
- **Dehydration pre-load**: The `dehydration-preload` rule may inject dehydration protocol files if context usage is already elevated.
- **Session gate**: The `session-gate` rule will NOT fire once `engine session activate` succeeds (lifecycle becomes active).

Engine standards (`COMMANDS.md`, `INVARIANTS.md`, `TAGS.md`) are auto-injected by the injection framework's `standards-preload` and `directive-autoload` rules. The continue protocol relies on this injection for standards loading — no manual loading phase is needed.

---

## Constraints

- **Fresh context**: You have 0% context usage. Do NOT run `/session dehydrate restart` again.
- **Trust dehydrated context**: It was written by the previous Claude with full knowledge.
- **Follow original protocol**: Once recovered, follow the skill protocol exactly as if you were in that phase.
- **Logging**: The previous Claude logged. Continue logging per `§CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE` and `§CMD_THINK_IN_LOG`. The `engine session continue` output tells you the log file path.
