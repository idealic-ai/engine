# Agent Handoff & Coordination (HANDOFF.md)

This document is the comprehensive reference for inter-agent coordination and work handoff in the workflow engine.

---

## 1. Overview

**What is handoff?** Transferring work from one agent (or session) to another, with proper context and coordination to prevent duplication or lost work.

**When to use handoff?**
- Work requires a different skill set (e.g., brainstorm -> implement)
- Work is long-running and may outlive the current session
- Work should be parallelized across multiple agents
- You want async execution (fire and forget, poll later)

### The Three Handoff Patterns

| Pattern | Mechanism | Execution | Coordination |
|---------|-----------|-----------|--------------|
| **Sub-Agents** | `Task` tool | Synchronous | Same conversation, foreground |
| **Tagged Requests** | `#needs-*` tags | Asynchronous | Cross-session, file-based |
| **Daemon-Spawned** | `engine run --monitor-tags` + `§TAG_DISPATCH` | Parallel | Automatic, tag-triggered (`#delegated-*`) |

---

## 2. Handoff Mechanisms

### 2.1 Sub-Agents (Task Tool)

**Command**: `§CMD_HANDOFF_TO_AGENT`

**Characteristics**:
- Synchronous — parent waits for completion
- Same conversation — sub-agent sees parent's context
- Foreground — user can observe progress
- Opt-in — parent asks, user decides

**Use Cases**:
- Delegating a well-defined implementation task after planning
- Running parallel analysis that will rejoin the parent flow
- Any task where the parent needs the result immediately

**Invocation Flow**:
```
1. Parent completes planning phase
2. Parent asks: "Launch builder agent, or continue inline?"
3. User chooses "Launch agent"
4. Task tool invoked with agent definition
5. Agent executes plan, writes log and debrief
6. Parent resumes with agent's outputs
```

### 2.2 Tagged Requests (Async)

**Commands**:
- `§CMD_TAG_FILE` / `§CMD_SWAP_TAG_IN_FILE` — tag lifecycle management
- `§CMD_FIND_TAGGED_FILES` — discover tagged work items

**Characteristics**:
- Asynchronous — requester continues immediately
- Cross-session — responder is a different Claude instance
- Tag-based — `#needs-X` tags ARE the delegation mechanism
- Per-skill — each skill resolves its own tag (see `§TAG_DISPATCH`)

**Use Cases**:
- Implementation tasks that can wait (`#needs-implementation`)
- Research requests with external API latency (`#needs-research`)
- Any deferred work tagged during a session

**Mechanism**:
Every `#needs-X` tag maps 1:1 to a resolving skill (`¶INV_1_TO_1_TAG_SKILL`). When a tag is applied to a debrief or work artifact, the corresponding skill discovers and processes it.

Skills that support structured delegation have `_REQUEST.md` and `_RESPONSE.md` templates in their `assets/` folder (`¶INV_DELEGATION_VIA_TEMPLATES`). Skills without these templates process inline tags directly (reading the surrounding context).

**Lifecycle** (two paths):
```
Daemon path (async):
  #needs-X → #delegated-X → #claimed-X → #done-X
   staging    approved       worker       resolved
   (human     for daemon     picked up
    review)   dispatch       & working

Immediate path (next-skill):
  #needs-X → #next-X → #claimed-X → #done-X
   staging   claimed     worker      resolved
   (human    for next    picked up
    review)  skill       & working
```

**Key rules**:
- `#needs-X` is a staging tag — daemons MUST NOT monitor it (`¶INV_NEEDS_IS_STAGING`)
- `#needs-X` → `#delegated-X` requires human approval (`¶INV_DISPATCH_APPROVAL_REQUIRED`)
- `#next-X` is for immediate next-skill execution — daemons MUST NOT monitor it (`¶INV_NEXT_IS_IMMEDIATE`)
- Only `#delegated-X` triggers daemon dispatch

### 2.3 Research Handoff

**Commands**:
- `§CMD_AWAIT_TAG` — block until tag appears
- `/research` skill — Gemini Deep Research integration

**Characteristics**:
- External API call (Gemini Deep Research)
- Long-running (minutes to hours)
- Produces rich markdown report
- Resumable if session dies (via Interaction ID)

