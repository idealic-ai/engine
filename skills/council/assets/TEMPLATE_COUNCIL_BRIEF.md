# Council Brief — <SUBJECT / CHUNK>
*The self-contained grounding a caller hands `/council`. Council reads THIS, never a session — so every field a panel needs must live here. A human, `/implement`, `/pr`, or any future skill fills this and passes the path via `--brief <path>`.*

*Every field below is marked **REQUIRED** / **SELF-GATHERED-IF-OMITTED** / **OPTIONAL**. The **minimum viable Brief is `Subject` + `Mode` + `Brief version`** — council can self-gather or default the rest, but a thin brief yields a generic panel and gets its thinness stated as a Panel Blind Spot. Fill what you have.*

## Brief version — **REQUIRED**
`2`

<!-- The template revision this Brief was written against. Council warns on a mismatch (and on a missing value) rather than aborting — the template is strictly additive, so an older Brief stays readable. Bump this ONLY when adding fields; never repurpose or remove one. -->

## Subject (what the panel reviews) — **REQUIRED**
<**No default. Council never assumes a subject** — an unnamed subject is one question in `interactive` mode and a HARD ERROR in `report-only`. Exactly one of:
- `plan <path>` — a plan / design doc reviewed BEFORE code exists (panel critiques the plan, not code)
- `pr <#>` — a pull request (immutable via `gh pr diff` — not the live tree)
- `commit <ref>` / `<a>..<b>` — a commit or range
- `files <glob…>` — explicitly named files
- `doc <path>` — a prose / architecture doc (panel critiques the argument)
- `build-report <path>` — a /build Build Report (review its filesTouched)
- `session <dir>` — a session's whole body of work: its plan + the session's OWN diff (only the files it touched, per its log + build reports) + its build reports. The plan-vs-actual subject.
- `diff` — the uncommitted working-tree diff. **Explicit-only**: legitimate to ask for, never assumed. Note it resolves a LIVE, always-dirty tree that may hold parallel agents' work — prefer `commit`/`pr`/`session` when you need a stable subject.>

## Mode — **REQUIRED**
<`interactive` | `report-only`

- `interactive` — a human is at the terminal. Council may ask clarifying questions and offers the §5.E next-step chains.
- `report-only` — a machine caller. Council asks NOTHING (every `AskUserQuestion` is forbidden), suppresses the §5.E offer, and hands back the report path **plus a structured verdict block** (`verdict`, `counts`, `findings[{id,tier,file_line,consensus}]`, `report_path`, `blind_spots`). **The caller owns the single gate.**

This is a BEHAVIOR flag, not caller identity — council never learns who called it.>

## Report path (where the reconciled report is written) — **REQUIRED for a machine caller**
<an absolute path unique to THIS dispatch. A machine caller MUST mint one and pass it, because its failure branch checks that exact path for absence to tell "the panel ran" from "the panel died" — and council's fallback folds in a run-id minted inside council, which the caller cannot predict. An absence-check against a guessed path would read a live, successful council as a dead one.

Omit only for a human `interactive` run, where council self-derives `<trailDir>/<slug>_COUNCIL_<run-id>.md`. Never the bare `<slug>_COUNCIL.md`: the slug is reused across runs of the same work, so a prior run's complete report already sits there (the *died-stale* hazard — `SKILL.md` §1.C).

Not part of the minimum viable Brief above: council can always proceed without it by self-deriving. It is the CALLER that loses, not council.>

## Touched files (the FULL files, not just hunks) — **SELF-GATHERED-IF-OMITTED**
<the authoritative list of files the panel must read in full to judge the change in situ. For a build-report subject, this is its `filesTouched`. For a plan/doc, the document + any file it centrally references. For a session, the files that session's log + build reports record touching.

Omit and council resolves them from the subject, noting the thin Brief as a Panel Blind Spot.>

- `path/to/file` — <one-line what changed / why it matters>

## Files referenced but not yet existing (optional — sharpens a plan review)
<for a `plan` / `doc` subject: files the plan proposes to CREATE. Council labels these to the panel as to-be-created context so no expert wastes its lens flagging "file not found". For a CODE subject, an unreadable referenced file is the opposite — a real, stated blind spot.>

## Intent (what this work is FOR) — **SELF-GATHERED-IF-OMITTED**
<the ticket intent / goal in 1–3 sentences — so the panel reviews against purpose, not in a vacuum. Include the ticket ID if there is one.>

