# Writing an ask the operator can decide from

This guide is for an agent about to run `engine ask new`. The ask skill (`skills/ask/SKILL.md`) is the format reference: the header fields, the heading grammar, the CLI. This guide is the craft: how to turn a messy situation into a short decision tree the operator can answer in one pass, without asking you anything back.

The operator's complaint about today's asks is "this is not enough info". Most of the time the facts existed, but they were in the asker's head, in a dropped paragraph, or in a one-line header lean that covered five forks at once. The aim is an ask where every fork carries its own options, costs, lean and counter-argument.

Two house formats set the vocabulary, and this guide follows them rather than restating them: `¶FMT_DECISION_CARD` (what a card holds: stake, options with the honest do-nothing, cost to act, how to verify, confidence, the lean after the options) and `¶FMT_ANSWER_GRADATION` (risk, confidence, effort and ★, shown only where they differ across the options). Both are in `~/.claude/.directives/SIGILS.md`.

## What the parser reads today

Status as of 2026-10-29. Write only what the parser reads, or the operator never sees it.

- **Read today, per fork** (flush-left lines under the heading): `Stake:`, `Unblocks:`, `Related:`, `Lean:`, `Counter:`, `Confidence:`, `Reversible:`, `Verify:`, `Falsifier:`, `IfUnanswered:`, `NeededBy:`, `Blocks:`, `Context:` (one line; a second `Context:` replaces the first), repeatable `Evidence:` and `Panel:`, and `DependsOn:`.
- **Read today, per option** (indented under the option): a description, and `Cost:`, `Effort:`, `Blast:`. Every other indented line is joined onto the description as plain text.
- **Coming with ASK v2 H4, not read yet:** per-option `Pro:`, `Con:`, `Risk:`, `Complexity:`, `Confidence:`, `Unblocks:`, `Reversible:`; a do-nothing marker; per-fork `Parent:`; `Council:` and `CouncilAsOf:`; header `project:` and `group:`. Until H4 lands, carry the same facts as plain sentences in the option's description. An indented `Risk: med` line is not lost today, but it runs into the description as one line of text, so a sentence reads better.
- **Prose under a fork heading.** The v2 parser keeps it: the reasons before the options are shown at the top of the fork's card, and an unindented note after the options between that card and the next. A fenced example inside a fork stays in its prose. The options are the fork's last list (its coded list, when it has one), so a `- [ ]` checklist line in your reasons is shown as prose, never offered as an option. An indented line under an option stays that option's description. (The v1 parser dropped it, which is how IDE-264's reason for existing was lost; the operator's running app stays v1 until v2 is deployed, so for an ask it must answer before then, also put the key fact in a `Context:` line.)
- **Header lean on a multi-fork ask.** A header `lean:` (and every header card field) fills the first fork's card only. `lean: F1 ALL; F2 DEGR` gives F2 onward no lean at all. Write a `Lean:` line under every fork.

## Is this an ask at all?

An ask is a question whose answer unblocks work and that you are not entitled to decide. Before writing one, check the other three cases.

- **You can check it.** A fact you can read, grep or run is not a question. Find it out, then decide.
- **You may decide it.** If the choice is inside your grant, reversible, and cheap to undo, decide it, say so in your log, and move on. An ask for something you could have decided costs the operator a context switch and teaches them to skim.
- **It gathers information rather than unblocking work.** That is an interrogation (`/interrogate`), not an ask.
- **You are a loom lane.** A lane escalates to its conductor; the conductor writes the ask.

Write an ask when the choice is a one-way door, crosses another seat's ground, spends something that is not yours, or is reserved for the operator. Keep working on everything that does not depend on the answer.

## Build the tree

1. **List the decisions.** Write down every place in the situation where a reasonable person could pick differently. One fork is one decision that someone could get wrong on its own. "Re-scope the acceptance and build after MOUNTBIND" is two decisions; split it.
2. **Merge forks that always move together.** If one answer forces the other, it is one fork.
3. **Order by dependency.** A fork whose answer changes another fork's options comes first. The dependent fork carries `DependsOn: ASK_D8=SAME`, which hides it until D8 is answered with SAME (or `DependsOn: ASK_D8` for any answer).
4. **Split into sub-questions** when an option opens its own choice. Nest those options under the option, at most two levels deep. When a whole fork only means something under one answer, make it its own fork with `DependsOn:`. `Parent: ASK_D8`, which shows a fork under its parent in the outline without hiding it, is coming with ASK v2 H4.
5. **At most five forks per ask.** With more, write two asks and link them with the header's `dependsOn: <other ask id>`.
6. **Name every fork** with `¶ASK_<NAME>:` in the heading. The name is the answer key and the fork's link anchor. An unnamed fork is keyed `q0`, `q1`, which breaks when forks are reordered.

Use the right kind. `Choose one` for one pick, `Choose` for several, `Yes or no` for a plain confirmation, `Number`, `Date`, `Text` and `Rank` when the answer is a value or an order.

## The options

- **Two to four real alternatives,** each one something you would carry out if picked. Two options that differ only in wording are one option.
- **Neutral order.** Smallest change first, or the order the debate arose. Never put your lean first, and never write "(lean)" or "recommended" into a label; the app marks the lean itself.
- **An honest do-nothing,** whenever doing nothing is possible. Code it `NONE`, `HOLD` or `DEFER`, put it last, and say in its description what stays broken and who hits it next. "Defer" with no cost is not honest.
- **Labels of three to seven words** that name the action. The description holds the rest.

