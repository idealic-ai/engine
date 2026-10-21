---
name: groom
description: "A light grooming pass over everything a project could be working on that ends in dispatched work and always names the next move. Drains its sources — the intake inbox, the open tickets, the un-ticketed session leftovers, and the findings a loom's `/sweep` handed over — then CLUSTERS them into topics across those sources (the unit of work — one topic may hold an inbox report, two related open tickets and a leftover about the same area), disposes each topic once against what its members already are (an unfiled signal can graduate, fold, route to the tooling channel or marinate; an already-filed ticket instead dispatches as-is, folds, is re-scoped, or is deferred), then hands each topic to the running loom as ONE thread so related jobs on one area ride one worker. Every pass ends with a ranked next move read from the project's own importance ranking — never with \"nothing to groom\". The reduction of /intake: no decision board of its own, no announcements, no documentation phase. Triggers: \"groom the inbox\", \"groom this project\", \"groom the open work\", \"what's in the inbox\", \"what should I groom\", \"cluster the open work into topics\", \"batch up the related tickets\", \"pull work from the inbox into the loom\", \"groom\"."
version: 1.1
tier: protocol
args: "[project] [--since <ISO8601>] [--take <n>] [--limit <n>] [--sources inbox,tickets,leftovers,sweep]"
---

Drain a project's inbox, its open tickets and its un-ticketed leftovers, group them into topics across every one of them, dispose each topic once, dispatch each as a thread, and name the next move.

# /groom Protocol (The Groomer)

Execute §CMD_EXECUTE_SKILL_PHASES.

### What /groom is (and is not)

*   **It is** a **grooming pass that ends in dispatched work and a stated next move**. Four phases — drain, cluster, dispose, dispatch — and the pass is over. It is the deliberate reduction of `/intake`: that skill runs a full wave with a decision board, an expert panel, a two-point announce, a discussion loop and a documentation phase; `/groom` does the minimum that turns what a project could be working on into work somebody is building.
*   **It is NOT** an executor, and it writes nothing directly (`¶INV_GROOM_COMPOSED_WRITES`). Every mutation happens inside a composed skill under that skill's own confirm — `/ticket` files, `/inbox-post` routes a drop, the loom's own stages commit and open PRs. `/groom` reads, clusters, asks, and hands off. It transitions, assigns and starts nothing, which is also `/inbox-next`'s rule and the reason both skills route rather than mutate.
*   **`/groom` vs `/intake`**: reach for `/intake` when the inbox itself needs care — channels created, a handbook written, the hairball reorganized, a project update posted. Reach for `/groom` when you want work out of the project now.
*   **`/groom` vs `/inbox-next`**: `/inbox-next` answers *what do I do next* for one person at one moment and routes them into it. `/groom` answers *what is the batched shape of everything open here*, disposes it, and dispatches it as threads — and it **composes** `/inbox-next` for the ranking, the relation clusters and the leftover gather rather than re-deriving any of them. Two skills that both answered "what should I work on" with rankings of their own would drift apart; that is the failure this composition designs out.
*   **`/groom` vs `/sweep`** (stated in both files): `/sweep` answers *what does this one living loom know that nobody wrote down* — its own registers and its own files, nothing else — and hands what it finds to `/groom` as flat members in `builds/sweep-findings.md`. `/groom` reads that file as source (d), clusters those members with every other source, and disposes each topic once. `/sweep` never clusters, ranks, files or dispatches, and `/groom` never sweeps a loom's log itself: a second pass over the same log would be a second answer to what `/sweep` already answered. `/groom` does not read another loom's findings, and does not widen `/sweep` to an archive or the inbox.

### The sources, and the one unit

`/groom` drains **the intake inbox, the project's open tickets, the un-ticketed session leftovers, and the findings a loom's `/sweep` handed over** — Phase 0 names the mechanism for each, and that list of sources is the one place to extend. The reason is the pass that is otherwise wasted: an inbox can be legitimately empty while the project has thirty ranked open tickets and a week of unfiled followups, and a grooming pass that reads only the inbox calls that "nothing to groom".

### The unit is a TOPIC (`¶INV_GROOM_TOPIC_IS_THE_UNIT`)

A **topic** is one subject, carrying however many **members** arrived about it — one, or nine. A **member** is one item from any source: an inbox signal, an open ticket, or a leftover. Work is batched by subject so there are not too many things in flight, and every phase after the drain operates on topics.

**The unit keeps its name, deliberately.** More sources, one unit — "topic" is already defined as a *subject* rather than as a kind of item, both `¶INV_GROOM_TOPIC_IS_THE_UNIT` and `¶INV_GROOM_ONE_TOPIC_ONE_THREAD` are phrased on it, and a parallel "work group" vocabulary beside it would force every later phase to say which of the two it operates on. What is new is the word **member**, so this file can say "the things inside a topic" without saying "signal" where it means any of the three.

**A topic that mixes sources is the point, not an edge case** — an inbox report, the two open tickets already filed near it, and last week's leftover about the same area are ONE topic, and dispatching them as one thread is why clustering happens at all.

