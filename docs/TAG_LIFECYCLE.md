# Tag Lifecycle Reference

This document provides the operational reference for the tag system's complete lifecycle — from creation through governance to resolution. It complements `~/.claude/.directives/TAGS.md` (which defines tag conventions, feeds, and dispatch) with detailed flow paths, mechanism descriptions, and daemon integration.

**When to use this doc**: When you need to understand how tags flow through the system, how the daemon dispatches work, or how tag promotions and cross-session resolution work.

**When to use TAGS.md**: When you need tag conventions, escaping rules, feed definitions, or the dispatch table.

---

## The Complete Tag Lifecycle — 4 States, 14 Mechanisms

### State Diagram

```
#needs-X → #delegated-X → #claimed-X → #done-X
   │           │              │           │
 staging    approved       worker      resolved
 (human     for daemon     picked up
  review)   dispatch       & working
```

**Actors**: Requester (creates `#needs-X`), Human (approves → `#delegated-X`), Worker/`/delegation-claim` (claims → `#claimed-X`), Worker/target skill (resolves → `#done-X`)

### Understanding Each State

**`#needs-X` (Staging).** A `#needs-X` tag means work has been *identified* but not yet *approved* for autonomous processing. Any agent can create one — during analysis, implementation, review, or brainstorming — whenever it discovers work that falls outside its current scope. The `#needs-X` tag is a staging area, not a dispatch trigger (`¶INV_NEEDS_IS_STAGING`). The daemon ignores `#needs-X` tags entirely. They accumulate until a human reviews them during synthesis and decides which ones are ready for dispatch.

**`#delegated-X` (Approved).** A `#delegated-X` tag means the human has explicitly approved this work item for autonomous processing. The transition from `#needs-X` to `#delegated-X` happens during `/delegation-review` and requires human judgment (`¶INV_DISPATCH_APPROVAL_REQUIRED`). The human sees the full context — the requesting session's debrief, the REQUEST file contents, any related items — and decides whether this work should proceed. Once a tag is `#delegated-X`, the daemon can detect it and spawn a worker.

**`#claimed-X` (In-Flight).** A `#claimed-X` tag means a worker has picked up this item and is actively processing it. The transition from `#delegated-X` to `#claimed-X` uses `tag.sh swap`, which is race-safe — if the tag has already been swapped by another worker, the operation errors out (`¶INV_CLAIM_BEFORE_WORK`). This prevents double-processing without requiring locks or a coordination service. While a tag is `#claimed-X`, the work is in progress and no other worker should attempt to process it.

**`#done-X` (Resolved).** A `#done-X` tag means the work has been completed. The target skill (e.g., `/implement`, `/brainstorm`) sets this after producing its debrief and RESPONSE file. A `#done-X` tag is terminal — the work item's lifecycle is complete. Cross-session resolution (`§CMD_RESOLVE_CROSS_SESSION_TAGS`) can also set `#done-X` directly on `#needs-X` items when a session's work resolves them without going through the dispatch path.

### Stage 1: Creation (Where Tags Are Born — `#needs-X`)

| # | Mechanism | Trigger | Output |
|---|-----------|---------|--------|
| 1 | `§CMD_HANDLE_INLINE_TAG` | User types `#needs-X` during dialogue | Inline tag placed in work artifact |
| 2 | `§CMD_WALK_THROUGH_RESULTS` (results mode) | User selects triage action (delegate/defer) | Inline tag applied via `§CMD_HANDLE_INLINE_TAG` |
| 3 | `§CMD_CAPTURE_SIDE_DISCOVERIES` | Agent scans log for observations/parking lot entries | User selects tag type → `tag.sh add` to Tags line |
| 4 | `§CMD_GENERATE_DEBRIEF` | Debrief creation (auto-tagging) | `#needs-review` on every debrief |
| 5 | Manual REQUEST file creation | `engine session request-template '#needs-X'` → template | Populated REQUEST file with `#needs-X` on Tags line |

### Stage 2: Governance (Quality Gates During Synthesis)

