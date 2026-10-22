---
name: inbox-next
description: "Pick what to work on next in a Linear project: runs `engine project next` (open work ranked milestone→priority→blocked, with per-ticket estimate + the exact Linear relation clusters), then a two-round pick — round 1 chooses a STRATEGY (start one · bunch small things · take a bigger task · brainstorm a cluster · create tickets from leftovers), round 2 shows the matching options — and ROUTES it (→/implement, /fix, /brainstorm, /ticket) or reads. Also graduates un-ticketed session leftovers (debriefs · /snapshot comments · LESSONS) into tickets via /ticket, closing the loop. Read-only toward Linear; it proposes and routes, never transitions/assigns/starts on its own. Works on any project despite the name. **It owns `pick my next ticket` in that phrase's narrow sense — one ranked item, asked for as one item.** The front-door phrases *what's next*, *what should I work on*, *what is blocking me* and *where did we leave off* belong to `/next`, which reads what state the work is in and routes blocking-first, because the honest answer to them is often not a ticket at all; the batched framing — *what is open here*, *batch up the related tickets* — belongs to `/groom`, which composes this skill for its ranking. Triggers: \"pick my next ticket\", \"next task here\", \"show me the cluster\", \"bunch up small things\", \"file my leftovers\", \"inbox-next\"."
version: 1.0
tier: lightweight
args: "[project] [--query <text>] [--tickets K1,K2] [free-text hint]"
---

Pick what to work on next in a project — surface `engine project next`, then decide and route.

# /inbox-next Protocol (The Next-Task Picker)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It boots, runs the CLI, asks what to do, and routes — same pattern as `/inbox-post` and `/session`.

## What it does (and does not)

*   **It does**: run `engine project next` (read-only), surface the ranked open work + per-ticket effort (`estimate`) + the exact Linear relation clusters, run a **two-round pick** (round 1 = strategy, round 2 = matching options with a loop-back), and **route** the choice to the right skill (`/implement`, `/fix`, `/brainstorm`, `/ticket`) or a read path. One strategy is **create-from-leftovers** — gathering un-ticketed session followups (debriefs · `/snapshot` comments · `LESSONS.md`) and graduating the picked ones into tickets via `/ticket`.
*   **It does NOT**: transition, assign, branch, or otherwise **mutate Linear** — the design deliberately rejected auto-start. Starting work is the user's explicit pick, executed by the target skill; filing a leftover goes through `/ticket`, which the user drives. It never re-implements ranking (that's the CLI) and never re-investigates a ticket beyond a read.
*   **Scope**: generic — works on **any** project (the CLI excludes inbox-channel container tickets and surfaces real work). The `inbox-` name is intake-family framing, not a scope limit.

## Siblings — and when the question is bigger than a ticket

This skill picks **one ticket for one person at one moment**. Two skills sit above it and both compose it rather than re-deriving its ranking, so a reader who arrived here first is told where they are:

*   **`/groom`** answers *what is the batched shape of everything open here* — it drains the intake inbox, the open tickets and the un-ticketed leftovers, clusters them into topics **across** all of those, disposes each topic once, and hands each to a loom as one thread. It composes this skill for the ranking, the relation clusters and the leftover gather. Reach for it when several related items should ride one worker instead of being picked one at a time. `skills/groom/SKILL.md:20` states the boundary and its reason: two skills that both answered *"what should I work on"* with rankings of their own would drift apart, which is the failure that composition designs out.
*   **`/next`** answers *what is in the way* — it reads the states that block a return (a lane that stopped without handing back, an unanswered fork or an unread decision board, uncommitted work or a wave nobody brought back together, then groomable work) and proposes the one move that clears the nearest, blocking-first. Reach for it when the honest answer to *"what now"* may not be a ticket at all. It hands down to this skill whenever nothing is blocking.

### Who owns which words

The three questions are asked in phrases that do not separate them, so the phrases are allocated here rather than left to whichever file the reader opened first:

*   **This skill owns `pick my next ticket`**, in that phrase's narrow sense — one ranked item out of a project's open work, asked for as one item. *"next task here"*, *"show me the cluster"*, *"bunch up small things"* and *"file my leftovers"* are its too.
*   **`/next` owns the front door** — *"what's next"*, *"what should I work on"*, *"what is blocking me"*, *"where did we leave off"*.
*   **`/groom` owns the batched framing** — *"what is open here"*, *"batch up the related tickets"*.

