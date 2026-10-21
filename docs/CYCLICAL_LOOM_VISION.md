# The Cyclical Loom — Orchestration Vision
**Tags**: #needs-review

**For the operator and the lanes that will build this.** Sections 1–4 and 7 are **evergreen** — direction and target, no dates or status. Sections 5–6 and every chapter's measurement block are **dated**: they describe 2026-10-20 and carry their denominators. A measurement taken in another repository says so.

Every claim here is labelled **measured** (someone ran it, here), **inferred** (it follows from something measured), or **proposed** (a design choice, with the thing that would falsify it). Rendered as named lists rather than tables, per `§INV_LISTS_INSTEAD_OF_TABLES`.

---

## Provenance

*   **Created by** — `sessions/2026_10_14_LAND_TREE_BRANCHES`, riding a live `/loom` session rather than activating its own
*   **Mode** — Greenfield (no prior vision existed to diff), grounded in the skills as they are today
*   **Date** — 2026-10-20
*   **Version** — v1
*   **Previous version** — none
*   **Plan** — `DIRECT_PLAN.md` in the session directory above

---

## 1. Background & Motivation

### Problem Statement

A loom runs one batch of work and ends. Everything it learned that it did not write down ends with it — and a great deal is never written down, because writing it down is offered rather than required. The operator's own words: *"with regular Loom, I believe we are losing a bunch of stuff — things don't get properly integrated, they get deprioritized, not written down."*

**The cause is not insufficient discipline. The spine is a context, and contexts end.** A conductor holds the ledger, the open decisions, the parked threads and every "noticed but not touched" finding in working memory. When that memory ends — by overflow, by the operator closing the terminal, by a day finishing — the work does not fail visibly. It becomes indistinguishable from work that never existed. There is no gap where it used to be.

That is the whole problem, and it is why the remedy is structural.

### Current State

A loom today is `Setup → Loom → Synthesis`. It takes a batch, fans threads out in parallel, brokers file conflicts, escalates what the operator must decide, and closes on an explicit *wrap up*. It works. What it lacks:

*   **The ledger dies with it.** The thread ledger and the board rows live in the session log. Nothing reads them afterwards.
*   **Harvesting leftovers is an offer with explicit selectivity** — *"a thread that surfaced nothing worth filing posts nothing."* Reasonable when the session persists. Fatal when it does not.
*   **Decisions cannot come back.** A board renders and publishes; it collects nothing and returns nothing. *(measured — see `@engine/decision-transport`.)*
*   **The conductor has no planned exit.** It runs until an overflow hook fires and dehydrates, which is lossy and unchosen — while the rule one level down already says a *lane* near its cap should write its state and hand to a fresh lane. The conductor is held to a weaker standard than the agents it dispatches. *(measured.)*
*   **Nobody owns concurrency across looms.** *"Live lanes = shared slots"* holds inside one loom. Two looms do not know about each other. *(measured — the rule is scoped to one loom by its own text.)*

### Opportunity

An operator who checks in on their own cadence — not on the machine's — answers every open decision in one sitting and walks away. Work continues without them. Each loom leaves the next one a batch already reconciled against those answers, so attention compounds instead of being spent re-establishing where things were.

The deeper win is that **a leftover becomes detectable.** Once the inheritance is a written artifact, something absent from it is a visible omission rather than a silent loss. That is the difference between a system you can trust to run unattended and one you have to supervise.

### Cost of Inaction

Every loom keeps paying the re-establishment tax: a fresh session re-derives what the last one knew, and the findings that do not survive are rediscovered later **with full confidence and no provenance**, so nobody can tell they have been learned and lost before. That failure is invisible by construction, which is why it persists rather than getting fixed on its own.

### Stakeholders

*   **The operator** — cares that checking in hourly is enough, and that answering a decision actually changes what happens next. Affected most: this changes their job from supervising to deciding.
*   **A conductor (a loom session)** — cares that it knows when to hand over and what to write. Gains a planned exit it does not have.
*   **A lane** — largely unaffected; its contract is unchanged. Benefits from the execution-shape dial via cheaper, better-scoped runs.
*   **Whoever inherits** — a fresh loom, possibly days later, possibly a different person. Cares that the inheritance is self-contained. Today there is nothing for them to read.

---

## 2. Vision

### Goal

**A loom is a worker, not a vessel.** It picks up an inheritance, runs many waves against it, tops itself up with adjacent work as capacity frees, and when its own context nears its cap it grooms its exhaust, writes the next inheritance, and hands over. The spine — what is open, what was decided, what is owed — lives where it outlives any session. The operator's check-in is the clock.

### Success Criteria

- [ ] A loom closes with its leftovers written where the next loom reads them, and **a leftover that was not written down is detectable as missing** rather than silently absent.
- [ ] An operator answer left on a decision board **reaches the next loom.** Today it reaches nothing.
- [ ] A hand-off happens because the conductor **chose its moment**, never because an overflow hook fired — and the operator's explicit choice is still what ends the session (`¶INV_LOOM_NO_RUSH_TO_CLOSE`).
- [ ] A startup groom is measurably **cheaper** than an end-of-session groom. If they cost the same, the inheritance is not carrying enough.
- [ ] A loom tops up mid-run with **adjacent** work and routes unrelated topics to the inheritance instead of loading them.
- [ ] Concurrent looms do not thrash a shared test queue or tree — the live-lane count is bounded **globally**.
- [ ] The full test suite runs **once per wave**, never once per thread.
- [ ] A chunk of this vision can earn a ticket without violating the ticket-subject rule.

### Non-Goals

*   **A scheduler.** No cron, no watcher, no poll loop. The bill is wakes, and a loom that wakes to check whether anything happened pays for nothing. The operator's check-in drives the cycle.
*   **An immortal loom.** Keeping one session alive across gaps by repeated dehydration was weighed and rejected: the spine would remain a context. Contexts end whether or not a design admits it.
*   **A second clustering skill.** `/groom` already turns a pile into topics and hands back one topic per thread even when a topic carries several tickets. This vision gives groom new *positions*, not a rival.
*   **Relaxing the ticket-subject rule for product projects.** The carve-out is for the engine alone; the rule exists to stop a product tracker filling with agent plumbing, and it keeps doing that job.
*   **Autonomous decision-making.** A loom surfaces forks and records answers. It never answers its own, and it never tallies a vote across people.

### Constraints

*   **A loom never writes code, the tracker or git directly.** Every mutation goes through a composed skill under that skill's own confirm. This vision does not loosen it.
*   **No destructive git, ever.** The working tree is shared with live sessions and an unstaged revert leaves no recoverable trace.
*   **The hard escalation floor stands** — cyclic deadlock, build-fails-after-retries, a blocking critique finding, and a thread loopback always reach the operator, whatever the autonomy setting.
*   **A decision board must not show a count across people.** A panel read is attributable per lens; a tally starts resolving items by itself, which is the failure the no-voting rule exists to prevent.
*   **Measurements from another repository are labelled as such** and may not be relied on here until re-measured.

---

## 3. Architecture Sketch

### The lifecycle, after this project

```
§CMD_FLOWGRAPH — A loom's life, and the hand-off

START → inheritance exists (durable: batch + open ledger rows + open board rows)
  ↓
STARTUP GROOM  ⟨cold, cheap — RATIFY⟩
  │ • reads the inherited candidate batch
  │ • folds in: gap drops · others' tickets · THE OPERATOR'S ANSWERS · open ledger rows
  │ • the only groom that can see the answers — the batch was composed before they existed
  ↓
  ╭──────────── WAVE LOOP (many hops — iteration and deviation are intrinsic) ──────────╮
  │                                                                                      │
  │  FAN OUT lanes (worktree-per-lane where clonable; targeted tests only)               │
  │    ↓                                                                                 │
  │  CONDUCT — relay · broker · escalate · keep the ledger live                          │
  │    ↓                                                                                 │
  │  WAVE GATE — lanes land, full suite runs ONCE, capacity frees                        │
  │    ↓                                                                                 │
  │  ◆ conductor context has room for another wave?                                      │
  │  ║                                                                                    │
  │  ╠⇒ YES → MID-LOOM GROOM ⟨top up⟩                                                    │
  │  ║        │ • ADJACENT topics only — context already loaded, so nearly free           │
  │  ║        │ • unrelated topics → written to the inheritance, not loaded               │
  │  ║        ╰──────────────── back to FAN OUT ─────────────────────────────────────────┤
  │  ║                                                                                    │
  │  ╚⇒ NO  → leave the loop                                                             │
  ╰──────────────────────────────────────┬──────────────────────────────────────────────╯
                                         ↓
HAND-OFF  ⟨hot, deliberate — the groom and the write are MANDATORY; the close is the operator's⟩
  │ • END-OF-SESSION GROOM — exhaust → next candidate batch
  │   (out-of-scope piles · critique deferrals · parked threads · newly-OPENED questions)
  │ • write the inheritance: batch + ledger rows + open board rows
  │ • triggered by CONTEXT, never by work completion, never by a hook firing
  │ • the conductor RECOMMENDS wrap-up; the gate still defaults to keep-going
  ↓
END → the operator's explicit close lands it · a fresh loom inherits · answers come in their own time
```

### Key components

*   **`/loom`** — `engine/skills/loom/` — the conductor. Gains two boundaries, three groom positions, the execution-shape dial. Changed by `@engine/loom-cycle`, `@engine/groom-positions`, `@engine/execution-shape`.
*   **`/groom`** — `engine/skills/groom/` — clustering, unchanged in substance. Gains two new call sites and loses its selectivity at the hand-off. Changed by `@engine/groom-positions`.
*   **`/decide`** — `engine/skills/decide/` — board composition and the decision record. Needs a transport that works beneath it. Changed by `@engine/decision-transport`.
*   **The proof transport** — `engine/skills/prove/assets/publish-s3.sh`, `sign-post.py`, the board widget kit — where the cycle is currently broken at both ends. Changed by `@engine/decision-transport`.
*   **The durable ledger** — storage shape not yet chosen — what the next loom reads. Created by `@engine/durable-ledger`.
*   **The inbox-read command** — new, under `engine/.directives/commands/` — makes own-comment exclusion mechanical. Created by `@engine/inbox-read-cmd`.

