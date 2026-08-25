---
name: design
description: "Work with the design kit, IN YOUR OWN CONTEXT — no subagent, no brief. Two subjects, one protocol: (1) PRODUCE A PAGE of any kind the library declares — resolve the library, read the composing contract, start from a page KIND (never a blank canvas or a copied skeleton), or REWRITE a page that already exists; fill it from the vocabulary the library actually advertises, wire it so it opens, bundle it so it travels, and prove it renders by looking at it. (2) AUTHOR OR ALTER AN IDEA the library does not have yet — rule its tier with the argument and a falsifier, rule its placement, declare it, BIND every closed set, write the CSS it owns, ship a control, and look at the render. It owns everything about a page and a widget EXCEPT what the content says: the caller supplies words and choices, the skill supplies structure and proof-of-correctness. The design-kit primitive /prove, /remix and any page-writing task compose on top of. Triggers: \"design a page\", \"make a page\", \"build a page from the kit\", \"compose a page\", \"design a widget\", \"add an idea to the kit\", \"rewrite this page\", \"work with the design kit\", \"lint the kit\", \"design\"."
version: 1.0
tier: lightweight
args: "[<the subject>] [--kind <page-kind>] [--idea <name>] [--theme <name>] [--kit <library path>] [--out <file>] [--no-bundle]"
---

Work with the design kit. You do the work, here, in this context — **there is no subagent and no brief.** This skill hands you the sequence, the contract, the vocabulary and the gates; you supply the words.

**Two subjects, one kit.** Producing a page and authoring an idea are not two skills — they are the same protocol with a different middle. §0–§4 and §6–§8 are the page. §5 is the idea. **A page that CONTAINS ideas is a page of a different `--kind` whose §4 is §5** — that is the whole difference, and it is why these live together rather than apart.

**The one thing it does not own is what the page or the idea SAYS.** Structure, resolution, wiring, bundling and proof are the skill's. Content is yours.

> **Why in-context.** A page is written by whoever holds the finding, and an idea is designed by whoever met the gap. Dispatching throws that away and hands a stranger a summary; the measured cost is a page whose captions are one abstraction level away from the evidence. `/prove` dispatches because it is *presenting* work someone else already did; `/design` is the act of making, so it stays where the maker is.

# /design Protocol

## 0. Resolve the library — BEFORE anything else

🔴 **READ `<libRoot>/../.directives/PITFALLS.md` NOW, IN FULL.** It is short, and it is the list of ways this toolchain wastes your time — each entry a trap that was actually hit, with the symptom first. **Most of them are dangerous because the failure looks exactly like success**: a command that exits 127 and prints nothing reads as a clean measurement; a `grep` that returns zero because it decided a file was binary reads as *no matches*; a page whose every clause passes can be painting as unstyled text. **You will not recognise these from the output. Read them before you start, not after you have reported a number.**

**A page is composed from an idea library, and an idea is authored into one. The page *declares* the ideas it instantiates; the tools resolve everything else.** There is exactly one composition path.

**Resolve `<libDir>` in this order. Never guess a path.**

1. **`--kit <path>`** — an explicit library directory. Takes precedence over everything.
2. **`$IDEA_LIBRARY`** — an absolute path in the environment.
3. **`<projectRoot>/.idea-library`** — a JSON marker, prescribed once per project (walk up from `$PWD`). Two absolute paths:
   ```json
   { "library": "…/kit-library", "cli": "…/idea-cli/idea.ts" }
   ```
   **Two, not four.** A page's starting artifact and a library's per-idea documentation are both **derived on demand** — `idea generate` writes the first, `idea view` prints the second — so neither is a path anyone prescribes. A marker naming a generated file goes stale the moment that file moves; a marker naming the generator cannot. Extra keys are not an error: read the two, ignore the rest.
4. **Nothing resolved → say so in one line and STOP.** Do not improvise a path, do not compose from a directory you have not resolved, and do not reach for a second composition contract. A project without a library is a project to prescribe a marker for, not to compose differently in.

**`<libDir>` is a DIRECTORY, not a register — and the CLI decides whether it resolved.** There is no manifest and no index. A library *is* its documents, discovered as the document layer's own `.html` files or — when that layer holds none of its own — the `.html` files exactly **one** level down. Do not hand-verify the layout; run the walk once and read what it reports:

```
node <cli> start                                # the kinds, derived on every run
```

One provenance line answers the whole question — which directory it chose, how many documents, which tree shape, and (on `bundle --graph`) every subdirectory it did *not* descend into. **Read the exit code; do not re-derive the judgement behind it.** Exit **2** *is* "the library did not resolve", and the CLI names which failure in a line worth quoting verbatim when you take step 4.

**Never substitute a hardcoded list of document names.** That is a second copy of the library's layout, and it goes wrong twice — stale while the tree stands still, and pointing at nothing the moment it moves.

**The marker may carry a `_known_state` note. Read it.** A library mid-migration has facts nothing else will tell you — a verb that would propagate a half-landed change, a document that is knowingly wrong. Acting on the tree without reading its own note is how a lane re-does damage someone already recorded.

## 1. Read the contract

🔴 **ABSOLUTELY CRITICAL: READ THE WHOLE `docs` AND `browse` OUTPUT FROM START TO END. NO TRUNCATION.**

**Not the first screen. Not the headings. Not a search for what you expected to find.** Start to end, both commands, every line — `docs` here in §1 and `browse` in §4. If the output is long, page through it with `Read` until you reach the last line. **An agent that stops early has not read the contract; it has sampled a document that had no reason to put the important part first.**

🔴 **THIS STEP IS MANDATORY AND IT IS NOT SAMPLABLE. RUN THE COMMAND AND READ THE WHOLE OUTPUT.**

Not "be aware of", not "consult if unsure" — **run `docs`, and read every line it returns before you author anything.** Skipping it is not a deviation to be flagged in a report, it is a step that did not happen, and a page composed without it is unreviewable because nobody can tell which rules the author had.

