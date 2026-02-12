# Automatic Guards Reference

This document catalogs every mechanical guard in the workflow engine that blocks agent progress. Guards are enforcement mechanisms — they prevent agents from skipping protocol steps by blocking tool use or rejecting commands until prerequisites are met.

**Why guards exist**: Agents systematically skip steps they judge as "unnecessary." Guards remove this judgment call — the protocol decides, not the agent.

---

## How Guards Work

Guards operate at two levels:

1. **Hook-based guards** — Registered in `settings.local.json` as Claude Code hooks. They fire automatically before/after tool calls or on user input. The agent cannot bypass them.
2. **Script-level gates** — Validation logic inside `session.sh` commands. They fire when the agent calls a specific command (activate, deactivate, phase, check).

**Error prefixes**: Guard messages use `§CMD_*` (command enforcement) or `¶INV_*` (invariant enforcement) prefixes to identify which rule is being enforced.

---

## PreToolUse Guards

These fire **before every tool call**. If they deny, the tool does not execute.

### 1. Session Gate

**Hook**: `pre-tool-use-session-gate.sh`
**Enforces**: `§CMD_REQUIRE_ACTIVE_SESSION`
**Purpose**: Blocks all tools until the agent formally activates a session via a skill invocation.

**When it fires**: When `SESSION_REQUIRED=1` (default) and no active session exists, or the previous session is completed.

**What it blocks**: All tools except a whitelist:
- `AskUserQuestion` — always allowed (for session/skill selection)
- `Skill` — always allowed (skill invocation activates sessions)
- `Bash` — only `session.sh`, `log.sh`, `tag.sh`, `glob.sh` commands
- `Read` — only `~/.claude/*`, `.claude/*`, `*/CLAUDE.md`, `*/MEMORY.md`, session `.md` files

**Error messages**:
- `§CMD_REQUIRE_ACTIVE_SESSION: No active session. Tool use blocked.`
- `§CMD_REQUIRE_ACTIVE_SESSION: Previous session '[name]' (skill: [skill]) is completed. Tool use blocked.`

**Resolution**: Invoke a skill via the Skill tool (e.g., `Skill(skill: "implement")`), which triggers `engine session activate`.

---

### 2. Logging Heartbeat

**Hook**: `pre-tool-use-heartbeat.sh`
**Enforces**: `§CMD_LOG_BETWEEN_TOOL_USES`
**Purpose**: Ensures agents log their progress at regular intervals. Prevents "invisible work" where agents make many tool calls without recording what they're doing.

**When it fires**: After N tool calls without a `log.sh` append.

**Behavior** (configurable thresholds in `.state.json`):
| Threshold | Default | Effect |
|-----------|---------|--------|
| `toolUseWithoutLogsWarnAfter` | 3 | WARN — tool allowed, but message reminds agent to log |
| `toolUseWithoutLogsBlockAfter` | 10 | BLOCK — tool denied until agent logs |

**What resets the counter**: Any `Bash` call containing `log.sh`.

**Whitelisted** (no counting, always allowed):
- `Bash` calls to `log.sh` or `session.sh`
- `Read` of `~/.claude/*` files
- `Read` of `TEMPLATE_*_LOG.md` files
- `Task` tool launches (sub-agents have their own counters)
- `Edit` of the same file consecutively (only first edit counts)

**Skipped entirely when**:
- `loading=true` in `.state.json` (during session bootstrap, cleared by `engine session phase`)
- No active session
- No `logTemplate` set in `.state.json`

**Error messages**:
- Warn: `§CMD_LOG_BETWEEN_TOOL_USES: N/10 tool calls without logging. Log soon.`
- Block: `§CMD_LOG_BETWEEN_TOOL_USES: N tool calls without logging. Tool DENIED.`

**Resolution**: Read the log template, then append a progress entry via `log.sh`:
```bash
~/.claude/scripts/log.sh [session_dir]/[SKILL]_LOG.md <<'EOF'
## [Entry Type]
*   **Item**: ...
EOF
```

---

### 3. Context Overflow

**Hook**: `pre-tool-use-overflow.sh`
**Enforces**: `§CMD_RECOVER_SESSION`
**Purpose**: Forces context dehydration when the conversation approaches the context window limit. Prevents data loss from silent truncation.

