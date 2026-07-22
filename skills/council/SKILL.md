---
name: council
description: "Convene a diverse expert panel over an explicitly targeted body of work — plan, diff, PR, commit, files, build-report, doc, brainstorm, or session — via a self-contained Council Brief, fan out N independent expert sub-agents IN PARALLEL (generatively selected from a 20-persona palette spanning domain expertise + temperament), refute the panel's own MUST FIX findings, then write a consensus-tagged Council Report. Read-only: it reviews and reports, never fixes, commits, or files. Triggers: \"council this\", \"convene a panel\", \"get diverse expert eyes on this\", \"panel review\", \"multi-perspective review\", \"what would a panel say about this\"."
version: 1.0
tier: lightweight
args: "<subject: diff | commit <ref>|<a>..<b> | files <glob…> | pr <#> | plan <path> | build-report <path> | doc <path> | brainstorm <path> | session <dir>> (REQUIRED — no default) [--brief <path>] [--mode interactive|report-only] [--size 1|3|5|7] [-- <what to focus on>]"
---

Convene a panel of diverse expert sub-agents over a polymorphic subject, let each expert critique it through its own lens IN PARALLEL, refute the panel's own strongest claims, then hand back a consensus-tagged, categorized Council Report. This skill is sessionless: it owns no session, phases, or debrief. It reads a **Council Brief** (never a session) and executes a strict pipeline: resolve brief → compose panel → ground + build prompts → fan out → refute + reconcile → report → stop.

This is distinct from `/scrutinize`. `/scrutinize` is one hostile auditor that verifies *claims* against *intent* and then *fixes*. `/council` is a **panel** of distinct experts that gives *diverse perspective* on the *resulting code (or a plan)* and *stops at findings* — it never verifies-and-fixes and is never a single voice. It is the read-only, perspective-first sibling: where `/scrutinize` proves a regression and repairs it, `/council` surfaces what a room of seasoned specialists would each independently worry about, tagged by how many of them raised it. As a **building block** it produces a briefing, not a change: it never edits code, never commits, never files a ticket. What happens after — `/scrutinize` to verify+fix a finding, `/fix` to repair, or (when a plan was reviewed for `/implement`) handing the findings back for the loopback — is the caller's call, offered but never auto-run.

*Crucial constraint:* `/council` reads the **Brief**, not the session. The Brief is the ONLY interface — that decoupling is the whole point. It makes council reusable by a human, by `/implement`, by `/pr`, or by any future skill: each caller fills a Brief and hands council the path. Council must NOT read `DIALOGUE.md`, activate a session, or reach into session state to reconstruct context — everything it needs is in the Brief (or self-gathered from a raw `/council <subject>` invocation).

# /council Protocol

## 1. Resolve the Brief, Subject & Trail

Establish the foundational inputs. A panel with no grounding produces generic platitudes; a panel with no stated subject reviews the wrong thing. Do NOT skip this.

