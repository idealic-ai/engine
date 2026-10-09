# Organizing an experiment so it is actionable

For the conductor and any lane designing a Registered thread. Evergreen. It says how to lay out an experiment, phrase its question, climb the ladder of checks, read the statistics, and write a finding someone can act on. Where the project has its own experiment runbook, that runbook wins on project specifics; this file is the general shape.

## One folder per experiment

The conductor assigns the number. The slug names the question, not the technique. The folder lives in the repository next to the code it measures, not in a scratchpad — scratchpads are reaped, and a result whose evidence is gone is a claim nobody can check.

```
NNN-slug/
  PREMISE.md      question, decision, falsifier, Lever: line, tier — written first, from the first commit
  design.json     the sealed, machine-read design: arms, placebo, metric, guards, documents, built inputs
  arms/           the arm files exactly as sent (sealed with the design)
  instruments/    the scoring code this run used, kept with it
  runs/           every response body, receipts, the rule record, units, the verdict output
  RESULTS.md      what the instruments printed, exact counts
  FINDINGS.md     what we now believe, each claim with its measurement and its limits
  README.md       the entry point: what ran, what moved, what broke, what was retracted, the proof link
```

- `PREMISE.md` carries a `Lever:` line (which stage the arm changes) from its first commit, even as a draft; tooling that derives held-out documents reads it.
- A draft may carry `OPEN` markers. A run may not start from one.
- The premise is never edited after results exist. Changes go in as dated revisions below the original.
- Results and findings stay separate: results are what the instrument printed; findings are what we now believe. Conflating them is how a number becomes a claim nobody decided on.
- Commit the inputs that produced a number, not only the number. A repository that ignores the run record keeps the answer and drops the evidence.

## Phrase the question so the answer changes a decision

- Write the decision first: "if yes, we ship X; if no, we park it / try Y". A question whose answer changes nothing is not worth money.
- It can come out either way. The falsifier is written before the run and does not move.
- One change per arm, against a named control. Two changes in one arm produce a result that belongs to neither.
- Say which rung of the lever ladder the arm sits on and why the cheaper rung was ruled out.
- Say what "solved" looks like and what would leave it open. "We moved the needle but not by much" is a warning that the lever is not the one the problem responds to.
- Put the existence of the thing on trial, not only its correctness. A judge asked "is this link correct?" cannot say there is no link.

## The ladder of checks

Climb only as far as the question needs. Each rung is cheaper than the next and often answers the question.

1. **$0 census** — count the failure across all stored outputs, with denominators. It sizes the prize. A defect on a tiny share of outputs rarely earns a build; a defect concentrated in one document is a case study, not a trend.
2. **$0 replay or prototype** — run the proposed code over stored inputs. Show what changes, what does not, and that the off path is byte-identical. Check the replay reproduces from a committed command. Before a paid rung, dry-run the base arm through every downstream stage the metric reads and count the documents the change can reach; a gain measured on the documents a fix was developed on is a ceiling (`¶INV_EXP_DRY_RUN_DOWNSTREAM`).
3. **Pilot** — a small paid run, in-sample allowed, DESCRIPTIVE ONLY. It catches design errors (a refusal, an arm that cannot fire, a runaway reply) before the budget does.
4. **Registered arm** — sealed, registered, held-out, placebo, same-batch control, enough documents. This is the rung that can say LAND.
5. **Confirmation** — the same design on fresh documents nobody has touched, when the registered arm was close or the stakes are high.
6. **Acceptance run** — the production path on unseen inputs after landing and restart, checking the headline fields and the guards together.

## Recording findings

- Label every claim **measured**, **inferred** or **proposed**. A claim with no measurement under it is a suspicion and says so.
- Every number carries its denominator, its date, the harness that produced it, and the gold version it was scored against (`¶INV_EXP_GOLD_IS_VERSIONED`). Two numbers from different runs are not added into a third and called a rate.
- State limits precisely enough that someone could close them: "not measured: correctness — stable wrong answers look stable" beats any hedge.
- Retractions stay in the record with the reason. The next person will otherwise re-derive the same wrong thing.
- Publish the workings, not only the conclusion. A guard reported as "green" cannot be refuted; the feed it was given can.

## The statistics you observe

- **Rates with denominators** — always "k of n", with what n counts and what it excludes.
- **Repeat noise** — measure it from control re-runs in the same batch before claiming any effect. An effect inside that spread is no effect.
- **Per-document, not per-read** — documents are the unit. Repeats of one document are one observation. Resample whole documents (permutation for p, bootstrap for bounds).
- **Pooled statistics** — when each read carries only a few cells, a per-read share is too coarse; pool cells across an arm's reads so each cell counts once, and bound it with a document bootstrap.
- **Placebo comparison** — the arm must beat the placebo, not only the control. A placebo that moves as much as the arm means the effect is length, salience or noise. A placebo must itself be neutral against base before it can excuse anything. Where arms are deterministic over one shared read, a placebo may be waived, but a sealed null takes its place: a second, independent paid read of the same documents with both arms applied to each read; re-running deterministic code over the same read is not a null (`¶INV_EXP_DETERMINISTIC_ARMS_SEAL_A_NULL`).
- **Guards** — cost, tokens and latency are absolute guards judged against base. Quality guards carry a measured null bar.
- **Multiplicity** — with several treatment arms, report the family-wise correction beside the raw p.
- **Too small to verdict** — say so rather than spend when: fewer documents than the smallest attainable p allows (about five one-sided, six two-sided at 0.05, and in practice seven to nine or more); the noise bar exceeds the defect's base rate; most chosen documents never show the defect; or the minimum detectable effect for your documents and repeats exceeds the effect you claim.
- **Temperature 0** — repeats at temperature 0 do not reliably replay each other and are not independent replicates.
- **Stability is not correctness** — agreement between reads cannot see a value that is wrong every time.
- **Agreement over optional fields** — report the empty-answer share beside it; a cell where every read returns nothing agrees perfectly and identifies nothing.

## What an actionable finding looks like

Each finding ends with:

- **the claim** and its evidence class;
- **the lever it points to** — a wording change, a code change, a schema change, a missing vocabulary member, or "not this lever" with the lever it really is;
- **the next action**, its **cost** ($0 or a priced arm), and **who** would do it;
- **what would overturn it**.

A worked replacement carries the wrong reading it excludes beside the reading it produces. Having nothing to propose is a result — say so plainly rather than padding the section.

## Which findings become checks

A finding becomes a **report-only check** over real outputs when the failure is deterministic to detect, recurs, and nobody would notice it otherwise (a silent drop, a value that disagrees with its own printed text, a page number that disagrees with its source). Build it with a known-positive and known-negative canary. Keep it an alarm; promote it to a gate only after its noise floor and false-alarm rate are measured on repeat-vs-repeat pairs. When a census finds the defect absent, a report-only check is often the whole fix — it watches for the day it appears.

## Carry the lesson upward

A lesson left in a run report teaches nobody. In the same turn, move each one to its home: how we test → the experiment runbook; which lever to reach for → the lever ladder; a measured way a lever backfires → pitfalls; a settled claim → the findings list; something that did not work and what would overturn it → negative results.
