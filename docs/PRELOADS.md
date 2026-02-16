# Preload System

How hooks deliver files into the agent's context window. Companion to [HOOKS.md](HOOKS.md) (fleet notifications) — this doc covers the content injection pipeline.

## Overview

The preload system ensures agents always have the right reference material in their context window — standards, commands, skill protocols, templates, and directives — without the agent having to discover and read them manually. It uses a **queue-and-deliver** architecture: hooks queue file paths into `.state.json`, and a guard rule delivers the content on the next tool call.

**Core principle**: Preloading is invisible to the agent. The agent sees `[Preloaded: path]` markers in its context and uses the content. It never calls Read on preloaded files (unless it needs to Edit them — see `INV_PRELOAD_IS_REFERENCE_ONLY`).

---

## The Pipeline (End-to-End Flow)

Content flows through 4 stages from disk to the agent's context:

```
Stage 1: SEED          Stage 2: QUEUE           Stage 3: DELIVER         Stage 4: TRACK
SessionStart hook       PostToolUse hooks         PreToolUse guard rule    .state.json
                        + PreToolUse discovery

preloadedFiles = [6     pendingPreloads += [      _claim_and_preload()    preloadedFiles += [
  core standards]         CMD files,                reads files,             delivered files]
                          templates,                builds content,        pendingPreloads -= [
                          directives]               injects via              delivered files]
                                                    additionalContext
```

**Stage 1 (Seed)**: SessionStart clears stale state and seeds `preloadedFiles` with the 6 core standards it just injected.