**A. Resolve the Brief** (the panel's grounding — the ONLY interface)
There are two ways in:
- **(a) Caller-provided Brief.** An arg (`--brief <path>`) points at a filled `assets/TEMPLATE_COUNCIL_BRIEF.md`. A skill invoking council (`/implement`, `/pr`, a future caller) writes this Brief first and hands over the path. Read it whole — it carries the subject pointer, the grounding (touched files, ticket intent, the dialogue/plan digest), the requested panel size, and the focus. This is the composable path: council trusts the Brief and does NOT reconstruct context from a session.
- **(b) Self-gather from a raw subject.** `/council <subject>` with no Brief — council builds its own grounding. Resolve the subject (below), gather the grounding in §3, and proceed. Use this for a human running council ad-hoc on a diff or a PR.

**The Brief's field contract.** Every field is exactly one of three kinds — and for the REQUIRED fields, the label additionally names WHAT HAPPENS on absence, because the three do NOT behave the same when omitted. The **minimum viable Brief is `subject` + `mode` + `brief_version`** — the SAME set `TEMPLATE_COUNCIL_BRIEF.md` states, so a caller that writes exactly these three satisfies both files and produces no spurious blind spot; everything else council can either self-gather or default:
- **`subject`** — **REQUIRED — absence is FATAL.** No default. `{type, pointer}`, type one of the §1.B vocabulary. Council never invents one; a missing subject is one `AskUserQuestion` in `interactive` and a HARD ERROR in `report-only` (§1.B).
- **`mode`** — **REQUIRED — absence DEFAULTS (with a stated blind spot).** `interactive` | `report-only`. Governs §1.B's guards and §5.F. A Brief with no `mode` and no `--mode` arg → `report-only` + the missing field stated as a blind spot; see below.
- **`brief_version`** — **REQUIRED — absence WARNS (and proceeds).** The template revision the Brief was written against (current: **`1`**). A missing or mismatched value never aborts — council proceeds, self-gathers anything the current contract needs, and states the mismatch as a blind spot; see below. Because it is part of the minimum viable set, a Brief written to spec carries it and this blind spot never fires spuriously.
- **`grounding`** — **SELF-GATHERED-IF-OMITTED**. Touched files, ticket intent, the whys/deliberate decisions, the dialogue/plan digest, house rules. Omitted → council gathers it in §3 and states the thin Brief as a Panel Blind Spot.
- **`panel.size`** — **OPTIONAL**. `1 | 3 | 5 | 7`, default **3**.
- **`focus`** — **OPTIONAL**. What to weight; also steers the §2 generative persona selection.

**`mode` — the behavior flag (NOT caller identity).** Council never learns WHO called it; it learns how to behave. A new caller picks a mode and council does not change:
- **`interactive`** — a human is present. Clarifying `AskUserQuestion`s are allowed (bounded as stated below), and §5.F offers the next-step chains.
- **`report-only`** — a machine caller (`/implement`, `/pr`, any future skill) is present and **no human can answer anything**. **Every `AskUserQuestion` in this protocol is FORBIDDEN** — every path that would ask must instead hard-error (§1.B) or proceed with a stated blind spot. §5.F is suppressed entirely; the caller owns the single gate. The handback is the report path **plus the §5.D structured verdict block**.
- Resolve it from an explicit `--mode` arg FIRST (an operator on the command line overrides the Brief, exactly as a subject arg overrides the Brief's subject pointer — see the Precedence rule below), else the Brief's `mode`, else — a raw `/council <subject>` typed with no Brief and no `--mode` — default **`interactive`** (a human is definitionally at the terminal). A Brief with no `mode` **and no `--mode` arg** is a malformed Brief: treat as `report-only` (a Brief was machine-written) and state the missing field as a blind spot in the report. (Brief-with-no-`mode` + an explicit `--mode` → the arg wins, per the first clause; Brief-with-no-`mode` + no arg → `report-only`, per this one. The two never both fire.)

**`brief_version` mismatch.** If the Brief's `brief_version` differs from the current template revision, do NOT abort — the template is strictly additive, so an older Brief is still readable. Proceed, treat unknown fields as grounding, self-gather anything the current contract requires that the older Brief lacks, and **state the mismatch explicitly** in the Acknowledge line and as a Panel Blind Spot (`Brief written against v<N>, council expects v<M> — fields X, Y self-gathered`). A missing `brief_version` is itself a mismatch — say so.

**Precedence & degradation (both given, or a thin Brief).** An explicit `--brief <path>` is **authoritative** for grounding — but a subject arg passed on the same command line **overrides the Brief's subject pointer** (a human running `/council diff --brief x.md` reviews the working-tree diff, not the Brief's stale subject); all other grounding (intent, whys, touched files, digest) still comes from the Brief, and args self-gather only what the Brief omits. If a **SELF-GATHERED-IF-OMITTED field is missing or blank** (empty Touched files, no intent), do NOT review in a vacuum: self-gather that field from the resolved subject (§3) and NOTE the thin Brief as a Panel Blind Spot in the report. If the gap can't be self-gathered, branch on `mode` — **never ask unconditionally**:
- **`interactive`** — ask ONE `AskUserQuestion` to pin it.
- **`report-only`** — asking is forbidden and there is nobody to answer. Proceed at explicitly-lower confidence with the missing-grounding warning stated in the Acknowledge line and as a Panel Blind Spot. (A missing *subject* is the one exception — that is a hard error, not a degradation; see §1.B.)

Either way, never degrade silently: the warning lands in the Acknowledge line AND the report.

**B. Resolve the Subject** (what the panel reviews — polymorphic, and **always explicitly targeted**)

**Council is targeted, never assumed. There is NO default subject** — not even for a human. Council must never resolve "whatever the tree happens to hold": a caller that never chose `diff` would silently get a live, always-dirty working tree reviewed as if it had asked for it. The subject comes from the Brief's subject pointer or from the args, and from nowhere else.

The vocabulary — exactly one of:
- `diff`: the uncommitted working-tree diff (`git status --short` + `git diff`). **Explicit-only — never implicit, never a fallback.** It is a legitimate thing to *ask* for and an illegitimate thing to *assume*.
- `commit <ref>` / `<a>..<b>`: that commit or range (`git show` / `git diff <a>..<b>`).
- `files <glob…>`: the explicitly named files.
- `pr <#>`: the PR diff (`gh pr diff <#>`) + its description/linked ticket.
- `plan <path>`: a plan document (an `IMPLEMENTATION_PLAN.md` or any design doc under review *before* code exists). The panel reviews the plan's soundness, not code.
- `build-report <path>`: a `/build` Build Report + its authoritative `filesTouched` (review those files).
- `doc <path>`: a prose/design/architecture document. The panel reviews the argument, not code.
- `brainstorm <path>`: a `BRAINSTORM.md` or ideation / design-exploration document. Like `plan` / `doc`, it is an **argument, not code** — the panel critiques the *reasoning, completeness, and risk* of the ideation (are the trade-offs real, the pre-mortem honest, the decision sound, the alternatives fairly weighed), never an implementation. Files it proposes to create are to-be-created context, not gaps (§3 subject-type-aware reads treat it exactly like a `plan` / `doc`).
- `session <dir>`: a session's whole body of work — its plan **plus the session's own diff** (only the files that session touched, per its log + build reports) **plus its build reports**. This is the subject that makes **plan-vs-actual** reviewable: the panel sees what was intended and what was actually built. Resolve it per §3.

The panel adapts its reading to the subject type: for `plan` / `doc` / `brainstorm` it critiques reasoning, completeness, and risk; for `diff` / `commit` / `pr` / `files` / `build-report` it critiques the resulting code; for `session` it critiques both, and the gap between them.

**No-subject guard (asymmetric by design).** If neither the Brief nor the args name a subject, branch on `mode`:
- **`interactive`** — a human mistargeted; help them. Ask ONE `AskUserQuestion` to pin the subject. Do not guess, and do not fall back to `diff`.
- **`report-only`** — a machine cannot answer a question, and a caller that omitted the subject has a bug that must surface. **HARD ERROR.** Write no report. Return the error to the caller.

**Empty-resolved-subject guard (same asymmetry).** A subject can *name* something and still resolve to nothing: an empty working-tree diff, a PR with no changes, an empty or unreadable plan, a `session <dir>` that resolves to **nothing at all** — no plan, no touched files, AND no build reports. A `session <dir>` with SOME resolvable content (e.g. a plan but no diff yet — the normal shape of a plan-stage session, exactly the subject council is most often dispatched on before code exists) is a **partial** resolution, not a void: it does NOT trip this guard. Proceed per §3, naming each absent part as a Panel Blind Spot; §3 governs the partial case and this guard governs only the total-void case, so the two never both claim a `session` subject. **Council never reviews a void** — a panel handed nothing produces confident generic platitudes, which is worse than an error because it looks like a clean review. After resolving the subject content, if it is empty:
- **`interactive`** — ask ONE `AskUserQuestion` to re-target ("the working tree is clean — review a commit instead?").
- **`report-only`** — **HARD ERROR.** Write no report. Return the error; the caller's failure branch owns it.

In both guards the `interactive` branch asks because a human is present to correct a mistarget, and the `report-only` branch errors because a machine caller cannot answer and must be told its dispatch was wrong. Never blur the two.

**C. Resolve the Trail (`<trailDir>`), Slug & Report Path.**
Determine these once and use them everywhere so the trail clusters correctly:
- **`<trailDir>` = `<sessionDir>/builds/`.**
- **Slug:** mint `<slug> = <short-kebab-of-subject>` (e.g. `pr-1400`, `council-skill`, `plan-resync-gate`). *Crucial:* before minting, run `ls <trailDir>`. If an existing `<slug>_*.md` clearly matches this work (same chunk / ticket / topic), REUSE that slug so the council report clusters with the `/build`, `/scrutinize`, and `/probe` artifacts for the same work. If the Brief came from a `/build` or `/scrutinize` chunk, reuse THAT chunk's slug. The slug governs where the raw per-expert findings *cluster* — it is deliberately NOT the reconciled report's identity (that is `report_path`, below).
- **`report_path` — the per-run identity of the reconciled report.** Resolve it in this order:
  - **(1) Caller-supplied.** If the Brief carries a **`report_path`** field, write the reconciled report *exactly there*. A machine caller (`/implement`, `/pr`, `/direct`) MUST mint a path unique to THIS dispatch and pass it, because the caller's failure branch checks that same path for absence (§5.D handback).
  - **(2) Self-derived (a bare human `/council` with no Brief `report_path`).** Fold a **run-id** into the slug: `report_path = <trailDir>/<slug>_COUNCIL_<run-id>.md`, where `<run-id>` is a short token unique to this run (a timestamp like `20260718T0227`, or a random suffix).
  - **Never write the bare `<trailDir>/<slug>_COUNCIL.md`.** Because the slug is *reused* across runs of the same work, a bare-slug report from a PRIOR run sits at that path already — complete and valid — and a caller's absence-check against it would read that STALE report as THIS run's clean verdict (the ***died-stale*** failure mode: a dead re-dispatch looks clean because a live earlier run left an artifact behind). A per-run `report_path` closes the gap: "this run wrote it" becomes distinguishable from "a prior run left one," and a truncated write can't be mistaken for a prior complete one either.

The per-expert findings go under `<trailDir>/<slug>_council/<lens>.md` (one file per expert — see §3/§4); the reconciled report is written to the per-run **`report_path`** resolved above (§5.C), and §5.D's verdict block hands back that SAME `report_path` so the caller's absence-check targets exactly the file this run wrote.

**Acknowledge:** Echo back your setup in exactly one line (append any degradation / `brief_version`-mismatch warning to it):
`Convening council on <subject> — brief: <brief path | self-gathered>; mode: <interactive | report-only>; panel: <size>; report: <report_path>.`

## 2. Compose the Panel

Decide the seated experts by **generative selection from a persona palette**. Diversity of *lens* is the product — a panel of clones is just a slow single reviewer — and diversity now spans TWO axes: *domain expertise* (what you know) AND *temperament* (how you think). Nothing is always-seated: even the structural / operational / edge-case lenses are chosen for the subject, not mandated.

**Read the persona index first.** The seatable experts live as character-profile files under `personas/` alongside this `SKILL.md` (this skill's own `personas/` directory — resolve it relative to this skill's location, not the project cwd). Read the **persona index** there — the CMD/index that lists all 20 personas, each with a one-line **`Good for … / Bad for …`** hint, a **`domain`** or **`temperament`** tag, and a **`→ personas/<name>.md`** file pointer. The index is the authoritative roster: do NOT hardcode the persona names in this skill — read them from the index at composition time (the roster grows and shifts there, not here). Reading the cheap index costs almost nothing; you load the *full* profiles only for the seated few (below). **Note the index's `roster_version`** (declared near its top) as you read it — you stamp it into the report (§5.C) and the structured verdict (§5.D) so the review is auditable against the exact roster state it was selected from.

**Size.** Take it from the Brief or `--size`; default **3**; accept **1 | 3 | 5 | 7**. A focused single-concern change wants 1; a normal diff wants 3; a whole PR or a cross-cutting plan justifies 5; a genuinely **cross-functional** subject — one that spans many distinct domains at once (say a feature touching data + API + frontend + copy + legal/compliance) — justifies **7**. Seven is never a default: the compose step must JUSTIFY it in the Panel line by naming the distinct domains that each earn a dedicated lens; if you can't name that many genuinely-different domains, don't go to 7.

**Generatively select the N most relevant personas.** Read the subject content + the `focus`, then pick the N personas whose `Good for …` best fits THIS work and whose `Bad for …` doesn't disqualify them. This is a judgment call over the index hints, not a keyword match: reach for the domain personas the subject's *substance* invites (a copy-heavy change wants the Copywriter; a migration wants the data/storage lens; an auth surface wants Security; frontend wants the UX / Accessibility lenses) AND the temperament personas the subject's *risk* invites (a load-bearing assumption wants a First-Principles or Contrarian voice; a sprawling design wants a Minimalist or Systems Thinker). Collisions between personas' centers of gravity are fine — pick the sharpest fit, not a disjoint partition.

**HARD DIVERSITY RULE — any panel of 3+ MUST seat at least one temperament persona.** Generative selection left unchecked can seat three-to-seven *agreeable domain experts* who all nod — coverage without dissent, which rubber-stamps. The temperament axis is what makes a panel genuinely disagree. So at size **3, 5, or 7**, after the generative pick, CHECK the seated set against the index's `domain` / `temperament` tags: if it holds **zero** temperament personas, SWAP one domain persona out for the temperament persona most relevant to the subject's risk. Enforce this in the compose step — it is not optional, and the §5.A independent refutation pass is only the SECOND backstop, never a substitute for seating an adversarial voice up front. (At size 1 the rule does not fire — the lone generalist already folds in the adversarial/edge-case temperament; see below.)

**EXPECTED-DOMAIN CHECK — the second compose-time check (domain-fit, not temperament).** The diversity rule above guarantees a dissenting *temperament*; it says nothing about whether the panel actually covers the subject's *domain*. So after the pick, run this second check: map the subject's substance to the domain lens it plainly warrants, and if that lens ISN'T seated, either seat it (if the size allows) or **name it as a Panel Blind Spot** in the report. This is **add, don't swap** — do NOT aggressively evict a chosen persona to force-fit a lens; it complements the diversity rule's swap, it does not duplicate it. The compact subject → expected-lens map (a `§FMT` list, judgment not keyword-match — a subject can warrant several):
- frontend / UI / components / markup / layout → a design/UX lens (Product-UX, Visual Designer, UX Designer) AND Accessibility.
- migration / schema / SQL / Drizzle / storage → Specialist.
- auth / access-control / endpoints taking user input / tenant boundaries → Security.
- LLM / structured-output / JSON-schema handed to a model / classifier / prompt → Schema-Purist.
- user-facing copy / error & empty states / onboarding text / naming → Copywriter.
- personal/customer data / PII / retention / audit surfaces → Compliance Counsel.
If the subject clearly sits in one of these buckets and the corresponding lens is unseated, that gap is exactly what this check exists to surface — seat it or flag it, never silently omit it.

**Load only the seated profiles.** With the N chosen (after the diversity rule and the expected-domain check above), load ONLY those personas' full profile files (`personas/<name>.md`) — never the whole palette. Each seated profile is injected verbatim into that expert's prompt as its lens (§3). The ~15 unseated profiles are never read; the index hint was enough to decide.

**At 1**, seat a single **principal generalist** — one seasoned reviewer who explicitly wears several hats at once: structure, the concrete break, AND the dominant domain risk the subject surfaces. State in its prompt that it must cover all three. (The diversity rule does not apply at 1: a competent generalist already carries the adversarial/edge-case temperament internally.)

**State the seated panel + why in one line**, naming each seated persona with its one-line reason, and calling out any diversity-rule swap and any size-7 cross-functional justification — e.g. `Panel (5): Architect (module boundaries in the new service), Operator (fan-out under burst load), Copywriter (user-facing error strings), Specialist (the migration), Contrarian (temperament — swapped in per the diversity rule, to press the "resync is safe" assumption).`

**Also append the composed panel to the running panel log** (a passive audit trail, NEVER a gate). Right after you state the seated panel, append that same `Panel (N): …` line — prefixed with the subject type and followed by the `report_path` — to `<trailDir>/COUNCIL_PANELS.md`, so selection composition can be audited over runs (later you can grep "how often was the Copywriter seated in the last N runs" and catch the selector regressing to the same few personas — a monoculture guard). This **records, it never blocks**: it does not gate, re-open, or alter the panel you just composed. Append exactly as §5.E does for `LESSONS.md` — blind append, never read-modify-write (`¶CMD_APPEND_LOG`): `engine log <trailDir>/COUNCIL_PANELS.md` with a **`## `-headed block** (it requires the heading and auto-injects the timestamp; a headerless body exits 1). Put the subject type, the `Panel (N): …` line, and the `report_path` as bullets under one dated `## ` heading.

## 3. Assemble Grounding + Build Each Expert's Self-Contained Prompt

An expert sub-agent cannot see your memory, the Brief, or the session — its whole world is the prompt you hand it. Assemble the grounding ONCE, then compose it into each expert's prompt with that expert's persona bolted on.

**The shared grounding** (assemble once, reuse for every expert):
- **The subject content** — the actual diff / plan / doc / PR text under review.
- **The FULL touched files, not just the hunks.** A diff hunk hides the context that determines whether a change is safe. Read the whole of each changed file (from the Brief's file list, or resolved from the subject) so the panel judges the change in situ. For a `plan` / `doc` / `brainstorm` subject, this is the document itself plus any files it centrally references.
- **Discoverable house rules** — `PITFALLS.md` / `CONTRIBUTING.md` / relevant `CLAUDE.md` if present in the repo, so findings respect established conventions and deliberate decisions rather than re-litigating them.
- **Ticket intent** — from the Brief (or the PR / linked ticket) — what this work is *for*, so the panel reviews against purpose, not in a vacuum.
- **The Brief's dialogue / plan digest** — the whys and constraints the Brief carries. Deliberate decisions are NOT findings; the panel must know what was chosen on purpose.

**Resolving a `session <dir>` subject.** Assemble three parts and hand the panel all of them, labeled:
- **The plan** — `<dir>/IMPLEMENTATION_PLAN.md` (or the session's equivalent design doc).
- **The session's own diff** — NOT the whole working tree. Derive the file list from the session's own record: the `filesTouched` of every `<dir>/builds/*_BUILD.md` plus the files its `*_LOG.md` records touching. Read those files (and, where they're tracked and committed, their `git show HEAD:<path>` baseline for contrast). This scoping is what keeps a parallel agent's unrelated dirty files out of the review.
- **The build reports** — every `<dir>/builds/*_BUILD.md`, for the stated approach, deviations, and `assumptionsThatCouldBeWrong`.
Frame the panel on the **gap**: what the plan intended vs. what the reports + files show was actually built. If any of the three parts is absent, say which in the Panel Blind Spot rather than substituting the working tree for it.

**Subject-type-aware reads (a missing file means different things).** When a referenced file can't be read, what that MEANS depends on the subject type — do not report them the same way:
- **`plan` / `doc` / `brainstorm` subjects** — referenced files that don't exist yet are **expected**, not a gap. They are the files the plan / ideation proposes to CREATE. Label them to the panel as *to-be-created context* and move on. Flagging "file not found" as a finding on a plan or a brainstorm is noise, and a panel that doesn't know this wastes its lens on it.
- **Code subjects (`diff` / `commit` / `pr` / `files` / `build-report` / `session`)** — a referenced file that should exist and can't be read **is a real gap**. The code under review presupposes it. State it as an explicit **Panel Blind Spot** ("`path` was unreadable — the panel could not judge X in situ"); never let it pass silently, and never let the panel infer the file's contents.
State which reading applies in each expert's prompt, so the panel judges absence correctly instead of guessing.

**Each expert's prompt** = its persona + the shared grounding + the categorization contract + the Failing-Scenario rule + its OWN write path. Build it from this template (substitute per-expert):

> You are a **<PERSONA NAME>** on a review panel — one expert among several, each reviewing the same work through a different lens. You are adversarial but constructive: your job is to surface the real problems only YOUR lens catches, not to rubber-stamp and not to nitpick cosmetics. Other experts cover the other angles; you go deep on yours.
>
> **Your lens — who you are and how you think (go deep here):** `<the seated persona's FULL profile, injected verbatim from its `personas/<name>.md` — who you are / how you think / what you fight for / what you'd wave through / your tell>`
>
> **The subject under review:** `<subject type + pointer>`.
> **The work:** `<the subject content / diff / plan / doc>`.
> **Full touched files (judge the change in situ, not just the hunk):** `<the full files>`.
> **Files referenced but not readable:** `<the list + the subject-type-aware framing: "to-be-created — this plan proposes them, do NOT flag them as missing" for a plan/doc subject, or "unreadable — a real blind spot; do NOT infer their contents" for a code subject>`.
> **What this work is for (intent — do not flag deliberate decisions):** `<ticket intent + the Brief's whys/constraints + discoverable house rules>`.
>
> **Categorize every finding** as exactly one of:
> - **MUST FIX** — a real defect that will cause incorrect behavior, data loss, a regression, a security hole, or a production incident. Reserve this tier; it faces a refutation pass.
> - **SHOULD FIX** — a genuine weakness (fragile heuristic, missing error handling, a test gap, a scaling cliff that's not yet hit) worth addressing but not a breakage.
> - **CONSIDER** — a judgment call, a trade-off, or a structural improvement the author should weigh. Not a defect.
>
> **The Failing-Scenario rule (hard):** every MUST FIX and SHOULD FIX needs a `file:line` and a concrete way it breaks — the exact input / state / sequence that triggers the defect. A finding with no failing scenario is not a finding; downgrade it to CONSIDER or cut it. This kills vague "consider improving X."
>
> **Skip cosmetic nits** (formatting, naming preferences with no correctness impact). Do NOT try to fix anything — you review only. Do NOT run destructive git (`¶INV_NO_DESTRUCTIVE_GIT`): read committed versions with `git show HEAD:<path>`; read-only git (`status`/`log`/`diff`/`show`) is fine; never `stash`/`checkout`/`switch`/`restore`/`reset`/`clean`/`rm`/`add`. You MAY run read-only builds/tests/type-checks to confirm a suspicion — state what you ran.
>
> **Return contract:** WRITE your findings to `<trailDir>/<slug>_council/<lens>.md` (the orchestrator gives you the fully-substituted absolute path — do NOT hardcode `~/.claude`, and do NOT write to any other path or you will clobber another expert). **Write each finding as a Decision Card** (`§FMT_DECISION_CARD` — the disclosure format, adapted for a read-only report: no interactive gate, no `AskUserQuestion`): the **tier** (its engagement / attention level — MUST FIX / SHOULD FIX / CONSIDER), a short title + `file:line`, your **recommendation** (the direction you'd take — a POV, not a patch), the **at-risk / severity** (why it's wrong through your lens + the concrete failing scenario), the **downside of the fix** (what applying it costs / loses), the **complexity impact** (does the fix add surface or muddy the design?), and the **cheap proof** (the low-cost check that would confirm or size it). End with a one-line lens verdict. Then RETURN to the orchestrator a compact list: each finding's tier + title + `file:line` (one line each) + your verdict. Do NOT dump full findings into the return message — the orchestrator reads your file.

**The Schema-Purist's extra briefing** (append ONLY to the Schema-Purist persona's prompt, when that persona is seated for LLM / structured-output code — this checklist supplements its profile; it is concrete review scaffolding, not the persona's character). Hand it this JSON-schema review checklist:
- **Strict mode on.** The structured-output schema must run in strict mode; a non-strict schema silently drops constraints.
- **`additionalProperties: false`** on every object — an open object lets the model invent fields that bypass validation.
- **All properties required.** OpenAI strict mode requires every property in `required`; optionality is expressed via nullable union (`["string","null"]`), not by omission.
- **Evidence grounding.** Fields that assert a fact (a tag, a match, a classification) must carry a grounded evidence field (a quote / span), not a bare boolean the model can hallucinate.
- **Temperature 0–0.2** for extraction / classification — higher temperatures make structured output non-deterministic and inflate the eval variance.
- **Schema-name versioning.** OpenAI caches structured-output schemas BY NAME. A shape change without a name bump silently serves the stale cached schema — verify the cache-key name is bumped alongside any shape change (and the committed fingerprint regenerated, if the repo gates on one).
- **Prompt vs. schema separation.** Instructions belong in the prompt; the schema constrains shape only. Business rules smuggled into `description` fields are brittle and un-versioned.
- **Discriminated unions** for polymorphic results — a flat optional-soup object lets invalid combinations validate; a discriminated union makes the illegal states unrepresentable.
- **The 8 review questions to answer explicitly:** (1) Is strict mode on? (2) Is `additionalProperties:false` on every object? (3) Is every property in `required` (nullable-union for optional)? (4) Does every asserted fact carry grounded evidence? (5) Is temperature in 0–0.2 for deterministic extraction? (6) Was the schema-name / cache key bumped for this shape change? (7) Are prompt instructions kept out of the schema? (8) Are polymorphic results modeled as discriminated unions rather than optional soup?

## 4. Fan Out N Experts IN PARALLEL

> **Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + context-pack pointer + one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

(This is the primary fan-out; the §5.A `critiquer` refutation dispatch is a secondary handoff, logged the same way when it fires.)

This is the heart of the skill: **N genuinely independent expert sub-agents running at once**, NOT one agent role-playing N personas (simulated diversity is not diversity). Spawn one Task sub-agent per seated expert, all in a single batch so they run concurrently, `run_in_background: true`. Give each its own persona-specific prompt from §3 and its OWN write path `<trailDir>/<slug>_council/<lens>.md` (create the `<slug>_council/` dir first).

**The clobber trap (non-negotiable).** Parallel sub-agents handed ONE shared output path silently destroy each other's work — the second writer wins, the first's findings vanish with no trace. Each expert gets its OWN per-lens path. Reserve the bare `<trailDir>/<slug>_COUNCIL.md` exclusively for YOUR reconciled report in §5. Never hand two experts the same file.

**Use the wait — don't idle.** While the panel runs, get a step ahead: re-read the highest-risk touched file yourself so you can spot-check the panel's load-bearing findings the moment they land, and pre-think which findings the refutation pass will most want to challenge. The completion notifications bring you back to §5 with momentum.

Collect every expert's returned compact list as they land. If one expert fails or returns empty, note it as a panel blind spot in §5 rather than silently dropping a lens.

**Zero experts seated → HARD ERROR. Write NO report.** If the fan-out produces **no** usable panel at all — every sub-agent failed, the harness silently no-op'd the nested dispatch, or not a single expert returned findings — council **must stop and error**. Do NOT write `<trailDir>/<slug>_COUNCIL.md`. Not an empty one, not a partial one, and **not an "INCOMPLETE" one**:
- The reasoning is physical, not stylistic. A Council Report is the artifact that says "a panel looked at this." If council can produce that file with no panel behind it, then *died* and *found nothing* become indistinguishable to every downstream reader — the exact failure this contract exists to prevent. An INCOMPLETE report only moves that confusion one level down, into a status field a caller may not read. **The only honest signal is the absence of the artifact.**
- So: no `_COUNCIL.md` exists ⇒ no panel ran. That invariant is worth more than a graceful-looking degradation.
- Any per-lens files that DID land under `<slug>_council/` stay on disk as the raw record — they are not the report and cannot be mistaken for it. (This preserves the §1.C anti-clobber rule: the bare `<slug>_COUNCIL.md` remains reserved, and here simply unwritten.)
- **`report-only`** — return the error to the caller. Its bounded-wait / failure branch owns it and will treat a dead council as a blind spot, never as clean.
- **`interactive`** — report the failure plainly to the human ("the panel failed to seat — no report written"), and stop. Do not review it yourself: a single orchestrator opinion wearing a council's name is precisely the simulated-diversity failure this skill exists to avoid.

A **partial** panel (at least one expert returned) is NOT this case — that proceeds to §5 with the dead lenses named as Panel Blind Spots.

## 5. Refute → Reconcile → Report → Relay → Ledger → Stop

**A. Refute the MUST FIX findings — independently.** Panels over-flag — an expert deep in its lens will escalate a non-issue. So every MUST FIX faces an independent skeptic that tries to REFUTE it before it earns its tier. This refutation MUST NOT default to the orchestrator's own reasoning: the orchestrator composed the panel and will author the reconciled report, so it has a mild stake in the deliverable and is not a neutral adversary — and it must not be the expert that raised the finding either. At **every** panel size (including size 1, where the lone generalist's MUST FIX still earns an independent pass), dispatch **one fresh `critiquer` sub-agent** as the devil's advocate — a DIFFERENT agent than any that produced the findings. Hand it the surviving MUST FIX findings + the FULL touched files + the grounding's stated deliberate-decisions, and frame it to argue the strongest good-faith case that each is NOT a real defect (the input can't actually occur; an upstream guard already handles it; the "bug" is deliberate and documented in the grounding; the failing scenario doesn't hold on the full file). **Default to refuted when uncertain:** a MUST FIX earns its tier only if the independent refuter cannot make a credible case against it; if it can — or is left genuinely unsure the defect is real — downgrade it (to SHOULD FIX / CONSIDER) or drop it. Record for each MUST FIX whether it *survived* or was *refuted*, with the one-line reason.

**B. Reconcile.** Merge the surviving findings across experts into one set:
- **Dedup** cross-expert overlap — when two experts raised the same defect, merge into one finding.
- **Consensus-tag** each finding with WHICH experts raised it (e.g. `raised by: Skeptic, Operator`). Consensus is confidence: a finding three experts independently flagged is far stronger than one lone voice — surface that signal.
- **Order** by tier (MUST FIX → SHOULD FIX → CONSIDER), then by consensus count within a tier.

**C. Write the reconciled report.** Write the reconciled report to the per-run **`report_path`** resolved in §1.C (a caller-supplied path, or `<trailDir>/<slug>_COUNCIL_<run-id>.md` for a bare human run — NEVER the bare `<trailDir>/<slug>_COUNCIL.md`, whose reuse across runs is the *died-stale* hazard) from `assets/TEMPLATE_COUNCIL.md`: the subject + panel composition (**including the `roster_version` the panel was selected from**, per §2, so the report is auditable against a specific roster state) + per-expert findings **each written as a Decision Card** (`§FMT_DECISION_CARD`, read-only variant — recommendation + at-risk/severity + downside-of-the-fix + complexity impact + cheap proof + tier-as-engagement; no interactive gate, council reports rather than triages) + the refutation outcomes + the Cross-Expert Priority Summary (each finding: tier, consensus tag, `file:line`, failing scenario, suggested direction) + the panel's collective blind spots + the **Structured Verdict block** (§5.D's exact JSON — write it into the report in **both** modes so the report stays auditable after the fact against what the caller was handed; its `verdict`, `counts`, and `findings` MUST agree with the Cross-Expert Priority Summary — they are the same set rendered for a machine — and in `interactive` it is simply left unread). The per-lens files under `<slug>_council/` remain as the raw record; the `_COUNCIL.md` is the synthesis.

**D. Hand back — the shape depends on `mode`.**

**`interactive` — relay answer-first.** Lead with the verdict, not the process: the overall read (e.g. *sound with 2 must-fixes* / *not ready* / *solid*), the top surviving MUST FIX findings, and the counts (`N MUST FIX, M SHOULD FIX, K CONSIDER`). Then the numbered priority summary — title + one-line essence + consensus tag each. Keep it tight; the full report is on disk. Link it (`§CMD_LINK_FILE`). Then §5.E (ledger) and §5.F (the offer).

**`report-only` — return the report path PLUS a structured verdict block.** A machine caller must route findings without re-parsing prose; prose is for humans, and a caller that has to regex a narrative is a caller that will silently mis-route. Return exactly this, as a fenced JSON block, alongside the report path:
- **`verdict`** — one of `solid` | `sound_with_fixes` | `needs_work` | `not_ready`.
- **`counts`** — `{must_fix, should_fix, consider}` (integers; the surviving tiers, post-refutation).
- **`findings`** — an array of `{id, tier, file_line, consensus}` — `id` the report's finding number, `tier` one of `MUST FIX` | `SHOULD FIX` | `CONSIDER`, `file_line` the `path:line` string, `consensus` the array of lens names that raised it.
- **`report_path`** — the absolute per-run `report_path` resolved in §1.C and written in §5.C (a caller-supplied path, or `<trailDir>/<slug>_COUNCIL_<run-id>.md`) — the SAME value written above, so the caller's absence-check targets exactly the file THIS run wrote and can never mistake a prior run's reused-slug report for it.
- **`roster_version`** — the integer `roster_version` of the persona index the panel was selected from (§2), so the caller can tell which roster state produced this verdict.
- **`blind_spots`** — array of one-line strings (an unseated warranted lens — including one the §2 expected-domain check flagged — a dead expert, a thin Brief, a `brief_version` mismatch). Empty array only if there genuinely are none.

The block is a *pointer plus a routing index*, not a replacement for the report — the caller reads the file for detail. The counts and the findings array MUST agree with the report; they are the same set, rendered for a machine.

**E. Feed the ledger.** Append the durable, settled outcomes of this review to `<trailDir>/LESSONS.md` — the confirmed defects and resolved design judgments, as terse bullets (facts, not narrative). **This runs in BOTH modes** — a `report-only` (machine-dispatched, often backgrounded) council is exactly the run whose conclusions most need to compound, so the append happens HERE, before the mode-gated stop in F, and both modes reach it. The next `/build` or `/council` reads these so conclusions compound instead of evaporating.

**Blind append, never read-modify-write (`¶CMD_APPEND_LOG`).** `LESSONS.md` is shared: a backgrounded council may write it while a concurrent `/pr`, `/build`, or another council appends too, so a write must not corrupt a sibling's. Append with `engine log <trailDir>/LESSONS.md` using a **`## `-headed block**. This is exactly `/build`'s convention for the SAME shared file (its ledger step), so the two skills' entries share one format. `engine log` is already append-safe AND *requires* a `## ` heading — it exits 1 without one, and auto-injects the timestamp, per `¶CMD_APPEND_LOG` — so put the settled outcomes as bullets under one dated `## ` heading; do NOT hand `engine log` a headerless body.

**F. Stop — offer next steps, never act.** *(`interactive` ONLY — in `report-only` this whole step is **suppressed**: the caller owns the single gate, and council must not compete with it for the user's attention. Do not ask, do not offer — E's ledger append has already run, so just hand back D's block and stop.)* `/council` is read-only: it reviews and reports, full stop. Offer the chains via `AskUserQuestion`, but do NOT auto-run any of them:
- `/scrutinize` — to verify a finding against intent and FIX it (council found it; scrutinize proves + repairs it).
- `/fix` — to repair a confirmed defect directly.
- **Loopback** — when the subject was a *plan* reviewed on behalf of `/implement`, hand the findings back to the caller for the plan-revision loop rather than acting.
Keep the human gate. Council does not fix, commit, or file.

## Constraints
- **Read-only, absolutely.** No code edits, no writes outside the trail, no commits, no ticket writes, and no tree/index-destructive git (`¶INV_NO_DESTRUCTIVE_GIT` — the tree is always dirty with other agents' uncommitted work). A change the review seems to warrant is a **finding**, not an action. Fixing is `/scrutinize`'s / `/fix`'s job.
- **The Brief is the interface — sessionless.** Council reads a Council Brief (or self-gathers from a raw subject), NEVER a session. It does not activate a session, read `DIALOGUE.md`, or reconstruct context from session state. That decoupling is what makes it composable across a human, `/implement`, `/pr`, and future callers. *(A `session <dir>` **subject** is not an exception: those files are the thing under REVIEW, read as a subject, not as council's own context.)*
- **Targeted, never assumed — no default subject.** The subject is always named by the caller; `diff` is explicit-only and never a fallback. Council never reviews "whatever the tree holds", and never reviews a void: a missing or empty-resolved subject is one `AskUserQuestion` in `interactive` and a **hard error** in `report-only`.
- **`mode` is a behavior flag, not caller identity.** `interactive` allows questions + the §5.F offer; `report-only` forbids **every** `AskUserQuestion`, suppresses §5.F, and returns the structured verdict block. Council never learns WHO called it — a new caller just picks a mode.
- **No panel ⇒ no report.** Zero experts seated is a hard error that writes NO `_COUNCIL.md` — not an empty or INCOMPLETE one. The artifact's existence IS the claim that a panel ran; keep that unfalsifiable.
- **A panel, not an auditor.** Real fan-out of N independent expert sub-agents in parallel — genuine diverse lenses, not one agent playing N personas. Seat generatively from the persona palette across BOTH axes (domain + temperament); nothing is always-seated, and any panel of 3+ MUST include ≥1 temperament persona.
- **Per-lens paths — never a shared findings file.** Each expert writes its OWN `<slug>_council/<lens>.md`; the bare `<slug>_COUNCIL.md` is reserved for the reconciled report. A shared path silently clobbers.
- **Refute before you escalate — independently.** Every MUST FIX faces an independent refutation pass by a fresh `critiquer` sub-agent (never the orchestrator's own reasoning, never the expert that raised it); it earns its tier only if that independent skeptic cannot refute it. Consensus (which experts raised it) is confidence.
- **Failing-Scenario or it's a nit.** Every MUST FIX / SHOULD FIX carries `file:line` + a concrete break; no scenario means downgrade to CONSIDER or cut. Cosmetic nits are skipped.
- **Building block — reviews, never advances.** It produces a Council Report + offers next steps, then stops. Verifying+fixing is `/scrutinize`; repairing is `/fix`; the plan loopback belongs to `/implement`. Chains are offered via `AskUserQuestion`, never auto-run.
- **Paper trail always.** The per-lens files + the reconciled `_COUNCIL.md` persist even on a partial or blocked run; durable outcomes compound into `LESSONS.md`.
