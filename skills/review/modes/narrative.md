# Narrative Mode (Waterline-Windowed, Gemini-Synthesized Progress Report)
*Bundles everything that happened since the last waterline and hands it to Gemini to write a continuous, story-driven progress update. Claude orchestrates discovery + bundling; Gemini does 100% of the reading and writing. Each run advances a running narrative and drops a fresh waterline so the next run is self-defining.*

**Role**: You are the **Windowed Narrative Reporter**.
**Goal**: Produce a continuous EOD/period progress narrative for the window *since the last waterline → now*, by bundling all evidence (git, debriefs, continuation logs, Linear, prior reviews) and letting Gemini synthesize — building the storyline forward, never restating it.
**Mindset**: "Since the last waterline, what's the *story*? Bundle it all, let Gemini write, advance the arc, then move the waterline."

## Key Principles
- **The waterline is the clock.** The report window is defined by the last logged `🔖 Waterline` in `REVIEW_LOG.md`, not a user-picked date range. Every run ends by dropping a new waterline, so the next run needs no date question.
- **Claude bundles, Gemini writes.** Claude does NOT read debriefs/logs into its own context — it discovers paths, assembles ONE consolidated bundle file, and pipes it to Gemini. No manual report prose, ever.
- **Continuity over snapshots.** Every run builds forward from the 3 most-recent reviews + the "banked shifts" recorded in the waterline. Honor the established headline arc; do not repeat what prior reviews already covered.
- **Size follows substance.** Target length scales to the volume of work (commits/sessions/tickets). A multiplier (1x / 2x) is offered up front; longer reports use a two-pass Gemini call (a single pass reliably under-shoots length).
- **Timezone-honest.** Window boundaries and `git --since` use *local* time. Commits and continuation-log timestamps are local.

## Phase Overrides

### Phase 0: Setup — Waterline + Window
*Derive the window from the waterline. No tag scan. No date-range question.*
1. Do NOT search for `#needs-review` / `#needs-rework` tags.
2. Read `REVIEW_LOG.md` in the active review session dir. Find the **last** `🔖 Waterline` entry and extract its "Next window: starts ___" local timestamp. That is the window START.
   - **No waterline found** (first-ever run): ask ONE `AskUserQuestion` — "What start date for this window?" (options: "Last 24h", "Last 3 days", "This week", "Custom"). Otherwise skip the question entirely.
3. Window = `[START(local) → now(local)]`. Compute a window slug: `MON_D_D` (same month) or `MON_D_MON_D` (spanning).
4. Auto-select **Gemini 2.5 Pro** (`gemini -m gemini-2.5-pro`). Skip `§CMD_SUGGEST_EXTERNAL_MODEL`. Audience is always the founder/team narrative voice.
5. Ask ONE `AskUserQuestion` — report length: "Default (scaled to volume)" / "2x (long — big window)" / "Custom multiplier". Record as `lengthMultiplier`.

#### Proof Override
> **Phase 0 proof:**
> - Mode: `narrative`
> - Role: `Windowed Narrative Reporter`
> - Window: `________ → now` (local)
> - Window slug: `________`
> - Length multiplier: `________`

### Phase 1: Discovery — Bundle Assembly (paths + bundling, no content-reading into Claude)
*Assemble ONE consolidated bundle file. Claude never reads debriefs into its own context.*
1. **Author git log — `--all` IS MANDATORY** — `git log --all --author="$(git config user.email)" --since="<START local>" --date=iso --pretty=format:'%h %ad %s' | sort -u -k1,1 | sort -k2,2r > GIT_LOG_[SLUG]_MINE.md`. Record the commit count.
   - ⚠️ **Never omit `--all`.** Without it the log is scoped to the *current checked-out branch* and every parallel workstream on its own branches (ops, hotfixes, merged PRs) becomes invisible. This has silently swallowed ~45% of a window's commits and an entire initiative. **Sanity gate**: compare `git log --oneline | wc -l` vs `git log --all --oneline | wc -l` for the window; if `--all` is materially larger, the extra commits are real work — bundle them.
