# Critique Trail — <slug>
*Written by the critiquer sub-agent (`/scrutinize` §2), then APPENDED to by the orchestrator across the run (per-finding triage decision + reason, and the fixer outcome). The full severity-ranked findings live here; the orchestrator relays only a compact ranked summary in chat.*

> **Frame of mind:** You are a hostile forensic auditor, not a summarizer. You are looking for the fatal flaw the author missed. Every finding below earns its place with a concrete **Failing Scenario** — no scenario, no finding. Do not invent theoretical nits; prove the breakage.

## Verdict
**<Approve (clean) | Approve with comments | Request changes | Block>** — <One line: the essence + the single most important thing to fix>

*(Illustrative — adapt, don't copy: **Request changes** — The core migration is solid, but the fallback parser drops the `tenant_id` on legacy payloads, which will corrupt the billing database.)*

Top 3 to fix: <#, #, #>

---

## Findings
*Severity order: CRITICAL (correctness/security) → HIGH (regression/edge-case) → MEDIUM (test-gap/quality) → LOW (nit).*

### 1. <SEVERITY> — <short title>
- **File:** `path/to/file:line`
- **Why it's wrong:** <The defect, precisely — not a vague worry. What exactly is misconfigured, missing, or miscalculated?>
- **Failing Scenario (required):** <Step-by-step: exactly what inputs / state / sequence of events makes this code fail or corrupt data.>
  *(Illustrative — adapt, don't copy: "A carrier whose cover page contains a line like 'Total Amount' (→ total,total) — that line is encountered BEFORE the real detail header → columns resolved from prose geometry → all downstream values extracted using wrong x-bands.")*
- **Repro test:** <STRONG DEFAULT — a saved RED test the fixer can run instead of re-deriving. Path in `<trailDir>/<slug>_repro/` + the EXACT run command + the observed failure line. The in-tree copy was reverted; the fixer re-creates it. Write "none — <why a test is infeasible>" only when genuinely test-infeasible (integration/live-service/env-only).>
  *(Illustrative — adapt, don't copy: "`<slug>_repro/finding-1.test.ts` — `cd packages/estimate && npx vitest run <slug>-repro/finding-1` → RED: `expected 'total' to not equal 'total' (col collision)`.")*
- **Root cause:** <1–2 sentences on WHY the code is wrong — the underlying conceptual mistake, not just the symptom.>
- **Suggested fix:** <The concrete change. If there's a 'right' way and a 'cheap' way, name both so the user can triage effectively.>

### 2. <SEVERITY> — <short title>
- **File:** `path/to/file:line`
- **Why it's wrong:** <…>
- **Failing Scenario (required):** <…>
- **Repro test:** <`<slug>_repro/finding-2.test.ts` + run command + RED line, or "none — <why>">
- **Root cause:** <…>
- **Suggested fix:** <…>

<!-- repeat per finding -->

---

## Audit Blind Spots
*What this review could NOT verify — files, states, or integrations outside your context that still pose risk. A green verdict with unstated blind spots is dishonest; name them.*
- *(Illustrative — adapt, don't copy: "Could not verify `mutool draw -F svg -o -` for single-page SVG on this build — if that invocation is subtly wrong it fails identically for every case, which I could not reproduce here without the binary.")*
- *(Illustrative — adapt, don't copy: "The `StripeWebhook` handler assumes the `event.data.object` matches the V2 schema, but I do not have the V2 schema definitions in my context to verify the field mappings.")*

## Reusable Facts Discovered
*Hard architectural truths learned by auditing this code — durable know-how the next `/build` should carry. The orchestrator appends these to `LESSONS.md`.*
- *(Illustrative — adapt, don't copy: "`mutool` SVG export is clip-aware, but `stext` is clip-blind.")*
- *(Illustrative — adapt, don't copy: "The reconciliation join key is the scope nanoid end-to-end; nothing reads `heading.nanoid` for matching.")*

---

## Triage & fix outcomes
*(APPENDED by the orchestrator during §3/§4 — one line per finding.)*
- **#1** — <Fix | Skip | Defer> <reason if given> → <fixer outcome + gate result, or "n/a">
- **#2** — <…>
