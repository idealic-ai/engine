---
id: council-panel-picks
to: manager:meta
from: meta:utils
why: how panel results appear on asks, and whether old asks are back-filled
importance: medium
stakes: a pick shown in the wrong place reads as the asker's recommendation
context: /home/user/project/sessions/2026_10_29_PROOF_ASK_UI/builds/COUNCILUI_CRITIQUE.md
alternatives: COUNT; MAJORITY / LEAVE; ATTACH
lean: COUNT — the panel's view sits on each option, not in the asker's bar
falsifier: you look for the panel's pick in the Suggested picks bar first
status: open
revision: 1
dependsOn:
created: 2026-10-30T15:16:32.185Z
tickets: IDE-338
topic: panel results on asks
reserved-for: operator
---

The app can now show panel results: a link to the council report, each lens's pick and why, and "2 of 3 lenses picked this" on each option. It is on a branch, not live yet.

Your question about where panel suggestions show turned out to have two causes:
- The app could not show them. That is now built.
- Agents almost never record them. I parsed all 430 asks: only 2 questions carry `Panel:` lines, and 8 answered asks say in prose that a council ran but record nothing on the question. Example: manager:docs/voice-v2-202610300727.md.

Old asks keep showing nothing until an asker writes `Panel:` lines or attaches the panel. Meanwhile the app will show the line "A council is named here, but no lens reads were recorded". New asks get a warning from `ask new`, and /council and /decide now write the lines themselves.

## ¶ASK_SUGGEST: Choose one: Should the panel's picks also pre-fill the "Suggested picks" bar?
Lean: COUNT — the count on each option shows the panel's view without making it look like the asker's recommendation
- [ ] [COUNT] No, show them only as the count and the disclosure (recommended)
  The dashed "Suggested picks" bar keeps meaning the asker's own lean. The panel's view sits beside each option as "N of M lenses picked this".
  Cost: you read the panel on each option rather than in one place
  Unblocks: nothing; this is what's built
  Then: no change
  Elegance: one meaning per place
  Effort: S
- [ ] [MAJORITY] Yes, the panel's majority pick joins the bar, labelled "panel"
  When most lenses agree, that pick appears in the bar with a "panel" tag beside the asker's lean.
  Cost: two sources in one bar, so a disagreement between asker and panel needs its own wording
  Unblocks: one-click acceptance of the panel's view
  Then: I build it in the same council round
  Elegance: convenient, but the bar stops meaning one thing
  Effort: S

## ¶ASK_BACKFILL: Choose one: Should the 8 old asks get their panel reads attached now?
Lean: LEAVE — they are all answered already, and attaching to another seat's ask waits on your pending "who may attach" answer
- [ ] [LEAVE] Leave them; fix new asks only (recommended)
  The warning and the skills cover new asks. The 8 old ones show the "council named, no reads recorded" line.
  Cost: old decisions keep their panel only in prose
  Unblocks: nothing
  Then: nothing
  Elegance: no rewriting of settled asks
  Effort: S
- [ ] [ATTACH] Attach their reads from the council reports
  One lane runs `engine ask attach-panel` for each of the 8, reading the reports they cite.
  Cost: writes to other seats' answered asks, before you have ruled on who may attach
  Unblocks: the panel visible on past decisions
  Then: meta:engine or I run it after your "who may attach" ruling
  Elegance: complete history, at the cost of editing settled records
  Effort: S
