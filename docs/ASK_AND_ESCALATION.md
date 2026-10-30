# Asks and Escalation

An ask is a question written to a file. When an agent needs a decision it is not entitled to make, it writes the question down with `engine ask new`, keeps working on everything that does not depend on the answer, and picks the answer up later. The file travels up a chain of seats (a seat is one agent's tmux pane, named `window:label`) until it reaches someone allowed to answer it: a manager seat for the questions a manager may rule on, the operator for everything else. Asks replaced questions put at the agent's own terminal with `AskUserQuestion`, which blocked the agent until someone answered, held at most four questions per round, and reached only whoever happened to be watching that one pane. An ask blocks nobody, holds any number of nested questions, and can be answered by whichever seat the chain reaches. A decision board from `/decide`, when one was made, no longer has to be its own channel either: the ask links it by path or URL, and the ask is what carries it to the person who answers.

**Related**: `skills/ask/SKILL.md` (the file format and every CLI command), `skills/ask/assets/ASK_AUTHOR_GUIDE.md` (how to write an ask that can be answered), `skills/loom/SKILL.md` § The manager chain (how a loom conductor escalates), `COORDINATE.md` (the older coordinator event loop), `FLEET.md` (seats and panes).

## The path of a question

```
  asking seat                     its parent (a manager)            operator
  -----------                     ----------------------            --------
  engine ask new  ──── to: ────>  hop.sh inbox lists it
       │                          hop.sh may-rule
       │                            ├─ rule ──> engine ask answer ─┐
       │                            └─ pass-up ─> engine ask forward ──> app at 127.0.0.1:4977
       │                                                              or engine ask answer
       │                                                                   │
       │   <──────── answer written into the file, then pushed ────────────┘
       │             to the asker and every seat that forwarded it
       v
  engine ask read   (on its own turn: /next, or a loom's loop gate)
```

### 1. The agent writes the ask

A seated agent runs `engine ask new` with the question body on stdin. The command prints the new file's path, `<asks root>/<asking seat>/<id>.md`. The file has a header of one-line `key: value` fields (who it is from and to, why it matters, the asker's lean and what would prove the lean wrong) and a body written as a decision tree: one heading per question, with coded options under it.

The asker is always the live seat that runs the command, read from tmux. `--from` may only repeat it.

### 2. It is routed to the parent seat, or to the operator

Unless `--to` names someone, the ask goes to the asking seat's parent: the pane's live `@pane_parent` in tmux. A seat with no parent asks `operator`. This is the same rule `hop.sh target` uses (`skills/coordinate/scripts/hop.sh`), and a loom conductor reads its destination with `hop.sh target` at each escalation rather than trusting an old reading. When `hop.sh target` cannot name a parent (the live tree is unreadable, or the seat is missing from it), the question still goes somewhere: to the operator, with the reason it could not go up the chain.

An ask can be marked `reserved-for: operator` (`engine ask new --reserved-for operator`). That mark means only the operator may answer it, directly or through a seat that relays the operator's words. Mark an ask this way when the call is a one-way door, touches another team's code, spends money, or falls in a class the grant reserves (below). A loom also marks everything on its hard escalation floor this way: a thread's ticket-disposition question, a cyclic deadlock between lanes, a build that keeps failing after retries, a critique finding that must be fixed or explicitly skipped, and a thread sent back to an earlier stage.

### 3. A manager may rule on it, but only within its grant

A seat that manages other seats reads the asks addressed to it with `hop.sh inbox`, and checks each one with `hop.sh may-rule`, which prints either `rule` or `pass-up: <reason>`. What a manager may rule on is set by the grant, the operator's written list of the decision classes a manager may settle on its own:

- **Delegated** (A to D): assigning an action the operator already approved; a fast-forward or an append onto ground this fleet owns; a provisional working position for one weave; interpreting a ruling already given.
- **Reserved** (E to H): rewriting history other people hold; a standing configuration change; an outward obligation; approving a merge of verified work.

Linear posts have their own split, set by an operator ruling relayed to every seat as the broadcast `ruling-ticket-tier`:

