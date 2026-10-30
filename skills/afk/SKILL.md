---
name: afk
description: "Set the stance for a stretch of work with nobody watching — keep going, park every question only the operator can answer in ONE ordered register, coordinate through the relay that already exists, and hand over before the context runs out. It RIDES the session that is already running: it sets the stance, names the register's absolute address, says what would otherwise have woken the operator and what happens to each one instead, then hands straight back to whatever was already in flight. It mints no lanes, keeps no ledger, decides no forks of its own, and reads no state its host is not already reading. Triggers: \"going afk\", \"I'm going to sleep, keep working\", \"work autonomously and write the questions down for me\", \"keep going without me\", \"do your best judgement and leave me the questions\", \"afk\"."
version: 1.0
tier: lightweight
args: "[what to keep working on]"
---

Set the stance for working while nobody is there, then hand straight back to whatever is already running.

# /afk Protocol (The Stance)

[!!!] A **sessionless utility** skill — no session directory of its own, no phases, no log, no debrief. The same shape as `/next`, `/session` and `/engine`, and for the same reason: it reads sources that already exist and adds no durable store.

**Its first user is a person who is not there, so its quality is measured by what they can act on when they get back.** Everything else here follows from that.

## What a run is

Four acts, and then it is over.

1.  **Set the stance.** The host's **Autonomy** disposition becomes **Automagic**, which `/loom` already defines at its Setup dispositions: proceed autonomously, auto-resolve what is safe to auto-resolve, escalate only on the hard floor. Where the host is a loom mid-weave this changes a disposition it already holds and is echoed into its ledger header; where the host is something else, it is the standing instruction for the rest of the run. Whatever arrived in `args` becomes the **standing priority** — what to pick up when a thread lands and the host asks itself what next. ⚠️ **Automagic does not lower a mandatory step into an optional one** (`¶INV_LOOM_MANDATORY_STEPS` rules that at its definition site), and this stance does not either: the interrogation, the ticket-disposition ask and the scrutinize pass still run.
2.  **Name the register, by its absolute path, computed.** See *The register* below. Print the path in the hand-back, so the operator has the address before they close the laptop rather than having to ask for it later.
3.  **Say what would otherwise have woken them, and what happens to each one instead.** That is the hard floor, item by item, and *The hard floor with nobody to wake* below is the answer. Say it out loud now, because a stance whose escalation behaviour the operator has not seen is a stance they did not agree to.
4.  **Hand back.** Name the next move the host was already going to make, and stop. `/afk` does not take that move itself.

## It rides; it does not conduct

**`/afk` sets a stance and hands back. It is not a second conductor.** It mints no lanes, keeps no ledger, holds no partition, maintains no waiting-on graph, and decides no fork of its own. Everything it needs is already running in the host; what it changes is the host's disposition toward it.

**`§INV_RIDE_NEVER_ACTIVATES` is binding here** — declared in `/loom`'s Constraints and in `/direct`'s `## Composed entry` section. It runs no `engine session activate`, runs no `engine session phase`, and writes nothing to `.state.json`. The reason is mechanical rather than stylistic: there is one state file per session directory carrying a single `currentPhase`, so a composed pass that advances it **overwrites its host's own position in the only file the host has**. Where the host needs its phase moved, the host moves it.

⛔ **The falsifier, and it retires this skill rather than amending it.** The engine holds a standing decision to extend `/loom` and not to fork it — *one conductor; the integration is a capability, not a second skill to keep in step*. That decision has been overruled exactly once, for `/groom`, narrowly, on the measured ground that `/groom` mints no lanes. `/afk` survives the same falsifier on the same ground only while it mints none either. **So: if `/afk` starts dispatching workers, keeping a register of its own, or needing partition logic to work, the standing decision wins and `/afk` folds back into `/loom` as a disposition.** That is not a risk to watch; it is the condition of its existence.

## What it inherits — named at its definition site, never restated here

