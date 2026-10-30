---
name: ask-council
description: "Batch council pass over the asks waiting on the operator: read the open asks and the per-ask council requests, group them by topic, file ONE operator-reserved ask proposing which council or scrutinize sets to run (topic, angle, size), run only what the operator approved, publish each council report to the proof store, and attach each panel's per-fork reads to the asks it covered with `engine ask attach-panel` — so the reads show beside the options on the ask page. Director-run on a cadence. Spends nothing before the plan is answered. Triggers: \"council the open asks\", \"groom asks for counciling\", \"batch councils on the questions\", \"ask-council\", \"which asks need a panel\"."
version: 1.0
tier: protocol
args: "[--seat <S>] [--to <T>] [--min-group 2] [--max-sets 4] [--dry-run]"
---

The operator asked for this twice. First, on meta:utils/20261029-133853 (CNCL=SKIL, ANGL=all four): read the open asks together, group them by topic, and post one ask proposing councils, so a panel costs one run per topic instead of one per question. Second, at 21:39, the panel's results must show **on the ask page next to each option**, not only as a linked board. The ticket is IDE-338. The operator then answered meta:engine/20261030-103346: reads go on with an append-only `engine ask attach-panel` any panel runner may use (ATTACH); the first version runs critique, design-off and refute-the-lean (ANGLES); a /scrutinize set counts as a set this pass can propose (SCRUT).

This skill composes `/council` (and `/scrutinize`), `engine ask`, and the proof store. It never answers an ask, never edits an ask's question or options, and never spends a panel the operator did not approve.

# /ask-council Protocol

## 0. Who runs it, and when

The director runs it from its loop gate. The cadence is the director's choice; once per working block is the intended rate. Any seat may run it with `--seat`/`--to` to cover only its own subtree. `--dry-run` stops after §2 and prints the grouping. It files nothing.

## 1. Gather — what could use a panel

```bash
engine ask list --status open --json          # every open ask, all seats (narrow with --seat / --to)
```

Parse each with its file (the `file` field). Collect two kinds of candidate:
- **Open asks** with at least one choice fork (`Choose one`, `Choose`, `Rank`). A `Text`/`Number`/`Date`-only ask has no options for a panel to read, so drop it.
- **Per-ask requests**: an answer, draft or follow-up whose note or `.other` text starts with `request: council:<angle>` or `request: scrutinize`. The ask app's Request menu writes these (tools/ask-app/src/client/loop.ts). The app's menu also offers `council:ideas`, which this version does not run: list such a request in the plan as not available and propose critique or design-off for it instead. This is the per-ask route meta:utils' draft asked for, so a request skips grouping and becomes its own set with the angle it named, unless a group in §2 already covers that ask with that angle.

Drop an ask that already has `Panel:` reads on every choice fork (`questions[i].panel.length > 0` in the parse), unless a request names a different angle. Drop an ask whose `reserved-for` or `neededBy` passes before a council could return (a council run takes about 10–20 minutes; say so in the plan if the margin is thin).

## 2. Group — one panel per topic, not per question

Cluster the candidates. Use this order and stop at the first rule that places an ask:
1. The same `topic:` header value, compared case-folded after trimming.
2. Shared `tickets:` keys.
3. The same `related:` ask, or a `dependsOn:` between them.
4. Your own reading of the forks' titles and Context. When you place an ask by reading, say so in the plan ("grouped by reading, no shared field").

A group of one is fine when the ask is weighty, meaning a high `importance` or a `reserved-for: operator`. Otherwise, a group smaller than `--min-group` waits for the next pass, and the plan lists it under "waiting for company". Cap the plan at `--max-sets` sets. Rank the sets by what deciding them unblocks (`unblocks:`/`blocks:`), then by age.

For each set, choose its **kind and angle**:
- **critique** is the default.
- **refute** fits a set whose forks carry a confident `Lean:`. It is refused for a fork with no lean.
- **design-off** fits an open design question.
- **scrutinize** fits a set whose asks are about finished work (a landed change, a report, a PR), where the question is "is this right" rather than "which option".

Choose the **size** with /council's `--size`: 3 by default, 5 for a set reserved for the operator or touching two lanes, 1 for a lone ask with a cheap question. The angle prompts live in `skills/council/assets/ANGLES.md`.

## 3. Propose — ONE ask, reserved for the operator, before anything spends

File exactly one ask. Each set is one `Choose` fork, multi-select, so the operator can approve a set with a different angle than the one you proposed. Pick a fork key that names the set (`¶ASK_S1`…). The card states what will run and what it costs:

