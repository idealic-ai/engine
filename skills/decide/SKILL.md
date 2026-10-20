---
name: decide
description: "Mine the live session for the decisions that are actually blocking work, frame each one so it can be decided in place, optionally convene an expert panel as input, publish a shareable Decision Board, collect the human's call per item, and record what was decided — including what was decided against and why. Replaces the ad-hoc mid-thread question round, never a dispatched /interrogate a conductor requires: a question that GATHERS INFORMATION is an interrogation (/interrogate), a question that UNBLOCKS WORK is a decision (here). Fires preemptively on a conductor's cadence so a parallel run keeps moving without the operator asking to be asked, and every item names what deciding it unblocks. A building block: it surfaces, asks, and records — it never executes the decided work, and it never tallies a vote across people. Triggers: \"what do you need from me\", \"unblock yourself\", \"what decisions are pending\", \"put the forks up\", \"decision board\", \"ask me what you need to proceed\", \"decide\"."
version: 1.0
tier: lightweight
args: "[<the fork(s) to decide>] [--items <path>] [--vocabulary <a|b|c>] [--council] [--no-board] [-- <what the decisions must unblock>]"
---

Find the forks that are holding work up, and get them decided. `/decide` reads the **live session** — the log, the dialogue, the build trail, the lanes that handed something back unresolved — and extracts the decisions that are genuinely pending. It frames each as a decision card, optionally lets an expert panel react, publishes a **Decision Board** people can read, collects your call per item, and writes a record that says what was decided *and what was decided against*.

**The boundary that defines this skill.** A question that **gathers information** is an interrogation — `/interrogate` owns it. A question that **unblocks work** is a decision — `/decide` owns it. The test is mechanical: if nothing is waiting on the answer, it is not a decision, it is a **signal**.

**What it replaces, and what it does not.** It replaces the **ad-hoc question round** an agent improvises mid-thread when it needs the operator to choose. It does **not** replace a dispatched `/interrogate` that a conductor's protocol requires — `/loom` marks its per-thread interrogation `[MANDATORY]` and forbids substituting an inline exchange for the dispatched run, and that holds. Run both where both apply: the dispatched interrogation scopes the thread, `/decide` clears the forks the thread then hits.

**It is preemptive.** A conductor runs it on its own cadence so the operator never has to ask to be asked. It is also what moves the loop: every item names the work it unblocks, so deciding it visibly frees something rather than filing a note.

**The primitive is `AskUserQuestion`.** This skill invents no interaction mechanism — it is the *discipline* around one that exists: what counts as a fork worth surfacing, how it is framed so it can be decided in place, what evidence rides along, and what happens to the record afterwards. Every question routes through `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` and `§FMT_DECISION_CARD`.

⛔ **No multiplayer voting.** No ballots, no tallies across people, no quorum. A panel's verdict is *input to one person's decision*. A tally is out of brief.

*Crucial constraint:* `/decide` does NOT own a session. It reads the **active** session and writes its record into that session's `builds/`. With no active session it still works — from the arguments or a caller's list — and skips the session logging.

# /decide Protocol

## 1. Find the forks — the mining pass

**A. Mine the live session (the primary mode).** Read, in this order, and stop when the sources run out:
- the active session log and `DIALOGUE.md` — questions asked and left hanging, answers that opened a new fork;
- `builds/*` — build reports' open questions and assumptions-taken, `*_CRITIQUE.md` findings left untriaged, a council report's unresolved MUST FIX, an interrogate digest's **open residue**;
- the conductor's ledger where one exists — running threads, lane handbacks, escalations, parked items, anything a thread returned unresolved;
- the arguments and the recent conversation, for a fork named out loud and never settled.

**B. Apply the fork test to each candidate.** It is a decision for this skill when work is **blocked on it now**, when a **named upcoming dispatch** is blocked on it, or when an **agent is about to guess**. Keep the ones that pass; route the rest:
- nothing waiting on it, now or next → it is a signal. Record it as a recommended inbox drop and offer `Skill(inbox-post, …)`; the human accepting that chain is what posts it, never this skill (`§INV_DECIDE_DISPATCHES_NEVER_EXECUTES`);
- the answer is a fact someone has to supply → that is information-gathering; recommend `/interrogate` over it;
- already settled earlier in the session → cite the prior decision and drop it, rather than re-litigating.

**C. Name what each one unblocks, and check it is one decision** (`§INV_EVERY_ITEM_NAMES_WHAT_IT_UNBLOCKS`). One clause per item: the thread, the file, the dispatch, or the lane that moves once it is decided. An item with nothing named is a signal — route it per B and say so. Then ask *"is this one decision?"* — a fork that is really three gets split into three cards, because one pick cannot answer three questions.

