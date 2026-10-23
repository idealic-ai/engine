---
name: sweep
description: "Sweep ONE living loom for what it knows and has not rowed, while its context still exists: the decisions, owed docs, open forks, parked items and named-but-unfixed findings that sit in its log or in the conductor's head and appear in no register. Fires before a hand-over and on demand, never per gate (the loop gate runs `engine sweep-check`, the mechanical half, as a free cadence). The conductor sweeps its own live context inline; one dispatched read-only lane sweeps the files; neither claims the other's half. Writes `builds/sweep-findings.md`, which `/groom` reads as its source (d), and rows nothing, files nothing, ranks nothing, clusters nothing. Triggers: \"sweep the loom\", \"what haven't we rowed\", \"before I hand this over\", \"what does this loom know that nobody wrote down\", \"sweep\"."
version: 1.0
tier: lightweight
args: "[--session <dir>] [--files-only | --context-only]"
---

Find what this loom knows and has not rowed, hand it to `/groom` flat, and stop.

# /sweep Protocol (The Within-Loom Sweep)

[!!!] This is a **sessionless utility** skill that **rides the loom's session**. No session directory of its own, no debrief, no log of its own beyond entries in the loom's log. It reads sources that already exist and adds no durable store (`¶INV_SWEEP_ADDS_NO_STORE`). Its one output is `builds/sweep-findings.md`, a handoff artifact that `/groom` reads and that no register treats as state.

## What this is, what it is not, and who it is for

**For the conductor of a long-living loom**, at the moment its context is about to stop existing, or whenever it suspects the registers lag what it has decided.

*   **It is** the judgement half of a pair. The mechanical half is `engine sweep-check <logFile>`: a read-only script the loop gate runs as a cadence, exiting 3 when a `## 💡 Decision` heading has no register block written after it. The script answers one narrow, temporal question (*could this have been rowed at all?*) and cannot fail on anything it has no pattern for. This skill answers the wide one.
*   **It is NOT per-gate.** A skill fired every few minutes loads this file over a growing log each time, which is the cost shape `/loom` refuses by name for its weave-status page and the reason the stall sweep is a script. If the gate needs a mechanical answer, it runs the script; it does not invoke this skill.
*   **It is NOT an archive harvest and NOT a reconstruction.** The subject is one living loom's own registers, its own files and the conductor's own live context. Another session's debriefs, `builds/LESSONS.md` of other sessions and the intake inbox are `/groom`'s sources.
*   **It rows nothing and files nothing** (`¶INV_SWEEP_REPORTS_AND_HANDS_OVER`). The conductor rows (`¶INV_LOOM_COMPOSED_WRITES`), `/ticket` files under its own confirm, the loom dispatches.
*   **It ranks nothing and clusters nothing** (`¶INV_SWEEP_CLUSTERS_NOTHING`). Two findings that plainly belong together are handed over as two rows; `/groom` rejoins them, in the one place that clusters.

## Boundary, in both directions

Stated here and in `skills/groom/SKILL.md` and `skills/next/SKILL.md`, because a neighbour named in one direction only is the failure that left `/groom` mentioning `/inbox-next` seventeen times and `/inbox-next` never mentioning `/groom`.

*   **`/sweep` vs `/groom`.** `/sweep` finds what one loom has not written down and writes `builds/sweep-findings.md`. `/groom` reads that file as source (d), clusters its rows with the inbox, the open tickets and the leftovers, and disposes each topic once as `graduate` (a ticket via `/ticket`) or `dispatch` (a thread). This skill never disposes; `/groom` never sweeps a loom's log.
*   **`/sweep` vs `/next`.** `/next` reads a loom's state (stalled lanes, open forks, a dirty tree) and orders the moves that advance it. `/sweep` reads for the unrowed. Neither runs the other; `/next` may offer this skill before a hand-over.
*   **`/sweep` vs `/inbox-next`.** `/inbox-next` ranks open tickets and routes a pick. `/sweep` touches no ticket and ranks nothing.
*   **`/sweep` vs the synthesis commands** (`§CMD_REPORT_LEFTOVER_WORK`, `§CMD_CAPTURE_SIDE_DISCOVERIES`, `§CMD_SURFACE_OPPORTUNITIES`). Those run at synthesis or close and print to chat. This skill runs while the loom is alive and writes a file.

## When it fires

*   **Mandatory before a hand-over.** Before the conductor writes `LOOM_INHERITANCE.md` or dehydrates, because that is the last moment the live-context half exists. A hand-over written without it carries only what was rowed.
*   **On demand**, whenever the operator or the conductor asks.
*   **Never at a loop gate.** The gate's cadence is `engine sweep-check`.

## Algorithm

### 1. Locate the loom

The session directory is the active session's, or `--session`. The log is `<sessionDir>/LOOM_LOG.md`; findings go to `<sessionDir>/builds/sweep-findings.md`. If there is no loom log, say so and stop; there is nothing to sweep and this skill invents no subject.

### 2. Run the mechanical half first

`engine sweep-check "<logFile>" --all`. Read the exit status directly, never through a pipeline. Exit 3 is a finding, exit 2 is an instrument fault and is reported as such.