```markdown
## ¶ASK_S1: Choose: Run a council on "ask app proofs and briefs" (3 asks)?
Stake: meta:utils/…-133853 (2 forks), meta:engine/…-ticket-batch (fork BRIEF), app:writer/onedoc-fate (fork FATE)
Context: grouped by topic: field "ask proofs"; all three ask which page an ask links
Lean: CRIT
Counter: the forks already carry their asker's reasoning; a panel may only restate it
Unblocks: the operator answers three asks with the panel's reads beside the options
- [ ] [CRIT] Critique, size 3
  Cost: one /council run, ~15 min
- [ ] [REFU] Refute the lean, size 3
- [ ] [DOFF] Design-off, size 3
- [ ] [SCRU] /scrutinize instead of a panel
- [ ] [SKIP] Not this set
```

```bash
engine ask new --to operator --reserved-for operator --topic "ask council pass" \
  --why "a council per topic instead of per question; nothing runs until you pick" --body-file <plan.md>
```

List the "waiting for company" asks in the preamble. Do not give them forks. Then **stop and wait**. Do not run a set because the plan has sat unanswered; an unanswered plan runs nothing (`IfUnanswered: nothing runs`). Go back to whatever else you were doing; the answer arrives through the ask's delivery.

## 4. Run only what was approved

Read the answer with `engine ask read <seat>/<id>`. For each fork, its codes are the approved runs. `SKIP`, or a fork left unanswered, runs nothing. Two approved angles on one set means two runs.

For each approved council run:
1. Write a Council Brief (`skills/council/assets/TEMPLATE_COUNCIL_BRIEF.md`).
   - **Subject**: `doc` naming a file you assemble. It lists the set's asks, each with its path, its preamble, and the covered forks verbatim.
   - **Poll**: one item per covered fork, keyed `<seat>/<id>#<FORK>`, with the fork's own options as `{key: code, label}`. Never add options to it.
   - **Lean**: the fork's `Lean:` line, so the `refute` angle has something to attack.
2. Run `/council doc <subject> --brief <brief> --mode report-only --size <n> --angle <angle>`.
3. The report's **Ask Lines** section gives, per fork, the `Panel:` lines from the votes and, under design-off, the `Proposed:` lines.

For an approved scrutinize run, run `/scrutinize` over the work the asks are about. A scrutinize pass is no vote, so it produces no `Panel:` reads. Its report is published as in §5 and goes to each covered asker as a link, with `engine ask` delivery or `engine broadcast` to the asker, naming the ask.

## 5. Publish, then attach — so `Council:` is always a URL

`attach-panel` refuses anything but an http(s) URL. A council report is markdown, so publish it first:

```bash
python3 ~/.claude/engine/skills/ask-council/assets/council-page.py <report.md> <report.html>
~/.claude/engine/skills/prove/assets/publish-s3.sh <report.html> council-<set-slug>   # prints the URL on stdout
```

Take the URL from stdout and the destination it states on stderr. Do not guess the store. Then attach each fork's block:

```bash
engine ask attach-panel <seat>/<id> --fork <FORK> \
  --panel 'Security → B — a separate root keeps the blast small' \
  --panel 'Economist → A — one root is simpler to audit' \
  [--proposed 'Design-off → Fund from the deployer root — no new root at all'] \
  --council <url>
```

`attach-panel` behaves as follows:
- It is append-only. The question, options, answer and revision do not move, so an answer in flight is not refused.
- It records who attached the reads and when, and it tells the asker.
- It refuses a withdrawn or superseded ask. If the asker withdrew or replaced the ask while the panel ran, report that and drop it. An ask answered in the meantime still takes the reads, as a record beside the answer.
- It refuses a pick that names no option. A lens that voted outside the options was proposing, so put that under `--proposed` instead.

Write no `--panel` line for a lens that did not vote on that fork. A fork the run did not cover gets nothing.

## 6. Close the pass

Mark the plan ask acted, naming what ran and where the reads went:

```bash
engine ask acted <seat>/<plan-id> "S1 CRIT ran (report <url>), reads on 3 asks; S2 skipped"
```

Then report to whoever runs the loop, in one line per set: the set, its angle, the report URL, the asks attached, and anything refused.

## Constraints

- **`¶INV_ASKCOUNCIL_PLAN_BEFORE_SPEND`**: no panel runs before the plan ask is answered, and only the approved angle runs on each set. A set that seems urgent goes in the plan with its `neededBy`. It is never run ahead of the answer.
- **`¶INV_ASKCOUNCIL_READS_ON_THE_ASK`**: a run is done only when its reads are attached to every fork it covered with `attach-panel`. A report that exists only as a file, or reads described in prose, does not count, because the ask page draws a panel only from those records.
- **The panel never answers.** Attached reads are input for the operator. Never present them as a tally, never answer the ask from them, and never edit a fork's options. A proposed option becomes real only if its asker revises the ask to add it.
- **One plan per pass.** A second pass while a plan is still unanswered adds nothing. It says the plan is pending and stops.