2. **Session discovery** — find every `sessions/*/` dir (excluding the active review session) with at least one file `-newermt "<START local>"`. For EVERY in-window session emit a `### ▚ SESSION <dir>` block containing:
   - **Primary debrief** if present (priority: `IMPLEMENTATION.md` > `FIX.md` > `SESSION_SUMMARY.md` > `DO.md` > `ANALYSIS.md` > `BRAINSTORM.md` > first non-`_LOG`/`DIALOGUE`/`_PLAN` `.md`), capped ~25KB.
   - ⚠️ **No debrief? Do NOT drop the session.** Fall back to `head -120` of each `*_LOG.md`. A debrief-less session is often where the freshest/most urgent work lives — silently dropping them has hidden whole initiatives.
   - ⚠️ **The `builds/` trail** (from `/build`, `/probe`, `/scrutinize`): include the **summary-grade** artifacts — `LESSONS.md`, `*_TICKETS.md`, `*_CRITIQUE.md` — capped ~15KB each. Skip the raw transcripts (`*_CONTEXT_PACK.md`, `*_BUILD.md`, `*_PROBE.md`, `*_SNAPSHOT.md`, `*_FIX.md`) — they blow the context window (uncapped they reached 4.1MB) with little summary value. `find` at depth 1 only will miss `builds/` entirely.
   - **Continuation sessions** (dir date-prefix older than the window, but in-window activity): `awk`-filter each `*_LOG.md`, keeping only `## [<in-window YYYY-MM-DD>]` heading blocks → `_filtered_logs_[SLUG]/`. Write only non-empty files (never `rm` — it trips the destructive-command guard).
3. **Linear digest** — `grep -oE 'FIN-[0-9]+'` **the `--all` git log** → dispatch a **background sub-agent** to pull each ticket (state + title + outcome/pivot from comments), grouped into 4-6 thematic clusters, written to `LINEAR_TICKETS_[SLUG].md`. Proceed with bundling while it runs; splice in when it lands.
   - ⚠️ The ticket list inherits any git-log scoping bug — a branch-scoped log yields a workstream-blind ticket pull. Cross-check: skim the session dir *names* for themes absent from the ticket list (e.g. ops/alerting/email dirs when every ticket is one package) and pull those explicitly.
   - Also ask the sub-agent for any **project/initiative** the window's tickets hang off — new projects are the clearest signal a fresh initiative started, and they never appear in a commit message.
   - Instruct the sub-agent to **correct your brief** where it's wrong. Briefs written from commit messages routinely mis-state parentage and invent metrics; a rigorous agent will push back, and that correction is signal.
4. **Continuity reviews** — the 3 most-recent `REVIEW_*.md` (by waterline order in the log). These anchor the narrative arc.
5. **Assemble the bundle** — concatenate into `_BUNDLE_[SLUG].md` with clear `## SECTION` separators, in order: (1) git log, (2) new-session debriefs, (3) filtered continuation logs, (4) 3 prior reviews (labeled "build FORWARD, do not repeat"), (5) Linear digest.
6. **Size estimate** — baseline ≈ the last review's word count AND line count (`wc -w`, `wc -l` the newest REVIEW). Apply `lengthMultiplier` to the baseline: a 2x ask on a ~2,200-word / ~69-line prior means **~4,400+ words / ~130+ lines**. Record `targetWords`, `targetLines`, and a target sub-section count (~1 per major theme cluster; a 2x window is 14-18).
   - ⚠️ **The floor is the previous report, never less.** If the output lands *shorter* than the prior review when a longer one was asked for, that is a **failure**, not a judgment call — do not rationalize it ("2041 ≈ 2188, close enough" is exactly the error). Readers measure in lines as much as words; check both.
   - ⚠️ **Under-length is usually an input problem, not a Gemini problem.** Before accepting a short report, re-check step 1's `--all` gate and step 2's no-debrief/`builds/` fallbacks — a thin bundle produces a thin report, and the honest fix is more evidence in, not more padding out.
7. Log a one-line manifest to `REVIEW_LOG.md` (window, commits, sessions, bundle size, targetWords). Do NOT log per-session cards. Do NOT read debrief content.

#### Proof Override
> **Phase 1 proof:**
> - Commits in window: `________`
> - Sessions (new / continuation): `________`
> - Bundle size: `________`
> - Target words: `________`

### Phase 2: Dashboard & Interrogation — Skip Entirely
*No dashboard, no per-debrief validation, no interrogation.* Both framing questions (length, optional start date) were asked in Phase 0. If the user volunteered extra context, carry it into the Gemini prompt as `KEY CONTEXT`.

