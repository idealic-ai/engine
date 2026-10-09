# Measurement tooling

For the conductor at Setup, and for any thread that needs an instrument that is not there. Evergreen. Most of what an experiment programme costs is not model calls: it is a result that measured something else, a verdict nobody can reproduce, or a paid run that ends in NO VERDICT because a control was missing. The instruments below are what prevent that. Build them as threads of their own, at $0, smallest version first.

## Guiding the user through a missing instrument

When the inventory finds a gap a Registered thread will need:

1. **Offer it as a thread**, with a recommendation, a size, and what it unblocks: "No verdict tool exists, so no paid arm can land. Recommended: build the minimal one ($0, one lane, reviewed) before any paid thread."
2. **Build the smallest version the next experiment needs.** Add later features only when a lane needs them. The operator's guidance here was "be reasonable, don't overbuild".
3. **Prove the instrument before it scores anything**: a known positive and a known negative (a canary), a perturbed copy that must lose exactly what was perturbed, and a replay of a finished experiment whose answer is known.
4. **Review it like production code.** A tool that decides verdicts or writes git gets the same adversarial review and fix rounds as a landed change.
5. **Commit the command that runs it** and document it where the experiment runbook points. A number is quotable only if it can be recomputed from the repository.

## The instruments

### Scorer (the yardstick)
- **Answers**: how good is an output, on axes that cannot be gamed by doing less.
- **Axes**: correctness (against truth or independent judges), stability (across repeats, pooled per cell), completeness (did it keep everything it should), and cost. Report them together; any one alone can be won by a regression on another.
- **Smallest version**: one script over stored outputs that prints each axis with denominators, versioned, with its version in every output row.
- **Its controls**: scores the gold set itself first and gets it right except listed, explained exceptions; a perturbed gold loses exactly what was perturbed.
- **Gold is versioned**: the gold carries a version, sealed beside the design, and every score names it. A gold revision re-scores affected runs at $0 as DESCRIPTIVE ONLY (`¶INV_EXP_GOLD_IS_VERSIONED`).
- **Reason, measured**: the first yardstick had no completeness axis, so dropping rows would have scored as improvement. One comparison measured printed strings instead of identities and reported a drift the pipeline had already joined. A scorer version absent from its output let the verdict tool mix two scoring rules. Logic copied into three places instead of imported drifted apart.

### Census over stored data
- **Answers**: how often does this happen, across everything we have, today.
- **Smallest version**: a read-only query or script over the store, printing counts with denominators and a handful of real examples per class.
- **Its controls**: a known instance must be found; say what the census cannot see.
- **Reason, measured**: a census found 0 wrong model-written page numbers in 456,902 stored facts, so the proposed code stamp became a report-only check instead of a build. Another counted inputs above a size cap at 0.36% of policies, so a ranged-reading feature stayed parked. Another found a numeric misparse on 544 of 82,832 money facts, which sized and justified a code fix.

### Replay harness
- **Answers**: what would the new code do to everything already stored, at $0.
- **Smallest version**: feed stored inputs through the new code, diff against stored outputs, and show the off path is byte-identical.
- **Its controls**: a committed command that reproduces the counts; a case known to change must change.
- **Reason, measured**: a replay caught its own sign-flip bug before any review. A later replay claim was not reproducible (a reviewer got 20 changes in 6,258 where the lane reported 2 in 9,142). A merge guard reported "unchanged" on stored inputs that the change never touched, so the evidence was vacuous. A defect in handling prior answers was invisible because no stored input carried priors.

### Verdict tool
- **Answers**: does this arm beat its control, with the controls present that make the answer mean something.
- **Checks**: a placebo arm; a same-batch null; distinct inputs after near-duplicate clustering; derived held-out documents; a registered design whose hash matches; document-level resampling; an attainable p; guards against base. It prints one verdict word or `NO VERDICT: missing …`.
- **Smallest version**: reads the sealed design and per-unit outputs, runs a document-level permutation test and the guard checks, and refuses rather than guesses.
- **Its controls**: replays of finished experiments reproduce their hand verdicts; each refusal has a test. A change to the verdict tool replays every stored verdict and reports how many verdict lines moved (`¶INV_EXP_REPLAY_AFTER_THE_VERDICT`).
- **Deterministic designs**: the tool accepts a sealed placebo waiver for arms that are deterministic over one shared read, and still requires a null: a second, independent paid read of the same documents with both arms applied to each read, so the null measures read-to-read noise. Re-running deterministic code over the same read is not a null (`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`).
- **Reason, measured**: its first review found the placebo could be the control arm, a missing guard field passed, NaN became p = 0, and the placebo rule waved regressions through. Switching to document-level resampling flipped three earlier verdicts, one LAND to NO VERDICT and one LAND to NO-EFFECT. A zero bootstrap bar from too few documents let an arm land on margin over noise. It fails closed: across four days every tooling defect cost spend or a NO VERDICT, never a false LAND.

