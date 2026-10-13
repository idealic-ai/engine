# /loom-experiment pitfalls

A catalogue to consult, not to read front to back. Each entry names a failure that has already cost money, time or a verdict, the incident behind it, and the guard. Consult the Measurement section before sealing a design, the Execution section before touching shared runtime, and the whole list when a number looks too good.

## Measurement

### ¶PTF_AUTHOR_DECLARED_HELD_OUT
**What happens**: the author picks which documents are "held out", and picks in the arm's favour, usually without meaning to.
**Incident**: an arm re-declared eight in-sample documents as held out and loosened its cluster rule; derived by tooling, 15 of its 16 documents were in-sample. Later a rule change proposed to reuse any document a lane's own contact file did not name — the same exemption by another route; three reviewers caught it independently.
**Guard**: held-out and contact come from the touch ledger and committed rules; an author's list only adds exclusions (`¶INV_EXP_HELD_OUT_IS_DERIVED`).

### ¶PTF_REPEATS_COUNTED_AS_DOCUMENTS
**What happens**: repeats of one document are treated as independent observations, and a small effect looks significant.
**Incident**: moving to document-level resampling turned one LAND into NO VERDICT (3 documents) and another into NO-EFFECT (p 0.094 at 12 documents).
**Guard**: resample whole documents; seven to nine or more documents.

### ¶PTF_UNDERPOWERED_BY_CONSTRUCTION
**What happens**: the design cannot reach a verdict whatever the arm does, and the money is spent anyway.
**Incident**: a re-verdict's noise bar exceeded the defect's base rate and 10 of 16 documents never showed the defect; a six-document design had a minimum detectable effect near 0.34; a reference test drew 13 policies that printed 14 references between them.
**Guard**: before paying, count how many chosen documents carry the defect and compute the minimum detectable effect. Stop if it exceeds the claim.

### ¶PTF_TEMP_ZERO_REPLICATES
**What happens**: temperature-0 repeats are treated as either identical (no noise) or independent (full noise); they are neither.
**Incident**: 13 of 15 repeats in one run were identical, while elsewhere re-asks at temperature 0 flipped outcomes on the same input.
**Guard**: measure noise from same-batch control re-runs at the settings you ship; count documents, not repeats.

### ¶PTF_CROSS_BATCH_CONTROL
**What happens**: a control from an earlier batch is used as the baseline, and the day's drift reads as an effect.
**Incident**: a byte-identical arm re-run fifteen hours later scored 0.571 against 0.419; an "11/16 → 16/16" gain was withdrawn once base and arm ran in one batch.
**Guard**: the control runs concurrently, interleaved with the arms.

### ¶PTF_PLACEBO_EXCUSES_A_REGRESSION
**What happens**: a guard trips, the placebo trips too, and the rule calls it noise — letting a real cost through.
**Incident**: a schema field cleared its token gate this way; judged directly against base it cost +8.9% against a 5% gate. Another arm excused +28.9% cost with a +50.1% placebo; elsewhere a placebo itself made 20 wrong joins.
**Guard**: guards against base; cost, tokens and latency are absolute; a placebo must be shown neutral before it excuses anything.

### ¶PTF_PLACEBO_GAP_BECOMES_THE_BAR
**What happens**: a placebo moves the metric and its gap from control becomes the bar the arm must clear — too low when a wording placebo leaked information, impossibly high when a label-breaking placebo was used as a margin — or the failed placebo check is only printed as a flag.
**Incident**: one run's bar became a label-breaking placebo's gap, 0.585 against a document noise bar of 0.034, and no arm could land. The tool's comparable checks were printed flags that never stopped a LAND.
**Guard**: seal each placebo's role; a wording placebo outside the noise bar gives NO VERDICT with the reason named; a label-breaking placebo must come out worse than control and never widens the bar (`¶INV_EXP_PLACEBO_ALWAYS`).

