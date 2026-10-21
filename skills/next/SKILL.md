---
name: next
description: "Read what state the work is actually in and propose ONE move that advances it — from a cold start, with no live loom and no idle session. Reads the session's `.state.json`, `engine project next`, the loom log's ledger blocks, git, `LOOM_INHERITANCE.md` and `engine lane-stall`, then routes BLOCKING-FIRST: a lane that stopped without handing back → resume it from its log path · an unanswered fork or an unread decision board → the decision pass, or fold and read it · uncommitted work or a wave nobody brought back together → the checkpoint · groomable work → the batched pass, then the weave. One move per invocation, the other applicable states shown and visibly unacted. It groups nothing and ranks nothing of its own — `/groom` owns the topics and `engine project next` owns the order. It proposes; one keystroke accepts; it dispatches, commits, files and transitions nothing on its own reading. Triggers: \"what do I do now\", \"where did we leave off\", \"what is blocking me\", \"advance the work\", \"pick up where I left off\", \"what needs me\", \"what state is this in\", \"next move\", \"next\"."
version: 1.0
tier: lightweight
args: "[project] [--minutes N] [--session <dir>] [free-text hint]"
---

Read the state the work is in, and propose the one move that advances it.

# /next Protocol (The Cold Entry)

[!!!] This is a **sessionless utility** skill. No session directory of its own, no logging, no debrief — the same pattern as `/inbox-next` and `/inbox-post`. It reads sources that already exist and adds no durable store (`§INV_NEXT_INVENTS_NO_STORE`).

## What this is, what it is not, and who it is for

**For whoever just sat down.** A person returning after a gap has no live loom and no idle session, so neither state-reading router in the engine will answer them: `§CMD_PRESENT_NEXT_STEPS` states its own prerequisite as `lifecycle=idle` — it runs only after a session closes — and `/loom`'s loop gate presents *"after each unit of progress"* and opens with *"The loom is running. What next?"*. **The one thing this skill adds is an entry that works when neither of those holds.**

*   **It is** the **join plus a precedence rule**. Every state it reads is read somewhere already; nothing in the engine reads them *together* and orders them, and the ordering is the only part that is judgement rather than sequence.
*   **It is NOT a router of its own invention.** Three of its routes are conditions `/loom`'s loop gate already declares, under a pool mechanism that is itself a declared rule (`§INV_LOOM_GATE_SURFACES_BY_RELEVANCE`): the stalled-lane sweep (`§INV_LOOM_STALL_IS_SWEPT_NOT_SENSED`), the fork pass and the board fold (`§INV_LOOM_SURFACES_FORKS_UNASKED`, `§INV_LOOM_A_FORK_ARRIVES_DECIDABLE`), and the *"Pull more work"* offer that already reaches for `/groom` and `/inbox-next`. **Each is cited by its rule name or by the offer's own label, never by line number** — that file is edited often enough that a line cite rots within the day, measured. **Those conditions are borrowed BY CITATION and restated nowhere in this file** — a citation cannot drift the way a copy does, and "a second thing to keep in step" is the whole objection this skill has to survive. So each rule above is named and followed at its own definition site; where a reading is in question, that site is the authority and this file is not.
*   **Only one reading here is this skill's own**: the state of the working tree, specified properly below because nothing else specifies it. Measured in `skills/loom/SKILL.md` against a `snapshot` control that fires: `uncommitted` → 0 and `working tree` → 0. **The wave half of that route is no longer this skill's**, and the honest reading changed under it — `§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY` has since landed in that file and now owns bringing a wave's trees back together, so this skill cites it rather than claiming the gap. What remains unspecified anywhere else is the **dirty-or-ahead tree reading**, and that is the only part asserted as new here.
*   **It is NOT a conductor.** It mints no lanes, keeps no ledger, and holds no partition. The moment it dispatches its own workers it has become a second conductor, which is the shape the standing *extend-`/loom`-do-not-fork-it* decision is aimed at and the falsifier that would retire this skill into `/loom`.
*   **It is NOT a clusterer or a ranker** (`§INV_NEXT_BORROWS_THE_GROUPING`). `/groom` owns grouping work into topics; `engine project next` owns the order of open work. Two rankings of the same work drift apart and a reader cannot tell which one they are looking at — `skills/groom/SKILL.md:20` records that exact failure for the pair that already exists, and a third ranking is the same bug.
*   **It writes nothing.** No code, no tracker row, no git object, no status, no assignee. Every mutation happens inside a composed skill under that skill's own confirm.

