### ¶FMT_DECISION_CARD

**When to use**: The richer successor to `§FMT_CONTEXT_BLOCK` for disclosing the agent's own judgment per item. Used by `§CMD_ELICIT` (and, via it, `§CMD_WALK_THROUGH_RESULTS` results mode) — front-loading what the user reliably asks for next so they judge from context instead of interrogating. **The fields are generalized off the fix-shape** so one card fits a proposed **fix**, a raw **idea**, or a neutral **observation** — not only findings-to-fix. One card per item.

**Rendering as the question body (plain text — NO markdown)**: the card renders **as the `AskUserQuestion` question body** (via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`), not as separate chat text before a terse question. **AskUserQuestion bodies do not render markdown** — `**bold**`, `` `code` ``, `####` show literally. So in the body use **plain text, one field per section as `Label: value`** — the field label, a colon, then its value **inline** — and **separate sections with a blank line**. Do **not** whitespace-align into columns (the padding gap is hard to scan); wrap multi-line values under the label with no column alignment. Labels stay plain (`My lean:`), never bold. Unicode renders fine (`·`, the `§FMT_ANSWER_GRADATION` glyphs `△●Ⓢ★`). The markdown card layout above is for **chat** rendering only.

**Drop the Options field in the body** — the `AskUserQuestion`'s **answers ARE the options**, so re-listing them in the body is redundant. The body carries only the *analysis*: What's-at-stake, How-to-verify, My-lean, Confidence, plus any context/subtitle (`itemId · Title`, `scope · △●Ⓜ`). Each **answer** is a disposition whose label leads with `§FMT_ANSWER_GRADATION` (`△●Ⓢ★ short action`) and whose **description carries that option's COST in its own sentences** — what the user gives up, not a restatement of the label; a description that only re-describes the option is the thin-question failure `§FMT_CONTEXT_BLOCK` names. **My lean** becomes the `★` on the recommended answer. The user reads the analysis and picks in one place — no scroll, no redundancy.

```
[3.2/1] · Update the sticky PR comment on failing tests
scope: comment-builder · △ low · ● solid · Ⓜ med

At stake: failing tests are invisible in the PR summary — reviewers miss them

Verify: grep the comment builder for the failures block

My lean: add a failures section — one comment stays clean · cost: builder branches

Confidence: high — verified against the real comment output, not a fixture
```
*(answers, carrying the options: `△●Ⓢ★ Add a failures section` · `◭●Ⓜ Separate comment per failure` · `△●Ⓢ Leave the summary as-is`)*

**Rules**: A named-list card (never a table — `¶INV_LISTS_INSTEAD_OF_TABLES`). Card **depth scales with the triage bucket**: `FYI` = a one-liner (what + why-no-action); `I've-got-this` = a one-line what + why (never a bare count); `Your-call` = the full card, every required field below. On a `Your-call`, order the body **options-first-neutral, then the defeasible lean** (`§CMD_ELICIT` anti-anchor rule) — the POV lives in the lean, never in a separate recommendation-first field.

**Layout**: each `Your-call` card leads with a markdown **heading** — `#### [itemId] · [Title]` (or larger when a card stands alone) — immediately followed by a **subtitle line** carrying `file:line`/scope + confidence + any *optional* fields. Then the body fields, each on its own line. **No blank line after a heading; one blank line before it** (blocks separate above, not below — keeps cards tight).

**Required fields** (a `Your-call`):
*   **What's at stake** — the concrete consequence if left unaddressed: who/what it hits, how widely (a fix's failure, an idea's missed upside, an observation's implication).
*   **Options** — 2–4 framed trade-offs: *A → risk X; B → risk Y, gain Z*; **always the honest do-nothing / defer** where it's real. Neutral, before the lean.
*   **Complexity / cost to act** — does acting add surface / muddy the design / bloat the build? (orthogonal to correctness).
*   **How to verify / validate** — the low-cost check that confirms or *sizes* it (a read-only count, a one-line repro, a grep, a quick spike).
*   **Confidence** — the agent's honest confidence in its own read (load-bearing — gates the triage). Goes on the subtitle line.
*   **My lean** — the agent's defeasible POV, *after* the options: what it recommends + its paired **trade-off / cost** + the strongest case against it (the anti-anchor rule; the POV lives here, never in a recommendation-first field).
*   **Engagement** — the advisory triage verdict: `I've-got-this` | `Your-call` | `FYI`.
*   **Why you'd want to understand this** — one line, on `Your-call`s (folds into the Engagement line): a one-way door? a load-bearing assumption? a domain rule?

**Optional fields** — render **only when they carry signal** (keep the core lean): **effort** (rough size ~S/M/L or time), **blast-radius / scope** (how many affected — rows / callers / users), **reversibility** (one-way door?), **depends-on / blocks** (sequencing vs. other items). When present, ride them on the **subtitle line** next to `file:line`, not as separate body blocks.

```markdown
#### [itemId] · [Title]
`[file:line or scope]` — confidence **[high|med|low]** · effort **[~S/M/L]** · blast-radius **[scope]**

**What's at stake**
[concrete consequence — who/what, how widely]

**Options**
- **A** — [risk X]
- **B** — [risk Y, gain Z]
- **C** — do nothing → [what stays unaddressed]

**Complexity / cost to act**
[low | real — adds/muddies X]

**How to verify**
[the low-cost confirm/size check]

**My lean**
**B**, because […] — cost: […] — strongest counter: […]

**Engagement**
Your-call — [one line: why it's worth your attention]
```

**Anti-pattern**: a neutral dump with no lean; a recommendation-first framing that anchors before the options; a lean without its paired trade-off; a bare count for the `I've-got-this` / `FYI` buckets; a full expensive card spent on an `FYI`; **a blank line jammed after every heading** (blank before headings, not after).
