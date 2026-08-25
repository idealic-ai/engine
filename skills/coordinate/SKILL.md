---
name: coordinate
description: "Persistent fleet coordinator — monitors workers, answers routine questions autonomously, escalates uncertain decisions. Triggers: \"coordinate the fleet\", \"manage workers\", \"start oversight\", \"monitor agents\"."
version: 3.0
tier: protocol
---

Persistent fleet coordinator — monitors TMUX fleet workers, autonomously answers routine AskUserQuestion prompts via `tmux send-keys`, and escalates uncertain decisions to the human.

# Oversight Protocol (The Manager's Code)

Execute §CMD_EXECUTE_SKILL_PHASES.

This skill has three modes of operation: **Chapter Planning** (Phases 1-2) where the coordinator interrogates context and creates a rich chapter plan, **Dispatch** (Phase 3) where work items are mapped to workers and delegation tags are applied, and the **Oversight Loop** (Phase 4) which runs as a persistent event loop. Worker communication happens ONLY through the existing TUI (`§INV_TRANSCRIPT_IS_API`): read terminal transcripts, type responses via `tmux send-keys`. No custom protocols or file-based handshakes.

The coordinator consumes any structured document (vision docs from `/direct`, brainstorm outputs, analysis reports) as input for chapter planning. It works best with `/direct` vision documents but is not limited to them.

## Core Invariants

*   **§INV_COORDINATOR_NEVER_RESTARTS_WORKERS**: The coordinator MUST NOT kill or restart worker processes. It only sends keystrokes. Stuck workers are escalated to the human.
*   **¶INV_ESCALATION_CATEGORIES_OVERRIDE**: Category-based escalation rules from `coordinate.config.json` always override confidence-based autonomy. Dangerous operations always escalate regardless of confidence.
*   **§INV_SERIAL_PROCESSING**: Workers are processed one at a time. No parallel decision-making.
*   **§INV_TRANSCRIPT_IS_API**: Worker communication happens through terminal transcripts. No custom protocols.
*   Log significant decisions per the config's explicit categories. Do not log routine option picks.
---

## 0. Setup

§CMD_REPORT_INTENT:
> 0: Setting up fleet oversight session. Fleet target: ___ worker panes.
> Focus: ___.
> Not: ___.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

*   **Scope**: Validate the fleet is running, load oversight config, discover target panes.

**Mode Selection** (`§CMD_SELECT_MODE`):

**On selection**: Read the corresponding `modes/{mode}.md` file. Apply Role, Goal, Mindset.

**On "Custom"**: Read ALL 3 named mode files first (`modes/autonomous.md`, `modes/cautious.md`, `modes/supervised.md`), then accept user's framing. Parse into role/goal/mindset.

**Fleet Validation**: Check that fleet is running.
```bash
engine fleet status
```
If fleet is not running, STOP and inform the user:
> "Fleet is not running. Start it with `engine fleet start` first, then re-invoke `/coordinate`."

**Config Loading**: Look for `coordinate.config.json` in the session directory. If not found, ask the user:
> "No `coordinate.config.json` found. Use defaults?"
> - **"Use defaults"** -- Apply the example config values
> - **"Create config"** -- I'll create one for you to customize

If "Create config": Copy `assets/coordinate.config.example.json` to the session directory and present for editing.

**Pane Discovery**: Enumerate target panes.
*   **`@pane_manages` tmux option** (set in fleet.yml): The coordinator's pane declares its managed panes. `await-next` reads `FLEET_MANAGES` env var (exported from `@pane_manages` by run.sh) — no `--panes` argument needed.
    ```bash
    engine await-next 30   # reads FLEET_MANAGES from env
    ```
*   **Fallback**: If `FLEET_MANAGES` is not set, use `--panes` explicitly or fall back to `engine fleet status`, parse all panes, exclude the coordinator's own pane.

Display:
> **Monitoring [N] worker panes:**
> - `meta-sessions` -- Sessions (analyzer)
> - `meta-reports` -- Reports (writer)
> ...