### ¶PTF_GUARD_BLIND_UNDER_THE_NULL
**What happens**: a guard is tuned until it rarely trips on a null arm, and in the process stops seeing the harm it was built for.
**Incident**: a calibration proposal sealed any guard that tripped at most 10% of the time under the null and named no positive control; one guard had already been redefined this way and was caught only by a critic. Budgeted per guard, five guards at 10% give about a 41% chance of a false trip on a null arm.
**Guard**: a planted-harm positive control the guard must trip on, beside the null check; false trips budgeted per arm or guard family (`¶INV_EXP_GUARDS_HAVE_TWO_CONTROLS`).

### ¶PTF_REPEATS_CHANGED_UNDER_A_CALIBRATION
**What happens**: a design runs fewer repeats than its guard was calibrated at, and the guard's false-trip rate quietly multiplies.
**Incident**: a guard calibrated at 3 repeats (0.003 false trips per document) would have run at 2 (0.017), about 7% against 35% per 25-document run; its label pinned values, not the repeat count, so the tool would not have noticed.
**Guard**: the calibration records its repeat count; preseal refuses a mismatch (`¶INV_EXP_GUARD_CALIBRATION_PINS_THE_REPEATS`).

### ¶PTF_VERDICT_CODE_REWRITES_SEALED_RUNS
**What happens**: a change to how the verdict tool evaluates an existing rule value changes what every old sealed design prints on re-verdict, after its outcome is known.
**Incident**: deleting one margin term would have rewritten re-verdicts of 128 sealed design files and moved one run's bar from 0.585 to 0.034. The tool's own revision comparison applied the same code defaults on both sides and could not see it.
**Guard**: new statistics as new sealed values, fields or a method version; a full-output replay of every stored verdict before merging (`¶INV_EXP_SEALED_MEANING_NEVER_CHANGES`).

### ¶PTF_ONE_SIDED_SCOREBOARD
**What happens**: the programme tracks only how often runs reach a verdict, so a change that lets false LANDs through looks like progress.
**Incident**: moves to cut procedural NO VERDICT spend were judged on that number alone; nothing recorded whether any of 16 registered LANDs had later held.
**Guard**: track each LAND as held, reversed or untested, and gate every loosening on it (`¶INV_EXP_LANDS_HAVE_A_COUNTER_METRIC`).

### ¶PTF_METRIC_THAT_CANNOT_LOSE
**What happens**: the primary metric is zero for base and placebo by construction, so any arm "wins".
**Incident**: an all-kinds reading arm was scored on kinds the base never asked for; a "self-binds 9 → 0" claim counted something the change itself removed.
**Guard**: before sealing, ask what base and placebo score on the metric. Judge added capability on its own quality.

### ¶PTF_DOING_LESS_WINS
**What happens**: an agreement or precision metric improves because the arm answers less.
**Incident**: an arm scored 0.515 against 0.000 with 12 of its 17 agreements on an empty answer; the first yardstick had no completeness axis at all.
**Guard**: pair every quality axis with completeness and report the empty-answer share.

### ¶PTF_BLIND_ZERO
**What happens**: an instrument reports zero defects because it could not see them.
**Incident**: a merge guard "held" on stored inputs that the change never touched; a format check caught none of the tenfold amount errors a later probe found; a comparison gate passed a tenfold regression and an empty candidate.
**Guard**: every absence ships with a positive control that must fire.

### ¶PTF_BUILT_INPUTS_COUNTED_AS_READS
**What happens**: inputs a lane builds from stored data before its first call are ledgered as reads, putting its own documents in-sample.
**Incident**: one lane's $0 built inputs burned its fourteen-document slate; another's inputs silently became reads and a $20.74 run lost its verdict.
**Guard**: declare built inputs in the sealed design.

### ¶PTF_BUILT_INPUTS_SEALED_AT_THE_WRONG_COMMIT
**What happens**: the design's built-inputs commit points at a commit that does not contain the build script, so the tooling cannot see the inputs as built and counts them as reads.
**Incident**: two sealing errors in one day pointed built inputs at the product commit instead of the experiment commit; one made all 10 documents in-sample after $7.89.
**Guard**: preflight refuses a built-inputs commit that does not contain the declared build script.

