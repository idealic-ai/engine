---
name: experiment
description: "Hands-on hypothesis probe — actually TRY something to answer a question rather than just read about it: reproduce a suspected behavior, hack a proof-of-concept, test whether an approach is feasible. A subagent runs the experiment in-tree (uncommitted, flagged, every touched file tracked), then reports a VERDICT (proved / disproved / inconclusive) + confidence — and you revert it or keep it for /implement. A building block: it probes and stops, never fixes, ships, or files. Triggers: \"let me try…\", \"see if I can reproduce\", \"hack a POC\", \"proof of concept\", \"is X feasible\", \"does Y actually happen\", \"spike this\"."
version: 1.0
tier: lightweight
args: "[<hypothesis / what to try>] [-- <what would count as proved / disproved>]"
---

Stop guessing; start knowing. Use `/experiment` to actually TRY something to answer a question — reproduce a suspected bug, hack a proof-of-concept, or probe an API's actual behavior — instead of merely reasoning about it. A subagent does the hands-on work in-tree (writing throwaway, uncommitted code; tracking every touched file), then reports the raw evidence and a verdict.

This is the **hands-on counterpart to `/analyze`**: where `/analyze` reads and reasons, `/experiment` writes and runs. Reach for it when the honest answer is "I'd have to try it to know." As a **building block**, it produces a *verdict*, not a fix. It never repairs the bug, ships the POC, or files a ticket. It runs within the active session, reports its findings, cleans up (or flags seeds), and stops. You decide what happens next: a repair via `/fix`, a full build via `/implement`, or capturing the work via `/ticket`.

# /experiment Protocol

## 1. Hypothesis & Success Criteria