**Initialize Log**: Execute `§CMD_INIT_LOG` for `COORDINATE_LOG.md`.

---

## 1. Chapter Interrogation

§CMD_REPORT_INTENT:
> 1: Interrogating chapter context before planning. Vision doc: ___.
> Focus: scope boundaries, worker assignments, dependency analysis, decision principles.
> Not: creating the plan or dispatching work — information gathering only.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### Topics (Coordination)
*Standard topics for the command to draw from. Adapt to the chapter — skip irrelevant ones, invent new ones as needed.*

- **Vision doc analysis** -- chapter objectives, scope boundaries, how it fits the larger project
- **Worker group assignment** -- which groups handle which work items, capacity, skills needed
- **Dependency analysis** -- what must complete before this chapter starts, inter-item dependencies
- **Decision principles** -- inherited `RUL_` rules from vision, chapter-specific additions
- **Scope boundaries** -- what's in/out, deferred to later chapters
- **Architecture constraints** -- technical decisions, patterns to follow, codebase conventions
- **Risk assessment** -- what could go wrong, blocking risks, escalation scenarios
- **Completion criteria** -- how do we know the chapter is done, verification strategy
- **Open questions** -- gaps in the source material, things needing clarification
- **Cross-chapter continuity** -- what previous chapters established, what this unblocks

---

## 2. Chapter Planning

§CMD_REPORT_INTENT:
> 2: Planning chapter execution. ___ topics gathered from interrogation.
> Focus: creating coordination plan from template, assigning work items, defining completion criteria.
> Not: executing work or entering the oversight loop — planning only.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Unless the user points to an existing plan, you MUST create one.**

*   **Plan**: Fill in every section of `TEMPLATE_COORDINATION_PLAN.md` — provenance, objective, decision principles (`RUL_` naming), architecture notes, work items (big/small task formats), per-group worker briefings, open questions, completion criteria, references.

**Walk-through** (optional):
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "plan"
  gateQuestion: "Chapter plan is ready. Walk through the work items before dispatch?"
  debriefFile: "COORDINATION_PLAN.md"
  planQuestions:
    - "Any concerns about this work item's scope or assignment?"
    - "Should the scope change — expand, narrow, or split this item?"
    - "Dependencies or risks I'm missing?"
```

If any items are flagged for revision, return to the plan for edits before proceeding.

**Phase Gate**: Execute §CMD_DECISION_TREE with `¶ASK_COORDINATE_PLAN_EXIT`.

## ¶ASK_COORDINATE_PLAN_EXIT: Choose one: Chapter Plan Ready
Trigger: after chapter plan is created/walked through

- [ ] [NEXT] Proceed to dispatch
  Plan approved — prepare task-to-worker mapping
- [ ] [EDIT] Refine plan
  Return to plan editing to add details or restructure
- [ ] [DONE] Close session
  Plan is complete as-is — no dispatch or loop needed
- [ ] [MORE] Other
  - [ ] [BACK] Return to interrogation
    Need more context before finalizing
  - [ ] [SKIP] Skip to oversight loop
    Dispatch mapping not needed — go straight to monitoring

---

## 3. Dispatch

§CMD_REPORT_INTENT:
> 3: Preparing dispatch mapping. ___ work items from chapter plan.
> Focus: matching work items to worker groups, applying delegation tags, user approval.
> Not: monitoring workers or making decisions — dispatch mapping only.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

### Dispatch Algorithm

The coordinator prepares a task-to-worker mapping BEFORE the user approves it. It's a suggested assignment, not a blank form.

1. **Read plan items**: Scan the chapter plan's work items (checkboxes in `COORDINATION_PLAN.md`).
2. **Match to workers**: For each work item, match to available worker groups based on:
   *   Worker group skills (from fleet status / `@pane_claims`)
   *   Item domain (layout, API, SDK, etc.)
   *   Worker capacity (idle vs. busy)
3. **Present mapping**: Display the suggested mapping to the user:
   > **Dispatch Mapping — [N] items to [M] workers:**
   > *   **Item 1**: [description] → `%worker-pane` ([group])
   > *   **Item 2**: [description] → `%worker-pane` ([group])
   > *   ...
4. **On approval**: Apply `#delegated-coordination` + `%worker` tags to plan items. Workers pick up via `engine await-next`.
5. **On adjustment**: User can reassign items, split items, or defer items. Re-present the mapping after changes.

