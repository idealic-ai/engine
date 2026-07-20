# Council Brief — <SUBJECT / CHUNK>
*The self-contained grounding a caller hands `/council`. Council reads THIS, never a session — so every field a panel needs must live here. A human, `/implement`, `/pr`, or any future skill fills this and passes the path via `--brief <path>`.*

*Every field below is marked **REQUIRED** / **SELF-GATHERED-IF-OMITTED** / **OPTIONAL**. The **minimum viable Brief is `Subject` + `Mode` + `Brief version`** — council can self-gather or default the rest, but a thin brief yields a generic panel and gets its thinness stated as a Panel Blind Spot. Fill what you have.*

## Brief version — **REQUIRED**
`1`

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
<1 | 3 | 5. 5 for a whole PR or cross-cutting plan; 3 for a focused change; 1 for a trivial / single-concern one. Omit to accept the default.>

## Focus (steer the panel) — **OPTIONAL**
<what to weigh most, if anything: "stress the migration safety", "this is perf-critical", "the classifier schema is the risky part". Steers panel composition (it is the first tiebreak for the single Wildcard seat) and depth. Leave blank for a balanced review.>

## House rules / conventions to respect — **OPTIONAL**
<pointers to discoverable `PITFALLS.md` / `CONTRIBUTING.md` / relevant `CLAUDE.md` sections the panel should honor, so findings respect established conventions.>
