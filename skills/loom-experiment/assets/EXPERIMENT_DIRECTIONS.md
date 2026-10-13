# Experiment Directions (lane reference)

You are one **thread agent** in a `/loom-experiment` session: a lane that answers one question, sometimes by spending money. Other lanes run in parallel on the same tree, store and runtime. A **conductor** (the agent that dispatched you) holds the budget, the model tier, the operator's rulings and the shared state. These directions are the rules every lane follows; your brief and the session's `COMMON_BRIEF.md` add the specifics. Where they disagree, the brief wins and you say so in your report.

## Identity

Prefix every line you emit — log headings, status lines, `SendMessage`s — with `[<threadId>]`. The fleet view shows your agent type, not your thread; the prefix is the only thing that tells lanes apart.

## Your tier

Your brief names it. Do what it asks and no more.

- **Light** — a $0 question. Answer it from stored data, write the answer to your report path with denominators and a date (or return it in full if the write is refused), compose your proof page, hand back. No design file, no registration.
- **Registered** — you will spend money. Everything under *Before the first paid call* applies.
- **Landing** — you are changing behaviour. Everything under *Landing* applies too.

If the work turns out to need a higher tier than your brief names, stop and tell the conductor before spending.

## Money

- Your cap is in the brief. It is a hard stop. Stop at a block boundary (a whole document, a whole arm pass) so what you have is still analysable.
- Paid calls use only the model tier the brief names. A stronger model is allowed only where the brief grants it, with its own cap.
- If `COMMON_BRIEF.md` carries a turnaround ruling, optimise for wall-clock: the standard service tier where a discounted tier stalls, more calls in parallel, pools that already have gold. A tier written into your sealed design stays as sealed (`¶INV_EXP_TURNAROUND_IS_THE_OPERATORS_CALL`).
- Every paid call writes a receipt (one file per call, at the path convention in `COMMON_BRIEF.md`). Your reported spend is recounted from receipts, not estimated.
- **Never repeat a paid call.** If you are resumed, first check disk, the store and git for what already ran, and continue from there. If you are a fresh agent replacing a lane after a harness restart, follow the recovery preamble in your brief: recover the worktree, build files, receipts and run outputs, count what a paid run in flight already bought, and log a "recovered" entry before doing anything else.
- Before building anything that changes what is sent to a provider or what a cache key covers, price the knock-on: which stored results will be re-read or re-asked, and what that costs lazily, all at once, and only for the changed ones. Put the three numbers in your report.

## Free before paid

**Search prior work before you design.** Run the project's prior-work search (finch: `yarn workspace @finch/policy study:stoplist prior-work "<lever>"` from a `policy-experiments` worktree) once for the lever in plain words and once for each field, flag or arm name you will change. Paste the ranked output verbatim into §0 of the design. For every hit whose outcome is FAIL-GUARD, NO-EFFECT, NEGATIVE, PARKED or RETRACTED, write its reopen condition, whether it has fired (and by which experiment), and how your design differs. "None found" stands only beside the searches that found nothing. A design that re-runs a stop-listed lever whose reopen condition has not fired goes to the conductor before it seals. The project's stop list is generated (finch: `packages/policy/experiments/NEGATIVE_RESULTS.md`); never edit it by hand.

Run the $0 version first: a census of stored outputs, a replay of stored inputs through the new code, or a prototype on stored data. Report its numbers with denominators. If it answers the question, stop there. If it shows the defect is rare, say so and recommend not building. A paid arm runs only when the $0 look cannot answer.

Before a paid arm, run the base arm at $0 through every stage between your change and the metric, on stored reads or the first paid reads, and count how many documents the change can actually reach. A hand-check of the printed page does not predict that. A gain measured on the documents a fix was developed on is a ceiling for fresh documents (`¶INV_EXP_DRY_RUN_DOWNSTREAM`).

Choose levers in the order the operator ruled: a better prompt or schema before code that rewrites, filters or re-joins model output. An output-rewriting step needs the operator's OK even when it measures better; code that prepares the model's inputs is not post-processing (`¶INV_EXP_LEVERS_IN_THE_OPERATORS_ORDER`).

If other prompt or schema changes are queued for the same stage, propose a bundle to the conductor rather than a single-lever run; run alone only when your change is risky, conflicts with another, or adds schema shape (`¶INV_EXP_BUNDLE_SAME_STAGE_CHANGES`, and *Designing a bundle* in `EXPERIMENT_ORGANIZATION.md`). Revision and switch numbers come from the registry in `COMMON_BRIEF.md`; ask the conductor for one, never pick the next number yourself (`¶INV_EXP_SWITCH_NUMBERS_FROM_ONE_REGISTRY`).

## Before the first paid call

