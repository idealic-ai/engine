# Loom Inheritance — the open-work rows that outlive a session

**For the next conductor, which is probably a fresh context. This file is STATE; the session log is NARRATIVE.** Where the two disagree about a row, this file is authoritative — the log says what happened, this says what is still open.

**Where it lives**: one file at the **sessions root** (`<sessionsRoot>/LOOM_INHERITANCE.md`), beside the dated session directories rather than inside one, because a successor knows the root and does not know which predecessor to read. It is **rewritten in place** by the handing-over conductor; the superseded copy is appended to that session's own log, so the history stays with the narrative and the live rows stay addressable.

**Several looms may share this file.** Every row carries its `owner` — the session directory that wrote it — so a fresh conductor reads the whole file and claims only the rows whose subject it is taking, and says in its startup entry which rows it claimed and which it left.

**A field a successor needs and the writer could not fill is written `UNKNOWN — <why>`, never left blank.** A successor that finds `UNKNOWN` in a field it needs to act **stops and reports that row** rather than acting on the rest of it — a partial row acted on silently reproduces the loss this file exists to prevent, with no visible gap where it used to be. A blank cell is a defect in the row, not a permission.

**An open row may be passed on. It may never be dropped.** A conductor closing a session carries every open row into this file; one that would discard a row instead has not written a legitimate hand-over.

---

## 🧵 Threads — work in flight or parked

*A row closes when its thread reaches a terminal stage with its proof URL recorded, or when the operator parks it with a reason. `reach it by` is the lane's **LOG PATH**, never an agent id: a context clear ends every in-process subagent, so an id is executable only while the parent context lives, and the log is what a fresh lane reads to take over.*

| owner | threadId | subject | stage | reach it by (LOG PATH) | file holds | closes when |
|-------|----------|---------|-------|------------------------|------------|-------------|
| [session dir] | [ENG-XXXX / SLUG] | [one line] | [triaged \| interrogated \| building \| scrutinized \| snapshotted \| pr'd \| council'd \| parked] | `[absolute path to the lane's _BUILD_LOG.md]` | [paths this thread holds, or `none`] | [the terminal stage + its proof URL \| `parked — <reason>`] |

## 🗳️ Boards — published decision boards awaiting a fold

*Carried from the session log's `## 🗳️ Boards` block **unchanged**, including the `docId` — `/decide` §4 says the handle is unrecoverable once the publishing pass ends, so a row arriving here without it has lost that board's answers permanently and says `UNKNOWN — docId not captured at publish`. A row closes when a successor folds it and reads the state doc; it may be passed on open, and it may not be discarded.*

| owner | board | url | docId | forks held | closes when |
|-------|-------|-----|-------|------------|-------------|
| [session dir] | [slug] | [board URL] | [docId \| `no shared state` \| `UNKNOWN — <why>`] | [forkIds / threadIds] | [folded + read, with what the answers changed] |

## 📚 Docs owed — claims a landed change falsified

*The doc register. One row per documentation claim a landed thread made false, and per piece of doc work a per-thread lane is forbidden to do. `claim` is a located sentence — path, line, what it asserts — because a row naming only a file is a row a successor cannot act on. A row closes when `/revise` repairs the claim and its Revise Report records the repair, or when the row is routed to `/document` and that session picks it up.*

| owner | from thread | claim (path:line · what it asserts) | why it is owed | destination | closes when |
|-------|-------------|-------------------------------------|----------------|-------------|-------------|
| [session dir] | [threadId] | `path/to/doc.md:LINE` · [what a reader would check] | [falsified by the change \| unverifiable here \| outside a diff's scope] | [`/revise` \| `/document` \| escalate — no home] | [Revise Report path + the repair \| the session that took it] |

## 🔓 Open claims — what the operator still owes an answer on

*Forks put up and not yet answered, including ones decided in chat where the decision has not reached an artifact. A row closes when the answer is recorded somewhere a successor reads — a board fold, a ticket comment, or a `## 💡 Decision` entry this file points at.*

| owner | the fork | what it unblocks | asked at | closes when |
|-------|----------|------------------|----------|-------------|
| [session dir] | [one line] | [threadIds / the work waiting] | [gate N, timestamp] | [the artifact that records the answer] |

## ⚙️ Standing arrangements — things that die on their own and need re-arming

*A background watcher, a subscription, a lane's held file, a credential pinned for a publish. Each row says what dies, what blocks when it does, and how to restore it — because a successor cannot infer any of the three from an absence.*

| owner | what | dies when | what blocks on its absence | restore by |
|-------|------|-----------|----------------------------|------------|
| [session dir] | [e.g. the ticket watcher on ENG-XXXX] | [its ceiling, and the ceiling's length] | [the exact gate or tool class, named — never "writes"] | [the command] |