**Use Cases**:
- Market research, competitor analysis
- Technical deep dives requiring web search
- Any question requiring synthesis from multiple sources

**Lifecycle** (follows standard two-path model — see Section 3):
```
#needs-research → #delegated-research → #claimed-research → #done-research
   (staging)       (approved)            (API call in-flight)  (report ready)
```

---

## 3. Tag Lifecycle

All coordination uses a 5-state lifecycle with two paths. See `§FEED_*` sections in `~/.claude/.directives/TAGS.md` for the canonical reference.

### State Transitions

```
Daemon path (async — for background processing):

┌─────────────────┐
│  #needs-X       │  Staging — work identified, pending human review
└────────┬────────┘
         │ Human approves via §CMD_DISPATCH_APPROVAL
         ▼
┌─────────────────┐
│  #delegated-X   │  Approved for daemon dispatch
└────────┬────────┘
         │ Worker claims via /delegation-claim (¶INV_CLAIM_BEFORE_WORK)
         ▼
┌─────────────────┐
│  #claimed-X     │  Work in progress, claimed by agent
└────────┬────────┘
         │ Agent completes work (swap tag)
         ▼
┌─────────────────┐
│  #done-X        │  Work complete, response linked
└─────────────────┘


Immediate path (next-skill — for inline execution):

┌─────────────────┐
│  #needs-X       │  Staging — work identified, pending human review
└────────┬────────┘
         │ Human selects "Claim for next skill" via §CMD_DISPATCH_APPROVAL
         ▼
┌─────────────────┐
│  #next-X        │  Claimed for immediate next-skill execution
└────────┬────────┘
         │ Next skill auto-claims on activation
         ▼
┌─────────────────┐
│  #claimed-X     │  Work in progress, claimed by agent
└────────┬────────┘
         │ Agent completes work (swap tag)
         ▼
┌─────────────────┐
│  #done-X        │  Work complete, response linked
└─────────────────┘
```

### Claiming Semantics

**CRITICAL**: An agent MUST swap `#delegated-X` → `#claimed-X` **before** starting work (`¶INV_CLAIM_BEFORE_WORK`).

Note: Agents claim from `#delegated-X` (not `#needs-X`). The `#needs-X` → `#delegated-X` transition requires human approval (`¶INV_DISPATCH_APPROVAL_REQUIRED`).

This prevents double-processing:
1. Human approves `#needs-implementation` → `#delegated-implementation`
2. Agent A sees `#delegated-implementation`, swaps to `#claimed-implementation`
3. Agent B sees `#claimed-implementation`, skips (already claimed)
4. Agent A completes, swaps to `#done-implementation`

**Implementation**:
```bash
engine tag swap "$FILE" '#delegated-implementation' '#claimed-implementation'
```

### Tag Discovery

```bash
# Find all open implementation requests
engine tag find '#needs-implementation'

# Find with context (line numbers + lookaround)
engine tag find '#needs-implementation' sessions/ --context
```

---

## 4. Weight Tags

Weight tags express urgency and effort. They are **optional metadata** — absence means default priority (P2) and unknown effort.

### Priority Tags

| Tag | Meaning | Scheduling |
|-----|---------|------------|
| `#P0` | Critical | Blocks everything. Process immediately. |
| `#P1` | Important | Should be done soon. Higher queue priority. |
| `#P2` | Normal | Default priority (assumed if absent). |

### Effort Tags

| Tag | Meaning | Time Estimate |
|-----|---------|---------------|
| `#S` | Small | < 30 minutes |
| `#M` | Medium | 30 min - 2 hours |
| `#L` | Large | > 2 hours |

### Usage

Tags are separate and combinable:
```markdown
**Tags**: #needs-implementation #P1 #M
```

Scheduling behavior:
- **Priority-first**: P0 before P1 before P2
- **FIFO within priority**: First-in, first-out for same priority
- **Effort is informational**: For human planning, not daemon scheduling

**See Also**: `§TAG_WEIGHTS` in `~/.claude/.directives/TAGS.md`

---

## 5. The Dispatch Daemon

### 5.1 Architecture

The dispatch daemon is a background process that automatically processes tagged work items.

**Location**: `~/.claude/scripts/run.sh --monitor-tags` (daemon mode). See `~/.claude/docs/DAEMON.md` for full reference.

