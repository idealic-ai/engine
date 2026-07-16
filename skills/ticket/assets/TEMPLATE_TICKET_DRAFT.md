# Ticket Drafts — <slug>
*The drafting agent (`/ticket` §2) fills this, WRITES it to `<trailDir>/<slug>_TICKETS.md`, one block per ticket. Premise-first: every field states the PROBLEM and its BOUNDARIES, never a prescribed algorithm. The orchestrator reads it back for the calibration gate (§3), then stamps each block's outcome after posting (§5). Every "Illustrative Example" below is a made-up placeholder to show the target shape — adapt to the real work, don't copy.*

**Intent (what this set of tickets is for):** <1–2 sentences — the motivation behind ticketing this work>
**Context ticket:** <<PREFIX>-NNNN detected from session slug / branch / conversation, or "none">
**Ticket count:** <N — default 1; >1 only when the work has genuinely independent deliverables>

---

## Ticket 1 — <crisp, outcome-oriented title>

**Type**
<bug | feature | chore | tech-debt | spike — maps to a label and drives what the other fields need to say (a bug wants Reproduction + Evidence; a spike wants Open questions, NOT fabricated constraints/acceptance).>

**Premise / problem**
<What's wrong / missing / needed, grounded in the actual work. State the problem, not the fix. A reader who never saw the session should understand what's broken or absent and why it's worth a ticket.
*(Illustrative — adapt, don't copy: "The profile read-path fetches all relational rows synchronously, so accounts with very large child collections time out. The heavy fetch needs to be decoupled from the request path.")*>

**Intent / why now**
<The motivation — why this matters, what it unblocks or de-risks, the cost of leaving it. This is the "why" the ticket exists.
*(Illustrative — adapt, don't copy: "Unblocks the upcoming traffic ramp. Left alone, the added load turns these timeouts into cascading lock contention.")*>

**Evidence / grounding**
<The anti-solutioning field — ground the premise in artifacts, not assertions. Name the general AREAS / modules involved (dirs, file-groups) + a one-line description of the observed symptom + provenance: the spawning commit / PR / session URL(s).
A representative pointer or two is plenty — do NOT dump exhaustive `file:line` lists; they rot fast and the implementor rediscovers specifics anyway. Concrete-but-durable beats precise-but-brittle.
*(Illustrative — adapt, don't copy: "Areas: the profile route module + the order-read repository. Symptom: latency dashboards spike in lockstep with the profile-load call. Spawning session: [URL].")*>

**Constraints**
<What must hold: invariants, backward/data compat, prior decisions that bound the solution, interfaces that can't change. The guardrails any implementation must respect.
*Smell test: if renaming the functions / rewriting the approach would invalidate this line, it's an implementation detail — cut it.*
*(Illustrative — adapt, don't copy: "Must keep the v1 API response schema byte-compatible. No new columns on the shared table without a migration plan.")*>

**Non-goals**
<Explicitly out of scope — the adjacent things this ticket does NOT cover, so it doesn't sprawl. Name the sibling work that belongs elsewhere.
*(Illustrative — adapt, don't copy: "Reworking the repository's caching layer is out of scope (tracked separately). This ticket only decouples the synchronous fetch in the read path.")*>

**Acceptance signals**
<How we'd know it's done — observable outcomes, not steps. "X no longer happens", "Y is stable across Z", "the gate passes". This IS the definition of done.
*Smell test: if renaming the functions / rewriting the approach would invalidate this line, it's an implementation detail — cut it.*
*(Illustrative — adapt, don't copy: "1. The profile read returns well under the timeout for very large accounts. 2. The heavy child data loads off the request path.")*>

**Implementation traps** *(the know-how the drafter can offer without over-specifying — omit if none)*
<Pitfalls / deceptive code the analysis surfaced that will bite the builder — conceptual warnings, NOT a path dump. "You'll be tempted to X — don't, because Y."
*(Illustrative — adapt, don't copy: "You'll be tempted to use the projection helper as the parity oracle — DON'T; it copies the id onto projected rows, so the suite is blind to this exact change. Prove it against the real assembler.")* A head-start, not a spec.>

**Escalation triggers** *(when the builder should STOP — omit if none)*
<The specific conditions under which the builder should stop and return to the user rather than guessing. Bounds the autonomy the ticket grants.
*(Illustrative — adapt, don't copy: "If the real reconciler assertion reveals that parent rows (not just child rows) are lost or mis-joined, STOP and report — do not attempt to fix the join logic in this ticket.")*>

**Reproduction** *(bugs only — omit for non-bug types)*
<Minimal steps / input / state that triggers the defect, and the wrong behavior observed vs. expected. Delete this field entirely unless Type is `bug`.>

**Open questions / unknowns**
<The premise-first home for what's undecided — questions the implementer must resolve, ambiguities, a possible split that wasn't taken (and why it's held as one ticket for now). For a `spike`, this is the main field: populate it heavily instead of fabricating constraints/acceptance. Empty is fine; guessing is not.
*(Illustrative — adapt, don't copy: "Do we need a distinct loading state while the deferred data arrives, or is the existing placeholder acceptable?")*>

**Dependencies**
<Cross-ticket wiring expressed BY DRAFT # while drafting (there are no `<PREFIX>-NNNN` ids yet): `blocked-by #2` / `blocks #3` / `relates-to #2`. The orchestrator resolves draft # → `<PREFIX>-NNNN` in a second pass after all creates return (§4.4). Omit if standalone.>

**Suggested priority + labels**
<A proposed Linear priority (Urgent/High/Medium/Low/none) with an IMPACT-based reason (who/what is hurt by leaving it, urgency), plus candidate labels — SUGGESTED only, drawn from likely team labels; the orchestrator reconciles these against the real team label set at §4.1 (a label not in the set is dropped/flagged) because the drafter doesn't know the team yet. The user finalizes at calibration.>

**Proposed placement**
<`sub-issue of <PREFIX>-NNNN` (with one-line reason it belongs under that parent) OR `new top-level issue` (with reason no parent fits). Default: sub-issue when a context ticket is detected, new otherwise.>

**Rendered description (postable)** *(the drafter renders the EXACT `save_issue({ description })` body here — §4 lifts it VERBATIM, no re-render)*
<The final postable Markdown: the premise-first fields as `## Premise` / `## Intent` / `## Constraints` / `## Non-goals` / `## Acceptance` sections, plus Evidence/grounding and (bugs only) Reproduction headers — all rendered ready-to-post. Exclude any "possible direction" unless the user flagged it to keep. This is what gets filed; keep it complete and self-contained.>

**Possible direction** *(a hint, never a spec — dropped from the filed ticket unless the user keeps it; ≤1 line, omit by default)*
<Only if the work strongly implies an approach worth recording. Keep it a hint, not a spec — the ticket must not depend on it.>

**Estimate / size** *(optional — off by default)*
<A rough size only if genuinely useful. Pre-refinement sizing is often noise; leave blank unless the team estimates at intake.>

**Outcome** *(stamped by the orchestrator after §5)*
<`→ filed <PREFIX>-NNNN <url>` | `merged into Ticket #` | `dropped (<reason>)` — filled post-posting>

---

## Ticket 2 — <title>
*(repeat the block only when the work genuinely splits — two decoupled, independently deployable/assignable systems; delete this section for a single-ticket draft)*
