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

## 2. Claim Ledger (Provenance per Assertion)
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

## 3. Assets Rendered
*Rendered from the ACTUAL source. Name any that FAILED — a silent gap reads as "covered".*

*   **`[file.png]`** — [what it is + how rendered, e.g. `mutool draw -r 150 estimate.pdf 73` → real page 73]
*   **Failed**: "[asset that could not be rendered + why + how the page degrades around it]" / "none"

## 4. Structural Device
*The device chosen to carry the truth, and why it makes the thesis self-evident.*

*   **Device**: [before/after | claim→proof→verdict | color-coded-by-real-fact]
*   **What the encoding MEANS**: "[e.g. row color = the row's owner per the finding; legend states the mapping. Never decorative.]"

## 5. Scope Block (as it appears on the page)
*Honesty lives here — and on the page, where the reader meets the claim, not buried.*

*   **What the evidence shows**: "[what the rendered assets on the page depict]"
*   **Out of scope**: "[what the page deliberately does NOT claim — e.g. the fix itself]"
*   **Rests on the trusted upstream finding**: "[the conclusion(s) established by /probe//analyze//experiment and taken as given here — not re-derived]"

## 6. Publish Record
*Filled by the orchestrator at §4.*

*   **Artifact URL**: [url] / "[held as file — reason]"
*   **Integrity-checked**: "[which load-bearing asset the orchestrator opened itself, and that its caption matched]"
*   **Honesty summary**: "Shown: N claims with real assets · trusted-from-upstream: N (labeled) · out-of-scope: …"