### ¶PTF_COPIED_DESIGN_DROPS_A_BLOCK
**What happens**: a design copied from an earlier experiment's shape lacks a block the verdict now needs.
**Incident**: a design copied from an older one had no held-out block; the data was held out 46 of 46, but the verdict was a procedural NO VERDICT.
**Guard**: preflight refuses a design without a held-out block, a sealed null, or any other block the verdict reads.

### ¶PTF_DRAW_NOT_IN_THE_LEDGER
**What happens**: freshly drawn documents are registered before the ledger has scanned the draw, so the run's first store write postdates the pinned ledger and the first call cannot be vouched for.
**Incident**: one run's verdict refused because the draw folder was not in the ledger pinned at registration; that run spent $12.71 and an earlier run had hit the same.
**Guard**: add the draw to the ledger and regenerate before registering; preflight refuses documents the pinned ledger has never seen.

### ¶PTF_PRE_RUN_FILES_IN_THE_FOLDER
**What happens**: a file written into the experiment folder before the first call (an attempt, a probe receipt) is scanned as a read, and retiring it in the ledger does not stick.
**Incident**: a retired pre-run read kept coming back because the folder scan re-added it from the file's modification time on every regeneration; the run stayed `NO VERDICT: held-out/cluster drift` and was recorded as descriptive only.
**Guard**: keep pre-run attempts and probe receipts outside the experiment folder; preflight refuses run outputs or receipts under `runs/` dated before the registration.

### ¶PTF_HAND_CHECK_NOT_DOWNSTREAM
**What happens**: a hand-check of the page predicts how many documents a fix will move, but later stages never reach the fixed step on those documents.
**Incident**: a hand-check predicted about ten movers of twelve; the paid run moved 0 of 12, because 387 of 406 scenarios were blocked before the fixed stage. The fix's earlier gain had been measured on the documents it was developed on.
**Guard**: a $0 dry run of the base arm through every downstream stage before paying (`¶INV_EXP_DRY_RUN_DOWNSTREAM`); quote in-sample gains as ceilings.

### ¶PTF_DETERMINISTIC_DESIGN_WITHOUT_A_NULL
**What happens**: a design with deterministic arms over one shared read waives the placebo and seals no null, and the verdict tool refuses.
**Incident**: `NO VERDICT: missing same-batch null` after $13.14, with a rule outcome of NO-EFFECT.
**Guard**: seal a placebo waiver and a real null — a second, independent paid read of the same documents with both arms applied to each read, so the null measures read-to-read noise (`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`).

### ¶PTF_GOLD_MOVED_UNDER_THE_VERDICT
**What happens**: the truth set changes after a verdict, and the old verdict keeps being quoted as if it were scored under the new one.
**Incident**: a gold revision after an expert ruling turned a registered LAND into NO-EFFECT on re-score, and a running experiment was still scoring under the old rule.
**Guard**: version the gold; re-score affected verdicts at $0 and label them descriptive (`¶INV_EXP_GOLD_IS_VERSIONED`).

### ¶PTF_STAGE_LEVER_MISMATCH
**What happens**: a run writes a stage its design does not declare as a lever — often through a stage name hard-coded in the entry point — and the verdict refuses the run after the money is spent.
**Incident**: a registered run got `NO VERDICT` with "wrote clauses, which the design does not declare"; a later run declared only the reading lever, wrote its receipts under a hard-coded clause stage, passed preseal, and was finished as descriptive only — re-registering would have made its documents in-sample on its own receipts.
**Guard**: preseal simulates the stages the run will write, receipt paths included, against the declared levers and refuses a mismatch; the lane lists the stages in the design (`TOOLING.md`, *Preflight and scaffolding*).

### ¶PTF_LEDGER_MISATTRIBUTES_STAGE
**What happens**: the touch ledger files a run's reads under the wrong lever, so documents the run read derive as held out on the lever it actually touched.
**Incident**: one run's fact reads were recorded as clauses-only; its 7 documents derived as held out on reading, and a lane designing a reading bundle had to exclude them by hand.
**Guard**: attribute stages from what each run wrote, not from its declared lever; print per-run stage counts on every regeneration and check them before trusting a derived split (`¶INV_EXP_REUSE_BY_LEVER_AND_CONTACT`).

