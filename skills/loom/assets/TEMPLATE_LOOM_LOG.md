# Loom Log (The Conductor's Journal)
**Usage**: Track the weave — thread intake, the live ledger, conflicts brokered, escalations, and each thread's advance through the chain.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.
**Authority**: this log is the **narrative** record and the live blocks below are the session's state while the session runs. At a hand-over the open rows are written to the sessions root's `LOOM_INHERITANCE.md` (`assets/TEMPLATE_LOOM_INHERITANCE.md`, whose *Where it lives* section says how to compute that root), and **from that moment that file is authoritative for them** — it is the copy a successor reads, and this log becomes history. One file, one authority at a time, so no row has two owners.

## ▶️ Loom Opened
*   **Batch**: [what tickets/tasks are in scope]
*   **Dispositions**: Autonomy=[Automagic|Careful|Allow-agents] · Council=[selective|auto-after-pr|none] · Interrogation=[Reasonable|Thorough|None] · Detail=[Low|Balanced|High] · Run=[Session|Long-running]
*   **Global slots**: `[n]` live lanes across all looms · cap `[N]` here · `[n]` stale rows kept rather than dropped — or `directory unreadable — one lane at a time until it is`. Taken **here** because the cap is shared with every other loom (`§INV_SLOT_CAP_IS_GLOBAL`): the figure is a reading of every loom's file at the moment this one opens, and nothing later reconstructs what the directory said when this loom chose its first dispatch.
*   **Session branch**: `[name]` @ `[sha at open]` — the base every wave integrates onto. Taken **here** because it is not reconstructable at the boundary: under worktree-per-lane the conductor's tree is not any lane's, so a base read at integration time is a base guessed. A detached HEAD or a tree with no branch is written as that reading (`detached @ <sha>`, `no branch`) and reported; **a loom whose base is unknown does not integrate** (`§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY`).
*   **Execution shape**: [one shared tree | worktree-per-lane] — decides which of the two collision answers is live. One shared tree ⇒ the conductor partitions files and brokers claims, and a wave has nothing to merge. Worktree-per-lane ⇒ **no partition and no brokering**, and lanes land through the wave boundary's merge. Never both.
*   **Interruption**: [confirmed each time | automatic posting | quiet] — which offers reached the operator and which the conductor fired on its own. Taken **here** because whether a human saw a posted comment before it went out is not recoverable from the comment afterwards.
*   **Peer instructions**: [a request to ask | trusted] — whether a peer seat's relayed instruction counted as the operator's. Taken here for the same reason: a conductor that acted on a peer's word leaves nothing in the artifact saying whose word it was.

## 🧵 Ledger (live — rewrite in place as threads advance)
*The session's spine. One row per thread. Stages: triaged → interrogated → building → scrutinized → snapshotted → pr'd → council'd.*
*A pass the conductor ran in its OWN context takes a row here too, under a slug threadId — a grooming pass, an inline ticket, a decision pass, a published weave-status page. `¶INV_LOOM_EVERY_THREAD_PROVES` binds the work rather than the actor and `proofPages` gates on these rows, so a conductor pass with no row is a proof the gate cannot see.*

*`status` is a **closed grammar, not free prose**, because it is the cell a gate reads at a glance and the one place a thread says why it is not moving. A waiting thread names **what it waits on** in `LOOM_AGENT_DIRECTIONS.md` § Progress reporting's own wording, plus **how long** and **what it is doing meanwhile** — `waiting: FACTS → the schema · 41m · idle` or `waiting: path/to/file (denied) · 12m · working around`. The durable event keeps its `📡 Relay / Conflict` entry; this cell is the glance. A bare `in flight` on a thread the stall sweep reads `parked` is a stale cell, and `in flight` is not a reading — it is the absence of one.*

| threadId | ticket | stage | PR | status |
|----------|--------|-------|----|--------|
| ENG-XXXX | [title] | building | — | in flight |
| A | [title] | interrogated | — | queued (wave 2) |
| FACTS | [title] | building | — | waiting: ENG-3141 → the migration · 41m · idle |
| INTRODOC | [title] | building | — | waiting: operator → claim #3 · 2 gates · proceeding on the lean |