**Stage 2 (Queue)**: Various hooks discover files and add them to `pendingPreloads` in `.state.json`. Discovery happens via:
- Skill activation (Phase 0 CMDs + templates)
- Phase transitions (new phase's CMDs)
- File access (directive discovery via walk-up search)
- Reference resolution (§ sigil scanning in already-loaded files)

**Stage 3 (Deliver)**: On the next tool call, the PreToolUse guard evaluates rules. The `preload` rule fires when `pendingPreloads` is non-empty. It atomically claims files via `_claim_and_preload()` (preventing parallel hooks from double-delivering), reads their contents, and injects them as `[Preloaded: path]` blocks.

**Stage 4 (Track)**: Delivered files move from `pendingPreloads` to `preloadedFiles`. Future discovery checks `preloadedFiles` to avoid re-queuing.

---

## Timing: What Gets Preloaded When

### Session Startup (SessionStart hook)

**Hook**: `session-start-restore.sh`
**Fires**: On every Claude process start (startup, resume, clear, compact).

**Actions**:
1. **Clear stale state**: Resets `preloadedFiles`, `touchedDirs`, `pendingPreloads`, `pendingAllowInjections` in ALL session `.state.json` files. A new Claude process = new context window = previous preload tracking is invalid.
2. **Re-seed**: Sets `preloadedFiles` to the 6 core standards via `get_session_start_seeds()`.
3. **Inject standards**: Reads and outputs the 6 core files as `[Preloaded: path]` content via `additionalContext`.
4. **Dehydration restore** (startup only): If a `.state.json` has `dehydratedContext`, reads required files and injects them.

**Core standards** (always preloaded, always in `preloadedFiles`):
- `~/.claude/.directives/COMMANDS.md`
- `~/.claude/.directives/INVARIANTS.md`
- `~/.claude/.directives/SIGILS.md`
- `~/.claude/.directives/commands/CMD_DEHYDRATE.md`
- `~/.claude/.directives/commands/CMD_RESUME_SESSION.md`
- `~/.claude/.directives/commands/CMD_PARSE_PARAMETERS.md`

### Skill Expansion (UserPromptSubmit: Claude Code built-in)

**Mechanism**: Claude Code's built-in skill expansion, not a custom hook.
**Fires**: When the user types `/skill-name args` and presses Enter.

**What happens**: Claude Code reads the skill's SKILL.md and injects it into the agent's context as the expanded command. This is a **built-in delivery** — no hook writes to `.state.json`, no preload tracking occurs.

**The tracking gap**: SKILL.md is now in the context window, but NO tracking mechanism knows about it. The `preloadedFiles` array (seeded with 6 core standards) has no entry for SKILL.md. When the templates hook fires next (PostToolUse:Skill), it may re-deliver SKILL.md because dedup doesn't know it was already delivered by skill expansion.

### Skill Invocation (PostToolUse: templates hook)

**Hook**: `post-tool-use-templates.sh`
**Fires**: PostToolUse for `Skill` tool AND `Bash(engine session activate|continue)`.

**Actions**:
1. **Extract Phase 0 preloads**: Calls `extract_skill_preloads(SKILL_NAME)` which reads the skill's SKILL.md JSON block, finds Phase 0's `steps` + `commands` arrays, resolves each `§CMD_*` to a CMD file path, and collects template paths (`logTemplate`, `debriefTemplate`, `planTemplate`).
2. **Dedup filter**: Checks discovered paths against `preloadedFiles` in `.state.json` (if a session exists) or against SessionStart seeds (if no session yet, via `filter_preseeded_paths()`).
3. **Direct delivery**: Reads file contents and outputs as `additionalContext` JSON — zero latency, content arrives on this same tool call.
4. **State tracking**: In a subshell (best-effort, `|| true`): adds delivered paths to `preloadedFiles`, queues to `pendingPreloads`.
5. **Reference resolution**: Scans delivered files + SKILL.md for `§CMD_*`, `§FMT_*`, `§INV_*` references. Discovered refs are queued in `pendingPreloads` for lazy loading on the next tool call.

**Why direct delivery**: Phase 0 CMDs and templates are needed immediately (the agent is about to execute Phase 0 steps). Queuing them for next-tool-call delivery would cause a one-call latency gap.

**Why also queue**: The state update ensures future dedup checks work. If the direct delivery's state write fails silently (subshell `|| true`), the preload rule will re-deliver on the next call — duplicated but not lost.

### Phase Transition (PostToolUse: phase-commands hook)

**Hook**: `post-tool-use-phase-commands.sh`
**Fires**: PostToolUse for `Bash` when stdout starts with `"Phase:"` (output of `engine session phase`).

**Actions**:
1. **Read phase metadata**: From `.state.json`, reads the `phases` array entry matching the current phase's major number.
2. **Collect §CMD_ references**: From `proof`, `steps`, and `commands` arrays. Filters out non-`§CMD_` prefixed entries (data fields like `depthChosen`).
3. **Resolve to file paths**: Strips `§CMD_` prefix and lowercase suffixes (`§CMD_GENERATE_DEBRIEF_file` → `CMD_GENERATE_DEBRIEF.md`), builds path to `~/.claude/engine/.directives/commands/`.
4. **Dedup**: Checks against `preloadedFiles` in `.state.json`.
5. **Queue**: Adds new paths to `pendingPreloads` one at a time (N×lock for N files — known inefficiency).

**Why queue instead of direct delivery**: Phase commands are not urgently needed at the exact moment of transition. Queuing lets the preload rule deliver them on the next tool call with proper claim-and-preload atomicity.

### File Access (PreToolUse: directive discovery)

**Hook**: `pre-tool-use-overflow-v2.sh` → `_run_discovery()`
**Fires**: PreToolUse for `Read`, `Edit`, `Write`, `Glob`, `Grep` tools.

**Actions**:
1. **Extract directory**: Gets the directory from the tool's `file_path` or `path` parameter.
2. **Check touchedDirs**: If this directory is already tracked, skip (no re-discovery).
3. **Walk-up search**: Runs `discover-directives.sh` from the target directory up to the project root, checking `.directives/` folders at each level.
4. **Filter by skill**: Core directives (AGENTS.md, INVARIANTS.md, COMMANDS.md) are always discovered. Skill-specific directives (TESTING.md, PITFALLS.md, CONTRIBUTING.md, CHECKLIST.md) are only discovered if the active skill declares them in the `directives` parameter.
5. **Queue**: Adds discovered files to `pendingPreloads`. Tracks CHECKLIST.md in `discoveredChecklists` for the deactivation gate.

**Why in PreToolUse**: Running discovery before the tool executes means the preload rule can fire in the same tool call — the agent gets directives immediately when it first touches a new directory, not one call later.

### Preload Delivery (PreToolUse: guard rule)

**Guard**: `preload` rule in `guards.json`
**Fires**: PreToolUse when `pendingPreloads` is non-empty.

**Actions**:
1. **Claim atomically**: Calls `_claim_and_preload()` which acquires the `.state.json` lock, reads `preloadedFiles`, filters out already-claimed files (by path string AND inode for hardlink/symlink dedup), marks unclaimed files as preloaded, releases lock.
2. **Read outside lock**: After releasing the lock, reads file contents. Lock is held only for the state check/update — minimizes hold time.
3. **Resolve references**: Scans claimed files for `§CMD_*`, `§FMT_*`, `§INV_*` references. New refs are queued in `pendingPreloads` for the next cycle.
4. **Inject**: Content is stashed to `pendingAllowInjections` (for allow-urgency rules). PostToolUse injection hook (`post-tool-use-injections.sh`) delivers it as `additionalContext`.

**Allow-urgency flow**: The preload rule has `urgency: "allow"` — it doesn't block the tool call. Instead, content is stashed and delivered via the PostToolUse injection hook. This means preloaded content arrives AFTER the tool runs, not before.

**Why PreToolUse, not PostToolUse**: Three reasons the preload rule evaluates in PreToolUse even though delivery happens in PostToolUse:
1. **Same-call discovery**: `_run_discovery()` also runs in PreToolUse (step 5b in overflow-v2). It populates `pendingPreloads` BEFORE the preload rule evaluates. If discovery were in PostToolUse, there'd be a one-call delay — the agent touches a directory on call N, discovery runs after call N, preload rule fires on call N+1, delivery on call N+2. With PreToolUse: touch on call N → discovery + claim in PreToolUse N → delivery in PostToolUse N. Same call.
2. **Unified rule evaluation**: All guards (overflow, session-gate, heartbeat, preload) are evaluated in one pass by `evaluate_rules()`. The preload rule shares the same evaluation engine — separating it into PostToolUse would mean two evaluation passes.
3. **Atomic claiming**: `_claim_and_preload()` needs to run before any PostToolUse hooks fire (templates hook, phase-commands hook could also be writing to `.state.json`). Claiming in PreToolUse happens in a single, controlled context before the tool call's PostToolUse hooks scatter.

### Reference Resolution (Auto-Expansion)

**Function**: `resolve_refs()` in `lib.sh`

Every preloaded file is automatically scanned for `§CMD_*`, `§FMT_*`, `§INV_*` references. Discovered refs are queued for preloading, which triggers their own scanning when delivered — creating a natural recursive expansion through the pipeline.

**Current architecture** (fragmented): `resolve_refs()` is called from 3 places (templates hook, overflow-v2 preload rule, UPS hook) with `depth=2`. Each caller independently manages the results.

**Target architecture** (centralized): `resolve_refs()` is called from ONE place — `_auto_expand_refs()` inside `preload_ensure()` — with `depth=1`. Recursion happens naturally: when a queued ref gets delivered on the next tool call, `preload_ensure()` fires again, scans THAT file, queues ITS refs. The recursion is implicit via the preload pipeline, not explicit via a depth parameter.

**Scanning algorithm** (unchanged):

1. **Two-pass regex**: First strip code fences and backtick spans (inert per `INV_BACKTICK_INERT_SIGIL`), then extract bare `§PREFIX_NAME` patterns.
2. **Walk-up resolution**: Starting from the file's directory, check `.directives/{prefix_folder}/` at each ancestor level up to the project root, then fall back to `~/.claude/engine/.directives/`.
3. **Prefix-to-folder mapping**: `CMD → commands/`, `FMT → formats/`, `INV → invariants/`.
4. **SKILL.md exception**: SKILL.md files are excluded from CMD preloading (preserves lazy per-phase loading). SKILL.md CAN trigger FMT/INV preloading.

**What changes**: No explicit recursion or depth parameter. Each file is scanned once (depth=1) when it enters the pipeline. Its refs get queued, delivered, scanned, and their refs queued — the pipeline IS the recursion. No hook needs to know about reference resolution. `resolve_refs()` calls are removed from templates hook, overflow-v2, and UPS hook.

**What to remove after migration**:
*   `resolve_refs()` calls from `post-tool-use-templates.sh`
*   `resolve_refs()` calls from `_claim_and_preload()` in `pre-tool-use-overflow-v2.sh`
*   `resolve_refs()` calls from `user-prompt-submit-session-gate.sh`
*   The `depth` parameter in `resolve_refs()` (always 1 — pipeline handles recursion)

---

## .state.json Fields

*   **`preloadedFiles`** — Array of normalized file paths that have been injected into the current context window. Source of truth for dedup. Reset to core seeds on every SessionStart.

*   **`pendingPreloads`** — Array of file paths waiting to be delivered. Populated by templates hook, phase-commands hook, directive discovery, and reference resolution. Consumed by the preload guard rule via `_claim_and_preload()`.

*   **`pendingAllowInjections`** — Array of `{ruleId, content}` objects. Stashed by PreToolUse (for allow-urgency rules like preload). Consumed by PostToolUse injections hook with atomic read+clear under lock.

*   **`touchedDirs`** — Map of `{directory: [directive_files]}`. Tracks which directories have been scanned for directives to prevent re-discovery.

*   **`discoveredChecklists`** — Array of CHECKLIST.md paths found during directive discovery. Used by the deactivation gate (`INV_CHECKLIST_BEFORE_CLOSE`).

---

## Pre-Seed Mechanism (Before Session Activation)

There's a timing gap between SessionStart (Claude process starts) and session activation (agent calls `engine session activate`). During this gap, there is no session `.state.json` to track preloads — but hooks still need dedup.

### Current Approach (Hardcoded Seeds)

SessionStart seeds `preloadedFiles` in ALL existing session `.state.json` files with the 6 core standard paths. The seed function `get_session_start_seeds()` returns these paths deterministically. When a skill is invoked before a session exists, the templates hook calls `filter_preseeded_paths()` which compares against these seeds without needing a `.state.json`.

**Flow**:
1. Claude starts → SessionStart clears all `.state.json` preload fields, re-seeds `preloadedFiles = [6 core paths]`.
2. User invokes `/implement` → **skill expansion delivers SKILL.md** (untracked).
3. Skill tool fires → templates hook extracts Phase 0 CMDs.
4. Templates hook checks: is there an active session? No (not activated yet).
5. Templates hook calls `filter_preseeded_paths()` → removes paths matching the 6 core seeds.
6. Templates hook delivers CMDs + templates directly. **Also re-delivers SKILL.md on the Bash(activate) path** because SKILL.md from step 2 was never tracked.
7. Agent calls `engine session activate` → `.state.json` is created/updated.
8. From this point, all hooks use `.state.json:preloadedFiles` for dedup.

**Problem**: Step 2 is a black hole. `filter_preseeded_paths()` only knows the 6 core standards. SKILL.md delivered by skill expansion, and Phase 0 CMDs delivered by the templates hook in step 6, are not tracked anywhere persistent until a session `.state.json` exists. If the templates hook's best-effort state write (step 6, `|| true`) fails silently, the preload rule will re-deliver on the next call.

### Target Design: Per-Transcript Seed State File

A per-transcript seed `.state.json` bridges the gap between SessionStart and session activation. It uses the same schema as a session `.state.json` — meaning all existing hooks that know how to read/write `.state.json` can work with it — but exists independently before any session is created.

**Location**: `sessions/.seeds/{pid}.json`

A dedicated `.seeds/` subdirectory inside `sessions/`. One file per Claude process, named by PID.

**Why a subdirectory**: Keeps seeds completely isolated from session directories. No risk of `session.sh find` or `engine find-sessions` accidentally matching them — they scan `sessions/*/.state.json`, not `sessions/.seeds/`. Clean separation: `sessions/{NAME}/.state.json` = real sessions, `sessions/.seeds/{pid}.json` = ephemeral pre-session state. The directory is gitignored and auto-created.

**Discovery**: The seed file is keyed by the Claude process PID (`$PPID` from hooks, since hooks are child processes of Claude). PID is available everywhere — in hooks (via `$PPID`), in engine scripts (via the PID stored at session activation), and from Claude Code's process tree. No scanning needed — direct path construction: `sessions/.seeds/$PPID.json`.

**Why PID, not transcript key**: Transcript path is only available in hook input JSON — engine scripts like `session.sh activate` don't receive it. PID is universally available. A PID uniquely identifies one Claude process, which maps 1:1 to one context window. PID reuse after process death is handled by stale cleanup (see below).

**Schema**: Same as session `.state.json`. Key fields used pre-session:
- `preloadedFiles` — accumulated paths injected into this context window
- `pendingPreloads` — files queued for delivery
- `touchedDirs` — directories already scanned for directives
- `lifecycle: "seeding"` — distinguishes from real sessions (`active`, `completed`)

**Lifecycle**:

```
SessionStart                    Skill expansion           Templates hook              engine session activate
    │                               │                         │                              │
    ▼                               ▼                         ▼                              ▼
Create seed .state.json       Write SKILL.md path       Write Phase 0 CMD paths      Merge seed → session .state.json
  lifecycle: "seeding"        to seed state              to seed state                Delete seed file
  preloadedFiles: [6 seeds]
```

**Actions by hook**:

*   **SessionStart**: Creates `sessions/.seeds/{PPID}.json` (mkdir -p the directory) with `lifecycle: "seeding"`, `pid: PPID`, `preloadedFiles: [6 core standards]`. Also cleans up stale seed files where the stored PID is dead (`! kill -0 $pid`).

*   **UserPromptSubmit** (skill expansion): Writes the SKILL.md path to the seed state's `preloadedFiles`. This is the critical addition — skill expansion currently leaves no trace.

*   **PostToolUse: templates hook**: When no active session exists, finds the seed state by scanning for `lifecycle: "seeding"` (same as how hooks currently find `lifecycle: "active"`). Uses `preloadedFiles` for dedup. After delivering, writes delivered paths to the seed state.

*   **PreToolUse: overflow-v2**: When no active session exists but a seed state is found, uses it for the preload rule evaluation. Discovery writes to the seed state's `touchedDirs` and `pendingPreloads`.

*   **`engine session activate`**: Reads the seed state, merges `preloadedFiles` + `pendingPreloads` + `touchedDirs` into the new session's `.state.json`, then deletes the seed file. From this point, the session `.state.json` is the source of truth.

*   **Cleanup**: SessionStart scans `sessions/.seeds/` and checks each file's stored PID via `kill -0 $pid`. Dead process → delete the file. The `.seeds/` directory is invisible to `engine find-sessions` (which scans `sessions/*/`).

**Discovery by hooks**: Every hook computes the seed path directly: `sessions/.seeds/$PPID.json`. No scanning needed.

**Discovery by `session.sh activate`**: When activating a new session, `session.sh` checks for `sessions/.seeds/$$.json` (or the PID passed by the hook). If found, merges it into the new `.state.json` and deletes the seed. A `session.sh find-seed` subcommand provides the lookup for other callers.

**Why per-transcript**: Each Claude process has its own context window. Fleet agents run concurrently with separate transcripts — their seed files don't collide.

**Why `.state.json` shape (not a flat array)**: Hooks already know how to read/write `.state.json` via `safe_json_write`, `jq` transforms, and `state_read`. A seed file with the same schema means zero hook code changes for read/write operations — only the file discovery logic needs to fall back to `sessions/.seed-{key}.state.json` when no active session is found. `session.sh find` gains one additional scan path.

**What this fixes**:
- SKILL.md delivered by skill expansion is now tracked → templates hook won't re-deliver it
- Phase 0 CMDs delivered before session activation are tracked → preload rule won't re-deliver them
- `filter_preseeded_paths()` becomes unnecessary — the seed state IS the pre-session truth
- Session `.state.json` inherits a complete picture of the context window on activation
- Hooks that run before session activation (directive discovery, guard rules) have a real state file to work with

**Propagation**: `engine session activate` reads the seed file and merges its tracking fields into the new `.state.json`. This is a one-time handoff. The merge is additive — seed `preloadedFiles` are appended to the session's initial `preloadedFiles` (which may already have the 6 seeds from SessionStart's blanket re-seed). Duplicates are removed by `unique`.