This is the spine, and the failure it prevents is specific: **a drained list of items is not a worklist.** Presenting one as if it were produces a pass that disposes nine comments about the same subject nine times, files duplicate tickets, and puts nine threads into a loom that then has to broker nine threads' file conflicts over one area of code (`¶INV_GROOM_NEVER_THE_UNGROUPED_LIST`).

`/loom`'s add-a-thread flow already groups very adjacent threads into one. `/groom` does that grouping **upstream**, so the loom receives topics already batched rather than re-deriving the grouping per thread — feed that rule, never duplicate it.

### Session — riding a loom, or a light session of its own

Read the active engine session's `.state.json`:

*   **`taskType` is `LOOM`** → **ride it.** The loom's session stays the session: artifacts go in its `builds/`, log entries go to its log (prefixed as the conductor's convention requires), and Phase 3's dispatched topics become that loom's threads. `/groom` runs no `engine session activate` here, and its phase list below is a reading order rather than a second session.
*   **any other `taskType`, or no active session** → **activate a light session of its own** from the Session Parameters below, and Phase 3 offers `/loom` over the topic list instead of handing threads to a conductor.

Say which case you are in, in one line, before Phase 0 does anything — the two cases differ in where every artifact lands.

### Deferred tools

`ToolSearch` `select:mcp__linear__list_documents,mcp__linear__get_document,mcp__linear__list_issues,mcp__linear__save_comment` before the first Linear call. *The `mcp__linear__` prefix is the standard server name, not a guarantee — resolve the same tool names from the available tool list when this machine mounts the server under another name.*

### Session Parameters
```json
{
  "taskType": "GROOM",
  "phases": [
    {"label": "0", "name": "Drain",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["sessionRide", "parametersParsed", "handbookRead", "sourcesRead", "drained", "openWork", "leftovers", "logEntries"], "gate": false},
    {"label": "1", "name": "Cluster",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["topics", "topicMembers", "relationClustersRead", "clusterConfirmed", "logEntries"]},
    {"label": "2", "name": "Dispose",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_REFUSE_OFF_COURSE"],
      "proof": ["dispositions", "markersPosted", "logEntries"]},
    {"label": "3", "name": "Dispatch",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG"],
      "proof": ["dispatch", "nextMove", "logEntries"]},
    {"label": "4", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "4.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "4.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "4.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_MANAGE_BACKLINKS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "4.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/decide", "/loom", "/inbox-next", "/groom", "/ticket", "/triangulate"],
  "directives": [],
  "logTemplate": "assets/TEMPLATE_GROOM_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_GROOM.md"
}
```

---

## 0. Drain
*Read everything that could be worked on — the inbox, the open tickets, and the leftovers nobody filed — and read the project's own dials first.*

§CMD_REPORT_INTENT:
> 0: Draining ___'s sources — inbox channels, open tickets, un-ticketed leftovers. Reading the handbook dials first.
> Focus: the project's Ticketing Strategy + channel set, then each source read through the thing that owns it, each count reported separately.
> Not: grouping or deciding anything — a drained item has no disposition yet, and a ticket already being filed is not one.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

**First, read the project's handbook — `§CMD_READ_PROJECT_HANDBOOK`, with `ask: true`.** That command owns resolving the handbook by doc id, the fresh fetch, the project-identity check, and the one-line degradation when a project publishes none; `/groom` calls it and never hand-rolls a document fetch. Pass `ask: true` because the project is load-bearing here — a pass that cannot name its project has nothing to drain.

Carry four things forward, verbatim, into every later phase (`¶INV_GROOM_HANDBOOK_SETS_THE_DIALS`):

*   **`## Ticketing Strategy`** — the project's Volume, Size and Substance dials. Phase 2 obeys these rather than this skill's habits.
*   **`## Boundaries`** — each neighbouring project's split plus the one-line test that decides a borderline topic.
*   **The channel set**, including whether a **🛠️ Tooling & Gates** channel exists. Phase 2 names that destination only when the command reports it real.
*   **The repo destinations** the project published for a tooling item's resolution. Name what the command returns and invent nothing when it returns nothing — a path that exists in one repository does not exist in the next.

The channel set's fast path is the registry `/inbox-post` owns, with that skill's discovery fallback behind it. Read it; do not copy it into this skill's assets.

**Then drain every source below.** Each is read through the thing that already owns it, each count is reported separately, and **a source that cannot be read degrades in one line and never silently becomes an empty source.** An empty inbox is not an empty pass — that is what the other sources are for. `--sources` narrows the set when a caller wants only some; absent, every source is read.

### (a) The inbox — through `§CMD_READ_INBOX_CHANNEL`

That command owns the fetch, the exclusion vocabulary and the filter that applies it (`¶INV_EXCLUDE_OWN_COMMENTS`). Run its program; **do not restate its marker list here and do not hand-roll the filter** — a second copy of that list is how `/groom`'s own replies drained back as fresh human feedback. The drained set is what the command returns.

```
engine project fetch <project> [--since=<ISO8601>] --out=<the session's builds dir>/groom-fetch-<ts>.json
```

