---
name: coordinate
description: "Persistent fleet coordinator — monitors workers, answers what it may rule on (orientation questions in every mode; grant classes A–D only in Manager mode) and passes the rest up its parent chain, to the operator only from a seat with no parent. Triggers: \"coordinate the fleet\", \"manage workers\", \"start oversight\", \"monitor agents\"."
version: 3.0
tier: protocol
---

Persistent fleet coordinator — monitors TMUX fleet workers, answers the AskUserQuestion prompts it may rule on via `tmux send-keys` (orientation questions in every mode; grant classes A–D in Manager mode only), and passes everything else up its parent chain, reaching the human only from a seat with no parent.

# Oversight Protocol (The Manager's Code)

Execute §CMD_EXECUTE_SKILL_PHASES.

This skill has three modes of operation: **Chapter Planning** (Phases 1-2) where the coordinator interrogates context and creates a rich chapter plan, **Dispatch** (Phase 3) where work items are mapped to workers and delegation tags are applied, and the **Oversight Loop** (Phase 4) which runs as a persistent event loop. Worker communication happens ONLY through the existing TUI (`§INV_TRANSCRIPT_IS_API`): read terminal transcripts, type responses via `tmux send-keys`. There is one exception: a question carried **between seats** as an /ask file (see `¶INV_MANAGER_IS_THE_FRONT_DOOR`). Every other exchange with a worker stays transcript-only.

The coordinator consumes any structured document (vision docs from `/direct`, brainstorm outputs, analysis reports) as input for chapter planning. It works best with `/direct` vision documents but is not limited to them.

## Core Invariants

