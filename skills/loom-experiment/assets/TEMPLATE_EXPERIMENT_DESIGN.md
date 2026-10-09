# [NNN] [slug] — Premise and design
**Lever**: [the stage this arm changes, e.g. prompt | schema | retrieval | post-processing code]
**Tier**: [Registered | Landing]
**Thread**: [threadId] · **Cap**: $[n] · **Model tier**: [as ruled]
**Status**: [DRAFT — OPEN markers below | SEALED at <commit>]

*Written before the first paid call. A draft may carry `OPEN` markers; a run may not start from one. Never edited after results exist — changes go under "Revisions", dated.*

## 1. The question and the decision
*   **Question** (can come out either way): [...]
*   **Decision it changes**: if yes → [ship / turn on / build X]; if no → [park / try Y].
*   **Falsifier** (what result means no): [...]
*   **What "solved" looks like / what leaves it open**: [...]
*   **Rung** (lever ladder) and why the cheaper rung was ruled out: [...]
*   **The $0 look this rests on**: [census/replay path, its numbers with denominators]
*   **Downstream dry run**: [base arm through every stage the metric reads: documents the change can reach, k of n]

## 2. Arms
*Each arm differs from its named control by exactly one change.*
*   **base** — [the shipped behaviour, sent digest `<sha>`]
*   **[arm]** vs base — [the one change]; arm file `arms/<file>` sha `<sha>`
*   **placebo** vs base — [same channel, no information under test]; shown neutral on: [guards]
*   **same-batch null** — [control re-runs interleaved with the arms; for deterministic arms over one shared read: a second independent paid read of the same documents with both arms applied to each, and why the placebo is waived]

## 3. Metric
*   **Primary**: [name] = [numerator] / [denominator]; unit = document; [per-read | pooled per cell]
*   **Can it lose?** base and placebo expected at: [value] (not zero by construction)
*   **Completeness axis**: [what stops "answer less" from winning]
*   **Noise bar**: [same-batch null | document bootstrap, draws, seed]
*   **Gold**: [path] version [v] sealed at [commit]
*   **Rule**: LAND if [effect > bar and p < α on document-level permutation], α = [..]

## 4. Guards
*   **Absolute** (judged against base; a placebo cannot excuse): cost ≤ +[x]%, output tokens ≤ +[x]%, latency ≤ +[x]%
*   **Quality** (measured null bar): [wrong merges ≤ base + bar, completion ≥ base − bar, …]
*   **Positive control**: [a planted or known case each absence-type guard must catch]

## 5. Documents
*   **Selection rule**: [query over the derived held-out pool, at ledger `<commit>`]
*   **Claimed**: [ids and their clusters, in the claims file]
*   **Carry the defect**: [k of n chosen documents show it in the $0 look]
*   **Power**: [n documents × r repeats; smallest attainable p; minimum detectable effect vs claimed effect]
*   **Built inputs** (declared so they are not counted as reads): [paths, commit]

## 6. Runtime
*   **Worker / queues**: [private worker, private queue names, code pinned at `<commit>`]
*   **Entry point and flags**: [command; flags that stop later stages]
*   **Intervention check**: [compiled sent text contains the arm; removal restores base byte for byte; digest recorded per record]
*   **Receipts**: [path convention]

## 7. Money
*   **Estimate**: $[n] ([calls] × [$/call]) · **Cap**: $[n] · **Stop rule**: [at a block boundary when …]
*   **Knock-on if it lands**: lazy $[a] · re-derive all $[b] ([count]) · only changed $[c] ([count])

## 8. Registration
*   **Run id**: [id] · **Registered at**: [store time] · **Corpus pin**: [ledger commit]
*   **First call**: [time] (launched by register-and-launch)

## 9. Revisions (append-only, dated)
*   [YYYY-MM-DD HH:MM] — [what changed, why, and whether it is a new arm]
