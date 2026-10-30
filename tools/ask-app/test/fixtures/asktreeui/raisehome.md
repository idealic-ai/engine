---
id: 20261030-155443-where-does-raiserend-s-checkpoin
to: manager:core
from: core:kernel
why:
importance:
stakes:
context:
alternatives:
lean:
falsifier:
status: open
revision: 1
dependsOn:
created: 2026-10-30T15:54:43.664Z
reserved-for: operator
---

Tickets this question names:
- [IDE-17](https://linear.app/example/issue/EX-1) "Example ticket A" [In Progress]. Its last checkpoint lists the work below as a leftover.
- [IDE-36](https://linear.app/example/issue/EX-2) "Example ticket B" [Backlog]. Its acceptance covers the function this work extends.

RAISEREND landed on main as four commits: a refusal message now renders in one place. It has no ticket. `/snapshot --yes` drafted a new ticket and then stopped, as it must, because the duplicate search found the two overlaps above. Draft ticket and checkpoint comment: /home/user/project/sessions/example/builds/raiserend_SNAPSHOT.md. Verified from origin; the gates pass.

## ¶ASK_RAISEHOME: Choose one: Where does RAISEREND's checkpoint go?
Stake: every landed change has a ticket. This one has none until this is answered, and its proof page waits on the key.
Context: IDE-17 already names this exact work as an owed leftover. IDE-36's premise is the `${…}` lowering, and RAISEREND only touches the same function.
Lean: IDE17
Counter: IDE-17 is the web-server switch-on ticket, so a kernel renderer checkpoint there buries kernel work in a deploy ticket; a ticket of its own keeps the project's record whole.
Reversible: a comment can be followed by a separate ticket later; a filed ticket can be closed as a duplicate.
IfUnanswered: nothing is filed or posted; the work stays landed and un-ticketed, and its proof page waits.
- [ ] [IDE17] Post the checkpoint on IDE-17
  Re-run `/snapshot --yes -- IDE-17`: the checkpoint comment goes on IDE-17 and closes the leftover it lists. No new ticket. IDE-17 stays In Progress for its other work.
  Cost: the project gets no ticket for this change.
  Elegance: high, because IDE-17 already names this work.
  Then: re-run the snapshot with that key and write the proof page against IDE-17.
- [ ] [NEW] File the drafted ticket anyway
  File the draft in the example project as its own ticket, move it to Done, post the checkpoint there, and add a one-line comment on IDE-17 saying its leftover is closed by the new key.
  Cost: one more ticket, and a second place that tells the story.
  Elegance: med.
  Then: file it through /ticket (it needs your confirm here), then the snapshot with the new key.
- [ ] [HOLD] Leave it un-ticketed for now
  Nothing is filed or posted.
  Cost: a landed change with no ticket; IDE-17 keeps listing it as an open leftover.
  Elegance: low.
  Then: nothing until you decide.