| # | Mechanism | Trigger | Output |
|---|-----------|---------|--------|
| 6 | `§CMD_RESOLVE_BARE_TAGS` | `engine session check` finds bare inline tags | PROMOTE → REQUEST file + escape inline, ACKNOWLEDGE → keep bare, ESCAPE → backtick-escape |
| 7 | `¶INV_ESCAPE_BY_DEFAULT` | `engine session check` gate | Blocks deactivation until all bare inline tags addressed |

### Stage 3: Dispatch Approval (`#needs-X` → `#delegated-X`)

| # | Mechanism | Trigger | Output |
|---|-----------|---------|--------|
| 8 | `/delegation-review` | Synthesis pipeline (after debrief, before next-skill menu) | Human reviews `#needs-X` items → approved ones flipped to `#delegated-X` |

### Stage 4: Resolution (Where Tags Die — `#delegated-X` → `#claimed-X` → `#done-X`)

| # | Mechanism | Trigger | Output |
|---|-----------|---------|--------|
| 9 | `/delegation-claim` (daemon-spawned) | Daemon detects `#delegated-X` after 3s debounce | `/delegation-claim` presents items → worker approves → `tag.sh swap` `#delegated-X` → `#claimed-X` → routes to target skill → `#done-X` |
| 10 | `/delegation-claim` (manual) | User invokes `/delegation-claim` directly | Same flow as daemon-spawned, but user-initiated |
| 11 | `§CMD_RESOLVE_CROSS_SESSION_TAGS` | Synthesis of a completing session | Scans OTHER sessions, swaps `#needs-X` → `#done-X` |
| 12 | `/review` | Manual invocation | `#needs-review` → `#done-review` (or `#needs-rework`) |
| 13 | `/document` | Manual invocation | `#needs-documentation` → `#done-documentation` |
| 14 | `§CMD_MANAGE_ALERTS` | Synthesis step | Raises `#active-alert` / resolves → `#done-alert` |

---

## Flow Paths (How Tags Travel From Creation to Resolution)

### Path A — Manual REQUEST → Dispatch Approval → Daemon → Worker (Happy Path)

```
Agent creates REQUEST file → Tags line: #needs-X
  → Synthesis runs /delegation-review
  → Human reviews and approves → tag.sh swap #needs-X → #delegated-X
  → Daemon detects #delegated-X (after 3s debounce)
  → Spawns Claude with /delegation-claim
  → /delegation-claim presents #delegated-X items → worker approves
  → tag.sh swap #delegated-X → #claimed-X (race-safe: errors if already claimed)
  → Routes to target skill (e.g., /implement)
  → Claude reads REQUEST fields (Topic, Context, Expectations)
  → Skill runs, produces debrief + RESPONSE file
  → Session deactivated → #done-X (via tag.sh swap)
```

### Path B — Walk-Through → Tag Promotion → REQUEST → Dispatch → Daemon

```
Walk-through applies inline #needs-X in debrief
  → §CMD_RESOLVE_BARE_TAGS catches bare tag during synthesis
  → User chooses "Promote"
  → REQUEST file created from skill's template + inline tag backtick-escaped
  → /delegation-review presents the REQUEST for approval
  → User approves → #delegated-X → Daemon processes via Path A
```

### Path C — Side Discovery → Tags Line → Dispatch → Daemon

```
§CMD_CAPTURE_SIDE_DISCOVERIES finds parking lot item
  → User selects tag type → tag.sh add to debrief's Tags line (#needs-X)
  → /delegation-review presents for approval
  → User approves → tag.sh swap #needs-X → #delegated-X
  → Daemon detects #delegated-X → processes via Path A
```

### Path D — Cross-Session Resolution (Direct)

```
Session A tags item #needs-X (inline or Tags line)
  → Session B does the work (may not know about Session A)
  → Session B's synthesis runs §CMD_RESOLVE_CROSS_SESSION_TAGS
  → Scans for #needs-X in other sessions → finds Session A
  → Swaps #needs-X → #done-X in Session A (direct, no dispatch needed)
```

### Path E — Auto-Review/Documentation (2-State, No Dispatch)

```
Skill completes → debrief auto-tagged #needs-review
  → /review discovers it → validates → #done-review (or #needs-rework)

Code-changing skills also auto-tag #needs-documentation
  → /delegation-review may approve → #delegated-documentation → daemon
  → Or /document invoked directly → #done-documentation
```

---