**D. A caller-supplied list is the secondary entry point.** `--items <path>`, or a list in the prompt, skips A and enters at §2.

A caller's list must arrive **decision-shaped**: each item carrying its own **fork** (the choice, as a question), its **options with their trade-offs**, and **what deciding it unblocks**. Items that arrive shaped this way have already passed B — the caller established the block, and re-deriving it here would second-guess the caller's own protocol. Apply only C's one-decision check.

An item arriving **without options** is not carded — this skill frames options, it does not invent them (§2). Report which items were unshaped and ask the caller or the operator to frame them, rather than manufacturing an option set.

**Where a caller owns its own outcome vocabulary, it passes it**: `--vocabulary "<a> | <b> | <c>"` replaces §5's default dispositions for this run, and §6 records the caller's terms verbatim. `§CMD_ELICIT` hands the answer vocabulary to its caller; this flag passes that slot through rather than closing it one level down.

**With `--items`, write the decisions back into that file** as well as into the record — a caller that handed over a list reads its own file afterwards, and a record it does not know the path of is not a return leg (§6).

**E. When this fires** (`§INV_DECIDE_FIRES_PREEMPTIVELY`). A conductor runs a pass without being summoned, at any of: a thread landing · a lane handing back something unresolved · three or more open forks accumulated · immediately before a dispatch that would otherwise proceed on a guess. Run it then rather than waiting to be asked; the operator asking *"what do you need from me"* means a pass was already overdue.

*Honest status: `/loom`'s loop gate is this cadence's caller — it runs a pass on the list above and leads the gate with the forks, exits underneath. Not yet exercised on a real pass*, so the wiring exists and the behaviour is unobserved. Say it in that form rather than claiming either less or more.

**Acknowledge** in one line: `Deciding: N forks mined from <source> — <the one blocking the most>; record → <trailDir>/<slug>_DECIDE.md.` Mint `<trailDir> = <sessionDir>/builds/` and a kebab `<slug>`; reuse an existing `<slug>_*.md` in that directory when this is the same thread, so the record clusters with its build trail.

## 2. Rank the forks, then card each one

**Rank first** (`§INV_RANKING_WITH_PROOFS`, `§INV_TWO_LEVEL_PRIORITY`). The ordering axis here is **what the fork unblocks**: how many threads wait on it · what guessing wrong costs · whether the door swings back. Each rank carries its proof-pointer — the log line, the report finding, the handback that establishes the block. Put the top of the ranking up as a question rather than publishing it as settled; urgency lives in things a session cannot see.

**Then card each fork — this phase IS `§CMD_ELICIT`.** Execute it over the ranked forks and follow it as written: it owns the card fields, the anti-anchor ordering, the severity × complexity triage, the card depth per bucket, the always-visible buckets, and the rule on honest versus manufactured options. Read it there rather than from a summary here — a restatement is what drifts.

What this skill supplies as the caller is the **answer vocabulary** (§5's dispositions, or the caller's own via `--vocabulary`) and one field `§CMD_ELICIT` does not know about: the **unblocks** clause from §1C, which goes in the card body next to what's at stake.

## 3. Optionally convene a panel — offered, never forced

Run `§CMD_OFFER_COUNCIL_REVIEW` with **subject** `doc <the ranked decision list path>`. That command owns the offer, the Brief, the background dispatch, the bounded wait, the absence-check and the relay — compose it rather than dispatching council directly. `--council` accepts the offer without asking; `--no-board` and a declined offer are both normal outcomes.

**One council run per board, never one per fork.** The subject is the whole ranked list and the panel rules on every item in that single run — a panel per fork multiplies the most expensive step in the skill by the number of forks, for reasoning that reads the same list either way. Run it **before** the board publishes, so the panel's read can be stamped onto the page the render produces.

**The panel reacts; it never authors** (`§INV_STEERING_NOT_SOLUTIONS`). An expert proposing a further option returns to *you* as a signal the option set may be wrong — re-author the options and re-card, or leave it; never paste an expert's alternative onto the board as a choice. An absent council report means an absent panel: render without marks and say so, rather than reconstructing what a panel would have said.

**A panel's verdict is input to one person's decision** — `¶INV_PANEL_VOTES_ARE_A_READ_NOT_A_VERDICT`, declared in §Constraints below. Present it one layer further from authority than the operator's own lean, and never as a count that resolves anything.

## 4. Render the Decision Board — what a pass produces