### ¶PTF_SEED_COPY_COUNTED_AS_READ
**What happens**: seeding a run by copying stored stages is ledgered as a fresh read.
**Incident**: an arm whose rule said LAND got NO VERDICT partly on this; the fix recognised 5,573 copied stages by identical object hashes.
**Guard**: byte-identical copies count on no lever.

### ¶PTF_HIDDEN_LATER_STAGE
**What happens**: a "read only" run goes through an entry point that now also runs the next stage by default.
**Incident**: seeded reads went through the full pipeline, reconciled 16 documents (~$1.66), and made them in-sample for the stage under test; the lane redrew fresh documents.
**Guard**: pass the flag that stops at the stage you mean; check which stages wrote objects.

### ¶PTF_VANISHED_LOCAL_MIRROR
**What happens**: a local cache the ledger generator depends on disappears, and the generator quietly produces a wrong ledger.
**Incident**: a text mirror vanished; near-duplicate joins fell from 372 to 5 and printed-string ties were under-counted, putting ten documents wrongly in the held-out pool. The cause was never found.
**Guard**: the generator stamps what it read (counts, sources) and fails when a required source is empty.

### ¶PTF_CLAIMED_IDS_NOT_CLUSTERS
**What happens**: lanes claim document ids but not their near-duplicates, and a sibling's read makes a claimed document in-sample.
**Incident**: a near-duplicate was read by another lane seventeen minutes before a re-verdict's first call, costing its verdict; six of ten freshly drawn documents landed in already-read clusters after $14.86.
**Guard**: claim and exclude whole clusters in one append-only claims file.

### ¶PTF_STALE_REGISTRATION
**What happens**: a run is registered well before its first call, or from a checkout at an old ledger, and the verdict refuses it.
**Incident**: a 15.8-minute gap cost a $19.49 run its verdict; another run registered with a stale corpus pin from a main checkout.
**Guard**: register last, from the current ledger head, with registration and launch in one command; preflight refuses stale registrations.

### ¶PTF_UNBALANCED_ARMS
**What happens**: a treatment arm runs on fewer documents than the design names, and the comparison collapses.
**Incident**: one arm ran on 2 of 9 documents and the run ended NO VERDICT.
**Guard**: the verdict checks each arm's unit count against the plan; crashed units count as failing.

### ¶PTF_SILENT_EMPTY_ANSWER
**What happens**: the provider returns success with an empty body, and it is scored as "nothing on this page".
**Incident**: a refused form contributed a zero record to every cell — 42 page-runs of agreement between arms that read nothing.
**Guard**: probe the page set with the control first; an empty body is a retry and a counted failure; report answered-rate.

### ¶PTF_EXAMPLE_REACHES_PAST_ITS_TARGET
**What happens**: an instruction or example written for one case moves others, or fails to reach its neighbour.
**Incident**: an example for one kind emptied the answers of two other kinds; a long verbatim counter-example pulled its own text onto the member it sat on.
**Guard**: state the case per member, and score the neighbours as guards.

### ¶PTF_SMOKE_FLIPS_A_DEFAULT
**What happens**: a production default flips on descriptive or smoke evidence written up as a LAND.
**Incident**: a LAND held only under one of three scorings; the default's real basis was a smoke run and a stronger judge.
**Guard**: the landing note states the evidence class.

## Money

### ¶PTF_SENT_BYTES_MOVED_QUIETLY
**What happens**: an edit that looks internal is part of what is sent, and every stored input must be re-read.
**Incident**: a wording change in a description moved the sent-schema digest; the review caught it and it was restored byte for byte.
**Guard**: pin the sent digest in a test; price any move before landing.

### ¶PTF_FREE_CLAIM_THAT_ISNT
**What happens**: "$0 re-derive" is claimed for a change whose version bump will re-ask stored results.
**Incident**: a rule-version bump would have re-asked about $15 of stored reconciliations; another "$0" claim failed because most stored results lacked the stamp that allows re-derivation.
**Guard**: price lazy / all / only-changed from the actual stamps in the store.