### Key technical decisions, already taken

*   **Decisions sync through boards, and the transport gets fixed first.** *Rationale:* a board is the only surface that renders a fork with its context, options and costs; `/decide`'s premise is that a row with a title and four buttons is the failure it exists to prevent. *Rejected:* making the tracker the durable queue and demoting the board to a view — cheaper and available immediately, but it flattens the thing being decided. **Operator's call, against the recommendation on record.**
*   **The session is disposable; the spine is durable.** *Rationale:* anything else keeps the spine in a context. *Rejected:* one long-lived loom dehydrating across gaps.
*   **The hand-off is triggered by context, not by work completion.** *Rationale:* a loom is multi-hop by nature — threads iterate and deviate — so work completion is not a boundary that arrives. *Rejected:* one wave per session, which conflates two different events. **It does not become the conductor's close**: `¶INV_LOOM_NO_RUSH_TO_CLOSE` reserves that for the operator, and `@engine/loom-cycle` carries the amendment that keeps both — the conductor recommends, the operator ends the session.
*   **Own-comment exclusion becomes a command, not a directive entry.** *Rationale:* a rule with two genuine owners is owned by neither, and an ungated rule is a preference. *Rejected:* both `.directives` homes, for measured reasons recorded in `@engine/inbox-read-cmd`.

---

## 4. Decision Principles

### Development approach

*   **The thing the next loom reads must outlive the loom that wrote it.** The design in one line. Not *"trackers are good"* — a mechanical consequence of a session that ends on purpose.
*   **Batch at dispatch, not at duration.** One lane fed several related tickets' context in one brief, one batched run, hand back early. Many small-context well-fed lanes, never few long ones. **This is counter to the instinct and is the single thing most likely to be got wrong**: bigger batches save wakes, but a longer-lived lane costs more *per* wake.
*   **Top up on adjacency; hand over everything else.** Work in an area whose context is already loaded is nearly free. Unrelated work costs a fresh load and buys nothing a fresh loom would not do better.
*   **A hand-off is planned; a dehydration is an accident.** Apply to the conductor the rule that already governs a lane.

### Risk & escalation

*   **Top-up is governed by the conductor's remaining context, not by lane availability.** Free lanes are an invitation, not a licence. A loom that tops up whenever a lane idles never reaches its hand-off.
*   **A fork reaches the operator before it blocks a thread**, not after. An operator asking *"what do you need from me"* means a pass was already overdue.
*   **An escape hatch must be the result of doing the work, not a note written instead of it.** A board row left open must state what the fold found — which cannot be written without folding.

### Quality & standards

*   **A gate that has not executed is not evidence.** Cite a gate with how it was measured. Two dead checks in series were found in this system's own safety net, each masking the next.
*   **An assertion whose two sides cannot diverge is not coverage.** Before a check counts, name the input that makes it fail.
*   **Prove a zero with a positive control in the same invocation**, and prove a quotation against the file at the path cited. A mistyped pattern and a real absence print identically.
*   **Never read an exit status through a pipe.** A pipeline reports its last command's status.

### Prioritization

*   **Unblock the inheritance before optimising the wave.** A faster wave that loses its leftovers is worth less than a slow one that keeps them.
*   **Prefer a mechanism to a rule** wherever the rule can be made mechanical.

---

## 5. Context Sources
*Dated — all 2026-10-20.*

*   **`sessions/2026_10_14_LAND_TREE_BRANCHES/LOOM.md` + `LOOM_LOG.md`** — `/loom` — the session this vision came out of. Contributed the wake cost model, the suite timing distribution, the worktree figures, and the catalogue of instrument failures the quality principles are drawn from.
*   **`builds/board_BUILD.md`** — board render lane — the four transport defects, found by publishing and then driving a real board in a browser.
*   **`builds/board_CRITIQUE.md`** — adversarial pass — strengthened rather than retracted all four, and established the two findings that reshaped `@engine/decision-transport`: the state document is never written, and the naive write fix targets AWS.
*   **`builds/decouple_BUILD.md`** — build lane — the directives-placement measurement, the two dead gate checks, and the live `⏳ marinating` leak.
*   **`builds/flakyload_INTERROGATE.md`** and the FLAKYLOAD thread — experiment — the suite timing distribution over 105 interleaved order-rotated runs, and the remedies it falsified.
*   **`engine/skills/{loom,groom,decide,intake,prove}/SKILL.md`** — current source — the factual floor for what exists today.

---

## 6. Dependency Graph

```
§CMD_FLOWGRAPH — Chapter dependencies

START → vision approved
  ↓
GROUP A (no dependencies — all startable at once)
  │
  ├► @engine/ticket-carveout ─────────────────────────╮
  │   │ • lets engine work earn a ticket at all       │
  │                                                    │
  ├► @engine/decision-transport ────────────╮         │
  │   │ • operator-ordered first to staff    │         │
  │                                          │         │
  ├► @engine/durable-ledger ──────╮         │         │
  │   │ • the inheritance itself   │         │         │
  │                                │         │         │
  ├► @engine/execution-shape       │         │         │
  │   │ • NO downstream — ships alone        │         │
  │                                │         │         │
  ╰► @engine/inbox-read-cmd        │         │         │
      │ • NO downstream — ships alone        │         │
                                   │         │         │
  ╭────────────────────────────────╯         │         │
  ↓                                          │         ↓
GROUP B (one hop)                            │    @engine/direct-in-loom
  │                                          │
  ╰► @engine/groom-positions ───────╮        │
      │ • ratify · top up · preserve │        │
  ╭─────────────────────────────────┴────────╯
  ↓
GROUP C
  @engine/loom-cycle
   │ • the spine — composes the others, so it lands LAST
  ↓
END → a loom inherits, runs, and hands over
```

### Parallel groups

*   **Group A** — `@engine/ticket-carveout`, `@engine/decision-transport`, `@engine/durable-ledger`, `@engine/execution-shape`, `@engine/inbox-read-cmd`. No shared files: `ticket-carveout` touches the tracker and a rule clause, `decision-transport` touches `prove/assets/`, the rest are disjoint.
*   **Group B** — `@engine/groom-positions` (after `durable-ledger`), `@engine/direct-in-loom` (after `ticket-carveout`). Independent of each other.
*   **Group C** — `@engine/loom-cycle`. Last by necessity.

### Critical path

`@engine/durable-ledger` → `@engine/groom-positions` → `@engine/loom-cycle`

**`@engine/decision-transport` is not on the critical path despite being ordered first.** It is large and it gates the *cycle being worth running*, but nothing needs it until `loom-cycle`. "First" means first to be staffed. **`@engine/execution-shape` and `@engine/inbox-read-cmd` have no downstream at all** — they are independently shippable. **`@engine/inbox-read-cmd` has since landed** (§ STATUS RECONCILIATION), so `@engine/execution-shape` is the one left as a cheap independent start — and it now carries an unspecified integration step, so "cheap" means its test-shape half. A recommendation is corrected in place when a chapter lands, never left for a reader to discover: unlike a measurement, it cannot be a point-in-time snapshot and stay useful, and a lane sent to a finished chapter wastes a whole wake rediscovering it.

### Shared resources

*   **`engine/skills/loom/SKILL.md`** — `loom-cycle`, `groom-positions`, `execution-shape`. *Risk:* three chapters editing one file. *Mitigation:* they touch different sections; sequence them, or run them in worktrees, which is `execution-shape`'s own subject.
*   **The ticket-subject rule and the handbooks carrying it** — `ticket-carveout`, `inbox-read-cmd`. *Risk:* both amend inbox-adjacent rules. *Mitigation:* different clauses; `ticket-carveout` lands first as everything's precondition.
*   **`engine/skills/prove/assets/publish-s3.sh`** — `decision-transport` only, but **shared with every published page in the system**. *Risk:* a transport change breaks unrelated proof publishing. *Mitigation:* the chapter's acceptance includes an existing-page regression check.

---

## 7. Glossary

*   **Loom** — one conductor session running many threads in parallel. A worker, not a vessel.
*   **Thread** — one ticket, or one grouped topic, walking the build chain. Multi-hop by nature.
*   **Wave** — one fan-out-and-land cycle inside a loom. Frequent and cheap. **It ends at a boundary, and the boundary is a reading rather than a feeling**: every thread in the wave's fanned-out set has landed or parked and none reads `running`. **"Land" named a mechanism on 2026-10-21** — the conductor merges each lane's branch onto the session branch in landing order and the once-per-wave suite runs against the sha that produces (`skills/loom/SKILL.md` § *The wave boundary — integration*, `§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY`). *It had been a placeholder, which is recorded rather than erased: a wave was the unit the once-per-wave economy was measured in while the event that ends one was undefined.* **Still unexercised** — the merge needs a tree per lane, which is unbuilt, so under one shared tree a wave lands with nothing to merge.
*   **Lane** — one running agent, at one stage, for one thread. A thread spawns several lanes in sequence, so the two units differ: a cap written in lanes is not a cap on threads, and reading one for the other mis-sizes the concurrency budget by roughly the number of stages a thread walks.
*   **Hand-off** — a loom's deliberate end: groom the exhaust, write the inheritance, recommend the close. Triggered by the conductor's context rather than by work completion; the operator's explicit choice still ends the session, so a hand-off is a hand-over the conductor proposes, never one it takes.
*   **Inheritance** — what a loom writes for its successor: the candidate batch, open ledger rows, open board rows. The durable spine.
*   **Candidate batch** — the next loom's work, composed at hand-off *before* the operator has answered. Ratified at startup, not executed as-is.
*   **Gap** — the stretch between a loom closing and the next starting, during which the operator answers. Costs nothing: an idle loom makes no model calls.
*   **Wake** — a lane or conductor resuming after waiting. **The unit of cost.** A wake after the prompt cache expires re-reads the whole context at full price.
*   **Exhaust** — what a wave produces besides its deliverable: out-of-scope findings, critique deferrals, parked threads, newly-opened questions.
*   **Adjacency** — whether new work falls in an area whose context the loom already holds. Governs mid-loom top-up.
*   **Fork** — a decision blocking work, framed so it can be answered in place. Lives on a board.
*   **Board** — the rendered decision surface. Renders today; collects and returns nothing.
*   **Chunk** — a landing arc of days rather than hours. The unit that earns a ticket.