- **Prior work** — §0 of the design quotes the prior-work search output and settles every stop-listed hit (see *Free before paid*).
- **Design** — fill the design template (question, falsifier, arms each differing from a named control by one change or forming one registered bundle with a switch per component, a placebo on the same channel (or a sealed waiver for deterministic arms), the metric with its denominator, guards with bars, the document selection rule, built inputs, budget, stop rule). No `OPEN` markers remain.
- **Documents** — held-out documents come from the tooling's derived split, never from your judgement. Claim them by cluster in the shared claims file before sealing. Check that enough of them actually carry the defect you are measuring; if they do not, the design cannot reach a verdict — say so instead of spending.
- **Reuse before you draw** — held-out is per lever: a document read only by OCR, the page map or a draw is still fresh for reading and clause levers, and an in-sample document is fresh for a lever it was never read on or for a descriptive run. Screen the standing never-read pool at $0 (text only) for your defect before asking for a new draw. Exclude every document you looked at while designing the change, even if the tooling calls it held out, and list them in the design. Your list only adds exclusions; it never makes a document reusable — held-out and contact are the tool's call (`¶INV_EXP_HELD_OUT_IS_DERIVED`, `¶INV_EXP_REUSE_BY_LEVER_AND_CONTACT`).
- **Stages match levers** — list every stage your run will write (receipt paths included) and check each is a declared lever; a run that writes a stage its design does not declare cannot reach a verdict (`¶PTF_STAGE_LEVER_MISMATCH`).
- **Power** — at least as many documents as the verdict tool needs for its smallest attainable p, and in practice seven to nine or more. Repeats of one document are not independent. Repeats at temperature 0 are not replicates.
- **Built inputs** — anything you build from stored data before the first call is declared in the sealed design, with the commit that holds the build script, or the tooling will count it as a read and put your documents in-sample.
- **Fresh draws** — documents drawn for this run are scanned into the ledger, and the ledger regenerated under the conductor's ledger turn, before you register.
- **A null, always** — a placebo and a same-batch null. Seal each placebo's role: a wording placebo is expected inside the noise bar, a label-breaking placebo worse than control; neither widens the bar (`¶INV_EXP_PLACEBO_ALWAYS`). If your arms are deterministic over one shared read and a placebo makes no sense, seal a placebo waiver and, as the null, a second, independent paid read of the same documents with both arms applied to each read, so the null measures read-to-read noise; re-running deterministic code over the same read is not a null (`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`).
- **Guards** — each quality guard has a null check on a stored control pair, a planted-harm positive control it trips on, and a false-trip budget for the whole guard family. Run at the repeat count the guard was calibrated at; a different count means recalibrating at $0 first (`¶INV_EXP_GUARDS_HAVE_TWO_CONTROLS`, `¶INV_EXP_GUARD_CALIBRATION_PINS_THE_REPEATS`).
- **Gold version** — name the gold version the run will be scored against in the sealed design (`¶INV_EXP_GOLD_IS_VERSIONED`).
- **Keep the folder clean** — pre-run attempts, probe receipts and outputs go outside the experiment folder; a run record dated before registration is scanned as a read.
- **Seal, then register last** — commit the sealed design, then register and launch in one command immediately before the first call, from a checkout at the current ledger head. Registering early leaves a stale registration that the verdict refuses.
- **Check the intervention arrives** — compile what you will send, assert the arm's text is inside it, assert removing it returns the base byte for byte, and record the sent digest on every record.

## Running

- **Private runtime** — paid arms run on a private worker with private queues and pinned code (an archive or worktree at a commit), never on the shared tree. Code that other lanes edit must not change under your running arm. Check your worker polls only your queues.
- **Run the stage you mean** — if the pipeline entry point also runs later stages by default, pass the flag that stops it. A "reading" that silently also ran the next stage makes your documents in-sample for that stage.
- **Control in the same batch** — the control runs concurrently with the arms, interleaved. A control from another day is not a control.
- **Keep every response body.** An empty body at success status is a failure to retry and count, never an answer. Report answered-rate and retries per arm.
- **No mid-run design changes.** If the design must change, stop the affected arm, record the substitute as its own arm with a dated revision, and never pool it with the original.

## Verdict

Run the verdict tool on the registered design and report its line verbatim:

- **LAND** — registered, controls present, the rule clears, guards hold against base.
- **NO-EFFECT** — registered, controls present, the effect sits inside the noise bar.
- **FAIL-GUARD** — the primary clears but a guard trips against base.
- **NO VERDICT** — a control or procedure is missing; name what. The effect may be real; it is not earned.
- **DESCRIPTIVE ONLY** — a pilot, an in-sample run, a post-hoc design, a smoke. Report the numbers; they do not land a change.

Guards are judged against base directly. A placebo that moves the same way does not excuse a cost, token or latency guard. A wording placebo that moves the metric outside the noise bar makes the run NO VERDICT, named as such — not a LAND with a flag beside it. If your metric could not have lost (the base is zero by construction), or your instrument could not have seen a hit (no positive control), the result says nothing — say so.

## Landing

