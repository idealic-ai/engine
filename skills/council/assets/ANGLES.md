# Council angles — the prompt each angle adds to every expert

An **angle** sets what kind of answer the panel produces. `/council --angle <name>` picks one. With no `--angle`, the angle is `critique`, which is what /council has always done, so a caller that passes nothing gets the old behaviour unchanged. The first version has three: critique, refute and design-off (the operator's answer on meta:engine/20261030-103346, fork ANGLES, which narrowed the earlier "all four" on meta:utils/20261029-133853 ¶ASK_ANGL). An `ideas` angle, a panel that only widens the option set, is not in this version; `--angle ideas` is refused at §1 with that reason.

Every expert still gets its persona, the shared grounding and the return contract from SKILL.md §3. The angle block below goes **after the persona and before the categorisation rules**, word for word, with `<…>` filled in. Only `critique` keeps the MUST FIX / SHOULD FIX / CONSIDER tiers and the refutation pass. The other two return their own shape, given in their block, and SKILL.md §5 says how each one is reconciled.

Proposals are new in this version. Under `design-off` an expert may propose an option the subject does not have. A proposal is never added to the curated poll: the poll's options stay as the caller wrote them, and the expert still votes on them. A proposal is returned as a separate `proposals` list, `{label, why}` per entry, and goes onto an ask through `engine ask attach-panel --proposed` (skills/ask-council). Whether a proposed option becomes a real one is the asker's decision, made with `engine ask revise`.

---

## critique (the default)

> **Your angle is critique.** Find what is wrong with the subject, or with each option it offers: the defect, the failing case, the cost the author has not counted. Use the tiers and the Failing-Scenario rule below. If a poll is attached, vote on it as instructed, and let your vote follow your findings.

Reconciled as SKILL.md §5 already describes (refute, reconcile, tiers).

## refute-the-lean (`--angle refute`)

> **Your angle is refute the lean.** The subject recommends one option: `<the lean, with its code and its stated reason>`. Argue ONLY against it. Make the strongest good-faith case that the lean is wrong: the evidence it ignores, the case where it fails, the option that beats it and why. Do not review the other options except as what the lean loses to. If after an honest attempt you cannot make a case that would change a careful reader's mind, say so plainly: `the lean holds — <the attack you tried and why it failed>`. That is a valid answer, not a failure.
>
> Return: `verdict: <holds | weakened | broken>`, `strongest_case: <one paragraph>`, `evidence: <file:line, a log path, a measured number — or "none beyond the subject">`, and, if a poll is attached, your vote (you may vote for the lean; your vote is about what you would choose, your case is about whether the lean survives attack).

Reconciled: no tiers and no refutation pass. Every expert attacked the same lean, so the report lists each lens's verdict and strongest case side by side. Do not take a majority. A single `broken` with evidence outweighs four `holds` without any, and the report says which verdicts carried evidence. A subject with no lean cannot take this angle. Refuse it at §1 ("refute needs a lean to attack; this subject has none") rather than inventing one.

## design-off (`--angle design-off`)

> **Your angle is design-off.** Propose the design you would choose for `<the question>`, and defend it against the others. It may be one of the existing options, or a new one. Either way, state it concretely enough to build: what it is, the one or two decisions that define it, what it costs, and what would prove it wrong. Then name the strongest competing design (another option, or what you expect another lens to propose) and say in one sentence why yours beats it.
>
> Return: `design: {label, summary, defining_decisions[], cost, falsifier}`, `is_existing_option: <code | null>`, `beats: {rival, why}`, and, if a poll is attached, your vote on the existing options. If `is_existing_option` is null, also add your design to `proposals` as `{label, why}`.

Reconciled: the report has one section per distinct design. Designs that two lenses proposed in the same shape are merged and both lenses are named. Each section carries the design, the lenses behind it, its falsifier, and the rival each lens said it beats. Do not crown a winner. The report may say which design the most lenses converged on, and must give that count with the lens names, never as a bare number.

---

## What a /scrutinize set is, beside these

`/scrutinize` is not an angle. It is one adversarial auditor that checks claims against intent and then fixes. The batch pass (skills/ask-council) may propose a scrutinize set for a topic whose asks are about **finished work** (a landed change, a report, a PR), where the question is "is this right" rather than "which option". A scrutinize set produces no `Panel:` reads. Its result is attached to each covered ask as an Evidence-style link, through the asker. See skills/ask-council §4.
