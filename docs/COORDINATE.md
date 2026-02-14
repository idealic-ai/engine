# Coordinator Single-Session Mechanics

**Provenance**: `sessions/2026_02_13_COORDINATOR_SKILL_BRAINSTORM` (9 rounds, Focused mode)
**Related**: `ORCHESTRATION.md` (multi-chapter project lifecycle), `FLEET.md` (multi-agent workspace), `TAG_LIFECYCLE.md` (tag dispatch), `DAEMON.md` (daemon dispatch)

This document defines the single-session mechanics of the coordinator — everything about how the `/coordinate` skill processes panes, makes decisions, communicates with workers, and handles interrupts within one continuous event loop. For multi-chapter orchestration (vision documents, chapter progression, autonomous advancement), see `ORCHESTRATION.md`. For vision creation (splitting work into serial/parallel chapters), see the `/direct` skill.

---

## 1. Core Concepts

### What Is the Coordinator?

The coordinator is a persistent Claude Code agent that monitors a fleet of worker agents, answering their questions autonomously when confident and escalating to the human when uncertain. It runs as a long-lived event loop within a single `/coordinate` session.

**The mental model**: A manager who reads terminals. The coordinator sits in its own tmux pane, watches worker panes for activity, reads what workers are asking, decides whether to answer or escalate, and types responses into worker panes via `tmux send-keys`. It never runs worker code, never restarts workers, never touches the filesystem on workers' behalf. It only sends keystrokes.

### Key Properties

- **Event-driven, not polling**: The coordinator blocks on `coordinate-wait` until a worker needs attention. Zero CPU cost while idle.
- **Serial processing**: One worker at a time (`§INV_SERIAL_PROCESSING`). The coordinator finishes with one pane before moving to the next. No parallel decision-making.
- **TUI-only communication** (`§INV_TERMINAL_IS_API`): Worker communication happens through the existing terminal UI. No custom protocols, no file-based handshakes, no signals. The coordinator reads terminal output and types responses.
- **Never restarts workers** (`§INV_COORDINATOR_NEVER_RESTARTS_WORKERS`): The coordinator sends keystrokes only. If a worker is stuck, the coordinator escalates to the human. It never kills or restarts worker processes.
- **Long-running**: The coordinator is designed to run for hours. Context overflow is expected and handled via dehydration/restart.

### The Coordinator's Pane