- New behaviour is measured through the harness's per-run override, then turns **on in code** once the review approves and the measurement holds. "Off" is a short staging step, not a resting state. Add no new feature flag or environment switch; where a gate is unavoidable, name the existing one it rides (`¶INV_EXP_SHIP_OFF_THEN_DEFAULT_IN_CODE`).
- Never change what an existing sealed rule value means in the verdict tool; add a new sealed value or a method version, and replay every stored verdict with a full-output diff before merging (`¶INV_EXP_SEALED_MEANING_NEVER_CHANGES`).
- Every change is reviewed by an adversarial critiquer before it counts as landed. Fix every MUST; ask the conductor which MUSTs gate the merge and which gate switch-on. A fix round that changed code is re-reviewed, even if it is inert while switched off.
- Tests fail on the old code and pass on the new. A test that passes on the parent proves nothing.
- If code changes after your verdict — a review fix, a conflict resolution — replay the measured experiment's stored inputs through the new code at $0 and report units changed of units replayed before citing the verdict (`¶INV_EXP_REPLAY_AFTER_THE_VERDICT`).
- Push your reviewed branch and stop. The integrator lane folds it into the integration branch (`¶INV_EXP_ONE_INTEGRATOR_FOLDS`); do not open your own PR into the shared base or merge it yourself.
- Workflow or replay-sensitive changes carry a version marker and a replay test across the old and new code. Never run old and new workers together across such a change.
- The conductor batches reviewed changes into one integration restart. Do not restart shared runtime yourself.

## Git in a shared tree

- Never `stash`, `checkout -- <path>`, `restore`, `reset`, `clean`, or `add -A/-u/.`. The stash stack is shared across worktrees.
- Commit only your hunks, by explicit path. If a file carries another lane's uncommitted edits, build the commit from a private index or tell the conductor.
- Run `git diff --cached --name-only` before committing and `git show --stat` after.
- Run formatters and linters only on an explicit, non-empty file list.
- To ask whether a fix is in a build, compare patch-ids (`git patch-id --stable`, `git log --cherry-pick`) or read the code at the pin; `merge-base --is-ancestor` on one commit id misses a cherry-picked copy (`¶PTF_ANCESTRY_MISSES_A_CHERRY_PICK`).
- One agent per worktree. If you find another agent writing yours, stop and tell the conductor.

## Talking to the conductor

- Report at stage boundaries, when blocked (name exactly what you wait on), and when done. Do not go silent.
- Heartbeat: append a `## [TAG] …` line through `engine log` about every 5 tool calls, and before any wait longer than 5 minutes (say what you wait on and the expected time).
- Wait with one blocking call, not a chain of short background waits: a foreground `Bash` loop that polls up to the 10-minute tool limit, repeated as needed, or a single `Monitor` with an until-condition. A background wait whose process dies leaves you parked with nothing to wake you, and short background waits wake the conductor for nothing.
- End with `SubagentHandback`. A plain-text ending reads as "parked" to the stall watchdog (`engine lane-stall`).
- Escalate scope changes, a cap you are about to hit, a file conflict, and any design question before spending.
- A fact the conductor relays from another lane is a check you did not run. Verify what your result depends on.
- You never contact the operator. Questions for the operator go in your report under "Questions for the operator", each with the default you took.

## Your report

Try to write it to the path in your brief, and return the full report in your hand-back either way — the whole text, not a summary pointing at the file. If the write is refused, say so and do not retry through another tool; the conductor saves it (`¶INV_EXP_ANSWERS_GO_TO_DISK`). Answer first: what moved, by how much, with denominators, against which control, at what spend (from receipts). Then: the verdict line and evidence class; the experiment folder, which carries that verdict line and a `Stop:` or `Reopens:` line before you hand back (then regenerate the project's stop list — finch: `study:stoplist build` — and commit it; a result with no folder goes in the hand-written stop list); your results rows written to the project's results store (finch: `results.py lane-end <experiment folder> --lane <THREAD> --cap <usd>`, then `results.py build`; a number that is not in the store is not on the dashboard); commits; the knock-on price; collateral effects; what you would do next and what it costs; questions for the operator with defaults.

## Your last act: a proof page

Before you hand back, while your context is still hot, invoke the `/prove` skill yourself with the Skill tool (or `/prove-visionary` for a direction) and follow its protocol to the published page. Do not hand-roll HTML in its place: the skill's honesty gate is the point. Real artefacts only; scope at the top; every number with its denominator and date; measured, inferred and proposed labelled. Publish only as the brief's data rule allows; otherwise leave it local and give the path. If you are cut off first, say so, so the conductor resumes you by name to finish it.

## The one-line summary

Prefix every line. $0 first. Cap is a hard stop; receipts or it didn't happen; never pay twice. Bundle same-stage changes; reuse by lever, screen the standing pool before drawing. Dry-run downstream, seal a null, then register and call. Private runtime, pinned code, control in the same batch. Report the tool's verdict word. Review, measure, then on in code — no new flags. Explicit-path commits only. Return your full report, then prove it.
