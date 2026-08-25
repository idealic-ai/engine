# Proof Dossier: [Thesis]
**Tags**: #needs-review
*Written by the evidence-engineer sub-agent. This is the record BEHIND the published artifact — every claim the page makes, the real evidence that shows it, and its PROVENANCE. `/prove` TRUSTS the upstream finding; this dossier does not re-prove it — it documents what is shown and where each claim comes from, so the page can be re-derived and its honesty checked. It is read by the **orchestrator** (which runs the presentation-integrity pass before publishing) and by the **next agent**. Fill every field.*

**Slug**: `[slug]`
**Proof HTML**: `builds/[slug]_PROOF.html` — the durable, self-contained, Linear-attachable artifact this dossier documents (composed once; published as-is).
**Reader & job**: [reviewer / future self / stakeholder] — the page lets them [the 10-second job].
**Source finding (trusted)**: [what already-resolved work this presents — _PROBE.md / findings / before-after / VERDICT / log+plan+builds]. Its conclusion is the INPUT, taken as given.
**Status**: [Shown / Partial / Blocked]

## 1. The Thesis
*The one claim the page presents. A claim with a truth value — established upstream, shown here.*

*   **Thesis**: "[The single claim, one sentence.]"
*   **Upstream verdict**: "[What the source finding concluded, quoted/attributed — this is trusted, not re-derived.]"

## 2. Questions & Answers (what the reader ARRIVES with)
*The questions come from the READER named above, not from the author. A page that answers the author's question ("what did we learn about X?") instead of the reader's ("can I turn this on?") fails its job however well it argues. Derive 3-5 from the reader's stated job; answer each in ONE line — a direct yes / no / partly plus the number that settles it. Not a summary: an answer. "We don't know" is a valid answer when paired with what would settle it.*

*Constraint: every answer must be supported by a claim in §2 below and must not outrun it. An answer more confident than its evidence is the failure mode this section exists to prevent.*

*   **Q**: "[the question, in the reader's words — e.g. 'Does it work?']"
    *   **A**: "[direct answer + the settling number — e.g. 'Partly: 18/0 on the metric that can see it, blind in 4 named cases.']"
    *   **Rests on**: [claim # from the ledger / trusted-upstream / checked-here]
*   **Q**: "[e.g. 'Can I turn it on?']"
    *   **A**: "..."
    *   **Rests on**: ...
*   **Q**: "[e.g. 'What breaks?']"
    *   **A**: "..."
    *   **Rests on**: ...

## 3. Claim Ledger (Provenance per Assertion)
*EVERY assertion the page makes, with its provenance. The page may only assert what appears here as shown-by-a-real-asset or attributed to the trusted upstream finding.*

### Claim 1: [short statement]
*   **Provenance**: [trusted-upstream / checked-here]
    *   `trusted-upstream` = the finding's own verdict, taken as given.
    *   `checked-here` = something YOU confirmed purely for the presentation (the render depicts it), NOT a re-run of the analysis.
*   **Shown by**: "[the real asset that depicts it — `<assetDir>/<file>.png`, a quoted log line, a code block from `file:line`] / [attributed text: 'per the /experiment VERDICT: …']"
*   **Faithful?**: "[for checked-here: what you confirmed the asset actually shows, e.g. 'p86 render shows rows 12–14 tinted, matching the named rows']"

### Claim 2: [short statement]
*   **Provenance**: ...
*   **Shown by**: ...
*   **Faithful?**: ...

## 4. Assets Rendered
*Rendered from the ACTUAL source. Name any that FAILED — a silent gap reads as "covered".*

*   **`[file.png]`** — [what it is + how rendered, e.g. `mutool draw -r 150 estimate.pdf 73` → real page 73]
*   **Failed**: "[asset that could not be rendered + why + how the page degrades around it]" / "none"

## 5. Structural Device
*The device chosen to carry the truth, and why it makes the thesis self-evident.*

*   **Device**: [before/after | claim→proof→verdict | color-coded-by-real-fact]
*   **What the encoding MEANS**: "[e.g. row color = the row's owner per the finding; legend states the mapping. Never decorative.]"

## 6. Scope Block (as it appears on the page)
*Honesty lives here — and on the page, where the reader meets the claim, not buried.*

*   **What the evidence shows**: "[what the rendered assets on the page depict]"
*   **Out of scope**: "[what the page deliberately does NOT claim — e.g. the fix itself]"
*   **Rests on the trusted upstream finding**: "[the conclusion(s) established by /probe//analyze//experiment and taken as given here — not re-derived]"

## 7. Next Steps (what to DO about it)
*A proof that establishes what is true should not make the reader re-derive what to do. Each step traces to a finding — never invented, never a generic backlog. `/prove` SUGGESTS; it does not act, and it does not commit the reader to anything.*

*Mark each honestly:*
*   `follows` — the evidence points directly at this; little judgement involved.
*   `idea` — a reasonable option this evidence permits but does not establish. Say so; do not launder an idea into a recommendation.

*   **[follows]** "[the step]" — **because** "[the finding it traces to]" · **effort** [~S/M/L] · **unblocks** "[what it enables]"
*   **[follows]** "..." — because ... · effort ... · unblocks ...
*   **[idea]** "[the option]" — **why it's only an idea** "[what the evidence does NOT settle about it]"
*   **Deliberately NOT suggested**: "[paths a reader might expect but the evidence argues against — with the reason]"

## 8. Publish Record
*Filled by the orchestrator at §4.*

*   **Artifact URL**: [url] / "[held as file — reason]"
*   **Integrity-checked**: "[which load-bearing asset the orchestrator opened itself, and that its caption matched]"
*   **Answers checked**: "[each Q&A answer traced to its ledger claim; any that outran its evidence and was softened]"
*   **Honesty summary**: "Shown: N claims with real assets · trusted-from-upstream: N (labeled) · out-of-scope: …"