*   **This is the reading side only; Phase 2's marker list is a separate contract and stays there.** One says what a read must not count, the other what this skill stamps — what they share is the vocabulary the command defines, and they must agree on it or the exclusion is incomplete. **An unmarked reply returns through the next pass's snapshot looking like fresh human feedback** — and because a marinated thread stays unresolved by design, its own reason is the comment most certain to come back.
*   **Two walks, one payload.** The new-signal set is what the command hands back — **recursive**, every node at every depth, because a reply is itself signal. The still-owed set is a second read of the same payload, run through the command with `INBOX_WALK=open-threads` (or read directly from the payload): it is **root-only**, because resolution is a property of a thread, so a reply reads `resolvedAt: null` forever and a recursive walk overstates what is open by roughly the reply count.
*   **Take the still-owed set from a fetch with no `--since`.** A delta filters on `updatedAt`, so a thread nobody has touched since it was last looked at cannot appear in one — which is exactly the thread a grooming pass is for.

**`/groom` mints no watermark** (`¶INV_GROOM_ADDS_NO_NEW_WATERMARK`). `--since` is a value the caller supplies — an argument, or the one an `/intake` project record already carries — and this pass **never advances it**, because a groom pass is not an intake wave and moving that waterline would skip every comment an intake drain has not yet read. What is still owed is already recorded in Linear as the unresolved threads; a second marker would have to be reconciled by every pass that reads either one.

### (b) The open tickets — through `engine project next`

```
engine project next <project> --json --limit <n>
```

`/inbox-next` step 1 owns this call and step 2 owns how its envelope is read and surfaced; **read it there rather than re-deriving a presentation here.** The envelope is `{project, degraded, importance[], adjacency[], linked[], overlap[]}`, and these of its properties bear on the phases below:

*   **Every `importance` and `adjacency` row already carries its own relation keys** — `relatedTo`, `parent`, `blocks`, `blockedBy`, `duplicateOf` — alongside `estimate`, `workType`, `state`, `milestone` and `blocked`. **The ticket clusters are therefore already computed, by Linear, and Phase 1 reads them rather than deriving them** (`¶INV_GROOM_READS_GIVEN_STRUCTURE`).
*   **`next` already drops In-Progress work** and reports how many as `excludedInProgress`. Say that number and re-filter nothing — something already being built is not groomable work, and a second filter beside the CLI's is the usual way a drop becomes silent.
*   **`degraded: true`** means the project publishes no milestones and the ranking fell back to priority. Say so in one line; the order is still the project's order.
*   **The `importance` order IS the project's ranking.** Phase 3's required next move is read from it, and `/groom` never computes another one.

### (c) The un-ticketed leftovers — through `/inbox-next` §3b, *Create from leftovers*

Run the gather that section specifies, and **stop before its multi-select** — the picking is this skill's clustering and disposal, which is the part `/groom` adds. That section owns which surfaces a leftover may come from and the de-dupe against the open tickets, and **this skill names none of them**, for the same reason it does not copy the channel registry: a second list of sources drifts from the first and nothing reports the drift.

*   **`/inbox-next` is a shared engine skill**, mounted wherever this engine is, so a project no longer has to carry its own copy for source (c) to work. Where the skill genuinely does not resolve — an environment with the engine absent — say so in one line and groom the sources that answered: the `engine project next` CLI is what source (b) needs, so (b) survives that absence and (c) does not.
*   **`/inbox-next`'s own two-round pick is NOT run here.** It is interactive and routes straight into `/implement`, which would take the pass out of Phase 1's confirm; it is offered whole at Phase 3's next-move point instead, which is the surface it was built for.

### (d) The sweep findings — `builds/sweep-findings.md`, written by `/sweep`

Read the file at `<sessionDir>/builds/sweep-findings.md` of the loom this pass rides, **its latest `## Sweep` section only** — each sweep re-reads the whole loom, so the latest section supersedes the ones before it, the same way a register block does. Every `*   **<finding>**` row in it is one **member**, tagged `sweep` and linked by its `Source` pointer. Row shape (declared in `/sweep`; this skill reads it and adds nothing): the finding in one line, then `Loom`, `Half` (`files` or `context`), `Kind`, `Source`, `Seen at`.

*   **Flat in, clustered here.** The rows arrive unranked and ungrouped, in source order. Cluster them with the inbox signals, open tickets and leftovers like any other member (`¶INV_GROOM_TOPIC_IS_THE_UNIT`); a topic may hold one open ticket and three sweep findings, and that mixed topic is the payoff.
*   **Dispose with the existing outcomes.** A topic of unfiled members is `graduate` (one ticket via `/ticket`) or dispatch as a thread of the riding loom, exactly as for a leftover. Nothing is added to the outcome set.
*   **De-dupe against the open tickets**, as source (c) does, before presenting.
*   **Not riding a loom, or no file at that path:** say so in one line and groom the sources that answered. A sweep that has not run is a finding about the loom, not an empty source.
*   **This is a pointer to one artifact, not a list of surfaces.** Which files and registers a loom sweep reads is `/sweep`'s; this skill names none of them.

### Then report what each source returned