## Daemon Dispatch Details

### How the Daemon Finds Work

The daemon (`run.sh --monitor-tags`) uses `fswatch` to watch the `sessions/` directory for file changes. When a change is detected:

1. `daemon_scan_for_work` iterates through `$MONITOR_TAGS` (comma-separated list of `#delegated-*` tags — NOT `#needs-*`, per `¶INV_NEEDS_IS_STAGING`)
2. For each tag, runs `tag.sh find "$tag" "$sessions_dir" --tags-only` (searches Tags line only)
3. **Debounce** (`¶INV_DAEMON_DEBOUNCE`): After first match, wait 3 seconds for batch writes to settle, then re-scan to collect ALL `#delegated-*` items
4. Groups results by tag type (e.g., all `#delegated-implementation` together, all `#delegated-chores` together)
5. Returns grouped results for batch processing

### How the Daemon Processes Work

For each tag-type group, the daemon spawns one Claude instance:

1. **Spawn**: Runs `claude /delegation-claim` — the `/delegation-claim` skill handles all downstream logic
2. `/delegation-claim` scans for `#delegated-X` tags (same tags the daemon found)
3. `/delegation-claim` presents items to the human for claiming approval
4. On approval: `tag.sh swap #delegated-X → #claimed-X` (race-safe — errors if already claimed by another worker)
5. Routes to the target skill (e.g., `/implement`, `/brainstorm`)
6. Target skill runs, produces debrief
7. On completion: `tag.sh swap #claimed-X → #done-X`

**Key change from previous model**: The daemon no longer claims work itself. `/delegation-claim` is the worker-side skill that handles the `#delegated-X` → `#claimed-X` transition. This separation ensures the human monitoring the daemon terminal approves what gets claimed.

### Daemon Signal Handling

- `Ctrl+C` triggers `daemon_exit_handler` which sets `DAEMON_EXIT=1`
- The watchdog process is killed if Claude is running
- **Note**: If the daemon is killed while `/delegation-claim` is processing, the tag stays as `#claimed-*` and must be manually reset. If killed before `/delegation-claim` claims, the tag stays as `#delegated-*` and will be picked up on next daemon cycle.

---

## The Claim Process: Intelligent Work Bunching

The daemon does not dispatch work items one-by-one. It groups `#delegated-X` items by tag type, collects them across all sessions, and spawns one worker per tag-type group. This grouping is the key design feature that makes delegation produce high-quality results rather than fragmented, context-blind changes.

### The Concept

When `daemon_scan_for_work` finds `#delegated-*` tags, it waits for the debounce period (3 seconds, per `¶INV_DAEMON_DEBOUNCE`), re-scans to collect all available items, then groups results by tag type. All `#delegated-implementation` items become one group. All `#delegated-chores` items become another. Each group is dispatched to a single `/delegation-claim` invocation, which means the worker that picks up the group sees every item in it together.

This matters because related work from different sessions gets presented as a portfolio rather than a queue. The worker can see the full picture and make intelligent decisions about ordering, shared context, and dependencies — decisions that are impossible when items arrive in isolation.

### Example: Cross-Session Implementation Batching

Three sessions over three days each produce `#needs-implementation` items:

- **Monday** (brainstorm session): Identifies that the auth module needs rate limiting. Tags `#needs-implementation` in the REQUEST file.
- **Tuesday** (analysis session): Discovers the auth module's token refresh logic has a race condition. Tags `#needs-implementation`.
- **Wednesday** (review session): Flags that the auth module's error responses don't follow the API convention. Tags `#needs-implementation`.

During synthesis of each session, the human approves each item via `/delegation-review`, flipping them to `#delegated-implementation`. The daemon collects all three. When `/delegation-claim` runs, the worker sees all three items together — and recognizes they all touch the auth module. Instead of three isolated changes (which might conflict or duplicate setup work), the worker implements them as a coordinated batch: fix the race condition first (since rate limiting depends on correct token handling), then add rate limiting, then standardize error responses across both new and existing code paths. The ordering and coordination emerge from seeing the work together.

### Example: Mixed Tag-Type Dispatch

A daemon cycle finds 2 `#delegated-chores` items and 1 `#delegated-implementation` item across various sessions. The daemon spawns two workers:

- **Worker 1** (chores): Receives both chores items — "update the README badges" and "clean up unused test fixtures." The worker handles both in a single session, sharing the setup overhead and producing one debrief that covers both tasks.
- **Worker 2** (implementation): Receives the single implementation item and runs the full implementation protocol — interrogation, planning, execution, synthesis — with focused attention on that one task.

The chores worker benefits from batching (two small tasks are more efficient together than separately). The implementation worker benefits from isolation (the full protocol runs without distraction from unrelated chores). The tag-type grouping ensures each worker operates in the mode appropriate for its work type.

---

## REQUEST/RESPONSE Template System

### Invariant

`¶INV_DELEGATION_VIA_TEMPLATES`: A skill supports delegation if and only if it has `_REQUEST.md` and `_RESPONSE.md` templates in its `assets/` folder.

### Template Inventory

| Skill | REQUEST Template | RESPONSE Template | Tag |
|-------|-----------------|-------------------|-----|
| `/implement` | `TEMPLATE_IMPLEMENTATION_REQUEST.md` | `TEMPLATE_IMPLEMENTATION_RESPONSE.md` | `#needs-implementation` |
| `/brainstorm` | `TEMPLATE_BRAINSTORM_REQUEST.md` | `TEMPLATE_BRAINSTORM_RESPONSE.md` | `#needs-brainstorm` |
| `/document` | `TEMPLATE_DOCUMENTATION_REQUEST.md` | `TEMPLATE_DOCUMENTATION_RESPONSE.md` | `#needs-documentation` |
| `/review` | `TEMPLATE_REVIEW_REQUEST.md` | `TEMPLATE_REVIEW_RESPONSE.md` | `#needs-review` |
| `/chores` | `TEMPLATE_CHORES_REQUEST.md` | `TEMPLATE_CHORES_RESPONSE.md` | `#needs-chores` |
| `/research` | `TEMPLATE_RESEARCH_REQUEST.md` | `TEMPLATE_RESEARCH_RESPONSE.md` | `#needs-research` |

### File Locations

- **REQUEST files**: Written to the **requesting** session directory (e.g., `sessions/2026_02_08_MY_SESSION/IMPLEMENTATION_REQUEST_FOO.md`)
- **RESPONSE files**: Written to the **responding** session directory (where the skill runs)
- **Template lookup**: `engine session request-template '#needs-X'` resolves tag → skill → template path

### RESPONSE Template Design

Each RESPONSE template is tailored to the skill's specific outputs:

- **Implementation**: Code changes, test results, deviations from request, tech debt, acceptance criteria status
- **Brainstorm**: Decisions made, alternatives rejected, trade-offs explored, open questions
- **Documentation**: Documents updated/created, accuracy notes, remaining doc gaps
- **Review**: Verdict (approved/rework), findings with severity, invariant compliance
- **Chores**: Task completion checklist, skipped tasks with reasons, side effects
- **Research**: Gemini interaction ID, raw research report

---

## Tag Promotion Gate

The promotion gate (`§CMD_RESOLVE_BARE_TAGS`) runs during synthesis when `engine session check` finds bare inline lifecycle tags. For each bare tag:

1. **PROMOTE**: Create a REQUEST file from the skill's template (via `engine session request-template`) + backtick-escape the inline tag. This makes the work item formally dispatchable.
2. **ACKNOWLEDGE**: Leave the tag bare (intentional inline marker). Agent logs the acknowledgment.
3. **ESCAPE**: Backtick-escape the tag (it was a reference, not a work item).

The gate is the mechanism that converts informal inline tags into formal REQUEST files — answering the question "how does a walk-through tag become a REQUEST file?"

---

## Cross-Session Tag Resolution

`§CMD_RESOLVE_CROSS_SESSION_TAGS` runs during synthesis and checks if the current session's work resolved items tagged in OTHER sessions:

1. Review current session's plan, log, and debrief to identify what was accomplished
2. Run `tag.sh find` for relevant `#needs-*` tags in other sessions
3. For each match, check if the tagged item was resolved
4. If resolved: `tag.sh swap '#needs-X' '#done-X'` on the source file

**Guidance**: Be conservative — only swap tags where the work is clearly complete.
