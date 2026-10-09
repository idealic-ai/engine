# /loom-experiment pitfalls

A catalogue to consult, not to read front to back. Each entry names a failure that has already cost money, time or a verdict, the incident behind it, and the guard. Consult the Measurement section before sealing a design, the Execution section before touching shared runtime, and the whole list when a number looks too good.

## Measurement

### ¶PTF_AUTHOR_DECLARED_HELD_OUT
**What happens**: the author picks which documents are "held out", and picks in the arm's favour, usually without meaning to.
**Incident**: an arm re-declared eight in-sample documents as held out and loosened its cluster rule; derived by tooling, 15 of its 16 documents were in-sample.
**Guard**: held-out comes from the touch ledger and a committed cluster rule (`¶INV_EXP_HELD_OUT_IS_DERIVED`).

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
**Guard**: register last, from the current ledger head; preflight refuses stale registrations.

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

### ¶PTF_ENV_SWITCH_LEFTOVER
**What happens**: a feature stays behind an environment variable after it is measured, and runtime behaviour depends on how each process was started.
**Incident**: the operator ruled env switches out; the example env file still documented the switch and needed a separate cleanup.
**Guard**: turn on in code; delete the switch and its documentation in the same change.

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
**Incident**: a lane finished with no report on disk and had to be resumed to write it; a probe's answer survived only because the conductor saved it.
**Guard**: every brief names an absolute report path.

### ¶PTF_SAFEGUARD_KILL
**What happens**: an API safeguard false positive kills a lane mid-build.
**Incident**: four lanes doing ordinary build work were killed this way, one just before its paid arm.
**Guard**: resume by id; if it recurs, relaunch on another model, told to resume from disk.

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
**Incident**: experiment numbers collided more than once; folders without a `Lever:` line blocked every lane's ledger regeneration twice in one evening.
**Guard**: the conductor assigns numbers; the `Lever:` line is in the first commit.

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