## `/next` vs `/groom` vs `/inbox-next` — the one place all three are stated together

Three skills answer three different questions, and the words people type do not separate them, so the precedence is written down rather than left to whichever file the reader opened:

*   **`/inbox-next`** answers *which ticket do I pick* — it ranks a project's open work and routes one item into `/implement`, `/fix`, `/brainstorm` or `/ticket`. It owns the phrases *"what's next"*, *"what should I work on"* and *"pick my next ticket"*.
*   **`/groom`** answers *what is the batched shape of everything open here* — it drains the inbox, the open tickets and the un-ticketed leftovers, clusters them into topics across all of those, disposes each topic once, and hands each to a loom as one thread. It **composes** `/inbox-next` for the ranking rather than re-deriving it.
*   **`/next`** answers *what is in the way* — it reads the states that block a return and proposes the one move that clears the nearest of them, which is frequently not a ticket at all. It **composes both of the above**, and ranks and clusters nothing itself.

**Where the words overlap, the wider question wins and hands down.** An ask that names a ticket, a project or a pick is `/inbox-next`'s and goes straight there. An ask about the state of the work — *where were we*, *what is blocking*, *what do I do now* — is this skill's, and when its reading finds nothing blocking it hands down to `/inbox-next` for the ranked pick rather than answering the ranking question itself. Handing down is the normal ending, not a fallback.

## Requirements, and what a missing one costs

Nothing here is a hard requirement. Each source that cannot be read is **reported as unread rather than read as empty**, because the two are indistinguishable at the call site and treating one as the other is how a blocking state goes unnamed:

*   **A session directory**, for the state file, the ledger blocks and the stall sweep. Resolved as: `--session <dir>` · else the engine's active session · else the most recently modified session directory under the sessions root. **No session resolvable** → say so and run the cold floor (step 5): the project ranking alone still names a move.
*   **`engine project next`** + `LINEAR_API_KEY`, for the ranked open work. Absent → report it and propose from the states that did read.
*   **`engine lane-stall <sessionDir> [--minutes N]`** for the stall reading. **No second detector is written** — if it is not on the path, say the stall state is unread and do not substitute an improvised one.
*   **A git repository.** The work being read may live in a different repository from the engine; resolve which one the session was working in before reading its tree, and say which you read.

## Algorithm

### 1. Establish where you are, in one line, before reading anything else

Read the resolved session's `.state.json` and say which case you are in — the cases differ in what you may touch:

*   **No session, or no state file** → **cold**. Steps 2 and 3 run on whatever sources exist; the session-shaped readings report as unread.
*   **`lifecycle=idle`** → a session that closed. `§CMD_PRESENT_NEXT_STEPS` owns this case and is the better answer when the question is *which skill next for this session's work*; say it exists, and continue only because the question asked here is wider.
*   **`lifecycle=active`** → a live session. **Ride it and activate nothing** (`§INV_RIDE_NEVER_ACTIVATES`): run no `engine session activate` and no `engine session phase`, and write nothing to `.state.json`. There is one state file per session carrying a single `currentPhase`, so a composed pass that advances it overwrites its host's own position in the only file the host has. Where `taskType` is `LOOM` and the phase is the loom body, **the loop gate is the operator's better surface** — it is already awake and already runs these conditions as cadences. Say so, and prefer it.

**The state file does not carry its own path.** Its `sessionDir` field reads `null` on a live session, so compute the directory from the file's own location rather than from the field — a measured trap, and a skill that trusts the field resolves `null` and reads nothing.

### 2. Read the states — each reading, and what its absence means

