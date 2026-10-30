---
id: asktree-build
to: operator
from: meta:utils
why: which decision-tree improvements get built, and by whom
importance: medium
stakes: teaching agents before TRAPS lands makes them write more broken options
context: /home/user/project/sessions/2026_10_29_PROOF_ASK_UI/builds/ASKTREE_RESEARCH.md
alternatives: TRAPS; FLOOR; SHOWFOLLOW; FIELDS; TEACH; COMPARE
lean: TRAPS, FLOOR and SHOWFOLLOW first — cheap, and they stop asks getting thinner
falsifier: FLOOR refuses so many asks that agents stop asking and decide in chat
status: answered
revision: 5
dependsOn:
created: 2026-10-30T09:37:41.228Z
tickets: IDE-304
topic: decision trees: richer options and nesting
reserved-for: operator
revisions: 2@2026-10-30T09:38:20.095Z:body
forwards: manager:meta→manager:director@2026-10-30T09:38:40.443Z ; manager:director→operator@2026-10-30T09:39:04.542Z
delivery: delivered
deliveryNote:
reads: meta:utils@2026-10-30T12:50:55.249Z ; manager:meta@2026-10-30T12:51:01.812Z
readAt: 2026-10-30T12:50:55.249Z
readBy: meta:utils
acted: Relayed: meta:engine TRAPS/FLOOR/FIELDS parser/TEACH; meta:utils SHOWFOLLOW/FIELDS render/COMPARE; fields = Unblocks, Then, Elegance.
actedAt: 2026-10-30T12:51:23.372Z
actedBy: manager:meta
---

The decision-tree research you asked for at 17:22 is finished. The full report is `/home/user/project/sessions/2026_10_29_PROOF_ASK_UI/builds/ASKTREE_RESEARCH.md`.

The research ran the parser over all 355 ask files: 594 questions and 1,608 options.
- Only 17.6% of options carry both a description and a Cost. 17% are a bare label.
- Bare labels are rising: 11% of options on 10-28, 17% on 10-29, 23% on 10-30.
- Nested follow-ups are almost unused: 1 question in 594 nests options, and 19 use `DependsOn:`.

It also found two traps that silently break today's asks:
- **Name after kind.** 167 question headings put the name after the kind word (`## Choose one: ¶ASK_X …`). The parser does not read that order. Those questions are stored as q0, q1… and no follow-up can point at them. I recounted 167 myself.
- **Indented bullet.** An indented `- ` bullet under an option becomes an extra, codeless option you can pick, with no warning. That is the first thing an agent would write when asked to "say more about each answer". So the teaching has to wait until this is fixed.

Who builds what: the parser, `engine ask new` checks and the ask skill are meta:engine's, so I would hand those over. The rendering in the app is mine.

## ¶ASK_TREEFIX: Choose: Which parts do we build first?
- [ ] [TRAPS] Fix the two silent traps (recommended)
  Indented bullets become description text. `ask new` and `revise` refuse a heading with the name after the kind word. meta:engine builds it. Undo: revert one commit.
  Cost: none to you; meta:engine's queue grows by one small round
  Effort: S
- [ ] [FLOOR] Refuse bare options and questions with no context (recommended)
  `ask new` refuses 257 bare options (in 54 asks) and 121 questions with no context of their own. It warns, without refusing, when an option lacks a description or Cost; that would fire 1,010 times. It follows the pattern of the code-block-language check that just landed. meta:engine builds it.
  Cost: agents get refused more often, and an ask takes longer to write
  Effort: S
- [ ] [SHOWFOLLOW] Show follow-ups and a one-way badge in the app (recommended)
  Under an option, the app shows "Opens ¶ASK_X" or "+N follow-ups" before you pick it, plus a reversible/one-way badge and a consequence line. I build it.
  Cost: one more thing in my queue, after the withdrawn status
  Effort: S
- [ ] [FIELDS] New per-option fields: Reversible, Unblocks, Then
  `Then:` holds what the asker does next if that option is picked. The parser and the app both learn the fields, built by meta:engine and me.
  Cost: more for agents to fill in; worth it only together with FLOOR
  Effort: S each
- [ ] [TEACH] The teaching section in the ask guide
  A checklist, a rule for when to nest, and a before/after rewrite of a real thin ask. It lands only after TRAPS. meta:engine owns the skill.
  Cost: a longer guide that every asking agent reads
  Effort: S
- [ ] [COMPARE] Compare table and a question outline in the app
  A side-by-side view of options, and an outline for asks with many questions, re-built from the prototype's design. I build it.
  Cost: a medium build; the director dropped the earlier port of this
  Effort: M

## ¶ASK_TREEORDER: Choose one: Should the parser also accept the name after the kind word?
DependsOn: ASK_TREEFIX=TRAPS
Lean: REFUSE — one form is simpler, and the old asks keep working as they are
- [ ] [REFUSE] No, refuse that order and keep one form (recommended)
  `new` and `revise` refuse it and name the fix. The 105 old asks stay keyed q0, q1….
  Cost: the old asks keep their positional keys
  Effort: S
- [ ] [BOTH] Yes, accept both orders
  Both headings parse to the same name. This needs an alias, so answers already stored under q0, q1… still match their questions.
  Cost: two spellings forever, plus an alias that is easy to get wrong
  Effort: M

```json answer
{
  "answers": {
    "TREEFIX": [
      "TRAPS",
      "FLOOR",
      "SHOWFOLLOW",
      "FIELDS",
      "TEACH",
      "COMPARE"
    ],
    "TREEFIX.other": "a note on which per-option fields to add",
    "TREEORDER": [
      "REFUSE"
    ]
  },
  "answeredBy": "operator",
  "answeredVia": "browser",
  "answeredAt": "2026-10-30T12:50:40.741Z",
  "revision": 5
}
```