> **Note**: The legacy standalone `dispatch-daemon.sh` at `~/.claude/tools/dispatch-daemon/` is deprecated.

**Technology**:
- `engine run --monitor-tags` with `fswatch` for file watching
- `/delegation-claim` skill for worker-side routing
- Stateless — tags ARE the state

**Invariant** (`¶INV_DAEMON_STATELESS`): The daemon MUST NOT maintain state beyond what tags encode. `#claimed-X` IS the claim state.

### 5.2 Routing

The daemon reads the `§TAG_DISPATCH` table from `~/.claude/.directives/TAGS.md` to map tags to skills:

| Tag | Skill | Mode | Priority |
|-----|-------|------|----------|
| `#delegated-brainstorm` | `/brainstorm` | interactive | 1 (exploration unblocks decisions) |
| `#delegated-research` | `/research` | async (Gemini) | 2 (queue early) |
| `#delegated-fix` | `/fix` | interactive/agent | 3 (bugs block progress) |
| `#delegated-implementation` | `/implement` | interactive/agent | 4 |
| `#delegated-loop` | `/loop` | interactive | 4.5 (iteration workloads) |
| `#delegated-chores` | `/chores` | interactive | 5 (quick wins, filler) |
| `#delegated-documentation` | `/document` | interactive | 6 |

**Note**: Only `#delegated-*` tags trigger daemon dispatch. `#needs-*` and `#next-*` tags are ignored by the daemon. See `§TAG_DISPATCH` in `~/.claude/.directives/TAGS.md` for the canonical routing table.

### 5.3 Spawning

Each agent runs in a named `tmux` window:

**Session**: `dispatch` (created if not exists)
**Window naming**: `agent-{type}-{timestamp}`

```bash
# Example: spawned research agent
tmux new-window -t dispatch -n "agent-research-1707235200" \
  "engine run /research $REQUEST_FILE"
```

**Parallelism**: Unbounded. The daemon spawns as many agents as there are open tags.

### 5.4 Observability

**List all running agents**:
```bash
tmux list-windows -t dispatch
```

**Attach to watch live**:
```bash
tmux attach -t dispatch:agent-impl-1707235200
```

**Check agent status**:
```bash
# Each agent writes .state.json in its session
cat sessions/2026_02_06_MY_SESSION/.state.json
# Shows: pid, skill, phase, status
```

### 5.5 Failure Detection

**Detection method**: `.state.json` PID liveness check

**Algorithm**:
1. Agent claims work (swaps `#delegated-X` → `#claimed-X`)
2. Agent writes session reference to request file
3. Agent writes PID to `.state.json` in session dir
4. If daemon sees `#claimed-X` with no `#done-X`:
   - Check PID from `.state.json`
   - Dead PID = failed work
   - Options: re-queue (swap back to `#needs-X`) or alert

**Failure states**:
- `#claimed-X` + dead PID + no `#done-X` = crashed mid-work
- `#claimed-X` + live PID = still running (ok)
- `#done-X` = complete (ignore)

---

## 6. §CMD_ Reference (Summary)

All handoff-related commands are defined in `~/.claude/.directives/COMMANDS.md`. Summary:

| Command | Purpose |
|---------|---------|
| `§CMD_HANDOFF_TO_AGENT` | Synchronous sub-agent invocation |
| `§CMD_AWAIT_TAG` | Block until tag appears (fswatch) |
| `§CMD_FIND_TAGGED_FILES` | Discover files with specific tags |
| `§CMD_TAG_FILE` | Add tag to file's Tags line |
| `§CMD_UNTAG_FILE` | Remove tag from file's Tags line |
| `§CMD_SWAP_TAG_IN_FILE` | Atomically swap one tag for another |
| `§CMD_MANAGE_ALERTS` | Raise/resolve alerts during synthesis |

---

## 7. Worked Examples

### Example 1: Research Handoff (Blocking)

**Scenario**: During brainstorming, you need market data before proceeding.

```bash
# 1. Create research request
# (via /research skill)
# Creates: RESEARCH_REQUEST_MARKET_SIZE.md with #needs-research

# 2. Start background watcher
Bash("engine await-tag sessions/.../RESEARCH_REQUEST_MARKET_SIZE.md '#done-research'", run_in_background=true)

# 3. Continue other work...

# 4. When tag appears, read response
# Response is linked in request file's ## Response section
```