---

## Chapters

### `@engine/ticket-carveout`: Let engine work earn a ticket
**Tags**: #needs-coordinate

**State (2026-10-20, after v1) — landed, one item owed.** The project exists, the clause is in `loom/SKILL.md` with its boundary stated, and the chapters are filed as tickets with the dependency graph intact. **Owed**: the subject rule is stated in four shipped skill files and only `loom/SKILL.md` carries the clause, so the rule disagrees with itself by entry point *(measured — the phrase `agent-coordination machinery` appears in `skills/{groom,inbox-post,loom,ticket}/SKILL.md`; `Product: Orchestration` appears in `loom/SKILL.md` alone)*. v1's premise was also too broad: there are **two** gates, not one, and the carve-out clears only the conductor's. Details in § STATUS RECONCILIATION. **The acceptance checkboxes below are v1's plan, not the current state.**

The ticket-subject rule refuses *"a guard, tooling, a seat/ownership question or agent-coordination machinery"* as a ticket subject, and redirects such reports to a 🛠️ Tooling & Gates channel. This vision is agent-coordination machinery throughout, so **as the rule stands, none of it can earn a ticket** — which collides head-on with the reason tickets were brought back. This chapter creates the exception and draws its boundary.

#### Scope
*   **In scope**: a tracker project in which coordination machinery **is** the domain work; one clause in the rule naming the carve-out and its limit; propagation to every handbook carrying the rule.
*   **Out of scope**: relaxing the rule for product projects. That is the job it exists to do and it keeps doing it.
*   **Key files/components**: `engine/skills/loom/SKILL.md` (the invariant's text) · the Inbox Handbooks (tracker documents) · a new tracker project.

#### Dependencies
*   **Depends on**: nothing.
*   **Blocks**: `@engine/direct-in-loom`, and *trackability* for every other chapter.
*   **Shared resources**: the rule text and the handbooks — shared with `@engine/inbox-read-cmd`.

#### Acceptance criteria
- [ ] A project exists whose stated scope makes engine coordination work in-scope domain work.
- [ ] The rule carries a clause naming the carve-out **and its boundary**, so it cannot be read as a general relaxation.
- [ ] Every handbook that carries the rule carries the clause; the copies agree.
- [ ] A chunk of this vision is filed as a ticket without violating the rule — the end-to-end check.

#### Risks & open questions
*   **Risk**: a carve-out written loosely becomes a general escape, and the product trackers fill with plumbing anyway. → **Mitigation**: the clause names the project, not a category of work.
*   **Open question**: the project's name and summary. The convention is that a `Product:` prefix marks a standing product scope rather than a delivery effort — which this is. The existing bare-named `Kit` project is the counter-example the convention warns about.

#### Complexity & effort
*   **Effort**: S
*   **Complexity drivers**: none technical. The care is in the wording and in keeping the handbook copies in agreement.
*   **Label**: **measured** — the conflict was found by reading the shipped rule against this vision's own subject. **measured** — no existing project hosts engine work: a listing returned `Product: Realm`, `Demos & Explainers`, `Editor`, `Handbook`, `CI & Gates`, `Worlds & Branches`, `Market & Jobs`, `Idea`, and a bare `Kit`; the nearest neighbour, `CI & Gates`, is about gate jobs and the gate board, not the conductor.

---

### `@engine/decision-transport`: Make a board able to collect and return an answer
**Tags**: #needs-coordinate

**State (2026-10-20, after v1) — substantially done.** The full loop ran live (publish → presigned grant → POST 204 → fold → anonymous read carrying the vote), every defect listed below is fixed, and a fifth was found and fixed. The remedy was **cheaper** than this chapter claimed: no bucket policy needed touching. Details in § STATUS RECONCILIATION. **The defect list below is v1's diagnosis, preserved as history; the acceptance checkboxes are v1's plan, not the current state.** Note the key-files list below also named the wrong directory — the board widget kit is in `engine/skills/intake/assets/`.

A decision board renders correctly and emits schema-correct events — a real browser click produced valid vote events with deterministic ids — and it **cannot collect or return a single answer** on the destination in use. Until this lands, the cycle's feedback edge does not exist: the operator can be shown a fork and has no way to answer it that reaches anything. Operator-ordered as the first chunk to staff.

#### Scope
*   **In scope**: the write path, the read path, the state document that is never written, the silent-refusal failure mode, and the per-publish identity churn.
*   **Out of scope**: widening a bucket policy as a fix in itself — this chapter establishes that it does not work. Also out: redesigning the board's composition, which is sound.
*   **Key files/components**:
    *   `engine/skills/prove/assets/publish-s3.sh` — the write-grant refusal, the never-written state document, the per-run identity
    *   `engine/skills/prove/assets/sign-post.py` — no endpoint support; hardcodes the POST target
    *   the board widget kit — the swallowed refusal

#### The defects
*   **The write path is blocked twice, independently.** `publish-s3.sh` refuses a presigned write grant on **any** non-empty endpoint — unconditional, no bypass flag, **not** a credential failure. ⚠️ **And the obvious one-line fix is dangerous**: `sign-post.py` has no endpoint support at all and hardcodes the POST target to the cloud provider's own hostname, so removing the refusal would **mint a grant against the real cloud account** and send operator answers there. Read this before proposing the fix. *(measured.)*
*   **The read path is not a policy problem.** The state and event prefixes hold **zero objects on either store** — the script mints a state URL and never writes it. **Widening the grant turns a refusal into a not-found, not into a working read.** A chunk written from the refusal alone would fix the wrong layer. *(measured.)*
*   **A refusal is swallowed through the success arm.** The kit treats a refused read as the not-yet-folded case, so the flag never flips and **a board waits calmly forever looking as though nothing had been folded.** A refused read and an unfolded board are indistinguishable by construction. *(measured.)*
*   **A republish mints a new identity.** The document id derives from a per-run random stem, so each render iteration produced a new page URL *and* a new state document; answers against an earlier URL are stranded. **A cyclical design republishes boards, so this is load-bearing rather than cosmetic.** The script names a counter-harm for the obvious fix a few lines above the assignment — read it before proposing the rejected design. *(measured.)*
*   **The comment is true somewhere.** One store grants anonymous reads across the whole prefix, so the script's claim that state is publicly readable is correct there and wrong only on the store in use. A one-store divergence, not a wrong comment. *(measured.)*

#### Dependencies
*   **Depends on**: nothing.
*   **Blocks**: `@engine/loom-cycle`.
*   **Shared resources**: `publish-s3.sh` is shared with **every published page in the system**, not just boards.

#### Acceptance criteria
- [ ] An answer submitted on a published board arrives in durable shared state.
- [ ] A fresh reader of that board sees the answer.
- [ ] A refused read is **distinguishable** from an unfolded board, in the page and in whatever a conductor reads.
- [ ] Republishing a board **preserves its identity**, or the design explicitly re-points answers and says how.
- [ ] No path in the changed code can direct a write to a destination the operator did not choose — asserted, with a test that fails if it can.
- [ ] Existing non-board published pages still publish and render — the regression check for a shared script.

#### Risks & open questions
*   **Risk**: the write fix sends answers to the wrong cloud account. → **Mitigation**: the acceptance criterion above exists specifically for this, and is written to fail rather than to pass.
*   **Risk**: a shared script change breaks unrelated proof pages. → **Mitigation**: the regression criterion.
*   **Open question**: where this session's misdirected pages actually went. The adversarial pass **removed the evidence that had closed this** without putting an answer in its place, so it is open rather than resolved. Not blocking, but it is an unresolved safety question on the same publish path.

#### Complexity & effort
*   **Effort**: L
*   **Complexity drivers**: four defects across two scripts and a client; a shared script with unrelated consumers; one safety trap where the obvious fix is worse than the defect.
*   **Label**: **measured**, and re-verified by an adversarial pass that strengthened rather than retracted every finding.

---

### `@engine/durable-ledger`: The ledger becomes the inheritance
**Tags**: #needs-coordinate

**State (2026-10-20, after the hand-over lane) — the storage choice is MADE and the row grammar is written; no reader is built.** *(measured — the files exist in the working tree.)*
*   **Storage**: one file named `LOOM_INHERITANCE.md` at the **sessions root**, templated by `engine/skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md`. Beside the dated session directories rather than inside one, because **a successor knows the root and does not know which predecessor to read** — the open question's real content was addressing, not persistence. Rewritten in place; the superseded copy appended to the handing-over session's log. No new tooling: a file, written by the conductor, read by its successor.
*   **The root is computed, and there is more than one of them.** The address is the parent of the active session directory — `engine session find` yields it, the hand-over payload already carries it as `sessionDir`, and it agrees with the engine's own `resolve_sessions_dir` (`engine/scripts/lib.sh`, which anchors to the nearest `.claude/` ancestor and nests under `$WORKSPACE`) whenever one root is in play. **It is not always one**: a resolver's answer and the root a session demonstrably writes into diverge under a symlinked `sessions/`, an artifact root on a shared drive, or a `$WORKSPACE` set for one process and not another, and a session directory of the same name can exist at both with different content while every path check exits 0 *(measured on this engine while closing the gap)*. So the ruling mirrors the ordered `SEARCH_PATHS` `engine/scripts/session.sh` already builds: **write** to the root you can prove and carry the absolute path in `requiredFiles`; **read** a preference-ordered candidate list; **report** a copy found at more than one root rather than merging them.
*   **Row kinds, one grammar**: 🧵 Threads · 🗳️ Boards · **📚 Docs owed** · 🔓 Open claims · ⚙️ Standing arrangements. The doc register is a **row kind here, not a second store** — a doc owed is another open-work row that must outlive the session, so one mechanism serves both.
*   **Authority resolved by hand-off rather than by two copies**: the session log's live blocks are authoritative while the session runs; from the moment the inheritance is written that file is authoritative for its rows and the log is history. The drift risk this chapter names is answered by there being one owner at a time.
*   **Loud failure given a mechanism**: a field the writer could not fill reads `UNKNOWN — <why>`, never blank, and a successor finding `UNKNOWN` in a field it needs stops and reports that row.
*   **The amendment is landed** in `loom/SKILL.md` as `¶INV_LOOM_PASS_ON_NEVER_DISCARD`, at the explicit-close path and in the Constraints list.
*   **Still owed**: a successor's claim-and-report demonstrated end to end — the rule exists, no conductor has executed it, and a gate that has not executed is not evidence. **The startup read is no longer owed as text**: Phase 0 of `loom/SKILL.md` now carries a `[MANDATORY]` inheritance intake gated by an `inheritanceRead` proof. See `@engine/groom-positions` for what remains of that chapter.

The thread ledger and the board rows live in the session log, which ends with the session — and under this design the session ends on purpose. **The ledger is what the next loom inherits**, so it has to outlive its writer. This chapter decides where it lives and what a row must carry to be resumable by a loom that never saw the wave.

#### Scope
*   **In scope**: the storage shape; what a resumable row carries; the amendment below.
*   **Out of scope**: replacing the session log, which remains the narrative record. This is about the rows a successor reads, not the story a human reads.
*   **Key files/components**: `engine/skills/loom/assets/TEMPLATE_LOOM_LOG.md` (where the rows are defined today) · `engine/skills/loom/SKILL.md` (the gate being amended) · a storage target, not yet chosen.

#### The amendment this forces
The Synthesis gate blocks wrap-up on an unread board, with a row closing by folding **at the next gate**. **A loom that hands over has no next gate.** So a handing-over loom must be *allowed* to close with an open board row — **provided the row is inherited and the next startup groom reads it.** Without this, the gate makes cyclicality impossible. The gate's intent is preserved: an unread board still cannot be *discarded*, only *passed on*.

#### Dependencies
*   **Depends on**: nothing.
*   **Blocks**: `@engine/groom-positions`, `@engine/loom-cycle`.
*   **Shared resources**: `loom/SKILL.md`.

#### Acceptance criteria
- [ ] A loom writes rows a successor can act on **without reading the predecessor's log**.
- [ ] A fresh loom reads them and reports what it inherited.
- [ ] A handing-over loom may close with an open board row; a loom that would **discard** one still cannot.
- [ ] An inherited row missing a field a successor needs **fails loudly** rather than being silently acted on.

#### Risks & open questions
*   **Risk**: rows become a second source of truth that drifts from the log. → **Mitigation**: the log is narrative, the rows are state; say which is authoritative in the template itself, as was already done once for the board handles.
*   **Settled**: **where the rows live** — a file at the sessions root, not the tracker and not a document the tracker points at. See the `State` line above for the choice and its reason; neither alternative was needed, because what a successor lacks is an address rather than a store.

#### Complexity & effort
*   **Effort**: M
*   **Complexity drivers**: the storage choice is genuinely open and has knock-on effects on every chapter that reads the inheritance.
*   **Label**: **inferred** — the mechanism follows from the disposable session; the storage shape is **proposed** at best, since it is not yet chosen.

---

### `@engine/groom-positions`: Ratify at the start, top up in the middle, preserve at the end
**Tags**: #needs-coordinate

**State (2026-10-20, after the doc-gaps lane) — the RATIFY position's READ half is built; its clustering half, TOP UP and PRESERVE are not.** *(measured — the step is in the working tree.)*
*   **Built**: `loom/SKILL.md` Phase 0 carries a `[MANDATORY]` inheritance intake — resolve the file at a computed root, re-measure the point-in-time readings before acting, claim rows, leave rows to their `owner`, refuse a row with `UNKNOWN` in a field it needs, and write the `## ♻️ Inheritance claimed` entry. Setup's proof list gains `inheritanceRead`, which clears on a no-file reading rather than on a skip. The *Rehydration* section routes to that same step, so the cold start and the resume share one mechanism.
*   **Deliberately not built, and why each**: RATIFY's **clustering** half, because of the factual correction below — `/groom` cannot take an arbitrary pile as input, so the startup step hands rows to the add-a-thread adjacency assessment instead and the sharper cut (clustering at startup, capture at the hand-off) is **still unresolved as a /groom change**. **PRESERVE**, because its mandatory-at-hand-off contract lives in `engine/skills/groom/SKILL.md`, and removing the selectivity sentence in `loom/SKILL.md` without the refusal that replaces it is half a mechanism. **TOP UP's governor**, because it rests on this chapter's own open question — whether a conductor can read its own remaining context reliably enough to be bounded by it — which is untouched.
*   **The selectivity sentence this chapter amends is cited by line in its ticket and the citation is wrong.** It reads at `loom/SKILL.md` **192** before this lane's edits; the ticket says 163 and a prior lane's correction said 165 then 167, neither of which reproduces. Cite the sentence — *"Be selective: a thread that surfaced nothing worth filing posts nothing"* — not the line.

**Shape revisited (2026-10-21) — the scope decision that forbids this skill is overruled, and the case against it is stronger than this chapter previously admitted.** *(decided by the operator; every figure measured.)*

`builds/ticketnorm_INTERROGATE.md:30` settled, under *Decisions taken*: *"Shape — extend `/loom`, do not fork it. Handbook-awareness goes into the existing `/loom`, `/ticket` and `/inbox-post`, which is where filing actually happens. One conductor; the Linear integration is a capability, not a second skill to keep in step."* Nothing argued against it, and `/groom` ran on regardless. The revisit is owed and is recorded here.

**The hardest fact first, because it argues for the opposite conclusion.** That decision was written 2026-10-20 at 12:36; the earliest datable mention of `/groom` anywhere is 19:01:25 the same day, six and a half hours later. *(measured: every stamped line mentioning `/groom` across the finch sessions root falls on 2026-10-20, and in the engine repo `git log -S'/groom'` reaches only that day's three commits while the same sweep for `threadId` reaches 2026-08-26 — so the absence is real rather than a blind search. `skills/groom/SKILL.md` is untracked, so git cannot date the file itself, and APFS birthtime dates a rewrite rather than a creation.)* So this is not a standing skill a later decision overlooked. It is a skill created **after** the decision that forbade it, by the same programme, with the decision never revisited — and *"a second skill to keep in step"* reaches it directly, since `/groom` drains a Linear inbox channel through an atom of its own.

**Overruled on two measured grounds.** The decision's subject was **handbook-awareness**, and that half was honoured rather than forked: `§CMD_READ_PROJECT_HANDBOOK` is present in all three skills it names, and no skill was created for it *(measured, with an invented name returning 0 so the search discriminates)*. And `/groom` does not conduct — it mints no lanes *(measured: `Agent(` and `subagent` both 0 in `skills/groom/SKILL.md`, against 130 for `topic`)*. It turns a drained pile into topics and hands them back, one topic per thread, and the conductor consumes that output. A producer the conductor reads is not a second conductor.

**The cost the decision was protecting is real and is now being paid.** `/groom` has three call sites in `loom/SKILL.md`, an atom of its own and a template, and every change to the conductor has to keep them in step.

**Falsifier.** If `/groom` starts conducting — dispatching its own lanes, keeping a ledger, or needing the partition logic — the decision wins and it folds back into `/loom`. The same if keeping the two in step costs more than one further chapter's worth of edits.

`/groom` runs at three positions in a loom's life, on three different inputs, for three different reasons. The middle one exists today and is incidental; the other two are new. Clustering itself does not change — `/groom` already turns a pile into topics and hands back one topic per thread even when a topic carries several tickets.

#### Scope
*   **Startup, cold — RATIFY.** Groom the inheritance: the candidate batch, plus drops that arrived in the gap, plus tickets others filed, plus **the operator's answers**, plus open ledger and board rows. **This is the only groom that can see the answers** — the candidate batch was composed before they existed — which is what makes it a distinct job rather than a repeat.
*   **Mid-loom, on freed capacity — TOP UP.** Pull more work in without closing. **Exists today** as the offer that reaches for `/groom` or the ticket picker when a loom has room; the change is to make it load-bearing and to **govern** it: bounded by the conductor's remaining context rather than by lane availability, and **preferring adjacency**, with unrelated topics written to the inheritance instead of loaded.
*   **Session end, hot — PRESERVE.** Groom the exhaust into the next candidate batch. **Mandatory** — an amendment, since groom-at-thread-end is offered today with explicit selectivity, and under a session that ends on purpose **that selectivity is the leak**.
*   **Out of scope**: a second clustering skill; changing how `/groom` clusters.
*   **Key files/components**: `engine/skills/loom/SKILL.md` (the three call sites) · `engine/skills/groom/SKILL.md` (the mandatory-at-hand-off contract).

#### Dependencies
*   **Depends on**: `@engine/durable-ledger` — preserve has nowhere to write without it.
*   **Blocks**: `@engine/loom-cycle`.
*   **Shared resources**: `loom/SKILL.md`.

#### Acceptance criteria
- [ ] A loom's hand-off groom runs **without being offered**, and a hand-off that skipped it is refused.
- [ ] A startup groom demonstrably folds in an operator answer that arrived after the batch was composed.
- [ ] Mid-loom top-up refuses a non-adjacent topic and writes it to the inheritance instead.
- [ ] Top-up stops on the conductor's context budget even while lanes sit idle.

#### Risks & open questions
*   **Risk**: mandatory harvesting turns every hand-off into a long ceremony, and conductors start handing over late to avoid it. → **Mitigation**: the cost criterion in the success list — a hand-off groom that is expensive is a design signal, not an acceptable cost.
*   **Open question**: how adjacency is judged. A conductor knows what context it holds; whether that is expressible as a rule or stays a judgment call is unresolved.

#### Complexity & effort
*   **Effort**: M
*   **Complexity drivers**: three call sites with different inputs; an invariant amendment; a governor that depends on the conductor knowing its own context budget.
*   **Falsifiers**: if a startup groom costs as much as a hand-off groom, the ratify/preserve split is wrong. If top-up routinely pulls non-adjacent topics, the adjacency rule does no work and this position collapses into startup.
*   **Label**: **proposed**, except the mid-loom position which is **measured** to exist today as an offer.

---

### `@engine/execution-shape`: The batching dial and the global slot budget
**Tags**: #needs-coordinate

**State (2026-10-21, after the integration lane) — the INTEGRATION step is specified; nothing else in this chapter is built, and the specification is unexercised.** *(measured — the sections are in the working tree.)* "Lanes land" now names a mechanism rather than a word: `skills/loom/SKILL.md` § *The wave boundary — integration* and `§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY` give it an owner (the conductor), a boundary (every lane of the wave landed or parked, none `running`), a base (the session branch, captured at Setup as a name and a sha), an order (landing order, first-landed first), a conflict answer (abort, and resume the **later lander** to resolve in its own tree) and a subject tree for the gate (`§INV_LOOM_GATE_RUNS_ON_THE_INTEGRATED_TREE`). **Still unbuilt**: the batching dial, worktree-per-lane, the global slot budget — and therefore the trigger for the merge itself, since two lanes sharing one tree produce no lane branch to merge. **Half of the integration step is reachable today and half is not, and that line matters**: the boundary, the suite-against-a-named-sha and the wave record work under one shared tree with an empty merge step; the merge, the ordering and the conflict hand-back cannot fire at all until lanes have their own trees. A skipped case asserts the unreachable half against the rule and **arms itself** when an Execution shape disposition appears (`skills/loom/assets/__tests__/wave-integration.test.sh`). **Two decisions inside the step are open and are named below rather than guessed.** **The acceptance checkboxes below are v1's plan, not the current state.**

How work is batched and where lanes run — a Setup disposition beside the existing ones — plus the concurrency budget nobody currently owns. **This chapter has no downstream dependents and is independently shippable**, which makes it the best starting point for something usable early.

#### Scope
*   **Test shape — default now.** Targeted tests per lane; the full suite **once per wave at the gate**, never per thread. *Measured here*, over 105 interleaved order-rotated runs: the same command spread 10.7s–102.0s (p50 21.5s, p90 58.1s), and **every** concurrency reduction measured worse — disabling file parallelism came in at 311.1s against a 40.4s baseline, nearly 8× — while a cache advertised as removing 57% of tracked time measured inside the noise band. A lane running the full suite per step is the dominant cost of a parallel run.
*   **Worktree-per-lane — default, gated on a local measurement.** Removes the file partition, the first-claim-wins brokering and next-wave deferral entirely, which is the conductor's most attention-expensive job. ⚠️ *Measured in another repository, **not** here*: dependencies 1.4G per tree, 392 of 517 worktrees carrying one, volume at 94%; cloning is correct-by-construction there because the workspace links are **relative** symlinks (verified with a planted marker read back through the link), and a real tree cloned in ~101s — metadata-bound, not size-bound.
*   **Integration — what "lanes land" means, and which tree the wave gate runs against.** The gate's subject is an assembled tree, and worktree-per-lane removes the thing that assembled it. ⚠️ **v1 adopted the worktree default and named no step that brings the trees back together.** Measured against v1, before this bullet existed: *merge*, *rebase*, and *branch* in the git sense (as opposed to a session directory name and a tracker project) occurred **zero** times across the whole document, against positive controls in the same invocation. *(measured — this bullet and the open question below are now the only places those words appear, which is the gap being closed rather than evidence it was not there.)* Two worktrees cannot share a branch, so each lane needs its own — and nothing here says who integrates them, onto what base, in what order, or what a lane whose integration conflicts does instead. Until that is specified, **"lanes land" is undefined and the once-per-wave suite has no subject tree.** That matters more than a gap usually would, because the once-per-wave economy is this chapter's **only locally-measured** claim: its measured half is contingent on an integrated tree that its unmeasured half removes. The file partition it retires was a *prevention* mechanism; a merge is a *detector*, and a better one — it finds real textual collisions at integration rather than predicted ones at allocation — but a detector with no owner runs nowhere.
    *   **🧭 The detector now has an owner (2026-10-21).** *The paragraph above is preserved as the gap it was; this names what fills it.* **Integration is a step in the loom's own body, owned by the conductor**, and `skills/loom/SKILL.md` § *The wave boundary — integration* is its normative text. **Who**: the conductor, which already holds the ledger, the lane list and the wave block, and is the only participant that can see every lane's branch at once — so `§INV_LOOM_COMPOSED_WRITES` carries one narrow named carve-out for the merge and nothing else. **When**: at the **wave boundary**, which this document's glossary had as a placeholder and the skill did not define at all — *measured: `wave` occurred twice in `loom/SKILL.md` before this landed, in the Run-length disposition's prose and in first-claim-wins' deferral clause, neither of them a boundary; the non-zero reading is its own control.* The boundary is every thread in the wave's fanned-out set landed or parked with none reading `running`, taken from `engine lane-stall --all`; it is **not** the loop gate, which fires on one thread landing and would merge a lane at a time — per-lane integration under the boundary's name. **Onto what base**: the session branch, **captured at Setup as a name and a sha**, because under worktree-per-lane the conductor's tree is not any lane's and a base read at integration time is a base guessed. **In what order**: landing order, first-landed first — already written down in each lane's `/snapshot` Outcome, and it makes the loser the **later lander**, so the loom keeps one precedence rule rather than acquiring a second alongside first-claim-wins. **What a conflicting lane does**: the conductor aborts, leaving the session branch at its exact pre-merge sha, and resumes the later lander with its branch, that sha and the conflicting paths; **the lane merges the session branch INTO its own branch and resolves there**, never the reverse, because shared ground the earlier lanes already landed on is not a resolution surface. **And the gate's subject**: the assembled tree, named by sha, after the last merge — never a lane's tree and never a partly-assembled one, which records `suite deferred` and runs nothing, since a green against an assembly nobody will ship is an unrun gate that reads as evidence. **The assembled wave is proposed as one pull request**, and merging `--no-ff` is load-bearing rather than cosmetic: the merge commit engages `/pr`'s own refusal to cherry-pick merge commits and forces the whole-branch path, so the declined per-lane PR is structurally unavailable instead of merely remembered. *(Measured in a throwaway repository by `skills/loom/assets/__tests__/wave-integration.test.sh`: `--no-ff` leaves two parents, a fast-forwardable merge without it leaves one, the abort restores the exact pre-merge sha, and `--diff-filter=U` names the collision.)* **⚠️ Unexercised, and the reason is structural rather than an omission**: the live collision strategy is *prevention*, so a conflict has never arisen here, and the thing that makes one possible — a tree per lane — is the rest of this chapter. **Two decisions inside the step are open and were deliberately not guessed**: what integrates when every lane is **cold** (resuming the loser is the whole conflict mechanism and it is unavailable once lanes have ended, which `engine lane-stall` cannot even detect because it answers state and never reachability — so the step **STOPS** and escalates), and whether a **per-wave integration branch** is needed after all, since onto-the-session-branch was chosen as the smallest change and a wave that integrates badly then lands on shared ground.
*   **Global slot budget.** *"Live lanes = shared slots"* holds inside one loom; across concurrent looms nobody owns the number, so several looms thrash one test queue and one tree.
*   **Out of scope**: making the test suite faster. Every remedy tried was falsified; this chapter routes around the cost rather than reducing it.
*   **Key files/components**: `engine/skills/loom/SKILL.md` (the disposition and the wave gate) · `engine/skills/loom/assets/LOOM_AGENT_DIRECTIONS.md` (what lanes are told).

#### Dependencies
*   **Depends on**: nothing. **Blocks**: nothing.
*   **Shared resources**: `loom/SKILL.md`.

#### Acceptance criteria
- [ ] A loom asks the batching question at Setup and records the answer with its other dispositions.
- [ ] Lanes are briefed to run targeted tests; the full suite runs once at the wave gate.
- [ ] With worktree-per-lane selected, lanes run in their own trees and the conductor performs **no** file-partition brokering.
- [ ] The live-lane cap is enforced across concurrent looms, not per loom — demonstrated with more than one loom running.
- [ ] The worktree default is **justified by a local measurement**, or it ships as opt-in.
- [ ] Under worktree-per-lane, **"lanes land" names a mechanism** rather than a word: who integrates, onto what base, in what order, and what a lane whose integration conflicts does instead. The wave gate runs against the tree that mechanism produces, named explicitly.
- [ ] The once-per-wave suite timing is **re-taken against that assembled tree**, or the test-shape default states that its measurement rests on the pre-worktree shape — the two defaults are not independently justified while one supplies the other's subject.

#### Risks & open questions
*   **Risk**: the worktree default is adopted on another repository's numbers and the local disk or link structure does not support it. → **Mitigation**: the acceptance criterion above; the default flips to opt-in if the measurement fails.
*   **Risk**: targeted-tests-per-lane lets a cross-cutting break through to the wave gate, where it is more expensive to attribute. → **Mitigation**: accepted deliberately — the gate still catches it, and the per-thread alternative is measured as the dominant cost.
*   **Open question**: where the global slot count lives, given it must be visible to looms that do not know about each other.
*   **Open question — what integrates when every lane is COLD.** Resuming the losing lane is the whole conflict mechanism, and it is unavailable once lanes have ended, which is the likely state at a session-end integration. **No fallback has been chosen**, and the step stops and escalates rather than inventing one. What would settle it: a decision between the conductor resolving the conflict itself (which contradicts the composed-writes carve-out's bound and puts the integrator in the position of authoring somebody else's change), a fresh lane briefed from the losing lane's LOG PATH (the `§INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID` shape, at the cost that the resolver did not write the code), and deferring the whole wave to the next session as an inherited row. **A detail that bears on the choice**: `engine lane-stall` cannot tell you a lane is cold — it answers state, never reachability — so whichever fallback is chosen, its trigger is a `SendMessage` attempt answering *no transcript found*, not a sweep reading.
*   **Open question — whether a per-wave integration branch is needed after all.** Integrating onto the session branch was chosen as the smallest change from current behaviour, and declined an integration branch. The cost of that choice: a wave that integrates badly lands on shared ground, where an integration branch would have made it discardable. What would settle it: the first wave that integrates red — whether backing a bad assembly out of the session branch is recoverable without destructive git, which is forbidden here. Until a wave has actually been integrated, the question has no evidence either way.
*   **Open question, narrowed rather than open**: whether integration is the conductor's job or a composed skill's. `¶INV_LOOM_COMPOSED_WRITES` forbids the conductor touching git directly, so a merge owner is `/snapshot` widened, a new composed step, or the lane itself before it hands back — and the constraint **rules the conductor out**, which narrows the design rather than leaving it free. Settle this before the worktree default ships, not after: a default whose landing step is unassigned fails at the first conflict, where it is most expensive.
*   **Risk**: the two defaults in this chapter are scored independently but are coupled — the targeted-tests-per-lane saving is banked at a gate that worktree-per-lane leaves without a tree. → **Mitigation**: the acceptance criteria above tie them together, so neither ships on the other's evidence.

#### Complexity & effort
*   **Effort**: M
*   **Complexity drivers**: cross-process coordination for the slot budget; a default resting on a measurement not yet taken here.
*   **Falsifier for the worktree default**: a local measurement of disk headroom and link structure. If the workspace links here are not relative, cloning is not correct-by-construction and the default must flip.
*   **Label**: test shape **measured here**; worktree figures **measured elsewhere and explicitly unverified locally**; slot budget **inferred**.

---

### `@engine/inbox-read-cmd`: Make the exclusion mechanical, and fix the live leak
**Tags**: #needs-coordinate

**State (2026-10-20, after v1) — done.** The command exists at `engine/.directives/commands/CMD_READ_INBOX_CHANNEL.md`, is registered in `.directives/COMMANDS.md`, both callers (`groom`, `intake`) cite it, `scripts/tests/test-inbox-read-cmd.sh` covers the exclusion, and the marker leak is closed — the command's own fence carries `⏳ marinating` and narrates the failure in the past tense. *(measured here, later than the review panel's read, with a positive control on the citation sweep.)* **The body below is v1's problem statement, preserved as history; the acceptance checkboxes are v1's plan, not the current state.** A lane sent here to build the command finds it built.

A shared command that reads an inbox channel and **excludes own comments by construction**, replacing a rule two skills must each remember. **No downstream dependents — independently shippable.**

#### Scope
*   **In scope**: the command; both callers converted; the live leak below.
*   **Out of scope**: placing the rule in a directives file. Both candidate homes were measured and rejected.
*   **Key files/components**: a new command under `engine/.directives/commands/` · `engine/skills/groom/SKILL.md` · `engine/skills/intake/SKILL.md`.

#### Why a command rather than a directive entry
*   **The always-preloaded home taxes every session.** `~/.claude/.directives` is a **symlink** to the engine's directives, and that invariants file is already 93,907 bytes and preloaded into *every* session — so a narrow inbox rule is paid for by all of them, on a page whose length is itself a candidate reason readers miss things in it. *(measured.)*
*   **The scoped home reaches the wrong audience.** Directives are discovered by walking up from directories a session **touches**. A groom run operates on the tracker and touches no skill directory, so a rule placed there reaches skill **authors**, not skill **runs**. *(measured.)*
*   **And an ungated rule is a preference** — established twice in the session that produced this vision. The pattern to follow already exists: several skills cite one handbook-reading command rather than each reimplementing the fetch.

#### The live leak — closed, see the State line above
As found: `/groom` posted a `⏳ marinating` reply and `/intake`'s filter did not drop it, so **those replies came back as fresh human feedback.** It had been parked as needing an owner's acceptance; it was a defect in flight rather than a pending proposal. *(measured.)* The command's fence now carries the marker and narrates this failure in the past tense, with a test that reddens when the fix is removed.

#### Dependencies
*   **Depends on**: nothing. **Blocks**: nothing.
*   **Shared resources**: the inbox rules and handbooks — shared with `@engine/ticket-carveout`.

#### Acceptance criteria
- [ ] One command reads an inbox channel and excludes own comments; **neither caller can read a channel without it.**
- [ ] A test plants an own-comment and asserts it is excluded — red before the command exists, green after.
- [ ] A `⏳ marinating` reply does **not** return as fresh feedback. Red-first against the live leak.
- [ ] Exactly one statement of the exclusion rule exists in the system — verified with a search and a positive control.

#### Risks & open questions
*   **Risk**: "own comment" is ambiguous when two skills post as the same actor. → **Mitigation**: resolve it in the command, which is the point of putting it there.
*   **Open question**: whether a marker vocabulary belongs in the command too, since the leak is really a marker both sides must agree on.

#### Complexity & effort
*   **Effort**: M
*   **Complexity drivers**: two callers to convert without changing their behaviour otherwise; a live defect to fix red-first.
*   **Label**: **measured** — both the placement objections and the leak.

---

### `@engine/direct-in-loom`: Vision as a durable artifact, chunks as tickets
**Tags**: #needs-coordinate

**State (2026-10-20, after the DIRECTRIDE lane) — the ride is DECLARED and the two flows are separated structurally; revision is still unexercised.** *(measured — the sections are in the working tree.)*
*   **The ride, named at the mechanism rather than as a risk.** `direct/SKILL.md` carries a `## Composed entry` section declaring `§INV_RIDE_NEVER_ACTIVATES`: a composed pass does **not execute `§CMD_EXECUTE_SKILL_PHASES` at all**, so there is no phase for it to transition and no change to how the host manages its own. What it would have collided with is a single field — `.state.json` is one file per session directory carrying one `skill`, one `taskType` and one `currentPhase`, and this host's read `{skill: loom, currentPhase: "1: Loom"}` while the lane ran.
*   **The flows no longer share a path, and neither carries a flag.** RECONCILE is deliberately **not a mode**, because a mode is chosen in Phase 0 and anything reachable only through Phase 0 is reachable only through the gated sequence — so it cannot acquire a gate. REVISE is Evolution mode and its phase proof gains `chapterDispositions`, which clears on a recorded per-chapter walk or on `n/a — no baseline`, never on a skip — so it cannot lose one. Their write surfaces are **disjoint**: reconciliation may correct a statement of fact, revision alone may change intent, and the revision walk excludes reconciliation-origin hunks because a walk gates whatever it shows.
*   🔴 **Box 2 below was ticked in error and is reverted to v1's plan.** Reconciliation's **flow** was gated when that box was ticked — the only path to the skill's reconciliation instruction ran through Phase 3's `AskUserQuestion` user approval — so § STATUS RECONCILIATION demonstrated the output *shape* and not the ungated *property* the invariant names; one ungated hand-edit says nothing about the flow. **And state belongs in this line, never in an acceptance box**: the convention is this document's own, so ticking the box put the state where the document tells a reader not to look for it.
*   **Still owed**: the call site in `loom/SKILL.md` (held by another lane while this ran — the text is specified in `builds/directride_BUILD.md`), the `destination` value the two register templates need, and a revision pass actually run.

`/direct` composable inside a loom: negotiate a vision, keep it live as execution deviates, decompose into chunks, let chunks earn tickets. This document is the pattern's own first instance — it was produced by a `/direct` pass riding a live loom session.

#### Scope
*   **In scope**: riding the host session rather than activating its own; **both** of the two flows below; the decomposition hand-off into chunks.
*   **Out of scope**: shredding a plan into a ticket per item.
*   **Key files/components**: `engine/skills/direct/SKILL.md` · `engine/skills/loom/SKILL.md` (the call site).

#### Two flows, not one — and only one of them is drift correction
These are distinct in trigger, direction and who initiates, and conflating them is why a vision goes stale in practice. Both are needed.
*   **RECONCILIATION — reality moved, the document did not.** Triggered by execution deviating: a chapter re-scoped mid-build, a dependency re-cut, a principle superseded by what was learned. Direction is *from the work back into the document*. Initiated by whoever noticed. Remedy: a dated reconciliation section appended, the original preserved as history, surgical edits only where the text is most wrong.
*   **REVISION — the operator changed their mind.** Triggered by a person wanting the direction itself different. Direction is *from the person into the document*. Remedy: load the current version as a baseline, write the next, and **walk the diff per chapter** so each change is accepted or rejected deliberately — a new chapter is marked for work, a materially changed one re-opens, a removed one is cleaned up or dismissed. `/direct`'s Evolution mode already implements this shape; **what it has never had is a baseline to diff against, because this document is the first one.**
*   **Why it matters that they are separate**: reconciliation must never require a decision (it records what already happened, and gating it is how the record goes unwritten), while revision must never happen without one (it changes the direction, and applying it silently is how a vision drifts from the person who owns it).

#### The guard
**The plan is the durable artifact; chunks earn tickets, not plan items.** `/ticket` already refuses a finding-as-ticket and caps an agent at one ticket per run unless a human asks for a split, so the filter exists — the risk is a many-item plan becoming many tickets.

#### Dependencies
*   **Depends on**: `@engine/ticket-carveout` — chunks cannot earn tickets before the carve-out exists.
*   **Blocks**: nothing.
*   **Shared resources**: `loom/SKILL.md`.

#### Acceptance criteria
- [ ] `/direct` runs inside a live loom **without activating its own session or transitioning the host's phase**.
- [ ] **Reconciliation**: a vision that execution has deviated from gets a dated reconciliation rather than silent staleness — and it lands **without** requiring anyone's decision.
- [ ] **Revision**: this document can be revised against itself as a baseline, with the diff walked per chapter and each change accepted or rejected — the capability exists and has never run, because until now there was no baseline.
- [ ] The two flows are **distinguishable in the document** — a reader can tell what changed because reality moved from what changed because a person decided.
- [ ] A decomposition produces chunks, and a plan item that is not a chunk **does not** become a ticket.

#### Risks & open questions
*   **Risk**: composing a protocol-tier skill inside another collides over session state. → **Mitigation**: the pattern is already proven once by this document; make it explicit rather than incidental.
*   **Risk**: the revision flow stays untested because nobody wants to be the first to diff the document that defines the work. → **Mitigation**: the first real change to this vision is the test; run it as a revision rather than hand-editing, even when hand-editing is quicker.
*   **Open question**: who reconciles a vision — the deviating loom, or a later `/direct` pass. Reconciliation needs no decision, so a loom could do it; revision needs one, so a loom must not.

#### Complexity & effort
*   **Effort**: M
*   **Complexity drivers**: two flows with opposite gating rules in one skill — reconciliation must not gate, revision must.
*   **Label**: **proposed**; the riding pattern is **measured** to work, once — this document. The revision flow is **proposed and unexercised**: `/direct`'s Evolution mode implements the shape but has never had a baseline to run against.

---

### `@engine/loom-cycle`: Two boundaries — the wave, and the hand-off
**Tags**: #needs-coordinate

**State (2026-10-20, after the hand-over lane) — the hand-off's CONTENT is specified; its trigger and the phase shape are not built.** *(measured — the section exists in `loom/SKILL.md`.)* What a conductor owes a successor is now written as a `### Dehydration and rehydration` section plus `¶INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID`: the rows, the live lanes **by LOG PATH rather than by agent id**, the forbidden brief forms each with a redirect, and the successor's first acts. It composes `§CMD_DEHYDRATE` and `§CMD_RESUME_SESSION` rather than restating them. **Still owed**: the conductor choosing its own moment (the open question below is untouched — the figure removes the discretion and still does not supply the self-knowledge), the wave/hand-off phase shape, and the end-to-end proof that an answer given in the gap changes what the next session does.

The spine. A loom is **multi-hop by nature** — threads iterate and deviate, so it runs many waves, topping up on adjacency as capacity frees. It ends by **handing over**, not by finishing the work. This chapter lands **last** because it composes the others.

#### Scope
*   **The wave boundary** — lanes land, capacity frees, the loom tops up and continues. Cheap, frequent, no ceremony. A board is **not** part of this boundary and would contradict *no ceremony* — `¶INV_LOOM_BOARD_AT_A_BOUNDARY` costs a board at a dispatched render subagent, an integrity pass, two publishes and a later fold, plus an obligation that blocks the close. A wave that cannot resolve a fork **rows it as an open claim and carries it**; the page is owed at the hand-off boundary, where the fork must survive into an inheritance a successor reads cold.
*   **The hand-off boundary** — near **~150K tokens** the conductor grooms its exhaust, writes the inheritance, and **recommends the close the operator still makes** (`¶INV_LOOM_NO_RUSH_TO_CLOSE`, and the amendment below). Deliberate, and the figure is the lane-level rule's own, so the two cannot drift apart. **Triggered by context rather than by work completion.** The hand-off is also where every open `🔓 Open claims` row crosses with a **pointer to its prepared decision card**, so a successor inherits a decidable fork rather than a re-asked question.
*   What a fresh loom does on startup, and how it knows which inheritance is its own.
*   **Out of scope**: letting the conductor ride to an unplanned dehydration, which is today's behaviour and is lossy. Also out: one session alive indefinitely across gaps.
*   **Key files/components**: `engine/skills/loom/SKILL.md` — the phase shape and both boundaries.

#### The amendment this forces
**`¶INV_LOOM_NO_RUSH_TO_CLOSE` forbids what this boundary does, and it says so at every entry point of the file this chapter edits.** The rule appears in the skill's `description` frontmatter, its opening overview, its own *No rush to close* section (*"A session ends only when you say so"*), the phase shape, the Loom phase's stated Not-this, the Loom body's loop sentence, the loop-gate heading, the gate's *Wrap up* exit, the Synthesis subtitle, and the Constraints list. *(measured — pattern, line numbers and positive control recorded in the lane log that wrote this block.)* A hand-off the conductor triggers off its own context is the conductor ending a session, which is the single act that rule reserves for the operator. v1 took the design decision and never named the rule.

**The amendment resolves it in the rule's direction, not this chapter's.** The conductor does not gain a close. It gains a *recommendation*: a spent context budget puts wrap-up on the gate card with that reason attached, the gate still defaults to keep-going, and the operator's explicit choice is still the only thing that ends the session. The one unprompted act is the opposite of closing — with an involuntary exit imminent, write the state and the inheritance **first**. That is the standard the same file already holds a lane to (`¶INV_LOOM_WAKES_ARE_THE_BILL`: cap a lane's context and hand back to a fresh one), so the shape is precedented one level down rather than invented here. Today's conductor rides to the hook and loses the ledger, and that is not an end the operator chose either — which is why the rule's intent is served by this amendment rather than bent by it.