Almost everything the stance needs is already built and already enforced. **A citation cannot drift the way a copy can**, and *a second thing to keep in step* is the whole objection this skill has to survive — so each of these is followed at its own definition site, and where a reading is in question that site is the authority and this file is not. Each is cited by **rule name**, never by line number, because these files are edited hourly and a line cite rots within the day.

*   **Working autonomously** — the **Automagic** value of `/loom`'s Setup *Autonomy* disposition.
*   **The parking lot** — `¶INV_LOOM_A_FORK_ARRIVES_DECIDABLE`, and the live `## 🔓 Open claims` block whose row shape is specified in `skills/loom/assets/TEMPLATE_LOOM_LOG.md`.
*   **Proceeding without the operator** — `/decide` §5's vocabulary: decide provisionally with the falsifier recorded · hand it to the lane inside a stated bound · defer with a trigger. Its own rule is that `idle` is legitimate and is the **only** value that spends the operator's attention, so an idling row carries why idling was right.
*   **Never closing** — `¶INV_LOOM_NO_RUSH_TO_CLOSE`. The gate defaults to keep-going; a session ends only on the operator's explicit choice, and that holds while they are asleep exactly as it holds while they are watching.
*   **Coordinating with others** — the conductor's live relay: `SendMessage`, out-of-partition file claims, `¶INV_LOOM_FIRST_CLAIM_WINS`, the waiting-on graph rowed rather than remembered (`¶INV_LOOM_WAITING_IS_ROWED`), and the stall sweep `engine lane-stall` (`¶INV_LOOM_STALL_IS_SWEPT_NOT_SENSED`).
*   **The hard floor** — `¶INV_LOOM_HARD_ESCALATION_FLOOR`: the per-thread ticket-disposition ask · a cyclic deadlock · a build failing after retries · a scrutinize MUST-FIX · a thread loopback. These reach the operator even under Automagic.
*   **An open row may be passed on and never dropped** — `¶INV_LOOM_PASS_ON_NEVER_DISCARD`.
*   **What a hand-over owes a successor** — `¶INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID` and `§CMD_DEHYDRATE`.
*   **Why a wake costs what it costs** — `¶INV_LOOM_WAKES_ARE_THE_BILL`, which is why nothing in this stance polls for the operator's return.

## The register — one address, and it is not a new file

**The register is the live `## 🔓 Open claims` block, and `/afk` adds no file.** `¶INV_LOOM_PASS_ON_NEVER_DISCARD` already makes that row authoritative, and `TEMPLATE_LOOM_LOG.md` records the inverse bug in its own preamble: the block once lived in the inheritance template alone, so the one moment a lane sat waiting was the one moment nothing was written down. **A fourth place a question can hide is a regression**, so a new file would have to beat a register that already exists, and it does not.

**Address it by computing it, never by typing a convention.** The live register is the **latest** `## 🔓 Open claims` block of the active session's loom log — latest because the log is append-only and the heading recurs every time the conductor rewrote it, so a reader who takes any other occurrence reads a weave's history as its present state. Resolve the session directory from `engine session find` and the sessions root as its **parent**; a same-named session directory at a different root holds different content under a symlinked `sessions/`, a shared-drive artifact root, or a `$WORKSPACE` set for one process and not another.

⚠️ **Two ways of reaching that block are measured wrong, and both read as success.** On the log this skill was built against — 8,156 lines, one register — the bare substring `🔓 Open claims` matched **20** times while only **7** were headings, the other 13 being prose about the register; its first match sits 2,442 lines above the live block, so a reader who greps and takes the first hit answers a two-day-old question. And the naive heading anchor `^## 🔓` matched **4 of those 7**, because `engine log` stamps a `[timestamp]` into the **first** `## ` heading of an append and no others — so whether a given block is reachable by that anchor depends on how the conductor happened to batch its writes, which is not a property anyone reasoning about the pattern would predict. **Instead:** match the glyph anywhere in the heading (`^## .*🔓 Open claims`) and take the **last** match. Both figures carry a control that fired: a fabricated `🦆 Duck claims` heading returned 0 by the same pattern, and the real sibling `🧵 Ledger` returned 26.

