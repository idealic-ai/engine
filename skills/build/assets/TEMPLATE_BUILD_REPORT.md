# Build Report — <CHUNK / TASK>
**Tags**: #needs-review
*Written by the builder sub-agent at the end of its run. This is the authoritative account of what happened. It is read downstream by TWO consumers: `/scrutinize` (goal + approach + files + risks + assumptions + parity evidence) and the NEXT chunk's `/build` (via `reusableFacts` → `LESSONS.md`). Fill every field meticulously for both readers.*

## Goal
<the exact goal this build served — echoed directly from the Context Pack>

## Approach chosen + rationale
<what approach was taken and WHY.
**Crucial:** call out any DEVIATIONS from the suggested approach explicitly, and defend them with the reason.
*(Illustrative — adapt, don't copy: "chose the accessor over the generic flip because DEFAULT_RULES typing cascades, which would have broken the downstream parser.")*>

## Dead ends & ruled out (the invisible work)
<what you tried FIRST that failed, and the approaches you considered but rejected, with WHY. This is a pure gift to the next agent: it saves them from re-hitting the walls you already hit.
*(Illustrative — adapt, don't copy: "tried a geometric range-skip to filter headings — dropped 9 real unit headings that legitimately sit inside correctly-bounded table bodies. Ruled out pure geometry; needs a prose-guard.")*
Write "None — the first approach worked" ONLY if genuinely true.>

## Files touched (authoritative)
<the exact files changed — this is the definitive in-scope set `/scrutinize` should review; nothing else in the working tree belongs to this build>

- `path/to/file` — <one-line what/why>

## Autonomous decisions
<calls made without asking, and the reasoning — so the reviewer/user can second-guess them.
*(Illustrative — adapt, don't copy: "extracted the regex into a module-level constant rather than keeping it inline, to prevent recompilation on every loop.")*>

## Self-flagged risks / uncertainties
<be honest — this seeds the adversarial review. What are you unsure about?
*(Illustrative — adapt, don't copy: "I widened the `User` interface; a legacy caller might rely on a dropped field — worth a second look during scrutinize.")*>

## Assumptions that could be wrong
<the load-bearing beliefs this build rests on — "what would make this wrong". The reviewer verifies these first.
*(Illustrative — adapt, don't copy: "I assumed live extraction is heading-only; if scope docs still flow, X breaks.")*>

## Parity evidence (for behavior-preserving work)
<HOW parity was proven — which test is the oracle, what was diffed, what stayed byte-identical. "N/A — greenfield" if not applicable. Do NOT claim behavior-preserving without evidence.>

## Test fidelity (oracle strength)
<do the green tests ACTUALLY prove the behavior, or are they tautological / blind to the change? Name what they cover AND what they don't.
*(Illustrative — adapt, don't copy: "the parity oracle is blind to `pricingType` — it diffs values/units/presence but never reads `pricingType`, so the green run gives false comfort for that seam; fidelity rests on the 6 unit tests.")*
A green suite is only as good as its oracle — state exactly how strong yours is.>

## Reusable facts (carry forward to `LESSONS.md`)
<durable facts discovered here that later chunks / the reviewer will need. The orchestrator appends these to `<trailDir>/LESSONS.md`.
*(Illustrative — adapt, don't copy: "the path engine never lands a table on a subroom path.")*
Keep these to terse, single-sentence bullet points.>

## Gate results (exact commands, re-runnable)
<paste the EXACT command, its exit code, and the summary line — so the orchestrator re-runs byte-identical commands to verify.>
- `<exact cmd>` → exit `<N>` — `<summary line>`
- `<exact test cmd>` → exit `<N>` — `<suites/tests pass count>`

## Out-of-scope noticed (not touched)
<things spotted while working but deliberately left alone because they were outside your boundary — candidates for `#needs-X` follow-ups>

## Blockers
<anything that stopped progress; options presented rather than guessed. Empty if none.>