**What the amendment does not license.** A mid-range context reading is not a trigger. `¶INV_CONTEXT_BUDGET` exists because agents misread a mid-range percentage as *getting full* and preemptively hand off, wasting a session with headroom left. So the threshold is **declared and numeric**: **~150K tokens**, the same figure the lane rule uses, one number governing both sides so neither drifts. Below it the gate behaves exactly as it does today, and whether the conductor may decide for itself this amendment answers **no**.

**What the figure governs, and what it does not.** It governs **when wrap-up appears on the gate card as a recommendation carrying its reason** — not when a conductor dehydrates. Those are different events, and conflating them is how an unnumbered rule misfired in the first place: recommending early costs a card the operator can decline, while riding to a hook costs the ledger. **Operator's call**, taken over an 80%-of-the-dehydration-point framing and over leaving it unnumbered.

**The shipped file is edited to match, and stays stricter than this chapter.** The *No rush to close* section and the Constraints entry now carry the figure and the recommend-don't-close distinction directly, so a conductor reading only the skill reaches the same answer as one reading this vision.

**The skill's `description` frontmatter does NOT need amending, and that is a finding rather than an omission.** It is one of the places the rule is asserted, and it is the first thing a model reads about the skill — so it was checked rather than assumed. Its claim is *"a persistent session that keeps a live status ledger and never rushes to close: add threads, adjust a thread, or wrap up"*, and every clause survives the amendment: the session still never rushes to close, because the conductor only ever **recommends**; and the three exits are unchanged, because the recommendation marks the existing *Wrap up* exit rather than adding a fourth. The same holds for the opening overview, which makes the same claim in the same words. The remaining statements describe the gate menu, where the operator still owns *Wrap up*, so they are all true unamended — **the amendment reaches two statements out of the eleven, and the other nine needed nothing.**

