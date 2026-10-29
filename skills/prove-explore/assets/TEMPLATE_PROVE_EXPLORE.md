# Explore Dossier — [the question]
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/builds/[slug]_PROVE_EXPLORE.md`.
**Usage**: The record behind `[slug]_EXPLORE.html` — what each section answers, what grounds it, and where the map ends. The page is the artifact; this is how a reader checks it.
**Write the skeleton FIRST**: every heading below, each section marked `IN PROGRESS`, on disk before any grounding starts — then fill each as you establish it. A lane that dies mid-run must leave a record the next one resumes from.

## 1. The Question
*   **Question**: [the one question the map answers]
*   **Answered means**: [what counts as having answered it]
*   **Reader & job**: [teammate | newcomer | operator | future self] — must be able to [the 10-second job] and [the full-read job]
*   **Page**: `builds/[slug]_EXPLORE.html` · **Published**: [S3 URL, or "not published — reason"]

## 2. The Boundary
*What this map does NOT cover. Load-bearing: an incomplete map read as complete is this skill's signature defect.*

*   **Out of scope**: [named, not implied]
*   **Why it is out**: [a different page's subject / nobody has looked / deliberately deferred]
*   **Where the page says so**: [the section the reader meets it in — must be with the map, not at the bottom]

## 3. The Decomposition
*One entry per sub-question. The page's outline IS this list. Checked in both directions at the gate.*

*   **[Sub-question 1]**
  *   **Section**: [the page section answering it, or `UNANSWERED`]
  *   **Answer in one line**: [what the section establishes]
  *   **Evidence**: [the real asset or source]
  *   **Provenance**: [trusted-upstream `<source>` | checked-here <YYYY-MM-DD>]
  *   **Carries**: [`carries: <the asset>` — hide the prose and this still delivers the one-line answer | `bare: <why nothing can carry it>`]
  *   **Shape**: [walk | comparison | one large render | table | short verbatim | …] · **opens on**: [what would surprise a reader who thought they knew the territory]

*   **[Sub-question 2]**
  *   **Section**: ...
  *   **Answer in one line**: ...
  *   **Evidence**: ...
  *   **Provenance**: ...
  *   **Carries**: ...
  *   **Shape**: ... · **opens on**: ...

*   **Sections answering no sub-question**: [none — or named and cut, with why]
*   **Sub-questions with no section**: [none — or named, on the page as unanswered, with why]
*   **Carry tally**: `sections: [N] · carrying: [N] · declared bare: [names] · decorative, removed: [names]`

## 4. The Epistemic Inventory
*The blank regions are part of the answer. A measured absence, an unsettled question and an unexamined region are different findings and never share a treatment.*

### Known
*   **[Region]** — [what is established] · evidence: [asset/source] · provenance: [trusted-upstream | checked-here <YYYY-MM-DD>]

### Measured absent
*Somebody looked and it is not there — a finding, not a blank.*
*   **[Region]** — [what is absent] · evidence: [the reading] · **control**: [the positive control that fired in the same invocation] · provenance: [trusted-upstream | checked-here <YYYY-MM-DD>]

### Not established
*Somebody looked and could not settle it.*
*   **[Region]** — [what is unsettled] · **what would settle it**: [the named check] · why it could not be settled here: [reason]

### Not looked at
*Nobody has examined it.*
*   **[Region]** — [what is unexamined] · why: [out of reach / out of time / out of scope]

*   **Rendering convention**: [how the kinds are kept distinct, as stated in the page's legend]
*   **Every label renders outside a disclosure**: [confirmed — none of these regions sits inside a `<details>`]

## 5. Disagreements Shown
*Where sources conflict or the parts do not fit. Resolving by preference is prohibited; resolving by evidence, with the reasoning shown, is a finding.*

*   **[The disagreement]**
  *   **Side A**: [claim] — evidence: [asset/source]
  *   **Side B**: [claim] — evidence: [asset/source]
  *   **Resolution**: [unresolved, both shown | resolved by evidence: which side, and the evidence that decided it]
  *   **Where the page shows it**: [section]

## 6. Assets
### Rendered
*   **[Asset]** — [what it is] · from: [the actual command / file / URL] · shows: [what its caption claims] · **caption confirmed against asset**: [yes, by whom | NOT confirmed]

### Failed
*   **[Asset]** — `asset-failed` · why: [reason] · **degraded to**: [what the page shows instead — never a fabricated stand-in]

## 7. The Structural Device
*   **Device**: [map/layered diagram | a walk along the real path | parts-and-connections | known/unknown overlay]
*   **What it encodes**: [the real relation it carries]
*   **Legend**: [what any colour or treatment MEANS, and its real referent]
*   **Why this device**: [why it makes the shape self-evident rather than decorating it]

## 8. Gate Record
*The ORCHESTRATOR owns this gate. What the cartographer fills in here is its input, never a pass. Each check pass/fail; a failure is a targeted edit plus a re-check, not a note.*

*   **C1 decomposition coverage (both directions)**: [pass | fail → what was fixed] · **`decomposition:`** [holds | really-two | sub-question N wrong] → [what the orchestrator did about it]
*   **C2 boundary test**: [pass | fail → ...]
*   **C3 per-section provenance**: [pass | fail → ...] · sections checked: [every one — name any skipped and why]
*   **C4 load-bearing render per region**: [pass | fail → ...] · captions I could not confirm: [none | named] · verbatim captures legible in full where they sit: [yes | what was re-laid-out]
*   **C5 unknowns render as unknowns, and outside every disclosure**: [pass | fail → ...] · strip-the-`<details>` pass: [each label's count outside, and zero inside-only]
*   **C6 no false coherence**: [pass | fail → ...]
*   **C7 padding audit**: [pass | fail → what was cut]
*   **C8 orientation test (map + headings + assets, no paragraphs)**: [pass | fail → ...]
*   **C9 page mechanics**: [pass | fail → ...] · `scrollWidth`=`clientWidth` at [widths, both themes] · foreign requests / console errors / `<script>` / renderer blocks: [counts]
*   **C10 carry audit**: [pass | fail → ...] · `sections: [N] · carrying: [N] · declared bare: [names] · decorative, removed: [names]` · subtraction run on: [the sections tested] · bare on the page but silent in this dossier: [none | named]

## 9. Coverage Summary
*The one-line honesty close, as reported.*

> Mapped: [N] sub-questions answered · unanswered: [...] · known / not-established / not-looked-at: [...] · disagreements shown: [...] · out of scope: [...]
