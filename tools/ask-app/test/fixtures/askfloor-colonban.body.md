# Colon-title ban: three choices before the parser change (COLONBAN)

**Context.** You ruled "no title after `:`; the whole tail is the value". A parser-based count on main (caa7cb9a9, after the colon port) finds **67 tracked lines** that put a title after `:` today: 46 in .idea files and 21 in Markdown fences. Another 14 are in inline examples, among them the 8 GRAMMAR ones. Language owns 48 of them. The rest belong to core:ui (5), app:writer (5), domain:platform (4), packages:converge (3), docs:handbook (1) and domain:stats (1). The rewrite moves the title in front of the entries: `price num agent: plan Price` becomes `price num Price agent: plan`, and the compiled output is identical. Today's parser misreads that new form with no error, so the order is: (1) the parser reads title-first, (2) each owner's lines are rewritten, one commit per owner, (3) the flip makes the tail all value. Plan: ~/project/sessions/2026_10_29_LANGUAGE_LOOM/builds/COLONBAN_PLAN.md

## Choose one: ¶ASK_COLONBANEND — where does a title end?
Lean: WORD.
- [ ] [WORD] At the first unquoted `word: `; a title that really contains one is written quoted (Recommended)
  One simple rule. Only titles containing a colon need quotes.
- [ ] [QUOTE] Every title before entries must be quoted
  Never ambiguous, but every rewritten line gains quotes.

## Choose one: ¶ASK_COLONBANRUN — does an earlier entry's value run to the next `, word:`?
Lean: RUN.
- [ ] [RUN] Yes, a value runs to the next `, word:` (Recommended)
  Multi-word values work in any position, which matches "the whole tail is the value".
- [ ] [ONEWORD] No, only the last entry takes multiple words
  Stricter, but `a: two words, b: x` refuses.

## Choose one: ¶ASK_COLONBANDROP — titles that only repeat the name
Lean: KEEP.
- [ ] [KEEP] Move them like the rest; dropping one is each owner's separate call (Recommended)
  53 of the 67 titles only repeat the name, but dropping one removes `title` from the schema, so the rewrite stays output-identical.
- [ ] [DROP] Drop name-repeating titles as part of the rewrite
  Shorter lines, but the compiled schemas change for 53 members.

