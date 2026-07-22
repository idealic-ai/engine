---
name: scrutinize
description: "Adversarially critique a body of work with a sub-agent, triage each finding with the user (fix / skip / defer), then apply the approved fixes inline or via a fixer sub-agent that knows the original goal + the critique + the resolution plan. Triggers: \"scrutinize this\", \"critique and fix\", \"adversarial review\", \"poke holes then fix\", \"review-triage-fix\"."
version: 1.0
tier: lightweight
args: "[scope: diff | commit <ref>|<a>..<b> | files <glob…> | session | pr <#> | build-report <path>] [-- <what you were trying to do>]"
---

Adversarially review a body of work, decide finding-by-finding with the user what to fix, then apply the approved fixes with full context. This skill is sessionless: it owns no session directory, phases, or debrief. It executes a strict pipeline: critique → triage → fix → stop.

This is distinct from a standard `/code-review`. It runs an interactive **per-finding triage round** and dispatches a **goal-aware fixer**. The fixer receives the original intent, the critique, and the user's resolution decisions. This guarantees fixes are made in service of what the work was *for*, rather than in isolated, context-free vacuums. As a **building block**, it sits between `/build` (which implements) and `/snapshot` (which verifies and commits) — hardening the work before it is checkpointed.

### Execution Mode: Engine vs. Standalone
Before proceeding, determine your environment. You are running under the workflow engine **if and only if `COMMANDS.md`** (the engine's core command standards, containing `§CMD_*` / `§INV_*` definitions) **is preloaded in your context** (the SessionStart hook injects it). This single check dictates every fallback below:
- **Engine Mode (`COMMANDS.md` present):** An active session exists. Use `engine log`, `<sessionDir>`, and set `<trailDir> = <sessionDir>/builds/`. The `§CMD_*` references (e.g., `§CMD_WALK_THROUGH_RESULTS`) resolve to their engine definitions.
- **Standalone Mode (`COMMANDS.md` absent):** You are assisting a teammate without the engine. No session exists. Use the global `/tmp` trail directory and plain file appends (defined in Step 1). Treat every `§CMD_*`/`§FMT_*` reference as plain-English guidance (e.g., the granularity gate and Fix/Skip/Defer tree are fully spelled out in §3).

# /scrutinize Protocol

## 1. Scope, Goal & Trail

Establish the foundational inputs. Do NOT skip this. A critique without a goal produces pedantic noise; a fix without a goal produces architectural drift.

**A. Resolve the Scope** (What work is under review)
Resolve from arguments, or infer and confirm with the user:
- `diff` (default): The uncommitted working-tree diff (`git status` + `git diff`).
- `commit <ref>` / `<a>..<b>`: That specific commit or range (`git show` / `git diff <a>..<b>`).
- `files <glob…>`: The explicitly named files.
- `session`: The work described in the active session's log and artifacts.
- `pr <#>`: The PR diff (via `gh pr diff <#>`).
- `build-report <path>`: A `/build` Build Report.

**Handling a `build-report` scope (The `/build` ↔ `/scrutinize` Coupling):**
If the scope is a build report, you must read the report AND its sibling Context Pack (`<same-dir>/<slug>_CONTEXT_PACK.md`, where `<slug>` is the report's slug — resolved in §1.C), plus the session `LESSONS.md` if present.
- **The Context Pack** carries *what was asked and why* (`goal`, `whys`, `constraints`, `likelyTraps`, `parityOracle`).
- **The Build Report** carries *what was done* (`approach`, `filesTouched`, `selfFlaggedRisks`, `assumptionsThatCouldBeWrong`, `parityEvidence`).

Use these directly:
1.  **Goal:** Seeded from the pack's `goal`.
2.  **Scope:** The report's `filesTouched` is the **authoritative review scope**. Review ONLY these files. Ignore everything else in the tree.
3.  **Leads:** The report's `selfFlaggedRisks` + `assumptionsThatCouldBeWrong` and the pack's `likelyTraps` become the critiquer's primary investigative leads.
4.  **Parity:** The pack's `parityOracle` + report's `parityEvidence` dictate exactly how to check behavior preservation.

*Fallback:* If the Context Pack is genuinely missing, do NOT block. Degrade gracefully: use the report alone, source the goal from the report's `goal` field + the `--` text, and explicitly note in chat that the pack was absent (meaning goal/whys/parity context is thinner).

If scope is ambiguous, run `git status --short` and present the candidates via `AskUserQuestion`.

**B. Resolve the Goal** (What the work was *trying* to do)
Take the goal from the text after `--`, or extract it from the active session's task summary / recent conversation.
*Constraint:* If you cannot state the goal in 1–3 clear sentences, you MUST ask the user before proceeding. Both the critiquer and the fixer depend on this.
*(Illustrative — adapt, don't copy: "Migrate the billing webhook parser to use the new Zod schemas without breaking the legacy Stripe event format.")*

**C. Resolve the Artifact Location (`<trailDir>`) & Slug.**
Determine this once and use it everywhere below so the trail clusters correctly:
- **From a `build-report`:** `<trailDir>` is the report's directory (session `builds/` or global `${TMPDIR:-/tmp}/finch-build-trail/<repo-basename>/`). `<slug>` is the report's slug (strip `_BUILD.md` from its filename).
- **Other scopes:**
  - *Engine Mode:* `<trailDir> = <sessionDir>/builds/`.
  - *Standalone Mode:* `<trailDir> = ${TMPDIR:-/tmp}/finch-build-trail/<repo-basename>/` (`mkdir -p`).
  - *Minting:* Mint `<slug> = <short-kebab-of-scope>` (e.g., `pr-1400`). *Crucial:* Before minting, `ls <trailDir>`. If an existing `<slug>_*.md` matches this work, REUSE that slug to cluster the trail.

**Acknowledge:** Echo back your setup in exactly one line:
`Scrutinizing <scope> — goal: <goal>; trail: <trailDir>/<slug>_CRITIQUE.md.`

## 2. Critique — Spawn the Critiquer

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

**Use the wait — don't idle.** When you background the critiquer, spend that time getting a step ahead so the moment findings land you move straight into action rather than starting cold. Concretely, while it runs: (a) **anticipate the triage** — from the goal + the leads (self-flagged risks, likely traps), predict the probable findings and pre-think a fix direction for each; (b) **surface open questions to the user now** (`AskUserQuestion`) — anything about scope, intent, acceptable trade-offs, or which classes of finding they'd fix vs skip — so their answers are in hand when triage starts; (c) **prep the next move** — line up the fix approach, the branch/checkpoint plan, or the follow-up work that likely comes after. Don't block waiting; the completion notification will bring you back to §3 with momentum.

Spawn **one** `critiquer` sub-agent — **prefer the background** (`run_in_background: true`) so you keep working while it runs and are notified when it lands; run it in the **foreground** only if you need its findings before your next step. Give it a strong, adversarial, self-contained prompt built exactly from this template:

> You are a **hostile, forensic auditor** hunting for the severe regression the builder is hiding. You are NOT a polite reviewer summarizing a diff. Assume the code is broken until you have tried to break it and failed.
>
> **Your Mandate:**
> Find REAL problems: correctness bugs, behavior/regression risks, unhandled edge cases, fragile heuristics, test gaps, security issues, and over-engineering. Do NOT rubber-stamp. If prior work claimed "all green," treat that as a claim to be DISPROVEN. Verify it independently.
>
> **The "Failing Scenario" Rule:**
> For EVERY finding, you MUST supply a concrete, step-by-step **Failing Scenario** that proves the defect. A theoretical "this could be risky" with no scenario is not a finding. If you cannot construct a failing scenario, downgrade the finding to a LOW/nit and state why.
>
> **Context:**
> - **Goal (Intent):** `<GOAL>`
> - **Scope (Target):** `<SCOPE>` — Exact pointers: `<CONCRETE POINTERS: git diff cmd, file list, PR#>`. Review ONLY these. Ignore unrelated working tree changes.
> - **Deliberate Decisions (Do not flag):** `<whys + carriedForwardLessons>`. These were chosen on purpose.
> - **Background:** `<any design docs, session log, related modules>`.
> - **Primary Leads (Verify/Refute):** `<selfFlaggedRisks + assumptionsThatCouldBeWrong + likelyTraps>`.
>
> **Execution:**
> - **Behavior-Preservation:** If applicable, use oracle `<parityOracle>` and evidence `<parityEvidence>`. Confirm the oracle is green AND unmodified (a fixer editing the oracle to pass is a red flag). Try to construct an input where old vs. new output diverges.
> - **Verify, Don't Trust:** You MAY run builds/tests/linters/type-checkers and execute code on fixtures. State exactly what you ran.
> - **Reproduce with a failing test (STRONG DEFAULT):** For any finding a test CAN demonstrate, WRITE a throwaway test that FAILS on the current code (proving the bug RED) and run it — a described scenario is weaker than a red test the fixer can run. This hands the fixer a red→green target so the reproduction is never re-derived. Then, for each repro: **save it to `<trailDir>/<slug>_repro/`** — the test file's content (e.g. `<slug>_repro/finding-<n>.test.ts`), the EXACT run command, and the observed failure output — and **REVERT the in-tree test file so the working tree stays clean** (mirror `/experiment`'s discipline: `rm` a new file [strongly preferred — repro tests are new files you wrote] / `git checkout -- <path>` a modified one, per exact path; NEVER touch the parent's uncommitted work or run repo-wide git commands — see `¶INV_NO_DESTRUCTIVE_GIT`. The one-strike git hook blocks `git checkout -- <path>`; that per-path revert of YOUR OWN throwaway file is the sole sanctioned exception, but NEVER escalate to a repo-wide `git checkout`/`stash`/`reset`/`clean`). Reference the saved repro path + command in that finding's Failing Scenario. Only fall back to a described-only Failing Scenario when a test is genuinely infeasible (integration/live-service/env-only) — and say why.
>
> **Deliverables:**
> 1. **Severity-Ranked Findings:** CRITICAL (correctness/security) → HIGH (regression/edge-case) → MEDIUM (test-gap/quality) → LOW (nit).
>    *Format per finding:* Short title, `file:line`, why it's wrong, **Failing Scenario** (required — prefer a saved **repro test** in `<trailDir>/<slug>_repro/` + its exact run command + the RED failure line; else a described scenario with why-no-test), one-line **root cause**, and suggested fix.
> 2. **Audit Blind Spots:** What you could NOT verify (files/states/integrations outside your context). A green review with unstated blind spots is dishonest.
> 3. **Reusable Facts Discovered:** Hard architectural truths learned (e.g., "the reconciliation join key is the scope nanoid end-to-end").
>
> **Closing:** End with a one-line **verdict** + **the top 3 things to fix**. Be specific; **if it's genuinely solid, say so**.
>
> **Return Contract (CRITICAL):**
> - **WRITE** your full severity-ranked findings to `<trailDir>/<slug>_CRITIQUE.md` yourself, following `assets/TEMPLATE_CRITIQUE.md` (the orchestrator gives you its base dir; **do not hardcode `~/.claude`**).
> - **RETURN** to the orchestrator ONLY a compact ranked summary: finding numbers + a one-line essence each (highest-severity first) + the final verdict. Do NOT dump the full findings into your return message. The orchestrator will read the file.

**Relay the Summary:**
Once the critiquer returns, relay its **returned ranked summary** to the user as a **numbered, severity-ordered list**. The user will triage by these numbers.
*Crucial:* The full findings already live in `<trailDir>/<slug>_CRITIQUE.md` (written by the critiquer). Relay the summary directly; do NOT re-read the file and transcribe it. Keep it to a title + one-line essence in chat.

## 3. Triage — Walk the Findings with the User

The interactive **`AskUserQuestion` walkthrough is the core of `/scrutinize`**. The user, not the model, decides fix/skip/defer per finding. Run it explicitly. NEVER dump findings as bare text and assume the user's intent.

**Disclose findings as Decision Cards before you triage (`§CMD_ELICIT` — disclosure only).** Findings carry the fields the user reliably asks for next — the trade-off of the fix, what's at stake, the complexity it adds, how to verify it cheaply — so front-load them per `¶INV_DISCLOSE_AND_TRIAGE`. If under the engine, this is `§CMD_WALK_THROUGH_RESULTS` (results mode), which uses `§CMD_ELICIT` to render **cards-then-summary** before the triage. If standalone, render the same disclosure directly: a `§FMT_DECISION_CARD` per finding (depth scaling with the severity×complexity triage — `Your-call`s get the full card, clean-and-clear lows collapse to one-liners), then the compact triaged summary, THEN the per-finding `AskUserQuestion` below. `§CMD_ELICIT` **only discloses and classifies attention** — its `I've-got-this` verdict is *advisory* (a "this one's clear-cut" recommendation), **never an auto-fix**. **The user still decides fix/skip/defer per finding** (scrutinize's core invariant — the user, not the model, decides). Do NOT use the `§CMD_TAG_TRIAGE` default; use the specific review decision set below.

**The Walkthrough Routine:**

1. **Granularity Gate (1x `AskUserQuestion`):**
   Ask: "How do you want to walk the N findings?" (`§ASK_WALKTHROUGH_GRANULARITY`).
   Options (Single-select):
   - **Each:** One at a time.
   - **Groups:** Batches of 4.
   - **Smart:** ≤4 → Each, 5–12 → Groups.
   - **Top-N:** By severity (e.g., just CRITICAL+HIGH).
   - **None:** Accept the critiquer's verdict as-is.

2. **Per-Finding Evaluation (Decision Card + `AskUserQuestion`):**
   For each finding (or batch), present its `§FMT_DECISION_CARD` in chat (from the disclosure pass above — full card for a `Your-call`, one-liner where the triage collapsed it). At minimum the card carries:
   *   `Options + my lean:` framed trade-offs (incl. the honest do-nothing), with the fix POV stated *after* the options as the defeasible lean (anti-anchor).
   *   `What's at stake / severity:` `[#]: <title> — <file:line>, <severity>` — `<the defect> | <concrete failing scenario>`.
   *   `Trade-off · Complexity · How to verify · Confidence:` the fields the user would otherwise interrogate for.
   *(Illustrative — adapt, don't copy: `[1]: Null pointer in parser — src/parse.ts:42, CRITICAL`. Options: add `user?.id` chaining → risk none, or validate upstream → risk broader refactor. My lean: the chain, but it hides a malformed payload. How to verify: the saved repro test goes RED. Confidence: high.)*

   Then, call `AskUserQuestion` with the finding number as the header and this option tree:
   - **Fix:** Include in the resolution plan.
   - **Skip:** Acknowledged, no action (record the user's reason if provided).
   - **Defer:** Out of scope now (offer to tag/track if the project uses tags).
   - **Discuss:** Needs more detail/disagreement. Answer in chat, then re-present this finding.

3. **Batch Shortcuts:**
   Honor natural language shortcuts immediately without further questions (e.g., "fix all", "skip the LOWs", "defer the rest", "fix the CRITICALs only"). Apply these to all remaining findings.

**Assemble the Resolution Plan:**
Let the user override severities—the critiquer advises, the user decides. After the walkthrough, assemble the **resolution plan**: a list of findings marked *Fix*, including the critiquer's suggested fix plus any user amendments. If nothing is marked *Fix*, report that and stop.

## 4. Fix — Inline or Fixer Sub-Agent

Ask the user via `AskUserQuestion` how to apply the approved fixes:
- **Fixer sub-agent (default):** Dispatches one `builder`/`debugger` sub-agent with full context. Preserves the main-thread context window.
- **Inline:** Apply the fixes directly in this thread.

Either way, the fixer must receive the **complete picture**. Build its prompt from this template:

> **Task:** Apply a set of approved fixes to work whose original goal was: `<GOAL>`.
> **Scope:** The work under review is `<SCOPE + concrete pointers>`.
>
> **The Resolution Plan (Apply these):**
> A reviewer found issues; the user approved these specific fixes:
> `<PER-FINDING: title, file:line, the defect, the agreed fix + any user amendment>`
>
> **Off-Limits (Do NOT touch):**
> The user chose to SKIP/DEFER these findings: `<list>`.
>
> **Constraints:**
> - Make ONLY the approved changes.
> - Preserve the original goal and all existing behavior not explicitly called out.
> - Do NOT opportunistically refactor.
> - **Secondary breakage from your own change is in-scope to repair:** you MAY fix breakage that YOUR OWN approved change introduced (e.g. a type error, failing test, or broken import caused by an edit in the resolution plan) — as long as the repair does NOT touch the goal, a skipped/deferred finding, or unrelated behavior. Beyond that boundary it is an escalation, not a silent fix.
> - **Reuse the saved repro — DON'T re-derive:** for any finding with a repro test in `<trailDir>/<slug>_repro/`, re-create that test in-project from the saved content, run it to confirm it's RED (reproduces the bug), apply the fix, then run it again to confirm GREEN. That red→green IS your verification for that finding — do not reinvent the reproduction. A repro that won't go RED before your fix means the finding or the repro is wrong: STOP and report.
> - **Verify:** After applying, also run the relevant tests + type-check/build/lint and report exact results.
> - **Git Safety (`¶INV_NO_DESTRUCTIVE_GIT`):** the tree is ALWAYS dirty with parallel-agent work. Edit files directly; NEVER run tree/index-destructive git — no `git stash`/`checkout`/`switch`/`restore`/`reset --hard`/`clean`/`rm`, no `git checkout -- <path>`, and no `git add -A`/`-u`/`.` to "reset" state. Read baselines with `git show HEAD:<path>`. Do NOT commit (that is `/snapshot`'s job). A hook blocks these; if blocked, STOP and report rather than bypassing.
> - **Escalate:** If an approved fix conflicts with the goal, **conflicts with another finding**, or changes unrelated behavior, STOP and report. Do not guess.
>
> **Persist the Outcome:**
> WRITE `<trailDir>/<slug>_FIX.md` (per-finding what-changed `file:line` + edit made + verification result: **exact gate commands → results**). This is the fix's paper trail, distinct from the critique.

For a **sub-agent**, dispatch it to the background by default (foreground only if you need its fix report before proceeding) and relay its report when it lands. For **inline**, apply each approved fix, run the verification, and write the `<slug>_FIX.md` file yourself.

**Promote or discard the repros.** After a fix verifies GREEN against its repro, ask the user (`AskUserQuestion`) whether to **keep** that repro as a permanent regression test (move it from `<trailDir>/<slug>_repro/` into the project's test suite at an appropriate path) or **discard** it (it stays in the trail for the record only). Default suggestion: **keep** — a red→green repro is a high-value regression test that pins the bug from recurring. Batch the decision across findings.

## 5. Report & Paper Trail

Summarize in chat: findings raised (by severity), decisions made, files changed, and the verification result. Surface any fixer escalations verbatim. Do NOT commit unless asked (committing is `/snapshot`'s job).

**Appending to the Trail:**
The `<trailDir>/<slug>_CRITIQUE.md` (resolved in §1.C, initially written by the critiquer) is NOT re-resolved here. The orchestrator does NOT create it; instead it **APPENDS** to it across the run:
1. The per-finding triage decision + reason.
2. The fixer outcome + gate result for each.

Appending ensures a killed/resumed run doesn't lose history. Link the files in chat (`§CMD_LINK_FILE`) — including any `<trailDir>/<slug>_repro/` reproduction tests the critiquer saved (each finding's red proof + run command). *(Truly standalone with no writable trail: stay chat-only.)*

**Feed the Ledger (Compounding Loop):**
Append the durable outcomes of this review to `<trailDir>/LESSONS.md`. Capture confirmed facts and resolved design decisions as terse bullets.
*(Illustrative — adapt, don't copy: "Type is prefix-authoritative — rule X removed as inert.")*
Use `engine log` under a session, else a plain file append (`printf '## …\n…\n' >> <trailDir>/LESSONS.md`). The next `/build` reads these, ensuring conclusions shape the next handoff instead of evaporating.

## Constraints
- **Mandatory Inputs:** Never run the critiquer without a stated goal + concrete scope.
- **User Ownership:** Severity is advice; fix/skip/defer is the user's call via `AskUserQuestion`.
- **Scoped Fixes:** The fixer touches only approved findings and must re-run the gate. Skipped/deferred findings are strictly off-limits. It MAY repair secondary breakage its own approved change introduced, provided the repair does not touch the goal, a skipped/deferred finding, or unrelated behavior.
- **Sessionless & Engine-Optional:** `/scrutinize` manages no session. It writes to `<trailDir>` but works entirely via Task/AskUserQuestion/Skill mechanics. If tracking is needed, suggest a session skill.
- **No Silent Changes:** A fixer that must alter the goal, another finding, or unrelated behavior to implement a fix must escalate instead of deciding silently.
- **Reproduce over assert:** where a test can demonstrate a finding, the critiquer writes a RED repro test (saved to `<trailDir>/<slug>_repro/`, in-tree file reverted) so the fixer runs red→green instead of re-deriving the bug; worthy repros are promoted to permanent regression tests at the user's choice. A described-only Failing Scenario is the fallback for genuinely test-infeasible findings.
