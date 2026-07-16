# Snapshot Draft — <slug> → <PREFIX>-NNNN
*The reviewer subagent (`/snapshot` §2) fills this and WRITES it to `<trailDir>/<slug>_SNAPSHOT.md`. Four parts: the COMMIT proposal (what gets committed), the COMMENT (what gets posted), the STATUS proposal, and the DESCRIPTION proposal. The orchestrator reads it back for the single batch confirm (§3), then attempts the four actions BEST-EFFORT and non-atomic (commit FIRST so its short SHA fills the comment's `{{COMMIT_SHA}}` sentinel — or scrubs the commit-claims if no commit lands), then stamps exactly what landed. No git gymnastics: clean files are whole-file staged, mixed files are surfaced to the user, never auto-split.*

> **The blockquoted `>` examples below are ILLUSTRATIVE only — adapt, don't copy.** They show the palette's shape, not your content. Replace each one entirely with THIS work's real details; do NOT echo their specific phrasing (nanoid / identity-model / PR #1400 / "304 suites" / recap-by-room are placeholders from an unrelated example).

---

## PART 1 — Commit proposal (the checkpoint)
*The reviewer identifies the exact file set, classifies each CLEAN vs MIXED, + proposes the message; it NEVER commits. The orchestrator whole-file-stages CLEAN files with `git add -- <path>` (never a wildcard, never `-p`/stash/checkout/revert — the NO-GYMNASTICS rule), SURFACES MIXED files to the user per file (commit whole as-is / skip / defer — default: skip), reviews `git diff --cached` before committing, and commits after the batch confirm. Gated on green (§2 gates passed, re-checked at commit time); branch-first if on `dev`/`main`.*

- **Proposed message** (`type(scope): <PREFIX>-NNNN <summary>` — match `git log --oneline -5`; the `Co-Authored-By` trailer is appended by the orchestrator):
  > *(Illustrative — adapt, don't copy)* `refactor(estimate): FIN-2712 deterministic recap-by-room extractor`
- **Staged files — CLEAN vs MIXED** (the reviewed work's EXACT paths — no wildcard; a MIXED file also carries churn outside the work and is surfaced to the user, never auto-split):
  > *(Illustrative — adapt, don't copy)*
  > - `packages/estimate/src/extraction/deterministic/recap/recap-by-room.ts` — **CLEAN** (stage)
  > - `packages/estimate/src/extraction/deterministic/recap/__tests__/recap-by-room.test.ts` — **CLEAN** (stage)
  > - `packages/estimate/src/extraction/deterministic/recap/index.ts` — **MIXED** (also carries unrelated churn → surface; default suggestion: skip, commit the clean files)
- **Staged-diff note** (orchestrator fills at confirm — `git diff --cached --stat` + hunk count, so the user approves actual STAGED CONTENT, not just a file list; re-surface if anything unexpected is staged):
  > `<e.g. 2 files, +84/−3, 5 hunks — all within the reviewed work>`
- **Branch:** `<current branch, or "on dev → branch first to the canonical branch name from get_issue, else fin-2712-…; abort commit if branch creation fails">`
- **Green gate:** `<§2 gates passed → OK to commit (re-check narrowest gate at commit time, TOCTOU) | red/unrun → confirm offers commit-anyway vs skip-the-commit (post update only)>`

---

## PART 2 — Comment (Markdown, this is what posts)
*Build from the palette below. ALWAYS-ON sections render every time; INCLUDE-IF-PRESENT sections render only when they have real content — skip them, never write "none". Tight TL;DR on top; big is fine, padding is not.*

### `## Status: <state>` + **TL;DR** + **Covers:**  — ALWAYS
*Use: every update. Headline state + 1–3 lines a skimmer/reviewer-agent reads first. The `Covers:` line names the window this update spans (cumulative vs incremental) so a reader of update #4 knows what's new. The `Committed {{COMMIT_SHA}}` clause is filled with the short SHA after commit — or STRIPPED entirely if the commit is skipped/failed (commit-claim scrub).*
> *(Illustrative — adapt, don't copy)*
> **## Status: In review**
> **TL;DR** Identity-model fix landed + verified (suite green); chunk-5 reader-swap now unblocked on a stable join key. Committed `{{COMMIT_SHA}}`. Two minor leftovers (a coexistence test, a doc note). No blockers.
> **Covers:** work since the 2026-06-28 update (chunks 3–5).

### `### On-direction`  — ALWAYS
*Use: every update. Is the work aligned with the ticket's intent/acceptance — on track, drifted (how + why), or re-scoped? The core judgment.*
> *(Illustrative — adapt, don't copy)*
> Aligned with the ticket's "no-scope cutover" intent. The identity model changed exactly as the plan required; no drift from the stated acceptance. One deliberate re-scope: nanoid unification pulled ahead of chunk 6 (recorded in the ticket's change history).

### `### Verified`  — ALWAYS
*Use: every update. What you actually RAN to confirm 'done', with results. Turns asserted status into evidence. The orchestrator fills `{{COMMIT_SHA}}` after committing, or strips the "Checkpointed as …" line if no commit lands.*
> *(Illustrative — adapt, don't copy)*
> - `cd packages/estimate && npx tsc --noEmit` → exit 0
> - `yarn workspace @finch/estimate test` → 304 suites green / 9 skips (pre-existing)
> - Cross-checked the claim against the diff: heading nanoid == scope nanoid confirmed in `flat-identity.test.ts` (5 real-assembler proofs).
> - Checkpointed as `{{COMMIT_SHA}}`.

### `### Confidence & fragility`  — ALWAYS
*Use: every update. Your honest read on how STABLE this checkpoint is — the single most fragile assumption, what's held together with duct tape, where it would break first. This replaces tautological "on-direction" padding with a real signal a future debugger needs.*
> *(Illustrative — adapt, don't copy)*
> Confidence low-medium. The stepper is fully derived/stateless (no persistence risk), but relies entirely on the URL matching the tab map perfectly — add a new tab without updating the map and it silently breaks. The DB schema half is high-confidence; the FE shadow types are the soft spot.

### `### What the diff doesn't show`  — if present
*Use: when crucial context, abandoned dead-ends, or invisible constraints shaped the work but won't be visible in the git diff. The "why it looks like this" a reviewer can't reconstruct from the code alone.*
> *(Illustrative — adapt, don't copy)*
> The diff shows a bespoke `ComparisonStepper`. What it doesn't show: we explicitly abandoned extending `RebuttalPipeline` because sibling FIN-2597 had already dismantled it — so this isn't NIH, it's the only remaining path.

### `### Leftovers & followups`  — ALWAYS
*Use: every update. What's unfinished / deferred / open — guidance for the next person or agent. Not filed, not fixed.*
> *(Illustrative — adapt, don't copy)*
> - Coexistence test (scope + heading in one `entities[]`) still to add — deferred.
> - Parent-detection edge (branch-FIN ≠ slug-FIN) unhandled in the sibling flow.
> - (Guidance only — file via `/ticket` or address via `/fix` if you choose.)

### `### Hurdles & mismatches`  — if present
*Use: when something fought back or reality diverged from expectation. Reviewer-agents learn most from these.*
> *(Illustrative — adapt, don't copy)*
> The chunk-4 test oracle (`projectScopesToFlat`) copies `scope.nanoid` onto flat entities → it was BLIND to the identity change; a naive green would have been a false positive. Had to prove identity against the real assembler instead.

### `### Findings`  — if present
*Use: when the work surfaced something others should know (a fact, a gotcha, a corrected assumption).*
> *(Illustrative — adapt, don't copy)*
> The `heading.ts` docstring claiming "flattening doesn't churn ids" was aspirational — it became TRUE only after this fix.

### `### Results / evidence`  — if present
*Use: concrete outcomes/numbers worth recording (counts, timings, before/after).*
> *(Illustrative — adapt, don't copy)*
> 1,240 headings across 38 fixtures now flatten with 0 id churn (was 217 churned ids before the fix).

### `### Decisions & rationale`  — if present
*Use: key choices + WHY. Gold for a later reviewer-agent reconstructing intent — the "why" that usually evaporates.*
> *(Illustrative — adapt, don't copy)*
> - Unified the nanoid in the assembler (Option A) over a data migration (Option B) — avoids churning persisted ids.
> - Cross-entity-type nanoid collision ruled benign — the no-scope end state removes the collidee.

### `### Risks / watch-outs`  — if present
*Use: done-but-watch. Latent hazards, fragile assumptions, areas needing care at review/merge. Distinct from leftovers (which are undone).*
> *(Illustrative — adapt, don't copy)*
> The reader-swap relies on `heading.nanoid == scope.nanoid`; if a cutover step ever emits headings into a doc that still holds scopes, `overlay()` collides. The no-scope direction avoids it, but flag it at merge.

### `### Links`  — if present
*Use: pointers — PRs, the checkpoint commit, the session, build/critique reports. The orchestrator fills `{{COMMIT_SHA}}` after committing, or removes the commit entry (or writes "commit: not committed") if the commit is skipped/failed.*
> *(Illustrative — adapt, don't copy)*
> commit `{{COMMIT_SHA}}` · PR #1400 · build report `identity-model-fix_BUILD.md`

---

## PART 3 — Status proposal
*The orchestrator confirms this at the batch gate.*
- **Current state:** `<state from get_issue>`
- **Proposed:** `<new state>` — <one-line reason>  *(or: "no state change")*

---

## PART 4 — Description proposal
*Only when the ticket's premise / scope / acceptance MATERIALLY drifted — NOT for routine progress. If no drift, write "No material drift — description unchanged" and stop here. Standalone/no-MCP: write "skipped — cannot read current body to preserve history".*

**Drift assessment:** <what materially changed about the premise/scope/acceptance, or "none">

**Proposed description body — the SINGLE complete final body that will REPLACE the current description** (save_issue.description is a full-field replace, so this box must be the whole thing):
*The evergreen rewritten text, THEN a `## Change history` carrying EVERY prior entry copied verbatim + one new appended line. The orchestrator re-reads the current description immediately before posting and aborts if any prior entry would be lost.*
> *(Illustrative — adapt, don't copy)*
> <evergreen rewritten body — reads as current truth>
>
> ## Change history
> - <prior entry 1 — copied VERBATIM from the current description>
> - <prior entry 2 — copied VERBATIM>
> - <YYYY-MM-DD>: <the one new line — what changed (why)>

---

## Outcome
*(stamped by the orchestrator after §3 — BEST-EFFORT + non-atomic: mark each action for EXACTLY what landed; never claim one that didn't. A skipped/failed commit is scrubbed from the comment; the other three still run. Hand back any un-posted artifact for manual retry.)*
- **Commit:** <committed `<sha>` on `<branch>` (done) | skipped (user chose post-only / all files mixed→skipped) | failed (<reason>) | n/a>
- **Comment:** <posted <url> (done) | edited then posted (done) | failed (<reason>) | skipped>
- **Status:** <moved <from>→<to> (done) | failed (<reason>) | skipped | n/a>
- **Description:** <replaced with full body, history preserved (done) | failed (<reason>) | skipped | no drift>