**This is enforced because it has already failed.** A lane that otherwise did excellent work did not run `idea docs` at all and recorded it honestly as a deviation — which is the correct behaviour under a rule that reads as advisory, and the reason this paragraph now exists. **A prescription with no obligation is a suggestion, and this one is load-bearing.**

**And do not sample the output to save context.** The always-read stage is ~28K–33K tokens against a page read that costs roughly ten times that, so this is the cheapest input you will take all session — **and the failure mode of skimming it is silent, because a page written without the rules looks exactly like a page written with them until someone runs the gates.**

These are the rules the work will be judged against, and each one cost a real page. **One command reads them, in the order they answer each other:**

```
node <cli> docs                 # the COMPOSE stage — always owed. ~28K-33K tokens, and it prints that number
node <cli> docs --names         # the map first, a couple of KB: which stage you need, and why each doc is where it is
node <cli> docs author          # ADD this when you are writing a new idea (§5) — IDEA.md, AUTHORING.md, QUERY.md
node <cli> docs theme           # ADD this when you are theming — THEME_RULES.md
```

🔴 **Never substitute a hand-listed set of document names here.** This section used to carry one, pointing at `~/.claude/engine/skills/intake/assets/`, and it went wrong in both of the ways a second copy goes wrong: it was stale while the tree stood still, and it pointed at nothing the moment the documents moved. The documents now live in the library, at `<library>/docs/`, and `idea docs` derives the list from what is there.

**The order is not arbitrary and the verb states its own reasoning** — `--names` prints one line per document saying why it sits where it sits, so you can disagree with the order rather than merely obey it. The shape of it: the tier question first (`IDEAS_TOC.md`, whose §0 sets the counting discipline everything later depends on), then the model (`PILLARS.md`), then what a library is (`LIBRARY.md`), then *is this file mine to edit* (`FORMS.md`) before *what do I write*, then the protocol (`AGENTS.md`), composition (`PAGE.md`), the line-level rules (`HTML_WRITING_STANDARDS.md`), and last the seven things that bit a real page (`KIT_COMPOSING.md`) — last because it is the one you re-read.

**Four of those rules bind every line you author and are worth having in mind before the read**, from `HTML_WRITING_STANDARDS.md`:

*   a set of names is a set of **elements**, never a delimited cell
*   a group of things gets a **parent element that IS the group**
*   a separator (`·` `,` `;` `|`) is decoration and lives in CSS — never a delimiter anyone parses
*   **never a `style` attribute** — it outranks every rule an idea can write

**There is no `--all`, and that is a ruling rather than a gap.** The corpus behind this library is ~1.19 MB across 39 documents — ~208K–254K tokens, spent mostly on its least-maintained part. The curated thirteen are ~48K–57K across all three stages, and the always-read nine are **less than the eight documents this section used to hand-list**, while *adding* the one that answers the tier question. **Cheaper and more complete** — and the verb prints both numbers on every run, so check the claim rather than taking it.

**A reference layer exists and is addressed, never read through — with one exception you SHOULD read.** `idea docs` names the layer in its header without printing it, and counts the citation load from `lint.ts` on every run: **22 distinct rule numbers, 134 citation instances over 91 sites** at the last measurement. **`kit-library/docs/extras/RULES.md` is what those citations resolve to** — all 60 numbered rules as one verbatim line each, ~15 KB, with a `file:line` pointer into the long form. When the linter says `rule: 'idea 32'`, open RULES.md; open `extras/KIT_SPEC_IDEA.md` only when you need the *argument* under the rule rather than the rule. **Never renumber one**: the numbers are an interface.

**Fetch the contract; do not carry it.** The specs behind these files are far larger than any prompt can hold. This skill states the rules once and points at the contract rather than transcribing it — a transcription is a second copy that drifts, and the copy is the half that goes stale.

## 2. Start from a page KIND

**A page kind is the unit of starting. There is no skeleton to copy and no blank canvas.**

```
node <cli> start                                # what kinds exist, with descriptions — ON STDOUT
node <cli> start <kind> <pagePath>              # generate + wire + prove it opens, one call
```

What arrives is a complete, working page of that kind: the kind and its declared host recipe on `<html data-instance>`, the kind's **own specimen** lifted verbatim as the body, and — see §3 — the loader line that makes it openable. Every byte traces to an idea someone authored who knew what that page is.

🔴 **The kinds are DISCOVERED, never listed.** `generate --list` is the only source, and it is derived on every run. A kind list written into a prompt, a brief or a skill is stale the day an idea uses a new one — and a skill asserting a kind does *not* exist is worse than one that never mentioned it, because it tells an agent to stop when the answer is one command away.

**Read the report, not just the file.** `generate` prints `tokens`, `absorbed`, `imports`, `OVERFLOW` and `UNBOUND`. An `UNBOUND` token is a page that will not fully resolve; it exits 1 and still writes the file, because the page you need to look at is the one that is wrong.

### The theme — `--theme <name>`

**It is a flag, on both verbs.** `generate --theme` sets it at birth; `wire --theme` moves an existing page. Both run the same resolution, so a theme named at birth and a theme swapped later cannot come out different.

```
node <cli> start <kind> <pagePath> --theme theme-nerv    # at birth
node <cli> wire <pagePath> --library <libDir> --theme theme-nerv   # to move an existing page
```

**Never edit the token by hand.** A theme lives in its own document, so changing the token changes which file the page must import — and a page that names one theme while importing another's document renders in whichever the loader happened to fetch, with nothing checking the pairing. The flag does the swap and the re-derivation in one call, which is what makes that state unreachable.

**It takes the idea's exact name** — `theme-warm-print`, not `warm` or `warm-print`. An unknown name is refused with the list the library actually declares.

**Ask the library which themes exist rather than trusting a hardcoded list.** Pass a name you know is wrong and read the refusal — it names every theme the resolved library declares, derived on the spot. Do not carry a list of theme names in your head or in a prompt.