### Touch ledger and derived held-out split
- **Answers**: which documents has any lever already seen, so which are still held out, and which cluster together.
- **Records per document**: every citation in shipped text, every distinctive string the shipped text prints, and every read by any run, with the run's first object time, stamped with the listing time. Reads are append-only. Clusters come from one committed rule.
- **Rules**: copies and seeds read nothing (byte-identical objects are copies); built inputs are declared in the design; a design's own runs start at its first call; the ledger regenerates after the first call, one lane at a time.
- **Reason, measured**: before it existed, an arm re-declared eight in-sample documents as held out in its own favour, and 15 of its 16 documents turned out in-sample. Its review rounds found a first-call time that could be moved a day, a forged older corpus pin accepted, and a run id reused to backdate reads. A vanished local text mirror silently broke clustering (near-duplicate joins fell from 372 to 5) and hid printed-string ties, putting ten documents wrongly in the pool.

### Registration and corpus pin
- **Answers**: was this design fixed before the money was spent, and on which corpus.
- **Smallest version**: a store-side record written right before the first call, carrying the design hash, run id, and the ledger commit in force. The store's own timestamps vouch for the first call.
- **Reason, measured**: a registration written early left a 15.8-minute gap before the first read; that run spent $19.49 and got NO VERDICT. A documented local-only registration path could never produce a verdict and survived in the docs.

### Spend and receipts ledger
- **Answers**: what was actually spent, per lane and in total.
- **Smallest version**: one receipt file per paid call at a fixed path (run, stage, document, arm, repeat), a recount script, and the lane cap checked at block boundaries.
- **Rules**: count separately billed services separately; served-from-cache costs zero and says so; never estimate what receipts can count.
- **Reason, measured**: one lane's reported spend moved from $24.8 to $27.0 on recount; its next run closed with 95 of 95 receipts and no repeated call. A result served from cache reported its original cost again, double-counting it.

### Checks layer (report-only)
- **Answers**: did anything silently go wrong in real outputs — a dropped value, a quote not on the page, a number that disagrees with its own printed text.
- **Smallest version**: pure deterministic functions over stored outputs, each with a known-positive and known-negative canary run before every sweep, writing findings to files.
- **Rules**: alarm, not gate, until its repeat-vs-repeat noise floor and false-alarm rate are measured.
- **Reason, measured**: a comparison gate between two sweeps failed 24 of 90 repeat pairs and passed both a tenfold regression and an empty candidate, so it stayed an alarm. A value-format check caught none of the tenfold amount errors a later probe found. A loss check first treated any row sharing a numbering key as "the same thing", hiding a real loss behind a warning.

### Judges
- **Answers**: correctness where no truth set exists.
- **Rules**: at least two engines; the two prompts framed differently; order and wording randomised per item; planted negatives with a stated single-label ceiling; report both-correct and either-correct bounds; a stronger tie-break judge only by capped permission. Agreement is corroboration, never proof.
- **Reason, measured**: two judges on one engine split on 68 of 129 joins because their wording was tied to their seat; a stronger tie-break judge settled 67 of 68. A LAND held only under the "both judges correct" scoring and not under the others, and a default was flipped on it.

### Preflight and scaffolding
- **Answers**: is this run allowed to start.
- **Smallest version**: `new <slug>` claims the experiment number from the conductor's ledger and scaffolds the folder. One `register-and-launch` command registers the run and starts it, so nothing can fall between the two. Before either, preflight refuses:
  - `OPEN` markers, an uncommitted design, or a missing `Lever:` line;
  - a design with no held-out block or no sealed null;
  - a built-inputs commit that does not contain the declared build script;
  - documents from a draw the pinned ledger has never scanned;
  - a stale registration;
  - an experiment number not claimed through `new`;
  - run outputs or receipts under `runs/` dated before the registration.
- **Reason, measured**: folders without a `Lever:` line blocked every lane's ledger regeneration twice in one evening. Experiment numbers collided more than once when lanes numbered themselves, including after the rule was written. A design copied from an older one lacked its held-out block and got a procedural NO VERDICT with the data held out 46 of 46. Two built-inputs commits pointing at the product commit made all 10 documents of one run in-sample. Draws registered before the ledger had scanned them cost runs their verdicts twice. A pre-run receipt left in the folder kept a retired read alive across every ledger regeneration. Each of these was caught only by the verdict, after the money was spent.

### Proof pages and review UI
- **Answers**: can someone who was not there see what happened and disagree with it.
- **Rules**: real artefacts only; numbers copied from the verdict output, never re-typed; scope at the top; the publishing channel verified by fetching the page back.
- **Reason, measured**: several published pages carried figures that went stale within hours and could not be deleted with the credentials at hand.

## Tools that write git or decide verdicts

Treat them as production code. A folder-commit helper took three review rounds to stop escaping its folder, corrupting a worktree link when given `.`, and committing symlinks; until it passed, lanes were told not to use it.