## 🗳️ Boards (live — one row per published decision board)
*Sibling to the thread ledger: a board spans threads and has no stage of its own. Capture `docId` as the board publishes — `/decide` §4 says it is not recoverable later, so a row missing it has lost that board's answers permanently. This row is the board's **state of record**: it outlives the pass that published it, and `/decide`'s own record keeps the URL and points back here. `read back` closes as `gate N: folded + read`, or states what the fold found that leaves it open; a bare `open` is an unworked row and blocks Synthesis.*

| board | url | docId | published at | forks held | read back |
|-------|-----|-------|--------------|------------|-----------|
| [slug] | [board URL] | [state-doc docId, or `no shared state`] | [gate N, timestamp] | [forkIds / threadIds] | [gate N: folded + read \| gate N: open — no answers yet] |

## 📚 Docs owed (live — one row per documentation claim the weave has falsified)
*The doc register, sibling to the thread ledger: a claim spans threads and has no stage of its own. A `claim` is a **located sentence** — path, line, what it asserts — because a row naming only a file is a row the doc lane cannot act on, and the lane is dispatched from these rows. Open the row when a thread lands, from its Revise Report's `## Register rows owed` and from the claims the thread falsified; the register is what the conductor tracks, not the doc lane's context, which dies with a context clear. `closed by` reads `revised — <Revise Report path>`, or states what the lane found that leaves it open — `open — no home, escalated`, `open — routed to /document`, `open — unverifiable here, needs <command>`. A bare `open` is an unworked row and blocks Synthesis. A row whose claim is a statement of **intent** — a vision's goal, principle, scope or dependency — or a fact whose supersession the document's history must keep, routes to **`/direct` — reconcile** and closes with the dated reconciliation that records it. It may not route to `/revise`: that lane repairs a claim by making the sentence true, which on a vision erases the deviation.*