**The board renders. It is not an offer.** A pass produces a page, and `--no-board` is the operator's explicit opt-out — not a call the agent makes on their behalf under time pressure. The page is what makes a fork legible to someone who was not in the session and re-readable by anyone afterwards; a pass that skips it has done the deciding and thrown away the product. That §5's confirm holds the authority says nothing about whether the page is produced (`§INV_BOARD_PAYLOAD_IS_ADVISORY`).

**Stat the skeleton** — `assets/skeletons/decision-board.skeleton.html`, this skill's own, the artifact the handoff template's first step says to copy. Absent, say so and render from the template alone, flagging the page as composed without it; the stat exists so the file degrades honestly, not as a reason to skip.

The house path, in order:
1. **Render** via a dispatched subagent from this skill's board handoff template — `assets/TEMPLATE_DECISION_BOARD_PROMPT.md` — referenced, never copied. The template reaches its skeleton by a relative path, so hand the subagent the template's own absolute path and let it resolve `./skeletons/` from there. Author the handoff as a **structured, non-lossy envelope per fork** (`§INV_HANDOFF_STRUCTURED_NOT_LOSSY`) and point at the full reports rather than digesting them. The skeleton also serves `/intake`'s waves and each `§` head states both readings, so the sections this pass has no content for are **cut, never invented** — say in the handoff that this is a build-loop board, not a wave.
2. **Integrity pass, by the orchestrator** (`§INV_PROVE_FAITHFUL_PRESENTATION`): every caption matches its asset, provenance is honest, each option key on the page matches an authored option, and the kit reference resolves.
3. **Publish kit first, then the board** — `~/.claude/engine/skills/prove/assets/publish-kit.sh`, then `publish-s3.sh <boardPath> <slug>` — because a board pointing at an absent kit has no behaviour. Capture the printed URL, the state-doc URL and its `docId` at this same moment, into the conductor's boards ledger where one exists and otherwise into the record (§6); the id is not recoverable later.

**Publishing a board creates an obligation someone else carries.** A conductor holding a boards ledger must come back and fold it, read what it collected, and account for it before it can close — so a board published and never read blocks a wrap-up rather than quietly expiring. That consequence is invisible from inside this skill, which is why it is stated here: publish because the forks warrant a page, and say in the handback that the board is now owed a read.

**Every fork carries its own full context on the page.** A row with a title and four buttons is the failure this phase exists to prevent — each entry renders the fork, its unblocks clause, the options as framed, the lean with its trade-off, confidence, the panel's read, and a free-text slot. The field lists are `§FMT_DECISION_CARD`'s for the card and `PAYLOAD_SCHEMA.md`'s for the panel; take them from there rather than from a copy here.

**Wire prose, not only buttons.** The payload schema's `note` type carries free text per item for any fact the option keys cannot hold, and `field` carries a structured value — render both on every fork, so nobody has to compress a thought into a checkbox.

**Render the panel per lens.** Each expert appears with its `lens`, `icon`, conviction `weight`, one-line `why`, its `alternative`, and `thinGrounds` where declared — the reasoning is the value, and a mark without its lens is an opinion with no author. A **count of lenses** may appear only under an explicit *panel read* label (`§INV_NO_MULTIPLAYER_VOTING` — it counts lenses, never people).

**The state layer is the normal path, not an upgrade.** `~/.claude/engine/skills/prove/assets/STATE_TRANSPORT.md` is finished: a presigned POST into a private events inbox (no anonymous write), an agent-run fold that CAS-writes the public state doc, and conditional-GET polling that costs 304 and no bytes when idle. Inject the state config at publish and record the `docId` where §6 places it. Two limits to state rather than discover: the presign lasts up to 7 days for a static IAM user but only **hours** under a temporary profile, so a long-lived board degrades to the clipboard copy-back; and the fold is agent-run, so a `404` or a stale read means *not yet folded*. Run `~/.claude/engine/skills/prove/assets/prove-sync.sh <docId>` and re-fetch rather than reporting zero answers. To read the doc, load the fetch tool first (`ToolSearch` → `select:WebFetch`).

⛔ **Two tally traps sit directly on this path.** `state-demo.html` renders a live 👍/👎 scoreboard — read it for the transport wiring and copy none of its presentation. And `PAYLOAD_SCHEMA.md` must be **split, not adopted whole**: take its event shape, id grammar, dedupe-by-`id` and greatest-`ts`-per-`(actor, item)` supersede rules, which this skill needs because the state doc is an append-only log every reader reconciles at read time; leave its **human-tally** rules, which belong to a wave that counts teammate votes. Same events, same dedupe, different presentation — named readings here, never a total.