**One name per axis; the theme is one name.** A theme extends its own axes — palette, rhythm, material, type, channel, atmosphere — so naming the theme brings all of them, and naming the theme *and* its axes puts a name on `<html>` beside something that already `extends` it, which `PILLARS.md` forbids as `¶INV_HTML_NAMES_ONE_INSTANCE_PER_AXIS`. The flag moves exactly one token and the outgoing theme's axes leave with it. **Check the emitted `<html>` line: one theme name, not seven.**

**Then look at it.** Measured in this library, a theme can swap cleanly — token moved, imports re-derived, page opens, zero errors — and render **untuned**, because only some themes fill the `--t-*` slots the page kinds read; others carry their own vocabularies entirely. A green swap is not a themed page. Read `--ink` and a `--t-*` slot at `:root` in the rendered document, and open the shot.

**If no kind fits, that is a finding, not a licence.** Report the gap and stop, or compose the nearest kind and say plainly what it does not cover. Do NOT invent a page shape — a synthesized scaffold is a second answer to "what is a page of this sort", and the second answer is the one that goes stale.

### When the page already EXISTS — rewrite mode

`generate` writes a NEW page, so a document already on disk has no starting move of its own. It gets one here. **Read the document's two independent facts first** — they can disagree, and a drifted document usually does:

```
grep -o 'data-instance="[^"]*"' <pagePath> | head -1      # the ROOT instance — what this page IS
node <cli> check <pagePath>                     # what it reaches, what resolves to nothing, and what is DEAD
```

🔴 **A root naming an idea the library no longer defines is the first thing to check, and the two commands are not redundant — the `grep` is the ONLY one that catches it.** Measured on `page/proof-page.html`: its root reads `data-instance="kit-floor"`, an idea deleted to a tombstone (`kit-library/D5_DELETED_kit-floor.html.txt`), and `view --json` returns it in **neither `roots` nor `missing`** — the walk starts from names it can resolve, so a dead root is simply not a name it sees. The page renders unstyled or half-styled and every automated reading over it stays green. **Four of the seven `page/*.html` documents are in this state**, while each defines its own live kind perfectly. That is Rule 0 of the migration document — deleted, surviving only as `kit-library/D11_DELETED_MIGRATION.md.txt` — and the three that are correct are exactly the three a prior migration wave reached. **Un-migrated documents do not announce themselves.**

**1. Regenerate; do not edit in place.** `generate <kind>` writes the correct root, the kind's declared host recipe and the kind's own specimen **by construction**, so a stale root fixes itself instead of depending on an author noticing it. Editing in place preserves whatever drift is already there — which is precisely how those four survived a twelve-lane wave.