### ¶PTF_CACHE_KEY_MISSING_A_FIELD
**What happens**: a cache key omits the prompt, model or rule version, and stale answers are served as current.
**Incident**: a reconciliation cache compared only a guidance digest; a rule-version bump would not have applied to re-runs. Every field added to the key later costs another full re-run.
**Guard**: key caches on everything that changes the answer, from the start.

### ¶PTF_PAYING_PAST_THE_EVIDENCE
**What happens**: paid quality arms continue after the levers have run dry.
**Incident**: a council over measured results found every paid lever it had proposed measured and rejected; about $75–108 had ended in procedural NO VERDICT.
**Guard**: council the data when nulls accumulate; write a stop list; switch to $0 hardening.

### ¶PTF_HEADLINE_MIXES_ERAS
**What happens**: a waste figure pools spend from before and after the protection against that waste landed, so causes already fixed inflate today's headline and the case for the next fix.
**Incident**: "21% of spend ended in procedural NO VERDICT" was almost all from before a preseal check landed; after it, only two runs ended that way, each for a new reason. A companion "87% tonight" rested on four runs.
**Guard**: split spend by outcome and by NO VERDICT reason, against the date each protection landed; attribute each run by its first registered verdict; give every share its denominator.

## Execution

### ¶PTF_SHARED_QUEUE_POACHING
**What happens**: a private worker polls shared queues and runs another lane's work on the wrong code.
**Incident**: queue names hard-coded in the worker made a private worker take three activities of another run in fifteen seconds.
**Guard**: queue names from configuration; check what a new worker polls before starting arms.

### ¶PTF_ARMS_READ_THE_LIVE_TREE
**What happens**: in-process arms import code from the shared working tree, which other lanes are editing.
**Incident**: code changed under running experiments; worker-routed arms were safe only because they were pinned to the worker's start commit.
**Guard**: run arms from an archive or worktree at a commit.

### ¶PTF_DIRTY_TREE_RESTART
**What happens**: a restart from a clean worktree loses an uncommitted runtime file the old worker relied on.
**Incident**: a never-committed shim had been shadowing a stale file; the clean worker ran the stale behaviour for 69 runs across 59 documents.
**Guard**: before a clean restart, list dirty runtime files in the worker's import graph and commit or discard each deliberately.

### ¶PTF_TWO_WORKERS_ONE_HISTORY
**What happens**: old and new workers run together across a replay-incompatible change, or a rollback is attempted after new histories exist.
**Incident**: reviews proved the old code fails replay on post-change histories; the cutover was run with no open runs and no rollback path.
**Guard**: version markers, worker-swap replay tests, clean cutover, never two workers.

### ¶PTF_ROLLBACK_THROUGH_A_ONE_WAY_DOOR
**What happens**: a release passes every per-change review, but a migration cannot be undone and the deploy's automatic rollback would restore code that fails on the new schema.
**Incident**: a migration dropped a table the production code still wrote, with no one-way-door marker; only a release-level safety review saw it.
**Guard**: a read-only production-safety review of the release as it will deploy (`¶INV_EXP_PRODUCTION_SAFETY_BEFORE_SHIPPING`).

### ¶PTF_ENV_SWITCH_LEFTOVER
**What happens**: a feature stays behind an environment variable after it is measured, and runtime behaviour depends on how each process was started.
**Incident**: the operator ruled env switches out; the example env file still documented the switch and needed a separate cleanup. Later the operator ruled against new flags too ("i want less flags and move movement forward"), and a fix that had been given its own flag moved onto an existing one.
**Guard**: add no new flag or environment switch; turn on in code once reviewed and measured; where a gate is unavoidable, reuse an existing one, and delete it with its documentation in the same change that turns the behaviour on (`¶INV_EXP_SHIP_OFF_THEN_DEFAULT_IN_CODE`).

### ¶PTF_ANCESTRY_MISSES_A_CHERRY_PICK
**What happens**: "is the fix in this build?" is answered with an ancestry check on one commit id, and a cherry-picked copy of the fix under another id reads as absent.
**Incident**: an ancestry check said a memory-release fix was missing from all three pinned trees of a run that crashed; the same patch was in both solve trees under other commit ids. The diagnosis "the pin predates the fix" was wrong, and the crash happened with the fix present.
**Guard**: compare patch-ids (`git patch-id --stable`, or `git log --cherry-pick`), or read the fixed code at the pin; never conclude from `merge-base --is-ancestor` alone.