*   **§INV_COORDINATOR_NEVER_RESTARTS_WORKERS**: The coordinator MUST NOT kill or restart worker processes. It only sends keystrokes. Stuck workers are escalated to the human.
*   **¶INV_ESCALATION_CATEGORIES_OVERRIDE**: Category-based escalation rules from `coordinate.config.json` always override confidence-based autonomy. Dangerous operations always escalate regardless of confidence.
*   **§INV_SERIAL_PROCESSING**: Workers are processed one at a time. No parallel decision-making.
*   **§INV_TRANSCRIPT_IS_API**: Worker communication happens through terminal transcripts. No custom protocols. The one exception is a question that moves between seats as an /ask file, under `¶INV_MANAGER_IS_THE_FRONT_DOOR`. That covers a seat's question addressed to this coordinator, and this coordinator's pass-up to its parent. Answering a worker's AskUserQuestion is always done through its transcript.
*   Log significant decisions per the config's explicit categories. Do not log routine option picks.
*   **¶INV_MANAGER_IS_THE_FRONT_DOOR**: An escalation goes **up the parent chain**, not straight to the human. The coordinator rules on what the grant allows, answers orientation questions itself, and passes the rest to its `FLEET_PARENT` with a recommendation attached. Only a seat with no parent addresses the operator. (Operator ruling, `manager-tier_INTERROGATE.md` § Escalation routing.) A question moving between seats travels as an /ask file. The operator chose that carrier, and it is the one stated exception to `§INV_TRANSCRIPT_IS_API`, limited to seat-to-seat hops.
*   **¶INV_MANAGER_NEVER_RULES_ON_RESERVED**: Reserved classes (E history others hold, F standing configuration, G outward obligations, and H while it is unmarked) and the IDE-135 hard floor (cyclic deadlock, build failing after retries, blocking critique finding, thread loopback) are never a manager's ruling. They pass up with a recommendation, carrying the mark `reserved-for: operator` on the /ask and on the row. A rung that receives such a mark may only forward the question. It never rules on it. `scripts/hop.sh may-rule` enforces this, and confidence cannot override it.
*   **¶INV_MANAGER_NEVER_ANSWERS_ITS_OWN**: A manager never rules on a question it raised itself (IDE-135's non-goal). Its own forks go up like any other.
*   **¶INV_HOP_IS_ROWED**: Every hop (received, ruled, passed up, re-pinged, answered) is **one** row, keyed by its ask id (`hop.sh ask-id`). A blocked worker that `await-next` re-emits is found by `hop.sh rowed` and is not rowed or asked a second time. Each row in the `🪜 Escalations` register of `COORDINATE_LOG.md`, written **before** the send. It uses the `📨 Seat handovers` row shape plus a `disposition` cell. No question moves between seats without a row, and the rows live nowhere else.
*   **¶INV_HOP_ADDS_NO_SCHEDULER**: The hop adds no polling loop, timer, clock or background wait (IDE-135). The operator ruled at 2026-10-28 23:05: "push is fine; timers aren't". **Re-pinging is manual.** The hook point is the seat's `/next`, which lists overdue asks: a `sent` row with an open `ack`. Passing an ask one rung further up is a deliberate step (§ Re-ping and re-pass). It never happens automatically.
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
> - **"Use defaults"** -- Copy `assets/coordinate.config.example.json` (Manager mode: `assets/coordinate.manager.config.json`) to the session directory unchanged. `hop.sh` requires a real config file, so "defaults" means that copy and never an absent file.
> - **"Create config"** -- I'll create one for you to customize

If "Create config": Copy `assets/coordinate.config.example.json` to the session directory and present for editing. **In Manager mode**, copy `assets/coordinate.manager.config.json` (the C1 preset) instead.

**Parent Resolution** (every mode): Resolve where a pass-up goes before entering the loop, and record the chain.
```bash
H=~/.claude/engine/skills/coordinate/scripts/hop.sh
bash $H chain > [sessionDir]/hop-chain.txt || echo "chain exit $?"   # must be 0
bash $H target --config [sessionDir]/coordinate.config.json --chain-file [sessionDir]/hop-chain.txt
```
*   `chain` records this seat's ancestry from the live tree. When a parent's pane later dies, its own `@pane_parent` dies with it, and only this record still knows the next rung. **Check its exit.** A non-zero exit (2: no identity; 4: the tree is unreadable; 5: a rung is already missing or the chain loops) leaves a **partial** file, and a later `target` would skip a live ancestor because of it. STOP at Setup as for `target` exit 2, and name the rung that is missing.
*   `target` reads this seat's **live** `@pane_parent`, and a readable live edge always wins. `FLEET_PARENT` is exported once by run.sh at launch, so after a reparent it is stale: when it is unset or disagrees, `target` notes it on stderr and uses the live edge. `@pane_manager` is not read. The exit codes:

| exit | stdout | meaning | do this |
|------|--------|---------|---------|
| 0 | `<window:label> <pane_id>` or `operator` | the parent, or no parent | use it |
| 3 | a target | a dead rung was skipped using the chain record; a dead top gives `operator` | use it, and copy the stderr reason into the `sent` row |
| 2 | — | config missing or unparseable, `hop.parentFrom` set, or no identity for this seat | Setup: STOP and fix it. In the loop: Step 5c, reason `broken hop: <stderr>` |
| 4 | — | the live tree could not be read | as for exit 2 |
| 5 | — | the live edge cannot be used: this seat is not in the live tree (FLEET_PARENT alone is never trusted), or the live edge names this seat or `operator` | as for exit 2. Name both values to the human |

*   A route to the operator is either `operator` printed on stdout or a Step 5c with a stated reason. It is never a silent fallback.
*   Show the result, for example `> **Pass-ups go to:** manager:director (%114)` or `> **Pass-ups go to:** the operator (no parent)`.

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

Block until a worker pane needs attention, a tag file changes, or timeout expires. **Sweep only the panes that are not waiting on a pass-up:**
```bash
P=$(bash ~/.claude/engine/skills/coordinate/scripts/hop.sh panes --log [sessionDir]/COORDINATE_LOG.md)
engine await-next [waitTimeoutSeconds] --panes "$P"
```
*   `hop.sh panes` takes `FLEET_MANAGES` and removes every pane whose `received` row is `passed up` while its `sent` row's `ack` is still open. A worker blocked on a pass-up stays `unchecked`, and `await-next` keeps no memory between calls. Without this filter, the same pane comes back as `CHILD` at once on every call: the loop never blocks, and siblings that sort after it are never returned. The pane comes back into the sweep as soon as its answer closes the `ack`.
*   When every pane is held, the command prints `-`, a name that matches no pane. An empty `--panes` would make `await-next` fall back to all of `FLEET_MANAGES`.
*   Exit 2 (no log, or no managed panes) means you pass `FLEET_MANAGES` unchanged and say so in the log.

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
> `[HH:MM] [N] workers: [working] working, [done] done, [idle] idle. [K] pass-ups open (oldest [age]). Waiting...`

The open pass-up count is read from the register's `sent` rows. It is printed so whoever watches this seat sees what is outstanding, and it never triggers a re-ping (§ Re-ping and re-pass).

**Asks addressed to this seat** (checked at the top of **every** iteration, before Step 2). This is the receiving half of the hop. A child manager's pass-up arrives as an /ask file with `to:` this seat, and nothing in `await-next` watches that directory:
```bash
bash ~/.claude/engine/skills/coordinate/scripts/hop.sh inbox
```
*   Each line reads `<seat>/<id>`, then the file, then `reserved-for:operator` or `-`. It comes from `engine ask list --status open --to <this seat>`, or from the /ask headers directly when the CLI is unavailable.
*   For each id that `hop.sh rowed` does not already find, run Step 2.3 and Step 2.4 on that file. Then continue through Steps 3 to 5, passing `--reserved-for operator` when the line carries the mark.
*   Exit 2 means neither the ask CLI nor the ask root could be read. Say so in the log and continue. The asker's own ping is the fallback channel.

**Answers that came back** (checked at the top of **every** iteration, before Step 2, because an outstanding pass-up keeps its worker `unchecked`, and `await-next` then returns `CHILD` instead of `TIMEOUT`): for each `sent` row with an open `ack`, read the /ask file named in its member links. If its status is answered (per /ask), relay the answer down (Step 5, *Answer comes back*). This is a read of files the row already names. It is not a clock.

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
    *   **Raised by**: the seat that asked (`window:label`). It is this seat itself when the fork is the coordinator's own.

3.  **Questions that arrive as files**: a worker or a child manager may send its question as an /ask file addressed `to:` this seat instead of an AskUserQuestion (format per /ask). Read its header (why, importance, stakes, context, alternatives, lean, falsifier) as the decision context. Its `from:` field is **Raised by**. Assess it like any other question.

4.  **Dedupe, then row it**: the ask id is the /ask file's id. For an AskUserQuestion it is `hop.sh ask-id --pane [pane_id] --question "[question block]"`. Pass the **raw question block captured from the pane**, verbatim, never your own summary of it: the id normalises only whitespace, so a paraphrase gives a new id.
    ```bash
    bash ~/.claude/engine/skills/coordinate/scripts/hop.sh rowed --log [sessionDir]/COORDINATE_LOG.md --id [ask id]
    ```
    *   exit 0: already rowed. Write no new row and send no new /ask. Return to Step 1. After the row reads `passed up`, `hop.sh panes` keeps this pane out of the next sweep, so it does not come back.
    *   exit 2 (from `rowed` or `ask-id`): the dedupe could not run. Write the row anyway, append `dedupe failed — <stderr>` to its topic cell, and do not send a second /ask for a question already passed up in this iteration.
    *   exit 1: append a `received` row with `ask:[ask id]` in its member links (`¶INV_HOP_IS_ROWED`). Its `disposition` stays `open` until Step 4, 4a or 5 closes it.
    *   If the incoming /ask carries `reserved-for: operator`, copy that mark into the row's topic cell.

#### Step 3 -- Assess

0.  **Hop Check** (authority comes before confidence). Answer **both** classification questions, every time:
    *   **Class**: `orientation`, or one uppercase grant class `A`–`H` (§ The Grant). Lowercase letters are refused.
    *   **Floor**: `none`, or one of `cyclic-deadlock`, `build-fails-after-retries`, `blocking-critique`, `thread-loopback`. A floor item outranks any class, including `orientation`.
    *   **Orientation** means a question about *where things are or what was already said*: which file, which branch, which ticket, which seat owns something, what an existing instruction literally says. It decides nothing new and changes nothing. *In*: "Which session dir holds the plan?" *Out*: "Should I push this branch?" (that is B or E), and "Does 'land batch 2' cover batch 3?" (that is D).
    ```bash
    bash ~/.claude/engine/skills/coordinate/scripts/hop.sh may-rule --class [class] --floor [none|item] \
      --raised-by [Raised by] --config [sessionDir]/coordinate.config.json [--reserved-for operator]
    ```
    *   Pass `--reserved-for operator` when the incoming /ask or row carries that mark.
    *   `pass-up: …` (exit 1) -> Go to Step 5 with that reason. This is **final**: no confidence score and no probe overrides it. If a second line reads `reserved-for: operator`, carry that mark on the /ask and on the row.
    *   `rule` (exit 0) -> Continue to the category check.
    *   **Any other exit** (2: a missing argument, a bad class, a broken config, or no identity for this seat) -> treat it as a pass-up, with the script's stderr as the reason, **and mark it `reserved-for: operator`** (fail closed). An authority check that could not run must not let a floor item travel unmarked. Never treat it as a ruling.

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

3.  **Log** (if in `alwaysLog` categories): `§CMD_APPEND_LOG` with `## Autonomous Decision` schema. **A ruling on a grant class is always logged.** It carries its **class**, its **condition** and **what would reverse it**. The grant proposal's words: "a grant with no condition is a blank cheque; a grant with no record is unreviewable." Close the question's `received` row with disposition `answered`.

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

5.  **Log**: `§CMD_APPEND_LOG` with `## Pre-Escalation Probe` schema. If the probe settled the question, the `received` row's disposition is `probed`.

A probe raises **confidence**. It never grants **authority**. A question that `hop.sh may-rule` passed up is not probed into a ruling. If it needs more context before it goes up, probe first and attach what came back. Use `/council` second, and only when there is a subject for it. Council is read-only, so it cannot settle an authority question. A question settled through it closes as `councilled`. A question that dissolves on its own (the worker answered itself, or the pane moved on) closes as `absorbed`.

#### Step 5 -- Escalate (pass it up the chain)

Re-run `hop.sh target --config [sessionDir]/coordinate.config.json --chain-file [sessionDir]/hop-chain.txt` here rather than trusting the Setup reading, because the tree may have changed since then. Handle every exit code:
*   **exit 0**: the target on stdout.
*   **exit 3**: the target on stdout is still valid. A dead rung was skipped, or the top of the chain is dead and it printed `operator`. Copy the stderr reason into the `sent` row's `sent` cell.
*   **exit 2, 4 or 5**: there is no target. Go to 5c with the reason `broken hop: <stderr>`, so the operator is told why the chain did not carry it. This step sends every exit 5 to 5c. `¶CMD_CONTINUE_ON_STOP` step 4.1 (the ask a seat writes on an auto-continue) splits exit 5 under the director's interim rule: when stderr says this seat is not in the live tree and names `FLEET_PARENT='<seat>'`, that ask goes to that seat. The split is not adopted here yet.

1.  **Leave worker blocked**: Do NOT send any keystrokes. The worker's AskUserQuestion remains unanswered. The next `await-next` call will re-sweep this pane. **Keep the middle rung thin**: a worker waits on every rung above it, so pass the question up at once. Do not hold it for a batch.

2.  **Attach a recommendation**, always, including on reserved classes and floor items. State the lean, why, and what would falsify it.

**5a. `target` printed `operator`** (no parent, or a dead top): escalate to the human (5c).

**5b. Parent resolved**: pass the question up one rung.
*   **Row first**: append a `sent` row to `🪜 Escalations` *before* sending (`¶INV_HOP_IS_ROWED`). Put `ask:[ask id]` and the /ask file's path in its member links. The `seat` cell holds the parent's from-name and pane id. The `sent` cell holds a delivery reading with its time. Close the `received` row's disposition as `passed up`.
*   **Mark it**: when `may-rule` printed `reserved-for: operator`, write `reserved-for: operator` into the /ask's header and at the start of the row's topic cell. A parent that receives it can only forward it (Step 3.0 `--reserved-for operator`), and only the operator's answer closes it.
*   **Carry it as an /ask file** (format per /ask). If the question arrived as an /ask file, change only its `to:` field to the parent. If it arrived as an AskUserQuestion, write a new /ask file with `from:` this seat and `to:` the parent. Put the worker's question and options in as the decision tree and your recommendation as its `lean`. Delivery, and the fallback when a delivery is missed, are also per /ask. This skill does not depend on /ask's code. If /ask is not installed, send the parent seat a one-line note naming the question and record that in the `sent` cell.
*   **Then continue the loop.** Never wait in place for the parent. Nothing re-pings automatically. See § Re-ping and re-pass.
*   Log `§CMD_APPEND_LOG` with `## ⬆️ Pass-up` schema.

**Answer comes back** (found by the check at the top of each iteration): the answering seat's own words close the `sent` row's `ack`. **On a `reserved-for: operator` ask, only an answer by the operator closes it.** An answer from any other seat is rowed as `declined — not the operator's answer`, and the question stays up. Relay it down by typing the answer to the blocked worker via `tmux send-keys`, or by answering its /ask file. Log it as `## 🔄 Human Resolution`, with **Resolved by** naming the seat that answered.

**5c. Human escalation** (no parent):

3.  **Log**: `§CMD_APPEND_LOG` with `## Escalation to Human` schema. Write a `sent` row with seat `operator`.

4.  **Notify human in chat**: Output in the coordinator's own conversation:
    > **Escalation Required**
    >
    > **Worker**: `[pane_id]` ([skill])
    > **Question**: "[full question text]"
    > **Options**:
    > 1. [option 1]
    > 2. [option 2]
    > ...
    > **Reason**: [Category rule: {category} | Low confidence: {score} | Unknown context | Hop: {may-rule reason}]
    > **Recommendation**: [the lean, why, and what would falsify it]
    > **Came from**: [the seats the question passed through, from the register]
    >
    > The worker is **blocked** waiting for input. Please either:
    > - Answer here and I'll relay it
    > - Switch to the worker's pane to answer directly

5.  **Wait for human**: The human will either:
    *   **Type an answer here** -> Relay it to the worker via `tmux send-keys`, log as `## Human Resolution`, and close the operator row's `ack` in the human's words. If the question came up from a child manager, relay the answer down to that seat instead (the answer to its /ask file, per /ask). That seat then relays it to its own worker.
    *   **Say "skip"** -> Continue to next pane, leave this worker blocked.
    *   **Handle it directly** in the worker's pane -> The next poll will find the pane no longer `unchecked`.

6.  **Continue**: Return to Step 1 (Wait).

### Re-ping and re-pass (manual)

The operator ruled at 2026-10-28 23:05: "push is fine; timers aren't". So nothing in this skill re-pings on a clock.
*   **Hook point: the seat's `/next`.** It lists overdue asks: `sent` rows with an open `ack`, oldest first. The 10-minute and 20-minute figures from the interrogation are a reading guide for that list, not a timer.
*   **Re-ping**: a deliberate one-line note to the same seat naming the ask id. Append `re-pinged HH:MM` to the row's `sent` cell.
*   **Re-pass one rung up**: a deliberate step. Run `hop.sh target --of [the unanswered seat] --chain-file [sessionDir]/hop-chain.txt` and handle its exit codes as in Step 5. Change the /ask's `to:` field and write a new `sent` row. Set the old row's `disposition` to `superseded — passed up to [seat]` and leave its `ack` alone: the sender never closes its own row. The first answer to arrive wins; a later one is rowed as `declined — superseded`.

### The Grant (v1, installed)

**Installed 2026-10-28** from GRANTBOARD (IDE-238). The record is `builds/authority-grant_DECIDE.md` in the 2026_10_28_DIRECTOR session: the operator took the leans. The grant is a living document, and amendments go through RULINGS (IDE-233).

| class | what | v1 |
|-------|------|----|
| A | assigning an action the operator already approved | delegated |
| B | a fast-forward or an append onto ground this fleet owns, under its four conditions | delegated |
| C | a provisional working position, for this weave only | delegated |
| D | interpreting a ruling already given | delegated |
| E | rewriting history other people hold | reserved |
| F | a standing configuration change | reserved |
| G | an outward obligation | reserved |
| H | approving a merge of verified work | reserved (unmarked) |

**Manager mode only** (director ruling R7, 2026-10-29). The grant lives in `assets/coordinate.manager.config.json`. `coordinate.config.example.json`, which the other modes copy, has an empty grant and keeps the blanket `"git operations"` entry. An autonomous, cautious, supervised or custom run therefore rules on orientation questions only and passes every class question up.

*   In the manager config, `grant.classes` is `["A","B","C","D"]`. `grant.clauses.<class>` holds each class's condition and reversal, and a ruling copies both into its `✅ Autonomous Decision` entry.
*   `alwaysEscalate` (manager config):
    *   The blanket `"git operations"` entry is replaced by the four git clauses quoted on the board, verbatim from `AUTHORITY_GRANT_PROPOSAL.md` lines 117–120.
    *   The proposal's backstops are restored verbatim from lines 121, 122 and 126: standing configuration (F), outward obligations (G) and **merge approval into fleet-owned ground** (H). This is director ruling R6, interpreting v1 as class D. So a merge is still escalated **by category** even if it is classed as B.
    *   Four entries from the earlier config are kept beyond the proposal, conservatively: architecture changes, PR creation, deployment and dependency changes.
*   `alwaysLog` (manager config) carries the proposal's lines for classes C and D: "provisional rulings, with the escalation they stand in front of" and "readings-forward of an existing instruction, with the words read".
*   `hop.sh` refuses E, F and G even if a config lists them, and H unless the grant lists it.
*   **To amend**: change `grant.classes` and `grant.clauses` in the config, quoting the operator's mark. Install nothing that was not marked.

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
    *   Any pending escalations (the open `🪜 Escalations` rows) and the path of `hop-chain.txt`
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
