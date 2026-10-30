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