### ¶PTF_BIGGER_BOX_FOR_A_PER_PROCESS_CAP
**What happens**: a memory crash is blamed on the machine, and a bigger one is bought, when the limit is per process.
**Incident**: a solver library compiled to WebAssembly declares a fixed 2 GiB memory maximum in its binary; a proposal said a larger cloud machine "fixes" its out-of-memory aborts. More RAM runs more solves at once; it never gives one solve more memory.
**Guard**: before buying capacity for a crash, find where the limit lives (binary, runtime flag, container, host); solo-retry crashed items and log their peak allocation. Judge a bigger host on per-item time and on batch time over the longest single item, since batches are tail-bound.

### ¶PTF_WHOLE_TREE_FORMAT
**What happens**: a formatter given an empty path list formats everything.
**Incident**: 3,363 files rewritten; restoring them took a per-file check that each was format-only.
**Guard**: formatters and linters only on an explicit, non-empty file list.

### ¶PTF_WHOLE_FILE_PATHSPEC_SWEEP
**What happens**: committing a whole file carries another lane's uncommitted hunks in the same file.
**Incident**: it happened twice in one day in a file several lanes edited.
**Guard**: commit your hunks from a private index; tell the conductor when a file is shared.

### ¶PTF_TWO_AGENTS_ONE_WORKTREE
**What happens**: a lane believed dead is alive, a replacement is started, and both write one worktree.
**Incident**: a "dead" builder was alive; the duplicate was stopped after both had written.
**Guard**: check the agent list before relaunching; one agent per worktree.

### ¶PTF_SHARED_STASH
**What happens**: `git stash` in a scratch worktree lands in the stash stack every worktree shares.
**Incident**: a lane stashed its own findings edit; it was re-applied by hand and the entry stayed in the shared stack.
**Guard**: never stash in a shared repository.

### ¶PTF_OUTAGE_WITHOUT_AN_OWNER
**What happens**: the store or runtime stops mid-run, and lanes restart it independently or stall.
**Incident**: the whole container stack stopped twice in one day (the operator was changing resource limits); a disk filled and killed the store; a synced session folder emptied from the cloud side.
**Guard**: one written restart recipe, run by the conductor with the operator's OK; ask who stopped it; keep working state on local disk.

## Agents

### ¶PTF_TRANSCRIPT_ONLY_ANSWER
**What happens**: an agent answers in its reply only, and the answer dies with the context.
**Incident**: a lane finished with no report on disk and had to be resumed to write it; a probe's answer survived only because the conductor saved it. Later, the harness refused subagent report writes at least ten times, so the lane could not write the file even when told to.
**Guard**: the brief names the report path; the lane returns the full report in its hand-back; the conductor saves it (`¶INV_EXP_ANSWERS_GO_TO_DISK`).

### ¶PTF_SAFEGUARD_KILL
**What happens**: an API safeguard false positive kills a lane mid-build.
**Incident**: four lanes doing ordinary build work were killed this way, one just before its paid arm.
**Guard**: resume by id; if it recurs, relaunch on another model, told to resume from disk.

### ¶PTF_IDS_LOST_ON_RESTART
**What happens**: the harness restarts, every old lane id stops resuming, and hand-backs from lanes started before the restart arrive with no name or never arrive.
**Incident**: after a restart, resume-by-id failed for every running lane; one finished lane's hand-back never reached the conductor, whose log could only say "lane name unknown; recover from disk".
**Guard**: replace each lane with a fresh agent carrying a written recovery preamble; recover from disk, git and receipts before acting (`¶INV_EXP_RESUME_BY_ID`).

### ¶PTF_RELAYED_BRIEF_REFUSED
**What happens**: a smaller model treats a relayed brief or approval as unverifiable and does nothing.
**Incident**: two relaunches declined; the lane was parked overnight with $0 spent.
**Guard**: give explicit context — who is asking, the ruling, the branch, the cap — or relaunch on a model that has worked for this lane.

