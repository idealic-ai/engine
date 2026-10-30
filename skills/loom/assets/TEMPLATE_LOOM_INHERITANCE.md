# Loom Inheritance — the open-work rows that outlive a session

**For the next conductor, which is probably a fresh context. This file is STATE; the session log is NARRATIVE.** Where the two disagree about a row, this file is authoritative — the log says what happened, this says what is still open.

**Where it lives**: one file named `LOOM_INHERITANCE.md` at the **sessions root**, beside the dated session directories rather than inside one, because a successor knows the root and does not know which predecessor to read. It is **rewritten in place** by the handing-over conductor; the superseded copy is appended to that session's own log, so the history stays with the narrative and the live rows stay addressable.

**The root is COMPUTED, never typed from a convention** — a conductor that types a root writes to a file nobody reads, which is the one failure this file cannot survive. Compute it as the parent of the **active session directory**: `engine session find` yields that directory as an absolute path, and `§CMD_HANDOFF_TO_AGENT`'s payload already carries it as `sessionDir`. That is the same anchor the engine's own resolver produces — `resolve_sessions_dir` in `engine/scripts/lib.sh`, which walks up to the nearest `.claude/` ancestor and nests under `$WORKSPACE` when one is set — whenever the two agree.

**They do not always agree, so there is no single root to pick.** A resolver's answer and the root a session is demonstrably writing into diverge under a symlinked `sessions/`, an artifact root on a shared drive, or a `$WORKSPACE` set for one process and not another — and a session directory of the *same name* can exist under both roots holding different content, with every path check answering at exit 0. What a conductor does instead:

*   **Writing** uses the parent of the session directory it is already writing into, because that is the root it can prove rather than the root it can name. It **also puts the file's absolute path in the hand-over** — `requiredFiles` carries paths — so the convention is the successor's fallback, not its only address.
*   **Reading** searches candidate roots in **preference order**, which is the engine's own precedent (`engine/scripts/session.sh` builds an ordered `SEARCH_PATHS`: the `$WORKSPACE` root first, the workspace-less root second): the parent of any session directory the successor was handed, then the resolver's answer, then that answer with `WORKSPACE` unset.
*   **Compare roots PHYSICALLY, not by spelling.** A project's `sessions/` is commonly a symlink into a data root, so two candidates are routinely two spellings of one directory; resolve each with `pwd -P` (or `realpath`) before deciding they differ, or every correct read reports a divergence that does not exist. This is the comparison `engine/scripts/log.sh`'s own session guard makes, for the same reason.
*   **A copy at more than one PHYSICALLY distinct root is a divergence to REPORT, never to merge.** Read every copy found, act on the one whose rows are newest, and name the roots that held one in the `## ♻️ Inheritance claimed` entry. Merging two roots silently invents a state neither conductor wrote.

**Several looms may share this file.** Every row carries its `owner` — the session directory that wrote it — so a fresh conductor reads the whole file and claims only the rows whose subject it is taking, and says in its startup entry which rows it claimed and which it left.

**A field a successor needs and the writer could not fill is written `UNKNOWN — <why>`, never left blank.** A successor that finds `UNKNOWN` in a field it needs to act **stops and reports that row** rather than acting on the rest of it — a partial row acted on silently reproduces the loss this file exists to prevent, with no visible gap where it used to be. A blank cell is a defect in the row, not a permission.

**An open row may be passed on. It may never be dropped.** A conductor closing a session carries every open row into this file; one that would discard a row instead has not written a legitimate hand-over.

---

## 🧵 Threads — work in flight or parked

*A row closes when its thread reaches a terminal stage with its proof URL recorded, or when the operator parks it with a reason. `reach it by` is the lane's **LOG PATH**, never an agent id alone: an id survives a `/clear` in the same process (*measured 2026-10-30*) but not a process exit or restart (`/dehydrate` on the watchdog path (no tmux, or `DISABLE_CLEAR=1`: `session.sh dehydrate` sends `kill -USR1` to the watchdog, which kills the Claude process, or with no watchdog prints a manual restart), a pane relaunch, a crash), where `SendMessage` answers *no transcript found* (*relayed, 2026-10-29*), and the log is what a fresh lane reads to take over.*