#### Proof Override
> **Phase 2 proof:**
> - Skipped per narrative mode: `true`
> - User context provided: `________`

### Phase 3: Synthesis — Gemini Two-Pass Pipeline
*Bundle → Gemini. Claude writes zero report prose.*
1. **Source the key**: `export GEMINI_API_KEY=$(grep -E '^GEMINI_API_KEY=' <repo-root>/.env | head -1 | cut -d= -f2- | tr -d '"'\'' ')`. (There is NO `engine gemini` command — use the `gemini` CLI directly.)
2. **Prompt** (write `_PROMPT_[SLUG].md`): instruct Gemini to write the Nth update (N = prior update number + 1), continuing the established headline arc; honor the **banked shifts** listed in the last waterline (extend, don't re-derive); mine 1-2 genuinely-new shifts from the window; match the prior reviews' voice (first-person plural, lay-explained jargon, outcome-first, numbers woven in); follow `TEMPLATE_REVIEW_NARRATIVE.md`; hit `targetWords` with the target sub-section count; output ONLY the markdown doc.
3. **Pass 1**: `cat _PROMPT_[SLUG].md _BUNDLE_[SLUG].md | gemini -m gemini-2.5-pro -o text > _GEMINI_OUT_[SLUG].md`.
4. **Expansion passes — Gemini systematically under-shoots length; plan on 2-3 passes total.** Loop until `wc -w` ≥ 0.95 × targetWords:
   - **Pass 2 (thematic)**: feed `_EXPAND prompt + pass-1 draft + bundle`. KEEP the draft (headline, voice, banked shifts, existing sub-sections); GROW by naming under-covered themes to add.
   - **Pass 3 (per-section, the one that actually works)**: if still short, run `awk '/^#{2,3} /{if(h)printf "%-60s %d\n",h,w; h=$0; w=0; next}{w+=NF}END{if(h)printf "%-60s %d\n",h,w}' draft.md` to get **per-section word counts**, then hand Gemini an explicit `current → target` per thin section **plus the specific unused bundle facts to spend the words on**. Vague "make it longer" instructions get ignored; per-section targets + named material reliably land it (3,483 → 4,966 in one pass).
   - **Check the headline each pass**: it must not recycle a phrase already banked as a prior "Shift in Thinking" (a draft once titled itself with the previous update's shift). Also scan for duplicate sub-sections covering the same subject twice.
5. **Finalize**: write the chosen output to `REVIEW_[SLUG].md`; ensure `**Tags**: #needs-review` sits on **line 2, immediately after the H1 with no blank line between** (Gemini often emits a blank line there, which breaks discovery). Verify with `engine tag find '#needs-review'` **run from the project root** — run from inside the session dir it searches a non-existent `sessions/` and returns 0 for everything, which looks like a tagging failure but isn't.
5b. **Fact-check before shipping**: grep the bundle for every figure the report cites. Numbers Gemini synthesizes from debriefs (rather than the git log) are usually right but occasionally unmoored — verifying is cheap and a wrong number in a stakeholder report is expensive.
6. **Log + move the waterline**: append to `REVIEW_LOG.md` a generation entry AND a fresh `🔖 Waterline` (last window covered → next window start = now; banked shifts to honor next time; live arcs to track; recommended default bundle = 3 newest reviews).
7. **Archive** intermediates (`_BUNDLE_*`, `_PROMPT_*`, `_GEMINI_OUT_*`, err logs) into `_audit_[SLUG]/`. Keep `GIT_LOG_[SLUG]_MINE.md`, `LINEAR_TICKETS_[SLUG].md`, `REVIEW_[SLUG].md` at top level.
8. Skip finding triage (`§CMD_WALK_THROUGH_RESULTS`). Skip cross-session conflict analysis. Narrative mode reports; it does not validate or triage.

#### Proof Override
> **Phase 3 proof:**
> - REVIEW written: `________` (real file path)
> - Generator: Gemini 2.5 Pro (passes: `___`)
> - Final word count: `________`
> - Waterline moved to: `________`

## Mode Template
**template**: `~/.claude/skills/review/assets/TEMPLATE_REVIEW_NARRATIVE.md`

## Walk-Through Config
*Not applicable — narrative reports skip triage entirely.*
**skip**: true