## The whys / deliberate decisions (do NOT flag these) — **SELF-GATHERED-IF-OMITTED**
<the decisions already made on purpose + their rationale — so the panel doesn't "find" a deliberate choice. Pull from the design dialogue / plan. Include any carried-forward lessons or established facts the panel should rely on rather than re-litigate. Council cannot self-gather these well — this is the field most worth filling.>

## Dialogue / plan digest — **SELF-GATHERED-IF-OMITTED**
<a distilled digest of the design conversation and/or the plan slice this work implements — the constraints, the trade-offs weighed, what was ruled out. This is the context that makes findings sharp instead of generic.>

## Panel size — **OPTIONAL** (default 3)
<1 | 3 | 5 | 7. 5 for a whole PR or cross-cutting plan; 3 for a focused change; 1 for a trivial / single-concern one. 7 is never a default — it must be earned by a genuinely cross-functional subject, and council states in its Panel line which distinct domains each earn a seat. Omit to accept the default.>

## Focus (steer the panel) — **OPTIONAL**
<what to weigh most, if anything: "stress the migration safety", "this is perf-critical", "the classifier schema is the risky part". Steers the generative persona selection across all three axes — domain, temperament, external-engine — and the panel's depth. Leave blank for a balanced review.>

## Poll (ask the panel to VOTE on curated options) — **OPTIONAL**
<Present ONLY when the caller wants a vote as well as a review. Omit it entirely and council behaves exactly as before — findings only, nothing else changes.

**The panel reacts; it never authors.** Every option below was curated by the caller. An expert picks among them and may say what it would have offered instead (`alternative`), but it does not add, rename, or remove an option, and its `alternative` is feedback to the caller — never a selectable choice presented to anyone else.

**Votes are not findings and do NOT face the §5.A refutation pass.** A preference has no `file:line` and no failing scenario; dispatching a skeptic to argue that a preference is not real is a category error. Findings and votes are independent outputs of the same run, reconciled separately.

**Evidence must be sufficient to rule.** Give each item what an expert needs to answer honestly. A one-line summary is not enough where the ruling is consequential — an expert asked to approve a merge from a summary of tickets it cannot open produces a confident judgement on thin grounds, which is exactly what the Failing-Scenario rule prevents everywhere else in this skill. Where you cannot supply enough, expect `evidenceUsed` to say so and the vote to be worth less accordingly. That is the honest outcome, not a failure.

Per item: `id` (echoed back verbatim on every vote) · `kind` · `options` (2–5 `{key, label}` — keys are stable machine ids, labels display-only) · `evidence` · `depth` (`full` | `brief`).

**What each expert returns per item**: the chosen `key`, a `weight`, and a reasoning card at the item's `depth`.

**`weight` (1–5) — anchor it behaviourally, never as a feeling.** `5` = *"I would object if the caller went the other way"* · `3` = *"a real preference I would state once"* · `1` = *"weak, I would not argue"*. Unanchored, self-reported importance collapses toward 4 and the scale stops carrying information — the same failure the Failing-Scenario rule exists to prevent for tiers.

**The reasoning card — named axes, each answering its own question.** One blob field yields one confident paragraph that covers nothing; separate axes force separate thinking.
- **`why`** — In one sentence, what makes this the right option?
- **`throughMyLens`** — What does YOUR lens see that another expert's would not? If nothing, say so — that is useful.
- **`whatItBuys`** — Concretely, what does choosing this get?
- **`whatItCosts`** — What is given up or risked? Name a real cost; "none" is almost never true.
- **`runnerUp`** — Which option is second, and what would have to be true for it to be first?
- **`whatWouldChangeMyMind`** — What specific evidence would flip your pick? If nothing would, say so and explain why.
- **`evidenceUsed`** — Which parts of the material did you actually rely on? Name them. **If the evidence was too thin to rule honestly, say that here rather than picking anyway.** This field is the poll's Failing-Scenario rule.
- **`alternative`** — An option the caller did not offer that you would want considered? Feedback to the caller only.
- **`blindSpot`** — What can your lens NOT see about this item?

**`depth: full`** → all nine axes. **`depth: brief`** → `why`, `evidenceUsed`, `alternative` only. Grade them deliberately: a binary approve/reject rarely earns nine axes, and demanding them anyway produces boilerplate across the back half of a long item list. Nine fields that look rigorous and carry nothing are worse than three honest ones.>

- `<item-id>` (`<kind>`, depth `full`|`brief`) — options: `<key>` "<label>" · … — evidence: <what the expert must be able to read to rule>

## House rules / conventions to respect — **OPTIONAL**
<pointers to discoverable `PITFALLS.md` / `CONTRIBUTING.md` / relevant `CLAUDE.md` sections the panel should honor, so findings respect established conventions.>