*🔍 `scrutiny` travels because it is the reading a successor cannot re-take (`§INV_LOOM_SCRUTINY_IS_DECLARED_AND_ROWED`). Once the lane is gone, nothing in git or in the ticket says whether anybody other than its author read its work, and `clean` and `never read` look identical in the diff. So the cell is carried verbatim — `clean` · `[n] findings → triaged` · `not scrutinized — [why]` — and a row arriving with it **empty** reads `UNKNOWN — cell never written`, which a successor stops on rather than acting past, like any other `UNKNOWN` in a field it needs.*

| owner | threadId | subject | stage | 🔍 scrutiny | reach it by (LOG PATH) | file holds | closes when |
|-------|----------|---------|-------|----------|------------------------|------------|-------------|
| [session dir] | [ENG-XXXX / SLUG] | [one line] | [triaged \| interrogated \| building \| scrutinized \| snapshotted \| pr'd \| council'd \| parked] | [clean \| [n] findings → triaged \| not scrutinized — [why] \| `UNKNOWN — cell never written`] | `[absolute path to the lane's _BUILD_LOG.md]` | [paths this thread holds, or `none`] | [the terminal stage + its proof URL \| `parked — <reason>`] |

## 🗳️ Asks — asks this loom raised, still open

*Carried from the session log's `## 🗳️ Asks` block **unchanged**. The ask file itself survives the session, so a row here is a pointer: a successor reads it with `engine ask read <seat>/<id>` once it is answered, or re-pings by hand while it is not. A row closes when a successor has read the answer and recorded it; it may be passed on open, and it may not be discarded. An inherited `🗳️ Boards` row, from a log written before IDE-255, is still folded with `/decide` §4's fold and closed there, never re-asked.*

| owner | ask | to | forks held | closes when |
|-------|-----|----|------------|-------------|
| [session dir] | [`<seat>/<id>`] | [holder seat, or `operator`] | [forkIds / threadIds] | [answer read, with what it changed] |

## 📚 Docs owed — claims a landed change falsified

*The doc register. One row per documentation claim a landed thread made false, and per piece of doc work a per-thread lane is forbidden to do. `claim` is a located sentence — path, line, what it asserts — because a row naming only a file is a row a successor cannot act on. A row closes when `/revise` repairs the claim and its Revise Report records the repair, or when the row is routed to `/document` and that session picks it up. A row whose claim is a statement of **intent** — a vision's goal, principle, scope or dependency — or a fact whose supersession the document's history must keep, routes to **`/direct` — reconcile** and closes with the dated reconciliation that records it. It may not route to `/revise`: that lane repairs a claim by making the sentence true, which on a vision erases the deviation.*