**Say the numbers and get a ruling on how much this pass takes.** A mature project hands back more than one pass should groom, and **how much of it to take is the operator's call rather than the pass's** — an agent that quietly picks a subset has decided scope. Report, *before* Phase 1 clusters anything: the drained inbox count and the still-owed count · the open-ticket count with `excludedInProgress` · the leftover count or its one-line degradation. Then ask how much to take — `--take <n>` answers it up front, and `--limit <n>` bounds source (b) at the CLI. Whatever is not taken keeps the state it already had: an inbox signal stays unresolved, a ticket stays open at its rank, a leftover stays in the debrief it was found in. The next pass re-offers each of them. **Deferring is free; deferring silently is the one unacceptable outcome.**

---

## 1. Cluster
*Group everything drained into topics, ACROSS the sources. This phase is why the skill exists.*

§CMD_REPORT_INTENT:
> 1: Clustering ___ inbox signals, ___ open tickets and ___ leftovers into topics. Proposing groups with my reasoning.
> Focus: a proposed cluster set, each with its members and their sources, and why they belong together; then your merges and splits.
> Not: disposing anything — a topic has no outcome until Phase 2, and a member's existing state is not one.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

**Cluster across the sources, not within them.** One topic may hold an inbox report, the two open tickets already filed near it, and a leftover from last week about the same area — and that mixed topic is the point of the phase, because dispatching it as one thread is what batches related jobs on one area onto one worker. A proposed set in which every topic draws from exactly one source has probably clustered three times rather than once: say so and give the reason, because it is occasionally the honest answer.

**Ticket relations are READ, never re-derived** (`¶INV_GROOM_READS_GIVEN_STRUCTURE`). Linear already holds them and Phase 0's rows already carry them — `relatedTo`, `parent`, `blocks`, `blockedBy`, `duplicateOf`. Two tickets wired `relatedTo` each other are one topic's members **because the row says so**; inferring that from their titles while the keys sit in the row is the duplication this rule exists to stop, and it is the one this widening is most likely to commit by accident. **Inference is for the other two sources.** An inbox signal and a leftover carry no relations at all, so a topic is where they acquire one — that is the judgement this phase is for, and the tickets are the part it must not spend judgement on.

**Propose the clusters with the reasoning visible, then let the human merge, split and confirm.** Present each proposed topic as: a one-sentence subject · its **members**, each tagged with its source and linked in that source's own convention — an inbox signal as a `§FMT_TICKET_COMMENT_LINK` deep link, a ticket as a `§FMT_TICKET_LINK` with its `estimate` and `blocked` flag, a leftover as its source pointer · the channels it spans · one clause saying *why these are one subject*, naming the Linear relation where a relation is what joined them. The confirm runs through `AskUserQuestion` (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`) — merge two proposals, split one, move a member, or take the set as proposed.

**A single-member topic is legitimate.** One comment, or one ticket, about one subject is a topic; padding it with neighbours to look like a cluster manufactures a batch nobody asked for.

**Never present the ungrouped list as the worklist** (`¶INV_GROOM_NEVER_THE_UNGROUPED_LIST`). A drained list offered as "here is what to work on" has skipped this phase while appearing to have run it, and every later phase then operates per member. This now binds over every source, and **the ranked ticket list is the easiest way to violate it** — handing back `project next`'s output as the answer is exactly the ungrouped list, however well ranked. If clustering genuinely found no groups — every member its own subject — **say that as a finding**, with the reasoning, rather than letting the flat list pass as the default.

**Give each confirmed topic a slug**, so Phase 3 can hand it over as a thread without reshaping it: SCREAMING, at most 12 characters of `[A-Z0-9-]`, starting with a letter, never ending in a hyphen, digit-suffixed on collision. The slug is the loom's `threadId` convention. **A topic holding a ticket takes its highest-ranked member's ticket key as the slug instead of a minted one** — the key already names the work, and a minted slug beside it would be a second name for one thread. A topic with no ticket mints a slug that upgrades to a key if Phase 2 files one.

Record the confirmed set to `<the session's builds dir>/groom-topics-<ts>.md` (shape: `assets/TEMPLATE_GROOM_TOPICS.md`). Phase 2 reads it, and `/decide` takes it directly as `--items`.

**Fill each topic's `### Decision fork` block as you write it** — the fork, the Phase 3 dispatch it is waiting on, and what each outcome **available to this topic's members** would cost it. Phase 2 sets which those are, and they differ: a topic of unfiled members can graduate, a topic holding a ticket cannot, and omitting an outcome the topic cannot take is part of framing it rather than a gap in the block. That block is what makes the topic decidable by anything other than this protocol; a topic without it can only be disposed here, since `/decide` frames options and never invents them. The reading is Phase 1's lean, not a ruling — Phase 2 or `/decide` settles it.

---

## 2. Dispose
*Act per topic. Never per member.*

§CMD_REPORT_INTENT:
> 2: Disposing ___ topics against the project's Ticketing Strategy.
> Focus: one outcome per topic, drawn from the set its members' sources allow, each under its composed skill's own confirm.
> Not: filing per member, filing a ticket for work a member already tracks, and not writing anything directly.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Re-read the handbook immediately before the first write** — `§CMD_READ_PROJECT_HANDBOOK` is fresh-at-the-point-of-need, and a pass holding a copy from Phase 0 can act on a strategy that has since been edited.

### Which outcomes a topic may take

