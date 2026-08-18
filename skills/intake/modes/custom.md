# Custom Mode (User-Defined Reach)
*The mode axis here is **how far this pass goes**, so a custom mode is a custom stopping point — not a custom persona.*

**Boot**: Before accepting user input, read **all three** named mode files to understand the span (`¶CMD_SELECT_MODE` requires this, and the span is the thing a custom reach is carved out of):
- `modes/full-wave.md` — the complete pass: drain → triage → decide → file → close
- `modes/quick-pass.md` — the daily working pass: drain → scope → triage → stop
- `modes/decide.md` — the back half: no drain, clear the accumulated unresolved set, watermark untouched

> **Quick Pass ingests and decides nothing · Decide decides and ingests nothing · Full Wave does both.**

**Most "custom" asks are actually one of those three.** Check before carving a fourth: a reach is only genuinely custom if it stops somewhere none of them do (e.g. *drain and consolidate but decide nothing* — `0 → 1 → 2 → 3 → 4 → 9`). If the ask matches a named mode, say so and use it rather than reconstructing it by hand.

**Role**: **The Curator**, unchanged. The persona does not vary by mode.
**Goal**: *Set from the user's free-text input — expressed as the phase this pass stops after.*
**Mindset**: *Blended from whichever named mode the stopping point sits closest to.*

## Configuration

**Ask for the stop, not the flavour.** Turn the user's framing into an explicit phase list and read it back before Phase 1 (e.g. *"0 → 1 → 2 → 3 → 4 → 9: drain, triage and consolidate, but decide nothing"*). Record it in `modeStop` at Phase 3 the same way the named modes do.

**Decide pull (c) at Setup, not at Phase 1.** Phase 1's unresolved-thread sweep runs **iff this pass will reach Phase 5**. A reach that stops earlier must skip it — dragging the accumulated undecided set into a pass that cannot decide it is the black hole in reverse, and it buries the day's actual new signal under a backlog nobody asked this pass to clear.

**Three rules bind every custom reach — they are not the user's to relax:**

1.  **One watermark.** It advances at Phase 1 whatever the pass does afterwards, and it means *what have I read*. Never a second marker.
2.  **Resolve only on disposition** (`¶INV_RESOLVE_ON_DISPOSITION`). A pass that stops before Phase 6 resolves nothing, because it dispositioned nothing.
3.  **Announce only a pass that decided.** `§PASS_HEARTBEAT` fires from Phase 5 and Phase 9's Final Sync; a custom reach that stops short of Outcomes takes the Quick Pass close (debrief + watermark confirm, no board, no Update, no Slack).

**Everything else** — proof fields, gates, the invariants — comes from the phases the pass actually runs, at full strength. A shorter reach is never a licence to relax a gate on a phase it does run.

**If the user's framing is really "skip a gate" rather than "stop earlier"**, that is not a mode — refuse it via `§CMD_REFUSE_OFF_COURSE` and say which gate they are asking to drop.
