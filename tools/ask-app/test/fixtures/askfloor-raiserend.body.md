Tickets this question names:
- [IDE-17](https://linear.app/example/issue/IDE-17) "ideas.app's web server binds the market, and the fixes owed before switch-on are closed" [In Progress, since unread]. Its 2026-10-29 checkpoint lists "Kernel: one renderer for compiled refusal messages" as a leftover and as fragility 3, which is the work below.
- [IDE-36](https://linear.app/example/issue/IDE-36) "${…} in a JSLT string has one meaning, lowered in one place that every filler uses" [Backlog, since unread]. Its acceptance (e) and (f) cover resource-kernel's renderRefusal, the function this work extends.

RAISEREND landed on main at 21:16 as 0de418fd3, 5eab586cd, 35f6b146d and 8e29df7d2: a refusal compiled from an `.idea` now renders its message in the kernel, so no door evaluates a compiled message formula itself. It has no ticket. `/snapshot --yes` drafted a new ticket in Product: Resources & Platform and then stopped, as it must, because the duplicate search found the two overlaps above. Draft ticket and checkpoint comment: ~/project/sessions/2026_10_29_KERNEL/builds/raiserend_SNAPSHOT.md. Verified from origin at 3863b4d38: all four commits are ancestors, the three receipts recompute, kernel refusal tests 49 passed, gate 0, contracts:verify 0, market-doors 57 passed with 4 PostgreSQL-only skips.

## ¶ASK_RAISEHOME: Choose one: Where does RAISEREND's checkpoint go?
Stake: under Linear-first, every landed change has a ticket. This one has none until this is answered, and its proof page waits on the key.
Context: IDE-17 already names this exact work as an owed leftover. IDE-36's premise is the `${…}` lowering, and RAISEREND only touches the same function.
Lean: IDE17
Counter: IDE-17 is the web-server switch-on ticket, so a kernel renderer checkpoint there buries kernel work in a deploy ticket; a ticket of its own keeps Product: Resources & Platform's record whole.
Reversible: a comment can be followed by a separate ticket later; a filed ticket can be closed as a duplicate.
IfUnanswered: nothing is filed or posted; the work stays landed and un-ticketed, and its proof page waits.
- [ ] [IDE17] Post the checkpoint on IDE-17
  Re-run `/snapshot --yes -- IDE-17`: the checkpoint comment goes on IDE-17 and closes the leftover it lists. No new ticket. IDE-17 stays In Progress for its other work.
  Cost: Product: Resources & Platform gets no ticket for a kernel change.
  Elegance: high, because IDE-17 already names this work.
  Then: re-run the snapshot with that key and write the proof page against IDE-17.
- [ ] [NEW] File the drafted ticket anyway
  File the draft in Product: Resources & Platform (P-IDE-11) as its own ticket, move it to Done, post the checkpoint there, and add a one-line comment on IDE-17 saying its leftover is closed by the new key.
  Cost: one more ticket, and a second place that tells the story.
  Elegance: med.
  Then: file it through /ticket (it needs your confirm here), then the snapshot with the new key.
- [ ] [HOLD] Leave it un-ticketed for now
  Nothing is filed or posted.
  Cost: a landed change with no ticket, against Linear-first; IDE-17 keeps listing it as an open leftover.
  Elegance: low.
  Then: nothing until you decide.