**Nothing on the board executes** (`§INV_DECIDE_DISPATCHES_NEVER_EXECUTES`). The page makes each decision legible — including what was decided against — and collects answers; it performs no work.

## 5. Collect the decisions — per item, in chat

Present each `Your-call` card **as its own `AskUserQuestion` body** via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`, batching per that command. The body carries the analysis; the **answers are the options**, each label led by `§FMT_ANSWER_GRADATION` — follow that format as specified, including its rule that only the dimensions actually differentiating this answer set appear. Write the body about the operator's decision and what it costs them, not about this protocol.

The default disposition vocabulary — what a pick *means* here, unless `--vocabulary` replaced it:
- **Decide it** — the chosen option becomes the lane's instruction. Record the option, and the falsifier that would reopen it.
- **Decide it provisionally** — proceed on this, flagged, with the named cheap check that would confirm or reverse it.
- **Defer with a trigger** — not now; record the event that brings it back, so it returns on its own rather than on a reminder.
- **Hand it to the lane** — the agent has enough to choose; record that the choice was delegated and the bound it must stay inside.
- **Needs information first** — the fork is not decidable yet; recommend `/interrogate` over it and carry its digest back into the next pass.
- **Drop it** — the fork dissolved. Record why, so it is not re-mined next pass.

The `I've-got-this` and `FYI` buckets are presented as `§CMD_ELICIT` requires and may be batched in one confirm.

**Natural-language answers are honored.** *"Do B on all of them"*, *"hold the whole set"* — apply the obvious reading and echo what you applied, rather than re-asking item by item.

## 6. Record, hand back, stop

Write the decision record to `<trailDir>/<slug>_DECIDE.md` using this skill's `assets/TEMPLATE_DECISION_RECORD.md`. Per item: the fork · what it blocked · the options **as framed** · the decision · **what was decided against and the reason** (`§INV_REJECTED_OPTIONS_ARE_RECORDED` — this is the half that stops the same question being re-litigated next pass) · the falsifier or revisit trigger · the panel's read where one exists, labeled as input · who decided and when.

**The board's handles belong to the conductor's ledger, not here.** Where a conductor keeps a boards ledger, it owns the `docId` and everything about fold and read state — it is read at every gate and it outlives this pass, whereas a decision record is finished the moment it is written. Record the board **URL** so a reader of the record can reach the page, and point at the ledger row for the rest; a second copy of a handle is a second copy of a contract. **Running with no such ledger** — standalone, or under a caller that keeps none — this record is the only home the handles have, so write them here and say that is why.

**Then close the return leg where one is owed.** Invoked with `--items`, write each item's outcome back into its own block in that file — the caller's vocabulary verbatim, plus the reason and a pointer to the record — so the caller reads its decisions where it already looks. A caller that handed over a file and got back only a path it does not know has no return leg at all. Leave every other part of the caller's file alone: this skill fills the outcome, never the caller's own framing.

Then echo **one line** in chat — how many forks were decided, what that unblocks, and the record path (`§CMD_LINK_FILE`). The file is the handoff; chat gets the pointer.

**The record path is the return value.** A conductor reads it and applies each disposition to its threads; a human reads it and picks the next move. `/decide` offers the chains — resume a blocked lane, `/interrogate` the items that needed information, `/snapshot` to put a decision on its ticket — and runs none of them. Decisions surfaced, asked, recorded; it stops here.

---

## Constraints