**The available outcomes depend on what a topic's members already are**, and this is where the widening bites hardest: the original set assumed an unfiled signal, so applying it unchanged to a ticket files a duplicate of a ticket this pass just read.

*   **An unfiled member** — an inbox signal, or a leftover — can take **graduate · fold · route 🛠️ · marinate**, unchanged.
*   **An already-filed member — an open ticket — cannot graduate.** It is filed. "File it" is not an outcome available to it, and a pass that reaches for one duplicates its own source. Its outcomes are **dispatch as-is · fold · re-scope · defer**, and **route 🛠️** as the next bullet explains.
*   **Route 🛠️ reads the same for both**, because the Subject dial is about the *subject*, not about filing: a filed ticket whose subject turns out to be machinery routes to the channel and the ticket is the thing that should not have existed — say that plainly rather than dispatching it.
*   **A mixed topic still takes exactly ONE outcome** (`¶INV_GROOM_TOPIC_IS_THE_UNIT`). Its usual shape is *fold the unfiled members onto the topic's ticket, and dispatch that ticket* — which is one decision with a consequence for each member, not a disposition per member. What is forbidden is deciding each member separately; what is required is that the one decision say what becomes of each.

**Offered first: `/decide` over the topic list** (`§INV_OFFER_DONT_FORCE_SKILLS`) — `Skill(decide, "--items <the topic list path> --vocabulary \"graduate | fold | route 🛠️ | marinate | dispatch as-is | re-scope | defer\"")` gives a shareable decision surface over the topics before any of them is disposed. Pass the whole vocabulary and let each topic's fork block carry the subset it can actually take; `/decide` frames what it is given and invents nothing. That skill owns the board, the cards and the record; `/groom` builds none of it. Declining is a normal answer and the per-topic confirm below is the gate, as it always was.

**What is handed over is each topic's `### Decision fork` block, not the raw topic** — the fork, what its Phase 3 dispatch is waiting on, and the per-topic trade-off of each outcome that topic may take. Phase 1 wrote those; a topic whose fork block is unframed is held back and disposed here instead, because `/decide` frames options and does not invent them. **`/decide` writes each outcome back into that topic's `### Disposition`** — read it from there, and treat it exactly as a Phase 2 confirm: the outcomes below still execute here, under their own composed skills' confirms.

**Offered where a topic is not ripe**: `/triangulate` to establish it from two angles, or `/triage` for a single angle on a topic that will produce neither a ticket nor a disposition. A not-ripe topic marinates with the gap named; it is not filed thin.

**Then exactly one outcome per topic:**

*   **Graduate — one ticket, via `/ticket`.** For a topic of **unfiled members only.** Invoke `Skill(ticket, …)` with caller-pinned placement: the project, the work-type milestone, and *new issue, never a sub-issue* — the parent it would otherwise detect is the frozen channel the signal arrived on. `/ticket` owns the body, its own prior-work sweep, and its own confirm; a hand-written body inherits none of that. **The Volume dial caps an agent at one ticket per run unless a human asks for more, which reads here as one ticket per topic** — a topic needing a split is a human's explicit ask, not an agent's judgement. A leftover graduating goes the same way, which is also `/inbox-next` §3b's own route for one.
*   **Fold into an existing ticket.** Real, but a facet of work already tracked. Carry the topic's context onto that ticket and post the pointer reply under each of its **inbox** signals. This is how the Size dial is actually honoured, and with tickets as a source it becomes the ordinary outcome rather than the exception — the ticket a signal folds onto is now usually a member of its own topic rather than something a sweep had to find. **When the members folding are themselves tickets**, the survivor is the one Linear's own `duplicateOf` names, or else the highest-ranked key; the fold is recorded and carried into Phase 3, and **the duplicate's close is a Linear write that happens in the loom's own stages when the work lands, never here** (`¶INV_GROOM_COMPOSED_WRITES`).
*   **Dispatch as-is.** The topic's ticket is filed, ranked and ripe; the outcome is that it rides Phase 3's thread and **nothing is written anywhere** — no reply, no transition, no second ticket. Once tickets are a source this is the most common outcome in a healthy project, and it is the one needing the least machinery: `project next` already ranked it and Linear already holds it.
*   **Re-scope.** The right ticket, the wrong shape — the topic shows its scope too narrow, too wide, or straddling two of its members. `/groom` does not rewrite a ticket: record the re-scope as the topic's disposition and carry it into Phase 3 as the thread's scope input, where the loom's own stages write it under their confirms. **A re-scope that reaches no thread is a note, not an outcome** — say which it is, so it is not counted as disposed.
*   **Defer.** The filed counterpart of marinating: real, ranked, and not this pass's work. **It needs no reply and no marker — the ticket's own open state at its own rank IS the record**, which is the standing advantage of a member that arrives already filed. Put the reason in the ledger; the next pass re-reads the ticket from the CLI at whatever rank it then holds.
*   **Route to 🛠️ Tooling & Gates, which never graduates.** When the topic's subject is a guard or check, tooling, a seat/ownership question, or agent-coordination machinery, it routes here through `Skill(inbox-post, …)` — the channel **is** the record, and the resolution lands in the repo destination the handbook named. Obey the **Subject** dial: a ticket's subject is product work, and **a guard may be a ticket's acceptance but never its subject.** The discriminator: strip the proposed fix and ask what is left wrong — something broken in the product is a defect topic, nothing left but the machinery routes here. Say both halves in the drop: the report is this comment, the resolution is in the repo.
    *   **One named project is carved out of the subject half, so a machinery topic bound for it graduates instead of routing here.** `/ticket`'s Subject Gate (§3 step 0) states the carve-out once and names the project; read it there rather than carrying a copy, and do not infer a second project from a topic's resemblance to that one. Everything else about this outcome is unchanged: the carve-out answers the subject question alone, so such a topic still has to clear the **Volume** and **Size** dials to be a ticket at all, and a topic that is a finding rather than a chunk marinates exactly as it would here. For every other project, machinery still routes to 🛠️.