- **Routine posts** are approved by the seat's manager: "a new ticket inside your area's existing scope, status moves, and landing or checkpoint comments". The seat files the confirm as an ask to its manager (`engine ask new --to <the first word of hop.sh target>`), not marked `reserved-for: operator`. The manager's approvals stay visible to the operator, who can overrule them.
- **Scope-level posts** go to the operator, marked `--reserved-for operator`: "a ticket that opens new scope, crosses areas, creates or changes a project or initiative, or reverses an operator ruling".
- **A loom's automatic posting** (`/snapshot --yes` under the Automatic posting disposition) posts status and checkpoint comments without asking anyone. That counts as routine and stays allowed.
- **A new ticket never goes out through automatic posting.** It always takes a confirm: the manager's, or the operator's when it is scope-level.

Only a manager running `/coordinate` in Manager mode, or a loom conductor receiving its child seats' asks, holds the delegated classes. Any other manager rules on orientation questions alone ("which file is that in", "what did the operator mean by X"). `hop.sh may-rule` refuses E, F and G whatever a config says, and H unless the grant lists it.

A `rule` from `may-rule` is not yet a ruling. The manager still checks the question against its config's always-escalate list and its own confidence before answering. Anything that fails a check, and anything marked `reserved-for: operator`, the manager forwards: `engine ask forward <seat>/<id> --to <its own parent>`. The ask app refuses any answer to a reserved ask that does not come from the operator, so the mark holds even if a manager misreads it. Nothing catches an ask that should have been marked and was not, so the asker has to mark it.

### 4. The operator answers

The operator answers in the ask app or at a terminal.

- **In the app**, at `http://127.0.0.1:4977`. meta:engine deploys it from engine main, and nobody else serves it: `engine ask serve` rebuilds and deploys whatever ask-app code sits in the tree it is run from, uncommitted work included, so a serve from another tree replaces the operator's app with that tree's copy. The broadcasts `ask-serve-hold` and `ask-app-live-4977` say so, and the second one also tells seats not to run `/afk`'s serve step. The command (`engine ask serve`, and `engine ask serve --stop` to stop it) is meta:engine's to run. When the app is down, use `engine ask list` and `engine ask answer`. The app lists open asks as they change on disk, renders each question as a card with the asker's lean marked, hides questions that depend on an unanswered one, and writes the answer into the file.
- **At a terminal.** `engine ask answer <seat>/<id> --revision <N> --json '{"NAME":["CODE"]}'`. `<N>` is the revision you read; `engine ask list` prints it as `rev=`. A shell that is not a seat names itself with `--by operator`.
- **Relayed.** When the operator answers in some seat's chat, that seat records it with `--relayed-from operator --note "<when and where>"`. Only a seat with standing may relay: the addressee, a seat that forwarded the ask, or a manager of the asker. The asker never relays an answer to its own ask.

Every answer names the revision it read. If the ask moved since then (it was forwarded, revised or answered by someone else), the answer is refused and nothing is written, so one answer always wins.

### 5. The answer comes back

The answer is written into the ask file first, then pushed as a chat message to the asker and to every seat that forwarded it. The push is best effort. A seat that is in the middle of a turn only sees the message when that turn ends, and when no live session holds the seat the file says `delivery: undelivered` with the reason. The file is always the record.

The asker picks the answer up on its own turns:

- **`/next`** lists the seat's open asks and its answered asks it has not read, and folds each answer with `engine ask read <seat>/<id>`.
- **A loom's loop gate** reads them the same way before it looks for new forks.
- `engine ask read --unread` prints, in one go, every settled ask this seat asked or forwarded and has not yet read.

Read one id at a time with `engine ask read <seat>/<id>`, as `/next` does, rather than relying on `--unread`. A read is stamped only when the reader is a recipient of the answer (the asker or a seat that forwarded it). When it is not stamped, the command still prints the answer, but the reason goes to stderr as `(not stamped read: <why>)`, and the ask stays unread and comes back on the next pickup. In a bulk run that note is easy to lose among the other answers, and anything that keeps only stdout loses it entirely; one id at a time, you see each result with its own stamp or its own reason.

Reading through `engine ask read` stamps the reader's own read. Opening the file does not, and `delivery: delivered` only means the message was queued. Once the answer is used, `engine ask acted <seat>/<id> "<summary>"` records that, and the app shows the ask as queued, then read, then acted.

### Waiting: re-ping and pass-up

