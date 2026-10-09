# /loom-experiment invariants

For the conductor and lanes. Evergreen rules; the measured reasons are dated evidence from the run that produced this skill (a multi-day experiment loom on a document-parsing LLM pipeline). Each rule says what to do, what to do instead of the tempting shortcut, and why.

## Stakes

*   **¶INV_EXP_RIGOR_SCALES_WITH_STAKES**: A thread's tier decides its ceremony.
    *   **Rule**: Light ($0 question) is answered and written down. Registered (money spent) is designed, sealed, registered and verdicted. Landing (behaviour changes) adds review, knock-on pricing and a staged switch-on.
    *   **Redirection**: do not pre-register a census; do not land a change on a census.
    *   **Reason, measured**: many of the most useful answers were $0 — a census of 456,902 facts, a replay of stored inputs, a count of oversized inputs — and each settled a build decision in minutes. The expensive failures were the reverse: paid runs without the controls that would let them count.

## Money

*   **¶INV_EXP_BUDGET_IS_A_LEDGER**: The session has a ceiling, each lane a cap, and spend is recounted from receipts.
    *   **Rule**: Keep committed caps beside receipts-counted spend in the ledger. Refuse a paid thread that would breach the ceiling. Hold a reserve.
    *   **Redirection**: when a figure is "≈", recount it from receipts before quoting it.
    *   **Reason, measured**: the ledger's own spend line read "rough; recount from lane reports" for a day; one lane's figure moved from $24.8 to $27.0 on recount. The operator raised the ceiling several times in steps, and each step was spread across named lanes with caps.

*   **¶INV_EXP_MODEL_TIER_IS_THE_OPERATORS**: Which models paid calls may use is the operator's decision.
    *   **Rule**: Put the tier in every brief. A stronger model runs only as a capped tie-break judge under a standing permission the operator gave.
    *   **Redirection**: when a stronger model looks necessary, ask with the price.
    *   **Reason, measured**: "only flash models" was ruled while the operator slept and went into every brief; later "Pro judge: standing for tie-breaks, capped" at $5 per lane. A council's stop list named "Pro without approval".

*   **¶INV_EXP_FREE_BEFORE_PAID**: A $0 look runs before any paid arm; a pilot before a confirmation; a measurement before a fix.
    *   **Rule**: Census, replay or prototype over stored data first. If it answers, stop.
    *   **Redirection**: when a fix feels obvious, count the failure first.
    *   **Reason, measured**: a proposed code stamp for model-written page numbers was costed at up to $600 to do the schema way; a $0 census found 0 wrong pages in 456,902 facts, and it became a report-only check. A cache idea's paid step was never run because its $0 gate was not met.