Read all of them before proposing anything; precedence needs the whole set, and a skill that stops at the first hit cannot show the operator what it is not acting on.

*   **Lanes.** `engine lane-stall "<sessionDir>" [--minutes N]` — read-only, exit **3** when any lane is stale, which is a finding rather than a failure. **`§INV_LOOM_STALL_IS_SWEPT_NOT_SENSED` rules what each reading means and which two readings are forbidden; follow it there and write no second detector.** Read that exit code from a bare invocation: a pipeline's status is its LAST command's, so a sweep read through `head` or `tail` reports the pager's success.
    *   **Then map the tag to a LOG path, because the sweep does not print one.** Measured: a `STALE` row ends in the lane's agent-transcript `.jsonl`, and forwarding that is precisely what `§INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID` forbids. Resolve the lane's own log from its bracketed tag under the session's `builds/` directory, and if no log is found say so — a lane with no log is a different hand-over from a lane with one.
*   **The ledger blocks**, from the session's loom log: the thread ledger, the open claims, the boards, the docs owed, the parked rows, the relay and conflict entries. **The log is append-only, so a block's heading recurs every time the conductor rewrote it** — read the LATEST occurrence of each and never a count of all of them. A count over the whole file reports a weave's history as its present state; measured on one weave's log, the parked heading appears repeatedly while the number of lanes actually parked right now is whatever the newest block says.
*   **Forks and boards.** An open claims row with no record path is an unanswered fork; a boards row whose fold state is unread or absent is an unread board. **What closes either row, and what a fold that comes back empty means, are `§INV_LOOM_A_FORK_ARRIVES_DECIDABLE` and `/decide` §4's; read them rather than a summary here.**
*   **The tree — this skill's own reading, and the one it specifies.** Establish, in this order, and say which repository you read, since the work may live in a different one from the engine:
    *   **Which repository.** Resolve it from the session's own record of what it was working in. Walk up from a path the session names; never assume the engine's root, and never read a repository you cannot name.
    *   **Dirty or clean.** `git status --porcelain`, and read it as the dirty reading. **The silence to guard against is NOT here** — measured, a plain `--porcelain` on an untracked path prints `?? <path>` at exit 0, so this command does see new files. It goes silent at exit 0 in two narrower cases: run with `-uno`, and on a path `.gitignore` matches. Use neither when asking whether work is uncommitted.
    *   **The silence that actually bites is history-based.** Measured on an untracked file: `git log -- <path>` and `git diff HEAD -- <path>` each print nothing at exit 0, while the same two commands on a tracked file in the same repository return output. So any verification that leans on log or diff reads an untracked file as unchanged whatever it contains, and the engine's own most-edited skill files are untracked. **Establish tracked-ness with `git ls-files --error-unmatch <path>` before reading any history silence as clean**, and for an untracked path treat *landed* and *committed* as different claims: the first is read from the path, only the second from git.
    *   **Ahead of its base.** `git rev-list --count <base>..HEAD` against the base the project publishes. Commits that exist only locally are work at risk in the same way uncommitted edits are, and a tree that is clean but ahead is a different proposal from one that is dirty.
    *   **A wave nobody brought back together.** Several lanes' worth of landed work sitting on one branch with no assembled result. **This state is REPORTED, never acted on** — the step that assembles it is not built, and inventing interim behaviour for it is out of scope (see rung 3).
*   **Inheritance.** `LOOM_INHERITANCE.md` at the sessions root, at an address **computed** from the session directory rather than typed. A field reading `UNKNOWN — <why>` stops the run and is reported (`§INV_LOOM_PASS_ON_NEVER_DISCARD` owns why a partial row may not be acted on). Measured on one sessions root: the file was simply absent, which is a legitimate reading and is reported as *no inheritance written*, distinct from *not read*.
*   **Groomable work.** `engine project next` for the ranked open work; the inbox and the un-ticketed leftovers are `/groom`'s to drain, and this skill asks only *whether there is anything there*, never *what shape it is in*.

### 3. Apply precedence — blocking-first (`§INV_NEXT_BLOCKING_FIRST`)