### Proactive Content

Before presenting the gate, show a preview of the dispatch mapping — the coordinator has already analyzed the plan items and fleet state. The user sees the mapping and can approve, adjust, or go back.

**Phase Gate**: Execute §CMD_DECISION_TREE with `¶ASK_COORDINATE_DISPATCH_EXIT`.

## ¶ASK_COORDINATE_DISPATCH_EXIT: Choose one: Dispatch Mapping Ready
Trigger: after dispatch mapping is presented/approved

- [ ] [NEXT] Enter oversight loop
  Dispatch confirmed — start monitoring workers
- [ ] [EDIT] Adjust mapping
  Change task assignments or add/remove workers
- [ ] [BACK] Return to planning
  Need to revise the plan before dispatching
- [ ] [MORE] Other
  - [ ] [DONE] Close session
    Dispatch complete — workers will work autonomously
  - [ ] [ADDW] Add more work items
    Dispatch additional items from the plan

---

## 4. Oversight Loop (The Event Loop)

§CMD_REPORT_INTENT:
> 4: Entering oversight loop. Monitoring ___ worker panes. Dispatched ___ items.
> Focus: event-driven worker processing, autonomous decisions, escalation to human.
> Not: planning or dispatch — monitoring execution of the chapter plan.

§CMD_EXECUTE_PHASE_STEPS(4.0.*)

### The Loop

**Repeat until stopped:**

#### Step 1 -- Wait (Event-Driven)

Block until a worker pane needs attention, a tag file changes, or timeout expires:
```bash
engine await-next [waitTimeoutSeconds] --panes [managed_pane_ids]
```

*   **Output format**: JSON (`AwaitNextResult`). Contains `eventType` (`child`/`tag`/`timeout`), pane/tag details, and status summary.
*   **`timeout` eventType**: No actionable events within the timeout window. The `status` field contains `{total, working, done, focused, idle}`. Execute **idle heartbeat** (see below) and loop back to Step 1.
*   **`child` eventType**: A managed pane has actionable state. Proceed to Step 2.
*   **`tag` eventType**: A delegated work item was found and auto-claimed. Route to the appropriate skill.

**How it works**: Dual-channel blocking via TypeScript tool (`tools/await-next/`):
1.  **Crash recovery**: Checks for `#claimed-X %self` tags (previously claimed, interrupted work).
2.  **Child sweep**: Sweeps managed panes for `unchecked`/`error`/`done` states (children first per `¶INV_CHILDREN_FIRST`).
3.  **Tag scan**: Scans sessions/ for `#delegated-X` tags matching `FLEET_CLAIMS`/`FLEET_TARGETED_CLAIMS`.
4.  **Block**: If nothing found, blocks on `tmux wait-for await-wake` + chokidar file watcher (`Promise.race`). On wake, re-sweeps both channels.
5.  **Auto-claim**: Delegated work is automatically claimed with `%self` stamp before returning (`¶INV_AUTO_CLAIM_ON_FIND`).

**Pane discovery**: `await-next` reads `FLEET_MANAGES` env var (exported by run.sh from `@pane_manages` tmux option). Use `--panes` for explicit filtering.

**Idle Heartbeat**: When `TIMEOUT` is returned, parse the `STATUS` line to report accurately:
> `[HH:MM] [N] workers: [working] working, [done] done, [idle] idle. Waiting...`

This confirms the coordinator is alive without consuming context. Log only every 3rd consecutive timeout (avoid log bloat).

#### Step 2 -- Parse

For `child` events, read the worker's terminal transcript to understand what it needs (`§INV_TRANSCRIPT_IS_API`):

