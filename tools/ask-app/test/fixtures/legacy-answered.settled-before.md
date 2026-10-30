---
id: 20261029-142923-rule-1-after-a-conductor-restart
to: manager:core
from: core:exchange
why: Two durable rules have sat in an inheritance block as 'operator to rule' with no ask behind them.
importance: low
stakes:
context:
alternatives:
lean:
falsifier:
status: answered
revision: 3
dependsOn:
created: 2026-10-29T14:29:23.799Z
tickets: IDE-186
stake: Without a ruling the next conductor restart can redispatch a live lane.
confidence: high on the facts
delivery: delivered
deliveryNote:
replaced: revision 2 by manager:core at 2026-10-29T15:34:02.869Z; was RESUMELANES LOOM, NOCHECKOUT DECLINE
---

The exchange loom learned two rules it is not allowed to land.

## ¶ASK_RESUMELANES: Choose one: rule 1, after a conductor restart, resume surviving lanes first
Context: The loom skill never mentions ListAgents.
Lean: LOOM. It's a loom-protocol step.
- [ ] [LOOM] Land it in the loom skill's resume text
  One sentence in skills/loom.
  Cost: one more line in a file every loom loads.
- [ ] [DECLINE] Decline it
  Rely on judgement.

## ¶ASK_NOCHECKOUT: Choose one: rule 2, never use git checkout as a probe
- [ ] [EXAMPLE] Add one example line
- [ ] [DECLINE] Decline it as already covered

```json answer
{
  "answers": {
    "RESUMELANES": [
      "DECLINE"
    ]
  },
  "answeredBy": "manager:core",
  "answeredVia": "cli",
  "answeredAt": "2026-10-30T00:00:00.000Z",
  "revision": 3
}
```
