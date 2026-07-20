# Council Report — <slug>
**Tags**: #needs-review
*Written by the `/council` orchestrator (§5) after the expert panel fans out (§4) and the MUST FIX findings survive a refutation pass. The raw per-expert findings live under `<slug>_council/<lens>.md`; this file is the reconciled synthesis. Read-only — council reports, it does not fix.*

> **Frame of mind:** This is a panel, not a single voice. Each finding below is tagged with which experts independently raised it — consensus is confidence. Every MUST FIX survived a deliberate attempt to refute it. Every MUST FIX / SHOULD FIX carries a `file:line` and a concrete failing scenario; anything vaguer was downgraded or cut.

## Verdict
**<Solid | Sound with fixes | Needs work | Not ready>** — <one line: the panel's collective read + the single most important thing to address>

*(Illustrative — adapt, don't copy: **Sound with fixes** — The plan's staging is right, but the backfill step has no reversal path and the Operator + Skeptic both flag the migration locking the table for the full backfill window.)*

**Counts:** <N MUST FIX, M SHOULD FIX, K CONSIDER>  ·  **Top to address:** <#, #, #>

## Subject & Panel
- **Subject:** <type + pointer — e.g. `plan sessions/…/IMPLEMENTATION_PLAN.md` / `pr 1400` / `session sessions/2026_07_17_topic/` / `diff`>
- **Brief:** <path, or "self-gathered">
- **Mode:** <interactive | report-only>
- **Panel (<size>):** <seated experts + the one-line why — e.g. `Architect, Operator, Skeptic, Specialist (migration in diff), Schema-Purist (Zod classifier schema touched)`>
- **Roster version:** <the `roster_version` of `personas/INDEX.md` the panel was selected from — e.g. `1`>

## Structured Verdict
*The machine-readable routing index — written into the report in BOTH modes so it stays auditable after the fact against what the caller was handed. In `report-only` the caller routes findings from it without re-parsing prose; in `interactive` it is simply left unread (a human reads the prose). It is a pointer + index, never a replacement for the report below; `verdict`, `counts`, and `findings` MUST agree with the Cross-Expert Priority Summary.*

```json
{
  "verdict": "<solid | sound_with_fixes | needs_work | not_ready>",
  "counts": { "must_fix": 0, "should_fix": 0, "consider": 0 },
  "findings": [
    { "id": 1, "tier": "MUST FIX", "file_line": "path/to/file:120", "consensus": ["Skeptic", "Operator"] },
    { "id": 2, "tier": "SHOULD FIX", "file_line": "path/to/file:44", "consensus": ["Architect"] }
  ],
  "report_path": "<absolute path to this file>",
  "roster_version": 1,
  "blind_spots": ["<one line each — an unseated warranted lens, a dead expert, a thin Brief, a brief_version mismatch>"]
}
```

---

## Cross-Expert Priority Summary
*The reconciled, deduped, consensus-tagged findings. One row per distinct finding, ordered by tier then consensus count. (This table is the report artifact — it does not appear in the skill prose.)*

| # | Tier | Finding | Raised by | file:line | Failing scenario | Suggested direction |
|---|------|---------|-----------|-----------|------------------|---------------------|
| 1 | MUST FIX | <short title> | <Skeptic, Operator> | `path:line` | <the concrete break> | <the direction, not a patch> |
| 2 | SHOULD FIX | <short title> | <Architect> | `path:line` | <the concrete break> | <direction> |
| 3 | CONSIDER | <short title> | <Architect, Specialist> | `path:line` | <the trade-off> | <direction> |

---

## Refutation Outcomes
*Every MUST FIX faced a skeptic that tried to refute it. It survives only if it could not be refuted.*
- **<finding title>** — **SURVIVED**: <why the refutation failed — the input genuinely occurs / no upstream guard / scenario holds on the full file>.
- **<finding title>** — **REFUTED → downgraded to SHOULD FIX / dropped**: <the good-faith case that killed it — an upstream guard handles it / it's a documented deliberate choice / the scenario doesn't hold in situ>.

---

## Per-Expert Findings
*The distinct lens each expert brought, before reconciliation. Full detail in `<slug>_council/<lens>.md`.*

### Architect
- <tier> — <title> — `file:line` — <one-line essence>. **Verdict:** <lens verdict>.

### Operator
- <tier> — <title> — `file:line` — <one-line essence>. **Verdict:** <lens verdict>.

### Skeptic
- <tier> — <title> — `file:line` — <one-line essence>. **Verdict:** <lens verdict>.

<!-- At 5, add the adaptive pair: -->
### Specialist
- <tier> — <title> — `file:line` — <one-line essence>. **Verdict:** <lens verdict>.

### Wildcard (<Schema-Purist | Security | Product-UX>)
- <tier> — <title> — `file:line` — <one-line essence>. **Verdict:** <lens verdict>.

---

## Panel Blind Spots
*What the panel collectively could NOT judge — files/states/integrations outside the grounding, an expert that returned empty or failed, a lens the subject warranted but the panel didn't seat. A clean verdict with unstated blind spots is dishonest.*
- <blind spot + why it matters>

## Reusable Facts
*Durable architectural truths the panel surfaced — the orchestrator appends these to `LESSONS.md`. Terse, one sentence each.*
- <fact>

## Next Steps (offered, not taken)
*Council is read-only. In `interactive` mode these are offered via `AskUserQuestion`; council does not run them. In `report-only` mode the offer is **suppressed** — the machine caller owns the single gate — and this section stands as a note for whoever later reads the report.*
- `/scrutinize <subject>` — verify a MUST FIX against intent and fix it.
- `/fix <finding>` — repair a confirmed defect directly.
- **Loopback** — if the subject was a plan reviewed for `/implement`, hand these findings back for the plan-revision loop.