**The front-door phrases used to be this skill's, and moving them was a decision rather than a tidy-up.** `/next` is the only one of the three that can answer the question *wrongly asked*: someone typing *what's next* when the real obstacle is a lane that stopped without handing back, an unanswered fork, or finished work sitting uncommitted gets routed to the obstacle rather than handed a ticket to start. This skill is right about the question it was asked and has no way to tell that it was the wrong one — the ranking is sound and the premise is not. So the wider question takes the words, and hands down to here the moment it finds the way clear.

**Nothing above changes this skill's behaviour**: the ranking, the two-round pick and the routing are unchanged, and an ask that reaches here still gets the pick it asked for. This section exists so the composition and the allocation are both legible from the composed end and not only from the composing one.

## Requirements

*   `engine project next` (in `~/.claude/engine/scripts/project.sh`) + `LINEAR_API_KEY` (env or `.env`). No key → the CLI fails; report it and suggest setting the key. No project resolvable (no arg, no branch ticket key) → say so and ask for a project.
*   Linear MCP for the read path (`§CMD_READ_RELATED_TICKET`); load schemas on demand (ToolSearch `linear`).
*   **The issue-key prefix comes from the project's CLAUDE.md `## Tracker` block** — `<PREFIX>` uppercase for keys (`<PREFIX>-NNNN`), its lowercase form for branches (`<prefix>-NNNN-…`). Resolve it before reading a branch for a ticket key or writing a key into a prompt; do not assume a particular prefix. **No `## Tracker` block** → detect an uppercase-alpha prefix + `-NNNN` from the branch/slug/conversation at lower confidence. The config is never a hard requirement; absent it, degrade to detection rather than erroring.

## Algorithm