| owner | from thread | claim (path:line · what it asserts) | why it is owed | destination | closes when |
|-------|-------------|-------------------------------------|----------------|-------------|-------------|
| [session dir] | [threadId] | `path/to/doc.md:LINE` · [what a reader would check] | [falsified by the change \| unverifiable here \| outside a diff's scope] | [`/revise` \| `/direct` — reconcile \| `/document` \| escalate — no home] | [Revise Report path + the repair \| the session that took it] |

## ⚖️ Rules owed — durable rules a lane learned and could not land

*Carried from the session log's `## ⚖️ Rules owed` block **unchanged**, the way an ask row and an open claim are. The block is **live in the log** and this is its hand-over copy. The two directions of that pairing have each failed once: an open claim was durable in this file alone, so the one moment a lane sat waiting was the one moment nothing was written down; a rule owed was durable in the log alone, so a handing-over close counted it on the receipt and had nowhere to put it. A row kind lives in both places or it is lost at one of the two moments that matter.*

*The shared directive files sit outside every lane's partition, so a lane that learns a durable rule can only write it down and hand it on, and `¶INV_A_RULE_OWED_HAS_AN_OWNER` names the **conductor** as the party who acts on it. At a hand-over that owner is changing, which is the whole reason the row travels: the successor inherits the ruling, not the lane.*

*A row closes when the conductor **lands** the rule in the named file or **declines** it with the reason. Both close it; neither may be left implicit. A declined rule closes as `declined — <why>` and stays visible, because a rule rejected on purpose and a rule dropped on the floor are the same shape once the session ends. `the rule` is a **file and a clause** — a row naming only a subject is a row a successor cannot land.*

| owner | from thread | the rule (file · clause) | why the lane could not land it | closes when |
|-------|-------------|--------------------------|--------------------------------|-------------|
| [session dir] | [threadId] | `.directives/PITFALLS.md` · [the rule in a clause] | [outside the lane's partition \| held by another lane \| operator hold] | [landed — [sha or path] \| declined — [why] \| `UNKNOWN — <why>`] |

## 🔓 Open claims — what the operator still owes an answer on

*Forks put up and not yet answered, including ones decided in chat where the decision has not reached an artifact. A row closes when the answer is recorded somewhere a successor reads — an ask read, a ticket comment, or a `## 💡 Decision` entry this file points at.*

*Carried from the session log's `## 🔓 Open claims` block **unchanged**, the way an ask row is. The block is **live in the log** and this is its hand-over copy, so a conductor transcribes rather than mines — mining an unanswered fork out of a closing context is how a question the operator never saw gets dropped.*

*`prepared context` is a POINTER to the `§FMT_DECISION_CARD` already written — `/decide` §6's record holds the options as framed and, per `¶INV_REJECTED_OPTIONS_ARE_RECORDED`, what was decided against. A successor handed a fork with no card re-derives the stakes, the options and the lean before it can ask, which is the whole cost this column removes. Where no card exists the cell is `UNKNOWN — no card prepared`, never blank, and a successor needing it stops and reports the row.*

*`meanwhile` is what the waiting thread is doing unanswered, so a successor knows whether an unclosed row is a thread **idling** (it costs the operator their attention now) or a thread **proceeding on a lean** (it costs a rework if the answer goes the other way, and the falsifier says which).*

| owner | the fork | what it unblocks | prepared context | meanwhile | asked at | closes when |
|-------|----------|------------------|------------------|-----------|----------|-------------|
| [session dir] | [one line] | [threadIds / the work waiting] | [absolute path to the `_DECIDE.md` record or ask `<seat>/<id>` \| `UNKNOWN — no card prepared`] | [proceeding on the lean — falsifier: [x] \| working around \| parked \| idle] | [gate N, timestamp] | [the artifact that records the answer] |

## ❓ Lane asks open — questions a lane asked the conductor that have no answer yet

*The rows `engine open-asks "<sessionDir>"` prints, each `OPEN` or `UNPARSED` row copied verbatim with its `logpath=`. A row closes when `## [<lane tag>] ✅ Answered <id>: …` is appended to that log or to `LOOM_LOG.md`. When the command exited 2, the reading is incomplete, so record that in place of the rows.*

| row (verbatim, ends in `logpath=`) |
|------------------------------------|
| [OPEN ## [TAG] ❓ Ask <id>: … · logpath=<absolute path>] |

## 📨 Seat handovers — topics handed to or from another seat, still waiting on an ack

*Carried from the session log's `## 📨 Seat handovers` block **unchanged**, the way an ask row, an open claim and a rule owed are. The block is **live in the log** and this is its hand-over copy. A row kind lives in both places or it is lost at one of the two moments that matter — and this kind is the one most exposed at a hand-over, because **the party who owes the ack is not the party handing over**. A peer seat keeps its own context and answers in its own time, so an un-acked handover routinely outlives the session that sent it, and a successor that cannot see one re-sends a topic the peer already took or abandons one it never did.*

*⚠️ **Not the same thing as the `## 🤝 Hand-over written` receipt**, which is this conductor handing its own state to its own successor. This block is one seat handing a topic to **another seat**. The two were one word and are two registers.*

*A row closes on the receiving seat's own words — `taken`, `declined — <why>`, or `already done — <the evidence>` — and `§INV_HANDOVER_CLOSES_ON_ACK` forbids the sender closing it on sending, so **an open row is the normal thing to inherit** rather than a sign anybody fell behind. What a successor may not do is drop one: `¶INV_LOOM_PASS_ON_NEVER_DISCARD` binds this kind like the rest.*

*`seat` carries the from-name **and** the pane id, and a successor **re-measures the pane before acting on a row** — a session that took the name later, or a seat renamed since the row was written, makes the from-name resolve somewhere else or nowhere, and a handover sent nowhere reads exactly like one sent. Where the pane cannot be resolved the cell is `UNKNOWN — <why>` and the successor stops and reports the row rather than re-sending into the dark.*

| owner | direction | seat (from-name · pane id) | the topic | member links | sent | closes when |
|-------|-----------|----------------------------|-----------|--------------|------|-------------|
| [session dir] | [`sent` \| `received`] | `domain:<Seat>` · `yarik-fleet:domain:<Seat>` \| `UNKNOWN — <why>` | [one line, as the receiving seat reads it] | [ticket keys, comment ids, inbox roots — never `the topic` alone] | [timestamp · the delivery reading] | [the seat's own words — `taken` \| `declined — [why]` \| `already done — [evidence]` \| `UNKNOWN — <why>`] |

## ⚙️ Standing arrangements — things that die on their own and need re-arming

*A background watcher, a subscription, a lane's held file, a credential pinned for a publish. Each row says what dies, what blocks when it does, how to restore it, and **whether restoring it contradicts something** — because a successor cannot infer any of those from an absence.*

*`what blocks on its absence` names **the exact gate or tool class, never "writes"**. A claim is scoped to the tool class it was measured on: a gate's allowlist admits some classes and not others, so two successful writes in one class establish nothing about another. Measured tonight — a dead ticket watcher blocks `Agent` and plain `Bash` while `AskUserQuestion`, `Skill` and `engine ticket/session/log` stay allowed, and the first record of it read "the gate did not block" because it generalised from the class that was still passing.*

*`contradicts · settled by` is the column a successor needs most and the one hardest to reconstruct. **A restore instruction that conflicts with standing advice, with the conflict unrecorded, is an override the successor re-derives from scratch** — which is the re-derivation this file exists to prevent. The known instance: a watcher whose maximum lifetime is shorter than the session's creates a **mandatory periodic re-arm**, while the harness advises against restarting a watcher already at the longest timeout allowed. Neither rule is wrong alone; the conflict is structural. So the row records which rule was judged the authority and on what grounds, turning a judgement call repeated every ceiling into a decision taken once. **It is a column rather than a note inside `restore by`**, because that cell holds a command a successor copies and runs — a conflict buried in it is read after the command has already been acted on, and a cell holding both a command and its authority reasoning is a cell nobody can copy cleanly. `none` is a legitimate value and means nothing stands against the restore.*

*A re-arm that has fired repeatedly is a **standing cost, not an incident** — say how many ceilings it has already crossed, so a successor budgets for it rather than treating the next death as news.*

| owner | what | dies when | what blocks on its absence | restore by | contradicts · settled by |
|-------|------|-----------|----------------------------|------------|--------------------------|
| [session dir] | [e.g. the ticket watcher on ENG-XXXX] | [its ceiling, and the ceiling's length — plus how many times it has already died this session] | [the exact gate or tool class, named — never "writes"; and the classes that stayed allowed, so the scope is visible] | [the command] | [`none` \| the standing advice it goes against · which rule was judged the authority, on what grounds, and by whom] |