---

## Delivery Mechanisms

Two ways content reaches the agent:

*   **Direct delivery** (PostToolUse `additionalContext`)
    *   Used by: templates hook (Phase 0 CMDs + templates)
    *   Content appears as `[Preloaded: path]` in a `<system-reminder>` tag
    *   Zero latency — arrives on the same tool call that triggered the hook
    *   State tracking is best-effort (subshell with `|| true`)

*   **Guard-rule delivery** (PreToolUse → stash → PostToolUse)
    *   Used by: preload rule (pendingPreloads from any source)
    *   PreToolUse evaluates rules → preload rule claims files → stashes content to `pendingAllowInjections`
    *   PostToolUse injections hook reads stash → delivers as `additionalContext`
    *   One-call latency from queue to delivery (queued on call N, delivered on call N+1)
    *   Atomic claim-and-preload prevents parallel hook races

---

## Dedup Architecture

Multiple hooks can discover the same file. The system prevents duplicate injection via layered dedup:

*   **Layer 1: Path comparison** — `preloadedFiles` stores normalized paths. Every hook checks this array before queuing. `normalize_preload_path()` resolves `~`, follows directory symlinks, so `~/.claude/.directives/X.md` and `~/.claude/engine/.directives/X.md` (linked) match.

*   **Layer 2: Inode comparison** — `_claim_and_preload()` builds an inode set from `preloadedFiles` and checks each candidate's inode. Catches hardlinks and symlinks that resolve to different paths but the same file.

*   **Layer 3: Stale cleanup** — Files that are already in `preloadedFiles` but still in `pendingPreloads` (stale entries from failed state writes) are cleaned up during `_claim_and_preload()`.

*   **Layer 4: Pre-seed filter** — Before a session exists, `filter_preseeded_paths()` removes SessionStart seeds. After session activation, `.state.json:preloadedFiles` takes over.

---

## Content Categories

What gets preloaded, by category:

*   **Core Standards** (6 files, SessionStart)
    *   COMMANDS.md, INVARIANTS.md, SIGILS.md
    *   CMD_DEHYDRATE.md, CMD_RESUME_SESSION.md, CMD_PARSE_PARAMETERS.md
    *   Always available from the first tool call

*   **Skill Protocol** (SKILL.md, skill expansion)
    *   Delivered by Claude Code's built-in skill expansion on `/skill` invocation
    *   Also re-delivered by templates hook on `Bash(engine session activate)` for the Bash trigger path
    *   Contains phase definitions, proof schemas, mode configurations

*   **Phase 0 CMD Files** (templates hook)
    *   Extracted from SKILL.md JSON block → `phases[0].steps` + `phases[0].commands`
    *   Delivered directly (zero latency) alongside skill activation
    *   Examples: CMD_REPORT_INTENT.md, CMD_SELECT_MODE.md, CMD_INGEST_CONTEXT_BEFORE_WORK.md

*   **Phase N CMD Files** (phase-commands hook)
    *   Queued when `engine session phase` runs
    *   Delivered on next tool call via preload rule
    *   Examples: CMD_INTERROGATE.md, CMD_GENERATE_PLAN.md, CMD_WALK_THROUGH_RESULTS.md

*   **Templates** (templates hook)
    *   Log, debrief, and plan templates from the skill's `assets/` folder
    *   Delivered directly at skill activation

*   **Directives** (PreToolUse discovery)
    *   AGENTS.md, INVARIANTS.md, CONTRIBUTING.md, PITFALLS.md, TESTING.md, CHECKLIST.md
    *   Discovered when the agent touches a new directory
    *   Walk-up search finds directives at any ancestor level
    *   Skill-specific filtering (only directives declared in the `directives` parameter)

*   **Transitive References** (resolve_refs)
    *   Files referenced via `§CMD_*`, `§FMT_*`, `§INV_*` in already-preloaded files
    *   Discovered by scanning preloaded content for bare sigiled references
    *   Queued in pendingPreloads for lazy delivery

---

## Concurrency Model

The preload system assumes hooks execute sequentially within a single Claude process (Claude Code documentation: "Hooks execute in array order from settings.json"). However, it defensively handles the parallel case:

*   **`safe_json_write()`** — mkdir-based spinlock protecting individual writes. Prevents write corruption but has a TOCTOU gap on read-modify-write.

*   **`_claim_and_preload()`** — Holds the lock across read→filter→update→release, then reads files outside the lock. Prevents parallel hooks from claiming the same files. The canonical solution for preload dedup.