**When it fires**: When `contextUsage` in `.state.json` >= `OVERFLOW_THRESHOLD` (default 0.76, ~97.5% of Claude's 80% auto-compact threshold).

**What it blocks**: All tools except:
- `Bash` calls to `log.sh` or `session.sh` (needed for dehydration)
- `Skill(skill: "session", args: "dehydrate")` — sets lifecycle to "dehydrating" and allows through
- All tools when `lifecycle=dehydrating` or `killRequested=true`

**Error message**:
`§CMD_RECOVER_SESSION: Context overflow — you MUST invoke the session dehydrate skill NOW.`

**Resolution**: Invoke `Skill(skill: "session", args: "dehydrate restart")`. This saves context to `DEHYDRATED_CONTEXT.md` and triggers a fresh Claude session that resumes via `/session continue`.

---

## PostToolUse Guards

These fire **after tool calls complete**. They don't block — they inject suggestions.

### 4. Directory Discovery

**Hook**: `post-tool-use-discovery.sh`
**Enforces**: `¶INV_DIRECTIVE_STACK`
**Purpose**: Discovers directive files (README.md, INVARIANTS.md, CHECKLIST.md, TESTING.md, PITFALLS.md, CONTRIBUTING.md) near files the agent touches.

**When it fires**: After any `Read`, `Edit`, or `Write` tool call that targets a new directory (not previously tracked in `touchedDirs`).

**Behavior**:
- Runs `discover-directives.sh --walk-up` from the touched directory to the project root
- **Core directives** (always suggested): `README.md`, `INVARIANTS.md`
- **Skill directives** (only if declared in session `directives` param): `TESTING.md`, `PITFALLS.md`, `CONTRIBUTING.md`
- **Hard directives** (silently tracked): `CHECKLIST.md` — added to `discoveredChecklists` in `.state.json`, enforced at deactivation
- Adds discovered soft files to `pendingDirectives` in `.state.json` for enforcement by the directive gate (Guard 4b)

**Output**: Suggestion message listing discovered files. Not a block — just guidance.

**Side effect**: Tracks `CHECKLIST.md` files in `discoveredChecklists`. Populates `pendingDirectives` for the PreToolUse directive gate.

### 4b. Directive Enforcement Gate

**Hook**: `pre-tool-use-directive-gate.sh`
**Enforces**: `¶INV_DIRECTIVE_STACK`
**Purpose**: Blocks tool calls when the agent has unread directive files. Escalating enforcement: allows first N calls (default 3), then blocks.

**When it fires**: Before any tool call, when `pendingDirectives` in `.state.json` is non-empty.

**Behavior**:
- Fast path: if `pendingDirectives` is empty, allows immediately (no overhead)
- Whitelists: `log.sh`/`session.sh` calls, `~/.claude/*` reads, `Task` tool launches
- If `Read` tool targets a file in `pendingDirectives`: removes it from the list and allows
- Increments `directiveReadsWithoutClearing` counter each non-whitelisted tool call
- If counter < `directiveBlockAfter` (default 3): allows with warning
- If counter >= `directiveBlockAfter`: blocks with list of pending files

**Resolution**: Use the `Read` tool to load each file listed in the block message. Once all pending files are read, the gate clears automatically.

---

## UserPromptSubmit Guards

These fire **when the user submits a message**. They inject system messages to guide the agent.

### 5. Session Boot Injection

**Hook**: `user-prompt-submit-session-gate.sh`
**Enforces**: `§CMD_REQUIRE_ACTIVE_SESSION`
**Purpose**: Proactively instructs the agent to load standards and select a skill when no active session exists. Complements the PreToolUse session gate (which is reactive).

**When it fires**: When `SESSION_REQUIRED=1` and no active session exists (or session is completed).

**Behavior**: Injects a system message with boot instructions:
1. Load COMMANDS.md, INVARIANTS.md, TAGS.md
2. Load project INVARIANTS.md
3. Ask the user which skill to use

**Not a block** — the agent can still respond, but the injected message directs it to activate a session.

---

## Session.sh Gates

These are validation gates inside `session.sh` commands. They fire when the agent calls a specific command and reject with `exit 1` if prerequisites are not met.

### 6. Activate: Required Field Validation

**Command**: `engine session activate <dir> <skill> <<< '{json}'`
**Enforces**: `§CMD_PARSE_PARAMETERS`
**Purpose**: Ensures agents provide all required session parameters when activating with JSON.

**When it fires**: When JSON is provided on stdin (not on re-activation with `< /dev/null`).

**Required fields** (11): `taskType`, `taskSummary`, `scope`, `directoriesOfInterest`, `preludeFiles`, `contextPaths`, `planTemplate`, `logTemplate`, `debriefTemplate`, `extraInfo`, `phases`

**Behavior**: Checks all fields at once. If any are missing, outputs ALL missing field names in a single error message.

**Error message**: `§CMD_PARSE_PARAMETERS: Missing required field(s) in JSON: [field1], [field2], ...`

**Resolution**: Include all required fields in the JSON piped to `engine session activate`.

---

### 7. Activate: Completed Skill Gate

**Command**: `engine session activate <dir> <skill>`
**Enforces**: `§CMD_PARSE_PARAMETERS`
**Purpose**: Prevents accidentally re-entering a completed skill (e.g., re-running `/implement` after it was deactivated).

**When it fires**: When the requested skill is already in the session's `completedSkills` array.

**Error message**: `§CMD_PARSE_PARAMETERS: Skill '[skill]' already completed in this session.`

**Resolution**: Use `--user-approved "Reason: [why]"` flag to explicitly re-activate a completed skill.

---

### 8. Activate: PID Conflict

**Command**: `engine session activate <dir> <skill>`
**Enforces**: `§CMD_MAINTAIN_SESSION_DIR`
**Purpose**: Prevents two agents from claiming the same session simultaneously.

**When it fires**: When a different, still-alive process (different PID) already holds `.state.json`.

**Error message**: `§CMD_MAINTAIN_SESSION_DIR: Session already active by PID [pid].`

**Resolution**: Use a different session directory, or wait for the other agent to complete.

**Note**: If the existing PID is dead (stale `.state.json`), activate cleans up automatically and proceeds.

---

### 9. Phase: Format Validation

**Command**: `engine session phase <dir> "<label>"`
**Enforces**: `§CMD_UPDATE_PHASE`
**Purpose**: Ensures phase labels follow the required format.

**Valid formats**: `N: Name` or `N.M: Name` (e.g., `"3: Interrogation"`, `"4.1: Agent Handoff"`)

**Rejected formats**: Alpha-style (`5b: Triage`), no number prefix (`Setup`), trailing dots (`5.`), underscores (`5_1`).

**Error message**: `§CMD_UPDATE_PHASE: Invalid phase format '[label]'. Must be 'N: Name' or 'N.M: Name'.`

**Resolution**: Use the correct numeric format.

---

### 10. Phase: Sequential Enforcement

**Command**: `engine session phase <dir> "<label>"`
**Enforces**: `¶INV_PHASE_ENFORCEMENT`
**Purpose**: Prevents agents from skipping phases in the protocol.

**When it fires**: When the requested phase is not the next one in sequence (as defined in the `phases` array from session activation).

**Allowed without approval**:
- Re-entering the current phase (no-op)
- Moving to the next declared phase
- Skipping optional sub-phases (e.g., 3.0 → 4.0 when 3.1 exists)
- From sub-phase to next major (e.g., 4.1 → 5.0)
- Auto-appending a new sub-phase (e.g., current 4.0, request 4.1)

**Blocked without approval**:
- Skipping forward (e.g., 2 → 5)
- Going backward (e.g., 5 → 3)

**Error message**: `§CMD_UPDATE_PHASE: Non-sequential phase transition [current] → [requested]. Expected: [next]. Use --user-approved to override.`

**Resolution**: Use `--user-approved "Reason: [user's response]"` to override, or follow the sequential order.

---

### 11. Deactivate: Three Gates (Batched)

**Command**: `engine session deactivate <dir> [--keywords ...]`
**Purpose**: Ensures sessions produce required artifacts before closing.

All three gates are evaluated together — the agent sees ALL failures at once (not one-by-one).

#### Gate A: Description Required
**Enforces**: `§CMD_CLOSE_SESSION`
**Check**: Description must be piped on stdin.
**Resolution**: Pipe 1-3 lines of description: `engine session deactivate $DIR <<< "What was done"`

#### Gate B: Debrief Required
**Enforces**: `§CMD_DEBRIEF_BEFORE_CLOSE`
**Check**: If `debriefTemplate` is set, the corresponding debrief file must exist (e.g., `IMPLEMENTATION.md` for template `TEMPLATE_IMPLEMENTATION.md`).
**Resolution**: Write the debrief via `§CMD_GENERATE_DEBRIEF`, OR skip with `--skip-debrief "Reason: ..."` (requires user approval via `AskUserQuestion`).

#### Gate C: Checklist Required
**Enforces**: `¶INV_CHECKLIST_BEFORE_CLOSE`
**Check**: If `discoveredChecklists` is non-empty, `checkPassed` must be `true` in `.state.json`.
**Resolution**: Run `§CMD_PROCESS_CHECKLISTS` which calls `engine session check` with checklist results on stdin.

---

### 12. Check: Three Validations

**Command**: `engine session check <dir>`
**Purpose**: Pre-deactivation validation. Sets `checkPassed=true` when all validations pass.

#### Validation 1: Tag Scan
**Enforces**: `¶INV_ESCAPE_BY_DEFAULT`
**Check**: Scans session `.md` files for bare inline lifecycle tags (`#needs-*`, `#claimed-*`, `#done-*`) that are not on a `**Tags**:` line and not backtick-escaped.
**Resolution**: For each bare tag — PROMOTE (create request file + escape inline) or ACKNOWLEDGE (mark as intentional). Then set `tagCheckPassed=true` via `session.sh update`.
**Skip**: If `tagCheckPassed=true` already set, this validation is skipped.

#### Validation 2: Checklist Processing
**Enforces**: `§CMD_PROCESS_CHECKLISTS` / `¶INV_CHECKLIST_BEFORE_CLOSE`
**Check**: Each discovered checklist must have a matching `## CHECKLIST: /path` block in stdin, with at least one item.
**Resolution**: Pipe checklist results on stdin with matching paths and items.
**Skip**: If no `discoveredChecklists` in `.state.json`, passes automatically.

#### Validation 3: Request Files
**Enforces**: `¶INV_REQUEST_BEFORE_CLOSE`
**Check**: Each file in `requestFiles` array must exist, have a `## Response` section, and have no bare `#needs-*` tags on the Tags line.
**Resolution**: Complete request files with response sections and fulfilled tags.
**Skip**: If no `requestFiles` declared, passes automatically.

---

## Quick Reference

| # | Guard | Hook/Script | Trigger | Error Prefix | Resolution |
|---|-------|------------|---------|--------------|------------|
| 1 | Session Gate | `pre-tool-use-session-gate.sh` | Any tool without active session | `§CMD_REQUIRE_ACTIVE_SESSION` | Invoke a skill |
| 2 | Logging Heartbeat | `pre-tool-use-heartbeat.sh` | N tool calls without logging | `§CMD_LOG_BETWEEN_TOOL_USES` | Append to log via `log.sh` |
| 3 | Context Overflow | `pre-tool-use-overflow.sh` | Context usage >= 76% | `§CMD_RECOVER_SESSION` | Invoke `/session dehydrate restart` |
| 4 | Directory Discovery | `post-tool-use-discovery.sh` | Read/Edit/Write in new directory | `¶INV_DIRECTIVE_STACK` | Read suggested files |
| 4b | Directive Gate | `pre-tool-use-directive-gate.sh` | N tool calls with unread directives | `¶INV_DIRECTIVE_STACK` | Read pending directive files |
| 5 | Session Boot | `user-prompt-submit-session-gate.sh` | User message without session | `§CMD_REQUIRE_ACTIVE_SESSION` | Load standards, select skill |
| 6 | Activate: Fields | `engine session activate` | Missing required JSON fields | `§CMD_PARSE_PARAMETERS` | Include all 11 required fields |
| 7 | Activate: Completed | `engine session activate` | Skill in `completedSkills` | `§CMD_PARSE_PARAMETERS` | Use `--user-approved` |
| 8 | Activate: PID | `engine session activate` | Another agent holds session | `§CMD_MAINTAIN_SESSION_DIR` | Use different session |
| 9 | Phase: Format | `engine session phase` | Invalid label format | `§CMD_UPDATE_PHASE` | Use `N: Name` format |
| 10 | Phase: Sequence | `engine session phase` | Non-sequential transition | `¶INV_PHASE_ENFORCEMENT` | Use `--user-approved` |
| 11a | Deactivate: Desc | `engine session deactivate` | No description piped | `§CMD_CLOSE_SESSION` | Pipe description on stdin |
| 11b | Deactivate: Debrief | `engine session deactivate` | Missing debrief file | `§CMD_DEBRIEF_BEFORE_CLOSE` | Write debrief or `--skip-debrief` |
| 11c | Deactivate: Checklist | `engine session deactivate` | Unprocessed checklists | `¶INV_CHECKLIST_BEFORE_CLOSE` | Run `engine session check` |
| 12a | Check: Tags | `engine session check` | Bare inline lifecycle tags | `¶INV_ESCAPE_BY_DEFAULT` | Promote or acknowledge tags |
| 12b | Check: Checklists | `engine session check` | Missing checklist blocks | `§CMD_PROCESS_CHECKLISTS` | Pipe checklist results |
| 12c | Check: Requests | `engine session check` | Incomplete request files | `¶INV_REQUEST_BEFORE_CLOSE` | Complete response sections |