### 1. Resolve + fetch
Parse args: a bare positional non-flag = `<project>` (else the CLI infers it from the branch's ticket key); `--query <text>` and any **bare free-text hint** become the `--query` seed; `--tickets K1,K2` passes through as the relation anchor. Then run — read-only:
```bash
engine project next <project?> [--query "<seed>"] [--tickets <keys>] --json --limit 8
```
Capture the JSON envelope `{project, degraded, importance[], adjacency[], linked[], overlap[]}`. Each `importance`/`adjacency` row carries its own linkage keys (`relatedTo`, `parent`, `blocks`, `blockedBy`, `duplicateOf`); `linked[]` (present only with `--tickets`) is the resolved relation cluster — each row `{identifier, title, state, project, relation, anchor}`. On CLI failure, surface stderr and stop (see Requirements).

### 2. Surface
Present a compact read (NOT a table — `¶INV_LISTS_INSTEAD_OF_TABLES`):
*   **Importance** — top rows as `[KEY] title · <priority> · <milestone> · <workType>` + `· ~<estimate>pt` when `estimate` is set, marking `blocked` and `★` (overlap). If `degraded:true`, note "priority-ranked (no milestones here)". (`next` already drops In-Progress — a `started`-type state — from the queue; the envelope's `excludedInProgress` count says how many, mention it if non-zero.)
*   **Effort spread** — every row now carries `estimate` (story points; `null` = unsized). Note the split — a cluster of small items vs a couple of big ones — because it feeds the strategy pick in step 3 ("bunch small things" vs "take a bigger task").
*   **Adjacency** (if `--query`) and **Linked clusters** (if `--tickets`) — grouped, cross-project tagged.
*   **Cluster hints** — where an importance row has a non-empty `relatedTo`, note `↔ N related` so the user sees which items form neighborhoods worth batching.

### 3. Round 1 — pick a strategy (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`)
Don't jump straight to one ticket — first ask **how** the user wants to attack the work; the strategy shapes what round 2 shows. One `AskUserQuestion` (body carries the surfaced list + effort spread):
*   **Start one** — begin a single ticket (feature → `/implement`, bug-`workType` → `/fix`).
*   **Bunch up a few small things** — batch several low-effort items into one sitting (uses `estimate`; small = low points, `null`/unsized folded in last).
*   **Take on a bigger task** — the highest-`estimate` item(s), one at a time.
*   **Brainstorm a related cluster** — a `relatedTo` neighborhood thought through jointly (→ one `/brainstorm`).
*   **Create tickets from leftovers** — graduate un-ticketed session followups into real tickets (step 3b).
*   **Read one** / **Re-query** — inspect a ticket (`§CMD_READ_RELATED_TICKET`), or re-rank with a new `--query`/`--tickets`.

### 3a. Round 2 — the matching options (always with a loop-back)
Present the option set for the chosen strategy. **Every round-2 body carries a `↩ back to strategy` option** — re-enter round 1, *including* re-deciding ticket creation — so the user can change tack without restarting:
*   **Start one** → single-select the ranked list → route (step 4).
*   **Bunch small things** → `multiSelect: true` over the low-effort set (sorted by `estimate` asc, `null` last) → apply ONE action to the bundle: start them in sequence · `/brainstorm` them · read all · defer.
*   **Take a bigger task** → single-select from the top-`estimate` items → `/implement`|`/fix`.
*   **Brainstorm a cluster** → confirm the neighborhood (offer "expand to `<KEY>`'s cluster" via `--tickets <KEY>`, taking `<KEY>` from a surfaced row rather than composing one) → one `/brainstorm`.
*   **Create tickets from leftovers** → step 3b.

### 3b. Create from leftovers (the loop-closing strategy)
Surface un-ticketed session followups so they become trackable, then multi-select which to file. **Read-only toward Linear** — this routes to `/ticket`; it never files directly.
*   **Gather from three sources, scoped to the resolved project** (match by the project's ticket-key prefix / project name):
    1.  **Debriefs** — the `## Leftovers` / `## Next Steps` sections of recent session debriefs (`sessions/*/{IMPLEMENTATION,FIX,DO,ANALYSIS}.md`; bound to recent by mtime; grep only those sections, not whole bodies).
    2.  **/snapshot comments** — the "Leftovers & followups" block of `/snapshot` comments on the project's tickets (a bounded Linear read via `§CMD_READ_RELATED_TICKET` / a comment scan).
    3.  **LESSONS** — leftover bullets in recent sessions' `builds/LESSONS.md`.
*   **De-dupe** against open tickets — drop a leftover whose text already matches an open ticket title (surfaced by the `engine project next` list), so nothing gets double-filed.
*   **Present as `multiSelect: true` candidates** (each: the leftover text + its source pointer). For each selected → `Skill(ticket, args: "<leftover text + source + project>")` — `/ticket` owns the premise-first drafting, calibration, and filing.
*   Nothing files without the user's explicit multi-select pick; unpicked leftovers just drop from this pass.

### 4. Route / execute (never mutate Linear)
Execute the choice via the Skill tool or the read path:
*   Start work → `Skill(implement | fix, args: "<KEY> — <title>")`.
*   Small-batch bundle → sequence the starts, or `Skill(brainstorm, …)`, or read/defer the set.
*   `/brainstorm` a cluster → `Skill(brainstorm, args: "<the selected keys + titles + why they cluster>")`.
*   Leftover → ticket → `Skill(ticket, args: "<leftover + source + project>")`, once per selected leftover.
*   Read → `§CMD_READ_RELATED_TICKET` per key (bounded).
*   Defer / re-query / `↩ back to strategy` → drop, loop to step 1, or re-enter round 1.
*   **Never** call `save_issue`/`save_comment` or any status/assignee/branch mutation — routing hands the work to a skill the user chose; this skill only proposes. Filing a leftover goes **through `/ticket`** (which the user drives), so even the create path leaves this skill write-free toward Linear.

### 5. Report
One terse line of what was routed / filed-via-`/ticket` / read / deferred (and which skill(s) launched, if any), then **stop**. Handing further work to `/implement` / `/fix` / `/brainstorm` / `/ticket` is the routed skill's job, not this one's.

## Notes

*   **Advisory, not an executor.** The whole point of the CLI + this picker is to *propose*; the user's pick is what acts. Two actors, one write — never both in this skill.
*   **Pairs with the close loop.** `/snapshot`'s closing snapshot already surfaces `engine project next` after a ticket goes Done; `/inbox-next` is the same suggestion, run on demand and made actionable.
*   **Cluster-batching is the high-value move**, and how much it is worth depends on the project. Where tickets are richly wired via `relatedTo`, a related cluster is usually one decision, so batching it into a single `/brainstorm` (or reading it whole) beats picking tickets one at a time. Where the rows carry few relations, the clusters will be thin and the effort axis is the one that pays — say which you are looking at rather than promising neighborhoods that are not there.
*   **Close the loop with leftovers.** The picker only ranks *filed* tickets, so a followup noted in a session but never filed is invisible to it and falls on the floor. The **create-from-leftovers** strategy is the fix: it graduates un-ticketed session followups (debrief `## Leftovers`/`## Next Steps`, `/snapshot` "Leftovers & followups" comments, `LESSONS.md`) into real tickets via `/ticket`, so next time they rank. `/inbox-next` becomes able to *create* next work, not only pick from what's already there.
*   **Strategy before ticket.** Round 1 picks *how* to attack (bundle small wins · one big task · a cluster · file leftovers) before round 2 shows *which* — matching how people actually decide, and making effort (`estimate`) a first-class axis, not just priority.