**What stops progress outranks what adds progress**, because something is already waiting on the former. Walk the ladder and take the first rung that holds:

1.  **A lane stopped without handing back.** Something was mid-flight and nobody is holding it. → **Offer the resume, from the lane's LOG PATH and never from an agent id** (`§INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID` gives the reason and the payload; the successor is a fresh lane carrying that log in its context pack).
2.  **An unanswered fork, or a board published and never read.** A thread is waiting on a person, or answers a teammate left are sitting unread. → **The decision pass** (`Skill(decide, …)`), or the fold-and-read of the board's own row. ⚠️ **No board atom exists among the atoms `/decide` declares**, so this route invokes the whole skill and inherits its cadence and its wrap-up obligation. Say that cost out loud when proposing the route; it is the one route that acquires an obligation rather than discharging one.
3.  **Uncommitted work, or a wave nobody brought back together.** Finished work sitting only on disk is the state this programme has actually lost work to. → **The checkpoint** (`Skill(snapshot, …)`), which verifies before it commits and is the only route here that writes.
    *   **The wave half belongs to the loom, not here.** `§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY` owns bringing a wave's trees back together; follow it there and invent no interim behaviour. Where a wave is unassembled and no conductor is awake to run that boundary, **report it and name the owner** — do not improvise a merge from an entry point that holds no partition and no ledger. [IDE-132](https://linear.app/idealic/issue/IDE-132) carries the surrounding open questions.
    *   **The uncommitted half is this skill's**, and it is the proposal that fires: the checkpoint over the paths this session actually touched.
4.  **Groomable work.** Nothing is in the way. → **The batched pass** (`Skill(groom, …)`), and its own dispatch offer carries it into the weave. Where the pile is already curated and the ask was for one item, hand down to `/inbox-next` instead.

**This rung order is the whole of the judgement in this skill.** A dead lane and an unanswered fork outrank a commit, and a commit outranks starting something new; starting new work while three things wait is the failure the ladder exists to prevent.

### 4. The brake (`§INV_NEXT_BRAKE_IS_NUMBERED`)

**Past the threshold, propose closing rather than starting — and name what to close, with the count that put you there.** A refusal reading *"too much in flight"* is discretion wearing a rule's clothes, so the number is stated and the rows are named:

*   **The quantity** is the count of **open obligation rows**: open claims with no record path, boards not folded and read, docs owed still open, and parked lanes. It is **not** the context budget, which `§INV_LOOM_NO_RUSH_TO_CLOSE` already governs with its own number — two different quantities, and conflating them is how an unnumbered rule misfired before.
*   **The threshold is 5 open rows**, and its derivation is stated because it is an imperfect anchor rather than a measurement of itself: five is the number of lanes whose finished work nobody committed on this programme — the one observed instance of the pile costing real work, recorded at `builds/next-integrate_INTERROGATE.md:62`. **The quantities differ** (lanes there, obligation rows here), so this is a starting dial and the first weave that runs healthily past it should re-measure rather than defend it.
*   **It is a brake, not a gate.** It changes what is proposed; it refuses nothing the operator chooses anyway.

### 5. Propose ONE move, and show what you are not acting on

One `AskUserQuestion` via `§CMD_DECISION_TREE`, which owns the declare-N-surface-four mechanism (`§INV_ASK_SURFACE_FOUR`, `§INV_ASK_SLASH_FOR_MORE`). Use it; never a fixed menu.

*   **The recommended option is the first rung that held**, phrased as the move rather than as the state: *"Resume SCRUTFIX from its log"*, not *"a lane is parked"*.
*   **The body carries every other applicable state, visibly unacted** — named, with what would clear it, and no action attached. This is what makes one-move-per-invocation honest rather than lossy: the operator sees the whole reading and accepts one part of it.
*   **The body also carries what did not read** — each source that was unavailable, so a quiet state is never mistaken for a clear one.
*   **A run always names a move** (`§INV_NEXT_ALWAYS_A_MOVE`). Every state can be quiet while the project still has ranked open work, so the floor is the ranked next move from `engine project next`, handed to `/inbox-next`. An invocation ending in *"nothing to do"* is a bug: it means the floor was not reached, not that there was nothing.