**After a hand-over the rows move, and the authority moves with them.** They cross into `LOOM_INHERITANCE.md` at the sessions root, and from that moment that file is authoritative for them and the log is history — `TEMPLATE_LOOM_LOG.md`'s own `Authority` line rules this, one file and one authority at a time, so no row has two owners. **So the hand-back prints both absolute paths and says which is live**, because which one the operator should open depends on whether the host survived the night, and that is not something they can be expected to work out at the time.

⛔ **The hand-over CARRIES the rows, in their order. A pointer to the log block is not a hand-over.** The reason is the Authority line itself: the moment the inheritance is written the log is history, and a successor following a pointer into an append-only history cannot tell a live row from a closed one. **Measured on the hand-over written two minutes after this skill's own worked register**: the inheritance's own block held 3 of the register's 6 rows and the three it omitted were the top three by the ordering rule, including the one blocking ten owed rules — reachable only through a prose sentence naming the log block. **Instead:** copy every row across in order, with its pointer, and let `¶INV_LOOM_PASS_ON_NEVER_DISCARD` do what it is for.

### The ordering rule — the one thing this skill adds to the row

**The first row is the one to answer first.** Order the block, at every re-put:

1.  **Hard-floor rows first**, above everything, regardless of what they unblock — because a hard-floor row is the only kind where a thread is **stopped** rather than proceeding, so every minute of the operator's absence is a minute that thread is not moving.
2.  **Then by what the row unblocks** — `/decide` §2's existing ranking axis, inherited rather than invented: how many threads wait on it · what guessing wrong costs · whether the door swings back.
3.  **Then the rest**, in the order they were raised.

### What a row must carry, in the fields it already has

No new field. What the stance tightens is how two existing ones are filled, because a register the operator has to re-derive from has failed:

*   **`prepared context` is a pointer to the decision card and never a copy of its fields.** `/decide` §6 already writes the fork, the options as framed, the lean with its trade-off, the falsifier and — per `¶INV_REJECTED_OPTIONS_ARE_RECORDED` — what was decided against, to `builds/<slug>_DECIDE.md`. Point at that. Inlining the fields drifts from `§FMT_DECISION_CARD` and breaks `§INV_LISTS_INSTEAD_OF_TABLES`; a row whose `prepared context` reads `none` is a question asked without what it takes to answer it.
*   **`meanwhile` is written when the fork is RAISED, and it is written specifically enough that a *yes* confirms rather than re-litigates.** `proceeding on A` is not enough; `proceeding on A — three files written, falsifier: X` is, because the operator can see what their agreement ratifies. This is the clause that makes the register answerable in one pass instead of two.
*   **A hard-floor stop is written in `meanwhile`'s existing vocabulary** as `parked — hard floor: <which item> · log: <the lane's absolute LOG PATH>`. The log path is there because an absence outlives processes: an agent id survives a `/clear` in the same process (*measured 2026-10-30*) but not a process exit or restart, where it answers *no transcript found* (*relayed, 2026-10-29*), and only the lane's own log survives both — a lane at `logpath=none` has none, and its stop says so.

⛔ **A fork raised under this stance with no card is not parked — it is dropped, quietly.** The pointer rule above only works if something is on the other end of it, and nobody is awake to notice that nothing is. So a fork is raised **through `/decide`**, whose §6 writes the card and whose `--items` return leg closes the loop back to the caller, and the row then points at that record. **Instead of** writing a title and a `meanwhile` and leaving the reasoning in a lane's context that ends with the lane: the row survives, the argument for it does not, and the operator wakes to a question with no case attached. **An artifact pointer must resolve as written.** On the worked register, three rows named a resolvable path, two named something the reader had to derive — a threadId instead of its build log, a section instead of a file — and one named no artifact at all. *A threadId is not an address*, so write the path.

## The hard floor with nobody to wake

**A hard-floor item fires, the escalation has no destination, and `/afk` must say what happens. It is this: the affected thread STOPS, its question is parked at the top of the register marked hard-floor, and every other thread keeps running.**

**Why stopping is cheap and deciding is not.** All five hard-floor items sit at a point where the thread's *next* step is a write or a dispatch — the ticket-disposition ask comes before a build, a deadlock means the lanes in it have already stopped, a build has failed after its retries, a MUST-FIX is pending before snapshot and PR, a loopback is pending before the loop. So a stop costs latency and nothing else, while a decision costs **an agent resolving a one-way door at 3am with nobody witnessing it**. A stalled thread with a legible reason is recoverable in a minute; a wrong irreversible decision is not.

⛔ **Two answers that are forbidden, each with what to do instead.**

*   **Do not decide it anyway.** An unwitnessed one-way door is the harm the hard floor exists to prevent, and nothing about the operator being asleep makes it smaller — it makes it larger, because the correction arrives hours later against more work built on top. **Instead:** park it at the top of the register with its card, and let the thread stop.
*   **Do not stall silently.** A weave that stops with nothing written is a weave the operator wakes to as dead, with no way to tell a hard floor from a crash. **Instead:** the row *is* the record — the stop, which floor item caused it, the lane's log path, and what the thread was doing when it stopped.

**One blocked thread must not stop the weave.** Every other thread keeps running under the stance, and `¶INV_LOOM_PASS_ON_NEVER_DISCARD` is what makes that safe: the stopped thread's row is passed on rather than lost.

⚠️ **What would make this wrong, and it is measurable.** If a run stops more than half its threads on the floor, the operator wakes to a mostly-dead weave and the stance has failed at the exact thing it was chosen for. **The fix is then a narrower batch — threads whose hard-floor items were pre-answered before the operator left — and never a looser floor**, because the floor is the only thing standing between an absent operator and an unwitnessed irreversible call.

## Before you go, answer the ticket dispositions

**The per-thread ticket-disposition ask is on the hard floor and Automagic never suppresses it**, so every thread added during the absence stops there. That is correct and it is also the stance's main avoidable cost: an operator who answers the dispositions for the batch *before* leaving converts a night of stopped threads into a night of running ones. `/afk` says this at the hand-back as the one preparatory move worth making, and never answers a disposition on the operator's behalf.

## What ends a run

**Context exhaustion, not a decision — so the hand-over is mandatory and early rather than offered.**

`¶INV_LOOM_NO_RUSH_TO_CLOSE` puts wrap-up on the gate card as a *recommendation* near its stated context figure, and says plainly that the figure governs when that card appears and nothing else. **Under this stance that is not enough, because nobody is at the gate to accept the card.** So the stance makes one change and keeps the number: **at the same figure that invariant already states, the hand-over is written rather than offered.** One number for both readings, so neither drifts.

This adds no power the host did not have. That same invariant already licenses the unprompted write — *with an involuntary exit imminent, write its state and its hand-over first* — because riding into a dehydration loses the ledger, and that is not an end anyone chose. The stance promotes that permission to an obligation, which is what a stance-setter is for. **Riding into an involuntary exit loses the register, which is the one thing `/afk` exists to produce.**

**The session still ends only on the operator's explicit choice** (`¶INV_LOOM_NO_RUSH_TO_CLOSE`). So an `/afk` run has no end of its own: the host's context ends, a successor picks up the inheritance, and the stance ends when the operator comes back and says so. That is the honest reading of *keep going*.

### The forbidden hand-over forms, carried because they are measured and non-obvious

`§CMD_DEHYDRATE` owns the payload and `¶INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID` owns the forms; these three are repeated here only because a stance whose whole product is a register cannot afford to get its hand-over wrong.

*   ⛔ **An agent id is never the only handle.** It still works after a `/clear` in the same process (*measured 2026-10-30*), but not after a process exit or restart (`/dehydrate` on the watchdog path (no tmux, or `DISABLE_CLEAR=1`: `session.sh dehydrate` sends `kill -USR1` to the watchdog, which kills the Claude process, or with no watchdog prints a manual restart), a pane relaunch, a crash; under tmux without `DISABLE_CLEAR=1` `/dehydrate` is a `/clear` and the id keeps working), where `SendMessage` to the id answers *no transcript found* (*relayed, 2026-10-29*) — not slow, not idle, gone from this conversation until its transcript is copied in (`¶PTF_A_SUBAGENT_FROM_A_PREVIOUS_CONVERSATION_IS_RESUMABLE_BY_COPYING_ITS_TRANSCRIPT`). **Instead:** hand over the lane's **LOG PATH**, and the successor dispatches a fresh lane with that log in its context pack.
*   ⛔ **Do not read that path with `awk '{print $NF}'`.** `engine lane-stall` closes each row with `logpath=`, and a shared-drive session path contains spaces, so the last whitespace field is a truncated path that still reads like a real one. **Instead:** `sed 's/.*logpath=//'`, taking everything after `logpath=` to end of line.
*   ⛔ **Do not fill in a `logpath=none` row from the `agent=` transcript beside it.** A lane with no log is a **different hand-over**, not a lane to point at its transcript. **Instead:** carry it as that reading and say what the lane was doing.

## Constraints

*   **`¶INV_AFK_RIDES_NEVER_CONDUCTS`**: it sets the stance and hands back. Dispatching a worker, minting a lane, keeping a ledger or a register of its own, holding a partition, or deciding a fork is forbidden — each is the conducting job the host already has, and a second copy of it is a second thing to keep in step. **This is the skill's falsifier**: if the stance needs any of them to work, it folds back into `/loom` as a disposition.
*   **`¶INV_AFK_PARKS_NEVER_DECIDES_THE_FLOOR`**: a hard-floor item under this stance stops its thread and is parked at the top of the register. Deciding it autonomously is forbidden because the decision would be unwitnessed and may be one-way; stopping without writing the row is forbidden because the operator then cannot tell a floor stop from a crash.
*   **`¶INV_AFK_INVENTS_NO_REGISTER`**: the register is the existing `## 🔓 Open claims` block, ordered and tightened — a new file, a new field or a second copy of a row is forbidden, because a fourth place a question can hide is a regression on the one guarantee this skill sells.
*   **`¶INV_AFK_HANDS_OVER_EARLY`**: at the context figure `¶INV_LOOM_NO_RUSH_TO_CLOSE` already states, the hand-over is written and not offered. Riding past it is forbidden — an involuntary exit loses the register.
*   **`§INV_RIDE_NEVER_ACTIVATES`**: riding a live session, it activates nothing, moves no phase, and writes nothing to `.state.json`.
*   **Cite, do not restate.** Every guarantee here is followed at its definition site and named by rule name, never by line number. A paraphrase drifts on contact and the drift is invisible, because the text claims to be citing.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file.

## Notes

*   **A conducting `/afk` was declined, by the operator, with the alternative in front of them.** The fuller design — `/afk` as an autonomous driver that starts its own work from a cold start — was put up and *rides, no ticket* was chosen over it. **The cost they accepted, stated so nobody re-opens it as a gap: `/afk` does nothing on its own when nothing is running.** With no live session it sets a stance over an empty room; the thing to invoke then is `/next`, which reads what state the work is in from cold and is specified for exactly that entry.
*   **The ordering rule and the hard-floor stop are the only unexercised parts.** Everything else here is a disposition and a set of invariants that run today under operator supervision; what has never been observed is a register read cold by someone who was asleep while it was written. Treat a disagreement between this file and a live reading as evidence about this file.
*   **`assets/EXAMPLE_REGISTER.md`** holds a worked register — real rows from the session this skill was built in, ordered by the rule above. It is an **example**, not a live register; the live one is always the address computed above.