### Example 2: Implementation Delegation (Fire and Forget)

**Scenario**: Brainstorm session identifies a code change needed. Don't wait for it.

```bash
# 1. Tag the debrief or work artifact with #needs-implementation #P1 #M
# (via §CMD_TAG_FILE or §CMD_HANDLE_INLINE_TAG)

# 2. Worker (or manual /find-tagged) sees #needs-implementation
# 3. Builder agent spawns, swaps to #claimed-implementation
# 4. Builder completes, swaps to #done-implementation
```

### Example 3: Multi-Agent Parallel Work

**Scenario**: Multiple tasks identified during brainstorming. Process in parallel.

```markdown
# In a brainstorm output:

## Action Items
1. Refactor auth module #needs-implementation #P1 #M
2. Update API schema #needs-implementation #P1 #S
3. Fix typo in error messages #needs-chores #P2 #S
```

```bash
# Worker spawns agents per tag:
# - agent-impl-1707235200 working on auth (#needs-implementation)
# - agent-impl-1707235201 working on schema (#needs-implementation)
# - agent-chores-1707235202 working on typos (#needs-chores)

# P1 items start first (auth, schema)
# P2 item (typos) starts after P1 slots fill or P1 completes
```

---

## 8. Failure Recovery

### Stale `#claimed-*` Tags

**Symptom**: `engine tag find '#claimed-implementation'` returns files, but no agent is working on them.

**Diagnosis**:
```bash
# For each file with #claimed-X:
# 1. Check for ## Response section — if exists, should be #done-X (bug)
# 2. Check session referenced — read .state.json for PID
# 3. Check PID liveness: kill -0 $PID (0 = alive, nonzero = dead)
```

**Recovery**:
```bash
# Option A: Re-queue (swap back to #needs-X)
engine tag swap "$FILE" '#claimed-implementation' '#needs-implementation'

# Option B: Manual completion (if work was done)
engine tag swap "$FILE" '#claimed-implementation' '#done-implementation'
```

### Dead PIDs

**Symptom**: `.state.json` shows a PID that no longer exists.

**Recovery**:
```bash
# Check if work was completed (debrief exists?)
ls sessions/2026_02_06_MY_SESSION/IMPLEMENTATION.md

# If complete: clean up .state.json, swap tag to #done-X
# If incomplete: swap tag back to #needs-X for re-processing
```

### Re-Queue Protocol

When automatically re-queuing failed work:

1. Swap `#claimed-X` → `#needs-X`
2. Add a `## Recovery` section to the request file:
   ```markdown
   ## Recovery
   *   **Date**: 2026-02-06 14:30:00
   *   **Reason**: Agent PID 12345 died mid-work
   *   **Prior Session**: sessions/2026_02_06_IMPL_ATTEMPT_1/
   *   **Action**: Re-queued for processing
   ```
3. Daemon will re-process on next cycle

---

## 9. Invariants

These invariants govern handoff behavior. Canonical definitions live in `~/.claude/.directives/INVARIANTS.md`. Summary references:

*   **`¶INV_CLAIM_BEFORE_WORK`** — An agent MUST swap `#delegated-X` → `#claimed-X` before starting work. See shared INVARIANTS.md § Development Philosophy.
*   **`¶INV_DAEMON_STATELESS`** — The dispatch daemon MUST NOT maintain state beyond what tags encode. See shared INVARIANTS.md § Engine Physics.
*   **`¶INV_NEEDS_IS_STAGING`** — `#needs-X` is a staging tag; daemons MUST NOT monitor it. See shared INVARIANTS.md § Development Philosophy.
*   **`¶INV_NEXT_IS_IMMEDIATE`** — `#next-X` is an immediate-execution tag; daemons MUST NOT monitor it. See shared INVARIANTS.md § Development Philosophy.
*   **`¶INV_DISPATCH_APPROVAL_REQUIRED`** — The `#needs-X` → `#delegated-X` and `#needs-X` → `#next-X` transitions require human approval. See shared INVARIANTS.md § Development Philosophy.
*   **`¶INV_DAEMON_DEBOUNCE`** — 3-second debounce after detecting `#delegated-X`. See shared INVARIANTS.md § Development Philosophy.