*   **¶INV_EXP_PRICE_THE_KNOCK_ON**: Before building, price what landing will re-read or re-ask.
    *   **Rule**: Any change to sent prompt or schema bytes re-reads stored inputs; any change to a cache identity or rule version re-asks stored results. Price three ways: lazy (on each item's next natural run), re-derive all now, only the changed ones.
    *   **Redirection**: never write "$0 re-derive" without checking which stored results carry the stamp that allows it.
    *   **Reason, measured**: a wording edit in a comment turned out to be sent to the model and moved the sent digest, which would have re-read every stored page; it was restored byte for byte. A rule-version bump claimed "$0" would re-ask about $15 of stored reconciliations. An amount fix was priced at $0 lazy, $5.80 for all 74 re-asks, $2.67 for the 25 changed.

*   **¶INV_EXP_DRY_RUN_DOWNSTREAM**: Before a paid arm, the base arm runs at $0 through every stage between the change and the metric, on the chosen documents or the first reads.
    *   **Rule**: Predict how many documents will move from what the downstream stages actually reach, not from the printed page. A stop rule keyed to the prediction ("stop if fewer than N movers") uses the dry run's count. An in-sample gain is a ceiling for fresh documents, not an estimate.
    *   **Redirection**: when a hand-check says "the defect is on the page", run the stored or first reads through the rest of the pipeline before paying.
    *   **Reason, measured**: a hand-check predicted about ten movers of twelve and passed its "fewer than six" stop; the paid run moved 0 of 12, because 387 of 406 scenarios were blocked upstream of the stage the fix changed. The same fix had moved 306 → 763 on the documents it was developed on. $13.14 bought a null that a $0 dry run over the first reads would have shown.

*   **¶INV_EXP_NEVER_PAY_TWICE**: Resumed work continues from disk; it never repeats a paid call.
    *   **Rule**: Every resume message says "check disk, store and git; don't repeat paid calls"; a fresh agent replacing a lane after a harness restart gets the recovery preamble (`¶INV_EXP_RESUME_BY_ID`). Receipts make repeats visible.
    *   **Reason, measured**: usage limits, account holds and terms prompts stopped every lane at once several times; each was resumed by id with that sentence and no paid call was repeated.

## Measurement integrity

*   **¶INV_EXP_REGISTER_BEFORE_THE_FIRST_CALL**: A paid arm's design, arm files, guards and document selection are sealed, and the run is registered in the store, before its first call.
    *   **Rule**: Seal, commit, then register and launch in one command. A design changed after the first call is a new test with new calls.
    *   **Redirection**: do not register early "to be safe"; register as the final step.
    *   **Reason, measured**: a winning arm was re-printed as NO VERDICT under the final rules because its arm files were not sealed before its screen and the run was never registered. Another registered 15.8 minutes before its first read and got NO VERDICT after $19.49.

*   **¶INV_EXP_CORPUS_IS_PINNED**: The held-out split is judged on the corpus as it stood at the first call, and the pin cannot be forged or backdated.
    *   **Rule**: The registration records the ledger commit in force; the verdict refuses a pin older than that or unparseable times.
    *   **Reason, measured**: reviews found a first-call time that could be moved a day to flip about 250 documents into the pool, and an older corpus pin that the tool accepted. A late-arriving batch of documents bridged two held-out documents into an in-sample cluster after a run had started.

*   **¶INV_EXP_HELD_OUT_IS_DERIVED**: Tooling decides which documents are held out, from a touch ledger and a committed cluster rule. Authors never declare it.
    *   **Rule**: Every citation, printed tie and read is ledgered; clusters come from one rule; the ledger regenerates after the first call; copies and seeds read nothing; built inputs are declared.
    *   **Redirection**: when a design needs documents, query the pool and claim whole clusters.
    *   **Reason, measured**: an arm re-declared eight in-sample documents as held out and changed its cluster rule in its favour; derived, 15 of its 16 documents were in-sample, and none of that day's wins reached a verdict.

*   **¶INV_EXP_DOCUMENTS_ARE_THE_UNIT**: Statistics resample whole documents, and a design has enough documents that carry the defect.
    *   **Rule**: Document-level permutation and bootstrap; seven to nine or more documents; check the minimum detectable effect before paying. Temperature-0 repeats are not replicates.
    *   **Redirection**: buy documents, not repeats.
    *   **Reason, measured**: switching to document-level resampling flipped three verdicts. One re-verdict was underpowered by construction — its noise bar exceeded the defect's base rate and 10 of 16 documents never showed the defect. 13 of 15 temperature-0 repeats in one run were identical.

*   **¶INV_EXP_PLACEBO_ALWAYS**: Every arm has a placebo on the same channel, in the same batch, and the control runs concurrently.
    *   **Rule**: The placebo changes the same channel without the information under test. It must be shown neutral against base before it may excuse anything. The one exception is arms that are deterministic over one shared read; they seal a placebo waiver and a real null instead (`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`).
    *   **Reason, measured**: an unrelated sentence in the schema moved cells from 9 to 15; one wording arm's apparent win was matched by its own placebo; a byte-identical arm re-run fifteen hours later scored 0.571 against 0.419.

*   **¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL**: A design whose arms are deterministic (two versions of code over one shared paid read) still seals a null before registering.
    *   **Rule**: Seal a second, independent paid read of the same documents with both arms applied to each read, so the null measures read-to-read noise, or another null the verdict tool accepts, and write in the design why a placebo is waived. Re-running deterministic code over the same read is identical by construction and is not a null. A design that seals `null: null` cannot reach a verdict.
    *   **Redirection**: when a placebo makes no sense because the arms share one read, replace it with a sealed null; do not leave the slot empty.
    *   **Reason, measured**: a paired-solver design waived its placebo and sealed no null; after $13.14 of reads the tool printed `NO VERDICT: missing same-batch null` beside a rule outcome of NO-EFFECT, because the tool has no waiver for deterministic arms.

*   **¶INV_EXP_GUARDS_AGAINST_BASE**: Guards are judged against base directly. Cost, tokens and latency are absolute; a placebo cannot excuse them.
    *   **Redirection**: when a guard trips and the placebo trips too, report both numbers against base and let the rule decide, not the resemblance.
    *   **Reason, measured**: a schema field cleared its output-token gate through the placebo path; judged directly it cost +8.9% against a 5% gate, and it was built in code instead. A later arm excused +28.9% cost with a +50.1% placebo.

*   **¶INV_EXP_VERDICT_WORDS**: The verdict is one of LAND · NO-EFFECT · FAIL-GUARD · NO VERDICT · DESCRIPTIVE ONLY, printed by the tool, with its evidence class.
    *   **Rule**: Post-hoc, in-sample, pilot and smoke results are DESCRIPTIVE ONLY. A NO VERDICT names what was missing. A default flipped on descriptive evidence says so in writing.
    *   **Redirection**: never call a failed verdict "a technicality"; a procedural NO VERDICT is a tooling lesson.
    *   **Reason, measured**: about $75–108 of runs ended in procedural NO VERDICT across two days. A production default was flipped on an arm whose LAND held only under one of three scorings, with the real basis a smoke run.

*   **¶INV_EXP_GOLD_IS_VERSIONED**: The truth set a verdict is scored against carries a version, and the verdict names it.
    *   **Rule**: Seal the gold with its version beside the design. When the gold's rules change (an expert ruling, a relabelling), the old verdicts stay as recorded, and each one affected gets a $0 re-score under the new gold, labelled DESCRIPTIVE ONLY. A landing that rests on a verdict says which gold version it was scored under. A re-score that flips a verdict a landing rests on goes to the operator as a question with a recommendation (keep on, switch off, re-register).
    *   **Redirection**: when an expert ruling changes what counts as right, re-score the stored runs at $0 before quoting their verdicts again.
    *   **Reason, measured**: one expert-ruled revision of the gold turned a registered `A LAND` (0.347 → 0.536, p 0.0279) into NO-EFFECT on re-score (0.273 → 0.310, p 0.449), with a single rule driving the flip. A running experiment still scored under the old rule had to be flagged by hand.

*   **¶INV_EXP_METRIC_MUST_BE_ABLE_TO_LOSE**: A metric that cannot lose, an axis that rewards doing less, or a zero from an instrument that could not see is invalid.
    *   **Rule**: Check the base is not zero by construction; pair every quality axis with completeness; give every absence a positive control.
    *   **Reason, measured**: one arm's primary metric was 0 for base and placebo by construction. A "9 → 0 self-binds" claim was tautological — the same change removed the thing counted. A merge guard's "unchanged" rested on inputs the change never touched.

## Levers

*   **¶INV_EXP_LEVERS_IN_THE_OPERATORS_ORDER**: Levers are tried in the order the operator rules. A better prompt or schema comes before code that rewrites the model's output.
    *   **Rule**: Follow the project's lever ladder as the operator ordered it; within a class, cheapest first. After two or three arms of one lever class fail on the same failure, move to the next class on the ladder, not straight to code. A code step that rewrites, filters or re-joins model output after the fact comes last, and it needs the operator's OK even when it measures better. Deterministic code that prepares the model's inputs (text extraction, structured hints derived from the input) and plumbing (storage, routing, cache keys) do not count as post-processing.
    *   **Redirection**: when wording keeps failing, try the next prompt or schema shape (structure, a new field, a split request, better inputs) before an output fix. When an output fix is the only lever left, ask the operator with the numbers.
    *   **Reason, measured**: wording on one drift failure failed three times in a row; the one promising lead (0.571 → 0.427) did not replicate (0.431 → 0.529, the wrong way). Code folds then cut it a little (12,856 → 12,213 of 63,399 cells) and showed that most of the remainder was extraction, not keys. The operator then ruled: "i always will take better prompt/schema over some hacky/sketchy post-processing scripts that are brittle and optimize wrong thing". In the same run a code fix that moved 306 → 763 on the documents it was developed on moved 0 of 12 fresh documents. Input-preparing code that counts here: OCR, page facts, labelled numbers.

*   **¶INV_EXP_SCHEMA_LIMITS_ARE_GATED**: Provider limits on schema width, enum members and size get a CI gate and a $0 acceptance probe.
    *   **Reason, measured**: the provider refused a read once an enum reached six members at a width it otherwise accepted; one shape was refused at 320 enum occurrences while the production read carried 325 with no gate, and a later probe found the real wall was enum characters, which no width count could see; one grafted schema of about 107 KB came back HTTP 400. A pinned ceiling in CI and a probe costing cents replaced guessing.

## Execution

*   **¶INV_EXP_PAID_ARMS_RUN_PRIVATE**: Paid arms run on a private worker, private queues and pinned code.
    *   **Rule**: Queue names come from configuration, not code; check the worker polls only its own queues. In-process arms run from an archive or worktree, not the shared tree.
    *   **Reason, measured**: a private worker polled the shared queues for about 15 seconds through hard-coded queue names and took three activities of another lane's run. In-process arms reading the shared tree had code change under them mid-run.

*   **¶INV_EXP_SHIP_OFF_THEN_DEFAULT_IN_CODE**: New behaviour ships off, is measured, then turns on in code, with no lingering environment switch.
    *   **Reason, measured**: the operator: "when everything is ready I don't want to see reliance on those env variables". A per-process switch also flips every worker at once.

*   **¶INV_EXP_ONE_INTEGRATION_RESTART**: Reviewed changes are batched into one restart with a clean cutover.
    *   **Rule**: Restart from a clean worktree only after committing every dirty runtime file the old worker relied on. Replay-sensitive changes carry a version marker and a worker-swap replay test. Never run old and new workers together across such a change; there is no rollback once new-marker histories exist.
    *   **Reason, measured**: a clean-worktree restart silently ran a stale committed file that the dirty tree had been shadowing, and 69 runs across 59 documents used the old behaviour for hours.

*   **¶INV_EXP_ONE_INTEGRATOR_FOLDS**: Reviewed branches reach the integration branch through one integrator lane at a time, never through each lane's own PR or merge.
    *   **Rule**: A lane pushes its reviewed branch and stops. The integrator folds ready branches in order, gets every conflict resolution its own review, re-runs the type checks and a $0 replay at each new head, and updates the integration PR's body. Dispatch a new integrator only after the previous one has exited, so two never race on one branch.
    *   **Redirection**: when a lane wants its own PR into the shared base, tell it to push only and hand the branch to the next integrator.
    *   **Reason, measured**: one integrator folded five reviewed branches in four fast-forward pushes; both conflict resolutions got their own approving review, and a $0 replay at every head showed 0 of 78 map units changed. A lane that had asked for its own PR into the shared base was folded the same way.

*   **¶INV_EXP_SHARED_TREE_SAFETY**: In a shared tree, lanes commit their own hunks by explicit path, never run destructive git, and run formatters on explicit file lists.
    *   **Reason, measured**: a formatter given an empty path list rewrote 3,363 files; whole-file pathspec commits swept other lanes' hunks twice in one day; a "dead" builder was alive and two agents wrote one worktree; a lane's `git stash` landed in the stash stack every worktree shares.

## Agents

*   **¶INV_EXP_RESUME_BY_ID**: Within one harness process, a killed lane resumes by id. After the harness itself restarts, a lane is replaced by a fresh agent that recovers from disk, git and receipts using a written recovery preamble.
    *   **Rule**: A lane killed by a limit or a safeguard resumes by id: "resume; check disk, store and git; don't repeat paid calls". After a harness restart, old ids no longer resume; spawn a fresh agent with the thread's brief plus the recovery preamble. The preamble says: read the common brief and the log from the restart onward, search the log for the thread's tag, recover the worktree, branch, build files, receipts and run outputs, count what a paid run in flight already bought before relaunching anything, and log a "recovered" entry before continuing. A lane killed repeatedly by a safeguard switches model; a weaker model gets explicit context.
    *   **Redirection**: when a hand-back arrives from a lane whose name the conductor no longer knows, recover its result from disk before acting on it.
    *   **Reason, measured**: safeguard false positives killed four lanes doing ordinary build work; relaunches on another model got past it. Two relaunches on a smaller model declined a relayed brief as unverifiable and did nothing, parking the lane overnight at $0. Usage-limit outages stopped every lane at once at least seven times; after a harness restart, resume-by-id failed for every old lane, one finished lane's hand-back never reached the conductor, and lanes were replaced from a written recovery preamble with no paid call repeated.

*   **¶INV_EXP_ANSWERS_GO_TO_DISK**: Every answer reaches disk. The lane returns its full report in its hand-back; the conductor saves it to the path the brief named. See the engine's `¶INV_A_PROBE_WRITES_ITS_ANSWER_DOWN`.
    *   **Rule**: The brief names the report path. The lane tries to write there; whether or not the write succeeds, its hand-back carries the whole report, not a summary pointing at the file. The conductor saves any report that is not on disk before relaying it, and notes in the log that it did.
    *   **Redirection**: when a lane's write is refused, do not retry with another tool or path; put the full text in the hand-back and say the write was refused.
    *   **Reason, measured**: the harness refused subagent report writes at least ten times in one run, so a rule that the lane must write its own report could not be followed. A lane finished with no report on disk and had to be resumed to write it; a probe's answer survived only because the conductor saved it.

*   **¶INV_EXP_RELAYED_IS_UNCHECKED**: A fact relayed from another lane is a check you did not run. Consent-bearing actions are done by the agent that heard the operator.
    *   **Reason, measured**: the conductor authorised a lane to adopt a relaxed test from another lane, and review found it unsound ("my error"). An auditor missed a ruling it had only heard about. A lane correctly declined to publish on relayed consent; the conductor, holding the operator's answer, published instead.

## Review

*   **¶INV_EXP_EVERY_LANDING_IS_REVIEWED**: Every change that counts as landed has an approving adversarial review.
    *   **Rule**: Fix rounds until APPROVE. Split MUSTs into before-merge and before-switch-on. Re-review a fix round that changed code, even when it is inert while off. Tests must fail on the old code.
    *   **Reason, measured**: an amount fix merged off with its last round unreviewed because it was inert; the next review of that round found two new MUSTs. A unit test for a new exclusion passed on the parent commit.

*   **¶INV_EXP_REPLAY_AFTER_THE_VERDICT**: A code change made after the verdict measured an arm — a review fix, a merge resolution, a fold — is replayed at $0 against that experiment's stored outputs before the landing cites the verdict.
    *   **Rule**: Run the stored inputs of the measured experiment through the changed code and report units changed out of units replayed. Zero changed: the verdict still describes the code. Anything changed: say what moved, and decide with the conductor whether the verdict still stands. A change to the verdict tool itself replays every stored verdict and reports how many verdict lines changed.
    *   **Redirection**: when a reviewer's MUST changes code after the paid run, do not carry the verdict over on trust; replay first.
    *   **Reason, measured**: a review fix changed a landed arm's window code after its registered run; a $0 replay through the fixed commit showed 99 of 99 units identical, and only then was the proof page published. A verdict-tool fix was replayed over 126 stored verdicts: 0 verdict lines changed, 32 flag lines changed.

*   **¶INV_EXP_PRODUCTION_SAFETY_BEFORE_SHIPPING**: Before reviewed work ships to production, a read-only safety review reads it as it will deploy — migrations, rollback, switches, mixed fleets — separate from the per-change reviews.
    *   **Rule**: The review is report-only and covers every branch in the release together. It asks what an automatic rollback restores, which migrations are one-way doors, what runs ungated, and what the old and new code do side by side during the deploy. Its findings go to the operator as questions with a recommendation, for a ruling; it does not fix.
    *   **Redirection**: when every change has an approving review, still run the release-level review; per-change reviews do not see the deploy.
    *   **Reason, measured**: after every change had passed review, a production-safety review found a migration that dropped a table the production code still wrote, with no one-way-door marker, so the deploy's automatic rollback would have restored an image that errors. The operator ruled one-way-door headers on two migrations and a single release for the two branches.

## Operator

*   **¶INV_EXP_RULINGS_ARE_VERBATIM**: Operator rulings are recorded verbatim, kept in force, and re-broadcast when they change.
    *   **Reason, measured**: a mid-session ruling moved all merging from code to the model; lanes building code merges had to be paused and re-scoped, which only worked because every ruling lived in one brief every lane read.

*   **¶INV_EXP_ASK_WITH_A_RECOMMENDATION**: Questions go through `AskUserQuestion` with the recommended option first, in plain language, each option a positive choice. While the operator is away, they go to a morning-questions file with the default taken.
    *   **Reason, measured**: a "pick the ones you disagree with" question produced ticks that could mean either, and all three items had to be held. The morning-questions file carried a night's decisions with leans and was answered in one pass.

*   **¶INV_EXP_STOP_WHEN_THE_LEVERS_RUN_DRY**: When paid levers keep coming back null, stop buying quality and harden the system.
    *   **Reason, measured**: a council over the measured results found every paid lever it had proposed measured and rejected, and recommended a $0 day; the operator accepted the stop list. The operator's standing line: "systems before quality".

*   **¶INV_EXP_TOOLING_IS_WORK**: A missing instrument is a thread, built at $0, smallest first, reviewed like production code.
    *   **Reason, measured**: the verdict tool, touch ledger and registration took several review rounds each and caught real defects; once in place, the loop failed closed. The operator: "be reasonable … don't overbuild" — preflight, a locked ledger regeneration and a commit helper only.