### 6. Route on accept — one move, through a composed skill

Invoke the one skill the accepted move names, and stop. **One move per invocation** (`§INV_NEXT_ONE_MOVE_PER_RUN`): never chain a second route onto the same accept, because an accept is only ever consent to the one state the operator was shown. A second move is a second invocation.

*   Resume a lane → dispatch a fresh lane with that lane's **log path** in its context pack.
*   Fork or board → `Skill(decide, …)`.
*   Uncommitted → `Skill(snapshot, …)`.
*   Groomable → `Skill(groom, …)`.
*   Ranked pick → `Skill(inbox-next, …)`.
*   **Declined** → report the reading and stop. Nothing is dispatched, committed, filed or transitioned in a run the operator did not accept, which is demonstrable by running to the proposal and declining.

### 7. Report

One terse line: which state was acted on, which skill was invoked, and what remains named-and-unacted. Then stop — what happens next belongs to the routed skill.

## Constraints

*   **`¶INV_NEXT_PROPOSES_NEVER_DECIDES`**: it proposes; the operator accepts. Dispatching a lane, committing, filing or transitioning anything on its own reading of state is forbidden — an entry point acting on a misread state does damage nobody asked for, and every state here is read from a surface that can be stale, partial or silent at exit 0.
*   **`¶INV_NEXT_ONE_MOVE_PER_RUN`**: one move per invocation. Chaining several routes onto a single accept is forbidden; the other applicable states are shown and left unacted.
*   **`¶INV_NEXT_BORROWS_THE_GROUPING`**: it groups nothing and ranks nothing of its own. Any clustering of items into topics, or any ordering of open work, computed inside this skill is forbidden — `/groom`'s topics and `engine project next`'s order are the sources. This is `skills/groom/SKILL.md:20`'s own rule applied to a third party.
*   **`¶INV_NEXT_BLOCKING_FIRST`**: what stops progress outranks what adds progress. Proposing new work while a lane is parked, a fork is unanswered or finished work sits uncommitted is forbidden — those states are shown first and the new work waits a rung.
*   **`¶INV_NEXT_BRAKE_IS_NUMBERED`**: a refusal to advance names what to close and cites its count. Braking on an unnumbered judgement is forbidden.
*   **`¶INV_NEXT_ALWAYS_A_MOVE`**: a run always names a move. Ending with "nothing to do" is forbidden.
*   **`¶INV_NEXT_INVENTS_NO_STORE`**: it reads only sources that already exist and writes no ledger, no cache and no state of its own. A state that cannot be read without one is **reported as unread** and the reason given.
*   **`¶INV_NEXT_MINTS_NO_LANES`**: it dispatches no workers of its own beyond the single resume the operator accepted, and keeps no ledger. This is the falsifier the skill stands on: if it starts conducting, it folds back into `/loom`.
*   **`§INV_RIDE_NEVER_ACTIVATES`**: riding a live session, it activates nothing and moves no phase.
*   **`§INV_OFFER_DONT_FORCE_SKILLS`**: every route is an offer. A route whose state does not hold is skipped silently rather than displayed and declined.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file.

## Notes

*   **Nothing in this design has been exercised.** The routes and the precedence rule were decided by the operator and written here; the first run is the test. Treat a disagreement between this file and a live reading as evidence about this file.
*   **The loop gate is the better surface whenever it is awake.** This skill exists for the moment it is not. A conductor mid-weave should reach for its own gate, which runs these same conditions as cadences and costs no extra wake.
*   **Why the boundary is not redrawn.** `skills/groom/SKILL.md:20` states the `/groom` ↔ `/inbox-next` split and gives its reason, and `/groom` composes `/inbox-next` rather than re-deriving its ranking. That is a decision with a stated rationale. What this skill adds is a third question above both of them and the one place the three are stated together; it changes the signposting, not the split.