#### Dependencies
*   **Depends on**: `@engine/durable-ledger`, `@engine/decision-transport`, `@engine/groom-positions`.
*   **Blocks**: nothing — it is the last chapter.
*   **Shared resources**: `loom/SKILL.md`, shared with `groom-positions` and `execution-shape`.

#### Acceptance criteria
- [ ] A loom runs several waves, topping up, without closing.
- [ ] A loom hands over **on its own context budget**, and the hand-off writes a complete inheritance.
- [ ] A fresh loom starts from that inheritance alone and reports what it picked up.
- [ ] An operator answer given during the gap **changes what the next loom does** — the end-to-end proof that the cycle closed.
- [ ] A hand-off that would lose an open board row is refused.
- [ ] A lane that stops without handing back is **detected and rowed while the weave runs**, not discovered at the hand-off.
- [ ] A hand-off that would lose an open **claim** row is refused, and every claim it carries points at a prepared card.

#### Risks & open questions
*   **Risk**: the hand-off is described but never built, and conductors keep riding to an overflow. → **Mitigation**: the falsifier below, stated as an acceptance check rather than a hope.
*   **Risk**: a loom hands over with an inheritance a successor cannot use, and the failure is silent — the original problem in a new costume. → **Mitigation**: `durable-ledger`'s loud-failure criterion.
*   **Settled**: the threshold is **~150K tokens**, mirroring the lane rule so one number governs both sides. It is when the recommendation reaches the gate card, not when anything dehydrates. See the amendment above.
*   **Open question**: whether a conductor can read its own budget reliably enough to act on that figure. The number removes the discretion; it does not supply the self-knowledge, and this is the half that stays open. **Narrowed, not closed.** The self-knowledge problem has a second face the chapter did not separate: besides *am I full*, a conductor must know *is my weave still moving*, and the hand-off trigger depends on both. That second face is now **instrumented externally** — `engine lane-stall` reads lane liveness off the filesystem and exits 3 on a stale lane, so it does not depend on the conductor sensing anything, though it does depend on the instrument being right about what it can see, and tonight it was not, in both directions. The context-budget face stays open and unchanged: this instrument says nothing about token count. ⚠️ **It reports lane STATE, never reachability** — a dead lane's transcript persists on disk and reads `parked`, not gone.