*   **Marinate.** Real, not yet a chunk worth tracking. Record *why*, under the topic's own inbox signals. **A marinating leftover has no thread to record it on**, so its reason goes into this pass's debrief `## Leftovers` (Phase 4.3's `§CMD_REPORT_LEFTOVER_WORK` writes it) — which is a surface the next pass's gather reads, so the leftover returns with its reason attached instead of returning bare. **Marinating is an outcome, not a failure** (`¶INV_GROOM_NOTHING_IS_DROPPED`) — a topic left on the record with a stated reason is the opposite of loss, and "not its own ticket" always means folded, dispatched, deferred or marinating, never discarded.

**Every reply this phase posts onto an inbox channel leads with its marker** (`¶INV_GROOM_MARKS_WHAT_IT_WRITES`). One marker per outcome that posts one, so a pass can tell its own prior work from new signal:

*   **graduate** → `filed as ENG-XXX`, naming the ticket.
*   **fold** → `seems like ENG-XXX`, naming the parent it became a facet of.
*   **route to 🛠️** → `→`, naming the channel drop `/inbox-post` created, so the signal's destination is reachable from where it arrived.
*   **marinate** → `⏳ marinating`, with the reason in the same reply.

**The widening adds no marker, and that is a result rather than an omission.** A marker exists to stop `/groom`'s own reply draining back next pass as fresh human feedback, so the contract binds exactly the replies that land on an inbox channel thread — and a ticket or a leftover has no such thread. **`dispatch as-is`, `re-scope` and `defer` post nothing at all**: a ticket's record is its own open state at its own rank, so there is nothing to mark and nothing that could be misread as signal. A **leftover** is likewise disposed where it was found; what stops one being filed twice is the de-dupe against open tickets that `/inbox-next` §3b owns, plus a marinated leftover's reason landing in this pass's debrief `## Leftovers` where the next gather reads it. The reader-side vocabulary in `§CMD_READ_INBOX_CHANNEL` therefore needs no edit for this change, and the two sides stay identical.

**This list is a contract about what `/groom` WRITES, and it is not the same rule as Phase 0's exclusion** — that one is about what a read must not count. What the two share is the **vocabulary**, and `§CMD_READ_INBOX_CHANNEL` is where that vocabulary is defined. Every marker above must appear in that command's table; a marker here that is absent there is a reply no drain will recognise, and the check in `scripts/tests/test-inbox-read-cmd.sh` fails on exactly that divergence rather than leaving it to a later pass to discover.

**The marinate reply is the one that divergence costs most.** Its thread stays unresolved by design, so it re-surfaces on every later pass — which is how `⏳ marinating` came to drain back as fresh human feedback while it was in this list and absent from the neighbouring filter's. **Adding a disposition that posts onto a channel means adding its marker here and in the command's table, in one edit.** A disposition that posts nothing adds nothing to either — say which of the two a new outcome is, in the same edit that adds it, because the quiet third case is an outcome that posts a reply while its author believed it did not.

**Phase 1 writes nothing to Linear**, so clustering mints no marker and needs none — the topic grouping lives in the local topic list until a disposition gives it a destination.

**Then resolve only the threads that have left the inbox**, after the pointer reply is posted and never before: graduated, folded onto a ticket, routed, or closed as superseded or already-shipped. **An inbox signal folded onto a ticket that then dispatches is a thread that has left the inbox** — the ticket is where it now lives, so it resolves like any other fold. A topic that is marinating, deferred, or still owed something stays unresolved — that open thread is the record that a decision is owed, and burying it is the loss this system exists to prevent. Mechanism: `engine ticket resolve-comment <commentId>` per disposed thread (`--reopen` undoes one). **A ticket member resolves nothing**, because it was never a thread.

---

## 3. Dispatch
*One topic is one thread — and the pass always names the next move.*

§CMD_REPORT_INTENT:
> 3: Dispatching ___ topics as threads, then naming the ranked next move.
> Focus: hand each disposed topic over as ONE thread carrying its members, its tickets and the dials; then the next move, read from the ranking Phase 0 already has.
> Not: spawning build agents, starting or transitioning a ticket, or inventing a ranking — the conductor owns the weave and the CLI owns the order.

§CMD_EXECUTE_PHASE_STEPS(3.0.*)

**One topic is one thread** (`¶INV_GROOM_ONE_TOPIC_ONE_THREAD`). When a topic carries several tickets, **they ride that single thread** — tickets are joined at dispatch by topic, which is the whole reason clustering happens before filing rather than after, and with open tickets as a source it is also the batching this skill exists to deliver: one worker, the related jobs on one area.

*   **Riding a loom** → hand each topic into the conductor's **add-a-thread flow**, with the topic's slug as its `threadId` (the ticket key, where Phase 1 took one or Phase 2 filed one), and pass as the thread's scope input: the topic's members with their links, its tickets, its disposition, any re-scope Phase 2 recorded, and the handbook dials. The conductor owns what happens next — the partition, the interrogation, the fan-out, the ledger. **`/groom` spawns no build agents**, and does not re-implement the flow it is feeding.
*   **Standalone** → `/groom` does not weave. **Offer `/loom` over the topic list as its batch** (`§INV_OFFER_DONT_FORCE_SKILLS`); declined, the topic list is the deliverable and the dispositions already landed in Linear.

**A topic whose members are already-filed tickets dispatches the same way.** The differences are that there is nothing to file first, that the thread opens on the ticket rather than on a signal, and that `/groom` still neither starts nor transitions it — the conductor's own stages do that under their confirms. Its scope input is the ticket(s), plus whatever its unfiled members added to them, plus the re-scope if there was one.

Record per topic: slug · disposition · the ticket keys or the channel it routed to · the thread it became, or **`not dispatched — <reason>`**. A topic with neither is an unfinished topic, and `dispatch` gates this phase on it.

### The ranked next move — a required output of every pass

**Every pass ends by naming the next move** (`¶INV_GROOM_ALWAYS_A_NEXT_MOVE`), whether it dispatched nine topics or none:

*   **The move** — the one thing to do now, named as its key and title, **read from the `importance` order Phase 0 already fetched** and never from a ranking `/groom` computed. A topic dispatched this pass is the move when one was dispatched; otherwise it is the top of that order.
*   **Why it is the move** — the milestone, the priority, or the `blocked` flag that put it there, as the row carries it, plus its `estimate` where one is set.
*   **What it is instead of** — the runner-up, so the move reads as a choice rather than an only option.
*   **The route** — **offer `/inbox-next` whole over the same ranking** (`§INV_OFFER_DONT_FORCE_SKILLS`). Its two-round strategy pick — start one · bunch the small ones · take a bigger one · brainstorm a cluster · file leftovers — is the surface built for acting on this, and it already exists. Declined, the move stands as the pass's stated answer and nothing is started.

**"Nothing to groom" is never a whole output.** A pass draining an empty inbox has two other sources and a ranking, so it reports the empty inbox as a finding and then answers what next. The failure this prevents was observed, not imagined: an inbox holding two comments, both the pass's own and correctly excluded, ended a pass at Phase 0 with nothing — honest about the inbox and useless about the work.

---

## 4. Synthesis
*The pass is over. Close it out.*

§CMD_REPORT_INTENT:
> 4: Synthesizing. ___ topics from ___ inbox signals, ___ tickets and ___ leftovers; ___ dispatched; the next move is ___.
> Focus: the topic ledger, the next move, the debrief, close.
> Not: draining more — that is the next pass.

§CMD_EXECUTE_PHASE_STEPS(4.0.*)

**Riding a loom, there is no separate close**: the dispatched topics are now the loom's threads, so hand back to the conductor's loop gate and let the loom's own synthesis cover them. Write the topic ledger into its `builds/` and stop.

**Debrief notes** (standalone, for `GROOM.md`):
*   **The topic ledger** — every topic, its members and their sources, its disposition, its ticket(s), its thread.
*   **The clustering** — what grouped, what the human merged or split, what stayed single-member, and **which topics mixed sources**, since a cross-source topic is the payoff this pass is measured on.
*   **The next move** — the one named in Phase 3, with the reason it ranked first and whether `/inbox-next` was taken up.
*   **Deferred** — what each source surfaced and this pass did not take, and the ruling that set the bound. **A marinated leftover's reason belongs under `## Leftovers`**, because that is the surface the next pass's gather reads it back from.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Groom complete. Walk through the topics?"
  debriefFile: "GROOM.md"
```

---

## Deliberately not in /groom

Named so a later editor adds them on purpose rather than by drift: Slack, the two-point announce, the Notion knowledge base, the discussion phase, the documentation phase, and multiplayer voting of any kind. `/intake` keeps all of them. **The decision board is not dropped — it moved to `/decide`**, which Phase 2 offers.

Also absent, and for a different reason — they exist elsewhere rather than being declined: **a ranking, an estimate, a relation graph, and a leftover-source list of `/groom`'s own.** `engine project next` computes the ranking, the estimate and the relations; `/inbox-next` §3b owns where a leftover may come from; `/sweep` owns what a living loom has not rowed. This skill reads each of them. A copy of any one here would be a second answer to a question already answered, which is the drift `¶INV_GROOM_READS_GIVEN_STRUCTURE` exists to stop.

---

## Constraints

*   **`¶INV_GROOM_TOPIC_IS_THE_UNIT`**: every phase after the drain operates on topics. A topic carries one signal or many; work is batched by subject so there are not too many things in flight. An action taken per signal — a disposition, a filing, a dispatch — is this skill's defining defect. **A topic's members may come from any source and a mixed topic is the intended shape**, so the rule binds over all of them: one outcome per topic, naming what becomes of each member, never one outcome per member.
*   **`¶INV_GROOM_NEVER_THE_UNGROUPED_LIST`**: the drained list is never presented as the worklist, and this binds over every source — **the ranked ticket list handed back as the answer is the ungrouped list, however well ranked.** Clustering that finds no groups reports that as a finding with its reasoning; a flat list is a stated conclusion, never a default.
*   **`¶INV_GROOM_ONE_TOPIC_ONE_THREAD`**: a topic dispatches as exactly one thread, and several tickets on one topic ride it together — which is the batching the skill is for. Every dispatched topic records the thread it became or an explicit `not dispatched — <reason>`.
*   **`¶INV_GROOM_READS_GIVEN_STRUCTURE`** *(new with the widening — it is here because the structure it protects did not exist when the skill read one source, and reading three makes re-deriving it the likeliest accident)*: where a source already carries the structure, `/groom` reads it and computes none of its own. **Ticket relations come from the rows' `relatedTo` / `parent` / `blocks` / `blockedBy` / `duplicateOf`, the ranking from `importance` order, the effort from `estimate`, the In-Progress exclusion from `excludedInProgress`, and a leftover's sources from `/inbox-next` §3b.** Inference is for the inbox signals and the leftovers, which carry no relations at all. Two tickets wired as related are one topic's members because the row says so; grouping them from their titles while the keys sit in the row is the duplication this rule names.
*   **`¶INV_GROOM_ALWAYS_A_NEXT_MOVE`** *(new with the widening — it is here because the pass it forbids actually ran: an inbox of two comments, both the pass's own and correctly excluded, terminated at Phase 0 with nothing, and no existing invariant reached it — `¶INV_GROOM_NOTHING_IS_DROPPED` governs a topic's outcome, not whether the pass produced one)*: every pass names a ranked next move as a required output, read from `importance` order rather than from a ranking this skill invented, with the reason it ranks first and the runner-up it beat. **"Nothing to groom" is never a whole output**; an empty source is a finding, and the pass then answers what next from the sources that answered.
*   **`¶INV_GROOM_HANDBOOK_SETS_THE_DIALS`**: the project's Ticketing Strategy decides Volume, Size and Substance, read through `§CMD_READ_PROJECT_HANDBOOK` and re-read fresh before the first write. A ticket's subject is product work — a guard, tooling, a seat question or coordination machinery routes to the tooling channel, which never graduates, with the resolution going to the repo destination the project published. A guard may be a ticket's acceptance; never its subject. A missing handbook degrades in one line and never blocks a pass.
*   **`¶INV_GROOM_ADDS_NO_NEW_WATERMARK`**: `--since` is supplied by the caller and never advanced here, and the still-owed set is derived from Linear's unresolved root threads. Persisted state tracking what is undecided would have to be reconciled by every pass that reads it — add none.
*   **`¶INV_GROOM_MARKS_WHAT_IT_WRITES`** (the writer-side contract; `¶INV_EXCLUDE_OWN_COMMENTS` is the reader-side one, and they are two rules rather than one written twice): every reply this skill posts leads with a recognized marker — `filed as` on a graduation, `seems like` on a fold, `→` on a route, `⏳ marinating` on a marinate. **The vocabulary those markers come from is defined once, in `§CMD_READ_INBOX_CHANNEL`, and the filter that drops them is that command's too** — this skill writes markers and never its own filter. The two sides must agree on the vocabulary or the exclusion leaks: when they disagreed by one marker, the marinate reason returned through the next pass's snapshot as fresh human feedback. Adding a disposition **that posts onto a channel** means adding its marker in both places in one edit, and the agreement is checked mechanically rather than remembered. **The outcomes that post nothing — `dispatch as-is`, `re-scope`, `defer`, and anything done to a leftover — mark nothing and need no vocabulary entry**, because a marker exists to stop a reply draining back as signal and there is no reply; a new outcome states which of the two it is in the edit that adds it.
*   **`¶INV_GROOM_COMPOSED_WRITES`**: `/groom` writes no ticket, no code and no git, and **transitions, assigns, closes and starts nothing** — which is also `/inbox-next`'s rule, so neither skill mutates Linear. Filing goes through `/ticket`, routing through `/inbox-post`, deciding through `/decide`, building and closing through the loom — each under its own confirm. A fold between tickets and a re-scope are *recorded and carried*, and written where the work lands.
*   **`¶INV_GROOM_NOTHING_IS_DROPPED`**: every topic leaves this pass with a recorded outcome, and marinating or deferring with a stated reason is one of them. A topic that is neither disposed nor deferred-with-a-ruling is lost signal. **A leftover is the member whose deferral is least self-recording** — an inbox signal keeps an unresolved thread and a ticket keeps its rank, so a marinated leftover's reason goes into the debrief `## Leftovers` the next gather reads.
*   **`§INV_OFFER_DONT_FORCE_SKILLS`**: `/decide`, `/triangulate`, `/triage`, `/loom` and `/inbox-next` are offered at their decision point, never forced.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file; the topic ledger's table lives in the emitted template, where tables are allowed.