- **`¶INV_DECISION_UNBLOCKS_INFORMATION_GATHERS`**: route a question by what the answer does. Blocked work waiting on it → a decision, decided here. A fact someone must supply → information, gathered by `/interrogate`. Nothing waiting → a signal, recommended to the inbox. What this replaces is the **ad-hoc question round** improvised mid-thread, because rounds that gather context while a lane idles spend the operator's attention on the wrong half. It does **not** replace a dispatched `/interrogate` a conductor's protocol requires; where a conductor marks that step mandatory, the conductor wins.
- **`¶INV_FORKS_ARE_MINED_NOT_REQUESTED`**: the primary input is the live session, read by this skill. A caller may instead hand over a **decision-shaped** list — each item carrying its fork, its options and what it unblocks — which has already passed the fork test on the caller's side. An unshaped list is reported back for framing, because inventing the options would make up the caller's decision for it.
- **`¶INV_DECIDE_FIRES_PREEMPTIVELY`**: a conductor runs a pass on the cadence in §1E rather than on request. The operator asking to be asked is the signal that a pass is overdue, not the trigger for one.
- **`¶INV_EVERY_ITEM_NAMES_WHAT_IT_UNBLOCKS`**: every surfaced item carries the thread, file, or dispatch that moves once it is decided. Items without one are routed, not padded onto the board — the clause is what makes the board drive the loop.
- **`¶INV_NO_MULTIPLAYER_VOTING`**: no ballots, no cross-person tallies, no quorum, no count that resolves an item. One person decides each fork; everything else is input to that person. Where a shared surface collects several people's leanings, present them as named readings, never as a score. **The one permitted count is a panel read** — how many expert *lenses* landed where, rendered under that label, beside each lens's own reasoning. It is a count of **lenses, not people**, and it informs one person rather than resolving anything: a panel is a single reviewer's many angles, which is why it may be counted where teammates may not. The seam is exactly that wide — a count of humans is forbidden at any label, and an unlabelled count is forbidden even of lenses, because an unlabelled number reads as a result.
- **`¶INV_PANEL_VOTES_ARE_A_READ_NOT_A_VERDICT`**: a pass MAY convene a `/council` panel over its fork list and render each expert's pick on the option itself, so whoever decides does so with the panel's read in view instead of cold. A panel is offered, declinable and advisory; no panel is a normal passing outcome, and an absent report means an absent panel, never a reconstruction. Three things hold it in place. **It reacts, never authors** (`¶INV_STEERING_NOT_SOLUTIONS`) — the option set stays the orchestrator's curation, and an expert's `alternative` returns to the orchestrator as a signal the options may be wrong, never as a choice on the board. **It is distinguishable everywhere, structurally** — every answer in the payload carries a required `actor.kind`, and on the board the classes differ by *form* (icon for an expert, initials for a person), never by shade, because a contributor instrument counts distinct *human* contributors and a machine absorbed into that count disables the alarm that detects the system dying. **Its reasoning is reachable** — every mark carries the expert's own words, its self-reported 1–5 conviction, and whether it declared the grounds too thin to rule, reachable by hover, keyboard focus and tap alike; a mark whose reasoning cannot be reached is a judgement delivered at a confirm gate with its audit trail hidden, which is worse than showing no panel at all. Absent a panel, everything renders and ingests exactly as before; an orchestrator NEVER writes the votes itself.
- **`¶INV_REJECTED_OPTIONS_ARE_RECORDED`**: the record carries what was decided against and why, next to what was chosen. A record of winners only invites the same fork back next pass with the same options.
- **`§INV_BOARD_PAYLOAD_IS_ADVISORY`**: the board presents and collects; the §5 chat confirm is the authoritative gate. **Advisory describes the board's authority, never whether it is produced** — the two are separate claims, and reading the first as licence to skip the render is what made three passes answer a request for a page with a chat question. The board renders by default; only `--no-board` from the operator stops it. A published board with no recorded decision is a surface that collected nothing.
- **`¶INV_DECIDE_DISPATCHES_NEVER_EXECUTES`**: this skill surfaces, asks, records, and hands back. It writes no code, runs no lane's work, files no ticket, and posts to no tracker. **An offered chain is not an exception**: where a route needs a tracker write — an inbox drop, a ticket, a status update — this skill records the recommendation and offers `Skill(inbox-post, …)` / `/ticket` / `/snapshot`, and the human accepting it is what acts. The reason the line sits here rather than at a convenience: a skill meant to fire preemptively and often is only safe to fire unattended if it cannot write outward on its own.
- **`¶INV_PRIMITIVE_IS_ASK_USER_QUESTION`**: every question is an `AskUserQuestion` whose body carries its complete context (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`, `§FMT_DECISION_CARD`). Build the discipline on that primitive rather than a new interaction mechanism.
- **`§INV_QUESTION_GATE_OVER_TEXT_GATE`**: decisions are collected through a question, never a text block the operator is expected to answer in prose.
- **`§INV_OFFER_DONT_FORCE_SKILLS`**: the panel, the board, and every downstream chain are offers. A declined offer is a complete outcome, and no proof field gates this skill on one having been accepted.
- **`§INV_LISTS_INSTEAD_OF_TABLES`**: cards, buckets and the record render as named lists.
- **Cite, do not restate.** Where `§CMD_ELICIT`, `§FMT_ANSWER_GRADATION` or `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT` governs something, point at it and follow it there. A paraphrase drifts on contact and the drift is invisible, because the file claims to be citing.
- **Shared assets are referenced, never copied**: the board handoff template and payload schema live with `/intake`, the publish and state-sync scripts with `/prove`, the Council Brief with `/council`. Resolve them through this skill's `manifest.json` `sharedAssets` paths so a fix to any of them reaches this skill.
