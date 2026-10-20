# Loom Log (The Conductor's Journal)
**Usage**: Track the weave — thread intake, the live ledger, conflicts brokered, escalations, and each thread's advance through the chain.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.
**Authority**: this log is the **narrative** record and the live blocks below are the session's state while the session runs. At a hand-over the open rows are written to `<sessionsRoot>/LOOM_INHERITANCE.md` (`assets/TEMPLATE_LOOM_INHERITANCE.md`), and **from that moment that file is authoritative for them** — it is the copy a successor reads, and this log becomes history. One file, one authority at a time, so no row has two owners.

## ▶️ Loom Opened
*   **Batch**: [what tickets/tasks are in scope]
*   **Dispositions**: Autonomy=[Automagic|Careful|Allow-agents] · Council=[selective|auto-after-pr|none] · Interrogation=[Reasonable|Thorough|None] · Detail=[Low|Balanced|High] · Run=[Session|Long-running]

## 🧵 Ledger (live — rewrite in place as threads advance)
*The session's spine. One row per thread. Stages: triaged → interrogated → building → scrutinized → snapshotted → pr'd → council'd.*

| threadId | ticket | stage | PR | status |
|----------|--------|-------|----|--------|
| ENG-XXXX | [title] | building | — | in flight |
| A | [title] | interrogated | — | queued (wave 2) |

## 🗳️ Boards (live — one row per published decision board)
*Sibling to the thread ledger: a board spans threads and has no stage of its own. Capture `docId` as the board publishes — `/decide` §4 says it is not recoverable later, so a row missing it has lost that board's answers permanently. This row is the board's **state of record**: it outlives the pass that published it, and `/decide`'s own record keeps the URL and points back here. `read back` closes as `gate N: folded + read`, or states what the fold found that leaves it open; a bare `open` is an unworked row and blocks Synthesis.*

| board | url | docId | published at | forks held | read back |
|-------|-----|-------|--------------|------------|-----------|
| [slug] | [board URL] | [state-doc docId, or `no shared state`] | [gate N, timestamp] | [forkIds / threadIds] | [gate N: folded + read \| gate N: open — no answers yet] |

## 📚 Docs owed (live — one row per documentation claim the weave has falsified)
*The doc register, sibling to the thread ledger: a claim spans threads and has no stage of its own. A `claim` is a **located sentence** — path, line, what it asserts — because a row naming only a file is a row the doc lane cannot act on, and the lane is dispatched from these rows. Open the row when a thread lands, from its Revise Report's `## Register rows owed` and from the claims the thread falsified; the register is what the conductor tracks, not the doc lane's context, which dies with a context clear. `closed by` reads `revised — <Revise Report path>`, or states what the lane found that leaves it open — `open — no home, escalated`, `open — routed to /document`, `open — unverifiable here, needs <command>`. A bare `open` is an unworked row and blocks Synthesis.*

| claim (path:line · what it asserts) | from thread | why it is owed | destination | closed by |
|-------------------------------------|-------------|----------------|-------------|-----------|
| `path/to/doc.md:LINE` · [what a reader would check] | [threadId] | [falsified by the change \| unverifiable here \| outside a diff's scope] | [`/revise` \| `/document` \| escalate — no home] | [revised — [report path] \| open — [what the lane found]] |

## 🌊 Wave
*   **Wave**: [N]
*   **Threads fanned out**: [threadIds]
*   **Partition**: [disjoint file sets, or note what serialized to a later wave and why]

## 📡 Relay / Conflict
*   **Event**: [file claim | conflict | deadlock | escalation]
*   **Threads**: [who ⇄ who]
*   **Resolution**: [first-claim-wins → loser deferred | granted | escalated to user → decision]

## ⬆️ Escalation
*   **Trigger**: [cyclic deadlock | build-fails-after-retries | scrutinize MUST-FIX | thread loopback]
*   **Thread**: [threadId]
*   **Posed as**: [the plain-language choice shown to the operator]
*   **Decision**: [what the user chose / recommended default taken]

## 🔧 Progress
*   **Thread**: [threadId]
*   **Stage advance**: [from → to]
*   **Notes**: [Build Report path, critique outcome, snapshot/pr/council result]

## 🅿️ Parked
*   **Thread**: [threadId]
*   **Reason**: [not ripe (triangulate) | overlapping files (deferred) | user parked]

## 💡 Decision
*   **Board**: [its row in 🗳️ Boards, or `no board`]
*   **Choice**: "Chose A over B."
*   **Why**: "Reasoning."

## 🤝 Hand-over written
*Written when the conductor writes the inheritance — at a chosen hand-over, and FIRST when an involuntary exit is imminent. The entry is the receipt; the rows themselves live in the inheritance file.*
*   **Inheritance**: `[absolute path to <sessionsRoot>/LOOM_INHERITANCE.md]`
*   **Rows carried**: [threads N · boards N · docs owed N · open claims N · standing arrangements N — each kind named, with any `UNKNOWN —` field called out here rather than left for the successor to discover]
*   **Lanes live at the write**: [threadId → its LOG PATH, for each. **Never an agent id** — a context clear ends every in-process subagent, so an id is unexecutable on arrival.]
*   **Re-measure on arrival**: [the readings in this entry that are point-in-time and must be re-taken before being acted on]

## ♻️ Inheritance claimed
*Written by the successor, before it acts on any row.*
*   **Read**: `[inheritance path]` — rows claimed: [which] · rows left to another owner: [which]
*   **Re-measured first**: [the predecessor's readings re-taken, and which of them had moved]
*   **Rows refused**: [any row with an `UNKNOWN` in a field needed to act — reported, not acted on]