**Read its output as an input, not as findings, and at its true size.** The key is ordering and nothing else: a decision with no register block written after it is `UNROWED` (it cannot have been rowed, so that verdict is certain), and a decision that a register write followed is `FOLLOWED`. `FOLLOWED` is a superset and not a claim that the decision was rowed: the later write may not mention it, and a Ledger rewrite after a decision clears it whatever the rewrite says. The check compares no content (names, ids, words), because a content key matched a thread name rather than the decision and was wrong on half of its verdicts. So exit 0 means *no decision is certainly unrowed*, never *every decision was rowed*, and the `FOLLOWED` ones are where this skill's own reading starts: open the latest register blocks and check the decisions near them by hand.

Two recall limits belong in the findings header. The decision pattern recognises a heading whose first word is `Decision` or `Decisions` (after a stamp, `[TAG]` prefixes and glyphs), so a heading like `💡 FOUR DECISIONS` is not counted; the script prints how many other headings mention the word mid-heading. And a conductor that appends a short Ledger update rather than rewriting the block makes every earlier decision read `FOLLOWED`.

### 3. The context half, inline, by the conductor

Only the conductor can see the conductor's context, and a dispatched lane starts fresh, so this half is not delegated. List what you know that is in no register: a decision made in chat, a fork the operator has not answered, a doc claim you saw falsified, a thing you parked, a defect you named and did not fix. Each row is marked `Half: context`.

This half is judgement with no mechanism behind it and is only as good as honesty in the moment. Say so in the findings file's header. Do not pad it from the log: whatever is in the log belongs to the other half.

### 4. The files half, by one dispatched lane

Dispatch **one** read-only lane (a `/probe`, or a write-capable agent type such as `analyzer` or `general-purpose`) named by thread per `¶INV_LOOM_AGENTS_NAMED_BY_THREAD`, with a brief that carries the absolute log path and the `builds/` directory, and asks it to list items the loom's own files name and leave unrowed: `Named, not fixed` sections, `Rows owed` blocks, open questions in build and critique reports. The lane starts with no context, so the brief states the subject and the output row shape. It writes its answer to a file under `builds/` (`¶INV_A_PROBE_WRITES_ITS_ANSWER_DOWN`), by path. Rows from it are marked `Half: files`.

⛔ **Not an `Explore` agent**, although the work is read-only and the name fits — and the reason is not that it cannot write. `Explore` carries no `Write`/`Edit` tool but **does carry `Bash`**, so a brief mandating a file write is executable there by shell redirection. What goes wrong is the brief's wording: a demand phrased as a *tool* invites a lane to read its own tool set as a refusal, and a lane did exactly that rather than reaching for the shell — one confirmed instance, with two more lanes recorded as hitting the same brief shape and not re-checked for what they concluded. Name a write-capable type, and name the **outcome** — *your answer exists at this absolute path when you finish* — so there is no tool-set inference left to make. *Read-only* here describes what the lane does to the repo, not the tools it is given. **Measured**: a lane briefed this way concluded it could not write, and its findings had to be transcribed by hand out of the conductor's context; the file it was asked for carries a header saying the conductor wrote it because the lane could not — a record of what the lane concluded, not of what was possible.

The lane does not claim to know the conductor's context and the conductor does not re-derive the lane's file reading.

### 5. Write `builds/sweep-findings.md`

Append one dated section per run. The row shape is declared here:

```
## Sweep <YYYY-MM-DD HH:MM:SS> — <loom directory name>

*   **<the finding, one line>**
    *   **Loom**: <session directory name>
    *   **Half**: files | context
    *   **Kind**: unrowed decision | owed doc | open fork | parked | named-not-fixed | other
    *   **Source**: <path:line in the log or a builds file | context>
    *   **Seen at**: <YYYY-MM-DD HH:MM:SS>
```

Rows are listed in source order and carry no priority, grouping or recommendation. A reader of the file after a context clear must be able to act on every row from its own text, so each finding names the located thing, not "the earlier decision".

`/groom` reads the **latest** `## Sweep` section only, since each run re-reads the whole loom.

### 6. Hand over, then stop

Report the number of rows per half, the path, and any reading of step 2 that was an instrument fault. **Offer `/groom`** at that point (`§INV_OFFER_DONT_FORCE_SKILLS`); do not invoke it, do not row, do not file, do not dispatch.

## Constraints

*   **`¶INV_SWEEP_CHECK_CAN_FAIL`**: the mechanical half is read-only and fails by exit status. A check that only prints is the failure of the four layers this skill sits beside.
*   **`¶INV_SWEEP_LATEST_BLOCK_ONLY`**: the log is append-only, so a register block's heading recurs on every rewrite and only the latest occurrence is current state. Reading older occurrences reports history as the present.
*   **`¶INV_SWEEP_REPORTS_AND_HANDS_OVER`**: this skill writes no register row, opens no ticket and dispatches no thread other than its one read-only file lane.
*   **`¶INV_SWEEP_CLUSTERS_NOTHING`**: findings are handed over flat; `¶INV_GROOM_TOPIC_IS_THE_UNIT` and `¶INV_NEXT_BORROWS_THE_GROUPING` keep clustering in one place.
*   **`¶INV_SWEEP_ADDS_NO_STORE`**: no sidecar "already swept" record, no watermark, no marker list. `builds/sweep-findings.md` is a handoff, rewritten in meaning on every run, and the registers stay authoritative.
*   **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file.

## Notes

*   Every figure taken from a live log is stale by the next write to it. Timestamp each one and expect to invalidate your own reading; `engine sweep-check` prints its reading time and the line numbers it used for that reason.
*   The mechanical half answers whether a row could exist, not whether one does. When it and your own reading of the register disagree, your reading wins and the disagreement is worth a line in the findings header.