#### Complexity & effort
*   **Effort**: L
*   **Complexity drivers**: it integrates every other chapter; the trigger depends on self-knowledge the conductor may not have.
*   **Falsifier**: if hand-offs in practice are triggered by a hook firing rather than by the conductor choosing its moment, the planned hand-off was described and not built.
*   **Label**: **proposed**; the disposable-session shape and the multi-hop lifecycle are both operator decisions on record.

---

## 🔄 STATUS RECONCILIATION (2026-10-20, same day as v1)

**Reconciliation, not revision** — this records what execution found, and by this document's own rule (`@engine/direct-in-loom`) it required no decision to land. The original text above is preserved as history; only the lines below are corrected. **Every item here was measured by a lane or by the conductor, and each says which.**

**The reason this section exists on the day the document was written** is the finding a review panel confirmed at MUST: the document's state goes stale behind a `measured` label, and **`measured` carries no timestamp**. Within four hours of v1 being written, four of its statements were false. That is not a slow drift; it is the rate.

**How to read a chapter's state — the structural half of this fix.** A chapter's acceptance checkboxes are **v1's plan, not its current state**; its `**State (…)**` line is. A chapter whose state has moved carries that line **directly under its tags**, so a lane learns the state where it reads rather than hundreds of lines later in this section — which is the defect a reconciliation section alone does not fix, since nobody scrolls to it before starting work. And a **recommendation** — what to start on, what blocks what, where the cheap win is — is corrected **in place** rather than left for this section, because unlike a measurement it cannot be a point-in-time snapshot and remain useful.