### ¶PTF_RELAYED_FACT
**What happens**: a fact passed along from another lane is treated as checked.
**Incident**: the conductor authorised adopting a relaxed test from another lane, and review found it unsound; a lane's "fails on HEAD" proof rested on another lane's half-written file.
**Guard**: verify what your result depends on yourself.

### ¶PTF_CREDENTIAL_WORKAROUND
**What happens**: a lane that lacks access uses another credential instead of stopping, or prints part of a secret.
**Incident**: one lane used a different profile when its session expired; another printed the first characters of a database password in its own output.
**Guard**: secrets by reference only; a missing credential is an escalation.

## Review and records

### ¶PTF_INERT_FIX_ROUND_UNREVIEWED
**What happens**: a fix round is merged unreviewed because it is inert while switched off.
**Incident**: the next review of that round found two new MUSTs before switch-on.
**Guard**: re-review every fix round that changed code.

### ¶PTF_FIX_AFTER_THE_MEASUREMENT
**What happens**: review or integration changes code after the paid run measured it, and the landing cites a verdict for code that no longer exists.
**Incident**: a review MUST changed a landed arm's window code after its registered run; it was caught and replayed at $0 (99 of 99 units identical) before the proof page went out.
**Guard**: replay the measured experiment through the changed code (`¶INV_EXP_REPLAY_AFTER_THE_VERDICT`).

### ¶PTF_TEST_PASSES_ON_PARENT
**What happens**: a new test passes on the old code, so it proves nothing about the change.
**Incident**: a unit test for a new exclusion passed on the parent commit.
**Guard**: run new tests against the old code and see them fail.

### ¶PTF_UNREVIEWED_TOOL_WRITES_GIT
**What happens**: a helper that commits for lanes corrupts the repository.
**Incident**: a folder-commit helper escaped its folder, corrupted a worktree link when given `.`, and committed symlinks; three review rounds before lanes could use it.
**Guard**: tools that write git or decide verdicts are reviewed like production code.

### ¶PTF_EXTERNAL_WRITE_NOT_READ_BACK
**What happens**: an external write reports success and changes nothing.
**Incident**: a tracker's issue-update call returned OK and silently applied nothing; another path applied it.
**Guard**: re-read every external write.

### ¶PTF_UNCOORDINATED_NUMBERING
**What happens**: lanes number experiments themselves, or a folder lacks the line the ledger generator needs.
**Incident**: experiment numbers collided more than once, including after the rule was written, and the same thing happened to migration and prompt-version counters shared by several branches; prompt revision numbers already sealed to one experiment were reused in two other lanes' drafts; folders without a `Lever:` line blocked every lane's ledger regeneration twice in one evening.
**Guard**: the conductor assigns numbers through a claiming tool that refuses a number already taken; revision and switch numbers come from the registry in `COMMON_BRIEF.md` (`¶INV_EXP_SWITCH_NUMBERS_FROM_ONE_REGISTRY`); the `Lever:` line is in the first commit.

### ¶PTF_STALE_NUMBER
**What happens**: a figure is quoted after the thing it measured changed.
**Incident**: a handoff doc quoted a drift rate a day out of date; a status page went stale within minutes of publishing; public pages with old figures could not be deleted.
**Guard**: every number carries its date and harness; republish or annotate when it moves.

## Operator and publishing

### ¶PTF_AMBIGUOUS_QUESTION
**What happens**: a question phrased as "pick the ones you disagree with" produces answers that could mean either.
**Incident**: three defaults were held until the operator could clarify.
**Guard**: each option is a positive choice, recommended first.

### ¶PTF_PRIVATE_CHANNEL_THAT_ISNT
**What happens**: a page is published to a channel believed private or temporary that is neither.
**Incident**: a "presigned link" rule protected nothing because the prefix was public-read and uploads could not be deleted; private artifacts vanished about thirty minutes after publishing.
**Guard**: verify the channel by fetching the page back unsigned; ask the operator for the data rule; keep a local copy.