Nothing re-pings or passes an ask up on a timer; the operator ruled that a push triggered by an answer is fine and a timer is not. The asker checks on its own turns, at its loop gate or when `/next` marks an ask as overdue, and takes each step deliberately:

- **Re-ping** an ask that has waited about ten minutes: one short message to the holder naming the file. Do not rewrite the ask.
- **Pass it up** after about another ten. Only the current holder (the `to:` seat) moves an ask, with `engine ask forward`. When the holder itself is silent, the holder's own parent may move it. The asker may re-ping but never forward, and nobody edits `to:` by hand. `hop.sh target --of <the silent seat>` names the next rung up.

Meanwhile the asker keeps working on everything that does not depend on the answer. Blocking at one seat would block every seat above it.

### The other moves

- **Forward**: `engine ask forward <seat>/<id> --to <seat>` moves the ask one rung and records the hop in `forwards:`. Every forwarder also receives the answer.
- **Decline**: `engine ask answer … --decline "<reason>"` refuses an ask on the record. The asker picks up a decline exactly as it picks up an answer. An empty answer is never accepted in its place.
- **Drafts**: in the app, Save draft writes the answer into the file without settling it, and Send batch settles all of the operator's drafts at once and sends one message per seat. From the CLI: `engine ask draft`, `engine ask send`, `engine ask discard`.
- **Revise**: the asker changes an open question with `engine ask revise <seat>/<id>`. Drafts and answers made against the old revision are refused as stale.
- **Ruled in chat**: an ask the operator settled in conversation is closed with `engine ask acted <seat>/<id> "<summary>" --ruled-in-chat "<who, when>"`. On a reserved ask that close counts as a relay, so it needs `--relayed-from operator --note "<when and where>"` from a seat with standing.

Two kinds of seat do not write asks. A loom lane (a build agent working one thread inside a loom) escalates to its conductor, and the conductor writes the ask when the question has to leave the loom. An agent whose operator is at its own terminal in a session they are driving may still use `AskUserQuestion`.

## Writing a good ask

Read `skills/ask/assets/ASK_AUTHOR_GUIDE.md` before running `engine ask new`. Its rule is that the operator should be able to answer in one pass without asking you anything back. So each question is one decision, and each carries its own facts on its own card: what is at stake, two to four real options in neutral order (plus an honest do-nothing whenever doing nothing is possible), what each option costs, your lean with its reason, the strongest case against it, and how sure you are. A lean written once in the header covers only the first question, so a multi-question ask needs a lean under every question. Before writing, the guide also asks whether this is an ask at all: a fact you can look up, or a reversible choice inside your own grant, is not one.

One pitfall in the heading: the question's name comes first. Write `## ¶ASK_LAYOUT: Choose one: Where do the files live?`, not `## Choose one: ¶ASK_LAYOUT: Where do the files live?`. The parser (`HEADING_RE` in `tools/ask-app/src/lib/format.ts`) only reads a name placed between `##` and the question kind. With the name after the kind, the line still parses as a question, but with no name: `¶ASK_LAYOUT:` becomes part of the title, and the answer is stored under a positional key (`q0`, `q1` and so on). An answer keyed `LAYOUT` is then refused as an unknown question, which is what happened to one of meta:engine's asks.

## What /coordinate is, and whether we need it

meta:engine put it this way: "/coordinate is the old name for the seat-routing helper. What it does today is answer four questions for /ask: who is my parent, what is the chain above me, what is the tree, and may this seat rule on this ask. Use `engine ask` and the hop commands; you do not invoke /coordinate."

The skill itself (`skills/coordinate/SKILL.md`, with the mechanics in `COORDINATE.md`) is a manager's event loop. It watches worker panes, answers the terminal questions it may rule on by typing into them, and passes the rest up its parent chain. Around that loop it holds three things the rest of the system depends on:

- **`hop.sh`** (`skills/coordinate/scripts/hop.sh`): the script that reads the live seat tree from tmux and answers routing questions. `target` names a seat's parent, or `operator`; `chain` prints the ancestry up to the top; `may-rule` says whether a manager may rule on a question; `inbox` lists the open asks addressed to a seat.
- **The grant**: the delegated and reserved classes A to H described above, kept in the skill's Manager-mode config (`skills/coordinate/assets/coordinate.manager.config.json`).
- **The re-ping and pass-up rule**: deliberate steps on the seat's own turns, never a timer.