**Most of what is below has since been committed, and this paragraph said the opposite.** As written it read *"Nothing below is committed… the engine repository carries **no commit from today**, and this document is **untracked** — it has never been committed at all,"* citing an empty `git log --since` and a `??` from `git status --porcelain`. **Both readings have been overtaken.** *(measured by the DIRECTRIDE lane, each against a positive control in the same invocation — three commits carry today's date against 211 all-time, so the `--since` filter discriminates; this document is in `21f8ea4` and `577a910`, `git cat-file -e "HEAD:<path>"` succeeds where a planted nonexistent path errors, and `git status --porcelain` reads ` M`.)* The remaining divergence from the tip is small and attributable per hunk. **Landing facts and measured facts are still different kinds of claim and are still kept apart here on purpose** — and this paragraph is the sharpest case for that separation rather than a counter-example, because the stalest statement in the document was the one asserting its own landing state, inside the section whose whole job is to stop the document going stale. A landing fact ages the moment somebody commits; it cannot be left behind a `measured` label and trusted.

**Moved again after this section was first written.** `@engine/inbox-read-cmd` finished later the same afternoon — the command file, its registration, both callers and the test all post-date the review panel's read. *(measured.)* So this section is itself a snapshot, and the `**State**` lines on the chapters are the surface to trust over it.

### Factual corrections

*   🔴 **`@engine/decision-transport`'s key-files list names the wrong directory.** The board widget kit is in **`engine/skills/intake/assets/`**, not `prove/assets/`. *(Found by the transport lane while working the artifacts.)* **This error propagated**: the conductor derived a lane's file partition from this list, which put two lanes in one directory at once. They touched different files and nothing broke — by luck, not design. **A partition is derived from where files ARE, never from where a document says they are.**
*   🔴 **`@engine/durable-ledger`'s "three shipped answers" is wrong about at least one of them.** `prev_session_id` and `dehydration_payload` appear in **exactly one file** — `docs/SQLITE_DAEMON_VISION.md`, inside a `CREATE TABLE` sketch — with **zero** hits across every `.sh`, `.ts`, `.js` and `.json` in the engine (positive control: `dehydrate` found in three live hook scripts; negative control clean). **It is a proposed schema nobody built.** At least one of the three IS real — the session state file plus the dehydration command, exercised by this very session — so the honest statement is *one shipped mechanism and at least one paper one, conflated*. A lane told "three shipped answers exist" goes looking for code and finds a sketch.
*   🔴 **`@engine/ticket-carveout`'s premise was too broad: there are TWO gates, not one.** The carve-out clears the **conductor's** gate. It does **not** clear the filing skill's own Subject Gate, which is a separate floor admitting no override — every chunk still had to name its live instance. *(Found by the carve-out lane while filing.)* The chapter is correspondingly smaller than written.
*   🔴 **`@engine/groom-positions` assumed a capability `/groom` does not have.** Its drain is an **inbox adapter welded to its clusterer**, so it cannot take an arbitrary pile as input. *(Found independently by two review lenses.)* **The resolution is a sharper cut than the chapter's**: *clustering* belongs at startup, only *capture* belongs at the hand-off — so the hand-off never needed the clusterer at all.

### Chapters whose state has moved

*   **`@engine/decision-transport` is substantially done.** The full loop ran live: publish → a real presigned grant at the local store → POST 204 → fold → anonymous 200 carrying the vote. All four defects fixed plus a fifth. ⭐ **And the remedy was cheaper than the chapter claimed**: the store's anonymous grant is a **prefix** match, so nesting the state document *under* the publish prefix rather than beside it made it readable — **no bucket policy needed touching at all.** The chapter asserted the opposite.
*   **`@engine/ticket-carveout`** — the project exists, the clause landed in the rule and in all three handbooks, and all eight chapters are filed as tickets with their dependency graph intact. **Owed**: the rule is stated in five files and only one carries the clause, so it now disagrees with itself by entry point.
*   **`@engine/inbox-read-cmd`** — the command exists, both callers cite it, and the live marker leak is closed with a test that reddens when the fix is removed.

### Gaps this document does not cover, found by execution

*   🔴 **Four permanently-red test suites, and no chapter owns them.** By this document's own principle that a gate which has not executed is not evidence, **a permanently-red suite is that same problem with a louder voice** — a red nobody is accountable for is indistinguishable from a red nobody has seen.
*   🔴 **A decision board reveals the agent's recommendation for every item as soon as any one is answered** — the page-wide read gating the anti-anchoring reveal. Filed separately; it blocks the exposed pre-selected controls an operator asked for, because pre-filling any control would both emit a vote nobody cast and unblind the whole board.
*   🔴 **The kit's publish route contradicts itself.** `publish-kit.sh` documents republishing a versioned key as *"how a fix reaches existing boards"*, and its immutability gate refuses exactly that. Shipping a fix to already-published pages requires overriding the gate the script relies on.
*   ⚠️ **A skill the loop depends on exists in one project only.** The thread-end refill offer reaches for a picker that is not installed everywhere, so the refill leg silently loses a source depending on where the loom runs.
*   🔴 **No chapter covers keeping documentation true across the cycle, and the gap is now partly built rather than merely named.** A disposable session that hands over also hands over whatever it made the docs wrong about, and nothing in this document says who repairs that. The loom now carries a **standing documentation lane** fed batched on a landed thread, a `📚 Docs owed` register row kind in the inheritance, and `/revise` — a `/build`-shaped, dispatchable block that repairs the **located claims** one change falsified and is forbidden the tree-wide work (index reconciliation, sweeps, count audits, housing an undocumented change) that `/document` keeps because no single diff can scope it. **Un-ticketed**: this surface has no chunk and no acceptance in this document, so it is carried here rather than claimed as a chapter's state.
*   🔴 **Lane liveness had a working detector, no owner for ten days, and four defects — each of which returned a confident wrong answer.** `engine/scripts/lane-stall.sh` was written 2026-10-10 and, until 2026-10-20, was referenced in exactly one file — `skills/loom-experiment/assets/EXPERIMENT_DIRECTIONS.md:102` — and **nowhere in `skills/loom/`**, while `loom/SKILL.md` carried an uninstrumented *"poll agent status (silence past a timeout → probe)"* clause with no instrument and no number. *(Measured with a positive control in the same invocation: `ticket watch` reaches six files including `skills/loom/assets/`, so the search does reach the partition.)* **Toward FALSE CLEAN**: the lane test was `re.match`, so the bracketed tag had to be the first characters of the dispatch prompt, and every brief this loom wrote opened `You are thread NAME in a /loom run.` On the loom session `2026_09_16_KIT_UI_KERNEL` that is **24 lanes resolved from their spawn descriptions against 0 seen by the anchored test, reported as "no stale lanes" at exit 0**. ⛔ *A figure first recorded here — "61 lanes of one session, 0 seen" — was withdrawn on re-measurement: that session is an **intake** wave whose subagents are `/inbox-triage` runs, so reporting zero loom lanes there was correct, and its `.state.json` reads `skill: intake` at all three roots it exists under.* **Toward FALSE STALE**: line 45 globbed `<sessionDir>/*_LOG.md` non-recursively, discovering **1** log where a recursive walk finds **28**, 27 of them under `builds/` where every dispatched lane writes; and because `fresh = min(…)`, a dropped reading can only make a lane look staler than it is. **Toward CROSS-WEAVE THEFT**: the session-identity test was a bare substring match on the directory basename, so a new empty directory named `empty` claimed **7 lanes from six unrelated weaves at exit 3** — the word occurs in 2,073 of 12,594 transcripts, while `sessions/empty` occurs in 0. ⚠️ *The obvious remedy was rejected on measurement: requiring the absolute session path costs **326 of 596** lanes on one weave, trading one false clean for another; the parent-component-plus-name tail keeps 595 of 596.* **And upstream of all three, `engine log` disabled its own timestamp on exactly the headings this document's naming rule mandates** — its double-stamp guard skipped injection for any heading opening with a bracket, which `¶INV_LOOM_AGENTS_NAMED_BY_THREAD` requires every lane to write, leaving **15 of 28** lane logs with no timestamp for the detector to read. *Stated as a before-and-after rather than a rate, because the instrument changed mid-measurement: every bracket-opening heading lost its timestamp until the guard was tightened to require a `YYYY-MM-DD` date at 11:09:40 on 2026-10-21, and none has since. The repair is **not retroactive** — the logs written before that moment stay unstamped permanently, so a file-mtime fallback is the only thing that will ever date them.* **The reading no code can fix, now in the tool's own header**: `STALE` means a lane's last turn ended, which covers died, finished and waiting-on-the-conductor alike — three of the rows on the weave that found all this were threads that had **finished** the night before. By this document's own principle that an unexecuted gate is not evidence, a detector returning a confident wrong answer in any direction is the louder version of that gap. **The loom side is now wired, the prompt convention bound, and the regex, the glob and the guard all live in `scripts/` where no chapter owns them.**

### One correction to a correction

**A review panel reported that every chapter is tagged for a serial executor, and the conductor relayed it.** Both were wrong: the tag is the documented convention for chapters of this kind, and the cited invariant governs a monitor's decision loop rather than parallel execution. **The quotation was accurate; the reading of it was not** — recorded because an accurate quote supporting a wrong conclusion is the failure that survives every check for misquotation.

---

## Appendix: Evolution History

*   **v1** — 2026-10-20 — `sessions/2026_10_14_LAND_TREE_BRANCHES` — Initial vision. Greenfield, grounded in the skills as they stood. Two operator corrections during the pass reshaped it: decisions sync **through boards** with the transport fixed first (against the recommendation on record), and the lifecycle is **multi-hop** with a context-triggered hand-off rather than one wave per session.
