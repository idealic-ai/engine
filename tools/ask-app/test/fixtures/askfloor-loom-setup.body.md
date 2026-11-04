This loom opened on its defaults and keeps working on them while these are open. Each question below sets one disposition for the whole weave; an answer replaces the default it overrides, and the ledger header records who chose it.

## ¶ASK_AUTONOMY: Choose one: Autonomy
Autonomy tunes how much the conductor resolves without asking you, never which steps run. Until you answer, the loom runs on Careful, so it escalates liberally and gates more.
- [ ] [AUTO] Automagic
  The conductor proceeds on its own, auto-resolves conflicts where safe, and escalates only the hard floor.
  Cost: fewer of its judgement calls reach you before they are acted on
- [ ] [CARE] Careful
  The conductor escalates liberally and gates more.
  Cost: more asks reach you, and lanes wait on them
- [ ] [AGNT] Allow agents to decide
  Agents use their own judgement on when to escalate, and the conductor relays.
  Cost: what reaches you depends on each lane's judgement

## ¶ASK_COUNCIL: Choose one: Council
Council decides when an expert panel reads the work. The default offers one panel on the assembled branch once nothing more will land on it, and nothing runs until then.
- [ ] [ASSM] On the assembled branch, when it is complete
  One panel reads what the lanes add up to.
  Cost: a defect in one lane is found late, at the branch
- [ ] [FLAG] Per PR, flagged only
  A panel reads one thread's branch, only on a thread you name.
  Cost: threads you do not name get no panel
- [ ] [NONE] None
  No panel runs at all.
  Cost: nothing reads the whole of the work but its lanes and the PR reviewers

## ¶ASK_SCRUTINIZE: Choose one: Scrutinize
Scrutinize decides whether an independent critique reads each lane before it is proposed. The default runs one on every build lane, which roughly doubles the lane count but means no lane is reviewed only by its author.
- [ ] [EVRY] Every build lane
  A critique agent reads every lane that wrote code, as it hands back.
  Cost: one more agent per lane
- [ ] [RISK] Lanes the conductor names risky
  The conductor judges per lane, and every lane it passes over says so on its row.
  Cost: the judgement belongs to the party that skipped before
- [ ] [OFF] Off
  No critique runs; the lanes' own reports are the only reading.
  Cost: nobody but the author reads the work before it is proposed