| claim (path:line · what it asserts) | from thread | why it is owed | destination | closed by |
|-------------------------------------|-------------|----------------|-------------|-----------|
| `path/to/doc.md:LINE` · [what a reader would check] | [threadId] | [falsified by the change \| unverifiable here \| outside a diff's scope] | [`/revise` \| `/direct` — reconcile \| `/document` \| escalate — no home] | [revised — [report path] \| open — [what the lane found]] |

## ⚖️ Rules owed (live — one row per durable rule a lane learned and was not permitted to land)
*The fourth sibling to the thread ledger, and a sibling of the doc register in particular: the shared directive files sit outside every lane's partition, so a lane that learns a rule can only write it down and hand it on. `¶INV_A_RULE_OWED_HAS_AN_OWNER` names the conductor as that owner. **Open the row from the lane's hand-back line**, `rule owed → <file>: <clause>`, not from its report — a `## Rule owed` block nobody was told about is read by whoever happens to open that report, which is nobody, and that is the failure the lane-side contract exists to prevent.*

*The conductor **rules on each row**: it lands the rule in the named file, or it declines with the reason. Both close the row; neither may be left implicit. A bare `open` is an unworked row and blocks Synthesis, on the same grounds as a bare `open` on a board, a doc or a fork row. A declined rule closes as `declined — <why>` and stays visible, because a rule rejected on purpose and a rule dropped on the floor are the same shape once the session ends.*

| the rule (file · clause) | from thread | why the lane could not land it | ruled |
|--------------------------|-------------|--------------------------------|-------|
| `.directives/PITFALLS.md` · [the rule in a clause] | [threadId] | [outside the lane's partition \| held by another lane \| operator hold] | [landed — [sha or path] \| declined — [why] \| open — [what leaves it open]] |

## 🔓 Open claims (live — one row per fork the operator still owes an answer on)
*The third sibling to the thread ledger, for the same reason the other two are siblings: a fork spans threads and has no stage of its own. **This block was previously in the inheritance template alone**, which made an unanswered fork durable only at a hand-over — so the one moment a lane sits waiting was the one moment nothing was written down. It is live here and carried to the inheritance unchanged at a hand-over.*

*A row's **`prepared context`** is a POINTER, never the card's fields copied in. `/decide` §6 already writes the fork, the options as framed, the lean with its trade-off, the falsifier, and — per `¶INV_REJECTED_OPTIONS_ARE_RECORDED` — what was decided against, into `builds/<slug>_DECIDE.md`. Point at it, so the operator reaching this row reaches a `§FMT_DECISION_CARD` rather than a title and four buttons, and so a successor reading a decided row can still see what it was decided from. A row whose `prepared context` is `none` is a question asked without what it takes to answer it, which is the complaint this block exists to answer.*

*A row's **`meanwhile`** is what stops the fork being a hang. A thread does not idle on an unanswered question by default: it proceeds on the lean with its falsifier recorded, works around, or parks with a reason — `/decide` §5's vocabulary (decide provisionally · hand it to the lane · defer with a trigger) is the shape of the answer, asked when the fork is RAISED rather than when it is answered. `idle` is a legitimate value and the only one that costs the operator their attention, so it carries why idling was the right call.*

*A row closes as `answered gate N — <the choice> — <record path>`, or states what leaves it open. **A bare `answered` is an unworked row** — the same shape as a bare `open` on a board row and a bare `open` on a docs-owed row — because an answer with no artifact is the shape a successor inherits as a decided question with no record of what decided it. A fork settled in chat and nowhere else closes as `open — decided in chat at gate N, not yet recorded`, which is true and actionable, rather than `answered`, which is neither.*

| the fork | what it unblocks | prepared context | meanwhile | asked at | answered by |
|----------|------------------|------------------|-----------|----------|-------------|
| [one line, as a question] | [threadIds / the dispatch that moves once it is decided] | [`builds/<slug>_DECIDE.md` \| board row in 🗳️ Boards \| `none` — and why] | [proceeding on the lean — falsifier: [x] \| working around \| parked — [reason] \| idle — [why idling was right]] | [gate N, timestamp] | [answered gate N — [choice] — [record path] \| open — [what leaves it open]] |

## 📨 Seat handovers (live — one row per topic handed to or from another seat)
*The fifth sibling to the thread ledger. **Not the same thing as `## 🤝 Hand-over written` below**, which is a conductor handing its own state to its OWN SUCCESSOR across a context boundary; this block is one seat handing a topic to **another seat**, a peer that keeps its own context and answers in its own time. The two were one word and are two registers, because a successor inherits everything and a peer takes one topic or declines it.*

*`§INV_HANDOVER_IS_A_ROW` (defined in `skills/loom/SKILL.md` § Constraints) is why the block exists. A handover carried only by a peer `SendMessage` and a narrative entry leaves **a topic the receiving seat never picked up looking exactly like one it took** — and a `🔧 Progress` or `📡 Relay` entry does not close that gap, because neither is rewritten and nothing reads either at a gate. Measured twice, eleven days apart, in the same weave: a pass handed topics to five seats and a later one to seven, five acks came back as peer messages both times, and **not one became a row** on either occasion.*

*Write the row **BEFORE the send**, not after. A row written after is a row the failure mode deletes: the send is the point at which a context most often ends, and the handover that is hardest to reconstruct is the one whose sender stopped mid-relay. The row is the artifact and the message is only its transport.*

*`sent` carries a **delivery reading, never a boolean**. A queued send is not a read — a peer in a different permission mode holds it for its user, and nothing reports back from a Remote Control or a cloud session — so **silence is not an ack** and `§INV_HANDOVER_CLOSES_ON_ACK` forbids the sender closing its own row. An un-acked handover is the case this block exists to show, so a sender that marks its row done on sending has written the bug down instead of the handover.*

*A row closes on the receiving seat's **own words**, and a decline closes it as surely as a take: `taken`, `declined — <why>`, and `already done — <the evidence the seat gave>` all close, on the `⚖️ Rules owed` argument — a topic refused on purpose and a topic dropped on the floor read identically once the session ends. A bare `acked` is an unworked row and blocks Synthesis, like a bare `open` on a board. **An ack that reached only the sender's chat is not recorded**: the reply has to reach the row.*

*`direction` is a closed pair, `sent` or `received`, and **`received` is a first-class row rather than the sender's row read backwards** — a seat asked to act on its own ground owes the asker an outcome, and that round trip (ask · verify · do · report the sha) went unrowed in the same afternoon as the outbound batch. ⚠️ **`→` is not in this grammar and may not be put into it.** `§INV_GROOM_MARKS_WHAT_IT_WRITES` already spends `→` as the **route marker** a groom pass posts onto an inbox root, and `§INV_EXCLUDE_OWN_COMMENTS` is the reader-side filter that drops it so the pass's own reply does not drain back as fresh signal. So a `→ <seat>` reply is what stops the root being re-offered; it is **not** the handover record, and nothing on the receiving side reads it as one. Reading it as an assignment couples two meanings onto one marker in the one place a reader would most reasonably confuse them, and the second meaning would be the one that quietly stops working.*

*`seat` carries the peer's **from-name and its pane id together**, because a from-name that no longer resolves to a pane is a handover sent nowhere that reads as sent — and hook binding resolves by pane name, so a renamed seat breaks silently and nothing turns red.*

*`seatHandovers` gates Loom→Synthesis on these rows and **clears on an empty result written down**, like `docRegister`: a weave that handed nothing to another seat passes by recording that reading, never by skipping the block.*

| direction | seat (from-name · pane id) | the topic | member links | sent | ack |
|-----------|----------------------------|-----------|--------------|------|-----|
| [`sent` \| `received`] | `domain:<Seat>` · `yarik-fleet:domain:<Seat>` | [one line — the topic as the receiving seat will read it] | [the members: ticket keys, comment ids, inbox roots — a topic named with no members is a row the seat cannot act on] | [timestamp · `queued` \| `delivered` \| `send failed — [what]` — the reading, never a boolean] | [`taken` — [what the seat said] \| `declined — [why]` \| `already done — [the evidence]` \| `open — [what leaves it open]`] |

## 🌊 Wave
*The wave's own row, and the integration record that closes it. **A wave is not a thread landing** — it is the whole fan-out since the last boundary, so this block closes once, when the last of its lanes has landed or parked, and not at every loop gate. `wavesIntegrated` gates Loom→Synthesis on these rows and **clears on an empty result written down**, like `docRegister`: a loom that never reached a boundary, or one on a shared tree with nothing to merge, passes by recording that reading rather than by skipping the block.*

*`integration` is the row a reader checks to know **which tree the suite judged**. It is written in **landing order, first-landed first** — which is also what makes the conflict loser the later lander, so the loom keeps one precedence rule instead of two. A lane whose merge conflicted names the lane it went back to; the conductor resolves nothing itself (`§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY`).*

*   **Wave**: [N]
*   **Threads fanned out**: [threadIds]
*   **Partition**: [disjoint file sets, or note what serialized to a later wave and why — `none — worktree-per-lane` where lanes hold their own trees, since the partition and the merge are two answers to one question and only one is live]
*   **Boundary**: [the reading that closed the wave — `engine lane-stall --all`: `<threadId>=done … ` with **no lane reading `running`**, or `not reached — <threadIds> still running`]
*   **Integration**: [per lane, in landing order — `<threadId> <branch>@<sha> → merged <merge sha> (--no-ff)` · `<threadId> → conflict on <paths from --diff-filter=U> → merge aborted, resumed <threadId>` · `<threadId> → conflict, lane unreachable → ESCALATED, open claim rowed` · or `nothing to merge — shared tree`]
*   **Integrated tree**: [the sha the wave assembled to — the one the suite ran against, or `n/a — nothing merged`]
*   **Suite**: [`green @ <sha>` · `red @ <sha> — <what failed>` · `deferred — <threadId> conflict open`. **Never a green taken against a partly-assembled tree**: that is an unrun gate that reads as evidence.]
*   **Wave PR**: [one PR for the assembled wave, whole-branch — or `none — <why>`. A per-lane PR here is the shape this step exists instead of.]

## 📡 Relay / Conflict
*The waiting-on graph's durable home. The conductor builds that graph from these entries rather than holding it in context, because a cycle found in a context that then clears is a cycle rediscovered from nothing.*
*   **Event**: [file claim | conflict | deadlock | escalation | **stall** (the sweep read a lane `parked` or quiet past the threshold)]
*   **Threads**: [who ⇄ who]
*   **Waiting on**: [the lane's own words, per `LOOM_AGENT_DIRECTIONS.md` § Progress reporting — `blocked on <path> (denied)` | `blocked waiting on <threadId> to produce <what>`, or `nothing — the lane stopped without saying` where the sweep found it and the lane never reported]
*   **Since**: [when the wait started, and the sweep's reading — `transcript=41m log=63m state=parked`]
*   **Resolution**: [first-claim-wins → loser deferred | granted | escalated to user → decision | resumed by LOG PATH | re-dispatched fresh]

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
*Two different things are called parked and they **must not collapse into one row**. A thread the conductor parked is a decision with a reason. A lane the stall sweep reads `parked` is a lane that **stopped on its own without handing back** — nobody chose it, nothing is recorded, and it is the shape the operator sees as an agent hung up waiting for something. Write which one this is.*
*   **Thread**: [threadId]
*   **Reason**: [not ripe (triangulate) | overlapping files (deferred) | user parked | **stopped without handing back** — `engine lane-stall` read `state=parked`; the lane's turn ended with no `SubagentHandback` and no block reported]
*   **Lane's LOG PATH**: [absolute path — for a `stopped without handing back` row, the only handle that survives. Read the log before briefing its state: a lane can land files after its last entry.]
*   **Next move**: [resume by LOG PATH with a fresh lane | re-dispatch | the fork it was waiting on, rowed in 🔓 Open claims]

## 💡 Decision
*   **Board**: [its row in 🗳️ Boards, or `no board`]
*   **Choice**: "Chose A over B."
*   **Why**: "Reasoning."

## 🤝 Hand-over written
*Written when the conductor writes the inheritance — at a chosen hand-over, and FIRST when an involuntary exit is imminent. The entry is the receipt; the rows themselves live in the inheritance file.*
*   **Inheritance**: `[the inheritance file's ABSOLUTE path — the sessions root computed as the parent of this session directory, never typed from the convention]`
*   **Rows carried**: [threads N · boards N · docs owed N · rules owed N · open claims N · lane asks open N · seat handovers N · standing arrangements N — each kind named, with any `UNKNOWN —` field called out here rather than left for the successor to discover]
*   **Lanes live at the write**: [threadId → its LOG PATH, for each. **Never an agent id** — a context clear ends every in-process subagent, so an id is unexecutable on arrival.]
    *   **Read the paths from `engine lane-stall "<sessionDir>"`, whose rows close with `logpath=`.** That column is the hand-over field; the `agent=` column beside it is the transcript and is diagnostic only. **Take the value as everything after `logpath=` to end of line — `sed 's/.*logpath=//'`, never `awk '{print $NF}'`:** this session's own directory sits under `Shared drives`, and the last whitespace field of such a row is a truncated path that still reads as one. A row reading `logpath=none` is a lane with no log, which is a **different hand-over** from a lane with one and is carried as that reading rather than filled in with the transcript. Take the reading from a bare invocation — a pipeline reports its last command's status, not the sweep's — and note the `window=` the first line states, because every row is scoped to it.
*   **Re-measure on arrival**: [the readings in this entry that are point-in-time and must be re-taken before being acted on]

## ♻️ Inheritance claimed
*Written by the successor, before it acts on any row.*
*   **Read**: `[inheritance path]` — rows claimed: [which] · rows left to another owner: [which]
*   **Roots searched**: [the candidate roots tried, in the order tried, and which held a copy — a copy at more than one root is reported here as a divergence and never merged]
*   **Re-measured first**: [the predecessor's readings re-taken, and which of them had moved]
*   **Rows refused**: [any row with an `UNKNOWN` in a field needed to act — reported, not acted on]