Establish — lightweight — exactly what you are testing and what evidence will settle it. Resolve this from the arguments, else the active session / recent conversation:
- **Hypothesis:** The single claim under test, stated so it *can* be falsified. Text after `--` sharpens what counts as proved/disproved.
  *(Illustrative — adapt, don't copy: "The flat detector drops continuation rows on >1-page rooms", "we can render the recap tree from `entities[]` alone", "Gemini truncates on >15-page PDFs")*
- **Success Criteria:** What specific observation proves it, and what disproves it. If this is genuinely ambiguous, ask ONE `AskUserQuestion` to pin it. Otherwise, state your read and proceed (lightweight — don't interrogate the user needlessly). **DISPROVED is a fully successful outcome** — as valuable as proved, because it saves the orchestrator from a dead end. Don't massage a disproof into "proved."
- **Sandbox Boundaries:** This experiment writes throwaway code **in-tree, uncommitted**. Note anything it MUST NOT touch (e.g., "Do not run migrations", "Do not hit real external/prod services").

**Resolve the Trail** (used in §2/§3):
Set `<trailDir> = <sessionDir>/builds/`. Mint a short, kebab-case `<slug>` from the hypothesis (e.g., `flat-detector-continuation`, `recap-from-entities`).
*Crucial:* Before minting a new slug, run `ls <trailDir>`. If an existing `<slug>_*.md` clearly matches this work (same chunk / ticket / topic), REUSE that slug to cluster the trail. Only mint a new slug for genuinely new work. Ledger/log appends (§3) use `engine log`.

**Snapshot the Baseline (BEFORE spawning the subagent):**
Record the parent session's pre-existing uncommitted state: `git status --porcelain=v1 > <trailDir>/<slug>_BASELINE.txt`.
**The tree is ALWAYS dirty here** — the experiment must leave every one of these files untouched. Disposition (§3) is computed by diffing the post-run `git status --porcelain` against this baseline (**git truth**), using the subagent's touched-files list only as a **cross-check** — any post-run delta NOT in the subagent's list is **flagged to the user at the gate** ("experiment touched files it didn't report: …").
- **Default Rule:** Forbid modifying any file that is dirty at baseline. The experiment may add *new* files and edit files that were CLEAN at baseline — nothing else.
- **Exception:** Allow a baseline-dirty edit ONLY with an explicit backup first: `cp <path> <trailDir>/backup/<path>`, so revert restores from that copy. Never `git checkout` these files — it would clobber the parent's uncommitted work.

**Acknowledge:** Echo back in one line:
`Experimenting: <hypothesis> — proved-if <criterion> / disproved-if <criterion>; trail: <trailDir>/<slug>_EXPERIMENT.md.`

## 2. Run — Spawn the Experimenter Subagent

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

Spawn **one** subagent to execute the hands-on work. Use the `debugger` persona (it runs the scientific method natively) or `general-purpose` (for pure feasibility POCs). You hold the thread; the subagent does the work. Build its prompt to be entirely self-contained:

> You are a **scientist proving a hypothesis with undeniable, reproducible evidence**. Your job is to TRY it and report what happened. You do NOT fix, ship, or productionize anything.
>
> **1. The Mission**
> - **Hypothesis:** `<hypothesis>`
> - **Proved if:** `<criterion>` | **Disproved if:** `<criterion>`. Inconclusive is an allowed, honest outcome — and a clean **DISPROVED is a fully successful experiment**, as valuable as a proof. Do NOT massage a failure into "proved."
> - **Context — read first:** `<relevant files / session artifacts / the code area in question>`.
>
> **2. Rules of Engagement (The Sandbox)**
> - **Work in-tree, but UNCOMMITTED.** Write throwaway code wherever it takes to answer the question: a scratch script, a clearly-named throwaway/asserting test (e.g., `*.experiment.test.ts`), a REPL/CLI run, or a temporary edit to real source to observe behavior. Pick whatever vehicle fits the hypothesis — there is no required form.
> - **Observation-only edits, never the fix.** A temporary source edit is for OBSERVATION ONLY (logging, asserts, a throwaway edit to force a code path) — NOT the candidate fix. If your probe reveals the actual fix, that is a *finding to report* (describe it in the verdict / threads-left-open), not an edit to leave applied. Revert any observational source edit before reporting unless the disposition explicitly keeps it; **never present an applied fix as the experiment's result**.
> - **Respect the Baseline.** The tree is already dirty — the orchestrator captured a baseline. Prefer adding new files or editing files that were CLEAN at baseline. If the hypothesis genuinely needs to edit a file that is ALREADY dirty at baseline, back it up first (`cp <path> <trailDir>/backup/<path>`) and flag it in your report. Do NOT `git checkout` or otherwise disturb the parent's uncommitted work.
> - **NO shared/parent state mutation.** Do NOT run repo-wide git state commands (`git stash`, `git checkout .`, `git reset`, `git clean`, `git add`, `git commit`) — they hit the parent session's uncommitted work; only create/edit your own files. Do NOT run destructive or shared-resource commands: `db:reset`, `db:migrate`, drops/deletes against a shared dev DB, calls to real external/prod services, `rm -rf`. If the hypothesis genuinely needs one of these, STOP and report it as a blocker instead of running it.
> - **Track EVERY touched file.** You MUST list every file you create or modify in the report (the orchestrator offers a clean revert against a git baseline, so this list must be complete). For each modified file, flag whether it was clean or already dirty at baseline. Prefer additive/reversible edits.
>
> **3. Execution Strategy**
> - **Free scope, fast convergence:** Explore as many threads as the question genuinely needs (branch a sub-probe if a side-question blocks the main one), then converge to ONE verdict. Iterate your method if the first attempt is inconclusive.
> - **Hard probe-attempt cap:** Max ~3 attempts to get a working probe. If it still won't compile/run or stays inconclusive after that, report **INCONCLUSIVE (setup failure)** rather than opening new probes or spiraling.
> - **Escalate, don't fake:** If you cannot reproduce the setup, or the hypothesis is ill-posed, report inconclusive and explain why. Never manufacture a green result.
> - **Show, don't tell:** Do not paraphrase results. Paste the EXACT log lines, exact coordinates, exact token/row counts, and exact command output. A verdict a reader can't re-derive from the evidence you pasted is worthless — make yours bulletproof.
> - **Do NOT:** commit, open a PR, repair the underlying bug, build the feature for real, or file a ticket. A revealed fix is a *finding to report*, not work to do.
>
> **4. Output Contract**
> WRITE your report to `<trailDir>/<slug>_EXPERIMENT.md` using the Experiment template (this skill's `assets/TEMPLATE_EXPERIMENT.md` — path provided; do not hardcode `~/.claude`). Include: hypothesis, success criteria, environment/setup (branch@shortsha, fixtures/seed, versions if relevant), method (what you tried and why that vehicle), observations (exact commands/inputs → actual output — evidence, not claims) with a **repro command** (one exact line to re-run the decisive probe), **verdict** (proved / disproved / inconclusive) + **confidence** (high/medium/low), **scope of verdict / not tried**, a neutral "threads left open" pointer, and the complete **touched-files** list (Created / Modified-clean-at-baseline / Modified-dirty-at-baseline / Ran). Then return a 4–6 line summary + the report path.

> **Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + context-pack pointer + one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

Dispatch the subagent to the background by default (`run_in_background: true`) so you keep working while it runs and are notified when it lands; relay the summary then. Run it in the **foreground** only if you need its verdict before your next step.

## 3. Verdict & Disposition

1. **Relay the Verdict:** Present a short, numbered summary — Hypothesis → What was tried → Observed → **Verdict** + confidence. Surface the "threads left open" pointer.
   *Trust, but verify:* If the verdict hinges on a single probe and unblocks a major decision, consider re-running that exact repro command yourself to confirm the subagent's work before presenting it — especially a "proved" that unblocks a decision.

2. **Disposition Gate (MANDATORY `AskUserQuestion`):** The experiment left uncommitted code in the tree. Show the user the touched-files list and ask: **"How to dispose of the experiment code?"**
   - **Revert all:** Discard only the experiment's own files/edits.
   - **Keep for `/implement`:** Leave it in-tree, flagged, as a seed to graduate.
   - **Keep selectively:** Name which to keep, revert the rest.

**Executing the Disposition:**
*WARNING: You are operating in a dirty tree (`¶INV_NO_DESTRUCTIVE_GIT`). NEVER use `git clean`, `git checkout .`, `git stash`, or `git reset` — they destroy the parent session's uncommitted work. The per-path `git checkout -- <exact path>` self-reverts below are the sole sanctioned exception (your OWN clean-at-baseline files); the one-strike git hook will prompt on them — that deliberate per-path retry is legitimate here, but NEVER escalate to a repo-wide git command.*

- **If Reverting (All or Selective):** Operate ONLY on the experiment's own touched files, per exact path:
  - *New files created:* `rm <exact path>` (each path individually; never bare `git clean`).
  - *Files modified, CLEAN at the §1 baseline:* `git checkout -- <exact path>` (per exact path).
  - *Files modified, ALREADY dirty at the §1 baseline* (parent had uncommitted edits): do NOT `git checkout`; restore from the pre-experiment backup captured in §1 (`<trailDir>/backup/<path>`). If no backup exists, STOP and keep-flag that file rather than blanket-reverting.
  - *Files the experiment deleted:* `git checkout -- <exact path>` (restores from HEAD/index).
  - *Verification:* "Clean" means the experiment's OWN residue is gone and every parent-dirty file matches its §1 baseline — NOT that `git status` is empty. Verify by diffing post-run `git status --porcelain` against `<trailDir>/<slug>_BASELINE.txt`, not by eyeballing for emptiness.

- **If Keeping (All or Selective):** The kept code stays in-tree, flagged (see step 3). If a kept edit is fix-shaped (touches real source in a way that looks like a repair), label it an **UNVERIFIED SEED** in the stamped Disposition line and the `LESSONS.md` bullet — a hypothesis the experiment surfaced, NOT a proven fix. Revert everything not kept using the same per-exact-path recipe above.

3. **Report & Trail:**
   - Stamp the report's `Disposition` line (`reverted` / `kept` / `kept-selective`).
   - Link the report (`§CMD_LINK_FILE`).
   - **Flag kept code concretely** so `/implement`'s handoff knows exactly what the seed is: kept NEW files use an obvious `*.experiment.*` / scratch name; any kept EDIT to real source is recorded with its `file:line` in the stamped Disposition line AND the `LESSONS.md` bullet (an UNVERIFIED SEED per step 2 if fix-shaped), since an unflagged source edit is otherwise invisible to the next agent.
   - **Append to memory:** Append the durable outcome to `<trailDir>/LESSONS.md` as one terse bullet — the hypothesis and its verdict (e.g., *"CONFIRMED: flat detector drops continuation rows on >1-page rooms — repro in flat-detector-continuation.experiment.test.ts"*) — via `engine log`. The next `/build`/`/analyze` reads these, so a settled verdict shapes the next handoff instead of evaporating.

Then **stop**. `/experiment` reports and ends. What comes next (repair via `/fix`, build via `/implement`, capture via `/ticket`, deeper study via `/analyze`, or a shareable visual proof of the verdict via `/prove` — when the run produced **renderable evidence** worth showing a reviewer, e.g. a reproduction render, a before/after, captured output; `/prove` trusts the verdict and presents it, never re-runs it) is the user's call, not this skill's.

## Constraints
- **Building block — probes, never advances.** `/experiment` produces a verdict, not a fix. It must not repair the bug, build the feature for real, commit, or file a ticket. A revealed fix is a *finding*, not an action.
- **Hands-on, not read-only.** If the question can be answered by reading + reasoning alone, that's `/analyze`. Use `/experiment` when you must actually write/run something to observe behavior (running existing tests to observe behavior counts).
- **In-tree but never silently polluting.** The experiment writes uncommitted throwaway code in the real tree; every touched file is tracked and the run ends on a revert-or-keep gate. The working tree is either cleanly reverted or knowingly kept — **never left in an unknown state**.
- **Never a repo-wide git command (`¶INV_NO_DESTRUCTIVE_GIT`).** The tree is ALWAYS dirty here with the parent session's uncommitted work. Cleanup operates ONLY on the experiment's own touched files, per exact path (`rm <path>` / `git checkout -- <path>` / restore-from-backup) against the §1 baseline — NEVER `git clean`, `git checkout .`, `git stash`, `git reset`, or `git add -A`, which would destroy the parent's work. The one-strike hook enforces this: a per-path `git checkout -- <path>` of your own file is the narrow sanctioned exception (retry-to-confirm is fine); a repo-wide git command is not.
- **Honest verdicts.** Proved / disproved / **inconclusive** are all valid — and DISPROVED is a full success, not a failure. Never manufacture a green result; an ill-posed hypothesis reports inconclusive with the reason.
- **Lightweight.** Runs within the active session — frame → run → report, then stop. No debrief, no phases, no commit.
- **Subagent does the work.** The orchestrator frames the hypothesis and owns the disposition gate; one experimenter subagent runs it and reports.