1.  **Read transcript**: Capture the worker's pane content via `tmux capture-pane -p -t [pane_id]`. Parse for AskUserQuestion patterns:
    *   `questionText` -- The question being asked
    *   `options` -- Array of available choices with labels and descriptions
    *   `preamble` -- Agent's context before the question

2.  **Build Decision Context**:
    *   Question text and available options (from transcript)
    *   Preamble context (agent's reasoning)
    *   Worker label and location (from routing metadata)
    *   Worker's active skill and phase (from status line in capture)

#### Step 3 -- Assess

1.  **Category Check**: Does the question match any `alwaysEscalate` category?
    *   YES -> Go to Step 5 (Escalate). Log reason: "Category rule: {category}".
    *   NO -> Continue.

2.  **Confidence Assessment**: Rate your confidence in choosing the right answer.
    *   Consider: clarity of the question, available context, stakes of the decision, reversibility.
    *   Rate: 0.0 (no idea) to 1.0 (completely certain).

3.  **Threshold Check**: Is confidence >= `confidenceThreshold` (from config)?
    *   YES -> Go to Step 4 (Decide).
    *   NO -> Go to Step 4a (Probe).

#### Step 4 -- Decide (Autonomous)

1.  **Choose**: Select the best option based on the question context, worker's goal, and project conventions.

2.  **Respond**: Send the response via tmux.
    ```bash
    # ALWAYS use "Other" field -- type "Choose [option number]: [optional reasoning]"
    # Navigate to Other field first (arrow down past all options), then type
    tmux -L [socket] send-keys -t [pane_id] "[response text]" Enter
    ```

    **Response Pattern**:
    *   To select option 2: Type `Choose 2` (NOT bare `2` -- a bare number selects that option immediately before you can add context)
    *   To select with reasoning: Type `Choose 2: [brief reasoning]`
    *   To provide free-text: Type the full answer text

3.  **Log** (if in `alwaysLog` categories): `§CMD_APPEND_LOG` with `## Autonomous Decision` schema.

4.  **Continue**: Return to Step 1 (Wait). The next `await-next` call will re-sweep this pane.

#### Step 4a -- Probe (Pre-Escalation)

If `preEscalation.enabled` is true in config:

1.  **Send probe**: Type into the "Other" field of the worker's AskUserQuestion.
    ```bash
    tmux -L [socket] send-keys -t [pane_id] "[preEscalation.probeMessage]" Enter
    ```

2.  **Wait**: The worker will respond with an explanation. Poll for the next `unchecked` state from this pane.

3.  **Capture response**: Read the worker's explanation from the terminal.

4.  **Reassess confidence**: With the new context, re-rate confidence.
    *   If now >= threshold -> Go to Step 4 (Decide).
    *   If still below -> Go to Step 5 (Escalate).

5.  **Log**: `§CMD_APPEND_LOG` with `## Pre-Escalation Probe` schema.

#### Step 5 -- Escalate

1.  **Leave worker blocked**: Do NOT send any keystrokes. The worker's AskUserQuestion remains unanswered. The next `await-next` call will re-sweep this pane.

2.  **Log**: `§CMD_APPEND_LOG` with `## Escalation to Human` schema.

3.  **Notify human in chat**: Output in the coordinator's own conversation:
    > **Escalation Required**
    >
    > **Worker**: `[pane_id]` ([skill])
    > **Question**: "[full question text]"
    > **Options**:
    > 1. [option 1]
    > 2. [option 2]
    > ...
    > **Reason**: [Category rule: {category} | Low confidence: {score} | Unknown context]
    >
    > The worker is **blocked** waiting for input. Please either:
    > - Answer here and I'll relay it
    > - Switch to the worker's pane to answer directly

4.  **Wait for human**: The human will either:
    *   **Type an answer here** -> Relay it to the worker via `tmux send-keys`, log as `## Human Resolution`.
    *   **Say "skip"** -> Continue to next pane, leave this worker blocked.
    *   **Handle it directly** in the worker's pane -> The next poll will find the pane no longer `unchecked`.

5.  **Continue**: Return to Step 1 (Wait).

### ESC Interrupt Handling

The user can press **ESC** (or Ctrl+C) at any time during the blocking `await-next` call. This kills the process and returns control to the coordinator.

**When ESC is detected** (the `await-next` call exits abnormally or is interrupted):

Execute §CMD_DECISION_TREE with `¶ASK_COORDINATE_LOOP_EXIT`.

## ¶ASK_COORDINATE_LOOP_EXIT: Choose one: Oversight Interrupted
Trigger: ESC/Ctrl+C during await-next blocking call

- [ ] [NEXT] Resume monitoring
  Return to the event loop immediately
- [ ] [STAT] Fleet status
  Show current worker states, then resume
- [ ] [SYNT] Proceed to synthesis
  End oversight and write the debrief
- [ ] [MORE] Other
  - [ ] [BACK] Return to dispatch
    Need to reassign or add work items
  - [ ] [PLAN] Return to planning
    Need to revise the chapter plan
  - [ ] [RELY] Relay a message
    Send a message to a specific worker pane

**On selection**:
*   **Resume**: Loop back to Step 1.
*   **Fleet status**: Run `engine fleet status`, display in chat, then loop back to Step 1.
*   **Synthesis**: Exit the loop. Proceed to Phase 5.
*   **Back to dispatch**: Exit the loop. Use `--user-approved` to transition back to Phase 3 (Dispatch).
*   **Back to planning**: Exit the loop. Use `--user-approved` to transition back to Phase 2 (Planning).
*   **Relay**: Ask which pane and what message, send via `tmux send-keys`, then loop back to Step 1.

### Loop Exit Conditions

*   **Human says "stop"** or selects "Proceed to Synthesis" from ESC menu: Proceed to Phase 5: Synthesis.
*   **Context approaching overflow**: The overflow hook triggers `§CMD_DEHYDRATE NOW`. Follow `§CMD_DEHYDRATE` (preloaded) to produce JSON and pipe to `engine session dehydrate`. The next Claude resumes at Phase 4 with dehydrated context.
*   **All workers done**: All managed panes report `done` state. Notify human, offer to proceed to Synthesis.
*   **Consecutive timeouts exceed limit**: After N consecutive `TIMEOUT` returns (configurable), notify human that fleet appears fully idle.

### Context Overflow Handling

The oversight loop is long-running and WILL overflow context. When context usage approaches 80%:

1.  **Dehydrate**: Follow `§CMD_DEHYDRATE` — produce JSON with decision history, worker state, and config.
2.  **Include in dehydration JSON**:
    *   Current config file path
    *   Worker pane IDs and their current tasks
    *   Recent decision history (last 10 decisions)
    *   Any pending escalations
    *   Manifest state (v2)
3.  **Restart**: `engine session dehydrate` stores JSON in `.state.json` and triggers restart. Fresh Claude resumes at Phase 4.

---

## 5. Synthesis

§CMD_REPORT_INTENT:
> 5: Synthesizing oversight session. ___ decisions made, ___ escalations.
> Focus: debrief, directive updates, delegation dispatch, artifact reporting.
> Not: monitoring workers or making decisions — synthesis only.

§CMD_EXECUTE_PHASE_STEPS(5.0.*)

**Debrief notes** (for `COORDINATE.md`):
*   Include decision summary tables (autonomous count, escalation count, autonomy rate)
*   Per-worker activity breakdown
*   Escalation pattern analysis
*   Config effectiveness review

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Oversight session complete. Walk through the decisions?"
  debriefFile: "COORDINATE.md"
```

**Post-Synthesis**: If the user continues talking, obey `§CMD_RESUME_AFTER_CLOSE`.

---

### Interrogation Topics (Loop-Specific)
*These topics are available if the user invokes ad-hoc interrogation during the oversight loop. Chapter-level interrogation happens in Phase 1.*

- **Fleet topology** -- which panes, what work is assigned
- **Escalation policy** -- what categories, what threshold
- **Worker context** -- what skills are workers running, what phase
- **Human availability** -- how often can the human check in
