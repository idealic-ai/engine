# Writing an ask the operator can decide from

This guide is for an agent about to run `engine ask new`. The ask skill (`skills/ask/SKILL.md`) is the format reference: the header fields, the heading grammar, the CLI. This guide is the craft: how to turn a messy situation into a short decision tree the operator can answer in one pass, without asking you anything back.

The operator's complaint about today's asks is "this is not enough info". Most of the time the facts existed, but they were in the asker's head, in a dropped paragraph, or in a one-line header lean that covered five forks at once. The aim is an ask where every fork carries its own options, costs, lean and counter-argument.

Two house formats set the vocabulary, and this guide follows them rather than restating them: `¶FMT_DECISION_CARD` (what a card holds: stake, options with the honest do-nothing, cost to act, how to verify, confidence, the lean after the options) and `¶FMT_ANSWER_GRADATION` (risk, confidence, effort and ★, shown only where they differ across the options). Both are in `~/.claude/.directives/SIGILS.md`.

## What the parser reads today

Status as of 2026-10-30. Write only what the parser reads, or the operator never sees it.

- **Read today, per fork** (flush-left lines under the heading): `Stake:`, `Unblocks:`, `Related:`, `Lean:`, `Counter:`, `Confidence:`, `Reversible:`, `Verify:`, `Falsifier:`, `IfUnanswered:`, `NeededBy:`, `Blocks:`, `Context:` (one line; a second `Context:` replaces the first), repeatable `Evidence:` and `Panel:`, and `DependsOn:`.
- **Read today, per option** (indented under the option): a description, and `Cost:`, `Effort:`, `Blast:`, `Unblocks:`, `Then:`, `Elegance:` (see *Give every answer its own context*). The operator's app does not show `Unblocks:`, `Then:` or `Elegance:` as fields yet, so each of those lines also stays in the description text, where the card shows it. An indented `- ` line that does not start with `[` is a bullet in the description, never an option. `- [ ]`, `- [CODE]` and anything else in brackets nests an option, so a bad code there is refused. Every other indented line is joined onto the description as plain text, except a fenced code block indented under the option: it stays part of that option, kept line for line (dedented to the fence's indent) as its own block in the description, and an indented line after it starts a new paragraph. Blank lines around the fence are fine. A fence that is not indented under an option is the fork's prose. An indented line belongs to the nearest option above it that is indented less, so a fence at a child option's own indent is its parent's. After a blank line, an indented line (a note, a fence, even a `- [ ]` line) still belongs to the last option; start a note at column 0 to keep it out of the options. `engine ask new` warns when a fence is never closed, because everything after it, later forks included, is then read as code.
- **Every fence carries a language.** Open each fenced block with its language (```` ```ts ````, ```` ```sh ````, ```` ```json ````), so the browser can highlight it; write ```` ```text ```` when nothing fits. `engine ask new` and `engine ask revise` refuse (exit 2) a fence with no language, at the top level or indented under an option, naming each line of the body: `line 14: fenced block has no language; write ```text if nothing fits`. The store's own record fences (`json answer`, `json history`) already carry a tag. An ask already on disk is never refused for this: reading, answering and listing it work as before, and a revise that keeps the body (`--keep-body`) passes.
- **Coming with ASK v2 H4, not read yet:** per-option `Pro:`, `Con:`, `Risk:`, `Complexity:`, `Confidence:`, `Reversible:`; a do-nothing marker; per-fork `Parent:`; `CouncilAsOf:`; header `project:` and `group:`. Until H4 lands, carry the same facts as plain sentences in the option's description. An indented `Risk: med` line is not lost today, but it runs into the description as one line of text, so a sentence reads better.
- **Prose under a fork heading.** The v2 parser keeps it: the reasons before the options are shown at the top of the fork's card, and an unindented note after the options between that card and the next. A fenced example inside a fork stays in its prose. The options are the fork's last list (its coded list, when it has one), so a `- [ ]` checklist line in your reasons is shown as prose, never offered as an option. An indented line under an option stays that option's description. (The v1 parser dropped it, which is how IDE-264's reason for existing was lost; the operator's running app stays v1 until v2 is deployed, so for an ask it must answer before then, also put the key fact in a `Context:` line.)
- **What `new` and `revise` refuse, and what they warn about.** They refuse, naming each fork or option and saying where the fix goes:
  - a fork named after its kind word (`## Choose one: ¶ASK_X: …`; write `## ¶ASK_X: Choose one: …`). Fixing it changes the fork's answer key from `q0` to its name; a revise already makes any draft stale, so nothing is lost.
  - a **bare option**: one with nothing indented under its label (no description, no field, no nested option) in a `Choose one` or `Choose` fork. Rank options are names to order and are exempt. A `Choose one` of bare `[YES]` and `[NO]` is pointed at `## ¶ASK_X: Yes or no: …`.
  - a `Choose one`, `Choose` or `Rank` **fork with no context**: none of `Context:`, `Stake:`, `Lean:`, `Counter:`, `Evidence:` or prose under its heading, and no preamble or header `why`, `context` or `stakes` (those count for every fork). `Panel:` and `Council:` lines are a council's read, not context. `Yes or no`, `Number`, `Date` and `Text` forks need none.

  A refused `revise` names `--keep-body`: that revises the card fields and reads no body, so an ask already on disk can always be revised. They warn, one line per fork, on options with no `Cost:` or no `Elegance:` (not on Rank options), on a nested option with no `[CODE]`, and, in a fork with no codes at all, on indented bullets that are now read as description. Files already on disk are never refused; a refusal applies to what you file or revise.
- **Header lean on a multi-fork ask.** A header `lean:` (and every header card field) fills the first fork's card only. `lean: F1 ALL; F2 DEGR` gives F2 onward no lean at all. Write a `Lean:` line under every fork.

## Is this an ask at all?

An ask is a question whose answer unblocks work and that you are not entitled to decide. Before writing one, check the other three cases.

- **You can check it.** A fact you can read, grep or run is not a question. Find it out, then decide.
  That includes what an earlier session or a doc already settled. Before you write an ask, search both
  for its subject: `engine session-search query "<subject>" --limit 5` and
  `engine doc-search query "<subject>" --limit 5`.
  Cite a hit that bears on the question as an `Evidence:` line (the path, or the session log). If none
  does, say `searched, nothing relevant` in the ask. A search can miss, since the index is only as fresh
  as its last run, so that line means the question is still open, not that nobody answered it.
- **You may decide it.** If the choice is inside your grant, reversible, and cheap to undo, decide it, say so in your log, and move on. An ask for something you could have decided costs the operator a context switch and teaches them to skim.
- **It gathers information rather than unblocking work.** That is an interrogation (`/interrogate`), not an ask.
- **You are a loom lane.** A lane escalates to its conductor; the conductor writes the ask.

Write an ask when the choice is a one-way door, crosses another seat's ground, spends something that is not yours, or is reserved for the operator. Keep working on everything that does not depend on the answer.

## Build the tree

1. **List the decisions.** Write down every place in the situation where a reasonable person could pick differently. One fork is one decision that someone could get wrong on its own. "Re-scope the acceptance and build after MOUNTBIND" is two decisions; split it.
2. **Merge forks that always move together.** If one answer forces the other, it is one fork.
3. **Order by dependency.** A fork whose answer changes another fork's options comes first. The dependent fork carries `DependsOn: ASK_D8=SAME`, which hides it until D8 is answered with SAME (or `DependsOn: ASK_D8` for any answer).
4. **Hang each follow-up off the answer that raises it** (*When to nest a follow-up question*, below). `Parent: ASK_D8`, which shows a fork under its parent in the outline without hiding it, is coming with ASK v2 H4.
5. **At most five forks per ask.** With more, write two asks and link them with the header's `dependsOn: <other ask id>`.
6. **Name every fork, with the name before the kind word**: `## ¶ASK_<NAME>: Choose one: …`. The name is the answer key and the fork's link anchor. An unnamed fork is keyed `q0`, `q1`, which breaks when forks are reordered, and no `DependsOn:` can point at it. `## Choose one: ¶ASK_<NAME>: …` reads no name at all, so `new` refuses it.

Use the right kind. `Choose one` for one pick, `Choose` for several, `Yes or no` for a plain confirmation, `Number`, `Date`, `Text` and `Rank` when the answer is a value or an order.

## The options

- **Two to four real alternatives,** each one something you would carry out if picked. Two options that differ only in wording are one option.
- **Neutral order.** Smallest change first, or the order the debate arose. Never put your lean first, and never write "(lean)" or "recommended" into a label; the app marks the lean itself.
- **An honest do-nothing,** whenever doing nothing is possible. Code it `NONE`, `HOLD` or `DEFER`, put it last, and say in its description what stays broken and who hits it next. "Defer" with no cost is not honest.
- **Labels of three to seven words** that name the action. The description holds the rest.

Every option carries its own facts, so the operator compares like with like. *Give every answer its own context*, next, says which and how.

## Give every answer its own context

The operator decides one option at a time. For each option they need to know what it changes, what it costs, how cleanly it fits, what it unblocks, and what you will do the moment they pick it. Put those facts on the option, not in a paragraph above the fork, so they can be compared line by line.

**Write each option as:**

```markdown
- [ ] [CODE] Three to seven words naming the action
  What changes, in one or two sentences: what is built, moved, refused or left alone. Link the proof or code it rests on as [label](url), or name the file:line.
  Cost: what the operator gives up by picking it, in its own words, and "one-way" if it cannot be undone
  Elegance: high | med | low — how cleanly it fits what is already there
  Unblocks: the tickets, lanes or forks this option frees   (when options differ)
  Then: the next thing you do if this is picked
  Effort: S | M | L   (only when options differ)
  Blast: who or what it touches   (only when options differ)
```

- **What changes** (the description) and **`Cost:`** are the floor. An option with neither is refused as bare; one without a `Cost:` is warned about. A cost that restates the label is missing. Risk and complexity go in the description until H4 brings their own fields.
- **`Elegance:` is a driving factor, not a tie-breaker.** The operator weighs it beside cost and often ahead of effort. Say how cleanly the option fits: does it remove a special case or add one, reuse a shape that exists or invent a parallel one, leave one way to do the thing or two. Start with `high`, `med` or `low`, then the reason. A cheap option that leaves two ways to do one thing is rarely the right pick, and its Elegance line is where the operator sees that. `new` warns when an option has none.
- **`Unblocks:`** under an option names what picking it frees (tickets, lanes, a later fork). Under the heading, flush-left, `Unblocks:` stays the fork's own line. Write the option's only where the options unblock different things.
- **`Then:`** is your next concrete step if this option is picked: the command, the lane, the ticket. It shows the operator what they are committing you to. Write it on the lean's option at least.
- **Reversibility** has no per-option field yet. Say "one-way" in the option's `Cost:` when it cannot be undone.
- **Bullets are fine under an option.** An indented `- ` line that does not start with `[` is a list item in the description, never an answerable option. To nest an option, write `- [CODE] …`.
- **The do-nothing option has a consequence too.** Its Cost says what stays broken and who hits it next, and its Elegance says what the standing shape costs.

`Blast:` names how much is touched (rows, callers, seats) when that differs. Following `¶FMT_ANSWER_GRADATION`, leave out any dimension that is the same for every option; it is noise. Cost and Elegance are the exceptions: write them on every option.

### When to nest a follow-up question

- **It only matters under one answer: hang it off that answer.**
  - If it is a quick refinement of how to carry out the pick (same kind, two or three choices, no lean of its own), nest its options under the option, one level deep, each with its own `[CODE]` and a line under it.
  - Otherwise make it its own fork with `DependsOn: ASK_PARENT=CODE`.
- **It matters whatever the answer: `DependsOn: ASK_PARENT`** (no code), or make it an independent fork.
- **Different answers raise different follow-ups: one dependent fork per answer**, each titled with the answer it follows ("Given a census first: who runs it?"), each with a `Context:` restating the one fact from the parent that matters, and offering only the options that make sense under that answer.
- **No deeper than two dependent forks in a chain.** A third level is a second ask, linked with the header `dependsOn:`.
- In the parent option's description, end with `Opens: <the follow-up> (¶ASK_WHO)`, so the operator sees the follow-up before picking.

## The lean, per fork

The operator answers most asks by accepting the lean, so the lean has to stand up on its own. The operator ruled that the app pre-selects the lean's option and marks it Recommended; that ships with ASK v2, so write every fork as if it already does. A pre-selected option the operator accepts in one click is only as good as the reason beside it.

- `Lean: SAME — because …` starts with the option code, then a dash, then the reason. A lean that names no code still shows, but no option gets the badge or the pre-selection.
- `Counter:` is the strongest case against your own lean, written as its best advocate would put it. "None" is not a counter. If you cannot find one, say what evidence you lack.
- `Confidence: med — …` is your confidence in the facts behind the lean, with the reason.
- `Falsifier:` names what would prove the lean wrong. `Verify:` names the cheap check that confirms or sizes it.
- `IfUnanswered:` says what you do by default and from when.
- With no lean, leave `Lean:` out, so nothing is pre-selected and the operator sees you made no recommendation. Do not invent a lean to fill the field.

## Tickets and evidence

- Put ticket keys in the header `tickets:` field (`--tickets "IDE-264, IDE-285"`). The app renders each key as a link with its live status. Do not write a markdown ticket list in the preamble.
- Name keys in the text where they explain something ("after IDE-285 lands"); those render as links too.
- `Evidence:` lines are the pieces a sceptic would open: `hire-attack.test.ts:270`, a commit, a board, a log path. One per line, so the card can count them.
- Link a document as `[label](url)`, never a bare URL.

## Attaching a council board

If a `/council` or `/decide` panel actually ran on this decision, add one `Panel:` line per lens under the fork: `Panel: Security → SAME — keeps the refusal narrow`. The card shows each lens beside the option it picks. A panel is a read, not a vote: report what each lens said, never a tally. Never write a `Panel:` line for a panel that did not run.

Under the `Panel:` lines, add one `Council: <path-or-url>` line naming the report the reads came from: the `_COUNCIL_<run-id>.md` path, the published board's URL, or a `[label](url)` link. The parser keeps the first `Council:` line per fork, and `/api/asks` returns it as the fork's `council` field.

```
## ¶ASK_FUND: Choose one: What does a world fund its contracts out of?
Lean: B
Panel: Security → B — a separate root keeps the blast small
Panel: Economist → A — one root is simpler to audit
Council: sessions/2026_10_29_KERNEL/builds/fund_COUNCIL_20261030T1545.md
- [ ] [A] One root
  Contracts derive from the world's own spend root, made transferable.
  Cost: changes what a holder can pass on
  Elegance: high — one root, no second kind
- [ ] [B] A separate root
  A transferable root at the world's budgets funds the contracts.
  Cost: a second root to audit
  Elegance: med — a parallel root beside the spend root
```

The reads go in `Panel:` lines, never only in prose. The app draws a panel only from `Panel:` lines, so "the panel's consensus is LAND" written in a Context line shows nothing beside the options. `engine ask new` and `revise` warn on stderr when a fork, or the header and the text above the first fork, names a council or panel report and carries no `Panel:` line. The warning names the fork and does not stop the filing. If the panel ran on several forks at once, each fork carries its own lens reads, and every fork names the same report.

**A panel run on an ask you did not file is attached, never pasted**: `engine ask attach-panel <seat>/<id> --fork <KEY> --panel '<lens> → <code> — <why>' [--panel …] [--proposed '<lens> → <label> — <why>' …] --council <url>`.
- Any panel runner may use it, for example `/ask-council` or a seat that ran `/council` for someone else.
- It is append-only. It writes a ```json panels``` record and leaves the question, the options, any answer and the revision unchanged, so an answer in flight is not refused.
- It records who attached the reads and when, and it tells the asker.
- `--council` must be the published report's http(s) URL. Publish the report first with `skills/ask-council/assets/council-page.py`, then `publish-s3.sh`.
- A `--panel` pick must be one of the fork's codes. An option the panel proposes (the design-off angle) goes in `--proposed`. Proposals are stored in the record and listed by `engine ask read`; the app does not show them yet. Only the asker can turn a proposal into a real option, with `revise`.
- It names the fork by its `¶ASK_` name. On an ask with more than one fork, a fork with no name is refused, because a position (`q0`) can point at a different question after a revise. Each entry also keeps the fork's title, and a fork retitled since does not show the reads; `revise` warns about that, and about an attached read whose option was removed.
- Attaching the same report (`--council` URL) to the same fork again changes nothing and prints `already attached`, so a re-run is safe.
- It is refused on a withdrawn or superseded ask. An answered or declined ask still takes the reads, as a record.
- A supersede does not carry the reads to the replacement. Whoever ran the panel attaches them to the new ask again, if its fork still asks the same thing.

Not built yet: `CouncilAsOf:`, and a richer `Panel:` line with a weight, an alternative and a thin-grounds mark.

## Reserved for the operator

Set `reserved-for: operator` in the header (`--reserved-for operator`) when only the operator may rule: a one-way door, another team's code, money, anything a standing ruling names as the operator's. Managers then forward the ask rather than answer it; a manager's `--decline` on it passes it up one rung with the reason instead of closing it. The header field is the marking; a sentence in the preamble saying "reserved for the operator" is not read.

## Codes, and why they matter

An option code is what the answer stores. The v2 parser reads **a capital, then up to 11 capitals or digits — 12 characters at most**: `SAME`, `RESCOPE`, `KEEPBROAD`, `A`, `L2`. `engine ask new` and `engine ask revise` refuse anything else written in the code brackets (`[THIRTEENCHARS]`, `[wt]`) and name it; nothing is folded into the label any more.

The v1 parser read only 2 to 4 capitals. In the IDE-264 ask, `[RESCOPE]`, `[KEEPBROAD]` and even `[DEFER]` were too long for it, and the recorded answer held the whole label sentence instead of a code. v2 readers (`engine ask read`, the batch lines) still resolve such a stored `"[CODE] label"` value to its option's label, so old answers read correctly without a migration. Until v2 is deployed to the operator's running app, a code of 5 or more characters answered there is still stored as a label; keep codes to 4 characters for an ask the operator must answer before then. Short, meaningful codes also make the answer readable in one line: `D8 → SAME`.

## Before you run `engine ask new`

- [ ] I cannot check or decide this myself, and I am not a loom lane.
- [ ] This is not a re-filing of an open ask: to change one, `engine ask revise` it; if it must be a new ask, `engine ask supersede` the old one right after filing (SKILL.md, *Replacing an ask*).
- [ ] This does not ask anyone to confirm a withdrawal: to take a question back, `engine ask withdraw <seat>/<id> --reason "<why>"` it; the withdrawal is the record and nobody acknowledges it (SKILL.md, *Taking a question back*).
- [ ] Each fork is one decision; there are at most five; each is named `## ¶ASK_<NAME>: <Kind>: …`, the name before the kind word.
- [ ] Each fork has its own `Context:`, `Stake:` or prose saying what the decider must know.
- [ ] Each follow-up hangs off the answer that raises it (`DependsOn: ASK_X=CODE`), is titled with that answer, and offers only the options valid under it.
- [ ] Each fork has two to four options in neutral order, plus an honest do-nothing when one exists.
- [ ] Every option has a description saying what changes, a `Cost:` and an `Elegance:`. None is a bare label.
- [ ] Any option that cannot be undone says "one-way" in its Cost.
- [ ] The lean's option has a `Then:`; `Unblocks:` sits on the options that free different things.
- [ ] Risk and complexity are in the description where they differ.
- [ ] Every proof, board or test an option rests on is a link or a file:line on that option.
- [ ] Every fork has its own `Stake:`, `Lean: CODE — because …`, `Counter:` and `Confidence:`, plus `Verify:` or `Falsifier:`.
- [ ] No fact the operator needs sits only in a paragraph under a heading; it is in `Context:` or a description.
- [ ] No "(lean)" in a label, no header-only lean on a multi-fork ask, no markdown ticket list, no bare URL.
- [ ] Codes are a capital then capitals or digits, 12 characters at most (4 or fewer while the operator's app is still v1).
- [ ] `tickets:` and `topic:` are set, and `reserved-for: operator` when the call is the operator's.
- [ ] No field marked "coming with ASK v2 H4" appears as its own line.

## Worked example: IDE-264

Before. This is the fork as written in `idealic:kernel/20261028-182556-…`. The reason under the heading was dropped by the parser, so the operator saw two long labels and a bare "Defer". Both long codes fell into the label text. The header lean covered all four forks in one sentence and attached to none of them.

```markdown
## Choose one: IDE-264 (D8 row-id refusal): ticket disposition
Its acceptance says `<project>/agents/agents` is refused. But that is a row under the agents collection, and hire-attack.test.ts:270 asserts that it is accepted. Kernel's reading of D8, sent to realm at 00:25: refuse only a row id equal to a literal that the SAME parent mounts.
- [ ] [RESCOPE] Re-scope the acceptance to the same-parent reading (via /snapshot at dispatch), and build after MOUNTBIND lands (both edit the kernel write path)
- [ ] [KEEPBROAD] Keep it as written (the broad reading; hire-attack.test.ts:270 would flip)
- [ ] [DEFER] Defer
```

After. The bundled option is split into two forks: which reading D8 takes, and when the build runs. The second fork waits on the first. Every option carries its cost and its elegance, and the facts that were dropped now sit in `Context:` and the descriptions. Every line is one the parser reads. The card shows `Cost:`, `Effort:` and `Blast:` as fields; `Elegance:` and `Then:` are read as fields too, but until the app renders them they show inside the description text.

```markdown
---
topic: kernel write path (D6/D8)
tickets: IDE-261, IDE-264, IDE-285
reserved-for: operator
---
## ¶ASK_D8: Choose one: Which row ids does IDE-264 refuse?
Context: IDE-264's acceptance refuses <project>/agents/agents, a row under the agents collection; hire-attack.test.ts:270 asserts that row is accepted today.
Stake: the ticket and the test disagree, so whoever builds IDE-264 breaks one of them.
Unblocks: the IDE-264 build thread
Evidence: hire-attack.test.ts:270
Evidence: Kernel's D8 reading, sent to realm at 00:25
Verify: grep the kernel fixtures for row ids equal to a literal mounted by any ancestor
Falsifier: the operator meant D8 to cover every mounted literal
Confidence: med — the D8 text is short and does not say "same parent"
Lean: SAME — because the passing test and Kernel's stated reading already agree on it
Counter: if D8 was written to mean any mounted literal, SAME quietly narrows the operator's own rule
- [ ] [SAME] Refuse only an id equal to a literal the same parent mounts
  Re-scope the acceptance at dispatch with /snapshot. The test stays green. Risk is low. An id that shadows a grandparent's mount still passes.
  Cost: one acceptance edit on IDE-264
  Elegance: high — one rule, the one the passing test already states
  Then: re-scope IDE-264's acceptance with /snapshot and dispatch it
  Effort: S
- [ ] [BROAD] Refuse any id equal to any mounted literal
  Keeps the acceptance as written. hire-attack.test.ts:270 flips from accept to refuse. Medium risk: nobody has counted the existing rows that share a mounted name, and the Verify check above sizes it. Hard to reverse once rows are refused.
  Cost: a test flips, and an unknown number of existing rows become invalid; one-way once rows are refused
  Elegance: med — one rule, but it reaches past the parent that mounts the name
  Blast: every row whose id matches a mounted literal anywhere above it
- [ ] [DEFER] Leave IDE-264 as written and unbuilt
  The contradiction stays in the ticket and the next builder meets it.
  Cost: D8 stays unenforced
  Elegance: low — the ticket and the test keep disagreeing

## ¶ASK_D8BLD: Choose one: When does the IDE-264 build start?
DependsOn: ASK_D8=SAME
Context: IDE-285 (MOUNTBIND) and IDE-264 both edit the kernel write path.
Stake: two lanes in the same file at once means a conflicted merge on the kernel's write path.
Lean: AFTER — because MOUNTBIND is already in flight and the wait is one landing
Counter: if MOUNTBIND slips, IDE-264 waits on it with no date
Confidence: high — both tickets name the write path
- [ ] [NOW] Dispatch now in its own worktree
  Cost: a merge against MOUNTBIND on the write path, settled by whichever lands second
  Elegance: low — two lanes edit one file at once
- [ ] [AFTER] Dispatch once IDE-285 lands
  Cost: IDE-264 waits for one landing
  Elegance: high — one lane on the write path at a time
  Then: queue IDE-264 behind IDE-285 in the loom
- [ ] [HOLD] Do not schedule it yet
  Cost: the re-scoped ticket sits with nothing building it
  Elegance: med — nothing collides, and nothing moves
```

Coming with ASK v2 H4, the same options would carry their facts as fields instead of sentences, for example under `[BROAD]`:

```markdown
  Risk: med — the existing rows that share a mounted name are uncounted
  Complexity: low — the refusal check changes; nothing new is added
  Reversible: no — refused rows stay refused
  Con: hire-attack.test.ts:270 flips
```

Do not write those lines today. Until H4 lands they run into the description as one line of text.