*   **Injection stash** — `post-tool-use-injections.sh` uses atomic read+clear under lock. Prevents parallel PostToolUse hooks from delivering the same stashed content.

*   **Stale lock detection** — Both locking mechanisms check lock mtime. If >10s old, force-remove (crash recovery). The 10s threshold is calibrated: hooks execute in <100ms typically.

---

## Key Functions (lib.sh)

*   **`normalize_preload_path(PATH)`** — Resolves `~` to `$HOME`, follows directory symlinks via `cd + pwd -P`. Ensures consistent paths for dedup.

*   **`get_session_start_seeds()`** — Returns JSON array of the 6 core standard paths (canonical, via `normalize_preload_path`). Deterministic — any hook can call it.

*   **`filter_preseeded_paths(PATHS)`** — Removes paths matching SessionStart seeds. Used when no active session exists for `.state.json` dedup.

*   **`extract_skill_preloads(SKILL_NAME)`** — Reads SKILL.md JSON block, extracts Phase 0 CMD file paths + template paths. Outputs normalized paths, one per line.

*   **`resolve_refs(FILE, DEPTH, LOADED_JSON)`** — Scans file for `§CMD_*`/`§FMT_*`/`§INV_*` references. Walk-up resolution from file's directory. Recursive to DEPTH (default 2). Outputs resolved paths.

---

## File Locations

```
~/.claude/
  engine/
    hooks/
      session-start-restore.sh        # Stage 1: Seed (SessionStart)
      post-tool-use-templates.sh       # Stage 2: Queue + direct delivery (Skill/activate)
      post-tool-use-phase-commands.sh  # Stage 2: Queue (phase transitions)
      pre-tool-use-overflow-v2.sh      # Stage 2: Discovery + Stage 3: Deliver (preload rule)
      post-tool-use-injections.sh      # Stage 3: Deliver (allow-urgency stash → context)
    guards.json                        # Rule definitions (preload rule: id="preload")
  scripts/
    lib.sh                             # Shared functions (normalize, seeds, extract, resolve_refs)
```

---

## Known Issues

*   **Pre-session tracking gap** (critical): Between SessionStart and session activation, skill expansion delivers SKILL.md and the templates hook delivers Phase 0 CMDs — but no persistent tracking exists. The hardcoded `filter_preseeded_paths()` only knows 6 core standards. Fix: implement the per-transcript seed file described in "Target Design" above.

*   **N×lock in phase-commands**: CMD files are written to `pendingPreloads` one at a time in a loop. 8 CMD files = 8 lock acquire/release cycles. Should be batched into a single `safe_json_write`.

*   **Templates hook best-effort state write**: The `.state.json` update after direct delivery is wrapped in `( ... ) || true`. If it fails silently, dedup tracking is lost and the preload rule may re-deliver the same files. The per-transcript seed file would eliminate this issue for pre-session deliveries.

---

## Consolidation Design

The preload pipeline works but has fragmented logic — 5 hooks independently implement the same 3 operations (discover files, check dedup, deliver/queue). This section describes what's not reconciled and how to unify it.

### What's Fragmented

#### State File Discovery — "Which `.state.json` do I read?"

Every hook answers this differently:

*   **session-start-restore.sh** — Scans ALL session dirs, blanket-clears all of them
*   **user-prompt-submit-session-gate.sh** — Reads from hook input JSON context, falls back to `filter_preseeded_paths()` when no session exists
*   **post-tool-use-templates.sh** — Calls `session.sh find` (by PID), falls back to `filter_preseeded_paths()`
*   **post-tool-use-phase-commands.sh** — Parses `Phase:` stdout to extract session dir
*   **pre-tool-use-overflow-v2.sh** — Reads state file path from its own guard context

Five different fallback chains for one question. The seed file design (above) fixes this — a single `find_preload_state()` function returns the seed file pre-session or the session `.state.json` post-session.

#### Preload Extraction — "Which files should I preload?"

Three separate extraction implementations:

*   **`extract_skill_preloads()`** — Called by user-prompt-submit AND templates hook. Reads SKILL.md JSON → resolves Phase 0 `steps` + `commands` → CMD file paths. Called twice at different times for the same skill, producing overlapping results.
*   **phase-commands hook** — Has its OWN extraction logic. Reads `phases[]` array from `.state.json`, resolves CMD names with suffix-stripping (`§CMD_GENERATE_DEBRIEF_file` → `CMD_GENERATE_DEBRIEF.md`). Does NOT use `extract_skill_preloads()`.
*   **`resolve_refs()`** — A third extraction mechanism. Scans file content for `§CMD_*` patterns and resolves to file paths.

Each has its own CMD name → file path resolution with subtly different normalization.

#### Dedup Checking — "Is this already loaded?"

Four dedup mechanisms depending on timing:

*   **Pre-session**: `filter_preseeded_paths()` — hardcoded 6 seeds, nothing else
*   **Templates hook**: Inline check against `preloadedFiles` (reads `.state.json`, may see stale data from previous hook's best-effort write)
*   **Phase-commands hook**: Its own inline check against `preloadedFiles` (N×lock, one file at a time)
*   **Preload rule**: `_claim_and_preload()` — atomic path + inode dedup under lock

The first three are weaker copies of `_claim_and_preload()`. They exist because direct delivery needs dedup before the preload rule fires. But the templates hook's dedup is racy (reads stale state), and phase-commands' dedup is slow (N×lock).

#### Delivery Path Split

Two delivery paths that create a dedup gap:

*   **Direct delivery** (templates hook → `additionalContext`): Zero latency, but state tracking is best-effort `|| true`. If the state write fails, the queue path may re-deliver the same files.
*   **Queue delivery** (pendingPreloads → preload rule → claim → stash → injections hook): One-call latency, but atomic dedup via `_claim_and_preload()`.

The SKILL.md quadruple-delivery bug comes from this split — skill expansion delivers (untracked), templates hook direct-delivers (racy tracking), queue path re-delivers (stale dedup).

### Target Architecture

#### `preload_ensure(path, source, urgency)` — Single Entry Point

A single function in `lib.sh` that all hooks call instead of implementing their own logic:

```bash
# Returns: "delivered" | "queued" | "skipped"
preload_ensure() {
  local path="$1" source="$2" urgency="${3:-next}"
  local state_file normalized

  # 1. Normalize path
  normalized=$(normalize_preload_path "$path")

  # 2. Find state (seed or session)
  state_file=$(find_preload_state)

  # 3. Check dedup (path + inode) against preloadedFiles
  if _is_already_preloaded "$normalized" "$state_file"; then
    _log_delivery "$HOOK_NAME" "skip-dedup" "$normalized" "$source"
    return 0
  fi

  # 4. Deliver or queue
  if [ "$urgency" = "immediate" ]; then
    _atomic_deliver_and_track "$normalized" "$state_file"
    _log_delivery "$HOOK_NAME" "direct-deliver" "$normalized" "$source"
  else
    _queue_pending "$normalized" "$state_file"
    _log_delivery "$HOOK_NAME" "queue-pending" "$normalized" "$source"
  fi

  # 5. Auto-expand: scan for § refs and queue them
  _auto_expand_refs "$normalized" "$state_file"
}

_auto_expand_refs() {
  local file="$1" state_file="$2"

  # SKILL.md: allow FMT/INV refs but skip CMD refs (preserve lazy per-phase loading)
  local skip_cmd=false
  [[ "$file" == */SKILL.md ]] && skip_cmd=true

  local already_loaded
  already_loaded=$(jq -c '.preloadedFiles // []' "$state_file" 2>/dev/null || echo '[]')

  # depth=1: no explicit recursion — pipeline handles it naturally
  # (queued refs get delivered → preload_ensure fires → _auto_expand_refs fires → ...)
  local refs
  refs=$(resolve_refs "$file" 1 "$already_loaded")

  while IFS= read -r ref_path; do
    [ -z "$ref_path" ] && continue
    [ "$skip_cmd" = true ] && [[ "$ref_path" == */CMD_* ]] && continue
    preload_ensure "$ref_path" "auto-expand($file)" "next"
  done <<< "$refs"
}
```

**Key changes**:

*   The `immediate` path does an atomic state update under lock — not the current best-effort `( ... ) || true` subshell. This eliminates the dedup gap that causes re-delivery.
*   **Auto-expansion** (step 5): Every preloaded file is automatically scanned for `§` references. Discovered refs are queued via `preload_ensure()` itself — recursion through the pipeline, not through a depth parameter. No hook needs to call `resolve_refs()` directly.
*   **SKILL.md CMD exclusion** preserved: SKILL.md `§CMD_*` refs are skipped (lazy per-phase loading). `§FMT_*` and `§INV_*` refs from SKILL.md are expanded normally.

Hooks are reduced to two responsibilities:
*   **When to fire** (trigger conditions — unchanged)
*   **What to preload** (file list construction, then call `preload_ensure()` for each)

#### `find_preload_state()` — Single State Discovery

```bash
find_preload_state() {
  # 1. Active session .state.json (by PID)
  local session_state
  session_state=$(find_active_session_state) && { echo "$session_state"; return 0; }

  # 2. Seed file: sessions/.seeds/$PPID.json
  local seed="sessions/.seeds/${PPID}.json"
  [ -f "$seed" ] && { echo "$seed"; return 0; }

  # 3. Create seed if neither exists
  _create_seed_file "$seed"
  echo "$seed"
}
```

Every hook calls this. No more 5 different fallback chains.

#### `resolve_phase_cmds(skill, phase_label)` — Unified CMD Resolution

One function that handles both Phase 0 and Phase N extraction:

```bash
resolve_phase_cmds() {
  local skill="$1" phase_label="$2"
  # Reads SKILL.md JSON block
  # Finds the phase entry matching phase_label
  # Extracts steps[] + commands[] arrays
  # Resolves each §CMD_* to a normalized file path
  # Outputs one path per line
}
```

`extract_skill_preloads()` becomes `resolve_phase_cmds "$skill" "0"`. The phase-commands hook calls `resolve_phase_cmds "$skill" "$phase_label"`. Same resolution logic, same normalization, same suffix stripping.

### Migration Path

The consolidation can be done incrementally without breaking existing tests:

1.  **Add `find_preload_state()` + seed file** — All hooks gain a unified state discovery path. Existing fallback logic stays but is dead-coded behind the new function. Existing tests pass unchanged.
2.  **Add `preload_ensure()`** — Wrap the existing per-hook dedup+deliver logic in the unified function. Each hook migrates one at a time. Tests verify delivery counts don't change.
3.  **Replace `extract_skill_preloads()` with `resolve_phase_cmds()`** — Unify CMD resolution. The phase-commands hook drops its custom extraction.
4.  **Remove dead code** — `filter_preseeded_paths()`, per-hook inline dedup, best-effort subshells.

Each step is independently testable. The delivery event log (below) tracks regressions across the migration.

---

## E2E Testing Strategy

Preload tests need to simulate the full hook stack across a skill lifecycle — not just unit-test individual hooks. The key insight: existing tests check "is this file in `preloadedFiles`?" (boolean), but the real bugs are about **delivery counts** and **duplicate sources**. The test schema must answer: "how many times was this file delivered, and by which hooks?"

### Test Infrastructure

Tests live in `~/.claude/engine/scripts/tests/` and use the existing `test-helpers.sh` framework with `FAKE_HOME` sandbox isolation.

### Delivery Event Log

The core addition: a structured JSON log that records every delivery event across all hooks. Each hook appends to this log when it delivers or queues content.

**Location**: `$TEST_DIR/delivery-log.json` (per-test, in the sandbox)

**Schema** (one entry per delivery event):

```json
{
  "ts": "2026-02-16T14:30:00Z",
  "hook": "post-tool-use-templates",
  "event": "direct-deliver",
  "file": "~/.claude/engine/.directives/commands/CMD_REPORT_INTENT.md",
  "source": "extract_skill_preloads(implement)",
  "toolCall": 2,
  "sessionExists": false,
  "dedupResult": "new"
}
```

**Fields**:

*   **`hook`** — Which hook produced this event (`session-start-restore`, `post-tool-use-templates`, `post-tool-use-phase-commands`, `pre-tool-use-overflow-v2`, `post-tool-use-injections`)
*   **`event`** — What happened: `seed`, `direct-deliver`, `queue-pending`, `claim-deliver`, `stash-inject`, `resolve-ref`, `skip-dedup`, `skip-inode`
*   **`file`** — Normalized path of the file
*   **`source`** — Why this file was discovered (e.g., `extract_skill_preloads(implement)`, `phase_transition(3: Planning)`, `directive_discovery(/src/lib)`, `resolve_refs(CMD_INTERROGATE.md)`)
*   **`toolCall`** — Sequential tool call number in the test (1, 2, 3...)
*   **`sessionExists`** — Whether a session `.state.json` was active at delivery time
*   **`dedupResult`** — `new` (first delivery), `skip-path` (path dedup), `skip-inode` (inode dedup), `skip-seed` (pre-seed filter)

**Instrumentation**: Each hook gains a `_log_delivery()` function gated by `PRELOAD_TEST_LOG` env var. In production, the env var is unset and logging is a no-op. Tests set `PRELOAD_TEST_LOG=$TEST_DIR/delivery-log.json`.

```bash
# In each hook (gated, zero cost when disabled):
_log_delivery() {
  [ -n "${PRELOAD_TEST_LOG:-}" ] || return 0
  local hook="$1" event="$2" file="$3" source="$4"
  printf '{"hook":"%s","event":"%s","file":"%s","source":"%s","toolCall":%d,"sessionExists":%s}\n' \
    "$hook" "$event" "$file" "$source" "${TOOL_CALL_NUM:-0}" "${SESSION_EXISTS:-false}" \
    >> "$PRELOAD_TEST_LOG"
}
```

### Assertion Helpers

Built on top of the delivery log, these helpers express preload-specific assertions:

```bash
# Count how many times a file was delivered (event=direct-deliver or claim-deliver)
assert_delivery_count() {
  local file="$1" expected="$2" msg="$3"
  local actual
  actual=$(jq -r --arg f "$file" \
    '[.[] | select(.file == $f) | select(.event == "direct-deliver" or .event == "claim-deliver")] | length' \
    "$DELIVERY_LOG")
  assert_eq "$msg" "$expected" "$actual"
}

# Assert no file was delivered more than N times
assert_no_duplicates() {
  local max="${1:-1}" msg="${2:-no duplicates}"
  local dupes
  dupes=$(jq -r --argjson max "$max" '
    group_by(.file)
    | map(select(
        [.[] | select(.event == "direct-deliver" or .event == "claim-deliver")] | length > $max
      ))
    | map(.[0].file)
    | .[]
  ' "$DELIVERY_LOG")
  if [ -n "$dupes" ]; then
    fail "$msg" "max $max deliveries" "duplicates: $dupes"
  else
    pass "$msg"
  fi
}

# List all files delivered more than once, with source hooks
assert_duplicate_report() {
  local msg="$1"
  jq -r '
    [.[] | select(.event == "direct-deliver" or .event == "claim-deliver")]
    | group_by(.file)
    | map(select(length > 1))
    | map({file: .[0].file, count: length, hooks: [.[].hook] | unique})
  ' "$DELIVERY_LOG"
}

# Assert a file was delivered by a specific hook
assert_delivered_by() {
  local file="$1" hook="$2" msg="$3"
  local found
  found=$(jq -r --arg f "$file" --arg h "$hook" \
    '[.[] | select(.file == $f and .hook == $h and (.event == "direct-deliver" or .event == "claim-deliver"))] | length' \
    "$DELIVERY_LOG")
  if [ "$found" -gt 0 ]; then
    pass "$msg"
  else
    fail "$msg" "delivered by $hook" "not found"
  fi
}

# Assert delivery ordering: file A was delivered before file B
assert_delivery_order() {
  local file_a="$1" file_b="$2" msg="$3"
  local idx_a idx_b
  idx_a=$(jq -r --arg f "$file_a" '[to_entries[] | select(.value.file == $f)] | .[0].key // 999' "$DELIVERY_LOG")
  idx_b=$(jq -r --arg f "$file_b" '[to_entries[] | select(.value.file == $f)] | .[0].key // 999' "$DELIVERY_LOG")
  assert_gt "$msg" "$idx_b" "$idx_a"
}

# Get total preload token cost estimate (sum of file sizes)
get_total_preload_bytes() {
  jq -r '[.[] | select(.event == "direct-deliver" or .event == "claim-deliver") | .file] | unique | .[]' \
    "$DELIVERY_LOG" | while read -r f; do
    wc -c < "${f/#\~/$HOME}" 2>/dev/null || echo 0
  done | awk '{sum+=$1} END {print sum}'
}
```

### Relationship to Existing Tests

The existing hook test suite is the safety net — it must keep working throughout any consolidation. The preload pipeline tests are additive, not replacements.

**Existing tests (keep as-is)**:

*   **test-overflow-v2.sh** (19 cases) — Guard rules, whitelist, preload claiming via `_claim_and_preload`
*   **test-heartbeat-v2.sh** (14 cases) — Warn/block thresholds, counter, same-file suppression
*   **test-session-start-restore.sh** (9 cases) — Standards seeding, dehydration restore
*   **test-rule-engine.sh** (48+ cases) — Unified rule evaluation, triggers, priority, composition
*   **test-post-tool-use-templates.sh** — Template/SKILL.md delivery
*   **test-post-tool-use-details-log.sh** — AskUserQuestion auto-logging

These test hooks in isolation by piping JSON and checking outputs. They don't involve Claude. They validate individual hook correctness.

**The gap**: Cross-hook interaction. Each hook is unit-tested, but the pipeline (SessionStart → UPS → templates → phase-commands → preload rule) is not. A file can be delivered exactly once by each individual hook (passing unit tests) while being delivered 4× across the pipeline (failing integration). The delivery event log and pipeline tests below fill this gap.

**New test files**:

*   **test-preload-pipeline.sh** — Cross-hook integration tests using the delivery event log. Categories 1, 3, 6, 7 below.
*   **test-preload-seed.sh** — Seed file lifecycle. Category 2 below.
*   **test-preload-dedup.sh** — Duplicate detection regressions. Category 3 below.
*   **test-preload-discovery.sh** — Directive discovery edge cases. Categories 4, 5 below.
*   **test-preload-fleet.sh** — Multi-agent isolation. Category 8 below.
*   **test-preload-integration.sh** — Real skill SKILL.md files + real hooks (not mocked). Category 9 below.

### AskUserQuestion Auto-Answer (E2E Protocol Tests)

E2e protocol tests invoke real Claude to verify behavioral compliance (e.g., "does the agent produce a blockquote for `§CMD_REPORT_INTENT`?"). The problem: Claude calls `AskUserQuestion`, which blocks waiting for user input. Tests stall.

**Solution**: A PreToolUse hook that intercepts `AskUserQuestion` and returns an auto-selected answer as context.

```bash
#!/bin/bash
# e2e-auto-answer.sh — PreToolUse hook, active only when E2E_AUTO_ANSWER is set
# Gated by env var: zero cost in production

[ -n "${E2E_AUTO_ANSWER:-}" ] || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
[ "$TOOL" = "AskUserQuestion" ] || exit 0

# Extract first option label from each question
ANSWERS=$(echo "$INPUT" | jq -rc '
  .tool_input.questions // [] | map({
    question: .question,
    selected: .options[0].label
  })
')

# Block the call and inject the "answer" as context
cat <<HOOK_EOF
{
  "decision": "block",
  "reason": "[E2E Auto-Answer] User selections (auto): $ANSWERS. Treat these as the user's choices and continue execution."
}
HOOK_EOF
```

**How it works**:

1.  Set `E2E_AUTO_ANSWER=1` in the test environment
2.  Register `e2e-auto-answer.sh` as a PreToolUse hook in the test's `settings.json`
3.  When Claude calls `AskUserQuestion`, the hook blocks the call and injects "the user selected [first option]" in the block reason
4.  Claude sees the block + reason, interprets it as user input, continues without stalling

**Why "block" not "allow"**: Allowing the call would show the interactive picker and stall. Blocking with a descriptive reason tells Claude "don't wait — here's the answer."

**Answer strategies** (via `E2E_AUTO_ANSWER` value):

*   `first` — Always pick the first option (default, deterministic)
*   `recommended` — Pick the option containing "(Recommended)" in its label
*   `random` — Random selection (for fuzz/chaos testing)

**Scope**: Only for e2e protocol tests in `tests/e2e/protocol/`. Unit tests (hook tests) don't involve Claude and are unaffected.

**Location**: `~/.claude/engine/scripts/tests/e2e/hooks/e2e-auto-answer.sh`

### Test Categories

Tests are organized by what they stress. Each category targets a specific failure mode of the preload pipeline.

---

### Category 1: Lifecycle (Happy Path)

Baseline tests that simulate normal skill execution end-to-end. Every test in this category should pass with zero duplicates — if they don't, there's a regression.

#### 1.1: Full Skill Lifecycle — Zero Duplicates

Simulates: SessionStart → `/implement` → activate → Phase 0 → Phase 1 → Phase 3.A → synthesis. Asserts every file delivered exactly once.

```bash
test_full_skill_no_duplicates() {
  # SessionStart → seed created
  simulate_session_start
  # Skill expansion → SKILL.md into seed
  simulate_user_prompt_submit "implement" "add auth middleware"
  # PostToolUse:Skill → Phase 0 CMDs + templates delivered, tracked in seed
  simulate_post_tool_use "Skill" '{"skill":"implement"}'
  # Bash(activate) → seed merged into session .state.json
  simulate_engine_activate "sessions/test" "implement"
  simulate_post_tool_use "Bash" '{"command":"engine session activate sessions/test implement"}'
  # Phase 1 → new CMDs queued
  simulate_engine_phase "sessions/test" "1: Interrogation"
  simulate_post_tool_use "Bash" '{"command":"engine session phase"}'
  # PreToolUse → preload rule delivers Phase 1 CMDs
  simulate_pre_tool_use "Read" '{"file_path":"src/auth.ts"}'
  # Phase 3.A → more CMDs
  simulate_engine_phase "sessions/test" "3.A: Build Loop"
  simulate_post_tool_use "Bash" '{"command":"engine session phase"}'
  simulate_pre_tool_use "Edit" '{"file_path":"src/auth.ts"}'

  assert_no_duplicates 1 "every file delivered exactly once"
  assert_delivery_count "~/.claude/skills/implement/SKILL.md" 1 "SKILL.md once"
}
```

#### 1.2: Lightweight Skill (No Phases)

Skills like `/do`, `/session`, `/engine` have no `phases` array. Tests that SessionStart seeds + skill expansion work without phase-commands hook ever firing.

#### 1.3: Context Overflow → Restart → Resume

SessionStart (fresh) → skill → work → dehydrate → SessionStart (new process) → `/session continue`. The second SessionStart must re-seed `preloadedFiles` (new context window) and the resume must not re-deliver files that the new SessionStart already seeded.

---

### Category 2: Seed File Lifecycle

Tests the `sessions/.seeds/{pid}.json` pre-session tracking mechanism.

#### 2.1: Seed Creation and Propagation

```bash
test_seed_propagation() {
  simulate_session_start
  assert_file_exists "sessions/.seeds/$$.json" "seed created"
  assert_json "6 core seeds" "sessions/.seeds/$$.json" '.preloadedFiles | length' "6"

  simulate_user_prompt_submit "implement" "add feature"
  assert_json "SKILL.md tracked" "sessions/.seeds/$$.json" \
    '[.preloadedFiles[] | select(contains("SKILL.md"))] | length' "1"

  simulate_post_tool_use "Skill" '{"skill":"implement"}'
  local pre_count=$(jq '.preloadedFiles | length' "sessions/.seeds/$$.json")

  simulate_engine_activate "sessions/test" "implement"
  assert_file_not_exists "sessions/.seeds/$$.json" "seed deleted after merge"
  assert_json "session inherited all" "sessions/test/.state.json" \
    ".preloadedFiles | length" "$pre_count"
}
```

#### 2.2: Seed Stale Cleanup

Create seed files with dead PIDs. SessionStart must delete them.

```bash
test_seed_stale_cleanup() {
  mkdir -p sessions/.seeds
  echo '{"pid":99999,"lifecycle":"seeding","preloadedFiles":[]}' > sessions/.seeds/99999.json
  # 99999 should not be a real process
  simulate_session_start
  assert_file_not_exists "sessions/.seeds/99999.json" "stale seed cleaned"
  assert_file_exists "sessions/.seeds/$$.json" "fresh seed created"
}
```

#### 2.3: Seed Without Activation

User invokes `/implement`, seed accumulates data, but then the user cancels (never calls `engine session activate`). Seed file must persist until cleaned up by the next SessionStart. No crash, no orphaned state in sessions/.

#### 2.4: Multiple Skills Before Activation

User types `/implement something`, agent starts working, realizes it should be `/analyze` instead. Two skill expansions happen before activation. Seed must accumulate both SKILL.md paths. Only the second should survive dedup when the session is actually activated for `/analyze`.

---

### Category 3: Duplicate Detection

These tests deliberately trigger known dedup failure modes. Some document current bugs (XFAIL — expected failure that becomes expected pass after fix).

#### 3.1: SKILL.md Quadruple Delivery (Regression Test)

The known bug: skill expansion + templates(Skill) + templates(Bash:activate) + preload rule from pendingPreloads.

```bash
test_skillmd_delivery_count() {
  simulate_session_start
  simulate_user_prompt_submit "analyze" "hooks"
  simulate_post_tool_use "Skill" '{"skill":"analyze"}'
  simulate_engine_activate "sessions/test" "analyze"
  simulate_post_tool_use "Bash" '{"command":"engine session activate sessions/test analyze"}'
  simulate_pre_tool_use "Read" '{"file_path":"src/foo.ts"}'

  local count=$(assert_delivery_count_raw "SKILL.md")
  # XFAIL: current=2+, target=1. Flip assertion after seed file fix.
  echo "SKILL.md delivered $count times"
  assert_duplicate_report "SKILL.md delivery sources"
}
```

#### 3.2: CMD File Shared Across Phases

`CMD_REPORT_INTENT.md` appears in Phase 0, Phase 1, Phase 2, Phase 3.A steps. Each phase transition queues it. Dedup must prevent re-delivery.

```bash
test_shared_cmd_across_phases() {
  # Full lifecycle through 4 phase transitions
  # ... setup + 4x simulate_engine_phase ...
  assert_delivery_count "CMD_REPORT_INTENT.md" 1 "shared CMD once despite 4 phases"
  # Check that phase-commands hook logged skip-dedup events for phases 1-3
  local skips=$(jq '[.[] | select(.file | contains("CMD_REPORT_INTENT")) | select(.event == "skip-dedup")] | length' "$DELIVERY_LOG")
  assert_eq "3 dedup skips for shared CMD" "3" "$skips"
}
```

#### 3.3: Symlink Dedup (Inode Detection)

`~/.claude/.directives/` is a symlink to `~/.claude/engine/.directives/`. A file discovered via the symlink path and the canonical path must be deduplicated.

```bash
test_symlink_inode_dedup() {
  # Create a symlink like the real system has
  ln -sf "$FAKE_HOME/.claude/engine/.directives" "$FAKE_HOME/.claude/.directives"

  # One hook delivers via symlink path, another via canonical
  simulate_delivery "session-start" "~/.claude/.directives/COMMANDS.md"
  simulate_delivery "templates" "~/.claude/engine/.directives/COMMANDS.md"

  # Both paths resolve to same inode — only one delivery
  assert_delivery_count_by_inode "COMMANDS.md" 1 "symlink + canonical = 1 delivery"
}
```

#### 3.4: Concurrent PostToolUse Race

Two PostToolUse hooks fire for the same tool call. Both read `preloadedFiles` before either writes. Without the seed file or `_claim_and_preload`, both deliver the same file.

```bash
test_parallel_posttooluse_race() {
  # Simulate two hooks reading .state.json at the "same time"
  # (read state, don't write, then both try to deliver)
  local state_snapshot=$(cat "sessions/test/.state.json")

  # Hook A: reads state, sees file not in preloadedFiles
  simulate_hook_read_state "templates" "$state_snapshot"
  # Hook B: reads SAME state (before A's write), sees file not in preloadedFiles
  simulate_hook_read_state "injections" "$state_snapshot"

  # Both deliver → duplicate
  # With _claim_and_preload: lock prevents this — second hook sees first's claim
  # This test validates the lock works
  assert_no_duplicates 1 "lock prevents parallel double-delivery"
}
```

---

### Category 4: Discovery Edge Cases

Tests the directive discovery subsystem (`_run_discovery` in overflow-v2).

#### 4.1: Walk-Up Multi-Level Hierarchy

```
project/
  .directives/INVARIANTS.md          ← project-level
  packages/
    estimate/
      .directives/INVARIANTS.md      ← package-level
      .directives/PITFALLS.md        ← package-level only
      src/
        parser.ts                    ← agent touches this file
```

Agent reads `packages/estimate/src/parser.ts`. Discovery must find BOTH `INVARIANTS.md` files (package + project) plus `PITFALLS.md`. All three delivered exactly once.

#### 4.2: Same Directory, Multiple Tools

Agent calls `Read(packages/estimate/src/a.ts)` then `Edit(packages/estimate/src/b.ts)`. Both are in the same directory. Discovery should fire once (first touch), not twice. `touchedDirs` prevents re-scan.

```bash
test_same_dir_no_rediscovery() {
  simulate_pre_tool_use "Read" '{"file_path":"packages/estimate/src/a.ts"}'
  simulate_pre_tool_use "Edit" '{"file_path":"packages/estimate/src/b.ts"}'

  local discoveries=$(jq '[.[] | select(.event == "queue-pending" and .source | contains("directive_discovery"))] | length' "$DELIVERY_LOG")
  assert_eq "discovery fired once for same dir" "1" "$discoveries"
}
```

#### 4.3: Sibling Directories Share Ancestors

Agent reads from `packages/estimate/src/` then `packages/estimate/tests/`. Both are children of `packages/estimate/`. The package-level directives should NOT be re-discovered — they were found during the first walk-up. Project-level directives also already found.

#### 4.4: Skill Directive Filtering

Skill declares `directives: ["TESTING.md", "PITFALLS.md"]`. Discovery finds `CONTRIBUTING.md` in a `.directives/` folder. It must be skipped (not queued) because the skill doesn't declare it. Core directives (AGENTS.md, INVARIANTS.md) are always included regardless.

#### 4.5: Engine Root Walk-Up Cap

Files under `~/.claude/` use `--root ~/.claude` to cap the walk-up. Without this, discovery would walk up to `/Users/` and `/`, finding nothing but wasting time. Test that walk-up stops at `~/.claude/`.

---

### Category 5: Reference Resolution

Tests `resolve_refs()` — the recursive § sigil scanner.

#### 5.1: Transitive CMD Resolution

`CMD_INTERROGATE.md` references `§CMD_ASK_ROUND`. `CMD_ASK_ROUND.md` references `§CMD_LOG_INTERACTION`. After preloading `CMD_INTERROGATE.md`, both `CMD_ASK_ROUND.md` and `CMD_LOG_INTERACTION.md` must be queued in `pendingPreloads`.

#### 5.2: Backtick Escaping Respected

A CMD file contains `` `§CMD_SOMETHING` `` (backtick-escaped reference). `resolve_refs()` must NOT resolve it — backticked sigils are inert.

```bash
test_backtick_refs_ignored() {
  echo '### Algorithm
Execute §CMD_REAL_REF to start.
See `§CMD_MENTION_ONLY` for details.' > "$CMD_DIR/CMD_TEST.md"
  echo '# Real ref' > "$CMD_DIR/CMD_REAL_REF.md"
  echo '# Mention' > "$CMD_DIR/CMD_MENTION_ONLY.md"

  local refs=$(resolve_refs "$CMD_DIR/CMD_TEST.md" 1 '[]')
  assert_contains "resolves bare ref" "CMD_REAL_REF" "$refs"
  assert_not_contains "skips backticked ref" "CMD_MENTION_ONLY" "$refs"
}
```

#### 5.3: Code Fence Blocks Ignored

References inside ``` code fences ``` are inert. Entire block is skipped by the awk pass.

#### 5.4: SKILL.md CMD Exclusion

SKILL.md references many `§CMD_*` throughout its body (phase sections, documentation). `resolve_refs()` must NOT resolve CMD references from SKILL.md — that would eagerly preload ALL phase CMDs upfront, defeating lazy per-phase loading. Only `§FMT_*` references from SKILL.md are resolved.

#### 5.5: Depth Limit

With depth=2 (default), a chain A→B→C→D should resolve A, B, C but NOT D (depth exhausted). Test that the recursion stops.

#### 5.6: Circular Reference

CMD_A references §CMD_B, CMD_B references §CMD_A. Must not infinite loop. The `already_loaded` dedup prevents re-scanning.

---

### Category 6: Phase Transition Timing

Tests the phase-commands hook and its interaction with the preload rule.

#### 6.1: Phase 0 CMDs via Templates, Phase N via Phase-Commands

Phase 0 CMDs are delivered directly by the templates hook (zero latency). Phase 1+ CMDs are queued by the phase-commands hook and delivered by the preload rule (one-call latency). Test that the delivery mechanism differs but the end result is the same — each CMD file delivered once.

#### 6.2: Rapid Phase Transitions

Agent transitions Phase 1 → Phase 2 → Phase 3 in rapid succession (e.g., fast-tracked skill). Phase-commands hook fires three times. Each queues its phase's CMDs. The preload rule fires once on the next tool call and delivers ALL accumulated CMDs from all three phases in one batch.

```bash
test_rapid_phase_transitions() {
  # Three phase transitions with no tool calls in between
  simulate_engine_phase "sessions/test" "1: Investigation"
  simulate_post_tool_use "Bash" '{"command":"engine session phase"}'
  simulate_engine_phase "sessions/test" "2: Planning"
  simulate_post_tool_use "Bash" '{"command":"engine session phase"}'
  simulate_engine_phase "sessions/test" "3: Execution"
  simulate_post_tool_use "Bash" '{"command":"engine session phase"}'

  # One PreToolUse fires → preload rule delivers everything queued
  simulate_pre_tool_use "Read" '{"file_path":"src/foo.ts"}'

  # All three phases' CMDs delivered in one batch
  assert_delivered_by "CMD_INTERROGATE.md" "pre-tool-use-overflow-v2" "phase 1"
  assert_delivered_by "CMD_GENERATE_PLAN.md" "pre-tool-use-overflow-v2" "phase 2"
  assert_delivered_by "CMD_SELECT_EXECUTION_PATH.md" "pre-tool-use-overflow-v2" "phase 3"
  assert_no_duplicates 1 "no duplicates across rapid transitions"
}
```

#### 6.3: Shared CMD Across Phases (N×Lock Stress)

`CMD_APPEND_LOG` appears in the `commands` array of phases 0, 1, 2, 3, 4, 5. Each phase transition attempts to queue it. The phase-commands hook checks `preloadedFiles` each time and should skip it after the first delivery. Tests that the N×lock pattern doesn't corrupt state.

---

### Category 7: Context Overflow and Recovery

Tests interaction between preloading and the dehydration/restart cycle.

#### 7.1: Dehydration Preserves Preload State

Agent is mid-session, has preloaded 20 files. Context overflow triggers `§CMD_DEHYDRATE`. The `dehydratedContext.requiredFiles` are a subset of `preloadedFiles`. On restart, SessionStart re-seeds `preloadedFiles` with the 6 core standards AND injects the required files from dehydrated context. Both must be tracked.

#### 7.2: Restart Re-Seeds Correctly

After restart, SessionStart clears ALL `preloadedFiles` in existing `.state.json` files and re-seeds with 6 core standards. This is correct — new process = new context window. Test that the old session's `preloadedFiles` (20 files) is replaced with the 6 seeds, not appended to.

#### 7.3: Resume Doesn't Re-Deliver Already-Loaded

After restart, the agent runs `/session continue`. The templates hook fires on `Bash(engine session continue)` and tries to deliver SKILL.md + Phase 0 CMDs. But the agent is resuming at Phase 3 — Phase 0 CMDs are irrelevant (and SKILL.md is already in context from the skill expansion). Dedup must prevent re-delivery of anything that SessionStart already seeded.

---

### Category 8: Fleet / Multi-Agent Isolation

Tests that concurrent Claude processes don't interfere with each other's preload state.

#### 8.1: Separate Seed Files Per PID

Two Claude processes start simultaneously. Each creates `sessions/.seeds/{pid}.json` with its own PID. They must not collide — different PIDs, different files.

```bash
test_fleet_seed_isolation() {
  # Simulate two concurrent SessionStarts with different PPIDs
  PPID=1001 simulate_session_start
  PPID=1002 simulate_session_start
  assert_file_exists "sessions/.seeds/1001.json" "agent 1 seed"
  assert_file_exists "sessions/.seeds/1002.json" "agent 2 seed"
  # Different content (seeded independently)
  local count1=$(jq '.preloadedFiles | length' "sessions/.seeds/1001.json")
  local count2=$(jq '.preloadedFiles | length' "sessions/.seeds/1002.json")
  assert_eq "agent 1 seeds" "6" "$count1"
  assert_eq "agent 2 seeds" "6" "$count2"
}
```

#### 8.2: Session .state.json Isolation

Two agents activate different sessions. Agent A writes to `sessions/A/.state.json`, Agent B writes to `sessions/B/.state.json`. Hooks use `session.sh find` which matches by PID — Agent A's hooks must never read or write Agent B's state.

#### 8.3: Lock Contention Under Parallel Writes

Two hooks both call `safe_json_write` on the same `.state.json` simultaneously. The mkdir lock must serialize them. One wins, the other retries. No data corruption. Test by running two subshells that write different fields concurrently and verify both fields are present after.

```bash
test_lock_contention() {
  echo '{"a":0,"b":0}' > "$STATE_FILE"
  # Two concurrent writers
  (jq '.a = 1' "$STATE_FILE" | safe_json_write "$STATE_FILE") &
  (jq '.b = 1' "$STATE_FILE" | safe_json_write "$STATE_FILE") &
  wait
  # TOCTOU: one write may overwrite the other (known safe_json_write weakness)
  # With seed file approach: each process writes its own file, no contention
  local a=$(jq '.a' "$STATE_FILE")
  local b=$(jq '.b' "$STATE_FILE")
  echo "a=$a b=$b (at least one should be 1; both=1 means no race)"
}
```

---

### Category 9: Real Skill Integration

These tests invoke actual skill SKILL.md files and real hook scripts (not mocked). They run in `FAKE_HOME` but with real engine scripts symlinked in.

#### 9.1: `/implement` Full Cycle

Runs the real `extract_skill_preloads("implement")`, creates a real session, transitions through real phases. Validates that the actual CMD files for `/implement` are preloaded at the right time.

#### 9.2: `/analyze` Audit Mode

`/analyze` has different modes (Explore, Audit, Improve). Mode selection happens in Phase 0. Test that mode-specific templates are preloaded when selected.

#### 9.3: `/fix` → `/test` Skill Switch

Agent finishes `/fix`, then the user invokes `/test` in the same session directory. The second skill must preload its own Phase 0 CMDs + templates without re-delivering files from the first skill that are already in context.

#### 9.4: `/do` Lightweight — No Phase CMDs

`/do` has no `phases` array. The phase-commands hook should be a no-op. Only SKILL.md + templates are preloaded. Test that zero CMD files are queued.

### Summary Report

Each test run produces a summary report from the delivery log:

```bash
print_preload_summary() {
  echo "=== Preload Summary ==="
  echo "Total delivery events: $(jq 'length' "$DELIVERY_LOG")"
  echo "Unique files delivered: $(jq '[.[] | select(.event | test("deliver")) | .file] | unique | length' "$DELIVERY_LOG")"
  echo "Duplicate deliveries: $(jq '[.[] | select(.event | test("deliver"))] | group_by(.file) | map(select(length > 1)) | length' "$DELIVERY_LOG")"
  echo "Dedup skips: $(jq '[.[] | select(.event | test("skip"))] | length' "$DELIVERY_LOG")"
  echo ""
  echo "--- Per-Hook Delivery Counts ---"
  jq -r '[.[] | select(.event | test("deliver"))] | group_by(.hook) | map({hook: .[0].hook, count: length}) | .[] | "  \(.hook): \(.count)"' "$DELIVERY_LOG"
  echo ""
  echo "--- Duplicates ---"
  jq -r '[.[] | select(.event | test("deliver"))] | group_by(.file) | map(select(length > 1)) | map({file: .[0].file, count: length, hooks: [.[].hook]}) | .[] | "  \(.file): \(.count)x via \(.hooks | join(", "))"' "$DELIVERY_LOG"
}