Every option carries the same six facts, so the operator compares like with like:

- **What it does,** in one or two sentences of description.
- **Cost** (`Cost:`): what the operator gives up by picking it, in its own words. A cost that restates the label is missing.
- **Risk:** what could go wrong, and how likely. Today in the description; `Risk: low|med|high — …` comes with H4.
- **Complexity:** the surface it adds, separate from how long it takes. `Effort:` (S, M, L) is the time; complexity goes in the description until H4 brings `Complexity:`.
- **What it unblocks:** named tickets or lanes. In the description until H4 brings a per-option `Unblocks:`.
- **Reversible or not:** say "one-way" in the description when it cannot be undone. A per-fork `Reversible:` line exists today; the per-option one comes with H4.

`Blast:` names how much is touched (rows, callers, seats) when that differs. Following `¶FMT_ANSWER_GRADATION`, leave out any dimension that is the same for every option; it is noise.

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

Coming with ASK v2 H4: `Council: <url>` and `CouncilAsOf:` to attach the board itself, and a richer `Panel:` line with a weight, an alternative and a thin-grounds mark. Until then, cite the board's URL in an `Evidence:` line.

## Reserved for the operator

Set `reserved-for: operator` in the header (`--reserved-for operator`) when only the operator may rule: a one-way door, another team's code, money, anything a standing ruling names as the operator's. Managers then forward the ask rather than answer it. The header field is the marking; a sentence in the preamble saying "reserved for the operator" is not read.

## Codes, and why they matter

An option code is what the answer stores. The v2 parser reads **a capital, then up to 11 capitals or digits — 12 characters at most**: `SAME`, `RESCOPE`, `KEEPBROAD`, `A`, `L2`. `engine ask new` and `engine ask revise` refuse anything else written in the code brackets (`[THIRTEENCHARS]`, `[wt]`) and name it; nothing is folded into the label any more.

The v1 parser read only 2 to 4 capitals. In the IDE-264 ask, `[RESCOPE]`, `[KEEPBROAD]` and even `[DEFER]` were too long for it, and the recorded answer held the whole label sentence instead of a code. v2 readers (`engine ask read`, the batch lines) still resolve such a stored `"[CODE] label"` value to its option's label, so old answers read correctly without a migration. Until v2 is deployed to the operator's running app, a code of 5 or more characters answered there is still stored as a label; keep codes to 4 characters for an ask the operator must answer before then. Short, meaningful codes also make the answer readable in one line: `D8 → SAME`.

## Before you run `engine ask new`

- [ ] I cannot check or decide this myself, and I am not a loom lane.
- [ ] Each fork is one decision; there are at most five; each is named `¶ASK_<NAME>`.
- [ ] Dependent forks carry `DependsOn:`.
- [ ] Each fork has two to four options in neutral order, plus an honest do-nothing when one exists.
- [ ] Every option has a description and a `Cost:`, and its risk, complexity, what it unblocks and its reversibility are in the description where they differ.
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

After. The bundled option is split into two forks: which reading D8 takes, and when the build runs. The second fork waits on the first. Every option carries its cost, and the facts that were dropped now sit in `Context:` and the descriptions. Only fields read today are used.

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
  Effort: S
- [ ] [BROAD] Refuse any id equal to any mounted literal
  Keeps the acceptance as written. hire-attack.test.ts:270 flips from accept to refuse. Medium risk: nobody has counted the existing rows that share a mounted name, and the Verify check above sizes it. Hard to reverse once rows are refused.
  Cost: a test flips, and an unknown number of existing rows become invalid
  Blast: every row whose id matches a mounted literal anywhere above it
- [ ] [DEFER] Leave IDE-264 as written and unbuilt
  The contradiction stays in the ticket and the next builder meets it.
  Cost: D8 stays unenforced

## ¶ASK_D8BLD: Choose one: When does the IDE-264 build start?
DependsOn: ASK_D8=SAME
Context: IDE-285 (MOUNTBIND) and IDE-264 both edit the kernel write path.
Stake: two lanes in the same file at once means a conflicted merge on the kernel's write path.
Lean: AFTER — because MOUNTBIND is already in flight and the wait is one landing
Counter: if MOUNTBIND slips, IDE-264 waits on it with no date
Confidence: high — both tickets name the write path
- [ ] [NOW] Dispatch now in its own worktree
  Cost: a merge against MOUNTBIND on the write path, settled by whichever lands second
- [ ] [AFTER] Dispatch once IDE-285 lands
  Cost: IDE-264 waits for one landing
- [ ] [HOLD] Do not schedule it yet
  Cost: the re-scoped ticket sits with nothing building it
```

Coming with ASK v2 H4, the same options would carry their facts as fields instead of sentences, for example under `[BROAD]`:

```markdown
  Risk: med — the existing rows that share a mounted name are uncounted
  Complexity: low — the refusal check changes; nothing new is added
  Reversible: no — refused rows stay refused
  Con: hire-attack.test.ts:270 flips
```

Do not write those lines today. Until H4 lands they run into the description as one line of text.