What every seat relies on, whether or not it is a manager:

- Routing an ask to its parent. `engine ask new` reads the parent by the same rule as `hop.sh target`, and a loom conductor calls `hop.sh target` directly at each escalation.
- `hop.sh chain`, which a loom records at setup so that a dead manager's own parent is still known.
- The live seat tree. There is no `hop.sh tree` command; `engine broadcast` (`scripts/broadcast.sh`) keeps its own copy of hop.sh's tree read, held to match it by a test, and uses it to bind each audience seat to its pane.

What only managers use: `hop.sh may-rule`, `hop.sh inbox` and the grant.

Nothing about this has moved yet. `hop.sh` is still at `skills/coordinate/scripts/hop.sh` and the grant is still in the coordinate skill's config. Moving them next to `/ask` and retiring the rest of the skill is planned as its own change, COORDFOLD.

### meta:engine's lean

In meta:engine's words: "Fold it. What seats use is the routing in hop.sh (target, chain, may-rule, inbox, and the tree read broadcast.sh copies) and the grant v1 classes behind may-rule; those move next to /ask and this doc. The 541-line /coordinate skill around them is an older manager event loop that /loom's manager chain and asks have replaced, so it retires."

Their strongest reason against it: "hop.sh's path is cited literally by the Stop atom in COMMANDS.md, by /afk and by five test suites. A move that misses one caller leaves a seat with no route up, and nothing goes red to say so". That is why the fold is its own ticket, and why `hop.sh` keeps its path until every caller moves in one change.

## Broadcasts or asks

An ask is a question going up. Use it when you need a decision from someone above you, and the work it blocks waits on the answer.

A broadcast is guidance going down or across. Use `engine broadcast` when you need to tell a set of live seats something they should apply: your direct children (`--children`), everyone under a seat (`--subtree SEAT`), or every live seat (`--all`). Each broadcast is written to a record, delivered to each seat's pane, and acknowledged by the seat with `engine broadcast ack <id>` once it has applied it; `engine broadcast status <id>` shows who has. A `--sticky` broadcast also reaches sessions that start later, because the session-start hook lists the standing broadcasts a seat has not acknowledged. A broadcast is pushed live only to seats whose session was active in the last hour (`BROADCAST_LIVE_WINDOW` minutes, read from the seat's `~/.claude/sessions/<pid>.json`), since waking a seat whose prompt cache has gone cold costs it a full re-read; every other seat gets it queued and is shown it once at its next wake, by the session-start listing or by the `user-prompt-broadcast-queue.sh` hook on its next prompt. `status` reports a seat as `queued` until then. `--all-live` pushes to every seat in the audience regardless. A broadcast expects no answer, and it does not grant authority: a seat treats it as guidance from a peer, not as an instruction from the operator.

If you find yourself broadcasting a question, write an ask instead. If you find yourself writing an ask to tell people something, broadcast it.

## Where things live

- **Asks**: `~/.claude/data/yarik/asks/<seat>/<id>.md`, one file per ask under the asking seat's directory. `engine ask path` prints the root; `ASK_ROOT` overrides it. `engine ask list` lists asks across every seat, with `--to <seat>` for the ones a seat holds and `--seat <seat>` for the ones it asked.
- **Broadcasts**: `~/.claude/data/yarik/broadcasts/`, holding `<id>.md` records, `<id>.acks.d/<seat>` acknowledgements, a `sticky/` index and a `queued/<seat>/<id>` queue per seat. `BROADCAST_DIR` overrides it.
- **The ask app**: `http://127.0.0.1:4977`, deployed by meta:engine from engine main and served by nobody else (see the `ask-serve-hold` and `ask-app-live-4977` broadcasts); its code is in `tools/ask-app/`. It also shows broadcasts and who has acknowledged them, read-only.
- **The CLI**: `scripts/ask.sh` (`engine ask`) handles `path` and `serve` and passes everything else to `tools/ask-app/src/cli.ts`, so the file format has one parser.
- **Routing**: `skills/coordinate/scripts/hop.sh`, until the fold moves it.