The coordinator runs in a dedicated tmux pane (configured in fleet.yml). This pane:
- Has `@pane_manages` set to the list of worker pane IDs it monitors
- Is NOT included in its own managed set (it doesn't monitor itself)
- Shows the coordinator's Claude Code conversation (escalations appear here)
- Has a distinct visual treatment (the coordinator label, not a worker label)

---

## 2. The Event Loop

The coordinator's main loop is built on `coordinate-wait` v2 — a single blocking call that handles the full lifecycle of pane engagement.

### Loop Structure

```
┌──────────────────────────────────────────────────────┐
│  Coordinator Event Loop                                 │
├──────────────────────────────────────────────────────┤
│                                                      │
│  while true:                                         │
│    │                                                 │
│    ├─► coordinate-wait(timeout, managed_panes)          │
│    │     [blocks until pane needs attention]          │
│    │     [auto-disconnects previous pane]             │
│    │     [auto-connects new pane (purple)]            │
│    │     [captures pane content]                      │
│    │                                                 │
│    ├─► Parse return value                            │
│    │     TIMEOUT → idle heartbeat, check completion  │
│    │     FOCUSED → skip (user has all panes)         │
│    │     pane_id|state|... → process this pane       │
│    │                                                 │
│    ├─► Assess (category check + confidence)          │
│    │                                                 │
│    ├─► Decide                                        │
│    │     High confidence → answer autonomously       │
│    │     Low confidence → probe (if enabled)         │
│    │     Category match → escalate immediately       │
│    │                                                 │
│    ├─► Execute                                       │
│    │     tmux send-keys (answer)                     │
│    │     or escalate to human in chat                │
│    │                                                 │
│    └─► Log (if in alwaysLog categories)              │
│                                                      │
│  Exit conditions:                                    │
│    - Human says "stop" / selects Synthesis from ESC  │
│    - Context overflow → §CMD_DEHYDRATE               │
│    - All workers done → offer Synthesis              │
│    - Consecutive timeout limit exceeded              │
└──────────────────────────────────────────────────────┘
```

### coordinate-wait v2 in Detail

The core primitive. Each call to `coordinate-wait` performs a complete engagement cycle:

**Step 1 — Auto-disconnect previous pane**
If the previous call returned a pane (stored internally as the "last connected" pane), `coordinate-wait` disconnects it: clears `@pane_coordinator_active`, reverts the purple background. This happens at the START of the new call, not at the end of the previous processing.

**Step 2 — Sweep for actionable panes**
Iterates through all managed panes (from `@pane_manages` or `--managed` flag). For each pane, reads `@pane_notify`, `@pane_coordinator_active`, and `@pane_user_focused`. Filters:
- Skip if `@pane_user_focused = 1` (human is looking at it)
- Skip if `@pane_coordinator_active = 1` (shouldn't happen after disconnect, but defensive)
- Include if `@pane_notify` is `unchecked`, `error`, or `done`

**Step 3 — Priority selection**
If multiple panes are actionable, pick one by priority:
- `error` > `unchecked` > `done`
- Within the same priority, FIFO (first detected wins)

**Step 4 — Block if nothing actionable**
If no panes are actionable after the sweep, block using `tmux wait-for coordinator-wake`. This is efficient — the process sleeps until a worker fires the wake signal. The wake signal is sent automatically when `engine fleet notify` changes any managed pane to `unchecked`, `error`, or `done`.

After wake (or after the `--timeout` expires), re-sweep to get current state. The wake signal only says "something changed" — the actual state is determined by the re-sweep.

**Step 5 — Auto-connect**
Set `@pane_coordinator_active = 1` on the selected pane. Apply the purple background tint (visual indicator that the coordinator is engaged).

**Step 6 — Capture**
Run `engine fleet capture-pane` on the selected pane. Returns structured JSON with terminal content, question detection, and AskUserQuestion metadata.

**Step 7 — Return**
Output `pane_id|state|label|location` on the first line, followed by the capture JSON on subsequent lines.

### Return Values

| Return | Meaning | Coordinator Action |
|--------|---------|-----------------|
| `pane_id\|state\|label\|location` + JSON | Worker needs attention | Process: assess → decide → execute |
| `TIMEOUT` + `STATUS ...` | No activity within timeout | Idle heartbeat, check chapter completion |
| `FOCUSED` + `STATUS ...` | All panes user-focused | Skip cycle, log if needed |

### The "Sweep-First" Optimization

`coordinate-wait` sweeps BEFORE blocking. This handles the common case where a worker fired `notify unchecked` while the coordinator was processing the previous pane. Without sweep-first, the coordinator would block on `wait-for` even though actionable panes already exist. With sweep-first, it detects them immediately and returns without blocking.

---

## 3. Three-Dimensional State Model

Pane state is three orthogonal boolean/enum dimensions that together describe the complete situation of any worker pane.

### The Three Dimensions

| Dimension | Variable | Values | Set By | Answers |
|-----------|----------|--------|--------|---------|
| **Notify** | `@pane_notify` | working, unchecked, error, done, checked | `engine fleet notify` | WHAT happened? |
| **Coordinator** | `@pane_coordinator_active` | 0 / 1 | `coordinate-wait` (auto-connect/disconnect) | Is the bot handling it? |
| **User Focus** | `@pane_user_focused` | 0 / 1 | tmux focus hook (`pane-focus-in` / `pane-focus-out`) | Is the human looking at it? |

### Why Three Dimensions?

The original system had one dimension (notify state) that conflated "what happened" with "who is handling it." Adding `@pane_coordinator_active` (the purple indicator) separated bot-handling from state. But user intervention was invisible — if a user focused a pane the coordinator was processing, neither knew about the conflict.

The three-dimension model gives complete situational awareness:
- The coordinator knows which panes the user is looking at (skip them)
- The coordinator knows which panes it's currently processing (track engagement)
- The user's focus is visible to the system (enable abort-on-focus)

### Notify State Transitions

```
working ──► unchecked    Worker completes task (fleet.sh notify unchecked)
unchecked ──► checked    User focuses pane (auto-transition via focus hook)
checked ──► working      Worker starts new task (fleet.sh notify working)
* ──► error              Worker encounters error (fleet.sh notify error)
* ──► done               Worker session complete (fleet.sh notify done)
```

The notify dimension is set by workers (via `engine fleet notify`) and the focus hook (`notify-check`). The coordinator reads it but never writes it directly — except when aborting on focus override (sets back to `unchecked`).

### Coordinator Active Transitions

```
0 ──► 1    coordinate-wait auto-connects (purple bg applied)
1 ──► 0    coordinate-wait auto-disconnects on next call
1 ──► 0    Focus override: user focuses managed pane, coordinator aborts
1 ──► 0    §INV_AUTO_DISCONNECT_ON_STATE_CHANGE: non-unchecked notify transition
```

The coordinator dimension is managed entirely by `coordinate-wait` and the abort mechanism. Workers and users never set it directly.

### User Focus Transitions

```
0 ──► 1    User focuses the pane (tmux pane-focus-in hook)
1 ──► 0    User focuses a different pane (tmux pane-focus-out hook)
```

The focus dimension is managed by tmux hooks. It is transient — it reflects the user's current attention, not a persistent state.

### Full Interaction Matrix

| Notify | Coordinator | Focused | Situation | Coordinator Response |
|--------|----------|---------|-----------|-------------------|
| working | 0 | 0 | Worker busy, nobody watching | Skip — not actionable |
| working | 0 | 1 | Worker busy, user watching | Skip — user present |
| unchecked | 0 | 0 | Needs attention, nobody on it | **Pick up** (high priority) |
| unchecked | 0 | 1 | Needs attention, user handling | Skip — user present |
| unchecked | 1 | 0 | Coordinator processing | Already engaged (shouldn't appear in sweep) |
| unchecked | 1 | 1 | **Conflict** — user focused managed pane | **Abort** → disconnect → unchecked → yield |
| error | 0 | 0 | Error, nobody on it | **Pick up** (highest priority) |
| error | 0 | 1 | Error, user handling | Skip — user present |
| done | 0 | 0 | Worker finished, nobody checked | **Pick up** (low priority) |
| checked | 0 | 0 | User saw it, no action needed | Skip — acknowledged |

---

## 4. Decision Engine

How the coordinator assesses worker questions and decides whether to answer autonomously or escalate.

### Assessment Flow

```
Question arrives (from capture-pane JSON)
  │
  ├─► Category Check (from config alwaysEscalate)
  │     Match? → ESCALATE (category rule override)
  │
  ├─► Confidence Assessment
  │     Rate 0.0 – 1.0 based on:
  │       - Question clarity
  │       - Available context (chapter plan, decision principles)
  │       - Stakes and reversibility
  │       - Domain familiarity
  │
  ├─► Threshold Check (from config confidenceThreshold)
  │     >= threshold? → DECIDE (autonomous answer)
  │     < threshold? → PROBE (if enabled) or ESCALATE
  │
  └─► Probe (optional pre-escalation)
        Send clarifying question to worker
        Worker responds with more context
        Re-assess confidence
        >= threshold? → DECIDE
        still < threshold? → ESCALATE
```

### Category Rules

Category rules are hard overrides — they always escalate regardless of confidence. Defined in `coordinate.config.json`:

```json
{
  "alwaysEscalate": [
    "git operations",
    "file deletion",
    "database changes",
    "security decisions",
    "API key management"
  ]
}
```

The coordinator checks if the question's topic matches any category. This is LLM-interpreted — the categories are natural language descriptions, not exact string matches.

### Confidence Scoring

The coordinator rates its confidence based on multiple factors:

| Factor | Low Confidence | High Confidence |
|--------|---------------|-----------------|
| **Question clarity** | Ambiguous, multiple interpretations | Clear, single answer |
| **Context availability** | No relevant plan context | Chapter plan + decision principles cover it |
| **Stakes** | Irreversible, affects production | Low-risk, easily reversible |
| **Domain knowledge** | Outside coordinator's loaded context | Within the chapter's scope |
| **Precedent** | First time seeing this pattern | Similar question answered before |

The threshold (from config, default 0.7) determines the cutoff. Confidence scoring is inherently subjective — the LLM's self-assessment. The config threshold tunes the aggressiveness of autonomous action.

### Probe Mechanics

When confidence is below threshold but pre-escalation probing is enabled (`preEscalation.enabled: true` in config):

1. The coordinator types a clarifying question into the worker's "Other" field
2. The worker responds with additional context
3. The coordinator waits for the worker's next `unchecked` notification
4. Captures the response, re-assesses confidence
5. If now above threshold → answer autonomously
6. If still below → escalate to human

The probe message is configurable (`preEscalation.probeMessage`). Default: "Can you elaborate on what you need? I want to make sure I give you the right answer."

### Decision Principles Integration

The vision document's "Decision Principles" section provides soft guidance that supplements the config's hard rules:

- **Config** (`coordinate.config.json`): Mechanical rules. "Always escalate git operations." These are category matches that override confidence.
- **Vision** (Decision Principles): LLM-interpreted guidance. "Prefer speed over thoroughness." These influence the coordinator's confidence assessment and answer quality.

Example: A worker asks "Should I write tests for this utility function?" The config has no category match. The vision says "Always use TDD for API changes." The coordinator checks — this is a utility function, not an API change. Decision principle doesn't apply. Confidence is high (simple yes/no, low stakes). Answer autonomously: "Yes, write unit tests."

---

## 5. Worker Communication

All worker communication follows the TUI-only constraint (`§INV_TERMINAL_IS_API`).

### Reading Worker Output

The coordinator reads worker state via `engine fleet capture-pane`, which returns structured JSON:

```json
{
  "paneId": "Main",
  "paneLabel": "Main",
  "notifyState": "unchecked",
  "hasQuestion": true,
  "questionText": "Which database migration strategy should we use?",
  "options": [
    {"label": "Incremental migrations", "description": "Add new columns, keep old ones"},
    {"label": "Full schema rewrite", "description": "Drop and recreate tables"}
  ],
  "preamble": "I've analyzed the current schema and found 3 tables that need updating..."
}
```

The `hasQuestion` flag indicates whether an `AskUserQuestion` prompt is active. When `true`, the coordinator can parse the question, options, and preamble to make an informed decision.

### Sending Responses

The coordinator types responses via `tmux send-keys`:

```bash
# Navigate to the "Other" field (arrow down past all options), then type
tmux -L fleet send-keys -t [pane_id] "[response text]" Enter
```

**Response patterns**:
- To select option N: Type `Choose N` (NOT bare `N` — a bare number selects immediately before reasoning can be added)
- To select with reasoning: Type `Choose N: [brief explanation]`
- To provide free-text: Type the full answer text

**The "Other" field pattern**: Workers present `AskUserQuestion` with structured options plus a free-text "Other" field. The coordinator always types into the "Other" field, using `Choose N` syntax to select options. This allows the coordinator to add reasoning context that the worker can log.

### Communication Constraints

- **No file-based handshakes**: The coordinator doesn't write files for workers to read. Communication is terminal-only.
- **No custom signals**: The coordinator doesn't send tmux signals or write to named pipes. Just keystrokes.
- **One response per engagement**: The coordinator sends one response per `coordinate-wait` cycle. If the worker needs follow-up, it will fire another `unchecked` notification, and the coordinator will pick it up on the next cycle.
- **No streaming**: The coordinator types the complete response at once. It doesn't stream characters one by one.

---

## 6. Focus & Interrupt Mechanics

The user can override the coordinator at any time by focusing a worker pane.

### The Interrupt Sequence

```
1. User focuses a pane the coordinator is processing
     (@pane_coordinator_active = 1 for this pane)

2. tmux pane-focus-in hook fires
     Sets @pane_user_focused = 1

3. Coordinator detects focus change
     (via polling or hook notification — implementation TBD)

4. Coordinator aborts current processing
     - Stops mid-assessment or mid-response
     - Half-sent responses are acceptable (user can see what was started)

5. Coordinator disconnects
     - Clears @pane_coordinator_active = 0
     - Reverts purple background

6. Coordinator sets notify back to unchecked
     - The pane re-enters the queue when user focuses away

7. Coordinator returns to coordinate-wait
     - Next call handles lifecycle normally
```

### Focus-Out Recovery

When the user focuses away from a managed pane:
1. `pane-focus-out` hook fires → `@pane_user_focused = 0`
2. The pane becomes eligible for `coordinate-wait` pickup again
3. If the pane's notify state is still `unchecked`, the coordinator will process it on the next sweep

This creates a natural handoff: user looks at a pane → coordinator yields. User looks away → coordinator can pick it back up.

### Race Conditions

| Race | Scenario | Resolution |
|------|----------|------------|
| **Focus during block** | User focuses a pane while `coordinate-wait` is blocking on `tmux wait-for` | Irrelevant — `coordinate-wait` filters focused panes on sweep. If the user focuses and then focuses away before the sweep, the pane is eligible. If still focused during sweep, it's skipped. |
| **Focus during capture** | User focuses the pane between `coordinator-connect` and `capture-pane` | The capture still succeeds (tmux captures regardless of focus). The coordinator detects the focus flag during assessment and aborts. |
| **Focus during send-keys** | User focuses the pane while the coordinator is typing a response | The keystrokes are still sent (tmux send-keys works regardless of focus). The user sees the coordinator's partial response in the terminal. The coordinator detects the focus after typing and aborts. |
| **Rapid focus toggle** | User quickly focuses in and out of a managed pane | The flag toggles. If the coordinator is between cycles (in `coordinate-wait`), it filters correctly. If mid-processing, it detects the current state at the next poll point. Rapid toggles may cause the coordinator to abort and then re-pick-up on the next cycle. |

### ESC Interrupt (Coordinator's Own Pane)

The user can press ESC (or Ctrl+C) at any time in the coordinator's pane. This kills the `coordinate-wait` Bash process and returns control to the coordinator.

**On ESC detection** (the `coordinate-wait` call exits abnormally):

The coordinator presents an interaction menu via `AskUserQuestion`:
> "Oversight interrupted. What would you like to do?"
> - **"Resume monitoring"** — Return to the event loop immediately
> - **"Fleet status"** — Show current pane states, then resume
> - **"Proceed to Synthesis"** — End the loop and write the debrief
> - **"Relay a message"** — Type a message to a specific worker pane

This is the primary mechanism for the user to interact with the coordinator mid-loop. The coordinator doesn't prompt unprompted — ESC is the interrupt signal.

---

## 7. Configuration System

The coordinator's behavior is configured via `coordinate.config.json`, which lives in the session directory.

### Structure

```json
{
  "confidenceThreshold": 0.7,
  "alwaysEscalate": [
    "git operations",
    "file deletion",
    "database changes",
    "security decisions"
  ],
  "alwaysLog": [
    "architecture decisions",
    "dependency changes",
    "test strategy"
  ],
  "preEscalation": {
    "enabled": true,
    "probeMessage": "Can you elaborate on what you need?"
  },
  "timeouts": {
    "waitTimeout": 300,
    "consecutiveTimeoutLimit": 10,
    "idleHeartbeatInterval": 3
  },
  "logging": {
    "logAutonomousDecisions": true,
    "logEscalations": true,
    "logProbes": true,
    "logRoutineSkips": false
  }
}
```

### Configuration Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `confidenceThreshold` | float | 0.7 | Minimum confidence to answer autonomously |
| `alwaysEscalate` | string[] | [] | Category descriptions that always escalate |
| `alwaysLog` | string[] | [] | Category descriptions that always get logged |
| `preEscalation.enabled` | bool | true | Whether to probe before escalating |
| `preEscalation.probeMessage` | string | "..." | Message sent to worker for clarification |
| `timeouts.waitTimeout` | int | 300 | Seconds before `coordinate-wait` returns TIMEOUT |
| `timeouts.consecutiveTimeoutLimit` | int | 10 | Timeouts before notifying human of idle fleet |
| `timeouts.idleHeartbeatInterval` | int | 3 | Log heartbeat every N consecutive timeouts |
| `logging.logAutonomousDecisions` | bool | true | Log autonomous answers |
| `logging.logEscalations` | bool | true | Log escalations |
| `logging.logProbes` | bool | true | Log probe attempts |
| `logging.logRoutineSkips` | bool | false | Log routine option selections |

### Config vs. Decision Principles

| Concern | Config (`coordinate.config.json`) | Decision Principles (vision doc) |
|---------|-------------------------------|----------------------------------|
| **Format** | Structured JSON | Natural language |
| **Scope** | HOW the coordinator operates | WHAT the coordinator should prioritize |
| **Enforcement** | Mechanical (category match → escalate) | LLM-interpreted (influences reasoning) |
| **Persistence** | Per-session (or shared across sessions) | Per-project (lives in vision doc) |
| **Examples** | "Always escalate file deletion" | "Prefer speed over thoroughness" |

### Mode Presets

The `/coordinate` skill offers three predefined modes that configure `coordinate.config.json`:

| Mode | Confidence Threshold | Escalation | Logging | Use Case |
|------|---------------------|------------|---------|----------|
| **Autonomous** | 0.5 | Minimal categories | Significant only | Trusted workers, low-risk project |
| **Cautious** | 0.85 | Many categories | Everything | High-stakes project, new workers |
| **Supervised** | 0.95 | Nearly everything | Everything | Training, first-time oversight |

Custom mode allows mixing: "Autonomous confidence but Cautious escalation categories."

---

## 8. Context Overflow Handling

The coordinator is a long-running loop that WILL overflow its context window. This is expected and designed for.

### When Overflow Happens

The overflow hook (`pre-tool-use-overflow-v2.sh`) triggers `§CMD_DEHYDRATE NOW` when context usage exceeds the threshold (~76%). The coordinator follows `§CMD_DEHYDRATE`:

1. Captures current state as JSON
2. Pipes to `engine session dehydrate`
3. Engine stores in `.state.json` and triggers restart

### What Gets Preserved

The dehydrated JSON includes:

| Content | Source | Purpose |
|---------|--------|---------|
| **Config path** | Session directory | New Claude loads the same config |
| **Vision path** | `contextPaths` parameter | New Claude finds the vision doc |
| **Current chapter** | Chapter plan in session dir | New Claude knows which chapter |
| **Worker pane IDs** | From `@pane_manages` | New Claude monitors the same workers |
| **Recent decisions** | Last ~10 from COORDINATE_LOG.md | Continuity — avoid re-answering same questions |
| **Pending escalations** | Any unanswered escalations | New Claude can re-present them |
| **Checkbox state** | Chapter plan file | Progress tracking survives restart |

### What Gets Lost

- **LLM conversation history**: The new Claude starts fresh. It reads the dehydrated context but doesn't have the full reasoning chain from previous decisions.
- **In-flight assessment**: If overflow hits mid-assessment, the current pane is abandoned. It will be `unchecked` on the next sweep (the auto-disconnect didn't happen, but the pane's `@pane_coordinator_active` will be stale — the new Claude's first `coordinate-wait` call handles this).
- **Accumulated context**: The coordinator builds up understanding of each worker's task over many cycles. This is partially preserved in the log but not as rich as the live context.

### Restart Behavior

After restart, the new Claude:
1. Re-activates the session (`engine session activate`)
2. Resumes tracking (`engine session continue`)
3. Reads the chapter plan (checkboxes show progress)
4. Enters the event loop at Phase 1 (Oversight Loop)
5. The first `coordinate-wait` call handles any stale `@pane_coordinator_active` flags

### Minimizing Overflow Frequency

- **Selective logging** (`§INV_SELECTIVE_LOGGING`): Don't log routine option picks — only significant decisions
- **Compact escalations**: Keep escalation messages concise
- **Config tuning**: Higher `confidenceThreshold` means fewer autonomous decisions to log

---

## 9. Edge Cases

Detailed handling of unusual situations within a single session.

### Worker Behavior Edge Cases

| Edge Case | What Happens | Resolution |
|-----------|-------------|------------|
| **Worker is mid-typing when coordinator captures** | `capture-pane` captures the current terminal state, including partial input. The coordinator may see an incomplete question. | The coordinator should wait for `hasQuestion: true` in the capture JSON. If the capture shows no active question, the pane may have been `unchecked` for a different reason (e.g., tool output). Skip and re-check on next cycle. |
| **Worker fires `unchecked` but then resolves itself** | The worker's `AskUserQuestion` gets answered by the user or by the worker's own logic before the coordinator reaches it. | `coordinate-wait` captures the pane. The capture shows `hasQuestion: false`. The coordinator disconnects and moves on. No wasted work. |
| **Worker fires `error` then recovers** | The worker hits an error, fires `error` state, then self-recovers and fires `working`. | If the coordinator picks up the `error` before recovery, it sees the error state. If the worker recovered first, the sweep sees `working` and skips. The state model is eventually consistent. |
| **All workers error simultaneously** | Every managed pane is in `error` state. | `coordinate-wait` picks them up one at a time (serial processing). The coordinator escalates each one. The human sees multiple escalation messages in the coordinator's chat. |

### Timing Edge Cases

| Edge Case | What Happens | Resolution |
|-----------|-------------|------------|
| **ESC fires during capture** | The user presses ESC while `capture-pane` is running inside `coordinate-wait`. | `coordinate-wait` exits abnormally. The coordinator presents the ESC menu. The pane may or may not have been captured — the coordinator doesn't use the partial result. |
| **Timeout fires at the same instant as a wake signal** | `tmux wait-for` returns (either from timeout or signal — unclear which). | `coordinate-wait` re-sweeps regardless of the return reason. If a pane is actionable, it's returned. If not (false wake), TIMEOUT is returned. The re-sweep is the source of truth, not the wake reason. |
| **Worker sends `notify unchecked` while coordinator is processing another pane** | The wake signal fires but the coordinator is busy. | The signal is "lost" (tmux wait-for is edge-triggered, not queued). But `coordinate-wait`'s sweep-first behavior catches it: the next call sweeps before blocking, finding the unchecked pane. |

### Config Edge Cases

| Edge Case | What Happens | Resolution |
|-----------|-------------|------------|
| **Config file missing** | The coordinator can't find `coordinate.config.json` in the session directory. | During Setup (Phase 0), the coordinator asks: "No config found. Use defaults?" If yes, applies default values. If no, creates a config file for the user to customize. |
| **Config has invalid JSON** | Parsing fails. | The coordinator reports the parse error and asks the user to fix it. Does not proceed with a partially parsed config. |
| **Confidence threshold is 0.0** | Everything is above threshold. | The coordinator answers everything autonomously. Only `alwaysEscalate` categories trigger escalation. Valid configuration for high-trust scenarios. |
| **Confidence threshold is 1.0** | Nothing is above threshold (confidence is never exactly 1.0 in practice). | The coordinator escalates everything. Effectively "supervised" mode. Valid but defeats the purpose. |

---

## 10. Connection to Fleet

The coordinator depends on the fleet system (`FLEET.md`) for its infrastructure.

### Fleet Components Used

| Component | Used By Coordinator | Purpose |
|-----------|-----------------|---------|
| `fleet.yml` config | Pane layout, `@pane_manages` | Defines which panes the coordinator monitors |
| `engine fleet coordinate-wait` | Event loop | Blocking wait for actionable panes |
| `engine fleet coordinator-connect` | `coordinate-wait` internal | Purple engagement indicator |
| `engine fleet coordinator-disconnect` | `coordinate-wait` internal | Clear engagement indicator |
| `engine fleet capture-pane` | `coordinate-wait` internal | Structured terminal capture |
| `engine fleet notify` | Workers (not coordinator) | State change signals |
| `engine fleet status` | Setup validation | Verify fleet is running |
| tmux `send-keys` | Worker communication | Type responses |

### The Coordinator Pane in fleet.yml

```yaml
panes:
  - label: "Coordinator"
    agent: operator
    manages: ["Main", "Research", "SDK"]  # Sets @pane_manages
    # No 'project' or 'skill' — the coordinator is invoked manually
```

The `manages` field is the critical configuration. It defines which panes the coordinator monitors. `coordinate-wait` reads `@pane_manages` from the calling pane to discover its managed set.

### Fleet Socket

The coordinator runs within a fleet tmux socket (e.g., `fleet` or `fleet-project`). All `tmux send-keys` commands use the `-L` flag with the fleet socket name. The coordinator auto-detects its socket from the environment (`TMUX` variable).

---

## 11. Connection to Delegation

The coordinator creates and processes tags that flow through the delegation system.

### Tags the Coordinator Creates

| Scenario | Tag Created | Flow |
|----------|------------|------|
| Worker question can't be answered | `#needs-brainstorm` or `#needs-research` | Standard delegation → `§CMD_DISPATCH_APPROVAL` during synthesis |
| Cross-chapter scope addition | `#needs-coordinate` on vision doc | Coordinator claims on next chapter boundary |
| Side discovery during processing | `#needs-implementation`, `#needs-fix`, etc. | Standard delegation → daemon dispatch |

### Tags the Coordinator Consumes

| Tag | Source | When |
|-----|--------|------|
| `#needs-coordinate` | Vision document chapters | Chapter initialization — claim next chapter |
| `#claimed-coordinate` | Self (previous claim) | Resume interrupted chapter |

### Escalation vs. Delegation

Escalation and delegation serve different purposes:

- **Escalation**: "I need a human to answer this question NOW." The worker is blocked. The human intervenes directly.
- **Delegation**: "I found work that should be done LATER by a different skill." The tag enters the staging → dispatch pipeline. Nobody is blocked.

The coordinator escalates questions (immediate, blocking). It delegates discovered work items (deferred, non-blocking).

---

## 12. Logging

The coordinator logs to `COORDINATE_LOG.md` in the session directory. Logging follows `§INV_SELECTIVE_LOGGING` — only significant events, not routine operations.

### Log Entry Types

| Type | When | Schema |
|------|------|--------|
| `## Autonomous Decision` | Coordinator answers a worker | Worker, question, answer chosen, confidence, reasoning |
| `## Escalation to Human` | Coordinator can't answer | Worker, question, reason (category/confidence), options |
| `## Human Resolution` | Human provides answer for escalation | Worker, question, human's answer, relayed |
| `## Pre-Escalation Probe` | Coordinator sends clarifying question | Worker, original question, probe, response, outcome |
| `## Idle Heartbeat` | Periodic during timeouts | Worker count, statuses, timestamp |
| `## Chapter Complete` | All criteria met | Chapter number, work items completed, time |
| `## Chapter Started` | New chapter claimed | Chapter number, vision path, work item count |

### Selective Logging

Not everything gets logged. The `logging` config controls granularity:

- `logAutonomousDecisions: true` — Log answers (useful for audit)
- `logEscalations: true` — Always log escalations (they're significant by definition)
- `logProbes: true` — Log probe attempts (debugging pre-escalation behavior)
- `logRoutineSkips: false` — Don't log "skipped pane X (working)" — too noisy

The `alwaysLog` category list in config adds forced logging for specific question categories regardless of the logging flags.