**2. The frame comes from `generate`; the definition is carried by hand — and the circularity is NAMED, not discovered.** A page-kind document defines its own kind, so `generate proof-page` to recreate the document that *defines* `proof-page` is circular. Resolution: take the frame, root and specimen from `generate`, then **lift the `<idea-def>` across verbatim** — never retype it (§4's rule about specimens binds a definition at least as hard). `FORMS.md` decides whether that file was yours to edit at all; read it first. This is the one place in this protocol where a hand copy is the correct answer.

**3. Diff old against new and account for EVERY loss — name-keyed, never by position.** Every `<idea-def>`, every clause, every `data-check` string and every declared field is either present in the new document or **recorded as dropped with a reason**. A rewrite that silently loses content is this corpus's worst failure mode *and it passes every gate* — §7's first reading is why no checker will tell you.

**4. The old document is EVIDENCE, not a TEMPLATE.** Read it for what it SAYS — its prose, its rulings, its clauses. Never copy its structure across. Half the reason a document needs rewriting is that its structure *is* the drift: bare classes, un-migrated chrome, a dead root token. Carrying structure forward is how a migration never finishes.

**5. Not done until you have looked at it — and a rewrite gets a before/after for free.** §7's render gates apply unchanged, and unlike a new page the old document rendered *somehow*, so shooting both is the strongest evidence available at no extra cost. Measured this session: 11 defects by eye / 0 by readouts on one page; 7 of 7 by eye / 0 by readouts on another whose readouts said `pageErrors=0 failedRequests=0 hOverflow=0` throughout.

**Edit in place only when the drift is purely content** — a caption, a row, one added instance, a swapped theme (`wire --theme`, above). Regenerating there throws away authored content to fix nothing. **Say in §8 which you took and why.**

**Either way the page is not finished until §3 has run on it.** A page you edited, regenerated or moved has an import list derived from tokens you changed.

## 3. Wire it — the step between "the page exists" and "the page opens"

```
node <cli> start <kind> <pagePath>              # wiring is part of starting; `wire` alone is the repair form
```

`generate` already runs this, so a generated page arrives wired. **You run it yourself whenever the page did not come from `generate`** — a page you authored, a page an LLM wrote, a page whose `<html data-instance>` you edited, or a page you moved (the paths are relative to where the file sits).

It **derives** the loader line and the `data-import` file list from the tokens on `<html data-instance>` and the relations of any ideas the page defines. **Never type either by hand.** A hand-maintained path list drifts the moment a file moves and nothing checks it; the derivation cannot rot, cannot be half-updated, and cannot disagree with the tokens.

It is **idempotent** — the tag's span is replaced in place, so running it twice writes the same bytes and reports `same`. Put it in a loop or a gate without tracking whether it already ran. `--check` writes nothing and exits 1 if anything would change.

**A library's own documents must be wired too**, or an importing page reaches files that load and push nothing:

```
node <cli> wire --library <libDir> --all --check     # READ FIRST. It writes nothing.
```

A child document serializes its own `<idea-def>` elements and postMessages them **up**; without a loader line it cannot, and the reader meets the red *"N idea file(s) did not arrive"* banner. This is a property of the library, not of your page — if you did not wire it, check whether someone did.

🔴 **`--all` without `--check` first is how a half-landed change gets propagated across every document.** A non-zero `would change` count is not automatically a repair to run: it can be a migration mid-flight, in which case writing spreads the incomplete half everywhere. Read the count, read §0's `_known_state` note, and only then decide. Your page needs `wire <pagePath> --library <libDir>`; it does not need `--all`.

⚠️ **`--library` is not optional on that command, and the bare form is not a shortcut — it fails.** `wire <pagePath>` with nothing else exits **2** with *"no library and no source — nothing says where the ideas live"*. `wire` does not resolve the library for you the way `browse` does; every `wire` invocation in this section names one.

**`wire` writes the library's SOURCE documents, always — there is no layer flag and there should not be one.** A library that also carries an assembled `dist/` is stamped at its sources: a stamp on generated bytes is wiped by the next build, and the file holding it is not the one anyone opens or edits. The run prints which root it read. Two consequences worth knowing before they surprise you: a declared import naming another copy of a resolved document is **dropped and named** in the report, and a wired page therefore imports source paths — so bundle it from its own declarations plus its second hop (`--source`), not from a `--library` pointing at the other layer.

## 4. Fill it with the vocabulary the library advertises

The body you were handed is a **working specimen of the kind**. You replace its content with yours.

**The structure is yours; the words are governed.** This skill owns the page and the widget — it does not own what the content says, and that is exactly the gap [Voice — how we write](https://app.notion.com/p/3c0c52348d1381b59818fab60aeabdd3) fills. Fetch it (`notion-fetch`, id `3c0c52348d1381b59818fab60aeabdd3`) before writing any prose. The rule that fails most often: **the page must state what it is about, what it is not about, and who it is for, at the top.**

### 🔴 If your content has to be GATHERED, read this step BEFORE you gather it

**`§INV_NEVER_GATHER_BEFORE_YOU_READ`.** When the caller hands you the words, the order does not matter. When you have to *go and get* the content — run a measurement, sample a system, query something, collect readings — **the vocabulary decides what is worth getting, so it is read first.** Otherwise you take one snapshot and then spend the rest of the job looking for a unit that happens to fit it.

**Measured on a real run of this skill**, on a task whose content was live system readings. Order taken: `start` → `top`/`ps` → `docs` → `browse`. It gathered before it read, and these are the units that were then unreachable — not by rule, but because the data to fill them no longer existed:

*   `block-confidence-band` — wants an estimate **and its interval** → requires sampling over time
*   `block-delta-gutter` — wants ≥2 rows with a **before and an after** → requires two samples
*   `block-distribution-histogram` — wants ≥2 observations **and buckets** → requires binning a population
*   `block-coverage-heatmap` — wants ≥2 rows **and** ≥2 columns → requires a two-axis matrix
*   `block-gauge-meter-row` — wants 2–4 metrics **each with a threshold** → requires choosing thresholds

**Not one of those can be filled from a single snapshot.** An agent that reads first knows to go back and sample twice; an agent that gathers first never learns there was a reason to. **Gathering is cheap to repeat. Go and take the data again if the vocabulary tells you it is the wrong shape — that is the read working.**

### Before you run anything: why this read is whole

**Read this paragraph before the command, because the command is where the temptation is.** Three invariants own this step and each one closes a failure that has actually happened here:

*   🔴 **`§INV_NEVER_SAMPLE_THE_VOCABULARY`** — **sampling the vocabulary does not give you a thinner page; it gives you a page composed against a smaller library, and nothing in the artifact records which one.** An agent that never read `block-terminal` does not reach for it and does not know it declined it, so the page ships a `codeblock` where a terminal belonged and every gate passes — because a gate grades what is present. **A thin page always looks correct.** That is the whole difficulty: it does not look wrong, it looks like an author with less to say.
*   🔴 **`§INV_LIBRARY_BUDGET_IS_APPROVED_BY_USER`** — the read is genuinely expensive and **the price is the user's to accept, not yours to quietly spend or quietly dodge.** If it will not fit, that is a thing to say out loud, with the number, before composing — not a calculation to make alone. The measured failure mode is not refusal, it is **substitution**: an agent short of context reaches for whichever narrower read it knows about and treats the result as the contract.
*   🔴 **`§INV_NO_UNPRICED_READ`** — the verb tells you what it costs on its first line, in bytes and tokens, before you spend it. Read that line. If a read announces itself as PARTIAL, it is not this step and it does not satisfy this step.

🔴 **YOU HAVE A 1M-TOKEN CONTEXT AND THIS READ SPENDS ABOUT A THIRD OF IT. TAKE IT.** Do the arithmetic once, here, so you do not do a worse version of it under pressure — and **take the number from the verb, not from this line**: `node <cli> browse <anyPage> --stats` composes the body in full, measures it, and discards it. At the last run over this library it printed **790,852 B · ~296.1K tokens** over 58 documents (2026-08-07), and the read as actually *taken* comes in a little above its own prediction — a measured pair was **~291K predicted against ~305K spent**. Add the contract read in §1 at **~29K–34K**; composing afterwards — pasting specimens you already hold and writing prose — is a fraction of either. **That is roughly a third of the window for both mandatory reads, and it still leaves you two thirds of it to work in** — one real run took the whole read and finished the page at 599K total. A `chars/4` estimate says ~197K and understates by about a third, because markup and CSS tokenize near **2.6 B/token**, not 4.

**So the read is supposed to dominate your context. That is the design, not an overrun.** Do not reserve room "for composing": composing is the cheap half, and an agent that protects a budget it was never going to need has spent the expensive half on nothing.

🔴 **AND NEVER DECLINE THIS READ ON A PREDICTION.** Arithmetic over the byte count is not a measurement of whether it fits — it is a guess, and the guess is always pessimistic because it is made by something with an interest in not paying. **The order is: take the whole read. If it genuinely does not fit, you will find out by hitting the limit, not by dividing.** A fallback taken *before* the attempt is a substitution wearing a justification, and it is the exact failure `§INV_NEVER_SAMPLE_THE_VOCABULARY` names — an agent that divided the library's byte count and declined on the quotient composed against a smaller library and could not tell you which one. **And the byte count is not even a constant**: this line quoted `866 KB` until the library measured `789,147 B`, so an agent budgeting off a remembered figure is dividing a number that has already moved.

**If the attempt actually fails**, then say so to the user with the number, take the narrowest partial that still lets you change your mind about what to reach for, and **say in the report that you did.** That is a legitimate outcome. Deciding it in advance is not.

**The reach is the deliverable, not the page.** This step is not diligence and not completeness for its own sake — the whole thesis of this library is that *a form that exists and is visible makes an agent reach for more data, and a form that does not exist makes it write a paragraph and move on.* Skipping the read removes that mechanism and leaves every check green.

### Then run it

```
node <cli> browse <pagePath> > <file>   # THE ONE BIG READ: markup, CSS and clauses for everything on offer
node <cli> browse <pagePath> --unspent  # before you call it finished: what is offered and unused
#  the offer EXCLUDES what this page has already settled — a second page kind or theme is not
#  something it can choose, so it is not listed. `--json` carries `offered`, `spent`, `ruledOutByAxis`.
```

🔴 **`browse` OFFERS THE WHOLE LIBRARY — every idea, not only the ones this page already names.** It resolves `--library` for you and passes it unconditionally, so the first reading is the entire vocabulary, with the ideas this entry has not reached marked `via library`. **Writing the token is the whole of using one** — then re-run `wire` so the file holding it joins `data-import`.

⚠️ **Do not confuse this with `view`.** `view <page>` *without* `--library` resolves only that entry's closure and prints everything else under a heading reading **"NOT REACHABLE FROM THIS ENTRY … not this job's vocabulary."** That heading means *not named by you yet* — never *forbidden* — and it is the reason ideas get re-invented by authors who had already been offered them. **`browse` is the composing verb precisely because it does not put you in that position.**

🔴 **Read that file WHOLE, paging through it with `Read`.** It carries three things and you need all three: the **markup** is for pasting, never retyping (a retyped specimen is a second copy that diverges silently); the **CSS** is what the idea actually keys on; the **clauses** are what it obliges — minimum row counts, closed value vocabularies, the literal text a page owes, and what it forbids anywhere inside itself. The clauses and the CSS can disagree, and when they do the CSS is authoritative: a clause may demand a class the stylesheet abandoned, and satisfying it yields an element that paints nothing.

🔴 **Grepping fragments out of the captured file is not reading it.** It is the same defect one step removed: you only ever see markup for units you had already decided on, so the read cannot change your mind about what to reach for — which is the one thing it is for. If you find yourself running `awk` over it, you are composing from a shortlist you wrote before you knew the vocabulary.

🔴 **READ IT ONCE PER SESSION. IF YOU HAVE ALREADY READ IT, DO NOT READ IT AGAIN.**

This is a **library** read, not a page read — it offers the whole vocabulary regardless of which page you point it at. Read it once, hold it, and compose every page of the session from that one reading. **Re-read only if the library itself changed under you.**

**`--unspent` is the exception and stays per page.** It answers *what did THIS page leave on the table* — genuinely page-specific, and it belongs to the finishing check in §7 rather than to this read.

🔴 **Assert a denominator before composing.** The view prints a rules block per idea. Count them against the ideas you mean to place and stop if the first does not cover the second. Nothing else warns you.

**Rules that each cost a real page:**

*   **ADD A UNIT, NEVER BEND ONE.** If the content does not fit a unit, the unit is not the one you want. A margin note admitting a stretch is the defect *signed*, not remedied. **The remedy is §5** — write the unit, or say plainly that the vocabulary does not cover this and name what is missing.
*   **Read an idea's `excludes` and `degrades to` clauses BEFORE you place it, not after the render looks wrong.** They are the contract you agree to by placing the block, and they catch authors — a clause demanding one row per mark the page actually draws has already caught a real page's unkeyed hue.
*   **An idea with no prior consumer is untested ground, not a discovery.** Say so where you place it.
*   **A green lint is not integrity.** The checker grades what is PRESENT — delete an entire idea and it still exits 0 and prints `clean`. **Never quote an exit code without the idea count beside it.**
*   **Never enumerate what a relation should pull.** A hand-typed list of component names means an idea that should own the combination does not exist yet. Write the idea (§5).
*   **`composes` where `extends` was meant is the most expensive available mistake.** It bundles clean, lints clean, reports nothing missing, and renders **unstyled**. `extends` inherits the rules; `composes` only says a part sits inside. If the page took the base's appearance, you meant `extends`.
*   **Consume tokens by name; never hardcode a hex.** A literal colour is a value that cannot follow a theme.
*   **If you are writing a card, a rail, a section head, a rule or a palette value into the page's own bespoke `<style>`, stop** — the library already ships it, and a page-local copy is a second source of truth that forks the moment the library ships a fix. The page's own style block is for what is genuinely *this page's*, and it usually stays empty.
*   **`HTML_WRITING_STANDARDS.md` binds every authored line.** Elements over delimiters, a parent element per group, never a `style` attribute.

## 5. Author an idea the library does not have

**Skip this section unless §4 dead-ended.** You arrive from exactly one place: the vocabulary does not cover what the page needs, and `--unspent` confirmed you did not simply fail to reach it. **An idea written because the library was under-read is a duplicate, and a duplicate is worse than the paragraph you were avoiding.**

You are authoring a **definition** — an `<idea-def>` with a stylesheet, a declaration, live instances and its rules. `IDEA.md` owns the format of all four. This section owns the **order and the judgements** and restates none of the grammar.

### a. First: does it already exist?

The cheapest step here, and now a machine check:

```
node <cli> lint <libDir>                                  # `name-collision` is HARD: a duplicate name REFUSES
```

**You already hold the answer.** §4's read is the whole vocabulary, so the existence check is a search of what you have, not a second command — and if you cannot answer it from that reading, the reading did not happen and §4 is where to go back to, not here.

Read `omitted` for a name that already does this, then read the *neighbourhood* — if your idea splits a job off an existing one, read that one in full; you may be writing a `variant`. A `QUERY.md` predicate against the library answers "does something already grade this axis" in seconds.

**Why it is first.** A lane that authored six ideas could not run this check at all, and named the cost as the most expensive thing the outage took: not effort, but *the possibility that some of the work was a re-implementation*. Two of its six had a suspected neighbour it could not read one line of. **The check exists now; skipping it is a choice.**

### b. Rule its tier — and state the falsifier

**There is no canonical list of kinds to look this up in; `LIBRARY.md` says why.** A kind exists because an idea uses it, so **every tier is a judgement that ships with an argument, not a label.** What has actually decided these:

*   **Can it go in a sentence?** A block has a box and a box cannot sit inside a line of prose. An idea the corpus writes *inside* sentences is an atom however many facts it carries.
*   **Are its facts parts or attributes?** Stacked parts that must appear in one order to make their point → block. One element carrying N attributes → atom.
*   **Editorial content, or presentation scaffolding?** Chrome is reached by `presents with`, dormant by default and resolved only when presenting. An idea a page needs on *every* render is not chrome, however much it looks like a wrapper.
*   **Atoms take no tier prefix and no `extends`** — so a wrong tier is a rename plus an edge, not a redesign. (Stated as settled here for years on the authority of a retired document that had it filed as an OPEN QUESTION. Treat it as a working convention, not a ruling, until a shipped file confirms it.)

🔴 **State a falsifier with every ruling** — the concrete future observation that would make it wrong ("if a page ever needs the bar without the reading beside it, this ruling is wrong and the bar splits out as an atom"). A tier ruled without one is an assertion; with one it is a decision the next person can overturn on evidence rather than taste. A lane that did this overturned two of its own brief's leanings, and both held.

### c. Rule its placement

**Name is identity, and a name is not a location** (`LIBRARY.md`). The file does not affect whether an idea resolves — it affects who finds it and how many cross-file edges the library carries.

*   **Co-locate to keep an edge intra-file.** If your idea `composes` another, the same document removes a cross-file edge for free.
*   **A grouped set splits by kind** — an atom does not belong in a file of blocks.
*   🔴 **If you cannot name the file honestly, leave it OWED.** Inventing a path to complete the table is inventing vocabulary, and the real path is one `ls` away for whoever lands it. OWED with the neighbourhood named is a finished ruling; a made-up path is an unfinished one wearing a tick.

Report placement as a **table with a reason per row.** The reason is the deliverable; the path is the easy half.

### d. Declare it

🔴 **The declaration row's grammar, the field vocabulary, and what is never a field all live in `IDEA.md`. Read them there — nothing here restates them, deliberately.** A second copy of a format spec is the defect this corpus exists to remove, and the copy is the half that goes stale.

What this section owns is the honesty rule on top of the grammar:

*   🔴 **DO NOT INVENT VOCABULARY.** Any field you cannot derive honestly is left **owed**, not filled. A filled row nobody can trace is worse than an empty one, because the empty one asks to be finished.
*   🔴 **Write no relation edge to a name you could not corroborate.** `LIBRARY.md` puts a `requires` naming something unreachable in the same class as a syntax error. Record it as an open question instead: an idea that under-declares its composition can be fixed, one that mis-declares it fails.
*   **`fits` predicates are `QUERY.md`'s grammar.** Read the grammar; do not pattern-match a specimen. A predicate spelled from a document is one nobody has parsed.

### e. Declare AND bind every closed set

**A closed set declared but not bound is a comment.** Declaring it (`data-attribute-name` / `-type` / `-enum` / `-description`) tells a reader the values; **binding it** is what makes a wrong value a finding.

*   **The bindable form is `absent` over the complement** — nothing exists carrying the attribute with a value outside the set:
    `absent [data-instance~="x"][data-foo]:not([data-foo='a']):not([data-foo='b'])`
*   🔴 **`vocab` cannot do this and neither can `attr`.** `vocab` reads `classList`, so it cannot grade an attribute *value* at all; `attr` tests presence only. Three families of malformed clause shipped through that gap. If your clause reads like it grades a value and uses either verb, it grades nothing.
*   **`data-attribute-scope="part"`** when the attribute sits on a descendant. `self` is the default and is never written.
*   **Take the verbs from the checker, not from a specimen** — a specimen is a *copy of* the checker's vocabulary, and a verb spelled from a document is one nobody confirmed.

**Count both sides and report the pair**: N declared, N bound. A lane that wrote nine and bound nine still recorded the caveat that mattered — **none had ever been run**, and a clause that has never failed has not been shown to work. Say which of yours have run.

### f. Write the CSS the idea owns

*   🔴 **Every rule keys on the idea's own token, in the LAST compound** (`¶INV_RULES_KEY_ON_THE_LAST_COMPOUND`). Getting this wrong is the `class-layer-bare` defect — the corpus's largest finding class, most of it manufactured by otherwise-correct work.
*   🔴 **An idea that wraps or annotates another idea's element may NEVER claim a pseudo-element on it.** `::before` and `::after` are one slot each; taking one silently unpaints whatever the owning idea drew there, with no error anywhere and every DOM readout green. One lane's single most expensive mistake, and only the picture showed it. A mark on someone else's element is **its own element**.
*   **`attr()` reads the attribute of the element its pseudo-element originates from, and nowhere else.** A line drawn from a wrapper's attribute prints its label with no value and passes every structural check. Put the attribute on the element that draws it, or scope it `part`.
*   **Demo CSS goes in `<style data-demo>`, a direct child of the `<idea-def>`, after the contract style.** A second *unmarked* `<style>` after the receipt trips `receipt-last`. **The receipt is planted last.**
*   **The idea's rules go in the idea; a page-level reset does not.** A reset keyed so the control receives it makes the control look serviced — the one thing a control may not do.

### g. Ship a control, and a specimen that teaches

`§INV_SPECIMEN_SHIPS_A_CONTROL`: the idea ships beside the same markup *without* its token, so a reader can see what the idea actually does.

🔴 **A control indistinguishable from a defect fails at its own job.** If any ambient stylesheet, page reset or bare-class rule paints your control, the control proves the *opposite* of its caption while every automated check stays green. Before you trust one, confirm nothing on the page styles the un-tokened shape.

**The same logic runs inside the idea:** absent, zero and unknown must be *visibly different pictures*. A meter rendering "0 of 55" identically to "nobody counted" has lost the distinction it exists to carry.

**Specimens carry REAL content** — lorem cannot show that the idea does its job. Where you have the phrase but not the measurement behind it, **do not fabricate the receipt**; render the marked-absent state, which doubles as the subject-absent control. For each specimen be able to finish: *what a reader learns from this that a sentence could not have told them.* If you cannot, the idea is not earning its place yet.

### h. Then lint it, render it, and LOOK

§7's gates apply unchanged, plus three the idea path adds:

*   **`lint` catches `name-collision` HARD**, so a green lint here is a real answer to step (a) — and still not integrity: quote the **idea count**.
*   **Render the idea AND its control in one shot** and compare by eye. This is the reading that catches everything else in this section.
*   **Render the pair the idea claims not to disturb.** If it annotates, wraps or marks something, shoot the annotated and un-annotated element side by side and read both geometries. That claim is unfalsifiable as prose and a check anyone can run with their eyes as a picture.

**The measured base rate: on a page of six new ideas, 7 of 7 defects were found by opening a shot. 0 by the readouts, which reported `pageErrors=0 failedRequests=0 hOverflow=0` throughout.**

## 6. Bundle it — ON by default

```
node <cli> ship <pagePath>                      # bundle + re-bundle identity + open the BUNDLE
```

**Bundling is a PUBLISH step, not a RENDER step.** A wired page already renders; the bundle makes it **travel** — one self-contained file, zero subresources, correct from any directory, correct with JavaScript off. Take it unless you have a reason not to.

**`--no-bundle` — when to skip it.** Skip when the page must stay a *source* you keep editing, when it lives beside its library and will never move, or when you are iterating and the round-trip is noise. The page still opens; it just reaches for its library at read time.

> 🔴 **`--no-bundle` depends on the wiring being live.** If `wire` has not been run on the page (or on the library's documents), the unbundled page opens **structurally complete and entirely unstyled** — the measured symptom is a red *"N idea file(s) did not arrive … loaded but pushed nothing (does it carry the loader?)"* banner, or no banner at all and simply no theme. A flag that silently does not work is worse than a documented one, so: **if the page opens unstyled, the first thing to check is `wire`, not the content.**

Bundling replaces the wired page's loader tag **in place** with the runtime it inlines, so the output still declares exactly one script and a re-bundle of an unchanged page reproduces its own bytes. **The definitions are never yours to place**: the bundler resolves the `requires` closure, emits it in dependency order, refuses on a HARD finding or a cycle, and reports every unresolved name as `MISSING` rather than dropping it. Hand-inlining `library.css` or pasting a definition into the page is the second copy this whole system removes.

## 7. The gates — every one of them, with the command and the number

Paste the exact command and its exit code. **An exit code without a count beside it proves nothing.**

1. **`node <cli> check <pagePath>`** — 🔴 **THE GATE. It grades YOUR PAGE, which nothing here used to do.** It runs `wire --check`, `lint <library> <page> --evaluate` (which opens a real browser by default) and a rendered geometry pass, then prints one report ordered by what each defect costs a reader: **DEAD** (the page cannot render right) · **FAIL** (a clause is false of it, element named) · **CLASS** (rules on a class no idea claims) · **MEASURE / COLUMN / GLYPH / INLINE** (geometry — characters per line, a starved column, an inline unit that wrapped) · **OWED** (a region the kind requires, carried and unfilled) · **UNSPENT**. Every line names an element and an action. **Exit 0 means nothing blocking.** Record the summary line verbatim.
   *   **`--width 390`** is a SECOND run and PAGE_RULES Rule 11 requires it: a column that survives 1400 can amputate at 390.
   *   **Never quote the median alone.** Measured on a real page, the median was 40 (passing) while four named blocks ran 119, 114, 107 and 94. A readout saying "median 40 — green" is not unhelpful, it is wrong.
1.5. 🔴 **THE GEOMETRY PASS — run it after gate 1, before you call the page done.** Re-read your own page asking one question: **what is wrong here that a LAYOUT or a MODIFIER fixes?**

**This step exists because it was measured.** On a real run, the tweaks after generation split like this: the gates caught 5, opening the images caught 3, and **this question caught 5 more — taking PASS from 200 to 224 and every MEASURE finding to zero.** The agent's own account of why it had not already done it is the reason the step is now mandatory:

> *"I composed down the page kind's required-regions list, then reached for the loudest blocks. Modifiers and layouts don't appear in a required-regions list. They're the tier you reach for when you notice a geometry problem, and I was treating geometry as something the blocks already owned."*

**A required-regions list is a checklist, and an agent composes down a checklist.** `layout-*` and `use-*` are on nobody's checklist — no kind requires them, no region owes them — so they are never reached for, however completely you read the vocabulary. **Reading the whole offer does not fix this. Only asking does.**

What the pass actually looks for, each with the shape of defect it answers:
*   a **MEASURE** finding → a prose track that is not capped. `layout-prose` caps the TRACK, not the box — and a `>`-keyed cap is deleted by one wrapper.
*   a **COLUMN** finding, or cells that should share a column count → `layout-fit` does the arithmetic over the container; you never type a number.
*   an attribute the markup already declares that **nothing is drawing** — a `data-focus`, a `.focus` cell, a pin with no counter-reset. That is a modifier the page is owed and has not written.
*   a mark on someone else's element → `use-annotated` + `inline-pin`, never a pseudo-element on an idea you do not own.

**Every addition must remove a NAMED defect.** A layout added because the page looked plain is decoration, and the two are told apart by re-running gate 1 and reading the count.

2. **`node <cli> lint <libDir>`** — the LIBRARY gate, and a different subject from gate 1. Record exit code, **HARD count and SOFT count and file/idea count**. Compare HARD against the library's known baseline; **HARD must not rise**. A green lint on a shrunken corpus is the failure this reading exists to catch. **Run it only if you touched the library** — a page-composing lane does not need it.
3. **`node <cli> ship <pagePath>`** — bundles it, **re-bundles the emitted page and diffs the two**, and **opens the BUNDLE** rather than the entry (they are different documents: the entry FETCHES its ideas, the bundle CARRIES them). It counts duplicate `<idea-def>` names itself, matching across newlines — the attributes wrap in this corpus and a single-line `grep` silently reports fewer than exist. Exit **0** means one file, a fixed point, and it opens.
4. **Re-bundle byte-identity, BOTH arms.** Unchanged → `same … (already there, identical)` exit 0. One hand-edited byte in the output → `REFUSE … (holds N B of different bytes)` exit 1. Observe both; the second arm is the one that proves the first means something.
5. 🔴 **DOES THIS PAGE ACTUALLY OPEN.** The gate nobody had. Open the page from `file://` in a real engine and read:
    *   the red **`[data-idea-import-failed]` banner** — absent, or the page did not resolve
    *   **`pageErrors`** — 0
    *   **`--ink` (or the theme's own token) resolved at `:root`** — a *value*, not empty. This is the only reading that distinguishes "linked" from **"loaded"**. If you passed `--theme`, read a `--t-*` slot too: `--ink` alone falls back to the alias bridge's deliberately-ugly neutral, so it resolves to a value even when no theme loaded at all
    *   **`idea-def` live on the page**, counted against the bundler's `walk order N`
    *   **head `<style>` count** and **`bodyOverflow`** — 0 is the bar for overflow
    *   run it on the **unbundled** page too if you shipped one; that is the reading that proves `--no-bundle` works
6. 🔴 **OPEN THE SHOT AND LOOK AT IT.** Element shots at **DPR 1**; **never `fullPage` above 16,384 CSS px** — Chrome's maximum texture dimension — so measure the height first and **say on the record when you skip it**. 🔴 **The failure is SILENT, not a truncation and not a blank**: above the ceiling the capture returns a PNG of the *correct dimensions containing wrong pixels*, `capturedH` still equals `docH`, and nothing throws. An agent verifying against a truncation sees the height match and ships a corrupt shot — **the only reading that catches it is looking at the image.** (`idea-cli/lib/shots.ts:67` carries the number and `idea check --help` states both halves; the ~7,900 figure this line used to give was inherited, transcribed eight times, and wrong by 2.07×.) A definition-dense page runs past even the real ceiling at narrow widths, so element shots are not a preference there, they are the only option. Every rendering defect in this corpus was found by looking, never by a readout.

**When a defect appears in the render, get a control before you blame your change.** Render the *other* shape — bundled if you were looking at wired, wired if you were looking at bundled — and compare. A defect present in both is the library's and belongs in a report, not in a fix you were not asked for.

**`grep -a` inside the CLI's own source.** Some of its files carry literal NUL bytes, so plain `grep` silently reports nothing and you conclude the opposite of the truth.

## 8. Report

One block, and it is the artifact people read after you are gone:

*   **what the page is** — kind, subject, path, and whether it is wired, bundled, or both; and **if the page already existed, whether you regenerated or edited in place, and why**
*   **every gate as `exact command → exit code → the counts`**
*   **the shot you opened and what you saw in it** — not "renders correctly", but what is on the page
*   **what you reached for and what you did not** — the unspent vocabulary, named
*   **every gap you met**: a kind that did not exist, a unit you wanted and had to do without, a defect present in the control

**If you authored an idea (§5), the report also carries:**

*   **the tier ruling per idea, with the argument and the falsifier** — and say which rulings you overturned against your own brief
*   **the placement table, with a reason per row** and every path honestly marked OWED rather than invented
*   **closed sets: N declared, N bound — and how many have ever RUN.** A clause never run is a promise, not a check, and saying so is the whole of its value
*   **dead ends and what they cost** — the approaches that got far enough to be worth not retrying, each with the reason it died. This is the invisible work and it is the part the next person cannot reconstruct
*   **what you could not do** — the gate that was unavailable, the name you could not corroborate, the edge you did not write. An OWED row is a finished ruling; a silent gap is not

## Anti-Patterns

*   **Composing from a path you did not resolve.** §0 exists because a brief naming an absent directory is the failure it removes.
*   **Carrying a list of page kinds, theme names, or idea names.** All three are derived on every run. A list in a prompt is stale the day the library grows, and a skill that asserts a kind does not exist is worse than one that stayed quiet.
*   **Retyping a specimen — or a definition.** Paste it. A retyped copy diverges and nothing notices.
*   **Hand-typing `data-import` or the loader line.** Run `wire`. If you are typing a list of file paths, you have re-created the registry this system retired.
*   **Running `wire --all` without reading `--check` first.** A `would change` count can be a migration mid-flight; writing propagates its incomplete half everywhere.
*   **Quoting a green exit code with no count.** The checker grades what is present.
*   **`composes` where `extends` was meant.** Clean on every readout, unstyled on the page.
*   **Bending a unit to fit content.** Add one (§5), or say the vocabulary does not cover this.
*   **Writing an idea before running the "does it already exist" check.** It is one command now. An idea that duplicates one you did not read is worse than the paragraph you were avoiding.
*   **Declaring a closed set and not binding it**, or binding it with `vocab`/`attr`, which cannot grade a value.
*   **Claiming a pseudo-element on an element another idea owns.** Silent, total, and invisible to every readout.
*   **Filling a declaration row you cannot derive.** Leave it owed.
*   **Declaring victory from a readout.** The last gate is a human looking at a shot.
*   **Dispatching this.** It is in-context by construction; a subagent gets a summary of the thing you are holding.

## Constraints

*   **In-context, no handoff.** No subagent, no brief, no Path-A/Path-B split.
*   **It produces a page and, when the vocabulary genuinely lacks a unit, an idea.** It never commits, never files a ticket, and never bends an existing idea to make a page fit.
*   **It never invents a page shape and never invents vocabulary.** Kinds come from the library; a missing kind is a finding; a field that cannot be derived is left owed.
*   **Every tier and every placement is a judgement that ships with its argument and its falsifier.** There is no lookup table to defer to, and a ruling without a falsifier is an assertion.
*   **The caller supplies words and choices. The skill supplies structure and proof-of-correctness.**
